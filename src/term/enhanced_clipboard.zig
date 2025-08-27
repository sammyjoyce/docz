const std = @import("std");
const base64 = std.base64;

/// Enhanced clipboard support with base64 encoding
/// Implements OSC 52 escape sequences for clipboard manipulation
///
/// This module provides robust clipboard integration that works across
/// different terminal emulators and platforms, including remote sessions
/// over SSH where normal clipboard access isn't available.
///
/// See: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands
/// See: https://github.com/ojroques/vim-oscyank
/// Clipboard selection types
pub const ClipboardType = enum(u8) {
    primary = 'p', // Primary selection (middle-click)
    system = 'c', // System clipboard (Ctrl+C/V)
    secondary = 's', // Secondary selection (rarely used)

    pub fn toChar(self: ClipboardType) u8 {
        return @intFromEnum(self);
    }
};

/// Clipboard operation result
pub const ClipboardError = error{
    EncodingError,
    InvalidData,
    OutOfMemory,
};

/// Set clipboard content using OSC 52 escape sequence
/// OSC 52 ; Pc ; Pd BEL/ST
/// Where Pc is the clipboard selector and Pd is base64-encoded data
pub fn setClipboard(alloc: std.mem.Allocator, clipboard: ClipboardType, data: []const u8) ![]u8 {
    // Encode data as base64
    const encoder = base64.standard.Encoder;
    const encoded_len = encoder.calcSize(data.len);
    const encoded = try alloc.alloc(u8, encoded_len);
    defer alloc.free(encoded);

    const actual_encoded = encoder.encode(encoded, data);

    // Build OSC 52 sequence
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();

    try result.appendSlice("\x1b]52;");
    try result.append(clipboard.toChar());
    try result.append(';');
    try result.appendSlice(actual_encoded);
    try result.appendSlice("\x07"); // BEL terminator

    return try result.toOwnedSlice();
}

/// Set system clipboard (most common use case)
pub fn setSystemClipboard(alloc: std.mem.Allocator, data: []const u8) ![]u8 {
    return setClipboard(alloc, .system, data);
}

/// Set primary clipboard (X11 middle-click selection)
pub fn setPrimaryClipboard(alloc: std.mem.Allocator, data: []const u8) ![]u8 {
    return setClipboard(alloc, .primary, data);
}

/// Clear clipboard by setting empty content
pub fn clearClipboard(alloc: std.mem.Allocator, clipboard: ClipboardType) ![]u8 {
    return setClipboard(alloc, clipboard, "");
}

/// Clear system clipboard
pub fn clearSystemClipboard(alloc: std.mem.Allocator) ![]u8 {
    return clearClipboard(alloc, .system);
}

/// Clear primary clipboard
pub fn clearPrimaryClipboard(alloc: std.mem.Allocator) ![]u8 {
    return clearClipboard(alloc, .primary);
}

/// Request clipboard content
/// OSC 52 ; Pc ; ? BEL/ST
/// Terminal should respond with current clipboard content
pub fn requestClipboard(alloc: std.mem.Allocator, clipboard: ClipboardType) ![]u8 {
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();

    try result.appendSlice("\x1b]52;");
    try result.append(clipboard.toChar());
    try result.appendSlice(";?\x07");

    return try result.toOwnedSlice();
}

/// Request system clipboard content
pub fn requestSystemClipboard(alloc: std.mem.Allocator) ![]u8 {
    return requestClipboard(alloc, .system);
}

/// Request primary clipboard content
pub fn requestPrimaryClipboard(alloc: std.mem.Allocator) ![]u8 {
    return requestClipboard(alloc, .primary);
}

/// Parse clipboard response from terminal
/// Returns decoded clipboard content from OSC 52 response
pub fn parseClipboardResponse(alloc: std.mem.Allocator, response: []const u8) !?[]u8 {
    // Expected format: ESC ] 52 ; c ; base64data BEL/ST

    // Find the start of OSC sequence
    const osc_start = std.mem.indexOf(u8, response, "\x1b]52;");
    if (osc_start == null) return null;

    // Find the clipboard type separator
    const start_idx = osc_start.? + 5; // Skip "\x1b]52;"
    if (start_idx >= response.len) return null;

    const semi_pos = std.mem.indexOfScalarPos(u8, response, start_idx, ';');
    if (semi_pos == null) return null;

    // Extract base64 data (after second semicolon, before terminator)
    const data_start = semi_pos.? + 1;
    if (data_start >= response.len) return null;

    // Find terminator (BEL or ST)
    var data_end = std.mem.indexOfScalarPos(u8, response, data_start, '\x07'); // BEL
    if (data_end == null) {
        // Try ST (ESC \)
        const st_pos = std.mem.indexOfPos(u8, response, data_start, "\x1b\\");
        if (st_pos != null) {
            data_end = st_pos;
        }
    }

    if (data_end == null) return null;

    const encoded_data = response[data_start..data_end.?];
    if (encoded_data.len == 0) return try alloc.dupe(u8, ""); // Empty clipboard

    // Decode base64
    const decoder = base64.standard.Decoder;
    const decoded_len = try decoder.calcSizeForSlice(encoded_data);
    const decoded = try alloc.alloc(u8, decoded_len);

    try decoder.decode(decoded, encoded_data);

    return decoded;
}

/// High-level clipboard manager
pub const ClipboardManager = struct {
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) ClipboardManager {
        return ClipboardManager{ .alloc = alloc };
    }

    /// Copy text to system clipboard
    pub fn copy(self: *ClipboardManager, text: []const u8) ![]u8 {
        return setSystemClipboard(self.alloc, text);
    }

    /// Copy text to primary clipboard (X11 selection)
    pub fn copyToPrimary(self: *ClipboardManager, text: []const u8) ![]u8 {
        return setPrimaryClipboard(self.alloc, text);
    }

    /// Copy to both system and primary clipboards
    pub fn copyToBoth(self: *ClipboardManager, text: []const u8) ![]u8 {
        const sys_seq = try setSystemClipboard(self.alloc, text);
        defer self.alloc.free(sys_seq);

        const prim_seq = try setPrimaryClipboard(self.alloc, text);
        defer self.alloc.free(prim_seq);

        // Combine both sequences
        var result = std.ArrayList(u8).init(self.alloc);
        errdefer result.deinit();

        try result.appendSlice(sys_seq);
        try result.appendSlice(prim_seq);

        return try result.toOwnedSlice();
    }

    /// Clear system clipboard
    pub fn clear(self: *ClipboardManager) ![]u8 {
        return clearSystemClipboard(self.alloc);
    }

    /// Request clipboard content
    pub fn request(self: *ClipboardManager) ![]u8 {
        return requestSystemClipboard(self.alloc);
    }

    /// Request primary clipboard content
    pub fn requestPrimary(self: *ClipboardManager) ![]u8 {
        return requestPrimaryClipboard(self.alloc);
    }
};

/// Utility function to check if text is safe for clipboard
/// Filters out control characters that might interfere with terminal
pub fn sanitizeClipboardText(alloc: std.mem.Allocator, text: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();

    for (text) |ch| {
        // Allow printable ASCII, tabs, newlines, and common Unicode
        if ((ch >= 32 and ch <= 126) or ch == '\t' or ch == '\n' or ch >= 128) {
            try result.append(ch);
        }
        // Skip other control characters
    }

    return try result.toOwnedSlice();
}

/// Constants for common sequences
pub const CLEAR_SYSTEM_CLIPBOARD = "\x1b]52;c;\x07";
pub const CLEAR_PRIMARY_CLIPBOARD = "\x1b]52;p;\x07";
pub const REQUEST_SYSTEM_CLIPBOARD = "\x1b]52;c;?\x07";
pub const REQUEST_PRIMARY_CLIPBOARD = "\x1b]52;p;?\x07";

test "clipboard basic operations" {
    const testing = std.testing;
    const alloc = testing.allocator;

    // Test setting system clipboard
    const hello_seq = try setSystemClipboard(alloc, "Hello, World!");
    defer alloc.free(hello_seq);

    // Should contain base64 encoded "Hello, World!"
    try testing.expect(std.mem.indexOf(u8, hello_seq, "\x1b]52;c;") != null);
    try testing.expect(std.mem.indexOf(u8, hello_seq, "\x07") != null);

    // Test clearing clipboard
    const clear_seq = try clearSystemClipboard(alloc);
    defer alloc.free(clear_seq);
    try testing.expectEqualStrings(CLEAR_SYSTEM_CLIPBOARD, clear_seq);

    // Test request sequence
    const request_seq = try requestSystemClipboard(alloc);
    defer alloc.free(request_seq);
    try testing.expectEqualStrings(REQUEST_SYSTEM_CLIPBOARD, request_seq);
}

test "clipboard response parsing" {
    const testing = std.testing;
    const alloc = testing.allocator;

    // Test parsing a valid response
    const response = "\x1b]52;c;SGVsbG8gV29ybGQ=\x07"; // "Hello World" in base64
    const parsed = try parseClipboardResponse(alloc, response);

    if (parsed) |content| {
        defer alloc.free(content);
        try testing.expectEqualStrings("Hello World", content);
    } else {
        try testing.expect(false); // Should have parsed successfully
    }

    // Test empty clipboard response
    const empty_response = "\x1b]52;c;\x07";
    const empty_parsed = try parseClipboardResponse(alloc, empty_response);

    if (empty_parsed) |content| {
        defer alloc.free(content);
        try testing.expectEqualStrings("", content);
    } else {
        try testing.expect(false); // Should have parsed successfully
    }
}

test "clipboard manager" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var manager = ClipboardManager.init(alloc);

    const copy_seq = try manager.copy("Test data");
    defer alloc.free(copy_seq);
    try testing.expect(std.mem.indexOf(u8, copy_seq, "\x1b]52;c;") != null);

    const both_seq = try manager.copyToBoth("Both clipboards");
    defer alloc.free(both_seq);
    try testing.expect(std.mem.indexOf(u8, both_seq, "\x1b]52;c;") != null);
    try testing.expect(std.mem.indexOf(u8, both_seq, "\x1b]52;p;") != null);

    const clear_seq = try manager.clear();
    defer alloc.free(clear_seq);
    try testing.expectEqualStrings(CLEAR_SYSTEM_CLIPBOARD, clear_seq);
}

test "text sanitization" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const dirty_text = "Hello\x1b\x07Control\tChar\nTest";
    const clean_text = try sanitizeClipboardText(alloc, dirty_text);
    defer alloc.free(clean_text);

    // Should remove ESC and BEL, but keep tab and newline
    try testing.expectEqualStrings("HelloControl\tChar\nTest", clean_text);
}

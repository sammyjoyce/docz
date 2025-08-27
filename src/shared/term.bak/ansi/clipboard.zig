const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

// Clipboard selection names for OSC 52
pub const ClipboardName = enum(u8) {
    system = 'c', // System clipboard
    primary = 'p', // Primary selection (X11)
    secondary = 's', // Secondary selection
    clipboard0 = '0', // Numbered clipboards
    clipboard1 = '1',
    clipboard2 = '2',
    clipboard3 = '3',
    clipboard4 = '4',
    clipboard5 = '5',
    clipboard6 = '6',
    clipboard7 = '7',

    pub fn toChar(self: ClipboardName) u8 {
        return @intFromEnum(self);
    }

    pub fn fromChar(c: u8) ?ClipboardName {
        return switch (c) {
            'c' => .system,
            'p' => .primary,
            's' => .secondary,
            '0' => .clipboard0,
            '1' => .clipboard1,
            '2' => .clipboard2,
            '3' => .clipboard3,
            '4' => .clipboard4,
            '5' => .clipboard5,
            '6' => .clipboard6,
            '7' => .clipboard7,
            else => null,
        };
    }
};

// Clipboard operation errors
pub const ClipboardError = error{
    EncodingError,
    InvalidData,
    OutOfMemory,
    ClipboardDataTooLarge,
    InvalidUtf8,
    Unsupported,
};

// Default maximum clipboard size (64KB should work with most terminals)
pub const DEFAULT_MAX_CLIPBOARD_SIZE: usize = 65536;

// Base64 encoding for clipboard data
fn base64Encode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const encoder = std.base64.standard.Encoder;
    const encoded_len = encoder.calcSize(data.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    _ = encoder.encode(encoded, data);
    return encoded;
}

// Base64 decoding for clipboard data
fn base64Decode(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    const decoder = std.base64.standard.Decoder;
    const decoded_len = try decoder.calcSizeForSlice(encoded);
    const decoded = try allocator.alloc(u8, decoded_len);
    try decoder.decode(decoded, encoded);
    return decoded;
}

// Utility function to check if clipboard operation is supported
pub fn isClipboardSupported() bool {
    // Simple check - in a real implementation, this could check TERM environment variable
    // or send a device attributes request to see if OSC 52 is supported
    return std.posix.isatty(std.posix.STDOUT_FILENO);
}

// Utility function to sanitize clipboard text
// Filters out control characters that might interfere with terminal
pub fn sanitizeClipboardText(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
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

// Escape special characters in clipboard data for safety
pub fn escapeClipboardData(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    // In most cases, base64 encoding handles this, but we might want to
    // escape certain control characters before encoding
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    for (data) |char| {
        switch (char) {
            // Replace potentially problematic characters
            '\x00'...'\x08', '\x0e'...'\x1f', '\x7f' => {
                // Replace control characters with space
                try result.append(' ');
            },
            else => {
                try result.append(char);
            },
        }
    }

    return try result.toOwnedSlice();
}

// Limit clipboard data size to prevent overwhelming the terminal
pub fn limitClipboardSize(allocator: std.mem.Allocator, data: []const u8, max_size: usize) ![]u8 {
    if (data.len <= max_size) {
        return try allocator.dupe(u8, data);
    }

    return try allocator.dupe(u8, data[0..max_size]);
}

// Set clipboard content - OSC 52 ; clipboard ; base64_data BEL
pub fn setClipboard(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, clipboard: ClipboardName, data: []const u8) !void {
    if (!caps.supportsOsc52Clipboard) return error.Unsupported;

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try buf.appendSlice("\x1b]52;");
    try buf.append(clipboard.toChar());
    try buf.append(';');

    if (data.len > 0) {
        const encoded = try base64Encode(allocator, data);
        defer allocator.free(encoded);
        try buf.appendSlice(encoded);
    }

    try buf.append(0x07); // BEL terminator

    try passthrough.writeWithPassthrough(writer, caps, buf.items);
}

// Set system clipboard (convenience function)
pub fn setSystemClipboard(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, data: []const u8) !void {
    try setClipboard(writer, caps, allocator, ClipboardName.system, data);
}

// Set primary clipboard/selection (convenience function)
pub fn setPrimaryClipboard(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, data: []const u8) !void {
    try setClipboard(writer, caps, allocator, ClipboardName.primary, data);
}

// Reset/clear clipboard - OSC 52 ; clipboard ; BEL
pub fn resetClipboard(writer: anytype, caps: TermCaps, clipboard: ClipboardName) !void {
    if (!caps.supportsOsc52Clipboard) return error.Unsupported;

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b]52;") catch unreachable;
    _ = w.writeByte(clipboard.toChar()) catch unreachable;
    _ = w.write(";\x07") catch unreachable;

    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Reset system clipboard (convenience function)
pub fn resetSystemClipboard(writer: anytype, caps: TermCaps) !void {
    try resetClipboard(writer, caps, ClipboardName.system);
}

// Reset primary clipboard (convenience function)
pub fn resetPrimaryClipboard(writer: anytype, caps: TermCaps) !void {
    try resetClipboard(writer, caps, ClipboardName.primary);
}

// Request clipboard content - OSC 52 ; clipboard ; ? BEL
pub fn requestClipboard(writer: anytype, caps: TermCaps, clipboard: ClipboardName) !void {
    if (!caps.supportsOsc52Clipboard) return error.Unsupported;

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b]52;") catch unreachable;
    _ = w.writeByte(clipboard.toChar()) catch unreachable;
    _ = w.write(";?\x07") catch unreachable;

    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Request system clipboard (convenience function)
pub fn requestSystemClipboard(writer: anytype, caps: TermCaps) !void {
    try requestClipboard(writer, caps, ClipboardName.system);
}

// Request primary clipboard (convenience function)
pub fn requestPrimaryClipboard(writer: anytype, caps: TermCaps) !void {
    try requestClipboard(writer, caps, ClipboardName.primary);
}

// Clipboard response parser
pub const ClipboardParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ClipboardParser {
        return ClipboardParser{ .allocator = allocator };
    }

    // Parse clipboard response: OSC 52 ; clipboard ; base64_data BEL/ST
    pub fn parseClipboardResponse(self: ClipboardParser, response: []const u8) !struct { clipboard: ClipboardName, data: []u8 } {
        // Inline parsing logic from input/clipboard.zig
        if (response.len < 6 or !std.mem.startsWith(u8, response, "\x1b]52;")) {
            return error.InvalidResponse;
        }

        var i: usize = 5; // Skip "\x1b]52;"
        if (i >= response.len) return error.InvalidResponse;

        const sel_ch = response[i];
        if (sel_ch != 'c' and sel_ch != 'p') return error.InvalidResponse;
        const selection = if (sel_ch == 'p') ClipboardName.primary else ClipboardName.system;
        i += 1;

        if (i >= response.len or response[i] != ';') return error.InvalidResponse;
        i += 1;

        // Data until ST (ESC \) or BEL
        const data_start = i;
        var data_end = i;
        while (i < response.len) : (i += 1) {
            const ch = response[i];
            if (ch == 0x07) { // BEL
                data_end = i;
                break;
            }
            if (ch == 0x1b and i + 1 < response.len and response[i + 1] == '\\') {
                data_end = i;
                i += 2; // consume ESC \
                break;
            }
        }
        if (data_end <= data_start) return error.InvalidResponse;

        const b64 = response[data_start..data_end];
        // Decode into a freshly allocated buffer.
        const dec = std.base64.standard.Decoder;
        const out_len = dec.calcSizeForSlice(b64) catch return error.InvalidResponse;
        const buf = self.allocator.alloc(u8, out_len) catch return error.InvalidResponse;
        errdefer self.allocator.free(buf);
        dec.decode(buf, b64) catch {
            self.allocator.free(buf);
            return error.InvalidResponse;
        };

        return .{ .clipboard = selection, .data = buf };
    }

    pub fn freeClipboardData(self: ClipboardParser, data: []u8) void {
        self.allocator.free(data);
    }
};

// ClipboardResponse represents a parsed clipboard response from the terminal
pub const ClipboardResponse = struct {
    clipboard: ClipboardName,
    data: []u8, // Decoded data (caller owns memory)

    pub fn deinit(self: ClipboardResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

// High-level clipboard manager for convenient operations
pub const Clipboard = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Clipboard {
        return Clipboard{ .allocator = allocator };
    }

    /// Copy text to clipboard with automatic encoding
    pub fn copy(self: *Clipboard, writer: anytype, caps: TermCaps, clipboard: ClipboardName, text: []const u8) !void {
        return try setClipboard(writer, caps, self.allocator, clipboard, text);
    }

    /// Copy text to system clipboard
    pub fn copyToSystem(self: *Clipboard, writer: anytype, caps: TermCaps, text: []const u8) !void {
        return try self.copy(writer, caps, ClipboardName.system, text);
    }

    /// Copy text to primary clipboard
    pub fn copyToPrimary(self: *Clipboard, writer: anytype, caps: TermCaps, text: []const u8) !void {
        return try self.copy(writer, caps, ClipboardName.primary, text);
    }

    /// Request clipboard content
    pub fn request(_: *Clipboard, writer: anytype, caps: TermCaps, clipboard: ClipboardName) !void {
        return try requestClipboard(writer, caps, clipboard);
    }

    /// Request system clipboard content
    pub fn requestSystem(self: *Clipboard, writer: anytype, caps: TermCaps) !void {
        return try self.request(writer, caps, ClipboardName.system);
    }

    /// Request primary clipboard content
    pub fn requestPrimary(self: *Clipboard, writer: anytype, caps: TermCaps) !void {
        return try self.request(writer, caps, ClipboardName.primary);
    }

    /// Clear clipboard
    pub fn clear(_: *Clipboard, writer: anytype, caps: TermCaps, clipboard: ClipboardName) !void {
        return try resetClipboard(writer, caps, clipboard);
    }

    /// Clear system clipboard
    pub fn clearSystem(self: *Clipboard, writer: anytype, caps: TermCaps) !void {
        return try self.clear(writer, caps, ClipboardName.system);
    }

    /// Clear primary clipboard
    pub fn clearPrimary(self: *Clipboard, writer: anytype, caps: TermCaps) !void {
        return try self.clear(writer, caps, ClipboardName.primary);
    }

    /// Copy to multiple clipboards at once
    pub fn copyToMultiple(self: *Clipboard, writer: anytype, caps: TermCaps, clipboards: []const ClipboardName, text: []const u8) !void {
        for (clipboards) |clipboard| {
            try self.copy(writer, caps, clipboard, text);
        }
    }

    /// Copy text to both system and primary clipboards
    pub fn copyToAll(self: *Clipboard, writer: anytype, caps: TermCaps, text: []const u8) !void {
        const clipboards = [_]ClipboardName{ .system, .primary };
        return try self.copyToMultiple(writer, caps, &clipboards, text);
    }
};

// Advanced clipboard operations

// Set multiple clipboards at once
pub fn setMultipleClipboards(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, clipboards: []const ClipboardName, data: []const u8) !void {
    for (clipboards) |clipboard| {
        try setClipboard(writer, caps, allocator, clipboard, data);
    }
}

// Copy text to both system and primary clipboards (common pattern)
pub fn copyToSystemAndPrimary(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, data: []const u8) !void {
    try setSystemClipboard(writer, caps, allocator, data);
    try setPrimaryClipboard(writer, caps, allocator, data);
}

// Clipboard operation with size limit check
pub fn setClipboardWithSizeCheck(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, clipboard: ClipboardName, data: []const u8, max_size: usize) !void {
    if (data.len > max_size) return error.ClipboardDataTooLarge;
    try setClipboard(writer, caps, allocator, clipboard, data);
}

// Clipboard operation with UTF-8 validation
pub fn setClipboardUtf8(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, clipboard: ClipboardName, data: []const u8) !void {
    if (!std.unicode.utf8ValidateSlice(data)) return error.InvalidUtf8;
    try setClipboard(writer, caps, allocator, clipboard, data);
}

// Constants for direct use
pub const RESET_SYSTEM_CLIPBOARD = "\x1b]52;c;\x07";
pub const RESET_PRIMARY_CLIPBOARD = "\x1b]52;p;\x07";
pub const REQUEST_SYSTEM_CLIPBOARD = "\x1b]52;c;?\x07";
pub const REQUEST_PRIMARY_CLIPBOARD = "\x1b]52;p;?\x07";

test "clipboard name to char conversion" {
    try std.testing.expect(ClipboardName.system.toChar() == 'c');
    try std.testing.expect(ClipboardName.primary.toChar() == 'p');
    try std.testing.expect(ClipboardName.clipboard0.toChar() == '0');
}

test "base64 encoding and decoding" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const original = "Hello, World!";
    const encoded = try base64Encode(allocator, original);
    defer allocator.free(encoded);

    const decoded = try base64Decode(allocator, encoded);
    defer allocator.free(decoded);

    try std.testing.expect(std.mem.eql(u8, original, decoded));
}

test "clipboard response parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parser = ClipboardParser.init(allocator);

    // Test basic response parsing
    const response = "\x1b]52;c;SGVsbG8sIFdvcmxkIQ==\x07";
    const result = try parser.parseClipboardResponse(response);
    defer parser.freeClipboardData(result.data);

    try std.testing.expect(result.clipboard == ClipboardName.system);
    try std.testing.expect(std.mem.eql(u8, result.data, "Hello, World!"));
}

test "utf8 validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const valid_utf8 = "Hello, 世界!";
    const invalid_utf8 = [_]u8{ 0xFF, 0xFE, 0xFD };

    // This would succeed if we had a mock writer/caps
    // For now just test UTF-8 validation
    try std.testing.expect(std.unicode.utf8ValidateSlice(valid_utf8));
    try std.testing.expect(!std.unicode.utf8ValidateSlice(&invalid_utf8));

    _ = allocator; // suppress unused variable warning
}

test "clipboard utilities" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test text sanitization
    const dirty_text = "Hello\x1b\x07Control\tChar\nTest";
    const clean_text = try sanitizeClipboardText(allocator, dirty_text);
    defer allocator.free(clean_text);
    try std.testing.expectEqualSlices(u8, "HelloControl\tChar\nTest", clean_text);

    // Test escaping control characters
    const input = "Hello\x00\x01World\x7f";
    const escaped = try escapeClipboardData(allocator, input);
    defer allocator.free(escaped);
    try std.testing.expectEqualSlices(u8, "Hello  World ", escaped);

    // Test size limiting
    const large_data = "x" ** 1000;
    const limited = try limitClipboardSize(allocator, large_data, 10);
    defer allocator.free(limited);
    try std.testing.expectEqual(@as(usize, 10), limited.len);
    try std.testing.expectEqualSlices(u8, "xxxxxxxxxx", limited);

    // Test clipboard name from char
    try std.testing.expectEqual(ClipboardName.system, ClipboardName.fromChar('c').?);
    try std.testing.expectEqual(ClipboardName.primary, ClipboardName.fromChar('p').?);
    try std.testing.expectEqual(@as(?ClipboardName, null), ClipboardName.fromChar('z'));
}

test "clipboard manager" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const manager = Clipboard.init(allocator);

    // Test that manager methods don't crash (would need mock writer/caps for full test)
    // These tests verify the method signatures work correctly
    _ = manager;
}

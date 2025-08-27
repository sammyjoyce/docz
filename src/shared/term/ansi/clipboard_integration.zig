const std = @import("std");
const base64 = std.base64;

/// Enhanced clipboard integration based on standard ANSI OSC 52 sequences
/// Provides proper OSC 52 clipboard manipulation with base64 encoding/decoding.

// ==== Clipboard Types ====

/// Clipboard identifiers for different clipboard selections
pub const ClipboardType = enum(u8) {
    /// System clipboard (c) - the primary system clipboard
    system = 'c',
    /// Primary clipboard (p) - X11 primary selection
    primary = 'p',
    /// Secondary clipboard (s) - X11 secondary selection
    secondary = 's',
    /// Clipboard 0-7 (0-7) - numbered clipboards
    clipboard0 = '0',
    clipboard1 = '1',
    clipboard2 = '2',
    clipboard3 = '3',
    clipboard4 = '4',
    clipboard5 = '5',
    clipboard6 = '6',
    clipboard7 = '7',

    pub fn toChar(self: ClipboardType) u8 {
        return @intFromEnum(self);
    }

    pub fn fromChar(c: u8) ?ClipboardType {
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

// ==== Core Clipboard Functions ====

/// SetClipboard sets clipboard content using OSC 52 sequence
/// OSC 52 ; Pc ; Pd ST / OSC 52 ; Pc ; Pd BEL
/// Where Pc is the clipboard identifier and Pd is base64-encoded data
pub fn setClipboard(allocator: std.mem.Allocator, clipboard_type: ClipboardType, data: []const u8) ![]u8 {
    if (data.len == 0) {
        // Empty data resets the clipboard
        return try std.fmt.allocPrint(allocator, "\x1b]52;{c};\x07", .{clipboard_type.toChar()});
    }

    // Calculate base64 encoded size
    const encoder = base64.standard.Encoder;
    const encoded_len = encoder.calcSize(data.len);

    // Allocate buffer for base64 encoded data
    const encoded_data = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded_data);

    // Encode the data
    _ = encoder.encode(encoded_data, data);

    // Build the OSC 52 sequence
    return try std.fmt.allocPrint(allocator, "\x1b]52;{c};{s}\x07", .{ clipboard_type.toChar(), encoded_data });
}

/// RequestClipboard requests clipboard content using OSC 52 sequence
/// OSC 52 ; Pc ; ? ST / OSC 52 ; Pc ; ? BEL
pub fn requestClipboard(allocator: std.mem.Allocator, clipboard_type: ClipboardType) ![]u8 {
    return try std.fmt.allocPrint(allocator, "\x1b]52;{c};?\x07", .{clipboard_type.toChar()});
}

/// ResetClipboard resets/clears clipboard content using OSC 52 sequence
/// OSC 52 ; Pc ; ST / OSC 52 ; Pc ; BEL (empty data)
pub fn resetClipboard(allocator: std.mem.Allocator, clipboard_type: ClipboardType) ![]u8 {
    return try std.fmt.allocPrint(allocator, "\x1b]52;{c};\x07", .{clipboard_type.toChar()});
}

// ==== Convenience Functions for Common Clipboards ====

/// Set system clipboard content
pub fn setSystemClipboard(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return try setClipboard(allocator, .system, data);
}

/// Set primary clipboard content
pub fn setPrimaryClipboard(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return try setClipboard(allocator, .primary, data);
}

/// Request system clipboard content
pub fn requestSystemClipboard(allocator: std.mem.Allocator) ![]u8 {
    return try requestClipboard(allocator, .system);
}

/// Request primary clipboard content
pub fn requestPrimaryClipboard(allocator: std.mem.Allocator) ![]u8 {
    return try requestClipboard(allocator, .primary);
}

/// Reset system clipboard
pub fn resetSystemClipboard(allocator: std.mem.Allocator) ![]u8 {
    return try resetClipboard(allocator, .system);
}

/// Reset primary clipboard
pub fn resetPrimaryClipboard(allocator: std.mem.Allocator) ![]u8 {
    return try resetClipboard(allocator, .primary);
}

// ==== Constants for Common Operations ====

/// Pre-built sequences for common operations (no allocation required)
pub const RESET_SYSTEM_CLIPBOARD_CONST = "\x1b]52;c;\x07";
pub const RESET_PRIMARY_CLIPBOARD_CONST = "\x1b]52;p;\x07";
pub const REQUEST_SYSTEM_CLIPBOARD_CONST = "\x1b]52;c;?\x07";
pub const REQUEST_PRIMARY_CLIPBOARD_CONST = "\x1b]52;p;?\x07";

// ==== Response Parsing ====

/// ClipboardResponse represents a parsed clipboard response from the terminal
pub const ClipboardResponse = struct {
    clipboard_type: ClipboardType,
    data: []u8, // Decoded data (caller owns memory)

    pub fn deinit(self: ClipboardResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

/// Parse a clipboard response from the terminal
/// Expected format: OSC 52 ; Pc ; Pd ST or OSC 52 ; Pc ; Pd BEL
/// Where Pc is clipboard type and Pd is base64-encoded data
pub fn parseClipboardResponse(allocator: std.mem.Allocator, response: []const u8) !?ClipboardResponse {
    // Check if it starts with OSC 52
    if (!std.mem.startsWith(u8, response, "\x1b]52;")) {
        return null;
    }

    // Find the terminator (ST or BEL)
    const end_idx = if (std.mem.lastIndexOf(u8, response, "\x07")) |idx| idx else if (std.mem.lastIndexOf(u8, response, "\x1b\\")) |idx| idx else return null;

    // Extract the parameters part
    const params = response[5..end_idx]; // Skip "\x1b]52;"

    var parts = std.mem.split(u8, params, ";");

    // Get clipboard type
    const clipboard_char_str = parts.next() orelse return null;
    if (clipboard_char_str.len != 1) return null;

    const clipboard_type = ClipboardType.fromChar(clipboard_char_str[0]) orelse return null;

    // Get base64 data
    const encoded_data = parts.next() orelse return null;

    // If data is "?" it's a request, not a response
    if (std.mem.eql(u8, encoded_data, "?")) {
        return null;
    }

    // If data is empty, return empty data
    if (encoded_data.len == 0) {
        const empty_data = try allocator.alloc(u8, 0);
        return ClipboardResponse{
            .clipboard_type = clipboard_type,
            .data = empty_data,
        };
    }

    // Decode base64 data
    const decoder = base64.standard.Decoder;
    const decoded_len = try decoder.calcSizeForSlice(encoded_data);

    const decoded_data = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(decoded_data);

    try decoder.decode(decoded_data, encoded_data);

    return ClipboardResponse{
        .clipboard_type = clipboard_type,
        .data = decoded_data,
    };
}

// ==== Advanced Clipboard Operations ====

/// Clipboard provides high-level clipboard operations
pub const Clipboard = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Clipboard {
        return Clipboard{
            .allocator = allocator,
        };
    }

    /// Copy text to clipboard with automatic encoding
    pub fn copy(self: Clipboard, clipboard_type: ClipboardType, text: []const u8) ![]u8 {
        return try setClipboard(self.allocator, clipboard_type, text);
    }

    /// Copy text to system clipboard
    pub fn copyToSystem(self: Clipboard, text: []const u8) ![]u8 {
        return try self.copy(.system, text);
    }

    /// Copy text to primary clipboard
    pub fn copyToPrimary(self: Clipboard, text: []const u8) ![]u8 {
        return try self.copy(.primary, text);
    }

    /// Request clipboard content
    pub fn paste(self: Clipboard, clipboard_type: ClipboardType) ![]u8 {
        return try requestClipboard(self.allocator, clipboard_type);
    }

    /// Request system clipboard content
    pub fn pasteFromSystem(self: Clipboard) ![]u8 {
        return try self.paste(.system);
    }

    /// Request primary clipboard content
    pub fn pasteFromPrimary(self: Clipboard) ![]u8 {
        return try self.paste(.primary);
    }

    /// Clear clipboard
    pub fn clear(self: Clipboard, clipboard_type: ClipboardType) ![]u8 {
        return try resetClipboard(self.allocator, clipboard_type);
    }

    /// Clear system clipboard
    pub fn clearSystem(self: Clipboard) ![]u8 {
        return try self.clear(.system);
    }

    /// Clear primary clipboard
    pub fn clearPrimary(self: Clipboard) ![]u8 {
        return try self.clear(.primary);
    }

    /// Copy to multiple clipboards at once
    pub fn copyToMultiple(self: Clipboard, clipboard_types: []const ClipboardType, text: []const u8) ![]u8 {
        var sequences = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (sequences.items) |seq| {
                self.allocator.free(seq);
            }
            sequences.deinit();
        }

        for (clipboard_types) |clipboard_type| {
            const seq = try self.copy(clipboard_type, text);
            try sequences.append(seq);
        }

        return try std.mem.join(self.allocator, "", sequences.items);
    }

    /// Copy text to both system and primary clipboards
    pub fn copyToAll(self: Clipboard, text: []const u8) ![]u8 {
        const clipboards = [_]ClipboardType{ .system, .primary };
        return try self.copyToMultiple(&clipboards, text);
    }
};

// ==== Utility Functions ====

/// Check if clipboard operation is supported by checking if we're in a terminal
pub fn isClipboardSupported() bool {
    // Simple check - in a real implementation, this could check TERM environment variable
    // or send a device attributes request to see if OSC 52 is supported
    return std.posix.isatty(std.posix.STDOUT_FILENO);
}

/// Escape special characters in clipboard data for safety
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

/// Limit clipboard data size to prevent overwhelming the terminal
pub fn limitClipboardSize(allocator: std.mem.Allocator, data: []const u8, max_size: usize) ![]u8 {
    if (data.len <= max_size) {
        return try allocator.dupe(u8, data);
    }

    return try allocator.dupe(u8, data[0..max_size]);
}

/// Default maximum clipboard size (64KB should work with most terminals)
pub const DEFAULT_MAX_CLIPBOARD_SIZE: usize = 65536;

// ==== Tests ====

test "clipboard type conversion" {
    const testing = std.testing;

    // Test enum to char conversion
    try testing.expectEqual(@as(u8, 'c'), ClipboardType.system.toChar());
    try testing.expectEqual(@as(u8, 'p'), ClipboardType.primary.toChar());
    try testing.expectEqual(@as(u8, '0'), ClipboardType.clipboard0.toChar());

    // Test char to enum conversion
    try testing.expectEqual(ClipboardType.system, ClipboardType.fromChar('c').?);
    try testing.expectEqual(ClipboardType.primary, ClipboardType.fromChar('p').?);
    try testing.expectEqual(@as(?ClipboardType, null), ClipboardType.fromChar('z'));
}

test "clipboard sequence generation" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test setting clipboard with text
    {
        const seq = try setSystemClipboard(allocator, "Hello, World!");
        defer allocator.free(seq);

        // Should contain OSC 52, system clipboard identifier, and base64 encoded data
        try testing.expect(std.mem.startsWith(u8, seq, "\x1b]52;c;"));
        try testing.expect(std.mem.endsWith(u8, seq, "\x07"));

        // Should contain base64 encoded "Hello, World!"
        // SGVsbG8sIFdvcmxkIQ== is base64 for "Hello, World!"
        try testing.expect(std.mem.indexOf(u8, seq, "SGVsbG8sIFdvcmxkIQ==") != null);
    }

    // Test requesting clipboard
    {
        const seq = try requestSystemClipboard(allocator);
        defer allocator.free(seq);
        try testing.expectEqualSlices(u8, REQUEST_SYSTEM_CLIPBOARD_CONST, seq);
    }

    // Test resetting clipboard
    {
        const seq = try resetSystemClipboard(allocator);
        defer allocator.free(seq);
        try testing.expectEqualSlices(u8, RESET_SYSTEM_CLIPBOARD_CONST, seq);
    }
}

test "clipboard response parsing" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test parsing valid response
    {
        const response = "\x1b]52;c;SGVsbG8sIFdvcmxkIQ==\x07"; // "Hello, World!" in base64
        const parsed = try parseClipboardResponse(allocator, response);
        try testing.expect(parsed != null);

        if (parsed) |clipboard_resp| {
            defer clipboard_resp.deinit(allocator);
            try testing.expectEqual(ClipboardType.system, clipboard_resp.clipboard_type);
            try testing.expectEqualSlices(u8, "Hello, World!", clipboard_resp.data);
        }
    }

    // Test parsing empty response
    {
        const response = "\x1b]52;p;\x07";
        const parsed = try parseClipboardResponse(allocator, response);
        try testing.expect(parsed != null);

        if (parsed) |clipboard_resp| {
            defer clipboard_resp.deinit(allocator);
            try testing.expectEqual(ClipboardType.primary, clipboard_resp.clipboard_type);
            try testing.expectEqual(@as(usize, 0), clipboard_resp.data.len);
        }
    }

    // Test parsing invalid response
    {
        const response = "not a clipboard response";
        const parsed = try parseClipboardResponse(allocator, response);
        try testing.expect(parsed == null);
    }
}

test "clipboard manager operations" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const manager = Clipboard.init(allocator);

    // Test copy to system
    {
        const seq = try manager.copyToSystem("test data");
        defer allocator.free(seq);
        try testing.expect(std.mem.startsWith(u8, seq, "\x1b]52;c;"));
    }

    // Test copy to multiple clipboards
    {
        const clipboards = [_]ClipboardType{ .system, .primary };
        const seq = try manager.copyToMultiple(&clipboards, "multi test");
        defer allocator.free(seq);

        // Should contain sequences for both clipboards
        try testing.expect(std.mem.indexOf(u8, seq, "\x1b]52;c;") != null); // system
        try testing.expect(std.mem.indexOf(u8, seq, "\x1b]52;p;") != null); // primary
    }
}

test "clipboard data utilities" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test escaping control characters
    {
        const input = "Hello\x00\x01World\x7f";
        const escaped = try escapeClipboardData(allocator, input);
        defer allocator.free(escaped);
        try testing.expectEqualSlices(u8, "Hello  World ", escaped);
    }

    // Test size limiting
    {
        const large_data = "x" ** 1000;
        const limited = try limitClipboardSize(allocator, large_data, 10);
        defer allocator.free(limited);
        try testing.expectEqual(@as(usize, 10), limited.len);
        try testing.expectEqualSlices(u8, "xxxxxxxxxx", limited);
    }

    // Test clipboard support detection
    {
        // This will depend on the test environment, just ensure it doesn't crash
        _ = isClipboardSupported();
    }
}

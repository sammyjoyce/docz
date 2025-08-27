const std = @import("std");
const caps_mod = @import("../caps.zig");
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
};

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
        // Check for OSC 52 prefix
        if (response.len < 6 or !std.mem.startsWith(u8, response, "\x1b]52;")) {
            return error.InvalidResponse;
        }

        // Find terminator (BEL or ST)
        const end_pos = blk: {
            if (std.mem.endsWith(u8, response, "\x07")) {
                break :blk response.len - 1;
            } else if (std.mem.endsWith(u8, response, "\x1b\\")) {
                break :blk response.len - 2;
            } else {
                return error.InvalidResponse;
            }
        };

        const payload = response[5..end_pos]; // Skip "\x1b]52;"

        // Find clipboard separator
        const sep_pos = std.mem.indexOf(u8, payload, ";") orelse return error.InvalidResponse;
        if (sep_pos == 0) return error.InvalidResponse;

        const clipboard_char = payload[0];
        const clipboard = @as(ClipboardName, @enumFromInt(clipboard_char));

        const encoded_data = payload[sep_pos + 1 ..];

        // Decode base64 data if present
        if (encoded_data.len == 0) {
            // Empty clipboard
            return .{ .clipboard = clipboard, .data = try self.allocator.alloc(u8, 0) };
        }

        const decoded = try base64Decode(self.allocator, encoded_data);
        return .{ .clipboard = clipboard, .data = decoded };
    }

    pub fn freeClipboardData(self: ClipboardParser, data: []u8) void {
        self.allocator.free(data);
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

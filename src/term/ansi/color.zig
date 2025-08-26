const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

fn oscTerminator() []const u8 {
    return if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel"))
        seqcfg.osc.bel
    else
        seqcfg.osc.st;
}

fn sanitize(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    // Filter out ESC and BEL to avoid premature termination or injection
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    try out.ensureTotalCapacity(s.len);
    for (s) |ch| {
        if (ch == 0x1b or ch == 0x07) continue;
        out.appendAssumeCapacity(ch);
    }
    return try out.toOwnedSlice();
}

fn appendDec(buf: *std.ArrayList(u8), n: u32) !void {
    var tmp: [12]u8 = undefined;
    const w = try std.fmt.bufPrint(&tmp, "{d}", .{n});
    try buf.appendSlice(w);
}

fn buildOscColor(
    alloc: std.mem.Allocator,
    code: u32,
    payload: []const u8,
) ![]u8 {
    const st = oscTerminator();
    const clean = try sanitize(alloc, payload);
    defer alloc.free(clean);

    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, code);
    try buf.append(';');
    try buf.appendSlice(clean);
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

fn buildOscQuery(alloc: std.mem.Allocator, code: u32) ![]u8 {
    const st = oscTerminator();
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, code);
    try buf.appendSlice(";?");
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

fn buildOscReset(alloc: std.mem.Allocator, code: u32) ![]u8 {
    const st = oscTerminator();
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, 100 + code);
    // OSC 110/111/112 are resets for 10/11/12 respectively
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

inline fn colorCode(kind: enum { fg, bg, cursor }) u32 {
    return switch (kind) {
        .fg => seqcfg.osc.ops.color.foreground,
        .bg => seqcfg.osc.ops.color.background,
        .cursor => seqcfg.osc.ops.color.cursor,
    };
}

// Foreground color (OSC 10)
pub fn setForegroundColor(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    color: []const u8,
) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscColor(alloc, colorCode(.fg), color);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn requestForegroundColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscQuery(alloc, colorCode(.fg));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn resetForegroundColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscReset(alloc, colorCode(.fg));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Background color (OSC 11)
pub fn setBackgroundColor(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    color: []const u8,
) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscColor(alloc, colorCode(.bg), color);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn requestBackgroundColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscQuery(alloc, colorCode(.bg));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn resetBackgroundColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscReset(alloc, colorCode(.bg));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Cursor color (OSC 12)
pub fn setCursorColor(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    color: []const u8,
) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscColor(alloc, colorCode(.cursor), color);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn requestCursorColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscQuery(alloc, colorCode(.cursor));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn resetCursorColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscReset(alloc, colorCode(.cursor));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// === ENHANCED COLOR FORMATS FROM CHARMBRACELET X ===

/// Color format types for terminal color specification
pub const ColorFormat = enum {
    hex, // #RRGGBB format
    xrgb, // XParseColor rgb:RRRR/GGGG/BBBB format
    xrgba, // XParseColor rgba:RRRR/GGGG/BBBB/AAAA format
    name, // Named color (e.g., "red", "blue")
};

/// Hex color representation (#RRGGBB)
pub const HexColor = struct {
    value: u32,

    pub fn init(hex: u32) HexColor {
        return HexColor{ .value = hex & 0xFFFFFF }; // Ensure only RGB bits
    }

    pub fn initFromString(hex_str: []const u8) !HexColor {
        const clean = if (hex_str.len > 0 and hex_str[0] == '#') hex_str[1..] else hex_str;
        if (clean.len != 6) return error.InvalidHexColor;

        const hex = std.fmt.parseInt(u32, clean, 16) catch return error.InvalidHexColor;
        return HexColor.init(hex);
    }

    pub fn toString(self: HexColor, alloc: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(alloc, "#{:06x}", .{self.value});
    }

    pub fn toRgb(self: HexColor) struct { r: u8, g: u8, b: u8 } {
        return .{
            .r = @intCast((self.value >> 16) & 0xFF),
            .g = @intCast((self.value >> 8) & 0xFF),
            .b = @intCast(self.value & 0xFF),
        };
    }
};

/// XParseColor RGB format (rgb:RRRR/GGGG/BBBB)
pub const XRGBColor = struct {
    r: u16,
    g: u16,
    b: u16,

    pub fn init(r: u16, g: u16, b: u16) XRGBColor {
        return XRGBColor{ .r = r, .g = g, .b = b };
    }

    pub fn fromRgb8(r: u8, g: u8, b: u8) XRGBColor {
        // Convert 8-bit to 16-bit by duplicating bits
        return XRGBColor{
            .r = (@as(u16, r) << 8) | r,
            .g = (@as(u16, g) << 8) | g,
            .b = (@as(u16, b) << 8) | b,
        };
    }

    pub fn toString(self: XRGBColor, alloc: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(alloc, "rgb:{:04x}/{:04x}/{:04x}", .{ self.r, self.g, self.b });
    }
};

/// XParseColor RGBA format (rgba:RRRR/GGGG/BBBB/AAAA)
pub const XRGBAColor = struct {
    r: u16,
    g: u16,
    b: u16,
    a: u16,

    pub fn init(r: u16, g: u16, b: u16, a: u16) XRGBAColor {
        return XRGBAColor{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn fromRgba8(r: u8, g: u8, b: u8, a: u8) XRGBAColor {
        return XRGBAColor{
            .r = (@as(u16, r) << 8) | r,
            .g = (@as(u16, g) << 8) | g,
            .b = (@as(u16, b) << 8) | b,
            .a = (@as(u16, a) << 8) | a,
        };
    }

    pub fn toString(self: XRGBAColor, alloc: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(alloc, "rgba:{:04x}/{:04x}/{:04x}/{:04x}", .{ self.r, self.g, self.b, self.a });
    }
};

/// Enhanced color setting functions with support for different formats
/// Set foreground color using hex format
pub fn setForegroundColorHex(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    hex_color: HexColor,
) !void {
    const color_str = try hex_color.toString(alloc);
    defer alloc.free(color_str);
    try setForegroundColor(writer, alloc, caps, color_str);
}

/// Set background color using hex format
pub fn setBackgroundColorHex(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    hex_color: HexColor,
) !void {
    const color_str = try hex_color.toString(alloc);
    defer alloc.free(color_str);
    try setBackgroundColor(writer, alloc, caps, color_str);
}

/// Set cursor color using hex format
pub fn setCursorColorHex(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    hex_color: HexColor,
) !void {
    const color_str = try hex_color.toString(alloc);
    defer alloc.free(color_str);
    try setCursorColor(writer, alloc, caps, color_str);
}

/// Set foreground color using XRGB format
pub fn setForegroundColorXRGB(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    xrgb_color: XRGBColor,
) !void {
    const color_str = try xrgb_color.toString(alloc);
    defer alloc.free(color_str);
    try setForegroundColor(writer, alloc, caps, color_str);
}

/// Set background color using XRGB format
pub fn setBackgroundColorXRGB(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    xrgb_color: XRGBColor,
) !void {
    const color_str = try xrgb_color.toString(alloc);
    defer alloc.free(color_str);
    try setBackgroundColor(writer, alloc, caps, color_str);
}

/// Set cursor color using XRGB format
pub fn setCursorColorXRGB(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    xrgb_color: XRGBColor,
) !void {
    const color_str = try xrgb_color.toString(alloc);
    defer alloc.free(color_str);
    try setCursorColor(writer, alloc, caps, color_str);
}

/// Set foreground color using XRGBA format
pub fn setForegroundColorXRGBA(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    xrgba_color: XRGBAColor,
) !void {
    const color_str = try xrgba_color.toString(alloc);
    defer alloc.free(color_str);
    try setForegroundColor(writer, alloc, caps, color_str);
}

/// Set background color using XRGBA format
pub fn setBackgroundColorXRGBA(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    xrgba_color: XRGBAColor,
) !void {
    const color_str = try xrgba_color.toString(alloc);
    defer alloc.free(color_str);
    try setBackgroundColor(writer, alloc, caps, color_str);
}

/// Set cursor color using XRGBA format
pub fn setCursorColorXRGBA(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    xrgba_color: XRGBAColor,
) !void {
    const color_str = try xrgba_color.toString(alloc);
    defer alloc.free(color_str);
    try setCursorColor(writer, alloc, caps, color_str);
}

/// Convenience function to set colors from RGB values
pub fn setForegroundColorRgb(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    r: u8,
    g: u8,
    b: u8,
) !void {
    const hex = HexColor.init((@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b));
    try setForegroundColorHex(writer, alloc, caps, hex);
}

/// Convenience function to set background color from RGB values
pub fn setBackgroundColorRgb(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    r: u8,
    g: u8,
    b: u8,
) !void {
    const hex = HexColor.init((@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b));
    try setBackgroundColorHex(writer, alloc, caps, hex);
}

/// Convenience function to set cursor color from RGB values
pub fn setCursorColorRgb(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    r: u8,
    g: u8,
    b: u8,
) !void {
    const hex = HexColor.init((@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b));
    try setCursorColorHex(writer, alloc, caps, hex);
}

/// Parse terminal color response (OSC 10/11/12 response)
/// Expected format: ESC ] code ; color BEL/ST
pub fn parseColorResponse(response: []const u8) ![]const u8 {
    if (response.len < 6) return error.InvalidResponse;

    if (!std.mem.startsWith(u8, response, "\x1b]")) {
        return error.InvalidResponse;
    }

    // Find first semicolon (after the code)
    const first_semi = std.mem.indexOf(u8, response, ";") orelse return error.InvalidResponse;

    // Find terminator
    var end_pos: ?usize = null;
    if (std.mem.lastIndexOf(u8, response, "\x07")) |bel_pos| {
        end_pos = bel_pos;
    } else if (std.mem.lastIndexOf(u8, response, "\x1b\\")) |st_pos| {
        end_pos = st_pos;
    } else {
        return error.InvalidResponse;
    }

    const end = end_pos.?;
    if (end <= first_semi + 1) return error.InvalidResponse;

    return response[first_semi + 1 .. end];
}

// Tests for enhanced color functionality
test "hex color creation and formatting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test hex color from value
    const red = HexColor.init(0xFF0000);
    const red_str = try red.toString(allocator);
    defer allocator.free(red_str);
    try testing.expectEqualStrings("#ff0000", red_str);

    // Test hex color from string
    const blue = try HexColor.initFromString("#0000FF");
    const blue_str = try blue.toString(allocator);
    defer allocator.free(blue_str);
    try testing.expectEqualStrings("#0000ff", blue_str);

    // Test RGB extraction
    const green_rgb = HexColor.init(0x00FF00).toRgb();
    try testing.expect(green_rgb.r == 0 and green_rgb.g == 255 and green_rgb.b == 0);
}

test "xrgb color formatting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test XRGB color from 8-bit values
    const white = XRGBColor.fromRgb8(255, 255, 255);
    const white_str = try white.toString(allocator);
    defer allocator.free(white_str);
    try testing.expectEqualStrings("rgb:ffff/ffff/ffff", white_str);
}

test "xrgba color formatting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test XRGBA color
    const semi_red = XRGBAColor.fromRgba8(255, 0, 0, 128);
    const semi_red_str = try semi_red.toString(allocator);
    defer allocator.free(semi_red_str);
    try testing.expectEqualStrings("rgba:ffff/0000/0000/8080", semi_red_str);
}

test "color response parsing" {
    const testing = std.testing;

    // Test valid response with BEL terminator
    const response_bel = "\x1b]10;#ff0000\x07";
    const color_bel = try parseColorResponse(response_bel);
    try testing.expectEqualStrings("#ff0000", color_bel);

    // Test valid response with ST terminator
    const response_st = "\x1b]11;rgb:ffff/0000/0000\x1b\\";
    const color_st = try parseColorResponse(response_st);
    try testing.expectEqualStrings("rgb:ffff/0000/0000", color_st);
}

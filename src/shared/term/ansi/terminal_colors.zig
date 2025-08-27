const std = @import("std");
const fmt = std.fmt;

/// Enhanced terminal background and foreground color management
/// Supports XParseColor rgb:/ rgba: formats and hex colors for maximum terminal compatibility
/// Compatible with Zig 0.15.1
/// HexColor represents a color that can be formatted as a hex string
/// Provides convenient conversion between RGB values and hex representation
pub const HexColor = struct {
    r: u8,
    g: u8,
    b: u8,

    /// Create HexColor from RGB values
    pub fn fromRgb(r: u8, g: u8, b: u8) HexColor {
        return HexColor{ .r = r, .g = g, .b = b };
    }

    /// Create HexColor from hex string (e.g., "#FF0000" or "FF0000")
    pub fn fromHex(hex: []const u8) !HexColor {
        var hex_str = hex;
        if (hex_str.len > 0 and hex_str[0] == '#') {
            hex_str = hex_str[1..];
        }

        if (hex_str.len != 6) {
            return error.InvalidHexFormat;
        }

        const r = try fmt.parseInt(u8, hex_str[0..2], 16);
        const g = try fmt.parseInt(u8, hex_str[2..4], 16);
        const b = try fmt.parseInt(u8, hex_str[4..6], 16);

        return HexColor{ .r = r, .g = g, .b = b };
    }

    /// Format as hex string (e.g., "#FF0000")
    pub fn toHex(self: HexColor, allocator: std.mem.Allocator) ![]u8 {
        return try fmt.allocPrint(allocator, "#{:02x}{:02x}{:02x}", .{ self.r, self.g, self.b });
    }

    /// Format as hex string without hash (e.g., "FF0000")
    pub fn toHexNoHash(self: HexColor, allocator: std.mem.Allocator) ![]u8 {
        return try fmt.allocPrint(allocator, "{:02x}{:02x}{:02x}", .{ self.r, self.g, self.b });
    }

    pub fn format(self: HexColor, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("#{:02x}{:02x}{:02x}", .{ self.r, self.g, self.b });
    }
};

/// XRGBColor represents a color formatted as XParseColor rgb: string
/// Used for better terminal compatibility with X11 color parsing
pub const XRGBColor = struct {
    r: u16,
    g: u16,
    b: u16,

    /// Create from 8-bit RGB values
    pub fn fromRgb8(r: u8, g: u8, b: u8) XRGBColor {
        return XRGBColor{
            .r = (@as(u16, r) << 8) | r, // Expand 8-bit to 16-bit
            .g = (@as(u16, g) << 8) | g,
            .b = (@as(u16, b) << 8) | b,
        };
    }

    /// Create from 16-bit RGB values
    pub fn fromRgb16(r: u16, g: u16, b: u16) XRGBColor {
        return XRGBColor{ .r = r, .g = g, .b = b };
    }

    /// Create from HexColor
    pub fn fromHex(hex_color: HexColor) XRGBColor {
        return fromRgb8(hex_color.r, hex_color.g, hex_color.b);
    }

    /// Format as XParseColor rgb: string (e.g., "rgb:ffff/0000/0000")
    pub fn toRgbString(self: XRGBColor, allocator: std.mem.Allocator) ![]u8 {
        return try fmt.allocPrint(allocator, "rgb:{:04x}/{:04x}/{:04x}", .{ self.r, self.g, self.b });
    }

    pub fn format(self: XRGBColor, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("rgb:{:04x}/{:04x}/{:04x}", .{ self.r, self.g, self.b });
    }
};

/// XRGBAColor represents a color formatted as XParseColor rgba: string
/// Includes alpha channel for transparency support
pub const XRGBAColor = struct {
    r: u16,
    g: u16,
    b: u16,
    a: u16,

    /// Create from 8-bit RGBA values
    pub fn fromRgba8(r: u8, g: u8, b: u8, a: u8) XRGBAColor {
        return XRGBAColor{
            .r = (@as(u16, r) << 8) | r,
            .g = (@as(u16, g) << 8) | g,
            .b = (@as(u16, b) << 8) | b,
            .a = (@as(u16, a) << 8) | a,
        };
    }

    /// Create from 16-bit RGBA values
    pub fn fromRgba16(r: u16, g: u16, b: u16, a: u16) XRGBAColor {
        return XRGBAColor{ .r = r, .g = g, .b = b, .a = a };
    }

    /// Create from HexColor with alpha
    pub fn fromHexWithAlpha(hex_color: HexColor, alpha: u8) XRGBAColor {
        return fromRgba8(hex_color.r, hex_color.g, hex_color.b, alpha);
    }

    /// Format as XParseColor rgba: string (e.g., "rgba:ffff/0000/0000/ffff")
    pub fn toRgbaString(self: XRGBAColor, allocator: std.mem.Allocator) ![]u8 {
        return try fmt.allocPrint(allocator, "rgba:{:04x}/{:04x}/{:04x}/{:04x}", .{ self.r, self.g, self.b, self.a });
    }

    pub fn format(self: XRGBAColor, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("rgba:{:04x}/{:04x}/{:04x}/{:04x}", .{ self.r, self.g, self.b, self.a });
    }
};

/// Terminal background/foreground color control functions
pub const TerminalColors = struct {
    /// Set terminal foreground color using string representation
    /// Supports hex, rgb:, and rgba: formats
    pub fn setForegroundColor(color_str: []const u8, allocator: std.mem.Allocator) ![]u8 {
        return try fmt.allocPrint(allocator, "\x1b]10;{s}\x07", .{color_str});
    }

    /// Set terminal foreground color using HexColor
    pub fn setForegroundHex(color: HexColor, allocator: std.mem.Allocator) ![]u8 {
        const hex_str = try color.toHex(allocator);
        defer allocator.free(hex_str);
        return try fmt.allocPrint(allocator, "\x1b]10;{s}\x07", .{hex_str});
    }

    /// Set terminal foreground color using XRGBColor
    pub fn setForegroundRgb(color: XRGBColor, allocator: std.mem.Allocator) ![]u8 {
        const rgb_str = try color.toRgbString(allocator);
        defer allocator.free(rgb_str);
        return try fmt.allocPrint(allocator, "\x1b]10;{s}\x07", .{rgb_str});
    }

    /// Request current terminal foreground color
    pub const REQUEST_FOREGROUND_COLOR = "\x1b]10;?\x07";

    /// Reset terminal foreground color to default
    pub const RESET_FOREGROUND_COLOR = "\x1b]110\x07";

    /// Set terminal background color using string representation
    /// Supports hex, rgb:, and rgba: formats
    pub fn setBackgroundColor(color_str: []const u8, allocator: std.mem.Allocator) ![]u8 {
        return try fmt.allocPrint(allocator, "\x1b]11;{s}\x07", .{color_str});
    }

    /// Set terminal background color using HexColor
    pub fn setBackgroundHex(color: HexColor, allocator: std.mem.Allocator) ![]u8 {
        const hex_str = try color.toHex(allocator);
        defer allocator.free(hex_str);
        return try fmt.allocPrint(allocator, "\x1b]11;{s}\x07", .{hex_str});
    }

    /// Set terminal background color using XRGBColor
    pub fn setBackgroundRgb(color: XRGBColor, allocator: std.mem.Allocator) ![]u8 {
        const rgb_str = try color.toRgbString(allocator);
        defer allocator.free(rgb_str);
        return try fmt.allocPrint(allocator, "\x1b]11;{s}\x07", .{rgb_str});
    }

    /// Request current terminal background color
    pub const REQUEST_BACKGROUND_COLOR = "\x1b]11;?\x07";

    /// Reset terminal background color to default
    pub const RESET_BACKGROUND_COLOR = "\x1b]111\x07";

    /// Set terminal cursor color using string representation
    /// Supports hex, rgb:, and rgba: formats
    pub fn setCursorColor(color_str: []const u8, allocator: std.mem.Allocator) ![]u8 {
        return try fmt.allocPrint(allocator, "\x1b]12;{s}\x07", .{color_str});
    }

    /// Set terminal cursor color using HexColor
    pub fn setCursorHex(color: HexColor, allocator: std.mem.Allocator) ![]u8 {
        const hex_str = try color.toHex(allocator);
        defer allocator.free(hex_str);
        return try fmt.allocPrint(allocator, "\x1b]12;{s}\x07", .{hex_str});
    }

    /// Set terminal cursor color using XRGBColor
    pub fn setCursorRgb(color: XRGBColor, allocator: std.mem.Allocator) ![]u8 {
        const rgb_str = try color.toRgbString(allocator);
        defer allocator.free(rgb_str);
        return try fmt.allocPrint(allocator, "\x1b]12;{s}\x07", .{rgb_str});
    }

    /// Request current terminal cursor color
    pub const REQUEST_CURSOR_COLOR = "\x1b]12;?\x07";

    /// Reset terminal cursor color to default
    pub const RESET_CURSOR_COLOR = "\x1b]112\x07";
};

// Tests
test "HexColor creation and formatting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const red = HexColor.fromRgb(255, 0, 0);
    const hex_str = try red.toHex(allocator);
    defer allocator.free(hex_str);

    try testing.expectEqualStrings("#ff0000", hex_str);

    const from_hex = try HexColor.fromHex("#FF0000");
    try testing.expectEqual(@as(u8, 255), from_hex.r);
    try testing.expectEqual(@as(u8, 0), from_hex.g);
    try testing.expectEqual(@as(u8, 0), from_hex.b);
}

test "XRGBColor formatting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const red = XRGBColor.fromRgb8(255, 0, 0);
    const rgb_str = try red.toRgbString(allocator);
    defer allocator.free(rgb_str);

    try testing.expectEqualStrings("rgb:ffff/0000/0000", rgb_str);
}

test "TerminalColors functions" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const red = HexColor.fromRgb(255, 0, 0);
    const fg_seq = try TerminalColors.setForegroundHex(red, allocator);
    defer allocator.free(fg_seq);

    try testing.expectEqualStrings("\x1b]10;#ff0000\x07", fg_seq);

    const bg_seq = try TerminalColors.setBackgroundColor("rgb:ffff/0000/0000", allocator);
    defer allocator.free(bg_seq);

    try testing.expectEqualStrings("\x1b]11;rgb:ffff/0000/0000\x07", bg_seq);
}

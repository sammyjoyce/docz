const std = @import("std");
const enhanced_color = @import("enhanced_color.zig");

// Import existing types for compatibility
pub const RGBA = enhanced_color.RGBA;
pub const BasicColor = enhanced_color.BasicColor;
pub const IndexedColor = enhanced_color.IndexedColor;
pub const RGBColor = enhanced_color.RGBColor;
pub const Color = enhanced_color.Color;

// Hex color string support - like Charmbracelet's HexColor
pub const HexColor = struct {
    hex: []const u8,

    pub fn init(hex_string: []const u8) HexColor {
        return HexColor{ .hex = hex_string };
    }

    pub fn toRGBColor(self: HexColor) !RGBColor {
        if (self.hex.len < 6) return error.InvalidHexColor;

        // Skip '#' if present
        const hex_start: usize = if (self.hex[0] == '#') 1 else 0;
        if (self.hex.len - hex_start != 6) return error.InvalidHexColor;

        const hex_value = try std.fmt.parseUnsigned(u32, self.hex[hex_start .. hex_start + 6], 16);
        return RGBColor.fromHex(hex_value);
    }

    pub fn toRGBA(self: HexColor) !RGBA {
        const rgb = try self.toRGBColor();
        return rgb.toRGBA();
    }
};

// XParseColor rgb: string support - X11 color specification
pub const XRGBColor = struct {
    r: u16,
    g: u16,
    b: u16,

    pub fn init(r: u16, g: u16, b: u16) XRGBColor {
        return XRGBColor{ .r = r, .g = g, .b = b };
    }

    pub fn toRGBColor(self: XRGBColor) RGBColor {
        // Convert from 16-bit to 8-bit by taking upper 8 bits
        return RGBColor{
            .r = @truncate(self.r >> 8),
            .g = @truncate(self.g >> 8),
            .b = @truncate(self.b >> 8),
        };
    }

    pub fn toRGBA(self: XRGBColor) RGBA {
        return self.toRGBColor().toRGBA();
    }

    pub fn toString(self: XRGBColor, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "rgb:{x:0>4}/{x:0>4}/{x:0>4}", .{ self.r, self.g, self.b });
    }
};

// XParseColor rgba: string support - X11 color specification with alpha
pub const XRGBAColor = struct {
    r: u16,
    g: u16,
    b: u16,
    a: u16,

    pub fn init(r: u16, g: u16, b: u16, a: u16) XRGBAColor {
        return XRGBAColor{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn toRGBA(self: XRGBAColor) RGBA {
        return RGBA{
            .r = @truncate(self.r >> 8),
            .g = @truncate(self.g >> 8),
            .b = @truncate(self.b >> 8),
            .a = @truncate(self.a >> 8),
        };
    }

    pub fn toString(self: XRGBAColor, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "rgba:{x:0>4}/{x:0>4}/{x:0>4}/{x:0>4}", .{ self.r, self.g, self.b, self.a });
    }
};

// Enhanced color conversion using better distance calculations
// Implements the Charmbracelet approach with improved color matching

// Convert to 6-cube value for xterm 256-color palette (more accurate than existing)
fn to6CubeFloat(v: f64) u8 {
    if (v < 48.0) return 0;
    if (v < 115.0) return 1;
    return @min(5, @as(u8, @intFromFloat((v - 35.0) / 40.0)));
}

// Enhanced 256-color conversion with better color matching
pub fn convert256Enhanced(rgba: RGBA) IndexedColor {
    const r = @as(f64, @floatFromInt(rgba.r));
    const g = @as(f64, @floatFromInt(rgba.g));
    const b = @as(f64, @floatFromInt(rgba.b));

    // xterm 6x6x6 color cube levels
    const q2c = [6]u8{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };

    // Map RGB to 6x6x6 cube
    const qr = to6CubeFloat(r);
    const cr = q2c[qr];
    const qg = to6CubeFloat(g);
    const cg = q2c[qg];
    const qb = to6CubeFloat(b);
    const cb = q2c[qb];

    // Calculate cube index
    const ci = (36 * qr) + (6 * qg) + qb;

    // Check if we hit the color exactly
    if (cr == rgba.r and cg == rgba.g and cb == rgba.b) {
        return @enumFromInt(16 + ci);
    }

    // Work out the closest grey (average of RGB)
    const grey_avg = (@as(u32, rgba.r) + @as(u32, rgba.g) + @as(u32, rgba.b)) / 3;
    const grey_idx: u8 = if (grey_avg > 238) 23 else @min(23, @as(u8, @intCast((grey_avg - 8) / 10)));
    const grey: u8 = 8 + (10 * grey_idx);

    // Use perceptual distance rather than simple Euclidean distance
    // This gives better color matching results
    const color_dist = perceptualDistance(cr, cg, cb, rgba.r, rgba.g, rgba.b);
    const grey_dist = perceptualDistance(grey, grey, grey, rgba.r, rgba.g, rgba.b);

    if (color_dist <= grey_dist) {
        return @enumFromInt(16 + ci);
    } else {
        return @enumFromInt(232 + grey_idx);
    }
}

// Perceptual distance calculation for better color matching
// Based on human perception of color differences
fn perceptualDistance(r1: u8, g1: u8, b1: u8, r2: u8, g2: u8, b2: u8) f64 {
    const dr = @as(f64, @floatFromInt(r1)) - @as(f64, @floatFromInt(r2));
    const dg = @as(f64, @floatFromInt(g1)) - @as(f64, @floatFromInt(g2));
    const db = @as(f64, @floatFromInt(b1)) - @as(f64, @floatFromInt(b2));

    // Weighted Euclidean distance with perceptual weights
    // Green is more perceptually significant than red or blue
    const weight_r = 0.30;
    const weight_g = 0.59;
    const weight_b = 0.11;

    return @sqrt((weight_r * dr * dr) + (weight_g * dg * dg) + (weight_b * db * db));
}

// Complete ANSI 256-color to 16-color mapping table from Charmbracelet
const ansi256To16Complete = blk: {
    var mapping: [256]BasicColor = undefined;

    // 0-15: direct mapping
    mapping[0] = BasicColor.black;
    mapping[1] = BasicColor.red;
    mapping[2] = BasicColor.green;
    mapping[3] = BasicColor.yellow;
    mapping[4] = BasicColor.blue;
    mapping[5] = BasicColor.magenta;
    mapping[6] = BasicColor.cyan;
    mapping[7] = BasicColor.white;
    mapping[8] = BasicColor.bright_black;
    mapping[9] = BasicColor.bright_red;
    mapping[10] = BasicColor.bright_green;
    mapping[11] = BasicColor.bright_yellow;
    mapping[12] = BasicColor.bright_blue;
    mapping[13] = BasicColor.bright_magenta;
    mapping[14] = BasicColor.bright_cyan;
    mapping[15] = BasicColor.bright_white;

    // 16-231: 6x6x6 color cube - simplified mapping
    for (16..232) |i| {
        const color_idx = i - 16;
        const r = color_idx / 36;
        const g = (color_idx % 36) / 6;
        const b = color_idx % 6;

        // Map to closest 16-color based on RGB values
        if (r < 2 and g < 2 and b < 2) {
            mapping[i] = BasicColor.black;
        } else if (r >= 4 and g >= 4 and b >= 4) {
            mapping[i] = BasicColor.bright_white;
        } else if (r >= 3 and g < 2 and b < 2) {
            mapping[i] = BasicColor.red;
        } else if (r < 2 and g >= 3 and b < 2) {
            mapping[i] = BasicColor.green;
        } else if (r >= 3 and g >= 3 and b < 2) {
            mapping[i] = BasicColor.yellow;
        } else if (r < 2 and g < 2 and b >= 3) {
            mapping[i] = BasicColor.blue;
        } else if (r >= 3 and g < 2 and b >= 3) {
            mapping[i] = BasicColor.magenta;
        } else if (r < 2 and g >= 3 and b >= 3) {
            mapping[i] = BasicColor.cyan;
        } else {
            mapping[i] = BasicColor.white;
        }
    }

    // 232-255: greyscale ramp
    for (232..256) |i| {
        const grey_level = i - 232;
        if (grey_level < 8) {
            mapping[i] = BasicColor.black;
        } else if (grey_level < 16) {
            mapping[i] = BasicColor.bright_black;
        } else {
            mapping[i] = BasicColor.white;
        }
    }

    break :blk mapping;
};

// Enhanced conversion to 16-color using the complete mapping table
pub fn convert16Enhanced(rgba: RGBA) BasicColor {
    const c256 = convert256Enhanced(rgba);
    return ansi256To16Complete[@intFromEnum(c256)];
}

// Color format detection and conversion utilities
pub fn parseColorString(color_str: []const u8) !Color {
    if (color_str.len == 0) return error.InvalidColorString;

    // Check for hex colors (#rrggbb or rrggbb)
    if (color_str[0] == '#' or (color_str.len == 6 and std.fmt.parseUnsigned(u32, color_str, 16) catch null != null)) {
        const hex = HexColor.init(color_str);
        const rgb = try hex.toRGBColor();
        return Color{ .rgb = rgb };
    }

    // Check for rgb: format (XParseColor)
    if (std.mem.startsWith(u8, color_str, "rgb:")) {
        // Parse rgb:rrrr/gggg/bbbb format
        var parts = std.mem.splitScalar(u8, color_str[4..], '/');
        var component_buf: [3][]const u8 = undefined;
        var i: usize = 0;
        while (parts.next()) |part| {
            if (i >= 3) return error.InvalidColorString;
            component_buf[i] = part;
            i += 1;
        }
        if (i != 3) return error.InvalidColorString;

        const r = try std.fmt.parseUnsigned(u16, component_buf[0], 16);
        const g = try std.fmt.parseUnsigned(u16, component_buf[1], 16);
        const b = try std.fmt.parseUnsigned(u16, component_buf[2], 16);

        const xrgb = XRGBColor.init(r, g, b);
        const rgb = xrgb.toRGBColor();
        return Color{ .rgb = rgb };
    }

    return error.UnsupportedColorFormat;
}

test "hex color parsing" {
    const hex1 = HexColor.init("#ff0000");
    const rgb1 = try hex1.toRGBColor();
    try std.testing.expect(rgb1.r == 255);
    try std.testing.expect(rgb1.g == 0);
    try std.testing.expect(rgb1.b == 0);

    const hex2 = HexColor.init("00ff00");
    const rgb2 = try hex2.toRGBColor();
    try std.testing.expect(rgb2.r == 0);
    try std.testing.expect(rgb2.g == 255);
    try std.testing.expect(rgb2.b == 0);
}

test "xrgb color formatting" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const xrgb = XRGBColor.init(0xffff, 0x8000, 0x0000);
    const str = try xrgb.toString(allocator);
    defer allocator.free(str);

    try std.testing.expect(std.mem.eql(u8, str, "rgb:ffff/8000/0000"));
}

test "enhanced color conversion" {
    const red = RGBA{ .r = 255, .g = 0, .b = 0 };
    const idx = convert256Enhanced(red);
    const basic = convert16Enhanced(red);

    // Should be a red-ish color
    try std.testing.expect(@intFromEnum(idx) >= 16);
    try std.testing.expect(basic == BasicColor.red or basic == BasicColor.bright_red);
}

test "color string parsing" {
    const color1 = try parseColorString("#ff0000");
    const rgba1 = color1.toRGBA();
    try std.testing.expect(rgba1.r == 255);
    try std.testing.expect(rgba1.g == 0);
    try std.testing.expect(rgba1.b == 0);

    const color2 = try parseColorString("rgb:ffff/0000/0000");
    const rgba2 = color2.toRGBA();
    try std.testing.expect(rgba2.r == 255);
    try std.testing.expect(rgba2.g == 0);
    try std.testing.expect(rgba2.b == 0);
}

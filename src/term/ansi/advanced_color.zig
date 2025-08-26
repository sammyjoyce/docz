const std = @import("std");

// Advanced color management system inspired by Charmbracelet X
// Supports 16-color, 256-color, and true color (RGB) with conversion algorithms

/// Color interface - all terminal colors implement this
pub const Color = union(enum) {
    basic: BasicColor,
    indexed: IndexedColor,
    rgb: RGBColor,
    hex: HexColor,

    pub fn toRgb(self: Color) RGBColor {
        return switch (self) {
            .basic => |c| c.toRgb(),
            .indexed => |c| c.toRgb(),
            .rgb => |c| c,
            .hex => |c| c.toRgb(),
        };
    }
};

/// ANSI 3-bit or 4-bit color with values 0-15
pub const BasicColor = enum(u8) {
    black = 0,
    red = 1,
    green = 2,
    yellow = 3,
    blue = 4,
    magenta = 5,
    cyan = 6,
    white = 7,
    bright_black = 8,
    bright_red = 9,
    bright_green = 10,
    bright_yellow = 11,
    bright_blue = 12,
    bright_magenta = 13,
    bright_cyan = 14,
    bright_white = 15,

    pub fn toRgb(self: BasicColor) RGBColor {
        return ansi16ToRgb(@intFromEnum(self));
    }
};

/// ANSI 256 (8-bit) color with values 0-255
pub const IndexedColor = struct {
    index: u8,

    pub fn init(index: u8) IndexedColor {
        return IndexedColor{ .index = index };
    }

    pub fn toRgb(self: IndexedColor) RGBColor {
        return ansi256ToRgb(self.index);
    }

    pub fn toBasic(self: IndexedColor) BasicColor {
        return @enumFromInt(ansi256To16[self.index]);
    }
};

/// 24-bit RGB color
pub const RGBColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RGBColor {
        return RGBColor{ .r = r, .g = g, .b = b };
    }

    pub fn fromHex(hex: u32) RGBColor {
        return RGBColor{
            .r = @intCast((hex >> 16) & 0xFF),
            .g = @intCast((hex >> 8) & 0xFF),
            .b = @intCast(hex & 0xFF),
        };
    }

    pub fn toHex(self: RGBColor) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }

    pub fn toIndexed(self: RGBColor) IndexedColor {
        return IndexedColor.init(convert256(self));
    }

    pub fn toBasic(self: RGBColor) BasicColor {
        return self.toIndexed().toBasic();
    }

    pub fn distanceSquared(self: RGBColor, other: RGBColor) u32 {
        const dr = @as(i32, self.r) - @as(i32, other.r);
        const dg = @as(i32, self.g) - @as(i32, other.g);
        const db = @as(i32, self.b) - @as(i32, other.b);
        return @intCast(dr * dr + dg * dg + db * db);
    }
};

/// Hex color string support
pub const HexColor = struct {
    hex: u32,

    pub fn init(hex: u32) HexColor {
        return HexColor{ .hex = hex };
    }

    pub fn parseFromString(hex_str: []const u8) !HexColor {
        const clean = if (hex_str.len > 0 and hex_str[0] == '#') hex_str[1..] else hex_str;
        if (clean.len != 6) return error.InvalidHexColor;

        const hex = std.fmt.parseInt(u32, clean, 16) catch return error.InvalidHexColor;
        return HexColor.init(hex);
    }

    pub fn toRgb(self: HexColor) RGBColor {
        return RGBColor.fromHex(self.hex);
    }

    pub fn toString(self: HexColor, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "#{:06x}", .{self.hex});
    }
};

/// Color conversion: 24-bit RGB to xterm 256-color palette
/// Uses 6x6x6 color cube (16-231) and 24 greys (232-255)
pub fn convert256(rgb: RGBColor) u8 {
    const r = @as(i32, rgb.r);
    const g = @as(i32, rgb.g);
    const b = @as(i32, rgb.b);

    // 6-level color cube values: 0, 95, 135, 175, 215, 255
    const q2c = [6]i32{ 0, 95, 135, 175, 215, 255 };

    // Map RGB to 6x6x6 cube
    const qr = to6Cube(r);
    const cr = q2c[qr];
    const qg = to6Cube(g);
    const cg = q2c[qg];
    const qb = to6Cube(b);
    const cb = q2c[qb];

    // Cube color index
    const ci: u8 = @intCast(36 * qr + 6 * qg + qb);

    // If exact match, return early
    if (cr == r and cg == g and cb == b) {
        return 16 + ci;
    }

    // Find closest grey (average of RGB)
    const grey_avg = (r + g + b) / 3;
    const grey_idx: u8 = if (grey_avg > 238) 23 else @intCast(@max(0, (grey_avg - 8) / 10));
    const grey = 8 + (10 * @as(i32, grey_idx));

    // Return the closer match based on distance
    const cube_rgb = RGBColor.init(@intCast(cr), @intCast(cg), @intCast(cb));
    const grey_rgb = RGBColor.init(@intCast(grey), @intCast(grey), @intCast(grey));

    if (rgb.distanceSquared(cube_rgb) <= rgb.distanceSquared(grey_rgb)) {
        return 16 + ci;
    } else {
        return 232 + grey_idx;
    }
}

fn to6Cube(v: i32) usize {
    if (v < 48) return 0;
    if (v < 115) return 1;
    return @min(5, @as(usize, @intCast((v - 35) / 40)));
}

/// Convert ANSI 256 color to RGB
fn ansi256ToRgb(index: u8) RGBColor {
    return ansi256_palette[index];
}

/// Convert ANSI 16 color to RGB
fn ansi16ToRgb(index: u8) RGBColor {
    if (index > 15) return RGBColor.init(0, 0, 0);
    return ansi256_palette[index];
}

// ANSI 256-color palette RGB values
const ansi256_palette = [256]RGBColor{
    // Standard colors (0-15)
    RGBColor.init(0x00, 0x00, 0x00), RGBColor.init(0x80, 0x00, 0x00), RGBColor.init(0x00, 0x80, 0x00), RGBColor.init(0x80, 0x80, 0x00),
    RGBColor.init(0x00, 0x00, 0x80), RGBColor.init(0x80, 0x00, 0x80), RGBColor.init(0x00, 0x80, 0x80), RGBColor.init(0xC0, 0xC0, 0xC0),
    RGBColor.init(0x80, 0x80, 0x80), RGBColor.init(0xFF, 0x00, 0x00), RGBColor.init(0x00, 0xFF, 0x00), RGBColor.init(0xFF, 0xFF, 0x00),
    RGBColor.init(0x00, 0x00, 0xFF), RGBColor.init(0xFF, 0x00, 0xFF), RGBColor.init(0x00, 0xFF, 0xFF), RGBColor.init(0xFF, 0xFF, 0xFF),

    // 216 colors (16-231): 6x6x6 color cube
    RGBColor.init(0x00, 0x00, 0x00), RGBColor.init(0x00, 0x00, 0x5F), RGBColor.init(0x00, 0x00, 0x87), RGBColor.init(0x00, 0x00, 0xAF),
    RGBColor.init(0x00, 0x00, 0xD7), RGBColor.init(0x00, 0x00, 0xFF), RGBColor.init(0x00, 0x5F, 0x00), RGBColor.init(0x00, 0x5F, 0x5F),
    RGBColor.init(0x00, 0x5F, 0x87), RGBColor.init(0x00, 0x5F, 0xAF), RGBColor.init(0x00, 0x5F, 0xD7), RGBColor.init(0x00, 0x5F, 0xFF),
    RGBColor.init(0x00, 0x87, 0x00), RGBColor.init(0x00, 0x87, 0x5F), RGBColor.init(0x00, 0x87, 0x87), RGBColor.init(0x00, 0x87, 0xAF),
    RGBColor.init(0x00, 0x87, 0xD7), RGBColor.init(0x00, 0x87, 0xFF), RGBColor.init(0x00, 0xAF, 0x00), RGBColor.init(0x00, 0xAF, 0x5F),
    RGBColor.init(0x00, 0xAF, 0x87), RGBColor.init(0x00, 0xAF, 0xAF), RGBColor.init(0x00, 0xAF, 0xD7), RGBColor.init(0x00, 0xAF, 0xFF),
    RGBColor.init(0x00, 0xD7, 0x00), RGBColor.init(0x00, 0xD7, 0x5F), RGBColor.init(0x00, 0xD7, 0x87), RGBColor.init(0x00, 0xD7, 0xAF),
    RGBColor.init(0x00, 0xD7, 0xD7), RGBColor.init(0x00, 0xD7, 0xFF), RGBColor.init(0x00, 0xFF, 0x00), RGBColor.init(0x00, 0xFF, 0x5F),
    RGBColor.init(0x00, 0xFF, 0x87), RGBColor.init(0x00, 0xFF, 0xAF), RGBColor.init(0x00, 0xFF, 0xD7), RGBColor.init(0x00, 0xFF, 0xFF),
    RGBColor.init(0x5F, 0x00, 0x00), RGBColor.init(0x5F, 0x00, 0x5F), RGBColor.init(0x5F, 0x00, 0x87), RGBColor.init(0x5F, 0x00, 0xAF),
    RGBColor.init(0x5F, 0x00, 0xD7), RGBColor.init(0x5F, 0x00, 0xFF), RGBColor.init(0x5F, 0x5F, 0x00), RGBColor.init(0x5F, 0x5F, 0x5F),
    RGBColor.init(0x5F, 0x5F, 0x87), RGBColor.init(0x5F, 0x5F, 0xAF), RGBColor.init(0x5F, 0x5F, 0xD7), RGBColor.init(0x5F, 0x5F, 0xFF),
    RGBColor.init(0x5F, 0x87, 0x00), RGBColor.init(0x5F, 0x87, 0x5F), RGBColor.init(0x5F, 0x87, 0x87), RGBColor.init(0x5F, 0x87, 0xAF),
    RGBColor.init(0x5F, 0x87, 0xD7), RGBColor.init(0x5F, 0x87, 0xFF), RGBColor.init(0x5F, 0xAF, 0x00), RGBColor.init(0x5F, 0xAF, 0x5F),
    RGBColor.init(0x5F, 0xAF, 0x87), RGBColor.init(0x5F, 0xAF, 0xAF), RGBColor.init(0x5F, 0xAF, 0xD7), RGBColor.init(0x5F, 0xAF, 0xFF),
    RGBColor.init(0x5F, 0xD7, 0x00), RGBColor.init(0x5F, 0xD7, 0x5F), RGBColor.init(0x5F, 0xD7, 0x87), RGBColor.init(0x5F, 0xD7, 0xAF),
    RGBColor.init(0x5F, 0xD7, 0xD7), RGBColor.init(0x5F, 0xD7, 0xFF), RGBColor.init(0x5F, 0xFF, 0x00), RGBColor.init(0x5F, 0xFF, 0x5F),
    RGBColor.init(0x5F, 0xFF, 0x87), RGBColor.init(0x5F, 0xFF, 0xAF), RGBColor.init(0x5F, 0xFF, 0xD7), RGBColor.init(0x5F, 0xFF, 0xFF),
    // Continue with remaining cube colors...
    RGBColor.init(0x87, 0x00, 0x00), RGBColor.init(0x87, 0x00, 0x5F), RGBColor.init(0x87, 0x00, 0x87), RGBColor.init(0x87, 0x00, 0xAF),
    RGBColor.init(0x87, 0x00, 0xD7), RGBColor.init(0x87, 0x00, 0xFF), RGBColor.init(0x87, 0x5F, 0x00), RGBColor.init(0x87, 0x5F, 0x5F),
    RGBColor.init(0x87, 0x5F, 0x87), RGBColor.init(0x87, 0x5F, 0xAF), RGBColor.init(0x87, 0x5F, 0xD7), RGBColor.init(0x87, 0x5F, 0xFF),
    RGBColor.init(0x87, 0x87, 0x00), RGBColor.init(0x87, 0x87, 0x5F), RGBColor.init(0x87, 0x87, 0x87), RGBColor.init(0x87, 0x87, 0xAF),
    RGBColor.init(0x87, 0x87, 0xD7), RGBColor.init(0x87, 0x87, 0xFF), RGBColor.init(0x87, 0xAF, 0x00), RGBColor.init(0x87, 0xAF, 0x5F),
    RGBColor.init(0x87, 0xAF, 0x87), RGBColor.init(0x87, 0xAF, 0xAF), RGBColor.init(0x87, 0xAF, 0xD7), RGBColor.init(0x87, 0xAF, 0xFF),
    RGBColor.init(0x87, 0xD7, 0x00), RGBColor.init(0x87, 0xD7, 0x5F), RGBColor.init(0x87, 0xD7, 0x87), RGBColor.init(0x87, 0xD7, 0xAF),
    RGBColor.init(0x87, 0xD7, 0xD7), RGBColor.init(0x87, 0xD7, 0xFF), RGBColor.init(0x87, 0xFF, 0x00), RGBColor.init(0x87, 0xFF, 0x5F),
    RGBColor.init(0x87, 0xFF, 0x87), RGBColor.init(0x87, 0xFF, 0xAF), RGBColor.init(0x87, 0xFF, 0xD7), RGBColor.init(0x87, 0xFF, 0xFF),
    RGBColor.init(0xAF, 0x00, 0x00), RGBColor.init(0xAF, 0x00, 0x5F), RGBColor.init(0xAF, 0x00, 0x87), RGBColor.init(0xAF, 0x00, 0xAF),
    RGBColor.init(0xAF, 0x00, 0xD7), RGBColor.init(0xAF, 0x00, 0xFF), RGBColor.init(0xAF, 0x5F, 0x00), RGBColor.init(0xAF, 0x5F, 0x5F),
    RGBColor.init(0xAF, 0x5F, 0x87), RGBColor.init(0xAF, 0x5F, 0xAF), RGBColor.init(0xAF, 0x5F, 0xD7), RGBColor.init(0xAF, 0x5F, 0xFF),
    RGBColor.init(0xAF, 0x87, 0x00), RGBColor.init(0xAF, 0x87, 0x5F), RGBColor.init(0xAF, 0x87, 0x87), RGBColor.init(0xAF, 0x87, 0xAF),
    RGBColor.init(0xAF, 0x87, 0xD7), RGBColor.init(0xAF, 0x87, 0xFF), RGBColor.init(0xAF, 0xAF, 0x00), RGBColor.init(0xAF, 0xAF, 0x5F),
    RGBColor.init(0xAF, 0xAF, 0x87), RGBColor.init(0xAF, 0xAF, 0xAF), RGBColor.init(0xAF, 0xAF, 0xD7), RGBColor.init(0xAF, 0xAF, 0xFF),
    RGBColor.init(0xAF, 0xD7, 0x00), RGBColor.init(0xAF, 0xD7, 0x5F), RGBColor.init(0xAF, 0xD7, 0x87), RGBColor.init(0xAF, 0xD7, 0xAF),
    RGBColor.init(0xAF, 0xD7, 0xD7), RGBColor.init(0xAF, 0xD7, 0xFF), RGBColor.init(0xAF, 0xFF, 0x00), RGBColor.init(0xAF, 0xFF, 0x5F),
    RGBColor.init(0xAF, 0xFF, 0x87), RGBColor.init(0xAF, 0xFF, 0xAF), RGBColor.init(0xAF, 0xFF, 0xD7), RGBColor.init(0xAF, 0xFF, 0xFF),
    RGBColor.init(0xD7, 0x00, 0x00), RGBColor.init(0xD7, 0x00, 0x5F), RGBColor.init(0xD7, 0x00, 0x87), RGBColor.init(0xD7, 0x00, 0xAF),
    RGBColor.init(0xD7, 0x00, 0xD7), RGBColor.init(0xD7, 0x00, 0xFF), RGBColor.init(0xD7, 0x5F, 0x00), RGBColor.init(0xD7, 0x5F, 0x5F),
    RGBColor.init(0xD7, 0x5F, 0x87), RGBColor.init(0xD7, 0x5F, 0xAF), RGBColor.init(0xD7, 0x5F, 0xD7), RGBColor.init(0xD7, 0x5F, 0xFF),
    RGBColor.init(0xD7, 0x87, 0x00), RGBColor.init(0xD7, 0x87, 0x5F), RGBColor.init(0xD7, 0x87, 0x87), RGBColor.init(0xD7, 0x87, 0xAF),
    RGBColor.init(0xD7, 0x87, 0xD7), RGBColor.init(0xD7, 0x87, 0xFF), RGBColor.init(0xD7, 0xAF, 0x00), RGBColor.init(0xD7, 0xAF, 0x5F),
    RGBColor.init(0xD7, 0xAF, 0x87), RGBColor.init(0xD7, 0xAF, 0xAF), RGBColor.init(0xD7, 0xAF, 0xD7), RGBColor.init(0xD7, 0xAF, 0xFF),
    RGBColor.init(0xD7, 0xD7, 0x00), RGBColor.init(0xD7, 0xD7, 0x5F), RGBColor.init(0xD7, 0xD7, 0x87), RGBColor.init(0xD7, 0xD7, 0xAF),
    RGBColor.init(0xD7, 0xD7, 0xD7), RGBColor.init(0xD7, 0xD7, 0xFF), RGBColor.init(0xD7, 0xFF, 0x00), RGBColor.init(0xD7, 0xFF, 0x5F),
    RGBColor.init(0xD7, 0xFF, 0x87), RGBColor.init(0xD7, 0xFF, 0xAF), RGBColor.init(0xD7, 0xFF, 0xD7), RGBColor.init(0xD7, 0xFF, 0xFF),
    RGBColor.init(0xFF, 0x00, 0x00), RGBColor.init(0xFF, 0x00, 0x5F), RGBColor.init(0xFF, 0x00, 0x87), RGBColor.init(0xFF, 0x00, 0xAF),
    RGBColor.init(0xFF, 0x00, 0xD7), RGBColor.init(0xFF, 0x00, 0xFF), RGBColor.init(0xFF, 0x5F, 0x00), RGBColor.init(0xFF, 0x5F, 0x5F),
    RGBColor.init(0xFF, 0x5F, 0x87), RGBColor.init(0xFF, 0x5F, 0xAF), RGBColor.init(0xFF, 0x5F, 0xD7), RGBColor.init(0xFF, 0x5F, 0xFF),
    RGBColor.init(0xFF, 0x87, 0x00), RGBColor.init(0xFF, 0x87, 0x5F), RGBColor.init(0xFF, 0x87, 0x87), RGBColor.init(0xFF, 0x87, 0xAF),
    RGBColor.init(0xFF, 0x87, 0xD7), RGBColor.init(0xFF, 0x87, 0xFF), RGBColor.init(0xFF, 0xAF, 0x00), RGBColor.init(0xFF, 0xAF, 0x5F),
    RGBColor.init(0xFF, 0xAF, 0x87), RGBColor.init(0xFF, 0xAF, 0xAF), RGBColor.init(0xFF, 0xAF, 0xD7), RGBColor.init(0xFF, 0xAF, 0xFF),
    RGBColor.init(0xFF, 0xD7, 0x00), RGBColor.init(0xFF, 0xD7, 0x5F), RGBColor.init(0xFF, 0xD7, 0x87), RGBColor.init(0xFF, 0xD7, 0xAF),
    RGBColor.init(0xFF, 0xD7, 0xD7), RGBColor.init(0xFF, 0xD7, 0xFF), RGBColor.init(0xFF, 0xFF, 0x00), RGBColor.init(0xFF, 0xFF, 0x5F),
    RGBColor.init(0xFF, 0xFF, 0x87), RGBColor.init(0xFF, 0xFF, 0xAF), RGBColor.init(0xFF, 0xFF, 0xD7), RGBColor.init(0xFF, 0xFF, 0xFF),

    // 24 greyscale colors (232-255)
    RGBColor.init(0x08, 0x08, 0x08), RGBColor.init(0x12, 0x12, 0x12), RGBColor.init(0x1C, 0x1C, 0x1C), RGBColor.init(0x26, 0x26, 0x26),
    RGBColor.init(0x30, 0x30, 0x30), RGBColor.init(0x3A, 0x3A, 0x3A), RGBColor.init(0x44, 0x44, 0x44), RGBColor.init(0x4E, 0x4E, 0x4E),
    RGBColor.init(0x58, 0x58, 0x58), RGBColor.init(0x62, 0x62, 0x62), RGBColor.init(0x6C, 0x6C, 0x6C), RGBColor.init(0x76, 0x76, 0x76),
    RGBColor.init(0x80, 0x80, 0x80), RGBColor.init(0x8A, 0x8A, 0x8A), RGBColor.init(0x94, 0x94, 0x94), RGBColor.init(0x9E, 0x9E, 0x9E),
    RGBColor.init(0xA8, 0xA8, 0xA8), RGBColor.init(0xB2, 0xB2, 0xB2), RGBColor.init(0xBC, 0xBC, 0xBC), RGBColor.init(0xC6, 0xC6, 0xC6),
    RGBColor.init(0xD0, 0xD0, 0xD0), RGBColor.init(0xDA, 0xDA, 0xDA), RGBColor.init(0xE4, 0xE4, 0xE4), RGBColor.init(0xEE, 0xEE, 0xEE),
};

// Mapping from ANSI 256 colors to 16 colors
const ansi256To16 = [256]u8{
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
    0,  4,  4,  4,  12, 12, 2,  6,  4,  4,  12, 12, 2,  2,  6,  4,
    12, 12, 2,  2,  2,  6,  12, 12, 10, 10, 10, 10, 14, 12, 10, 10,
    10, 10, 10, 14, 1,  5,  4,  4,  12, 12, 3,  8,  4,  4,  12, 12,
    2,  2,  6,  4,  12, 12, 2,  2,  2,  6,  12, 12, 10, 10, 10, 10,
    14, 12, 10, 10, 10, 10, 10, 14, 1,  1,  5,  4,  12, 12, 1,  1,
    5,  4,  12, 12, 3,  3,  8,  4,  12, 12, 2,  2,  2,  6,  12, 12,
    10, 10, 10, 10, 14, 12, 10, 10, 10, 10, 10, 14, 1,  1,  1,  5,
    12, 12, 1,  1,  1,  5,  12, 12, 1,  1,  1,  5,  12, 12, 3,  3,
    3,  7,  12, 12, 10, 10, 10, 10, 14, 12, 10, 10, 10, 10, 10, 14,
    9,  9,  9,  9,  13, 12, 9,  9,  9,  9,  13, 12, 9,  9,  9,  9,
    13, 12, 9,  9,  9,  9,  13, 12, 11, 11, 11, 11, 7,  12, 10, 10,
    10, 10, 10, 14, 9,  9,  9,  9,  9,  13, 9,  9,  9,  9,  9,  13,
    9,  9,  9,  9,  9,  13, 9,  9,  9,  9,  9,  13, 9,  9,  9,  9,
    9,  13, 11, 11, 11, 11, 11, 15, 0,  0,  0,  0,  0,  0,  8,  8,
    8,  8,  8,  8,  7,  7,  7,  7,  7,  7,  15, 15, 15, 15, 15, 15,
};

// Tests
test "color conversion" {
    const testing = std.testing;

    // Test RGB color creation
    const red = RGBColor.init(255, 0, 0);
    try testing.expect(red.r == 255);
    try testing.expect(red.g == 0);
    try testing.expect(red.b == 0);

    // Test hex conversion
    const hex_red = red.toHex();
    try testing.expect(hex_red == 0xFF0000);

    // Test RGB from hex
    const from_hex = RGBColor.fromHex(0xFF0000);
    try testing.expect(from_hex.r == 255);
    try testing.expect(from_hex.g == 0);
    try testing.expect(from_hex.b == 0);

    // Test 256-color conversion
    const indexed_red = red.toIndexed();
    try testing.expect(indexed_red.index == 196); // Red in 256-color palette

    // Test basic color conversion
    const basic_red = red.toBasic();
    try testing.expect(basic_red == .bright_red);
}

test "hex color parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test parsing with #
    const hex1 = try HexColor.parseFromString("#FF0000");
    const rgb1 = hex1.toRgb();
    try testing.expect(rgb1.r == 255 and rgb1.g == 0 and rgb1.b == 0);

    // Test parsing without #
    const hex2 = try HexColor.parseFromString("00FF00");
    const rgb2 = hex2.toRgb();
    try testing.expect(rgb2.r == 0 and rgb2.g == 255 and rgb2.b == 0);

    // Test string output
    const hex_str = try hex1.toString(allocator);
    defer allocator.free(hex_str);
    try testing.expectEqualStrings("#ff0000", hex_str);
}

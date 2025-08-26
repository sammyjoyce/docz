const std = @import("std");

// RGBA color components (0-255)
pub const RGBA = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn toU32(self: RGBA) u32 {
        return (@as(u32, self.r) << 24) |
            (@as(u32, self.g) << 16) |
            (@as(u32, self.b) << 8) |
            @as(u32, self.a);
    }

    pub fn fromU32(value: u32) RGBA {
        return RGBA{
            .r = @truncate(value >> 24),
            .g = @truncate(value >> 16),
            .b = @truncate(value >> 8),
            .a = @truncate(value),
        };
    }

    pub fn toHex(self: RGBA) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }
};

// Basic 16-color ANSI colors (0-15)
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

    pub fn toRGBA(self: BasicColor) RGBA {
        return ansi_colors[@intFromEnum(self)];
    }

    pub fn toIndexedColor(self: BasicColor) IndexedColor {
        return @enumFromInt(@intFromEnum(self));
    }
};

// 256-color indexed color (0-255)
pub const IndexedColor = enum(u8) {
    _,

    pub fn toRGBA(self: IndexedColor) RGBA {
        return ansi_colors[@intFromEnum(self)];
    }

    pub fn toBasicColor(self: IndexedColor) ?BasicColor {
        const value = @intFromEnum(self);
        if (value <= 15) {
            return @enumFromInt(value);
        }
        return ansi256To16[value];
    }
};

// 24-bit RGB color
pub const RGBColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn toRGBA(self: RGBColor) RGBA {
        return RGBA{ .r = self.r, .g = self.g, .b = self.b };
    }

    pub fn toHex(self: RGBColor) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }

    pub fn fromHex(hex: u32) RGBColor {
        return RGBColor{
            .r = @truncate(hex >> 16),
            .g = @truncate(hex >> 8),
            .b = @truncate(hex),
        };
    }
};

// Unified color type that can represent any terminal color
pub const Color = union(enum) {
    basic: BasicColor,
    indexed: IndexedColor,
    rgb: RGBColor,

    pub fn toRGBA(self: Color) RGBA {
        return switch (self) {
            .basic => |c| c.toRGBA(),
            .indexed => |c| c.toRGBA(),
            .rgb => |c| c.toRGBA(),
        };
    }

    pub fn toIndexedColor(self: Color) IndexedColor {
        return switch (self) {
            .basic => |c| c.toIndexedColor(),
            .indexed => |c| c,
            .rgb => |c| convert256(c.toRGBA()),
        };
    }

    pub fn toBasicColor(self: Color) BasicColor {
        return switch (self) {
            .basic => |c| c,
            .indexed => |c| c.toBasicColor() orelse convert16(self.toRGBA()),
            .rgb => |c| convert16(c.toRGBA()),
        };
    }
};

// Distance function for color matching
fn distanceSq(r1: u8, g1: u8, b1: u8, r2: u8, g2: u8, b2: u8) u32 {
    const dr = @as(i16, r1) - @as(i16, r2);
    const dg = @as(i16, g1) - @as(i16, g2);
    const db = @as(i16, b1) - @as(i16, b2);
    return @as(u32, @intCast(dr * dr + dg * dg + db * db));
}

// Convert to 6-cube value for xterm 256-color palette
fn to6Cube(v: u8) u8 {
    if (v < 48) return 0;
    if (v < 115) return 1;
    return @min(5, (v - 35) / 40);
}

// Convert RGB color to 256-color indexed color using xterm palette
pub fn convert256(rgba: RGBA) IndexedColor {
    const r = rgba.r;
    const g = rgba.g;
    const b = rgba.b;

    // xterm 6x6x6 color cube levels
    const q2c = [6]u8{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };

    // Map RGB to 6x6x6 cube
    const qr = to6Cube(r);
    const cr = q2c[qr];
    const qg = to6Cube(g);
    const cg = q2c[qg];
    const qb = to6Cube(b);
    const cb = q2c[qb];

    // Calculate cube index
    const ci = (36 * qr) + (6 * qg) + qb;

    // Check if we hit the color exactly
    if (cr == r and cg == g and cb == b) {
        return @enumFromInt(16 + ci);
    }

    // Work out the closest grey (average of RGB)
    const grey_avg: u16 = (@as(u16, r) + @as(u16, g) + @as(u16, b)) / 3;
    const grey_idx: u8 = if (grey_avg > 238) 23 else @min(23, @as(u8, @intCast((grey_avg - 8) / 10)));
    const grey: u8 = 8 + (10 * grey_idx);

    // Return the closer match
    const color_dist = distanceSq(cr, cg, cb, r, g, b);
    const grey_dist = distanceSq(grey, grey, grey, r, g, b);

    if (color_dist <= grey_dist) {
        return @enumFromInt(16 + ci);
    } else {
        return @enumFromInt(232 + grey_idx);
    }
}

// Convert RGB color to 16-color basic color
pub fn convert16(rgba: RGBA) BasicColor {
    const c256 = convert256(rgba);
    return ansi256To16[@intFromEnum(c256)] orelse BasicColor.white;
}

// RGB values for ANSI colors (0-255)
// Use a simpler approach to generate the full 256-color palette
fn generateAnsiColors() [256]RGBA {
    var colors: [256]RGBA = undefined;

    // 16 basic colors (0-15)
    colors[0] = RGBA{ .r = 0x00, .g = 0x00, .b = 0x00 }; // black
    colors[1] = RGBA{ .r = 0x80, .g = 0x00, .b = 0x00 }; // red
    colors[2] = RGBA{ .r = 0x00, .g = 0x80, .b = 0x00 }; // green
    colors[3] = RGBA{ .r = 0x80, .g = 0x80, .b = 0x00 }; // yellow
    colors[4] = RGBA{ .r = 0x00, .g = 0x00, .b = 0x80 }; // blue
    colors[5] = RGBA{ .r = 0x80, .g = 0x00, .b = 0x80 }; // magenta
    colors[6] = RGBA{ .r = 0x00, .g = 0x80, .b = 0x80 }; // cyan
    colors[7] = RGBA{ .r = 0xc0, .g = 0xc0, .b = 0xc0 }; // white
    colors[8] = RGBA{ .r = 0x80, .g = 0x80, .b = 0x80 }; // bright_black
    colors[9] = RGBA{ .r = 0xff, .g = 0x00, .b = 0x00 }; // bright_red
    colors[10] = RGBA{ .r = 0x00, .g = 0xff, .b = 0x00 }; // bright_green
    colors[11] = RGBA{ .r = 0xff, .g = 0xff, .b = 0x00 }; // bright_yellow
    colors[12] = RGBA{ .r = 0x00, .g = 0x00, .b = 0xff }; // bright_blue
    colors[13] = RGBA{ .r = 0xff, .g = 0x00, .b = 0xff }; // bright_magenta
    colors[14] = RGBA{ .r = 0x00, .g = 0xff, .b = 0xff }; // bright_cyan
    colors[15] = RGBA{ .r = 0xff, .g = 0xff, .b = 0xff }; // bright_white

    // 216 color cube (16-231): 6x6x6 cube
    const cube_levels = [6]u8{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };
    for (0..6) |r| {
        for (0..6) |g| {
            for (0..6) |b| {
                const idx = 16 + (r * 36) + (g * 6) + b;
                colors[idx] = RGBA{
                    .r = cube_levels[r],
                    .g = cube_levels[g],
                    .b = cube_levels[b],
                };
            }
        }
    }

    // 24 grayscale colors (232-255)
    for (0..24) |i| {
        const level: u8 = @intCast(8 + (i * 10));
        colors[232 + i] = RGBA{ .r = level, .g = level, .b = level };
    }

    return colors;
}

const ansi_colors = generateAnsiColors();

// Mapping from 256-color palette to 16-color palette
const ansi256To16 = [256]?BasicColor{
    BasicColor.black,        BasicColor.red,            BasicColor.green,        BasicColor.yellow,
    BasicColor.blue,         BasicColor.magenta,        BasicColor.cyan,         BasicColor.white,
    BasicColor.bright_black, BasicColor.bright_red,     BasicColor.bright_green, BasicColor.bright_yellow,
    BasicColor.bright_blue,  BasicColor.bright_magenta, BasicColor.bright_cyan,  BasicColor.bright_white,
    // Colors 16-231 mapped to closest 16-color equivalent
    BasicColor.black,        BasicColor.blue,           BasicColor.blue,         BasicColor.blue,
    BasicColor.bright_blue,  BasicColor.bright_blue,    BasicColor.green,        BasicColor.cyan,
    BasicColor.blue,         BasicColor.blue,           BasicColor.bright_blue,  BasicColor.bright_blue,
    BasicColor.green,        BasicColor.green,          BasicColor.cyan,         BasicColor.blue,
    BasicColor.bright_blue,  BasicColor.bright_blue,    BasicColor.green,        BasicColor.green,
    BasicColor.green,        BasicColor.cyan,           BasicColor.bright_blue,  BasicColor.bright_blue,
    BasicColor.bright_green, BasicColor.bright_green,   BasicColor.bright_green, BasicColor.bright_green,
    BasicColor.bright_cyan,  BasicColor.bright_blue,    BasicColor.bright_green, BasicColor.bright_green,
    BasicColor.bright_green, BasicColor.bright_green,   BasicColor.bright_green, BasicColor.bright_cyan,
} ++ [_]?BasicColor{BasicColor.white} ** (256 - 36); // Fill rest with white

test "basic color conversion" {
    const red = BasicColor.red;
    const rgba = red.toRGBA();
    const idx = red.toIndexedColor();

    try std.testing.expect(rgba.r == 0x80);
    try std.testing.expect(rgba.g == 0x00);
    try std.testing.expect(rgba.b == 0x00);
    try std.testing.expect(@intFromEnum(idx) == 1);
}

test "RGB to 256 color conversion" {
    const rgb = RGBColor{ .r = 255, .g = 0, .b = 0 };
    const idx = convert256(rgb.toRGBA());

    // Should map to a red-ish color in the 256 palette
    try std.testing.expect(@intFromEnum(idx) >= 16);
}

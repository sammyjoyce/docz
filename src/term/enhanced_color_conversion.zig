const std = @import("std");

/// Color represents a color that can be used in a terminal.
/// ANSI (including ANSI256) and 24-bit "true colors" fall under this category.
pub const Color = union(enum) {
    basic: BasicColor,
    indexed: IndexedColor,
    rgb: RGBColor,

    pub fn rgba(self: Color) RGBA {
        return switch (self) {
            .basic => |c| c.rgba(),
            .indexed => |c| c.rgba(),
            .rgb => |c| c.rgba(),
        };
    }
};

/// BasicColor is an ANSI 3-bit or 4-bit color with a value from 0 to 15.
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

    pub fn rgba(self: BasicColor) RGBA {
        const ansi = @intFromEnum(self);
        if (ansi > 15) return RGBA{ .r = 0, .g = 0, .b = 0, .a = 255 };
        return ansi_hex[ansi];
    }
};

/// IndexedColor is an ANSI 256 (8-bit) color with a value from 0 to 255.
pub const IndexedColor = struct {
    value: u8,

    pub fn rgba(self: IndexedColor) RGBA {
        return ansi_hex[self.value];
    }
};

/// RGBColor is a 24-bit color that can be used in the terminal.
pub const RGBColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn rgba(self: RGBColor) RGBA {
        return RGBA{
            .r = self.r,
            .g = self.g,
            .b = self.b,
            .a = 255,
        };
    }

    pub fn fromHex(hex: u32) RGBColor {
        const r, const g, const b = hexToRGB(hex);
        return RGBColor{
            .r = @intCast(r),
            .g = @intCast(g),
            .b = @intCast(b),
        };
    }
};

/// RGBA represents a color with red, green, blue, and alpha components.
pub const RGBA = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

/// Convert a hex value to RGB components.
fn hexToRGB(hex: u32) struct { u32, u32, u32 } {
    return .{ hex >> 16 & 0xff, hex >> 8 & 0xff, hex & 0xff };
}

fn to6Cube(v: f32) u32 {
    if (v < 48) return 0;
    if (v < 115) return 1;
    return @intFromFloat((v - 35) / 40);
}

/// Convert a 24-bit color to xterm(1) 256 color palette.
/// This implementation uses the sophisticated algorithm from charmbracelet/x
/// that maps RGB colors to the closest in the 6x6x6 cube and 24 greys.
pub fn convert256(color: Color) IndexedColor {
    const rgba_color = color.rgba();
    const r = @as(f32, @floatFromInt(rgba_color.r));
    const g = @as(f32, @floatFromInt(rgba_color.g));
    const b = @as(f32, @floatFromInt(rgba_color.b));

    const q2c = [6]u32{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };

    // Map RGB to 6x6x6 cube.
    const qr = to6Cube(r);
    const cr = q2c[qr];
    const qg = to6Cube(g);
    const cg = q2c[qg];
    const qb = to6Cube(b);
    const cb = q2c[qb];

    // If we have hit the color exactly, return early.
    const ci = (36 * qr) + (6 * qg) + qb;
    if (cr == @as(u32, @intFromFloat(r)) and cg == @as(u32, @intFromFloat(g)) and cb == @as(u32, @intFromFloat(b))) {
        return IndexedColor{ .value = @intCast(16 + ci) };
    }

    // Work out the closest grey (average of RGB).
    const grey_avg = @as(u32, @intFromFloat((r + g + b) / 3));
    var grey_idx: u32 = 0;
    if (grey_avg > 238) {
        grey_idx = 23;
    } else {
        grey_idx = (grey_avg - 3) / 10;
    }
    const grey = 8 + (10 * grey_idx);

    // Use perceptual color distance (simplified HSLuv approximation)
    const color_dist = colorDistance(r, g, b, @floatFromInt(cr), @floatFromInt(cg), @floatFromInt(cb));
    const grey_dist = colorDistance(r, g, b, @floatFromInt(grey), @floatFromInt(grey), @floatFromInt(grey));

    if (color_dist <= grey_dist) {
        return IndexedColor{ .value = @intCast(16 + ci) };
    }
    return IndexedColor{ .value = @intCast(232 + grey_idx) };
}

/// Convert a color to a 16-color ANSI palette.
pub fn convert16(color: Color) BasicColor {
    switch (color) {
        .basic => |c| return c,
        .indexed => |c| return ansi256To16[c.value],
        .rgb => |c| {
            const c256 = convert256(Color{ .rgb = c });
            return ansi256To16[c256.value];
        },
    }
}

/// Simplified perceptual color distance calculation.
fn colorDistance(r1: f32, g1: f32, b1: f32, r2: f32, g2: f32, b2: f32) f32 {
    // Weighted Euclidean distance that approximates perceptual color difference
    const dr = r1 - r2;
    const dg = g1 - g2;
    const db = b1 - b2;

    // Use perceptual weights (roughly based on human eye sensitivity)
    const wr: f32 = 0.3;
    const wg: f32 = 0.59;
    const wb: f32 = 0.11;

    return @sqrt(wr * dr * dr + wg * dg * dg + wb * db * db);
}

/// RGB values of ANSI colors (0-255).
const ansi_hex = [256]RGBA{
    .{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0xff }, //   0: "#000000"
    .{ .r = 0x80, .g = 0x00, .b = 0x00, .a = 0xff }, //   1: "#800000"
    .{ .r = 0x00, .g = 0x80, .b = 0x00, .a = 0xff }, //   2: "#008000"
    .{ .r = 0x80, .g = 0x80, .b = 0x00, .a = 0xff }, //   3: "#808000"
    .{ .r = 0x00, .g = 0x00, .b = 0x80, .a = 0xff }, //   4: "#000080"
    .{ .r = 0x80, .g = 0x00, .b = 0x80, .a = 0xff }, //   5: "#800080"
    .{ .r = 0x00, .g = 0x80, .b = 0x80, .a = 0xff }, //   6: "#008080"
    .{ .r = 0xc0, .g = 0xc0, .b = 0xc0, .a = 0xff }, //   7: "#c0c0c0"
    .{ .r = 0x80, .g = 0x80, .b = 0x80, .a = 0xff }, //   8: "#808080"
    .{ .r = 0xff, .g = 0x00, .b = 0x00, .a = 0xff }, //   9: "#ff0000"
    .{ .r = 0x00, .g = 0xff, .b = 0x00, .a = 0xff }, //  10: "#00ff00"
    .{ .r = 0xff, .g = 0xff, .b = 0x00, .a = 0xff }, //  11: "#ffff00"
    .{ .r = 0x00, .g = 0x00, .b = 0xff, .a = 0xff }, //  12: "#0000ff"
    .{ .r = 0xff, .g = 0x00, .b = 0xff, .a = 0xff }, //  13: "#ff00ff"
    .{ .r = 0x00, .g = 0xff, .b = 0xff, .a = 0xff }, //  14: "#00ffff"
    .{ .r = 0xff, .g = 0xff, .b = 0xff, .a = 0xff }, //  15: "#ffffff"
    .{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0xff }, //  16: "#000000"
    .{ .r = 0x00, .g = 0x00, .b = 0x5f, .a = 0xff }, //  17: "#00005f"
    .{ .r = 0x00, .g = 0x00, .b = 0x87, .a = 0xff }, //  18: "#000087"
    .{ .r = 0x00, .g = 0x00, .b = 0xaf, .a = 0xff }, //  19: "#0000af"
    .{ .r = 0x00, .g = 0x00, .b = 0xd7, .a = 0xff }, //  20: "#0000d7"
    .{ .r = 0x00, .g = 0x00, .b = 0xff, .a = 0xff }, //  21: "#0000ff"
    .{ .r = 0x00, .g = 0x5f, .b = 0x00, .a = 0xff }, //  22: "#005f00"
    .{ .r = 0x00, .g = 0x5f, .b = 0x5f, .a = 0xff }, //  23: "#005f5f"
    .{ .r = 0x00, .g = 0x5f, .b = 0x87, .a = 0xff }, //  24: "#005f87"
    .{ .r = 0x00, .g = 0x5f, .b = 0xaf, .a = 0xff }, //  25: "#005faf"
    .{ .r = 0x00, .g = 0x5f, .b = 0xd7, .a = 0xff }, //  26: "#005fd7"
    .{ .r = 0x00, .g = 0x5f, .b = 0xff, .a = 0xff }, //  27: "#005fff"
    .{ .r = 0x00, .g = 0x87, .b = 0x00, .a = 0xff }, //  28: "#008700"
    .{ .r = 0x00, .g = 0x87, .b = 0x5f, .a = 0xff }, //  29: "#00875f"
    .{ .r = 0x00, .g = 0x87, .b = 0x87, .a = 0xff }, //  30: "#008787"
    .{ .r = 0x00, .g = 0x87, .b = 0xaf, .a = 0xff }, //  31: "#0087af"
    .{ .r = 0x00, .g = 0x87, .b = 0xd7, .a = 0xff }, //  32: "#0087d7"
    .{ .r = 0x00, .g = 0x87, .b = 0xff, .a = 0xff }, //  33: "#0087ff"
    .{ .r = 0x00, .g = 0xaf, .b = 0x00, .a = 0xff }, //  34: "#00af00"
    .{ .r = 0x00, .g = 0xaf, .b = 0x5f, .a = 0xff }, //  35: "#00af5f"
    .{ .r = 0x00, .g = 0xaf, .b = 0x87, .a = 0xff }, //  36: "#00af87"
    .{ .r = 0x00, .g = 0xaf, .b = 0xaf, .a = 0xff }, //  37: "#00afaf"
    .{ .r = 0x00, .g = 0xaf, .b = 0xd7, .a = 0xff }, //  38: "#00afd7"
    .{ .r = 0x00, .g = 0xaf, .b = 0xff, .a = 0xff }, //  39: "#00afff"
    .{ .r = 0x00, .g = 0xd7, .b = 0x00, .a = 0xff }, //  40: "#00d700"
    .{ .r = 0x00, .g = 0xd7, .b = 0x5f, .a = 0xff }, //  41: "#00d75f"
    .{ .r = 0x00, .g = 0xd7, .b = 0x87, .a = 0xff }, //  42: "#00d787"
    .{ .r = 0x00, .g = 0xd7, .b = 0xaf, .a = 0xff }, //  43: "#00d7af"
    .{ .r = 0x00, .g = 0xd7, .b = 0xd7, .a = 0xff }, //  44: "#00d7d7"
    .{ .r = 0x00, .g = 0xd7, .b = 0xff, .a = 0xff }, //  45: "#00d7ff"
    .{ .r = 0x00, .g = 0xff, .b = 0x00, .a = 0xff }, //  46: "#00ff00"
    .{ .r = 0x00, .g = 0xff, .b = 0x5f, .a = 0xff }, //  47: "#00ff5f"
    .{ .r = 0x00, .g = 0xff, .b = 0x87, .a = 0xff }, //  48: "#00ff87"
    .{ .r = 0x00, .g = 0xff, .b = 0xaf, .a = 0xff }, //  49: "#00ffaf"
    .{ .r = 0x00, .g = 0xff, .b = 0xd7, .a = 0xff }, //  50: "#00ffd7"
    .{ .r = 0x00, .g = 0xff, .b = 0xff, .a = 0xff }, //  51: "#00ffff"
    .{ .r = 0x5f, .g = 0x00, .b = 0x00, .a = 0xff }, //  52: "#5f0000"
    .{ .r = 0x5f, .g = 0x00, .b = 0x5f, .a = 0xff }, //  53: "#5f005f"
    .{ .r = 0x5f, .g = 0x00, .b = 0x87, .a = 0xff }, //  54: "#5f0087"
    .{ .r = 0x5f, .g = 0x00, .b = 0xaf, .a = 0xff }, //  55: "#5f00af"
    .{ .r = 0x5f, .g = 0x00, .b = 0xd7, .a = 0xff }, //  56: "#5f00d7"
    .{ .r = 0x5f, .g = 0x00, .b = 0xff, .a = 0xff }, //  57: "#5f00ff"
    .{ .r = 0x5f, .g = 0x5f, .b = 0x00, .a = 0xff }, //  58: "#5f5f00"
    .{ .r = 0x5f, .g = 0x5f, .b = 0x5f, .a = 0xff }, //  59: "#5f5f5f"
    .{ .r = 0x5f, .g = 0x5f, .b = 0x87, .a = 0xff }, //  60: "#5f5f87"
    .{ .r = 0x5f, .g = 0x5f, .b = 0xaf, .a = 0xff }, //  61: "#5f5faf"
    .{ .r = 0x5f, .g = 0x5f, .b = 0xd7, .a = 0xff }, //  62: "#5f5fd7"
    .{ .r = 0x5f, .g = 0x5f, .b = 0xff, .a = 0xff }, //  63: "#5f5fff"
    .{ .r = 0x5f, .g = 0x87, .b = 0x00, .a = 0xff }, //  64: "#5f8700"
    .{ .r = 0x5f, .g = 0x87, .b = 0x5f, .a = 0xff }, //  65: "#5f875f"
    .{ .r = 0x5f, .g = 0x87, .b = 0x87, .a = 0xff }, //  66: "#5f8787"
    .{ .r = 0x5f, .g = 0x87, .b = 0xaf, .a = 0xff }, //  67: "#5f87af"
    .{ .r = 0x5f, .g = 0x87, .b = 0xd7, .a = 0xff }, //  68: "#5f87d7"
    .{ .r = 0x5f, .g = 0x87, .b = 0xff, .a = 0xff }, //  69: "#5f87ff"
    .{ .r = 0x5f, .g = 0xaf, .b = 0x00, .a = 0xff }, //  70: "#5faf00"
    .{ .r = 0x5f, .g = 0xaf, .b = 0x5f, .a = 0xff }, //  71: "#5faf5f"
    .{ .r = 0x5f, .g = 0xaf, .b = 0x87, .a = 0xff }, //  72: "#5faf87"
    .{ .r = 0x5f, .g = 0xaf, .b = 0xaf, .a = 0xff }, //  73: "#5fafaf"
    .{ .r = 0x5f, .g = 0xaf, .b = 0xd7, .a = 0xff }, //  74: "#5fafd7"
    .{ .r = 0x5f, .g = 0xaf, .b = 0xff, .a = 0xff }, //  75: "#5fafff"
    .{ .r = 0x5f, .g = 0xd7, .b = 0x00, .a = 0xff }, //  76: "#5fd700"
    .{ .r = 0x5f, .g = 0xd7, .b = 0x5f, .a = 0xff }, //  77: "#5fd75f"
    .{ .r = 0x5f, .g = 0xd7, .b = 0x87, .a = 0xff }, //  78: "#5fd787"
    .{ .r = 0x5f, .g = 0xd7, .b = 0xaf, .a = 0xff }, //  79: "#5fd7af"
    .{ .r = 0x5f, .g = 0xd7, .b = 0xd7, .a = 0xff }, //  80: "#5fd7d7"
    .{ .r = 0x5f, .g = 0xd7, .b = 0xff, .a = 0xff }, //  81: "#5fd7ff"
    .{ .r = 0x5f, .g = 0xff, .b = 0x00, .a = 0xff }, //  82: "#5fff00"
    .{ .r = 0x5f, .g = 0xff, .b = 0x5f, .a = 0xff }, //  83: "#5fff5f"
    .{ .r = 0x5f, .g = 0xff, .b = 0x87, .a = 0xff }, //  84: "#5fff87"
    .{ .r = 0x5f, .g = 0xff, .b = 0xaf, .a = 0xff }, //  85: "#5fffaf"
    .{ .r = 0x5f, .g = 0xff, .b = 0xd7, .a = 0xff }, //  86: "#5fffd7"
    .{ .r = 0x5f, .g = 0xff, .b = 0xff, .a = 0xff }, //  87: "#5fffff"
    .{ .r = 0x87, .g = 0x00, .b = 0x00, .a = 0xff }, //  88: "#870000"
    .{ .r = 0x87, .g = 0x00, .b = 0x5f, .a = 0xff }, //  89: "#87005f"
    .{ .r = 0x87, .g = 0x00, .b = 0x87, .a = 0xff }, //  90: "#870087"
    .{ .r = 0x87, .g = 0x00, .b = 0xaf, .a = 0xff }, //  91: "#8700af"
    .{ .r = 0x87, .g = 0x00, .b = 0xd7, .a = 0xff }, //  92: "#8700d7"
    .{ .r = 0x87, .g = 0x00, .b = 0xff, .a = 0xff }, //  93: "#8700ff"
    .{ .r = 0x87, .g = 0x5f, .b = 0x00, .a = 0xff }, //  94: "#875f00"
    .{ .r = 0x87, .g = 0x5f, .b = 0x5f, .a = 0xff }, //  95: "#875f5f"
    .{ .r = 0x87, .g = 0x5f, .b = 0x87, .a = 0xff }, //  96: "#875f87"
    .{ .r = 0x87, .g = 0x5f, .b = 0xaf, .a = 0xff }, //  97: "#875faf"
    .{ .r = 0x87, .g = 0x5f, .b = 0xd7, .a = 0xff }, //  98: "#875fd7"
    .{ .r = 0x87, .g = 0x5f, .b = 0xff, .a = 0xff }, //  99: "#875fff"
    .{ .r = 0x87, .g = 0x87, .b = 0x00, .a = 0xff }, // 100: "#878700"
    .{ .r = 0x87, .g = 0x87, .b = 0x5f, .a = 0xff }, // 101: "#87875f"
    .{ .r = 0x87, .g = 0x87, .b = 0x87, .a = 0xff }, // 102: "#878787"
    .{ .r = 0x87, .g = 0x87, .b = 0xaf, .a = 0xff }, // 103: "#8787af"
    .{ .r = 0x87, .g = 0x87, .b = 0xd7, .a = 0xff }, // 104: "#8787d7"
    .{ .r = 0x87, .g = 0x87, .b = 0xff, .a = 0xff }, // 105: "#8787ff"
    .{ .r = 0x87, .g = 0xaf, .b = 0x00, .a = 0xff }, // 106: "#87af00"
    .{ .r = 0x87, .g = 0xaf, .b = 0x5f, .a = 0xff }, // 107: "#87af5f"
    .{ .r = 0x87, .g = 0xaf, .b = 0x87, .a = 0xff }, // 108: "#87af87"
    .{ .r = 0x87, .g = 0xaf, .b = 0xaf, .a = 0xff }, // 109: "#87afaf"
    .{ .r = 0x87, .g = 0xaf, .b = 0xd7, .a = 0xff }, // 110: "#87afd7"
    .{ .r = 0x87, .g = 0xaf, .b = 0xff, .a = 0xff }, // 111: "#87afff"
    .{ .r = 0x87, .g = 0xd7, .b = 0x00, .a = 0xff }, // 112: "#87d700"
    .{ .r = 0x87, .g = 0xd7, .b = 0x5f, .a = 0xff }, // 113: "#87d75f"
    .{ .r = 0x87, .g = 0xd7, .b = 0x87, .a = 0xff }, // 114: "#87d787"
    .{ .r = 0x87, .g = 0xd7, .b = 0xaf, .a = 0xff }, // 115: "#87d7af"
    .{ .r = 0x87, .g = 0xd7, .b = 0xd7, .a = 0xff }, // 116: "#87d7d7"
    .{ .r = 0x87, .g = 0xd7, .b = 0xff, .a = 0xff }, // 117: "#87d7ff"
    .{ .r = 0x87, .g = 0xff, .b = 0x00, .a = 0xff }, // 118: "#87ff00"
    .{ .r = 0x87, .g = 0xff, .b = 0x5f, .a = 0xff }, // 119: "#87ff5f"
    .{ .r = 0x87, .g = 0xff, .b = 0x87, .a = 0xff }, // 120: "#87ff87"
    .{ .r = 0x87, .g = 0xff, .b = 0xaf, .a = 0xff }, // 121: "#87ffaf"
    .{ .r = 0x87, .g = 0xff, .b = 0xd7, .a = 0xff }, // 122: "#87ffd7"
    .{ .r = 0x87, .g = 0xff, .b = 0xff, .a = 0xff }, // 123: "#87ffff"
    .{ .r = 0xaf, .g = 0x00, .b = 0x00, .a = 0xff }, // 124: "#af0000"
    .{ .r = 0xaf, .g = 0x00, .b = 0x5f, .a = 0xff }, // 125: "#af005f"
    .{ .r = 0xaf, .g = 0x00, .b = 0x87, .a = 0xff }, // 126: "#af0087"
    .{ .r = 0xaf, .g = 0x00, .b = 0xaf, .a = 0xff }, // 127: "#af00af"
    .{ .r = 0xaf, .g = 0x00, .b = 0xd7, .a = 0xff }, // 128: "#af00d7"
    .{ .r = 0xaf, .g = 0x00, .b = 0xff, .a = 0xff }, // 129: "#af00ff"
    .{ .r = 0xaf, .g = 0x5f, .b = 0x00, .a = 0xff }, // 130: "#af5f00"
    .{ .r = 0xaf, .g = 0x5f, .b = 0x5f, .a = 0xff }, // 131: "#af5f5f"
    .{ .r = 0xaf, .g = 0x5f, .b = 0x87, .a = 0xff }, // 132: "#af5f87"
    .{ .r = 0xaf, .g = 0x5f, .b = 0xaf, .a = 0xff }, // 133: "#af5faf"
    .{ .r = 0xaf, .g = 0x5f, .b = 0xd7, .a = 0xff }, // 134: "#af5fd7"
    .{ .r = 0xaf, .g = 0x5f, .b = 0xff, .a = 0xff }, // 135: "#af5fff"
    .{ .r = 0xaf, .g = 0x87, .b = 0x00, .a = 0xff }, // 136: "#af8700"
    .{ .r = 0xaf, .g = 0x87, .b = 0x5f, .a = 0xff }, // 137: "#af875f"
    .{ .r = 0xaf, .g = 0x87, .b = 0x87, .a = 0xff }, // 138: "#af8787"
    .{ .r = 0xaf, .g = 0x87, .b = 0xaf, .a = 0xff }, // 139: "#af87af"
    .{ .r = 0xaf, .g = 0x87, .b = 0xd7, .a = 0xff }, // 140: "#af87d7"
    .{ .r = 0xaf, .g = 0x87, .b = 0xff, .a = 0xff }, // 141: "#af87ff"
    .{ .r = 0xaf, .g = 0xaf, .b = 0x00, .a = 0xff }, // 142: "#afaf00"
    .{ .r = 0xaf, .g = 0xaf, .b = 0x5f, .a = 0xff }, // 143: "#afaf5f"
    .{ .r = 0xaf, .g = 0xaf, .b = 0x87, .a = 0xff }, // 144: "#afaf87"
    .{ .r = 0xaf, .g = 0xaf, .b = 0xaf, .a = 0xff }, // 145: "#afafaf"
    .{ .r = 0xaf, .g = 0xaf, .b = 0xd7, .a = 0xff }, // 146: "#afafd7"
    .{ .r = 0xaf, .g = 0xaf, .b = 0xff, .a = 0xff }, // 147: "#afafff"
    .{ .r = 0xaf, .g = 0xd7, .b = 0x00, .a = 0xff }, // 148: "#afd700"
    .{ .r = 0xaf, .g = 0xd7, .b = 0x5f, .a = 0xff }, // 149: "#afd75f"
    .{ .r = 0xaf, .g = 0xd7, .b = 0x87, .a = 0xff }, // 150: "#afd787"
    .{ .r = 0xaf, .g = 0xd7, .b = 0xaf, .a = 0xff }, // 151: "#afd7af"
    .{ .r = 0xaf, .g = 0xd7, .b = 0xd7, .a = 0xff }, // 152: "#afd7d7"
    .{ .r = 0xaf, .g = 0xd7, .b = 0xff, .a = 0xff }, // 153: "#afd7ff"
    .{ .r = 0xaf, .g = 0xff, .b = 0x00, .a = 0xff }, // 154: "#afff00"
    .{ .r = 0xaf, .g = 0xff, .b = 0x5f, .a = 0xff }, // 155: "#afff5f"
    .{ .r = 0xaf, .g = 0xff, .b = 0x87, .a = 0xff }, // 156: "#afff87"
    .{ .r = 0xaf, .g = 0xff, .b = 0xaf, .a = 0xff }, // 157: "#afffaf"
    .{ .r = 0xaf, .g = 0xff, .b = 0xd7, .a = 0xff }, // 158: "#afffd7"
    .{ .r = 0xaf, .g = 0xff, .b = 0xff, .a = 0xff }, // 159: "#afffff"
    .{ .r = 0xd7, .g = 0x00, .b = 0x00, .a = 0xff }, // 160: "#d70000"
    .{ .r = 0xd7, .g = 0x00, .b = 0x5f, .a = 0xff }, // 161: "#d7005f"
    .{ .r = 0xd7, .g = 0x00, .b = 0x87, .a = 0xff }, // 162: "#d70087"
    .{ .r = 0xd7, .g = 0x00, .b = 0xaf, .a = 0xff }, // 163: "#d700af"
    .{ .r = 0xd7, .g = 0x00, .b = 0xd7, .a = 0xff }, // 164: "#d700d7"
    .{ .r = 0xd7, .g = 0x00, .b = 0xff, .a = 0xff }, // 165: "#d700ff"
    .{ .r = 0xd7, .g = 0x5f, .b = 0x00, .a = 0xff }, // 166: "#d75f00"
    .{ .r = 0xd7, .g = 0x5f, .b = 0x5f, .a = 0xff }, // 167: "#d75f5f"
    .{ .r = 0xd7, .g = 0x5f, .b = 0x87, .a = 0xff }, // 168: "#d75f87"
    .{ .r = 0xd7, .g = 0x5f, .b = 0xaf, .a = 0xff }, // 169: "#d75faf"
    .{ .r = 0xd7, .g = 0x5f, .b = 0xd7, .a = 0xff }, // 170: "#d75fd7"
    .{ .r = 0xd7, .g = 0x5f, .b = 0xff, .a = 0xff }, // 171: "#d75fff"
    .{ .r = 0xd7, .g = 0x87, .b = 0x00, .a = 0xff }, // 172: "#d78700"
    .{ .r = 0xd7, .g = 0x87, .b = 0x5f, .a = 0xff }, // 173: "#d7875f"
    .{ .r = 0xd7, .g = 0x87, .b = 0x87, .a = 0xff }, // 174: "#d78787"
    .{ .r = 0xd7, .g = 0x87, .b = 0xaf, .a = 0xff }, // 175: "#d787af"
    .{ .r = 0xd7, .g = 0x87, .b = 0xd7, .a = 0xff }, // 176: "#d787d7"
    .{ .r = 0xd7, .g = 0x87, .b = 0xff, .a = 0xff }, // 177: "#d787ff"
    .{ .r = 0xd7, .g = 0xaf, .b = 0x00, .a = 0xff }, // 178: "#d7af00"
    .{ .r = 0xd7, .g = 0xaf, .b = 0x5f, .a = 0xff }, // 179: "#d7af5f"
    .{ .r = 0xd7, .g = 0xaf, .b = 0x87, .a = 0xff }, // 180: "#d7af87"
    .{ .r = 0xd7, .g = 0xaf, .b = 0xaf, .a = 0xff }, // 181: "#d7afaf"
    .{ .r = 0xd7, .g = 0xaf, .b = 0xd7, .a = 0xff }, // 182: "#d7afd7"
    .{ .r = 0xd7, .g = 0xaf, .b = 0xff, .a = 0xff }, // 183: "#d7afff"
    .{ .r = 0xd7, .g = 0xd7, .b = 0x00, .a = 0xff }, // 184: "#d7d700"
    .{ .r = 0xd7, .g = 0xd7, .b = 0x5f, .a = 0xff }, // 185: "#d7d75f"
    .{ .r = 0xd7, .g = 0xd7, .b = 0x87, .a = 0xff }, // 186: "#d7d787"
    .{ .r = 0xd7, .g = 0xd7, .b = 0xaf, .a = 0xff }, // 187: "#d7d7af"
    .{ .r = 0xd7, .g = 0xd7, .b = 0xd7, .a = 0xff }, // 188: "#d7d7d7"
    .{ .r = 0xd7, .g = 0xd7, .b = 0xff, .a = 0xff }, // 189: "#d7d7ff"
    .{ .r = 0xd7, .g = 0xff, .b = 0x00, .a = 0xff }, // 190: "#d7ff00"
    .{ .r = 0xd7, .g = 0xff, .b = 0x5f, .a = 0xff }, // 191: "#d7ff5f"
    .{ .r = 0xd7, .g = 0xff, .b = 0x87, .a = 0xff }, // 192: "#d7ff87"
    .{ .r = 0xd7, .g = 0xff, .b = 0xaf, .a = 0xff }, // 193: "#d7ffaf"
    .{ .r = 0xd7, .g = 0xff, .b = 0xd7, .a = 0xff }, // 194: "#d7ffd7"
    .{ .r = 0xd7, .g = 0xff, .b = 0xff, .a = 0xff }, // 195: "#d7ffff"
    .{ .r = 0xff, .g = 0x00, .b = 0x00, .a = 0xff }, // 196: "#ff0000"
    .{ .r = 0xff, .g = 0x00, .b = 0x5f, .a = 0xff }, // 197: "#ff005f"
    .{ .r = 0xff, .g = 0x00, .b = 0x87, .a = 0xff }, // 198: "#ff0087"
    .{ .r = 0xff, .g = 0x00, .b = 0xaf, .a = 0xff }, // 199: "#ff00af"
    .{ .r = 0xff, .g = 0x00, .b = 0xd7, .a = 0xff }, // 200: "#ff00d7"
    .{ .r = 0xff, .g = 0x00, .b = 0xff, .a = 0xff }, // 201: "#ff00ff"
    .{ .r = 0xff, .g = 0x5f, .b = 0x00, .a = 0xff }, // 202: "#ff5f00"
    .{ .r = 0xff, .g = 0x5f, .b = 0x5f, .a = 0xff }, // 203: "#ff5f5f"
    .{ .r = 0xff, .g = 0x5f, .b = 0x87, .a = 0xff }, // 204: "#ff5f87"
    .{ .r = 0xff, .g = 0x5f, .b = 0xaf, .a = 0xff }, // 205: "#ff5faf"
    .{ .r = 0xff, .g = 0x5f, .b = 0xd7, .a = 0xff }, // 206: "#ff5fd7"
    .{ .r = 0xff, .g = 0x5f, .b = 0xff, .a = 0xff }, // 207: "#ff5fff"
    .{ .r = 0xff, .g = 0x87, .b = 0x00, .a = 0xff }, // 208: "#ff8700"
    .{ .r = 0xff, .g = 0x87, .b = 0x5f, .a = 0xff }, // 209: "#ff875f"
    .{ .r = 0xff, .g = 0x87, .b = 0x87, .a = 0xff }, // 210: "#ff8787"
    .{ .r = 0xff, .g = 0x87, .b = 0xaf, .a = 0xff }, // 211: "#ff87af"
    .{ .r = 0xff, .g = 0x87, .b = 0xd7, .a = 0xff }, // 212: "#ff87d7"
    .{ .r = 0xff, .g = 0x87, .b = 0xff, .a = 0xff }, // 213: "#ff87ff"
    .{ .r = 0xff, .g = 0xaf, .b = 0x00, .a = 0xff }, // 214: "#ffaf00"
    .{ .r = 0xff, .g = 0xaf, .b = 0x5f, .a = 0xff }, // 215: "#ffaf5f"
    .{ .r = 0xff, .g = 0xaf, .b = 0x87, .a = 0xff }, // 216: "#ffaf87"
    .{ .r = 0xff, .g = 0xaf, .b = 0xaf, .a = 0xff }, // 217: "#ffafaf"
    .{ .r = 0xff, .g = 0xaf, .b = 0xd7, .a = 0xff }, // 218: "#ffafd7"
    .{ .r = 0xff, .g = 0xaf, .b = 0xff, .a = 0xff }, // 219: "#ffafff"
    .{ .r = 0xff, .g = 0xd7, .b = 0x00, .a = 0xff }, // 220: "#ffd700"
    .{ .r = 0xff, .g = 0xd7, .b = 0x5f, .a = 0xff }, // 221: "#ffd75f"
    .{ .r = 0xff, .g = 0xd7, .b = 0x87, .a = 0xff }, // 222: "#ffd787"
    .{ .r = 0xff, .g = 0xd7, .b = 0xaf, .a = 0xff }, // 223: "#ffd7af"
    .{ .r = 0xff, .g = 0xd7, .b = 0xd7, .a = 0xff }, // 224: "#ffd7d7"
    .{ .r = 0xff, .g = 0xd7, .b = 0xff, .a = 0xff }, // 225: "#ffd7ff"
    .{ .r = 0xff, .g = 0xff, .b = 0x00, .a = 0xff }, // 226: "#ffff00"
    .{ .r = 0xff, .g = 0xff, .b = 0x5f, .a = 0xff }, // 227: "#ffff5f"
    .{ .r = 0xff, .g = 0xff, .b = 0x87, .a = 0xff }, // 228: "#ffff87"
    .{ .r = 0xff, .g = 0xff, .b = 0xaf, .a = 0xff }, // 229: "#ffffaf"
    .{ .r = 0xff, .g = 0xff, .b = 0xd7, .a = 0xff }, // 230: "#ffffd7"
    .{ .r = 0xff, .g = 0xff, .b = 0xff, .a = 0xff }, // 231: "#ffffff"
    .{ .r = 0x08, .g = 0x08, .b = 0x08, .a = 0xff }, // 232: "#080808"
    .{ .r = 0x12, .g = 0x12, .b = 0x12, .a = 0xff }, // 233: "#121212"
    .{ .r = 0x1c, .g = 0x1c, .b = 0x1c, .a = 0xff }, // 234: "#1c1c1c"
    .{ .r = 0x26, .g = 0x26, .b = 0x26, .a = 0xff }, // 235: "#262626"
    .{ .r = 0x30, .g = 0x30, .b = 0x30, .a = 0xff }, // 236: "#303030"
    .{ .r = 0x3a, .g = 0x3a, .b = 0x3a, .a = 0xff }, // 237: "#3a3a3a"
    .{ .r = 0x44, .g = 0x44, .b = 0x44, .a = 0xff }, // 238: "#444444"
    .{ .r = 0x4e, .g = 0x4e, .b = 0x4e, .a = 0xff }, // 239: "#4e4e4e"
    .{ .r = 0x58, .g = 0x58, .b = 0x58, .a = 0xff }, // 240: "#585858"
    .{ .r = 0x62, .g = 0x62, .b = 0x62, .a = 0xff }, // 241: "#626262"
    .{ .r = 0x6c, .g = 0x6c, .b = 0x6c, .a = 0xff }, // 242: "#6c6c6c"
    .{ .r = 0x76, .g = 0x76, .b = 0x76, .a = 0xff }, // 243: "#767676"
    .{ .r = 0x80, .g = 0x80, .b = 0x80, .a = 0xff }, // 244: "#808080"
    .{ .r = 0x8a, .g = 0x8a, .b = 0x8a, .a = 0xff }, // 245: "#8a8a8a"
    .{ .r = 0x94, .g = 0x94, .b = 0x94, .a = 0xff }, // 246: "#949494"
    .{ .r = 0x9e, .g = 0x9e, .b = 0x9e, .a = 0xff }, // 247: "#9e9e9e"
    .{ .r = 0xa8, .g = 0xa8, .b = 0xa8, .a = 0xff }, // 248: "#a8a8a8"
    .{ .r = 0xb2, .g = 0xb2, .b = 0xb2, .a = 0xff }, // 249: "#b2b2b2"
    .{ .r = 0xbc, .g = 0xbc, .b = 0xbc, .a = 0xff }, // 250: "#bcbcbc"
    .{ .r = 0xc6, .g = 0xc6, .b = 0xc6, .a = 0xff }, // 251: "#c6c6c6"
    .{ .r = 0xd0, .g = 0xd0, .b = 0xd0, .a = 0xff }, // 252: "#d0d0d0"
    .{ .r = 0xda, .g = 0xda, .b = 0xda, .a = 0xff }, // 253: "#dadada"
    .{ .r = 0xe4, .g = 0xe4, .b = 0xe4, .a = 0xff }, // 254: "#e4e4e4"
    .{ .r = 0xee, .g = 0xee, .b = 0xee, .a = 0xff }, // 255: "#eeeeee"
};

/// Mapping from 256-color ANSI palette to 16-color ANSI palette.
const ansi256To16 = [256]BasicColor{
    // Colors 0-15: Direct mapping to 16-color palette
    .black,        .red,        .green,        .yellow,        .blue,        .magenta,        .cyan,        .white,
    .bright_black, .bright_red, .bright_green, .bright_yellow, .bright_blue, .bright_magenta, .bright_cyan,
    .bright_white,
    // Colors 16-231: 6x6x6 color cube mapped to nearest 16-color equivalent
    .black, .blue, .blue, .blue, .bright_blue, .bright_blue, // 16-21
    .green, .cyan, .blue, .blue, .bright_blue, .bright_blue, // 22-27
    .green, .green, .cyan, .blue, .bright_blue, .bright_blue, // 28-33
    .green, .green, .green, .cyan, .bright_blue, .bright_blue, // 34-39
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_blue, // 40-45
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, // 46-51
    .red, .magenta, .blue, .blue, .bright_blue, .bright_blue, // 52-57
    .yellow, .bright_black, .blue, .blue, .bright_blue, .bright_blue, // 58-63
    .green, .green, .cyan, .blue, .bright_blue, .bright_blue, // 64-69
    .green, .green, .green, .cyan, .bright_blue, .bright_blue, // 70-75
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_blue, // 76-81
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, // 82-87
    .red, .red, .magenta, .blue, .bright_blue, .bright_blue, // 88-93
    .red, .red, .magenta, .blue, .bright_blue, .bright_blue, // 94-99
    .red, .red, .magenta, .blue, .bright_blue, .bright_blue, // 100-105
    .yellow, .yellow, .bright_black, .blue, .bright_blue, .bright_blue, // 106-111
    .green, .green, .green, .cyan, .bright_blue, .bright_blue, // 112-117
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_blue, // 118-123
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, // 124-129
    .red, .red, .red, .magenta, .bright_blue, .bright_blue, // 130-135
    .red, .red, .red, .magenta, .bright_blue, .bright_blue, // 136-141
    .red, .red, .red, .magenta, .bright_blue, .bright_blue, // 142-147
    .red, .red, .red, .magenta, .bright_blue, .bright_blue, // 148-153
    .yellow, .yellow, .yellow, .white, .bright_blue, .bright_blue, // 154-159
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_blue, // 160-165
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, // 166-171
    .bright_red, .bright_red, .bright_red, .bright_magenta, .bright_blue, .bright_blue, // 172-177
    .bright_red, .bright_red, .bright_red, .bright_magenta, .bright_blue, .bright_blue, // 178-183
    .bright_red, .bright_red, .bright_red, .bright_magenta, .bright_blue, .bright_blue, // 184-189
    .bright_red, .bright_red, .bright_red, .bright_magenta, .bright_blue, .bright_blue, // 190-195
    .bright_red, .bright_red, .bright_red, .bright_magenta, .bright_blue, .bright_blue, // 196-201
    .bright_yellow, .bright_yellow, .bright_yellow, .bright_white, .bright_white, .bright_blue, // 202-207
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, // 208-213
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, // 214-219
    .bright_red, .bright_red, .bright_red, .bright_red, .bright_red, .bright_magenta, // 220-225
    .bright_yellow, .bright_yellow, .bright_yellow, .bright_yellow, .bright_yellow, .bright_white, // 226-231
    // Colors 232-255: Grayscale ramp (24 colors)
    .black, .black, .black, .black, .black, .black, // 232-237
    .bright_black, .bright_black, .bright_black, .bright_black, .bright_black, .bright_black, // 238-243
    .white, .white, .white, .white, .white, .white, // 244-249
    .bright_white, .bright_white, .bright_white, .bright_white, .bright_white, .bright_white, // 250-255
};

// Test function to validate color conversions
test "enhanced color conversion" {
    // Test basic color conversion
    const red = Color{ .basic = .red };
    const red_rgba = red.rgba();
    try std.testing.expectEqual(@as(u8, 0x80), red_rgba.r);
    try std.testing.expectEqual(@as(u8, 0x00), red_rgba.g);
    try std.testing.expectEqual(@as(u8, 0x00), red_rgba.b);

    // Test RGB to 256-color conversion
    const bright_red = Color{ .rgb = RGBColor{ .r = 255, .g = 0, .b = 0 } };
    const converted = convert256(bright_red);
    try std.testing.expectEqual(@as(u8, 196), converted.value); // Should map to bright red in 256-color palette

    // Test 256 to 16-color conversion
    const converted16 = convert16(Color{ .indexed = IndexedColor{ .value = 196 } });
    try std.testing.expectEqual(BasicColor.bright_red, converted16);
}

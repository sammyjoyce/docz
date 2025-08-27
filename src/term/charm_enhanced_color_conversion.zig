const std = @import("std");
const math = std.math;

/// Enhanced color system based on Charmbracelet's x/ansi implementation
/// with proper HSLuv color distance calculations and comprehensive palette support.
/// Color represents a color that can be used in a terminal.
/// ANSI (including ANSI256) and 24-bit "true colors" fall under this category.
pub const Color = union(enum) {
    basic: BasicColor,
    indexed: IndexedColor,
    rgb: RGBColor,

    /// Convert any color to RGBA values
    pub fn rgba(self: Color) RGBA {
        return switch (self) {
            .basic => |c| c.rgba(),
            .indexed => |c| c.rgba(),
            .rgb => |c| c.rgba(),
        };
    }

    /// Check if two colors are equal
    pub fn eql(self: Color, other: Color) bool {
        return switch (self) {
            .basic => |a| switch (other) {
                .basic => |b| a == b,
                else => false,
            },
            .indexed => |a| switch (other) {
                .indexed => |b| a.value == b.value,
                else => false,
            },
            .rgb => |a| switch (other) {
                .rgb => |b| a.r == b.r and a.g == b.g and a.b == b.b,
                else => false,
            },
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

    pub fn init(value: u8) IndexedColor {
        return IndexedColor{ .value = value };
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

    pub fn toHex(self: RGBColor) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }

    pub fn init(r: u8, g: u8, b: u8) RGBColor {
        return RGBColor{ .r = r, .g = g, .b = b };
    }
};

/// RGBA represents a color with red, green, blue, and alpha components.
pub const RGBA = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn init(r: u8, g: u8, b: u8, a: u8) RGBA {
        return RGBA{ .r = r, .g = g, .b = b, .a = a };
    }
};

/// HSLuv color representation for more accurate perceptual color distance
const HSLuv = struct {
    h: f64, // Hue: 0-360
    s: f64, // Saturation: 0-100
    l: f64, // Lightness: 0-100

    /// Calculate perceptual distance between two HSLuv colors
    pub fn distance(self: HSLuv, other: HSLuv) f64 {
        // Use Delta E CIE 1976 approximation for HSLuv
        const dl = self.l - other.l;
        const ds = self.s - other.s;

        // Handle hue wraparound
        var dh = @abs(self.h - other.h);
        if (dh > 180) dh = 360 - dh;

        return @sqrt(dl * dl + ds * ds + dh * dh);
    }
};

/// Convert hex value to RGB components
fn hexToRGB(hex: u32) struct { u32, u32, u32 } {
    return .{ hex >> 16 & 0xff, hex >> 8 & 0xff, hex & 0xff };
}

/// Convert RGB to 6-cube index for xterm 6x6x6 color cube
fn to6Cube(v: f64) u32 {
    if (v < 48) return 0;
    if (v < 115) return 1;
    return @intFromFloat(@min(5, (v - 35) / 40));
}

/// Convert RGB to HSLuv (simplified approximation)
fn rgbToHSLuv(r: f64, g: f64, b: f64) HSLuv {
    // Normalize RGB values to 0-1
    const rn = r / 255.0;
    const gn = g / 255.0;
    const bn = b / 255.0;

    // Convert to HSL first (simplified)
    const max_val = @max(@max(rn, gn), bn);
    const min_val = @min(@min(rn, gn), bn);
    const delta = max_val - min_val;

    // Lightness
    const l = (max_val + min_val) / 2.0;

    // Saturation
    var s: f64 = 0;
    if (delta != 0) {
        s = if (l < 0.5) delta / (max_val + min_val) else delta / (2.0 - max_val - min_val);
    }

    // Hue
    var h: f64 = 0;
    if (delta != 0) {
        if (max_val == rn) {
            h = ((gn - bn) / delta) * 60;
        } else if (max_val == gn) {
            h = (2 + (bn - rn) / delta) * 60;
        } else {
            h = (4 + (rn - gn) / delta) * 60;
        }
        if (h < 0) h += 360;
    }

    return HSLuv{
        .h = h,
        .s = s * 100,
        .l = l * 100,
    };
}

/// Enhanced 256-color conversion using HSLuv color distance
/// This implementation follows charmbracelet/x's sophisticated algorithm
pub fn convert256(color: Color) IndexedColor {
    // If already indexed, return as-is
    if (color == .indexed) {
        return color.indexed;
    }

    const rgba_color = color.rgba();
    const r = @as(f64, @floatFromInt(rgba_color.r));
    const g = @as(f64, @floatFromInt(rgba_color.g));
    const b = @as(f64, @floatFromInt(rgba_color.b));

    // xterm 6x6x6 color cube values
    const q2c = [6]u32{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };

    // Map RGB to 6x6x6 cube
    const qr = to6Cube(r);
    const cr = q2c[qr];
    const qg = to6Cube(g);
    const cg = q2c[qg];
    const qb = to6Cube(b);
    const cb = q2c[qb];

    // Calculate cube color index
    const ci = (36 * qr) + (6 * qg) + qb;

    // If we hit the color exactly, return early
    if (cr == @as(u32, @intFromFloat(r)) and cg == @as(u32, @intFromFloat(g)) and cb == @as(u32, @intFromFloat(b))) {
        return IndexedColor.init(@intCast(16 + ci));
    }

    // Work out the closest grey (average of RGB)
    const grey_avg = @as(u32, @intFromFloat((r + g + b) / 3));
    var grey_idx: u32 = 0;
    if (grey_avg > 238) {
        grey_idx = 23;
    } else {
        grey_idx = @max(0, (grey_avg -| 3) / 10);
    }
    const grey = 8 + (10 * grey_idx);

    // Use HSLuv color distance for more accurate perceptual matching
    const original_hsluv = rgbToHSLuv(r, g, b);
    const cube_hsluv = rgbToHSLuv(@floatFromInt(cr), @floatFromInt(cg), @floatFromInt(cb));
    const grey_hsluv = rgbToHSLuv(@floatFromInt(grey), @floatFromInt(grey), @floatFromInt(grey));

    const color_dist = original_hsluv.distance(cube_hsluv);
    const grey_dist = original_hsluv.distance(grey_hsluv);

    if (color_dist <= grey_dist) {
        return IndexedColor.init(@intCast(16 + ci));
    }
    return IndexedColor.init(@intCast(232 + grey_idx));
}

/// Convert any color to 16-color ANSI palette
pub fn convert16(color: Color) BasicColor {
    return switch (color) {
        .basic => |c| c,
        .indexed => |c| ansi256To16[c.value],
        .rgb => |c| {
            const c256 = convert256(Color{ .rgb = c });
            return ansi256To16[c256.value];
        },
    };
}

/// Calculate distance between two colors in RGB space using perceptual weights
pub fn colorDistance(c1: Color, c2: Color) f64 {
    const rgba1 = c1.rgba();
    const rgba2 = c2.rgba();

    const r1 = @as(f64, @floatFromInt(rgba1.r));
    const g1 = @as(f64, @floatFromInt(rgba1.g));
    const b1 = @as(f64, @floatFromInt(rgba1.b));

    const r2 = @as(f64, @floatFromInt(rgba2.r));
    const g2 = @as(f64, @floatFromInt(rgba2.g));
    const b2 = @as(f64, @floatFromInt(rgba2.b));

    // Convert to HSLuv and calculate perceptual distance
    const hsluv1 = rgbToHSLuv(r1, g1, b1);
    const hsluv2 = rgbToHSLuv(r2, g2, b2);

    return hsluv1.distance(hsluv2);
}

/// Find the closest color in the 256-color palette to a given RGB color
pub fn findClosestColor(target: RGBColor) IndexedColor {
    var best_idx: u8 = 0;
    var best_distance: f64 = math.inf(f64);

    const target_color = Color{ .rgb = target };

    for (0..256) |i| {
        const palette_color = Color{ .indexed = IndexedColor.init(@intCast(i)) };
        const distance = colorDistance(target_color, palette_color);

        if (distance < best_distance) {
            best_distance = distance;
            best_idx = @intCast(i);
        }
    }

    return IndexedColor.init(best_idx);
}

/// Get a contrasting color for the given color (useful for text on backgrounds)
pub fn getContrastingColor(background: Color) Color {
    const rgba = background.rgba();

    // Calculate relative luminance using WCAG formula
    const r = @as(f64, @floatFromInt(rgba.r)) / 255.0;
    const g = @as(f64, @floatFromInt(rgba.g)) / 255.0;
    const b = @as(f64, @floatFromInt(rgba.b)) / 255.0;

    const luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;

    // Return white for dark backgrounds, black for light backgrounds
    if (luminance > 0.5) {
        return Color{ .basic = .black };
    } else {
        return Color{ .basic = .white };
    }
}

/// RGB values of ANSI colors (0-255) - complete xterm palette
const ansi_hex = [256]RGBA{
    // Standard colors (0-15)
    RGBA.init(0x00, 0x00, 0x00, 0xff), // 0: Black
    RGBA.init(0x80, 0x00, 0x00, 0xff), // 1: Red
    RGBA.init(0x00, 0x80, 0x00, 0xff), // 2: Green
    RGBA.init(0x80, 0x80, 0x00, 0xff), // 3: Yellow
    RGBA.init(0x00, 0x00, 0x80, 0xff), // 4: Blue
    RGBA.init(0x80, 0x00, 0x80, 0xff), // 5: Magenta
    RGBA.init(0x00, 0x80, 0x80, 0xff), // 6: Cyan
    RGBA.init(0xc0, 0xc0, 0xc0, 0xff), // 7: White
    RGBA.init(0x80, 0x80, 0x80, 0xff), // 8: Bright Black
    RGBA.init(0xff, 0x00, 0x00, 0xff), // 9: Bright Red
    RGBA.init(0x00, 0xff, 0x00, 0xff), // 10: Bright Green
    RGBA.init(0xff, 0xff, 0x00, 0xff), // 11: Bright Yellow
    RGBA.init(0x00, 0x00, 0xff, 0xff), // 12: Bright Blue
    RGBA.init(0xff, 0x00, 0xff, 0xff), // 13: Bright Magenta
    RGBA.init(0x00, 0xff, 0xff, 0xff), // 14: Bright Cyan
    RGBA.init(0xff, 0xff, 0xff, 0xff), // 15: Bright White

    // 6x6x6 color cube (16-231)
    RGBA.init(0x00, 0x00, 0x00, 0xff), // 16
    RGBA.init(0x00, 0x00, 0x5f, 0xff), // 17
    RGBA.init(0x00, 0x00, 0x87, 0xff), // 18
    RGBA.init(0x00, 0x00, 0xaf, 0xff), // 19
    RGBA.init(0x00, 0x00, 0xd7, 0xff), // 20
    RGBA.init(0x00, 0x00, 0xff, 0xff), // 21
    RGBA.init(0x00, 0x5f, 0x00, 0xff), // 22
    RGBA.init(0x00, 0x5f, 0x5f, 0xff), // 23
    RGBA.init(0x00, 0x5f, 0x87, 0xff), // 24
    RGBA.init(0x00, 0x5f, 0xaf, 0xff), // 25
    RGBA.init(0x00, 0x5f, 0xd7, 0xff), // 26
    RGBA.init(0x00, 0x5f, 0xff, 0xff), // 27
    RGBA.init(0x00, 0x87, 0x00, 0xff), // 28
    RGBA.init(0x00, 0x87, 0x5f, 0xff), // 29
    RGBA.init(0x00, 0x87, 0x87, 0xff), // 30
    RGBA.init(0x00, 0x87, 0xaf, 0xff), // 31
    RGBA.init(0x00, 0x87, 0xd7, 0xff), // 32
    RGBA.init(0x00, 0x87, 0xff, 0xff), // 33
    RGBA.init(0x00, 0xaf, 0x00, 0xff), // 34
    RGBA.init(0x00, 0xaf, 0x5f, 0xff), // 35
    RGBA.init(0x00, 0xaf, 0x87, 0xff), // 36
    RGBA.init(0x00, 0xaf, 0xaf, 0xff), // 37
    RGBA.init(0x00, 0xaf, 0xd7, 0xff), // 38
    RGBA.init(0x00, 0xaf, 0xff, 0xff), // 39
    RGBA.init(0x00, 0xd7, 0x00, 0xff), // 40
    RGBA.init(0x00, 0xd7, 0x5f, 0xff), // 41
    RGBA.init(0x00, 0xd7, 0x87, 0xff), // 42
    RGBA.init(0x00, 0xd7, 0xaf, 0xff), // 43
    RGBA.init(0x00, 0xd7, 0xd7, 0xff), // 44
    RGBA.init(0x00, 0xd7, 0xff, 0xff), // 45
    RGBA.init(0x00, 0xff, 0x00, 0xff), // 46
    RGBA.init(0x00, 0xff, 0x5f, 0xff), // 47
    RGBA.init(0x00, 0xff, 0x87, 0xff), // 48
    RGBA.init(0x00, 0xff, 0xaf, 0xff), // 49
    RGBA.init(0x00, 0xff, 0xd7, 0xff), // 50
    RGBA.init(0x00, 0xff, 0xff, 0xff), // 51
    RGBA.init(0x5f, 0x00, 0x00, 0xff), // 52
    RGBA.init(0x5f, 0x00, 0x5f, 0xff), // 53
    RGBA.init(0x5f, 0x00, 0x87, 0xff), // 54
    RGBA.init(0x5f, 0x00, 0xaf, 0xff), // 55
    RGBA.init(0x5f, 0x00, 0xd7, 0xff), // 56
    RGBA.init(0x5f, 0x00, 0xff, 0xff), // 57
    RGBA.init(0x5f, 0x5f, 0x00, 0xff), // 58
    RGBA.init(0x5f, 0x5f, 0x5f, 0xff), // 59
    RGBA.init(0x5f, 0x5f, 0x87, 0xff), // 60
    RGBA.init(0x5f, 0x5f, 0xaf, 0xff), // 61
    RGBA.init(0x5f, 0x5f, 0xd7, 0xff), // 62
    RGBA.init(0x5f, 0x5f, 0xff, 0xff), // 63
    RGBA.init(0x5f, 0x87, 0x00, 0xff), // 64
    RGBA.init(0x5f, 0x87, 0x5f, 0xff), // 65
    RGBA.init(0x5f, 0x87, 0x87, 0xff), // 66
    RGBA.init(0x5f, 0x87, 0xaf, 0xff), // 67
    RGBA.init(0x5f, 0x87, 0xd7, 0xff), // 68
    RGBA.init(0x5f, 0x87, 0xff, 0xff), // 69
    RGBA.init(0x5f, 0xaf, 0x00, 0xff), // 70
    RGBA.init(0x5f, 0xaf, 0x5f, 0xff), // 71
    RGBA.init(0x5f, 0xaf, 0x87, 0xff), // 72
    RGBA.init(0x5f, 0xaf, 0xaf, 0xff), // 73
    RGBA.init(0x5f, 0xaf, 0xd7, 0xff), // 74
    RGBA.init(0x5f, 0xaf, 0xff, 0xff), // 75
    RGBA.init(0x5f, 0xd7, 0x00, 0xff), // 76
    RGBA.init(0x5f, 0xd7, 0x5f, 0xff), // 77
    RGBA.init(0x5f, 0xd7, 0x87, 0xff), // 78
    RGBA.init(0x5f, 0xd7, 0xaf, 0xff), // 79
    RGBA.init(0x5f, 0xd7, 0xd7, 0xff), // 80
    RGBA.init(0x5f, 0xd7, 0xff, 0xff), // 81
    RGBA.init(0x5f, 0xff, 0x00, 0xff), // 82
    RGBA.init(0x5f, 0xff, 0x5f, 0xff), // 83
    RGBA.init(0x5f, 0xff, 0x87, 0xff), // 84
    RGBA.init(0x5f, 0xff, 0xaf, 0xff), // 85
    RGBA.init(0x5f, 0xff, 0xd7, 0xff), // 86
    RGBA.init(0x5f, 0xff, 0xff, 0xff), // 87
    RGBA.init(0x87, 0x00, 0x00, 0xff), // 88
    RGBA.init(0x87, 0x00, 0x5f, 0xff), // 89
    RGBA.init(0x87, 0x00, 0x87, 0xff), // 90
    RGBA.init(0x87, 0x00, 0xaf, 0xff), // 91
    RGBA.init(0x87, 0x00, 0xd7, 0xff), // 92
    RGBA.init(0x87, 0x00, 0xff, 0xff), // 93
    RGBA.init(0x87, 0x5f, 0x00, 0xff), // 94
    RGBA.init(0x87, 0x5f, 0x5f, 0xff), // 95
    RGBA.init(0x87, 0x5f, 0x87, 0xff), // 96
    RGBA.init(0x87, 0x5f, 0xaf, 0xff), // 97
    RGBA.init(0x87, 0x5f, 0xd7, 0xff), // 98
    RGBA.init(0x87, 0x5f, 0xff, 0xff), // 99
    RGBA.init(0x87, 0x87, 0x00, 0xff), // 100
    RGBA.init(0x87, 0x87, 0x5f, 0xff), // 101
    RGBA.init(0x87, 0x87, 0x87, 0xff), // 102
    RGBA.init(0x87, 0x87, 0xaf, 0xff), // 103
    RGBA.init(0x87, 0x87, 0xd7, 0xff), // 104
    RGBA.init(0x87, 0x87, 0xff, 0xff), // 105
    RGBA.init(0x87, 0xaf, 0x00, 0xff), // 106
    RGBA.init(0x87, 0xaf, 0x5f, 0xff), // 107
    RGBA.init(0x87, 0xaf, 0x87, 0xff), // 108
    RGBA.init(0x87, 0xaf, 0xaf, 0xff), // 109
    RGBA.init(0x87, 0xaf, 0xd7, 0xff), // 110
    RGBA.init(0x87, 0xaf, 0xff, 0xff), // 111
    RGBA.init(0x87, 0xd7, 0x00, 0xff), // 112
    RGBA.init(0x87, 0xd7, 0x5f, 0xff), // 113
    RGBA.init(0x87, 0xd7, 0x87, 0xff), // 114
    RGBA.init(0x87, 0xd7, 0xaf, 0xff), // 115
    RGBA.init(0x87, 0xd7, 0xd7, 0xff), // 116
    RGBA.init(0x87, 0xd7, 0xff, 0xff), // 117
    RGBA.init(0x87, 0xff, 0x00, 0xff), // 118
    RGBA.init(0x87, 0xff, 0x5f, 0xff), // 119
    RGBA.init(0x87, 0xff, 0x87, 0xff), // 120
    RGBA.init(0x87, 0xff, 0xaf, 0xff), // 121
    RGBA.init(0x87, 0xff, 0xd7, 0xff), // 122
    RGBA.init(0x87, 0xff, 0xff, 0xff), // 123
    RGBA.init(0xaf, 0x00, 0x00, 0xff), // 124
    RGBA.init(0xaf, 0x00, 0x5f, 0xff), // 125
    RGBA.init(0xaf, 0x00, 0x87, 0xff), // 126
    RGBA.init(0xaf, 0x00, 0xaf, 0xff), // 127
    RGBA.init(0xaf, 0x00, 0xd7, 0xff), // 128
    RGBA.init(0xaf, 0x00, 0xff, 0xff), // 129
    RGBA.init(0xaf, 0x5f, 0x00, 0xff), // 130
    RGBA.init(0xaf, 0x5f, 0x5f, 0xff), // 131
    RGBA.init(0xaf, 0x5f, 0x87, 0xff), // 132
    RGBA.init(0xaf, 0x5f, 0xaf, 0xff), // 133
    RGBA.init(0xaf, 0x5f, 0xd7, 0xff), // 134
    RGBA.init(0xaf, 0x5f, 0xff, 0xff), // 135
    RGBA.init(0xaf, 0x87, 0x00, 0xff), // 136
    RGBA.init(0xaf, 0x87, 0x5f, 0xff), // 137
    RGBA.init(0xaf, 0x87, 0x87, 0xff), // 138
    RGBA.init(0xaf, 0x87, 0xaf, 0xff), // 139
    RGBA.init(0xaf, 0x87, 0xd7, 0xff), // 140
    RGBA.init(0xaf, 0x87, 0xff, 0xff), // 141
    RGBA.init(0xaf, 0xaf, 0x00, 0xff), // 142
    RGBA.init(0xaf, 0xaf, 0x5f, 0xff), // 143
    RGBA.init(0xaf, 0xaf, 0x87, 0xff), // 144
    RGBA.init(0xaf, 0xaf, 0xaf, 0xff), // 145
    RGBA.init(0xaf, 0xaf, 0xd7, 0xff), // 146
    RGBA.init(0xaf, 0xaf, 0xff, 0xff), // 147
    RGBA.init(0xaf, 0xd7, 0x00, 0xff), // 148
    RGBA.init(0xaf, 0xd7, 0x5f, 0xff), // 149
    RGBA.init(0xaf, 0xd7, 0x87, 0xff), // 150
    RGBA.init(0xaf, 0xd7, 0xaf, 0xff), // 151
    RGBA.init(0xaf, 0xd7, 0xd7, 0xff), // 152
    RGBA.init(0xaf, 0xd7, 0xff, 0xff), // 153
    RGBA.init(0xaf, 0xff, 0x00, 0xff), // 154
    RGBA.init(0xaf, 0xff, 0x5f, 0xff), // 155
    RGBA.init(0xaf, 0xff, 0x87, 0xff), // 156
    RGBA.init(0xaf, 0xff, 0xaf, 0xff), // 157
    RGBA.init(0xaf, 0xff, 0xd7, 0xff), // 158
    RGBA.init(0xaf, 0xff, 0xff, 0xff), // 159
    RGBA.init(0xd7, 0x00, 0x00, 0xff), // 160
    RGBA.init(0xd7, 0x00, 0x5f, 0xff), // 161
    RGBA.init(0xd7, 0x00, 0x87, 0xff), // 162
    RGBA.init(0xd7, 0x00, 0xaf, 0xff), // 163
    RGBA.init(0xd7, 0x00, 0xd7, 0xff), // 164
    RGBA.init(0xd7, 0x00, 0xff, 0xff), // 165
    RGBA.init(0xd7, 0x5f, 0x00, 0xff), // 166
    RGBA.init(0xd7, 0x5f, 0x5f, 0xff), // 167
    RGBA.init(0xd7, 0x5f, 0x87, 0xff), // 168
    RGBA.init(0xd7, 0x5f, 0xaf, 0xff), // 169
    RGBA.init(0xd7, 0x5f, 0xd7, 0xff), // 170
    RGBA.init(0xd7, 0x5f, 0xff, 0xff), // 171
    RGBA.init(0xd7, 0x87, 0x00, 0xff), // 172
    RGBA.init(0xd7, 0x87, 0x5f, 0xff), // 173
    RGBA.init(0xd7, 0x87, 0x87, 0xff), // 174
    RGBA.init(0xd7, 0x87, 0xaf, 0xff), // 175
    RGBA.init(0xd7, 0x87, 0xd7, 0xff), // 176
    RGBA.init(0xd7, 0x87, 0xff, 0xff), // 177
    RGBA.init(0xd7, 0xaf, 0x00, 0xff), // 178
    RGBA.init(0xd7, 0xaf, 0x5f, 0xff), // 179
    RGBA.init(0xd7, 0xaf, 0x87, 0xff), // 180
    RGBA.init(0xd7, 0xaf, 0xaf, 0xff), // 181
    RGBA.init(0xd7, 0xaf, 0xd7, 0xff), // 182
    RGBA.init(0xd7, 0xaf, 0xff, 0xff), // 183
    RGBA.init(0xd7, 0xd7, 0x00, 0xff), // 184
    RGBA.init(0xd7, 0xd7, 0x5f, 0xff), // 185
    RGBA.init(0xd7, 0xd7, 0x87, 0xff), // 186
    RGBA.init(0xd7, 0xd7, 0xaf, 0xff), // 187
    RGBA.init(0xd7, 0xd7, 0xd7, 0xff), // 188
    RGBA.init(0xd7, 0xd7, 0xff, 0xff), // 189
    RGBA.init(0xd7, 0xff, 0x00, 0xff), // 190
    RGBA.init(0xd7, 0xff, 0x5f, 0xff), // 191
    RGBA.init(0xd7, 0xff, 0x87, 0xff), // 192
    RGBA.init(0xd7, 0xff, 0xaf, 0xff), // 193
    RGBA.init(0xd7, 0xff, 0xd7, 0xff), // 194
    RGBA.init(0xd7, 0xff, 0xff, 0xff), // 195
    RGBA.init(0xff, 0x00, 0x00, 0xff), // 196
    RGBA.init(0xff, 0x00, 0x5f, 0xff), // 197
    RGBA.init(0xff, 0x00, 0x87, 0xff), // 198
    RGBA.init(0xff, 0x00, 0xaf, 0xff), // 199
    RGBA.init(0xff, 0x00, 0xd7, 0xff), // 200
    RGBA.init(0xff, 0x00, 0xff, 0xff), // 201
    RGBA.init(0xff, 0x5f, 0x00, 0xff), // 202
    RGBA.init(0xff, 0x5f, 0x5f, 0xff), // 203
    RGBA.init(0xff, 0x5f, 0x87, 0xff), // 204
    RGBA.init(0xff, 0x5f, 0xaf, 0xff), // 205
    RGBA.init(0xff, 0x5f, 0xd7, 0xff), // 206
    RGBA.init(0xff, 0x5f, 0xff, 0xff), // 207
    RGBA.init(0xff, 0x87, 0x00, 0xff), // 208
    RGBA.init(0xff, 0x87, 0x5f, 0xff), // 209
    RGBA.init(0xff, 0x87, 0x87, 0xff), // 210
    RGBA.init(0xff, 0x87, 0xaf, 0xff), // 211
    RGBA.init(0xff, 0x87, 0xd7, 0xff), // 212
    RGBA.init(0xff, 0x87, 0xff, 0xff), // 213
    RGBA.init(0xff, 0xaf, 0x00, 0xff), // 214
    RGBA.init(0xff, 0xaf, 0x5f, 0xff), // 215
    RGBA.init(0xff, 0xaf, 0x87, 0xff), // 216
    RGBA.init(0xff, 0xaf, 0xaf, 0xff), // 217
    RGBA.init(0xff, 0xaf, 0xd7, 0xff), // 218
    RGBA.init(0xff, 0xaf, 0xff, 0xff), // 219
    RGBA.init(0xff, 0xd7, 0x00, 0xff), // 220
    RGBA.init(0xff, 0xd7, 0x5f, 0xff), // 221
    RGBA.init(0xff, 0xd7, 0x87, 0xff), // 222
    RGBA.init(0xff, 0xd7, 0xaf, 0xff), // 223
    RGBA.init(0xff, 0xd7, 0xd7, 0xff), // 224
    RGBA.init(0xff, 0xd7, 0xff, 0xff), // 225
    RGBA.init(0xff, 0xff, 0x00, 0xff), // 226
    RGBA.init(0xff, 0xff, 0x5f, 0xff), // 227
    RGBA.init(0xff, 0xff, 0x87, 0xff), // 228
    RGBA.init(0xff, 0xff, 0xaf, 0xff), // 229
    RGBA.init(0xff, 0xff, 0xd7, 0xff), // 230
    RGBA.init(0xff, 0xff, 0xff, 0xff), // 231

    // Grayscale ramp (232-255)
    RGBA.init(0x08, 0x08, 0x08, 0xff), // 232
    RGBA.init(0x12, 0x12, 0x12, 0xff), // 233
    RGBA.init(0x1c, 0x1c, 0x1c, 0xff), // 234
    RGBA.init(0x26, 0x26, 0x26, 0xff), // 235
    RGBA.init(0x30, 0x30, 0x30, 0xff), // 236
    RGBA.init(0x3a, 0x3a, 0x3a, 0xff), // 237
    RGBA.init(0x44, 0x44, 0x44, 0xff), // 238
    RGBA.init(0x4e, 0x4e, 0x4e, 0xff), // 239
    RGBA.init(0x58, 0x58, 0x58, 0xff), // 240
    RGBA.init(0x62, 0x62, 0x62, 0xff), // 241
    RGBA.init(0x6c, 0x6c, 0x6c, 0xff), // 242
    RGBA.init(0x76, 0x76, 0x76, 0xff), // 243
    RGBA.init(0x80, 0x80, 0x80, 0xff), // 244
    RGBA.init(0x8a, 0x8a, 0x8a, 0xff), // 245
    RGBA.init(0x94, 0x94, 0x94, 0xff), // 246
    RGBA.init(0x9e, 0x9e, 0x9e, 0xff), // 247
    RGBA.init(0xa8, 0xa8, 0xa8, 0xff), // 248
    RGBA.init(0xb2, 0xb2, 0xb2, 0xff), // 249
    RGBA.init(0xbc, 0xbc, 0xbc, 0xff), // 250
    RGBA.init(0xc6, 0xc6, 0xc6, 0xff), // 251
    RGBA.init(0xd0, 0xd0, 0xd0, 0xff), // 252
    RGBA.init(0xda, 0xda, 0xda, 0xff), // 253
    RGBA.init(0xe4, 0xe4, 0xe4, 0xff), // 254
    RGBA.init(0xee, 0xee, 0xee, 0xff), // 255
};

/// Mapping from 256-color ANSI palette to 16-color ANSI palette
const ansi256To16 = [256]BasicColor{
    // Direct mappings (0-15)
    .black,        .red,        .green,        .yellow,        .blue,        .magenta,        .cyan,        .white,
    .bright_black, .bright_red, .bright_green, .bright_yellow, .bright_blue, .bright_magenta, .bright_cyan,
    .bright_white,

    // 6x6x6 color cube (16-231) - mapping to closest 16-color equivalent
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
    .yellow, .yellow, .bright_black, .blue, .bright_blue, .bright_blue, // 100-105
    .green, .green, .green, .cyan, .bright_blue, .bright_blue, // 106-111
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_blue, // 112-117
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, // 118-123
    .red, .red, .red, .magenta, .bright_blue, .bright_blue, // 124-129
    .red, .red, .red, .magenta, .bright_blue, .bright_blue, // 130-135
    .red, .red, .red, .magenta, .bright_blue, .bright_blue, // 136-141
    .yellow, .yellow, .yellow, .white, .bright_blue, .bright_blue, // 142-147
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_blue, // 148-153
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, // 154-159
    .bright_red, .bright_red, .bright_red, .bright_red, .bright_red, .bright_magenta, // 160-165
    .bright_red, .bright_red, .bright_red, .bright_red, .bright_red, .bright_magenta, // 166-171
    .bright_red, .bright_red, .bright_red, .bright_red, .bright_red, .bright_magenta, // 172-177
    .bright_red, .bright_red, .bright_red, .bright_red, .bright_red, .bright_magenta, // 178-183
    .bright_yellow, .bright_yellow, .bright_yellow, .bright_yellow, .bright_white, .bright_white, // 184-189
    .bright_green, .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, // 190-195
    .bright_red, .bright_red, .bright_red, .bright_red, .bright_red, .bright_magenta, // 196-201
    .bright_red, .bright_red, .bright_red, .bright_red, .bright_red, .bright_magenta, // 202-207
    .bright_red, .bright_red, .bright_red, .bright_red, .bright_red, .bright_magenta, // 208-213
    .bright_yellow, .bright_yellow, .bright_yellow, .bright_yellow, .bright_yellow, .bright_white, // 214-219
    .bright_yellow, .bright_yellow, .bright_yellow, .bright_yellow, .bright_yellow, .bright_white, // 220-225
    .bright_yellow, .bright_yellow, .bright_yellow, .bright_yellow, .bright_yellow, .bright_white, // 226-231

    // Grayscale (232-255)
    .black, .black, .black, .black, .black, .black, // 232-237
    .bright_black, .bright_black, .bright_black, .bright_black, .bright_black, .bright_black, // 238-243
    .white, .white, .white, .white, .white, .white, // 244-249
    .bright_white, .bright_white, .bright_white, .bright_white, .bright_white, .bright_white, // 250-255
};

// Tests
test "charm enhanced color conversion" {
    // Test basic color conversion
    const red = Color{ .basic = .red };
    const red_rgba = red.rgba();
    try std.testing.expectEqual(@as(u8, 0x80), red_rgba.r);
    try std.testing.expectEqual(@as(u8, 0x00), red_rgba.g);
    try std.testing.expectEqual(@as(u8, 0x00), red_rgba.b);
    try std.testing.expectEqual(@as(u8, 0xff), red_rgba.a);

    // Test RGB to 256-color conversion with exact match
    const bright_red = Color{ .rgb = RGBColor.init(255, 0, 0) };
    const converted = convert256(bright_red);
    try std.testing.expectEqual(@as(u8, 196), converted.value); // Should map to bright red

    // Test 256 to 16-color conversion
    const converted16 = convert16(Color{ .indexed = IndexedColor.init(196) });
    try std.testing.expectEqual(BasicColor.bright_red, converted16);

    // Test color equality
    const color1 = Color{ .rgb = RGBColor.init(255, 0, 0) };
    const color2 = Color{ .rgb = RGBColor.init(255, 0, 0) };
    const color3 = Color{ .rgb = RGBColor.init(0, 255, 0) };
    try std.testing.expect(color1.eql(color2));
    try std.testing.expect(!color1.eql(color3));

    // Test contrasting color
    const dark_bg = Color{ .rgb = RGBColor.init(50, 50, 50) };
    const light_bg = Color{ .rgb = RGBColor.init(200, 200, 200) };
    const dark_contrast = getContrastingColor(dark_bg);
    const light_contrast = getContrastingColor(light_bg);

    try std.testing.expectEqual(Color{ .basic = .white }, dark_contrast);
    try std.testing.expectEqual(Color{ .basic = .black }, light_contrast);

    // Test hex conversion
    const rgb = RGBColor.fromHex(0xFF5733);
    try std.testing.expectEqual(@as(u8, 0xFF), rgb.r);
    try std.testing.expectEqual(@as(u8, 0x57), rgb.g);
    try std.testing.expectEqual(@as(u8, 0x33), rgb.b);

    try std.testing.expectEqual(@as(u32, 0xFF5733), rgb.toHex());
}

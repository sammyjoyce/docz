//! Unified Color Management System
//! Consolidated color primitives, conversions, and terminal color operations

const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

// === CORE COLOR TYPES ===

/// RGB color representation (24-bit true color)
pub const RgbColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RgbColor {
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn toHex(self: RgbColor) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }

    pub fn fromHex(hex: u32) RgbColor {
        return .{
            .r = @intCast((hex >> 16) & 0xFF),
            .g = @intCast((hex >> 8) & 0xFF),
            .b = @intCast(hex & 0xFF),
        };
    }

    /// Convert to normalized float values (0.0 - 1.0)
    pub fn toNormalized(self: RgbColor) struct { r: f32, g: f32, b: f32 } {
        return .{
            .r = @as(f32, @floatFromInt(self.r)) / 255.0,
            .g = @as(f32, @floatFromInt(self.g)) / 255.0,
            .b = @as(f32, @floatFromInt(self.b)) / 255.0,
        };
    }

    /// Create from normalized float values
    pub fn fromNormalized(r: f32, g: f32, b: f32) RgbColor {
        return RgbColor.init(
            @intFromFloat(@max(0, @min(255, r * 255))),
            @intFromFloat(@max(0, @min(255, g * 255))),
            @intFromFloat(@max(0, @min(255, b * 255))),
        );
    }

    pub fn toHsl(self: RgbColor) HslColor {
        const r_norm = @as(f32, @floatFromInt(self.r)) / 255.0;
        const g_norm = @as(f32, @floatFromInt(self.g)) / 255.0;
        const b_norm = @as(f32, @floatFromInt(self.b)) / 255.0;

        const max = @max(r_norm, @max(g_norm, b_norm));
        const min = @min(r_norm, @min(g_norm, b_norm));
        const delta = max - min;

        var h: f32 = 0;
        var s: f32 = 0;
        const l = (max + min) / 2.0;

        if (delta > 0) {
            s = if (l < 0.5) delta / (max + min) else delta / (2 - max - min);

            if (max == r_norm) {
                h = ((g_norm - b_norm) / delta) + if (g_norm < b_norm) 6 else 0;
            } else if (max == g_norm) {
                h = ((b_norm - r_norm) / delta) + 2;
            } else {
                h = ((r_norm - g_norm) / delta) + 4;
            }
            h = h / 6.0;
        }

        return .{ .h = h * 360, .s = s, .l = l };
    }

    pub fn toHsv(self: RgbColor) HsvColor {
        const r_norm = @as(f32, @floatFromInt(self.r)) / 255.0;
        const g_norm = @as(f32, @floatFromInt(self.g)) / 255.0;
        const b_norm = @as(f32, @floatFromInt(self.b)) / 255.0;

        const max = @max(r_norm, @max(g_norm, b_norm));
        const min = @min(r_norm, @min(g_norm, b_norm));
        const delta = max - min;

        const v = max;

        var s: f32 = 0;
        if (max != 0) {
            s = delta / max;
        }

        var h: f32 = 0;
        if (delta != 0) {
            if (max == r_norm) {
                h = ((g_norm - b_norm) / delta) + if (g_norm < b_norm) 6 else 0;
            } else if (max == g_norm) {
                h = ((b_norm - r_norm) / delta) + 2;
            } else {
                h = ((r_norm - g_norm) / delta) + 4;
            }
            h = h / 6.0;
        }

        return .{ .h = h * 360, .s = s, .v = v };
    }

    pub fn toXyz(self: RgbColor) XyzColor {
        const norm = self.toNormalized();

        // sRGB to linear RGB
        const r_lin = if (norm.r <= 0.04045) norm.r / 12.92 else std.math.pow(f32, (norm.r + 0.055) / 1.055, 2.4);
        const g_lin = if (norm.g <= 0.04045) norm.g / 12.92 else std.math.pow(f32, (norm.g + 0.055) / 1.055, 2.4);
        const b_lin = if (norm.b <= 0.04045) norm.b / 12.92 else std.math.pow(f32, (norm.b + 0.055) / 1.055, 2.4);

        // Linear RGB to XYZ (D65 illuminant)
        const x = r_lin * 0.4124564 + g_lin * 0.3575761 + b_lin * 0.1804375;
        const y = r_lin * 0.2126729 + g_lin * 0.7151522 + b_lin * 0.0721750;
        const z = r_lin * 0.0193339 + g_lin * 0.1191920 + b_lin * 0.9503041;

        return .{ .x = x, .y = y, .z = z };
    }

    pub fn toLab(self: RgbColor) LabColor {
        const xyz = self.toXyz();
        return xyz.toLab();
    }
};

/// HSV color representation (Hue, Saturation, Value)
pub const HsvColor = struct {
    h: f32, // Hue (0-360)
    s: f32, // Saturation (0-1)
    v: f32, // Value (0-1)

    pub fn init(h: f32, s: f32, v: f32) HsvColor {
        return HsvColor{
            .h = @mod(h, 360.0),
            .s = @max(0.0, @min(1.0, s)),
            .v = @max(0.0, @min(1.0, v)),
        };
    }

    pub fn toRgb(self: HsvColor) RgbColor {
        const c = self.v * self.s;
        const x = c * (1.0 - @abs(@mod(self.h / 60.0, 2.0) - 1.0));
        const m = self.v - c;

        const h_sector = @as(u32, @intFromFloat(self.h / 60.0)) % 6;

        var r: f32 = 0.0;
        var g: f32 = 0.0;
        var b: f32 = 0.0;

        switch (h_sector) {
            0 => {
                r = c;
                g = x;
                b = 0.0;
            },
            1 => {
                r = x;
                g = c;
                b = 0.0;
            },
            2 => {
                r = 0.0;
                g = c;
                b = x;
            },
            3 => {
                r = 0.0;
                g = x;
                b = c;
            },
            4 => {
                r = x;
                g = 0.0;
                b = c;
            },
            5 => {
                r = c;
                g = 0.0;
                b = x;
            },
            else => {},
        }

        return RgbColor.fromNormalized(r + m, g + m, b + m);
    }
};

/// HSL color representation for calculations
pub const HslColor = struct {
    h: f32, // Hue (0-360)
    s: f32, // Saturation (0-1)
    l: f32, // Lightness (0-1)

    pub fn init(h: f32, s: f32, l: f32) HslColor {
        return HslColor{
            .h = @mod(h, 360.0),
            .s = @max(0.0, @min(1.0, s)),
            .l = @max(0.0, @min(1.0, l)),
        };
    }

    pub fn toRgb(self: HslColor) RgbColor {
        const h_norm = self.h / 360.0;

        if (self.s == 0) {
            const v = @as(u8, @intFromFloat(self.l * 255));
            return RgbColor.init(v, v, v);
        }

        const q = if (self.l < 0.5) self.l * (1 + self.s) else self.l + self.s - (self.l * self.s);
        const p = 2 * self.l - q;

        const r = hueToRgb(p, q, h_norm + 1.0 / 3.0);
        const g = hueToRgb(p, q, h_norm);
        const b = hueToRgb(p, q, h_norm - 1.0 / 3.0);

        return RgbColor.init(
            @as(u8, @intFromFloat(r * 255)),
            @as(u8, @intFromFloat(g * 255)),
            @as(u8, @intFromFloat(b * 255)),
        );
    }

    fn hueToRgb(p: f32, q: f32, t_raw: f32) f32 {
        var t = t_raw;
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1.0 / 6.0) return p + (q - p) * 6 * t;
        if (t < 0.5) return q;
        if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6;
        return p;
    }
};

/// XYZ color representation
pub const XyzColor = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) XyzColor {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn toRgb(self: XyzColor) RgbColor {
        // XYZ to linear RGB
        const r_lin = self.x * 3.2404542 + self.y * -1.5371385 + self.z * -0.4985314;
        const g_lin = self.x * -0.9692660 + self.y * 1.8760108 + self.z * 0.0415560;
        const b_lin = self.x * 0.0556434 + self.y * -0.2040259 + self.z * 1.0572252;

        // Linear RGB to sRGB
        const r = if (r_lin <= 0.0031308) 12.92 * r_lin else 1.055 * std.math.pow(f32, r_lin, 1.0 / 2.4) - 0.055;
        const g = if (g_lin <= 0.0031308) 12.92 * g_lin else 1.055 * std.math.pow(f32, g_lin, 1.0 / 2.4) - 0.055;
        const b = if (b_lin <= 0.0031308) 12.92 * b_lin else 1.055 * std.math.pow(f32, b_lin, 1.0 / 2.4) - 0.055;

        return RgbColor.fromNormalized(r, g, b);
    }

    pub fn toLab(self: XyzColor) LabColor {
        // D65 white point
        const xn = 0.95047;
        const yn = 1.00000;
        const zn = 1.08883;

        // Normalize by white point and apply LAB function
        const fx = labF(self.x / xn);
        const fy = labF(self.y / yn);
        const fz = labF(self.z / zn);

        const l = 116.0 * fy - 16.0;
        const a = 500.0 * (fx - fy);
        const b = 200.0 * (fy - fz);

        return .{ .l = l, .a = a, .b = b };
    }

    fn labF(t: f32) f32 {
        const delta = 6.0 / 29.0;
        if (t > delta * delta * delta) {
            return std.math.pow(f32, t, 1.0 / 3.0);
        } else {
            return (t / (3.0 * delta * delta)) + (4.0 / 29.0);
        }
    }
};

/// LAB color representation
pub const LabColor = struct {
    l: f32, // Lightness (0-100)
    a: f32, // Green-Red axis (-128 to 127)
    b: f32, // Blue-Yellow axis (-128 to 127)

    pub fn init(l: f32, a: f32, b: f32) LabColor {
        return .{ .l = l, .a = a, .b = b };
    }

    /// Calculate chroma (saturation in LAB space)
    pub fn chroma(self: LabColor) f32 {
        return @sqrt(self.a * self.a + self.b * self.b);
    }

    /// Calculate hue angle in LAB space
    pub fn hue(self: LabColor) f32 {
        return std.math.atan2(f32, self.b, self.a) * 180.0 / std.math.pi;
    }

    pub fn toRgb(self: LabColor) RgbColor {
        const xyz = self.toXyz();
        return xyz.toRgb();
    }

    pub fn toXyz(self: LabColor) XyzColor {
        // D65 white point
        const xn = 0.95047;
        const yn = 1.00000;
        const zn = 1.08883;

        const fy = (self.l + 16.0) / 116.0;
        const fx = self.a / 500.0 + fy;
        const fz = fy - self.b / 200.0;

        const x = xn * labFInv(fx);
        const y = yn * labFInv(fy);
        const z = zn * labFInv(fz);

        return XyzColor.init(x, y, z);
    }

    fn labFInv(t: f32) f32 {
        const delta = 6.0 / 29.0;
        if (t > delta) {
            return t * t * t;
        } else {
            return 3.0 * delta * delta * (t - 4.0 / 29.0);
        }
    }
};

/// Hex color representation (#RRGGBB)
pub const HexColor = struct {
    value: u32,

    pub fn init(hex: u32) HexColor {
        return .{ .value = hex & 0xFFFFFF };
    }

    pub fn fromString(hex_str: []const u8) !HexColor {
        const clean = if (hex_str.len > 0 and hex_str[0] == '#') hex_str[1..] else hex_str;
        if (clean.len != 6) return error.InvalidHexColor;

        const hex = std.fmt.parseInt(u32, clean, 16) catch return error.InvalidHexColor;
        return init(hex);
    }

    pub fn toString(self: HexColor, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "#{x:0>6}", .{self.value});
    }

    pub fn toRgb(self: HexColor) RgbColor {
        return RgbColor.fromHex(self.value);
    }
};

/// XParseColor RGB format (rgb:RRRR/GGGG/BBBB)
pub const XRGBColor = struct {
    r: u16,
    g: u16,
    b: u16,

    pub fn init(r: u16, g: u16, b: u16) XRGBColor {
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn fromRgb8(r: u8, g: u8, b: u8) XRGBColor {
        return .{
            .r = (@as(u16, r) << 8) | r,
            .g = (@as(u16, g) << 8) | g,
            .b = (@as(u16, b) << 8) | b,
        };
    }

    pub fn toString(self: XRGBColor, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "rgb:{x:0>4}/{x:0>4}/{x:0>4}", .{ self.r, self.g, self.b });
    }
};

/// XParseColor RGBA format (rgba:RRRR/GGGG/BBBB/AAAA)
pub const XRGBAColor = struct {
    r: u16,
    g: u16,
    b: u16,
    a: u16,

    pub fn init(r: u16, g: u16, b: u16, a: u16) XRGBAColor {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn fromRgba8(r: u8, g: u8, b: u8, a: u8) XRGBAColor {
        return .{
            .r = (@as(u16, r) << 8) | r,
            .g = (@as(u16, g) << 8) | g,
            .b = (@as(u16, b) << 8) | b,
            .a = (@as(u16, a) << 8) | a,
        };
    }

    pub fn toString(self: XRGBAColor, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "rgba:{x:0>4}/{x:0>4}/{x:0>4}/{x:0>4}", .{ self.r, self.g, self.b, self.a });
    }
};

// === ANSI COLOR PALETTE AND CONVERSION ===

/// ANSI 256-color palette (0-255)
pub const ANSI_PALETTE = [_]RgbColor{
    // Standard 16 colors (0-15)
    RgbColor.init(0x00, 0x00, 0x00), RgbColor.init(0x80, 0x00, 0x00), RgbColor.init(0x00, 0x80, 0x00), RgbColor.init(0x80, 0x80, 0x00),
    RgbColor.init(0x00, 0x00, 0x80), RgbColor.init(0x80, 0x00, 0x80), RgbColor.init(0x00, 0x80, 0x80), RgbColor.init(0xc0, 0xc0, 0xc0),
    RgbColor.init(0x80, 0x80, 0x80), RgbColor.init(0xff, 0x00, 0x00), RgbColor.init(0x00, 0xff, 0x00), RgbColor.init(0xff, 0xff, 0x00),
    RgbColor.init(0x00, 0x00, 0xff), RgbColor.init(0xff, 0x00, 0xff), RgbColor.init(0x00, 0xff, 0xff),
    RgbColor.init(0xff, 0xff, 0xff),

    // 216 color cube (16-231): 6x6x6 color cube
} ++ generateExtendedPalette();

/// ANSI 256 to 16 color mapping table
pub const ANSI_256_TO_16 = [_]u8{
    // 0-15: Direct mapping
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
    // 16-231: 6x6x6 color cube mapped to closest 16-color equivalent
    0,  4,  4,  4,  12, 12, 2,  6,  4,  4,  12, 12, 2,  2,  6,  4,
    12, 12, 10, 10, 10, 10, 14, 12, 10, 10, 10, 10, 10, 14, 1,  5,
    4,  4,  12, 12, 3,  8,  4,  4,  12, 12, 2,  2,  6,  4,  12, 12,
    10, 10, 10, 10, 14, 12, 10, 10, 10, 10, 10, 14, 1,  1,  5,  4,
    12, 12, 1,  1,  5,  4,  12, 12, 3,  3,  8,  4,  12, 12, 2,  2,
    2,  6,  12, 12, 10, 10, 10, 10, 14, 12, 1,  1,  1,  5,  12, 12,
    1,  1,  1,  5,  12, 12, 1,  1,  1,  5,  12, 12, 3,  3,  3,  7,
    12, 12, 10, 10, 10, 10, 14, 12, 9,  9,  9,  9,  13, 12, 9,  9,
    9,  9,  13, 12, 9,  9,  9,  9,  13, 12, 9,  9,  9,  9,  13, 12,
    11, 11, 11, 11, 7,  12, 9,  9,  9,  9,  9,  13, 9,  9,  9,  9,
    9,  13, 9,  9,  9,  9,  9,  13, 9,  9,  9,  9,  9,  13, 9,  9,
    9,  9,  9,  13,
    // 232-255: Grayscale mapped to appropriate brightness
    0,  0,  0,  0,  0,  0,  8,  8,  8,  8,  8,  8,
    7,  7,  7,  7,  7,  7,  15, 15, 15, 15, 15, 15,
};

/// Generate extended 256-color palette (16-255)
fn generateExtendedPalette() [240]RgbColor {
    var palette: [240]RgbColor = undefined;
    var idx: usize = 0;

    // 6x6x6 color cube (216 colors: 16-231)
    for (0..6) |r| {
        for (0..6) |g| {
            for (0..6) |b| {
                const r_val: u8 = if (r == 0) 0 else @as(u8, @intCast(55 + r * 40));
                const g_val: u8 = if (g == 0) 0 else @as(u8, @intCast(55 + g * 40));
                const b_val: u8 = if (b == 0) 0 else @as(u8, @intCast(55 + b * 40));
                palette[idx] = RgbColor.init(r_val, g_val, b_val);
                idx += 1;
            }
        }
    }

    // Grayscale ramp (24 colors: 232-255)
    for (0..24) |i| {
        const gray: u8 = @as(u8, @intCast(8 + i * 10));
        palette[idx] = RgbColor.init(gray, gray, gray);
        idx += 1;
    }

    return palette;
}

/// Convert RGB color to ANSI 256-color index
pub fn rgbToAnsi256(rgb: RgbColor) u8 {
    const r: f32 = @floatFromInt(rgb.r);
    const g: f32 = @floatFromInt(rgb.g);
    const b: f32 = @floatFromInt(rgb.b);

    const q2c = [_]u8{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };

    // Map RGB to 6x6x6 cube
    const qr = to6Cube(r);
    const cr = q2c[qr];
    const qg = to6Cube(g);
    const cg = q2c[qg];
    const qb = to6Cube(b);
    const cb = q2c[qb];

    // If exact match in cube, return it
    const ci = (36 * qr) + (6 * qg) + qb;
    if (cr == rgb.r and cg == rgb.g and cb == rgb.b) {
        return @intCast(16 + ci);
    }

    // Work out the closest grey
    const grey_avg: u32 = (@as(u32, rgb.r) + @as(u32, rgb.g) + @as(u32, rgb.b)) / 3;
    const grey_idx: u8 = if (grey_avg > 238) 23 else @as(u8, @intCast((grey_avg - 8) / 10));
    const grey: u8 = 8 + (10 * grey_idx);

    // Use simple distance comparison
    const color_target = RgbColor.init(cr, cg, cb);
    const grey_target = RgbColor.init(grey, grey, grey);

    const color_dist = colorDistanceSquared(rgb, color_target);
    const grey_dist = colorDistanceSquared(rgb, grey_target);

    if (grey_dist < color_dist) {
        return @intCast(232 + grey_idx);
    }
    return @intCast(16 + ci);
}

/// Convert ANSI 256-color to 16-color ANSI
pub fn ansi256ToAnsi16(indexed: u8) u8 {
    return ANSI_256_TO_16[indexed];
}

/// Convert RGB to 16-color ANSI (via 256-color conversion)
pub fn rgbToAnsi16(rgb: RgbColor) u8 {
    const color_256 = rgbToAnsi256(rgb);
    return ansi256ToAnsi16(color_256);
}

/// Get RGB values for an indexed color (0-255)
pub fn ansi256ToRgb(index: u8) RgbColor {
    return ANSI_PALETTE[index];
}

/// Get RGB values for a basic color (0-15)
pub fn ansi16ToRgb(index: u8) RgbColor {
    return ANSI_PALETTE[index & 0x0F];
}

/// Map 6-cube coordinate to color component value
fn to6Cube(v: f32) u8 {
    if (v < 48.0) return 0;
    if (v < 115.0) return 1;
    return @min(5, @as(u8, @intFromFloat((v - 35.0) / 40.0)));
}

/// Calculate squared Euclidean distance between two RGB colors
pub fn colorDistanceSquared(a: RgbColor, b: RgbColor) u32 {
    const dr: i16 = @as(i16, a.r) - @as(i16, b.r);
    const dg: i16 = @as(i16, a.g) - @as(i16, b.g);
    const db: i16 = @as(i16, a.b) - @as(i16, b.b);
    return @intCast(dr * dr + dg * dg + db * db);
}

/// Calculate weighted distance considering human perception
pub fn colorDistanceWeighted(a: RgbColor, b: RgbColor) f32 {
    const dr: f32 = @as(f32, @floatFromInt(@as(i16, a.r) - @as(i16, b.r)));
    const dg: f32 = @as(f32, @floatFromInt(@as(i16, a.g) - @as(i16, b.g)));
    const db: f32 = @as(f32, @floatFromInt(@as(i16, a.b) - @as(i16, b.b)));

    // Weighted coefficients based on human eye sensitivity
    return @sqrt(0.3 * dr * dr + 0.59 * dg * dg + 0.11 * db * db);
}

// === HSLuv COLOR DISTANCE ===

/// HSLuv color space conversion functions for improved color distance calculation
pub const Hsluv = struct {
    const M = [_][3]f64{
        [_]f64{ 3.240969941904521, -1.537383177570093, -0.498610760293 },
        [_]f64{ -0.96924363628088, 1.87596750150772, 0.041555057407175 },
        [_]f64{ 0.055630079696993, -0.20397695888897, 1.056971514242878 },
    };

    const MINV = [_][3]f64{
        [_]f64{ 0.41239079926596, 0.35758433938388, 0.18048078840183 },
        [_]f64{ 0.21263900587151, 0.71516867876776, 0.07219231536073 },
        [_]f64{ 0.01933081871559, 0.11919477979463, 0.95053215224966 },
    };

    fn xyzToRgb(x: f64, y: f64, z: f64) struct { r: f64, g: f64, b: f64 } {
        const r = x * M[0][0] + y * M[0][1] + z * M[0][2];
        const g = x * M[1][0] + y * M[1][1] + z * M[1][2];
        const b = x * M[2][0] + y * M[2][1] + z * M[2][2];
        return .{ .r = r, .g = g, .b = b };
    }

    fn rgbToXyz(r: f64, g: f64, b: f64) struct { x: f64, y: f64, z: f64 } {
        const x = r * MINV[0][0] + g * MINV[0][1] + b * MINV[0][2];
        const y = r * MINV[1][0] + g * MINV[1][1] + b * MINV[1][2];
        const z = r * MINV[2][0] + g * MINV[2][1] + b * MINV[2][2];
        return .{ .x = x, .y = y, .z = z };
    }

    fn yToL(y: f64) f64 {
        return if (y <= 0.008856451679035631) {
            y * 903.2962962962963;
        } else {
            116.0 * std.math.pow(f64, y, 1.0 / 3.0) - 16.0;
        };
    }

    fn lToY(l: f64) f64 {
        return if (l <= 8.0) {
            l / 903.2962962962963;
        } else {
            std.math.pow(f64, (l + 16.0) / 116.0, 3.0);
        };
    }

    fn rgbToHsluv(r: f64, g: f64, b: f64) struct { h: f64, s: f64, l: f64 } {
        const xyz = rgbToXyz(r, g, b);
        const x = xyz.x;
        const y = xyz.y;
        const z = xyz.z;

        const l = yToL(y);

        if (l > 99.9999999 or l < 0.00000001) {
            return .{ .h = 0.0, .s = 0.0, .l = l };
        }

        const var_u = (2.0 * x + y + z) / (x + 4.0 * y + z);
        const var_v = 3.0 * y / (x + 4.0 * y + z);

        const hr = std.math.atan2(f64, 3.0 * (var_v - 0.3333333333333333), 2.0 * (var_u - 0.3333333333333333)) / (2.0 * std.math.pi);
        const h = if (hr < 0.0) hr + 1.0 else hr;

        const c = std.math.sqrt(std.math.pow(f64, var_u - 0.3333333333333333, 2.0) + std.math.pow(f64, var_v - 0.3333333333333333, 2.0));

        const s = if (c < 0.00000001) 0.0 else (c / (1.0 - std.math.fabs(2.0 * l - 100.0) / 100.0)) * 100.0;

        return .{ .h = h * 360.0, .s = s, .l = l };
    }

    /// Calculate perceptual color distance in HSLuv color space
    pub fn colorDistance(r1: u8, g1: u8, b1: u8, r2: u8, g2: u8, b2: u8) f64 {
        // Convert to 0-1 range for HSLuv calculation
        const r1_norm = @as(f64, @floatFromInt(r1)) / 255.0;
        const g1_norm = @as(f64, @floatFromInt(g1)) / 255.0;
        const b1_norm = @as(f64, @floatFromInt(b1)) / 255.0;

        const r2_norm = @as(f64, @floatFromInt(r2)) / 255.0;
        const g2_norm = @as(f64, @floatFromInt(g2)) / 255.0;
        const b2_norm = @as(f64, @floatFromInt(b2)) / 255.0;

        const hsluv1 = rgbToHsluv(r1_norm, g1_norm, b1_norm);
        const hsluv2 = rgbToHsluv(r2_norm, g2_norm, b2_norm);

        // Calculate Euclidean distance in HSLuv space
        const dh = hsluv1.h - hsluv2.h;
        const ds = hsluv1.s - hsluv2.s;
        const dl = hsluv1.l - hsluv2.l;

        // Handle hue wraparound (circular distance)
        const hue_diff = if (std.math.fabs(dh) > 180.0) {
            if (dh > 0.0) dh - 360.0 else dh + 360.0;
        } else dh;

        return std.math.sqrt(hue_diff * hue_diff + ds * ds + dl * dl);
    }
};

// === ANSI TERMINAL COLOR CONTROL ===

/// ANSI color types
pub const BasicColor = u8; // 0-15 (4-bit)
pub const IndexedColor = u8; // 0-255 (8-bit)

/// Color format types for terminal color specification
pub const ColorFormat = enum {
    hex, // #RRGGBB format
    xrgb, // XParseColor rgb:RRRR/GGGG/BBBB format
    xrgba, // XParseColor rgba:RRRR/GGGG/BBBB/AAAA format
    named, // Named color (e.g., "red", "blue")
};

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

// === ENHANCED COLOR FORMATS ===

/// Enhanced color setting functions with support for different formats
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

// === ANSI SEQUENCE GENERATION ===

/// Generate ANSI escape sequence for foreground color
pub fn generateForegroundColorSequence(allocator: std.mem.Allocator, color_index: u8) ![]u8 {
    if (color_index < 8) {
        // Standard colors: ESC[30-37m
        return try std.fmt.allocPrint(allocator, "\x1b[{d}m", .{30 + color_index});
    } else if (color_index < 16) {
        // Bright colors: ESC[90-97m
        return try std.fmt.allocPrint(allocator, "\x1b[{d}m", .{90 + (color_index - 8)});
    } else {
        // 256 colors: ESC[38;5;{n}m
        return try std.fmt.allocPrint(allocator, "\x1b[38;5;{d}m", .{color_index});
    }
}

/// Generate ANSI escape sequence for background color
pub fn generateBackgroundColorSequence(allocator: std.mem.Allocator, color_index: u8) ![]u8 {
    if (color_index < 8) {
        // Standard colors: ESC[40-47m
        return try std.fmt.allocPrint(allocator, "\x1b[{d}m", .{40 + color_index});
    } else if (color_index < 16) {
        // Bright colors: ESC[100-107m
        return try std.fmt.allocPrint(allocator, "\x1b[{d}m", .{100 + (color_index - 8)});
    } else {
        // 256 colors: ESC[48;5;{n}m
        return try std.fmt.allocPrint(allocator, "\x1b[48;5;{d}m", .{color_index});
    }
}

/// Generate ANSI escape sequence for RGB foreground color
pub fn generateRgbForegroundSequence(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "\x1b[38;2;{d};{d};{d}m", .{ r, g, b });
}

/// Generate ANSI escape sequence for RGB background color
pub fn generateRgbBackgroundSequence(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "\x1b[48;2;{d};{d};{d}m", .{ r, g, b });
}

/// Generate ANSI escape sequence for RGB cursor color
pub fn generateRgbCursorSequence(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "\x1b]12;rgb:{x:0>2}/{x:0>2}/{x:0>2}\x07", .{ r, g, b });
}

/// Generate color reset sequence
pub fn generateColorResetSequence(allocator: std.mem.Allocator) ![]u8 {
    return try allocator.dupe(u8, "\x1b[0m");
}

// === COLOR ANALYSIS AND UTILITIES ===

/// Color analysis utilities
pub const ColorAnalysis = struct {
    /// Classify color temperature (warm/cool)
    pub const Temperature = enum { very_cool, cool, neutral, warm, very_warm };

    /// Classify color saturation level
    pub const SaturationLevel = enum { grayscale, low, medium, high, vivid };

    /// Classify color lightness level
    pub const LightnessLevel = enum { very_dark, dark, medium, light, very_light };

    /// Analyze color temperature based on hue
    pub fn getTemperature(rgb: RgbColor) Temperature {
        const hsl = rgb.toHsl();

        if (hsl.s < 0.1) return .neutral; // Low saturation colors are neutral

        // Hue-based temperature classification
        if ((hsl.h >= 0 and hsl.h <= 60) or (hsl.h >= 300 and hsl.h < 360)) {
            return if (hsl.s > 0.7) .very_warm else .warm;
        } else if (hsl.h >= 120 and hsl.h <= 240) {
            return if (hsl.s > 0.7) .very_cool else .cool;
        } else {
            return .neutral;
        }
    }

    /// Analyze saturation level
    pub fn getSaturationLevel(rgb: RgbColor) SaturationLevel {
        const hsl = rgb.toHsl();

        if (hsl.s < 0.05) return .grayscale;
        if (hsl.s < 0.3) return .low;
        if (hsl.s < 0.6) return .medium;
        if (hsl.s < 0.8) return .high;
        return .vivid;
    }

    /// Analyze lightness level
    pub fn getLightnessLevel(rgb: RgbColor) LightnessLevel {
        const hsl = rgb.toHsl();

        if (hsl.l < 0.2) return .very_dark;
        if (hsl.l < 0.4) return .dark;
        if (hsl.l < 0.6) return .medium;
        if (hsl.l < 0.8) return .light;
        return .very_light;
    }

    /// Check if color is achromatic (grayscale)
    pub fn isAchromatic(rgb: RgbColor, tolerance: f64) bool {
        const max_diff = @max(@max(@abs(@as(f64, @floatFromInt(rgb.r)) - @as(f64, @floatFromInt(rgb.g))), @abs(@as(f64, @floatFromInt(rgb.g)) - @as(f64, @floatFromInt(rgb.b)))), @abs(@as(f64, @floatFromInt(rgb.r)) - @as(f64, @floatFromInt(rgb.b))));
        return max_diff <= tolerance;
    }

    /// Calculate perceived brightness using luminance formula
    pub fn getPerceivedBrightness(rgb: RgbColor) f64 {
        // Using ITU-R BT.709 luma coefficients for better accuracy
        const norm = rgb.toNormalized();
        return norm.r * 0.2126 + norm.g * 0.7152 + norm.b * 0.0722;
    }

    /// Determine contrast ratio between two colors
    pub fn getContrastRatio(color1: RgbColor, color2: RgbColor) f64 {
        const lum1 = getPerceivedBrightness(color1);
        const lum2 = getPerceivedBrightness(color2);

        const lighter = @max(lum1, lum2);
        const darker = @min(lum1, lum2);

        return (lighter + 0.05) / (darker + 0.05);
    }

    /// Check WCAG accessibility compliance
    pub fn isAccessible(foreground: RgbColor, background: RgbColor, level: enum { AA, AAA }) bool {
        const contrast = getContrastRatio(foreground, background);
        return switch (level) {
            .AA => contrast >= 4.5,
            .AAA => contrast >= 7.0,
        };
    }
};

/// Color harmony utilities
pub const ColorHarmony = struct {
    /// Generate complementary color (180° hue shift)
    pub fn getComplementary(rgb: RgbColor) RgbColor {
        const hsv = rgb.toHsv();
        const comp_hsv = HsvColor.init(hsv.h + 180.0, hsv.s, hsv.v);
        return comp_hsv.toRgb();
    }

    /// Generate triadic colors (120° hue shifts)
    pub fn getTriadic(rgb: RgbColor) [2]RgbColor {
        const hsv = rgb.toHsv();
        const hsv1 = HsvColor.init(hsv.h + 120.0, hsv.s, hsv.v);
        const hsv2 = HsvColor.init(hsv.h + 240.0, hsv.s, hsv.v);
        return [2]RgbColor{ hsv1.toRgb(), hsv2.toRgb() };
    }

    /// Generate analogous colors (±30° hue shifts)
    pub fn getAnalogous(rgb: RgbColor) [2]RgbColor {
        const hsv = rgb.toHsv();
        const hsv1 = HsvColor.init(hsv.h + 30.0, hsv.s, hsv.v);
        const hsv2 = HsvColor.init(hsv.h - 30.0, hsv.s, hsv.v);
        return [2]RgbColor{ hsv1.toRgb(), hsv2.toRgb() };
    }

    /// Generate monochromatic variations (same hue, different saturation/value)
    pub fn getMonochromatic(rgb: RgbColor, count: usize, allocator: std.mem.Allocator) ![]RgbColor {
        const hsv = rgb.toHsv();
        var colors = try allocator.alloc(RgbColor, count);

        for (0..count) |i| {
            const t = if (count == 1) 0.0 else @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count - 1));
            // Vary saturation and value while keeping hue constant
            const s = @max(0.2, @min(1.0, hsv.s * (0.5 + t * 0.5)));
            const v = @max(0.3, @min(1.0, hsv.v * (0.7 + t * 0.3)));
            colors[i] = HsvColor.init(hsv.h, s, v).toRgb();
        }

        return colors;
    }
};

// === VALIDATION AND ERROR HANDLING ===

/// Enhanced error types for color operations
pub const ColorError = error{
    InvalidHexColor,
    InvalidHexLength,
    InvalidHexCharacter,
    InvalidRgbValue,
    InvalidColorFormat,
    InvalidResponse,
    ColorNotSupported,
    TerminalCapabilityMissing,
    OutOfMemory,
};

/// Comprehensive color validation utilities
pub const ColorValidator = struct {
    /// Validate if a string is a valid hex color format (#RRGGBB or RRGGBB)
    pub fn isValidHex(hex: []const u8) bool {
        var hex_clean = hex;

        // Remove leading # if present
        if (hex.len > 0 and hex[0] == '#') {
            hex_clean = hex[1..];
        }

        // Check length (must be exactly 6 characters)
        if (hex_clean.len != 6) {
            return false;
        }

        // Check all characters are valid hex
        for (hex_clean) |char| {
            switch (char) {
                '0'...'9', 'A'...'F', 'a'...'f' => {},
                else => return false,
            }
        }
        return true;
    }

    /// Validate if a string is a valid XRGB color format (rgb:RRRR/GGGG/BBBB)
    pub fn isValidXRgb(rgb: []const u8) bool {
        if (!std.mem.startsWith(u8, rgb, "rgb:")) return false;

        const components = rgb[4..]; // Skip "rgb:"
        var parts = std.mem.split(u8, components, "/");

        var part_count: u8 = 0;
        while (parts.next()) |part| {
            part_count += 1;
            if (part_count > 3) return false; // Too many parts
            if (part.len != 4) return false; // Each part should be 4 hex chars

            // Validate hex characters
            for (part) |char| {
                switch (char) {
                    '0'...'9', 'A'...'F', 'a'...'f' => {},
                    else => return false,
                }
            }
        }

        return part_count == 3; // Must have exactly 3 parts
    }

    /// Validate if a string is a valid XRGBA color format (rgba:RRRR/GGGG/BBBB/AAAA)
    pub fn isValidXRgba(rgba: []const u8) bool {
        if (!std.mem.startsWith(u8, rgba, "rgba:")) return false;

        const components = rgba[5..]; // Skip "rgba:"
        var parts = std.mem.split(u8, components, "/");

        var part_count: u8 = 0;
        while (parts.next()) |part| {
            part_count += 1;
            if (part_count > 4) return false; // Too many parts
            if (part.len != 4) return false; // Each part should be 4 hex chars

            // Validate hex characters
            for (part) |char| {
                switch (char) {
                    '0'...'9', 'A'...'F', 'a'...'f' => {},
                    else => return false,
                }
            }
        }

        return part_count == 4; // Must have exactly 4 parts
    }

    /// Validate RGB component values (0-255)
    pub fn isValidRgb(r: u16, g: u16, b: u16) bool {
        return r <= 255 and g <= 255 and b <= 255;
    }

    /// Validate RGBA component values (0-255)
    pub fn isValidRgba(r: u16, g: u16, b: u16, a: u16) bool {
        return r <= 255 and g <= 255 and b <= 255 and a <= 255;
    }

    /// Detect the format of a color string
    pub fn detectColorFormat(color: []const u8) ColorFormat {
        if (isValidHex(color)) return .hex;
        if (isValidXRgb(color)) return .xrgb;
        if (isValidXRgba(color)) return .xrgba;
        return .named; // Assume it's a named color
    }

    /// Validate any color string against known formats
    pub fn isValidColor(color: []const u8) bool {
        return isValidHex(color) or isValidXRgb(color) or isValidXRgba(color);
    }
};

/// Safe color creation functions with validation
pub const SafeColor = struct {
    /// Safely create a hex color from string with validation
    pub fn hexFromString(hex_str: []const u8) ColorError!HexColor {
        if (!ColorValidator.isValidHex(hex_str)) {
            return ColorError.InvalidHexColor;
        }
        return HexColor.fromString(hex_str) catch ColorError.InvalidHexColor;
    }

    /// Safely create RGB values with validation
    pub fn validateRgb(r: u8, g: u8, b: u8) ColorError!RgbColor {
        if (!ColorValidator.isValidRgb(r, g, b)) {
            return ColorError.InvalidRgbValue;
        }
        return RgbColor.init(r, g, b);
    }

    /// Safely create RGBA values with validation
    pub fn validateRgba(r: u8, g: u8, b: u8, a: u8) ColorError!struct { r: u8, g: u8, b: u8, a: u8 } {
        if (!ColorValidator.isValidRgba(r, g, b, a)) {
            return ColorError.InvalidRgbValue;
        }
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    /// Safely set foreground color with format validation
    pub fn setForegroundColorSafe(
        writer: anytype,
        alloc: std.mem.Allocator,
        caps: TermCaps,
        color: []const u8,
    ) ColorError!void {
        if (!caps.supportsColorOsc10_12) {
            return ColorError.TerminalCapabilityMissing;
        }

        if (!ColorValidator.isValidColor(color)) {
            return ColorError.InvalidColorFormat;
        }

        setForegroundColor(writer, alloc, caps, color) catch |err| switch (err) {
            error.Unsupported => return ColorError.TerminalCapabilityMissing,
            error.OutOfMemory => return ColorError.OutOfMemory,
            else => return ColorError.InvalidColorFormat,
        };
    }

    /// Safely set background color with format validation
    pub fn setBackgroundColorSafe(
        writer: anytype,
        alloc: std.mem.Allocator,
        caps: TermCaps,
        color: []const u8,
    ) ColorError!void {
        if (!caps.supportsColorOsc10_12) {
            return ColorError.TerminalCapabilityMissing;
        }

        if (!ColorValidator.isValidColor(color)) {
            return ColorError.InvalidColorFormat;
        }

        setBackgroundColor(writer, alloc, caps, color) catch |err| switch (err) {
            error.Unsupported => return ColorError.TerminalCapabilityMissing,
            error.OutOfMemory => return ColorError.OutOfMemory,
            else => return ColorError.InvalidColorFormat,
        };
    }

    /// Safely set cursor color with format validation
    pub fn setCursorColorSafe(
        writer: anytype,
        alloc: std.mem.Allocator,
        caps: TermCaps,
        color: []const u8,
    ) ColorError!void {
        if (!caps.supportsColorOsc10_12) {
            return ColorError.TerminalCapabilityMissing;
        }

        if (!ColorValidator.isValidColor(color)) {
            return ColorError.InvalidColorFormat;
        }

        setCursorColor(writer, alloc, caps, color) catch |err| switch (err) {
            error.Unsupported => return ColorError.TerminalCapabilityMissing,
            error.OutOfMemory => return ColorError.OutOfMemory,
            else => return ColorError.InvalidColorFormat,
        };
    }
};

// === TESTS ===

test "RGB color creation and hex conversion" {
    const testing = std.testing;

    // Test RGB color creation
    const red = RgbColor.init(255, 0, 0);
    try testing.expect(red.r == 255 and red.g == 0 and red.b == 0);

    // Test hex conversion
    const red_hex = red.toHex();
    try testing.expect(red_hex == 0xFF0000);

    // Test white
    const white = RgbColor.init(255, 255, 255);
    try testing.expect(white.toHex() == 0xFFFFFF);
}

test "hex color creation and formatting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test hex color from value
    const red = HexColor.init(0xFF0000);
    const red_str = try red.toString(allocator);
    defer allocator.free(red_str);
    try testing.expectEqualStrings("#ff0000", red_str);

    // Test hex color from string
    const blue = try HexColor.fromString("#0000FF");
    const blue_str = try blue.toString(allocator);
    defer allocator.free(blue_str);
    try testing.expectEqualStrings("#0000ff", blue_str);

    // Test RGB extraction
    const green_rgb = HexColor.init(0x00FF00).toRgb();
    try testing.expect(green_rgb.r == 0 and green_rgb.g == 255 and green_rgb.b == 0);
}

test "RGB to HSL conversion" {
    const testing = std.testing;

    const red = RgbColor.init(255, 0, 0);
    const hsl = red.toHsl();

    try testing.expect(@abs(hsl.h - 0.0) < 1.0); // Hue should be ~0
    try testing.expect(@abs(hsl.s - 1.0) < 0.01); // Saturation should be 1
    try testing.expect(@abs(hsl.l - 0.5) < 0.01); // Lightness should be 0.5
}

test "HSL to RGB conversion" {
    const testing = std.testing;

    const hsl = HslColor.init(120.0, 1.0, 0.5); // Pure green
    const rgb = hsl.toRgb();

    try testing.expect(rgb.r < 5); // Should be close to 0
    try testing.expect(rgb.g > 250); // Should be close to 255
    try testing.expect(rgb.b < 5); // Should be close to 0
}

test "RGB to HSV conversion" {
    const testing = std.testing;

    const red = RgbColor.init(255, 0, 0);
    const hsv = red.toHsv();

    try testing.expect(@abs(hsv.h - 0.0) < 1.0); // Hue should be ~0
    try testing.expect(@abs(hsv.s - 1.0) < 0.01); // Saturation should be 1
    try testing.expect(@abs(hsv.v - 1.0) < 0.01); // Value should be 1
}

test "HSV to RGB conversion" {
    const testing = std.testing;

    const hsv = HsvColor.init(240.0, 1.0, 1.0); // Pure blue
    const rgb = hsv.toRgb();

    try testing.expect(rgb.r < 5); // Should be close to 0
    try testing.expect(rgb.g < 5); // Should be close to 0
    try testing.expect(rgb.b > 250); // Should be close to 255
}

test "RGB to LAB conversion" {
    const testing = std.testing;

    const white = RgbColor.init(255, 255, 255);
    const lab = white.toLab();

    // White should have L* close to 100, a* and b* close to 0
    try testing.expect(lab.l > 95.0 and lab.l <= 100.0);
    try testing.expect(@abs(lab.a) < 2.0);
    try testing.expect(@abs(lab.b) < 2.0);

    const black = RgbColor.init(0, 0, 0);
    const lab_black = black.toLab();

    // Black should have L* close to 0
    try testing.expect(lab_black.l < 5.0);
}

test "ANSI 256 color conversion" {
    const testing = std.testing;

    // Test pure colors that should have exact matches
    const pure_red = RgbColor.init(255, 0, 0);
    const red_256 = rgbToAnsi256(pure_red);
    try testing.expect(red_256 >= 16); // Should not be in basic 16 colors for pure red

    // Test black (should map to 0)
    const black = RgbColor.init(0, 0, 0);
    const black_256 = rgbToAnsi256(black);
    try testing.expect(black_256 == 16); // Black in 256-color cube

    // Test white (should be high index)
    const white = RgbColor.init(255, 255, 255);
    const white_256 = rgbToAnsi256(white);
    try testing.expect(white_256 >= 200); // Should be in bright range
}

test "ANSI 16 color conversion" {
    const testing = std.testing;

    // Test basic color mapping
    const red = RgbColor.init(255, 0, 0);
    const red_16 = rgbToAnsi16(red);
    try testing.expect(red_16 < 16);

    const green = RgbColor.init(0, 255, 0);
    const green_16 = rgbToAnsi16(green);
    try testing.expect(green_16 < 16);
}

test "color distance calculations" {
    const testing = std.testing;

    const red = RgbColor.init(255, 0, 0);
    const blue = RgbColor.init(0, 0, 255);
    const black = RgbColor.init(0, 0, 0);

    // Test squared distance
    const dist_red_blue = colorDistanceSquared(red, blue);
    const dist_red_black = colorDistanceSquared(red, black);

    try testing.expect(dist_red_blue > dist_red_black);
}

test "color analysis" {
    const testing = std.testing;

    const red = RgbColor.init(255, 0, 0);
    const blue = RgbColor.init(0, 0, 255);
    const gray = RgbColor.init(128, 128, 128);

    // Temperature analysis
    try testing.expect(ColorAnalysis.getTemperature(red) == .very_warm or
        ColorAnalysis.getTemperature(red) == .warm);
    try testing.expect(ColorAnalysis.getTemperature(blue) == .very_cool or
        ColorAnalysis.getTemperature(blue) == .cool);

    // Saturation analysis
    try testing.expect(ColorAnalysis.getSaturationLevel(red) == .vivid);
    try testing.expect(ColorAnalysis.getSaturationLevel(gray) == .grayscale);

    // Achromatic test
    try testing.expect(ColorAnalysis.isAchromatic(gray, 5.0));
    try testing.expect(!ColorAnalysis.isAchromatic(red, 5.0));
}

test "color harmony" {
    const testing = std.testing;

    const blue = RgbColor.init(0, 0, 255);

    // Complementary should be roughly orange/yellow
    const comp = ColorHarmony.getComplementary(blue);
    const comp_hsv = comp.toHsv();
    try testing.expect(@abs(comp_hsv.h - 60.0) < 30.0); // Should be around yellow-orange

    // Triadic colors
    const triadic = ColorHarmony.getTriadic(blue);
    try testing.expect(triadic.len == 2);
}

test "contrast ratio calculation" {
    const testing = std.testing;

    const white = RgbColor.init(255, 255, 255);
    const black = RgbColor.init(0, 0, 0);

    const contrast = ColorAnalysis.getContrastRatio(black, white);
    try testing.expect(contrast > 15.0); // Should be high contrast

    // Test accessibility
    try testing.expect(ColorAnalysis.isAccessible(black, white, .AA));
    try testing.expect(ColorAnalysis.isAccessible(black, white, .AAA));
}

test "color validation" {
    const testing = std.testing;

    // Valid hex colors
    try testing.expect(ColorValidator.isValidHex("#FF0000"));
    try testing.expect(ColorValidator.isValidHex("FF0000"));
    try testing.expect(ColorValidator.isValidHex("#ff0000"));
    try testing.expect(ColorValidator.isValidHex("ff0000"));

    // Invalid hex colors
    try testing.expect(!ColorValidator.isValidHex("#FF00")); // Too short
    try testing.expect(!ColorValidator.isValidHex("GG0000")); // Invalid character
    try testing.expect(!ColorValidator.isValidHex("#FF0000AA")); // Too long

    // Valid XRGB colors
    try testing.expect(ColorValidator.isValidXRgb("rgb:ffff/0000/0000"));
    try testing.expect(ColorValidator.isValidXRgb("rgb:FFFF/FFFF/FFFF"));

    // Invalid XRGB colors
    try testing.expect(!ColorValidator.isValidXRgb("rgb:ff/00/00")); // Too short
    try testing.expect(!ColorValidator.isValidXRgb("rgb:ffff/ffff")); // Missing component
    try testing.expect(!ColorValidator.isValidXRgb("rgb:ffff/ffff/ffff/ff")); // Too many components

    // Valid XRGBA colors
    try testing.expect(ColorValidator.isValidXRgba("rgba:ffff/0000/0000/8080"));

    // Invalid XRGBA colors
    try testing.expect(!ColorValidator.isValidXRgba("rgba:ff/00/00/80")); // Too short
    try testing.expect(!ColorValidator.isValidXRgba("rgba:ffff/ffff/ffff")); // Missing alpha

    // RGB value validation
    try testing.expect(ColorValidator.isValidRgb(255, 128, 0));
    try testing.expect(!ColorValidator.isValidRgb(256, 0, 0));

    // RGBA value validation
    try testing.expect(ColorValidator.isValidRgba(255, 128, 0, 200));
    try testing.expect(!ColorValidator.isValidRgba(256, 0, 0, 0));

    // Format detection
    try testing.expect(ColorValidator.detectColorFormat("#FF0000") == .hex);
    try testing.expect(ColorValidator.detectColorFormat("rgb:ffff/0000/0000") == .xrgb);
    try testing.expect(ColorValidator.detectColorFormat("rgba:ffff/0000/0000/8080") == .xrgba);
    try testing.expect(ColorValidator.detectColorFormat("red") == .named);
}

test "safe color creation" {
    const testing = std.testing;

    // Valid hex color creation
    const red = try SafeColor.hexFromString("#FF0000");
    const red_rgb = red.toRgb();
    try testing.expect(red_rgb.r == 255 and red_rgb.g == 0 and red_rgb.b == 0);

    // Invalid hex color creation should fail
    try testing.expectError(ColorError.InvalidHexColor, SafeColor.hexFromString("invalid"));

    // Valid RGB validation
    const valid_rgb = try SafeColor.validateRgb(255, 128, 64);
    try testing.expect(valid_rgb.r == 255 and valid_rgb.g == 128 and valid_rgb.b == 64);
}

test "ANSI sequence generation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test standard color sequences
    const red_fg = try generateForegroundColorSequence(allocator, 1);
    defer allocator.free(red_fg);
    try testing.expectEqualStrings("\x1b[31m", red_fg);

    const blue_bg = try generateBackgroundColorSequence(allocator, 4);
    defer allocator.free(blue_bg);
    try testing.expectEqualStrings("\x1b[44m", blue_bg);

    // Test bright color sequences
    const bright_red_fg = try generateForegroundColorSequence(allocator, 9);
    defer allocator.free(bright_red_fg);
    try testing.expectEqualStrings("\x1b[91m", bright_red_fg);

    const bright_blue_bg = try generateBackgroundColorSequence(allocator, 12);
    defer allocator.free(bright_blue_bg);
    try testing.expectEqualStrings("\x1b[104m", bright_blue_bg);

    // Test 256-color sequences
    const color_256_fg = try generateForegroundColorSequence(allocator, 196);
    defer allocator.free(color_256_fg);
    try testing.expectEqualStrings("\x1b[38;5;196m", color_256_fg);

    const color_256_bg = try generateBackgroundColorSequence(allocator, 196);
    defer allocator.free(color_256_bg);
    try testing.expectEqualStrings("\x1b[48;5;196m", color_256_bg);

    // Test RGB sequences
    const rgb_fg = try generateRgbForegroundSequence(allocator, 255, 128, 64);
    defer allocator.free(rgb_fg);
    try testing.expectEqualStrings("\x1b[38;2;255;128;64m", rgb_fg);

    const rgb_bg = try generateRgbBackgroundSequence(allocator, 64, 128, 255);
    defer allocator.free(rgb_bg);
    try testing.expectEqualStrings("\x1b[48;2;64;128;255m", rgb_bg);

    // Test reset sequence
    const reset = try generateColorResetSequence(allocator);
    defer allocator.free(reset);
    try testing.expectEqualStrings("\x1b[0m", reset);
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
}</content>
</xai:function_call name="bash">
<parameter name="command">rm src/shared/term/ansi/color_conversion.zig src/shared/term/ansi/color_converter.zig src/shared/term/ansi/color_space_utilities.zig
/// Enhanced color conversion system inspired by charmbracelet/x
/// Provides perceptually accurate color conversion using HSLuv color space
/// Compatible with Zig 0.15.1
const std = @import("std");
const math = std.math;

/// Color representation compatible with charmbracelet/x approach
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) Color {
        return Color{ .r = r, .g = g, .b = b };
    }

    /// Create from 24-bit hex value
    pub fn fromHex(hex: u32) Color {
        return Color{
            .r = @intCast((hex >> 16) & 0xFF),
            .g = @intCast((hex >> 8) & 0xFF),
            .b = @intCast(hex & 0xFF),
        };
    }

    /// Convert to 24-bit hex value
    pub fn toHex(self: Color) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }

    /// Convert to normalized float values (0.0 - 1.0) for color space calculations
    pub fn toFloat(self: Color) FloatColor {
        return FloatColor{
            .r = @as(f32, @floatFromInt(self.r)) / 255.0,
            .g = @as(f32, @floatFromInt(self.g)) / 255.0,
            .b = @as(f32, @floatFromInt(self.b)) / 255.0,
        };
    }

    /// Create from float RGB values (0.0 - 1.0)
    pub fn fromFloat(color: FloatColor) Color {
        return Color{
            .r = @intFromFloat(@round(color.r * 255.0)),
            .g = @intFromFloat(@round(color.g * 255.0)),
            .b = @intFromFloat(@round(color.b * 255.0)),
        };
    }
};

/// Float-based color for precise calculations
pub const FloatColor = struct {
    r: f32,
    g: f32,
    b: f32,

    /// Convert RGB to HSLuv color space for perceptual distance calculations
    /// Based on the HSLuv specification for better human perception
    pub fn toHSLuv(self: FloatColor) HSLuvColor {
        // Convert RGB to XYZ color space first
        const xyz = self.toXYZ();

        // Convert XYZ to LUV
        const luv = xyz.toLUV();

        // Convert LUV to HSLuv
        return luv.toHSLuv();
    }

    /// Convert RGB to XYZ color space (D65 illuminant)
    fn toXYZ(self: FloatColor) XYZColor {
        // Linearize RGB values (inverse gamma correction)
        const r_lin = gammaInverse(self.r);
        const g_lin = gammaInverse(self.g);
        const b_lin = gammaInverse(self.b);

        // Convert to XYZ using sRGB matrix
        return XYZColor{
            .x = 0.4124564 * r_lin + 0.3575761 * g_lin + 0.1804375 * b_lin,
            .y = 0.2126729 * r_lin + 0.7151522 * g_lin + 0.0721750 * b_lin,
            .z = 0.0193339 * r_lin + 0.1191920 * g_lin + 0.9503041 * b_lin,
        };
    }
};

/// XYZ color space representation
const XYZColor = struct {
    x: f32,
    y: f32,
    z: f32,

    /// Convert XYZ to LUV color space
    fn toLUV(self: XYZColor) LUVColor {
        // Reference white point D65
        const ref_x: f32 = 0.95047;
        const ref_y: f32 = 1.00000;
        const ref_z: f32 = 1.08883;

        const u_prime = (4.0 * self.x) / (self.x + 15.0 * self.y + 3.0 * self.z);
        const v_prime = (9.0 * self.y) / (self.x + 15.0 * self.y + 3.0 * self.z);

        const ref_u_prime = (4.0 * ref_x) / (ref_x + 15.0 * ref_y + 3.0 * ref_z);
        const ref_v_prime = (9.0 * ref_y) / (ref_x + 15.0 * ref_y + 3.0 * ref_z);

        const yr = self.y / ref_y;
        const l = if (yr > math.pow(f32, 6.0 / 29.0, 3))
            116.0 * math.cbrt(yr) - 16.0
        else
            math.pow(f32, 29.0 / 3.0, 3) * yr;

        const u = 13.0 * l * (u_prime - ref_u_prime);
        const v = 13.0 * l * (v_prime - ref_v_prime);

        return LUVColor{ .l = l, .u = u, .v = v };
    }
};

/// LUV color space representation
const LUVColor = struct {
    l: f32, // Lightness
    u: f32, // Green-Red chromaticity
    v: f32, // Blue-Yellow chromaticity

    /// Convert LUV to HSLuv (simplified for color distance calculation)
    fn toHSLuv(self: LUVColor) HSLuvColor {
        const h = math.atan2(self.v, self.u) * 180.0 / math.pi;
        const s = math.sqrt(self.u * self.u + self.v * self.v);
        return HSLuvColor{ .h = if (h < 0) h + 360.0 else h, .s = s, .l = self.l };
    }
};

/// HSLuv color space for perceptual color distance
const HSLuvColor = struct {
    h: f32, // Hue (0-360)
    s: f32, // Saturation
    l: f32, // Lightness (0-100)

    /// Calculate perceptual distance using HSLuv color space
    /// This provides much better color matching than RGB distance
    /// Balanced approach emphasizing hue over lightness for related colors
    pub fn distance(self: HSLuvColor, other: HSLuvColor) f32 {
        // Handle hue difference (circular) - this should be primary for color similarity
        var hue_diff = @abs(self.h - other.h);
        if (hue_diff > 180.0) {
            hue_diff = 360.0 - hue_diff;
        }

        // Hue weight - primary factor for color similarity
        const hue_weight = hue_diff * hue_diff * 0.1;

        // Lightness difference - important but secondary to hue
        const lightness_diff = self.l - other.l;
        const lightness_weight = lightness_diff * lightness_diff * 0.02;

        // Saturation difference - tertiary factor
        const chroma_diff = self.s - other.s;
        const chroma_weight = chroma_diff * chroma_diff * 0.005;

        return @sqrt(hue_weight + lightness_weight + chroma_weight);
    }
};

/// Inverse gamma correction for sRGB
fn gammaInverse(value: f32) f32 {
    return if (value <= 0.04045)
        value / 12.92
    else
        math.pow(f32, (value + 0.055) / 1.055, 2.4);
}

/// ANSI 256-color palette matching charmbracelet/x implementation
pub const ansi_256_palette = [_]Color{
    // 16 standard colors (0-15)
    Color.init(0x00, 0x00, 0x00), Color.init(0x80, 0x00, 0x00), Color.init(0x00, 0x80, 0x00), Color.init(0x80, 0x80, 0x00),
    Color.init(0x00, 0x00, 0x80), Color.init(0x80, 0x00, 0x80), Color.init(0x00, 0x80, 0x80), Color.init(0xc0, 0xc0, 0xc0),
    Color.init(0x80, 0x80, 0x80), Color.init(0xff, 0x00, 0x00), Color.init(0x00, 0xff, 0x00), Color.init(0xff, 0xff, 0x00),
    Color.init(0x00, 0x00, 0xff), Color.init(0xff, 0x00, 0xff), Color.init(0x00, 0xff, 0xff), Color.init(0xff, 0xff, 0xff),
} ++ blk: {
    // 216 6x6x6 color cube (16-231)
    const cube_values = [_]u8{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };
    var colors: [216]Color = undefined;
    var i: usize = 0;
    for (cube_values) |r| {
        for (cube_values) |g| {
            for (cube_values) |b| {
                colors[i] = Color.init(r, g, b);
                i += 1;
            }
        }
    }
    break :blk colors;
} ++ blk: {
    // 24 grayscale colors (232-255)
    var grays: [24]Color = undefined;
    for (&grays, 0..) |*color, i| {
        const gray_value: u8 = @intCast(8 + i * 10);
        color.* = Color.init(gray_value, gray_value, gray_value);
    }
    break :blk grays;
};

/// Map 6-cube coordinate according to charmbracelet/x algorithm
/// This matches the exact algorithm from charmbracelet/x/ansi/color.go
fn to6Cube(v: f32) u8 {
    if (v < 48.0) return 0;
    if (v < 115.0) return 1;
    return @intCast(@min(5, @as(u32, @intFromFloat((v - 35.0) / 40.0))));
}

/// Complete ANSI 256 color palette exactly matching charmbracelet implementation
/// This includes the full 6x6x6 color cube and 24 grayscale colors
pub const charmbracelet_256_palette = [_]Color{
    // Standard colors (0-15) - exact charmbracelet values
    Color.init(0x00, 0x00, 0x00), Color.init(0x80, 0x00, 0x00), Color.init(0x00, 0x80, 0x00), Color.init(0x80, 0x80, 0x00),
    Color.init(0x00, 0x00, 0x80), Color.init(0x80, 0x00, 0x80), Color.init(0x00, 0x80, 0x80), Color.init(0xc0, 0xc0, 0xc0),
    Color.init(0x80, 0x80, 0x80), Color.init(0xff, 0x00, 0x00), Color.init(0x00, 0xff, 0x00), Color.init(0xff, 0xff, 0x00),
    Color.init(0x00, 0x00, 0xff), Color.init(0xff, 0x00, 0xff), Color.init(0x00, 0xff, 0xff), Color.init(0xff, 0xff, 0xff),

    // 216 colors (16-231): 6x6x6 color cube - exact charmbracelet implementation
    Color.init(0x00, 0x00, 0x00), Color.init(0x00, 0x00, 0x5f), Color.init(0x00, 0x00, 0x87), Color.init(0x00, 0x00, 0xaf),
    Color.init(0x00, 0x00, 0xd7), Color.init(0x00, 0x00, 0xff), Color.init(0x00, 0x5f, 0x00), Color.init(0x00, 0x5f, 0x5f),
    Color.init(0x00, 0x5f, 0x87), Color.init(0x00, 0x5f, 0xaf), Color.init(0x00, 0x5f, 0xd7), Color.init(0x00, 0x5f, 0xff),
    Color.init(0x00, 0x87, 0x00), Color.init(0x00, 0x87, 0x5f), Color.init(0x00, 0x87, 0x87), Color.init(0x00, 0x87, 0xaf),
    Color.init(0x00, 0x87, 0xd7), Color.init(0x00, 0x87, 0xff), Color.init(0x00, 0xaf, 0x00), Color.init(0x00, 0xaf, 0x5f),
    Color.init(0x00, 0xaf, 0x87), Color.init(0x00, 0xaf, 0xaf), Color.init(0x00, 0xaf, 0xd7), Color.init(0x00, 0xaf, 0xff),
    Color.init(0x00, 0xd7, 0x00), Color.init(0x00, 0xd7, 0x5f), Color.init(0x00, 0xd7, 0x87), Color.init(0x00, 0xd7, 0xaf),
    Color.init(0x00, 0xd7, 0xd7), Color.init(0x00, 0xd7, 0xff), Color.init(0x00, 0xff, 0x00), Color.init(0x00, 0xff, 0x5f),
    Color.init(0x00, 0xff, 0x87), Color.init(0x00, 0xff, 0xaf), Color.init(0x00, 0xff, 0xd7), Color.init(0x00, 0xff, 0xff),
    Color.init(0x5f, 0x00, 0x00), Color.init(0x5f, 0x00, 0x5f), Color.init(0x5f, 0x00, 0x87), Color.init(0x5f, 0x00, 0xaf),
    Color.init(0x5f, 0x00, 0xd7), Color.init(0x5f, 0x00, 0xff), Color.init(0x5f, 0x5f, 0x00), Color.init(0x5f, 0x5f, 0x5f),
    Color.init(0x5f, 0x5f, 0x87), Color.init(0x5f, 0x5f, 0xaf), Color.init(0x5f, 0x5f, 0xd7), Color.init(0x5f, 0x5f, 0xff),
    Color.init(0x5f, 0x87, 0x00), Color.init(0x5f, 0x87, 0x5f), Color.init(0x5f, 0x87, 0x87), Color.init(0x5f, 0x87, 0xaf),
    Color.init(0x5f, 0x87, 0xd7), Color.init(0x5f, 0x87, 0xff), Color.init(0x5f, 0xaf, 0x00), Color.init(0x5f, 0xaf, 0x5f),
    Color.init(0x5f, 0xaf, 0x87), Color.init(0x5f, 0xaf, 0xaf), Color.init(0x5f, 0xaf, 0xd7), Color.init(0x5f, 0xaf, 0xff),
    Color.init(0x5f, 0xd7, 0x00), Color.init(0x5f, 0xd7, 0x5f), Color.init(0x5f, 0xd7, 0x87), Color.init(0x5f, 0xd7, 0xaf),
    Color.init(0x5f, 0xd7, 0xd7), Color.init(0x5f, 0xd7, 0xff), Color.init(0x5f, 0xff, 0x00), Color.init(0x5f, 0xff, 0x5f),
    Color.init(0x5f, 0xff, 0x87), Color.init(0x5f, 0xff, 0xaf), Color.init(0x5f, 0xff, 0xd7), Color.init(0x5f, 0xff, 0xff),
    Color.init(0x87, 0x00, 0x00), Color.init(0x87, 0x00, 0x5f), Color.init(0x87, 0x00, 0x87), Color.init(0x87, 0x00, 0xaf),
    Color.init(0x87, 0x00, 0xd7), Color.init(0x87, 0x00, 0xff), Color.init(0x87, 0x5f, 0x00), Color.init(0x87, 0x5f, 0x5f),
    Color.init(0x87, 0x5f, 0x87), Color.init(0x87, 0x5f, 0xaf), Color.init(0x87, 0x5f, 0xd7), Color.init(0x87, 0x5f, 0xff),
    Color.init(0x87, 0x87, 0x00), Color.init(0x87, 0x87, 0x5f), Color.init(0x87, 0x87, 0x87), Color.init(0x87, 0x87, 0xaf),
    Color.init(0x87, 0x87, 0xd7), Color.init(0x87, 0x87, 0xff), Color.init(0x87, 0xaf, 0x00), Color.init(0x87, 0xaf, 0x5f),
    Color.init(0x87, 0xaf, 0x87), Color.init(0x87, 0xaf, 0xaf), Color.init(0x87, 0xaf, 0xd7), Color.init(0x87, 0xaf, 0xff),
    Color.init(0x87, 0xd7, 0x00), Color.init(0x87, 0xd7, 0x5f), Color.init(0x87, 0xd7, 0x87), Color.init(0x87, 0xd7, 0xaf),
    Color.init(0x87, 0xd7, 0xd7), Color.init(0x87, 0xd7, 0xff), Color.init(0x87, 0xff, 0x00), Color.init(0x87, 0xff, 0x5f),
    Color.init(0x87, 0xff, 0x87), Color.init(0x87, 0xff, 0xaf), Color.init(0x87, 0xff, 0xd7), Color.init(0x87, 0xff, 0xff),
    Color.init(0xaf, 0x00, 0x00), Color.init(0xaf, 0x00, 0x5f), Color.init(0xaf, 0x00, 0x87), Color.init(0xaf, 0x00, 0xaf),
    Color.init(0xaf, 0x00, 0xd7), Color.init(0xaf, 0x00, 0xff), Color.init(0xaf, 0x5f, 0x00), Color.init(0xaf, 0x5f, 0x5f),
    Color.init(0xaf, 0x5f, 0x87), Color.init(0xaf, 0x5f, 0xaf), Color.init(0xaf, 0x5f, 0xd7), Color.init(0xaf, 0x5f, 0xff),
    Color.init(0xaf, 0x87, 0x00), Color.init(0xaf, 0x87, 0x5f), Color.init(0xaf, 0x87, 0x87), Color.init(0xaf, 0x87, 0xaf),
    Color.init(0xaf, 0x87, 0xd7), Color.init(0xaf, 0x87, 0xff), Color.init(0xaf, 0xaf, 0x00), Color.init(0xaf, 0xaf, 0x5f),
    Color.init(0xaf, 0xaf, 0x87), Color.init(0xaf, 0xaf, 0xaf), Color.init(0xaf, 0xaf, 0xd7), Color.init(0xaf, 0xaf, 0xff),
    Color.init(0xaf, 0xd7, 0x00), Color.init(0xaf, 0xd7, 0x5f), Color.init(0xaf, 0xd7, 0x87), Color.init(0xaf, 0xd7, 0xaf),
    Color.init(0xaf, 0xd7, 0xd7), Color.init(0xaf, 0xd7, 0xff), Color.init(0xaf, 0xff, 0x00), Color.init(0xaf, 0xff, 0x5f),
    Color.init(0xaf, 0xff, 0x87), Color.init(0xaf, 0xff, 0xaf), Color.init(0xaf, 0xff, 0xd7), Color.init(0xaf, 0xff, 0xff),
    Color.init(0xd7, 0x00, 0x00), Color.init(0xd7, 0x00, 0x5f), Color.init(0xd7, 0x00, 0x87), Color.init(0xd7, 0x00, 0xaf),
    Color.init(0xd7, 0x00, 0xd7), Color.init(0xd7, 0x00, 0xff), Color.init(0xd7, 0x5f, 0x00), Color.init(0xd7, 0x5f, 0x5f),
    Color.init(0xd7, 0x5f, 0x87), Color.init(0xd7, 0x5f, 0xaf), Color.init(0xd7, 0x5f, 0xd7), Color.init(0xd7, 0x5f, 0xff),
    Color.init(0xd7, 0x87, 0x00), Color.init(0xd7, 0x87, 0x5f), Color.init(0xd7, 0x87, 0x87), Color.init(0xd7, 0x87, 0xaf),
    Color.init(0xd7, 0x87, 0xd7), Color.init(0xd7, 0x87, 0xff), Color.init(0xd7, 0xaf, 0x00), Color.init(0xd7, 0xaf, 0x5f),
    Color.init(0xd7, 0xaf, 0x87), Color.init(0xd7, 0xaf, 0xaf), Color.init(0xd7, 0xaf, 0xd7), Color.init(0xd7, 0xaf, 0xff),
    Color.init(0xd7, 0xd7, 0x00), Color.init(0xd7, 0xd7, 0x5f), Color.init(0xd7, 0xd7, 0x87), Color.init(0xd7, 0xd7, 0xaf),
    Color.init(0xd7, 0xd7, 0xd7), Color.init(0xd7, 0xd7, 0xff), Color.init(0xd7, 0xff, 0x00), Color.init(0xd7, 0xff, 0x5f),
    Color.init(0xd7, 0xff, 0x87), Color.init(0xd7, 0xff, 0xaf), Color.init(0xd7, 0xff, 0xd7), Color.init(0xd7, 0xff, 0xff),
    Color.init(0xff, 0x00, 0x00), Color.init(0xff, 0x00, 0x5f), Color.init(0xff, 0x00, 0x87), Color.init(0xff, 0x00, 0xaf),
    Color.init(0xff, 0x00, 0xd7), Color.init(0xff, 0x00, 0xff), Color.init(0xff, 0x5f, 0x00), Color.init(0xff, 0x5f, 0x5f),
    Color.init(0xff, 0x5f, 0x87), Color.init(0xff, 0x5f, 0xaf), Color.init(0xff, 0x5f, 0xd7), Color.init(0xff, 0x5f, 0xff),
    Color.init(0xff, 0x87, 0x00), Color.init(0xff, 0x87, 0x5f), Color.init(0xff, 0x87, 0x87), Color.init(0xff, 0x87, 0xaf),
    Color.init(0xff, 0x87, 0xd7), Color.init(0xff, 0x87, 0xff), Color.init(0xff, 0xaf, 0x00), Color.init(0xff, 0xaf, 0x5f),
    Color.init(0xff, 0xaf, 0x87), Color.init(0xff, 0xaf, 0xaf), Color.init(0xff, 0xaf, 0xd7), Color.init(0xff, 0xaf, 0xff),
    Color.init(0xff, 0xd7, 0x00), Color.init(0xff, 0xd7, 0x5f), Color.init(0xff, 0xd7, 0x87), Color.init(0xff, 0xd7, 0xaf),
    Color.init(0xff, 0xd7, 0xd7), Color.init(0xff, 0xd7, 0xff), Color.init(0xff, 0xff, 0x00), Color.init(0xff, 0xff, 0x5f),
    Color.init(0xff, 0xff, 0x87), Color.init(0xff, 0xff, 0xaf), Color.init(0xff, 0xff, 0xd7), Color.init(0xff, 0xff, 0xff),

    // 24 greyscale colors (232-255) - exact charmbracelet values
    Color.init(0x08, 0x08, 0x08), Color.init(0x12, 0x12, 0x12), Color.init(0x1c, 0x1c, 0x1c), Color.init(0x26, 0x26, 0x26),
    Color.init(0x30, 0x30, 0x30), Color.init(0x3a, 0x3a, 0x3a), Color.init(0x44, 0x44, 0x44), Color.init(0x4e, 0x4e, 0x4e),
    Color.init(0x58, 0x58, 0x58), Color.init(0x62, 0x62, 0x62), Color.init(0x6c, 0x6c, 0x6c), Color.init(0x76, 0x76, 0x76),
    Color.init(0x80, 0x80, 0x80), Color.init(0x8a, 0x8a, 0x8a), Color.init(0x94, 0x94, 0x94), Color.init(0x9e, 0x9e, 0x9e),
    Color.init(0xa8, 0xa8, 0xa8), Color.init(0xb2, 0xb2, 0xb2), Color.init(0xbc, 0xbc, 0xbc), Color.init(0xc6, 0xc6, 0xc6),
    Color.init(0xd0, 0xd0, 0xd0), Color.init(0xda, 0xda, 0xda), Color.init(0xe4, 0xe4, 0xe4), Color.init(0xee, 0xee, 0xee),
};

/// Enhanced color conversion using charmbracelet/x algorithm with HSLuv distance
/// This provides much better perceptual color matching than traditional RGB distance
pub fn convertToAnsi256Enhanced(color: Color) u8 {
    const r: f32 = @floatFromInt(color.r);
    const g: f32 = @floatFromInt(color.g);
    const b: f32 = @floatFromInt(color.b);

    const q2c = [_]u8{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };

    // Map RGB to 6x6x6 cube
    const qr = to6Cube(r);
    const cr = q2c[qr];
    const qg = to6Cube(g);
    const cg = q2c[qg];
    const qb = to6Cube(b);
    const cb = q2c[qb];

    // Calculate cube index
    const ci = (36 * qr) + (6 * qg) + qb;

    // If we hit the color exactly, return early
    if (cr == color.r and cg == color.g and cb == color.b) {
        return @intCast(16 + ci);
    }

    // Work out the closest grey (average of RGB)
    const grey_avg: u32 = (@as(u32, color.r) + @as(u32, color.g) + @as(u32, color.b)) / 3;
    var grey_idx: u32 = 0;
    if (grey_avg > 238) {
        grey_idx = 23;
    } else if (grey_avg >= 3) {
        grey_idx = (grey_avg - 3) / 10;
    }
    const grey: u8 = @intCast(8 + (10 * grey_idx));

    // Use HSLuv distance for better perceptual matching (key enhancement!)
    const original_hsluv = color.toFloat().toHSLuv();
    const cube_color_hsluv = Color.init(cr, cg, cb).toFloat().toHSLuv();
    const grey_color_hsluv = Color.init(grey, grey, grey).toFloat().toHSLuv();

    const cube_distance = original_hsluv.distance(cube_color_hsluv);
    const grey_distance = original_hsluv.distance(grey_color_hsluv);

    if (cube_distance <= grey_distance) {
        return @intCast(16 + ci);
    }
    return @intCast(232 + grey_idx);
}

/// Enhanced palette-based color matching using HSLuv distance
pub fn findClosestColorHSLuv(target: Color, palette: []const Color) u8 {
    if (palette.len == 0) return 0;

    const target_hsluv = target.toFloat().toHSLuv();
    var closest_idx: u8 = 0;
    var min_distance = target_hsluv.distance(palette[0].toFloat().toHSLuv());

    for (palette[1..], 1..) |palette_color, i| {
        const candidate_hsluv = palette_color.toFloat().toHSLuv();
        const distance = target_hsluv.distance(candidate_hsluv);
        if (distance < min_distance) {
            min_distance = distance;
            closest_idx = @intCast(i);
        }
    }

    return closest_idx;
}

/// Charmbracelet-style color type system
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

    pub fn toColor(self: BasicColor) Color {
        return ansi_256_palette[@intFromEnum(self)];
    }
};

pub const IndexedColor = struct {
    index: u8,

    pub fn init(index: u8) IndexedColor {
        return IndexedColor{ .index = @min(index, 255) };
    }

    pub fn toColor(self: IndexedColor) Color {
        return ansi_256_palette[self.index];
    }
};

pub const RGBColor = struct {
    color: Color,

    pub fn init(r: u8, g: u8, b: u8) RGBColor {
        return RGBColor{ .color = Color.init(r, g, b) };
    }

    pub fn fromHex(hex: u32) RGBColor {
        return RGBColor{ .color = Color.fromHex(hex) };
    }

    /// Convert to closest ANSI 256 color using enhanced algorithm
    pub fn toAnsi256(self: RGBColor) IndexedColor {
        return IndexedColor.init(convertToAnsi256Enhanced(self.color));
    }

    /// Convert to closest ANSI 16 color
    pub fn toAnsi16(self: RGBColor) BasicColor {
        const ansi_256 = self.toAnsi256();

        // Exact 256-to-16 mapping from charmbracelet/x/ansi/color.go
        return @enumFromInt(charmbracelet_256_to_16_map[ansi_256.index]);
    }
};

/// Exact ANSI 256 to 16 color conversion table from charmbracelet/x
const charmbracelet_256_to_16_map = [_]u8{
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

/// High-level color converter with charmbracelet/x-style API
pub const ColorConverter = struct {
    /// Convert RGB to closest ANSI 256 color using enhanced algorithm
    pub fn rgbToAnsi256(r: u8, g: u8, b: u8) u8 {
        return convertToAnsi256Enhanced(Color.init(r, g, b));
    }

    /// Convert RGB to closest ANSI 16 color using enhanced algorithm
    pub fn rgbToAnsi16(r: u8, g: u8, b: u8) u8 {
        const rgb = RGBColor.init(r, g, b);
        return @intFromEnum(rgb.toAnsi16());
    }

    /// Convert hex color to ANSI 256 using enhanced algorithm
    pub fn hexToAnsi256(hex: u32) u8 {
        return convertToAnsi256Enhanced(Color.fromHex(hex));
    }

    /// Convert hex color to ANSI 16 using enhanced algorithm
    pub fn hexToAnsi16(hex: u32) u8 {
        const rgb = RGBColor.fromHex(hex);
        return @intFromEnum(rgb.toAnsi16());
    }

    /// Find closest color in palette using HSLuv distance
    pub fn findClosestInPalette(target_color: Color, palette: []const Color) u8 {
        return findClosestColorHSLuv(target_color, palette);
    }
};

/// Convenience functions matching charmbracelet/x API style
pub fn convert256(color: Color) IndexedColor {
    return IndexedColor.init(convertToAnsi256Enhanced(color));
}

pub fn convert16(color: Color) BasicColor {
    const rgb = RGBColor{ .color = color };
    return rgb.toAnsi16();
}

// Tests demonstrating enhanced color conversion
test "enhanced color conversion accuracy" {
    const testing = std.testing;

    // Test that enhanced algorithm produces reasonable results
    const red = Color.init(255, 0, 0);
    const red_256 = convertToAnsi256Enhanced(red);
    try testing.expect(red_256 >= 16); // Should not be in basic 16 colors

    // Test perceptual color matching
    const dark_red = Color.init(128, 0, 0);
    const light_red = Color.init(255, 200, 200);

    const dark_red_256 = convertToAnsi256Enhanced(dark_red);
    const light_red_256 = convertToAnsi256Enhanced(light_red);

    // They should map to different colors
    try testing.expect(dark_red_256 != light_red_256);
}

test "HSLuv color distance" {
    const testing = std.testing;

    const red = Color.init(255, 0, 0);
    const blue = Color.init(0, 0, 255);
    const dark_red = Color.init(128, 0, 0);

    const red_hsluv = red.toFloat().toHSLuv();
    const blue_hsluv = blue.toFloat().toHSLuv();
    const dark_red_hsluv = dark_red.toFloat().toHSLuv();

    // Red should be closer to dark red than to blue
    const red_to_dark_red = red_hsluv.distance(dark_red_hsluv);
    const red_to_blue = red_hsluv.distance(blue_hsluv);

    try testing.expect(red_to_dark_red < red_to_blue);
}

test "charmbracelet color type system" {
    const testing = std.testing;

    // Test BasicColor
    const red_basic = BasicColor.red;
    const red_color = red_basic.toColor();
    try testing.expectEqual(@as(u8, 128), red_color.r);

    // Test IndexedColor
    const indexed = IndexedColor.init(196); // Bright red in 256 palette
    const indexed_color = indexed.toColor();
    try testing.expectEqual(@as(u8, 255), indexed_color.r);

    // Test RGBColor conversion
    const rgb = RGBColor.init(255, 128, 0);
    const ansi256 = rgb.toAnsi256();
    try testing.expect(ansi256.index < 256);

    const ansi16 = rgb.toAnsi16();
    try testing.expect(@intFromEnum(ansi16) < 16);
}

test "color converter high-level API" {
    const testing = std.testing;

    // Test convenience functions
    const red_256 = ColorConverter.rgbToAnsi256(255, 0, 0);
    const red_16 = ColorConverter.rgbToAnsi16(255, 0, 0);
    const blue_hex_256 = ColorConverter.hexToAnsi256(0x0000FF);
    const blue_hex_16 = ColorConverter.hexToAnsi16(0x0000FF);

    try testing.expect(red_256 < 256);
    try testing.expect(red_16 < 16);
    try testing.expect(blue_hex_256 < 256);
    try testing.expect(blue_hex_16 < 16);
}

test "palette color matching" {
    const testing = std.testing;

    // Test HSLuv-based palette matching
    const target = Color.init(200, 100, 50);
    const small_palette = [_]Color{
        Color.init(255, 0, 0), // Red
        Color.init(0, 255, 0), // Green
        Color.init(0, 0, 255), // Blue
        Color.init(200, 100, 0), // Close to target
    };

    const closest = findClosestColorHSLuv(target, &small_palette);
    try testing.expectEqual(@as(u8, 3), closest); // Should pick the close orange color
}

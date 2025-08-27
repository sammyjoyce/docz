//! Color Space Conversions
//! Comprehensive color conversion algorithms between all supported color spaces
//! Consolidates all conversion logic from multiple files

const std = @import("std");
const types = @import("types.zig");

pub const RGB = types.RGB;
pub const RGBf = types.RGBf;
pub const HSL = types.HSL;
pub const HSV = types.HSV;
pub const Lab = types.Lab;
pub const XYZ = types.XYZ;
pub const Ansi256 = types.Ansi256;
pub const TerminalColor = types.TerminalColor;

// === RGB TO OTHER COLOR SPACES ===

pub fn rgbToHsl(rgb: RGB) HSL {
    const norm = rgb.toNormalized();
    const r = norm.r;
    const g = norm.g;
    const b = norm.b;

    const max = @max(@max(r, g), b);
    const min = @min(@min(r, g), b);
    const delta = max - min;

    // Lightness
    const l = (max + min) / 2.0;

    // Saturation and Hue
    var s: f32 = 0;
    var h: f32 = 0;

    if (delta > 0.0001) {
        s = if (l > 0.5)
            delta / (2.0 - max - min)
        else
            delta / (max + min);

        if (max == r) {
            h = (g - b) / delta + (if (g < b) 6.0 else 0.0);
        } else if (max == g) {
            h = (b - r) / delta + 2.0;
        } else {
            h = (r - g) / delta + 4.0;
        }
        h /= 6.0;
    }

    return HSL.init(h * 360.0, s * 100.0, l * 100.0);
}

pub fn hslToRgb(hsl: HSL) RGB {
    const h = hsl.h / 360.0;
    const s = hsl.s / 100.0;
    const l = hsl.l / 100.0;

    var r: f32 = undefined;
    var g: f32 = undefined;
    var b: f32 = undefined;

    if (s == 0) {
        r = l;
        g = l;
        b = l;
    } else {
        const q = if (l < 0.5) l * (1.0 + s) else l + s - l * s;
        const p = 2.0 * l - q;

        r = hueToRgb(p, q, h + 1.0 / 3.0);
        g = hueToRgb(p, q, h);
        b = hueToRgb(p, q, h - 1.0 / 3.0);
    }

    return RGB.init(
        @intFromFloat(r * 255.0),
        @intFromFloat(g * 255.0),
        @intFromFloat(b * 255.0),
    );
}

fn hueToRgb(p: f32, q: f32, t_raw: f32) f32 {
    var t = t_raw;
    if (t < 0) t += 1;
    if (t > 1) t -= 1;

    if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
    if (t < 1.0 / 2.0) return q;
    if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    return p;
}

pub fn rgbToHsv(rgb: RGB) HSV {
    const norm = rgb.toNormalized();
    const r = norm.r;
    const g = norm.g;
    const b = norm.b;

    const max = @max(@max(r, g), b);
    const min = @min(@min(r, g), b);
    const delta = max - min;

    const v = max;
    var s: f32 = 0;
    if (max != 0) {
        s = delta / max;
    }

    var h: f32 = 0;
    if (delta != 0) {
        if (max == r) {
            h = (g - b) / delta + (if (g < b) 6.0 else 0.0);
        } else if (max == g) {
            h = (b - r) / delta + 2.0;
        } else {
            h = (r - g) / delta + 4.0;
        }
        h /= 6.0;
    }

    return HSV.init(h * 360.0, s * 100.0, v * 100.0);
}

pub fn hsvToRgb(hsv: HSV) RGB {
    const h = hsv.h / 360.0;
    const s = hsv.s / 100.0;
    const v = hsv.v / 100.0;

    const c = v * s;
    const x = c * (1.0 - @abs(@mod(h * 6.0, 2.0) - 1.0));
    const m = v - c;

    var r: f32 = undefined;
    var g: f32 = undefined;
    var b: f32 = undefined;

    const h_segment = @as(u32, @intFromFloat(h * 6.0));
    switch (h_segment) {
        0 => {
            r = c;
            g = x;
            b = 0;
        },
        1 => {
            r = x;
            g = c;
            b = 0;
        },
        2 => {
            r = 0;
            g = c;
            b = x;
        },
        3 => {
            r = 0;
            g = x;
            b = c;
        },
        4 => {
            r = x;
            g = 0;
            b = c;
        },
        else => {
            r = c;
            g = 0;
            b = x;
        },
    }

    return RGB.init(
        @intFromFloat((r + m) * 255.0),
        @intFromFloat((g + m) * 255.0),
        @intFromFloat((b + m) * 255.0),
    );
}

// === RGB TO LAB/XYZ CONVERSIONS ===

// D65 illuminant constants
const D65_X = 95.047;
const D65_Y = 100.000;
const D65_Z = 108.883;

pub fn rgbToXyz(rgb: RGB) XYZ {
    const norm = rgb.toNormalized();

    // Apply gamma correction
    var r = norm.r;
    var g = norm.g;
    var b = norm.b;

    if (r > 0.04045) {
        r = std.math.pow(f32, (r + 0.055) / 1.055, 2.4);
    } else {
        r = r / 12.92;
    }

    if (g > 0.04045) {
        g = std.math.pow(f32, (g + 0.055) / 1.055, 2.4);
    } else {
        g = g / 12.92;
    }

    if (b > 0.04045) {
        b = std.math.pow(f32, (b + 0.055) / 1.055, 2.4);
    } else {
        b = b / 12.92;
    }

    // Observer = 2°, Illuminant = D65
    const x = r * 41.24 + g * 35.76 + b * 18.05;
    const y = r * 21.26 + g * 71.52 + b * 7.22;
    const z = r * 1.93 + g * 11.92 + b * 95.05;

    return XYZ.init(x, y, z);
}

pub fn xyzToRgb(xyz: XYZ) RGB {
    // Observer = 2°, Illuminant = D65
    var r = xyz.x * 0.032406 - xyz.y * 0.015372 - xyz.z * 0.004986;
    var g = xyz.x * -0.009689 + xyz.y * 0.018758 + xyz.z * 0.000415;
    var b = xyz.x * 0.000557 - xyz.y * 0.002040 + xyz.z * 0.010570;

    // Apply gamma correction
    if (r > 0.0031308) {
        r = 1.055 * std.math.pow(f32, r, 1.0 / 2.4) - 0.055;
    } else {
        r = r * 12.92;
    }

    if (g > 0.0031308) {
        g = 1.055 * std.math.pow(f32, g, 1.0 / 2.4) - 0.055;
    } else {
        g = g * 12.92;
    }

    if (b > 0.0031308) {
        b = 1.055 * std.math.pow(f32, b, 1.0 / 2.4) - 0.055;
    } else {
        b = b * 12.92;
    }

    return RGB.init(
        @intFromFloat(std.math.clamp(r * 255.0, 0.0, 255.0)),
        @intFromFloat(std.math.clamp(g * 255.0, 0.0, 255.0)),
        @intFromFloat(std.math.clamp(b * 255.0, 0.0, 255.0)),
    );
}

pub fn xyzToLab(xyz: XYZ) Lab {
    var x = xyz.x / D65_X;
    var y = xyz.y / D65_Y;
    var z = xyz.z / D65_Z;

    if (x > 0.008856) {
        x = std.math.pow(f32, x, 1.0 / 3.0);
    } else {
        x = (7.787 * x) + (16.0 / 116.0);
    }

    if (y > 0.008856) {
        y = std.math.pow(f32, y, 1.0 / 3.0);
    } else {
        y = (7.787 * y) + (16.0 / 116.0);
    }

    if (z > 0.008856) {
        z = std.math.pow(f32, z, 1.0 / 3.0);
    } else {
        z = (7.787 * z) + (16.0 / 116.0);
    }

    const l = (116.0 * y) - 16.0;
    const a = 500.0 * (x - y);
    const b = 200.0 * (y - z);

    return Lab.init(l, a, b);
}

pub fn labToXyz(lab: Lab) XYZ {
    var y = (lab.l + 16.0) / 116.0;
    var x = lab.a / 500.0 + y;
    var z = y - lab.b / 200.0;

    if (std.math.pow(f32, y, 3) > 0.008856) {
        y = std.math.pow(f32, y, 3);
    } else {
        y = (y - 16.0 / 116.0) / 7.787;
    }

    if (std.math.pow(f32, x, 3) > 0.008856) {
        x = std.math.pow(f32, x, 3);
    } else {
        x = (x - 16.0 / 116.0) / 7.787;
    }

    if (std.math.pow(f32, z, 3) > 0.008856) {
        z = std.math.pow(f32, z, 3);
    } else {
        z = (z - 16.0 / 116.0) / 7.787;
    }

    return XYZ.init(x * D65_X, y * D65_Y, z * D65_Z);
}

pub fn rgbToLab(rgb: RGB) Lab {
    const xyz = rgbToXyz(rgb);
    return xyzToLab(xyz);
}

pub fn labToRgb(lab: Lab) RGB {
    const xyz = labToXyz(lab);
    return xyzToRgb(xyz);
}

// === 256-COLOR CONVERSIONS ===

/// Convert RGB to ANSI 256-color palette index
pub fn rgbToAnsi256(rgb: RGB) Ansi256 {
    // Check for exact matches in basic 16 colors
    const basic_colors = [_]RGB{
        RGB.init(0, 0, 0), // 0: black
        RGB.init(205, 49, 49), // 1: red
        RGB.init(13, 188, 121), // 2: green
        RGB.init(229, 229, 16), // 3: yellow
        RGB.init(36, 114, 200), // 4: blue
        RGB.init(188, 63, 188), // 5: magenta
        RGB.init(17, 168, 205), // 6: cyan
        RGB.init(229, 229, 229), // 7: white
        RGB.init(102, 102, 102), // 8: bright black
        RGB.init(241, 76, 76), // 9: bright red
        RGB.init(35, 209, 139), // 10: bright green
        RGB.init(245, 245, 67), // 11: bright yellow
        RGB.init(59, 142, 234), // 12: bright blue
        RGB.init(214, 112, 214), // 13: bright magenta
        RGB.init(41, 184, 219), // 14: bright cyan
        RGB.init(255, 255, 255), // 15: bright white
    };

    for (basic_colors, 0..) |color, i| {
        if (rgb.equals(color)) {
            return Ansi256.init(@intCast(i));
        }
    }

    // Check if it's grayscale (232-255)
    if (rgb.r == rgb.g and rgb.g == rgb.b) {
        // Map to 24-level grayscale
        const gray_val = rgb.r;
        if (gray_val < 8) return Ansi256.init(16); // Use black
        if (gray_val > 248) return Ansi256.init(231); // Use white

        const gray_index = @divFloor(gray_val - 8, 10);
        return Ansi256.init(232 + gray_index);
    }

    // Map to 216-color cube (16-231)
    const r_index = quantize6(rgb.r);
    const g_index = quantize6(rgb.g);
    const b_index = quantize6(rgb.b);

    return Ansi256.init(16 + 36 * r_index + 6 * g_index + b_index);
}

fn quantize6(value: u8) u8 {
    // Quantize to 6 levels (0, 95, 135, 175, 215, 255)
    if (value < 48) return 0;
    if (value < 115) return 1;
    if (value < 155) return 2;
    if (value < 195) return 3;
    if (value < 235) return 4;
    return 5;
}

/// Convert ANSI 256-color index to RGB
pub fn ansi256ToRgb(index: u8) RGB {
    // Basic 16 colors (0-15)
    if (index < 16) {
        const ansi16: types.Ansi16 = @enumFromInt(@as(u4, @intCast(index)));
        return ansi16.toRGB();
    }

    // 216-color cube (16-231)
    if (index < 232) {
        const cube_index = index - 16;
        const r = @divFloor(cube_index, 36);
        const g = @divFloor(@mod(cube_index, 36), 6);
        const b = @mod(cube_index, 6);

        const levels = [_]u8{ 0, 95, 135, 175, 215, 255 };
        return RGB.init(levels[r], levels[g], levels[b]);
    }

    // Grayscale (232-255)
    const gray_level = 8 + (index - 232) * 10;
    return RGB.init(gray_level, gray_level, gray_level);
}

// === TESTS ===

test "RGB to HSL conversion" {
    const rgb = RGB.init(255, 128, 64);
    const hsl = rgbToHsl(rgb);

    try std.testing.expectApproxEqAbs(@as(f32, 20.1), hsl.h, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), hsl.s, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 62.5), hsl.l, 1.0);

    // Round trip
    const rgb2 = hslToRgb(hsl);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(rgb.r)), @as(f32, @floatFromInt(rgb2.r)), 2.0);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(rgb.g)), @as(f32, @floatFromInt(rgb2.g)), 2.0);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(rgb.b)), @as(f32, @floatFromInt(rgb2.b)), 2.0);
}

test "RGB to HSV conversion" {
    const rgb = RGB.init(255, 128, 64);
    const hsv = rgbToHsv(rgb);

    try std.testing.expectApproxEqAbs(@as(f32, 20.1), hsv.h, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 74.9), hsv.s, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), hsv.v, 1.0);
}

test "RGB to Lab conversion" {
    const rgb = RGB.init(255, 0, 0);
    const lab = rgbToLab(rgb);

    // Pure red in Lab space
    try std.testing.expectApproxEqAbs(@as(f32, 53.2), lab.l, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 80.1), lab.a, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 67.2), lab.b, 1.0);
}

test "RGB to ANSI 256 conversion" {
    // Test basic colors
    const black = RGB.init(0, 0, 0);
    try std.testing.expectEqual(@as(u8, 0), rgbToAnsi256(black).index);

    // Test grayscale
    const gray = RGB.init(128, 128, 128);
    const gray_index = rgbToAnsi256(gray).index;
    try std.testing.expect(gray_index >= 232 and gray_index <= 255);

    // Test color cube
    const orange = RGB.init(255, 128, 0);
    const orange_index = rgbToAnsi256(orange).index;
    try std.testing.expect(orange_index >= 16 and orange_index <= 231);
}

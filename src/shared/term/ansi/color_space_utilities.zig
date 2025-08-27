const std = @import("std");
const math = std.math;

/// Advanced color space conversion utilities for terminal color processing
/// Provides comprehensive color analysis and conversion capabilities
/// RGB color structure (0-255 range)
pub const RGBColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RGBColor {
        return RGBColor{ .r = r, .g = g, .b = b };
    }

    pub fn fromNormalized(r: f64, g: f64, b: f64) RGBColor {
        return RGBColor{
            .r = @intFromFloat(@max(0, @min(255, r * 255.0))),
            .g = @intFromFloat(@max(0, @min(255, g * 255.0))),
            .b = @intFromFloat(@max(0, @min(255, b * 255.0))),
        };
    }

    pub fn toNormalized(self: RGBColor) struct { r: f64, g: f64, b: f64 } {
        return .{
            .r = @as(f64, @floatFromInt(self.r)) / 255.0,
            .g = @as(f64, @floatFromInt(self.g)) / 255.0,
            .b = @as(f64, @floatFromInt(self.b)) / 255.0,
        };
    }
};

/// HSV color representation (Hue, Saturation, Value)
pub const HSVColor = struct {
    h: f64, // Hue: 0-360 degrees
    s: f64, // Saturation: 0-1
    v: f64, // Value: 0-1

    pub fn init(h: f64, s: f64, v: f64) HSVColor {
        return HSVColor{ .h = @mod(h, 360.0), .s = @max(0.0, @min(1.0, s)), .v = @max(0.0, @min(1.0, v)) };
    }
};

/// HSL color representation (Hue, Saturation, Lightness)
pub const HSLColor = struct {
    h: f64, // Hue: 0-360 degrees
    s: f64, // Saturation: 0-1
    l: f64, // Lightness: 0-1

    pub fn init(h: f64, s: f64, l: f64) HSLColor {
        return HSLColor{ .h = @mod(h, 360.0), .s = @max(0.0, @min(1.0, s)), .l = @max(0.0, @min(1.0, l)) };
    }
};

/// CIE XYZ color representation
pub const XYZColor = struct {
    x: f64,
    y: f64,
    z: f64,

    pub fn init(x: f64, y: f64, z: f64) XYZColor {
        return XYZColor{ .x = x, .y = y, .z = z };
    }
};

/// CIE L*a*b* color representation
pub const LABColor = struct {
    l: f64, // Lightness: 0-100
    a: f64, // Green-Red axis: -128 to 127
    b: f64, // Blue-Yellow axis: -128 to 127

    pub fn init(l: f64, a: f64, b: f64) LABColor {
        return LABColor{ .l = l, .a = a, .b = b };
    }

    /// Calculate chroma (saturation in LAB space)
    pub fn chroma(self: LABColor) f64 {
        return @sqrt(self.a * self.a + self.b * self.b);
    }

    /// Calculate hue angle in LAB space
    pub fn hue(self: LABColor) f64 {
        return math.atan2(f64, self.b, self.a) * 180.0 / math.pi;
    }
};

/// RGB to HSV conversion
pub fn rgbToHsv(rgb: RGBColor) HSVColor {
    const norm = rgb.toNormalized();
    const max_val = @max(@max(norm.r, norm.g), norm.b);
    const min_val = @min(@min(norm.r, norm.g), norm.b);
    const delta = max_val - min_val;

    // Value is the maximum component
    const v = max_val;

    // Saturation
    const s = if (max_val == 0.0) 0.0 else delta / max_val;

    // Hue
    var h: f64 = 0.0;
    if (delta != 0.0) {
        if (max_val == norm.r) {
            h = 60.0 * @mod((norm.g - norm.b) / delta, 6.0);
        } else if (max_val == norm.g) {
            h = 60.0 * ((norm.b - norm.r) / delta + 2.0);
        } else {
            h = 60.0 * ((norm.r - norm.g) / delta + 4.0);
        }
    }

    return HSVColor.init(h, s, v);
}

/// HSV to RGB conversion
pub fn hsvToRgb(hsv: HSVColor) RGBColor {
    const c = hsv.v * hsv.s;
    const x = c * (1.0 - @abs(@mod(hsv.h / 60.0, 2.0) - 1.0));
    const m = hsv.v - c;

    var r: f64 = 0.0;
    var g: f64 = 0.0;
    var b: f64 = 0.0;

    if (hsv.h >= 0.0 and hsv.h < 60.0) {
        r = c;
        g = x;
        b = 0.0;
    } else if (hsv.h >= 60.0 and hsv.h < 120.0) {
        r = x;
        g = c;
        b = 0.0;
    } else if (hsv.h >= 120.0 and hsv.h < 180.0) {
        r = 0.0;
        g = c;
        b = x;
    } else if (hsv.h >= 180.0 and hsv.h < 240.0) {
        r = 0.0;
        g = x;
        b = c;
    } else if (hsv.h >= 240.0 and hsv.h < 300.0) {
        r = x;
        g = 0.0;
        b = c;
    } else {
        r = c;
        g = 0.0;
        b = x;
    }

    return RGBColor.fromNormalized(r + m, g + m, b + m);
}

/// RGB to HSL conversion
pub fn rgbToHsl(rgb: RGBColor) HSLColor {
    const norm = rgb.toNormalized();
    const max_val = @max(@max(norm.r, norm.g), norm.b);
    const min_val = @min(@min(norm.r, norm.g), norm.b);
    const delta = max_val - min_val;

    // Lightness
    const l = (max_val + min_val) / 2.0;

    // Saturation
    var s: f64 = 0.0;
    if (delta != 0.0) {
        s = if (l <= 0.5) delta / (max_val + min_val) else delta / (2.0 - max_val - min_val);
    }

    // Hue (same calculation as HSV)
    var h: f64 = 0.0;
    if (delta != 0.0) {
        if (max_val == norm.r) {
            h = 60.0 * @mod((norm.g - norm.b) / delta, 6.0);
        } else if (max_val == norm.g) {
            h = 60.0 * ((norm.b - norm.r) / delta + 2.0);
        } else {
            h = 60.0 * ((norm.r - norm.g) / delta + 4.0);
        }
    }

    return HSLColor.init(h, s, l);
}

/// HSL to RGB conversion
pub fn hslToRgb(hsl: HSLColor) RGBColor {
    const c = (1.0 - @abs(2.0 * hsl.l - 1.0)) * hsl.s;
    const x = c * (1.0 - @abs(@mod(hsl.h / 60.0, 2.0) - 1.0));
    const m = hsl.l - c / 2.0;

    var r: f64 = 0.0;
    var g: f64 = 0.0;
    var b: f64 = 0.0;

    if (hsl.h >= 0.0 and hsl.h < 60.0) {
        r = c;
        g = x;
        b = 0.0;
    } else if (hsl.h >= 60.0 and hsl.h < 120.0) {
        r = x;
        g = c;
        b = 0.0;
    } else if (hsl.h >= 120.0 and hsl.h < 180.0) {
        r = 0.0;
        g = c;
        b = x;
    } else if (hsl.h >= 180.0 and hsl.h < 240.0) {
        r = 0.0;
        g = x;
        b = c;
    } else if (hsl.h >= 240.0 and hsl.h < 300.0) {
        r = x;
        g = 0.0;
        b = c;
    } else {
        r = c;
        g = 0.0;
        b = x;
    }

    return RGBColor.fromNormalized(r + m, g + m, b + m);
}

/// sRGB to linear RGB conversion
fn srgbToLinear(component: f64) f64 {
    if (component <= 0.04045) {
        return component / 12.92;
    } else {
        return math.pow(f64, (component + 0.055) / 1.055, 2.4);
    }
}

/// Linear RGB to sRGB conversion
fn linearToSrgb(component: f64) f64 {
    if (component <= 0.0031308) {
        return 12.92 * component;
    } else {
        return 1.055 * math.pow(f64, component, 1.0 / 2.4) - 0.055;
    }
}

/// RGB to XYZ conversion using sRGB color space
pub fn rgbToXyz(rgb: RGBColor) XYZColor {
    const norm = rgb.toNormalized();

    // Convert to linear RGB
    const r_lin = srgbToLinear(norm.r);
    const g_lin = srgbToLinear(norm.g);
    const b_lin = srgbToLinear(norm.b);

    // Apply sRGB to XYZ transformation matrix (D65 illuminant)
    const x = r_lin * 0.4124564 + g_lin * 0.3575761 + b_lin * 0.1804375;
    const y = r_lin * 0.2126729 + g_lin * 0.7151522 + b_lin * 0.0721750;
    const z = r_lin * 0.0193339 + g_lin * 0.1191920 + b_lin * 0.9503041;

    return XYZColor.init(x, y, z);
}

/// XYZ to RGB conversion using sRGB color space
pub fn xyzToRgb(xyz: XYZColor) RGBColor {
    // Apply XYZ to sRGB transformation matrix
    const r_lin = xyz.x * 3.2404542 + xyz.y * -1.5371385 + xyz.z * -0.4985314;
    const g_lin = xyz.x * -0.9692660 + xyz.y * 1.8760108 + xyz.z * 0.0415560;
    const b_lin = xyz.x * 0.0556434 + xyz.y * -0.2040259 + xyz.z * 1.0572252;

    // Convert to sRGB
    const r = linearToSrgb(r_lin);
    const g = linearToSrgb(g_lin);
    const b = linearToSrgb(b_lin);

    return RGBColor.fromNormalized(r, g, b);
}

/// LAB conversion helper function
fn labF(t: f64) f64 {
    const delta = 6.0 / 29.0;
    if (t > delta * delta * delta) {
        return math.pow(f64, t, 1.0 / 3.0);
    } else {
        return (t / (3.0 * delta * delta)) + (4.0 / 29.0);
    }
}

/// Inverse LAB function
fn labFInv(t: f64) f64 {
    const delta = 6.0 / 29.0;
    if (t > delta) {
        return t * t * t;
    } else {
        return 3.0 * delta * delta * (t - 4.0 / 29.0);
    }
}

/// XYZ to LAB conversion
pub fn xyzToLab(xyz: XYZColor) LABColor {
    // D65 white point
    const xn = 0.95047;
    const yn = 1.00000;
    const zn = 1.08883;

    // Normalize by white point and apply LAB function
    const fx = labF(xyz.x / xn);
    const fy = labF(xyz.y / yn);
    const fz = labF(xyz.z / zn);

    const l = 116.0 * fy - 16.0;
    const a = 500.0 * (fx - fy);
    const b = 200.0 * (fy - fz);

    return LABColor.init(l, a, b);
}

/// LAB to XYZ conversion
pub fn labToXyz(lab: LABColor) XYZColor {
    // D65 white point
    const xn = 0.95047;
    const yn = 1.00000;
    const zn = 1.08883;

    const fy = (lab.l + 16.0) / 116.0;
    const fx = lab.a / 500.0 + fy;
    const fz = fy - lab.b / 200.0;

    const x = xn * labFInv(fx);
    const y = yn * labFInv(fy);
    const z = zn * labFInv(fz);

    return XYZColor.init(x, y, z);
}

/// RGB to LAB conversion (convenience function)
pub fn rgbToLab(rgb: RGBColor) LABColor {
    const xyz = rgbToXyz(rgb);
    return xyzToLab(xyz);
}

/// LAB to RGB conversion (convenience function)
pub fn labToRgb(lab: LABColor) RGBColor {
    const xyz = labToXyz(lab);
    return xyzToRgb(xyz);
}

/// Color analysis utilities
pub const ColorAnalysis = struct {
    /// Classify color temperature (warm/cool)
    pub const Temperature = enum { very_cool, cool, neutral, warm, very_warm };

    /// Classify color saturation level
    pub const SaturationLevel = enum { grayscale, low, medium, high, vivid };

    /// Classify color lightness level
    pub const LightnessLevel = enum { very_dark, dark, medium, light, very_light };

    /// Analyze color temperature based on hue
    pub fn getTemperature(rgb: RGBColor) Temperature {
        const hsl = rgbToHsl(rgb);

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
    pub fn getSaturationLevel(rgb: RGBColor) SaturationLevel {
        const hsl = rgbToHsl(rgb);

        if (hsl.s < 0.05) return .grayscale;
        if (hsl.s < 0.3) return .low;
        if (hsl.s < 0.6) return .medium;
        if (hsl.s < 0.8) return .high;
        return .vivid;
    }

    /// Analyze lightness level
    pub fn getLightnessLevel(rgb: RGBColor) LightnessLevel {
        const hsl = rgbToHsl(rgb);

        if (hsl.l < 0.2) return .very_dark;
        if (hsl.l < 0.4) return .dark;
        if (hsl.l < 0.6) return .medium;
        if (hsl.l < 0.8) return .light;
        return .very_light;
    }

    /// Check if color is achromatic (grayscale)
    pub fn isAchromatic(rgb: RGBColor, tolerance: f64) bool {
        const max_diff = @max(@max(@abs(@as(f64, @floatFromInt(rgb.r)) - @as(f64, @floatFromInt(rgb.g))), @abs(@as(f64, @floatFromInt(rgb.g)) - @as(f64, @floatFromInt(rgb.b)))), @abs(@as(f64, @floatFromInt(rgb.r)) - @as(f64, @floatFromInt(rgb.b))));
        return max_diff <= tolerance;
    }

    /// Calculate perceived brightness using luminance formula
    pub fn getPerceivedBrightness(rgb: RGBColor) f64 {
        // Using ITU-R BT.709 luma coefficients for better accuracy
        const norm = rgb.toNormalized();
        return norm.r * 0.2126 + norm.g * 0.7152 + norm.b * 0.0722;
    }

    /// Determine contrast ratio between two colors
    pub fn getContrastRatio(color1: RGBColor, color2: RGBColor) f64 {
        const lum1 = getPerceivedBrightness(color1);
        const lum2 = getPerceivedBrightness(color2);

        const lighter = @max(lum1, lum2);
        const darker = @min(lum1, lum2);

        return (lighter + 0.05) / (darker + 0.05);
    }

    /// Check WCAG accessibility compliance
    pub fn isAccessible(foreground: RGBColor, background: RGBColor, level: enum { AA, AAA }) bool {
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
    pub fn getComplementary(rgb: RGBColor) RGBColor {
        const hsv = rgbToHsv(rgb);
        const comp_hsv = HSVColor.init(hsv.h + 180.0, hsv.s, hsv.v);
        return hsvToRgb(comp_hsv);
    }

    /// Generate triadic colors (120° hue shifts)
    pub fn getTriadic(rgb: RGBColor) [2]RGBColor {
        const hsv = rgbToHsv(rgb);
        const hsv1 = HSVColor.init(hsv.h + 120.0, hsv.s, hsv.v);
        const hsv2 = HSVColor.init(hsv.h + 240.0, hsv.s, hsv.v);
        return [2]RGBColor{ hsvToRgb(hsv1), hsvToRgb(hsv2) };
    }

    /// Generate analogous colors (±30° hue shifts)
    pub fn getAnalogous(rgb: RGBColor) [2]RGBColor {
        const hsv = rgbToHsv(rgb);
        const hsv1 = HSVColor.init(hsv.h + 30.0, hsv.s, hsv.v);
        const hsv2 = HSVColor.init(hsv.h - 30.0, hsv.s, hsv.v);
        return [2]RGBColor{ hsvToRgb(hsv1), hsvToRgb(hsv2) };
    }

    /// Generate monochromatic variations (same hue, different saturation/value)
    pub fn getMonochromatic(rgb: RGBColor, count: usize, allocator: std.mem.Allocator) ![]RGBColor {
        const hsv = rgbToHsv(rgb);
        var colors = try allocator.alloc(RGBColor, count);

        for (0..count) |i| {
            const t = if (count == 1) 0.0 else @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(count - 1));
            // Vary saturation and value while keeping hue constant
            const s = @max(0.2, @min(1.0, hsv.s * (0.5 + t * 0.5)));
            const v = @max(0.3, @min(1.0, hsv.v * (0.7 + t * 0.3)));
            colors[i] = hsvToRgb(HSVColor.init(hsv.h, s, v));
        }

        return colors;
    }
};

/// Color space conversion validation and utilities
pub const ColorSpaceUtils = struct {
    /// Validate RGB values are in range
    pub fn isValidRgb(r: i32, g: i32, b: i32) bool {
        return r >= 0 and r <= 255 and g >= 0 and g <= 255 and b >= 0 and b <= 255;
    }

    /// Clamp RGB values to valid range
    pub fn clampRgb(r: i32, g: i32, b: i32) RGBColor {
        return RGBColor.init(@intCast(@max(0, @min(255, r))), @intCast(@max(0, @min(255, g))), @intCast(@max(0, @min(255, b))));
    }

    /// Round-trip conversion test (RGB -> XYZ -> LAB -> XYZ -> RGB)
    pub fn testRoundTripConversion(rgb: RGBColor) struct { original: RGBColor, final: RGBColor, error_val: f64 } {
        const lab = rgbToLab(rgb);
        const final_rgb = labToRgb(lab);

        const orig_norm = rgb.toNormalized();
        const final_norm = final_rgb.toNormalized();

        const error_val = @sqrt(math.pow(f64, orig_norm.r - final_norm.r, 2) +
            math.pow(f64, orig_norm.g - final_norm.g, 2) +
            math.pow(f64, orig_norm.b - final_norm.b, 2));

        return .{ .original = rgb, .final = final_rgb, .error_val = error_val };
    }

    /// Get color space gamut coverage (rough estimation)
    pub fn estimateGamutCoverage(colors: []const RGBColor) struct {
        lab_volume: f64,
        hue_spread: f64,
        lightness_range: f64,
        chroma_range: f64,
    } {
        if (colors.len == 0) return .{ .lab_volume = 0, .hue_spread = 0, .lightness_range = 0, .chroma_range = 0 };

        var min_l: f64 = 100.0;
        var max_l: f64 = 0.0;
        var min_chroma: f64 = 1000.0;
        var max_chroma: f64 = 0.0;

        var hues = std.ArrayList(f64).init(std.testing.allocator);
        defer hues.deinit();

        for (colors) |color| {
            const lab = rgbToLab(color);
            const chroma_val = lab.chroma();
            const hue_val = lab.hue();

            min_l = @min(min_l, lab.l);
            max_l = @max(max_l, lab.l);
            min_chroma = @min(min_chroma, chroma_val);
            max_chroma = @max(max_chroma, chroma_val);

            hues.append(hue_val) catch {};
        }

        // Calculate rough volume in LAB space
        const lab_volume = (max_l - min_l) * (max_chroma - min_chroma) * (max_chroma - min_chroma);

        // Calculate hue spread
        var hue_spread: f64 = 0.0;
        if (hues.items.len > 1) {
            // Simple hue range calculation (could be improved for circular hue space)
            var min_hue: f64 = 360.0;
            var max_hue: f64 = -360.0;
            for (hues.items) |hue| {
                min_hue = @min(min_hue, hue);
                max_hue = @max(max_hue, hue);
            }
            hue_spread = max_hue - min_hue;
        }

        return .{
            .lab_volume = lab_volume,
            .hue_spread = hue_spread,
            .lightness_range = max_l - min_l,
            .chroma_range = max_chroma - min_chroma,
        };
    }
};

// Tests
const testing = std.testing;

test "RGB to HSV conversion" {
    const red = RGBColor.init(255, 0, 0);
    const hsv = rgbToHsv(red);

    try testing.expect(@abs(hsv.h - 0.0) < 1.0); // Hue should be ~0
    try testing.expect(@abs(hsv.s - 1.0) < 0.01); // Saturation should be 1
    try testing.expect(@abs(hsv.v - 1.0) < 0.01); // Value should be 1
}

test "HSV to RGB conversion" {
    const hsv = HSVColor.init(120.0, 1.0, 1.0); // Pure green
    const rgb = hsvToRgb(hsv);

    try testing.expect(rgb.r < 5); // Should be close to 0
    try testing.expect(rgb.g > 250); // Should be close to 255
    try testing.expect(rgb.b < 5); // Should be close to 0
}

test "RGB to HSL conversion" {
    const gray = RGBColor.init(128, 128, 128);
    const hsl = rgbToHsl(gray);

    try testing.expect(@abs(hsl.s - 0.0) < 0.01); // Should have no saturation
    try testing.expect(@abs(hsl.l - 0.5) < 0.02); // Should be ~50% lightness
}

test "RGB to LAB conversion" {
    const white = RGBColor.init(255, 255, 255);
    const lab = rgbToLab(white);

    // White should have L* close to 100, a* and b* close to 0
    try testing.expect(lab.l > 95.0 and lab.l <= 100.0);
    try testing.expect(@abs(lab.a) < 2.0);
    try testing.expect(@abs(lab.b) < 2.0);

    const black = RGBColor.init(0, 0, 0);
    const lab_black = rgbToLab(black);

    // Black should have L* close to 0
    try testing.expect(lab_black.l < 5.0);
}

test "color analysis" {
    const red = RGBColor.init(255, 0, 0);
    const blue = RGBColor.init(0, 0, 255);
    const gray = RGBColor.init(128, 128, 128);

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
    const blue = RGBColor.init(0, 0, 255);

    // Complementary should be roughly orange/yellow
    const comp = ColorHarmony.getComplementary(blue);
    const comp_hsv = rgbToHsv(comp);
    try testing.expect(@abs(comp_hsv.h - 60.0) < 30.0); // Should be around yellow-orange

    // Triadic colors
    const triadic = ColorHarmony.getTriadic(blue);
    try testing.expect(triadic.len == 2);
}

test "contrast ratio calculation" {
    const white = RGBColor.init(255, 255, 255);
    const black = RGBColor.init(0, 0, 0);

    const contrast = ColorAnalysis.getContrastRatio(black, white);
    try testing.expect(contrast > 15.0); // Should be high contrast

    // Test accessibility
    try testing.expect(ColorAnalysis.isAccessible(black, white, .AA));
    try testing.expect(ColorAnalysis.isAccessible(black, white, .AAA));
}

test "round-trip conversion accuracy" {
    const test_colors = [_]RGBColor{
        RGBColor.init(255, 0, 0), // Red
        RGBColor.init(0, 255, 0), // Green
        RGBColor.init(0, 0, 255), // Blue
        RGBColor.init(128, 128, 128), // Gray
        RGBColor.init(255, 128, 64), // Orange
    };

    for (test_colors) |color| {
        const result = ColorSpaceUtils.testRoundTripConversion(color);
        // Conversion should be reasonably accurate
        try testing.expect(result.err < 0.1);
    }
}

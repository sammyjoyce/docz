const std = @import("std");
const math = std.math;

/// Enhanced color distance calculation inspired by HSLuv and charmbracelet/x
/// Provides more perceptually accurate color matching than simple Euclidean distance
/// RGB color structure
pub const RGBColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RGBColor {
        return RGBColor{ .r = r, .g = g, .b = b };
    }

    pub fn fromU32(rgb: u32) RGBColor {
        return RGBColor{
            .r = @truncate((rgb >> 16) & 0xFF),
            .g = @truncate((rgb >> 8) & 0xFF),
            .b = @truncate(rgb & 0xFF),
        };
    }

    pub fn toU32(self: RGBColor) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }
};

/// LAB color representation for perceptual calculations
pub const LABColor = struct {
    l: f64, // Lightness (0-100)
    a: f64, // Green-Red axis (-128 to 127)
    b: f64, // Blue-Yellow axis (-128 to 127)

    pub fn init(l: f64, a: f64, b: f64) LABColor {
        return LABColor{ .l = l, .a = a, .b = b };
    }
};

/// Convert sRGB component to linear RGB
fn srgbToLinear(component: f64) f64 {
    if (component <= 0.04045) {
        return component / 12.92;
    } else {
        return math.pow(f64, (component + 0.055) / 1.055, 2.4);
    }
}

/// Convert linear RGB component to sRGB
fn linearToSrgb(component: f64) f64 {
    if (component <= 0.0031308) {
        return 12.92 * component;
    } else {
        return 1.055 * math.pow(f64, component, 1.0 / 2.4) - 0.055;
    }
}

/// Convert RGB to XYZ color space
pub fn rgbToXyz(rgb: RGBColor) struct { x: f64, y: f64, z: f64 } {
    // Normalize RGB values to 0-1
    const r_norm = @as(f64, @floatFromInt(rgb.r)) / 255.0;
    const g_norm = @as(f64, @floatFromInt(rgb.g)) / 255.0;
    const b_norm = @as(f64, @floatFromInt(rgb.b)) / 255.0;

    // Convert to linear RGB
    const r_lin = srgbToLinear(r_norm);
    const g_lin = srgbToLinear(g_norm);
    const b_lin = srgbToLinear(b_norm);

    // Apply sRGB to XYZ transformation matrix (D65 illuminant)
    const x = r_lin * 0.4124564 + g_lin * 0.3575761 + b_lin * 0.1804375;
    const y = r_lin * 0.2126729 + g_lin * 0.7151522 + b_lin * 0.0721750;
    const z = r_lin * 0.0193339 + g_lin * 0.1191920 + b_lin * 0.9503041;

    return .{ .x = x, .y = y, .z = z };
}

/// Convert XYZ to LAB color space
pub fn xyzToLab(xyz: struct { x: f64, y: f64, z: f64 }) LABColor {
    // D65 white point
    const xn = 0.95047;
    const yn = 1.00000;
    const zn = 1.08883;

    // Normalize by white point
    const fx = labF(xyz.x / xn);
    const fy = labF(xyz.y / yn);
    const fz = labF(xyz.z / zn);

    const l = 116.0 * fy - 16.0;
    const a = 500.0 * (fx - fy);
    const b = 200.0 * (fy - fz);

    return LABColor.init(l, a, b);
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

/// Convert RGB directly to LAB
pub fn rgbToLab(rgb: RGBColor) LABColor {
    const xyz = rgbToXyz(rgb);
    return xyzToLab(xyz);
}

/// Calculate Delta E CIE76 distance between two LAB colors
pub fn deltaE76(lab1: LABColor, lab2: LABColor) f64 {
    const dl = lab1.l - lab2.l;
    const da = lab1.a - lab2.a;
    const db = lab1.b - lab2.b;
    return @sqrt(dl * dl + da * da + db * db);
}

/// Calculate Delta E CIE94 distance (more accurate than CIE76)
pub fn deltaE94(lab1: LABColor, lab2: LABColor) f64 {
    const dl = lab1.l - lab2.l;
    const da = lab1.a - lab2.a;
    const db = lab1.b - lab2.b;

    const c1 = @sqrt(lab1.a * lab1.a + lab1.b * lab1.b);
    const c2 = @sqrt(lab2.a * lab2.a + lab2.b * lab2.b);
    const dc = c1 - c2;

    const dh_squared = da * da + db * db - dc * dc;
    const dh = if (dh_squared < 0) 0 else @sqrt(dh_squared);

    // CIE94 weighting factors (graphic arts)
    const kl = 1.0;
    const kc = 1.0;
    const kh = 1.0;
    const k1 = 0.045;
    const k2 = 0.015;

    const sl = 1.0;
    const sc = 1.0 + k1 * c1;
    const sh = 1.0 + k2 * c1;

    const dl_term = dl / (kl * sl);
    const dc_term = dc / (kc * sc);
    const dh_term = dh / (kh * sh);

    return @sqrt(dl_term * dl_term + dc_term * dc_term + dh_term * dh_term);
}

/// HSLuv-inspired perceptual distance calculation
/// This approximates the perceptual uniformity of HSLuv while being computationally efficient
pub fn perceptualDistance(rgb1: RGBColor, rgb2: RGBColor) f64 {
    // Convert to LAB for perceptual calculations
    const lab1 = rgbToLab(rgb1);
    const lab2 = rgbToLab(rgb2);

    // Use Delta E CIE94 for better perceptual accuracy
    return deltaE94(lab1, lab2);
}

/// Fast approximation of perceptual distance without full LAB conversion
/// Uses weighted RGB distance with perceptual adjustments
pub fn perceptualDistanceFast(rgb1: RGBColor, rgb2: RGBColor) f64 {
    const r1 = @as(f64, @floatFromInt(rgb1.r));
    const g1 = @as(f64, @floatFromInt(rgb1.g));
    const b1 = @as(f64, @floatFromInt(rgb1.b));
    const r2 = @as(f64, @floatFromInt(rgb2.r));
    const g2 = @as(f64, @floatFromInt(rgb2.g));
    const b2 = @as(f64, @floatFromInt(rgb2.b));

    // Calculate average red component for adaptive weighting
    const r_avg = (r1 + r2) / 2.0;

    // Delta components
    const dr = r1 - r2;
    const dg = g1 - g2;
    const db = b1 - b2;

    // Adaptive weights based on human vision sensitivity and red-green discrimination
    // These weights approximate the conversion to perceptual space
    const weight_r = 2.0 + r_avg / 256.0;
    const weight_g = 4.0; // Green has highest sensitivity
    const weight_b = 2.0 + (255.0 - r_avg) / 256.0;

    return @sqrt(weight_r * dr * dr + weight_g * dg * dg + weight_b * db * db);
}

/// Find the closest color in a palette using perceptual distance
pub fn findClosestColor(target: RGBColor, palette: []const RGBColor, use_fast: bool) struct { index: usize, distance: f64 } {
    if (palette.len == 0) return .{ .index = 0, .distance = math.inf(f64) };

    var best_index: usize = 0;
    var best_distance: f64 = math.inf(f64);

    for (palette, 0..) |color, i| {
        const distance = if (use_fast)
            perceptualDistanceFast(target, color)
        else
            perceptualDistance(target, color);

        if (distance < best_distance) {
            best_distance = distance;
            best_index = i;
        }
    }

    return .{ .index = best_index, .distance = best_distance };
}

/// Color difference thresholds for perceptual evaluation
pub const PerceptualThreshold = struct {
    pub const JUST_NOTICEABLE: f64 = 2.3; // Just noticeable difference
    pub const PERCEPTIBLE: f64 = 5.0; // Perceptible difference
    pub const OBVIOUS: f64 = 10.0; // Obvious difference
    pub const VERY_DIFFERENT: f64 = 50.0; // Very different colors
};

/// Evaluate perceptual difference category
pub fn evaluatePerceptualDifference(distance: f64) enum { identical, just_noticeable, perceptible, obvious, very_different } {
    if (distance < 1.0) return .identical;
    if (distance < PerceptualThreshold.JUST_NOTICEABLE) return .just_noticeable;
    if (distance < PerceptualThreshold.PERCEPTIBLE) return .perceptible;
    if (distance < PerceptualThreshold.OBVIOUS) return .obvious;
    return .very_different;
}

/// Enhanced color matching for terminal color conversion
pub const PerceptualColorMatcher = struct {
    const Self = @This();

    /// Find the best match in ANSI 16-color palette using perceptual distance
    pub fn matchAnsi16(target: RGBColor) struct { index: u8, distance: f64 } {
        const ansi_16_palette = [16]RGBColor{
            RGBColor.init(0x00, 0x00, 0x00), // Black
            RGBColor.init(0x80, 0x00, 0x00), // Maroon
            RGBColor.init(0x00, 0x80, 0x00), // Green
            RGBColor.init(0x80, 0x80, 0x00), // Olive
            RGBColor.init(0x00, 0x00, 0x80), // Navy
            RGBColor.init(0x80, 0x00, 0x80), // Purple
            RGBColor.init(0x00, 0x80, 0x80), // Teal
            RGBColor.init(0xC0, 0xC0, 0xC0), // Silver
            RGBColor.init(0x80, 0x80, 0x80), // Gray
            RGBColor.init(0xFF, 0x00, 0x00), // Red
            RGBColor.init(0x00, 0xFF, 0x00), // Lime
            RGBColor.init(0xFF, 0xFF, 0x00), // Yellow
            RGBColor.init(0x00, 0x00, 0xFF), // Blue
            RGBColor.init(0xFF, 0x00, 0xFF), // Fuchsia
            RGBColor.init(0x00, 0xFF, 0xFF), // Aqua
            RGBColor.init(0xFF, 0xFF, 0xFF), // White
        };

        const result = findClosestColor(target, &ansi_16_palette, false);
        return .{ .index = @intCast(result.index), .distance = result.distance };
    }

    /// Check if two colors are perceptually similar
    pub fn arePerceptuallySimilar(color1: RGBColor, color2: RGBColor, threshold: f64) bool {
        const distance = perceptualDistance(color1, color2);
        return distance <= threshold;
    }

    /// Get perceptual color category
    pub fn getColorCategory(rgb: RGBColor) enum { dark, light, saturated, desaturated, warm, cool } {
        const lab = rgbToLab(rgb);

        // Lightness-based categorization
        if (lab.l < 30.0) return .dark;
        if (lab.l > 80.0) return .light;

        // Saturation (chroma) in LAB space
        const chroma = @sqrt(lab.a * lab.a + lab.b * lab.b);
        if (chroma < 10.0) return .desaturated;
        if (chroma > 50.0) return .saturated;

        // Temperature based on a/b coordinates
        if (lab.a > 5.0) return .warm; // More red
        if (lab.b < -5.0) return .cool; // More blue

        return .desaturated; // Default fallback
    }
};

// Tests
const testing = std.testing;

test "RGB to LAB conversion" {
    // Test white point
    const white = RGBColor.init(255, 255, 255);
    const white_lab = rgbToLab(white);

    // White should have L* close to 100, a* and b* close to 0
    try testing.expect(white_lab.l > 95.0);
    try testing.expect(@abs(white_lab.a) < 2.0);
    try testing.expect(@abs(white_lab.b) < 2.0);

    // Test black point
    const black = RGBColor.init(0, 0, 0);
    const black_lab = rgbToLab(black);

    // Black should have L* close to 0
    try testing.expect(black_lab.l < 5.0);
}

test "perceptual distance calculation" {
    const red = RGBColor.init(255, 0, 0);
    const green = RGBColor.init(0, 255, 0);
    const dark_red = RGBColor.init(200, 0, 0);

    const red_to_green = perceptualDistance(red, green);
    const red_to_dark_red = perceptualDistance(red, dark_red);

    // Red should be perceptually closer to dark red than to green
    try testing.expect(red_to_dark_red < red_to_green);

    // Test fast approximation gives reasonable results
    const fast_red_green = perceptualDistanceFast(red, green);
    const fast_red_dark_red = perceptualDistanceFast(red, dark_red);

    try testing.expect(fast_red_dark_red < fast_red_green);
}

test "ANSI 16-color matching" {
    const pure_red = RGBColor.init(255, 0, 0);
    const match = PerceptualColorMatcher.matchAnsi16(pure_red);

    // Should match to bright red (index 9)
    try testing.expect(match.index == 9);

    // Test gray matching
    const gray = RGBColor.init(128, 128, 128);
    const gray_match = PerceptualColorMatcher.matchAnsi16(gray);

    // Should match to gray (index 8) or silver (index 7)
    try testing.expect(gray_match.index == 7 or gray_match.index == 8);
}

test "perceptual similarity" {
    const color1 = RGBColor.init(255, 100, 100);
    const color2 = RGBColor.init(250, 105, 95); // Very similar
    const color3 = RGBColor.init(100, 255, 100); // Very different

    try testing.expect(PerceptualColorMatcher.arePerceptuallySimilar(color1, color2, PerceptualThreshold.PERCEPTIBLE));
    try testing.expect(!PerceptualColorMatcher.arePerceptuallySimilar(color1, color3, PerceptualThreshold.PERCEPTIBLE));
}

test "color categorization" {
    const white = RGBColor.init(255, 255, 255);
    const black = RGBColor.init(0, 0, 0);
    const red = RGBColor.init(255, 0, 0);
    const blue = RGBColor.init(0, 0, 255);

    try testing.expect(PerceptualColorMatcher.getColorCategory(white) == .light);
    try testing.expect(PerceptualColorMatcher.getColorCategory(black) == .dark);
    try testing.expect(PerceptualColorMatcher.getColorCategory(red) == .saturated or
        PerceptualColorMatcher.getColorCategory(red) == .warm);
    try testing.expect(PerceptualColorMatcher.getColorCategory(blue) == .saturated or
        PerceptualColorMatcher.getColorCategory(blue) == .cool);
}

test "perceptual difference evaluation" {
    try testing.expect(evaluatePerceptualDifference(0.5) == .identical);
    try testing.expect(evaluatePerceptualDifference(3.0) == .perceptible);
    try testing.expect(evaluatePerceptualDifference(15.0) == .obvious);
    try testing.expect(evaluatePerceptualDifference(60.0) == .very_different);
}

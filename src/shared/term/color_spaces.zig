const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Maximum hue value (360 degrees)
pub const MAX_HUE = 360.0;
/// Minimum hue value (0 degrees)
pub const MIN_HUE = 0.0;
/// Maximum saturation/lightness/value (100%)
pub const MAX_SATURATION = 100.0;
/// Minimum saturation/lightness/value (0%)
pub const MIN_SATURATION = 0.0;
/// Maximum RGB component value
pub const MAX_RGB = 255.0;
/// Minimum RGB component value
pub const MIN_RGB = 0.0;

// WCAG contrast ratio thresholds
/// WCAG AA normal text minimum contrast ratio
pub const WCAG_AA_NORMAL = 4.5;
/// WCAG AA large text minimum contrast ratio
pub const WCAG_AA_LARGE = 3.0;
/// WCAG AAA normal text minimum contrast ratio
pub const WCAG_AAA_NORMAL = 7.0;
/// WCAG AAA large text minimum contrast ratio
pub const WCAG_AAA_LARGE = 4.5;

// ============================================================================
// Types
// ============================================================================

/// RGB color representation
pub const RGB = struct {
    /// Red component (0-255)
    r: f32,
    /// Green component (0-255)
    g: f32,
    /// Blue component (0-255)
    b: f32,

    /// Create RGB from normalized values (0.0-1.0)
    pub fn fromNormalized(r: f32, g: f32, b: f32) RGB {
        return RGB{
            .r = std.math.clamp(r * MAX_RGB, MIN_RGB, MAX_RGB),
            .g = std.math.clamp(g * MAX_RGB, MIN_RGB, MAX_RGB),
            .b = std.math.clamp(b * MAX_RGB, MIN_RGB, MAX_RGB),
        };
    }

    /// Convert to normalized values (0.0-1.0)
    pub fn toNormalized(self: RGB) struct { r: f32, g: f32, b: f32 } {
        return .{
            .r = self.r / MAX_RGB,
            .g = self.g / MAX_RGB,
            .b = self.b / MAX_RGB,
        };
    }

    /// Create RGB from hex string (e.g., "#FF0000" or "FF0000")
    pub fn fromHex(hex: []const u8) !RGB {
        if (hex.len != 6 and hex.len != 7) return error.InvalidHexLength;
        const start = if (hex.len == 7 and hex[0] == '#') 1 else 0;
        if (start + 6 != hex.len) return error.InvalidHexLength;

        const r = try std.fmt.parseInt(u8, hex[start .. start + 2], 16);
        const g = try std.fmt.parseInt(u8, hex[start + 2 .. start + 4], 16);
        const b = try std.fmt.parseInt(u8, hex[start + 4 .. start + 6], 16);

        return RGB{
            .r = @floatFromInt(r),
            .g = @floatFromInt(g),
            .b = @floatFromInt(b),
        };
    }

    /// Convert to hex string
    pub fn toHex(self: RGB, allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, "#{X:0>2}{X:0>2}{X:0>2}", .{ @as(u8, @intFromFloat(self.r)), @as(u8, @intFromFloat(self.g)), @as(u8, @intFromFloat(self.b)) });
    }
};

/// HSL color representation
pub const HSL = struct {
    /// Hue in degrees (0-360)
    h: f32,
    /// Saturation percentage (0-100)
    s: f32,
    /// Lightness percentage (0-100)
    l: f32,

    /// Create HSL with clamped values
    pub fn init(h: f32, s: f32, l: f32) HSL {
        return HSL{
            .h = std.math.clamp(h, MIN_HUE, MAX_HUE),
            .s = std.math.clamp(s, MIN_SATURATION, MAX_SATURATION),
            .l = std.math.clamp(l, MIN_SATURATION, MAX_SATURATION),
        };
    }
};

/// HSV color representation
pub const HSV = struct {
    /// Hue in degrees (0-360)
    h: f32,
    /// Saturation percentage (0-100)
    s: f32,
    /// Value/brightness percentage (0-100)
    v: f32,

    /// Create HSV with clamped values
    pub fn init(h: f32, s: f32, v: f32) HSV {
        return HSV{
            .h = std.math.clamp(h, MIN_HUE, MAX_HUE),
            .s = std.math.clamp(s, MIN_SATURATION, MAX_SATURATION),
            .v = std.math.clamp(v, MIN_SATURATION, MAX_SATURATION),
        };
    }
};

// ============================================================================
// HSL Functions
// ============================================================================

/// Convert RGB to HSL
/// Formula based on standard color space conversion algorithms
pub fn rgbToHsl(rgb: RGB) HSL {
    const norm = rgb.toNormalized();
    const r = norm.r;
    const g = norm.g;
    const b = norm.b;

    const max = @max(r, @max(g, b));
    const min = @min(r, @min(g, b));
    const delta = max - min;

    // Lightness
    const l = (max + min) / 2.0;

    // Saturation
    const s = if (delta == 0) 0 else delta / (1.0 - @abs(2.0 * l - 1.0));

    // Hue
    const h = if (delta == 0)
        0
    else if (max == r)
        60.0 * (@mod((g - b) / delta, 6.0))
    else if (max == g)
        60.0 * ((b - r) / delta + 2.0)
    else
        60.0 * ((r - g) / delta + 4.0);

    return HSL.init(h, s * 100.0, l * 100.0);
}

/// Convert HSL to RGB
/// Formula based on standard color space conversion algorithms
pub fn hslToRgb(hsl: HSL) RGB {
    const h = hsl.h / 360.0;
    const s = hsl.s / 100.0;
    const l = hsl.l / 100.0;

    const c = (1.0 - @abs(2.0 * l - 1.0)) * s;
    const x = c * (1.0 - @abs(@mod(h * 6.0, 2.0) - 1.0));
    const m = l - c / 2.0;

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    if (h >= 0 and h < 1.0 / 6.0) {
        r = c;
        g = x;
        b = 0;
    } else if (h >= 1.0 / 6.0 and h < 2.0 / 6.0) {
        r = x;
        g = c;
        b = 0;
    } else if (h >= 2.0 / 6.0 and h < 3.0 / 6.0) {
        r = 0;
        g = c;
        b = x;
    } else if (h >= 3.0 / 6.0 and h < 4.0 / 6.0) {
        r = 0;
        g = x;
        b = c;
    } else if (h >= 4.0 / 6.0 and h < 5.0 / 6.0) {
        r = x;
        g = 0;
        b = c;
    } else {
        r = c;
        g = 0;
        b = x;
    }

    return RGB.fromNormalized(r + m, g + m, b + m);
}

/// Adjust hue by specified degrees (-360 to 360)
pub fn adjustHue(hsl: HSL, degrees: f32) HSL {
    return HSL.init(hsl.h + degrees, hsl.s, hsl.l);
}

/// Adjust saturation by specified percentage (-100 to 100)
pub fn adjustSaturation(hsl: HSL, percentage: f32) HSL {
    return HSL.init(hsl.h, hsl.s + percentage, hsl.l);
}

/// Adjust lightness by specified percentage (-100 to 100)
pub fn adjustLightness(hsl: HSL, percentage: f32) HSL {
    return HSL.init(hsl.h, hsl.s, hsl.l + percentage);
}

/// Set absolute hue value
pub fn setHue(hsl: HSL, hue: f32) HSL {
    return HSL.init(hue, hsl.s, hsl.l);
}

/// Set absolute saturation value
pub fn setSaturation(hsl: HSL, saturation: f32) HSL {
    return HSL.init(hsl.h, saturation, hsl.l);
}

/// Set absolute lightness value
pub fn setLightness(hsl: HSL, lightness: f32) HSL {
    return HSL.init(hsl.h, hsl.s, lightness);
}

// ============================================================================
// HSV Functions
// ============================================================================

/// Convert RGB to HSV
/// Formula based on standard color space conversion algorithms
pub fn rgbToHsv(rgb: RGB) HSV {
    const norm = rgb.toNormalized();
    const r = norm.r;
    const g = norm.g;
    const b = norm.b;

    const max = @max(r, @max(g, b));
    const min = @min(r, @min(g, b));
    const delta = max - min;

    // Value
    const v = max;

    // Saturation
    const s = if (max == 0) 0 else delta / max;

    // Hue
    const h = if (delta == 0)
        0
    else if (max == r)
        60.0 * (@mod((g - b) / delta, 6.0))
    else if (max == g)
        60.0 * ((b - r) / delta + 2.0)
    else
        60.0 * ((r - g) / delta + 4.0);

    return HSV.init(h, s * 100.0, v * 100.0);
}

/// Convert HSV to RGB
/// Formula based on standard color space conversion algorithms
pub fn hsvToRgb(hsv: HSV) RGB {
    const h = hsv.h / 360.0;
    const s = hsv.s / 100.0;
    const v = hsv.v / 100.0;

    const c = v * s;
    const x = c * (1.0 - @abs(@mod(h * 6.0, 2.0) - 1.0));
    const m = v - c;

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    if (h >= 0 and h < 1.0 / 6.0) {
        r = c;
        g = x;
        b = 0;
    } else if (h >= 1.0 / 6.0 and h < 2.0 / 6.0) {
        r = x;
        g = c;
        b = 0;
    } else if (h >= 2.0 / 6.0 and h < 3.0 / 6.0) {
        r = 0;
        g = c;
        b = x;
    } else if (h >= 3.0 / 6.0 and h < 4.0 / 6.0) {
        r = 0;
        g = x;
        b = c;
    } else if (h >= 4.0 / 6.0 and h < 5.0 / 6.0) {
        r = x;
        g = 0;
        b = c;
    } else {
        r = c;
        g = 0;
        b = x;
    }

    return RGB.fromNormalized(r + m, g + m, b + m);
}

/// Adjust hue by specified degrees (-360 to 360)
pub fn adjustHueHsv(hsv: HSV, degrees: f32) HSV {
    return HSV.init(hsv.h + degrees, hsv.s, hsv.v);
}

/// Adjust saturation by specified percentage (-100 to 100)
pub fn adjustSaturationHsv(hsv: HSV, percentage: f32) HSV {
    return HSV.init(hsv.h, hsv.s + percentage, hsv.v);
}

/// Adjust value by specified percentage (-100 to 100)
pub fn adjustValue(hsv: HSV, percentage: f32) HSV {
    return HSV.init(hsv.h, hsv.s, hsv.v + percentage);
}

/// Set absolute hue value
pub fn setHueHsv(hsv: HSV, hue: f32) HSV {
    return HSV.init(hue, hsv.s, hsv.v);
}

/// Set absolute saturation value
pub fn setSaturationHsv(hsv: HSV, saturation: f32) HSV {
    return HSV.init(hsv.h, saturation, hsv.v);
}

/// Set absolute value
pub fn setValue(hsv: HSV, value: f32) HSV {
    return HSV.init(hsv.h, hsv.s, value);
}

// ============================================================================
// Color Harmony Functions
// ============================================================================

/// Generate complementary color (opposite on color wheel)
pub fn complementary(hsl: HSL) HSL {
    return adjustHue(hsl, 180.0);
}

/// Generate triadic colors (120 degrees apart)
pub fn triadic(hsl: HSL) struct { HSL, HSL } {
    const color1 = adjustHue(hsl, 120.0);
    const color2 = adjustHue(hsl, 240.0);
    return .{ color1, color2 };
}

/// Generate analogous colors (±30 degrees)
pub fn analogous(hsl: HSL) struct { HSL, HSL } {
    const color1 = adjustHue(hsl, 30.0);
    const color2 = adjustHue(hsl, -30.0);
    return .{ color1, color2 };
}

/// Generate split-complementary colors (150 and 210 degrees)
pub fn splitComplementary(hsl: HSL) struct { HSL, HSL } {
    const color1 = adjustHue(hsl, 150.0);
    const color2 = adjustHue(hsl, 210.0);
    return .{ color1, color2 };
}

/// Generate tetradic colors (90 degrees apart)
pub fn tetradic(hsl: HSL) struct { HSL, HSL, HSL } {
    const color1 = adjustHue(hsl, 90.0);
    const color2 = adjustHue(hsl, 180.0);
    const color3 = adjustHue(hsl, 270.0);
    return .{ color1, color2, color3 };
}

// ============================================================================
// Accessibility Functions
// ============================================================================

/// Calculate relative luminance of RGB color
/// Formula based on WCAG 2.1 guidelines
pub fn relativeLuminance(rgb: RGB) f32 {
    const norm = rgb.toNormalized();

    const ToLinear = struct {
        fn f(component: f32) f32 {
            return if (component <= 0.03928)
                component / 12.92
            else
                std.math.pow(f32, (component + 0.055) / 1.055, 2.4);
        }
    }.f;

    const r_linear = ToLinear(norm.r);
    const g_linear = ToLinear(norm.g);
    const b_linear = ToLinear(norm.b);

    return 0.2126 * r_linear + 0.7152 * g_linear + 0.0722 * b_linear;
}

/// Calculate contrast ratio between two colors
/// Formula: (L1 + 0.05) / (L2 + 0.05) where L1 >= L2
pub fn contrastRatio(color1: RGB, color2: RGB) f32 {
    const lum1 = relativeLuminance(color1);
    const lum2 = relativeLuminance(color2);

    const lighter = @max(lum1, lum2);
    const darker = @min(lum1, lum2);

    return (lighter + 0.05) / (darker + 0.05);
}

/// Check if contrast ratio meets WCAG AA standards
pub fn isWcagAaCompliant(color1: RGB, color2: RGB, is_large_text: bool) bool {
    const ratio = contrastRatio(color1, color2);
    return ratio >= if (is_large_text) WCAG_AA_LARGE else WCAG_AA_NORMAL;
}

/// Check if contrast ratio meets WCAG AAA standards
pub fn isWcagAaaCompliant(color1: RGB, color2: RGB, is_large_text: bool) bool {
    const ratio = contrastRatio(color1, color2);
    return ratio >= if (is_large_text) WCAG_AAA_LARGE else WCAG_AAA_NORMAL;
}

/// Suggest accessible text color for given background
/// Returns black or white based on which has better contrast
pub fn suggestAccessibleTextColor(background: RGB) RGB {
    const black = RGB{ .r = 0, .g = 0, .b = 0 };
    const white = RGB{ .r = 255, .g = 255, .b = 255 };

    const black_ratio = contrastRatio(background, black);
    const white_ratio = contrastRatio(background, white);

    return if (black_ratio > white_ratio) black else white;
}

/// Find color with minimum contrast requirement
/// Adjusts lightness to meet WCAG AA standards
pub fn ensureMinimumContrast(background: RGB, foreground: RGB, min_ratio: f32) RGB {
    const current_ratio = contrastRatio(background, foreground);

    if (current_ratio >= min_ratio) {
        return foreground;
    }

    // Convert to HSL for adjustment
    var hsl = rgbToHsl(foreground);
    const bg_lum = relativeLuminance(background);

    // Try adjusting lightness to improve contrast
    const step = 5.0; // percentage points
    const max_iterations = 20;

    var iterations: usize = 0;
    while (iterations < max_iterations) : (iterations += 1) {
        const test_rgb = hslToRgb(hsl);
        const test_ratio = contrastRatio(background, test_rgb);

        if (test_ratio >= min_ratio) {
            break;
        }

        // Adjust lightness based on background luminance
        if (bg_lum > 0.5) {
            // Dark background, make foreground darker
            hsl.l = @max(hsl.l - step, 0);
        } else {
            // Light background, make foreground lighter
            hsl.l = @min(hsl.l + step, 100);
        }
    }

    return hslToRgb(hsl);
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Clamp value to specified range
pub fn clamp(value: f32, min: f32, max: f32) f32 {
    return std.math.clamp(value, min, max);
}

/// Normalize angle to 0-360 range
pub fn normalizeHue(hue: f32) f32 {
    const normalized = @mod(hue, MAX_HUE);
    return if (normalized < 0) normalized + MAX_HUE else normalized;
}

/// Linear interpolation between two values
pub fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * std.math.clamp(t, 0.0, 1.0);
}

// ============================================================================
// Examples and Tests
// ============================================================================

/// Example usage demonstrating color space conversions
pub fn example() void {
    var stdout_buffer: [4096]u8 = undefined;
    const stdout_file = std.fs.File.stdout();
    var std_out = stdout_file.writer(&stdout_buffer);

    // Create a red color
    const red = RGB{ .r = 255, .g = 0, .b = 0 };

    // Convert to HSL and HSV
    const hsl = rgbToHsl(red);
    const hsv = rgbToHsv(red);

    std_out.print("Original RGB: ({d:.0}, {d:.0}, {d:.0})\n", .{ red.r, red.g, red.b }) catch {};
    std_out.print("HSL: ({d:.1}, {d:.1}%, {d:.1}%)\n", .{ hsl.h, hsl.s, hsl.l }) catch {};
    std_out.print("HSV: ({d:.1}, {d:.1}%, {d:.1}%)\n", .{ hsv.h, hsv.s, hsv.v }) catch {};

    // Generate complementary color
    const complementary_color = complementary(hsl);
    const comp_rgb = hslToRgb(complementary_color);

    std_out.print("Complementary: ({d:.0}, {d:.0}, {d:.0})\n", .{ comp_rgb.r, comp_rgb.g, comp_rgb.b }) catch {};

    // Check contrast with white background
    const white = RGB{ .r = 255, .g = 255, .b = 255 };
    const ratio = contrastRatio(red, white);
    const is_aa = isWcagAaCompliant(red, white, false);

    std_out.print("Contrast ratio with white: {d:.2}\n", .{ratio}) catch {};
    std_out.print("WCAG AA compliant: {}\n", .{is_aa}) catch {};
}

test "RGB to HSL conversion" {
    const red = RGB{ .r = 255, .g = 0, .b = 0 };
    const hsl = rgbToHsl(red);

    try std.testing.expectApproxEqAbs(hsl.h, 0.0, 0.1);
    try std.testing.expectApproxEqAbs(hsl.s, 100.0, 0.1);
    try std.testing.expectApproxEqAbs(hsl.l, 50.0, 0.1);
}

test "HSL to RGB conversion" {
    const hsl = HSL{ .h = 0, .s = 100, .l = 50 };
    const rgb = hslToRgb(hsl);

    try std.testing.expectApproxEqAbs(rgb.r, 255.0, 1.0);
    try std.testing.expectApproxEqAbs(rgb.g, 0.0, 1.0);
    try std.testing.expectApproxEqAbs(rgb.b, 0.0, 1.0);
}

test "RGB to HSV conversion" {
    const red = RGB{ .r = 255, .g = 0, .b = 0 };
    const hsv = rgbToHsv(red);

    try std.testing.expectApproxEqAbs(hsv.h, 0.0, 0.1);
    try std.testing.expectApproxEqAbs(hsv.s, 100.0, 0.1);
    try std.testing.expectApproxEqAbs(hsv.v, 100.0, 0.1);
}

test "HSV to RGB conversion" {
    const hsv = HSV{ .h = 0, .s = 100, .v = 100 };
    const rgb = hsvToRgb(hsv);

    try std.testing.expectApproxEqAbs(rgb.r, 255.0, 1.0);
    try std.testing.expectApproxEqAbs(rgb.g, 0.0, 1.0);
    try std.testing.expectApproxEqAbs(rgb.b, 0.0, 1.0);
}

test "Complementary color" {
    const hsl = HSL{ .h = 0, .s = 100, .l = 50 };
    const comp = complementary(hsl);

    try std.testing.expectApproxEqAbs(comp.h, 180.0, 0.1);
    try std.testing.expectApproxEqAbs(comp.s, 100.0, 0.1);
    try std.testing.expectApproxEqAbs(comp.l, 50.0, 0.1);
}

test "Contrast ratio" {
    const black = RGB{ .r = 0, .g = 0, .b = 0 };
    const white = RGB{ .r = 255, .g = 255, .b = 255 };

    const ratio = contrastRatio(black, white);
    try std.testing.expectApproxEqAbs(ratio, 21.0, 0.1);
}

test "WCAG compliance" {
    const black = RGB{ .r = 0, .g = 0, .b = 0 };
    const white = RGB{ .r = 255, .g = 255, .b = 255 };

    try std.testing.expect(isWcagAaCompliant(black, white, false));
    try std.testing.expect(isWcagAaaCompliant(black, white, false));
}

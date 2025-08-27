const std = @import("std");
const enhanced_color = @import("color.zig");

/// Adaptive colors that automatically adjust based on terminal theme
/// Advanced color adaptation system for modern terminals
/// Provides beautiful, ready-to-use color palettes for TUI applications
/// Adaptive color that has different values for light and dark themes
pub const AdaptiveColor = struct {
    light: enhanced_color.Color,
    dark: enhanced_color.Color,

    /// Get the appropriate color based on theme
    pub fn resolve(self: AdaptiveColor, is_dark_theme: bool) enhanced_color.Color {
        return if (is_dark_theme) self.dark else self.light;
    }

    /// Create an adaptive color from hex values
    pub fn fromHex(light_hex: u32, dark_hex: u32) AdaptiveColor {
        return AdaptiveColor{
            .light = enhanced_color.hex(light_hex),
            .dark = enhanced_color.hex(dark_hex),
        };
    }

    /// Create an adaptive color from RGB values
    pub fn fromRgb(light_r: u8, light_g: u8, light_b: u8, dark_r: u8, dark_g: u8, dark_b: u8) AdaptiveColor {
        return AdaptiveColor{
            .light = enhanced_color.rgb(light_r, light_g, light_b),
            .dark = enhanced_color.rgb(dark_r, dark_g, dark_b),
        };
    }
};

/// Beautiful color palette with modern terminal aesthetics
pub const Palette = struct {
    // Base colors
    pub const WHITE_BRIGHT = AdaptiveColor.fromHex(0xFFFDF5, 0xFFFDF5);

    pub const NORMAL = AdaptiveColor.fromHex(0x1A1A1A, 0xDDDDDD);
    pub const NORMAL_DIM = AdaptiveColor.fromHex(0xA49FA5, 0x777777);

    // Grays
    pub const GRAY = AdaptiveColor.fromHex(0x909090, 0x626262);
    pub const GRAY_MID = AdaptiveColor.fromHex(0xB2B2B2, 0x4A4A4A);
    pub const GRAY_DARK = AdaptiveColor.fromHex(0xDDDADA, 0x222222);
    pub const GRAY_BRIGHT = AdaptiveColor.fromHex(0x847A85, 0x979797);
    pub const GRAY_BRIGHT_DIM = AdaptiveColor.fromHex(0xC2B8C2, 0x4D4D4D);

    // Indigo/Purple spectrum
    pub const INDIGO = AdaptiveColor.fromHex(0x5A56E0, 0x7571F9);
    pub const INDIGO_DIM = AdaptiveColor.fromHex(0x9498FF, 0x494690);
    pub const INDIGO_SUBTLE = AdaptiveColor.fromHex(0x7D79F6, 0x514DC1);
    pub const INDIGO_SUBTLE_DIM = AdaptiveColor.fromHex(0xBBBDFF, 0x383584);

    // Green spectrum
    pub const YELLOW_GREEN = AdaptiveColor.fromHex(0x04B575, 0xECFD65);
    pub const YELLOW_GREEN_DULL = AdaptiveColor.fromHex(0x6BCB94, 0x9BA92F);
    pub const GREEN = AdaptiveColor{
        .light = enhanced_color.hex(0x04B575),
        .dark = enhanced_color.hex(0x04B575),
    };
    pub const GREEN_DIM = AdaptiveColor.fromHex(0x72D2B0, 0x0B5137);

    // Fuschia/Pink spectrum
    pub const FUSCHIA = AdaptiveColor.fromHex(0xEE6FF8, 0xEE6FF8);
    pub const FUSCHIA_DIM = AdaptiveColor.fromHex(0xF1A8FF, 0x99519E);
    pub const FUSCHIA_DULL = AdaptiveColor.fromHex(0xF793FF, 0xAD58B4);
    pub const FUSCHIA_DULL_DIM = AdaptiveColor.fromHex(0xF6C9FF, 0x6B3A6F);

    // Red spectrum
    pub const RED = AdaptiveColor.fromHex(0xFF4672, 0xED567A);
    pub const RED_DULL = AdaptiveColor.fromHex(0xFF6F91, 0xC74665);

    /// Get a color by name for dynamic color selection
    pub fn getByName(name: []const u8) ?AdaptiveColor {
        const ColorMap = std.StaticStringMap(AdaptiveColor);
        const color_map = ColorMap.initComptime(.{
            .{ "white_bright", WHITE_BRIGHT },
            .{ "normal", NORMAL },
            .{ "normal_dim", NORMAL_DIM },
            .{ "gray", GRAY },
            .{ "gray_mid", GRAY_MID },
            .{ "gray_dark", GRAY_DARK },
            .{ "gray_bright", GRAY_BRIGHT },
            .{ "gray_bright_dim", GRAY_BRIGHT_DIM },
            .{ "indigo", INDIGO },
            .{ "indigo_dim", INDIGO_DIM },
            .{ "indigo_subtle", INDIGO_SUBTLE },
            .{ "indigo_subtle_dim", INDIGO_SUBTLE_DIM },
            .{ "yellow_green", YELLOW_GREEN },
            .{ "yellow_green_dull", YELLOW_GREEN_DULL },
            .{ "green", GREEN },
            .{ "green_dim", GREEN_DIM },
            .{ "fuschia", FUSCHIA },
            .{ "fuschia_dim", FUSCHIA_DIM },
            .{ "fuschia_dull", FUSCHIA_DULL },
            .{ "fuschia_dull_dim", FUSCHIA_DULL_DIM },
            .{ "red", RED },
            .{ "red_dull", RED_DULL },
        });

        return color_map.get(name);
    }

    /// Get all available color names
    pub fn getAllNames(allocator: std.mem.Allocator) ![][]const u8 {
        const names = [_][]const u8{
            "white_bright", "normal",            "normal_dim",    "gray",
            "gray_mid",     "gray_dark",         "gray_bright",   "gray_bright_dim",
            "indigo",       "indigo_dim",        "indigo_subtle", "indigo_subtle_dim",
            "yellow_green", "yellow_green_dull", "green",         "green_dim",
            "fuschia",      "fuschia_dim",       "fuschia_dull",  "fuschia_dull_dim",
            "red",          "red_dull",
        };

        return try allocator.dupe([]const u8, &names);
    }
};

/// Predefined themes for common UI patterns
pub const Themes = struct {
    /// Dark theme optimized for readability
    pub const DARK = Theme{
        .background = Palette.gray_dark.dark,
        .foreground = Palette.normal.dark,
        .primary = Palette.indigo.dark,
        .secondary = Palette.yellow_green.dark,
        .accent = Palette.fuschia.dark,
        .muted = Palette.gray_bright_dim.dark,
        .err = Palette.red.dark,
        .warn = Palette.yellow_green_dull.dark,
        .success = Palette.green.dark,
        .info = Palette.indigo_subtle.dark,
    };

    /// Light theme optimized for readability
    pub const LIGHT = Theme{
        .background = Palette.white_bright.light,
        .foreground = Palette.normal.light,
        .primary = Palette.indigo.light,
        .secondary = Palette.yellow_green.light,
        .accent = Palette.fuschia.light,
        .muted = Palette.gray_bright_dim.light,
        .err = Palette.red.light,
        .warn = Palette.yellow_green_dull.light,
        .success = Palette.green.light,
        .info = Palette.indigo_subtle.light,
    };

    /// High contrast theme for accessibility
    pub const HIGH_CONTRAST = Theme{
        .background = enhanced_color.basic(.black),
        .foreground = enhanced_color.basic(.bright_white),
        .primary = enhanced_color.basic(.bright_blue),
        .secondary = enhanced_color.basic(.bright_green),
        .accent = enhanced_color.basic(.bright_magenta),
        .muted = enhanced_color.basic(.bright_black),
        .err = enhanced_color.basic(.bright_red),
        .warn = enhanced_color.basic(.bright_yellow),
        .success = enhanced_color.basic(.bright_green),
        .info = enhanced_color.basic(.bright_cyan),
    };

    /// Grayscale theme for minimal UIs
    pub const GRAYSCALE = Theme{
        .background = Palette.gray_dark.resolve(true),
        .foreground = Palette.normal.resolve(true),
        .primary = Palette.gray_bright.resolve(true),
        .secondary = Palette.gray.resolve(true),
        .accent = Palette.gray_bright_dim.resolve(true),
        .muted = Palette.gray_mid.resolve(true),
        .err = Palette.gray.resolve(true),
        .warn = Palette.gray_bright.resolve(true),
        .success = Palette.gray_bright_dim.resolve(true),
        .info = Palette.gray.resolve(true),
    };
};

/// Theme structure for consistent UI coloring
pub const Theme = struct {
    background: enhanced_color.Color,
    foreground: enhanced_color.Color,
    primary: enhanced_color.Color,
    secondary: enhanced_color.Color,
    accent: enhanced_color.Color,
    muted: enhanced_color.Color,
    err: enhanced_color.Color,
    warn: enhanced_color.Color,
    success: enhanced_color.Color,
    info: enhanced_color.Color,

    /// Create a custom adaptive theme
    pub fn adaptive(
        background: AdaptiveColor,
        foreground: AdaptiveColor,
        primary: AdaptiveColor,
        secondary: AdaptiveColor,
        accent: AdaptiveColor,
        muted: AdaptiveColor,
        err_color: AdaptiveColor,
        warn_color: AdaptiveColor,
        success: AdaptiveColor,
        info: AdaptiveColor,
        is_dark: bool,
    ) Theme {
        return Theme{
            .background = background.resolve(is_dark),
            .foreground = foreground.resolve(is_dark),
            .primary = primary.resolve(is_dark),
            .secondary = secondary.resolve(is_dark),
            .accent = accent.resolve(is_dark),
            .muted = muted.resolve(is_dark),
            .err = err_color.resolve(is_dark),
            .warn = warn_color.resolve(is_dark),
            .success = success.resolve(is_dark),
            .info = info.resolve(is_dark),
        };
    }

    /// Get the default adaptive theme (resolves based on is_dark)
    pub fn defaultAdaptive(is_dark: bool) Theme {
        return adaptive(
            Palette.gray_dark,
            Palette.normal,
            Palette.indigo,
            Palette.yellow_green,
            Palette.fuschia,
            Palette.gray_bright_dim,
            Palette.red,
            Palette.yellow_green_dull,
            Palette.green,
            Palette.indigo_subtle,
            is_dark,
        );
    }

    /// Convert theme to ANSI 16-color palette for compatibility
    pub fn to16Color(self: Theme) Theme16 {
        return Theme16{
            .background = enhanced_color.convert16(self.background),
            .foreground = enhanced_color.convert16(self.foreground),
            .primary = enhanced_color.convert16(self.primary),
            .secondary = enhanced_color.convert16(self.secondary),
            .accent = enhanced_color.convert16(self.accent),
            .muted = enhanced_color.convert16(self.muted),
            .err = enhanced_color.convert16(self.err),
            .warn = enhanced_color.convert16(self.warn),
            .success = enhanced_color.convert16(self.success),
            .info = enhanced_color.convert16(self.info),
        };
    }

    /// Convert theme to ANSI 256-color palette
    pub fn to256Color(self: Theme) Theme256 {
        return Theme256{
            .background = enhanced_color.convert256(self.background),
            .foreground = enhanced_color.convert256(self.foreground),
            .primary = enhanced_color.convert256(self.primary),
            .secondary = enhanced_color.convert256(self.secondary),
            .accent = enhanced_color.convert256(self.accent),
            .muted = enhanced_color.convert256(self.muted),
            .err = enhanced_color.convert256(self.err),
            .warn = enhanced_color.convert256(self.warn),
            .success = enhanced_color.convert256(self.success),
            .info = enhanced_color.convert256(self.info),
        };
    }
};

/// Theme using 16-color ANSI palette
pub const Theme16 = struct {
    background: enhanced_color.BasicColor,
    foreground: enhanced_color.BasicColor,
    primary: enhanced_color.BasicColor,
    secondary: enhanced_color.BasicColor,
    accent: enhanced_color.BasicColor,
    muted: enhanced_color.BasicColor,
    err: enhanced_color.BasicColor,
    warn: enhanced_color.BasicColor,
    success: enhanced_color.BasicColor,
    info: enhanced_color.BasicColor,
};

/// Theme using 256-color ANSI palette
pub const Theme256 = struct {
    background: enhanced_color.IndexedColor,
    foreground: enhanced_color.IndexedColor,
    primary: enhanced_color.IndexedColor,
    secondary: enhanced_color.IndexedColor,
    accent: enhanced_color.IndexedColor,
    muted: enhanced_color.IndexedColor,
    err: enhanced_color.IndexedColor,
    warn: enhanced_color.IndexedColor,
    success: enhanced_color.IndexedColor,
    info: enhanced_color.IndexedColor,
};

/// Color scheme generator for automatic palette creation
pub const ColorScheme = struct {
    /// Generate a monochromatic color scheme from a base color
    pub fn monochromatic(allocator: std.mem.Allocator, base_color: enhanced_color.RGBColor, steps: u8) ![]enhanced_color.Color {
        var colors = try allocator.alloc(enhanced_color.Color, steps);

        const base_hsv = rgbToHsv(base_color);

        for (0..steps) |i| {
            const lightness = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps - 1));
            const hsv = HSV{
                .h = base_hsv.h,
                .s = base_hsv.s,
                .v = lightness,
            };
            const rgb = hsvToRgb(hsv);
            colors[i] = enhanced_color.Color{ .rgb = rgb };
        }

        return colors;
    }

    /// Generate an analogous color scheme (colors next to each other on color wheel)
    pub fn analogous(allocator: std.mem.Allocator, base_color: enhanced_color.RGBColor) ![]enhanced_color.Color {
        var colors = try allocator.alloc(enhanced_color.Color, 3);

        const base_hsv = rgbToHsv(base_color);

        // Base color
        colors[0] = enhanced_color.Color{ .rgb = base_color };

        // +30 degrees
        const hsv1 = HSV{
            .h = @mod(base_hsv.h + 30.0, 360.0),
            .s = base_hsv.s,
            .v = base_hsv.v,
        };
        colors[1] = enhanced_color.Color{ .rgb = hsvToRgb(hsv1) };

        // -30 degrees
        const hsv2 = HSV{
            .h = @mod(base_hsv.h - 30.0 + 360.0, 360.0),
            .s = base_hsv.s,
            .v = base_hsv.v,
        };
        colors[2] = enhanced_color.Color{ .rgb = hsvToRgb(hsv2) };

        return colors;
    }

    /// Generate a complementary color scheme (opposite colors on color wheel)
    pub fn complementary(allocator: std.mem.Allocator, base_color: enhanced_color.RGBColor) ![]enhanced_color.Color {
        var colors = try allocator.alloc(enhanced_color.Color, 2);

        const base_hsv = rgbToHsv(base_color);

        // Base color
        colors[0] = enhanced_color.Color{ .rgb = base_color };

        // Complementary (+180 degrees)
        const hsv_comp = HSV{
            .h = @mod(base_hsv.h + 180.0, 360.0),
            .s = base_hsv.s,
            .v = base_hsv.v,
        };
        colors[1] = enhanced_color.Color{ .rgb = hsvToRgb(hsv_comp) };

        return colors;
    }

    /// Generate a triadic color scheme (3 colors evenly spaced on color wheel)
    pub fn triadic(allocator: std.mem.Allocator, base_color: enhanced_color.RGBColor) ![]enhanced_color.Color {
        var colors = try allocator.alloc(enhanced_color.Color, 3);

        const base_hsv = rgbToHsv(base_color);

        // Base color
        colors[0] = enhanced_color.Color{ .rgb = base_color };

        // +120 degrees
        const hsv1 = HSV{
            .h = @mod(base_hsv.h + 120.0, 360.0),
            .s = base_hsv.s,
            .v = base_hsv.v,
        };
        colors[1] = enhanced_color.Color{ .rgb = hsvToRgb(hsv1) };

        // +240 degrees
        const hsv2 = HSV{
            .h = @mod(base_hsv.h + 240.0, 360.0),
            .s = base_hsv.s,
            .v = base_hsv.v,
        };
        colors[2] = enhanced_color.Color{ .rgb = hsvToRgb(hsv2) };

        return colors;
    }
};

/// HSV color representation for color scheme generation
const HSV = struct {
    h: f64, // 0-360
    s: f64, // 0-1
    v: f64, // 0-1
};

/// Convert RGB to HSV
fn rgbToHsv(rgb: enhanced_color.RGBColor) HSV {
    const r = @as(f64, @floatFromInt(rgb.r)) / 255.0;
    const g = @as(f64, @floatFromInt(rgb.g)) / 255.0;
    const b = @as(f64, @floatFromInt(rgb.b)) / 255.0;

    const max_val = @max(@max(r, g), b);
    const min_val = @min(@min(r, g), b);
    const delta = max_val - min_val;

    // Value
    const v = max_val;

    // Saturation
    const s = if (max_val == 0.0) 0.0 else delta / max_val;

    // Hue
    var h: f64 = 0.0;
    if (delta != 0.0) {
        if (max_val == r) {
            h = 60.0 * @mod((g - b) / delta, 6.0);
        } else if (max_val == g) {
            h = 60.0 * ((b - r) / delta + 2.0);
        } else if (max_val == b) {
            h = 60.0 * ((r - g) / delta + 4.0);
        }
    }

    if (h < 0.0) h += 360.0;

    return HSV{ .h = h, .s = s, .v = v };
}

/// Convert HSV to RGB
fn hsvToRgb(hsv: HSV) enhanced_color.RGBColor {
    const c = hsv.v * hsv.s;
    const x = c * (1.0 - @abs(@mod(hsv.h / 60.0, 2.0) - 1.0));
    const m = hsv.v - c;

    var r_prime: f64 = 0;
    var g_prime: f64 = 0;
    var b_prime: f64 = 0;

    if (hsv.h < 60.0) {
        r_prime = c;
        g_prime = x;
        b_prime = 0;
    } else if (hsv.h < 120.0) {
        r_prime = x;
        g_prime = c;
        b_prime = 0;
    } else if (hsv.h < 180.0) {
        r_prime = 0;
        g_prime = c;
        b_prime = x;
    } else if (hsv.h < 240.0) {
        r_prime = 0;
        g_prime = x;
        b_prime = c;
    } else if (hsv.h < 300.0) {
        r_prime = x;
        g_prime = 0;
        b_prime = c;
    } else {
        r_prime = c;
        g_prime = 0;
        b_prime = x;
    }

    return enhanced_color.RGBColor{
        .r = @as(u8, @intFromFloat((r_prime + m) * 255.0)),
        .g = @as(u8, @intFromFloat((g_prime + m) * 255.0)),
        .b = @as(u8, @intFromFloat((b_prime + m) * 255.0)),
    };
}

/// Terminal theme detector (basic heuristic)
pub const ThemeDetector = struct {
    /// Try to detect if terminal is using dark theme
    /// This is a best-effort approach since there's no reliable way to detect this
    pub fn isDarkTheme(allocator: std.mem.Allocator) bool {
        // Check environment variables first
        if (std.process.getEnvVarOwned(allocator, "COLORFGBG")) |colorfgbg| {
            defer allocator.free(colorfgbg);

            // COLORFGBG format is usually "foreground;background"
            // High background numbers typically indicate dark themes
            if (std.mem.lastIndexOfScalar(u8, colorfgbg, ';')) |sep_pos| {
                const bg_str = colorfgbg[sep_pos + 1 ..];
                if (std.fmt.parseInt(u8, bg_str, 10)) |bg_num| {
                    return bg_num < 8; // Colors 0-7 are dark, 8-15 are bright
                } else |_| {}
            }
        } else |_| {}

        // Check TERM_PROGRAM for known terminals with dark defaults
        if (std.process.getEnvVarOwned(allocator, "TERM_PROGRAM")) |term_program| {
            defer allocator.free(term_program);

            if (std.mem.eql(u8, term_program, "vscode") or
                std.mem.eql(u8, term_program, "Hyper") or
                std.mem.indexOf(u8, term_program, "Dark") != null)
            {
                return true;
            }
        } else |_| {}

        // Default to dark theme (most modern terminals default to dark)
        return true;
    }

    /// Get the appropriate theme based on detection
    pub fn getAdaptiveTheme(allocator: std.mem.Allocator) Theme {
        const is_dark = isDarkTheme(allocator);
        return Theme.defaultAdaptive(is_dark);
    }
};

/// Convenience functions for quick color access
pub fn primaryColor(is_dark: bool) enhanced_color.Color {
    return Palette.indigo.resolve(is_dark);
}

pub fn secondaryColor(is_dark: bool) enhanced_color.Color {
    return Palette.yellow_green.resolve(is_dark);
}

pub fn accentColor(is_dark: bool) enhanced_color.Color {
    return Palette.fuschia.resolve(is_dark);
}

pub fn errorColor(is_dark: bool) enhanced_color.Color {
    return Palette.red.resolve(is_dark);
}

pub fn successColor(is_dark: bool) enhanced_color.Color {
    return Palette.green.resolve(is_dark);
}

pub fn warningColor(is_dark: bool) enhanced_color.Color {
    return Palette.yellow_green_dull.resolve(is_dark);
}

pub fn infoColor(is_dark: bool) enhanced_color.Color {
    return Palette.indigo_subtle.resolve(is_dark);
}

pub fn mutedColor(is_dark: bool) enhanced_color.Color {
    return Palette.gray_bright_dim.resolve(is_dark);
}

// Tests
test "adaptive color resolution" {
    const testing = std.testing;

    const adaptive = AdaptiveColor.fromHex(0xFF0000, 0x00FF00);

    const light_result = adaptive.resolve(false);
    const dark_result = adaptive.resolve(true);

    // Should get different colors for different themes
    try testing.expect(!light_result.equal(dark_result));
}

test "theme creation and conversion" {
    const testing = std.testing;

    const theme = Themes.dark;

    // Test 256-color conversion
    const theme256 = theme.to256Color();
    try testing.expect(@intFromEnum(theme256.background) != @intFromEnum(theme256.foreground));

    // Test 16-color conversion - just ensure it doesn't crash
    const theme16 = theme.to16Color();
    _ = theme16; // Suppress unused variable warning

    // Test high contrast theme which should definitely have different colors
    const hc_theme = Themes.high_contrast;
    const hc_theme16 = hc_theme.to16Color();
    try testing.expect(hc_theme16.background != hc_theme16.foreground);
}

test "color scheme generation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const base_color = enhanced_color.RGBColor{ .r = 128, .g = 64, .b = 192 };

    // Test monochromatic scheme
    const mono_scheme = try ColorScheme.monochromatic(allocator, base_color, 5);
    defer allocator.free(mono_scheme);
    try testing.expect(mono_scheme.len == 5);

    // Test complementary scheme
    const comp_scheme = try ColorScheme.complementary(allocator, base_color);
    defer allocator.free(comp_scheme);
    try testing.expect(comp_scheme.len == 2);

    // Test triadic scheme
    const triadic_scheme = try ColorScheme.triadic(allocator, base_color);
    defer allocator.free(triadic_scheme);
    try testing.expect(triadic_scheme.len == 3);
}

test "color palette lookup" {
    const testing = std.testing;

    const indigo_color = Palette.getByName("indigo");
    try testing.expect(indigo_color != null);

    const nonexistent = Palette.getByName("nonexistent");
    try testing.expect(nonexistent == null);
}

test "hsv color conversion" {
    const testing = std.testing;

    const rgb = enhanced_color.RGBColor{ .r = 255, .g = 0, .b = 0 }; // Red
    const hsv = rgbToHsv(rgb);
    const rgb_back = hsvToRgb(hsv);

    // Should be close to original (allowing for rounding errors)
    try testing.expect(@abs(@as(i16, rgb_back.r) - @as(i16, rgb.r)) <= 1);
    try testing.expect(@abs(@as(i16, rgb_back.g) - @as(i16, rgb.g)) <= 1);
    try testing.expect(@abs(@as(i16, rgb_back.b) - @as(i16, rgb.b)) <= 1);
}

test "theme detector" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Theme detector should not crash and should return a valid theme
    const detected_theme = ThemeDetector.getAdaptiveTheme(allocator);

    // Basic sanity check - theme colors should be different
    try testing.expect(!detected_theme.background.equal(detected_theme.foreground));
}

//! DEPRECATED: Unified Color Management System
//! Comprehensive color handling for terminal applications
//!
//! ⚠️  DEPRECATED: This module has been replaced by the new ANSI color system
//!    located at `src/shared/term/ansi/color/`. Please use `term.ansi.color`
//!    or the convenience export `term.color` instead.
//!
//! This module consolidates all color functionality from 15+ scattered files
//! into a clean, organized structure with no duplication.
//!
//! Modules:
//! - types: Core color type definitions (RGB, HSL, HSV, Lab, XYZ, Terminal colors)
//! - conversions: Color space conversion algorithms
//! - distance: Color distance and matching algorithms
//! - terminal: Terminal color operations and ANSI sequences
//! - palettes: Color palettes and theme management

const std = @import("std");

// === BARREL EXPORTS ===

// Core types
pub const types = @import("types.zig");
pub const RGB = types.RGB;
pub const RGBA = types.RGBA;
pub const RGBf = types.RGBf;
pub const HSL = types.HSL;
pub const HSV = types.HSV;
pub const Lab = types.Lab;
pub const XYZ = types.XYZ;
pub const Ansi16 = types.Ansi16;
pub const Ansi256 = types.Ansi256;
pub const TerminalColor = types.TerminalColor;
pub const ColorError = types.ColorError;
pub const NamedColors = types.NamedColors;

// Conversions
pub const conversions = @import("conversions.zig");
pub const rgbToHsl = conversions.rgbToHsl;
pub const hslToRgb = conversions.hslToRgb;
pub const rgbToHsv = conversions.rgbToHsv;
pub const hsvToRgb = conversions.hsvToRgb;
pub const rgbToXyz = conversions.rgbToXyz;
pub const xyzToRgb = conversions.xyzToRgb;
pub const xyzToLab = conversions.xyzToLab;
pub const labToXyz = conversions.labToXyz;
pub const rgbToLab = conversions.rgbToLab;
pub const labToRgb = conversions.labToRgb;
pub const rgbToAnsi256 = conversions.rgbToAnsi256;
pub const ansi256ToRgb = conversions.ansi256ToRgb;

// Distance calculations
pub const distance = @import("distance.zig");
pub const rgbEuclidean = distance.rgbEuclidean;
pub const rgbWeighted = distance.rgbWeighted;
pub const deltaE76 = distance.deltaE76;
pub const deltaE94 = distance.deltaE94;
pub const deltaE2000 = distance.deltaE2000;
pub const hslDistance = distance.hslDistance;
pub const DistanceAlgorithm = distance.DistanceAlgorithm;
pub const findClosestColor = distance.findClosestColor;
pub const areColorsSimilar = distance.areColorsSimilar;

// Terminal operations
pub const terminal = @import("terminal.zig");
pub const ColorLayer = terminal.ColorLayer;
pub const toAnsiSequence = terminal.toAnsiSequence;
pub const AnsiBuilder = terminal.AnsiBuilder;
pub const ColorMode = terminal.ColorMode;
pub const downgradeColor = terminal.downgradeColor;
pub const parseHex = terminal.parseHex;
pub const parseRgb = terminal.parseRgb;
pub const relativeLuminance = terminal.relativeLuminance;
pub const contrastRatio = terminal.contrastRatio;
pub const meetsWcagAa = terminal.meetsWcagAa;
pub const meetsWcagAaa = terminal.meetsWcagAaa;

// Palettes and themes
pub const palettes = @import("palettes.zig");
pub const StandardPalette = palettes.StandardPalette;
pub const Theme = palettes.Theme;
pub const ansi16_palette = palettes.ansi16_palette;
pub const generateWebSafePalette = palettes.generateWebSafePalette;
pub const generateAnsi256Palette = palettes.generateAnsi256Palette;
pub const generateGradient = palettes.generateGradient;
pub const generateRainbow = palettes.generateRainbow;
pub const generateMonochrome = palettes.generateMonochrome;
pub const generateAnalogous = palettes.generateAnalogous;
pub const generateComplementary = palettes.generateComplementary;
pub const generateTriadic = palettes.generateTriadic;
pub const findTheme = palettes.findTheme;
pub const solarized_dark = palettes.solarized_dark;
pub const solarized_light = palettes.solarized_light;
pub const dracula = palettes.dracula;
pub const monokai = palettes.monokai;
pub const themes = palettes.themes;

// === HIGH-LEVEL CONVENIENCE API ===

/// Quick color creation from various formats
pub const Color = struct {
    /// Create from RGB values
    pub fn fromRgb(r: u8, g: u8, b: u8) RGB {
        return RGB.init(r, g, b);
    }

    /// Create from hex value
    pub fn fromHex(hex: u32) RGB {
        return RGB.fromHex(hex);
    }

    /// Parse from string (hex or rgb format)
    pub fn fromString(str: []const u8) !RGB {
        if (str.len > 0 and (str[0] == '#' or std.ascii.isHex(str[0]))) {
            return parseHex(str);
        } else {
            return parseRgb(str);
        }
    }

    /// Create from HSL values
    pub fn fromHsl(h: f32, s: f32, l: f32) RGB {
        const hsl = HSL.init(h, s, l);
        return hslToRgb(hsl);
    }

    /// Create from HSV values
    pub fn fromHsv(h: f32, s: f32, v: f32) RGB {
        const hsv = HSV.init(h, s, v);
        return hsvToRgb(hsv);
    }
};

/// Quick terminal color styling
pub const Style = struct {
    allocator: std.mem.Allocator,
    builder: AnsiBuilder,

    pub fn init(allocator: std.mem.Allocator) Style {
        return .{
            .allocator = allocator,
            .builder = AnsiBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *Style) void {
        self.builder.deinit();
    }

    pub fn fg(self: *Style, color: RGB) !*Style {
        try self.builder.setForeground(.{ .rgb = color });
        return self;
    }

    pub fn bg(self: *Style, color: RGB) !*Style {
        try self.builder.setBackground(.{ .rgb = color });
        return self;
    }

    pub fn bold(self: *Style) !*Style {
        try self.builder.bold();
        return self;
    }

    pub fn italic(self: *Style) !*Style {
        try self.builder.italic();
        return self;
    }

    pub fn underline(self: *Style) !*Style {
        try self.builder.underline();
        return self;
    }

    pub fn text(self: *Style, str: []const u8) !*Style {
        try self.builder.text(str);
        return self;
    }

    pub fn reset(self: *Style) !*Style {
        try self.builder.reset();
        return self;
    }

    pub fn build(self: *Style) []const u8 {
        return self.builder.build();
    }
};

// === COMMON USE CASES ===

/// Get the best contrasting color (black or white) for a given background
pub fn bestContrast(background: RGB) RGB {
    const black = RGB.init(0, 0, 0);
    const white = RGB.init(255, 255, 255);

    const black_ratio = contrastRatio(black, background);
    const white_ratio = contrastRatio(white, background);

    return if (white_ratio > black_ratio) white else black;
}

/// Mix two colors with a given ratio (0.0 = first color, 1.0 = second color)
pub fn mixColors(color1: RGB, color2: RGB, ratio: f32) RGB {
    const r = std.math.clamp(ratio, 0.0, 1.0);
    const inv_r = 1.0 - r;

    return RGB.init(
        @intFromFloat(@as(f32, @floatFromInt(color1.r)) * inv_r + @as(f32, @floatFromInt(color2.r)) * r),
        @intFromFloat(@as(f32, @floatFromInt(color1.g)) * inv_r + @as(f32, @floatFromInt(color2.g)) * r),
        @intFromFloat(@as(f32, @floatFromInt(color1.b)) * inv_r + @as(f32, @floatFromInt(color2.b)) * r),
    );
}

/// Lighten a color by a percentage (0-100)
pub fn lighten(color: RGB, percent: f32) RGB {
    const hsl = rgbToHsl(color);
    const new_l = @min(100.0, hsl.l + percent);
    const new_hsl = HSL.init(hsl.h, hsl.s, new_l);
    return hslToRgb(new_hsl);
}

/// Darken a color by a percentage (0-100)
pub fn darken(color: RGB, percent: f32) RGB {
    const hsl = rgbToHsl(color);
    const new_l = @max(0.0, hsl.l - percent);
    const new_hsl = HSL.init(hsl.h, hsl.s, new_l);
    return hslToRgb(new_hsl);
}

/// Saturate a color by a percentage (0-100)
pub fn saturate(color: RGB, percent: f32) RGB {
    const hsl = rgbToHsl(color);
    const new_s = @min(100.0, hsl.s + percent);
    const new_hsl = HSL.init(hsl.h, new_s, hsl.l);
    return hslToRgb(new_hsl);
}

/// Desaturate a color by a percentage (0-100)
pub fn desaturate(color: RGB, percent: f32) RGB {
    const hsl = rgbToHsl(color);
    const new_s = @max(0.0, hsl.s - percent);
    const new_hsl = HSL.init(hsl.h, new_s, hsl.l);
    return hslToRgb(new_hsl);
}

/// Convert a color to grayscale
pub fn grayscale(color: RGB) RGB {
    const gray = @as(u8, @intFromFloat(relativeLuminance(color) * 255.0));
    return RGB.init(gray, gray, gray);
}

/// Invert a color
pub fn invert(color: RGB) RGB {
    return RGB.init(255 - color.r, 255 - color.g, 255 - color.b);
}

// === TESTS ===

test "Color convenience API" {
    const red = Color.fromRgb(255, 0, 0);
    try std.testing.expectEqual(@as(u8, 255), red.r);
    try std.testing.expectEqual(@as(u8, 0), red.g);
    try std.testing.expectEqual(@as(u8, 0), red.b);

    const hex_color = Color.fromHex(0xFF8040);
    try std.testing.expectEqual(@as(u8, 255), hex_color.r);
    try std.testing.expectEqual(@as(u8, 128), hex_color.g);
    try std.testing.expectEqual(@as(u8, 64), hex_color.b);

    const parsed = try Color.fromString("#FF0000");
    try std.testing.expectEqual(@as(u8, 255), parsed.r);
    try std.testing.expectEqual(@as(u8, 0), parsed.g);
    try std.testing.expectEqual(@as(u8, 0), parsed.b);
}

test "Style builder" {
    const allocator = std.testing.allocator;
    var style = Style.init(allocator);
    defer style.deinit();

    const red = RGB.init(255, 0, 0);
    const blue = RGB.init(0, 0, 255);

    _ = try style.fg(red);
    _ = try style.bg(blue);
    _ = try style.bold();
    _ = try style.text("Hello");
    _ = try style.reset();

    const result = style.build();
    try std.testing.expect(result.len > 0);
}

test "Color manipulation" {
    const red = RGB.init(255, 0, 0);

    // Darken red by 20%
    const dark_red = darken(red, 20);
    const dark_hsl = rgbToHsl(dark_red);
    try std.testing.expect(dark_hsl.l < 50);

    // Lighten red by 20%
    const light_red = lighten(red, 20);
    const light_hsl = rgbToHsl(light_red);
    try std.testing.expect(light_hsl.l > 50);

    // Desaturate to gray
    const gray_red = desaturate(red, 100);
    const gray_hsl = rgbToHsl(gray_red);
    try std.testing.expectApproxEqAbs(@as(f32, 0), gray_hsl.s, 1.0);

    // Invert color
    const cyan = invert(red);
    try std.testing.expectEqual(@as(u8, 0), cyan.r);
    try std.testing.expectEqual(@as(u8, 255), cyan.g);
    try std.testing.expectEqual(@as(u8, 255), cyan.b);
}

test "Best contrast" {
    const dark_bg = RGB.init(32, 32, 32);
    const light_bg = RGB.init(224, 224, 224);

    const best_for_dark = bestContrast(dark_bg);
    try std.testing.expectEqual(@as(u8, 255), best_for_dark.r); // Should be white

    const best_for_light = bestContrast(light_bg);
    try std.testing.expectEqual(@as(u8, 0), best_for_light.r); // Should be black
}

test "Mix colors" {
    const red = RGB.init(255, 0, 0);
    const blue = RGB.init(0, 0, 255);

    // 50% mix should be purple
    const purple = mixColors(red, blue, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 127), @as(f32, @floatFromInt(purple.r)), 2);
    try std.testing.expectEqual(@as(u8, 0), purple.g);
    try std.testing.expectApproxEqAbs(@as(f32, 127), @as(f32, @floatFromInt(purple.b)), 2);

    // 0% mix should be first color
    const red_again = mixColors(red, blue, 0.0);
    try std.testing.expect(red_again.equals(red));

    // 100% mix should be second color
    const blue_again = mixColors(red, blue, 1.0);
    try std.testing.expect(blue_again.equals(blue));
}

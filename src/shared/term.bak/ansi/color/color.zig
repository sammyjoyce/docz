//! Color Management System
//! Consolidated color primitives that support all terminal contexts (CLI, TUI, Renderer)

const std = @import("std");
const ansi_color = @import("mod.zig");

/// Unified Color type that supports all terminal contexts
pub const Color = struct {
    /// RGB representation (24-bit true color)
    rgb: ansi_color.types.RGB,

    /// ANSI 256-color index
    ansi256: u8,

    /// ANSI 16-color index
    ansi16: u8,

    /// Human-readable name
    name: []const u8,

    /// Optional alpha channel (0.0-1.0, used for blending)
    alpha: f32 = 1.0,

    const Self = @This();

    /// Create a new Color with automatic ANSI conversion
    pub fn init(name: []const u8, rgb: ansi_color.types.RGB, alpha: f32) Self {
        const ansi256 = ansi_color.conversions.rgbToAnsi256(rgb);
        const ansi16 = ansi_color.conversions.ansi256ToAnsi16(ansi256);

        return Self{
            .rgb = rgb,
            .ansi256 = ansi256,
            .ansi16 = ansi16,
            .name = name,
            .alpha = alpha,
        };
    }

    /// Create from RGB values
    pub fn fromRgb(name: []const u8, r: u8, g: u8, b: u8, alpha: f32) Self {
        const rgb = ansi_color.types.RGB.init(r, g, b);
        return init(name, rgb, alpha);
    }

    /// Create from hex string (#RRGGBB or RRGGBB)
    pub fn fromHex(name: []const u8, hex: []const u8, alpha: f32) !Self {
        const hex_color = try ansi_color.types.HexColor.fromString(hex);
        return init(name, hex_color.toRgb(), alpha);
    }

    /// Create from HSL values
    pub fn fromHsl(name: []const u8, h: f32, s: f32, l: f32, alpha: f32) Self {
        const hsl = ansi_color.types.HSL.init(h, s, l);
        const rgb = ansi_color.conversions.hslToRgb(hsl);
        return init(name, rgb, alpha);
    }

    /// Create from HSV values
    pub fn fromHsv(name: []const u8, h: f32, s: f32, v: f32, alpha: f32) Self {
        const hsv = ansi_color.types.HSV.init(h, s, v);
        const rgb = ansi_color.conversions.hsvToRgb(hsv);
        return init(name, rgb, alpha);
    }

    /// Convert to ANSI escape sequence for foreground
    pub fn toAnsiForeground(self: Self, allocator: std.mem.Allocator) ![]u8 {
        const seq = ansi_color.terminal.formatRgbFg(self.rgb);
        return allocator.dupe(u8, seq);
    }

    /// Convert to ANSI escape sequence for background
    pub fn toAnsiBackground(self: Self, allocator: std.mem.Allocator) ![]u8 {
        const seq = ansi_color.terminal.formatRgbBg(self.rgb);
        return allocator.dupe(u8, seq);
    }

    /// Convert to hex string
    pub fn toHex(self: Self, allocator: std.mem.Allocator) ![]u8 {
        const hex_color = ansi_color.types.HexColor.init((@as(u32, self.rgb.r) << 16) | (@as(u32, self.rgb.g) << 8) | @as(u32, self.rgb.b));
        return try hex_color.toString(allocator);
    }

    /// Blend this color with another color
    pub fn blend(self: Self, other: Self, t: f32, allocator: std.mem.Allocator) !Self {
        const clamped_t = @max(0.0, @min(1.0, t));

        const r = @as(u8, @intFromFloat(@round(@as(f32, @floatFromInt(self.rgb.r)) * (1.0 - clamped_t) + @as(f32, @floatFromInt(other.rgb.r)) * clamped_t)));
        const g = @as(u8, @intFromFloat(@round(@as(f32, @floatFromInt(self.rgb.g)) * (1.0 - clamped_t) + @as(f32, @floatFromInt(other.rgb.g)) * clamped_t)));
        const b = @as(u8, @intFromFloat(@round(@as(f32, @floatFromInt(self.rgb.b)) * (1.0 - clamped_t) + @as(f32, @floatFromInt(other.rgb.b)) * clamped_t)));
        const alpha = self.alpha * (1.0 - clamped_t) + other.alpha * clamped_t;

        const rgb = ansi_color.types.RGB.init(r, g, b);
        const blended_name = try std.fmt.allocPrint(allocator, "{s}_blend_{s}", .{ self.name, other.name });

        return init(blended_name, rgb, alpha);
    }

    /// Get the luminance of this color
    pub fn luminance(self: Self) f32 {
        return ansi_color.terminal.relativeLuminance(self.rgb);
    }

    /// Calculate contrast ratio with another color
    pub fn contrastRatio(self: Self, other: Self) f32 {
        return ansi_color.terminal.contrastRatio(self.rgb, other.rgb);
    }

    /// Check if this color meets accessibility standards with another color
    pub fn isAccessible(self: Self, other: Self, level: enum { AA, AAA }) bool {
        const ratio = ansi_color.terminal.contrastRatio(self.rgb, other.rgb);
        return switch (level) {
            .AA => ratio >= 4.5,
            .AAA => ratio >= 7.0,
        };
    }

    /// Lighten the color by a factor
    pub fn lighten(self: Self, factor: f32, allocator: std.mem.Allocator) !Self {
        const hsl = ansi_color.conversions.rgbToHsl(self.rgb);
        const new_l = @min(100.0, hsl.l + factor * 100.0);
        const new_hsl = ansi_color.types.HSL.init(hsl.h, hsl.s, new_l);
        const new_rgb = ansi_color.conversions.hslToRgb(new_hsl);
        const new_name = try std.fmt.allocPrint(allocator, "{s}_lighter", .{self.name});
        return init(new_name, new_rgb, self.alpha);
    }

    /// Darken the color by a factor
    pub fn darken(self: Self, factor: f32, allocator: std.mem.Allocator) !Self {
        const hsl = ansi_color.conversions.rgbToHsl(self.rgb);
        const new_l = @max(0.0, hsl.l - factor * 100.0);
        const new_hsl = ansi_color.types.HSL.init(hsl.h, hsl.s, new_l);
        const new_rgb = ansi_color.conversions.hslToRgb(new_hsl);
        const new_name = try std.fmt.allocPrint(allocator, "{s}_darker", .{self.name});
        return init(new_name, new_rgb, self.alpha);
    }

    /// Saturate the color by a factor
    pub fn saturate(self: Self, factor: f32, allocator: std.mem.Allocator) !Self {
        const hsl = ansi_color.conversions.rgbToHsl(self.rgb);
        const new_s = @min(100.0, hsl.s + factor * 100.0);
        const new_hsl = ansi_color.types.HSL.init(hsl.h, new_s, hsl.l);
        const new_rgb = ansi_color.conversions.hslToRgb(new_hsl);
        const new_name = try std.fmt.allocPrint(allocator, "{s}_saturated", .{self.name});
        return init(new_name, new_rgb, self.alpha);
    }

    /// Desaturate the color by a factor
    pub fn desaturate(self: Self, factor: f32, allocator: std.mem.Allocator) !Self {
        const hsl = ansi_color.conversions.rgbToHsl(self.rgb);
        const new_s = @max(0.0, hsl.s - factor * 100.0);
        const new_hsl = ansi_color.types.HSL.init(hsl.h, new_s, hsl.l);
        const new_rgb = ansi_color.conversions.hslToRgb(new_hsl);
        const new_name = try std.fmt.allocPrint(allocator, "{s}_desaturated", .{self.name});
        return init(new_name, new_rgb, self.alpha);
    }

    /// Get complementary color
    pub fn complementary(self: Self, allocator: std.mem.Allocator) !Self {
        const hsl = ansi_color.conversions.rgbToHsl(self.rgb);
        const comp_hue = @mod(hsl.h + 180.0, 360.0);
        const comp_hsl = ansi_color.types.HSL.init(comp_hue, hsl.s, hsl.l);
        const comp_rgb = ansi_color.conversions.hslToRgb(comp_hsl);
        const comp_name = try std.fmt.allocPrint(allocator, "{s}_complement", .{self.name});
        return init(comp_name, comp_rgb, self.alpha);
    }

    /// Check if color is dark
    pub fn isDark(self: Self) bool {
        return self.luminance() < 0.5;
    }

    /// Check if color is light
    pub fn isLight(self: Self) bool {
        return self.luminance() >= 0.5;
    }
};

/// Predefined colors for common use cases
pub const Colors = struct {
    // Basic colors
    pub const BLACK = Color.fromRgb("black", 0, 0, 0, 1.0);
    pub const WHITE = Color.fromRgb("white", 255, 255, 255, 1.0);
    pub const RED = Color.fromRgb("red", 255, 0, 0, 1.0);
    pub const GREEN = Color.fromRgb("green", 0, 255, 0, 1.0);
    pub const BLUE = Color.fromRgb("blue", 0, 0, 255, 1.0);
    pub const YELLOW = Color.fromRgb("yellow", 255, 255, 0, 1.0);
    pub const MAGENTA = Color.fromRgb("magenta", 255, 0, 255, 1.0);
    pub const CYAN = Color.fromRgb("cyan", 0, 255, 255, 1.0);

    // Bright variants
    pub const BRIGHT_BLACK = Color.fromRgb("bright_black", 128, 128, 128, 1.0);
    pub const BRIGHT_RED = Color.fromRgb("bright_red", 255, 128, 128, 1.0);
    pub const BRIGHT_GREEN = Color.fromRgb("bright_green", 128, 255, 128, 1.0);
    pub const BRIGHT_BLUE = Color.fromRgb("bright_blue", 128, 128, 255, 1.0);
    pub const BRIGHT_YELLOW = Color.fromRgb("bright_yellow", 255, 255, 128, 1.0);
    pub const BRIGHT_MAGENTA = Color.fromRgb("bright_magenta", 255, 128, 255, 1.0);
    pub const BRIGHT_CYAN = Color.fromRgb("bright_cyan", 128, 255, 255, 1.0);
    pub const BRIGHT_WHITE = Color.fromRgb("bright_white", 255, 255, 255, 1.0);

    // Semantic colors
    pub const SUCCESS = GREEN;
    pub const WARNING = YELLOW;
    pub const ERROR = RED;
    pub const INFO = CYAN;
    pub const PRIMARY = BLUE;
    pub const SECONDARY = MAGENTA;
    pub const ACCENT = CYAN;
};

test "color creation and conversion" {
    const testing = std.testing;

    // Test RGB creation
    const red = Color.fromRgb("red", 255, 0, 0, 1.0);
    try testing.expect(red.rgb.r == 255);
    try testing.expect(red.rgb.g == 0);
    try testing.expect(red.rgb.b == 0);

    // Test hex creation
    const blue = try Color.fromHex("blue", "#0000FF", 1.0);
    try testing.expect(blue.rgb.b == 255);

    // Test HSL creation
    const green = Color.fromHsl("green", 120.0, 1.0, 0.5, 1.0);
    try testing.expect(green.rgb.g > 250); // Should be close to 255

    // Test HSV creation
    const purple = Color.fromHsv("purple", 270.0, 1.0, 1.0, 1.0);
    try testing.expect(purple.rgb.r > 200 and purple.rgb.b > 200);
}

test "color manipulation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const red = Color.fromRgb("red", 255, 0, 0, 1.0);

    // Test lightening
    const lighter = try red.lighten(0.2, allocator);
    defer allocator.free(lighter.name);
    try testing.expect(lighter.rgb.r == 255); // Red channel should stay max
    try testing.expect(lighter.rgb.g > 0); // Green channel should increase

    // Test darkening
    const darker = try red.darken(0.2, allocator);
    defer allocator.free(darker.name);
    try testing.expect(darker.rgb.r < 255); // Red channel should decrease

    // Test saturation
    const saturated = try red.saturate(0.1, allocator);
    defer allocator.free(saturated.name);
    try testing.expect(saturated.rgb.r == 255); // Should stay saturated

    // Test complementary
    const complement = try red.complementary(allocator);
    defer allocator.free(complement.name);
    try testing.expect(complement.rgb.b > 200); // Complement of red should be cyan-ish
}

test "color accessibility" {
    const testing = std.testing;

    const black = Colors.BLACK;
    const white = Colors.WHITE;

    // Test contrast ratio
    const contrast = black.contrastRatio(white);
    try testing.expect(contrast > 15.0); // High contrast expected

    // Test accessibility
    try testing.expect(black.isAccessible(white, .AA));
    try testing.expect(black.isAccessible(white, .AAA));
}

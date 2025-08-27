//! Theme Utilities
//! Helper functions for theme management and application

const std = @import("std");
const colors = @import("colors.zig");
const default_theme = @import("default_theme.zig");
const dark_theme = @import("dark_theme.zig");
const light_theme = @import("light_theme.zig");
const high_contrast_theme = @import("high_contrast_theme.zig");

/// Available themes
pub const ThemeType = enum {
    default,
    dark,
    light,
    high_contrast,

    /// Get theme name as string
    pub fn toString(self: ThemeType) []const u8 {
        return switch (self) {
            .default => "default",
            .dark => "dark",
            .light => "light",
            .high_contrast => "high_contrast",
        };
    }

    /// Parse theme name from string
    pub fn fromString(name: []const u8) ?ThemeType {
        if (std.mem.eql(u8, name, "default")) return .default;
        if (std.mem.eql(u8, name, "dark")) return .dark;
        if (std.mem.eql(u8, name, "light")) return .light;
        if (std.mem.eql(u8, name, "high_contrast")) return .high_contrast;
        return null;
    }
};

/// Theme manager for switching and applying themes
pub const ThemeHandler = struct {
    currentTheme: ThemeType = .default,

    /// Initialize theme manager
    pub fn init() ThemeHandler {
        return .{};
    }

    /// Set current theme
    pub fn setTheme(self: *ThemeHandler, theme: ThemeType) void {
        self.currentTheme = theme;
    }

    /// Get current theme colors
    pub fn getColors(self: ThemeHandler) colors.SemanticColors {
        return switch (self.currentTheme) {
            .default => default_theme.DEFAULT_THEME.colors,
            .dark => dark_theme.DARK_THEME.colors,
            .light => light_theme.LIGHT_THEME.colors,
            .high_contrast => high_contrast_theme.HIGH_CONTRAST_THEME.colors,
        };
    }

    /// Get theme description
    pub fn getDescription(self: ThemeHandler) []const u8 {
        return switch (self.currentTheme) {
            .default => default_theme.DEFAULT_THEME.getDescription(),
            .dark => dark_theme.DARK_THEME.getDescription(),
            .light => light_theme.LIGHT_THEME.getDescription(),
            .high_contrast => high_contrast_theme.HIGH_CONTRAST_THEME.getDescription(),
        };
    }

    /// Check if current theme is compatible with terminal capabilities
    pub fn isCompatible(self: ThemeHandler, caps: anytype) bool {
        return switch (self.currentTheme) {
            .default => default_theme.DEFAULT_THEME.isCompatible(caps),
            .dark => dark_theme.DARK_THEME.isCompatible(caps),
            .light => light_theme.LIGHT_THEME.isCompatible(caps),
            .high_contrast => high_contrast_theme.HIGH_CONTRAST_THEME.isCompatible(caps),
        };
    }

    /// Apply current theme settings
    pub fn applySettings(self: ThemeHandler, writer: anytype, caps: anytype) !void {
        switch (self.currentTheme) {
            .default => try default_theme.DEFAULT_THEME.applySettings(writer, caps),
            .dark => try dark_theme.DARK_THEME.applySettings(writer, caps),
            .light => light_theme.LIGHT_THEME.applySettings(writer, caps),
            .high_contrast => try high_contrast_theme.HIGH_CONTRAST_THEME.applySettings(writer, caps),
        }
    }

    /// Get list of all available themes
    pub fn getAvailableThemes() []const ThemeType {
        return &[_]ThemeType{ .default, .dark, .light, .high_contrast };
    }

    /// Auto-detect best theme based on environment
    pub fn detectBestTheme(self: *ThemeHandler) void {
        // Simple heuristics for theme detection
        // Could be enhanced with environment variable checks, time-based switching, etc.
        if (std.os.getenv("TERM_PROGRAM")) |term_program| {
            if (std.mem.indexOf(u8, term_program, "iTerm") != null or
                std.mem.indexOf(u8, term_program, "Terminal") != null)
            {
                self.currentTheme = .dark; // Default to dark for modern terminals
                return;
            }
        }

        // Default fallback
        self.currentTheme = .default;
    }
};

/// Utility functions for color operations
pub const ColorUtils = struct {
    /// Blend two colors
    pub fn blendColors(color1: colors.RgbColor, color2: colors.RgbColor, ratio: f32) colors.RgbColor {
        const inv_ratio = 1.0 - ratio;
        return colors.RgbColor.init(
            @as(u8, @intFromFloat(@as(f32, @floatFromInt(color1.r)) * inv_ratio + @as(f32, @floatFromInt(color2.r)) * ratio)),
            @as(u8, @intFromFloat(@as(f32, @floatFromInt(color1.g)) * inv_ratio + @as(f32, @floatFromInt(color2.g)) * ratio)),
            @as(u8, @intFromFloat(@as(f32, @floatFromInt(color1.b)) * inv_ratio + @as(f32, @floatFromInt(color2.b)) * ratio)),
        );
    }

    /// Calculate color contrast ratio
    pub fn contrastRatio(color1: colors.RgbColor, color2: colors.RgbColor) f32 {
        const lum1 = luminance(color1);
        const lum2 = luminance(color2);
        const lighter = @max(lum1, lum2);
        const darker = @min(lum1, lum2);
        return (lighter + 0.05) / (darker + 0.05);
    }

    /// Calculate relative luminance of a color
    fn luminance(color: colors.RgbColor) f32 {
        const r = srgbToLinear(@as(f32, @floatFromInt(color.r)) / 255.0);
        const g = srgbToLinear(@as(f32, @floatFromInt(color.g)) / 255.0);
        const b = srgbToLinear(@as(f32, @floatFromInt(color.b)) / 255.0);
        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    /// Convert sRGB to linear RGB
    fn srgbToLinear(c: f32) f32 {
        if (c <= 0.03928) {
            return c / 12.92;
        } else {
            return std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
        }
    }
};

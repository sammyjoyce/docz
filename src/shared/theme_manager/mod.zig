//! Theme Management System
//! Provides comprehensive theme management with persistence, customization,
//! accessibility features, and cross-platform support

const std = @import("std");
const builtin = @import("builtin");
const term = @import("term_shared");

pub const ThemeManager = @import("theme.zig").ThemeManager;
pub const ThemeConfig = @import("theme_config.zig").ThemeConfig;
pub const ColorScheme = @import("color_scheme.zig").ColorScheme;
pub const Color = @import("color.zig").Color;
pub const Colors = @import("color.zig").Colors;
pub const ThemeInheritance = @import("theme_inheritance.zig").ThemeInheritance;
pub const ThemeEditor = @import("theme_editor.zig").ThemeEditor;
pub const ThemeExporter = @import("theme_exporter.zig").ThemeExporter;
pub const SystemThemeDetector = @import("system_theme.zig").SystemThemeDetector;
pub const AccessibilityManager = @import("accessibility.zig").AccessibilityManager;
pub const ColorBlindnessAdapter = @import("color_blindness.zig").ColorBlindnessAdapter;
pub const ThemeValidator = @import("theme_validator.zig").ThemeValidator;
pub const ThemeDevelopmentTools = @import("theme_development_tools.zig").ThemeDevelopmentTools;

/// Initialize the global theme manager
pub fn init(allocator: std.mem.Allocator) !*ThemeManager {
    return ThemeManager.init(allocator);
}

/// Quick access to common theme operations
pub const Quick = struct {
    /// Switch to a theme by name
    pub fn switchTheme(manager: *ThemeManager, themeName: []const u8) !void {
        try manager.switchTheme(themeName);
    }

    /// Get current active theme
    pub fn getCurrentTheme(manager: *ThemeManager) *ColorScheme {
        return manager.getCurrentTheme();
    }

    /// Auto-detect and apply system theme
    pub fn applySystemTheme(manager: *ThemeManager) !void {
        const detector = SystemThemeDetector.init();
        const isDark = try detector.detectSystemTheme();
        const themeName = if (isDark) "dark" else "light";
        try manager.switchTheme(themeName);
    }

    /// Generate high contrast version of current theme
    pub fn generateHighContrast(manager: *ThemeManager) !*ColorScheme {
        const accessibility = AccessibilityManager.init(manager.allocator);
        return try accessibility.generateHighContrastTheme(manager.getCurrentTheme());
    }
};

test "theme manager initialization" {
    const allocator = std.testing.allocator;
    const manager = try init(allocator);
    defer manager.deinit();

    try std.testing.expect(manager.themes.count() > 0);
}

//! Theme System
//! Provides comprehensive theme management with persistence, customization,
//! accessibility features, and cross-platform support
//!
//! Compile-time Options
//! - Define `pub const shared_options = @import("src/shared/mod.zig").Options{ ... };` at root,
//!   or provide any struct; fields are discovered with `@hasField`.
//! - This module reads optional fields: `theme_enable_tools`,
//!   `theme_enable_accessibility`, `theme_default_scheme`.

const std = @import("std");
const builtin = @import("builtin");
const term = @import("term_shared");
const root = @import("root");
const shared = @import("../mod.zig");

// -----------------------------------------------------------------------------
// Compile-time Options for theme subsystem
// -----------------------------------------------------------------------------
/// Theme-level feature flags. Override via `root.shared_options` fields prefixed
/// with `theme_` or copy this struct to your agent to gate features.
pub const Options = struct {
    enable_tools: bool = true, // editor/exporter/development utilities
    enable_accessibility: bool = true, // color blindness transforms, HC variants
    default_scheme: ?[]const u8 = null, // e.g., "light" | "dark"
};

/// Resolve options from `root.shared_options` if present.
pub const options: Options = blk: {
    const defaults = Options{};
    if (@hasDecl(root, "shared_options")) {
        const T = @TypeOf(root.shared_options);
        break :blk Options{
            .enable_tools = if (@hasField(T, "theme_enable_tools")) @field(root.shared_options, "theme_enable_tools") else defaults.enable_tools,
            .enable_accessibility = if (@hasField(T, "theme_enable_accessibility")) @field(root.shared_options, "theme_enable_accessibility") else defaults.enable_accessibility,
            .default_scheme = if (@hasField(T, "theme_default_scheme")) @field(root.shared_options, "theme_default_scheme") else defaults.default_scheme,
        };
    }
    break :blk defaults;
};

// Runtime exports - always available
pub const Theme = @import("runtime/Theme.zig").Theme;
pub const Settings = @import("runtime/config.zig").Settings;
pub const ColorScheme = @import("runtime/ColorScheme.zig").ColorScheme;
pub const Color = @import("runtime/Color.zig").Color;
pub const Colors = @import("runtime/Color.zig").Colors;
pub const Inheritance = @import("runtime/Inheritance.zig").Inheritance;
pub const SystemTheme = @import("runtime/SystemTheme.zig").SystemTheme;
pub const Accessibility = @import("runtime/Accessibility.zig").Accessibility;
pub const ColorBlindness = @import("runtime/ColorBlindness.zig").ColorBlindness;
pub const Validator = @import("runtime/Validator.zig").Validator;
pub const Platform = @import("runtime/Platform.zig").Platform;

// Development tools - exported when tools are included
pub const Editor = @import("tools/Editor.zig").Editor;
pub const Exporter = @import("tools/Exporter.zig").Exporter;
pub const Development = @import("tools/Development.zig").Development;
pub const Generator = @import("tools/Generator.zig").Generator;

/// Initialize the global theme manager
pub fn init(allocator: std.mem.Allocator) !*Theme {
    return Theme.init(allocator);
}

/// Quick access to common theme operations
pub const Quick = struct {
    /// Switch to a theme by name
    pub fn switchTheme(manager: *Theme, themeName: []const u8) !void {
        try manager.switchTheme(themeName);
    }

    /// Get current active theme
    pub fn getCurrentTheme(manager: *Theme) *ColorScheme {
        return manager.getCurrentTheme();
    }

    /// Auto-detect and apply system theme
    pub fn applySystemTheme(manager: *Theme) !void {
        const systemTheme = SystemTheme.init();
        const isDark = try systemTheme.detectSystemTheme();
        const themeName = if (isDark) "dark" else "light";
        try manager.switchTheme(themeName);
    }

    /// Generate high contrast version of current theme
    pub fn generateHighContrast(manager: *Theme) !*ColorScheme {
        const accessibility = Accessibility.init(manager.allocator);
        return try accessibility.generateHighContrastTheme(manager.getCurrentTheme());
    }
};

test "theme manager initialization" {
    const allocator = std.testing.allocator;
    const manager = try init(allocator);
    defer manager.deinit();

    try std.testing.expect(manager.themes.count() > 0);
}

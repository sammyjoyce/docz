//! CLI Themes and Styling System
//! Provides consistent colors, styling, and terminal adaptations

pub const DefaultTheme = @import("default_theme.zig");
pub const DarkTheme = @import("dark_theme.zig");
pub const LightTheme = @import("light_theme.zig");
pub const HighContrastTheme = @import("high_contrast_theme.zig");

pub const ThemeColors = @import("colors.zig");
pub const ThemeManager = @import("theme_manager.zig");

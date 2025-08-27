//! CLI Themes and Styling System
//! Provides consistent colors, styling, and terminal adaptations

pub const DefaultTheme = @import("default.zig");
pub const DarkTheme = @import("dark.zig");
pub const LightTheme = @import("light.zig");
pub const HighContrastTheme = @import("high_contrast.zig");

pub const ThemeColors = @import("colors.zig");
pub const ThemeUtils = @import("utils.zig");

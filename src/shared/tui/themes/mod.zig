//! TUI Themes Module
//!
//! Consolidated theme system from existing src/tui/themes

// Re-export existing theme system
pub const Theme = @import("default.zig").Theme;
pub const DefaultTheme = @import("default.zig");

// Rich theme system
pub const RichColor = @import("rich.zig").Color;
pub const RichTheme = @import("rich.zig").Theme;
pub const ThemeManager = @import("rich.zig").ThemeManager;

// Additional theme definitions
pub const Color = Theme.Color;
pub const ColorEnum = @import("default.zig").ColorEnum;
pub const Box = Theme.Box;
pub const Status = Theme.Status;
pub const Progress = Theme.Progress;

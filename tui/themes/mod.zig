//! TUI Themes Module
//!
//! Consolidated theme system from existing src/tui/themes

// Re-export existing theme system
pub const Theme = @import("../../src/tui/themes/default.zig").Theme;
pub const DefaultTheme = @import("../../src/tui/themes/default.zig");

// Additional theme definitions
pub const Color = Theme.Color;
pub const Box = Theme.Box;
pub const Status = Theme.Status;
pub const Progress = Theme.Progress;
//! TUI framework module exports
const std = @import("std");

// Core components
pub const events = @import("core/events.zig");
pub const bounds = @import("core/bounds.zig");
pub const layout = @import("core/layout.zig");
pub const screen = @import("core/screen.zig");

// Widgets
pub const progress = @import("widgets/progress.zig");
pub const text_input = @import("widgets/text_input.zig");
pub const tabs = @import("widgets/tabs.zig");

// Themes
pub const themes = @import("themes/default.zig");

// Re-export commonly used types for convenience
pub const MouseEvent = events.MouseEvent;
pub const MouseHandler = events.MouseHandler;
pub const KeyEvent = events.KeyEvent;
pub const KeyboardHandler = events.KeyboardHandler;
pub const ShortcutRegistry = events.ShortcutRegistry;

pub const Bounds = bounds.Bounds;
pub const Point = bounds.Point;
pub const TerminalSize = bounds.TerminalSize;
pub const getTerminalSize = bounds.getTerminalSize;

pub const Layout = layout.Layout;
pub const Direction = layout.Direction;
pub const Alignment = layout.Alignment;
pub const Size = layout.Size;

pub const Screen = screen.Screen;
pub const clearScreen = screen.clearScreen;
pub const moveCursor = screen.moveCursor;
pub const clearLines = screen.clearLines;

pub const ProgressBar = progress.ProgressBar;
pub const TextInput = text_input.TextInput;
pub const TabContainer = tabs.TabContainer;

pub const Color = themes.Color;
pub const Box = themes.Box;
pub const Status = themes.Status;
pub const Progress = themes.Progress;
pub const Theme = themes.Theme;

// Terminal capabilities
pub const TermCaps = @import("../term/caps.zig").TermCaps;

// Utility functions
pub const parseSgrMouseEvent = events.parseSgrMouseEvent;

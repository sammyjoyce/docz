//! ANSI Terminal Control Sequences Module
//! Provides a centralized interface for all ANSI terminal capabilities

pub const clipboard = @import("clipboard.zig");
pub const color = @import("color.zig");
pub const cursor = @import("cursor.zig");
pub const screen = @import("screen.zig");
pub const graphics = @import("graphics.zig");
pub const hyperlink = @import("hyperlink.zig");
pub const notification = @import("notification.zig");
pub const mode = @import("mode.zig");
pub const paste = @import("paste.zig");
pub const reset = @import("reset.zig");
pub const charset = @import("charset.zig");
pub const control_chars = @import("control_chars.zig");
pub const device_attributes = @import("device_attributes.zig");
pub const focus = @import("focus.zig");
pub const keypad = @import("keypad.zig");
pub const palette = @import("palette.zig");
pub const pointer = @import("pointer.zig");
pub const sgr = @import("sgr.zig");
pub const status = @import("status.zig");
pub const title = @import("title.zig");
pub const width = @import("width.zig");
pub const wrap = @import("wrap.zig");

// Terminal-specific extensions
pub const xterm = @import("xterm.zig");
pub const kitty = @import("kitty.zig");
pub const iterm2 = @import("iterm2.zig");
pub const finalterm = @import("finalterm.zig");

// Advanced functionality
pub const enhanced_color = @import("enhanced_color.zig");
pub const advanced_color = @import("advanced_color.zig");
pub const color_conversion = @import("color_conversion.zig");
pub const structured_colors = @import("structured_colors.zig");
pub const terminal_background = @import("terminal_background.zig");
pub const terminal_colors = @import("terminal_colors.zig");
pub const terminal_queries = @import("terminal_queries.zig");
pub const shell_integration = @import("shell_integration.zig");
pub const passthrough = @import("passthrough.zig");
pub const truncate = @import("truncate.zig");
pub const cwd = @import("cwd.zig");
pub const winop = @import("winop.zig");
pub const advanced_cursor_management = @import("advanced_cursor_management.zig");
pub const advanced_color_conversion = @import("advanced_color_conversion.zig");

// Charmbracelet-inspired enhancements
pub const charmbracelet_color = @import("charmbracelet_color.zig");
pub const charmbracelet_cursor = @import("charmbracelet_cursor.zig");
pub const charmbracelet_clipboard = @import("charmbracelet_clipboard.zig");
pub const charmbracelet_background = @import("charmbracelet_background.zig");
pub const charmbracelet_device_attributes = @import("charmbracelet_device_attributes.zig");

// Modern ANSI features (2020+)
pub const modern_features = @import("modern_features.zig");
pub const bidirectional_text = @import("bidirectional_text.zig");

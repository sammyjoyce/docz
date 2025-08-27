//! ANSI Terminal Control Sequences Module
//! Provides a centralized interface for all ANSI terminal capabilities

// Core ANSI functionality
pub const color = @import("color.zig");
pub const cursor = @import("cursor.zig");
pub const screen = @import("screen.zig");

// Basic ANSI functionality
pub const clipboard = @import("clipboard.zig");
pub const graphics = @import("graphics.zig");
pub const sixel_graphics = @import("sixel_graphics.zig");
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
pub const iterm2_images = @import("iterm2_images.zig");
pub const iterm2_shell_integration = @import("iterm2_shell_integration.zig");
pub const finalterm = @import("finalterm.zig");
pub const ghostty = @import("ghostty.zig");

// Extended functionality
pub const background = @import("background.zig");
pub const background_color_control = @import("background_color_control.zig");
pub const bidirectional_text = @import("bidirectional_text.zig");

pub const clipboard_integration = @import("clipboard_integration.zig");
pub const color_converter = @import("color_converter.zig");
pub const color_conversion = @import("color_conversion.zig");
pub const color_conversion_extra = @import("color_conversion_extra.zig");
pub const color_distance = @import("color_distance.zig");
pub const color_extra = @import("color_extra.zig");
pub const color_management = @import("color_management.zig");
pub const color_palette = @import("color_palette.zig");
pub const color_space_utilities = @import("color_space_utilities.zig");
pub const colors = @import("colors.zig");
pub const cursor_control = @import("cursor_control.zig");
pub const cursor_management = @import("cursor_management.zig");
pub const cursor_optimizer = @import("cursor_optimizer.zig");
pub const cwd = @import("cwd.zig");
pub const enhancements = @import("enhancements.zig");
pub const input_extra = @import("input_extra.zig");
pub const kitty_graphics = @import("kitty_graphics.zig");
pub const modern_features = @import("modern_features.zig");
pub const passthrough = @import("passthrough.zig");
pub const precise_ansi_palette = @import("precise_ansi_palette.zig");
pub const queries = @import("queries.zig");
pub const shell_integration = @import("shell_integration.zig");
pub const structured_colors = @import("structured_colors.zig");
pub const terminal_background = @import("terminal_background.zig");
pub const terminal_color_control = @import("terminal_color_control.zig");
pub const truncate = @import("truncate.zig");
pub const winop = @import("winop.zig");

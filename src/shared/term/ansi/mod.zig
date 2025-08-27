//! ANSI Terminal Control Sequences Module
//! Provides a centralized interface for all ANSI terminal capabilities

// Core ANSI functionality
// Note: colors.zig and screen_control.zig need to be implemented or removed
// pub const color = @import("colors.zig");
// pub const screen_control = @import("screen_control.zig");

// Basic ANSI functionality
pub const clipboard = @import("clipboard.zig");
// Note: graphics modules need to be implemented or removed
// pub const graphics = @import("ansi_graphics.zig");
// pub const sixel_graphics = @import("sixel_graphics.zig");
pub const hyperlink = @import("hyperlink.zig");
pub const notification = @import("notification.zig");
pub const mode = @import("mode.zig");

pub const reset = @import("reset.zig");
pub const charset = @import("charset.zig");
pub const control_chars = @import("control_chars.zig");
pub const device_attributes = @import("device_attributes.zig");
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
// Note: Shell integration is now in term/shell/ directory
// pub const iterm2_images = @import("iterm2_images.zig");
// pub const iterm2_shell_integration = @import("iterm2_shell_integration.zig");
// pub const finalterm = @import("finalterm.zig");
pub const ghostty = @import("ghostty.zig");

// Extended functionality
pub const bidirectional_text = @import("bidirectional_text.zig");
pub const cwd = @import("cwd.zig");
pub const keys = @import("keys.zig");
pub const modern = @import("modern.zig");
pub const passthrough = @import("passthrough.zig");
pub const queries = @import("queries.zig");
pub const truncate = @import("truncate.zig");
pub const winop = @import("winop.zig");

// Additional features
pub const extended = @import("extended.zig");
pub const features = @import("features.zig");

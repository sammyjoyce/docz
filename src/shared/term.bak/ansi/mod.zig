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
pub const color = @import("color/mod.zig");
pub const hyperlink = @import("hyperlink.zig");
pub const notification = @import("notification.zig");
pub const mode = @import("mode.zig");

pub const reset = @import("reset.zig");
pub const charset = @import("charset.zig");
pub const control_chars = @import("ControlChars.zig");
pub const device_attributes = @import("DeviceAttributes.zig");
pub const keypad = @import("keypad.zig");
// Deprecated: use color.osc_palette instead
// pub const palette = @import("palette.zig");
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
// pub const term = @import("term.zig");
pub const ghostty = @import("ghostty.zig");

// Extended functionality
pub const extension = @import("extension.zig");
pub const features = @import("features.zig");
pub const recent = @import("recent.zig");

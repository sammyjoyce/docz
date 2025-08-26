//! Term module aggregator
//! Provides a single shared module for terminal capabilities so downstream modules
//! can import terminal functionality without duplicating file membership.

const std = @import("std");

// Core terminal capabilities and helpers
pub const caps = @import("caps.zig");
pub const unified = @import("unified.zig");

// ANSI submodules (selectively re-export the ones commonly used)
pub const ansi = struct {
    pub const color = @import("ansi/color.zig");
    pub const enhanced_color = @import("ansi/enhanced_color.zig");
    pub const cursor = @import("ansi/cursor.zig");
    pub const screen = @import("ansi/screen.zig");
    pub const clipboard = @import("ansi/clipboard.zig");
    pub const hyperlink = @import("ansi/hyperlink.zig");
    pub const hyperlinks = @import("ansi/hyperlinks.zig");
    pub const notification = @import("ansi/notification.zig");
    pub const notifications = @import("ansi/notifications.zig");
    pub const graphics = @import("ansi/graphics.zig");
};


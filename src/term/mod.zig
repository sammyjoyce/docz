//! Term module aggregator
//! Provides a single shared module for terminal capabilities so downstream modules
//! can import terminal functionality without duplicating file membership.

const std = @import("std");

// Core terminal capabilities and helpers
pub const caps = @import("caps.zig");
pub const unified = @import("unified.zig");
pub const graphics_manager = @import("graphics_manager.zig");

// ANSI submodules - export all commonly used modules for CLI components
pub const ansi = struct {
    // Core terminal capabilities and helpers
    pub const caps = @import("caps.zig");
    pub const unified = @import("unified.zig");
    pub const graphics_manager = @import("graphics_manager.zig");

    // ANSI control sequences
    pub const clipboard = @import("ansi/clipboard.zig");
    pub const color = @import("ansi/color.zig");
    pub const cursor = @import("ansi/cursor.zig");
    pub const screen = @import("ansi/screen.zig");
    pub const hyperlink = @import("ansi/hyperlink.zig");
    pub const notification = @import("ansi/notification.zig");
    pub const graphics = @import("ansi/graphics.zig");
    pub const mode = @import("ansi/mode.zig");
    pub const paste = @import("ansi/paste.zig");
    pub const reset = @import("ansi/reset.zig");
    pub const sgr = @import("ansi/sgr.zig");
    pub const title = @import("ansi/title.zig");
};

// Input submodules - provided for CLI components that need direct access
pub const input = struct {
    pub const types = @import("input/types.zig");
    pub const enhanced_keys = @import("input/enhanced_keys.zig");
    pub const unified_parser = @import("input/unified_parser.zig");
};

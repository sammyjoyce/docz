//! Core TUI System Module
//! 
//! Re-exports and bridges existing src/tui/core components with the consolidated structure

// Re-export existing core components from src/tui/core
pub const events = @import("../../src/tui/core/events.zig");
pub const bounds = @import("../../src/tui/core/bounds.zig"); 
pub const layout = @import("../../src/tui/core/layout.zig");
pub const screen = @import("../../src/tui/core/screen.zig");
pub const renderer = @import("../../src/tui/core/renderer.zig");

// Enhanced input system
pub const input = @import("../../src/tui/core/input/mod.zig");

// Global initialization functions
pub fn init(allocator: std.mem.Allocator) !void {
    _ = allocator;
    // Global TUI core initialization if needed
}

pub fn deinit() void {
    // Global TUI core cleanup if needed
}

const std = @import("std");
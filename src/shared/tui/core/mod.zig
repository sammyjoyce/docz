// Core TUI System Module
// Re-exports and bridges existing src/tui/core components with the consolidated structure

const std = @import("std");

// Re-export existing core components from src/tui/core
pub const events = @import("events.zig");
pub const bounds = @import("bounds.zig");
pub const layout = @import("layout.zig");
pub const screen = @import("screen.zig");
pub const renderer = @import("renderer.zig");

// Enhanced input system
pub const input = @import("input/mod.zig");

// Global initialization functions
pub fn init(allocator: std.mem.Allocator) !void {
    _ = allocator;
    // Global TUI core initialization if needed
}

pub fn deinit() void {
    // Global TUI core cleanup if needed
}

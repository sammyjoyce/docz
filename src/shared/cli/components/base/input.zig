//! CLI Input Manager Wrapper
//! Provides CLI-specific input handling using the unified input system.
//! This module wraps the unified InputManager to provide CLI-specific functionality.

const std = @import("std");
const components_mod = @import("../../mod.zig");

// Re-export unified input types for CLI convenience
pub const InputEvent = components_mod.InputEvent;
pub const InputManager = components_mod.InputManager;
pub const InputConfig = components_mod.InputConfig;
pub const InputFeatures = components_mod.InputFeatures;
pub const Key = components_mod.Key;
pub const Modifiers = components_mod.Modifiers;
pub const InputUtils = components_mod.InputUtils;

/// CLI-specific input manager that wraps the unified InputManager
pub const CliInput = struct {
    const Self = @This();

    manager: InputManager,

    pub fn init(allocator: std.mem.Allocator, config: InputConfig) !Self {
        const manager = try InputManager.init(allocator, config);
        return Self{
            .manager = manager,
        };
    }

    pub fn deinit(self: *Self) void {
        self.manager.deinit();
    }

    /// Enable CLI-appropriate input features
    pub fn enableFeatures(self: *Self) !void {
        try self.manager.enableFeatures();
    }

    /// Read next input event
    pub fn nextEvent(self: *Self) !InputEvent {
        return try self.manager.nextEvent();
    }

    /// Check if events are available
    pub fn hasEvent(self: *Self) !bool {
        return try self.manager.hasEvent();
    }

    /// Poll for events
    pub fn pollEvent(self: *Self) ?InputEvent {
        return self.manager.pollEvent();
    }

    /// Process raw input data
    pub fn processInput(self: *Self, data: []const u8) !void {
        return try self.manager.processInput(data);
    }
};

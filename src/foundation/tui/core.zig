// Core TUI System Module
// Re-exports and bridges existing src/tui/core components with the consolidated structure

const std = @import("std");

// Re-export existing core components from src/tui/core
pub const events = @import("core/events.zig");
pub const bounds = @import("core/bounds.zig");
pub const renderer = @import("core/renderer.zig");
pub const stylize = @import("core/stylize.zig");

// Border merging functionality
pub const border_merger = @import("core/border_merger.zig");
pub const BorderMerger = border_merger.Merger;

// Easing functions for animations
pub const easing = @import("core/easing.zig");
pub const Easing = easing.Easing;

// Typing animation system with particle effects
pub const typing_animation = @import("core/typing_animation.zig");
pub const TypingAnimation = typing_animation.TypingAnimation;
pub const TypingAnimationBuilder = typing_animation.TypingAnimationBuilder;
pub const ParticleEmitter = typing_animation.ParticleEmitter;
pub const Particle = typing_animation.Particle;

// Canvas system for graphics
pub const canvas = @import("core/canvas.zig");
// Backward compatibility alias
pub const canvas_engine = canvas;

// Global initialization functions
pub fn init(allocator: std.mem.Allocator) !void {
    _ = allocator;
    // Global TUI core initialization if needed
}

pub fn deinit() void {
    // Global TUI core cleanup if needed
}

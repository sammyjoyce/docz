// Core TUI System Module
// Re-exports and bridges existing src/tui/core components with the consolidated structure

const std = @import("std");

// Re-export existing core components from src/tui/core
pub const events = @import("events.zig");
pub const bounds = @import("bounds.zig");
pub const renderer = @import("renderer.zig");
pub const stylize = @import("stylize.zig");

// Border merging functionality
pub const border_merger = @import("border_merger.zig");
pub const BorderMerger = border_merger.BorderMerger;

// Easing functions for animations
pub const easing = @import("easing.zig");
pub const Easing = easing.Easing;

// Typing animation system with particle effects
pub const typing_animation = @import("typing_animation.zig");
pub const TypingAnimation = typing_animation.TypingAnimation;
pub const TypingAnimationBuilder = typing_animation.TypingAnimationBuilder;
pub const ParticleEmitter = typing_animation.ParticleEmitter;
pub const Particle = typing_animation.Particle;

// Canvas system for graphics
pub const canvas = @import("canvas.zig");
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

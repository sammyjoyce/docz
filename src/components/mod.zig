//! Shared Components Library
//!
//! This module provides reusable UI components that work across both CLI and TUI contexts.
//! Components are designed with progressive enhancement, automatically adapting their
//! rendering based on terminal capabilities.

const std = @import("std");

// Core components
pub const progress = @import("core/progress.zig");

// Re-exports for convenience
pub const UnifiedProgressBar = progress.UnifiedProgressBar;
pub const ProgressConfig = progress.ProgressConfig;
pub const ProgressState = progress.ProgressState;
pub const ProgressBarPresets = progress.ProgressBarPresets;
pub const ScopedProgress = progress.ScopedProgress;

// Common types
pub const ColorScheme = progress.ProgressConfig.ColorScheme;

/// Initialize shared components with an allocator
/// This can be extended in the future for global component management
pub fn init(allocator: std.mem.Allocator) !void {
    _ = allocator; // Reserved for future use
}

/// Deinitialize shared components  
pub fn deinit() void {
    // Reserved for future cleanup
}

test "components module" {
    // Basic smoke test to ensure module loads correctly
    _ = UnifiedProgressBar;
    _ = ProgressConfig;
    _ = ProgressState;
    _ = ProgressBarPresets;
}
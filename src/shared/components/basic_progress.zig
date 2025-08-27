//! Basic Progress Bar - Redirect to Unified System
//!
//! This module now redirects to the unified progress bar system.
//! For new code, use @import("progress.zig") instead.

const progress = @import("progress.zig");

// Re-export unified types for backward compatibility
pub const ProgressData = progress.ProgressData;
pub const ProgressStyle = progress.ProgressStyle;
pub const TermCaps = progress.TermCaps;
pub const ProgressRenderer = progress.ProgressRenderer;
pub const Color = progress.Color;
pub const ProgressUtils = progress.ProgressUtils;
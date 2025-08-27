//! Terminal shared module alias
//! Provides a convenient import path for the terminal module
//! This file acts as an alias to maintain consistency across the codebase

// Re-export the term module
pub const term = @import("shared/term/mod.zig");

// For convenience, also export common submodules directly
pub const ansi = term.ansi;
pub const caps = term.caps;
pub const input = term.input;

//! Terminal shared module alias
//! Provides a convenient import path for the terminal module
//! This file acts as an alias to maintain consistency across the codebase

// Re-export the term module (now using the refactored version)
pub const term = @import("shared/term_refactored/mod.zig");

// For convenience, also export common submodules directly
// Note: These now use the new hierarchical structure
pub const ansi = term.term.ansi;
pub const caps = term.term.core.capabilities;
pub const input = term.term.input;

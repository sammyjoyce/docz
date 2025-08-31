//! Terminal shared module alias
//! Provides a convenient import path for the terminal module
//! This file acts as an alias to maintain consistency across the codebase

// Re-export the term module from the consolidated foundation barrel
pub const term = @import("foundation/term.zig");

// For convenience, also export common submodules directly
// Note: These now use the consolidated hierarchy
pub const ansi = term.ansi;
pub const caps = term.capabilities;
pub const input = term.input;

// Convenience re-exports used around the codebase
pub const TermCaps = term.capabilities.TermCaps;
pub const color = term.color; // Re-export color module for easier access
pub const common = struct {
    pub const Color = term.color.Color;
    pub const Style = term.color.Style;
};

//! CLI formatters module
//! Output formatting for CLI responses

// Formatter implementations
pub const simple = @import("simple.zig");
pub const enhanced = @import("enhanced.zig");

// Main formatter export (using simple by default)
pub const CliFormatter = simple.CliFormatter;

// Alternative formatters
pub const EnhancedCliFormatter = enhanced.CliFormatter;

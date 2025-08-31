//! CLI formatters module
//! Output formatting for CLI responses

// Formatter implementations
pub const formatter = @import("formatter.zig");
pub const rich = @import("rich.zig");

// Main formatter export (using formatter by default)
pub const Formatter = formatter.Formatter;

// Alternative formatters
pub const RichFormatter = rich.Formatter;

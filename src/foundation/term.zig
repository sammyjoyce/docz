//! Terminal subsystem barrel.
//! Import terminal primitives via this module; avoid deep imports.
//! Feature-gate in consumers using `@import("../mod.zig").options.feature_tui`.
// Terminal namespace

// Layer enforcement disabled during consolidation

pub const ansi = @import("term/ansi.zig");
pub const buffer = @import("term/buffer.zig");
pub const capabilities = @import("term/capabilities.zig");
pub const color = @import("term/color.zig");
pub const control = @import("term/control.zig");
pub const core = @import("term/core.zig");
pub const graphics = @import("term/graphics.zig");
pub const input = @import("term/input.zig");
pub const io = @import("term/io.zig");
pub const query = @import("term/query.zig");
pub const shell = @import("term/shell.zig");
pub const unicode = @import("term/unicode.zig");

// Re-export main terminal functionality
pub const term = @import("term/term.zig");
pub const Terminal = io.Terminal;

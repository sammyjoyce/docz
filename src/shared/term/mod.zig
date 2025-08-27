// Terminal namespace

pub const ansi = @import("ansi/mod.zig");
pub const buffer = @import("buffer/mod.zig");
pub const color = @import("color/mod.zig");
pub const control = @import("control/mod.zig");
pub const core = @import("core/mod.zig");
pub const graphics = @import("graphics/mod.zig");
pub const input = @import("input/mod.zig");
pub const io = @import("io/mod.zig");
pub const query = @import("query/mod.zig");
pub const shell = @import("shell/mod.zig");
pub const unicode = @import("unicode/mod.zig");

// Re-export main terminal functionality
pub const term = @import("Term.zig");

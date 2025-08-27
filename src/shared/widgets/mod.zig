//! Widgets package barrel.
//! During migration, this exposes shims to legacy render/components/* implementations
//! while we port concrete widgets to the new ui.component interface.

pub const chart = @import("chart/mod.zig");
pub const table = @import("table/mod.zig");
pub const progress = @import("progress/mod.zig");
pub const notification = @import("notification/mod.zig");
pub const input = @import("input/mod.zig");

//! Widgets package barrel.
//! Exposes widget families via sub-barrels; avoid importing individual files.
//! Feature-gate at call sites via `@import("../shared/mod.zig").options.feature_widgets`.

pub const chart = @import("chart/mod.zig");
pub const table = @import("table/mod.zig");
pub const progress = @import("progress/mod.zig");
pub const notification = @import("notification/mod.zig");
pub const input = @import("input/mod.zig");

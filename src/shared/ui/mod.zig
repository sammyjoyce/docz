//! UI package barrel: component interface, layout and events.
//! Public surface intentionally minimal and stable.

pub const component = @import("component/mod.zig");
pub const layout = @import("layout/mod.zig");
pub const event = @import("event/mod.zig");
pub const theme = @import("theme/mod.zig");

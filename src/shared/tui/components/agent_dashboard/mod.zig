//! Agent Dashboard submodule barrel (transitional)
//! Exposes legacy implementation while preparing split into state/layout/renderers.

pub const legacy = @import("../agent_dashboard.zig");

// Note: explicit re-exports will be added as the split progresses.

// Planned split (stubs for future files):
pub const state = @import("state.zig");
pub const layout = @import("layout.zig");
pub const renderers = @import("renderers/mod.zig");

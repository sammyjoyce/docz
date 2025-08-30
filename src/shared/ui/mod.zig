//! UI package barrel: component interface, layout and events.
//! Public surface intentionally minimal and stable.
//!
//! Import via this barrel. If you need to feature-gate, use
//! `@import("../shared/mod.zig").options.feature_tui` in consumers.

const shared = @import("../mod.zig");
comptime {
    if (!shared.options.feature_tui) {
        @compileError("ui subsystem disabled; enable feature_tui");
    }
}

pub const component = @import("component/mod.zig");
pub const layout = @import("layout/mod.zig");
pub const event = @import("event/mod.zig");
pub const theme = @import("theme/mod.zig");

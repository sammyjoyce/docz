//! CLI Presenters for shared components
//! Thin adapters that render headless shared models to plain terminal output.

pub const notification = @import("presenters/notification.zig");
pub const progress = @import("presenters/progress.zig");

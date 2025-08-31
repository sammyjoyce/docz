//! TUI Presenters for shared components
//! Thin adapters that map headless shared models to TUI renderer calls.

pub const notification = @import("presenters/notification.zig");
pub const progress = @import("presenters/progress.zig");

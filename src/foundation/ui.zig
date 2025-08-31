//! Base UI framework with component model and standard widgets.
//! Layer: ui (may import: render, term)

const std = @import("std");
const deps = @import("internal/deps.zig");
comptime {
    deps.assertLayer(.ui);
}

// Core component model - explicit exports only
pub const Component = @import("ui/Component.zig");
pub const Layout = @import("ui/Layout.zig");
pub const Event = @import("ui/Event.zig");
pub const Runner = @import("ui/Runner.zig");

// Standard widgets namespace - lazy loading
pub const Widgets = struct {
    pub const Progress = @import("ui/widgets/Progress.zig");
    pub const Input = @import("ui/widgets/Input.zig");
    pub const Notification = @import("ui/widgets/Notification.zig");
    pub const Chart = @import("ui/widgets/Chart.zig");
    pub const Table = @import("ui/widgets/Table.zig");
    pub const Status = @import("ui/widgets/Status.zig");
};

// Temporary compatibility (remove after migration)
pub const widgets = Widgets;
pub const component = Component;
pub const layout = Layout;
pub const event = Event;

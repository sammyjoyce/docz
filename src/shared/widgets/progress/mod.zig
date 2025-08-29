// Progress widget (vtable-based) following the new widgets → ui → render layering.

const std = @import("std");
const ui = @import("../../ui/mod.zig");
const renderCtx = @import("../../render/mod.zig");
const draw = @import("draw.zig");

pub const Progress = struct {
    allocator: std.mem.Allocator,
    /// 0.0 .. 1.0
    value: f32 = 0.0,
    /// Optional label to render before the bar
    label: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) Progress {
        return .{ .allocator = allocator };
    }

    pub fn asComponent(self: *Progress) ui.component.Component {
        return ui.component.wrap(@TypeOf(self.*), self);
    }

    pub fn measure(self: *Progress, constraints: ui.layout.Constraints) ui.layout.Size {
        _ = self;
        // Single-line widget; take full width provided by constraints
        return .{ .w = constraints.max.w, .h = 1 };
    }

    pub fn layout(self: *Progress, rectangle: ui.layout.Rect) void {
        _ = self;
        _ = rectangle;
    }

    pub fn render(self: *Progress, context: *renderCtx.Context) !void {
        const rectangle = ui.layout.Rect{ .x = 0, .y = 0, .w = context.surface.size().w, .h = 1 };
        try draw.progress(context, rectangle, self.value, self.label);
    }

    pub fn event(self: *Progress, inputEvent: ui.event.Event) ui.component.Component.Invalidate {
        _ = self;
        _ = inputEvent;
        return .none;
    }
};

test "progress renders bar proportionally" {
    const allocator = std.testing.allocator;
    var surface = try renderCtx.MemorySurface.init(allocator, 10, 1);
    defer {
        surface.deinit(allocator);
        allocator.destroy(surface);
    }

    var context = renderCtx.Context.init(surface, null);
    try draw.progress(&context, .{ .x = 0, .y = 0, .w = 10, .h = 1 }, 0.5, null);
    const dump = try surface.toString(allocator);
    defer allocator.free(dump);
    try std.testing.expectEqualStrings("=====-----\n", dump);
}

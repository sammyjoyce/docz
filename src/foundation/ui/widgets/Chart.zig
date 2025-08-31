// Minimal chart widget using the new ui.component pattern with a separate renderer.

const std = @import("std");
const ui = @import("../../ui/mod.zig");
const render = @import("../../render.zig");

pub const Chart = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    // Values in 0..1
    values: []const f32 = &[_]f32{},

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn asComponent(self: *Self) ui.component.Component {
        return ui.component.wrap(@TypeOf(self.*), self);
    }

    pub fn measure(self: *Self, constraints: ui.layout.Constraints) ui.layout.Size {
        _ = self;
        // Single row sparkline for bootstrap
        return .{ .w = constraints.max.w, .h = 1 };
    }

    pub fn layout(self: *Self, rectangle: ui.layout.Rect) void {
        _ = self;
        _ = rectangle;
    }

    pub fn render(self: *Self, ctx: *render.Context) ui.component.ComponentError!void {
        // Use the render layer's chart widget renderer
        const rect = render.widgets.Chart.Rect{
            .x = 0,
            .y = 0,
            .w = 80, // Default width - should come from layout
            .h = 1,
        };

        // Call the sparkline function from render/widgets/Chart.zig
        render.widgets.Chart.sparkline(ctx, rect, self.values) catch return ui.component.ComponentError.RenderFailed;
    }

    pub fn event(self: *Self, inputEvent: ui.event.Event) ui.component.Component.Invalidate {
        _ = self;
        _ = inputEvent;
        return .none;
    }
};

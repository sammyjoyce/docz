// Minimal chart widget using the new ui.component pattern with a separate renderer.

const std = @import("std");
const ui = @import("../../ui/mod.zig");
const renderCtx = @import("../../render/mod.zig");
const draw = @import("Draw.zig");

pub const Chart = struct {
    allocator: std.mem.Allocator,
    // Values in 0..1
    values: []const f32 = &[_]f32{},

    pub fn init(allocator: std.mem.Allocator) Chart {
        return .{ .allocator = allocator };
    }

    pub fn asComponent(self: *Chart) ui.component.Component {
        return ui.component.wrap(@TypeOf(self.*), self);
    }

    pub fn measure(self: *Chart, c: ui.layout.Constraints) ui.layout.Size {
        _ = self;
        // Single row sparkline for bootstrap
        return .{ .w = c.max.w, .h = 1 };
    }

    pub fn layout(self: *Chart, rect: ui.layout.Rect) void {
        _ = self;
        _ = rect;
    }

    pub fn render(self: *Chart, ctx: *renderCtx.Context) !void {
        const rect = ui.layout.Rect{ .x = 0, .y = 0, .w = ctx.surface.size().w, .h = 1 };
        try draw.sparkline(ctx, rect, self.values);
    }

    pub fn event(self: *Chart, ev: ui.event.Event) ui.component.Component.Invalidate {
        _ = self;
        _ = ev;
        return .none;
    }
};

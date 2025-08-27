// Progress widget (vtable-based) following the new widgets → ui → render layering.

const std = @import("std");
const ui = @import("../../ui/mod.zig");
const renderCtx = @import("../../render/mod.zig");
const draw = @import("Draw.zig");

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

    pub fn measure(self: *Progress, c: ui.layout.Constraints) ui.layout.Size {
        _ = self;
        // Single-line widget; take full width provided by constraints
        return .{ .w = c.max.w, .h = 1 };
    }

    pub fn layout(self: *Progress, rect: ui.layout.Rect) void {
        _ = self;
        _ = rect;
    }

    pub fn render(self: *Progress, ctx: *renderCtx.Context) !void {
        const rect = ui.layout.Rect{ .x = 0, .y = 0, .w = ctx.surface.size().w, .h = 1 };
        try draw.progress(ctx, rect, self.value, self.label);
    }

    pub fn event(self: *Progress, ev: ui.event.Event) ui.component.Component.Invalidate {
        _ = self;
        _ = ev;
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

    var ctx = renderCtx.Context.init(surface, null);
    try draw.progress(&ctx, .{ .x = 0, .y = 0, .w = 10, .h = 1 }, 0.5, null);
    const dump = try surface.toString(allocator);
    defer allocator.free(dump);
    try std.testing.expectEqualStrings("=====-----\n", dump);
}

const std = @import("std");
const draw = @import("Draw.zig");
const render_ctx = @import("../../render/mod.zig");
const ui = @import("../../ui/mod.zig");

pub const Notification = struct {
    allocator: std.mem.Allocator,
    severity: draw.Severity = .info,
    title: []const u8,
    message: []const u8,

    pub fn init(allocator: std.mem.Allocator, title: []const u8, message: []const u8) Notification {
        return .{ .allocator = allocator, .title = title, .message = message };
    }

    pub fn asComponent(self: *Notification) ui.component.Component {
        return ui.component.wrap(@TypeOf(self.*), self);
    }

    pub fn measure(self: *Notification, c: ui.layout.Constraints) ui.layout.Size {
        _ = self;
        const w = c.max.w;
        const h: u32 = if (c.max.h >= 2) 2 else 1;
        return .{ .w = w, .h = h };
    }

    pub fn layout(self: *Notification, rect: ui.layout.Rect) void {
        _ = self;
        _ = rect; // No-op for now
    }

    pub fn render(self: *Notification, ctx: *render_ctx.Context) !void {
        // For now, render at origin; higher-level layout to provide rect soon
        const r = draw.Rect{ .x = 0, .y = 0, .w = 40, .h = 3 };
        try draw.notification(ctx, r, self.severity, self.title, self.message);
    }

    pub fn event(self: *Notification, ev: ui.event.Event) ui.component.Component.Invalidate {
        _ = self;
        _ = ev;
        return .none;
    }
};

const std = @import("std");
const draw = @import("draw.zig");
const renderCtx = @import("../../render/mod.zig");
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

    pub fn measure(self: *Notification, constraints: ui.layout.Constraints) ui.layout.Size {
        _ = self;
        const width = constraints.max.w;
        const height: u32 = if (constraints.max.h >= 2) 2 else 1;
        return .{ .w = width, .h = height };
    }

    pub fn layout(self: *Notification, rectangle: ui.layout.Rect) void {
        _ = self;
        _ = rectangle; // No-op for now
    }

    pub fn render(self: *Notification, context: *renderCtx.Context) !void {
        // For now, render at origin; higher-level layout to provide rectangle soon
        const rectangle = draw.Rectangle{ .x = 0, .y = 0, .w = 40, .h = 3 };
        try draw.notification(context, rectangle, self.severity, self.title, self.message);
    }

    pub fn event(self: *Notification, inputEvent: ui.event.Event) ui.component.Component.Invalidate {
        _ = self;
        _ = inputEvent;
        return .none;
    }
};

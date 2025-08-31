//! TUI Notification Presenter
//! Maps shared Notification to the TUI renderer's drawNotification API.

const std = @import("std");
const ui = @import("../../ui.zig");
const tui = @import("../core/renderer.zig");

const Notification = ui.Widgets.Notification.Notification;
const NotificationType = ui.Widgets.Notification.NotificationType;
const Renderer = tui.Renderer;
const Render = tui.Render;
const NotificationLevel = tui.NotificationLevel;

fn mapLevel(t: NotificationType) NotificationLevel {
    return switch (t) {
        .info => .info,
        .success => .success,
        .warning => .warning,
        .@"error" => .error_,
        .debug => .debug,
        .critical => .error_,
        .progress => .info,
    };
}

/// Draw a shared notification using the TUI renderer.
pub fn draw(renderer: *Renderer, ctx: Render, n: *const Notification) !void {
    // Use sanitized content to avoid stray control sequences.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const clean = try n.sanitizeContent(allocator);
    defer allocator.free(clean.title);
    defer allocator.free(clean.message);

    const level = mapLevel(n.notification_type);
    try renderer.drawNotification(ctx, clean.title, clean.message, level);
}

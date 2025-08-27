//! CLI Notification Presenter
//! Renders shared Notification model to terminal output without
//! depending on low-level ANSI modules.

const std = @import("std");
const notif_mod = @import("components_shared");

const Notification = notif_mod.Notification;
const NotificationType = notif_mod.NotificationType;
const NotificationUtils = notif_mod.NotificationUtils;

/// Render a notification to stdout with optional unicode glyphs.
pub fn display(allocator: std.mem.Allocator, n: *const Notification, use_unicode: bool) !void {
    const clean = try n.sanitizeContent(allocator);
    defer allocator.free(clean.title);
    defer allocator.free(clean.message);

    const icon = if (use_unicode) n.notification_type.icon() else n.notification_type.asciiIcon();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);

    // Header line
    try stdout_writer.print("{s} {s}\n", .{ icon, clean.title });

    // Message body
    if (clean.message.len > 0) {
        try stdout_writer.print("{s}\n", .{clean.message});
    }

    // Progress (if any)
    if (n.isProgress()) {
        const progress_val = n.progress orelse 0.0;
        const bar = try NotificationUtils.formatProgressBar(allocator, progress_val, 30, use_unicode);
        defer allocator.free(bar);
        try stdout_writer.print("{s} {d:.0}%\n", .{ bar, progress_val * 100.0 });
    }

    // Optional timestamp
    if (n.config.showTimestamp) {
        const ts = try n.getFormattedTimestamp(allocator);
        defer allocator.free(ts);
        try stdout_writer.print("{s}\n", .{ts});
    }

    try stdout_writer.flush();
}

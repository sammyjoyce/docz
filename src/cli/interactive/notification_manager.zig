//! Notification manager for long-running CLI operations
//! Integrates with terminal notification capabilities and provides fallback options

const std = @import("std");
const term_notification = @import("../../term/ansi/notification.zig");
const term_caps = @import("../../term/caps.zig");
const term_ansi = @import("../../term/ansi/color.zig");
const Allocator = std.mem.Allocator;

pub const NotificationType = enum {
    info,
    success,
    warning,
    err,
    progress,
};

pub const Notification = struct {
    id: u64,
    type: NotificationType,
    title: []const u8,
    message: []const u8,
    progress: ?f32 = null, // 0.0 to 1.0 for progress notifications
    timestamp: i64,
    persistent: bool = false,

    pub fn init(
        id: u64,
        notification_type: NotificationType,
        title: []const u8,
        message: []const u8,
    ) Notification {
        return .{
            .id = id,
            .type = notification_type,
            .title = title,
            .message = message,
            .timestamp = std.time.timestamp(),
        };
    }

    pub fn withProgress(self: Notification, progress_value: f32) Notification {
        return .{
            .id = self.id,
            .type = self.type,
            .title = self.title,
            .message = self.message,
            .progress = std.math.clamp(progress_value, 0.0, 1.0),
            .timestamp = self.timestamp,
            .persistent = self.persistent,
        };
    }

    pub fn asPersistent(self: Notification) Notification {
        return .{
            .id = self.id,
            .type = self.type,
            .title = self.title,
            .message = self.message,
            .progress = self.progress,
            .timestamp = self.timestamp,
            .persistent = true,
        };
    }
};

/// Enhanced notification manager with multiple delivery methods
pub const NotificationManager = struct {
    allocator: Allocator,
    caps: term_caps.TermCaps,
    active_notifications: std.ArrayList(Notification),
    notification_counter: u64,
    enable_desktop_notifications: bool,
    enable_inline_notifications: bool,
    enable_sound: bool,
    writer: ?*std.io.AnyWriter,

    pub fn init(allocator: Allocator) NotificationManager {
        return .{
            .allocator = allocator,
            .caps = term_caps.getTermCaps(),
            .active_notifications = std.ArrayList(Notification).init(allocator),
            .notification_counter = 0,
            .enable_desktop_notifications = true,
            .enable_inline_notifications = true,
            .enable_sound = false,
            .writer = null,
        };
    }

    pub fn deinit(self: *NotificationManager) void {
        self.active_notifications.deinit();
    }

    pub fn setWriter(self: *NotificationManager, writer: *std.io.AnyWriter) void {
        self.writer = writer;
    }

    /// Send a notification with automatic delivery method selection
    pub fn notify(
        self: *NotificationManager,
        notification_type: NotificationType,
        title: []const u8,
        message: []const u8,
    ) !u64 {
        self.notification_counter += 1;
        const notification = Notification.init(
            self.notification_counter,
            notification_type,
            title,
            message,
        );

        try self.active_notifications.append(notification);

        // Try desktop notification first if supported and enabled
        if (self.enable_desktop_notifications and self.caps.supportsNotifications()) {
            try self.sendDesktopNotification(notification);
        }

        // Always show inline notification as fallback
        if (self.enable_inline_notifications) {
            try self.showInlineNotification(notification);
        }

        return notification.id;
    }

    /// Send a progress notification
    pub fn notifyProgress(
        self: *NotificationManager,
        title: []const u8,
        message: []const u8,
        progress: f32,
    ) !u64 {
        self.notification_counter += 1;
        const notification = Notification.init(
            self.notification_counter,
            .progress,
            title,
            message,
        ).withProgress(progress).asPersistent();

        // Update or add progress notification
        var found = false;
        for (self.active_notifications.items, 0..) |*existing, i| {
            if (existing.type == .progress and std.mem.eql(u8, existing.title, title)) {
                self.active_notifications.items[i] = notification;
                found = true;
                break;
            }
        }

        if (!found) {
            try self.active_notifications.append(notification);
        }

        // Show progress notification
        try self.showProgressNotification(notification);

        return notification.id;
    }

    /// Send desktop notification using OSC 9
    fn sendDesktopNotification(self: *NotificationManager, notification: Notification) !void {
        if (self.writer == null) return error.NoWriter;

        const formatted_message = try std.fmt.allocPrint(
            self.allocator,
            "{s}: {s}",
            .{ notification.title, notification.message },
        );
        defer self.allocator.free(formatted_message);

        try term_notification.writeNotification(
            self.writer.?,
            self.allocator,
            self.caps,
            formatted_message,
        );
    }

    /// Show inline terminal notification with rich formatting
    fn showInlineNotification(self: *NotificationManager, notification: Notification) !void {
        if (self.writer == null) return;
        const writer = self.writer.?;

        // Save cursor position and create notification bar
        try writer.writeAll("\n");

        // Notification type indicator with colors
        switch (notification.type) {
            .info => {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer.*, self.caps, 100, 149, 237);
                } else {
                    try term_ansi.setForeground256(writer.*, self.caps, 12);
                }
                try writer.writeAll("ℹ ");
            },
            .success => {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer.*, self.caps, 50, 205, 50);
                } else {
                    try term_ansi.setForeground256(writer.*, self.caps, 10);
                }
                try writer.writeAll("✓ ");
            },
            .warning => {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer.*, self.caps, 255, 165, 0);
                } else {
                    try term_ansi.setForeground256(writer.*, self.caps, 11);
                }
                try writer.writeAll("⚠ ");
            },
            .err => {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer.*, self.caps, 255, 69, 0);
                } else {
                    try term_ansi.setForeground256(writer.*, self.caps, 9);
                }
                try writer.writeAll("✗ ");
            },
            .progress => {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer.*, self.caps, 255, 215, 0);
                } else {
                    try term_ansi.setForeground256(writer.*, self.caps, 11);
                }
                try writer.writeAll("⧖ ");
            },
        }

        // Title
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 255, 255, 255);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 15);
        }
        try writer.writeAll(notification.title);

        // Message
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 200, 200, 200);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 7);
        }
        try writer.print(": {s}", .{notification.message});

        try term_ansi.resetStyle(writer.*, self.caps);
        try writer.writeAll("\n");
    }

    /// Show progress notification with progress bar
    fn showProgressNotification(self: *NotificationManager, notification: Notification) !void {
        if (self.writer == null or notification.progress == null) return;
        const writer = self.writer.?;
        const progress = notification.progress.?;

        try writer.writeAll("\n");

        // Progress type indicator
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 255, 215, 0);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 11);
        }
        try writer.writeAll("⧖ ");

        // Title
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 255, 255, 255);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 15);
        }
        try writer.writeAll(notification.title);

        // Progress bar
        const bar_width = 30;
        const filled_width = @as(usize, @intFromFloat(progress * @as(f32, @floatFromInt(bar_width))));

        try writer.writeAll(" [");

        // Filled portion
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 50, 205, 50);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 10);
        }
        for (0..filled_width) |_| {
            try writer.writeAll("█");
        }

        // Empty portion
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 100, 100, 100);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 8);
        }
        for (filled_width..bar_width) |_| {
            try writer.writeAll("░");
        }

        try term_ansi.resetStyle(writer.*, self.caps);
        try writer.print("] {d:.1}%", .{progress * 100.0});

        // Message
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 200, 200, 200);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 7);
        }
        try writer.print(" - {s}", .{notification.message});

        try term_ansi.resetStyle(writer.*, self.caps);
        try writer.writeAll("\n");
    }

    /// Update progress for an existing notification
    pub fn updateProgress(self: *NotificationManager, notification_id: u64, progress: f32) !void {
        for (self.active_notifications.items, 0..) |*notification, i| {
            if (notification.id == notification_id and notification.type == .progress) {
                self.active_notifications.items[i].progress = std.math.clamp(progress, 0.0, 1.0);
                try self.showProgressNotification(self.active_notifications.items[i]);
                break;
            }
        }
    }

    /// Complete a progress notification
    pub fn completeProgress(self: *NotificationManager, notification_id: u64, final_message: []const u8) !void {
        for (self.active_notifications.items, 0..) |*notification, i| {
            if (notification.id == notification_id and notification.type == .progress) {
                // Convert to success notification
                const success_notification = Notification.init(
                    notification_id,
                    .success,
                    notification.title,
                    final_message,
                );

                self.active_notifications.items[i] = success_notification;
                try self.showInlineNotification(success_notification);

                // Send desktop notification for completion if enabled
                if (self.enable_desktop_notifications and self.caps.supportsNotifications()) {
                    try self.sendDesktopNotification(success_notification);
                }
                break;
            }
        }
    }

    /// Remove a notification
    pub fn dismiss(self: *NotificationManager, notification_id: u64) void {
        for (self.active_notifications.items, 0..) |notification, i| {
            if (notification.id == notification_id) {
                _ = self.active_notifications.swapRemove(i);
                break;
            }
        }
    }

    /// Clear all notifications
    pub fn clearAll(self: *NotificationManager) void {
        self.active_notifications.clearRetainingCapacity();
    }

    /// Get all active notifications
    pub fn getActiveNotifications(self: *NotificationManager) []const Notification {
        return self.active_notifications.items;
    }

    /// Configure notification preferences
    pub fn configure(
        self: *NotificationManager,
        desktop: bool,
        inline_notifications: bool,
        sound: bool,
    ) void {
        self.enable_desktop_notifications = desktop;
        self.enable_inline_notifications = inline_notifications;
        self.enable_sound = sound;
    }
};

/// Helper for common long-running operations
pub const OperationNotifier = struct {
    manager: *NotificationManager,
    notification_id: ?u64,
    operation_name: []const u8,

    pub fn init(manager: *NotificationManager, operation_name: []const u8) OperationNotifier {
        return .{
            .manager = manager,
            .notification_id = null,
            .operation_name = operation_name,
        };
    }

    pub fn start(self: *OperationNotifier, message: []const u8) !void {
        self.notification_id = try self.manager.notifyProgress(
            self.operation_name,
            message,
            0.0,
        );
    }

    pub fn updateProgress(self: *OperationNotifier, progress: f32, message: []const u8) !void {
        if (self.notification_id) |_| {
            // Update the message by creating a new notification
            _ = try self.manager.notifyProgress(self.operation_name, message, progress);
        }
    }

    pub fn complete(self: *OperationNotifier, final_message: []const u8) !void {
        if (self.notification_id) |id| {
            try self.manager.completeProgress(id, final_message);
            self.notification_id = null;
        }
    }

    pub fn fail(self: *OperationNotifier, error_message: []const u8) !void {
        if (self.notification_id) |_| {
            _ = try self.manager.notify(.err, self.operation_name, error_message);
            self.notification_id = null;
        }
    }
};

// Demo functions for testing notification features
pub const NotificationDemo = struct {
    pub fn runProgressDemo(manager: *NotificationManager) !void {
        var notifier = OperationNotifier.init(manager, "File Transfer");

        try notifier.start("Initializing transfer...");
        std.time.sleep(500 * std.time.ns_per_ms);

        try notifier.updateProgress(0.2, "Connecting to server...");
        std.time.sleep(500 * std.time.ns_per_ms);

        try notifier.updateProgress(0.4, "Uploading files...");
        std.time.sleep(500 * std.time.ns_per_ms);

        try notifier.updateProgress(0.7, "Verifying upload...");
        std.time.sleep(500 * std.time.ns_per_ms);

        try notifier.updateProgress(0.9, "Finalizing...");
        std.time.sleep(300 * std.time.ns_per_ms);

        try notifier.complete("Transfer completed successfully!");
    }

    pub fn runNotificationTypesDemo(manager: *NotificationManager) !void {
        _ = try manager.notify(.info, "Information", "This is an informational message");
        std.time.sleep(200 * std.time.ns_per_ms);

        _ = try manager.notify(.success, "Success", "Operation completed successfully!");
        std.time.sleep(200 * std.time.ns_per_ms);

        _ = try manager.notify(.warning, "Warning", "This action may have consequences");
        std.time.sleep(200 * std.time.ns_per_ms);

        _ = try manager.notify(.err, "Error", "Something went wrong!");
    }
};

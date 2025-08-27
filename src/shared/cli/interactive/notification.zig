//! Notification manager for long-running CLI operations
//! Integrates with terminal notification capabilities and provides fallback options

const std = @import("std");
const components = @import("../../components/mod.zig");
const term_shared = @import("../../term/mod.zig");
const term_notification = term_shared.ansi.notification;
const term_caps = term_shared.caps;
const term_ansi = term_shared.ansi.color;
const components_shared = @import("../components/mod.zig");
const notification_base = components_shared.notification;
const Allocator = std.mem.Allocator;

// Use base notification types
pub const NotificationType = notification_base.NotificationType;

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
pub const NotificationHandler = struct {
    allocator: Allocator,
    caps: term_caps.TermCaps,
    activeNotifications: std.ArrayList(Notification),
    notificationCounter: u64,
    enableDesktopNotifications: bool,
    enableInlineNotifications: bool,
    enableSound: bool,
    writer: ?*std.Io.Writer,

    pub fn init(allocator: Allocator) NotificationHandler {
        return .{
            .allocator = allocator,
            .caps = term_caps.getTermCaps(),
            .activeNotifications = std.ArrayList(Notification).init(allocator),
            .notificationCounter = 0,
            .enableDesktopNotifications = true,
            .enableInlineNotifications = true,
            .enableSound = false,
            .writer = null,
        };
    }

    pub fn deinit(self: *NotificationHandler) void {
        self.activeNotifications.deinit();
    }

    pub fn setWriter(self: *NotificationHandler, writer: *std.Io.Writer) void {
        self.writer = writer;
    }

    /// Send a notification with automatic delivery method selection
    pub fn notify(
        self: *NotificationHandler,
        notification_type: NotificationType,
        title: []const u8,
        message: []const u8,
    ) !u64 {
        self.notificationCounter += 1;
        const notif = Notification.init(
            self.notificationCounter,
            notification_type,
            title,
            message,
        );

        try self.activeNotifications.append(notif);

        // Try desktop notification first if supported and enabled
        if (self.enableDesktopNotifications and self.caps.supportsNotifications()) {
            try self.sendDesktopNotification(notif);
        }

        // Always show inline notification as fallback
        if (self.enableInlineNotifications) {
            try self.showInlineNotification(notif);
        }

        return notif.id;
    }

    /// Send a progress notification
    pub fn notifyProgress(
        self: *NotificationHandler,
        title: []const u8,
        message: []const u8,
        progress: f32,
    ) !u64 {
        self.notificationCounter += 1;
        const notification = Notification.init(
            self.notificationCounter,
            .progress,
            title,
            message,
        ).withProgress(progress).asPersistent();

        // Update or add progress notification
        var found = false;
        for (self.activeNotifications.items, 0..) |*existing, i| {
            if (existing.type == .progress and std.mem.eql(u8, existing.title, title)) {
                self.activeNotifications.items[i] = notification;
                found = true;
                break;
            }
        }

        if (!found) {
            try self.activeNotifications.append(notification);
        }

        // Show progress notification
        try self.showProgressNotification(notification);

        return notification.id;
    }

    /// Send desktop notification using OSC 9
    fn sendDesktopNotification(self: *NotificationHandler, notif: Notification) !void {
        if (self.writer == null) return error.NoWriter;

        const formatted_message = try std.fmt.allocPrint(
            self.allocator,
            "{s}: {s}",
            .{ notif.title, notif.message },
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
    fn showInlineNotification(self: *NotificationHandler, notif: Notification) !void {
        if (self.writer == null) return;
        const writer = self.writer.?;

        // Save cursor position and create notification bar
        try writer.writeAll("\n");

        // Notification type indicator with colors
        switch (notif.type) {
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
            .@"error" => {
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
            .debug => {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer.*, self.caps, 155, 89, 182);
                } else {
                    try term_ansi.setForeground256(writer.*, self.caps, 13);
                }
                try writer.writeAll("🐛 ");
            },
            .critical => {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer.*, self.caps, 192, 57, 43);
                } else {
                    try term_ansi.setForeground256(writer.*, self.caps, 9);
                }
                try writer.writeAll("🚨 ");
            },
        }

        // Title
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 255, 255, 255);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 15);
        }
        try writer.writeAll(notif.title);

        // Message
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 200, 200, 200);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 7);
        }
        try writer.print(": {s}", .{notif.message});

        try term_ansi.resetStyle(writer.*, self.caps);
        try writer.writeAll("\n");
    }

    /// Show progress notification with progress bar
    fn showProgressNotification(self: *NotificationHandler, notif: Notification) !void {
        if (self.writer == null or notif.progress == null) return;
        const writer = self.writer.?;
        const progress = notif.progress.?;

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
        try writer.writeAll(notif.title);

        // Progress bar
        const barWidth = 30;
        const filledWidth = @as(usize, @intFromFloat(progress * @as(f32, @floatFromInt(barWidth))));

        try writer.writeAll(" [");

        // Filled portion
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 50, 205, 50);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 10);
        }
        for (0..filledWidth) |_| {
            try writer.writeAll("█");
        }

        // Empty portion
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer.*, self.caps, 100, 100, 100);
        } else {
            try term_ansi.setForeground256(writer.*, self.caps, 8);
        }
        for (filledWidth..barWidth) |_| {
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
        try writer.print(" - {s}", .{notif.message});

        try term_ansi.resetStyle(writer.*, self.caps);
        try writer.writeAll("\n");
    }

    /// Update progress for an existing notification
    pub fn updateProgress(self: *NotificationHandler, notificationId: u64, progress_value: f32) !void {
        for (self.activeNotifications.items, 0..) |*notif, i| {
            if (notif.id == notificationId and notif.type == .progress) {
                self.activeNotifications.items[i].progress = std.math.clamp(progress_value, 0.0, 1.0);
                try self.showProgressNotification(self.activeNotifications.items[i]);
                break;
            }
        }
    }

    /// Complete a progress notification
    pub fn completeProgress(self: *NotificationHandler, notificationId: u64, final_message: []const u8) !void {
        for (self.activeNotifications.items, 0..) |*notif, i| {
            if (notif.id == notificationId and notif.type == .progress) {
                // Convert to success notification
                const success_notification = Notification.init(
                    notificationId,
                    .success,
                    notif.title,
                    final_message,
                );

                self.activeNotifications.items[i] = success_notification;
                try self.showInlineNotification(success_notification);

                // Send desktop notification for completion if enabled
                if (self.enableDesktopNotifications and self.caps.supportsNotifications()) {
                    try self.sendDesktopNotification(success_notification);
                }
                break;
            }
        }
    }

    /// Remove a notification
    pub fn dismiss(self: *NotificationHandler, notificationId: u64) void {
        for (self.activeNotifications.items, 0..) |notification, i| {
            if (notification.id == notificationId) {
                _ = self.activeNotifications.swapRemove(i);
                break;
            }
        }
    }

    /// Clear all notifications
    pub fn clearAll(self: *NotificationHandler) void {
        self.activeNotifications.clearRetainingCapacity();
    }

    /// Get all active notifications
    pub fn getActiveNotifications(self: *NotificationHandler) []const Notification {
        return self.activeNotifications.items;
    }

    /// Configure notification preferences
    pub fn configure(
        self: *NotificationHandler,
        desktop: bool,
        inlineNotifications: bool,
        sound: bool,
    ) void {
        self.enableDesktopNotifications = desktop;
        self.enableInlineNotifications = inlineNotifications;
        self.enableSound = sound;
    }
};

/// Helper for common long-running operations
pub const OperationNotifier = struct {
    manager: *NotificationHandler,
    notificationId: ?u64,
    operationName: []const u8,

    pub fn init(manager: *NotificationHandler, operationName: []const u8) OperationNotifier {
        return .{
            .manager = manager,
            .notificationId = null,
            .operationName = operationName,
        };
    }

    pub fn start(self: *OperationNotifier, message: []const u8) !void {
        self.notificationId = try self.manager.notifyProgress(
            self.operationName,
            message,
            0.0,
        );
    }

    pub fn updateProgress(self: *OperationNotifier, progress: f32, message: []const u8) !void {
        if (self.notificationId) |_| {
            // Update the message by creating a new notification
            _ = try self.manager.notifyProgress(self.operationName, message, progress);
        }
    }

    pub fn complete(self: *OperationNotifier, finalMessage: []const u8) !void {
        if (self.notificationId) |id| {
            try self.manager.completeProgress(id, finalMessage);
            self.notificationId = null;
        }
    }

    pub fn fail(self: *OperationNotifier, errorMessage: []const u8) !void {
        if (self.notificationId) |_| {
            _ = try self.manager.notify(.err, self.operationName, errorMessage);
            self.notificationId = null;
        }
    }
};

// Demo functions for testing notification features
pub const NotificationDemo = struct {
    pub fn runProgressDemo(manager: *NotificationHandler) !void {
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

    pub fn runNotificationTypesDemo(manager: *NotificationHandler) !void {
        _ = try manager.notify(.info, "Information", "This is an informational message");
        std.time.sleep(200 * std.time.ns_per_ms);

        _ = try manager.notify(.success, "Success", "Operation completed successfully!");
        std.time.sleep(200 * std.time.ns_per_ms);

        _ = try manager.notify(.warning, "Warning", "This action may have consequences");
        std.time.sleep(200 * std.time.ns_per_ms);

        _ = try manager.notify(.err, "Error", "Something went wrong!");
    }
};

//! Notification Display Component
//! Enhanced notification system using system notifications when available

const std = @import("std");
const context = @import("../../core/context.zig");

pub const NotificationDisplay = struct {
    context: *context.CliContext,

    pub const NotificationType = enum {
        info,
        success,
        warning,
        err, // error is reserved keyword
        progress,
    };

    pub const NotificationStyle = enum {
        minimal, // Just icon and text
        detailed, // Full formatting with borders
        system, // Use system notifications when available
    };

    pub fn init(ctx: *context.CliContext) NotificationDisplay {
        return NotificationDisplay{
            .context = ctx,
        };
    }

    /// Show a notification with the specified style
    pub fn show(self: *NotificationDisplay, notification_type: NotificationType, title: []const u8, message: ?[]const u8, style: NotificationStyle) !void {
        switch (style) {
            .system => try self.showSystem(notification_type, title, message),
            .detailed => try self.showDetailed(notification_type, title, message),
            .minimal => try self.showMinimal(notification_type, title, message),
        }
    }

    fn showSystem(self: *NotificationDisplay, notification_type: NotificationType, title: []const u8, message: ?[]const u8) !void {
        if (self.context.hasFeature(.notifications)) {
            // Use system notifications
            const level = switch (notification_type) {
                .info, .progress => context.NotificationManager.NotificationLevel.info,
                .success => context.NotificationManager.NotificationLevel.success,
                .warning => context.NotificationManager.NotificationLevel.warning,
                .err => context.NotificationManager.NotificationLevel.err,
            };

            try self.context.notification.send(.{
                .title = title,
                .body = message,
                .level = level,
                .sound = notification_type == .err or notification_type == .success,
            });
        } else {
            // Fallback to detailed display
            try self.showDetailed(notification_type, title, message);
        }
    }

    fn showDetailed(self: *NotificationDisplay, notification_type: NotificationType, title: []const u8, message: ?[]const u8) !void {
        const writer = std.io.getStdErr().writer();

        // Get colors based on terminal capabilities
        const elements = if (self.context.hasFeature(.truecolor))
            self.getStyledElements(notification_type, true)
        else
            self.getStyledElements(notification_type, false);
        const icon = elements.icon;
        const color_start = elements.color_start;
        const color_end = elements.color_end;

        // Top border
        try writer.print("{s}┌─", .{color_start});
        for (title) |_| try writer.print("─");
        if (message) |msg| {
            const max_len = @max(title.len, msg.len);
            for (0..max_len - title.len) |_| try writer.print("─");
        }
        try writer.print("─┐{s}\n", .{color_end});

        // Title line
        try writer.print("{s}│ {s} {s} │{s}\n", .{ color_start, icon, title, color_end });

        // Message line if provided
        if (message) |msg| {
            try writer.print("{s}│   {s}", .{ color_start, msg });

            // Pad to match title width
            const padding = if (title.len > msg.len) title.len - msg.len else 0;
            for (0..padding) |_| try writer.print(" ");

            try writer.print(" │{s}\n", .{color_end});
        }

        // Bottom border
        try writer.print("{s}└─", .{color_start});
        for (title) |_| try writer.print("─");
        if (message) |msg| {
            const max_len = @max(title.len, msg.len);
            for (0..max_len - title.len) |_| try writer.print("─");
        }
        try writer.print("─┘{s}\n\n", .{color_end});
    }

    fn showMinimal(self: *NotificationDisplay, notification_type: NotificationType, title: []const u8, message: ?[]const u8) !void {
        const writer = std.io.getStdErr().writer();

        const elements = if (self.context.hasFeature(.truecolor))
            self.getStyledElements(notification_type, true)
        else
            self.getStyledElements(notification_type, false);
        const icon = elements.icon;
        const color_start = elements.color_start;
        const color_end = elements.color_end;

        try writer.print("{s}{s} {s}", .{ color_start, icon, title });

        if (message) |msg| {
            try writer.print(": {s}", .{msg});
        }

        try writer.print("{s}\n", .{color_end});
    }

    const StyleElements = struct {
        icon: []const u8,
        color_start: []const u8,
        color_end: []const u8,
    };

    fn getStyledElements(self: *NotificationDisplay, notification_type: NotificationType, use_colors: bool) StyleElements {
        _ = self;

        return switch (notification_type) {
            .info => StyleElements{ .icon = "ℹ", .color_start = if (use_colors) "\x1b[94m" else "", .color_end = if (use_colors) "\x1b[0m" else "" },
            .success => StyleElements{ .icon = "✓", .color_start = if (use_colors) "\x1b[92m" else "", .color_end = if (use_colors) "\x1b[0m" else "" },
            .warning => StyleElements{ .icon = "⚠", .color_start = if (use_colors) "\x1b[93m" else "", .color_end = if (use_colors) "\x1b[0m" else "" },
            .err => StyleElements{ .icon = "✗", .color_start = if (use_colors) "\x1b[91m" else "", .color_end = if (use_colors) "\x1b[0m" else "" },
            .progress => StyleElements{ .icon = "⋯", .color_start = if (use_colors) "\x1b[96m" else "", .color_end = if (use_colors) "\x1b[0m" else "" },
        };
    }

    /// Show progress notification with percentage
    pub fn showProgress(self: *NotificationDisplay, title: []const u8, progress: f32) !void {
        const percentage = @as(u32, @intFromFloat(progress * 100));

        const message = try std.fmt.allocPrint(self.context.allocator, "{d}% complete", .{percentage});
        defer self.context.allocator.free(message);

        try self.show(.progress, title, message, .minimal);
    }
};

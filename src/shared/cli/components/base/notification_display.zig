//! Notification Display Component
//! Enhanced notification system using system notifications when available

const std = @import("std");
const context = @import("../../core/context.zig");
const components_shared = @import("../../components/mod.zig");
const notification_base = components_shared.notification;

// Use base notification types for consistency
pub const NotificationType = notification_base.NotificationType;

pub const NotificationDisplay = struct {
    context: *context.Cli,

    pub const NotificationStyle = enum {
        minimal, // Just icon and text
        detailed, // Full formatting with borders
        system, // Use system notifications when available
    };

    pub fn init(ctx: *context.Cli) NotificationDisplay {
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
                .info, .progress => context.NotificationHandler.NotificationLevel.info,
                .success => context.NotificationHandler.NotificationLevel.success,
                .warning => context.NotificationHandler.NotificationLevel.warning,
                .err => context.NotificationHandler.NotificationLevel.err,
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
        var stderr_buffer: [4096]u8 = undefined;
        const stderr_file = std.fs.File.stderr();
        var writer = stderr_file.writer(&stderr_buffer);

        // Get style based on terminal capabilities
        const elements = if (self.context.hasFeature(.truecolor))
            self.getStyledElements(notification_type, true)
        else
            self.getStyledElements(notification_type, false);
        const icon = elements.icon;
        const style = elements.style;

        // Top border
        try style.apply(writer, self.context.termCaps);
        try writer.print("┌─", .{});
        for (title) |_| try writer.print("─");
        if (message) |msg| {
            const max_len = @max(title.len, msg.len);
            for (0..max_len - title.len) |_| try writer.print("─");
        }
        try writer.print("─┐", .{});
        try context.term.unified.Style.reset(writer, self.context.termCaps);
        try writer.print("\n", .{});

        // Title line
        try style.apply(writer, self.context.termCaps);
        try writer.print("│ {s} {s} │", .{ icon, title });
        try context.term.unified.Style.reset(writer, self.context.termCaps);
        try writer.print("\n", .{});

        // Message line if provided
        if (message) |msg| {
            try style.apply(writer, self.context.termCaps);
            try writer.print("│   {s}", .{msg});

            // Pad to match title width
            const padding = if (title.len > msg.len) title.len - msg.len else 0;
            for (0..padding) |_| try writer.print(" ");

            try writer.print(" │", .{});
            try context.term.unified.Style.reset(writer, self.context.termCaps);
            try writer.print("\n", .{});
        }

        // Bottom border
        try style.apply(writer, self.context.termCaps);
        try writer.print("└─", .{});
        for (title) |_| try writer.print("─");
        if (message) |msg| {
            const max_len = @max(title.len, msg.len);
            for (0..max_len - title.len) |_| try writer.print("─");
        }
        try writer.print("─┘", .{});
        try context.term.unified.Style.reset(writer, self.context.termCaps);
        try writer.print("\n\n", .{});
    }

    fn showMinimal(self: *NotificationDisplay, notification_type: NotificationType, title: []const u8, message: ?[]const u8) !void {
        var stderr_buffer: [4096]u8 = undefined;
        const stderr_file = std.fs.File.stderr();
        var writer = stderr_file.writer(&stderr_buffer);

        const elements = if (self.context.hasFeature(.truecolor))
            self.getStyledElements(notification_type, true)
        else
            self.getStyledElements(notification_type, false);
        const icon = elements.icon;
        const style = elements.style;

        try style.apply(writer, self.context.termCaps);
        try writer.print("{s} {s}", .{ icon, title });

        if (message) |msg| {
            try writer.print(": {s}", .{msg});
        }

        try context.term.unified.Style.reset(writer, self.context.termCaps);
        try writer.print("\n", .{});
    }

    const StyleElements = struct {
        icon: []const u8,
        style: context.term.unified.Style,
    };

    fn getStyledElements(self: *NotificationDisplay, notification_type: NotificationType, use_colors: bool) StyleElements {
        _ = self;

        const style = if (use_colors) switch (notification_type) {
            .info => context.term.unified.Style{ .fg_color = .{ .ansi = 12 } }, // Bright Blue
            .success => context.term.unified.Style{ .fg_color = .{ .ansi = 10 } }, // Bright Green
            .warning => context.term.unified.Style{ .fg_color = .{ .ansi = 11 } }, // Bright Yellow
            .@"error" => context.term.unified.Style{ .fg_color = .{ .ansi = 9 } }, // Bright Red
            .debug => context.term.unified.Style{ .fg_color = .{ .ansi = 13 } }, // Bright Magenta
            .critical => context.term.unified.Style{ .fg_color = .{ .ansi = 9 } }, // Bright Red
            .progress => context.term.unified.Style{ .fg_color = .{ .ansi = 14 } }, // Bright Cyan
        } else context.term.unified.Style{};

        // Use base notification system's icons
        const icon = if (use_colors)
            notification_type.icon()
        else
            notification_type.asciiIcon();

        return StyleElements{ .icon = icon, .style = style };
    }

    /// Show progress notification with percentage
    pub fn showProgress(self: *NotificationDisplay, title: []const u8, progress: f32) !void {
        const percentage = @as(u32, @intFromFloat(progress * 100));

        const message = try std.fmt.allocPrint(self.context.allocator, "{d}% complete", .{percentage});
        defer self.context.allocator.free(message);

        try self.show(.progress, title, message, .minimal);
    }
};

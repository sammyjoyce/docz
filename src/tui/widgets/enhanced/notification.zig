//! Notification widget for user feedback using OSC notifications and TUI displays
//! Supports both terminal notifications (OSC 9) and in-terminal notification banners

const std = @import("std");
const term_caps = @import("../../term/caps.zig");
const term_notification = @import("../../term/ansi/notification.zig");
const term_ansi = @import("../../term/ansi/color.zig");
const term_cursor = @import("../../term/ansi/cursor.zig");
const term_screen = @import("../../term/ansi/screen.zig");
const bounds_mod = @import("../core/bounds.zig");

pub const NotificationLevel = enum {
    info,
    success,
    warning,
    err,
    debug,

    pub fn getIcon(self: NotificationLevel) []const u8 {
        return switch (self) {
            .info => "ℹ",
            .success => "✓",
            .warning => "⚠",
            .err => "✗",
            .debug => "🐛",
        };
    }

    pub fn getColor(self: NotificationLevel, caps: term_caps.TermCaps) []const u8 {
        if (caps.supportsTrueColor()) {
            return switch (self) {
                .info => "\x1b[38;2;100;149;237m", // Cornflower blue
                .success => "\x1b[38;2;50;205;50m", // Lime green
                .warning => "\x1b[38;2;255;215;0m", // Gold
                .err => "\x1b[38;2;220;20;60m", // Crimson
                .debug => "\x1b[38;2;138;43;226m", // Blue violet
            };
        } else if (caps.supports256Color()) {
            return switch (self) {
                .info => "\x1b[38;5;12m", // Bright blue
                .success => "\x1b[38;5;10m", // Bright green
                .warning => "\x1b[38;5;11m", // Bright yellow
                .err => "\x1b[38;5;9m", // Bright red
                .debug => "\x1b[38;5;13m", // Bright magenta
            };
        } else {
            return switch (self) {
                .info => "\x1b[94m", // Bright blue
                .success => "\x1b[92m", // Bright green
                .warning => "\x1b[93m", // Bright yellow
                .err => "\x1b[91m", // Bright red
                .debug => "\x1b[95m", // Bright magenta
            };
        }
    }
};

pub const NotificationPosition = enum {
    top,
    bottom,
    center,
    top_right,
    bottom_right,
};

pub const NotificationOptions = struct {
    level: NotificationLevel = .info,
    title: ?[]const u8 = null,
    position: NotificationPosition = .top,
    duration_ms: ?u32 = null, // Auto-hide after duration (null = manual dismiss)
    show_timestamp: bool = false,
    use_system_notification: bool = true, // Try OSC 9 first
    show_in_terminal: bool = true, // Show banner in terminal
    persistent: bool = false, // Don't auto-hide
    border: bool = true,
    width: ?u32 = null, // Auto-width if null
    padding: u32 = 1,
};

pub const Notification = struct {
    message: []const u8,
    options: NotificationOptions,
    timestamp: i64,
    is_displayed: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, message: []const u8, options: NotificationOptions) Notification {
        return Notification{
            .message = message,
            .options = options,
            .timestamp = std.time.timestamp(),
            .is_displayed = false,
            .allocator = allocator,
        };
    }

    pub fn show(self: *Notification) !void {
        const caps = term_caps.getTermCaps();

        // Try system notification first if enabled and supported
        if (self.options.use_system_notification and caps.supportsNotifyOsc9) {
            try self.showSystemNotification();
        }

        // Show in-terminal notification if enabled
        if (self.options.show_in_terminal) {
            try self.showTerminalNotification();
        }

        self.is_displayed = true;
    }

    pub fn hide(self: *Notification) !void {
        if (!self.is_displayed) return;

        // Clear the terminal notification area
        try self.clearTerminalNotification();
        self.is_displayed = false;
    }

    pub fn getBounds(self: Notification, terminal_size: bounds_mod.TerminalSize) bounds_mod.Bounds {
        const width = self.options.width orelse @min(60, terminal_size.width - 4);
        const height: u32 = if (self.options.title != null) 5 else 3; // Title + content + borders

        const x: u32 = switch (self.options.position) {
            .top, .bottom, .center => (terminal_size.width - width) / 2,
            .top_right, .bottom_right => terminal_size.width - width - 1,
        };

        const y: u32 = switch (self.options.position) {
            .top, .top_right => 1,
            .bottom, .bottom_right => terminal_size.height - height - 1,
            .center => (terminal_size.height - height) / 2,
        };

        return bounds_mod.Bounds{
            .x = @intCast(x),
            .y = @intCast(y),
            .width = width,
            .height = height,
        };
    }

    fn showSystemNotification(self: *Notification) !void {
        const caps = term_caps.getTermCaps();
        const writer = std.fs.File.stdout().writer().any();

        var notification_text = std.ArrayList(u8).init(self.allocator);
        defer notification_text.deinit();

        if (self.options.title) |title| {
            try notification_text.appendSlice(title);
            try notification_text.appendSlice(": ");
        }

        try notification_text.appendSlice(self.message);

        try term_notification.writeNotification(writer, self.allocator, caps, notification_text.items);
    }

    fn showTerminalNotification(self: *Notification) !void {
        const caps = term_caps.getTermCaps();
        const writer = std.fs.File.stdout().writer().any();
        const terminal_size = bounds_mod.getTerminalSize();
        const notification_bounds = self.getBounds(terminal_size);

        // Save cursor position
        try term_cursor.saveCursor(writer, caps);

        // Move to notification position
        try term_cursor.setCursor(writer, caps, @intCast(notification_bounds.y), @intCast(notification_bounds.x));

        try self.renderNotification(writer, caps, notification_bounds);

        // Restore cursor position
        try term_cursor.restoreCursor(writer, caps);
    }

    fn clearTerminalNotification(self: *Notification) !void {
        const caps = term_caps.getTermCaps();
        const writer = std.fs.File.stdout().writer().any();
        const terminal_size = bounds_mod.getTerminalSize();
        const notification_bounds = self.getBounds(terminal_size);

        // Save cursor position
        try term_cursor.saveCursor(writer, caps);

        // Clear notification area
        var y = notification_bounds.y;
        while (y < notification_bounds.y + notification_bounds.height) {
            try term_cursor.setCursor(writer, caps, @intCast(y), @intCast(notification_bounds.x));
            try term_screen.clearToEndOfLine(writer, caps);
            y += 1;
        }

        // Restore cursor position
        try term_cursor.restoreCursor(writer, caps);
    }

    fn renderNotification(self: *Notification, writer: anytype, caps: term_caps.TermCaps, bounds: bounds_mod.Bounds) !void {
        const level_color = self.options.level.getColor(caps);
        const icon = self.options.level.getIcon();
        const reset = "\x1b[0m";

        var current_y: u32 = 0;

        // Top border
        if (self.options.border) {
            try writer.writeAll(level_color);
            try writer.writeAll("┌");
            for (0..bounds.width - 2) |_| {
                try writer.writeAll("─");
            }
            try writer.writeAll("┐");
            try writer.writeAll(reset);
            current_y += 1;
        }

        // Title line (if present)
        if (self.options.title) |title| {
            try term_cursor.setCursor(writer, caps, @intCast(bounds.y + current_y), @intCast(bounds.x));

            if (self.options.border) {
                try writer.writeAll(level_color);
                try writer.writeAll("│ ");
                try writer.writeAll(reset);
            }

            try writer.writeAll(level_color);
            try term_ansi.bold(writer, caps);
            try writer.print("{s} {s}", .{ icon, title });
            try term_ansi.resetStyle(writer, caps);

            if (self.options.border) {
                // Pad to right border
                const content_width = bounds.width - 4; // Account for borders and padding
                const title_len = std.unicode.utf8CountCodepoints(title) catch title.len;
                const used_width = 2 + title_len; // icon + space + title
                if (used_width < content_width) {
                    for (0..(content_width - used_width)) |_| {
                        try writer.writeAll(" ");
                    }
                }
                try writer.writeAll(level_color);
                try writer.writeAll(" │");
                try writer.writeAll(reset);
            }

            current_y += 1;
        }

        // Message line
        try term_cursor.setCursor(writer, caps, @intCast(bounds.y + current_y), @intCast(bounds.x));

        if (self.options.border) {
            try writer.writeAll(level_color);
            try writer.writeAll("│ ");
            try writer.writeAll(reset);
        }

        // If no title, show icon with message
        if (self.options.title == null) {
            try writer.writeAll(level_color);
            try writer.print("{s} ", .{icon});
        }

        try writer.writeAll(self.message);

        if (self.options.border) {
            // Pad to right border
            const content_width = bounds.width - 4;
            const icon_width: u32 = if (self.options.title == null) 2 else 0;
            const message_len = std.unicode.utf8CountCodepoints(self.message) catch self.message.len;
            const used_width = icon_width + @as(u32, @intCast(message_len));

            if (used_width < content_width) {
                for (0..(content_width - used_width)) |_| {
                    try writer.writeAll(" ");
                }
            }

            try writer.writeAll(level_color);
            try writer.writeAll(" │");
            try writer.writeAll(reset);
        }

        current_y += 1;

        // Bottom border
        if (self.options.border) {
            try term_cursor.setCursor(writer, caps, @intCast(bounds.y + current_y), @intCast(bounds.x));
            try writer.writeAll(level_color);
            try writer.writeAll("└");
            for (0..bounds.width - 2) |_| {
                try writer.writeAll("─");
            }
            try writer.writeAll("┘");
            try writer.writeAll(reset);
        }

        try writer.writeAll(reset);
    }
};

/// Notification Manager for handling multiple notifications
pub const NotificationManager = struct {
    notifications: std.ArrayList(Notification),
    allocator: std.mem.Allocator,
    max_concurrent: u32,

    pub fn init(allocator: std.mem.Allocator) NotificationManager {
        return NotificationManager{
            .notifications = std.ArrayList(Notification).init(allocator),
            .allocator = allocator,
            .max_concurrent = 3, // Limit concurrent notifications
        };
    }

    pub fn deinit(self: *NotificationManager) void {
        for (self.notifications.items) |*notification| {
            notification.hide() catch {}; // Best effort cleanup
        }
        self.notifications.deinit();
    }

    pub fn notify(self: *NotificationManager, message: []const u8, options: NotificationOptions) !void {
        // Clean up old notifications if we're at the limit
        try self.cleanup();

        var notification = Notification.init(self.allocator, message, options);
        try notification.show();
        try self.notifications.append(notification);
    }

    pub fn info(self: *NotificationManager, message: []const u8) !void {
        try self.notify(message, NotificationOptions{ .level = .info });
    }

    pub fn success(self: *NotificationManager, message: []const u8) !void {
        try self.notify(message, NotificationOptions{ .level = .success });
    }

    pub fn warning(self: *NotificationManager, message: []const u8) !void {
        try self.notify(message, NotificationOptions{ .level = .warning });
    }

    pub fn error_(self: *NotificationManager, message: []const u8) !void {
        try self.notify(message, NotificationOptions{ .level = .err });
    }

    pub fn debug(self: *NotificationManager, message: []const u8) !void {
        try self.notify(message, NotificationOptions{ .level = .debug });
    }

    pub fn clearAll(self: *NotificationManager) !void {
        for (self.notifications.items) |*notification| {
            try notification.hide();
        }
        self.notifications.clearAndFree();
    }

    fn cleanup(self: *NotificationManager) !void {
        const now = std.time.timestamp();
        var i: usize = 0;

        while (i < self.notifications.items.len) {
            const notification = &self.notifications.items[i];
            const age_ms = @as(u32, @intCast(now - notification.timestamp)) * 1000;

            // Remove expired notifications or if we're over the limit
            const should_remove = if (notification.options.duration_ms) |duration|
                age_ms > duration and !notification.options.persistent
            else
                self.notifications.items.len >= self.max_concurrent;

            if (should_remove) {
                try notification.hide();
                _ = self.notifications.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }
};

/// Convenience functions for quick notifications
pub fn notify(allocator: std.mem.Allocator, message: []const u8, options: NotificationOptions) !void {
    var notification = Notification.init(allocator, message, options);
    try notification.show();
}

pub fn info(allocator: std.mem.Allocator, message: []const u8) !void {
    try notify(allocator, message, NotificationOptions{ .level = .info });
}

pub fn success(allocator: std.mem.Allocator, message: []const u8) !void {
    try notify(allocator, message, NotificationOptions{ .level = .success });
}

pub fn warning(allocator: std.mem.Allocator, message: []const u8) !void {
    try notify(allocator, message, NotificationOptions{ .level = .warning });
}

pub fn error_(allocator: std.mem.Allocator, message: []const u8) !void {
    try notify(allocator, message, NotificationOptions{ .level = .err });
}

pub fn debug(allocator: std.mem.Allocator, message: []const u8) !void {
    try notify(allocator, message, NotificationOptions{ .level = .debug });
}

/// Quick system notification (OSC 9 only)
pub fn systemNotify(allocator: std.mem.Allocator, message: []const u8) !void {
    try notify(allocator, message, NotificationOptions{ .use_system_notification = true, .show_in_terminal = false });
}

/// Check if notifications are supported
pub fn isNotificationSupported() bool {
    const caps = term_caps.getTermCaps();
    return caps.supportsNotifyOsc9;
}

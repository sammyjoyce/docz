//! Unified Notification Base System
//!
//! This module provides a common foundation for all notification systems,
//! eliminating duplication and providing consistent behavior across CLI and TUI contexts.
//!
//! Features:
//! - Common NotificationType enum with icons and colors
//! - Shared color schemes and icon mappings
//! - Base notification structure with common fields
//! - OSC 9 system notification wrapper
//! - Common sanitization and formatting utilities

const std = @import("std");
const term_shared = @import("../term/mod.zig");
const ansi_notifications = term_shared.ansi.notification;

/// Common notification types with semantic meaning
pub const NotificationType = enum {
    info,
    success,
    warning,
    @"error",
    debug,
    critical,

    /// Get the appropriate icon for this notification type
    pub fn icon(self: NotificationType) []const u8 {
        return switch (self) {
            .info => "ℹ️",
            .success => "✅",
            .warning => "⚠️",
            .@"error" => "❌",
            .debug => "🐛",
            .critical => "🚨",
        };
    }

    /// Get the fallback ASCII icon
    pub fn asciiIcon(self: NotificationType) []const u8 {
        return switch (self) {
            .info => "[INFO]",
            .success => "[OK]",
            .warning => "[WARN]",
            .@"error" => "[ERR]",
            .debug => "[DBG]",
            .critical => "[!!!]",
        };
    }

    /// Get the appropriate color for this notification type
    pub fn color(self: NotificationType) term_shared.unified.Color {
        return switch (self) {
            .info => term_shared.unified.Color{ .rgb = .{ .r = 52, .g = 152, .b = 219 } }, // Blue
            .success => term_shared.unified.Color{ .rgb = .{ .r = 46, .g = 204, .b = 113 } }, // Green
            .warning => term_shared.unified.Color{ .rgb = .{ .r = 241, .g = 196, .b = 15 } }, // Yellow
            .@"error" => term_shared.unified.Color{ .rgb = .{ .r = 231, .g = 76, .b = 60 } }, // Red
            .debug => term_shared.unified.Color{ .rgb = .{ .r = 155, .g = 89, .b = 182 } }, // Purple
            .critical => term_shared.unified.Color{ .rgb = .{ .r = 192, .g = 57, .b = 43 } }, // Dark red
        };
    }

    /// Convert to unified notification level
    pub fn toUnifiedLevel(self: NotificationType) term_shared.unified.NotificationLevel {
        return switch (self) {
            .info => .info,
            .success => .success,
            .warning => .warning,
            .@"error" => .@"error",
            .debug => .debug,
            .critical => .@"error", // Map critical to error for unified interface
        };
    }
};

/// Configuration for notification rendering and behavior
pub const NotificationConfig = struct {
    // Behavior settings
    enable_system_notifications: bool = true,
    enable_sound: bool = false,
    auto_dismiss_ms: ?u32 = null,

    // Appearance settings
    show_timestamp: bool = true,
    show_icons: bool = true,
    max_width: u32 = 80,
    padding: u32 = 1,

    // Integration settings
    enable_clipboard_actions: bool = true,
    enable_hyperlinks: bool = true,
};

/// Action that can be attached to a notification
pub const NotificationAction = struct {
    label: []const u8,
    action: ActionType,

    pub const ActionType = union(enum) {
        copy_text: []const u8,
        open_url: []const u8,
        execute_command: []const u8,
        callback: *const fn () void,
    };
};

/// Base notification structure with common fields
pub const BaseNotification = struct {
    const Self = @This();

    // Core notification data
    title: []const u8,
    message: []const u8,
    notification_type: NotificationType,
    timestamp: i64,
    config: NotificationConfig,

    // Optional metadata
    actions: []const NotificationAction = &[_]NotificationAction{},
    priority: Priority = .normal,
    persistent: bool = false,

    /// Priority levels for notifications
    pub const Priority = enum {
        low,
        normal,
        high,
        critical,
    };

    /// Initialize a new base notification
    pub fn init(
        title: []const u8,
        message: []const u8,
        notification_type: NotificationType,
        config: NotificationConfig,
    ) Self {
        return Self{
            .title = title,
            .message = message,
            .notification_type = notification_type,
            .timestamp = std.time.timestamp(),
            .config = config,
        };
    }

    /// Create a notification with actions
    pub fn initWithActions(
        title: []const u8,
        message: []const u8,
        notification_type: NotificationType,
        config: NotificationConfig,
        actions: []const NotificationAction,
    ) Self {
        return Self{
            .title = title,
            .message = message,
            .notification_type = notification_type,
            .timestamp = std.time.timestamp(),
            .config = config,
            .actions = actions,
        };
    }

    /// Check if the notification should auto-dismiss
    pub fn shouldAutoDismiss(self: *const Self) bool {
        if (self.persistent) return false;
        if (self.config.auto_dismiss_ms == null) return false;

        const now = std.time.timestamp();
        const age_ms = @as(u32, @intCast(now - self.timestamp)) * 1000;
        return age_ms > self.config.auto_dismiss_ms.?;
    }

    /// Get the formatted timestamp string
    pub fn getFormattedTimestamp(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const timestamp_str = try std.fmt.allocPrint(allocator, "at {d}", .{self.timestamp});
        return timestamp_str;
    }

    /// Sanitize notification content for safe display
    pub fn sanitizeContent(self: *const Self, allocator: std.mem.Allocator) !struct { title: []u8, message: []u8 } {
        const clean_title = try NotificationUtils.sanitizeText(allocator, self.title);
        errdefer allocator.free(clean_title);

        const clean_message = try NotificationUtils.sanitizeText(allocator, self.message);
        errdefer allocator.free(clean_message);

        return .{ .title = clean_title, .message = clean_message };
    }
};

/// System notification wrapper using OSC 9
pub const SystemNotification = struct {
    /// Send a system notification using OSC 9 if supported
    pub fn send(
        writer: anytype,
        allocator: std.mem.Allocator,
        caps: term_shared.TermCaps,
        title: []const u8,
        message: []const u8,
    ) !void {
        if (!caps.supportsNotifyOsc9) return error.Unsupported;

        // Combine title and message for system notification
        const combined = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ title, message });
        defer allocator.free(combined);

        try ansi_notifications.writeNotification(writer, allocator, caps, combined);
    }

    /// Send a system notification using the base notification
    pub fn sendFromBase(
        writer: anytype,
        allocator: std.mem.Allocator,
        caps: term_shared.TermCaps,
        notification: *const BaseNotification,
    ) !void {
        try send(writer, allocator, caps, notification.title, notification.message);
    }
};

/// Common sanitization and formatting utilities
pub const NotificationUtils = struct {
    /// Sanitize text by removing control characters
    pub fn sanitizeText(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        var out = std.ArrayList(u8).init(allocator);
        errdefer out.deinit();

        for (text) |ch| {
            // Remove control characters except newline and tab
            if (ch < 32 and ch != '\n' and ch != '\t') continue;
            // Remove escape sequences
            if (ch == 0x1b) continue;
            try out.append(ch);
        }

        return try out.toOwnedSlice();
    }

    /// Format notification content with word wrapping
    pub fn formatContent(
        allocator: std.mem.Allocator,
        title: []const u8,
        message: []const u8,
        max_width: u32,
    ) !struct { formatted_title: []u8, formatted_message: []u8 } {
        const clean_title = try sanitizeText(allocator, title);
        errdefer allocator.free(clean_title);

        const clean_message = try sanitizeText(allocator, message);
        errdefer allocator.free(clean_message);

        // Simple word wrapping for message
        const wrapped_message = try wordWrap(allocator, clean_message, max_width);
        errdefer allocator.free(wrapped_message);

        return .{
            .formatted_title = clean_title,
            .formatted_message = wrapped_message,
        };
    }

    /// Simple word wrapping implementation
    pub fn wordWrap(allocator: std.mem.Allocator, text: []const u8, max_width: u32) ![]u8 {
        if (text.len <= max_width) return allocator.dupe(u8, text);

        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        var line_start: usize = 0;
        var i: usize = 0;

        while (i < text.len) {
            if (i - line_start >= max_width) {
                // Find the last space within the line
                var break_pos = i;
                while (break_pos > line_start and text[break_pos] != ' ') {
                    break_pos -= 1;
                }

                if (break_pos == line_start) {
                    // No space found, break at max_width
                    break_pos = i;
                }

                // Add the line
                try result.appendSlice(text[line_start..break_pos]);
                try result.append('\n');
                line_start = break_pos + 1;
                i = line_start;
            } else {
                i += 1;
            }
        }

        // Add remaining text
        if (line_start < text.len) {
            try result.appendSlice(text[line_start..]);
        }

        return try result.toOwnedSlice();
    }

    /// Get appropriate border characters based on terminal capabilities
    pub fn getBorderChars(use_unicode: bool) struct { top: []const u8, middle: []const u8, bottom: []const u8, vertical: []const u8 } {
        if (use_unicode) {
            return .{
                .top = "╭─",
                .middle = "├─",
                .bottom = "╰─",
                .vertical = "│",
            };
        } else {
            return .{
                .top = "+-",
                .middle = "+-",
                .bottom = "+-",
                .vertical = "|",
            };
        }
    }

    /// Calculate notification dimensions
    pub fn calculateDimensions(
        title: []const u8,
        message: []const u8,
        config: NotificationConfig,
    ) struct { width: u32, height: u32 } {
        const title_len = std.unicode.utf8CountCodepoints(title) catch title.len;
        const message_len = std.unicode.utf8CountCodepoints(message) catch message.len;

        const content_width = @min(config.max_width - 4, @max(title_len, message_len) + 4);
        const total_width = content_width + 4; // Account for borders

        var height: u32 = 3; // Top border, title, bottom border
        height += if (config.show_timestamp) 1 else 0;
        height += if (message.len > 0) 1 else 0; // Message line

        return .{ .width = total_width, .height = height };
    }
};

/// Common color schemes for notifications
pub const ColorSchemes = struct {
    /// Get the standard color scheme for a notification type
    pub fn getStandard(notification_type: NotificationType) struct {
        border: term_shared.unified.Color,
        background: ?term_shared.unified.Color,
        text: ?term_shared.unified.Color,
    } {
        const base_color = notification_type.color();

        return .{
            .border = base_color,
            .background = switch (notification_type) {
                .critical => term_shared.unified.Color{ .rgb = .{ .r = 20, .g = 20, .b = 20 } },
                else => null,
            },
            .text = switch (notification_type) {
                .info, .success, .warning, .@"error", .debug, .critical => term_shared.unified.Colors.WHITE,
            },
        };
    }

    /// Get muted colors for less intrusive notifications
    pub fn getMuted() struct {
        border: term_shared.unified.Color,
        background: ?term_shared.unified.Color,
        text: ?term_shared.unified.Color,
    } {
        return .{
            .border = term_shared.unified.Colors.BRIGHT_BLACK,
            .background = null,
            .text = term_shared.unified.Colors.WHITE,
        };
    }
};

/// Sound notification patterns
pub const SoundPatterns = struct {
    /// Get the appropriate sound pattern for a notification type
    pub fn getPattern(notification_type: NotificationType) struct {
        pattern: []const u8,
        duration_ms: u32,
    } {
        return switch (notification_type) {
            .info => .{ .pattern = "\x07", .duration_ms = 100 },
            .success => .{ .pattern = "\x07\x07", .duration_ms = 150 },
            .warning => .{ .pattern = "\x07\x07\x07", .duration_ms = 200 },
            .@"error" => .{ .pattern = "\x07\x07\x07\x07", .duration_ms = 100 },
            .debug => .{ .pattern = "\x07", .duration_ms = 50 },
            .critical => .{ .pattern = "\x07\x07\x07\x07\x07", .duration_ms = 50 },
        };
    }

    /// Play a sound pattern using the writer
    pub fn playPattern(writer: anytype, pattern: []const u8, duration_ms: u32) !void {
        for (pattern) |bell| {
            try writer.writeByte(bell);
            if (duration_ms > 0) {
                std.time.sleep(@as(u64, duration_ms) * std.time.ns_per_ms);
            }
        }
    }
};

test "notification types" {
    try std.testing.expectEqualStrings("ℹ️", NotificationType.info.icon());
    try std.testing.expectEqualStrings("[INFO]", NotificationType.info.asciiIcon());

    const info_color = NotificationType.info.color();
    try std.testing.expect(info_color == .rgb);
}

test "notification sanitization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const dirty_text = "Hello\x1b[31m\x07World\x00Test";
    const clean_text = try NotificationUtils.sanitizeText(allocator, dirty_text);
    defer allocator.free(clean_text);

    try std.testing.expectEqualStrings("HelloWorldTest", clean_text);
}

test "word wrapping" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const long_text = "This is a very long message that should be wrapped";
    const wrapped = try NotificationUtils.wordWrap(allocator, long_text, 20);
    defer allocator.free(wrapped);

    // Should contain newlines
    try std.testing.expect(std.mem.indexOf(u8, wrapped, "\n") != null);
}

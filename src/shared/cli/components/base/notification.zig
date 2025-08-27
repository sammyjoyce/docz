//! Enhanced CLI Notification Component
//!
//! This component extends the unified notification base system with CLI-specific features:
//! - System notifications when supported
//! - Rich in-terminal notifications with proper styling
//! - Hyperlink support for clickable actions
//! - Clipboard integration for easy copying
//! - Progressive enhancement based on terminal capabilities
//! - CLI-specific sound patterns and actions

const std = @import("std");
const term_shared = @import("term_shared");
const unified = term_shared.unified;
const terminal_bridge = @import("../../core/terminal_bridge.zig");
const components_shared = @import("../../components/mod.zig");
const notification_base = components_shared.notification_base;

// Re-export base types for convenience
pub const NotificationType = notification_base.NotificationType;
pub const NotificationConfig = notification_base.NotificationConfig;
pub const NotificationAction = notification_base.NotificationAction;
pub const BaseNotification = notification_base.BaseNotification;

/// Main CLI notification component extending the base system
pub const Notification = struct {
    const Self = @This();

    bridge: *terminal_bridge.TerminalBridge,
    config: NotificationConfig,

    // State tracking
    notification_count: u64 = 0,
    last_notification_time: i64 = 0,

    pub fn init(bridge: *terminal_bridge.TerminalBridge, config: NotificationConfig) Self {
        return Self{
            .bridge = bridge,
            .config = config,
        };
    }

    /// Show a simple notification with just a message
    pub fn show(self: *Self, notification_type: NotificationType, title: []const u8, message: []const u8) !void {
        try self.showWithActions(notification_type, title, message, &[_]NotificationAction{});
    }

    /// Show a notification with clickable actions
    pub fn showWithActions(self: *Self, notification_type: NotificationType, title: []const u8, message: []const u8, actions: []const NotificationAction) !void {
        self.notification_count += 1;
        self.last_notification_time = std.time.milliTimestamp();

        const strategy = self.bridge.getRenderStrategy();
        const caps = self.bridge.getCapabilities();

        // Try system notification first if enabled and supported
        if (self.config.enable_system_notifications and caps.supportsNotifyOsc9) {
            try notification_base.SystemNotification.sendFromBase(
                self.bridge.writer(),
                self.bridge.allocator,
                caps,
                &BaseNotification.init(title, message, notification_type, self.config),
            );
        }

        // Always render in-terminal notification as well
        try self.renderInTerminal(notification_type, title, message, actions, strategy);

        // Add sound notification if enabled
        if (self.config.enable_sound) {
            try self.playNotificationSound(notification_type);
        }
    }

    /// Render the notification in the terminal with adaptive styling
    fn renderInTerminal(self: *Self, notification_type: NotificationType, title: []const u8, message: []const u8, actions: []const NotificationAction, strategy: terminal_bridge.RenderStrategy) !void {
        // Create notification box with adaptive styling
        const box_style = self.createBoxStyle(notification_type, strategy);

        // Calculate dimensions
        const content_width = @min(self.config.max_width - 4, @max(title.len, message.len) + 4);
        const total_width = content_width + 4; // Account for borders

        // Save cursor position and render notification
        var render_ctx = try self.bridge.createRenderContext();
        defer render_ctx.deinit();

        try self.renderNotificationBox(notification_type, title, message, actions, box_style, content_width, total_width, strategy);
    }

    /// Create appropriate box styling based on notification type and terminal capabilities
    fn createBoxStyle(self: *Self, notification_type: NotificationType, strategy: terminal_bridge.RenderStrategy) BoxStyle {
        _ = self;

        const color_scheme = notification_base.ColorSchemes.getStandard(notification_type);

        return BoxStyle{
            .border_color = color_scheme.border,
            .background_color = switch (strategy) {
                .rich_text, .full_graphics => color_scheme.background orelse unified.Color{ .rgb = .{ .r = 20, .g = 20, .b = 20 } },
                else => null, // No background for limited terminals
            },
            .text_color = switch (strategy) {
                .rich_text, .full_graphics, .enhanced_ansi => color_scheme.text orelse unified.Colors.WHITE,
                .basic_ascii => null, // Use default terminal colors
                .fallback => null,
            },
            .use_unicode_borders = strategy.supportsColor(),
        };
    }

    /// Render the complete notification box with borders, content, and actions
    fn renderNotificationBox(self: *Self, notification_type: NotificationType, title: []const u8, message: []const u8, actions: []const NotificationAction, box_style: BoxStyle, content_width: u32, total_width: u32, strategy: terminal_bridge.RenderStrategy) !void {
        // Top border
        try self.renderBorderLine(.top, box_style, total_width);

        // Title line with icon
        try self.renderTitleLine(notification_type, title, box_style, content_width, strategy);

        // Message line(s) - handle word wrapping
        try self.renderMessageLines(message, box_style, content_width);

        // Timestamp if enabled
        if (self.config.show_timestamp) {
            try self.renderTimestampLine(box_style, content_width);
        }

        // Actions if present
        if (actions.len > 0) {
            try self.renderActionLines(actions, box_style, content_width, strategy);
        }

        // Bottom border
        try self.renderBorderLine(.bottom, box_style, total_width);

        try self.bridge.print("\n", null);
    }

    /// Render a border line (top, middle, or bottom)
    fn renderBorderLine(self: *Self, border_type: BorderType, box_style: BoxStyle, width: u32) !void {
        const border_style = unified.Style{ .fg_color = box_style.border_color };

        if (box_style.use_unicode_borders) {
            const border_chars = switch (border_type) {
                .top => .{ "╭", "─", "╮" },
                .middle => .{ "├", "─", "┤" },
                .bottom => .{ "╰", "─", "╯" },
            };
            const left_char = border_chars[0];
            const middle_char = border_chars[1];
            const right_char = border_chars[2];

            try self.bridge.print(left_char, border_style);
            for (0..width - 2) |_| {
                try self.bridge.print(middle_char, border_style);
            }
            try self.bridge.print(right_char, border_style);
        } else {
            // ASCII fallback
            try self.bridge.print("+", border_style);
            for (0..width - 2) |_| {
                try self.bridge.print("-", border_style);
            }
            try self.bridge.print("+", border_style);
        }

        try self.bridge.print("\n", null);
    }

    /// Render the title line with icon and proper spacing
    fn renderTitleLine(self: *Self, notification_type: NotificationType, title: []const u8, box_style: BoxStyle, content_width: u32, strategy: terminal_bridge.RenderStrategy) !void {
        const border_style = unified.Style{ .fg_color = box_style.border_color };
        const text_style = if (box_style.text_color) |color| unified.Style{ .fg_color = color, .bold = true } else unified.Style{ .bold = true };

        const vertical_char = if (box_style.use_unicode_borders) "│" else "|";

        try self.bridge.print(vertical_char, border_style);
        try self.bridge.print(" ", null);

        // Icon
        if (self.config.show_icons) {
            const icon_text = switch (strategy) {
                .rich_text, .full_graphics, .enhanced_ansi => notification_type.icon(),
                else => notification_type.asciiIcon(),
            };
            try self.bridge.print(icon_text, unified.Style{ .fg_color = notification_type.color() });
            try self.bridge.print(" ", null);
        }

        // Title
        try self.bridge.print(title, text_style);

        // Padding to fill the line
        const used_width = 2 + title.len + if (self.config.show_icons) 3 else 0; // Rough estimate
        if (used_width < content_width) {
            for (0..content_width - used_width) |_| {
                try self.bridge.print(" ", null);
            }
        }

        try self.bridge.print(" ", null);
        try self.bridge.print(vertical_char, border_style);
        try self.bridge.print("\n", null);
    }

    /// Render message lines with word wrapping if needed
    fn renderMessageLines(self: *Self, message: []const u8, box_style: BoxStyle, content_width: u32) !void {
        const border_style = unified.Style{ .fg_color = box_style.border_color };
        const text_style = if (box_style.text_color) |color| unified.Style{ .fg_color = color } else null;

        const vertical_char = if (box_style.use_unicode_borders) "│" else "|";

        // Simple word wrapping (can be improved)
        const max_message_width = content_width - 2; // Account for padding
        var remaining = message;

        while (remaining.len > 0) {
            const line_end = if (remaining.len <= max_message_width)
                remaining.len
            else
                max_message_width;

            const line = remaining[0..line_end];
            remaining = remaining[line_end..];

            try self.bridge.print(vertical_char, border_style);
            try self.bridge.print(" ", null);
            try self.bridge.print(line, text_style);

            // Padding to fill the line
            if (line.len < max_message_width) {
                for (0..max_message_width - line.len) |_| {
                    try self.bridge.print(" ", null);
                }
            }

            try self.bridge.print(" ", null);
            try self.bridge.print(vertical_char, border_style);
            try self.bridge.print("\n", null);
        }
    }

    /// Render timestamp line if enabled
    fn renderTimestampLine(self: *Self, box_style: BoxStyle, content_width: u32) !void {
        const border_style = unified.Style{ .fg_color = box_style.border_color };
        const muted_style = terminal_bridge.Styles.MUTED;

        const vertical_char = if (box_style.use_unicode_borders) "│" else "|";

        // Get current timestamp
        const now = std.time.milliTimestamp();
        const timestamp_str = try std.fmt.allocPrint(self.bridge.allocator, "at {d}", .{now}); // Simplified timestamp
        defer self.bridge.allocator.free(timestamp_str);

        try self.bridge.print(vertical_char, border_style);
        try self.bridge.print(" ", null);
        try self.bridge.print(timestamp_str, muted_style);

        // Padding
        if (timestamp_str.len < content_width - 2) {
            for (0..content_width - 2 - timestamp_str.len) |_| {
                try self.bridge.print(" ", null);
            }
        }

        try self.bridge.print(" ", null);
        try self.bridge.print(vertical_char, border_style);
        try self.bridge.print("\n", null);
    }

    /// Render action lines with hyperlinks when supported
    fn renderActionLines(self: *Self, actions: []const NotificationAction, box_style: BoxStyle, content_width: u32, strategy: terminal_bridge.RenderStrategy) !void {
        const border_style = unified.Style{ .fg_color = box_style.border_color };
        const vertical_char = if (box_style.use_unicode_borders) "│" else "|";

        // Add separator line
        try self.renderBorderLine(.middle, box_style, content_width + 4);

        for (actions) |action| {
            try self.bridge.print(vertical_char, border_style);
            try self.bridge.print(" ", null);

            // Render action based on type and terminal capabilities
            switch (action.action) {
                .copy_text => |text| {
                    if (self.config.enable_clipboard_actions) {
                        try self.bridge.printf("📋 Copy: {s}", .{action.label}, terminal_bridge.Styles.INFO);
                        // Could add clipboard functionality here
                        _ = text;
                    }
                },
                .open_url => |url| {
                    if (self.config.enable_hyperlinks and strategy.supportsColor()) {
                        try self.bridge.hyperlink(url, action.label, unified.Style{ .underline = true, .fg_color = unified.Colors.BLUE });
                    } else {
                        try self.bridge.printf("{s} ({s})", .{ action.label, url }, null);
                    }
                },
                .execute_command => |cmd| {
                    try self.bridge.printf("⚡ {s} -> {s}", .{ action.label, cmd }, terminal_bridge.Styles.WARNING);
                },
                .callback => {
                    try self.bridge.printf("🔘 {s}", .{action.label}, terminal_bridge.Styles.HIGHLIGHT);
                },
            }

            try self.bridge.print(" ", null);
            try self.bridge.print(vertical_char, border_style);
            try self.bridge.print("\n", null);
        }
    }

    /// Play sound notification based on notification type
    fn playNotificationSound(self: *Self, notification_type: NotificationType) !void {
        // Only play sound if enabled in config
        if (!self.config.enable_sound) return;

        // Use system bell with different patterns for different notification types
        try self.playSystemBell(notification_type);
    }

    /// Play system bell with notification-type-specific patterns
    fn playSystemBell(self: *Self, notification_type: NotificationType) !void {
        const writer = self.bridge.writer();
        const pattern = notification_base.SoundPatterns.getPattern(notification_type);

        try notification_base.SoundPatterns.playPattern(writer, pattern.pattern, pattern.duration_ms);
    }

    /// Get notification statistics
    pub fn getStats(self: *Self) NotificationStats {
        return NotificationStats{
            .total_count = self.notification_count,
            .last_notification_time = self.last_notification_time,
        };
    }
};

/// Styling configuration for notification boxes
const BoxStyle = struct {
    border_color: unified.Color,
    background_color: ?unified.Color = null,
    text_color: ?unified.Color = null,
    use_unicode_borders: bool = true,
};

/// Border type for different parts of the notification box
const BorderType = enum {
    top,
    middle,
    bottom,
};

/// Statistics about notification usage
pub const NotificationStats = struct {
    total_count: u64,
    last_notification_time: i64,
};

/// Convenient preset notification functions
pub const NotificationPresets = struct {
    /// Show a success notification with copy action
    pub fn success(notification: *Notification, title: []const u8, message: []const u8, copy_text: ?[]const u8) !void {
        if (copy_text) |text| {
            const actions = [_]NotificationAction{
                NotificationAction{
                    .label = "Copy Result",
                    .action = .{ .copy_text = text },
                },
            };
            try notification.showWithActions(.success, title, message, &actions);
        } else {
            try notification.show(.success, title, message);
        }
    }

    /// Show an error notification with support link
    pub fn showError(notification: *Notification, title: []const u8, message: []const u8, support_url: ?[]const u8) !void {
        if (support_url) |url| {
            const actions = [_]NotificationAction{
                NotificationAction{
                    .label = "Get Help",
                    .action = .{ .open_url = url },
                },
            };
            try notification.showWithActions(.@"error", title, message, &actions);
        } else {
            try notification.show(.@"error", title, message);
        }
    }

    /// Show an info notification with a clickable link
    pub fn infoWithLink(notification: *Notification, title: []const u8, message: []const u8, link_text: []const u8, url: []const u8) !void {
        const actions = [_]NotificationAction{
            NotificationAction{
                .label = link_text,
                .action = .{ .open_url = url },
            },
        };
        try notification.showWithActions(.info, title, message, &actions);
    }
};

test "notification types" {
    try std.testing.expectEqualStrings("ℹ️", NotificationType.info.icon());
    try std.testing.expectEqualStrings("[INFO]", NotificationType.info.asciiIcon());

    const info_color = NotificationType.info.color();
    try std.testing.expect(info_color == .rgb);
}

test "enhanced notification initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bridge_config = terminal_bridge.Config{};
    var bridge = try terminal_bridge.TerminalBridge.init(allocator, bridge_config);
    defer bridge.deinit();

    const notification_config = NotificationConfig{};
    var notification = Notification.init(&bridge, notification_config);

    const stats = notification.getStats();
    try std.testing.expect(stats.total_count == 0);
}

test "sound notification functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bridge_config = terminal_bridge.Config{};
    var bridge = try terminal_bridge.TerminalBridge.init(allocator, bridge_config);
    defer bridge.deinit();

    // Test with sound enabled
    const notification_config = NotificationConfig{ .enable_sound = true };
    var notification = Notification.init(&bridge, notification_config);

    // Test that sound notifications don't error (we can't easily test the actual bell sound)
    try notification.playNotificationSound(.info);
    try notification.playNotificationSound(.success);
    try notification.playNotificationSound(.warning);
    try notification.playNotificationSound(.@"error");
    try notification.playNotificationSound(.critical);

    // Test with sound disabled
    const silent_config = NotificationConfig{ .enable_sound = false };
    var silent_notification = Notification.init(&bridge, silent_config);

    // Should not play any sound
    try silent_notification.playNotificationSound(.info);
}

//! CLI Notification System
//!
//! This module consolidates all CLI notification functionality into a single,
//! cohesive system that extends the notification base with CLI-specific features:
//! - System notifications when supported (OSC 9)
//! - Rich in-terminal notifications with proper styling
//! - Hyperlink support for clickable actions
//! - Clipboard integration for easy copying
//! - Progressive enhancement based on terminal capabilities
//! - CLI-specific sound patterns and actions
//! - Operation notifiers for long-running tasks
//! - Multiple display styles (minimal, detailed, system)

const std = @import("std");
const shared = @import("../mod.zig");
const components = shared.components;
const term_shared = @import("term_shared");
const unified = term_shared.unified;
const terminal_bridge = @import("./core/terminal_bridge.zig");
const components_shared = @import("./components/mod.zig");
const notification = components_shared.notification;
const presenters = @import("presenters/mod.zig");

// Re-export base types for convenience
pub const NotificationType = notification.NotificationType;
pub const NotificationConfig = notification.NotificationConfig;
pub const NotificationAction = notification.NotificationAction;
pub const BaseNotification = notification.BaseNotification;
pub const NotificationUtils = notification.NotificationUtils;
pub const ColorScheme = notification.ColorScheme;
pub const SoundPattern = notification.SoundPattern;

/// Main CLI notification manager combining all CLI notification features
pub const NotificationManager = struct {
    const Self = @This();

    bridge: *terminal_bridge.TerminalBridge,
    config: NotificationConfig,

    // State tracking
    notification_count: u64 = 0,
    last_notification_time: i64 = 0,

    // Active notifications for progress tracking
    active_notifications: std.ArrayList(BaseNotification),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, bridge: *terminal_bridge.TerminalBridge, config: NotificationConfig) !Self {
        return Self{
            .bridge = bridge,
            .config = config,
            .active_notifications = std.ArrayList(BaseNotification).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.active_notifications.items) |*notif| {
            self.allocator.free(notif.title);
            self.allocator.free(notif.message);
        }
        self.active_notifications.deinit();
    }

    /// Show a notification with just a message
    pub fn show(self: *Self, notification_type: NotificationType, title: []const u8, message: []const u8) !void {
        try self.showWithActions(notification_type, title, message, &[_]NotificationAction{});
    }

    /// Show a notification with clickable actions
    pub fn showWithActions(self: *Self, notification_type: NotificationType, title: []const u8, message: []const u8, actions: []const NotificationAction) !void {
        self.notification_count += 1;
        self.last_notification_time = std.time.milliTimestamp();

        const strategy = self.bridge.getRenderStrategy();
        const caps = self.bridge.getCapabilities();

        // Create base notification
        const base_notification = BaseNotification.init(title, message, notification_type, self.config);

        // Try system notification first if enabled and supported
        if (self.config.enableSystemNotifications and caps.supportsNotifyOsc9) {
            try notification.SystemNotification.sendFromBase(
                self.bridge.writer(),
                self.bridge.allocator,
                caps,
                &base_notification,
            );
        }

        // Always render in-terminal notification as well
        try self.renderInTerminal(&base_notification, actions, strategy);

        // Add sound notification if enabled
        if (self.config.enableSound) {
            try self.playNotificationSound(notification_type);
        }
    }

    /// Show a progress notification
    pub fn showProgress(self: *Self, title: []const u8, message: []const u8, progress_value: f32) !void {
        self.notification_count += 1;
        self.last_notification_time = std.time.milliTimestamp();

        const strategy = self.bridge.getRenderStrategy();
        const caps = self.bridge.getCapabilities();

        // Create progress notification
        const base_notif = BaseNotification.initProgress(title, message, progress_value, self.config);

        // Try system notification first if enabled and supported
        if (self.config.enableSystemNotifications and caps.supportsNotifyOsc9) {
            try notification.SystemNotification.sendFromBase(
                self.bridge.writer(),
                self.bridge.allocator,
                caps,
                &base_notif,
            );
        }

        // Render progress notification
        try self.renderProgressNotification(&base_notif, strategy);
    }

    /// Update progress for an existing notification
    pub fn updateProgress(self: *Self, title: []const u8, message: []const u8, progress_value: f32) !void {
        // For now, just show a new progress notification
        // In a more sophisticated implementation, we'd track notifications by ID
        try self.showProgress(title, message, progress_value);
    }

    /// Show notification with specific display style
    pub fn showWithStyle(self: *Self, notification_type: NotificationType, title: []const u8, message: ?[]const u8, style: DisplayStyle) !void {
        switch (style) {
            .system => try self.showSystem(notification_type, title, message),
            .detailed => try self.showDetailed(notification_type, title, message),
            .minimal => try self.showMinimal(notification_type, title, message),
        }
    }

    fn showSystem(self: *Self, notification_type: NotificationType, title: []const u8, message: ?[]const u8) !void {
        const caps = self.bridge.getCapabilities();
        if (caps.supportsNotifyOsc9) {
            const combined_message = if (message) |msg|
                try std.fmt.allocPrint(self.bridge.allocator, "{s}: {s}", .{ title, msg })
            else
                try self.bridge.allocator.dupe(u8, title);
            defer self.bridge.allocator.free(combined_message);

            try notification.SystemNotification.send(
                self.bridge.writer(),
                self.bridge.allocator,
                caps,
                title,
                combined_message,
            );
        } else {
            // Fallback to detailed display
            try self.showDetailed(notification_type, title, message);
        }
    }

    fn showDetailed(self: *Self, notification_type: NotificationType, title: []const u8, message: ?[]const u8) !void {
        const caps = self.bridge.getCapabilities();

        // Get style based on terminal capabilities
        const elements = self.getStyledElements(notification_type, caps.supportsTruecolor);
        const icon = elements.icon;
        const style = elements.style;

        try self.bridge.print("\n", null);

        // Top border
        try self.renderBorder(.top, title, message, style, caps);

        // Title line
        try self.renderTitleLine(icon, title, style, caps);

        // Message line if provided
        if (message) |msg| {
            try self.renderMessageLine(msg, style, caps);
        }

        // Bottom border
        try self.renderBorder(.bottom, title, message, style, caps);

        try self.bridge.print("\n", null);
    }

    fn showMinimal(self: *Self, notification_type: NotificationType, title: []const u8, message: ?[]const u8) !void {
        const caps = self.bridge.getCapabilities();
        const elements = self.getStyledElements(notification_type, caps.supportsTruecolor);
        const icon = elements.icon;
        const style = elements.style;

        try self.bridge.print("\n", null);
        try style.apply(self.bridge.writer(), caps);
        try self.bridge.print(icon, null);
        try self.bridge.print(" ", null);
        try self.bridge.print(title, null);

        if (message) |msg| {
            try self.bridge.print(": ", null);
            try self.bridge.print(msg, null);
        }

        try unified.Style.reset(self.bridge.writer(), caps);
        try self.bridge.print("\n", null);
    }

    /// Show progress notification with percentage
    pub fn showProgressWithPercentage(self: *Self, title: []const u8, progress: f32) !void {
        const percentage = @as(u32, @intFromFloat(progress * 100));
        const message = try std.fmt.allocPrint(self.bridge.allocator, "{d}% complete", .{percentage});
        defer self.bridge.allocator.free(message);

        try self.show(.progress, title, message);
    }

    /// Render the notification in the terminal with adaptive styling
    fn renderInTerminal(self: *Self, base_notif: *const BaseNotification, actions: []const NotificationAction, strategy: terminal_bridge.RenderStrategy) !void {
        // Create notification box with adaptive styling
        const box_style = self.createBoxStyle(base_notif.notification_type, strategy);

        // Calculate dimensions
        const content_width = @min(self.config.maxWidth - 4, @max(base_notif.title.len, base_notif.message.len) + 4);
        const total_width = content_width + 4; // Account for borders

        // Save cursor position and render notification
        var render_ctx = try self.bridge.createRenderContext();
        defer render_ctx.deinit();

        try self.renderNotificationBox(base_notif, actions, box_style, content_width, total_width, strategy);
    }

    /// Render a progress notification with progress bar
    fn renderProgressNotification(self: *Self, base_notif: *const BaseNotification, strategy: terminal_bridge.RenderStrategy) !void {
        const use_unicode = strategy.supportsColor();

        // Get progress information
        const progress = base_notif.progress orelse 0.0;
        const percentage = try base_notif.getProgressPercentage(self.bridge.allocator);
        defer self.bridge.allocator.free(percentage);

        // Create progress bar
        const bar_width = 30;
        const progress_bar = try NotificationUtils.formatProgressBar(
            self.bridge.allocator,
            progress,
            bar_width,
            use_unicode,
        );
        defer self.bridge.allocator.free(progress_bar);

        // Render progress notification
        const icon = if (use_unicode) base_notif.notification_type.icon() else base_notif.notification_type.asciiIcon();
        const color_style = unified.Style{ .fg_color = base_notif.notification_type.color() };

        try self.bridge.print("\n", null);
        try self.bridge.print(icon, color_style);
        try self.bridge.print(" ", null);
        try self.bridge.print(base_notif.title, unified.Style{ .bold = true });
        try self.bridge.print(" [", null);
        try self.bridge.print(progress_bar, color_style);
        try self.bridge.print("] ", null);
        try self.bridge.print(percentage, null);
        try self.bridge.print(" - ", null);
        try self.bridge.print(base_notif.message, null);
        try self.bridge.print("\n", null);
    }

    /// Create appropriate box styling based on notification type and terminal capabilities
    fn createBoxStyle(self: *Self, notification_type: NotificationType, strategy: terminal_bridge.RenderStrategy) BoxStyle {
        _ = self;

        const color_scheme = notification.ColorScheme.getStandard(notification_type);

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
    fn renderNotificationBox(self: *Self, base_notif: *const BaseNotification, actions: []const NotificationAction, box_style: BoxStyle, content_width: u32, total_width: u32, strategy: terminal_bridge.RenderStrategy) !void {
        // Top border
        try self.renderBorderLine(.top, box_style, total_width);

        // Title line with icon
        try self.renderTitleLine(base_notif.notification_type, base_notif.title, box_style, content_width, strategy);

        // Message line(s) - handle word wrapping
        try self.renderMessageLines(base_notif.message, box_style, content_width);

        // Timestamp if enabled
        if (self.config.showTimestamp) {
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

        // Word wrapping (can be improved)
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
        if (!self.config.enableSound) return;

        // Use system bell with different patterns for different notification types
        try self.playSystemBell(notification_type);
    }

    /// Play system bell with notification-type-specific patterns
    fn playSystemBell(self: *Self, notification_type: NotificationType) !void {
        const writer = self.bridge.writer();
        const pattern = SoundPattern.getPattern(notification_type);

        try SoundPattern.playPattern(writer, pattern.pattern, pattern.duration_ms);
    }

    /// Get notification statistics
    pub fn getStats(self: *Self) NotificationStats {
        return NotificationStats{
            .total_count = self.notification_count,
            .last_notification_time = self.last_notification_time,
        };
    }

    // Helper methods for styled elements
    fn getStyledElements(self: *Self, notification_type: NotificationType, use_colors: bool) StyleElements {
        _ = self;

        const style = if (use_colors) switch (notification_type) {
            .info => unified.Style{ .fg_color = .{ .ansi = 12 } }, // Bright Blue
            .success => unified.Style{ .fg_color = .{ .ansi = 10 } }, // Bright Green
            .warning => unified.Style{ .fg_color = .{ .ansi = 11 } }, // Bright Yellow
            .@"error" => unified.Style{ .fg_color = .{ .ansi = 9 } }, // Bright Red
            .debug => unified.Style{ .fg_color = .{ .ansi = 13 } }, // Bright Magenta
            .critical => unified.Style{ .fg_color = .{ .ansi = 9 } }, // Bright Red
            .progress => unified.Style{ .fg_color = .{ .ansi = 14 } }, // Bright Cyan
        } else unified.Style{};

        // Use base notification system's icons
        const icon = if (use_colors)
            notification_type.icon()
        else
            notification_type.asciiIcon();

        return StyleElements{ .icon = icon, .style = style };
    }

    fn renderBorder(self: *Self, border_type: BorderType, title: []const u8, message: ?[]const u8, style: unified.Style, caps: term_shared.TermCaps) !void {
        const border_chars = if (caps.supportsTruecolor) switch (border_type) {
            .top => .{ "┌─", "─┐" },
            .middle => .{ "├─", "─┤" },
            .bottom => .{ "└─", "─┘" },
        } else switch (border_type) {
            .top => .{ "+-", "-+" },
            .middle => .{ "+-", "-+" },
            .bottom => .{ "+-", "-+" },
        };

        const max_len = if (message) |msg| @max(title.len, msg.len) else title.len;
        const width = @max(max_len + 4, 20);

        try style.apply(self.bridge.writer(), caps);
        try self.bridge.print(border_chars[0], null);
        for (0..width - 4) |_| {
            try self.bridge.print("─", null);
        }
        try self.bridge.print(border_chars[1], null);
        try unified.Style.reset(self.bridge.writer(), caps);
        try self.bridge.print("\n", null);
    }

    fn renderTitleLineStyled(self: *Self, icon: []const u8, title: []const u8, style: unified.Style, caps: term_shared.TermCaps) !void {
        try style.apply(self.bridge.writer(), caps);
        try self.bridge.print("│ ", null);
        try self.bridge.print(icon, null);
        try self.bridge.print(" ", null);
        try self.bridge.print(title, unified.Style{ .bold = true });
        try unified.Style.reset(self.bridge.writer(), caps);
        try self.bridge.print(" │\n", null);
    }

    fn renderMessageLineStyled(self: *Self, message: []const u8, style: unified.Style, caps: term_shared.TermCaps) !void {
        try style.apply(self.bridge.writer(), caps);
        try self.bridge.print("│   ", null);
        try self.bridge.print(message, null);
        try unified.Style.reset(self.bridge.writer(), caps);
        try self.bridge.print(" │\n", null);
    }
};

/// Thin wrapper: display a base notification via CLI presenter
pub fn displaySimple(
    allocator: std.mem.Allocator,
    n: *const notification.BaseNotification,
    use_unicode: bool,
) !void {
    // Map BaseNotification to shared Notification structure if types are aligned
    // The BaseNotification is compatible with components/notification.Notification fields
    // We cast through pointer to avoid copy; safe if layout matches. Safer: reconstruct.
    const SharedNotification = shared.components.Notification;

    var reconstructed = SharedNotification{
        .title = n.title,
        .message = n.message,
        .notification_type = n.notification_type,
        .timestamp = n.timestamp,
        .config = .{
            .enableSystemNotifications = n.config.enableSystemNotifications,
            .enableSound = n.config.enableSound,
            .autoDismissMs = n.config.autoDismissMs,
            .showTimestamp = n.config.showTimestamp,
            .showIcons = n.config.showIcons,
            .maxWidth = n.config.maxWidth,
            .padding = n.config.padding,
            .enableClipboardActions = n.config.enableClipboardActions,
            .enableHyperlinks = n.config.enableHyperlinks,
        },
        .actions = n.actions,
        .priority = .normal,
        .persistent = n.persistent,
        .progress = n.progress,
    };

    try presenters.notification.display(allocator, &reconstructed, use_unicode);
}

/// Thin wrapper: display progress using CLI presenter
pub fn displayProgressSimple(
    data: *const shared.components.ProgressData,
    width: u32,
) !void {
    try presenters.progress.render(data, width);
}

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

/// Display style options
pub const DisplayStyle = enum {
    minimal, // Just icon and text
    detailed, // Full formatting with borders
    system, // Use system notifications when available
};

/// Style elements for notifications
const StyleElements = struct {
    icon: []const u8,
    style: unified.Style,
};

/// Enhanced notification handler with multiple delivery methods
pub const NotificationHandler = struct {
    allocator: std.mem.Allocator,
    caps: term_shared.caps.TermCaps,
    activeNotifications: std.ArrayList(BaseNotification),
    notificationCounter: u64,
    enableDesktopNotifications: bool,
    enableInlineNotifications: bool,
    enableSound: bool,
    writer: ?*std.Io.Writer,

    pub fn init(allocator: std.mem.Allocator) NotificationHandler {
        return NotificationHandler{
            .allocator = allocator,
            .caps = term_shared.caps.getTermCaps(),
            .activeNotifications = std.ArrayList(BaseNotification).init(allocator),
            .notificationCounter = 0,
            .enableDesktopNotifications = true,
            .enableInlineNotifications = true,
            .enableSound = false,
            .writer = null,
        };
    }

    pub fn deinit(self: *NotificationHandler) void {
        for (self.activeNotifications.items) |*notif| {
            self.allocator.free(notif.title);
            self.allocator.free(notif.message);
        }
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
        const notif = BaseNotification.init(
            try self.allocator.dupe(u8, title),
            try self.allocator.dupe(u8, message),
            notification_type,
            .{},
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
        const progress_notification = BaseNotification.init(
            try self.allocator.dupe(u8, title),
            try self.allocator.dupe(u8, message),
            .progress,
            .{},
        ).withProgress(progress).asPersistent();

        // Update or add progress notification
        var found = false;
        for (self.activeNotifications.items, 0..) |*existing, i| {
            if (existing.notification_type == .progress and std.mem.eql(u8, existing.title, title)) {
                self.activeNotifications.items[i] = progress_notification;
                found = true;
                break;
            }
        }

        if (!found) {
            try self.activeNotifications.append(progress_notification);
        }

        // Show progress notification
        try self.showProgressNotification(progress_notification);

        return notification.id;
    }

    /// Send desktop notification using OSC 9
    fn sendDesktopNotification(self: *NotificationHandler, notif: BaseNotification) !void {
        if (self.writer == null) return error.NoWriter;

        const formatted_message = try std.fmt.allocPrint(
            self.allocator,
            "{s}: {s}",
            .{ notif.title, notif.message },
        );
        defer self.allocator.free(formatted_message);

        try term_shared.ansi.notification.writeNotification(
            self.writer.?,
            self.allocator,
            self.caps,
            formatted_message,
        );
    }

    /// Show inline terminal notification with rich formatting
    fn showInlineNotification(self: *NotificationHandler, notif: BaseNotification) !void {
        if (self.writer == null) return;
        const writer = self.writer.?;

        // Save cursor position and create notification bar
        try writer.writeAll("\n");

        // Notification type indicator with colors
        switch (notif.notification_type) {
            .info => {
                if (self.caps.supportsTrueColor()) {
                    try term_shared.ansi.color.setForegroundRgb(writer.*, self.caps, 100, 149, 237);
                } else {
                    try term_shared.ansi.color.setForeground256(writer.*, self.caps, 12);
                }
                try writer.writeAll("ℹ ");
            },
            .success => {
                if (self.caps.supportsTrueColor()) {
                    try term_shared.ansi.color.setForegroundRgb(writer.*, self.caps, 50, 205, 50);
                } else {
                    try term_shared.ansi.color.setForeground256(writer.*, self.caps, 10);
                }
                try writer.writeAll("✓ ");
            },
            .warning => {
                if (self.caps.supportsTrueColor()) {
                    try term_shared.ansi.color.setForegroundRgb(writer.*, self.caps, 255, 165, 0);
                } else {
                    try term_shared.ansi.color.setForeground256(writer.*, self.caps, 11);
                }
                try writer.writeAll("⚠ ");
            },
            .@"error" => {
                if (self.caps.supportsTrueColor()) {
                    try term_shared.ansi.color.setForegroundRgb(writer.*, self.caps, 255, 69, 0);
                } else {
                    try term_shared.ansi.color.setForeground256(writer.*, self.caps, 9);
                }
                try writer.writeAll("✗ ");
            },
            .progress => {
                if (self.caps.supportsTrueColor()) {
                    try term_shared.ansi.color.setForegroundRgb(writer.*, self.caps, 255, 215, 0);
                } else {
                    try term_shared.ansi.color.setForeground256(writer.*, self.caps, 11);
                }
                try writer.writeAll("⧖ ");
            },
            .debug => {
                if (self.caps.supportsTrueColor()) {
                    try term_shared.ansi.color.setForegroundRgb(writer.*, self.caps, 155, 89, 182);
                } else {
                    try term_shared.ansi.color.setForeground256(writer.*, self.caps, 13);
                }
                try writer.writeAll("🐛 ");
            },
            .critical => {
                if (self.caps.supportsTrueColor()) {
                    try term_shared.ansi.color.setForegroundRgb(writer.*, self.caps, 192, 57, 43);
                } else {
                    try term_shared.ansi.color.setForeground256(writer.*, self.caps, 9);
                }
                try writer.writeAll("🚨 ");
            },
        }

        // Title
        if (self.caps.supportsTrueColor()) {
            try term_shared.ansi.color.setForegroundRgb(writer.*, self.caps, 255, 255, 255);
        } else {
            try term_shared.ansi.color.setForeground256(writer.*, self.caps, 15);
        }
        try writer.writeAll(notif.title);

        // Message
        if (self.caps.supportsTrueColor()) {
            try term_shared.ansi.color.setForegroundRgb(writer.*, self.caps, 200, 200, 200);
        } else {
            try term_shared.ansi.color.setForeground256(writer.*, self.caps, 7);
        }
        try writer.print(": {s}", .{notif.message});

        try term_shared.ansi.color.resetStyle(writer.*, self.caps);
        try writer.writeAll("\n");
    }

    /// Show progress notification with progress bar
    fn showProgressNotification(self: *NotificationHandler, notif: BaseNotification) !void {
        if (self.writer == null or notif.progress == null) return;
        const writer = self.writer.?;
        const progress = notif.progress.?;

        try writer.writeAll("\n");

        // Progress type indicator
        if (self.caps.supportsTrueColor()) {
            try term_shared.ansi.color.setForegroundRgb(writer.*, self.caps, 255, 215, 0);
        } else {
            try term_shared.ansi.color.setForeground256(writer.*, self.caps, 11);
        }
        try writer.writeAll("⧖ ");

        // Title
        if (self.caps.supportsTrueColor()) {
            try term_shared.ansi.color.setForegroundRgb(writer.*, self.caps, 255, 255, 255);
        } else {
            try term_shared.ansi.color.setForeground256(writer.*, self.caps, 15);
        }
        try writer.writeAll(notif.title);

        // Progress bar
        const barWidth = 30;
        const filledWidth = @as(usize, @intFromFloat(progress * @as(f32, @floatFromInt(barWidth))));

        try writer.writeAll(" [");

        // Filled portion
        if (self.caps.supportsTrueColor()) {
            try term_shared.ansi.color.setForegroundRgb(writer.*, self.caps, 50, 205, 50);
        } else {
            try term_shared.ansi.color.setForeground256(writer.*, self.caps, 10);
        }
        for (0..filledWidth) |_| {
            try writer.writeAll("█");
        }

        // Empty portion
        if (self.caps.supportsTrueColor()) {
            try term_shared.ansi.color.setForegroundRgb(writer.*, self.caps, 100, 100, 100);
        } else {
            try term_shared.ansi.color.setForeground256(writer.*, self.caps, 8);
        }
        for (filledWidth..barWidth) |_| {
            try writer.writeAll("░");
        }

        try term_shared.ansi.color.resetStyle(writer.*, self.caps);
        try writer.print("] {d:.1}%", .{progress * 100.0});

        // Message
        if (self.caps.supportsTrueColor()) {
            try term_shared.ansi.color.setForegroundRgb(writer.*, self.caps, 200, 200, 200);
        } else {
            try term_shared.ansi.color.setForeground256(writer.*, self.caps, 7);
        }
        try writer.print(" - {s}", .{notif.message});

        try term_shared.ansi.color.resetStyle(writer.*, self.caps);
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
                const success_notification = BaseNotification.init(
                    try self.allocator.dupe(u8, notif.title),
                    try self.allocator.dupe(u8, final_message),
                    .success,
                    .{},
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
        for (self.activeNotifications.items, 0..) |notif, i| {
            if (notif.id == notificationId) {
                _ = self.activeNotifications.swapRemove(i);
                break;
            }
        }
    }

    /// Clear all notifications
    pub fn clearAll(self: *NotificationHandler) void {
        for (self.activeNotifications.items) |*notif| {
            self.allocator.free(notif.title);
            self.allocator.free(notif.message);
        }
        self.activeNotifications.clearRetainingCapacity();
    }

    /// Get all active notifications
    pub fn getActiveNotifications(self: *NotificationHandler) []const BaseNotification {
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
        return OperationNotifier{
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
            _ = try self.manager.notify(.@"error", self.operationName, errorMessage);
            self.notificationId = null;
        }
    }
};

/// Convenient preset notification functions
pub const NotificationPresets = struct {
    /// Show a success notification with copy action
    pub fn success(notif: *NotificationManager, title: []const u8, message: []const u8, copy_text: ?[]const u8) !void {
        if (copy_text) |text| {
            const actions = [_]NotificationAction{
                .{
                    .label = "Copy Result",
                    .action = .{ .copy_text = text },
                },
            };
            try notif.showWithActions(.success, title, message, &actions);
        } else {
            try notif.show(.success, title, message);
        }
    }

    /// Show an error notification with support link
    pub fn showError(notif: *NotificationManager, title: []const u8, message: []const u8, support_url: ?[]const u8) !void {
        if (support_url) |url| {
            const actions = [_]NotificationAction{
                .{
                    .label = "Get Help",
                    .action = .{ .open_url = url },
                },
            };
            try notif.showWithActions(.@"error", title, message, &actions);
        } else {
            try notif.show(.@"error", title, message);
        }
    }

    /// Show an info notification with a clickable link
    pub fn infoWithLink(notif: *NotificationManager, title: []const u8, message: []const u8, link_text: []const u8, url: []const u8) !void {
        const actions = [_]NotificationAction{
            .{
                .label = link_text,
                .action = .{ .open_url = url },
            },
        };
        try notif.showWithActions(.info, title, message, &actions);
    }

    /// Show a progress notification
    pub fn progress(notif: *NotificationManager, title: []const u8, message: []const u8, progress_value: f32) !void {
        try notif.showProgress(title, message, progress_value);
    }

    /// Update progress for an existing notification
    pub fn updateProgress(notif: *NotificationManager, title: []const u8, message: []const u8, progress_value: f32) !void {
        try notif.updateProgress(title, message, progress_value);
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

        _ = try manager.notify(.@"error", "Error", "Something went wrong!");
    }
};

test "notification manager initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bridge_config = terminal_bridge.Config{};
    var bridge = try terminal_bridge.TerminalBridge.init(allocator, bridge_config);
    defer bridge.deinit();

    const notification_config = NotificationConfig{};
    var manager = try NotificationManager.init(allocator, &bridge, notification_config);
    defer manager.deinit();

    const stats = manager.getStats();
    try std.testing.expect(stats.total_count == 0);
}

test "notification handler initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var handler = NotificationHandler.init(allocator);
    defer handler.deinit();

    try std.testing.expect(handler.activeNotifications.items.len == 0);
}

//! TUI Notification System
//!
//! This module consolidates all TUI notification functionality into a single,
//! cohesive system that extends the notification base with TUI-specific features:
//! - System notifications (OSC 9) when supported
//! - Rich in-terminal notifications with graphics/colors
//! - Proper positioning and animation where supported
//! - TUI-specific animations and positioning
//! - Notification controller for managing multiple notifications
//! - Progressive enhancement based on terminal capabilities

const std = @import("std");
const renderer_mod = @import("./core/renderer.zig");
const bounds_mod = @import("./core/bounds.zig");
const ui = @import("../ui.zig");
const Notification = ui.Widgets.Notification;

const Renderer = renderer_mod.Renderer;
const Render = renderer_mod.Render;
const Style = renderer_mod.Style;
const BoxStyle = renderer_mod.BoxStyle;
const Point = renderer_mod.Point;
const Bounds = renderer_mod.Bounds;
const NotificationLevel = renderer_mod.NotificationLevel;

// Re-export base types for convenience
pub const NotificationType = Notification.Type;
pub const NotificationConfig = Notification.Config;
pub const NotificationAction = Notification.Action;

/// TUI Notification that extends the base system with positioning and animation
pub const NotificationWidget = struct {
    const Self = @This();

    // Base notification widget from UI
    base: *Notification,

    // TUI-specific options
    options: Options,
    is_displayed: bool,

    pub const Options = struct {
        position: Position = .top_right,
        duration_ms: ?u32 = 3000, // Auto-hide after 3 seconds
        show_timestamp: bool = false,
        persistent: bool = false, // Don't auto-hide
        border: bool = true,
        width: ?u32 = null, // Auto-width if null
        padding: Padding = .{ .top = 1, .right = 2, .bottom = 1, .left = 2 },
        use_system_notification: bool = true, // Try OSC 9 first
        show_in_terminal: bool = true, // Show in-terminal notification
        animation: Animation = .slide_in, // Animation style
        priority: Priority = .normal, // Notification priority

        pub const Position = enum {
            top_left,
            top_center,
            top_right,
            center_left,
            center,
            center_right,
            bottom_left,
            bottom_center,
            bottom_right,
        };

        pub const Animation = enum {
            none,
            slide_in,
            fade_in,
            bounce,
        };

        pub const Priority = enum {
            low,
            normal,
            high,
            critical,
        };

        pub const Padding = struct {
            top: u32 = 0,
            right: u32 = 0,
            bottom: u32 = 0,
            left: u32 = 0,
        };
    };

    pub fn init(
        title: []const u8,
        message: []const u8,
        notification_type: NotificationType,
        config: NotificationConfig,
        options: Options,
    ) Self {
        return Self{
            .base = BaseNotification.init(title, message, notification_type, config),
            .options = options,
            .is_displayed = false,
        };
    }

    pub fn show(self: *Self, renderer: *Renderer) !void {
        const caps = renderer.getCapabilities();

        // Try system notification first if enabled and supported
        if (self.options.use_system_notification and caps.supportsNotifyOsc9) {
            try notification.SystemNotification.sendFromBase(
                renderer.writer(),
                renderer.allocator,
                caps,
                &self.base,
            );
        }

        // Show in-terminal notification if enabled
        if (self.options.show_in_terminal) {
            if (self.base.isProgress()) {
                try self.showProgressNotification(renderer);
            } else {
                try self.showTerminalNotification(renderer);
            }
        }

        self.is_displayed = true;
    }

    pub fn hide(self: *Self, renderer: *Renderer) !void {
        if (!self.is_displayed) return;

        // Clear the terminal notification area
        try self.clearTerminalNotification(renderer);
        self.is_displayed = false;
    }

    pub fn isExpired(self: *Self) bool {
        if (self.options.persistent) return false;
        if (self.options.duration_ms == null) return false;

        const now = std.time.timestamp();
        const age_ms = @as(u32, @intCast(now - self.base.timestamp)) * 1000;
        return age_ms > self.options.duration_ms.?;
    }

    fn getBounds(self: *Self, terminal_size: bounds_mod.TerminalSize) Bounds {
        // Calculate content dimensions
        const title_len = std.unicode.utf8CountCodepoints(self.base.title) catch self.base.title.len;
        const message_len = std.unicode.utf8CountCodepoints(self.base.message) catch self.base.message.len;
        const max_content_width = @max(title_len, message_len);

        // Account for icon, spacing, and padding
        const icon_width: u32 = 2; // Icon + space
        const content_width = @as(u32, @intCast(max_content_width)) + icon_width;
        const total_padding = self.options.padding.left + self.options.padding.right;
        const border_width: u32 = if (self.options.border) 2 else 0;

        const width = self.options.width orelse @min(content_width + total_padding + border_width, @max(20, terminal_size.width - 4));

        // Calculate height based on content
        var height: u32 = if (self.options.border) 2 else 0; // Top and bottom borders
        height += self.options.padding.top + self.options.padding.bottom;
        height += 1; // Title line

        // Add message lines (simple word wrapping approximation)
        const available_width = width - total_padding - border_width - icon_width;
        const message_lines = (@as(u32, @intCast(message_len)) + available_width - 1) / available_width;
        height += message_lines;

        if (self.options.show_timestamp) {
            height += 1;
        }

        // Calculate position based on terminal size and position setting
        const x: u32 = switch (self.options.position) {
            .top_left, .center_left, .bottom_left => 1,
            .top_center, .center, .bottom_center => (terminal_size.width - width) / 2,
            .top_right, .center_right, .bottom_right => terminal_size.width - width - 1,
        };

        const y: u32 = switch (self.options.position) {
            .top_left, .top_center, .top_right => 1,
            .center_left, .center, .center_right => (terminal_size.height - height) / 2,
            .bottom_left, .bottom_center, .bottom_right => terminal_size.height - height - 1,
        };

        return Bounds{
            .x = @as(i32, @intCast(x)),
            .y = @as(i32, @intCast(y)),
            .width = width,
            .height = height,
        };
    }

    fn showTerminalNotification(self: *Self, renderer: *Renderer) !void {
        const terminal_size = bounds_mod.getTerminalSize();
        const notification_bounds = self.getBounds(terminal_size);

        // Create render context
        const ctx = Render{
            .bounds = notification_bounds,
            .style = self.getNotificationStyle(renderer.getCapabilities()),
            .zIndex = self.getPriorityZIndex(),
        };

        // Apply animation if supported
        if (self.options.animation != .none) {
            try self.animateIn(renderer, ctx);
        } else {
            try self.renderNotification(renderer, ctx);
        }
    }

    fn clearTerminalNotification(self: *Self, renderer: *Renderer) !void {
        const terminal_size = bounds_mod.getTerminalSize();
        const notification_bounds = self.getBounds(terminal_size);

        // Clear the notification area
        try renderer.clear(notification_bounds);
    }

    fn showProgressNotification(self: *Self, renderer: *Renderer) !void {
        const terminal_size = bounds_mod.getTerminalSize();
        const notification_bounds = self.getBounds(terminal_size);

        // Create render context
        const ctx = Render{
            .bounds = notification_bounds,
            .style = self.getNotificationStyle(renderer.getCapabilities()),
            .zIndex = self.getPriorityZIndex(),
        };

        // Apply animation if supported
        if (self.options.animation != .none) {
            try self.animateIn(renderer, ctx);
        } else {
            try self.renderProgressNotification(renderer, ctx);
        }
    }

    fn renderProgressNotification(self: *Self, renderer: *Renderer, ctx: Render) !void {
        const caps = renderer.getCapabilities();
        const progress = self.base.progress orelse 0.0;

        // Create box style for the notification
        const box_style = BoxStyle{
            .border = if (self.options.border) BoxStyle.BorderStyle{
                .style = if (caps.supportsTruecolor) .rounded else .single,
                .color = self.getLevelColor(caps),
            } else null,
            .background = self.getBackgroundColor(caps),
            .padding = .{
                .top = self.options.padding.top,
                .right = self.options.padding.right,
                .bottom = self.options.padding.bottom,
                .left = self.options.padding.left,
            },
        };

        // Format progress notification content
        var arena = std.heap.ArenaAllocator.init(renderer.allocator);
        defer arena.deinit();
        const temp_allocator = arena.allocator();

        const icon = self.getLevelIcon();
        const progress_percentage = try self.base.getProgressPercentage(temp_allocator);
        defer temp_allocator.free(progress_percentage);

        // Create progress bar
        const bar_width = 20;
        const progress_bar = try notification.NotificationUtils.formatProgressBar(
            temp_allocator,
            progress,
            bar_width,
            caps.supportsTruecolor,
        );
        defer temp_allocator.free(progress_bar);

        const content = try std.fmt.allocPrint(temp_allocator, "{s} {s}\n{s} {s}\n{s}", .{
            icon,
            self.base.title,
            progress_bar,
            progress_percentage,
            self.base.message,
        });
        defer temp_allocator.free(content);

        // Render the notification box with content
        try renderer.drawTextBox(ctx, content, box_style);
    }

    fn renderNotification(self: *Self, renderer: *Renderer, ctx: Render) !void {
        const caps = renderer.getCapabilities();

        // Create box style for the notification
        const box_style = BoxStyle{
            .border = if (self.options.border) BoxStyle.BorderStyle{
                .style = if (caps.supportsTruecolor) .rounded else .single,
                .color = self.getLevelColor(caps),
            } else null,
            .background = self.getBackgroundColor(caps),
            .padding = .{
                .top = self.options.padding.top,
                .right = self.options.padding.right,
                .bottom = self.options.padding.bottom,
                .left = self.options.padding.left,
            },
        };

        // Format notification content
        var arena = std.heap.ArenaAllocator.init(renderer.allocator);
        defer arena.deinit();
        const temp_allocator = arena.allocator();

        const icon = self.getLevelIcon();
        const content = try self.formatNotificationContent(temp_allocator, icon);

        // Render the notification box with content
        try renderer.drawTextBox(ctx, content, box_style);
    }

    fn animateIn(self: *Self, renderer: *Renderer, final_ctx: Render) !void {
        const caps = renderer.getCapabilities();

        // Only animate if terminal supports it (has cursor positioning)
        if (!caps.supportsCursorPositionReport) {
            try self.renderNotification(renderer, final_ctx);
            return;
        }

        switch (self.options.animation) {
            .slide_in => {
                // Slide in from the side
                const frames = 5;
                var frame: u32 = 0;
                while (frame < frames) : (frame += 1) {
                    const progress = @as(f32, @floatFromInt(frame)) / @as(f32, @floatFromInt(frames - 1));

                    var animated_ctx = final_ctx;
                    switch (self.options.position) {
                        .top_right, .center_right, .bottom_right => {
                            // Slide from right
                            const offset = @as(i32, @intFromFloat(@as(f32, @floatFromInt(final_ctx.bounds.width)) * (1.0 - progress)));
                            animated_ctx.bounds.x += offset;
                        },
                        .top_left, .center_left, .bottom_left => {
                            // Slide from left
                            const offset = @as(i32, @intFromFloat(@as(f32, @floatFromInt(final_ctx.bounds.width)) * (1.0 - progress)));
                            animated_ctx.bounds.x -= offset;
                        },
                        else => {
                            // Slide from top
                            const offset = @as(i32, @intFromFloat(@as(f32, @floatFromInt(final_ctx.bounds.height)) * (1.0 - progress)));
                            animated_ctx.bounds.y -= offset;
                        },
                    }

                    try renderer.beginFrame();
                    try self.renderNotification(renderer, animated_ctx);
                    try renderer.endFrame();

                    // Small delay between frames
                    std.time.sleep(16 * std.time.ns_per_ms); // ~60 FPS
                }
            },
            .fade_in => {
                // Simple fade by adjusting alpha (not really possible in terminals, so just show/hide quickly)
                try self.renderNotification(renderer, final_ctx);
            },
            .bounce => {
                // Bounce effect with scaling
                const frames = 8;
                var frame: u32 = 0;
                while (frame < frames) : (frame += 1) {
                    const progress = @as(f32, @floatFromInt(frame)) / @as(f32, @floatFromInt(frames - 1));
                    const bounce = @sin(progress * std.math.pi) * 0.2; // Simple sine bounce

                    var animated_ctx = final_ctx;
                    const y_offset = @as(i32, @intFromFloat(bounce * 3.0));
                    animated_ctx.bounds.y -= y_offset;

                    try renderer.beginFrame();
                    try self.renderNotification(renderer, animated_ctx);
                    try renderer.endFrame();

                    std.time.sleep(25 * std.time.ns_per_ms);
                }
            },
            .none => try self.renderNotification(renderer, final_ctx),
        }
    }

    fn formatNotificationContent(self: *Self, allocator: std.mem.Allocator, icon: []const u8) ![]u8 {
        var content = std.ArrayList(u8).init(allocator);
        defer content.deinit();

        // Title line with icon
        try content.appendSlice(icon);
        try content.appendSlice(" ");
        try content.appendSlice(self.base.title);
        try content.appendSlice("\n");

        // Message (with simple word wrapping if needed)
        try content.appendSlice(self.base.message);

        // Timestamp if requested
        if (self.options.show_timestamp) {
            try content.appendSlice("\n");
            const timestamp_str = try std.fmt.allocPrint(allocator, "{}s ago", .{std.time.timestamp() - self.base.timestamp});
            try content.appendSlice(timestamp_str);
        }

        return content.toOwnedSlice();
    }

    fn getNotificationStyle(self: *Self, caps: renderer_mod.TermCaps) Style {
        return Style{
            .fg_color = self.getLevelColor(caps),
            .bold = self.options.priority == .high or self.options.priority == .critical,
        };
    }

    fn getLevelIcon(self: *Self) []const u8 {
        return self.base.notification_type.icon();
    }

    fn getLevelColor(self: *Self, caps: renderer_mod.TermCaps) Style.Color {
        const color = self.base.notification_type.color();
        return if (caps.supportsTruecolor) color else color.adapt(caps);
    }

    fn getBackgroundColor(self: *Self, caps: renderer_mod.TermCaps) ?Style.Color {
        // Use base color schemes for background
        const color_scheme = notification.ColorScheme.getStandard(self.base.notification_type);
        if (color_scheme.background) |bg| {
            return bg.adapt(caps);
        }
        return null; // No background for normal notifications
    }

    fn getPriorityZIndex(self: *Self) i32 {
        return switch (self.base.priority) {
            .low => 1000,
            .normal => 2000,
            .high => 3000,
            .critical => 4000,
        };
    }
};

/// Notification Controller for handling multiple smart notifications
pub const NotificationController = struct {
    const Self = @This();

    notifications: std.ArrayList(NotificationWidget),
    allocator: std.mem.Allocator,
    renderer: *Renderer,
    max_concurrent: u32,

    pub fn init(allocator: std.mem.Allocator, renderer: *Renderer) Self {
        return Self{
            .notifications = std.ArrayList(NotificationWidget).init(allocator),
            .allocator = allocator,
            .renderer = renderer,
            .max_concurrent = 3, // Limit concurrent notifications
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up all notifications
        for (self.notifications.items) |*notif| {
            notif.hide(self.renderer) catch {}; // Best effort cleanup
        }
        self.notifications.deinit();
    }

    pub fn notify(
        self: *Self,
        title: []const u8,
        message: []const u8,
        notification_type: NotificationType,
        config: NotificationConfig,
        options: NotificationWidget.Options,
    ) !void {
        // Clean up old/expired notifications
        try self.cleanup();

        var notif = NotificationWidget.init(title, message, notification_type, config, options);
        try notif.show(self.renderer);
        try self.notifications.append(notif);
    }

    pub fn info(self: *Self, title: []const u8, message: []const u8) !void {
        try self.notify(title, message, .info, .{}, .{});
    }

    pub fn success(self: *Self, title: []const u8, message: []const u8) !void {
        try self.notify(title, message, .success, .{}, .{});
    }

    pub fn warning(self: *Self, title: []const u8, message: []const u8) !void {
        try self.notify(title, message, .warning, .{}, .{});
    }

    pub fn errorNotification(self: *Self, title: []const u8, message: []const u8) !void {
        try self.notify(title, message, .@"error", .{}, .{ .priority = .high, .persistent = true });
    }

    pub fn debug(self: *Self, title: []const u8, message: []const u8) !void {
        try self.notify(title, message, .debug, .{}, .{ .duration_ms = 5000 });
    }

    pub fn critical(self: *Self, title: []const u8, message: []const u8) !void {
        try self.notify(title, message, .critical, .{}, .{
            .priority = .critical,
            .persistent = true,
            .position = .center,
            .animation = .bounce,
        });
    }

    pub fn progress(self: *Self, title: []const u8, message: []const u8, progress_value: f32) !void {
        const config = NotificationConfig{};
        const options = NotificationWidget.Options{
            .persistent = true,
            .position = .bottom_left,
            .priority = .normal,
        };

        var notif = NotificationWidget.init(title, message, .progress, config, options);
        notif.base.progress = progress_value;
        try notif.show(self.renderer);
        try self.notifications.append(notif);
    }

    pub fn updateProgress(self: *Self, title: []const u8, message: []const u8, progress_value: f32) !void {
        // Find existing progress notification and update it
        for (self.notifications.items, 0..) |*notif, i| {
            if (notif.base.notification_type == .progress and
                std.mem.eql(u8, notif.base.title, title))
            {
                // Remove old notification
                try notif.hide(self.renderer);
                _ = self.notifications.swapRemove(i);

                // Create and show updated notification
                try self.progress(title, message, progress_value);
                return;
            }
        }

        // If not found, create new one
        try self.progress(title, message, progress_value);
    }

    pub fn clearAll(self: *Self) !void {
        for (self.notifications.items) |*notif| {
            try notif.hide(self.renderer);
        }
        self.notifications.clearAndFree();
    }

    fn cleanup(self: *Self) !void {
        var i: usize = 0;

        while (i < self.notifications.items.len) {
            const notif = &self.notifications.items[i];

            // Remove expired notifications or if we're over the limit
            const should_remove = notif.isExpired() or
                (self.notifications.items.len >= self.max_concurrent and
                    notif.options.priority != .critical);

            if (should_remove) {
                try notif.hide(self.renderer);
                _ = self.notifications.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }
};

/// TUI Notification system extending base (compatibility alias)
pub const NotificationSystem = struct {
    allocator: std.mem.Allocator,
    enabled: bool,
    notifications: std.ArrayList(BaseNotification),
    config: NotificationConfig,

    pub fn init(allocator: std.mem.Allocator, enabled: bool) !*NotificationSystem {
        const self = try allocator.create(NotificationSystem);
        self.* = .{
            .allocator = allocator,
            .enabled = enabled,
            .notifications = std.ArrayList(BaseNotification).init(allocator),
            .config = NotificationConfig{
                .enableSystemNotifications = true,
                .enableSound = false,
                .autoDismissMs = 3000,
                .showTimestamp = true,
                .showIcons = true,
                .maxWidth = 80,
                .padding = 1,
            },
        };
        return self;
    }

    pub fn deinit(self: *NotificationSystem) void {
        // Clean up all notifications
        for (self.notifications.items) |*notif| {
            self.allocator.free(notif.title);
            self.allocator.free(notif.message);
        }
        self.notifications.deinit();
        self.allocator.destroy(self);
    }

    /// Show notification using BaseNotification
    pub fn showNotification(self: *NotificationSystem, title: []const u8, message: []const u8, notification_type: NotificationType) !void {
        if (!self.enabled) return;

        const base_notification = BaseNotification.init(try self.allocator.dupe(u8, title), try self.allocator.dupe(u8, message), notification_type, self.config);

        try self.notifications.append(base_notification);

        // Send system notification if enabled
        if (self.config.enableSystemNotifications) {
            // Note: Would need terminal writer and caps passed in
            // try SystemNotification.send(writer, self.allocator, caps, title, message);
        }
    }

    /// Show notification with custom config
    pub fn showNotificationWithConfig(self: *NotificationSystem, title: []const u8, message: []const u8, notification_type: NotificationType, config: NotificationConfig) !void {
        if (!self.enabled) return;

        const base_notification = BaseNotification.init(try self.allocator.dupe(u8, title), try self.allocator.dupe(u8, message), notification_type, config);

        try self.notifications.append(base_notification);
    }

    /// Show progress notification
    pub fn showProgressNotification(self: *NotificationSystem, title: []const u8, message: []const u8, progress: f32) !void {
        if (!self.enabled) return;

        const progress_notification = BaseNotification.initProgress(try self.allocator.dupe(u8, title), try self.allocator.dupe(u8, message), progress, self.config);

        try self.notifications.append(progress_notification);
    }

    /// Update progress for existing notification
    pub fn updateProgress(self: *NotificationSystem, index: usize, progress: f32) !void {
        if (index >= self.notifications.items.len) return;
        self.notifications.items[index].updateProgress(progress);
    }

    /// Render all notifications using TUI-specific formatting
    pub fn renderNotifications(self: *NotificationSystem, writer: anytype) !void {
        // Remove expired notifications
        var i: usize = 0;
        while (i < self.notifications.items.len) {
            if (self.notifications.items[i].shouldAutoDismiss()) {
                const notif = self.notifications.swapRemove(i);
                self.allocator.free(notif.title);
                self.allocator.free(notif.message);
            } else {
                i += 1;
            }
        }

        // Render active notifications
        for (self.notifications.items, 0..) |notif, idx| {
            try self.renderNotification(writer, notif, idx);
        }
    }

    /// Render individual notification with TUI formatting
    fn renderNotification(self: *NotificationSystem, writer: anytype, notif: BaseNotification, index: usize) !void {
        // Position notification (stack from top)
        const y_pos = index + 1;
        try writer.print("\x1b[{d};1H", .{y_pos});

        // Clear line
        try writer.writeAll("\x1b[2K");

        // Render notification box
        try self.renderNotificationBox(writer, notif);
        try writer.writeAll("\n");
    }

    /// Render notification with border and formatting
    fn renderNotificationBox(self: *NotificationSystem, writer: anytype, notif: BaseNotification) !void {
        // Border characters
        const border = if (notif.notification_type == .critical) "!!" else "[]";

        // Color codes based on type
        const color_code = switch (notif.notification_type) {
            .info => "\x1b[36m", // Cyan
            .success => "\x1b[32m", // Green
            .warning => "\x1b[33m", // Yellow
            .@"error" => "\x1b[31m", // Red
            .debug => "\x1b[35m", // Magenta
            .critical => "\x1b[91m", // Bright red
            .progress => "\x1b[93m", // Bright yellow
        };

        const reset = "\x1b[0m";

        // Icon
        const icon = notif.notification_type.icon();

        // Title and message
        const title = notif.title;
        const message = notif.message;

        // Render notification
        try writer.print("{s}{s}{s} {s}{s} {s}", .{ color_code, border, icon, title, reset, message });

        // Add progress bar for progress notifications
        if (notif.isProgress() and notif.progress != null) {
            const progress = notif.progress.?;
            const progress_width = 20;
            const filled = @as(usize, @intFromFloat(progress * @as(f32, @floatFromInt(progress_width))));

            try writer.print(" {s}[", .{color_code});
            var i: usize = 0;
            while (i < progress_width) : (i += 1) {
                const char = if (i < filled) "=" else " ";
                try writer.writeByte(char);
            }
            try writer.print("]{s} {d:.0}%", .{ reset, progress * 100 });
        }

        // Add timestamp if enabled
        if (notif.config.showTimestamp) {
            const timestamp_str = try notif.getFormattedTimestamp(self.allocator);
            defer self.allocator.free(timestamp_str);
            try writer.print(" {s}{s}{s}", .{ color_code, timestamp_str, reset });
        }
    }

    /// Get notification count
    pub fn getNotificationCount(self: *NotificationSystem) usize {
        return self.notifications.items.len;
    }

    /// Clear all notifications
    pub fn clearAllNotifications(self: *NotificationSystem) void {
        for (self.notifications.items) |*notif| {
            self.allocator.free(notif.title);
            self.allocator.free(notif.message);
        }
        self.notifications.clearRetainingCapacity();
    }

    /// Enable/disable the notification system
    pub fn setEnabled(self: *NotificationSystem, enabled: bool) void {
        self.enabled = enabled;
    }

    /// Update configuration
    pub fn updateConfig(self: *NotificationSystem, config: NotificationConfig) void {
        self.config = config;
    }
};

/// Convenience functions using shared context controller
pub fn initManager(ctx: *SharedContext, allocator: std.mem.Allocator, renderer: *Renderer) void {
    if (ctx.notification.controller) |c| {
        const existing: *NotificationController = @ptrCast(@alignCast(c));
        existing.deinit();
    }
    const controller = NotificationController.init(allocator, renderer);
    ctx.notification.controller = controller;
    ctx.notification.allocator = allocator;
}

pub fn deinitManager(ctx: *SharedContext) void {
    if (ctx.notification.controller) |c| {
        const controller: *NotificationController = @ptrCast(@alignCast(c));
        controller.deinit();
        ctx.notification.controller = null;
        ctx.notification.allocator = null;
    }
}

pub fn notify(ctx: *SharedContext, title: []const u8, message: []const u8, notification_type: NotificationType, config: NotificationConfig, options: NotificationWidget.Options) !void {
    if (ctx.notification.controller) |c| {
        const controller: *NotificationController = @ptrCast(@alignCast(c));
        try controller.notify(title, message, notification_type, config, options);
    } else {
        return error.ControllerNotInitialized;
    }
}

pub fn info(ctx: *SharedContext, title: []const u8, message: []const u8) !void {
    try notify(ctx, title, message, .info, .{}, .{});
}

pub fn success(ctx: *SharedContext, title: []const u8, message: []const u8) !void {
    try notify(ctx, title, message, .success, .{}, .{});
}

pub fn warning(ctx: *SharedContext, title: []const u8, message: []const u8) !void {
    try notify(ctx, title, message, .warning, .{}, .{});
}

pub fn errorNotification(ctx: *SharedContext, title: []const u8, message: []const u8) !void {
    try notify(ctx, title, message, .@"error", .{}, .{ .priority = .high, .persistent = true });
}

pub fn debug(ctx: *SharedContext, title: []const u8, message: []const u8) !void {
    try notify(ctx, title, message, .debug, .{}, .{ .duration_ms = 5000 });
}

pub fn critical(ctx: *SharedContext, title: []const u8, message: []const u8) !void {
    try notify(ctx, title, message, .critical, .{}, .{
        .priority = .critical,
        .persistent = true,
        .position = .center,
        .animation = .bounce,
    });
}

pub fn showProgress(ctx: *SharedContext, title: []const u8, message: []const u8, progress_value: f32) !void {
    if (ctx.notification.controller) |c| {
        const controller: *NotificationController = @ptrCast(@alignCast(c));
        try controller.progress(title, message, progress_value);
    } else {
        return error.ControllerNotInitialized;
    }
}

pub fn updateProgress(ctx: *SharedContext, title: []const u8, message: []const u8, progress_value: f32) !void {
    if (ctx.notification.controller) |c| {
        const controller: *NotificationController = @ptrCast(@alignCast(c));
        try controller.updateProgress(title, message, progress_value);
    } else {
        return error.ControllerNotInitialized;
    }
}

test "notification widget initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const widget = NotificationWidget.init("Test", "Message", .info, .{}, .{});
    defer {
        allocator.free(widget.base.title);
        allocator.free(widget.base.message);
    }

    // Verify widget was initialized correctly
    try std.testing.expectEqualStrings("Test", widget.base.title);
    try std.testing.expectEqualStrings("Message", widget.base.message);
    try std.testing.expectEqual(NotificationType.info, widget.base.notification_type);
    try std.testing.expect(!widget.is_displayed);
}

const MockRenderer = struct {
    pub fn clear(_: *MockRenderer, _: Bounds) !void {}
    pub fn beginFrame(_: *MockRenderer) !void {}
    pub fn endFrame(_: *MockRenderer) !void {}
    pub fn drawTextBox(_: *MockRenderer, _: Render, _: []const u8, _: BoxStyle) !void {}
    pub fn writer(_: *MockRenderer) std.io.Writer(std.io.null_writer) {
        return std.io.null_writer;
    }
    pub fn getAllocator(_: *MockRenderer) std.mem.Allocator {
        return std.testing.allocator;
    }
    pub fn getCapabilities(_: *MockRenderer) renderer_mod.TermCaps {
        return .{};
    }
};

test "notification controller initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mock_renderer = MockRenderer{};
    var controller = NotificationController.init(allocator, @ptrCast(&mock_renderer));
    defer controller.deinit();

    try std.testing.expect(controller.notifications.items.len == 0);
}

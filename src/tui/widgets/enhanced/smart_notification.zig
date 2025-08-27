//! Smart Notification Widget with Progressive Enhancement
//!
//! This notification system automatically adapts to terminal capabilities:
//! - System notifications (OSC 9) when supported
//! - Rich in-terminal notifications with graphics/colors
//! - Graceful fallback to basic text notifications
//! - Proper positioning and animation where supported

const std = @import("std");
const renderer_mod = @import("../../core/renderer.zig");
const bounds_mod = @import("../../core/bounds.zig");

const Renderer = renderer_mod.Renderer;
const RenderContext = renderer_mod.RenderContext;
const Style = renderer_mod.Style;
const BoxStyle = renderer_mod.BoxStyle;
const Point = renderer_mod.Point;
const Bounds = renderer_mod.Bounds;
const NotificationLevel = renderer_mod.NotificationLevel;

/// Smart notification that adapts to terminal capabilities
pub const SmartNotification = struct {
    const Self = @This();

    title: []const u8,
    message: []const u8,
    level: NotificationLevel,
    options: Options,
    timestamp: i64,
    is_displayed: bool,
    allocator: std.mem.Allocator,

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
        allocator: std.mem.Allocator,
        title: []const u8,
        message: []const u8,
        level: NotificationLevel,
        options: Options,
    ) Self {
        return Self{
            .title = title,
            .message = message,
            .level = level,
            .options = options,
            .timestamp = std.time.timestamp(),
            .is_displayed = false,
            .allocator = allocator,
        };
    }

    pub fn show(self: *Self, renderer: *Renderer) !void {
        const caps = renderer.getCapabilities();

        // Try system notification first if enabled and supported
        if (self.options.use_system_notification and caps.supportsNotifyOsc9) {
            try renderer.sendNotification(self.title, self.message);
        }

        // Show in-terminal notification if enabled
        if (self.options.show_in_terminal) {
            try self.showTerminalNotification(renderer);
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
        const age_ms = @as(u32, @intCast(now - self.timestamp)) * 1000;
        return age_ms > self.options.duration_ms.?;
    }

    fn getBounds(self: *Self, terminal_size: bounds_mod.TerminalSize) Bounds {
        // Calculate content dimensions
        const title_len = std.unicode.utf8CountCodepoints(self.title) catch self.title.len;
        const message_len = std.unicode.utf8CountCodepoints(self.message) catch self.message.len;
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
        const ctx = RenderContext{
            .bounds = notification_bounds,
            .style = self.getNotificationStyle(renderer.getCapabilities()),
            .z_index = self.getPriorityZIndex(),
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

    fn renderNotification(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
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
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const temp_allocator = arena.allocator();

        const icon = self.getLevelIcon();
        const content = try self.formatNotificationContent(temp_allocator, icon);

        // Render the notification box with content
        try renderer.drawTextBox(ctx, content, box_style);

        // Add hyperlink if this is an error with support info
        if (self.level == .error_ and caps.supportsHyperlinkOsc8) {
            try renderer.setHyperlink("https://support.example.com/error-help");
            // The hyperlink would be applied to error-related text
            try renderer.clearHyperlink();
        }
    }

    fn animateIn(self: *Self, renderer: *Renderer, final_ctx: RenderContext) !void {
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
        try content.appendSlice(self.title);
        try content.appendSlice("\n");

        // Message (with simple word wrapping if needed)
        try content.appendSlice(self.message);

        // Timestamp if requested
        if (self.options.show_timestamp) {
            try content.appendSlice("\n");
            const timestamp_str = try std.fmt.allocPrint(allocator, "{}s ago", .{std.time.timestamp() - self.timestamp});
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
        return switch (self.level) {
            .info => "ℹ",
            .success => "✓",
            .warning => "⚠",
            .error_ => "✗",
            .debug => "🐛",
        };
    }

    fn getLevelColor(self: *Self, caps: renderer_mod.TermCaps) Style.Color {
        if (caps.supportsTruecolor) {
            return switch (self.level) {
                .info => .{ .rgb = .{ .r = 100, .g = 149, .b = 237 } }, // Cornflower blue
                .success => .{ .rgb = .{ .r = 50, .g = 205, .b = 50 } }, // Lime green
                .warning => .{ .rgb = .{ .r = 255, .g = 215, .b = 0 } }, // Gold
                .error_ => .{ .rgb = .{ .r = 220, .g = 20, .b = 60 } }, // Crimson
                .debug => .{ .rgb = .{ .r = 138, .g = 43, .b = 226 } }, // Blue violet
            };
        } else {
            return switch (self.level) {
                .info => .{ .palette = 12 }, // Bright blue
                .success => .{ .palette = 10 }, // Bright green
                .warning => .{ .palette = 11 }, // Bright yellow
                .error_ => .{ .palette = 9 }, // Bright red
                .debug => .{ .palette = 13 }, // Bright magenta
            };
        }
    }

    fn getBackgroundColor(self: *Self, caps: renderer_mod.TermCaps) ?Style.Color {
        // Subtle background for higher priority notifications
        if (self.options.priority == .critical) {
            if (caps.supportsTruecolor) {
                return .{ .rgb = .{ .r = 40, .g = 40, .b = 40 } }; // Dark background
            } else {
                return .{ .ansi = 0 }; // Black background
            }
        }
        return null; // No background for normal notifications
    }

    fn getPriorityZIndex(self: *Self) i32 {
        return switch (self.options.priority) {
            .low => 1000,
            .normal => 2000,
            .high => 3000,
            .critical => 4000,
        };
    }
};

/// Notification Manager for handling multiple smart notifications
pub const SmartNotificationManager = struct {
    const Self = @This();

    notifications: std.ArrayList(SmartNotification),
    allocator: std.mem.Allocator,
    renderer: *Renderer,
    max_concurrent: u32,

    pub fn init(allocator: std.mem.Allocator, renderer: *Renderer) Self {
        return Self{
            .notifications = std.ArrayList(SmartNotification).init(allocator),
            .allocator = allocator,
            .renderer = renderer,
            .max_concurrent = 3, // Limit concurrent notifications
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up all notifications
        for (self.notifications.items) |*notification| {
            notification.hide(self.renderer) catch {}; // Best effort cleanup
        }
        self.notifications.deinit();
    }

    pub fn notify(
        self: *Self,
        title: []const u8,
        message: []const u8,
        level: NotificationLevel,
        options: SmartNotification.Options,
    ) !void {
        // Clean up old/expired notifications
        try self.cleanup();

        var notification = SmartNotification.init(self.allocator, title, message, level, options);
        try notification.show(self.renderer);
        try self.notifications.append(notification);
    }

    pub fn info(self: *Self, title: []const u8, message: []const u8) !void {
        try self.notify(title, message, .info, .{});
    }

    pub fn success(self: *Self, title: []const u8, message: []const u8) !void {
        try self.notify(title, message, .success, .{});
    }

    pub fn warning(self: *Self, title: []const u8, message: []const u8) !void {
        try self.notify(title, message, .warning, .{});
    }

    pub fn error_(self: *Self, title: []const u8, message: []const u8) !void {
        try self.notify(title, message, .error_, .{ .priority = .high, .persistent = true });
    }

    pub fn debug(self: *Self, title: []const u8, message: []const u8) !void {
        try self.notify(title, message, .debug, .{ .duration_ms = 5000 });
    }

    pub fn critical(self: *Self, title: []const u8, message: []const u8) !void {
        try self.notify(title, message, .error_, .{
            .priority = .critical,
            .persistent = true,
            .position = .center,
            .animation = .bounce,
        });
    }

    pub fn clearAll(self: *Self) !void {
        for (self.notifications.items) |*notification| {
            try notification.hide(self.renderer);
        }
        self.notifications.clearAndFree();
    }

    fn cleanup(self: *Self) !void {
        var i: usize = 0;

        while (i < self.notifications.items.len) {
            const notification = &self.notifications.items[i];

            // Remove expired notifications or if we're over the limit
            const should_remove = notification.isExpired() or
                (self.notifications.items.len >= self.max_concurrent and
                    notification.options.priority != .critical);

            if (should_remove) {
                try notification.hide(self.renderer);
                _ = self.notifications.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }
};

/// Convenience functions for quick notifications with global manager
var global_manager: ?SmartNotificationManager = null;
var global_allocator: ?std.mem.Allocator = null;

pub fn initGlobalManager(allocator: std.mem.Allocator, renderer: *Renderer) void {
    if (global_manager) |*manager| {
        manager.deinit();
    }
    global_manager = SmartNotificationManager.init(allocator, renderer);
    global_allocator = allocator;
}

pub fn deinitGlobalManager() void {
    if (global_manager) |*manager| {
        manager.deinit();
        global_manager = null;
        global_allocator = null;
    }
}

pub fn notify(title: []const u8, message: []const u8, level: NotificationLevel, options: SmartNotification.Options) !void {
    if (global_manager) |*manager| {
        try manager.notify(title, message, level, options);
    } else {
        return error.ManagerNotInitialized;
    }
}

pub fn info(title: []const u8, message: []const u8) !void {
    try notify(title, message, .info, .{});
}

pub fn success(title: []const u8, message: []const u8) !void {
    try notify(title, message, .success, .{});
}

pub fn warning(title: []const u8, message: []const u8) !void {
    try notify(title, message, .warning, .{});
}

pub fn error_(title: []const u8, message: []const u8) !void {
    try notify(title, message, .error_, .{ .priority = .high, .persistent = true });
}

pub fn debug(title: []const u8, message: []const u8) !void {
    try notify(title, message, .debug, .{ .duration_ms = 5000 });
}

pub fn critical(title: []const u8, message: []const u8) !void {
    try notify(title, message, .error_, .{
        .priority = .critical,
        .persistent = true,
        .position = .center,
        .animation = .bounce,
    });
}

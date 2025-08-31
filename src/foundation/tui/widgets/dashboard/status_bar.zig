//! Status bar widget with live updates and system integration
//! Provides real-time status information with support for notifications,
//! system metrics, and interactive elements

const std = @import("std");
const renderer_mod = @import("../../core/renderer.zig");
const bounds_mod = @import("../../core/bounds.zig");
const events_mod = @import("../../core/events.zig");
const terminal_mod = @import("../../../term/unified.zig");

const Renderer = renderer_mod.Renderer;
const Render = renderer_mod.Render;
const Bounds = bounds_mod.Bounds;
const Point = bounds_mod.Point;

pub const StatusBarError = error{
    UpdateFailed,
    InvalidConfig,
} || std.mem.Allocator.Error;

pub const StatusBar = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: Config,
    state: StatusState,
    items: StatusItemList,
    bounds: Bounds = Bounds.init(0, 0, 0, 0),

    // Live update system
    update_timer: std.time.Timer,
    last_update: i64 = 0,

    pub const Config = struct {
        position: Position = .bottom,
        height: u32 = 1,
        show_time: bool = true,
        show_system_info: bool = true,
        show_notifications: bool = true,
        update_interval_ms: u32 = 1000,
        separator: []const u8 = " | ",
        use_colors: bool = true,
        show_shortcuts: bool = true,

        pub const Position = enum {
            top,
            bottom,
        };
    };

    pub const StatusState = struct {
        focused: bool = false,
        notification_count: u32 = 0,
        last_notification: ?Notification = null,
        system_metrics: ?SystemMetrics = null,

        pub const Notification = struct {
            message: []const u8,
            level: NotificationLevel,
            timestamp: i64,

            pub const NotificationLevel = enum {
                info,
                warning,
                err,
                success,
            };
        };

        pub const SystemMetrics = struct {
            cpu_usage: f64 = 0.0,
            memory_usage: f64 = 0.0,
            disk_usage: f64 = 0.0,
            network_activity: bool = false,
        };
    };

    const StatusItemList = std.ArrayList(StatusItem);

    pub const StatusItem = struct {
        id: []const u8,
        content: Content,
        style: Style = Style{},
        clickable: bool = false,
        priority: u32 = 0, // Higher priority items shown first when space is limited

        pub const Content = union(enum) {
            text: []const u8,
            formatted: struct {
                format: []const u8,
                args: []const std.fmt.ArgSetType(.{}).Arg,
            },
            dynamic: *const fn () []const u8,
            metric: Metric,
        };

        pub const Style = struct {
            color: ?terminal_mod.Color = null,
            backgroundColor: ?terminal_mod.Color = null,
            bold: bool = false,
            italic: bool = false,
            blink: bool = false,
        };

        pub const Metric = struct {
            value: f64,
            unit: []const u8,
            format: []const u8 = "{d:.1}{s}",
            thresholds: ?[]Threshold = null,

            pub const Threshold = struct {
                value: f64,
                color: terminal_mod.Color,
                style: Style = Style{},
            };
        };
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        var timer = try std.time.Timer.start();

        return Self{
            .allocator = allocator,
            .config = config,
            .state = StatusState{},
            .items = StatusItemList.init(allocator),
            .update_timer = timer,
            .last_update = timer.read(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit();
        if (self.state.last_notification) |notif| {
            self.allocator.free(notif.message);
        }
    }

    pub fn addItem(self: *Self, item: StatusItem) !void {
        try self.items.append(item);
        self.sortItemsByPriority();
    }

    pub fn removeItem(self: *Self, id: []const u8) bool {
        for (self.items.items, 0..) |item, i| {
            if (std.mem.eql(u8, item.id, id)) {
                _ = self.items.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn updateItem(self: *Self, id: []const u8, new_content: StatusItem.Content) bool {
        for (self.items.items) |*item| {
            if (std.mem.eql(u8, item.id, id)) {
                item.content = new_content;
                return true;
            }
        }
        return false;
    }

    fn sortItemsByPriority(self: *Self) void {
        std.mem.sort(StatusItem, self.items.items, {}, struct {
            fn lessThan(_: void, a: StatusItem, b: StatusItem) bool {
                return a.priority > b.priority; // Higher priority first
            }
        }.lessThan);
    }

    pub fn render(self: *Self, renderer: *Renderer, ctx: Render) !void {
        self.bounds = ctx.bounds;

        // Update live data if interval has passed
        const now = self.update_timer.read();
        if (now - self.last_update >= self.config.update_interval_ms * 1_000_000) { // Convert ms to ns
            try self.updateLiveData();
            self.last_update = now;
        }

        // Clear the status bar area
        try self.clearStatusBar(renderer, ctx);

        // Render status items
        try self.renderStatusItems(renderer, ctx);

        // Render notification if present
        if (self.state.last_notification) |notif| {
            try self.renderNotification(renderer, ctx, notif);
        }
    }

    fn clearStatusBar(self: *Self, renderer: *Renderer, ctx: Render) !void {
        for (0..self.config.height) |row| {
            const y = switch (self.config.position) {
                .top => ctx.bounds.y + @as(u32, @intCast(row)),
                .bottom => ctx.bounds.y + ctx.bounds.height - self.config.height + @as(u32, @intCast(row)),
            };

            try renderer.moveCursor(ctx.bounds.x, y);

            // Fill with background color if configured
            if (self.config.use_colors) {
                try renderer.setBackground(terminal_mod.Color.black);
            }

            for (0..ctx.bounds.width) |_| {
                try renderer.writeText(" ");
            }

            try renderer.resetStyle();
        }
    }

    fn renderStatusItems(self: *Self, renderer: *Renderer, ctx: Render) !void {
        const status_y = switch (self.config.position) {
            .top => ctx.bounds.y,
            .bottom => ctx.bounds.y + ctx.bounds.height - 1,
        };

        var current_x = ctx.bounds.x;
        const max_x = ctx.bounds.x + ctx.bounds.width;

        // Add built-in items first
        var items_to_render = std.ArrayList(StatusItem).init(self.allocator);
        defer items_to_render.deinit();

        // Time item
        if (self.config.show_time) {
            const time_item = try self.createTimeItem();
            try items_to_render.append(time_item);
        }

        // System info items
        if (self.config.show_system_info and self.state.system_metrics != null) {
            const sys_items = try self.createSystemItems();
            defer self.allocator.free(sys_items);
            try items_to_render.appendSlice(sys_items);
        }

        // User-defined items
        try items_to_render.appendSlice(self.items.items);

        // Render items with available space
        for (items_to_render.items, 0..) |item, i| {
            const content = try self.resolveItemContent(item);
            defer self.allocator.free(content);

            const item_width = content.len;
            const separator_width = if (i > 0) self.config.separator.len else 0;
            const total_width = separator_width + item_width;

            if (current_x + total_width > max_x) break; // Not enough space

            try renderer.moveCursor(current_x, status_y);

            // Render separator
            if (i > 0) {
                try renderer.writeText("{s}", .{self.config.separator});
                current_x += @intCast(separator_width);
            }

            // Apply item styling
            if (self.config.use_colors) {
                try self.applyItemStyle(renderer, item);
            }

            // Render content
            try renderer.writeText("{s}", .{content});
            try renderer.resetStyle();

            current_x += @intCast(item_width);
        }

        // Render shortcuts on the right side if space allows
        if (self.config.show_shortcuts) {
            try self.renderShortcuts(renderer, ctx, current_x, status_y);
        }
    }

    fn createTimeItem(self: *Self) !StatusItem {

        // Get current time
        const timestamp = std.time.timestamp();
        const epoch_seconds = @as(u64, @intCast(timestamp));

        // Simple time formatting (this is a simplified implementation)
        const hours = (epoch_seconds / 3600) % 24;
        const minutes = (epoch_seconds / 60) % 60;
        const seconds = epoch_seconds % 60;

        const time_str = try std.fmt.allocPrint(self.allocator, "{d:0>2}:{d:0>2}:{d:0>2}", .{ hours, minutes, seconds });

        return StatusItem{
            .id = "time",
            .content = StatusItem.Content{ .text = time_str },
            .priority = 100,
        };
    }

    fn createSystemItems(self: *Self) ![]StatusItem {
        if (self.state.system_metrics) |metrics| {
            var items = std.ArrayList(StatusItem).init(self.allocator);

            // CPU usage
            try items.append(StatusItem{
                .id = "cpu",
                .content = StatusItem.Content{ .metric = StatusItem.Metric{
                    .value = metrics.cpu_usage,
                    .unit = "%",
                    .format = "CPU:{d:.0}{s}",
                    .thresholds = &[_]StatusItem.Metric.Threshold{
                        .{ .value = 80, .color = terminal_mod.Color.yellow },
                        .{ .value = 95, .color = terminal_mod.Color.red },
                    },
                } },
                .priority = 90,
            });

            // Memory usage
            try items.append(StatusItem{
                .id = "memory",
                .content = StatusItem.Content{ .metric = StatusItem.Metric{
                    .value = metrics.memory_usage,
                    .unit = "%",
                    .format = "MEM:{d:.0}{s}",
                    .thresholds = &[_]StatusItem.Metric.Threshold{
                        .{ .value = 80, .color = terminal_mod.Color.yellow },
                        .{ .value = 90, .color = terminal_mod.Color.red },
                    },
                } },
                .priority = 85,
            });

            // Network activity indicator
            if (metrics.network_activity) {
                try items.append(StatusItem{
                    .id = "network",
                    .content = StatusItem.Content{ .text = "NET" },
                    .style = StatusItem.Style{ .color = terminal_mod.Color.green, .blink = true },
                    .priority = 70,
                });
            }

            return items.toOwnedSlice();
        }

        return &[_]StatusItem{};
    }

    fn resolveItemContent(self: *Self, item: StatusItem) ![]u8 {
        switch (item.content) {
            .text => |text| return try self.allocator.dupe(u8, text),
            .formatted => |fmt| {
                // This is a simplified implementation
                _ = fmt;
                return try self.allocator.dupe(u8, "formatted");
            },
            .dynamic => |func| {
                const content = func();
                return try self.allocator.dupe(u8, content);
            },
            .metric => |metric| {
                // TODO: Apply threshold coloring based on metric.thresholds
                return try std.fmt.allocPrint(self.allocator, metric.format, .{ metric.value, metric.unit });
            },
        }
    }

    fn applyItemStyle(self: *Self, renderer: *Renderer, item: StatusItem) !void {
        _ = self;

        var style = renderer_mod.Style{};

        if (item.style.color) |color| {
            style.foregroundColor = color;
        }

        if (item.style.backgroundColor) |bg| {
            style.backgroundColor = bg;
        }

        style.bold = item.style.bold;
        style.italic = item.style.italic;

        // TODO: Implement blink support

        try renderer.setStyleEx(style);
    }

    fn renderShortcuts(self: *Self, renderer: *Renderer, ctx: Render, start_x: u32, y: u32) !void {
        const shortcuts = "F1:Help F10:Quit";
        const shortcuts_width = shortcuts.len;

        if (start_x + shortcuts_width + 4 <= ctx.bounds.x + ctx.bounds.width) {
            const shortcuts_x = ctx.bounds.x + ctx.bounds.width - shortcuts_width;
            try renderer.moveCursor(shortcuts_x, y);

            if (self.config.use_colors) {
                try renderer.setStyle(.{ .dim = true });
            }

            try renderer.writeText("{s}", .{shortcuts});
            try renderer.resetStyle();
        }
    }

    fn renderNotification(self: *Self, renderer: *Renderer, ctx: Render, notification: StatusState.Notification) !void {

        // Render notification in a special area (could be a popup or overlay)
        const notif_y = ctx.bounds.y + if (self.config.position == .top) 1 else ctx.bounds.height - 2;

        try renderer.moveCursor(ctx.bounds.x, notif_y);

        // Apply notification styling based on level
        const style = switch (notification.level) {
            .info => renderer_mod.Style{ .foregroundColor = terminal_mod.Color.blue },
            .warning => renderer_mod.Style{ .foregroundColor = terminal_mod.Color.yellow },
            .err => renderer_mod.Style{ .foregroundColor = terminal_mod.Color.red, .bold = true },
            .success => renderer_mod.Style{ .foregroundColor = terminal_mod.Color.green },
        };

        try renderer.setStyleEx(style);
        try renderer.writeText("● {s}", .{notification.message});
        try renderer.resetStyle();
    }

    fn updateLiveData(self: *Self) !void {
        // Update system metrics (simplified implementation)
        self.state.system_metrics = StatusState.SystemMetrics{
            .cpu_usage = @mod(@as(f64, @floatFromInt(std.time.timestamp())), 100.0), // Mock CPU data
            .memory_usage = 67.5, // Mock memory data
            .network_activity = std.time.timestamp() % 5 == 0, // Mock network activity
        };
    }

    pub fn showNotification(self: *Self, message: []const u8, level: StatusState.Notification.NotificationLevel) !void {
        // Free previous notification if any
        if (self.state.last_notification) |old_notif| {
            self.allocator.free(old_notif.message);
        }

        self.state.last_notification = StatusState.Notification{
            .message = try self.allocator.dupe(u8, message),
            .level = level,
            .timestamp = std.time.timestamp(),
        };

        self.state.notification_count += 1;

        // System notification disabled in favor of renderer-level presenters.
        // In-terminal display will reflect the new state on next render.
    }

    pub fn clearNotification(self: *Self) void {
        if (self.state.last_notification) |notif| {
            self.allocator.free(notif.message);
            self.state.last_notification = null;
        }
    }

    pub fn handleInput(self: *Self, event: anytype) !void {
        // Handle status bar interactions (clicking on items, etc.)
        _ = self;
        _ = event;
        // TODO: Implement interactive features
    }

    // Convenience functions for common status bar configurations
    pub fn createMinimalStatusBar(allocator: std.mem.Allocator) !Self {
        return Self.init(allocator, Config{
            .show_system_info = false,
            .show_shortcuts = false,
            .update_interval_ms = 5000,
        });
    }

    pub fn createFullStatusBar(allocator: std.mem.Allocator) !Self {
        return Self.init(allocator, Config{
            .show_time = true,
            .show_system_info = true,
            .show_notifications = true,
            .show_shortcuts = true,
            .update_interval_ms = 1000,
        });
    }

    pub fn createDashboardStatusBar(allocator: std.mem.Allocator) !Self {
        return Self.init(allocator, Config{
            .position = .bottom,
            .show_time = true,
            .show_system_info = true,
            .show_notifications = true,
            .show_shortcuts = true,
            .update_interval_ms = 500, // Faster updates for dashboards
            .use_colors = true,
        });
    }
};

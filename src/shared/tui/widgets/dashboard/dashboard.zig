//! AdvancedDashboard - Advanced dashboard with progressive rendering capabilities
//!
//! This dashboard automatically adapts its rendering strategy based on terminal capabilities,
//! integrating the TerminalAdapter for optimal performance and visual quality.

const std = @import("std");
const terminal_adapter = @import("../../core/terminal_adapter.zig");
const renderer_mod = @import("../../core/renderer.zig");
const bounds_mod = @import("../../core/bounds.zig");
const chart_mod = @import("chart/mod.zig");
const table_mod = @import("table/mod.zig");

const TerminalAdapter = terminal_adapter.TerminalAdapter;
const Renderer = renderer_mod.Renderer;
const RenderContext = renderer_mod.RenderContext;
const Bounds = bounds_mod.Bounds;
const Point = bounds_mod.Point;

/// Advanced dashboard that adapts to terminal capabilities
pub const AdvancedDashboard = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    adapter: *TerminalAdapter,
    config: Config,
    layout: AdaptiveLayout,
    widgets: std.ArrayList(Widget),
    bounds: Bounds = Bounds.init(0, 0, 0, 0),

    // Progressive enhancement state
    render_mode: RenderMode,
    last_frame_time: i64 = 0,
    performance_stats: PerformanceStats = .{},

    pub const Config = struct {
        title: ?[]const u8 = null,
        auto_refresh: bool = true,
        refresh_rate_ms: u32 = 1000,
        adaptive_quality: bool = true,
        max_widgets: u32 = 20,
        enable_animations: bool = true,
        enable_interactions: bool = true,

        // Progressive enhancement settings
        fallback_on_slow_render: bool = true,
        max_render_time_ms: u32 = 100,

        // Layout configuration
        grid_columns: u32 = 12, // Bootstrap-style 12-column grid
        grid_rows: u32 = 8,
        widget_padding: u32 = 1,
    };

    /// Widget types supported by the dashboard
    pub const Widget = union(enum) {
        chart: ChartWidget,
        table: TableWidget,
        text: TextWidget,
        metric: MetricWidget,
        progress: ProgressWidget,
        notification: NotificationWidget,

        pub const ChartWidget = struct {
            id: []const u8,
            chart: chart_mod.Chart,
            position: GridPosition,
            update_callback: ?*const fn (chart: *chart_mod.Chart) void = null,
        };

        pub const TableWidget = struct {
            id: []const u8,
            table: table_mod.DataTable,
            position: GridPosition,
            update_callback: ?*const fn (table: *table_mod.DataTable) void = null,
        };

        pub const TextWidget = struct {
            id: []const u8,
            title: []const u8,
            content: []const u8,
            position: GridPosition,
            style: TextStyle = .normal,
        };

        pub const MetricWidget = struct {
            id: []const u8,
            label: []const u8,
            value: f64,
            unit: ?[]const u8 = null,
            position: GridPosition,
            format: MetricFormat = .number,
            trend: ?Trend = null,
        };

        pub const ProgressWidget = struct {
            id: []const u8,
            label: []const u8,
            progress: f64, // 0.0 to 1.0
            position: GridPosition,
            show_percentage: bool = true,
        };

        pub const NotificationWidget = struct {
            id: []const u8,
            message: []const u8,
            level: terminal_adapter.NotificationLevel,
            position: GridPosition,
            auto_dismiss: bool = true,
            dismiss_after_ms: u32 = 5000,
        };
    };

    /// Grid-based positioning system
    pub const GridPosition = struct {
        col: u32,
        row: u32,
        width: u32 = 1,
        height: u32 = 1,

        /// Check if this position overlaps with another
        pub fn overlaps(self: GridPosition, other: GridPosition) bool {
            return !(self.col + self.width <= other.col or
                other.col + other.width <= self.col or
                self.row + self.height <= other.row or
                other.row + other.height <= self.row);
        }

        /// Convert grid position to pixel bounds
        pub fn toBounds(self: GridPosition, dashboard_bounds: Bounds, grid_cols: u32, grid_rows: u32, padding: u32) Bounds {
            const cell_width = (@as(u32, @intCast(dashboard_bounds.width)) - padding) / grid_cols;
            const cell_height = (@as(u32, @intCast(dashboard_bounds.height)) - padding) / grid_rows;

            return Bounds.init(
                dashboard_bounds.x + @as(i32, @intCast(self.col * cell_width + padding / 2)),
                dashboard_bounds.y + @as(i32, @intCast(self.row * cell_height + padding / 2)),
                self.width * cell_width - padding,
                self.height * cell_height - padding,
            );
        }
    };

    /// Render mode based on terminal capabilities
    pub const RenderMode = enum {
        full_graphics, // Kitty graphics, full interactivity
        enhanced_unicode, // Unicode blocks, limited graphics
        basic_ascii, // ASCII only
        text_only, // Minimal fallback

        pub fn fromAdapter(adapter: *TerminalAdapter) RenderMode {
            return switch (adapter.current_mode) {
                .full_capability => .full_graphics,
                .graphics_enhanced => .enhanced_unicode,
                .enhanced_text => .enhanced_unicode,
                .text_only => .text_only,
            };
        }
    };

    /// Adaptive layout system
    pub const AdaptiveLayout = struct {
        current_bounds: Bounds,
        cell_size: Point,
        available_cells: u32,
        widget_positions: std.HashMap([]const u8, Bounds, std.hash_map.StringContext, 80),

        pub fn init(allocator: std.mem.Allocator) AdaptiveLayout {
            return AdaptiveLayout{
                .current_bounds = Bounds.init(0, 0, 0, 0),
                .cell_size = Point.init(0, 0),
                .available_cells = 0,
                .widget_positions = std.HashMap([]const u8, Bounds, std.hash_map.StringContext, 80).init(allocator),
            };
        }

        pub fn deinit(self: *AdaptiveLayout) void {
            self.widget_positions.deinit();
        }

        pub fn recalculate(self: *AdaptiveLayout, bounds: Bounds, config: Config) void {
            self.current_bounds = bounds;
            self.cell_size = Point.init(@divFloor(bounds.width, @as(i32, @intCast(config.grid_columns))), @divFloor(bounds.height, @as(i32, @intCast(config.grid_rows))));
            self.available_cells = config.grid_columns * config.grid_rows;

            // Clear existing positions for recalculation
            self.widget_positions.clearAndFree();
        }

        pub fn assignPosition(self: *AdaptiveLayout, widget_id: []const u8, position: GridPosition, config: Config) !void {
            const bounds = position.toBounds(self.current_bounds, config.grid_columns, config.grid_rows, config.widget_padding);
            try self.widget_positions.put(widget_id, bounds);
        }
    };

    /// Performance statistics for adaptive rendering
    pub const PerformanceStats = struct {
        total_render_time_ms: u32 = 0,
        widget_count: u32 = 0,
        frame_count: u32 = 0,
        dropped_frames: u32 = 0,
        average_render_time_ms: f32 = 0.0,

        pub fn update(self: *PerformanceStats, render_time_ms: u32) void {
            self.total_render_time_ms += render_time_ms;
            self.frame_count += 1;
            self.average_render_time_ms = @as(f32, @floatFromInt(self.total_render_time_ms)) / @as(f32, @floatFromInt(self.frame_count));
        }

        pub fn shouldDowngrade(self: PerformanceStats, max_render_time_ms: u32) bool {
            return self.average_render_time_ms > @as(f32, @floatFromInt(max_render_time_ms));
        }
    };

    /// Supporting enums and types
    pub const TextStyle = enum { normal, bold, italic, highlight };
    pub const MetricFormat = enum { number, currency, percentage, bytes };
    pub const Trend = enum { up, down, flat };

    pub fn init(allocator: std.mem.Allocator, adapter: *TerminalAdapter, config: Config) Self {
        return Self{
            .allocator = allocator,
            .adapter = adapter,
            .config = config,
            .layout = AdaptiveLayout.init(allocator),
            .widgets = std.ArrayList(Widget).init(allocator),
            .render_mode = RenderMode.fromAdapter(adapter),
        };
    }

    pub fn deinit(self: *Self) void {
        self.layout.deinit();
        self.widgets.deinit();
    }

    /// Add a widget to the dashboard
    pub fn addWidget(self: *Self, widget: Widget) !void {
        if (self.widgets.items.len >= self.config.max_widgets) {
            return error.TooManyWidgets;
        }

        try self.widgets.append(widget);

        // Assign position in layout
        const widget_id = switch (widget) {
            .chart => |c| c.id,
            .table => |t| t.id,
            .text => |txt| txt.id,
            .metric => |m| m.id,
            .progress => |p| p.id,
            .notification => |n| n.id,
        };

        const position = switch (widget) {
            .chart => |c| c.position,
            .table => |t| t.position,
            .text => |txt| txt.position,
            .metric => |m| m.position,
            .progress => |p| p.position,
            .notification => |n| n.position,
        };

        try self.layout.assignPosition(widget_id, position, self.config);
    }

    /// Remove a widget by ID
    pub fn removeWidget(self: *Self, widget_id: []const u8) bool {
        for (self.widgets.items, 0..) |widget, i| {
            const id = switch (widget) {
                .chart => |c| c.id,
                .table => |t| t.id,
                .text => |txt| txt.id,
                .metric => |m| m.id,
                .progress => |p| p.id,
                .notification => |n| n.id,
            };

            if (std.mem.eql(u8, id, widget_id)) {
                _ = self.widgets.swapRemove(i);
                _ = self.layout.widget_positions.remove(widget_id);
                return true;
            }
        }
        return false;
    }

    /// Main render method with progressive enhancement
    pub fn render(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        const start_time = std.time.milliTimestamp();
        defer {
            const render_time = std.time.milliTimestamp() - start_time;
            self.performance_stats.update(@as(u32, @intCast(render_time)));
            self.last_frame_time = render_time;

            // Adaptive quality adjustment
            if (self.config.adaptive_quality and self.config.fallback_on_slow_render) {
                if (self.performance_stats.shouldDowngrade(self.config.max_render_time_ms)) {
                    self.downgradeRenderMode();
                }
            }
        }

        self.bounds = ctx.bounds;
        self.layout.recalculate(ctx.bounds, self.config);

        // Clear screen
        try renderer.clear(ctx.bounds);

        // Render title if present
        if (self.config.title) |title| {
            const title_ctx = RenderContext{
                .bounds = Bounds.init(ctx.bounds.x, ctx.bounds.y, ctx.bounds.width, 1),
                .style = renderer_mod.Style{ .bold = true },
                .zIndex = ctx.zIndex + 1,
                .clipRegion = ctx.clipRegion,
            };
            try renderer.drawText(title_ctx, title);
        }

        // Render widgets based on current mode
        const content_bounds = Bounds.init(
            ctx.bounds.x,
            ctx.bounds.y + if (self.config.title != null) @as(i32, 2) else 0,
            ctx.bounds.width,
            ctx.bounds.height - if (self.config.title != null) @as(u32, 2) else 0,
        );

        try self.renderWidgets(renderer, content_bounds);

        // Render performance info if in debug mode
        if (self.config.adaptive_quality) {
            try self.renderPerformanceInfo(renderer, ctx);
        }
    }

    /// Render all widgets with appropriate method for current render mode
    fn renderWidgets(self: *Self, renderer: *Renderer, bounds: Bounds) !void {
        for (self.widgets.items) |widget| {
            const widget_id = switch (widget) {
                .chart => |c| c.id,
                .table => |t| t.id,
                .text => |txt| txt.id,
                .metric => |m| m.id,
                .progress => |p| p.id,
                .notification => |n| n.id,
            };

            if (self.layout.widget_positions.get(widget_id)) |widget_bounds| {
                const widget_ctx = RenderContext{
                    .bounds = widget_bounds,
                    .style = renderer_mod.Style{},
                    .z_index = 0,
                    .clip_region = bounds,
                };

                try self.renderWidget(renderer, widget, widget_ctx);
            }
        }
    }

    /// Render an individual widget
    fn renderWidget(self: *Self, renderer: *Renderer, widget: Widget, ctx: RenderContext) !void {
        switch (widget) {
            .chart => |chart_widget| {
                // Update chart data if callback provided
                if (chart_widget.update_callback) |callback| {
                    // Note: This is a conceptual callback - in reality, chart is not mutable here
                    _ = callback;
                }

                // Render based on capabilities
                switch (self.render_mode) {
                    .full_graphics => {
                        // Use adapter's advanced chart rendering
                        const dummy_data = [_]f64{ 1.0, 2.0, 3.0, 2.5, 4.0 };
                        const chart_style = terminal_adapter.ChartStyle{
                            .line_color = .{ .rgb = .{ .r = 100, .g = 149, .b = 237 } },
                            .show_grid = true,
                        };
                        try self.adapter.renderChart(&dummy_data, chart_style, ctx.bounds);
                    },
                    else => {
                        // Fallback to basic chart rendering
                        try chart_widget.chart.render(renderer, ctx);
                    },
                }
            },
            .table => |table_widget| {
                try table_widget.table.render(renderer, ctx);
            },
            .text => |text_widget| {
                try self.renderTextWidget(renderer, text_widget, ctx);
            },
            .metric => |metric_widget| {
                try self.renderMetricWidget(renderer, metric_widget, ctx);
            },
            .progress => |progress_widget| {
                try self.renderProgressWidget(renderer, progress_widget, ctx);
            },
            .notification => |notif_widget| {
                try self.renderNotificationWidget(renderer, notif_widget, ctx);
            },
        }
    }

    /// Render text widget
    fn renderTextWidget(self: *Self, renderer: *Renderer, widget: Widget.TextWidget, ctx: RenderContext) !void {
        _ = self;

        // Title
        const title_ctx = RenderContext{
            .bounds = Bounds.init(ctx.bounds.x, ctx.bounds.y, ctx.bounds.width, 1),
            .style = renderer_mod.Style{ .bold = true },
            .z_index = ctx.z_index,
            .clip_region = ctx.clip_region,
        };
        try renderer.drawText(title_ctx, widget.title);

        // Content
        const content_ctx = RenderContext{
            .bounds = Bounds.init(ctx.bounds.x, ctx.bounds.y + 1, ctx.bounds.width, ctx.bounds.height - 1),
            .style = switch (widget.style) {
                .normal => renderer_mod.Style{},
                .bold => renderer_mod.Style{ .bold = true },
                .italic => renderer_mod.Style{ .italic = true },
                .highlight => renderer_mod.Style{ .bg_color = .{ .palette = 11 } },
            },
            .z_index = ctx.z_index,
            .clip_region = ctx.clip_region,
        };
        try renderer.drawText(content_ctx, widget.content);
    }

    /// Render metric widget with trend indicators
    fn renderMetricWidget(self: *Self, renderer: *Renderer, widget: Widget.MetricWidget, ctx: RenderContext) !void {
        // Label
        const label_ctx = RenderContext{
            .bounds = Bounds.init(ctx.bounds.x, ctx.bounds.y, ctx.bounds.width, 1),
            .style = renderer_mod.Style{},
            .z_index = ctx.z_index,
            .clip_region = ctx.clip_region,
        };
        try renderer.drawText(label_ctx, widget.label);

        // Format value
        var buffer: [256]u8 = undefined;
        const formatted_value = switch (widget.format) {
            .number => try std.fmt.bufPrint(buffer[0..], "{d:.2}", .{widget.value}),
            .currency => try std.fmt.bufPrint(buffer[0..], "${d:.2}", .{widget.value}),
            .percentage => try std.fmt.bufPrint(buffer[0..], "{d:.1}%", .{widget.value * 100}),
            .bytes => blk: {
                if (widget.value < 1024) {
                    break :blk try std.fmt.bufPrint(buffer[0..], "{d:.0} B", .{widget.value});
                } else if (widget.value < 1024 * 1024) {
                    break :blk try std.fmt.bufPrint(buffer[0..], "{d:.1} KB", .{widget.value / 1024});
                } else {
                    break :blk try std.fmt.bufPrint(buffer[0..], "{d:.1} MB", .{widget.value / (1024 * 1024)});
                }
            },
        };

        // Add unit if provided
        const final_value = if (widget.unit) |unit|
            try std.fmt.bufPrint(buffer[128..], "{s} {s}", .{ formatted_value, unit })
        else
            formatted_value;

        // Value with trend
        const trend_symbol = if (widget.trend) |trend| switch (trend) {
            .up => "↗ ",
            .down => "↘ ",
            .flat => "→ ",
        } else "";

        const value_text = try std.fmt.bufPrint(buffer[200..], "{s}{s}", .{ trend_symbol, final_value });

        const value_ctx = RenderContext{
            .bounds = Bounds.init(ctx.bounds.x, ctx.bounds.y + 1, ctx.bounds.width, 1),
            .style = renderer_mod.Style{ .bold = true },
            .z_index = ctx.z_index,
            .clip_region = ctx.clip_region,
        };
        try renderer.drawText(value_ctx, value_text);

        _ = self;
    }

    /// Render progress widget
    fn renderProgressWidget(self: *Self, renderer: *Renderer, widget: Widget.ProgressWidget, ctx: RenderContext) !void {
        // Label
        const label_ctx = RenderContext{
            .bounds = Bounds.init(ctx.bounds.x, ctx.bounds.y, ctx.bounds.width, 1),
            .style = renderer_mod.Style{},
            .z_index = ctx.z_index,
            .clip_region = ctx.clip_region,
        };
        try renderer.drawText(label_ctx, widget.label);

        // Progress bar
        const progress_width = @as(u32, @intCast(ctx.bounds.width)) - 10; // Reserve space for percentage
        const filled_width = @as(u32, @intFromFloat(@as(f64, @floatFromInt(progress_width)) * widget.progress));

        // Draw progress bar based on terminal capabilities
        const bar_ctx = RenderContext{
            .bounds = Bounds.init(ctx.bounds.x, ctx.bounds.y + 1, @intCast(progress_width), 1),
            .style = renderer_mod.Style{},
            .z_index = ctx.z_index,
            .clip_region = ctx.clip_region,
        };

        switch (self.render_mode) {
            .full_graphics, .enhanced_unicode => {
                // Use Unicode blocks for smooth progress
                var bar_buffer: [256]u8 = undefined;
                var i: u32 = 0;
                while (i < progress_width and i < bar_buffer.len) : (i += 1) {
                    if (i < filled_width) {
                        bar_buffer[i] = '█';
                    } else {
                        bar_buffer[i] = '░';
                    }
                }
                try renderer.drawText(bar_ctx, bar_buffer[0..@min(progress_width, bar_buffer.len)]);
            },
            else => {
                // ASCII fallback
                var bar_buffer: [256]u8 = undefined;
                var i: u32 = 0;
                while (i < progress_width and i < bar_buffer.len) : (i += 1) {
                    if (i < filled_width) {
                        bar_buffer[i] = '#';
                    } else {
                        bar_buffer[i] = '-';
                    }
                }
                try renderer.drawText(bar_ctx, bar_buffer[0..@min(progress_width, bar_buffer.len)]);
            },
        }

        // Percentage
        if (widget.show_percentage) {
            var percent_buffer: [16]u8 = undefined;
            const percent_text = try std.fmt.bufPrint(percent_buffer[0..], "{d:.0}%", .{widget.progress * 100});

            const percent_ctx = RenderContext{
                .bounds = Bounds.init(ctx.bounds.x + @as(i32, @intCast(progress_width)) + 1, ctx.bounds.y + 1, 10, 1),
                .style = renderer_mod.Style{},
                .z_index = ctx.z_index,
                .clip_region = ctx.clip_region,
            };
            try renderer.drawText(percent_ctx, percent_text);
        }
    }

    /// Render notification widget
    fn renderNotificationWidget(self: *Self, renderer: *Renderer, widget: Widget.NotificationWidget, ctx: RenderContext) !void {
        // Use adapter's smart notification system
        try self.adapter.showNotification("Dashboard", widget.message, widget.level);

        // Also render in-place for immediate feedback
        const style = renderer_mod.Style{
            .fg_color = switch (widget.level) {
                .info => .{ .palette = 12 },
                .success => .{ .palette = 10 },
                .warning => .{ .palette = 11 },
                .error_ => .{ .palette = 9 },
                .debug => .{ .palette = 13 },
            },
        };

        const notif_ctx = RenderContext{
            .bounds = ctx.bounds,
            .style = style,
            .z_index = ctx.z_index + 100, // High z-index for notifications
            .clip_region = ctx.clip_region,
        };

        const icon = widget.level.getIcon();
        var message_buffer: [256]u8 = undefined;
        const full_message = try std.fmt.bufPrint(message_buffer[0..], "{s} {s}", .{ icon, widget.message });

        try renderer.drawText(notif_ctx, full_message);
    }

    /// Render performance information
    fn renderPerformanceInfo(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        var perf_buffer: [256]u8 = undefined;
        const perf_text = try std.fmt.bufPrint(perf_buffer[0..], "Render: {d:.1}ms | Widgets: {d} | Mode: {s}", .{ self.performance_stats.average_render_time_ms, self.widgets.items.len, @tagName(self.render_mode) });

        const perf_ctx = RenderContext{
            .bounds = Bounds.init(ctx.bounds.x, ctx.bounds.y + ctx.bounds.height - 1, ctx.bounds.width, 1),
            .style = renderer_mod.Style{ .fg_color = .{ .palette = 8 } }, // Dim color
            .z_index = ctx.z_index + 1,
            .clip_region = ctx.clip_region,
        };

        try renderer.drawText(perf_ctx, perf_text);
    }

    /// Downgrade render mode for performance
    fn downgradeRenderMode(self: *Self) void {
        self.render_mode = switch (self.render_mode) {
            .full_graphics => .enhanced_unicode,
            .enhanced_unicode => .basic_ascii,
            .basic_ascii => .text_only,
            .text_only => .text_only, // Already at lowest
        };
    }

    /// Handle input events for interactive dashboard
    pub fn handleInput(self: *Self, event: anytype) !bool {
        _ = self;
        _ = event;
        // TODO: Implement interactive event handling
        return false;
    }

    /// Update dashboard with new data
    pub fn update(self: *Self) !void {
        for (self.widgets.items) |*widget| {
            switch (widget.*) {
                .chart => |*chart_widget| {
                    if (chart_widget.update_callback) |callback| {
                        callback(&chart_widget.chart);
                    }
                },
                .table => |*table_widget| {
                    if (table_widget.update_callback) |callback| {
                        callback(&table_widget.table);
                    }
                },
                else => {}, // Static widgets don't need updates
            }
        }
    }
};

//! Performance Metrics Renderer
//!
//! Renders performance metrics including API latency, token usage,
//! rate limits, and various charts (sparklines, gauges, bars).

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import dependencies
const state = @import("../state.zig");
const layout = @import("../layout.zig");
const theme = @import("../../../../theme/mod.zig");
const term_mod = @import("../../../../term/mod.zig");
const render_mod = @import("../../../../render/mod.zig");

// Type aliases
const PerformanceMetrics = state.PerformanceMetrics;
const DashboardStore = state.DashboardStore;
const Rect = layout.Rect;

/// Configuration for metrics rendering
pub const MetricsConfig = struct {
    /// Show CPU usage
    show_cpu: bool = true,

    /// Show memory usage
    show_memory: bool = true,

    /// Show network I/O
    show_network: bool = true,

    /// Show API latency
    show_latency: bool = true,

    /// Chart type for visualizations
    chart_type: ChartType = .sparkline,

    /// Update interval in milliseconds
    update_interval_ms: u64 = 1000,

    /// Number of data points to keep for charts
    history_size: usize = 60,

    /// Show percentage labels
    show_labels: bool = true,

    /// Use colors for charts
    use_colors: bool = true,
};

/// Chart types for metrics visualization
pub const ChartType = enum {
    sparkline,
    bar_chart,
    line_chart,
    gauge,
    histogram,
};

/// Metrics renderer
pub const MetricsRenderer = struct {
    allocator: Allocator,
    config: MetricsConfig,
    history: MetricsHistory,
    last_update: i64 = 0,

    const Self = @This();

    pub fn init(allocator: Allocator, config: MetricsConfig) !Self {
        return .{
            .allocator = allocator,
            .config = config,
            .history = try MetricsHistory.init(allocator, config.history_size),
        };
    }

    pub fn deinit(self: *Self) void {
        self.history.deinit();
    }

    /// Render the metrics panel
    pub fn render(
        self: *Self,
        writer: anytype,
        bounds: Rect,
        data_store: *const DashboardStore,
        theme: *const theme.ColorScheme,
    ) !void {
        // Update history with current metrics
        try self.history.add(data_store.metrics);

        // Draw panel border
        try self.renderBorder(writer, bounds, theme);

        // Draw title bar
        try self.renderTitleBar(writer, bounds, theme);

        // Calculate content area
        const content_bounds = Rect{
            .x = bounds.x + 1,
            .y = bounds.y + 2,
            .width = bounds.width - 2,
            .height = bounds.height - 3,
        };

        // Render metrics based on configuration
        var y_offset: u16 = 0;

        if (self.config.show_cpu) {
            try self.renderMetric(
                writer,
                content_bounds,
                y_offset,
                "CPU",
                data_store.metrics.cpu_percent,
                .percent,
                theme,
            );
            y_offset += 3;
        }

        if (self.config.show_memory) {
            try self.renderMetric(
                writer,
                content_bounds,
                y_offset,
                "Memory",
                data_store.metrics.mem_percent,
                .percent,
                theme,
            );
            y_offset += 3;
        }

        if (self.config.show_network) {
            try self.renderNetworkMetrics(
                writer,
                content_bounds,
                y_offset,
                data_store.metrics,
                theme,
            );
            y_offset += 4;
        }

        if (self.config.show_latency) {
            try self.renderLatency(
                writer,
                content_bounds,
                y_offset,
                data_store.metrics.latency_ms,
                theme,
            );
        }
    }

    /// Render panel border
    fn renderBorder(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        theme: *const theme.ColorScheme,
    ) !void {
        _ = self;

        const box_chars = if (theme.use_unicode)
            term_mod.BoxDrawing.rounded
        else
            term_mod.BoxDrawing.ascii;

        try term_mod.drawBox(writer, bounds, box_chars, theme.border);
    }

    /// Render title bar
    fn renderTitleBar(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        theme: *const theme.ColorScheme,
    ) !void {
        _ = self;

        try term_mod.moveTo(writer, bounds.x + 2, bounds.y);
        try term_mod.setStyle(writer, .{ .bold = true, .foreground = theme.title });
        try writer.writeAll(" Performance Metrics ");
        try term_mod.resetStyle(writer);
    }

    /// Render a single metric with visualization
    fn renderMetric(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        label: []const u8,
        value: f32,
        unit: MetricUnit,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));

        // Draw label
        try term_mod.moveTo(writer, bounds.x, y);
        try term_mod.setStyle(writer, .{ .foreground = theme.foreground });
        try writer.print("{s:>8}: ", .{label});

        // Draw value
        const color = self.getColorForValue(value, unit, theme);
        try term_mod.setStyle(writer, .{ .foreground = color });

        switch (unit) {
            .percent => try writer.print("{d:6.1}%", .{value}),
            .milliseconds => try writer.print("{d:6}ms", .{@as(u64, @intFromFloat(value))}),
            .kilobytes => try writer.print("{d:6.1}KB", .{value}),
            .count => try writer.print("{d:6}", .{@as(u64, @intFromFloat(value))}),
        }

        // Draw visualization
        const viz_width = bounds.width - 20;
        if (viz_width > 5) {
            try term_mod.moveTo(writer, bounds.x + 18, y);
            try self.renderVisualization(writer, value, viz_width, unit, theme);
        }

        try term_mod.resetStyle(writer);
    }

    /// Render network metrics (in/out)
    fn renderNetworkMetrics(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        metrics: PerformanceMetrics,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));

        // Network IN
        try term_mod.moveTo(writer, bounds.x, y);
        try term_mod.setStyle(writer, .{ .foreground = theme.foreground });
        try writer.writeAll(" Net IN: ");
        try term_mod.setStyle(writer, .{ .foreground = theme.success });
        try writer.print("{d:6.1} KB/s", .{metrics.net_in_kbps});

        // Network OUT
        try term_mod.moveTo(writer, bounds.x, y + 1);
        try term_mod.setStyle(writer, .{ .foreground = theme.foreground });
        try writer.writeAll("Net OUT: ");
        try term_mod.setStyle(writer, .{ .foreground = theme.info });
        try writer.print("{d:6.1} KB/s", .{metrics.net_out_kbps});

        // Combined sparkline if space permits
        const viz_width = bounds.width - 20;
        if (viz_width > 10) {
            try term_mod.moveTo(writer, bounds.x + 18, y);
            try self.renderDualSparkline(
                writer,
                metrics.net_in_kbps,
                metrics.net_out_kbps,
                viz_width,
                theme,
            );
        }

        try term_mod.resetStyle(writer);
    }

    /// Render latency metric
    fn renderLatency(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        latency_ms: u64,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));

        try term_mod.moveTo(writer, bounds.x, y);
        try term_mod.setStyle(writer, .{ .foreground = theme.foreground });
        try writer.writeAll("Latency: ");

        // Color based on latency
        const color = if (latency_ms < 100)
            theme.success
        else if (latency_ms < 500)
            theme.warning
        else
            theme.@"error";

        try term_mod.setStyle(writer, .{ .foreground = color });
        try writer.print("{d:6}ms", .{latency_ms});

        // Draw latency histogram
        const viz_width = bounds.width - 20;
        if (viz_width > 5 and self.history.latency_history.items.len > 0) {
            try term_mod.moveTo(writer, bounds.x + 18, y);
            try self.renderLatencyHistogram(writer, viz_width, theme);
        }

        try term_mod.resetStyle(writer);
    }

    /// Render visualization based on chart type
    fn renderVisualization(
        self: *const Self,
        writer: anytype,
        value: f32,
        width: u16,
        unit: MetricUnit,
        theme: *const theme.ColorScheme,
    ) !void {
        switch (self.config.chart_type) {
            .sparkline => try self.renderSparkline(writer, value, width, unit, theme),
            .bar_chart => try self.renderBar(writer, value, width, unit, theme),
            .gauge => try self.renderGauge(writer, value, width, unit, theme),
            else => try self.renderBar(writer, value, width, unit, theme),
        }
    }

    /// Render a sparkline chart
    fn renderSparkline(
        self: *const Self,
        writer: anytype,
        current_value: f32,
        width: u16,
        unit: MetricUnit,
        theme: *const theme.ColorScheme,
    ) !void {
        _ = current_value;

        const sparkline_chars = [_][]const u8{ " ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };

        // Get history for this metric type
        const history = switch (unit) {
            .percent => self.history.cpu_history.items, // Could be cpu or memory
            .milliseconds => self.history.latency_history.items,
            else => &[_]f32{},
        };

        if (history.len == 0) return;

        // Calculate how many data points to show
        const points_to_show = @min(width, history.len);
        const start = if (history.len > points_to_show)
            history.len - points_to_show
        else
            0;

        // Find min/max for normalization
        var min: f32 = history[start];
        var max: f32 = history[start];
        for (history[start..]) |val| {
            min = @min(min, val);
            max = @max(max, val);
        }

        if (max == min) max = min + 1.0; // Prevent division by zero

        // Render sparkline
        try term_mod.setStyle(writer, .{ .foreground = theme.accent });
        for (history[start..]) |val| {
            const normalized = (val - min) / (max - min);
            const index = @min(sparkline_chars.len - 1, @as(usize, @intFromFloat(normalized * @as(f32, @floatFromInt(sparkline_chars.len - 1)))));
            try writer.writeAll(sparkline_chars[index]);
        }
    }

    /// Render a horizontal bar
    fn renderBar(
        self: *const Self,
        writer: anytype,
        value: f32,
        width: u16,
        unit: MetricUnit,
        theme: *const theme.ColorScheme,
    ) !void {
        _ = self;

        const normalized = switch (unit) {
            .percent => value / 100.0,
            .milliseconds => @min(1.0, value / 1000.0), // Normalize to 1 second
            else => @min(1.0, value / 100.0),
        };

        const filled = @as(u16, @intFromFloat(@as(f32, @floatFromInt(width)) * normalized));

        // Choose color based on value
        const color = if (normalized < 0.5)
            theme.success
        else if (normalized < 0.8)
            theme.warning
        else
            theme.@"error";

        try term_mod.setStyle(writer, .{ .foreground = color });

        // Draw filled portion
        for (0..filled) |_| {
            try writer.writeAll("█");
        }

        // Draw empty portion
        try term_mod.setStyle(writer, .{ .foreground = theme.dim });
        for (filled..width) |_| {
            try writer.writeAll("░");
        }
    }

    /// Render a gauge visualization
    fn renderGauge(
        self: *const Self,
        writer: anytype,
        value: f32,
        width: u16,
        unit: MetricUnit,
        theme: *const theme.ColorScheme,
    ) !void {
        _ = self;

        const normalized = switch (unit) {
            .percent => value / 100.0,
            .milliseconds => @min(1.0, value / 1000.0),
            else => @min(1.0, value / 100.0),
        };

        const segments = @min(width, 10);
        const filled = @as(u16, @intFromFloat(@as(f32, @floatFromInt(segments)) * normalized));

        try writer.writeAll("[");

        for (0..segments) |i| {
            if (i < filled) {
                const color = if (i < segments * 5 / 10)
                    theme.success
                else if (i < segments * 8 / 10)
                    theme.warning
                else
                    theme.@"error";

                try term_mod.setStyle(writer, .{ .foreground = color });
                try writer.writeAll("●");
            } else {
                try term_mod.setStyle(writer, .{ .foreground = theme.dim });
                try writer.writeAll("○");
            }
        }

        try term_mod.setStyle(writer, .{ .foreground = theme.foreground });
        try writer.writeAll("]");
    }

    /// Render dual sparkline for network I/O
    fn renderDualSparkline(
        self: *const Self,
        writer: anytype,
        in_value: f32,
        out_value: f32,
        width: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        _ = self;
        _ = in_value;
        _ = out_value;

        // Simple placeholder for dual sparkline
        try term_mod.setStyle(writer, .{ .foreground = theme.success });
        try writer.writeAll("↓");

        for (0..width - 2) |_| {
            try writer.writeAll("▂");
        }

        try term_mod.setStyle(writer, .{ .foreground = theme.info });
        try writer.writeAll("↑");
    }

    /// Render latency histogram
    fn renderLatencyHistogram(
        self: *const Self,
        writer: anytype,
        width: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        const history = self.history.latency_history.items;
        if (history.len == 0) return;

        // Create histogram buckets
        const bucket_count = @min(width, 8);
        var buckets = try self.allocator.alloc(usize, bucket_count);
        defer self.allocator.free(buckets);
        @memset(buckets, 0);

        // Find min/max for bucket ranges
        var min: f32 = history[0];
        var max: f32 = history[0];
        for (history) |val| {
            min = @min(min, val);
            max = @max(max, val);
        }

        if (max == min) max = min + 1.0;

        // Fill buckets
        for (history) |val| {
            const normalized = (val - min) / (max - min);
            const bucket = @min(bucket_count - 1, @as(usize, @intFromFloat(normalized * @as(f32, @floatFromInt(bucket_count - 1)))));
            buckets[bucket] += 1;
        }

        // Find max bucket count for normalization
        var max_count: usize = 1;
        for (buckets) |count| {
            max_count = @max(max_count, count);
        }

        // Render histogram
        const bars = [_][]const u8{ " ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };

        for (buckets) |count| {
            const normalized = @as(f32, @floatFromInt(count)) / @as(f32, @floatFromInt(max_count));
            const bar_index = @as(usize, @intFromFloat(normalized * @as(f32, @floatFromInt(bars.len - 1))));

            try term_mod.setStyle(writer, .{ .foreground = theme.accent });
            try writer.writeAll(bars[bar_index]);
        }
    }

    /// Get color based on value and unit
    fn getColorForValue(
        self: *const Self,
        value: f32,
        unit: MetricUnit,
        theme: *const theme.ColorScheme,
    ) theme.Color {
        _ = self;

        switch (unit) {
            .percent => {
                if (value < 50) return theme.success;
                if (value < 80) return theme.warning;
                return theme.@"error";
            },
            .milliseconds => {
                if (value < 100) return theme.success;
                if (value < 500) return theme.warning;
                return theme.@"error";
            },
            else => return theme.foreground,
        }
    }
};

/// Metric units
const MetricUnit = enum {
    percent,
    milliseconds,
    kilobytes,
    count,
};

/// History tracking for metrics
const MetricsHistory = struct {
    allocator: Allocator,
    cpu_history: std.ArrayList(f32),
    memory_history: std.ArrayList(f32),
    network_in_history: std.ArrayList(f32),
    network_out_history: std.ArrayList(f32),
    latency_history: std.ArrayList(f32),
    max_size: usize,

    pub fn init(allocator: Allocator, max_size: usize) !MetricsHistory {
        return .{
            .allocator = allocator,
            .cpu_history = std.ArrayList(f32).init(allocator),
            .memory_history = std.ArrayList(f32).init(allocator),
            .network_in_history = std.ArrayList(f32).init(allocator),
            .network_out_history = std.ArrayList(f32).init(allocator),
            .latency_history = std.ArrayList(f32).init(allocator),
            .max_size = max_size,
        };
    }

    pub fn deinit(self: *MetricsHistory) void {
        self.cpu_history.deinit();
        self.memory_history.deinit();
        self.network_in_history.deinit();
        self.network_out_history.deinit();
        self.latency_history.deinit();
    }

    pub fn add(self: *MetricsHistory, metrics: PerformanceMetrics) !void {
        try self.addToHistory(&self.cpu_history, metrics.cpu_percent);
        try self.addToHistory(&self.memory_history, metrics.mem_percent);
        try self.addToHistory(&self.network_in_history, metrics.net_in_kbps);
        try self.addToHistory(&self.network_out_history, metrics.net_out_kbps);
        try self.addToHistory(&self.latency_history, @as(f32, @floatFromInt(metrics.latency_ms)));
    }

    fn addToHistory(self: *MetricsHistory, history: *std.ArrayList(f32), value: f32) !void {
        try history.append(value);

        // Remove oldest if we exceed max size
        if (history.items.len > self.max_size) {
            _ = history.orderedRemove(0);
        }
    }
};

/// Create a default metrics renderer
pub fn createDefault(allocator: Allocator) !*MetricsRenderer {
    const renderer = try allocator.create(MetricsRenderer);
    renderer.* = try MetricsRenderer.init(allocator, .{});
    return renderer;
}

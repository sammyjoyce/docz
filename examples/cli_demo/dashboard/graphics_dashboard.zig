//! Graphics-Enhanced Dashboard Component
//! Leverages advanced terminal graphics capabilities to display rich data visualizations
//! Features progressive enhancement: Kitty Graphics → Sixel → Unicode → ASCII

const std = @import("std");
const unified_terminal = @import("../core/unified_terminal.zig");
const rich_progress = @import("../../src/cli/components/base/rich_progress_bar.zig");

const Allocator = std.mem.Allocator;
const UnifiedTerminal = unified_terminal.UnifiedTerminal;
const Color = unified_terminal.Color;
const RichProgressBar = rich_progress.RichProgressBar;

/// Data point for dashboard metrics
pub const DataPoint = struct {
    timestamp: i64,
    value: f32,
    label: []const u8,
    category: []const u8,
};

/// Dashboard configuration options
pub const DashboardConfig = struct {
    width: u16 = 80,
    height: u16 = 24,
    title: []const u8 = "System Dashboard",
    show_legend: bool = true,
    show_grid: bool = true,
    update_interval_ms: u64 = 1000,
    max_data_points: usize = 100,
};

/// Graphics-enhanced dashboard that adapts to terminal capabilities
pub const GraphicsDashboard = struct {
    const Self = @This();

    allocator: Allocator,
    terminal: UnifiedTerminal,
    config: DashboardConfig,

    // Data storage
    data_sets: std.HashMap([]const u8, DataSet),
    metrics: std.HashMap([]const u8, Metric),

    // Visual components
    progress_bars: std.ArrayList(*RichProgressBar),

    // State
    last_update: i64,
    animation_frame: u32,

    const DataSet = struct {
        points: std.ArrayList(DataPoint),
        color: Color,
        style: ChartStyle,
    };

    const Metric = struct {
        name: []const u8,
        value: f32,
        unit: []const u8,
        trend: f32, // Positive = increasing, negative = decreasing
        color: Color,
    };

    pub const ChartStyle = enum {
        line,
        bar,
        area,
        sparkline,
        gauge,
    };

    pub fn init(allocator: Allocator, config: DashboardConfig) !Self {
        const terminal = try UnifiedTerminal.init(allocator);

        return Self{
            .allocator = allocator,
            .terminal = terminal,
            .config = config,
            .data_sets = std.HashMap([]const u8, DataSet).init(allocator),
            .metrics = std.HashMap([]const u8, Metric).init(allocator),
            .progress_bars = std.ArrayList(*RichProgressBar).init(allocator),
            .last_update = std.time.timestamp(),
            .animation_frame = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up progress bars
        for (self.progress_bars.items) |bar| {
            bar.deinit();
            self.allocator.destroy(bar);
        }
        self.progress_bars.deinit();

        // Clean up data sets
        var data_iter = self.data_sets.iterator();
        while (data_iter.next()) |entry| {
            entry.value_ptr.points.deinit();
        }
        self.data_sets.deinit();
        self.metrics.deinit();

        self.terminal.deinit();
    }

    /// Add or update a data set for visualization
    pub fn addDataSet(self: *Self, name: []const u8, color: Color, style: ChartStyle) !void {
        const key = try self.allocator.dupe(u8, name);
        try self.data_sets.put(key, DataSet{
            .points = std.ArrayList(DataPoint).init(self.allocator),
            .color = color,
            .style = style,
        });
    }

    /// Add data point to a specific set
    pub fn addDataPoint(self: *Self, set_name: []const u8, value: f32, label: []const u8) !void {
        if (self.data_sets.getPtr(set_name)) |data_set| {
            const now = std.time.timestamp();
            try data_set.points.append(DataPoint{
                .timestamp = now,
                .value = value,
                .label = try self.allocator.dupe(u8, label),
                .category = set_name,
            });

            // Limit data points to prevent memory growth
            if (data_set.points.items.len > self.config.max_data_points) {
                _ = data_set.points.orderedRemove(0);
            }
        }
    }

    /// Add or update a metric display
    pub fn addMetric(self: *Self, name: []const u8, value: f32, unit: []const u8, trend: f32, color: Color) !void {
        const key = try self.allocator.dupe(u8, name);
        try self.metrics.put(key, Metric{
            .name = key,
            .value = value,
            .unit = try self.allocator.dupe(u8, unit),
            .trend = trend,
            .color = color,
        });
    }

    /// Add a rich progress bar to the dashboard
    pub fn addProgressBar(self: *Self, label: []const u8, style: rich_progress.ProgressStyle, width: u32) !*RichProgressBar {
        const bar = try self.allocator.create(RichProgressBar);
        bar.* = RichProgressBar.init(self.allocator, style, width, label);

        // Connect graphics manager if available
        if (self.terminal.graphics) |graphics| {
            bar.setGraphicsManager(graphics);
        }

        try self.progress_bars.append(bar);
        return bar;
    }

    /// Render the complete dashboard with progressive enhancement
    pub fn render(self: *Self) !void {
        try self.terminal.beginSynchronizedOutput();
        defer self.terminal.endSynchronizedOutput() catch {};

        try self.terminal.clearScreen();
        self.animation_frame +%= 1;

        const size = self.terminal.getSize() orelse .{ .width = 80, .height = 24 };

        // Header with title and capabilities
        try self.renderHeader(size);

        // Metrics row
        try self.renderMetrics(size);

        // Charts and visualizations
        try self.renderCharts(size);

        // Progress bars
        try self.renderProgressBars(size);

        // Footer with status
        try self.renderFooter(size);
    }

    fn renderHeader(self: *Self, size: UnifiedTerminal.Size) !void {
        try self.terminal.moveCursor(1, 1);
        try self.terminal.setForeground(Color.CYAN);

        const w = self.terminal.writer();

        // Title with border
        const title_len = self.config.title.len;
        const padding = (size.width - title_len - 4) / 2;

        // Top border
        try w.writeByteNTimes('═', size.width);
        try w.writeByte('\n');

        // Title line
        try w.writeByteNTimes(' ', padding);
        try w.print("╣ {s} ╠", .{self.config.title});
        try w.writeByte('\n');

        // Capabilities line
        try self.terminal.resetStyles();
        try self.terminal.setForeground(Color.GRAY);
        try w.writeAll("  Features: ");

        if (self.terminal.hasFeature(.graphics)) {
            try self.terminal.setForeground(Color.GREEN);
            try w.writeAll("Graphics ");
        }
        if (self.terminal.hasFeature(.truecolor)) {
            try self.terminal.setForeground(Color.GREEN);
            try w.writeAll("TrueColor ");
        }
        if (self.terminal.hasFeature(.hyperlinks)) {
            try self.terminal.setForeground(Color.GREEN);
            try w.writeAll("Hyperlinks ");
        }
        if (self.terminal.hasFeature(.clipboard)) {
            try self.terminal.setForeground(Color.GREEN);
            try w.writeAll("Clipboard ");
        }

        try w.writeByte('\n');
        try self.terminal.resetStyles();

        // Separator
        try w.writeByteNTimes('─', size.width);
        try w.writeByte('\n');
    }

    fn renderMetrics(self: *Self, size: UnifiedTerminal.Size) !void {
        const w = self.terminal.writer();

        if (self.metrics.count() == 0) return;

        try self.terminal.setForeground(Color.YELLOW);
        try w.writeAll(" 📊 Metrics:\n");
        try self.terminal.resetStyles();

        const metrics_per_row = @min(4, size.width / 18);

        var count: usize = 0;
        var metric_iter = self.metrics.iterator();
        while (metric_iter.next()) |entry| {
            const metric = entry.value_ptr.*;

            if (count % metrics_per_row == 0 and count > 0) {
                try w.writeByte('\n');
            }

            try self.terminal.setForeground(metric.color);

            // Format metric with trend indicator
            const trend_indicator = if (metric.trend > 0.1) "↗" else if (metric.trend < -0.1) "↘" else "→";
            try w.print(" {s:<10} {d:.1}{s} {s} ", .{ metric.name, metric.value, metric.unit, trend_indicator });

            count += 1;
        }

        try w.writeByte('\n');
        try w.writeByteNTimes('─', size.width);
        try w.writeByte('\n');
        try self.terminal.resetStyles();
    }

    fn renderCharts(self: *Self, size: UnifiedTerminal.Size) !void {
        const w = self.terminal.writer();

        if (self.data_sets.count() == 0) return;

        const chart_height = @min(8, (size.height - 10) / 2);
        const chart_width = size.width - 4;

        var set_iter = self.data_sets.iterator();
        while (set_iter.next()) |entry| {
            const name = entry.key_ptr.*;
            const data_set = entry.value_ptr.*;

            if (data_set.points.items.len < 2) continue;

            try self.terminal.setForeground(data_set.color);
            try w.print(" 📈 {s}\n", .{name});
            try self.terminal.resetStyles();

            switch (data_set.style) {
                .sparkline => try self.renderSparkline(data_set, chart_width),
                .bar => try self.renderBarChart(data_set, chart_width, chart_height),
                .line => try self.renderLineChart(data_set, chart_width, chart_height),
                .area => try self.renderAreaChart(data_set, chart_width, chart_height),
                .gauge => try self.renderGauge(data_set, chart_width),
            }

            try w.writeByte('\n');
        }
    }

    fn renderSparkline(self: *Self, data_set: DataSet, width: u16) !void {
        const w = self.terminal.writer();
        const sparkline_chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };

        // Find min/max for normalization
        var min_val: f32 = std.math.floatMax(f32);
        var max_val: f32 = -std.math.floatMax(f32);

        for (data_set.points.items) |point| {
            min_val = @min(min_val, point.value);
            max_val = @max(max_val, point.value);
        }

        const range = max_val - min_val;
        if (range == 0) return;

        try w.writeAll("  ");

        const data_points = @min(width - 4, data_set.points.items.len);
        const start_idx = if (data_set.points.items.len > data_points)
            data_set.points.items.len - data_points
        else
            0;

        for (0..data_points) |i| {
            const point = data_set.points.items[start_idx + i];
            const normalized = (point.value - min_val) / range;
            const char_idx: usize = @intFromFloat(normalized * 7.0);

            try self.terminal.setForeground(data_set.color);
            try w.writeAll(sparkline_chars[@min(char_idx, sparkline_chars.len - 1)]);
        }

        try self.terminal.resetStyles();
        try w.print(" (min: {d:.1}, max: {d:.1})\n", .{ min_val, max_val });
    }

    fn renderBarChart(self: *Self, data_set: DataSet, width: u16, height: u16) !void {
        const w = self.terminal.writer();

        // Simplified bar chart using Unicode blocks
        const data_points = @min(width / 3, data_set.points.items.len);
        if (data_points == 0) return;

        const start_idx = if (data_set.points.items.len > data_points)
            data_set.points.items.len - data_points
        else
            0;

        // Find max for scaling
        var max_val: f32 = 0;
        for (start_idx..start_idx + data_points) |i| {
            max_val = @max(max_val, data_set.points.items[i].value);
        }

        if (max_val == 0) return;

        // Render bars
        for (0..height) |row| {
            try w.writeAll("  ");
            const threshold = ((@as(f32, @floatFromInt(height - row - 1))) / @as(f32, @floatFromInt(height))) * max_val;

            for (0..data_points) |i| {
                const point = data_set.points.items[start_idx + i];
                if (point.value >= threshold) {
                    try self.terminal.setForeground(data_set.color);
                    try w.writeAll("██ ");
                } else {
                    try w.writeAll("   ");
                }
            }
            try w.writeByte('\n');
        }

        try self.terminal.resetStyles();
    }

    fn renderLineChart(self: *Self, data_set: DataSet, width: u16, height: u16) !void {
        _ = height; // Unused in simplified implementation
        // Simplified line chart implementation
        try self.renderSparkline(data_set, width);
    }

    fn renderAreaChart(self: *Self, data_set: DataSet, width: u16, height: u16) !void {
        // Simplified area chart implementation (uses bar chart as base)
        try self.renderBarChart(data_set, width, height);
    }

    fn renderGauge(self: *Self, data_set: DataSet, width: u16) !void {
        _ = width; // Unused in simplified implementation
        const w = self.terminal.writer();

        if (data_set.points.items.len == 0) return;

        const latest = data_set.points.items[data_set.points.items.len - 1];
        const progress = std.math.clamp(latest.value / 100.0, 0.0, 1.0); // Assume 0-100 scale

        // Create circular gauge using Unicode characters
        const gauge_chars = [_][]const u8{ "○", "◔", "◑", "◕", "●" };
        const gauge_level: usize = @intFromFloat(progress * 4.0);

        try w.writeAll("  ");
        try self.terminal.setForeground(data_set.color);
        try w.print("{s} {d:.1}%", .{ gauge_chars[@min(gauge_level, gauge_chars.len - 1)], progress * 100.0 });
        try w.writeByte('\n');
        try self.terminal.resetStyles();
    }

    fn renderProgressBars(self: *Self, size: UnifiedTerminal.Size) !void {
        _ = size; // Size not used in current implementation
        const w = self.terminal.writer();

        if (self.progress_bars.items.len == 0) return;

        try self.terminal.setForeground(Color.MAGENTA);
        try w.writeAll(" ⚡ Progress Indicators:\n");
        try self.terminal.resetStyles();

        for (self.progress_bars.items) |bar| {
            try w.writeAll("  ");
            try bar.render(w);
            try w.writeByte('\n');
        }
    }

    fn renderFooter(self: *Self, size: UnifiedTerminal.Size) !void {
        const w = self.terminal.writer();

        try self.terminal.moveCursor(size.height - 1, 1);
        try self.terminal.setForeground(Color.GRAY);

        const now = std.time.timestamp();
        const uptime = now - self.last_update;

        try w.print(" Last update: {}s ago | Frame: {} | ", .{ uptime, self.animation_frame });

        // Show keyboard shortcuts
        if (self.terminal.hasFeature(.hyperlinks)) {
            try self.terminal.writeHyperlink("https://github.com/sam/docz", "GitHub");
        } else {
            try w.writeAll("q=quit r=refresh");
        }

        try self.terminal.resetStyles();
    }

    /// Update dashboard with new data
    pub fn update(self: *Self) !void {
        self.last_update = std.time.timestamp();
        try self.render();
    }

    /// Demo data generator for testing
    pub fn generateDemoData(self: *Self) !void {
        // Add some demo data sets
        try self.addDataSet("CPU Usage", Color.RED, .sparkline);
        try self.addDataSet("Memory", Color.BLUE, .bar);
        try self.addDataSet("Network", Color.GREEN, .line);
        try self.addDataSet("Disk I/O", Color.ORANGE, .gauge);

        // Add some demo metrics
        try self.addMetric("CPU", 45.2, "%", 2.1, Color.RED);
        try self.addMetric("Memory", 8.4, "GB", -0.1, Color.BLUE);
        try self.addMetric("Network", 125.8, "MB/s", 15.2, Color.GREEN);
        try self.addMetric("Disk", 85.0, "%", 0.0, Color.ORANGE);

        // Generate random data points
        const now = std.time.timestamp();
        var rng = std.rand.DefaultPrng.init(@as(u64, @intCast(now)));

        for (0..50) |i| {
            // Generate timestamp for demo data (not used in simplified version)
            _ = now - 50 + @as(i64, @intCast(i));

            // CPU data - oscillating around 45%
            const cpu_base: f32 = 45.0;
            const cpu_noise = (rng.random().float(f32) - 0.5) * 20.0;
            const cpu_value = std.math.clamp(cpu_base + cpu_noise, 0.0, 100.0);
            try self.addDataPoint("CPU Usage", cpu_value, "cpu");

            // Memory data - gradually increasing
            const mem_value = 60.0 + @as(f32, @floatFromInt(i)) * 0.5 + (rng.random().float(f32) - 0.5) * 10.0;
            try self.addDataPoint("Memory", std.math.clamp(mem_value, 0.0, 100.0), "mem");

            // Network data - spiky
            const net_value = rng.random().float(f32) * 200.0;
            try self.addDataPoint("Network", net_value, "net");

            // Disk I/O - steady
            const disk_value = 80.0 + (rng.random().float(f32) - 0.5) * 30.0;
            try self.addDataPoint("Disk I/O", std.math.clamp(disk_value, 0.0, 100.0), "disk");
        }

        // Add some progress bars
        const progress1 = try self.addProgressBar("Download Progress", .gradient, 40);
        try progress1.setProgress(0.65);

        const progress2 = try self.addProgressBar("System Health", .sparkline, 35);
        try progress2.setProgress(0.82);

        const progress3 = try self.addProgressBar("Task Queue", .animated, 30);
        try progress3.setProgress(0.38);
    }
};

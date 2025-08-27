const std = @import("std");
const adaptive_render = @import("../../src/render/mod.zig");
const AdaptiveRenderer = adaptive_render.AdaptiveRenderer;
const EnhancedRenderer = adaptive_render.EnhancedRenderer;
const Progress = adaptive_render.Progress;
const Table = adaptive_render.Table;
const Chart = adaptive_render.Chart;
const AnimatedProgress = adaptive_render.AnimatedProgress;
const Color = @import("../../src/shared/term/ansi/color.zig").Color;

/// Adaptive CLI that demonstrates enhanced terminal features
pub const AdaptiveCLI = struct {
    renderer: EnhancedRenderer,
    config: Config,

    pub const Config = struct {
        app_name: []const u8 = "Adaptive CLI",
        show_capabilities: bool = true,
        use_colors: bool = true,
        verbose: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !AdaptiveCLI {
        const renderer = try EnhancedRenderer.init(allocator);

        return AdaptiveCLI{
            .renderer = renderer,
            .config = config,
        };
    }

    pub fn deinit(self: *AdaptiveCLI) void {
        self.renderer.deinit();
    }

    /// Display welcome banner with capability information
    pub fn showBanner(self: *AdaptiveCLI) !void {
        const info = self.renderer.getRenderingInfo();

        // App name banner
        try self.renderer.writeText("🚀 ", Color.ansi(.bright_green), false);
        try self.renderer.writeText(self.config.app_name, Color.ansi(.bright_cyan), true);
        try self.renderer.writeText("\n", null, false);

        if (self.config.show_capabilities) {
            try self.renderer.writeText("─" ** 40, Color.ansi(.bright_black), false);
            try self.renderer.writeText("\n", null, false);

            try self.renderer.writeText("Terminal: ", null, false);
            try self.renderer.writeText(info.terminal_name, Color.ansi(.cyan), false);
            try self.renderer.writeText(" (", null, false);
            try self.renderer.writeText(info.mode.description(), Color.ansi(.yellow), false);
            try self.renderer.writeText(")\n", null, false);

            // Feature grid
            const features = [_]struct { name: []const u8, supported: bool, icon: []const u8 }{
                .{ .name = "True Color", .supported = info.supports_truecolor, .icon = "🎨" },
                .{ .name = "256 Colors", .supported = info.supports_256_color, .icon = "🌈" },
                .{ .name = "Unicode", .supported = info.supports_unicode, .icon = "📝" },
                .{ .name = "Graphics", .supported = info.supports_graphics, .icon = "🖼" },
                .{ .name = "Mouse", .supported = info.supports_mouse, .icon = "🖱" },
                .{ .name = "Synchronized", .supported = info.supports_synchronized, .icon = "⚡" },
            };

            try self.renderer.writeText("Features: ", null, false);
            for (features, 0..) |feature, i| {
                if (i > 0) try self.renderer.writeText(" ", null, false);

                const color = if (feature.supported) Color.ansi(.green) else Color.ansi(.red);
                const symbol = if (feature.supported) "✓" else "✗";

                try self.renderer.writeText(feature.icon, null, false);
                try self.renderer.writeText(symbol, color, false);
            }
            try self.renderer.writeText("\n\n", null, false);
        }
    }

    /// Show help information with adaptive formatting
    pub fn showHelp(self: *AdaptiveCLI) !void {
        try self.renderer.writeText("📚 Help\n", Color.ansi(.bright_blue), true);
        try self.renderer.writeText("─" ** 10, Color.ansi(.bright_black), false);
        try self.renderer.writeText("\n", null, false);

        const commands = [_]struct { name: []const u8, desc: []const u8, example: []const u8 }{
            .{ .name = "demo", .desc = "Run interactive demo", .example = "demo --all" },
            .{ .name = "progress", .desc = "Show progress examples", .example = "progress --animated" },
            .{ .name = "table", .desc = "Display data table", .example = "table data.csv" },
            .{ .name = "chart", .desc = "Generate charts", .example = "chart --type line data.json" },
            .{ .name = "monitor", .desc = "System monitoring", .example = "monitor --interval 1s" },
            .{ .name = "benchmark", .desc = "Performance benchmarks", .example = "benchmark --terminal" },
        };

        // Create help table
        const headers = [_][]const u8{ "Command", "Description", "Example" };
        const rows = std.ArrayList([]const []const u8).init(std.heap.page_allocator);
        defer rows.deinit();

        for (commands) |cmd| {
            const row = [_][]const u8{ cmd.name, cmd.desc, cmd.example };
            try rows.append(&row);
        }

        const table = Table{
            .headers = &headers,
            .rows = try rows.toOwnedSlice(),
            .title = "Available Commands",
            .column_alignments = &[_]Table.Alignment{ .left, .left, .left },
            .header_color = Color.ansi(.bright_cyan),
        };

        try self.renderer.renderTable(table);

        try self.renderer.writeText("\nUse ", null, false);
        try self.renderer.writeText("<command> --help", Color.ansi(.green), false);
        try self.renderer.writeText(" for detailed information.\n", null, false);
    }

    /// Demonstrate progress bars with different styles
    pub fn demoProgress(self: *AdaptiveCLI, animated: bool) !void {
        try self.renderer.writeText("📊 Progress Bar Demo\n", Color.ansi(.bright_blue), true);
        try self.renderer.writeText("─" ** 22, Color.ansi(.bright_black), false);
        try self.renderer.writeText("\n\n", null, false);

        if (animated) {
            // Animated progress demo
            const tasks = [_]struct { name: []const u8, color: Color, duration_ms: u64 }{
                .{ .name = "Initializing", .color = Color.ansi(.blue), .duration_ms = 1000 },
                .{ .name = "Processing data", .color = Color.ansi(.yellow), .duration_ms = 2000 },
                .{ .name = "Finalizing", .color = Color.ansi(.green), .duration_ms = 500 },
            };

            for (tasks) |task| {
                var progress = AnimatedProgress.init(&self.renderer.renderer, Progress{
                    .value = 0.0,
                    .label = task.name,
                    .show_percentage = true,
                    .show_eta = true,
                    .color = task.color,
                });

                const steps = 100;
                const step_duration = task.duration_ms * 1_000_000 / steps; // nanoseconds

                for (0..steps + 1) |i| {
                    const value = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
                    try progress.update(value);
                    std.time.sleep(step_duration);
                }

                try progress.finish();
                try self.renderer.writeText("\n", null, false);
            }
        } else {
            // Static progress examples
            const examples = [_]Progress{
                .{
                    .value = 0.1,
                    .label = "Download",
                    .show_percentage = true,
                    .color = Color.ansi(.red),
                },
                .{
                    .value = 0.5,
                    .label = "Install",
                    .show_percentage = true,
                    .show_eta = true,
                    .eta_seconds = 120,
                    .color = Color.ansi(.yellow),
                },
                .{
                    .value = 0.85,
                    .label = "Configure",
                    .show_percentage = true,
                    .color = Color.ansi(.blue),
                },
                .{
                    .value = 1.0,
                    .label = "Complete",
                    .show_percentage = true,
                    .color = Color.ansi(.green),
                },
            };

            for (examples) |progress| {
                try self.renderer.renderProgress(progress);
                try self.renderer.writeText("\n", null, false);
            }
        }
    }

    /// Display sample data table
    pub fn demoTable(self: *AdaptiveCLI) !void {
        try self.renderer.writeText("📋 Data Table Demo\n", Color.ansi(.bright_blue), true);
        try self.renderer.writeText("─" ** 20, Color.ansi(.bright_black), false);
        try self.renderer.writeText("\n\n", null, false);

        // Sample data
        const headers = [_][]const u8{ "Process", "PID", "CPU%", "Memory", "Status" };
        const row1 = [_][]const u8{ "adaptive-cli", "1234", "2.4", "45.2 MB", "Running" };
        const row2 = [_][]const u8{ "zig", "5678", "15.7", "128.1 MB", "Building" };
        const row3 = [_][]const u8{ "terminal", "9012", "1.1", "32.8 MB", "Idle" };
        const row4 = [_][]const u8{ "system-monitor", "3456", "0.8", "21.5 MB", "Running" };
        const rows = [_][]const []const u8{ &row1, &row2, &row3, &row4 };

        const alignments = [_]Table.Alignment{ .left, .right, .right, .right, .center };
        const row_colors = [_]?Color{
            Color.ansi(.green), // Running
            Color.ansi(.yellow), // Building
            Color.ansi(.bright_black), // Idle
            Color.ansi(.cyan), // Running
        };

        const table = Table{
            .headers = &headers,
            .rows = &rows,
            .title = "Process Monitor",
            .column_alignments = &alignments,
            .row_colors = &row_colors,
            .header_color = Color.ansi(.bright_cyan),
            .sortable = true,
        };

        try self.renderer.renderTable(table);
    }

    /// Display sample charts
    pub fn demoChart(self: *AdaptiveCLI, chart_type: Chart.ChartType) !void {
        try self.renderer.writeText("📈 Chart Demo\n", Color.ansi(.bright_blue), true);
        try self.renderer.writeText("─" ** 15, Color.ansi(.bright_black), false);
        try self.renderer.writeText("\n\n", null, false);

        // Generate sample data
        const data1 = [_]f64{ 10, 15, 12, 25, 20, 30, 28, 35, 32, 40, 38, 45 };
        const data2 = [_]f64{ 5, 8, 15, 12, 18, 22, 25, 20, 28, 30, 35, 38 };
        const data3 = [_]f64{ 2, 5, 8, 10, 12, 15, 18, 22, 25, 28, 30, 32 };

        const series = [_]Chart.DataSeries{
            .{
                .name = "Revenue",
                .data = &data1,
                .color = Color.ansi(.green),
                .style = .solid,
            },
            .{
                .name = "Expenses",
                .data = &data2,
                .color = Color.ansi(.red),
                .style = .dashed,
            },
            .{
                .name = "Profit",
                .data = &data3,
                .color = Color.ansi(.blue),
                .style = .dotted,
            },
        };

        const chart = Chart{
            .title = switch (chart_type) {
                .line => "Financial Performance (Line Chart)",
                .bar => "Quarterly Results (Bar Chart)",
                .area => "Growth Area Chart",
                .sparkline => "Quick Trend",
                else => "Chart Demo",
            },
            .data_series = &series,
            .chart_type = chart_type,
            .width = 70,
            .height = 20,
            .show_legend = true,
            .show_axes = true,
            .x_axis_label = "Month",
            .y_axis_label = "Amount ($k)",
        };

        try self.renderer.renderChart(chart);
    }

    /// Run system monitoring demo
    pub fn demoMonitor(self: *AdaptiveCLI, interval_ms: u64) !void {
        try self.renderer.writeText("🖥 System Monitor Demo\n", Color.ansi(.bright_blue), true);
        try self.renderer.writeText("─" ** 25, Color.ansi(.bright_black), false);
        try self.renderer.writeText("\n", null, false);
        try self.renderer.writeText("Press 'q' to quit\n\n", Color.ansi(.bright_black), false);

        var iteration: u32 = 0;

        while (iteration < 30) { // Limit for demo
            // Move to start of monitoring area
            try self.renderer.moveCursor(0, 4);

            // Generate fake system stats
            const cpu_usage = 0.2 + 0.3 * @sin(@as(f32, @floatFromInt(iteration)) * 0.1);
            const mem_usage = 0.4 + 0.2 * @cos(@as(f32, @floatFromInt(iteration)) * 0.05);
            const disk_usage = 0.15 + 0.05 * @sin(@as(f32, @floatFromInt(iteration)) * 0.03);

            const stats = [_]Progress{
                .{
                    .value = cpu_usage,
                    .label = "CPU Usage",
                    .show_percentage = true,
                    .color = if (cpu_usage > 0.8) Color.ansi(.red) else if (cpu_usage > 0.6) Color.ansi(.yellow) else Color.ansi(.green),
                },
                .{
                    .value = mem_usage,
                    .label = "Memory",
                    .show_percentage = true,
                    .color = if (mem_usage > 0.9) Color.ansi(.red) else if (mem_usage > 0.7) Color.ansi(.yellow) else Color.ansi(.blue),
                },
                .{
                    .value = disk_usage,
                    .label = "Disk I/O",
                    .show_percentage = true,
                    .color = Color.ansi(.cyan),
                },
            };

            for (stats) |stat| {
                try self.renderer.renderProgress(stat);
                try self.renderer.writeText("\n", null, false);
            }

            try self.renderer.writeText("\nIteration: ", null, false);
            const iter_text = try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{iteration + 1});
            defer std.heap.page_allocator.free(iter_text);
            try self.renderer.writeText(iter_text, Color.ansi(.yellow), false);

            try self.renderer.flush();

            // Check for input (simplified)
            std.time.sleep(interval_ms * 1_000_000);
            iteration += 1;
        }

        try self.renderer.writeText("\n\nMonitoring demo complete.\n", Color.ansi(.green), false);
    }

    /// Benchmark terminal performance
    pub fn demoBenchmark(self: *AdaptiveCLI) !void {
        try self.renderer.writeText("⚡ Terminal Performance Benchmark\n", Color.ansi(.bright_blue), true);
        try self.renderer.writeText("─" ** 40, Color.ansi(.bright_black), false);
        try self.renderer.writeText("\n\n", null, false);

        const info = self.renderer.getRenderingInfo();

        // Benchmark different operations
        const benchmarks = [_]struct { name: []const u8, operation: fn (*AdaptiveCLI) anyerror!u64 }{
            .{ .name = "Progress Bar Rendering", .operation = benchmarkProgress },
            .{ .name = "Table Rendering", .operation = benchmarkTable },
            .{ .name = "Chart Rendering", .operation = benchmarkChart },
            .{ .name = "Text Output", .operation = benchmarkText },
        };

        var results = std.ArrayList([]const u8).init(std.heap.page_allocator);
        defer {
            for (results.items) |item| {
                std.heap.page_allocator.free(item);
            }
            results.deinit();
        }

        for (benchmarks) |benchmark| {
            try self.renderer.writeText("Running: ", null, false);
            try self.renderer.writeText(benchmark.name, Color.ansi(.cyan), false);
            try self.renderer.writeText("... ", null, false);

            const start_time = std.time.nanoTimestamp();
            const operations = try benchmark.operation(self);
            const end_time = std.time.nanoTimestamp();

            const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
            const ops_per_sec = @as(f64, @floatFromInt(operations)) / (duration_ms / 1000.0);

            const result = try std.fmt.allocPrint(std.heap.page_allocator, "{s}: {d:.2} ms, {d:.0} ops/sec", .{ benchmark.name, duration_ms, ops_per_sec });
            try results.append(result);

            try self.renderer.writeText("Done\n", Color.ansi(.green), false);
        }

        try self.renderer.writeText("\n📊 Benchmark Results:\n", Color.ansi(.bright_green), true);
        try self.renderer.writeText("─" ** 20, Color.ansi(.bright_black), false);
        try self.renderer.writeText("\n", null, false);

        for (results.items) |result| {
            try self.renderer.writeText("  • ", Color.ansi(.bright_blue), false);
            try self.renderer.writeText(result, null, false);
            try self.renderer.writeText("\n", null, false);
        }

        try self.renderer.writeText("\nTerminal Mode: ", null, false);
        try self.renderer.writeText(info.mode.description(), Color.ansi(.yellow), true);
        try self.renderer.writeText("\n", null, false);
    }

    fn benchmarkProgress(self: *AdaptiveCLI) !u64 {
        const iterations = 1000;
        for (0..iterations) |i| {
            const progress = Progress{
                .value = @as(f32, @floatFromInt(i % 100)) / 100.0,
                .label = "Benchmark",
                .show_percentage = true,
            };
            try self.renderer.renderProgress(progress);
        }
        return iterations;
    }

    fn benchmarkTable(self: *AdaptiveCLI) !u64 {
        const iterations = 100;
        const headers = [_][]const u8{ "Col1", "Col2", "Col3" };
        const row = [_][]const u8{ "A", "B", "C" };
        const rows = [_][]const []const u8{&row};

        const table = Table{
            .headers = &headers,
            .rows = &rows,
        };

        for (0..iterations) |_| {
            try self.renderer.renderTable(table);
        }
        return iterations;
    }

    fn benchmarkChart(self: *AdaptiveCLI) !u64 {
        const iterations = 50;
        const data = [_]f64{ 1.0, 2.0, 3.0 };
        const series = Chart.DataSeries{ .name = "Test", .data = &data };
        const chart = Chart{ .data_series = &[_]Chart.DataSeries{series} };

        for (0..iterations) |_| {
            try self.renderer.renderChart(chart);
        }
        return iterations;
    }

    fn benchmarkText(self: *AdaptiveCLI) !u64 {
        const iterations = 5000;
        for (0..iterations) |_| {
            try self.renderer.writeText("Benchmark text output\n", null, false);
        }
        return iterations;
    }
};

// Tests
test "adaptive CLI" {
    const testing = std.testing;

    var cli = try AdaptiveCLI.init(testing.allocator, .{});
    defer cli.deinit();

    try cli.showBanner();
    try cli.showHelp();
    try cli.demoProgress(false);
    try cli.demoTable();
    try cli.demoChart(.line);
}

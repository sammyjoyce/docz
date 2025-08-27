const std = @import("std");
const AdaptiveRenderer = @import("adaptive_renderer.zig").AdaptiveRenderer;
const RenderMode = AdaptiveRenderer.RenderMode;
const Progress = @import("components/ProgressBar.zig").Progress;
const renderProgress = @import("components/ProgressBar.zig").renderProgress;
const AnimatedProgress = @import("components/ProgressBar.zig").AnimatedProgress;
const Table = @import("components/Table.zig").Table;
const renderTable = @import("components/Table.zig").renderTable;
const Chart = @import("components/Chart.zig").Chart;
const renderChart = @import("components/Chart.zig").renderChart;
const Color = @import("../term/ansi/color.zig").Color;

/// Comprehensive demo showcasing all adaptive rendering features
pub fn runDemo(allocator: std.mem.Allocator) !void {
    // Initialize adaptive renderer with automatic capability detection
    const renderer = try AdaptiveRenderer.init(allocator);
    defer renderer.deinit();

    // Clear screen and show header
    try renderer.clearScreen();
    try renderer.moveCursor(0, 0);

    // Show rendering info
    const info = renderer.getRenderingInfo();
    try renderer.writeText("🎨 Adaptive Rendering System Demo\n", Color.ansi(.bright_cyan), true);
    try renderer.writeText("=" ** 50, null, false);
    try renderer.writeText("\n\n", null, false);

    try renderer.writeText("Terminal Capabilities:\n", Color.ansi(.yellow), true);
    try renderer.writeText("  Mode: ", null, false);
    try renderer.writeText(info.mode.description(), Color.ansi(.green), false);
    try renderer.writeText("\n", null, false);
    try renderer.writeText("  Terminal: ", null, false);
    try renderer.writeText(info.terminal_name, Color.ansi(.cyan), false);
    try renderer.writeText("\n", null, false);
    try renderer.writeText("  Features: ", null, false);

    const features = [_]struct { name: []const u8, supported: bool }{
        .{ .name = "True Color", .supported = info.supports_truecolor },
        .{ .name = "256 Colors", .supported = info.supports_256_color },
        .{ .name = "Unicode", .supported = info.supports_unicode },
        .{ .name = "Graphics", .supported = info.supports_graphics },
        .{ .name = "Mouse", .supported = info.supports_mouse },
        .{ .name = "Synchronized", .supported = info.supports_synchronized },
    };

    for (features, 0..) |feature, i| {
        if (i > 0) try renderer.writeText(" | ", null, false);
        const color = if (feature.supported) Color.ansi(.green) else Color.ansi(.red);
        const symbol = if (feature.supported) "✓" else "✗";
        try renderer.writeText(symbol, color, false);
        try renderer.writeText(" ", null, false);
        try renderer.writeText(feature.name, null, false);
    }

    try renderer.writeText("\n\n", null, false);
    try renderer.writeText("Press Enter to continue...", Color.ansi(.bright_black), false);
    var stdin_buffer: [1]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;
    _ = try stdin.readByte();

    // Demo 1: Progress Bars
    try demoProgressBars(renderer);

    // Demo 2: Tables
    try demoTables(renderer);

    // Demo 3: Charts
    try demoCharts(renderer);

    // Demo 4: Animated Progress
    try demoAnimatedProgress(renderer);

    // Demo 5: All render modes comparison
    try demoRenderModeComparison(allocator);

    // Final message
    try renderer.clearScreen();
    try renderer.moveCursor(0, 0);
    try renderer.writeText("🎉 Adaptive Rendering System Demo Complete!\n\n", Color.ansi(.bright_green), true);
    try renderer.writeText("The system successfully adapted to your terminal's capabilities\n", null, false);
    try renderer.writeText("and provided the best possible visual experience.\n\n", null, false);
    try renderer.writeText("Features demonstrated:\n", Color.ansi(.yellow), true);
    try renderer.writeText("  • Automatic capability detection\n", null, false);
    try renderer.writeText("  • Progressive enhancement\n", null, false);
    try renderer.writeText("  • Multiple quality tiers\n", null, false);
    try renderer.writeText("  • Caching system\n", null, false);
    try renderer.writeText("  • Component-based architecture\n", null, false);

    try renderer.flush();
}

/// Demo progress bars with different configurations
fn demoProgressBars(renderer: *AdaptiveRenderer) !void {
    try renderer.clearScreen();
    try renderer.moveCursor(0, 0);

    try renderer.writeText("📊 Progress Bar Demonstration\n", Color.ansi(.bright_blue), true);
    try renderer.writeText("=" ** 40, null, false);
    try renderer.writeText("\n\n", null, false);

    const progress_examples = [_]Progress{
        .{
            .value = 0.25,
            .label = "Download",
            .showPercentage = true,
            .color = Color.ansi(.blue),
        },
        .{
            .value = 0.67,
            .label = "Processing",
            .showPercentage = true,
            .showEta = true,
            .eta_seconds = 45,
            .color = Color.ansi(.yellow),
        },
        .{
            .value = 0.89,
            .label = "Upload",
            .showPercentage = true,
            .color = Color.ansi(.green),
        },
        .{
            .value = 1.0,
            .label = "Complete",
            .showPercentage = true,
            .color = Color.rgb(0, 255, 0),
        },
    };

    for (progress_examples) |progress| {
        try renderProgress(renderer, progress);
        try renderer.writeText("\n", null, false);
    }

    try renderer.writeText("\nPress Enter to continue...", Color.ansi(.bright_black), false);
    try renderer.flush();
    var stdin_buffer: [1]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;
    _ = try stdin.readByte();
}

/// Demo tables with different configurations
fn demoTables(renderer: *AdaptiveRenderer) !void {
    try renderer.clearScreen();
    try renderer.moveCursor(0, 0);

    try renderer.writeText("📋 Table Demonstration\n", Color.ansi(.bright_blue), true);
    try renderer.writeText("=" ** 30, null, false);
    try renderer.writeText("\n\n", null, false);

    // Sample data
    const headers = [_][]const u8{ "Name", "Score", "Status", "Progress" };
    const row1 = [_][]const u8{ "Alice Johnson", "95", "✓ Complete", "100%" };
    const row2 = [_][]const u8{ "Bob Smith", "87", "⚡ In Progress", "78%" };
    const row3 = [_][]const u8{ "Carol Davis", "92", "✓ Complete", "100%" };
    const row4 = [_][]const u8{ "David Wilson", "74", "⏸ Paused", "45%" };
    const rows = [_][]const []const u8{ &row1, &row2, &row3, &row4 };

    const alignments = [_]Table.Alignment{ .left, .right, .center, .right };
    const row_colors = [_]?Color{
        Color.ansi(.green), // Alice - Complete
        Color.ansi(.yellow), // Bob - In Progress
        Color.ansi(.green), // Carol - Complete
        Color.ansi(.red), // David - Paused
    };

    const table = Table{
        .headers = &headers,
        .rows = &rows,
        .title = "Student Progress Report",
        .column_alignments = &alignments,
        .row_colors = &row_colors,
        .header_color = Color.ansi(.bright_cyan),
        .sortable = true,
        .sort_column = 1, // Sort by score
        .sort_ascending = false,
    };

    try renderTable(renderer, table);

    try renderer.writeText("\nPress Enter to continue...", Color.ansi(.bright_black), false);
    try renderer.flush();
    var stdin_buffer: [1]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;
    _ = try stdin.readByte();
}

/// Demo charts with different types
fn demoCharts(renderer: *AdaptiveRenderer) !void {
    try renderer.clearScreen();
    try renderer.moveCursor(0, 0);

    try renderer.writeText("📈 Chart Demonstration\n", Color.ansi(.bright_blue), true);
    try renderer.writeText("=" ** 30, null, false);
    try renderer.writeText("\n\n", null, false);

    // Sample data
    const data1 = [_]f64{ 10, 25, 15, 35, 30, 45, 40, 55, 50, 65 };
    const data2 = [_]f64{ 5, 15, 25, 20, 30, 35, 45, 40, 50, 55 };

    const series1 = Chart.Series{
        .name = "Revenue",
        .data = &data1,
        .color = Color.ansi(.green),
        .style = .solid,
    };

    const series2 = Chart.Series{
        .name = "Expenses",
        .data = &data2,
        .color = Color.ansi(.red),
        .style = .dashed,
    };

    // Line Chart
    const line_chart = Chart{
        .title = "Financial Performance (Line Chart)",
        .data_series = &[_]Chart.Series{ series1, series2 },
        .chart_type = .line,
        .width = 60,
        .height = 15,
        .show_legend = true,
        .show_axes = true,
        .x_axis_label = "Month",
        .y_axis_label = "Amount ($k)",
    };

    try renderChart(renderer, line_chart);
    try renderer.writeText("\n", null, false);

    // Bar Chart
    const bar_chart = Chart{
        .title = "Revenue by Quarter (Bar Chart)",
        .data_series = &[_]Chart.Series{series1},
        .chart_type = .bar,
        .width = 50,
        .height = 12,
        .show_legend = true,
        .show_axes = true,
    };

    try renderChart(renderer, bar_chart);
    try renderer.writeText("\n", null, false);

    // Sparkline
    const sparkline_data = [_]f64{ 1, 3, 2, 5, 4, 6, 8, 7, 9, 11, 10, 12 };
    const sparkline_series = Chart.Series{
        .name = "Trend",
        .data = &sparkline_data,
        .color = Color.ansi(.cyan),
    };

    const sparkline_chart = Chart{
        .title = "Quick Trend (Sparkline)",
        .data_series = &[_]Chart.Series{sparkline_series},
        .chart_type = .sparkline,
        .show_legend = false,
        .show_axes = false,
    };

    try renderChart(renderer, sparkline_chart);

    try renderer.writeText("\nPress Enter to continue...", Color.ansi(.bright_black), false);
    try renderer.flush();
    var stdin_buffer: [1]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;
    _ = try stdin.readByte();
}

/// Demo animated progress bars
fn demoAnimatedProgress(renderer: *AdaptiveRenderer) !void {
    try renderer.clearScreen();
    try renderer.moveCursor(0, 0);

    try renderer.writeText("🎬 Animated Progress Demonstration\n", Color.ansi(.bright_blue), true);
    try renderer.writeText("=" ** 45, null, false);
    try renderer.writeText("\n\n", null, false);

    var progress = AnimatedProgress.init(renderer, Progress{
        .value = 0.0,
        .label = "Processing files",
        .showPercentage = true,
        .showEta = true,
        .color = Color.ansi(.green),
    });

    const steps = 50;
    for (0..steps + 1) |i| {
        const value = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        try progress.update(value);

        // Simulate work
        std.time.sleep(50_000_000); // 50ms
    }

    try progress.finish();

    try renderer.writeText("\nAnimation complete!\n", Color.ansi(.bright_green), true);
    try renderer.writeText("Press Enter to continue...", Color.ansi(.bright_black), false);
    try renderer.flush();
    var stdin_buffer: [1]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;
    _ = try stdin.readByte();
}

/// Demo render mode comparison
fn demoRenderModeComparison(allocator: std.mem.Allocator) !void {
    const modes = [_]RenderMode{ .enhanced, .standard, .compatible, .minimal };

    for (modes) |mode| {
        const renderer = try AdaptiveRenderer.initWithMode(allocator, mode);
        defer renderer.deinit();

        try renderer.clearScreen();
        try renderer.moveCursor(0, 0);

        try renderer.writeText("🔍 Render Mode Comparison\n", Color.ansi(.bright_blue), true);
        try renderer.writeText("=" ** 35, null, false);
        try renderer.writeText("\n\n", null, false);

        try renderer.writeText("Current Mode: ", null, false);
        try renderer.writeText(mode.description(), Color.ansi(.yellow), true);
        try renderer.writeText("\n\n", null, false);

        // Sample progress bar
        const progress = Progress{
            .value = 0.75,
            .label = "Sample Progress",
            .showPercentage = true,
            .color = Color.ansi(.green),
        };
        try renderProgress(renderer, progress);
        try renderer.writeText("\n\n", null, false);

        // Sample table
        const headers = [_][]const u8{ "Item", "Value" };
        const row1 = [_][]const u8{ "Alpha", "100" };
        const row2 = [_][]const u8{ "Beta", "200" };
        const rows = [_][]const []const u8{ &row1, &row2 };

        const table = Table{
            .headers = &headers,
            .rows = &rows,
            .title = "Sample Table",
        };
        try renderTable(renderer, table);

        try renderer.writeText("\nPress Enter for next mode...", Color.ansi(.bright_black), false);
        try renderer.flush();
        var stdin_buffer: [1]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
        const stdin = &stdin_reader.interface;
        _ = try stdin.readByte();
    }
}

// Main function for standalone demo
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try runDemo(allocator);
}

test "adaptive demo" {
    const testing = std.testing;

    // Test that demo components can be instantiated
    const renderer = try AdaptiveRenderer.initWithMode(testing.allocator, .minimal);
    defer renderer.deinit();

    const progress = Progress{
        .value = 0.5,
        .label = "Test",
        .showPercentage = true,
    };
    try renderProgress(renderer, progress);

    const headers = [_][]const u8{ "A", "B" };
    const row = [_][]const u8{ "1", "2" };
    const rows = [_][]const []const u8{&row};

    const table = Table{
        .headers = &headers,
        .rows = &rows,
    };
    try renderTable(renderer, table);

    const data = [_]f64{ 1.0, 2.0, 3.0 };
    const series = Chart.Series{ .name = "Test", .data = &data };
    const chart = Chart{ .data_series = &[_]Chart.Series{series} };
    try renderChart(renderer, chart);
}

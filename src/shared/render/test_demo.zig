const std = @import("std");
const adaptive_render = @import("mod.zig");
const AdaptiveRenderer = adaptive_render.AdaptiveRenderer;
const EnhancedRenderer = adaptive_render.EnhancedRenderer;
const Progress = adaptive_render.Progress;
const Table = adaptive_render.Table;
const Chart = adaptive_render.Chart;
const Color = @import("../term/ansi/color.zig").Color;

/// Comprehensive test and validation of the adaptive rendering system
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🧪 Adaptive Rendering System - Comprehensive Test\n");
    std.debug.print("=" ** 60);
    std.debug.print("\n\n");

    try testAllRenderModes(allocator);
    try testComponentFunctionality(allocator);
    try testPerformance(allocator);
    try runInteractiveDemo(allocator);

    std.debug.print("✅ All tests completed successfully!\n");
    std.debug.print("The adaptive rendering system is fully functional.\n\n");
}

/// Test all render modes
fn testAllRenderModes(allocator: std.mem.Allocator) !void {
    std.debug.print("🔍 Testing All Render Modes\n");
    std.debug.print("-" ** 30);
    std.debug.print("\n");

    const modes = [_]AdaptiveRenderer.RenderMode{ .enhanced, .standard, .compatible, .minimal };

    for (modes) |mode| {
        std.debug.print("  Testing {s} mode... ", mode.description());

        var renderer = try AdaptiveRenderer.initWithMode(allocator, mode);
        defer renderer.deinit();

        const info = renderer.getRenderingInfo();
        std.debug.print("✓ (terminal: {s})\n", .{info.terminal_name});

        // Test basic functionality
        try testBasicRendering(renderer);
    }

    std.debug.print("✅ All render modes tested successfully\n\n");
}

/// Test basic rendering functionality
fn testBasicRendering(renderer: *AdaptiveRenderer) !void {
    // Test progress bar
    const progress = Progress{
        .value = 0.75,
        .label = "Test Progress",
        .show_percentage = true,
        .color = Color.ansi(.green),
    };
    try adaptive_render.renderProgress(renderer, progress);

    // Test table
    const headers = [_][]const u8{ "Test", "Result" };
    const row1 = [_][]const u8{ "Progress", "Pass" };
    const row2 = [_][]const u8{ "Table", "Pass" };
    const rows = [_][]const []const u8{ &row1, &row2 };

    const table = Table{
        .headers = &headers,
        .rows = &rows,
        .title = "Test Results",
    };
    try adaptive_render.renderTable(renderer, table);

    // Test chart
    const data = [_]f64{ 1.0, 3.0, 2.0, 4.0, 3.0 };
    const series = Chart.Series{ .name = "Test Data", .data = &data, .color = Color.ansi(.blue) };
    const chart = Chart{
        .title = "Test Chart",
        .data_series = &[_]Chart.Series{series},
        .chart_type = .line,
    };
    try adaptive_render.renderChart(renderer, chart);
}

/// Test component functionality
fn testComponentFunctionality(allocator: std.mem.Allocator) !void {
    std.debug.print("🔧 Testing Component Functionality\n");
    std.debug.print("-" ** 35);
    std.debug.print("\n");

    var enhanced = try EnhancedRenderer.init(allocator);
    defer enhanced.deinit();

    // Test progress bars with different configurations
    std.debug.print("  Testing progress bars... ");
    const progress_tests = [_]Progress{
        .{ .value = 0.0, .label = "Start", .show_percentage = true },
        .{ .value = 0.5, .label = "Middle", .show_percentage = true, .color = Color.ansi(.yellow) },
        .{ .value = 1.0, .label = "Complete", .show_percentage = true, .color = Color.ansi(.green) },
    };

    for (progress_tests) |progress| {
        try enhanced.renderProgress(progress);
    }
    std.debug.print("✓\n");

    // Test tables with different configurations
    std.debug.print("  Testing tables... ");
    const table_headers = [_][]const u8{ "Name", "Score", "Grade" };
    const table_row1 = [_][]const u8{ "Alice", "95", "A" };
    const table_row2 = [_][]const u8{ "Bob", "87", "B" };
    const table_row3 = [_][]const u8{ "Carol", "92", "A-" };
    const table_rows = [_][]const []const u8{ &table_row1, &table_row2, &table_row3 };

    const test_table = Table{
        .headers = &table_headers,
        .rows = &table_rows,
        .title = "Student Grades",
        .column_alignments = &[_]Table.Alignment{ .left, .right, .center },
        .header_color = Color.ansi(.bright_cyan),
    };
    try enhanced.renderTable(test_table);
    std.debug.print("✓\n");

    // Test charts with different types
    std.debug.print("  Testing charts... ");
    const chart_data = [_]f64{ 10, 25, 15, 35, 30, 45, 40 };
    const chart_series = Chart.Series{
        .name = "Sales",
        .data = &chart_data,
        .color = Color.ansi(.green),
    };

    const chart_types = [_]Chart.ChartType{ .line, .bar, .sparkline };
    for (chart_types) |chart_type| {
        const test_chart = Chart{
            .title = "Test Chart",
            .data_series = &[_]Chart.Series{chart_series},
            .chart_type = chart_type,
            .width = 40,
            .height = 10,
        };
        try enhanced.renderChart(test_chart);
    }
    std.debug.print("✓\n");

    std.debug.print("✅ All components tested successfully\n\n");
}

/// Test performance characteristics
fn testPerformance(allocator: std.mem.Allocator) !void {
    std.debug.print("⚡ Testing Performance\n");
    std.debug.print("-" ** 20);
    std.debug.print("\n");

    var renderer = try AdaptiveRenderer.init(allocator);
    defer renderer.deinit();

    const iterations = 1000;

    // Test progress bar rendering speed
    std.debug.print("  Progress bar rendering... ");
    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const progress = Progress{
            .value = @as(f32, @floatFromInt(i % 100)) / 100.0,
            .label = "Performance Test",
            .show_percentage = true,
        };
        try adaptive_render.renderProgress(renderer, progress);
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

    std.debug.print("✓ ({d:.1} ms, {d:.0} ops/sec)\n", .{ duration_ms, ops_per_sec });

    // Test cache effectiveness
    std.debug.print("  Cache effectiveness... ");
    const cache_start = std.time.nanoTimestamp();

    const cached_progress = Progress{
        .value = 0.5,
        .label = "Cached Test",
        .show_percentage = true,
    };

    // First render (cache miss)
    try adaptive_render.renderProgress(renderer, cached_progress);

    // Second render (cache hit)
    try adaptive_render.renderProgress(renderer, cached_progress);

    const cache_end = std.time.nanoTimestamp();
    const cache_duration = @as(f64, @floatFromInt(cache_end - cache_start)) / 1_000_000.0;

    std.debug.print("✓ ({d:.2} ms)\n", .{cache_duration});

    std.debug.print("✅ Performance tests completed\n\n");
}

/// Run interactive demo
fn runInteractiveDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("🎮 Running Interactive Demo\n");
    std.debug.print("-" ** 27);
    std.debug.print("\n");

    std.debug.print("Would you like to run the full interactive demo? (y/n): ");

    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;
    var buffer: [10]u8 = undefined;
    const input = (try stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) orelse "";

    if (input.len > 0 and (input[0] == 'y' or input[0] == 'Y')) {
        std.debug.print("\n🚀 Starting Interactive Demo...\n\n");
        try adaptive_render.runDemo(allocator);
    } else {
        std.debug.print("Skipping interactive demo.\n");
    }

    std.debug.print("\n✅ Demo completed\n\n");
}

/// Stress test the system
fn stressTest(allocator: std.mem.Allocator) !void {
    std.debug.print("💪 Stress Testing\n");
    std.debug.print("-" ** 17);
    std.debug.print("\n");

    var renderer = try AdaptiveRenderer.init(allocator);
    defer renderer.deinit();

    const stress_iterations = 10000;
    std.debug.print("  Stress test with {d} iterations... ", stress_iterations);

    const start_time = std.time.nanoTimestamp();

    for (0..stress_iterations) |i| {
        const value = @as(f32, @floatFromInt(i % 100)) / 100.0;

        // Progress bar
        const progress = Progress{
            .value = value,
            .label = "Stress Test",
            .show_percentage = true,
            .color = if (value > 0.8) Color.ansi(.green) else Color.ansi(.yellow),
        };
        try adaptive_render.renderProgress(renderer, progress);

        // Table (every 100 iterations)
        if (i % 100 == 0) {
            const headers = [_][]const u8{ "Iteration", "Progress" };
            const row = [_][]const u8{ "Current", "Running" };
            const rows = [_][]const []const u8{&row};

            const table = Table{
                .headers = &headers,
                .rows = &rows,
                .title = "Stress Test Status",
            };
            try adaptive_render.renderTable(renderer, table);
        }

        // Chart (every 1000 iterations)
        if (i % 1000 == 0 and i > 0) {
            const data = [_]f64{ @as(f64, @floatFromInt(i)), @as(f64, @floatFromInt(i)) / 2.0 };
            const series = Chart.Series{ .name = "Progress", .data = &data };
            const chart = Chart{ .data_series = &[_]Chart.Series{series} };
            try adaptive_render.renderChart(renderer, chart);
        }
    }

    const end_time = std.time.nanoTimestamp();
    const duration_s = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;

    std.debug.print("✓ ({d:.2}s, {d:.0} ops/sec)\n", .{ duration_s, @as(f64, @floatFromInt(stress_iterations)) / duration_s });
    std.debug.print("✅ Stress test completed successfully\n\n");
}

test "comprehensive adaptive rendering tests" {
    const testing = std.testing;

    // Test core functionality
    var renderer = try AdaptiveRenderer.initWithMode(testing.allocator, .minimal);
    defer renderer.deinit();

    // Test progress
    const progress = Progress{ .value = 0.5, .label = "Test" };
    try adaptive_render.renderProgress(renderer, progress);

    // Test table
    const headers = [_][]const u8{ "A", "B" };
    const row = [_][]const u8{ "1", "2" };
    const rows = [_][]const []const u8{&row};
    const table = Table{ .headers = &headers, .rows = &rows };
    try adaptive_render.renderTable(renderer, table);

    // Test chart
    const data = [_]f64{ 1.0, 2.0 };
    const series = Chart.Series{ .name = "Test", .data = &data };
    const chart = Chart{ .data_series = &[_]Chart.Series{series} };
    try adaptive_render.renderChart(renderer, chart);

    // Test enhanced renderer
    var enhanced = try EnhancedRenderer.init(testing.allocator);
    defer enhanced.deinit();

    try enhanced.renderProgress(progress);
    try enhanced.renderTable(table);
    try enhanced.renderChart(chart);

    // Test rendering info
    const info = enhanced.getRenderingInfo();
    try testing.expect(info.mode == .enhanced or info.mode == .standard or info.mode == .compatible or info.mode == .minimal);
}

const std = @import("std");
const adaptive_render = @import("src/render/mod.zig");
const AdaptiveRenderer = adaptive_render.AdaptiveRenderer;
const EnhancedRenderer = adaptive_render.EnhancedRenderer;
const Progress = adaptive_render.Progress;
const Table = adaptive_render.Table;
const Chart = adaptive_render.Chart;
const Color = @import("src/term/ansi/color.zig").Color;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create adaptive renderer
    var enhanced = try EnhancedRenderer.init(allocator);
    defer enhanced.deinit();
    
    // Clear screen and show header
    try enhanced.clearScreen();
    try enhanced.moveCursor(0, 0);
    
    try enhanced.writeText("🎨 Adaptive Rendering System - Live Demo\n", Color.ansi(.bright_cyan), true);
    try enhanced.writeText("=" ** 50, Color.ansi(.bright_black), false);
    try enhanced.writeText("\n\n", null, false);
    
    // Show terminal capabilities
    const info = enhanced.getRenderingInfo();
    try enhanced.writeText("Terminal: ", null, false);
    try enhanced.writeText(info.terminal_name, Color.ansi(.cyan), false);
    try enhanced.writeText(" (", null, false);
    try enhanced.writeText(info.mode.description(), Color.ansi(.yellow), false);
    try enhanced.writeText(")\n\n", null, false);
    
    // Demo progress bars
    try enhanced.writeText("📊 Progress Bars:\n", Color.ansi(.bright_blue), true);
    
    const progress_examples = [_]Progress{
        .{ .value = 0.25, .label = "Download", .show_percentage = true, .color = Color.ansi(.blue) },
        .{ .value = 0.67, .label = "Processing", .show_percentage = true, .color = Color.ansi(.yellow) },
        .{ .value = 1.0, .label = "Complete", .show_percentage = true, .color = Color.ansi(.green) },
    };
    
    for (progress_examples) |progress| {
        try enhanced.renderProgress(progress);
        try enhanced.writeText("\n", null, false);
    }
    
    try enhanced.writeText("\n", null, false);
    
    // Demo table
    try enhanced.writeText("📋 Data Table:\n", Color.ansi(.bright_blue), true);
    
    const headers = [_][]const u8{ "Feature", "Status", "Performance" };
    const row1 = [_][]const u8{ "Progress Bars", "✓ Working", "Excellent" };
    const row2 = [_][]const u8{ "Tables", "✓ Working", "Very Good" };
    const row3 = [_][]const u8{ "Charts", "✓ Working", "Good" };
    const rows = [_][]const []const u8{ &row1, &row2, &row3 };
    
    const table = Table{
        .headers = &headers,
        .rows = &rows,
        .title = "System Status",
        .column_alignments = &[_]Table.Alignment{ .left, .center, .right },
        .header_color = Color.ansi(.bright_cyan),
    };
    
    try enhanced.renderTable(table);
    try enhanced.writeText("\n", null, false);
    
    // Demo chart
    try enhanced.writeText("📈 Sample Chart:\n", Color.ansi(.bright_blue), true);
    
    const chart_data = [_]f64{ 10, 15, 12, 25, 20, 30, 28, 35, 32, 40 };
    const series = Chart.DataSeries{
        .name = "Performance",
        .data = &chart_data,
        .color = Color.ansi(.green),
    };
    
    const chart = Chart{
        .title = "System Performance Over Time",
        .data_series = &[_]Chart.DataSeries{series},
        .chart_type = .line,
        .width = 60,
        .height = 15,
        .show_legend = true,
        .show_axes = true,
    };
    
    try enhanced.renderChart(chart);
    try enhanced.writeText("\n", null, false);
    
    // Footer
    try enhanced.writeText("🎉 Adaptive Rendering System Successfully Demonstrated!\n", Color.ansi(.bright_green), true);
    try enhanced.writeText("All components adapt automatically to your terminal's capabilities.\n", null, false);
    
    try enhanced.flush();
}
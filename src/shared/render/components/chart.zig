const std = @import("std");
const AdaptiveRenderer = @import("../adaptive_renderer.zig").AdaptiveRenderer;
const RenderMode = AdaptiveRenderer.RenderMode;
const QualityTiers = @import("../quality_tiers.zig").QualityTiers;
const ChartConfig = @import("../quality_tiers.zig").ChartConfig;
const term_shared = @import("term_shared");
const Color = term_shared.ansi.color.Color;
const cacheKey = @import("../adaptive_renderer.zig").cacheKey;

/// Chart data structure
pub const Chart = struct {
    title: ?[]const u8 = null,
    data_series: []const Series,
    chart_type: ChartType = .line,
    width: ?u16 = null,
    height: ?u16 = null,
    show_legend: bool = true,
    show_axes: bool = true,
    x_axis_label: ?[]const u8 = null,
    y_axis_label: ?[]const u8 = null,
    background_color: ?Color = null,

    pub const ChartType = enum {
        line,
        bar,
        area,
        pie,
        sparkline,
        histogram,
    };

    pub const Series = struct {
        name: []const u8,
        data: []const f64,
        color: ?Color = null,
        style: Style = .solid,

        pub const Style = enum {
            solid,
            dashed,
            dotted,
        };
    };

    pub fn validate(self: Chart) !void {
        if (self.data_series.len == 0) {
            return error.NoSeries;
        }

        for (self.data_series) |series| {
            if (series.data.len == 0) {
                return error.EmptySeries;
            }
        }
    }

    pub fn getMinMaxValues(self: Chart) struct { min: f64, max: f64 } {
        var min_val: f64 = std.math.inf(f64);
        var max_val: f64 = -std.math.inf(f64);

        for (self.data_series) |series| {
            for (series.data) |value| {
                min_val = @min(min_val, value);
                max_val = @max(max_val, value);
            }
        }

        return .{ .min = min_val, .max = max_val };
    }
};

/// Render chart using adaptive renderer
pub fn renderChart(renderer: *AdaptiveRenderer, chart: Chart) !void {
    try chart.validate();

    const key = cacheKey("chart_{d}_{s}_{?s}", .{ chart.data_series.len, @tagName(chart.chart_type), chart.title });

    if (renderer.cache.get(key, renderer.render_mode)) |cached| {
        try renderer.terminal.writeText(cached);
        return;
    }

    var output = std.ArrayList(u8).init(renderer.allocator);
    defer output.deinit();

    switch (renderer.render_mode) {
        .enhanced => try renderEnhanced(renderer, chart, &output),
        .standard => try renderStandard(renderer, chart, &output),
        .compatible => try renderCompatible(renderer, chart, &output),
        .minimal => try renderMinimal(renderer, chart, &output),
    }

    const content = try output.toOwnedSlice();
    defer renderer.allocator.free(content);

    try renderer.cache.put(key, content, renderer.render_mode);
    try renderer.terminal.writeText(content);
}

/// Enhanced rendering with graphics support
fn renderEnhanced(renderer: *AdaptiveRenderer, chart: Chart, output: *std.ArrayList(u8)) !void {
    const config = QualityTiers.Chart.enhanced;
    const writer = output.writer();

    // Title
    if (chart.title) |title| {
        try writer.print("\x1b[1m{s}\x1b[0m\n\n", .{title});
    }

    if (config.use_graphics and renderer.graphics_manager != null) {
        // Use graphics manager to create chart image
        try writer.writeAll("[Graphics rendering would be implemented here with Kitty/Sixel]\n");

        // For now, fall back to Unicode rendering
        try renderUnicodeChart(renderer, chart, config, writer);
    } else {
        try renderUnicodeChart(renderer, chart, config, writer);
    }

    // Legend
    if (chart.show_legend and config.supports_legends) {
        try renderLegend(renderer, chart, config, writer);
    }
}

/// Standard rendering with Unicode blocks
fn renderStandard(renderer: *AdaptiveRenderer, chart: Chart, output: *std.ArrayList(u8)) !void {
    const config = QualityTiers.Chart.standard;
    const writer = output.writer();

    // Title
    if (chart.title) |title| {
        try writer.print("{s}\n\n", .{title});
    }

    try renderUnicodeChart(renderer, chart, config, writer);

    // Legend
    if (chart.show_legend and config.supports_legends) {
        try renderLegend(renderer, chart, config, writer);
    }
}

/// Compatible rendering with ASCII characters
fn renderCompatible(renderer: *AdaptiveRenderer, chart: Chart, output: *std.ArrayList(u8)) !void {
    const config = QualityTiers.Chart.compatible;
    const writer = output.writer();

    // Title
    if (chart.title) |title| {
        try writer.print("{s}\n\n", .{title});
    }

    try renderAsciiChart(renderer, chart, config, writer);

    // Legend
    if (chart.show_legend and config.supports_legends) {
        try renderLegend(renderer, chart, config, writer);
    }
}

/// Minimal rendering with text summary
fn renderMinimal(_: *AdaptiveRenderer, chart: Chart, output: *std.ArrayList(u8)) !void {
    const writer = output.writer();

    // Title
    if (chart.title) |title| {
        try writer.print("{s}\n", .{title});
    }

    // Data summary
    try writer.print("Data Summary ({s} chart):\n", .{@tagName(chart.chart_type)});

    for (chart.data_series, 0..) |series, i| {
        var sum: f64 = 0;
        var min_val: f64 = std.math.inf(f64);
        var max_val: f64 = -std.math.inf(f64);

        for (series.data) |value| {
            sum += value;
            min_val = @min(min_val, value);
            max_val = @max(max_val, value);
        }

        const avg = sum / @as(f64, @floatFromInt(series.data.len));

        try writer.print("  {d}. {s}: {d} points, avg={d:.2}, min={d:.2}, max={d:.2}\n", .{ i + 1, series.name, series.data.len, avg, min_val, max_val });
    }
}

/// Render chart using Unicode block characters
fn renderUnicodeChart(renderer: *AdaptiveRenderer, chart: Chart, config: ChartConfig, writer: anytype) !void {
    const dimensions = getDimensions(chart, config);
    const min_max = chart.getMinMaxValues();

    switch (chart.chart_type) {
        .line => try renderUnicodeLineChart(renderer, chart, config, dimensions, min_max, writer),
        .bar => try renderUnicodeBarChart(renderer, chart, config, dimensions, min_max, writer),
        .area => try renderUnicodeAreaChart(renderer, chart, config, dimensions, min_max, writer),
        .sparkline => try renderSparkline(renderer, chart, config, writer),
        else => {
            try writer.writeAll("[Chart type not yet implemented for Unicode rendering]\n");
            try renderDataTable(chart, writer);
        },
    }
}

/// Render chart using ASCII characters
fn renderAsciiChart(renderer: *AdaptiveRenderer, chart: Chart, config: ChartConfig, writer: anytype) !void {
    const dimensions = getDimensions(chart, config);
    const min_max = chart.getMinMaxValues();

    switch (chart.chart_type) {
        .line => try renderAsciiLineChart(renderer, chart, config, dimensions, min_max, writer),
        .bar => try renderAsciiBarChart(renderer, chart, config, dimensions, min_max, writer),
        else => {
            try writer.writeAll("[Chart type not yet implemented for ASCII rendering]\n");
            try renderDataTable(chart, writer);
        },
    }
}

/// Get chart dimensions based on config and chart settings
fn getDimensions(chart: Chart, config: ChartConfig) struct { width: u16, height: u16 } {
    return .{
        .width = chart.width orelse config.max_resolution.width,
        .height = chart.height orelse config.max_resolution.height,
    };
}

/// Render Unicode line chart
fn renderUnicodeLineChart(renderer: *AdaptiveRenderer, chart: Chart, config: ChartConfig, dimensions: struct { width: u16, height: u16 }, min_max: struct { min: f64, max: f64 }, writer: anytype) !void {
    const value_range = min_max.max - min_max.min;
    if (value_range == 0) return;

    // Y-axis (top to bottom)
    for (0..dimensions.height) |row_idx| {
        const y_value = min_max.max - (value_range * @as(f64, @floatFromInt(row_idx)) / @as(f64, @floatFromInt(dimensions.height - 1)));

        // Y-axis label
        if (chart.show_axes) {
            try writer.print("{d:6.1} │ ", .{y_value});
        }

        // Plot area
        for (0..dimensions.width) |col_idx| {
            const x_progress = @as(f64, @floatFromInt(col_idx)) / @as(f64, @floatFromInt(dimensions.width - 1));

            var has_point = false;
            var point_color: ?Color = null;

            // Check all series for points at this position
            for (chart.data_series) |series| {
                const data_idx = @as(usize, @intFromFloat(x_progress * @as(f64, @floatFromInt(series.data.len - 1))));
                if (data_idx < series.data.len) {
                    const normalized_value = (series.data[data_idx] - min_max.min) / value_range;
                    const pixel_y = @as(f64, @floatFromInt(dimensions.height - 1)) * (1.0 - normalized_value);

                    if (@abs(pixel_y - @as(f64, @floatFromInt(row_idx))) < 0.5) {
                        has_point = true;
                        point_color = series.color;
                        break;
                    }
                }
            }

            if (has_point) {
                if (config.supports_color and point_color) |color| {
                    try setChartColor(renderer, color, writer);
                }
                try writer.writeAll("●");
                if (config.supports_color and point_color) |_| {
                    try writer.writeAll("\x1b[0m");
                }
            } else {
                try writer.writeAll(" ");
            }
        }

        try writer.writeAll("\n");
    }

    // X-axis
    if (chart.show_axes) {
        try writer.writeAll("       └");
        for (0..dimensions.width) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("\n");
    }
}

/// Render Unicode bar chart
fn renderUnicodeBarChart(renderer: *AdaptiveRenderer, chart: Chart, config: ChartConfig, dimensions: struct { width: u16, height: u16 }, min_max: struct { min: f64, max: f64 }, writer: anytype) !void {
    if (chart.data_series.len == 0) return;

    const series = chart.data_series[0]; // Use first series for bar chart
    const value_range = min_max.max - min_max.min;
    if (value_range == 0) return;

    const bar_width = dimensions.width / @as(u16, @intCast(series.data.len));
    const bars_per_char = if (bar_width == 0) series.data.len / dimensions.width else 1;

    // Render bars from top to bottom
    for (0..dimensions.height) |row_idx| {
        const threshold_value = min_max.max - (value_range * @as(f64, @floatFromInt(row_idx)) / @as(f64, @floatFromInt(dimensions.height - 1)));

        for (0..@min(dimensions.width, @as(u16, @intCast(series.data.len)))) |col_idx| {
            const data_idx = col_idx * bars_per_char;
            if (data_idx >= series.data.len) break;

            const value = series.data[data_idx];
            const should_fill = value >= threshold_value;

            if (should_fill) {
                if (config.supports_color and series.color) |color| {
                    try setChartColor(renderer, color, writer);
                }
                try writer.writeAll("█");
                if (config.supports_color and series.color) |_| {
                    try writer.writeAll("\x1b[0m");
                }
            } else {
                try writer.writeAll(" ");
            }
        }
        try writer.writeAll("\n");
    }
}

/// Render Unicode area chart
fn renderUnicodeAreaChart(renderer: *AdaptiveRenderer, chart: Chart, config: ChartConfig, dimensions: struct { width: u16, height: u16 }, min_max: struct { min: f64, max: f64 }, writer: anytype) !void {
    // Similar to line chart but fills area below the line
    try renderUnicodeLineChart(renderer, chart, config, dimensions, min_max, writer);
}

/// Render sparkline (compact line chart)
fn renderSparkline(renderer: *AdaptiveRenderer, chart: Chart, config: ChartConfig, writer: anytype) !void {
    if (chart.data_series.len == 0) return;

    const series = chart.data_series[0];
    if (series.data.len == 0) return;

    const min_max = chart.getMinMaxValues();
    const value_range = min_max.max - min_max.min;
    if (value_range == 0) {
        for (0..series.data.len) |_| {
            try writer.writeAll("─");
        }
        return;
    }

    const sparkline_chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };

    if (config.supports_color and series.color) |color| {
        try setChartColor(renderer, color, writer);
    }

    for (series.data) |value| {
        const normalized = (value - min_max.min) / value_range;
        const char_index = @as(usize, @intFromFloat(normalized * @as(f64, @floatFromInt(sparkline_chars.len - 1))));
        try writer.writeAll(sparkline_chars[@min(char_index, sparkline_chars.len - 1)]);
    }

    if (config.supports_color and series.color) |_| {
        try writer.writeAll("\x1b[0m");
    }

    try writer.writeAll("\n");
}

/// Render ASCII line chart
fn renderAsciiLineChart(_: *AdaptiveRenderer, chart: Chart, _: ChartConfig, dimensions: struct { width: u16, height: u16 }, min_max: struct { min: f64, max: f64 }, writer: anytype) !void {
    const value_range = min_max.max - min_max.min;
    if (value_range == 0) return;

    // Simplified ASCII line chart
    for (0..dimensions.height) |row_idx| {
        const y_value = min_max.max - (value_range * @as(f64, @floatFromInt(row_idx)) / @as(f64, @floatFromInt(dimensions.height - 1)));

        if (chart.show_axes) {
            try writer.print("{d:6.1} | ", .{y_value});
        }

        for (0..dimensions.width) |col_idx| {
            const x_progress = @as(f64, @floatFromInt(col_idx)) / @as(f64, @floatFromInt(dimensions.width - 1));

            var has_point = false;
            for (chart.data_series) |series| {
                const data_idx = @as(usize, @intFromFloat(x_progress * @as(f64, @floatFromInt(series.data.len - 1))));
                if (data_idx < series.data.len) {
                    const normalized_value = (series.data[data_idx] - min_max.min) / value_range;
                    const pixel_y = @as(f64, @floatFromInt(dimensions.height - 1)) * (1.0 - normalized_value);

                    if (@abs(pixel_y - @as(f64, @floatFromInt(row_idx))) < 0.5) {
                        has_point = true;
                        break;
                    }
                }
            }

            try writer.writeAll(if (has_point) "*" else " ");
        }

        try writer.writeAll("\n");
    }
}

/// Render ASCII bar chart
fn renderAsciiBarChart(_: *AdaptiveRenderer, chart: Chart, _: ChartConfig, dimensions: struct { width: u16, height: u16 }, min_max: struct { min: f64, max: f64 }, writer: anytype) !void {
    if (chart.data_series.len == 0) return;

    const series = chart.data_series[0];
    const value_range = min_max.max - min_max.min;
    if (value_range == 0) return;

    for (0..dimensions.height) |row_idx| {
        const threshold_value = min_max.max - (value_range * @as(f64, @floatFromInt(row_idx)) / @as(f64, @floatFromInt(dimensions.height - 1)));

        for (0..@min(dimensions.width, @as(u16, @intCast(series.data.len)))) |col_idx| {
            if (col_idx >= series.data.len) break;

            const value = series.data[col_idx];
            try writer.writeAll(if (value >= threshold_value) "#" else " ");
        }
        try writer.writeAll("\n");
    }
}

/// Render legend
fn renderLegend(renderer: *AdaptiveRenderer, chart: Chart, config: ChartConfig, writer: anytype) !void {
    try writer.writeAll("\nLegend:\n");

    for (chart.data_series) |series| {
        if (config.supports_color and series.color) |color| {
            try setChartColor(renderer, color, writer);
        }

        try writer.print("  ● {s}", .{series.name});

        if (config.supports_color and series.color) |_| {
            try writer.writeAll("\x1b[0m");
        }

        try writer.writeAll("\n");
    }
}

/// Render data as table (fallback)
fn renderDataTable(chart: Chart, writer: anytype) !void {
    try writer.writeAll("\nData Table:\n");

    // Headers
    for (chart.data_series, 0..) |series, i| {
        if (i > 0) try writer.writeAll("\t");
        try writer.writeAll(series.name);
    }
    try writer.writeAll("\n");

    // Find max data length
    var max_len: usize = 0;
    for (chart.data_series) |series| {
        max_len = @max(max_len, series.data.len);
    }

    // Data rows
    for (0..max_len) |row_idx| {
        for (chart.data_series, 0..) |series, col_idx| {
            if (col_idx > 0) try writer.writeAll("\t");

            if (row_idx < series.data.len) {
                try writer.print("{d:.2}", .{series.data[row_idx]});
            } else {
                try writer.writeAll("-");
            }
        }
        try writer.writeAll("\n");
    }
}

/// Set chart color based on renderer capabilities
fn setChartColor(renderer: *AdaptiveRenderer, color: Color, writer: anytype) !void {
    switch (renderer.render_mode) {
        .enhanced => {
            switch (color) {
                .rgb => |rgb| try writer.print("\x1b[38;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }),
                .ansi => |ansi| try writer.print("\x1b[3{d}m", .{@intFromEnum(ansi)}),
                .palette => |pal| try writer.print("\x1b[38;5;{d}m", .{pal}),
            }
        },
        .standard => {
            switch (color) {
                .rgb => |rgb| {
                    const palette_index = rgbToPalette256(rgb);
                    try writer.print("\x1b[38;5;{d}m", .{palette_index});
                },
                .ansi => |ansi| try writer.print("\x1b[3{d}m", .{@intFromEnum(ansi)}),
                .palette => |pal| try writer.print("\x1b[38;5;{d}m", .{pal}),
            }
        },
        .compatible, .minimal => {
            switch (color) {
                .ansi => |ansi| try writer.print("\x1b[3{d}m", .{@intFromEnum(ansi)}),
                else => {}, // No color support
            }
        },
    }
}

/// Convert RGB to nearest 256-color palette index
fn rgbToPalette256(rgb: struct { r: u8, g: u8, b: u8 }) u8 {
    const r6 = rgb.r * 5 / 255;
    const g6 = rgb.g * 5 / 255;
    const b6 = rgb.b * 5 / 255;
    return 16 + (r6 * 36) + (g6 * 6) + b6;
}

// Tests
test "chart rendering" {
    const testing = std.testing;

    var renderer = try AdaptiveRenderer.initWithMode(testing.allocator, .standard);
    defer renderer.deinit();

    const data1 = [_]f64{ 1.0, 3.0, 2.0, 5.0, 4.0 };
    const series1 = Chart.Series{
        .name = "Series 1",
        .data = &data1,
        .color = Color.ansi(.red),
    };

    const chart = Chart{
        .title = "Test Chart",
        .data_series = &[_]Chart.Series{series1},
        .chart_type = .line,
    };

    try renderChart(renderer, chart);

    // Test validation
    const invalid_chart = Chart{
        .data_series = &[_]Chart.Series{},
    };
    try testing.expectError(error.NoSeries, invalid_chart.validate());
}

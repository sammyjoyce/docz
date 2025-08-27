//! Line and area chart implementations
//!
//! Provides line chart, area chart, and related visualization types.

const std = @import("std");
const base = @import("base.zig");
const graphics = @import("graphics.zig");
const renderer_mod = @import("../../../core/renderer.zig");

const Color = base.Color;
const ChartData = base.Chart;
const ChartStyle = base.ChartStyle;
const Bounds = base.Bounds;
const DrawingContext = graphics.DrawingContext;
const Renderer = renderer_mod.Renderer;
const RenderContext = renderer_mod.RenderContext;

/// Line chart renderer
pub const LineChart = struct {
    /// Render line chart to bitmap
    pub fn renderToBitmap(data: ChartData, style: ChartStyle, ctx: DrawingContext, chart_area: Bounds) !void {
        if (data.series.len == 0) return;

        // Calculate Y range if not provided
        const y_range = data.y_range orelse data.calculateYRange();

        // Draw grid and axes if enabled
        if (style.show_grid) {
            graphics.AxesRenderer.drawGrid(ctx, chart_area, style);
        }
        if (style.show_axes) {
            graphics.AxesRenderer.drawAxes(ctx, chart_area, y_range, style);
        }

        // Draw each series
        for (data.series, 0..) |series, series_idx| {
            const color = series.color orelse style.getSeriesColor(series_idx);
            try renderSeries(ctx, chart_area, series, y_range, color, style);
        }
    }

    /// Render line chart using Unicode blocks
    pub fn renderUnicode(data: ChartData, style: ChartStyle, renderer: *Renderer, ctx: RenderContext) !void {
        if (data.series.len == 0) return;

        const chart_width = ctx.bounds.width - 4;
        const chart_height = ctx.bounds.height - 4;

        // Create ASCII buffer for plotting
        const buffer = try std.heap.page_allocator.alloc([]u8, chart_height);
        defer std.heap.page_allocator.free(buffer);

        for (buffer, 0..) |*row, i| {
            row.* = try std.heap.page_allocator.alloc(u8, chart_width);
            @memset(row.*, ' ');
            _ = i;
        }
        defer {
            for (buffer) |row| {
                std.heap.page_allocator.free(row);
            }
        }

        // Plot data points
        const series = data.series[0]; // Just use first series for simplicity
        const y_range = data.y_range orelse data.calculateYRange();

        for (series.values, 0..) |value, i| {
            if (series.values.len <= 1) continue;

            const x = (i * chart_width) / (series.values.len - 1);
            const normalized_y = (value - y_range.min) / (y_range.max - y_range.min);
            const y = chart_height - @as(u32, @intFromFloat(normalized_y * @as(f64, @floatFromInt(chart_height)))) - 1;

            if (x < chart_width and y < chart_height) {
                // Use Unicode blocks for better visual quality
                buffer[y][x] = switch (series.style) {
                    .solid => '█',
                    .dashed => '▬',
                    .dotted => '•',
                    .points => '◆',
                };
            }

            // Draw connecting lines for solid style
            if (series.style == .solid and i > 0) {
                const prev_x = ((i - 1) * chart_width) / (series.values.len - 1);
                const prev_normalized_y = (series.values[i - 1] - y_range.min) / (y_range.max - y_range.min);
                const prev_y = chart_height - @as(u32, @intFromFloat(prev_normalized_y * @as(f64, @floatFromInt(chart_height)))) - 1;

                // Simple line drawing with Unicode characters
                drawUnicodeLine(buffer, chart_width, chart_height, prev_x, prev_y, x, y);
            }
        }

        // Render title
        try renderer.drawText(ctx, style.title orelse "Line Chart");

        // Render the buffer
        const title_height = 2;
        for (buffer, 0..) |row, i| {
            const render_ctx = RenderContext{
                .bounds = Bounds.init(ctx.bounds.x + 2, ctx.bounds.y + title_height + @as(i32, @intCast(i)), @intCast(row.len), 1),
                .style = ctx.style,
                .z_index = ctx.z_index,
                .clip_region = ctx.clip_region,
            };
            try renderer.drawText(render_ctx, row);
        }
    }

    /// Render line chart using ASCII characters
    pub fn renderAscii(data: ChartData, style: ChartStyle, renderer: *Renderer, ctx: RenderContext) !void {
        // Similar to Unicode but with ASCII characters only
        if (data.series.len == 0) return;

        const chart_width = ctx.bounds.width - 4;
        const chart_height = ctx.bounds.height - 4;

        // Create ASCII buffer for plotting
        const buffer = try std.heap.page_allocator.alloc([]u8, chart_height);
        defer std.heap.page_allocator.free(buffer);

        for (buffer, 0..) |*row, i| {
            row.* = try std.heap.page_allocator.alloc(u8, chart_width);
            @memset(row.*, ' ');
            _ = i;
        }
        defer {
            for (buffer) |row| {
                std.heap.page_allocator.free(row);
            }
        }

        // Plot data points with ASCII characters
        const series = data.series[0];
        const y_range = data.y_range orelse data.calculateYRange();

        for (series.values, 0..) |value, i| {
            if (series.values.len <= 1) continue;

            const x = (i * chart_width) / (series.values.len - 1);
            const normalized_y = (value - y_range.min) / (y_range.max - y_range.min);
            const y = chart_height - @as(u32, @intFromFloat(normalized_y * @as(f64, @floatFromInt(chart_height)))) - 1;

            if (x < chart_width and y < chart_height) {
                buffer[y][x] = '*';
            }
        }

        // Render title
        try renderer.drawText(ctx, style.title orelse "Line Chart");

        // Render the buffer
        const title_height = 2;
        for (buffer, 0..) |row, i| {
            const render_ctx = RenderContext{
                .bounds = Bounds.init(ctx.bounds.x + 2, ctx.bounds.y + title_height + @as(i32, @intCast(i)), @intCast(row.len), 1),
                .style = ctx.style,
                .z_index = ctx.z_index,
                .clip_region = ctx.clip_region,
            };
            try renderer.drawText(render_ctx, row);
        }
    }

    /// Helper function to render a single series
    fn renderSeries(ctx: DrawingContext, chart_area: Bounds, series: ChartData.Series, y_range: ChartData.Range, color: Color, style: ChartStyle) !void {
        if (series.values.len < 2) return;

        // Draw line segments connecting data points
        for (0..series.values.len - 1) |i| {
            const x1 = @as(u32, @intCast(chart_area.x)) + @as(u32, @intFromFloat(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(series.values.len - 1)) * @as(f64, @floatFromInt(chart_area.width))));
            const y1 = @as(u32, @intCast(chart_area.y)) + chart_area.height - @as(u32, @intFromFloat((series.values[i] - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_area.height))));

            const x2 = @as(u32, @intCast(chart_area.x)) + @as(u32, @intFromFloat(@as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(series.values.len - 1)) * @as(f64, @floatFromInt(chart_area.width))));
            const y2 = @as(u32, @intCast(chart_area.y)) + chart_area.height - @as(u32, @intFromFloat((series.values[i + 1] - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_area.height))));

            // Draw line with appropriate style
            switch (series.style) {
                .solid => ctx.drawLine(x1, y1, x2, y2, color),
                .dashed => drawDashedLine(ctx, x1, y1, x2, y2, color),
                .dotted => drawDottedLine(ctx, x1, y1, x2, y2, color),
                .points => {
                    // Just draw points, no connecting lines
                    ctx.drawPoint(x1, y1, style.point_size, color);
                    if (i == series.values.len - 2) { // Last point
                        ctx.drawPoint(x2, y2, style.point_size, color);
                    }
                },
            }
        }

        // Draw points if configured
        if (series.style == .points or series.style == .solid) {
            for (series.values, 0..) |value, i| {
                const x = @as(u32, @intCast(chart_area.x)) + @as(u32, @intFromFloat(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(series.values.len - 1)) * @as(f64, @floatFromInt(chart_area.width))));
                const y = @as(u32, @intCast(chart_area.y)) + chart_area.height - @as(u32, @intFromFloat((value - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_area.height))));
                ctx.drawPoint(x, y, style.point_size, color);
            }
        }
    }

    /// Draw a dashed line
    fn drawDashedLine(ctx: DrawingContext, x1: u32, y1: u32, x2: u32, y2: u32, color: Color) void {
        // Simple dashed line implementation - draw every other pixel
        const dx = @abs(@as(i32, @intCast(x2)) - @as(i32, @intCast(x1)));
        const dy = @abs(@as(i32, @intCast(y2)) - @as(i32, @intCast(y1)));
        const distance = @sqrt(@as(f64, @floatFromInt(dx * dx + dy * dy)));
        const steps = @as(u32, @intFromFloat(distance));

        for (0..steps) |i| {
            if (i % 8 < 4) { // Dash pattern: 4 on, 4 off
                const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
                const x = @as(u32, @intFromFloat(@as(f64, @floatFromInt(x1)) + t * @as(f64, @floatFromInt(@as(i32, @intCast(x2)) - @as(i32, @intCast(x1))))));
                const y = @as(u32, @intFromFloat(@as(f64, @floatFromInt(y1)) + t * @as(f64, @floatFromInt(@as(i32, @intCast(y2)) - @as(i32, @intCast(y1))))));
                // Set pixel directly
                if (x < ctx.width and y < ctx.height) {
                    const pixel_offset = (y * ctx.width + x) * 4;
                    if (pixel_offset + 3 < ctx.image_data.len) {
                        ctx.image_data[pixel_offset] = color.r;
                        ctx.image_data[pixel_offset + 1] = color.g;
                        ctx.image_data[pixel_offset + 2] = color.b;
                        ctx.image_data[pixel_offset + 3] = color.a;
                    }
                }
            }
        }
    }

    /// Draw a dotted line
    fn drawDottedLine(ctx: DrawingContext, x1: u32, y1: u32, x2: u32, y2: u32, color: Color) void {
        // Draw every 6th pixel for dotted effect
        const dx = @abs(@as(i32, @intCast(x2)) - @as(i32, @intCast(x1)));
        const dy = @abs(@as(i32, @intCast(y2)) - @as(i32, @intCast(y1)));
        const distance = @sqrt(@as(f64, @floatFromInt(dx * dx + dy * dy)));
        const steps = @as(u32, @intFromFloat(distance));

        for (0..steps) |i| {
            if (i % 6 == 0) { // Draw every 6th pixel
                const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
                const x = @as(u32, @intFromFloat(@as(f64, @floatFromInt(x1)) + t * @as(f64, @floatFromInt(@as(i32, @intCast(x2)) - @as(i32, @intCast(x1))))));
                const y = @as(u32, @intFromFloat(@as(f64, @floatFromInt(y1)) + t * @as(f64, @floatFromInt(@as(i32, @intCast(y2)) - @as(i32, @intCast(y1))))));
                // Set pixel directly
                if (x < ctx.width and y < ctx.height) {
                    const pixel_offset = (y * ctx.width + x) * 4;
                    if (pixel_offset + 3 < ctx.image_data.len) {
                        ctx.image_data[pixel_offset] = color.r;
                        ctx.image_data[pixel_offset + 1] = color.g;
                        ctx.image_data[pixel_offset + 2] = color.b;
                        ctx.image_data[pixel_offset + 3] = color.a;
                    }
                }
            }
        }
    }

    /// Draw Unicode line connecting two points
    fn drawUnicodeLine(buffer: [][]u8, width: u32, height: u32, x1: u32, y1: u32, x2: u32, y2: u32) void {
        // Simple line drawing for Unicode buffers
        const dx = @abs(@as(i32, @intCast(x2)) - @as(i32, @intCast(x1)));
        const dy = @abs(@as(i32, @intCast(y2)) - @as(i32, @intCast(y1)));

        if (dx > dy) {
            // More horizontal than vertical
            const start_x = @min(x1, x2);
            const end_x = @max(x1, x2);
            const start_y = if (x1 < x2) y1 else y2;
            const end_y = if (x1 < x2) y2 else y1;

            for (start_x..end_x + 1) |x| {
                if (x >= width) continue;
                const t = @as(f64, @floatFromInt(x - start_x)) / @as(f64, @floatFromInt(end_x - start_x));
                const y = @as(u32, @intFromFloat(@as(f64, @floatFromInt(start_y)) + t * @as(f64, @floatFromInt(@as(i32, @intCast(end_y)) - @as(i32, @intCast(start_y))))));
                if (y < height) {
                    buffer[y][x] = '─';
                }
            }
        } else {
            // More vertical than horizontal
            const start_y = @min(y1, y2);
            const end_y = @max(y1, y2);

            for (start_y..end_y + 1) |y| {
                if (y >= height) continue;
                const t = @as(f64, @floatFromInt(y - start_y)) / @as(f64, @floatFromInt(end_y - start_y));
                const x = @as(u32, @intFromFloat(@as(f64, @floatFromInt(@min(x1, x2))) + t * @as(f64, @floatFromInt(@max(x1, x2) - @min(x1, x2)))));
                if (x < width) {
                    buffer[y][x] = '│';
                }
            }
        }
    }
};

/// Area chart renderer (extends line chart with filled areas)
pub const AreaChart = struct {
    /// Render area chart to bitmap
    pub fn renderToBitmap(data: ChartData, style: ChartStyle, ctx: DrawingContext, chart_area: Bounds) !void {
        // First render the line chart
        try LineChart.renderToBitmap(data, style, ctx, chart_area);

        // Then fill areas under the lines
        if (data.series.len == 0) return;

        const y_range = data.y_range orelse data.calculateYRange();

        for (data.series, 0..) |series, series_idx| {
            const color = series.color orelse style.getSeriesColor(series_idx);
            // Create semi-transparent version for area fill
            const area_color = Color{ .r = color.r, .g = color.g, .b = color.b, .a = 128 };

            try fillAreaUnderCurve(ctx, chart_area, series, y_range, area_color);
        }
    }

    /// Fill the area under a series curve
    fn fillAreaUnderCurve(ctx: DrawingContext, chart_area: Bounds, series: ChartData.Series, y_range: ChartData.Range, color: Color) !void {
        if (series.values.len < 2) return;

        const baseline_y = @as(u32, @intCast(chart_area.y)) + chart_area.height;

        // Fill area under each line segment
        for (0..series.values.len - 1) |i| {
            const x1 = @as(u32, @intCast(chart_area.x)) + @as(u32, @intFromFloat(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(series.values.len - 1)) * @as(f64, @floatFromInt(chart_area.width))));
            const y1 = @as(u32, @intCast(chart_area.y)) + chart_area.height - @as(u32, @intFromFloat((series.values[i] - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_area.height))));

            const x2 = @as(u32, @intCast(chart_area.x)) + @as(u32, @intFromFloat(@as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(series.values.len - 1)) * @as(f64, @floatFromInt(chart_area.width))));
            const y2 = @as(u32, @intCast(chart_area.y)) + chart_area.height - @as(u32, @intFromFloat((series.values[i + 1] - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_area.height))));

            // Fill trapezoid from baseline to line segment
            fillTrapezoid(ctx, x1, y1, x2, y2, baseline_y, color);
        }
    }

    /// Fill a trapezoid (used for area fill)
    fn fillTrapezoid(ctx: DrawingContext, x1: u32, y1: u32, x2: u32, y2: u32, baseline_y: u32, color: Color) void {
        const start_x = @min(x1, x2);
        const end_x = @max(x1, x2);

        for (start_x..end_x + 1) |x| {
            // Calculate top and bottom Y coordinates for this X
            const t = if (end_x == start_x) 0.0 else @as(f64, @floatFromInt(x - start_x)) / @as(f64, @floatFromInt(end_x - start_x));
            const top_y = @as(u32, @intFromFloat(@as(f64, @floatFromInt(@min(y1, y2))) + t * @as(f64, @floatFromInt(@max(y1, y2) - @min(y1, y2)))));

            // Fill vertical line from baseline to curve
            for (top_y..baseline_y + 1) |y| {
                if (x < ctx.width and y < ctx.height) {
                    // Set pixel using the private method
                    if (x < ctx.width and y < ctx.height) {
                        const pixel_offset = (y * ctx.width + x) * 4;
                        if (pixel_offset + 3 < ctx.image_data.len) {
                            ctx.image_data[pixel_offset] = color.r;
                            ctx.image_data[pixel_offset + 1] = color.g;
                            ctx.image_data[pixel_offset + 2] = color.b;
                            ctx.image_data[pixel_offset + 3] = color.a;
                        }
                    }
                }
            }
        }
    }
};

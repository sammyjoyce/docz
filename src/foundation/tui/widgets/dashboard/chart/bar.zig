//! Bar chart implementations
//!
//! Provides bar chart, column chart, and histogram visualization types.

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
const Render = renderer_mod.Render;

/// Bar chart renderer
pub const BarChart = struct {
    /// Render bar chart to bitmap
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

        // Calculate bar dimensions
        const series = data.series[0]; // Use first series for now
        const bar_count = series.values.len;
        if (bar_count == 0) return;

        const total_width = chart_area.width;
        const bar_width = total_width / @as(u32, @intCast(bar_count));
        const bar_spacing = @max(1, bar_width / 10); // 10% spacing between bars
        const actual_bar_width = bar_width - bar_spacing;

        // Draw bars
        const color = series.color orelse style.getSeriesColor(0);
        for (series.values, 0..) |value, i| {
            const bar_height = @as(u32, @intFromFloat((value - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_area.height))));

            const bar_x = @as(u32, @intCast(chart_area.x)) + @as(u32, @intCast(i)) * bar_width + bar_spacing / 2;
            const bar_y = @as(u32, @intCast(chart_area.y)) + chart_area.height - bar_height;

            // Draw the bar
            ctx.drawRect(bar_x, bar_y, actual_bar_width, bar_height, color);

            // Draw bar outline for better visual separation
            const outline_color = Color{ .r = color.r / 2, .g = color.g / 2, .b = color.b / 2, .a = color.a };
            drawBarOutline(ctx, bar_x, bar_y, actual_bar_width, bar_height, outline_color);
        }
    }

    /// Render bar chart using Unicode blocks
    pub fn renderUnicode(data: ChartData, style: ChartStyle, renderer: *Renderer, ctx: Render) !void {
        if (data.series.len == 0) return;

        const series = data.series[0];
        const y_range = data.y_range orelse data.calculateYRange();
        const chart_height = ctx.bounds.height - 4;
        const chart_width = ctx.bounds.width - 4;

        // Render title
        const title_ctx = Render{
            .bounds = Bounds.init(ctx.bounds.x, ctx.bounds.y, ctx.bounds.width, 1),
            .style = ctx.style,
            .z_index = ctx.z_index,
            .clip_region = ctx.clip_region,
        };
        try renderer.drawText(title_ctx, style.title orelse "Bar Chart");

        // Calculate bar width
        const bar_width = if (series.values.len > 0) @max(1, chart_width / @as(u32, @intCast(series.values.len))) else 1;

        // Render bars using Unicode blocks
        for (series.values, 0..) |value, i| {
            const bar_height = @as(u32, @intFromFloat((value - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_height))));

            // Draw bar from bottom up using full blocks
            for (0..bar_height) |j| {
                const y = ctx.bounds.y + ctx.bounds.height - @as(i32, @intCast(j)) - 2;

                // Draw full width of bar
                for (0..bar_width) |k| {
                    const x = ctx.bounds.x + @as(i32, @intCast(i * bar_width + k)) + 2;

                    if (x < ctx.bounds.x + ctx.bounds.width and y >= ctx.bounds.y) {
                        const block_ctx = Render{
                            .bounds = Bounds.init(x, y, 1, 1),
                            .style = ctx.style,
                            .z_index = ctx.z_index,
                            .clip_region = ctx.clip_region,
                        };
                        try renderer.drawText(block_ctx, "█");
                    }
                }
            }

            // Add partial block for fractional height
            const fractional_part = (value - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_height)) - @as(f64, @floatFromInt(bar_height));
            if (fractional_part > 0.25) {
                const partial_y = ctx.bounds.y + ctx.bounds.height - @as(i32, @intCast(bar_height)) - 3;
                const partial_char = getPartialBlock(fractional_part);

                for (0..bar_width) |k| {
                    const x = ctx.bounds.x + @as(i32, @intCast(i * bar_width + k)) + 2;

                    if (x < ctx.bounds.x + ctx.bounds.width and partial_y >= ctx.bounds.y) {
                        const partial_ctx = Render{
                            .bounds = Bounds.init(x, partial_y, 1, 1),
                            .style = ctx.style,
                            .z_index = ctx.z_index,
                            .clip_region = ctx.clip_region,
                        };
                        try renderer.drawText(partial_ctx, partial_char);
                    }
                }
            }
        }
    }

    /// Render bar chart using ASCII characters
    pub fn renderAscii(data: ChartData, style: ChartStyle, renderer: *Renderer, ctx: Render) !void {
        if (data.series.len == 0) return;

        const series = data.series[0];
        const y_range = data.y_range orelse data.calculateYRange();
        const chart_height = ctx.bounds.height - 4;
        const chart_width = ctx.bounds.width - 4;

        // Render title
        const title_ctx = Render{
            .bounds = Bounds.init(ctx.bounds.x, ctx.bounds.y, ctx.bounds.width, 1),
            .style = ctx.style,
            .z_index = ctx.z_index,
            .clip_region = ctx.clip_region,
        };
        try renderer.drawText(title_ctx, style.title orelse "Bar Chart");

        // Calculate bar width
        const bar_width = if (series.values.len > 0) @max(1, chart_width / @as(u32, @intCast(series.values.len))) else 1;

        // Render bars using ASCII blocks
        for (series.values, 0..) |value, i| {
            const bar_height = @as(u32, @intFromFloat((value - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_height))));

            // Draw bar using ASCII # characters
            for (0..bar_height) |j| {
                const y = ctx.bounds.y + ctx.bounds.height - @as(i32, @intCast(j)) - 2;

                // Draw full width of bar
                for (0..bar_width) |k| {
                    const x = ctx.bounds.x + @as(i32, @intCast(i * bar_width + k)) + 2;

                    if (x < ctx.bounds.x + ctx.bounds.width and y >= ctx.bounds.y) {
                        const block_ctx = Render{
                            .bounds = Bounds.init(x, y, 1, 1),
                            .style = ctx.style,
                            .z_index = ctx.z_index,
                            .clip_region = ctx.clip_region,
                        };
                        try renderer.drawText(block_ctx, "#");
                    }
                }
            }
        }
    }

    /// Draw bar outline for visual separation
    fn drawBarOutline(ctx: DrawingContext, x: u32, y: u32, width: u32, height: u32, color: Color) void {
        // Top edge
        ctx.drawLine(x, y, x + width - 1, y, color);
        // Bottom edge
        ctx.drawLine(x, y + height - 1, x + width - 1, y + height - 1, color);
        // Left edge
        ctx.drawLine(x, y, x, y + height - 1, color);
        // Right edge
        ctx.drawLine(x + width - 1, y, x + width - 1, y + height - 1, color);
    }

    /// Get partial Unicode block character based on fractional height
    fn getPartialBlock(fraction: f64) []const u8 {
        if (fraction < 0.25) {
            return " "; // Empty
        } else if (fraction < 0.5) {
            return "▂"; // Lower 1/4
        } else if (fraction < 0.75) {
            return "▄"; // Lower 1/2
        } else {
            return "▆"; // Lower 3/4
        }
    }
};

/// Horizontal bar chart (bars extend horizontally instead of vertically)
pub const HorizontalBarChart = struct {
    /// Render horizontal bar chart to bitmap
    pub fn renderToBitmap(data: ChartData, style: ChartStyle, ctx: DrawingContext, chart_area: Bounds) !void {
        if (data.series.len == 0) return;

        // Calculate value range (now for horizontal bars)
        const value_range = data.y_range orelse data.calculateYRange();

        // Draw grid and axes if enabled
        if (style.show_grid) {
            graphics.AxesRenderer.drawGrid(ctx, chart_area, style);
        }
        if (style.show_axes) {
            graphics.AxesRenderer.drawAxes(ctx, chart_area, value_range, style);
        }

        // Calculate bar dimensions
        const series = data.series[0];
        const bar_count = series.values.len;
        if (bar_count == 0) return;

        const total_height = chart_area.height;
        const bar_height = total_height / @as(u32, @intCast(bar_count));
        const bar_spacing = @max(1, bar_height / 10);
        const actual_bar_height = bar_height - bar_spacing;

        // Draw horizontal bars
        const color = series.color orelse style.getSeriesColor(0);
        for (series.values, 0..) |value, i| {
            const bar_width = @as(u32, @intFromFloat((value - value_range.min) / (value_range.max - value_range.min) * @as(f64, @floatFromInt(chart_area.width))));

            const bar_x = @as(u32, @intCast(chart_area.x));
            const bar_y = @as(u32, @intCast(chart_area.y)) + @as(u32, @intCast(i)) * bar_height + bar_spacing / 2;

            // Draw the horizontal bar
            ctx.drawRect(bar_x, bar_y, bar_width, actual_bar_height, color);

            // Draw bar outline
            const outline_color = Color{ .r = color.r / 2, .g = color.g / 2, .b = color.b / 2, .a = color.a };
            drawHorizontalBarOutline(ctx, bar_x, bar_y, bar_width, actual_bar_height, outline_color);
        }
    }

    /// Draw horizontal bar outline
    fn drawHorizontalBarOutline(ctx: DrawingContext, x: u32, y: u32, width: u32, height: u32, color: Color) void {
        // Top edge
        ctx.drawLine(x, y, x + width - 1, y, color);
        // Bottom edge
        ctx.drawLine(x, y + height - 1, x + width - 1, y + height - 1, color);
        // Left edge
        ctx.drawLine(x, y, x, y + height - 1, color);
        // Right edge
        if (width > 0) {
            ctx.drawLine(x + width - 1, y, x + width - 1, y + height - 1, color);
        }
    }
};

/// Stacked bar chart (multiple series stacked in same bars)
pub const StackedBarChart = struct {
    /// Render stacked bar chart to bitmap
    pub fn renderToBitmap(data: ChartData, style: ChartStyle, ctx: DrawingContext, chart_area: Bounds) !void {
        if (data.series.len == 0) return;

        // Calculate stacked totals for proper scaling
        var max_total: f64 = 0.0;
        const value_count = if (data.series.len > 0) data.series[0].values.len else 0;

        for (0..value_count) |i| {
            var total: f64 = 0.0;
            for (data.series) |series| {
                if (i < series.values.len) {
                    total += @max(0.0, series.values[i]); // Only stack positive values
                }
            }
            max_total = @max(max_total, total);
        }

        const value_range = base.Chart.Range{ .min = 0.0, .max = max_total };

        // Draw grid and axes
        if (style.show_grid) {
            graphics.AxesRenderer.drawGrid(ctx, chart_area, style);
        }
        if (style.show_axes) {
            graphics.AxesRenderer.drawAxes(ctx, chart_area, value_range, style);
        }

        // Calculate bar dimensions
        const bar_width = chart_area.width / @as(u32, @intCast(value_count));
        const bar_spacing = @max(1, bar_width / 10);
        const actual_bar_width = bar_width - bar_spacing;

        // Draw stacked bars
        for (0..value_count) |i| {
            var stack_base: f64 = 0.0;

            for (data.series, 0..) |series, series_idx| {
                if (i >= series.values.len) continue;

                const value = @max(0.0, series.values[i]); // Only stack positive values
                if (value <= 0.0) continue;

                const segment_height = @as(u32, @intFromFloat(value / max_total * @as(f64, @floatFromInt(chart_area.height))));
                const segment_base = @as(u32, @intFromFloat(stack_base / max_total * @as(f64, @floatFromInt(chart_area.height))));

                const bar_x = @as(u32, @intCast(chart_area.x)) + @as(u32, @intCast(i)) * bar_width + bar_spacing / 2;
                const bar_y = @as(u32, @intCast(chart_area.y)) + chart_area.height - segment_base - segment_height;

                // Get color for this series
                const color = series.color orelse style.getSeriesColor(series_idx);

                // Draw the stacked segment
                ctx.drawRect(bar_x, bar_y, actual_bar_width, segment_height, color);

                stack_base += value;
            }
        }
    }
};

//! Graphics drawing utilities for chart rendering
//!
//! Low-level drawing functions used by chart implementations for bitmap rendering.

const std = @import("std");
const base = @import("base.zig");

const Color = base.Color;
const Bounds = base.Bounds;

/// Drawing context for bitmap operations
pub const Drawing = struct {
    image_data: []u8,
    width: u32,
    height: u32,

    /// Draw a line using Bresenham's line algorithm
    pub fn drawLine(self: Drawing, x1: u32, y1: u32, x2: u32, y2: u32, color: Color) void {
        const dx = @abs(@as(i32, @intCast(x2)) - @as(i32, @intCast(x1)));
        const dy = @abs(@as(i32, @intCast(y2)) - @as(i32, @intCast(y1)));
        const sx: i32 = if (x1 < x2) 1 else -1;
        const sy: i32 = if (y1 < y2) 1 else -1;
        var err = dx - dy;

        var x = @as(i32, @intCast(x1));
        var y = @as(i32, @intCast(y1));

        while (true) {
            if (x >= 0 and x < self.width and y >= 0 and y < self.height) {
                self.setPixel(@intCast(x), @intCast(y), color);
            }

            if (x == x2 and y == y2) break;

            const e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                x += sx;
            }
            if (e2 < dx) {
                err += dx;
                y += sy;
            }
        }
    }

    /// Draw a filled rectangle
    pub fn drawRect(self: Drawing, x: u32, y: u32, rect_width: u32, rect_height: u32, color: Color) void {
        for (0..rect_height) |row| {
            for (0..rect_width) |col| {
                const px = x + @as(u32, @intCast(col));
                const py = y + @as(u32, @intCast(row));

                if (px < self.width and py < self.height) {
                    self.setPixel(px, py, color);
                }
            }
        }
    }

    /// Draw a point/circle
    pub fn drawPoint(self: Drawing, x: u32, y: u32, radius: f32, color: Color) void {
        const point_radius = @as(u32, @intFromFloat(radius));
        self.drawRect(x -| point_radius / 2, y -| point_radius / 2, point_radius, point_radius, color);
    }

    /// Draw a pie slice using line segments from center
    pub fn drawPieSlice(self: Drawing, center_x: u32, center_y: u32, radius: u32, start_angle: f64, end_angle: f64, color: Color) void {
        const steps = 20;
        const angle_step = (end_angle - start_angle) / @as(f64, @floatFromInt(steps));

        for (0..steps) |i| {
            const angle = start_angle + @as(f64, @floatFromInt(i)) * angle_step;
            const x = center_x + @as(u32, @intFromFloat(@cos(angle) * @as(f64, @floatFromInt(radius))));
            const y = center_y + @as(u32, @intFromFloat(@sin(angle) * @as(f64, @floatFromInt(radius))));

            self.drawLine(center_x, center_y, x, y, color);
        }
    }

    /// Fill background with solid color
    pub fn fillBackground(self: Drawing, color: Color) void {
        const pixel_count = self.width * self.height;
        var i: usize = 0;
        while (i < pixel_count) : (i += 1) {
            const pixel_offset = i * 4;
            if (pixel_offset + 3 < self.image_data.len) {
                self.image_data[pixel_offset] = color.r;
                self.image_data[pixel_offset + 1] = color.g;
                self.image_data[pixel_offset + 2] = color.b;
                self.image_data[pixel_offset + 3] = color.a;
            }
        }
    }

    /// Set a single pixel color
    pub fn setPixel(self: Drawing, x: u32, y: u32, color: Color) void {
        if (x >= self.width or y >= self.height) return;

        const pixel_offset = (y * self.width + x) * 4;
        if (pixel_offset + 3 < self.image_data.len) {
            self.image_data[pixel_offset] = color.r;
            self.image_data[pixel_offset + 1] = color.g;
            self.image_data[pixel_offset + 2] = color.b;
            self.image_data[pixel_offset + 3] = color.a;
        }
    }
};

/// Chart axes drawing utilities
pub const AxesRenderer = struct {
    /// Draw X and Y axes with labels
    pub fn drawAxes(ctx: Drawing, chart_area: Bounds, y_range: base.Chart.Range, style: base.ChartStyle) void {
        // Draw Y-axis (left side of chart area)
        ctx.drawLine(@intCast(chart_area.x), @intCast(chart_area.y), @intCast(chart_area.x), @intCast(chart_area.y + chart_area.height), style.axis_color);

        // Draw X-axis (bottom of chart area)
        ctx.drawLine(@intCast(chart_area.x), @intCast(chart_area.y + chart_area.height), @intCast(chart_area.x + chart_area.width), @intCast(chart_area.y + chart_area.height), style.axis_color);

        // Draw tick marks on Y-axis
        const num_ticks = 5;
        for (0..num_ticks + 1) |i| {
            const y = chart_area.y + @as(i32, @intFromFloat(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(num_ticks)) * @as(f64, @floatFromInt(chart_area.height))));
            ctx.drawLine(@intCast(chart_area.x - 5), @intCast(y), @intCast(chart_area.x), @intCast(y), style.axis_color);
        }

        _ = y_range; // TODO: Use for tick labels
    }

    /// Draw grid lines
    pub fn drawGrid(ctx: Drawing, chart_area: Bounds, style: base.ChartStyle) void {
        const grid_lines = 5;

        // Vertical grid lines
        for (1..grid_lines) |i| {
            const x = chart_area.x + @as(i32, @intFromFloat(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(grid_lines)) * @as(f64, @floatFromInt(chart_area.width))));
            ctx.drawLine(@intCast(x), @intCast(chart_area.y), @intCast(x), @intCast(chart_area.y + chart_area.height), style.grid_color);
        }

        // Horizontal grid lines
        for (1..grid_lines) |i| {
            const y = chart_area.y + @as(i32, @intFromFloat(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(grid_lines)) * @as(f64, @floatFromInt(chart_area.height))));
            ctx.drawLine(@intCast(chart_area.x), @intCast(y), @intCast(chart_area.x + chart_area.width), @intCast(y), style.grid_color);
        }
    }
};

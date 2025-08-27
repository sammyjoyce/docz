//! Chart widget for data visualization
//! Provides multiple chart types with progressive enhancement:
//! - Kitty Graphics Protocol for high-quality charts
//! - Sixel graphics for compatibility
//! - Unicode block art for wide terminal support
//! - ASCII fallback for universal compatibility

const std = @import("std");
const renderer_mod = @import("../../core/renderer.zig");
const bounds_mod = @import("../../core/bounds.zig");
const events_mod = @import("../../core/events.zig");
const graphics_manager = @import("../../../term/graphics_manager.zig");
const unified = @import("../../../term/unified.zig");

const Renderer = renderer_mod.Renderer;
const RenderContext = renderer_mod.RenderContext;
const Bounds = bounds_mod.Bounds;
const Point = bounds_mod.Point;
const GraphicsMode = graphics_manager.GraphicsMode;

pub const ChartError = error{
    InvalidData,
    UnsupportedChartType,
    InsufficientSpace,
    RenderFailed,
} || std.mem.Allocator.Error;

pub const ChartType = enum {
    line,
    bar,
    area,
    pie,
    scatter,
    heatmap,
    candlestick,
};

pub const ChartRenderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    data: Chart,
    style: ChartStyle,
    config: Config,
    bounds: Bounds = Bounds.init(0, 0, 0, 0),

    // Graphics caching
    rendered_image: ?RenderedImage = null,
    graphics_dirty: bool = true,

    pub const Config = struct {
        chart_type: ChartType = .line,
        title: ?[]const u8 = null,
        x_axis_label: ?[]const u8 = null,
        y_axis_label: ?[]const u8 = null,
        show_legend: bool = true,
        show_grid: bool = true,
        show_axes: bool = true,
        show_values: bool = false,
        animation: bool = false,
        responsive: bool = true,
    };

    pub const Chart = struct {
        series: []Series,
        x_labels: ?[][]const u8 = null,
        y_range: ?Range = null, // Auto-calculate if null

        pub const Series = struct {
            name: []const u8,
            values: []f64,
            color: ?Color = null,
            style: SeriesStyle = .solid,

            pub const SeriesStyle = enum {
                solid,
                dashed,
                dotted,
                points,
            };
        };

        pub const Range = struct {
            min: f64,
            max: f64,
        };
    };

    pub const ChartStyle = struct {
        backgroundColor: Color = Color.init(255, 255, 255), // White
        text_color: Color = Color.init(0, 0, 0), // Black
        grid_color: Color = Color.init(200, 200, 200), // Light gray
        axis_color: Color = Color.init(100, 100, 100), // Dark gray

        // Default series colors (will cycle through these)
        series_colors: []const Color = &[_]Color{
            Color.init(31, 119, 180), // Blue
            Color.init(255, 127, 14), // Orange
            Color.init(44, 160, 44), // Green
            Color.init(214, 39, 40), // Red
            Color.init(148, 103, 189), // Purple
            Color.init(140, 86, 75), // Brown
            Color.init(227, 119, 194), // Pink
            Color.init(127, 127, 127), // Gray
        },

        font_size: u32 = 12,
        line_width: f32 = 2.0,
        point_size: f32 = 4.0,
        padding: Padding = Padding{ .left = 50, .right = 20, .top = 30, .bottom = 40 },

        pub const Padding = struct {
            left: u32,
            right: u32,
            top: u32,
            bottom: u32,
        };
    };

    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8 = 255,

        pub fn init(r: u8, g: u8, b: u8) Color {
            return Color{ .r = r, .g = g, .b = b };
        }

        pub fn toRgb(self: Color) u32 {
            return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
        }
    };

    const RenderedImage = struct {
        data: []u8,
        width: u32,
        height: u32,
        format: ImageFormat,

        const ImageFormat = enum {
            RGBA,
            RGB,
            PNG,
        };

        pub fn deinit(self: *RenderedImage, allocator: std.mem.Allocator) void {
            allocator.free(self.data);
        }
    };

    pub fn init(allocator: std.mem.Allocator, data: Chart, config: Config) Self {
        return Self{
            .allocator = allocator,
            .data = data,
            .style = ChartStyle{},
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.rendered_image) |*image| {
            image.deinit(self.allocator);
        }
        // Note: We don't own the data, so we don't free it
    }

    pub fn setData(self: *Self, data: Chart) void {
        self.data = data;
        self.graphics_dirty = true;
    }

    pub fn setStyle(self: *Self, style: ChartStyle) void {
        self.style = style;
        self.graphics_dirty = true;
    }

    pub fn setBounds(self: *Self, bounds: Bounds) void {
        self.bounds = bounds;
        self.graphics_dirty = true;
    }

    pub fn render(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        self.bounds = ctx.bounds;

        // Determine the best rendering mode based on terminal capabilities
        const graphics_mode = self.detectGraphicsMode(renderer);

        switch (graphics_mode) {
            .kitty, .sixel => try self.renderGraphics(renderer, ctx, graphics_mode),
            .unicode => try self.renderUnicodeBlocks(renderer, ctx),
            .ascii => try self.renderAsciiArt(renderer, ctx),
            .none => try self.renderTextOnly(renderer, ctx),
        }
    }

    fn detectGraphicsMode(self: *Self, renderer: *Renderer) GraphicsMode {
        _ = self;

        // Try to get terminal capabilities from renderer
        if (renderer.getTermCaps()) |caps| {
            return GraphicsMode.detect(caps);
        }

        // Default to unicode if we can't detect
        return .unicode;
    }

    fn renderGraphics(self: *Self, renderer: *Renderer, ctx: RenderContext, mode: GraphicsMode) !void {
        // Generate or use cached image
        if (self.graphics_dirty or self.rendered_image == null) {
            try self.generateImage(mode);
            self.graphics_dirty = false;
        }

        if (self.rendered_image) |image| {
            // Use the graphics system to display the image
            // This would integrate with the existing graphics widget
            try self.displayImage(renderer, ctx, &image);
        }
    }

    fn generateImage(self: *Self, _: GraphicsMode) !void {
        // Free existing image if any
        if (self.rendered_image) |*image| {
            image.deinit(self.allocator);
            self.rendered_image = null;
        }

        // Calculate image dimensions based on terminal bounds
        // Each terminal cell is approximately 8x16 pixels
        const image_width = self.bounds.width * 8;
        const image_height = self.bounds.height * 16;

        // Create RGBA image buffer
        const pixel_count = image_width * image_height;
        const image_data = try self.allocator.alloc(u8, pixel_count * 4); // RGBA

        // Clear background
        var i: usize = 0;
        while (i < pixel_count) : (i += 1) {
            const pixel_offset = i * 4;
            image_data[pixel_offset] = self.style.backgroundColor.r;
            image_data[pixel_offset + 1] = self.style.backgroundColor.g;
            image_data[pixel_offset + 2] = self.style.backgroundColor.b;
            image_data[pixel_offset + 3] = self.style.backgroundColor.a;
        }

        // Draw chart based on type
        switch (self.config.chart_type) {
            .line => try self.drawLineChart(image_data, image_width, image_height),
            .bar => try self.drawBarChart(image_data, image_width, image_height),
            .area => try self.drawAreaChart(image_data, image_width, image_height),
            .pie => try self.drawPieChart(image_data, image_width, image_height),
            .scatter => try self.drawScatterChart(image_data, image_width, image_height),
            .heatmap => try self.drawHeatmapChart(image_data, image_width, image_height),
            .candlestick => try self.drawCandlestickChart(image_data, image_width, image_height),
        }

        self.rendered_image = RenderedImage{
            .data = image_data,
            .width = image_width,
            .height = image_height,
            .format = .RGBA,
        };
    }

    fn drawLineChart(self: *Self, image_data: []u8, width: u32, height: u32) !void {
        if (self.data.series.len == 0) return;

        const chart_area = self.getChartArea(width, height);

        // Calculate Y range if not provided
        const y_range = self.data.y_range orelse self.calculateYRange();

        for (self.data.series, 0..) |series, series_idx| {
            const color = series.color orelse self.getSeriesColor(series_idx);

            if (series.values.len < 2) continue;

            // Draw line segments
            for (0..series.values.len - 1) |i| {
                const x1 = chart_area.x + @as(u32, @intFromFloat(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(series.values.len - 1)) * @as(f64, @floatFromInt(chart_area.width))));
                const y1 = chart_area.y + chart_area.height - @as(u32, @intFromFloat((series.values[i] - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_area.height))));

                const x2 = chart_area.x + @as(u32, @intFromFloat(@as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(series.values.len - 1)) * @as(f64, @floatFromInt(chart_area.width))));
                const y2 = chart_area.y + chart_area.height - @as(u32, @intFromFloat((series.values[i + 1] - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_area.height))));

                self.drawLine(image_data, width, height, x1, y1, x2, y2, color);
            }

            // Draw points if configured
            if (series.style == .points) {
                for (series.values, 0..) |value, i| {
                    const x = chart_area.x + @as(u32, @intFromFloat(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(series.values.len - 1)) * @as(f64, @floatFromInt(chart_area.width))));
                    const y = chart_area.y + chart_area.height - @as(u32, @intFromFloat((value - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_area.height))));
                    self.drawPoint(image_data, width, height, x, y, color);
                }
            }
        }

        // Draw axes and grid
        if (self.config.show_axes) {
            try self.drawAxes(image_data, width, height, chart_area, y_range);
        }

        if (self.config.show_grid) {
            try self.drawGrid(image_data, width, height, chart_area);
        }
    }

    fn drawBarChart(self: *Self, image_data: []u8, width: u32, height: u32) !void {
        if (self.data.series.len == 0) return;

        const chart_area = self.getChartArea(width, height);
        const y_range = self.data.y_range orelse self.calculateYRange();

        const bar_width = chart_area.width / @as(u32, @intCast(self.data.series[0].values.len * self.data.series.len));
        const bar_spacing = bar_width / 4;

        for (self.data.series, 0..) |series, series_idx| {
            const color = series.color orelse self.getSeriesColor(series_idx);

            for (series.values, 0..) |value, i| {
                const x_offset = @as(u32, @intCast(i)) * (bar_width * @as(u32, @intCast(self.data.series.len)) + bar_spacing);
                const x = chart_area.x + x_offset + @as(u32, @intCast(series_idx)) * bar_width;

                const bar_height = @as(u32, @intFromFloat((value - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_area.height))));
                const y = chart_area.y + chart_area.height - bar_height;

                self.drawRect(image_data, width, height, x, y, bar_width, bar_height, color);
            }
        }

        // Draw axes and grid
        if (self.config.show_axes) {
            try self.drawAxes(image_data, width, height, chart_area, y_range);
        }

        if (self.config.show_grid) {
            try self.drawGrid(image_data, width, height, chart_area);
        }
    }

    fn drawAreaChart(self: *Self, image_data: []u8, width: u32, height: u32) !void {
        // Similar to line chart but fill areas below the lines
        try self.drawLineChart(image_data, width, height);

        // Add area filling logic here
        // This would involve polygon filling which is more complex
    }

    fn drawPieChart(self: *Self, image_data: []u8, width: u32, height: u32) !void {
        if (self.data.series.len == 0 or self.data.series[0].values.len == 0) return;

        const chart_area = self.getChartArea(width, height);
        const center_x = chart_area.x + chart_area.width / 2;
        const center_y = chart_area.y + chart_area.height / 2;
        const radius = @min(chart_area.width, chart_area.height) / 2 - 10;

        // Calculate total value
        var total: f64 = 0;
        for (self.data.series[0].values) |value| {
            total += value;
        }

        // Draw pie slices
        var current_angle: f64 = 0;
        for (self.data.series[0].values, 0..) |value, i| {
            const color = self.getSeriesColor(i);
            const slice_angle = (value / total) * 2 * std.math.pi;

            self.drawPieSlice(image_data, width, height, center_x, center_y, radius, current_angle, current_angle + slice_angle, color);
            current_angle += slice_angle;
        }
    }

    fn drawScatterChart(self: *Self, image_data: []u8, width: u32, height: u32) !void {
        // Similar to line chart but only draw points
        if (self.data.series.len == 0) return;

        const chart_area = self.getChartArea(width, height);
        const y_range = self.data.y_range orelse self.calculateYRange();

        for (self.data.series, 0..) |series, series_idx| {
            const color = series.color orelse self.getSeriesColor(series_idx);

            for (series.values, 0..) |value, i| {
                const x = chart_area.x + @as(u32, @intFromFloat(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(series.values.len - 1)) * @as(f64, @floatFromInt(chart_area.width))));
                const y = chart_area.y + chart_area.height - @as(u32, @intFromFloat((value - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_area.height))));
                self.drawPoint(image_data, width, height, x, y, color);
            }
        }
    }

    fn drawHeatmapChart(self: *Self, image_data: []u8, width: u32, height: u32) !void {
        // Implement heatmap visualization
        _ = self;
        _ = image_data;
        _ = width;
        _ = height;
        // TODO: Implement heatmap rendering
    }

    fn drawCandlestickChart(self: *Self, image_data: []u8, width: u32, height: u32) !void {
        // Implement candlestick chart for financial data
        _ = self;
        _ = image_data;
        _ = width;
        _ = height;
        // TODO: Implement candlestick rendering
    }

    // Helper drawing functions
    fn drawLine(self: *Self, image_data: []u8, width: u32, height: u32, x1: u32, y1: u32, x2: u32, y2: u32, color: Color) void {
        _ = self;

        // Bresenham's line algorithm
        const dx = @abs(@as(i32, @intCast(x2)) - @as(i32, @intCast(x1)));
        const dy = @abs(@as(i32, @intCast(y2)) - @as(i32, @intCast(y1)));
        const sx: i32 = if (x1 < x2) 1 else -1;
        const sy: i32 = if (y1 < y2) 1 else -1;
        var err = dx - dy;

        var x = @as(i32, @intCast(x1));
        var y = @as(i32, @intCast(y1));

        while (true) {
            if (x >= 0 and x < width and y >= 0 and y < height) {
                const pixel_offset = (@as(u32, @intCast(y)) * width + @as(u32, @intCast(x))) * 4;
                if (pixel_offset + 3 < image_data.len) {
                    image_data[pixel_offset] = color.r;
                    image_data[pixel_offset + 1] = color.g;
                    image_data[pixel_offset + 2] = color.b;
                    image_data[pixel_offset + 3] = color.a;
                }
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

    fn drawRect(self: *Self, image_data: []u8, width: u32, height: u32, x: u32, y: u32, rect_width: u32, rect_height: u32, color: Color) void {
        _ = self;

        for (0..rect_height) |row| {
            for (0..rect_width) |col| {
                const px = x + @as(u32, @intCast(col));
                const py = y + @as(u32, @intCast(row));

                if (px < width and py < height) {
                    const pixel_offset = (py * width + px) * 4;
                    if (pixel_offset + 3 < image_data.len) {
                        image_data[pixel_offset] = color.r;
                        image_data[pixel_offset + 1] = color.g;
                        image_data[pixel_offset + 2] = color.b;
                        image_data[pixel_offset + 3] = color.a;
                    }
                }
            }
        }
    }

    fn drawPoint(self: *Self, image_data: []u8, width: u32, height: u32, x: u32, y: u32, color: Color) void {
        const point_radius = @as(u32, @intFromFloat(self.style.point_size));
        self.drawRect(image_data, width, height, x -| point_radius / 2, y -| point_radius / 2, point_radius, point_radius, color);
    }

    fn drawPieSlice(self: *Self, image_data: []u8, width: u32, height: u32, center_x: u32, center_y: u32, radius: u32, start_angle: f64, end_angle: f64, color: Color) void {

        // Simple pie slice drawing using line segments
        const steps = 20;
        const angle_step = (end_angle - start_angle) / @as(f64, @floatFromInt(steps));

        for (0..steps) |i| {
            const angle = start_angle + @as(f64, @floatFromInt(i)) * angle_step;
            const x = center_x + @as(u32, @intFromFloat(@cos(angle) * @as(f64, @floatFromInt(radius))));
            const y = center_y + @as(u32, @intFromFloat(@sin(angle) * @as(f64, @floatFromInt(radius))));

            self.drawLine(image_data, width, height, center_x, center_y, x, y, color);
        }
    }

    // Helper functions for chart calculation
    fn getChartArea(self: *Self, width: u32, height: u32) Bounds {
        return Bounds.init(
            self.style.padding.left,
            self.style.padding.top,
            width - self.style.padding.left - self.style.padding.right,
            height - self.style.padding.top - self.style.padding.bottom,
        );
    }

    fn calculateYRange(self: *Self) Chart.Range {
        var min_val: f64 = std.math.inf(f64);
        var max_val: f64 = -std.math.inf(f64);

        for (self.data.series) |series| {
            for (series.values) |value| {
                if (value < min_val) min_val = value;
                if (value > max_val) max_val = value;
            }
        }

        // Add some padding
        const range = max_val - min_val;
        const padding = range * 0.1;

        return Chart.Range{
            .min = min_val - padding,
            .max = max_val + padding,
        };
    }

    fn getSeriesColor(self: *Self, series_index: usize) Color {
        return self.style.series_colors[series_index % self.style.series_colors.len];
    }

    fn drawAxes(self: *Self, image_data: []u8, width: u32, height: u32, chart_area: Bounds, y_range: Chart.Range) !void {
        // Draw X axis
        self.drawLine(image_data, width, height, chart_area.x, chart_area.y + chart_area.height, chart_area.x + chart_area.width, chart_area.y + chart_area.height, self.style.axis_color);

        // Draw Y axis
        self.drawLine(image_data, width, height, chart_area.x, chart_area.y, chart_area.x, chart_area.y + chart_area.height, self.style.axis_color);

        _ = y_range; // TODO: Add axis labels and tick marks
    }

    fn drawGrid(self: *Self, image_data: []u8, width: u32, height: u32, chart_area: Bounds) !void {
        const grid_lines = 5;

        // Vertical grid lines
        for (1..grid_lines) |i| {
            const x = chart_area.x + (chart_area.width * @as(u32, @intCast(i))) / grid_lines;
            self.drawLine(image_data, width, height, x, chart_area.y, x, chart_area.y + chart_area.height, self.style.grid_color);
        }

        // Horizontal grid lines
        for (1..grid_lines) |i| {
            const y = chart_area.y + (chart_area.height * @as(u32, @intCast(i))) / grid_lines;
            self.drawLine(image_data, width, height, chart_area.x, y, chart_area.x + chart_area.width, y, self.style.grid_color);
        }
    }

    fn displayImage(self: *Self, renderer: *Renderer, ctx: RenderContext, image: *const RenderedImage) !void {
        _ = self;
        _ = renderer;
        _ = ctx;
        _ = image;
        // TODO: Integrate with the graphics system to actually display the image
        // This would use the Kitty graphics protocol or Sixel graphics
    }

    // Fallback rendering methods
    fn renderUnicodeBlocks(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        // Use Unicode block characters to create a simplified chart
        switch (self.config.chart_type) {
            .line => try self.renderUnicodeLineChart(renderer, ctx),
            .bar => try self.renderUnicodeBarChart(renderer, ctx),
            else => try self.renderTextOnly(renderer, ctx),
        }
    }

    fn renderUnicodeLineChart(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        if (self.data.series.len == 0) return;

        const chart_height = ctx.bounds.height - 4; // Leave space for axes and labels
        const chart_width = ctx.bounds.width - 10; // Leave space for Y axis labels

        // Create a simple line chart using Unicode characters
        var buffer = try self.allocator.alloc([]u8, chart_height);
        defer self.allocator.free(buffer);

        for (buffer) |*row| {
            row.* = try self.allocator.alloc(u8, chart_width);
            @memset(row.*, ' ');
        }
        defer {
            for (buffer) |row| {
                self.allocator.free(row);
            }
        }

        // Plot data points
        const series = self.data.series[0]; // Just use first series for simplicity
        const y_range = self.data.y_range orelse self.calculateYRange();

        for (series.values, 0..) |value, i| {
            const x = (i * chart_width) / series.values.len;
            const y = chart_height - @as(u32, @intFromFloat((value - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_height)))) - 1;

            if (x < chart_width and y < chart_height) {
                buffer[y][x] = '*';
            }
        }

        // Render the buffer
        try renderer.moveCursor(ctx.bounds.x, ctx.bounds.y);
        try renderer.writeText("{s}", .{self.config.title orelse "Chart"});

        for (buffer, 0..) |row, i| {
            try renderer.moveCursor(ctx.bounds.x, ctx.bounds.y + @as(u32, @intCast(i)) + 2);
            try renderer.writeText("{s}", .{row});
        }
    }

    fn renderUnicodeBarChart(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        if (self.data.series.len == 0) return;

        const series = self.data.series[0];
        const y_range = self.data.y_range orelse self.calculateYRange();
        const chart_height = ctx.bounds.height - 4;

        // Render title
        try renderer.moveCursor(ctx.bounds.x, ctx.bounds.y);
        try renderer.writeText("{s}", .{self.config.title orelse "Bar Chart"});

        // Render bars
        for (series.values, 0..) |value, i| {
            const bar_height = @as(u32, @intFromFloat((value - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_height))));

            // Draw bar using Unicode blocks
            for (0..bar_height) |j| {
                const y = ctx.bounds.y + ctx.bounds.height - @as(u32, @intCast(j)) - 2;
                const x = ctx.bounds.x + @as(u32, @intCast(i)) * 3 + 2;
                try renderer.moveCursor(x, y);
                try renderer.writeText("█");
            }
        }
    }

    fn renderAsciiArt(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        // Simplified ASCII chart using basic characters
        switch (self.config.chart_type) {
            .line => try self.renderAsciiLineChart(renderer, ctx),
            .bar => try self.renderAsciiBarChart(renderer, ctx),
            else => try self.renderTextOnly(renderer, ctx),
        }
    }

    fn renderAsciiLineChart(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        // Similar to Unicode version but with ASCII characters only
        try self.renderUnicodeLineChart(renderer, ctx); // Reuse for now
    }

    fn renderAsciiBarChart(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        if (self.data.series.len == 0) return;

        const series = self.data.series[0];
        const y_range = self.data.y_range orelse self.calculateYRange();
        const chart_height = ctx.bounds.height - 4;

        // Render title
        try renderer.moveCursor(ctx.bounds.x, ctx.bounds.y);
        try renderer.writeText("{s}", .{self.config.title orelse "Bar Chart"});

        // Render bars using ASCII characters
        for (series.values, 0..) |value, i| {
            const bar_height = @as(u32, @intFromFloat((value - y_range.min) / (y_range.max - y_range.min) * @as(f64, @floatFromInt(chart_height))));

            // Draw bar using ASCII blocks
            for (0..bar_height) |j| {
                const y = ctx.bounds.y + ctx.bounds.height - @as(u32, @intCast(j)) - 2;
                const x = ctx.bounds.x + @as(u32, @intCast(i)) * 3 + 2;
                try renderer.moveCursor(x, y);
                try renderer.writeText("#");
            }
        }
    }

    fn renderTextOnly(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        // Fallback to simple text representation
        try renderer.moveCursor(ctx.bounds.x, ctx.bounds.y);
        try renderer.writeText("{s}", .{self.config.title orelse "Chart"});

        var row: u32 = 1;
        for (self.data.series) |series| {
            try renderer.moveCursor(ctx.bounds.x, ctx.bounds.y + row);
            try renderer.writeText("{s}: ", .{series.name});

            for (series.values, 0..) |value, i| {
                if (i > 0) try renderer.writeText(", ");
                try renderer.writeText("{d:.2}", .{value});
            }

            row += 1;
        }
    }

    pub fn handleInput(self: *Self, event: anytype) !void {
        // Handle chart-specific input events
        _ = self;
        _ = event;
        // TODO: Implement interactive features like zooming, panning, etc.
    }
};

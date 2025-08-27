//! Adaptive Graphics Renderer
//!
//! This module provides smart rendering that adapts to terminal capabilities,
//! progressively enhancing from ASCII to full Kitty graphics protocol.

const std = @import("std");
const graphics_manager = @import("../../term/graphics_manager.zig");
const unified = @import("../../term/unified.zig");
const canvas_engine = @import("../../core/canvas_engine.zig");

/// Adaptive renderer that selects optimal rendering strategy
pub const AdaptiveRenderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    graphics: *graphics_manager.GraphicsManager,
    terminal: *unified.Terminal,
    rendering_tier: RenderingTier,

    pub const RenderingTier = enum {
        ultra, // Kitty graphics with animations
        enhanced, // Sixel graphics
        standard, // Unicode blocks and braille
        minimal, // ASCII art only

        pub fn fromGraphicsMode(mode: graphics_manager.GraphicsMode) RenderingTier {
            return switch (mode) {
                .kitty => .ultra,
                .sixel => .enhanced,
                .unicode => .standard,
                .ascii, .none => .minimal,
            };
        }
    };

    pub const RenderableContent = union(enum) {
        realtime_chart: RealtimeChart,
        interactive_plot: InteractivePlot,
        drawing_canvas: DrawingCanvas,
        data_visualization: DataVisualization,

        pub const RealtimeChart = struct {
            data_stream: []const f64,
            window_size: u32 = 100,
            chart_type: ChartType = .line,
            update_rate_ms: u32 = 100,

            pub const ChartType = enum { line, bar, area, scatter };
        };

        pub const InteractivePlot = struct {
            datasets: []const Dataset,
            viewport: PlotViewport,
            interaction_enabled: bool = true,

            pub const Dataset = struct {
                name: []const u8,
                points: []const Point2D,
                color: unified.Color,
                style: PlotStyle = .line,
            };

            pub const Point2D = struct { x: f64, y: f64 };

            pub const PlotViewport = struct {
                min_x: f64,
                max_x: f64,
                min_y: f64,
                max_y: f64,
                zoom: f32 = 1.0,
            };

            pub const PlotStyle = enum { line, scatter, bar };
        };

        pub const DrawingCanvas = struct {
            layers: []const DrawingLayer,
            tools: DrawingTools,

            pub const DrawingLayer = struct {
                strokes: []const Stroke,
                visible: bool = true,
                opacity: f32 = 1.0,
            };

            pub const Stroke = struct {
                points: []const Point2D,
                color: unified.Color,
                width: f32,
                style: StrokeStyle = .solid,
            };

            const Point2D = struct { x: f32, y: f32 };

            pub const DrawingTools = struct {
                active_tool: Tool = .brush,
                brush_size: f32 = 2.0,
                active_color: unified.Color = unified.Colors.WHITE,

                pub const Tool = enum { brush, line, rectangle, circle, eraser };
            };

            pub const StrokeStyle = enum { solid, dashed, dotted };
        };

        pub const DataVisualization = struct {
            viz_type: VisualizationType,
            data: VisualizationData,
            styling: VisualizationStyling,

            pub const VisualizationType = enum {
                heatmap,
                scatter_matrix,
                histogram,
                box_plot,
                parallel_coordinates,
            };

            pub const VisualizationData = union(enum) {
                matrix: []const []const f64,
                series: []const DataSeries,
                histogram: HistogramData,

                pub const DataSeries = struct {
                    name: []const u8,
                    values: []const f64,
                };

                pub const HistogramData = struct {
                    bins: []const f64,
                    counts: []const u32,
                };
            };

            pub const VisualizationStyling = struct {
                color_scheme: ColorScheme = .viridis,
                show_labels: bool = true,
                show_grid: bool = true,
                animation: bool = false,

                pub const ColorScheme = enum { viridis, plasma, inferno, magma, grayscale };
            };
        };
    };

    pub fn init(allocator: std.mem.Allocator, graphics: *graphics_manager.GraphicsManager, terminal: *unified.Terminal) Self {
        const graphics_mode = graphics.getMode();
        const rendering_tier = RenderingTier.fromGraphicsMode(graphics_mode);

        return Self{
            .allocator = allocator,
            .graphics = graphics,
            .terminal = terminal,
            .rendering_tier = rendering_tier,
        };
    }

    /// Render content using the best available method
    pub fn render(self: *Self, content: RenderableContent, bounds: unified.Rect) !void {
        switch (content) {
            .realtime_chart => |chart| try self.renderRealtimeChart(chart, bounds),
            .interactive_plot => |plot| try self.renderInteractivePlot(plot, bounds),
            .drawing_canvas => |canvas| try self.renderDrawingCanvas(canvas, bounds),
            .data_visualization => |viz| try self.renderDataVisualization(viz, bounds),
        }
    }

    fn renderRealtimeChart(self: *Self, chart: RenderableContent.RealtimeChart, bounds: unified.Rect) !void {
        switch (self.rendering_tier) {
            .ultra => try self.renderChartUltra(chart, bounds),
            .enhanced => try self.renderChartEnhanced(chart, bounds),
            .standard => try self.renderChartStandard(chart, bounds),
            .minimal => try self.renderChartMinimal(chart, bounds),
        }
    }

    fn renderInteractivePlot(self: *Self, plot: RenderableContent.InteractivePlot, bounds: unified.Rect) !void {
        switch (self.rendering_tier) {
            .ultra => try self.renderPlotUltra(plot, bounds),
            .enhanced => try self.renderPlotEnhanced(plot, bounds),
            .standard => try self.renderPlotStandard(plot, bounds),
            .minimal => try self.renderPlotMinimal(plot, bounds),
        }
    }

    fn renderDrawingCanvas(self: *Self, canvas: RenderableContent.DrawingCanvas, bounds: unified.Rect) !void {
        switch (self.rendering_tier) {
            .ultra => try self.renderCanvasUltra(canvas, bounds),
            .enhanced => try self.renderCanvasEnhanced(canvas, bounds),
            .standard => try self.renderCanvasStandard(canvas, bounds),
            .minimal => try self.renderCanvasMinimal(canvas, bounds),
        }
    }

    fn renderDataVisualization(self: *Self, viz: RenderableContent.DataVisualization, bounds: unified.Rect) !void {
        switch (viz.viz_type) {
            .heatmap => try self.renderHeatmap(viz, bounds),
            .scatter_matrix => try self.renderScatterMatrix(viz, bounds),
            .histogram => try self.renderHistogram(viz, bounds),
            .box_plot => try self.renderBoxPlot(viz, bounds),
            .parallel_coordinates => try self.renderParallelCoordinates(viz, bounds),
        }
    }

    // Ultra-quality renderings (Kitty graphics)
    fn renderChartUltra(self: *Self, chart: RenderableContent.RealtimeChart, bounds: unified.Rect) !void {
        // Generate high-resolution chart with smooth animations
        const image_width = @as(u32, @intCast(bounds.width)) * 16;
        const image_height = @as(u32, @intCast(bounds.height)) * 32;

        const chart_image = try self.generateChartImage(chart, image_width, image_height);
        defer self.allocator.free(chart_image);

        const image_id = try self.graphics.createImage(chart_image, image_width, image_height, .rgba32);
        defer self.graphics.removeImage(image_id);

        try self.graphics.renderImage(image_id, .{ .x = bounds.x, .y = bounds.y }, .{
            .max_width = @as(u32, @intCast(bounds.width)),
            .max_height = @as(u32, @intCast(bounds.height)),
            .persistent = true,
        });

        // Add animation effects for realtime updates
        if (chart.update_rate_ms < 500) {
            try self.addChartAnimation(chart, bounds);
        }
    }

    fn renderChartEnhanced(self: *Self, chart: RenderableContent.RealtimeChart, bounds: unified.Rect) !void {
        // Use Sixel graphics with optimized palette
        const sixel_data = try self.generateSixelChart(chart, bounds);
        defer self.allocator.free(sixel_data);

        try self.terminal.moveTo(bounds.x, bounds.y);
        try self.terminal.print(sixel_data, null);
    }

    fn renderChartStandard(self: *Self, chart: RenderableContent.RealtimeChart, bounds: unified.Rect) !void {
        // Use Unicode blocks and braille patterns for high-density visualization
        try self.renderChartWithUnicode(chart, bounds);
    }

    fn renderChartMinimal(self: *Self, chart: RenderableContent.RealtimeChart, bounds: unified.Rect) !void {
        // ASCII art fallback
        try self.renderChartWithASCII(chart, bounds);
    }

    // Plot rendering implementations
    fn renderPlotUltra(self: *Self, plot: RenderableContent.InteractivePlot, bounds: unified.Rect) !void {
        // High-quality interactive plot with zoom/pan capabilities
        const plot_image = try self.generatePlotImage(plot, bounds);
        defer self.allocator.free(plot_image);

        const image_id = try self.graphics.createImage(plot_image, @as(u32, @intCast(bounds.width)) * 16, @as(u32, @intCast(bounds.height)) * 32, .rgba32);
        defer self.graphics.removeImage(image_id);

        try self.graphics.renderImage(image_id, .{ .x = bounds.x, .y = bounds.y }, .{});

        // Add interactive overlays
        if (plot.interaction_enabled) {
            try self.renderPlotInteractionOverlay(plot, bounds);
        }
    }

    fn renderPlotEnhanced(self: *Self, plot: RenderableContent.InteractivePlot, bounds: unified.Rect) !void {
        // Sixel-based plot rendering
        _ = self;
        _ = plot;
        _ = bounds;
        // Implementation for Sixel plot rendering
    }

    fn renderPlotStandard(self: *Self, plot: RenderableContent.InteractivePlot, bounds: unified.Rect) !void {
        // Unicode character-based plotting
        try self.renderPlotWithBraille(plot, bounds);
    }

    fn renderPlotMinimal(self: *Self, plot: RenderableContent.InteractivePlot, bounds: unified.Rect) !void {
        // ASCII scatter plot
        try self.renderPlotWithASCII(plot, bounds);
    }

    // Canvas rendering implementations
    fn renderCanvasUltra(self: *Self, canvas: RenderableContent.DrawingCanvas, bounds: unified.Rect) !void {
        // High-quality drawing canvas with pressure sensitivity and anti-aliasing
        const canvas_image = try self.generateCanvasImage(canvas, bounds);
        defer self.allocator.free(canvas_image);

        const image_id = try self.graphics.createImage(canvas_image, @as(u32, @intCast(bounds.width)) * 16, @as(u32, @intCast(bounds.height)) * 32, .rgba32);
        defer self.graphics.removeImage(image_id);

        try self.graphics.renderImage(image_id, .{ .x = bounds.x, .y = bounds.y }, .{});
    }

    fn renderCanvasEnhanced(self: *Self, canvas: RenderableContent.DrawingCanvas, bounds: unified.Rect) !void {
        // Sixel-based canvas
        _ = self;
        _ = canvas;
        _ = bounds;
    }

    fn renderCanvasStandard(self: *Self, canvas: RenderableContent.DrawingCanvas, bounds: unified.Rect) !void {
        // Unicode block-based canvas
        for (canvas.layers) |layer| {
            if (!layer.visible) continue;
            try self.renderDrawingLayerWithBlocks(layer, bounds);
        }
    }

    fn renderCanvasMinimal(self: *Self, canvas: RenderableContent.DrawingCanvas, bounds: unified.Rect) !void {
        // ASCII canvas
        for (canvas.layers) |layer| {
            if (!layer.visible) continue;
            try self.renderDrawingLayerWithASCII(layer, bounds);
        }
    }

    // Specialized visualization renderers
    fn renderHeatmap(self: *Self, viz: RenderableContent.DataVisualization, bounds: unified.Rect) !void {
        switch (self.rendering_tier) {
            .ultra, .enhanced => {
                // Generate color-mapped heatmap image
                const heatmap_image = try self.generateHeatmapImage(viz, bounds);
                defer self.allocator.free(heatmap_image);

                const image_id = try self.graphics.createImage(heatmap_image, @as(u32, @intCast(bounds.width)) * 8, @as(u32, @intCast(bounds.height)) * 16, .rgb24);
                defer self.graphics.removeImage(image_id);

                try self.graphics.renderImage(image_id, .{ .x = bounds.x, .y = bounds.y }, .{});
            },
            .standard => {
                // Use Unicode blocks with colors
                try self.renderHeatmapWithBlocks(viz, bounds);
            },
            .minimal => {
                // ASCII intensity heatmap
                try self.renderHeatmapWithASCII(viz, bounds);
            },
        }
    }

    // Implementation helper methods (simplified for brevity)
    fn generateChartImage(self: *Self, chart: RenderableContent.RealtimeChart, width: u32, height: u32) ![]u8 {
        const image_data = try self.allocator.alloc(u8, width * height * 4); // RGBA

        // Clear with dark background
        var i: usize = 0;
        while (i < image_data.len) : (i += 4) {
            image_data[i] = 20; // R
            image_data[i + 1] = 20; // G
            image_data[i + 2] = 20; // B
            image_data[i + 3] = 255; // A
        }

        // Draw chart data based on type
        switch (chart.chart_type) {
            .line => try self.drawLineChart(image_data, width, height, chart.data_stream),
            .bar => try self.drawBarChart(image_data, width, height, chart.data_stream),
            .area => try self.drawAreaChart(image_data, width, height, chart.data_stream),
            .scatter => try self.drawScatterChart(image_data, width, height, chart.data_stream),
        }

        return image_data;
    }

    fn drawLineChart(self: *Self, image_data: []u8, width: u32, height: u32, data: []const f64) !void {
        _ = self;

        if (data.len < 2) return;

        // Find data range
        var min_val = data[0];
        var max_val = data[0];
        for (data[1..]) |val| {
            min_val = @min(min_val, val);
            max_val = @max(max_val, val);
        }

        const range = max_val - min_val;
        if (range == 0) return;

        // Draw line connecting data points
        for (data[1..], 1..) |val, i| {
            const prev_val = data[i - 1];

            const x1 = @as(u32, @intFromFloat(@as(f64, @floatFromInt(i - 1)) / @as(f64, @floatFromInt(data.len - 1)) * @as(f64, @floatFromInt(width))));
            const y1 = height - @as(u32, @intFromFloat((prev_val - min_val) / range * @as(f64, @floatFromInt(height))));
            const x2 = @as(u32, @intFromFloat(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(data.len - 1)) * @as(f64, @floatFromInt(width))));
            const y2 = height - @as(u32, @intFromFloat((val - min_val) / range * @as(f64, @floatFromInt(height))));

            drawLineRGBA(image_data, width, height, x1, y1, x2, y2, .{ .r = 100, .g = 149, .b = 237, .a = 255 });
        }
    }

    fn drawBarChart(self: *Self, image_data: []u8, width: u32, height: u32, data: []const f64) !void {
        _ = self;

        if (data.len == 0) return;

        var max_val = data[0];
        for (data[1..]) |val| {
            max_val = @max(max_val, val);
        }

        if (max_val == 0) return;

        const bar_width = width / @as(u32, @intCast(data.len));

        for (data, 0..) |val, i| {
            const bar_height = @as(u32, @intFromFloat(val / max_val * @as(f64, @floatFromInt(height))));
            const x = @as(u32, @intCast(i)) * bar_width;
            const y = height - bar_height;

            fillRectRGBA(image_data, width, height, x, y, bar_width, bar_height, .{ .r = 50, .g = 205, .b = 50, .a = 255 });
        }
    }

    fn drawAreaChart(self: *Self, image_data: []u8, width: u32, height: u32, data: []const f64) !void {
        // First draw the line chart
        try self.drawLineChart(image_data, width, height, data);

        // Then fill the area below
        if (data.len < 2) return;

        var min_val = data[0];
        var max_val = data[0];
        for (data[1..]) |val| {
            min_val = @min(min_val, val);
            max_val = @max(max_val, val);
        }

        const range = max_val - min_val;
        if (range == 0) return;

        // Fill area with transparency
        for (data, 0..) |val, i| {
            const x = @as(u32, @intFromFloat(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(data.len - 1)) * @as(f64, @floatFromInt(width))));
            const y = height - @as(u32, @intFromFloat((val - min_val) / range * @as(f64, @floatFromInt(height))));

            // Draw vertical line from bottom to data point with transparency
            var fill_y = y;
            while (fill_y < height) : (fill_y += 1) {
                if (x < width and fill_y < height) {
                    const pixel_idx = (fill_y * width + x) * 4;
                    if (pixel_idx + 3 < image_data.len) {
                        // Blend with existing color
                        image_data[pixel_idx] = @min(255, image_data[pixel_idx] + 30); // R
                        image_data[pixel_idx + 1] = @min(255, image_data[pixel_idx + 1] + 60); // G
                        image_data[pixel_idx + 2] = @min(255, image_data[pixel_idx + 2] + 120); // B
                    }
                }
            }
        }
    }

    fn drawScatterChart(self: *Self, image_data: []u8, width: u32, height: u32, data: []const f64) !void {
        _ = self;

        if (data.len == 0) return;

        var min_val = data[0];
        var max_val = data[0];
        for (data[1..]) |val| {
            min_val = @min(min_val, val);
            max_val = @max(max_val, val);
        }

        const range = max_val - min_val;
        if (range == 0) return;

        // Draw points
        for (data, 0..) |val, i| {
            const x = @as(u32, @intFromFloat(@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(data.len - 1)) * @as(f64, @floatFromInt(width))));
            const y = height - @as(u32, @intFromFloat((val - min_val) / range * @as(f64, @floatFromInt(height))));

            // Draw a small circle for each point
            drawCircleRGBA(image_data, width, height, x, y, 3, .{ .r = 255, .g = 100, .b = 100, .a = 255 });
        }
    }

    // More implementation stubs for other rendering methods...
    fn generateSixelChart(self: *Self, chart: RenderableContent.RealtimeChart, bounds: unified.Rect) ![]u8 {
        _ = chart;
        _ = bounds;
        // Placeholder for Sixel chart generation
        return try self.allocator.dupe(u8, "");
    }

    fn renderChartWithUnicode(self: *Self, chart: RenderableContent.RealtimeChart, bounds: unified.Rect) !void {
        // Use Unicode blocks for chart visualization
        if (chart.data_stream.len == 0) return;

        var max_val = chart.data_stream[0];
        for (chart.data_stream[1..]) |val| {
            max_val = @max(max_val, val);
        }

        if (max_val == 0) return;

        const chart_height = @as(u32, @intCast(bounds.height)) - 2;
        const chart_width = @as(u32, @intCast(bounds.width)) - 2;

        // Render chart
        for (0..chart_height) |row| {
            try self.terminal.moveTo(bounds.x + 1, bounds.y + @as(i32, @intCast(row)) + 1);

            const threshold = max_val * (1.0 - @as(f64, @floatFromInt(row)) / @as(f64, @floatFromInt(chart_height)));

            for (0..chart_width) |col| {
                const data_idx = (col * chart.data_stream.len) / chart_width;
                const value = if (data_idx < chart.data_stream.len) chart.data_stream[data_idx] else 0.0;

                const block = if (value >= threshold) "█" else " ";
                const color = if (value > max_val * 0.75) unified.Colors.RED else if (value > max_val * 0.5) unified.Colors.YELLOW else unified.Colors.GREEN;

                try self.terminal.print(block, .{ .fg_color = color });
            }
        }
    }

    fn renderChartWithASCII(self: *Self, chart: RenderableContent.RealtimeChart, bounds: unified.Rect) !void {
        // ASCII art chart
        _ = self;
        _ = chart;
        _ = bounds;
        // Implementation would render with ASCII characters
    }

    // Additional helper methods with minimal implementations
    fn generatePlotImage(self: *Self, plot: RenderableContent.InteractivePlot, bounds: unified.Rect) ![]u8 {
        _ = plot;
        _ = bounds;
        return try self.allocator.alloc(u8, 1024); // Placeholder
    }

    fn generateCanvasImage(self: *Self, canvas: RenderableContent.DrawingCanvas, bounds: unified.Rect) ![]u8 {
        _ = canvas;
        _ = bounds;
        return try self.allocator.alloc(u8, 1024); // Placeholder
    }

    fn addChartAnimation(self: *Self, chart: RenderableContent.RealtimeChart, bounds: unified.Rect) !void {
        _ = self;
        _ = chart;
        _ = bounds;
        // Animation implementation
    }

    fn renderPlotInteractionOverlay(self: *Self, plot: RenderableContent.InteractivePlot, bounds: unified.Rect) !void {
        _ = self;
        _ = plot;
        _ = bounds;
        // Interactive overlay implementation
    }

    fn renderPlotWithBraille(self: *Self, plot: RenderableContent.InteractivePlot, bounds: unified.Rect) !void {
        _ = self;
        _ = plot;
        _ = bounds;
        // Braille pattern plotting
    }

    fn renderPlotWithASCII(self: *Self, plot: RenderableContent.InteractivePlot, bounds: unified.Rect) !void {
        _ = self;
        _ = plot;
        _ = bounds;
        // ASCII plotting
    }

    fn renderDrawingLayerWithBlocks(self: *Self, layer: RenderableContent.DrawingCanvas.DrawingLayer, bounds: unified.Rect) !void {
        _ = self;
        _ = layer;
        _ = bounds;
        // Unicode block drawing
    }

    fn renderDrawingLayerWithASCII(self: *Self, layer: RenderableContent.DrawingCanvas.DrawingLayer, bounds: unified.Rect) !void {
        _ = self;
        _ = layer;
        _ = bounds;
        // ASCII drawing
    }

    // Additional visualization methods (stubs)
    fn generateHeatmapImage(self: *Self, viz: RenderableContent.DataVisualization, bounds: unified.Rect) ![]u8 {
        _ = viz;
        _ = bounds;
        return try self.allocator.alloc(u8, 1024);
    }

    fn renderHeatmapWithBlocks(self: *Self, viz: RenderableContent.DataVisualization, bounds: unified.Rect) !void {
        _ = self;
        _ = viz;
        _ = bounds;
    }

    fn renderHeatmapWithASCII(self: *Self, viz: RenderableContent.DataVisualization, bounds: unified.Rect) !void {
        _ = self;
        _ = viz;
        _ = bounds;
    }

    fn renderScatterMatrix(self: *Self, viz: RenderableContent.DataVisualization, bounds: unified.Rect) !void {
        _ = self;
        _ = viz;
        _ = bounds;
    }

    fn renderHistogram(self: *Self, viz: RenderableContent.DataVisualization, bounds: unified.Rect) !void {
        _ = self;
        _ = viz;
        _ = bounds;
    }

    fn renderBoxPlot(self: *Self, viz: RenderableContent.DataVisualization, bounds: unified.Rect) !void {
        _ = self;
        _ = viz;
        _ = bounds;
    }

    fn renderParallelCoordinates(self: *Self, viz: RenderableContent.DataVisualization, bounds: unified.Rect) !void {
        _ = self;
        _ = viz;
        _ = bounds;
    }
};

// Drawing helper functions
const RGBA = struct { r: u8, g: u8, b: u8, a: u8 };

fn drawLineRGBA(image_data: []u8, width: u32, height: u32, x0: u32, y0: u32, x1: u32, y1: u32, color: RGBA) void {
    // Simple Bresenham line algorithm
    const dx = @abs(@as(i32, @intCast(x1)) - @as(i32, @intCast(x0)));
    const dy = @abs(@as(i32, @intCast(y1)) - @as(i32, @intCast(y0)));
    const sx: i32 = if (x0 < x1) 1 else -1;
    const sy: i32 = if (y0 < y1) 1 else -1;
    var err = dx - dy;

    var x: i32 = @intCast(x0);
    var y: i32 = @intCast(y0);

    while (true) {
        if (x >= 0 and x < width and y >= 0 and y < height) {
            const pixel_idx = (@as(usize, @intCast(y)) * width + @as(usize, @intCast(x))) * 4;
            if (pixel_idx + 3 < image_data.len) {
                image_data[pixel_idx] = color.r;
                image_data[pixel_idx + 1] = color.g;
                image_data[pixel_idx + 2] = color.b;
                image_data[pixel_idx + 3] = color.a;
            }
        }

        if (x == x1 and y == y1) break;

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

fn fillRectRGBA(image_data: []u8, width: u32, height: u32, x: u32, y: u32, rect_width: u32, rect_height: u32, color: RGBA) void {
    for (0..rect_height) |dy| {
        for (0..rect_width) |dx| {
            const px = x + @as(u32, @intCast(dx));
            const py = y + @as(u32, @intCast(dy));

            if (px < width and py < height) {
                const pixel_idx = (py * width + px) * 4;
                if (pixel_idx + 3 < image_data.len) {
                    image_data[pixel_idx] = color.r;
                    image_data[pixel_idx + 1] = color.g;
                    image_data[pixel_idx + 2] = color.b;
                    image_data[pixel_idx + 3] = color.a;
                }
            }
        }
    }
}

fn drawCircleRGBA(image_data: []u8, width: u32, height: u32, cx: u32, cy: u32, radius: u32, color: RGBA) void {
    const r = @as(i32, @intCast(radius));
    var x: i32 = 0;
    var y: i32 = r;
    var d: i32 = 3 - 2 * r;

    while (x <= y) {
        putPixelSafe(image_data, width, height, @as(i32, @intCast(cx)) + x, @as(i32, @intCast(cy)) + y, color);
        putPixelSafe(image_data, width, height, @as(i32, @intCast(cx)) + x, @as(i32, @intCast(cy)) - y, color);
        putPixelSafe(image_data, width, height, @as(i32, @intCast(cx)) - x, @as(i32, @intCast(cy)) + y, color);
        putPixelSafe(image_data, width, height, @as(i32, @intCast(cx)) - x, @as(i32, @intCast(cy)) - y, color);
        putPixelSafe(image_data, width, height, @as(i32, @intCast(cx)) + y, @as(i32, @intCast(cy)) + x, color);
        putPixelSafe(image_data, width, height, @as(i32, @intCast(cx)) + y, @as(i32, @intCast(cy)) - x, color);
        putPixelSafe(image_data, width, height, @as(i32, @intCast(cx)) - y, @as(i32, @intCast(cy)) + x, color);
        putPixelSafe(image_data, width, height, @as(i32, @intCast(cx)) - y, @as(i32, @intCast(cy)) - x, color);

        if (d < 0) {
            d = d + 4 * x + 6;
        } else {
            d = d + 4 * (x - y) + 10;
            y -= 1;
        }
        x += 1;
    }
}

fn putPixelSafe(image_data: []u8, width: u32, height: u32, x: i32, y: i32, color: RGBA) void {
    if (x >= 0 and x < width and y >= 0 and y < height) {
        const pixel_idx = (@as(usize, @intCast(y)) * width + @as(usize, @intCast(x))) * 4;
        if (pixel_idx + 3 < image_data.len) {
            image_data[pixel_idx] = color.r;
            image_data[pixel_idx + 1] = color.g;
            image_data[pixel_idx + 2] = color.b;
            image_data[pixel_idx + 3] = color.a;
        }
    }
}

//! Canvas Engine - Core rendering system for interactive graphics
//!
//! This module provides the foundation for the Interactive Canvas system,
//! leveraging the existing graphics_manager and unified terminal capabilities
//! while providing a cleaner, more focused API for canvas operations.

const std = @import("std");
const graphics_manager = @import("../../src/term/graphics_manager.zig");
const unified = @import("../../src/term/unified.zig");

/// Simplified Canvas Engine that integrates with existing terminal graphics
pub const CanvasEngine = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    terminal: *unified.Terminal,
    graphics: graphics_manager.GraphicsManager,
    viewport: Viewport,
    layers: std.ArrayList(CanvasLayer),
    next_layer_id: u32,
    
    pub const Viewport = struct {
        x: i32 = 0,
        y: i32 = 0,
        width: u32 = 80,
        height: u32 = 24,
        zoom: f32 = 1.0,
        offset_x: f32 = 0.0,
        offset_y: f32 = 0.0,
    };
    
    pub const CanvasLayer = struct {
        id: u32,
        name: []const u8,
        visible: bool = true,
        opacity: f32 = 1.0,
        content: LayerContent,
        
        pub const LayerContent = union(enum) {
            drawing: DrawingContent,
            chart: ChartContent,
            text: TextContent,
            
            pub const DrawingContent = struct {
                strokes: std.ArrayList(Stroke),
                
                pub const Stroke = struct {
                    points: std.ArrayList(Point),
                    color: unified.Color,
                    width: f32,
                    
                    pub const Point = struct { x: f32, y: f32 };
                };
            };
            
            pub const ChartContent = struct {
                data: []const f64,
                chart_type: ChartType,
                style: ChartStyle,
                
                pub const ChartType = enum { line, bar, scatter };
                
                pub const ChartStyle = struct {
                    color: unified.Color = unified.Colors.BLUE,
                    show_grid: bool = true,
                    title: ?[]const u8 = null,
                };
            };
            
            pub const TextContent = struct {
                text: []const u8,
                position: Point,
                style: TextStyle,
                
                const Point = struct { x: f32, y: f32 };
                
                pub const TextStyle = struct {
                    color: unified.Color = unified.Colors.WHITE,
                    size: f32 = 12.0,
                    bold: bool = false,
                };
            };
        };
    };
    
    pub fn init(allocator: std.mem.Allocator, terminal: *unified.Terminal) !Self {
        return Self{
            .allocator = allocator,
            .terminal = terminal,
            .graphics = graphics_manager.GraphicsManager.init(allocator, terminal),
            .viewport = .{},
            .layers = std.ArrayList(CanvasLayer).init(allocator),
            .next_layer_id = 0,
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.layers.items) |*layer| {
            self.cleanupLayer(layer);
        }
        self.layers.deinit();
        self.graphics.deinit();
    }
    
    /// Create a new drawing layer
    pub fn createDrawingLayer(self: *Self, name: []const u8) !u32 {
        const layer_id = self.next_layer_id;
        self.next_layer_id += 1;
        
        const layer = CanvasLayer{
            .id = layer_id,
            .name = name,
            .content = .{ .drawing = .{ .strokes = std.ArrayList(CanvasLayer.LayerContent.DrawingContent.Stroke).init(self.allocator) } },
        };
        
        try self.layers.append(layer);
        return layer_id;
    }
    
    /// Create a new chart layer
    pub fn createChartLayer(self: *Self, name: []const u8, data: []const f64, chart_type: CanvasLayer.LayerContent.ChartContent.ChartType) !u32 {
        const layer_id = self.next_layer_id;
        self.next_layer_id += 1;
        
        const layer = CanvasLayer{
            .id = layer_id,
            .name = name,
            .content = .{ .chart = .{ .data = data, .chart_type = chart_type, .style = .{} } },
        };
        
        try self.layers.append(layer);
        return layer_id;
    }
    
    /// Set viewport dimensions (usually terminal size)
    pub fn setViewport(self: *Self, x: i32, y: i32, width: u32, height: u32) void {
        self.viewport = .{ .x = x, .y = y, .width = width, .height = height, .zoom = self.viewport.zoom, .offset_x = self.viewport.offset_x, .offset_y = self.viewport.offset_y };
    }
    
    /// Add a drawing stroke to a layer
    pub fn addStroke(self: *Self, layer_id: u32, points: []const CanvasLayer.LayerContent.DrawingContent.Stroke.Point, color: unified.Color, width: f32) !void {
        const layer = self.getLayer(layer_id) orelse return error.LayerNotFound;
        
        switch (layer.content) {
            .drawing => |*drawing| {
                var stroke = CanvasLayer.LayerContent.DrawingContent.Stroke{
                    .points = std.ArrayList(CanvasLayer.LayerContent.DrawingContent.Stroke.Point).init(self.allocator),
                    .color = color,
                    .width = width,
                };
                
                try stroke.points.appendSlice(points);
                try drawing.strokes.append(stroke);
            },
            else => return error.InvalidLayerType,
        }
    }
    
    /// Render all layers to the terminal
    pub fn render(self: *Self) !void {
        const graphics_mode = self.graphics.getMode();
        
        // Clear the viewport area
        try self.clearViewport();
        
        // Render each visible layer
        for (self.layers.items) |layer| {
            if (!layer.visible) continue;
            try self.renderLayer(layer, graphics_mode);
        }
    }
    
    fn clearViewport(self: *Self) !void {
        // Move to viewport position and clear the area
        try self.terminal.moveTo(self.viewport.x, self.viewport.y);
        
        for (0..self.viewport.height) |y| {
            try self.terminal.moveTo(self.viewport.x, self.viewport.y + @as(i32, @intCast(y)));
            for (0..self.viewport.width) |_| {
                try self.terminal.print(" ", null);
            }
        }
    }
    
    fn renderLayer(self: *Self, layer: CanvasLayer, graphics_mode: graphics_manager.GraphicsMode) !void {
        switch (layer.content) {
            .drawing => |drawing| try self.renderDrawingLayer(drawing, graphics_mode),
            .chart => |chart| try self.renderChartLayer(chart, graphics_mode),
            .text => |text| try self.renderTextLayer(text),
        }
    }
    
    fn renderDrawingLayer(self: *Self, drawing: CanvasLayer.LayerContent.DrawingContent, graphics_mode: graphics_manager.GraphicsMode) !void {
        switch (graphics_mode) {
            .kitty, .sixel => {
                // Use high-quality graphics rendering
                try self.renderDrawingWithGraphics(drawing);
            },
            .unicode, .ascii, .none => {
                // Use character-based rendering
                try self.renderDrawingWithCharacters(drawing);
            },
        }
    }
    
    fn renderChartLayer(self: *Self, chart: CanvasLayer.LayerContent.ChartContent, graphics_mode: graphics_manager.GraphicsMode) !void {
        _ = graphics_mode; // Handle fallback if needed
        
        // Create a chart using the graphics manager
        const chart_config = graphics_manager.Chart{
            .width = self.viewport.width,
            .height = self.viewport.height,
            .chart_type = switch (chart.chart_type) {
                .line => .line,
                .bar => .bar,
                .scatter => .line, // Use line for scatter plots
            },
            .title = chart.style.title,
            .data_points = try self.convertChartData(chart.data),
            .colors = &[_]unified.Color{chart.style.color},
        };
        
        const chart_image_id = try self.graphics.createChart(chart_config);
        defer self.graphics.removeImage(chart_image_id);
        
        const render_options = graphics_manager.RenderOptions{
            .max_width = self.viewport.width,
            .max_height = self.viewport.height,
        };
        
        try self.graphics.renderImage(chart_image_id, .{ .x = self.viewport.x, .y = self.viewport.y }, render_options);
    }
    
    fn renderTextLayer(self: *Self, text: CanvasLayer.LayerContent.TextContent) !void {
        const screen_x = self.viewport.x + @as(i32, @intFromFloat(text.position.x));
        const screen_y = self.viewport.y + @as(i32, @intFromFloat(text.position.y));
        
        try self.terminal.moveTo(screen_x, screen_y);
        
        const style = unified.Style{
            .fg_color = text.style.color,
            .bold = text.style.bold,
        };
        
        try self.terminal.print(text.text, style);
    }
    
    fn renderDrawingWithGraphics(self: *Self, drawing: CanvasLayer.LayerContent.DrawingContent) !void {
        // Create an image buffer for the drawing
        const image_width = self.viewport.width * 8; // 8 pixels per character
        const image_height = self.viewport.height * 16; // 16 pixels per character
        const image_data = try self.allocator.alloc(u8, image_width * image_height * 3); // RGB
        defer self.allocator.free(image_data);
        
        // Clear with black background
        @memset(image_data, 0);
        
        // Render each stroke
        for (drawing.strokes.items) |stroke| {
            try self.renderStrokeToImage(stroke, image_data, image_width, image_height);
        }
        
        // Create and render the image
        const image_id = try self.graphics.createImage(image_data, image_width, image_height, .rgb24);
        defer self.graphics.removeImage(image_id);
        
        const render_options = graphics_manager.RenderOptions{
            .max_width = self.viewport.width,
            .max_height = self.viewport.height,
        };
        
        try self.graphics.renderImage(image_id, .{ .x = self.viewport.x, .y = self.viewport.y }, render_options);
    }
    
    fn renderDrawingWithCharacters(self: *Self, drawing: CanvasLayer.LayerContent.DrawingContent) !void {
        // Create a character buffer
        const buffer_size = self.viewport.width * self.viewport.height;
        const char_buffer = try self.allocator.alloc(u8, buffer_size);
        defer self.allocator.free(char_buffer);
        @memset(char_buffer, ' ');
        
        // Render each stroke as characters
        for (drawing.strokes.items) |stroke| {
            self.renderStrokeToCharBuffer(stroke, char_buffer);
        }
        
        // Output the character buffer
        for (0..self.viewport.height) |y| {
            try self.terminal.moveTo(self.viewport.x, self.viewport.y + @as(i32, @intCast(y)));
            const line_start = y * self.viewport.width;
            const line_end = line_start + self.viewport.width;
            
            for (char_buffer[line_start..line_end]) |char| {
                try self.terminal.print(&[_]u8{char}, null);
            }
        }
    }
    
    fn renderStrokeToImage(self: *Self, stroke: CanvasLayer.LayerContent.DrawingContent.Stroke, image_data: []u8, width: u32, height: u32) !void {
        _ = self;
        
        // Convert stroke color to RGB
        const rgb = switch (stroke.color) {
            .rgb => |rgb_val| rgb_val,
            .ansi => |ansi_val| convertAnsiToRGB(ansi_val),
            .palette => |pal_val| convertPaletteToRGB(pal_val),
        };
        
        // Render stroke points
        for (stroke.points.items[1..], 0..) |point, i| {
            const prev_point = stroke.points.items[i];
            drawLine(image_data, width, height, prev_point, point, rgb, stroke.width);
        }
    }
    
    fn renderStrokeToCharBuffer(self: *Self, stroke: CanvasLayer.LayerContent.DrawingContent.Stroke, buffer: []u8) void {
        // Simple character-based stroke rendering
        for (stroke.points.items) |point| {
            const x = @as(usize, @intFromFloat(point.x));
            const y = @as(usize, @intFromFloat(point.y));
            
            if (x < self.viewport.width and y < self.viewport.height) {
                const index = y * self.viewport.width + x;
                if (index < buffer.len) {
                    buffer[index] = if (stroke.width > 2.0) '█' else if (stroke.width > 1.0) '▓' else '▒';
                }
            }
        }
    }
    
    fn convertChartData(self: *Self, data: []const f64) ![]const graphics_manager.Chart.DataPoint {
        const points = try self.allocator.alloc(graphics_manager.Chart.DataPoint, data.len);
        
        for (data, 0..) |value, i| {
            points[i] = .{
                .value = @as(f32, @floatCast(value)),
                .label = null,
            };
        }
        
        return points;
    }
    
    fn getLayer(self: *Self, layer_id: u32) ?*CanvasLayer {
        for (self.layers.items) |*layer| {
            if (layer.id == layer_id) return layer;
        }
        return null;
    }
    
    fn cleanupLayer(self: *Self, layer: *CanvasLayer) void {
        switch (layer.content) {
            .drawing => |*drawing| {
                for (drawing.strokes.items) |*stroke| {
                    stroke.points.deinit();
                }
                drawing.strokes.deinit();
            },
            .chart => {},
            .text => {},
        }
        _ = self;
    }
    
    /// Pan the viewport
    pub fn pan(self: *Self, delta_x: f32, delta_y: f32) void {
        self.viewport.offset_x += delta_x;
        self.viewport.offset_y += delta_y;
    }
    
    /// Zoom the viewport
    pub fn zoom(self: *Self, factor: f32) void {
        self.viewport.zoom *= factor;
        self.viewport.zoom = @max(0.1, @min(10.0, self.viewport.zoom)); // Clamp zoom
    }
    
    /// Reset viewport to default
    pub fn resetViewport(self: *Self) void {
        self.viewport.zoom = 1.0;
        self.viewport.offset_x = 0.0;
        self.viewport.offset_y = 0.0;
    }
};

// Utility functions for color conversion
fn convertAnsiToRGB(ansi: u8) unified.Color.RGB {
    // Simple ANSI to RGB conversion
    return switch (ansi) {
        0 => .{ .r = 0, .g = 0, .b = 0 },       // Black
        1 => .{ .r = 255, .g = 0, .b = 0 },     // Red
        2 => .{ .r = 0, .g = 255, .b = 0 },     // Green
        3 => .{ .r = 255, .g = 255, .b = 0 },   // Yellow
        4 => .{ .r = 0, .g = 0, .b = 255 },     // Blue
        5 => .{ .r = 255, .g = 0, .b = 255 },   // Magenta
        6 => .{ .r = 0, .g = 255, .b = 255 },   // Cyan
        7 => .{ .r = 255, .g = 255, .b = 255 }, // White
        else => .{ .r = 128, .g = 128, .b = 128 }, // Gray fallback
    };
}

fn convertPaletteToRGB(palette: u8) unified.Color.RGB {
    // Simple 256-color palette to RGB conversion (simplified)
    if (palette < 16) {
        return convertAnsiToRGB(palette);
    }
    
    // For now, just use a gradient
    const intensity = @as(f32, @floatFromInt(palette - 16)) / 240.0;
    const value = @as(u8, @intFromFloat(intensity * 255.0));
    return .{ .r = value, .g = value, .b = value };
}

fn drawLine(image_data: []u8, width: u32, height: u32, start: CanvasEngine.CanvasLayer.LayerContent.DrawingContent.Stroke.Point, end: CanvasEngine.CanvasLayer.LayerContent.DrawingContent.Stroke.Point, color: unified.Color.RGB, line_width: f32) void {
    _ = line_width; // For simplicity, ignore line width for now
    
    // Simple Bresenham line drawing
    const x0 = @as(i32, @intFromFloat(start.x));
    const y0 = @as(i32, @intFromFloat(start.y));
    const x1 = @as(i32, @intFromFloat(end.x));
    const y1 = @as(i32, @intFromFloat(end.y));
    
    const dx = @abs(x1 - x0);
    const dy = @abs(y1 - y0);
    const sx: i32 = if (x0 < x1) 1 else -1;
    const sy: i32 = if (y0 < y1) 1 else -1;
    var err = dx - dy;
    
    var x = x0;
    var y = y0;
    
    while (true) {
        // Set pixel if within bounds
        if (x >= 0 and x < width and y >= 0 and y < height) {
            const pixel_index = (@as(usize, @intCast(y)) * width + @as(usize, @intCast(x))) * 3;
            if (pixel_index + 2 < image_data.len) {
                image_data[pixel_index] = color.r;
                image_data[pixel_index + 1] = color.g;
                image_data[pixel_index + 2] = color.b;
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
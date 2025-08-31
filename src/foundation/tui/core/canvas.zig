//! Canvas System - Graphics canvas with layer management and real-time interaction
//!
//! This module provides a graphics canvas that leverages terminal capabilities.
//! It supports multi-layer compositing, real-time interaction, progressive
//! enhancement based on terminal features, and maintains backward compatibility
//! with the original canvas_engine API.

const std = @import("std");
const term = @import("../../term.zig");
const unified = term;
const graphics_manager = struct {
    pub const GraphicsManager = anyopaque;
};

/// Canvas with layer management and real-time interaction
/// Maintains backward compatibility with CanvasEngine API
pub const Canvas = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    terminal: *anyopaque,
    graphics: anyopaque,
    layers: std.ArrayList(Layer),
    viewport: Viewport,
    interaction: Interaction,
    animation: AnimationEngine,
    render_cache: RenderCache,
    dirty_regions: std.ArrayList(Rect),
    next_layer_id: u32,

    /// Canvas layer for compositing different visual elements
    pub const Layer = struct {
        id: u32,
        name: []const u8,
        content: LayerContent,
        transform: Transform2D,
        opacity: f32 = 1.0,
        blend_mode: BlendMode = .normal,
        visible: bool = true,
        interactive: bool = false,
        zIndex: i32 = 0,
    };

    /// Layer content types - supports both original and advanced content
    pub const LayerContent = union(enum) {
        // Original canvas_engine content types
        drawing: DrawingContent,
        chart: ChartContent,
        text: TextContent,

        // Extended content types from Canvas.zig
        image: ImageLayer,
        vector: VectorLayer,

        /// Original drawing content (backward compatible)
        pub const DrawingContent = struct {
            strokes: std.ArrayList(Stroke),

            pub const Stroke = struct {
                points: std.ArrayList(Point),
                color: unified.Color,
                width: f32,
                opacity: f32 = 1.0,

                pub const Point = struct { x: f32, y: f32 };
            };
        };

        /// Original chart content (backward compatible)
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

        /// Original text content (backward compatible)
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

        /// Image layer
        pub const ImageLayer = struct {
            image_id: u32,
            source_rect: ?Rect = null,
        };

        /// Vector layer
        pub const VectorLayer = struct {
            elements: std.ArrayList(VectorElement),

            pub const VectorElement = union(enum) {
                path: Path,
                circle: Circle,
                rectangle: Rectangle,
                line: Line,

                pub const Path = struct {
                    points: []Point2D,
                    stroke_color: ?unified.Color = null,
                    fill_color: ?unified.Color = null,
                    stroke_width: f32 = 1.0,
                };

                pub const Circle = struct {
                    center: Point2D,
                    radius: f32,
                    stroke_color: ?unified.Color = null,
                    fill_color: ?unified.Color = null,
                    stroke_width: f32 = 1.0,
                };

                pub const Rectangle = struct {
                    rect: Rect,
                    stroke_color: ?unified.Color = null,
                    fill_color: ?unified.Color = null,
                    stroke_width: f32 = 1.0,
                    corner_radius: f32 = 0.0,
                };

                pub const Line = struct {
                    start: Point2D,
                    end: Point2D,
                    color: unified.Color,
                    width: f32 = 1.0,
                    style: LineStyle = .solid,

                    pub const LineStyle = enum { solid, dashed, dotted };
                };
            };
        };
    };

    /// 2D transformation support
    pub const Transform2D = struct {
        translation: Point2D = .{ .x = 0, .y = 0 },
        scale: Point2D = .{ .x = 1.0, .y = 1.0 },
        rotation: f32 = 0.0,

        pub fn apply(self: Transform2D, point: Point2D) Point2D {
            // Apply transformation matrix
            const cos_r = std.math.cos(self.rotation);
            const sin_r = std.math.sin(self.rotation);

            // Scale
            var result = Point2D{
                .x = point.x * self.scale.x,
                .y = point.y * self.scale.y,
            };

            // Rotate
            const rotated_x = result.x * cos_r - result.y * sin_r;
            const rotated_y = result.x * sin_r + result.y * cos_r;
            result.x = rotated_x;
            result.y = rotated_y;

            // Translate
            result.x += self.translation.x;
            result.y += self.translation.y;

            return result;
        }
    };

    /// Blend modes for layer compositing
    pub const BlendMode = enum {
        normal,
        multiply,
        screen,
        overlay,
        add,
        subtract,
    };

    /// Viewport with zoom and pan support (enhanced from original)
    pub const Viewport = struct {
        x: i32 = 0,
        y: i32 = 0,
        width: u32 = 80,
        height: u32 = 24,
        zoom: f32 = 1.0,
        offset_x: f32 = 0.0,
        offset_y: f32 = 0.0,

        /// Convert screen coordinates to world coordinates
        pub fn screenToWorld(self: Viewport, screen_point: Point2D) Point2D {
            return .{
                .x = (screen_point.x - @as(f32, @floatFromInt(self.x))) / self.zoom + self.offset_x,
                .y = (screen_point.y - @as(f32, @floatFromInt(self.y))) / self.zoom + self.offset_y,
            };
        }

        /// Convert world coordinates to screen coordinates
        pub fn worldToScreen(self: Viewport, world_point: Point2D) Point2D {
            return .{
                .x = (world_point.x - self.offset_x) * self.zoom + @as(f32, @floatFromInt(self.x)),
                .y = (world_point.y - self.offset_y) * self.zoom + @as(f32, @floatFromInt(self.y)),
            };
        }
    };

    /// Interaction system for real-time canvas manipulation
    pub const Interaction = struct {
        current_tool: Tool = .pointer,
        is_drawing: bool = false,
        active_layer: ?u32 = null,
        hover_layer: ?u32 = null,

        pub const Tool = enum {
            pointer, // Selection and manipulation
            brush, // Free-form drawing
            line, // Line drawing
            rectangle, // Rectangle drawing
            circle, // Circle drawing
            text, // Text insertion
            pan, // Pan viewport
            zoom, // Zoom tool
        };
    };

    /// Animation engine for smooth layer transitions
    pub const AnimationEngine = struct {
        animations: std.ArrayList(Animation),

        pub const Animation = struct {
            target_layer: u32,
            property: AnimationProperty,
            start_value: f32,
            end_value: f32,
            duration_ms: u32,
            elapsed_ms: u32 = 0,
            easing: EasingFunction = .ease_in_out,

            pub const AnimationProperty = enum {
                opacity,
                scale_x,
                scale_y,
                rotation,
                translation_x,
                translation_y,
            };

            pub const EasingFunction = enum {
                linear,
                ease_in,
                ease_out,
                ease_in_out,
                bounce,
            };
        };
    };

    /// Render cache for performance optimization
    pub const RenderCache = struct {
        layer_cache: std.HashMap(u32, CachedLayer),
        composite_cache: ?CompositeImage = null,
        last_render_hash: u64 = 0,

        pub const CachedLayer = struct {
            image_id: u32,
            hash: u64,
            timestamp: u64,
        };

        pub const CompositeImage = struct {
            image_id: u32,
            bounds: Rect,
            timestamp: u64,
        };
    };

    /// Utility types
    const Point2D = struct { x: f32, y: f32 };
    const Rect = struct { x: i32, y: i32, width: u32, height: u32 };

    /// Initialize canvas (backward compatible with CanvasEngine.init)
    pub fn init(allocator: std.mem.Allocator, terminal: *unified.Terminal) !Self {
        return Self{
            .allocator = allocator,
            .terminal = terminal,
            .graphics = graphics_manager.GraphicsManager.init(allocator, terminal),
            .layers = std.ArrayList(Layer).init(allocator),
            .viewport = .{},
            .interaction = .{},
            .animation = .{ .animations = std.ArrayList(AnimationEngine.Animation).init(allocator) },
            .render_cache = .{ .layer_cache = std.HashMap(u32, RenderCache.CachedLayer).init(allocator) },
            .dirty_regions = std.ArrayList(Rect).init(allocator),
            .next_layer_id = 0,
        };
    }

    /// Deinitialize canvas
    pub fn deinit(self: *Self) void {
        // Clean up layers
        for (self.layers.items) |*layer| {
            self.cleanupLayer(layer);
        }
        self.layers.deinit();

        // Clean up caches
        var cache_iter = self.render_cache.layer_cache.iterator();
        while (cache_iter.next()) |entry| {
            self.graphics.removeImage(entry.value_ptr.image_id);
        }
        self.render_cache.layer_cache.deinit();

        if (self.render_cache.composite_cache) |composite| {
            self.graphics.removeImage(composite.image_id);
        }

        // Clean up other resources
        self.dirty_regions.deinit();
        self.animation.animations.deinit();
        self.graphics.deinit();
    }

    /// Create a new drawing layer (backward compatible)
    pub fn createDrawingLayer(self: *Self, name: []const u8) !u32 {
        const layer_id = self.next_layer_id;
        self.next_layer_id += 1;

        const layer = Layer{
            .id = layer_id,
            .name = try self.allocator.dupe(u8, name),
            .content = .{ .drawing = .{ .strokes = std.ArrayList(LayerContent.DrawingContent.Stroke).init(self.allocator) } },
            .transform = .{},
        };

        try self.layers.append(layer);
        return layer_id;
    }

    /// Create a new chart layer (backward compatible)
    pub fn createChartLayer(self: *Self, name: []const u8, data: []const f64, chart_type: LayerContent.ChartContent.ChartType) !u32 {
        const layer_id = self.next_layer_id;
        self.next_layer_id += 1;

        const layer = Layer{
            .id = layer_id,
            .name = try self.allocator.dupe(u8, name),
            .content = .{ .chart = .{ .data = try self.allocator.dupe(f64, data), .chart_type = chart_type, .style = .{} } },
            .transform = .{},
        };

        try self.layers.append(layer);
        return layer_id;
    }

    /// Create a new text layer (backward compatible)
    pub fn createTextLayer(self: *Self, name: []const u8) !u32 {
        const layer_id = self.next_layer_id;
        self.next_layer_id += 1;

        const layer = Layer{
            .id = layer_id,
            .name = try self.allocator.dupe(u8, name),
            .content = .{ .text = .{ .text = "", .position = .{ .x = 0, .y = 0 }, .style = .{} } },
            .transform = .{},
        };

        try self.layers.append(layer);
        return layer_id;
    }

    /// Create a new vector layer
    pub fn createVectorLayer(self: *Self, name: []const u8) !u32 {
        const layer_id = self.next_layer_id;
        self.next_layer_id += 1;

        const layer = Layer{
            .id = layer_id,
            .name = try self.allocator.dupe(u8, name),
            .content = .{ .vector = .{ .elements = std.ArrayList(LayerContent.VectorLayer.VectorElement).init(self.allocator) } },
            .transform = .{},
        };

        try self.layers.append(layer);
        return layer_id;
    }

    /// Set viewport dimensions (backward compatible)
    pub fn setViewport(self: *Self, x: i32, y: i32, width: u32, height: u32) void {
        self.viewport = .{ .x = x, .y = y, .width = width, .height = height, .zoom = self.viewport.zoom, .offset_x = self.viewport.offset_x, .offset_y = self.viewport.offset_y };
        self.markDirty(null);
    }

    /// Add a drawing stroke to a layer (backward compatible)
    pub fn addStroke(self: *Self, layer_id: u32, points: []const LayerContent.DrawingContent.Stroke.Point, color: unified.Color, width: f32) !void {
        const layer = self.getLayer(layer_id) orelse return error.LayerNotFound;

        switch (layer.content) {
            .drawing => |*drawing| {
                var stroke = LayerContent.DrawingContent.Stroke{
                    .points = std.ArrayList(LayerContent.DrawingContent.Stroke.Point).init(self.allocator),
                    .color = color,
                    .width = width,
                };

                try stroke.points.appendSlice(points);
                try drawing.strokes.append(stroke);
                self.invalidateLayerCache(layer_id);
            },
            else => return error.InvalidLayerType,
        }
    }

    /// Add a vector element to a layer
    pub fn addVectorElement(self: *Self, layer_id: u32, element: LayerContent.VectorLayer.VectorElement) !void {
        const layer = self.getLayer(layer_id) orelse return error.LayerNotFound;

        switch (layer.content) {
            .vector => |*vector_layer| {
                try vector_layer.elements.append(element);
                self.invalidateLayerCache(layer_id);
            },
            else => return error.InvalidLayerType,
        }
    }

    /// Render all layers to the terminal (backward compatible)
    pub fn render(self: *Self) !void {
        // Check if we need to render at all
        if (self.dirty_regions.items.len == 0) return;

        // Sort layers by z-index
        std.mem.sort(Layer, self.layers.items, {}, layerCompare);

        // Update animations first
        try self.updateAnimations();

        // Render each visible layer
        const graphics_mode = self.graphics.getMode();

        // Clear the viewport area
        try self.clearViewport();

        // Render each visible layer
        for (self.layers.items) |layer| {
            if (!layer.visible) continue;
            try self.renderLayer(layer, graphics_mode);
        }

        // Clear dirty regions
        self.dirty_regions.clearRetainingCapacity();
    }

    /// Pan the viewport (backward compatible)
    pub fn pan(self: *Self, delta_x: f32, delta_y: f32) void {
        self.viewport.offset_x += delta_x;
        self.viewport.offset_y += delta_y;
        self.markDirty(null);
    }

    /// Zoom the viewport (backward compatible)
    pub fn zoom(self: *Self, factor: f32) void {
        self.viewport.zoom *= factor;
        self.viewport.zoom = @max(0.1, @min(10.0, self.viewport.zoom)); // Clamp zoom
        self.markDirty(null);
    }

    /// Reset viewport to default (backward compatible)
    pub fn resetViewport(self: *Self) void {
        self.viewport.zoom = 1.0;
        self.viewport.offset_x = 0.0;
        self.viewport.offset_y = 0.0;
        self.markDirty(null);
    }

    /// Clear the viewport area
    pub fn clearViewport(self: *Self) !void {
        // Move to viewport position and clear the area
        try self.terminal.moveTo(self.viewport.x, self.viewport.y);

        for (0..self.viewport.height) |y| {
            try self.terminal.moveTo(self.viewport.x, self.viewport.y + @as(i32, @intCast(y)));
            for (0..self.viewport.width) |_| {
                try self.terminal.print(" ", null);
            }
        }
    }

    /// Get layer by ID
    pub fn getLayer(self: *Self, layer_id: u32) ?*Layer {
        for (self.layers.items) |*layer| {
            if (layer.id == layer_id) return layer;
        }
        return null;
    }

    /// Animate a layer property
    pub fn animateLayer(self: *Self, layer_id: u32, property: AnimationEngine.Animation.AnimationProperty, target_value: f32, duration_ms: u32) !void {
        if (layer_id >= self.layers.items.len) return error.InvalidLayerId;

        const layer = &self.layers.items[layer_id];
        const start_value = switch (property) {
            .opacity => layer.opacity,
            .scale_x => layer.transform.scale.x,
            .scale_y => layer.transform.scale.y,
            .rotation => layer.transform.rotation,
            .translation_x => layer.transform.translation.x,
            .translation_y => layer.transform.translation.y,
        };

        const animation = AnimationEngine.Animation{
            .target_layer = layer_id,
            .property = property,
            .start_value = start_value,
            .end_value = target_value,
            .duration_ms = duration_ms,
        };

        try self.animation.animations.append(animation);
    }

    // Internal methods

    fn layerCompare(_: void, a: Layer, b: Layer) bool {
        return a.zIndex < b.zIndex;
    }

    fn renderLayer(self: *Self, layer: Layer, graphics_mode: graphics_manager.GraphicsMode) !void {
        switch (layer.content) {
            .drawing => |drawing| try self.renderDrawingLayer(drawing, graphics_mode),
            .chart => |chart| try self.renderChartLayer(chart, graphics_mode),
            .text => |text| try self.renderTextLayer(text),
            .vector => |vector| try self.renderVectorLayer(vector, layer.transform, graphics_mode),
            .image => |image| try self.renderImageLayer(image, layer.transform, graphics_mode),
        }
    }

    fn renderDrawingLayer(self: *Self, drawing: LayerContent.DrawingContent, graphics_mode: graphics_manager.GraphicsMode) !void {
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

    fn renderChartLayer(self: *Self, chart: LayerContent.ChartContent, graphics_mode: graphics_manager.GraphicsMode) !void {
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

    fn renderTextLayer(self: *Self, text: LayerContent.TextContent) !void {
        const screen_x = self.viewport.x + @as(i32, @intFromFloat(text.position.x));
        const screen_y = self.viewport.y + @as(i32, @intFromFloat(text.position.y));

        try self.terminal.moveTo(screen_x, screen_y);

        const style = unified.Style{
            .fg_color = text.style.color,
            .bold = text.style.bold,
        };

        try self.terminal.print(text.text, style);
    }

    fn renderVectorLayer(self: *Self, vector_layer: LayerContent.VectorLayer, transform: Transform2D, graphics_mode: graphics_manager.GraphicsMode) !void {
        _ = self;
        _ = transform;
        _ = graphics_mode;

        for (vector_layer.elements.items) |element| {
            switch (element) {
                .line => |line| {
                    // Render line using Bresenham algorithm
                    _ = line; // Implementation would draw the line
                },
                .circle => |circle| {
                    // Render circle using midpoint circle algorithm
                    _ = circle; // Implementation would draw the circle
                },
                .rectangle => |rect| {
                    // Render rectangle
                    _ = rect; // Implementation would draw the rectangle
                },
                .path => |path| {
                    // Render path by connecting points
                    _ = path; // Implementation would draw the path
                },
            }
        }
    }

    fn renderImageLayer(self: *Self, image_layer: LayerContent.ImageLayer, transform: Transform2D, graphics_mode: graphics_manager.GraphicsMode) !void {
        _ = self;
        _ = transform;
        _ = graphics_mode;
        _ = image_layer; // Implementation would render the image
    }

    fn renderDrawingWithGraphics(self: *Self, drawing: LayerContent.DrawingContent) !void {
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

    fn renderDrawingWithCharacters(self: *Self, drawing: LayerContent.DrawingContent) !void {
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

    fn renderStrokeToImage(self: *Self, stroke: LayerContent.DrawingContent.Stroke, image_data: []u8, width: u32, height: u32) !void {
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

    fn renderStrokeToCharBuffer(self: *Self, stroke: LayerContent.DrawingContent.Stroke, buffer: []u8) void {
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

    fn updateAnimations(self: *Self) !void {
        var i: usize = 0;
        while (i < self.animation.animations.items.len) {
            var animation = &self.animation.animations.items[i];
            animation.elapsed_ms += 16; // Assume 60 FPS (16ms per frame)

            if (animation.elapsed_ms >= animation.duration_ms) {
                // Animation complete
                try self.applyAnimationValue(animation.target_layer, animation.property, animation.end_value);
                _ = self.animation.animations.swapRemove(i);
            } else {
                // Update animation
                const progress = @as(f32, @floatFromInt(animation.elapsed_ms)) / @as(f32, @floatFromInt(animation.duration_ms));
                const eased_progress = self.applyEasing(progress, animation.easing);
                const current_value = animation.start_value + (animation.end_value - animation.start_value) * eased_progress;

                try self.applyAnimationValue(animation.target_layer, animation.property, current_value);
                i += 1;
            }
        }
    }

    fn applyEasing(self: *Self, progress: f32, easing: AnimationEngine.Animation.EasingFunction) f32 {
        _ = self;
        return switch (easing) {
            .linear => progress,
            .ease_in => progress * progress,
            .ease_out => 1.0 - (1.0 - progress) * (1.0 - progress),
            .ease_in_out => if (progress < 0.5) 2.0 * progress * progress else 1.0 - 2.0 * (1.0 - progress) * (1.0 - progress),
            .bounce => {
                const n1 = 7.5625;
                const d1 = 2.75;

                if (progress < 1.0 / d1) {
                    return n1 * progress * progress;
                } else if (progress < 2.0 / d1) {
                    const p = progress - 1.5 / d1;
                    return n1 * p * p + 0.75;
                } else if (progress < 2.5 / d1) {
                    const p = progress - 2.25 / d1;
                    return n1 * p * p + 0.9375;
                } else {
                    const p = progress - 2.625 / d1;
                    return n1 * p * p + 0.984375;
                }
            },
        };
    }

    fn applyAnimationValue(self: *Self, layer_id: u32, property: AnimationEngine.Animation.AnimationProperty, value: f32) !void {
        if (layer_id >= self.layers.items.len) return;

        var layer = &self.layers.items[layer_id];
        switch (property) {
            .opacity => layer.opacity = value,
            .scale_x => layer.transform.scale.x = value,
            .scale_y => layer.transform.scale.y = value,
            .rotation => layer.transform.rotation = value,
            .translation_x => layer.transform.translation.x = value,
            .translation_y => layer.transform.translation.y = value,
        }

        self.invalidateLayerCache(layer_id);
    }

    fn markDirty(self: *Self, region: ?Rect) void {
        const dirty_rect = region orelse self.viewportToRect();
        self.dirty_regions.append(dirty_rect) catch {};
    }

    fn invalidateLayerCache(self: *Self, layer_id: u32) void {
        if (self.render_cache.layer_cache.get(layer_id)) |cached_layer| {
            self.graphics.removeImage(cached_layer.image_id);
            _ = self.render_cache.layer_cache.remove(layer_id);
        }
        self.markDirty(null);
    }

    fn viewportToRect(self: *Self) Rect {
        return .{
            .x = self.viewport.x,
            .y = self.viewport.y,
            .width = self.viewport.width,
            .height = self.viewport.height,
        };
    }

    fn cleanupLayer(self: *Self, layer: *Layer) void {
        // Clean up layer name
        self.allocator.free(layer.name);

        switch (layer.content) {
            .drawing => |*drawing| {
                for (drawing.strokes.items) |*stroke| {
                    stroke.points.deinit();
                }
                drawing.strokes.deinit();
            },
            .chart => |*chart| {
                self.allocator.free(chart.data);
            },
            .text => {},
            .vector => |*vector| {
                vector.elements.deinit();
            },
            .image => {},
        }
    }
};

// Utility functions for color conversion
fn convertAnsiToRGB(ansi: u8) unified.Color.RGB {
    // Simple ANSI to RGB conversion
    return switch (ansi) {
        0 => .{ .r = 0, .g = 0, .b = 0 }, // Black
        1 => .{ .r = 255, .g = 0, .b = 0 }, // Red
        2 => .{ .r = 0, .g = 255, .b = 0 }, // Green
        3 => .{ .r = 255, .g = 255, .b = 0 }, // Yellow
        4 => .{ .r = 0, .g = 0, .b = 255 }, // Blue
        5 => .{ .r = 255, .g = 0, .b = 255 }, // Magenta
        6 => .{ .r = 0, .g = 255, .b = 255 }, // Cyan
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

fn drawLine(image_data: []u8, width: u32, height: u32, start: Canvas.LayerContent.DrawingContent.Stroke.Point, end: Canvas.LayerContent.DrawingContent.Stroke.Point, color: unified.Color.RGB, line_width: f32) void {
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

// Backward compatibility alias
pub const CanvasEngine = Canvas;

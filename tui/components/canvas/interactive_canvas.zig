//! Interactive Terminal Graphics Canvas System
//!
//! This module provides a sophisticated graphics canvas that leverages the full power
//! of modern terminal capabilities. It supports multi-layer compositing, real-time
//! interaction, and progressive enhancement based on terminal features.

const std = @import("std");
const graphics_manager = @import("../../../src/term/graphics_manager.zig");
const unified = @import("../../../src/term/unified.zig");
const enhanced_mouse = @import("../../../src/term/enhanced_mouse.zig");
const enhanced_input = @import("../../../src/term/enhanced_input_handler.zig");

/// Interactive Graphics Canvas with layer management and real-time interaction
pub const InteractiveCanvas = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    terminal: *unified.Terminal,
    graphics: *graphics_manager.GraphicsManager,
    layers: std.ArrayList(Layer),
    viewport: Viewport,
    interaction: InteractionManager,
    animation: AnimationEngine,
    render_cache: RenderCache,
    dirty_regions: std.ArrayList(Rect),
    
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
        z_index: i32 = 0,
        
        pub const LayerContent = union(enum) {
            image: ImageLayer,
            vector: VectorLayer,
            text: TextLayer,
            chart: ChartLayer,
            drawing: DrawingLayer,
        };
        
        pub const ImageLayer = struct {
            image_id: u32,
            source_rect: ?Rect = null,
        };
        
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
        
        pub const TextLayer = struct {
            text: []const u8,
            position: Point2D,
            style: TextStyle,
            
            pub const TextStyle = struct {
                font_size: f32 = 12.0,
                color: unified.Color = unified.Colors.WHITE,
                bold: bool = false,
                italic: bool = false,
                underline: bool = false,
            };
        };
        
        pub const ChartLayer = struct {
            chart_type: ChartType,
            data: ChartData,
            style: ChartStyle,
            
            pub const ChartType = enum { line, bar, scatter, heatmap };
            
            pub const ChartData = struct {
                series: []DataSeries,
                
                pub const DataSeries = struct {
                    name: []const u8,
                    points: []Point2D,
                    color: unified.Color,
                };
            };
            
            pub const ChartStyle = struct {
                show_grid: bool = true,
                show_axes: bool = true,
                animate: bool = false,
            };
        };
        
        pub const DrawingLayer = struct {
            strokes: std.ArrayList(Stroke),
            
            pub const Stroke = struct {
                points: std.ArrayList(Point2D),
                color: unified.Color,
                width: f32,
                opacity: f32 = 1.0,
            };
        };
    };
    
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
    
    pub const BlendMode = enum {
        normal,
        multiply,
        screen,
        overlay,
        add,
        subtract,
    };
    
    pub const Viewport = struct {
        bounds: Rect,
        zoom: f32 = 1.0,
        offset: Point2D = .{ .x = 0, .y = 0 },
        
        pub fn worldToScreen(self: Viewport, world_point: Point2D) Point2D {
            return .{
                .x = (world_point.x - self.offset.x) * self.zoom + @as(f32, @floatFromInt(self.bounds.x)),
                .y = (world_point.y - self.offset.y) * self.zoom + @as(f32, @floatFromInt(self.bounds.y)),
            };
        }
        
        pub fn screenToWorld(self: Viewport, screen_point: Point2D) Point2D {
            return .{
                .x = (screen_point.x - @as(f32, @floatFromInt(self.bounds.x))) / self.zoom + self.offset.x,
                .y = (screen_point.y - @as(f32, @floatFromInt(self.bounds.y))) / self.zoom + self.offset.y,
            };
        }
    };
    
    pub const InteractionManager = struct {
        current_tool: Tool = .pointer,
        is_drawing: bool = false,
        active_layer: ?u32 = null,
        hover_layer: ?u32 = null,
        gesture_recognizer: GestureRecognizer,
        
        pub const Tool = enum {
            pointer,    // Selection and manipulation
            brush,      // Free-form drawing
            line,       // Line drawing
            rectangle,  // Rectangle drawing
            circle,     // Circle drawing
            text,       // Text insertion
            pan,        // Pan viewport
            zoom,       // Zoom tool
        };
        
        pub const GestureRecognizer = struct {
            touch_points: std.ArrayList(TouchPoint),
            current_gesture: ?Gesture = null,
            
            pub const TouchPoint = struct {
                id: u32,
                position: Point2D,
                start_position: Point2D,
                timestamp: u64,
            };
            
            pub const Gesture = enum {
                tap,
                double_tap,
                drag,
                pinch,
                rotate,
                swipe,
            };
        };
    };
    
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
    
    const Point2D = struct { x: f32, y: f32 };
    const Rect = struct { x: i32, y: i32, width: u32, height: u32 };
    
    pub fn init(allocator: std.mem.Allocator, terminal: *unified.Terminal) !*Self {
        const canvas = try allocator.create(Self);
        
        canvas.* = .{
            .allocator = allocator,
            .terminal = terminal,
            .graphics = graphics_manager.GraphicsManager.init(allocator, terminal),
            .layers = std.ArrayList(Layer).init(allocator),
            .viewport = .{ .bounds = .{ .x = 0, .y = 0, .width = 80, .height = 24 } },
            .interaction = .{ .gesture_recognizer = .{ .touch_points = std.ArrayList(InteractionManager.GestureRecognizer.TouchPoint).init(allocator) } },
            .animation = .{ .animations = std.ArrayList(AnimationEngine.Animation).init(allocator) },
            .render_cache = .{ .layer_cache = std.HashMap(u32, RenderCache.CachedLayer).init(allocator) },
            .dirty_regions = std.ArrayList(Rect).init(allocator),
        };
        
        return canvas;
    }
    
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
        self.interaction.gesture_recognizer.touch_points.deinit();
        self.animation.animations.deinit();
        self.graphics.deinit();
        
        self.allocator.destroy(self);
    }
    
    /// Create a new layer and return its ID
    pub fn createLayer(self: *Self, name: []const u8, layer_type: Layer.LayerContent) !u32 {
        const layer_id = @as(u32, @intCast(self.layers.items.len));
        
        const layer = Layer{
            .id = layer_id,
            .name = name,
            .content = layer_type,
            .transform = .{},
        };
        
        try self.layers.append(layer);
        self.markDirty(null); // Mark entire canvas as dirty
        
        return layer_id;
    }
    
    /// Set the viewport size (typically terminal dimensions)
    pub fn setViewport(self: *Self, bounds: Rect) void {
        self.viewport.bounds = bounds;
        self.markDirty(null);
    }
    
    /// Add a vector element to a layer
    pub fn addVectorElement(self: *Self, layer_id: u32, element: Layer.VectorLayer.VectorElement) !void {
        if (layer_id >= self.layers.items.len) return error.InvalidLayerId;
        
        const layer = &self.layers.items[layer_id];
        switch (layer.content) {
            .vector => |*vector_layer| {
                try vector_layer.elements.append(element);
                self.invalidateLayerCache(layer_id);
            },
            else => return error.InvalidLayerType,
        }
    }
    
    /// Start drawing on a drawing layer
    pub fn startDrawing(self: *Self, layer_id: u32, start_point: Point2D, color: unified.Color, width: f32) !void {
        if (layer_id >= self.layers.items.len) return error.InvalidLayerId;
        
        const layer = &self.layers.items[layer_id];
        switch (layer.content) {
            .drawing => |*drawing_layer| {
                var stroke = Layer.DrawingLayer.Stroke{
                    .points = std.ArrayList(Point2D).init(self.allocator),
                    .color = color,
                    .width = width,
                };
                
                try stroke.points.append(start_point);
                try drawing_layer.strokes.append(stroke);
                
                self.interaction.is_drawing = true;
                self.interaction.active_layer = layer_id;
                self.invalidateLayerCache(layer_id);
            },
            else => return error.InvalidLayerType,
        }
    }
    
    /// Continue drawing (add point to current stroke)
    pub fn continueDrawing(self: *Self, point: Point2D) !void {
        if (!self.interaction.is_drawing or self.interaction.active_layer == null) return;
        
        const layer_id = self.interaction.active_layer.?;
        const layer = &self.layers.items[layer_id];
        
        switch (layer.content) {
            .drawing => |*drawing_layer| {
                if (drawing_layer.strokes.items.len > 0) {
                    const current_stroke = &drawing_layer.strokes.items[drawing_layer.strokes.items.len - 1];
                    try current_stroke.points.append(point);
                    
                    // Mark only the affected region as dirty
                    const last_point = current_stroke.points.items[current_stroke.points.items.len - 2];
                    const stroke_rect = self.calculateStrokeRect(last_point, point, current_stroke.width);
                    try self.dirty_regions.append(stroke_rect);
                    
                    self.invalidateLayerCache(layer_id);
                }
            },
            else => {},
        }
    }
    
    /// End drawing
    pub fn endDrawing(self: *Self) void {
        self.interaction.is_drawing = false;
        self.interaction.active_layer = null;
    }
    
    /// Handle input events
    pub fn handleInput(self: *Self, input: InputEvent) !bool {
        switch (input) {
            .mouse => |mouse| return try self.handleMouseInput(mouse),
            .keyboard => |key| return try self.handleKeyboardInput(key),
            .touch => |touch| return try self.handleTouchInput(touch),
        }
    }
    
    const InputEvent = union(enum) {
        mouse: MouseEvent,
        keyboard: KeyboardEvent,
        touch: TouchEvent,
        
        pub const MouseEvent = struct {
            action: Action,
            position: Point2D,
            button: Button = .left,
            modifiers: Modifiers = .{},
            
            pub const Action = enum { press, release, move, scroll_up, scroll_down };
            pub const Button = enum { left, right, middle };
            pub const Modifiers = struct { ctrl: bool = false, alt: bool = false, shift: bool = false };
        };
        
        pub const KeyboardEvent = struct {
            key: u32,
            modifiers: MouseEvent.Modifiers = .{},
        };
        
        pub const TouchEvent = struct {
            touches: []TouchPoint,
            
            pub const TouchPoint = struct {
                id: u32,
                position: Point2D,
                phase: Phase,
                
                pub const Phase = enum { began, moved, ended };
            };
        };
    };
    
    fn handleMouseInput(self: *Self, mouse: InputEvent.MouseEvent) !bool {
        const world_pos = self.viewport.screenToWorld(mouse.position);
        
        switch (mouse.action) {
            .press => {
                switch (self.interaction.current_tool) {
                    .brush => {
                        if (self.interaction.active_layer) |layer_id| {
                            try self.startDrawing(layer_id, world_pos, unified.Colors.WHITE, 2.0);
                            return true;
                        }
                    },
                    .pan => {
                        // Start panning
                        return true;
                    },
                    else => {},
                }
            },
            .move => {
                if (self.interaction.is_drawing) {
                    try self.continueDrawing(world_pos);
                    return true;
                }
            },
            .release => {
                if (self.interaction.is_drawing) {
                    self.endDrawing();
                    return true;
                }
            },
            .scroll_up => {
                self.viewport.zoom *= 1.1;
                self.markDirty(null);
                return true;
            },
            .scroll_down => {
                self.viewport.zoom *= 0.9;
                self.markDirty(null);
                return true;
            },
        }
        
        return false;
    }
    
    fn handleKeyboardInput(self: *Self, key: InputEvent.KeyboardEvent) !bool {
        switch (key.key) {
            'p', 'P' => {
                self.interaction.current_tool = .pointer;
                return true;
            },
            'b', 'B' => {
                self.interaction.current_tool = .brush;
                return true;
            },
            'l', 'L' => {
                self.interaction.current_tool = .line;
                return true;
            },
            'r', 'R' => {
                self.interaction.current_tool = .rectangle;
                return true;
            },
            'c', 'C' => {
                self.interaction.current_tool = .circle;
                return true;
            },
            27 => { // ESC key
                if (self.interaction.is_drawing) {
                    self.endDrawing();
                    return true;
                }
            },
            else => return false,
        }
        
        return false;
    }
    
    fn handleTouchInput(self: *Self, touch: InputEvent.TouchEvent) !bool {
        // Update gesture recognizer with touch points
        _ = self;
        _ = touch; // Placeholder implementation
        return false;
    }
    
    /// Render the complete canvas with all layers
    pub fn render(self: *Self) !void {
        // Check if we need to render at all
        if (self.dirty_regions.items.len == 0) return;
        
        // Sort layers by z-index
        std.mem.sort(Layer, self.layers.items, {}, layerCompare);
        
        // Update animations first
        try self.updateAnimations();
        
        // Render each layer based on terminal capabilities
        const graphics_mode = self.graphics.getMode();
        
        switch (graphics_mode) {
            .kitty => try self.renderCompositeKitty(),
            .sixel => try self.renderCompositeSixel(),
            .unicode => try self.renderCompositeUnicode(),
            .ascii => try self.renderCompositeASCII(),
            .none => {}, // No graphics support
        }
        
        // Clear dirty regions
        self.dirty_regions.clearRetainingCapacity();
    }
    
    fn layerCompare(_: void, a: Layer, b: Layer) bool {
        return a.z_index < b.z_index;
    }
    
    fn renderCompositeKitty(self: *Self) !void {
        // Use Kitty graphics protocol for high-quality rendering
        const width = self.viewport.bounds.width * 8;  // 8 pixels per character cell
        const height = self.viewport.bounds.height * 16; // 16 pixels per character cell
        
        // Create composite image
        const composite_data = try self.allocator.alloc(u8, width * height * 4); // RGBA
        defer self.allocator.free(composite_data);
        
        // Clear with transparent background
        @memset(composite_data, 0);
        
        // Render each visible layer
        for (self.layers.items) |layer| {
            if (!layer.visible) continue;
            try self.renderLayerToBuffer(layer, composite_data, width, height);
        }
        
        // Upload to graphics manager and display
        const image_id = try self.graphics.createImage(composite_data, width, height, .rgba32);
        defer self.graphics.removeImage(image_id);
        
        const render_options = graphics_manager.RenderOptions{
            .max_width = self.viewport.bounds.width,
            .max_height = self.viewport.bounds.height,
            .preserve_aspect_ratio = true,
        };
        
        try self.graphics.renderImage(image_id, .{ .x = self.viewport.bounds.x, .y = self.viewport.bounds.y }, render_options);
    }
    
    fn renderCompositeSixel(self: *Self) !void {
        // Similar to Kitty but using Sixel protocol
        // Implementation would create an RGB buffer and convert to Sixel
        std.debug.print("[Sixel Canvas Rendering - {} layers]\n", .{self.layers.items.len});
    }
    
    fn renderCompositeUnicode(self: *Self) !void {
        // Use Unicode block characters for visualization
        try self.terminal.moveTo(self.viewport.bounds.x, self.viewport.bounds.y);
        
        // Simple ASCII representation of layers
        for (0..self.viewport.bounds.height) |y| {
            for (0..self.viewport.bounds.width) |x| {
                const world_point = self.viewport.screenToWorld(.{ 
                    .x = @as(f32, @floatFromInt(x)), 
                    .y = @as(f32, @floatFromInt(y)) 
                });
                
                const char = self.getCharAtWorldPosition(world_point);
                try self.terminal.print(char, null);
            }
            if (y < self.viewport.bounds.height - 1) {
                try self.terminal.print("\n", null);
            }
        }
    }
    
    fn renderCompositeASCII(self: *Self) !void {
        // ASCII fallback rendering
        try self.renderCompositeUnicode(); // Use same implementation for now
    }
    
    fn renderLayerToBuffer(self: *Self, layer: Layer, buffer: []u8, width: u32, height: u32) !void {
        switch (layer.content) {
            .vector => |vector_layer| {
                try self.renderVectorLayerToBuffer(vector_layer, layer.transform, buffer, width, height);
            },
            .drawing => |drawing_layer| {
                try self.renderDrawingLayerToBuffer(drawing_layer, layer.transform, buffer, width, height);
            },
            .chart => |chart_layer| {
                try self.renderChartLayerToBuffer(chart_layer, layer.transform, buffer, width, height);
            },
            else => {}, // Placeholder for other layer types
        }
    }
    
    fn renderVectorLayerToBuffer(self: *Self, vector_layer: Layer.VectorLayer, transform: Transform2D, buffer: []u8, width: u32, height: u32) !void {
        _ = self;
        _ = transform;
        _ = buffer;
        _ = width;
        _ = height;
        
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
    
    fn renderDrawingLayerToBuffer(self: *Self, drawing_layer: Layer.DrawingLayer, transform: Transform2D, buffer: []u8, width: u32, height: u32) !void {
        _ = transform;
        
        for (drawing_layer.strokes.items) |stroke| {
            // Render each stroke as connected line segments
            for (stroke.points.items[1..], 0..) |point, i| {
                const prev_point = stroke.points.items[i];
                
                // Draw line from prev_point to point with stroke.width and stroke.color
                self.drawLineToBuffer(buffer, width, prev_point, point, stroke.color, stroke.width);
            }
        }
    }
    
    fn renderChartLayerToBuffer(self: *Self, chart_layer: Layer.ChartLayer, transform: Transform2D, buffer: []u8, width: u32, height: u32) !void {
        _ = self;
        _ = chart_layer;
        _ = transform;
        _ = buffer;
        _ = width;
        _ = height;
        // Implementation would render chart data
    }
    
    fn drawLineToBuffer(self: *Self, buffer: []u8, width: u32, start: Point2D, end: Point2D, color: unified.Color, line_width: f32) void {
        _ = self;
        _ = buffer;
        _ = width;
        _ = start;
        _ = end;
        _ = color;
        _ = line_width;
        // Implementation would use Bresenham algorithm to draw line
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
    
    fn getCharAtWorldPosition(self: *Self, world_pos: Point2D) []const u8 {
        // Check each layer for content at this position
        for (self.layers.items) |layer| {
            if (!layer.visible) continue;
            
            switch (layer.content) {
                .drawing => |drawing_layer| {
                    for (drawing_layer.strokes.items) |stroke| {
                        if (self.strokeContainsPoint(stroke, world_pos)) {
                            return "█"; // Solid block for drawing
                        }
                    }
                },
                .vector => |vector_layer| {
                    for (vector_layer.elements.items) |element| {
                        if (self.vectorElementContainsPoint(element, world_pos)) {
                            return "▓"; // Medium shade for vector elements
                        }
                    }
                },
                else => {},
            }
        }
        
        return " "; // Empty space
    }
    
    fn strokeContainsPoint(self: *Self, stroke: Layer.DrawingLayer.Stroke, point: Point2D) bool {
        _ = self;
        _ = point;
        
        // Simple distance check from stroke points
        for (stroke.points.items) |stroke_point| {
            const dx = stroke_point.x - point.x;
            const dy = stroke_point.y - point.y;
            const distance = std.math.sqrt(dx * dx + dy * dy);
            
            if (distance <= stroke.width) {
                return true;
            }
        }
        
        return false;
    }
    
    fn vectorElementContainsPoint(self: *Self, element: Layer.VectorLayer.VectorElement, point: Point2D) bool {
        _ = self;
        
        switch (element) {
            .circle => |circle| {
                const dx = circle.center.x - point.x;
                const dy = circle.center.y - point.y;
                const distance = std.math.sqrt(dx * dx + dy * dy);
                return distance <= circle.radius;
            },
            .rectangle => |rect| {
                return point.x >= @as(f32, @floatFromInt(rect.rect.x)) and 
                       point.x <= @as(f32, @floatFromInt(rect.rect.x + @as(i32, @intCast(rect.rect.width)))) and
                       point.y >= @as(f32, @floatFromInt(rect.rect.y)) and 
                       point.y <= @as(f32, @floatFromInt(rect.rect.y + @as(i32, @intCast(rect.rect.height))));
            },
            else => return false,
        }
    }
    
    fn markDirty(self: *Self, region: ?Rect) void {
        const dirty_rect = region orelse self.viewport.bounds;
        self.dirty_regions.append(dirty_rect) catch {};
    }
    
    fn invalidateLayerCache(self: *Self, layer_id: u32) void {
        if (self.render_cache.layer_cache.get(layer_id)) |cached_layer| {
            self.graphics.removeImage(cached_layer.image_id);
            _ = self.render_cache.layer_cache.remove(layer_id);
        }
        self.markDirty(null);
    }
    
    fn calculateStrokeRect(self: *Self, start: Point2D, end: Point2D, width: f32) Rect {
        _ = self;
        
        const min_x = @min(start.x, end.x) - width;
        const max_x = @max(start.x, end.x) + width;
        const min_y = @min(start.y, end.y) - width;
        const max_y = @max(start.y, end.y) + width;
        
        return Rect{
            .x = @as(i32, @intFromFloat(min_x)),
            .y = @as(i32, @intFromFloat(min_y)),
            .width = @as(u32, @intFromFloat(max_x - min_x)),
            .height = @as(u32, @intFromFloat(max_y - min_y)),
        };
    }
    
    fn cleanupLayer(self: *Self, layer: *Layer) void {
        _ = self;
        switch (layer.content) {
            .vector => |*vector_layer| {
                vector_layer.elements.deinit();
            },
            .drawing => |*drawing_layer| {
                for (drawing_layer.strokes.items) |*stroke| {
                    stroke.points.deinit();
                }
                drawing_layer.strokes.deinit();
            },
            .chart => |*chart_layer| {
                _ = chart_layer; // Chart data cleanup if needed
            },
            else => {},
        }
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
};
//! Chart renderer coordination and progressive enhancement
//! 
//! This module coordinates different chart rendering methods and handles progressive
//! enhancement based on terminal capabilities.

const std = @import("std");
const base = @import("base.zig");
const graphics = @import("graphics.zig");
const line = @import("line.zig");
const bar = @import("bar.zig");
const graphics_manager = @import("../../../../term/graphics_manager.zig");
const renderer_mod = @import("../../../core/renderer.zig");

const ChartData = base.ChartData;
const ChartStyle = base.ChartStyle;
const ChartType = base.ChartType;
const Config = base.Config;
const Bounds = base.Bounds;
const RenderedImage = base.RenderedImage;
const DrawingContext = graphics.DrawingContext;
const Renderer = renderer_mod.Renderer;
const RenderContext = renderer_mod.RenderContext;
const GraphicsMode = graphics_manager.GraphicsMode;

/// Main chart renderer that handles all chart types and rendering modes
pub const ChartRenderer = struct {
    allocator: std.mem.Allocator,
    data: ChartData,
    style: ChartStyle,
    config: Config,
    bounds: Bounds = Bounds.init(0, 0, 0, 0),
    
    // Graphics caching
    rendered_image: ?RenderedImage = null,
    graphics_dirty: bool = true,
    
    pub fn init(allocator: std.mem.Allocator, data: ChartData, config: Config) ChartRenderer {
        return ChartRenderer{
            .allocator = allocator,
            .data = data,
            .style = ChartStyle{},
            .config = config,
        };
    }
    
    pub fn deinit(self: *ChartRenderer) void {
        if (self.rendered_image) |*image| {
            image.deinit(self.allocator);
        }
    }
    
    pub fn setData(self: *ChartRenderer, data: ChartData) void {
        self.data = data;
        self.graphics_dirty = true;
    }
    
    pub fn setStyle(self: *ChartRenderer, style: ChartStyle) void {
        self.style = style;
        self.graphics_dirty = true;
    }
    
    pub fn setBounds(self: *ChartRenderer, bounds: Bounds) void {
        self.bounds = bounds;
        self.graphics_dirty = true;
    }
    
    /// Main rendering method that chooses the appropriate rendering mode
    pub fn render(self: *ChartRenderer, renderer: *Renderer, ctx: RenderContext) !void {
        self.bounds = ctx.bounds;
        
        // Determine the best rendering mode based on terminal capabilities
        const graphics_mode = self.detectGraphicsMode(renderer);
        
        switch (graphics_mode) {
            .kitty, .sixel => try self.renderGraphics(renderer, ctx, graphics_mode),
            .unicode => try self.renderUnicode(renderer, ctx),
            .ascii => try self.renderAscii(renderer, ctx),
            .none => try self.renderTextOnly(renderer, ctx),
        }
    }
    
    /// Detect the best graphics mode for the terminal
    fn detectGraphicsMode(self: *ChartRenderer, renderer: *Renderer) GraphicsMode {
        _ = self;
        
        const caps = renderer.getCapabilities();
        return GraphicsMode.detect(caps);
    }
    
    /// Render chart using graphics protocols (Kitty/Sixel)
    fn renderGraphics(self: *ChartRenderer, renderer: *Renderer, ctx: RenderContext, mode: GraphicsMode) !void {
        // Generate or use cached image
        if (self.graphics_dirty or self.rendered_image == null) {
            try self.generateImage(mode);
            self.graphics_dirty = false;
        }
        
        if (self.rendered_image) |image| {
            const image_render = renderer_mod.Image{
                .format = switch (image.format) {
                    .RGBA => .ascii_art, // TODO: Map to proper graphics format
                    .RGB => .ascii_art,
                    .PNG => .ascii_art,
                },
                .data = image.data,
                .width = image.width,
                .height = image.height,
            };
            
            try renderer.drawImage(ctx, image_render);
        }
    }
    
    /// Render chart using Unicode block characters
    fn renderUnicode(self: *ChartRenderer, renderer: *Renderer, ctx: RenderContext) !void {
        switch (self.config.chart_type) {
            .line => try line.LineChart.renderUnicode(self.data, self.style, renderer, ctx),
            .bar => try bar.BarChart.renderUnicode(self.data, self.style, renderer, ctx),
            .area => try line.AreaChart.renderToBitmap(self.data, self.style, undefined, undefined), // TODO: Add Unicode area chart
            else => try self.renderTextOnly(renderer, ctx),
        }
    }
    
    /// Render chart using ASCII characters
    fn renderAscii(self: *ChartRenderer, renderer: *Renderer, ctx: RenderContext) !void {
        switch (self.config.chart_type) {
            .line => try line.LineChart.renderAscii(self.data, self.style, renderer, ctx),
            .bar => try bar.BarChart.renderAscii(self.data, self.style, renderer, ctx),
            else => try self.renderTextOnly(renderer, ctx),
        }
    }
    
    /// Fallback text-only rendering
    fn renderTextOnly(self: *ChartRenderer, renderer: *Renderer, ctx: RenderContext) !void {
        // Simple text representation of data
        const title_ctx = RenderContext{
            .bounds = Bounds.init(ctx.bounds.x, ctx.bounds.y, ctx.bounds.width, 1),
            .style = ctx.style,
            .z_index = ctx.z_index,
            .clip_region = ctx.clip_region,
        };
        try renderer.drawText(title_ctx, self.config.title orelse "Chart");
        
        var row: i32 = 2;
        for (self.data.series) |series| {
            // Series name
            const series_ctx = RenderContext{
                .bounds = Bounds.init(ctx.bounds.x, ctx.bounds.y + row, ctx.bounds.width, 1),
                .style = ctx.style,
                .z_index = ctx.z_index,
                .clip_region = ctx.clip_region,
            };
            
            var buffer: [256]u8 = undefined;
            const series_text = try std.fmt.bufPrint(buffer[0..], "{s}:", .{series.name});
            try renderer.drawText(series_ctx, series_text);
            row += 1;
            
            // Values (abbreviated)
            for (series.values[0..@min(5, series.values.len)], 0..) |value, i| {
                const value_ctx = RenderContext{
                    .bounds = Bounds.init(ctx.bounds.x + 2, ctx.bounds.y + row, ctx.bounds.width - 2, 1),
                    .style = ctx.style,
                    .z_index = ctx.z_index,
                    .clip_region = ctx.clip_region,
                };
                
                const value_text = try std.fmt.bufPrint(buffer[0..], "[{d}] {d:.2}", .{ i, value });
                try renderer.drawText(value_ctx, value_text);
                row += 1;
                
                if (row >= ctx.bounds.height - ctx.bounds.y) break;
            }
            
            if (series.values.len > 5) {
                const more_ctx = RenderContext{
                    .bounds = Bounds.init(ctx.bounds.x + 2, ctx.bounds.y + row, ctx.bounds.width - 2, 1),
                    .style = ctx.style,
                    .z_index = ctx.z_index,
                    .clip_region = ctx.clip_region,
                };
                
                const more_text = try std.fmt.bufPrint(buffer[0..], "... and {d} more values", .{series.values.len - 5});
                try renderer.drawText(more_ctx, more_text);
                row += 1;
            }
            
            row += 1; // Space between series
            if (row >= ctx.bounds.height - ctx.bounds.y) break;
        }
    }
    
    /// Generate bitmap image for graphics rendering
    fn generateImage(self: *ChartRenderer, mode: GraphicsMode) !void {
        _ = mode;
        
        // Free existing image if any
        if (self.rendered_image) |*image| {
            image.deinit(self.allocator);
            self.rendered_image = null;
        }
        
        // Calculate image dimensions based on terminal bounds
        // Each terminal cell is approximately 8x16 pixels
        const image_width = @as(u32, @intCast(self.bounds.width)) * 8;
        const image_height = @as(u32, @intCast(self.bounds.height)) * 16;
        
        // Create RGBA image buffer
        const pixel_count = image_width * image_height;
        const image_data = try self.allocator.alloc(u8, pixel_count * 4); // RGBA
        
        // Create drawing context
        const ctx = DrawingContext{
            .image_data = image_data,
            .width = image_width,
            .height = image_height,
        };
        
        // Clear background
        ctx.fillBackground(self.style.background_color);
        
        // Calculate chart area (accounting for padding)
        const chart_area = base.ChartArea.calculate(
            Bounds.init(0, 0, @intCast(image_width), @intCast(image_height)),
            self.style
        );
        
        // Draw chart based on type
        switch (self.config.chart_type) {
            .line => try line.LineChart.renderToBitmap(self.data, self.style, ctx, chart_area),
            .bar => try bar.BarChart.renderToBitmap(self.data, self.style, ctx, chart_area),
            .area => try line.AreaChart.renderToBitmap(self.data, self.style, ctx, chart_area),
            .pie => try self.renderPieChartToBitmap(ctx, chart_area),
            .scatter => try self.renderScatterChartToBitmap(ctx, chart_area),
            .heatmap => try self.renderHeatmapToBitmap(ctx, chart_area),
            .candlestick => try self.renderCandlestickToBitmap(ctx, chart_area),
        }
        
        self.rendered_image = RenderedImage{
            .data = image_data,
            .width = image_width,
            .height = image_height,
            .format = .RGBA,
        };
    }
    
    // Placeholder implementations for chart types not yet modularized
    fn renderPieChartToBitmap(self: *ChartRenderer, ctx: DrawingContext, chart_area: Bounds) !void {
        // TODO: Move to pie.zig module
        _ = self; _ = ctx; _ = chart_area;
    }
    
    fn renderScatterChartToBitmap(self: *ChartRenderer, ctx: DrawingContext, chart_area: Bounds) !void {
        // TODO: Move to scatter.zig module  
        _ = self; _ = ctx; _ = chart_area;
    }
    
    fn renderHeatmapToBitmap(self: *ChartRenderer, ctx: DrawingContext, chart_area: Bounds) !void {
        // TODO: Move to heatmap.zig module
        _ = self; _ = ctx; _ = chart_area;
    }
    
    fn renderCandlestickToBitmap(self: *ChartRenderer, ctx: DrawingContext, chart_area: Bounds) !void {
        // TODO: Move to candlestick.zig module
        _ = self; _ = ctx; _ = chart_area;
    }
};
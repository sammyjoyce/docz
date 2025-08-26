//! Enhanced Graphics Manager
//!
//! Provides high-level graphics capabilities using Kitty Graphics Protocol, Sixel, 
//! and ASCII art fallbacks. This leverages the underutilized graphics capabilities
//! available in the terminal system.

const std = @import("std");
const unified = @import("unified.zig");
const ansi_graphics = @import("ansi/graphics.zig");

const Terminal = unified.Terminal;
const Image = unified.Image;
const Point = unified.Point;
const Color = unified.Color;
const TermCaps = unified.TermCaps;

/// Graphics rendering modes based on terminal capabilities
pub const GraphicsMode = enum {
    kitty,      // Kitty Graphics Protocol (best quality)
    sixel,      // Sixel graphics (good compatibility)  
    ascii,      // ASCII art fallback (universal)
    unicode,    // Unicode block art (better than ASCII)
    none,       // No graphics support
    
    /// Detect best available graphics mode
    pub fn detect(caps: TermCaps) GraphicsMode {
        if (caps.supportsKittyGraphics) return .kitty;
        if (caps.supportsSixel) return .sixel;
        return .unicode; // Unicode is widely supported
    }
};

/// Graphics manager that handles image rendering and caching
pub const GraphicsManager = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    terminal: *Terminal,
    mode: GraphicsMode,
    image_cache: ImageCache,
    next_image_id: u32,
    
    const ImageCache = std.HashMap(u32, CachedImage);
    
    const CachedImage = struct {
        data: []const u8,
        width: u32,
        height: u32,
        format: Image.Format,
        rendered_data: ?[]const u8, // Cached rendered data for mode
    };
    
    pub fn init(allocator: std.mem.Allocator, terminal: *Terminal) Self {
        const caps = terminal.getCapabilities();
        const mode = GraphicsMode.detect(caps);
        
        return Self{
            .allocator = allocator,
            .terminal = terminal,
            .mode = mode,
            .image_cache = ImageCache.init(allocator),
            .next_image_id = 1,
        };
    }
    
    pub fn deinit(self: *Self) void {
        var iterator = self.image_cache.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.data);
            if (entry.value_ptr.rendered_data) |rd| {
                self.allocator.free(rd);
            }
        }
        self.image_cache.deinit();
    }
    
    /// Load an image from file path
    pub fn loadImage(self: *Self, path: []const u8) !u32 {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        
        const data = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB limit
        const format = detectImageFormat(path, data);
        
        // Get image dimensions (simplified - in real implementation would decode headers)
        const dimensions = try getImageDimensions(data, format);
        
        const image_id = self.next_image_id;
        self.next_image_id += 1;
        
        try self.image_cache.put(image_id, CachedImage{
            .data = data,
            .width = dimensions.width,
            .height = dimensions.height,
            .format = format,
            .rendered_data = null,
        });
        
        return image_id;
    }
    
    /// Create image from raw data
    pub fn createImage(self: *Self, data: []const u8, width: u32, height: u32, format: Image.Format) !u32 {
        const owned_data = try self.allocator.dupe(u8, data);
        
        const image_id = self.next_image_id;
        self.next_image_id += 1;
        
        try self.image_cache.put(image_id, CachedImage{
            .data = owned_data,
            .width = width,
            .height = height,
            .format = format,
            .rendered_data = null,
        });
        
        return image_id;
    }
    
    /// Render image at specified position with optional scaling
    pub fn renderImage(self: *Self, image_id: u32, pos: Point, options: RenderOptions) !void {
        const cached_image = self.image_cache.get(image_id) orelse return error.ImageNotFound;
        
        const display_width = options.max_width orelse cached_image.width;
        const display_height = options.max_height orelse cached_image.height;
        
        // Move to position
        try self.terminal.moveTo(pos.x, pos.y);
        
        switch (self.mode) {
            .kitty => try self.renderKittyImage(cached_image, display_width, display_height, options),
            .sixel => try self.renderSixelImage(cached_image, display_width, display_height, options),
            .unicode => try self.renderUnicodeImage(cached_image, display_width, display_height, options),
            .ascii => try self.renderAsciiImage(cached_image, display_width, display_height, options),
            .none => {}, // No graphics support
        }
    }
    
    /// Create a chart/graph as an image
    pub fn createChart(self: *Self, chart: Chart) !u32 {
        const rendered_data = try self.renderChart(chart);
        return self.createImage(rendered_data, chart.width, chart.height, .rgba32);
    }
    
    /// Create a progress visualization
    pub fn createProgressVisualization(self: *Self, progress: f32, style: ProgressVisualizationStyle) !u32 {
        const vis_data = try self.renderProgressVisualization(progress, style);
        return self.createImage(vis_data, style.width, style.height, .rgba32);
    }
    
    /// Remove image from cache
    pub fn removeImage(self: *Self, image_id: u32) void {
        if (self.image_cache.fetchRemove(image_id)) |entry| {
            self.allocator.free(entry.value.data);
            if (entry.value.rendered_data) |rd| {
                self.allocator.free(rd);
            }
        }
    }
    
    /// Get current graphics mode
    pub fn getMode(self: *Self) GraphicsMode {
        return self.mode;
    }
    
    /// Check if specific image format is supported
    pub fn supportsFormat(self: *Self, format: Image.Format) bool {
        return switch (self.mode) {
            .kitty => true, // Kitty supports all formats
            .sixel => format != .gif, // Sixel supports most formats but GIF needs conversion
            .unicode, .ascii, .none => false, // Text modes don't support native formats
        };
    }
    
    // Private rendering implementations
    
    fn renderKittyImage(self: *Self, image: CachedImage, width: u32, height: u32, options: RenderOptions) !void {
        const format_code = switch (image.format) {
            .png => "f=100",
            .jpeg => "f=100", 
            .gif => "f=100",
            .rgb24 => "f=24",
            .rgba32 => "f=32",
        };
        
        // Use placement options for scaling and positioning
        const transmission_medium = if (options.persistent) "f" else "t";
        
        const encoded = try self.allocator.alloc(u8, std.base64.Encoder.calcSize(image.data.len));
        defer self.allocator.free(encoded);
        _ = std.base64.standard.Encoder.encode(encoded, image.data);
        
        try self.terminal.writer.print(
            "\x1b_G{s}={s},{s},s={d},v={d},C=1;{s}\x1b\\",
            .{ transmission_medium, transmission_medium, format_code, width, height, encoded }
        );
    }
    
    fn renderSixelImage(self: *Self, image: CachedImage, width: u32, height: u32, options: RenderOptions) !void {
        // Basic Sixel implementation - convert to indexed color format
        const sixel_data = try self.convertToSixel(image, width, height);
        defer self.allocator.free(sixel_data);
        
        // Options could be used for background color, transparency, etc.
        _ = options;
        
        try self.terminal.writer.print("\x1bP0;0;0q{s}\x1b\\", .{sixel_data});
    }
    
    fn renderUnicodeImage(self: *Self, image: CachedImage, width: u32, height: u32, options: RenderOptions) !void {
        // Convert to Unicode block art using half-blocks for higher resolution
        const block_width = (width + 1) / 2; // Each character represents 2 pixels wide
        const block_height = (height + 1) / 4; // Each character represents 4 pixels tall with quarter blocks
        
        // Options could be used for background color, dithering, etc.
        _ = options;
        
        // Sample the image at block positions and convert to colors
        var y: u32 = 0;
        while (y < block_height) : (y += 1) {
            var x: u32 = 0;
            while (x < block_width) : (x += 1) {
                // Sample 2x4 pixel region and convert to best Unicode block character
                const sample_x = (x * 2 * image.width) / width;
                const sample_y = (y * 4 * image.height) / height;
                
                // For now, use simple intensity-based blocks (could be enhanced with actual color sampling)
                const intensity = self.sampleIntensity(image, sample_x, sample_y);
                const block_char = intensityToBlock(intensity);
                
                try self.terminal.writer.writeAll(block_char);
            }
            if (y < block_height - 1) try self.terminal.writer.writeAll("\n");
        }
    }
    
    fn renderAsciiImage(self: *Self, image: CachedImage, width: u32, height: u32, options: RenderOptions) !void {
        _ = options;
        
        const ascii_chars = " .:-=+*#%@";
        const char_width = @min(width, 80); // Limit ASCII width
        const char_height = @min(height, 24); // Limit ASCII height
        
        var y: u32 = 0;
        while (y < char_height) : (y += 1) {
            var x: u32 = 0;
            while (x < char_width) : (x += 1) {
                const sample_x = (x * image.width) / char_width;
                const sample_y = (y * image.height) / char_height;
                
                const intensity = self.sampleIntensity(image, sample_x, sample_y);
                const char_idx = @min(ascii_chars.len - 1, @as(usize, @intFromFloat(intensity * @as(f32, @floatFromInt(ascii_chars.len)))));
                
                try self.terminal.writer.print("{c}", .{ascii_chars[char_idx]});
            }
            if (y < char_height - 1) try self.terminal.writer.writeAll("\n");
        }
    }
    
    fn sampleIntensity(self: *Self, image: CachedImage, x: u32, y: u32) f32 {
        // Simplified intensity sampling - real implementation would decode image data
        // For now return a pattern for demonstration based on position
        _ = self;
        _ = image;
        
        return @as(f32, @floatFromInt((x + y) % 10)) / 10.0;
    }
    
    fn convertToSixel(self: *Self, image: CachedImage, width: u32, height: u32) ![]u8 {
        _ = image;
        _ = width;
        _ = height;
        
        // Simplified Sixel conversion - real implementation would:
        // 1. Convert image to 6-row strips
        // 2. Apply color quantization  
        // 3. Encode as Sixel format with color palette
        
        return try self.allocator.dupe(u8, "\"1;1;80;24");  // Basic Sixel header
    }
    
    fn renderChart(self: *Self, chart: Chart) ![]u8 {
        const pixel_count = chart.width * chart.height * 4; // RGBA
        const data = try self.allocator.alloc(u8, pixel_count);
        
        // Clear background
        var i: usize = 0;
        while (i < pixel_count) : (i += 4) {
            data[i] = 32;     // R
            data[i + 1] = 32; // G  
            data[i + 2] = 32; // B
            data[i + 3] = 255; // A
        }
        
        // Render chart elements based on type
        switch (chart.chart_type) {
            .bar => try self.renderBarChart(data, chart),
            .line => try self.renderLineChart(data, chart),
            .pie => try self.renderPieChart(data, chart),
        }
        
        return data;
    }
    
    fn renderProgressVisualization(self: *Self, progress: f32, style: ProgressVisualizationStyle) ![]u8 {
        const pixel_count = style.width * style.height * 4; // RGBA
        const data = try self.allocator.alloc(u8, pixel_count);
        
        const filled_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(style.width)) * progress));
        
        var y: u32 = 0;
        while (y < style.height) : (y += 1) {
            var x: u32 = 0;
            while (x < style.width) : (x += 1) {
                const idx = (y * style.width + x) * 4;
                
                if (x < filled_width) {
                    // Filled portion - gradient from green to red based on progress  
                    if (progress < 0.5) {
                        data[idx] = @as(u8, @intFromFloat(255.0 * progress * 2.0));     // R
                        data[idx + 1] = 255;                                            // G
                        data[idx + 2] = 0;                                              // B
                    } else {
                        data[idx] = 255;                                                     // R
                        data[idx + 1] = @as(u8, @intFromFloat(255.0 * (1.0 - progress)));   // G
                        data[idx + 2] = 0;                                                   // B
                    }
                    data[idx + 3] = 255; // A
                } else {
                    // Empty portion
                    data[idx] = 64;       // R
                    data[idx + 1] = 64;   // G
                    data[idx + 2] = 64;   // B
                    data[idx + 3] = 255;  // A
                }
            }
        }
        
        return data;
    }
    
    fn renderBarChart(self: *Self, data: []u8, chart: Chart) !void {
        _ = self;
        _ = data;
        _ = chart;
        // TODO: Implement bar chart rendering
    }
    
    fn renderLineChart(self: *Self, data: []u8, chart: Chart) !void {
        _ = self;
        _ = data;
        _ = chart;
        // TODO: Implement line chart rendering
    }
    
    fn renderPieChart(self: *Self, data: []u8, chart: Chart) !void {
        _ = self;
        _ = data; 
        _ = chart;
        // TODO: Implement pie chart rendering
    }
};

/// Options for image rendering
pub const RenderOptions = struct {
    max_width: ?u32 = null,
    max_height: ?u32 = null,
    preserve_aspect_ratio: bool = true,
    background_color: ?Color = null,
    persistent: bool = false, // Keep image in terminal's memory (Kitty only)
};

/// Chart data and configuration
pub const Chart = struct {
    width: u32,
    height: u32,
    chart_type: ChartType,
    title: ?[]const u8,
    data_points: []const DataPoint,
    colors: []const Color,
    
    pub const ChartType = enum {
        bar,
        line,
        pie,
    };
    
    pub const DataPoint = struct {
        value: f32,
        label: ?[]const u8,
    };
};

/// Progress visualization style
pub const ProgressVisualizationStyle = struct {
    width: u32,
    height: u32,
    style: Style,
    
    pub const Style = enum {
        bar,
        circular,
        gradient,
    };
};

// Utility functions

fn detectImageFormat(path: []const u8, data: []const u8) Image.Format {
    // Check file extension first
    if (std.mem.endsWith(u8, path, ".png")) return .png;
    if (std.mem.endsWith(u8, path, ".jpg") or std.mem.endsWith(u8, path, ".jpeg")) return .jpeg;
    if (std.mem.endsWith(u8, path, ".gif")) return .gif;
    
    // Check magic bytes
    if (data.len >= 4) {
        // PNG: 89 50 4E 47
        if (std.mem.eql(u8, data[0..4], "\x89PNG")) return .png;
        // JPEG: FF D8 FF
        if (data[0] == 0xFF and data[1] == 0xD8 and data[2] == 0xFF) return .jpeg;
        // GIF: GIF8
        if (std.mem.eql(u8, data[0..4], "GIF8")) return .gif;
    }
    
    return .rgb24; // Default fallback
}

const ImageDimensions = struct { width: u32, height: u32 };

fn getImageDimensions(data: []const u8, format: Image.Format) !ImageDimensions {
    _ = data;
    _ = format;
    // Simplified - real implementation would decode image headers
    return ImageDimensions{ .width = 100, .height = 100 };
}

fn intensityToBlock(intensity: f32) []const u8 {
    // Unicode block characters for different intensities
    if (intensity < 0.125) return " ";
    if (intensity < 0.25) return "░";
    if (intensity < 0.375) return "▒";
    if (intensity < 0.5) return "▓";
    if (intensity < 0.625) return "█";
    if (intensity < 0.75) return "█";
    if (intensity < 0.875) return "█";
    return "█";
}
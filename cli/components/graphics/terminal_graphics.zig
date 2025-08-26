//! Terminal Graphics Integration for CLI Components
//!
//! This module provides comprehensive graphics support for CLI components using:
//! - Kitty Graphics Protocol for high-quality images and charts
//! - Sixel graphics for legacy support
//! - Unicode block rendering for maximum compatibility
//! - ASCII art as final fallback
//!
//! Features:
//! - Real-time chart generation and rendering
//! - Image display with multiple format support
//! - Progress visualization with graphics
//! - Data visualization components
//! - Automatic capability detection and fallback

const std = @import("std");
const unified = @import("../../../src/term/unified.zig");
const caps = @import("../../../src/term/caps.zig");
const terminal_abstraction = @import("../../core/terminal_abstraction.zig");

const Allocator = std.mem.Allocator;
const TerminalAbstraction = terminal_abstraction.TerminalAbstraction;

/// Graphics rendering capabilities
pub const GraphicsCapability = enum {
    kitty_protocol,  // Full Kitty graphics protocol
    sixel_graphics,  // Sixel graphics support  
    unicode_blocks,  // Rich Unicode block characters
    ascii_art,       // ASCII art fallback
    text_only,       // Plain text only
};

/// Image format support
pub const ImageFormat = enum {
    png,
    jpeg,
    gif,
    bmp,
    rgba_raw,
    rgb_raw,
};

/// Chart types supported
pub const ChartType = enum {
    line,
    bar,
    scatter,
    histogram,
    pie,
    sparkline,
    heatmap,
};

/// Color scheme options
pub const ColorScheme = enum {
    default,
    monochrome,
    rainbow,
    heat_map,
    cool_tones,
    warm_tones,
    custom,
};

/// Graphics configuration
pub const GraphicsConfig = struct {
    width: u32,
    height: u32,
    color_scheme: ColorScheme = .default,
    background_transparent: bool = true,
    enable_animation: bool = true,
    quality: enum { low, medium, high } = .medium,
    fallback_mode: GraphicsCapability = .unicode_blocks,
};

/// Data point for chart generation
pub const DataPoint = struct {
    x: f64,
    y: f64,
    label: ?[]const u8 = null,
    color: ?unified.Color = null,
};

/// Chart dataset
pub const Dataset = struct {
    name: []const u8,
    data: []const DataPoint,
    color: ?unified.Color = null,
    style: enum { solid, dashed, dotted } = .solid,
};

/// Terminal Graphics Manager
pub const TerminalGraphics = struct {
    allocator: Allocator,
    terminal: TerminalAbstraction,
    capability: GraphicsCapability,
    config: GraphicsConfig,
    
    // Graphics state
    next_image_id: u32,
    active_images: std.HashMap(u32, ImageInfo, std.hash_map.DefaultContext(u32), std.hash_map.default_max_load_percentage),
    
    // Render buffers
    render_buffer: std.ArrayList(u8),
    image_buffer: ?[]u8,
    
    pub fn init(allocator: Allocator, terminal: TerminalAbstraction, config: GraphicsConfig) !TerminalGraphics {
        const capability = detectGraphicsCapability(terminal.getFeatures());
        
        return TerminalGraphics{
            .allocator = allocator,
            .terminal = terminal,
            .capability = capability,
            .config = config,
            .next_image_id = 1,
            .active_images = std.HashMap(u32, ImageInfo, std.hash_map.DefaultContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .render_buffer = std.ArrayList(u8).init(allocator),
            .image_buffer = null,
        };
    }
    
    pub fn deinit(self: *TerminalGraphics) void {
        // Clean up active images
        var iterator = self.active_images.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.data) |data| {
                self.allocator.free(data);
            }
        }
        self.active_images.deinit();
        
        if (self.image_buffer) |buffer| {
            self.allocator.free(buffer);
        }
        
        self.render_buffer.deinit();
    }
    
    /// Render a chart with the given configuration
    pub fn renderChart(
        self: *TerminalGraphics,
        chart_type: ChartType,
        datasets: []const Dataset,
        title: ?[]const u8,
        x_label: ?[]const u8,
        y_label: ?[]const u8,
    ) !u32 {
        switch (self.capability) {
            .kitty_protocol => return try self.renderChartKitty(chart_type, datasets, title, x_label, y_label),
            .sixel_graphics => return try self.renderChartSixel(chart_type, datasets, title, x_label, y_label),
            .unicode_blocks => return try self.renderChartUnicode(chart_type, datasets, title, x_label, y_label),
            .ascii_art => return try self.renderChartAscii(chart_type, datasets, title, x_label, y_label),
            .text_only => return try self.renderChartText(chart_type, datasets, title, x_label, y_label),
        }
    }
    
    /// Display an image from file or data
    pub fn displayImage(
        self: *TerminalGraphics,
        data: []const u8,
        format: ImageFormat,
        width: ?u32,
        height: ?u32,
    ) !u32 {
        const image_id = self.next_image_id;
        self.next_image_id += 1;
        
        switch (self.capability) {
            .kitty_protocol => try self.displayImageKitty(image_id, data, format, width, height),
            .sixel_graphics => try self.displayImageSixel(image_id, data, format, width, height),
            .unicode_blocks => try self.displayImageUnicode(image_id, data, format, width, height),
            .ascii_art => try self.displayImageAscii(image_id, data, format, width, height),
            .text_only => try self.displayImageText(image_id, data, format, width, height),
        }
        
        // Store image info
        try self.active_images.put(image_id, ImageInfo{
            .data = try self.allocator.dupe(u8, data),
            .format = format,
            .width = width orelse self.config.width,
            .height = height orelse self.config.height,
        });
        
        return image_id;
    }
    
    /// Remove an image from display
    pub fn removeImage(self: *TerminalGraphics, image_id: u32) !void {
        if (self.active_images.get(image_id)) |info| {
            switch (self.capability) {
                .kitty_protocol => try self.removeImageKitty(image_id),
                .sixel_graphics => try self.removeImageSixel(image_id),
                else => {}, // Other modes don't need cleanup
            }
            
            if (info.data) |data| {
                self.allocator.free(data);
            }
            _ = self.active_images.remove(image_id);
        }
    }
    
    /// Render enhanced progress bar with graphics
    pub fn renderProgressWithChart(
        self: *TerminalGraphics,
        progress: f32,
        history: []const f32,
        label: []const u8,
    ) !void {
        switch (self.capability) {
            .kitty_protocol, .sixel_graphics => {
                // Generate mini chart showing progress history
                try self.renderProgressChart(progress, history, label);
            },
            .unicode_blocks => {
                // Rich Unicode progress with sparkline
                try self.renderProgressUnicode(progress, history, label);
            },
            .ascii_art => {
                // ASCII progress with basic chart
                try self.renderProgressAscii(progress, history, label);
            },
            .text_only => {
                // Simple text progress
                try self.renderProgressText(progress, label);
            },
        }
    }
    
    /// Generate data visualization dashboard
    pub fn renderDataDashboard(
        self: *TerminalGraphics,
        data: []const Dataset,
        layout: DashboardLayout,
    ) !void {
        switch (layout) {
            .single => {
                if (data.len > 0) {
                    _ = try self.renderChart(.line, data, "Data Overview", "Time", "Value");
                }
            },
            .grid => |grid_config| {
                const charts_per_row = grid_config.columns;
                const chart_width = self.config.width / charts_per_row;
                const chart_height = self.config.height / grid_config.rows;
                
                for (data, 0..) |dataset, i| {
                    const row = i / charts_per_row;
                    const col = i % charts_per_row;
                    
                    // Position chart in grid (would need cursor positioning)
                    const x = col * chart_width;
                    const y = row * chart_height;
                    
                    // Render dataset as individual chart
                    var single_dataset = [_]Dataset{dataset};
                    _ = try self.renderChart(.line, &single_dataset, dataset.name, null, null);
                    
                    // Move cursor to next position
                    try self.terminal.moveTo(@intCast(x), @intCast(y));
                }
            },
            .tabs => |tab_config| {
                // Render tab headers
                try self.renderTabHeaders(data, tab_config.active_tab);
                
                // Render active tab content
                if (tab_config.active_tab < data.len) {
                    var single_dataset = [_]Dataset{data[tab_config.active_tab]};
                    _ = try self.renderChart(.line, &single_dataset, data[tab_config.active_tab].name, null, null);
                }
            },
        }
    }
    
    // ========== PRIVATE IMPLEMENTATIONS ==========
    
    fn detectGraphicsCapability(features: terminal_abstraction.TerminalAbstraction.Features) GraphicsCapability {
        if (features.graphics) {
            // Check specific protocols (simplified)
            return .kitty_protocol; // Would detect Kitty vs Sixel
        } else if (features.truecolor) {
            return .unicode_blocks;
        } else {
            return .ascii_art;
        }
    }
    
    fn renderChartKitty(
        self: *TerminalGraphics,
        chart_type: ChartType,
        datasets: []const Dataset,
        title: ?[]const u8,
        x_label: ?[]const u8,
        y_label: ?[]const u8,
    ) !u32 {
        // Generate chart image
        const image_data = try self.generateChartImage(chart_type, datasets, title, x_label, y_label);
        defer self.allocator.free(image_data);
        
        const image_id = self.next_image_id;
        self.next_image_id += 1;
        
        // Encode as base64 for Kitty protocol
        const encoded_size = std.base64.Encoder.calcSize(image_data.len);
        const encoded_data = try self.allocator.alloc(u8, encoded_size);
        defer self.allocator.free(encoded_data);
        
        _ = std.base64.standard.Encoder.encode(encoded_data, image_data);
        
        // Send Kitty graphics command
        self.render_buffer.clearRetainingCapacity();
        const writer = self.render_buffer.writer();
        
        try writer.print(
            "\x1b_Gf=32,s={d},v={d},i={d},t=d,m=1;{s}\x1b\\",
            .{ self.config.width, self.config.height, image_id, encoded_data }
        );
        
        // Display the image
        try writer.print("\x1b_Gi={d}\x1b\\", .{image_id});
        
        try self.terminal.print(self.render_buffer.items, null);
        return image_id;
    }
    
    fn renderChartSixel(
        self: *TerminalGraphics,
        chart_type: ChartType,
        datasets: []const Dataset,
        title: ?[]const u8,
        x_label: ?[]const u8,
        y_label: ?[]const u8,
    ) !u32 {
        _ = chart_type;
        _ = datasets;
        _ = title;
        _ = x_label;
        _ = y_label;
        
        // Simplified Sixel implementation
        self.render_buffer.clearRetainingCapacity();
        const writer = self.render_buffer.writer();
        
        // Start Sixel sequence
        try writer.writeAll("\x1bP0;0;0q");
        
        // Simple pattern (would generate actual Sixel data)
        try writer.writeAll("#0;2;0;0;0#1;2;100;100;0");
        try writer.writeAll("#0~~@@vv@@~~@@~~$");
        try writer.writeAll("#1!!}}GG}}!!}}~~$");
        
        // End Sixel sequence
        try writer.writeAll("\x1b\\");
        
        try self.terminal.print(self.render_buffer.items, null);
        return self.next_image_id - 1;
    }
    
    fn renderChartUnicode(
        self: *TerminalGraphics,
        chart_type: ChartType,
        datasets: []const Dataset,
        title: ?[]const u8,
        x_label: ?[]const u8,
        y_label: ?[]const u8,
    ) !u32 {
        self.render_buffer.clearRetainingCapacity();
        const writer = self.render_buffer.writer();
        
        // Render title
        if (title) |t| {
            // Would apply CliStyles.HEADER styling in full implementation
            try writer.print("{s}\n", .{t});
        }
        
        switch (chart_type) {
            .line => try self.renderLineChartUnicode(writer, datasets),
            .bar => try self.renderBarChartUnicode(writer, datasets),
            .sparkline => try self.renderSparklineUnicode(writer, datasets),
            else => try self.renderLineChartUnicode(writer, datasets), // Default to line
        }
        
        // Render labels
        if (x_label) |xl| {
            try writer.print("\n{s}", .{xl});
        }
        if (y_label) |yl| {
            try writer.print(" | {s}", .{yl});
        }
        
        try self.terminal.print(self.render_buffer.items, null);
        return self.next_image_id - 1;
    }
    
    fn renderLineChartUnicode(self: *TerminalGraphics, writer: anytype, datasets: []const Dataset) !void {
        if (datasets.len == 0) return;
        
        const chart_width = @min(self.config.width, 60);
        _ = @min(self.config.height, 20); // chart_height not used in simplified implementation
        
        // Find data bounds
        var min_y: f64 = std.math.inf(f64);
        var max_y: f64 = -std.math.inf(f64);
        
        for (datasets) |dataset| {
            for (dataset.data) |point| {
                min_y = @min(min_y, point.y);
                max_y = @max(max_y, point.y);
            }
        }
        
        const y_range = max_y - min_y;
        if (y_range == 0) return;
        
        // Render chart area
        const blocks = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
        
        // For each dataset, render line
        for (datasets, 0..) |dataset, dataset_idx| {
            if (dataset.data.len == 0) continue;
            
            // Sample data points to fit chart width
            for (0..chart_width) |x| {
                const data_idx = (x * dataset.data.len) / chart_width;
                if (data_idx >= dataset.data.len) continue;
                
                const point = dataset.data[data_idx];
                const normalized_y = (point.y - min_y) / y_range;
                const block_idx = @as(usize, @intFromFloat(normalized_y * 7.0));
                
                // Apply color if supported
                if (dataset.color) |color| {
                    // Would apply color styling here
                    _ = color;
                }
                
                try writer.writeAll(blocks[@min(block_idx, blocks.len - 1)]);
            }
            
            if (dataset_idx < datasets.len - 1) {
                try writer.writeAll("\n");
            }
        }
    }
    
    fn renderBarChartUnicode(self: *TerminalGraphics, writer: anytype, datasets: []const Dataset) !void {
        if (datasets.len == 0) return;
        
        const chart_height = @min(self.config.height, 15);
        
        // Find max value for scaling
        var max_val: f64 = 0;
        for (datasets) |dataset| {
            for (dataset.data) |point| {
                max_val = @max(max_val, point.y);
            }
        }
        
        if (max_val == 0) return;
        
        // Render each dataset as bars
        for (datasets) |dataset| {
            for (dataset.data) |point| {
                const bar_height = @as(u32, @intFromFloat((point.y / max_val) * @as(f64, @floatFromInt(chart_height))));
                
                // Render vertical bar
                for (0..bar_height) |_| {
                    try writer.writeAll("█");
                }
                
                // Label if available
                if (point.label) |label| {
                    try writer.print(" {s}", .{label});
                }
                
                try writer.writeAll("\n");
            }
        }
    }
    
    fn renderSparklineUnicode(self: *TerminalGraphics, writer: anytype, datasets: []const Dataset) !void {
        _ = self;
        if (datasets.len == 0) return;
        
        const sparkline_chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
        
        for (datasets) |dataset| {
            if (dataset.data.len == 0) continue;
            
            // Find min/max for this dataset
            var min_val = dataset.data[0].y;
            var max_val = dataset.data[0].y;
            
            for (dataset.data[1..]) |point| {
                min_val = @min(min_val, point.y);
                max_val = @max(max_val, point.y);
            }
            
            const range = max_val - min_val;
            if (range == 0) continue;
            
            // Render sparkline
            for (dataset.data) |point| {
                const normalized = (point.y - min_val) / range;
                const char_idx = @as(usize, @intFromFloat(normalized * 7.0));
                try writer.writeAll(sparkline_chars[@min(char_idx, sparkline_chars.len - 1)]);
            }
            
            try writer.writeAll(" ");
        }
    }
    
    fn renderChartAscii(
        self: *TerminalGraphics,
        chart_type: ChartType,
        datasets: []const Dataset,
        title: ?[]const u8,
        x_label: ?[]const u8,
        y_label: ?[]const u8,
    ) !u32 {
        _ = chart_type;
        _ = x_label;
        _ = y_label;
        
        self.render_buffer.clearRetainingCapacity();
        const writer = self.render_buffer.writer();
        
        if (title) |t| {
            try writer.print("{s}\n", .{t});
        }
        
        // Simple ASCII chart representation
        for (datasets) |dataset| {
            for (dataset.data) |point| {
                const bar_length = @as(u32, @intFromFloat(point.y * 20.0)); // Scale to 20 chars
                for (0..bar_length) |_| {
                    try writer.writeAll("#");
                }
                if (point.label) |label| {
                    try writer.print(" {s}", .{label});
                }
                try writer.writeAll("\n");
            }
        }
        
        try self.terminal.print(self.render_buffer.items, null);
        return self.next_image_id - 1;
    }
    
    fn renderChartText(
        self: *TerminalGraphics,
        chart_type: ChartType,
        datasets: []const Dataset,
        title: ?[]const u8,
        x_label: ?[]const u8,
        y_label: ?[]const u8,
    ) !u32 {
        _ = chart_type;
        _ = x_label;
        _ = y_label;
        
        self.render_buffer.clearRetainingCapacity();
        const writer = self.render_buffer.writer();
        
        if (title) |t| {
            try writer.print("Chart: {s}\n", .{t});
        }
        
        // Text representation of data
        for (datasets) |dataset| {
            try writer.print("Dataset: {s}\n", .{dataset.name});
            for (dataset.data) |point| {
                try writer.print("  {d:.2}", .{point.y});
                if (point.label) |label| {
                    try writer.print(" ({s})", .{label});
                }
                try writer.writeAll("\n");
            }
        }
        
        try self.terminal.print(self.render_buffer.items, null);
        return self.next_image_id - 1;
    }
    
    fn generateChartImage(
        self: *TerminalGraphics,
        chart_type: ChartType,
        datasets: []const Dataset,
        title: ?[]const u8,
        x_label: ?[]const u8,
        y_label: ?[]const u8,
    ) ![]u8 {
        _ = chart_type;
        _ = title;
        _ = x_label;
        _ = y_label;
        
        const width = self.config.width;
        const height = self.config.height;
        const bytes_per_pixel = 4; // RGBA
        const image_size = width * height * bytes_per_pixel;
        
        const image_data = try self.allocator.alloc(u8, image_size);
        
        // Fill with background color
        @memset(image_data, 255); // White background
        
        // Simple chart rendering (would be much more sophisticated in real implementation)
        for (datasets) |dataset| {
            if (dataset.data.len < 2) continue;
            
            // Find bounds
            var min_y: f64 = dataset.data[0].y;
            var max_y: f64 = dataset.data[0].y;
            
            for (dataset.data[1..]) |point| {
                min_y = @min(min_y, point.y);
                max_y = @max(max_y, point.y);
            }
            
            const y_range = max_y - min_y;
            if (y_range == 0) continue;
            
            // Draw line chart
            for (0..dataset.data.len - 1) |i| {
                const x1 = (i * width) / dataset.data.len;
                const y1 = height - @as(u32, @intFromFloat(((dataset.data[i].y - min_y) / y_range) * @as(f64, @floatFromInt(height))));
                const x2 = ((i + 1) * width) / dataset.data.len;
                const y2 = height - @as(u32, @intFromFloat(((dataset.data[i + 1].y - min_y) / y_range) * @as(f64, @floatFromInt(height))));
                
                // Draw line (simplified)
                self.drawLineOnImage(image_data, width, height, x1, y1, x2, y2);
            }
        }
        
        return image_data;
    }
    
    fn drawLineOnImage(self: *TerminalGraphics, image_data: []u8, width: u32, height: u32, x1: u32, y1: u32, x2: u32, y2: u32) void {
        _ = self;
        
        // Simplified line drawing
        const dx = @as(i32, @intCast(x2)) - @as(i32, @intCast(x1));
        const dy = @as(i32, @intCast(y2)) - @as(i32, @intCast(y1));
        const steps = @max(@abs(dx), @abs(dy));
        
        if (steps == 0) return;
        
        for (0..@as(u32, @intCast(steps))) |step| {
            const x = x1 + @as(u32, @intCast((@as(i32, @intCast(step)) * dx) / steps));
            const y = y1 + @as(u32, @intCast((@as(i32, @intCast(step)) * dy) / steps));
            
            if (x < width and y < height) {
                const pixel_offset = (y * width + x) * 4;
                if (pixel_offset + 3 < image_data.len) {
                    image_data[pixel_offset] = 0;     // R
                    image_data[pixel_offset + 1] = 100; // G
                    image_data[pixel_offset + 2] = 200; // B
                    image_data[pixel_offset + 3] = 255; // A
                }
            }
        }
    }
    
    // Placeholder implementations for image display
    fn displayImageKitty(self: *TerminalGraphics, image_id: u32, data: []const u8, format: ImageFormat, width: ?u32, height: ?u32) !void {
        _ = self;
        _ = image_id;
        _ = data;
        _ = format;
        _ = width;
        _ = height;
        // Implementation would handle Kitty image protocol
    }
    
    fn displayImageSixel(self: *TerminalGraphics, image_id: u32, data: []const u8, format: ImageFormat, width: ?u32, height: ?u32) !void {
        _ = self;
        _ = image_id;
        _ = data;
        _ = format;
        _ = width;
        _ = height;
        // Implementation would handle Sixel conversion
    }
    
    fn displayImageUnicode(self: *TerminalGraphics, image_id: u32, data: []const u8, format: ImageFormat, width: ?u32, height: ?u32) !void {
        _ = self;
        _ = image_id;
        _ = data;
        _ = format;
        _ = width;
        _ = height;
        // Implementation would convert to Unicode blocks
    }
    
    fn displayImageAscii(self: *TerminalGraphics, image_id: u32, data: []const u8, format: ImageFormat, width: ?u32, height: ?u32) !void {
        _ = self;
        _ = image_id;
        _ = data;
        _ = format;
        _ = width;
        _ = height;
        // Implementation would convert to ASCII art
    }
    
    fn displayImageText(self: *TerminalGraphics, image_id: u32, data: []const u8, format: ImageFormat, width: ?u32, height: ?u32) !void {
        _ = data;
        _ = format;
        _ = width;
        _ = height;
        
        try self.terminal.printf("[IMAGE #{d}]\n", .{image_id}, null);
    }
    
    fn removeImageKitty(self: *TerminalGraphics, image_id: u32) !void {
        self.render_buffer.clearRetainingCapacity();
        try self.render_buffer.writer().print("\x1b_Gd=i,i={d}\x1b\\", .{image_id});
        try self.terminal.print(self.render_buffer.items, null);
    }
    
    fn removeImageSixel(self: *TerminalGraphics, image_id: u32) !void {
        _ = self;
        _ = image_id;
        // Sixel doesn't have direct removal, would need screen management
    }
    
    fn renderProgressChart(self: *TerminalGraphics, progress: f32, history: []const f32, label: []const u8) !void {
        _ = progress; // Not used in this simplified implementation
        // Create dataset from history
        var data_points = try self.allocator.alloc(DataPoint, history.len);
        defer self.allocator.free(data_points);
        
        for (history, 0..) |value, i| {
            data_points[i] = DataPoint{
                .x = @floatFromInt(i),
                .y = value,
            };
        }
        
        const dataset = Dataset{
            .name = "Progress",
            .data = data_points,
            .color = terminal_abstraction.CliColors.SUCCESS,
        };
        
        const datasets = [_]Dataset{dataset};
        _ = try self.renderChart(.sparkline, &datasets, label, null, null);
    }
    
    fn renderProgressUnicode(self: *TerminalGraphics, progress: f32, history: []const f32, label: []const u8) !void {
        self.render_buffer.clearRetainingCapacity();
        const writer = self.render_buffer.writer();
        
        try writer.print("{s}: ", .{label});
        
        // Unicode progress bar
        const bar_width = 30;
        const filled = @as(u32, @intFromFloat(progress * @as(f32, @floatFromInt(bar_width))));
        
        try writer.writeAll("▕");
        for (0..filled) |_| try writer.writeAll("█");
        for (filled..bar_width) |_| try writer.writeAll("░");
        try writer.writeAll("▏");
        
        try writer.print(" {d:.1}%", .{progress * 100});
        
        // Add sparkline if history available
        if (history.len > 0) {
            try writer.writeAll(" ");
            try self.renderProgressSparkline(writer, history);
        }
        
        try self.terminal.print(self.render_buffer.items, null);
    }
    
    fn renderProgressAscii(self: *TerminalGraphics, progress: f32, history: []const f32, label: []const u8) !void {
        self.render_buffer.clearRetainingCapacity();
        const writer = self.render_buffer.writer();
        
        try writer.print("{s}: [", .{label});
        
        const bar_width = 20;
        const filled = @as(u32, @intFromFloat(progress * @as(f32, @floatFromInt(bar_width))));
        
        for (0..filled) |_| try writer.writeAll("=");
        for (filled..bar_width) |_| try writer.writeAll("-");
        
        try writer.print("] {d:.1}%", .{progress * 100});
        
        if (history.len > 0) {
            try writer.print(" (avg: {d:.1}%)", .{self.calculateAverage(history) * 100});
        }
        
        try self.terminal.print(self.render_buffer.items, null);
    }
    
    fn renderProgressText(self: *TerminalGraphics, progress: f32, label: []const u8) !void {
        try self.terminal.printf("{s}: {d:.1}%\n", .{ label, progress * 100 }, null);
    }
    
    fn renderProgressSparkline(self: *TerminalGraphics, writer: anytype, history: []const f32) !void {
        _ = self;
        
        const sparkline_chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
        const max_points = @min(20, history.len);
        const start_idx = if (history.len > 20) history.len - 20 else 0;
        
        try writer.writeAll("[");
        for (history[start_idx..start_idx + max_points]) |value| {
            const char_idx = @as(usize, @intFromFloat(value * 7.0));
            try writer.writeAll(sparkline_chars[@min(char_idx, sparkline_chars.len - 1)]);
        }
        try writer.writeAll("]");
    }
    
    fn renderTabHeaders(self: *TerminalGraphics, datasets: []const Dataset, active_tab: usize) !void {
        self.render_buffer.clearRetainingCapacity();
        const writer = self.render_buffer.writer();
        
        for (datasets, 0..) |dataset, i| {
            if (i == active_tab) {
                try writer.print("[{s}] ", .{dataset.name});
            } else {
                try writer.print(" {s}  ", .{dataset.name});
            }
        }
        try writer.writeAll("\n");
        
        try self.terminal.print(self.render_buffer.items, null);
    }
    
    fn calculateAverage(self: *TerminalGraphics, values: []const f32) f32 {
        _ = self;
        
        if (values.len == 0) return 0.0;
        
        var sum: f32 = 0.0;
        for (values) |value| {
            sum += value;
        }
        return sum / @as(f32, @floatFromInt(values.len));
    }
};

/// Image information for tracking
const ImageInfo = struct {
    data: ?[]u8,
    format: ImageFormat,
    width: u32,
    height: u32,
};

/// Dashboard layout options
pub const DashboardLayout = union(enum) {
    single: void,
    grid: struct {
        rows: u32,
        columns: u32,
    },
    tabs: struct {
        active_tab: usize,
    },
};
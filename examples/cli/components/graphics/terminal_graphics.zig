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
const unified = @import("../../../src/shared/term/unified.zig");
const capabilities = @import("../../../src/shared/term/caps.zig");
const terminal_abstraction = @import("../../core/terminal_abstraction.zig");

const Allocator = std.mem.Allocator;
const TerminalAbstraction = terminal_abstraction.TerminalAbstraction;

/// Graphics rendering capabilities
pub const GraphicsCapability = enum {
    kitty_protocol, // Full Kitty graphics protocol
    sixel_graphics, // Sixel graphics support
    unicode_blocks, // Rich Unicode block characters
    ascii_art, // ASCII art fallback
    text_only, // Plain text only
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
pub const Point = struct {
    x: f64,
    y: f64,
    label: ?[]const u8 = null,
    color: ?unified.Color = null,
};

/// Chart dataset
pub const Set = struct {
    name: []const u8,
    data: []const Point,
    color: ?unified.Color = null,
    style: enum { solid, dashed, dotted } = .solid,
};

/// Terminal Graphics
pub const TerminalGraphics = struct {
    allocator: Allocator,
    terminal: TerminalAbstraction,
    capability: GraphicsCapability,
    config: GraphicsConfig,

    // Graphics state
    nextImageId: u32,
    activeImages: std.HashMap(u32, Image, std.hash_map.DefaultContext(u32), std.hash_map.default_max_load_percentage),

    // Render buffers
    renderBuffer: std.ArrayList(u8),
    imageBuffer: ?[]u8,

    pub fn init(allocator: Allocator, terminal: TerminalAbstraction, config: GraphicsConfig) !TerminalGraphics {
        const capability = detectGraphicsCapability(terminal.getFeatures());

        return TerminalGraphics{
            .allocator = allocator,
            .terminal = terminal,
            .capability = capability,
            .config = config,
            .nextImageId = 1,
            .activeImages = std.HashMap(u32, Image, std.hash_map.DefaultContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .renderBuffer = std.ArrayList(u8).init(allocator),
            .imageBuffer = null,
        };
    }

    pub fn deinit(self: *TerminalGraphics) void {
        // Clean up active images
        var iterator = self.activeImages.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.data) |data| {
                self.allocator.free(data);
            }
        }
        self.activeImages.deinit();

        if (self.imageBuffer) |buffer| {
            self.allocator.free(buffer);
        }

        self.renderBuffer.deinit();
    }

    /// Render a chart with the given configuration
    pub fn renderChart(
        self: *TerminalGraphics,
        chart_type: ChartType,
        datasets: []const Set,
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
        const imageId = self.nextImageId;
        self.nextImageId += 1;

        switch (self.capability) {
            .kitty_protocol => try self.displayImageKitty(imageId, data, format, width, height),
            .sixel_graphics => try self.displayImageSixel(imageId, data, format, width, height),
            .unicode_blocks => try self.displayImageUnicode(imageId, data, format, width, height),
            .ascii_art => try self.displayImageAscii(imageId, data, format, width, height),
            .text_only => try self.displayImageText(imageId, data, format, width, height),
        }

        // Store image info
        try self.activeImages.put(imageId, Image{
            .data = try self.allocator.dupe(u8, data),
            .format = format,
            .width = width orelse self.config.width,
            .height = height orelse self.config.height,
        });

        return imageId;
    }

    /// Remove an image from display
    pub fn removeImage(self: *TerminalGraphics, imageId: u32) !void {
        if (self.activeImages.get(imageId)) |info| {
            switch (self.capability) {
                .kitty_protocol => try self.removeImageKitty(imageId),
                .sixel_graphics => try self.removeImageSixel(imageId),
                else => {}, // Other modes don't need cleanup
            }

            if (info.data) |data| {
                self.allocator.free(data);
            }
            _ = self.activeImages.remove(imageId);
        }
    }

    /// Render progress bar with graphics
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
        data: []const Set,
        layout: DashboardLayout,
    ) !void {
        switch (layout) {
            .single => {
                if (data.len > 0) {
                    _ = try self.renderChart(.line, data, "Data Overview", "Time", "Value");
                }
            },
            .grid => |gridConfig| {
                const chartsPerRow = gridConfig.columns;
                const chartWidth = self.config.width / chartsPerRow;
                const chartHeight = self.config.height / gridConfig.rows;

                for (data, 0..) |dataset, i| {
                    const row = i / chartsPerRow;
                    const col = i % chartsPerRow;

                    // Position chart in grid (would need cursor positioning)
                    const x = col * chartWidth;
                    const y = row * chartHeight;

                    // Render dataset as individual chart
                    var singleSet = [_]Set{dataset};
                    _ = try self.renderChart(.line, &singleSet, dataset.name, null, null);

                    // Move cursor to next position
                    try self.terminal.moveTo(@intCast(x), @intCast(y));
                }
            },
            .tabs => |tabConfig| {
                // Render tab headers
                try self.renderTabHeaders(data, tabConfig.active_tab);

                // Render active tab content
                if (tabConfig.active_tab < data.len) {
                    var singleSet = [_]Set{data[tabConfig.active_tab]};
                    _ = try self.renderChart(.line, &singleSet, data[tabConfig.active_tab].name, null, null);
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
        chartType: ChartType,
        datasets: []const Set,
        title: ?[]const u8,
        xLabel: ?[]const u8,
        yLabel: ?[]const u8,
    ) !u32 {
        // Generate chart image
        const imageData = try self.generateChartImage(chartType, datasets, title, xLabel, yLabel);
        defer self.allocator.free(imageData);

        const imageId = self.nextImageId;
        self.nextImageId += 1;

        // Encode as base64 for Kitty protocol
        const encodedSize = std.base64.Encoder.calcSize(imageData.len);
        const encodedData = try self.allocator.alloc(u8, encodedSize);
        defer self.allocator.free(encodedData);

        _ = std.base64.standard.Encoder.encode(encodedData, imageData);

        // Send Kitty graphics command
        self.renderBuffer.clearRetainingCapacity();
        const writer = self.renderBuffer.writer();

        try writer.print("\x1b_Gf=32,s={d},v={d},i={d},t=d,m=1;{s}\x1b\\", .{ self.config.width, self.config.height, imageId, encodedData });

        // Display the image
        try writer.print("\x1b_Gi={d}\x1b\\", .{imageId});

        try self.terminal.print(self.renderBuffer.items, null);
        return imageId;
    }

    fn renderChartSixel(
        self: *TerminalGraphics,
        chartType: ChartType,
        datasets: []const Set,
        title: ?[]const u8,
        xLabel: ?[]const u8,
        yLabel: ?[]const u8,
    ) !u32 {
        _ = chartType;
        _ = datasets;
        _ = title;
        _ = xLabel;
        _ = yLabel;

        // Simplified Sixel implementation
        self.renderBuffer.clearRetainingCapacity();
        const writer = self.renderBuffer.writer();

        // Start Sixel sequence
        try writer.writeAll("\x1bP0;0;0q");

        // Simple pattern (would generate actual Sixel data)
        try writer.writeAll("#0;2;0;0;0#1;2;100;100;0");
        try writer.writeAll("#0~~@@vv@@~~@@~~$");
        try writer.writeAll("#1!!}}GG}}!!}}~~$");

         // End Sixel sequence
         try writer.writeAll("\x1b\\");

         try self.terminal.print(self.renderBuffer.items, null);
         return self.nextImageId - 1;
    }

    fn renderChartUnicode(
        self: *TerminalGraphics,
        chartType: ChartType,
        datasets: []const Set,
        title: ?[]const u8,
        xLabel: ?[]const u8,
        yLabel: ?[]const u8,
    ) !u32 {
        self.renderBuffer.clearRetainingCapacity();
        const writer = self.renderBuffer.writer();

        // Render title
        if (title) |t| {
            // Would apply CliStyles.HEADER styling in full implementation
            try writer.print("{s}\n", .{t});
        }

        switch (chartType) {
            .line => try self.renderLineChartUnicode(writer, datasets),
            .bar => try self.renderBarChartUnicode(writer, datasets),
            .sparkline => try self.renderSparklineUnicode(writer, datasets),
            else => try self.renderLineChartUnicode(writer, datasets), // Default to line
        }

        // Render labels
        if (xLabel) |xl| {
            try writer.print("\n{s}", .{xl});
        }
        if (yLabel) |yl| {
            try writer.print(" | {s}", .{yl});
        }

        try self.terminal.print(self.renderBuffer.items, null);
        return self.nextImageId - 1;
    }

    fn renderLineChartUnicode(self: *TerminalGraphics, writer: anytype, datasets: []const Set) !void {
        if (datasets.len == 0) return;

        const chartWidth = @min(self.config.width, 60);
        _ = @min(self.config.height, 20); // chartHeight not used in simplified implementation

        // Find data bounds
        var minY: f64 = std.math.inf(f64);
        var maxY: f64 = -std.math.inf(f64);

        for (datasets) |dataset| {
            for (dataset.data) |point| {
                minY = @min(minY, point.y);
                maxY = @max(maxY, point.y);
            }
        }

        const yRange = maxY - minY;
        if (yRange == 0) return;

        // Render chart area
        const blocks = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };

        // For each dataset, render line
        for (datasets, 0..) |dataset, datasetIdx| {
            if (dataset.data.len == 0) continue;

            // Sample data points to fit chart width
            for (0..chartWidth) |x| {
                const dataIdx = (x * dataset.data.len) / chartWidth;
                if (dataIdx >= dataset.data.len) continue;

                const point = dataset.data[dataIdx];
                const normalizedY = (point.y - minY) / yRange;
                const blockIdx = @as(usize, @intFromFloat(normalizedY * 7.0));

                // Apply color if supported
                if (dataset.color) |color| {
                    // Would apply color styling here
                    _ = color;
                }

                try writer.writeAll(blocks[@min(blockIdx, blocks.len - 1)]);
            }

            if (datasetIdx < datasets.len - 1) {
                try writer.writeAll("\n");
            }
        }
    }

    fn renderBarChartUnicode(self: *TerminalGraphics, writer: anytype, datasets: []const Set) !void {
        if (datasets.len == 0) return;

        const chartHeight = @min(self.config.height, 15);

        // Find max value for scaling
        var maxVal: f64 = 0;
        for (datasets) |dataset| {
            for (dataset.data) |point| {
                maxVal = @max(maxVal, point.y);
            }
        }

        if (maxVal == 0) return;

        // Render each dataset as bars
        for (datasets) |dataset| {
            for (dataset.data) |point| {
                const barHeight = @as(u32, @intFromFloat((point.y / maxVal) * @as(f64, @floatFromInt(chartHeight))));

                // Render vertical bar
                for (0..barHeight) |_| {
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

    fn renderSparklineUnicode(self: *TerminalGraphics, writer: anytype, datasets: []const Set) !void {
        _ = self;
        if (datasets.len == 0) return;

        const sparklineChars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };

        for (datasets) |dataset| {
            if (dataset.data.len == 0) continue;

            // Find min/max for this dataset
            var minVal = dataset.data[0].y;
            var maxVal = dataset.data[0].y;

            for (dataset.data[1..]) |point| {
                minVal = @min(minVal, point.y);
                maxVal = @max(maxVal, point.y);
            }

            const range = maxVal - minVal;
            if (range == 0) continue;

            // Render sparkline
            for (dataset.data) |point| {
                const normalized = (point.y - minVal) / range;
                const charIdx = @as(usize, @intFromFloat(normalized * 7.0));
                try writer.writeAll(sparklineChars[@min(charIdx, sparklineChars.len - 1)]);
            }

            try writer.writeAll(" ");
        }
    }

    fn renderChartAscii(
        self: *TerminalGraphics,
        chartType: ChartType,
        datasets: []const Set,
        title: ?[]const u8,
        xLabel: ?[]const u8,
        yLabel: ?[]const u8,
    ) !u32 {
        _ = chartType;
        _ = xLabel;
        _ = yLabel;

        self.renderBuffer.clearRetainingCapacity();
        const writer = self.renderBuffer.writer();

        if (title) |t| {
            try writer.print("{s}\n", .{t});
        }

        // Simple ASCII chart representation
        for (datasets) |dataset| {
            for (dataset.data) |point| {
                const barLength = @as(u32, @intFromFloat(point.y * 20.0)); // Scale to 20 chars
                for (0..barLength) |_| {
                    try writer.writeAll("#");
                }
                if (point.label) |label| {
                    try writer.print(" {s}", .{label});
                }
                try writer.writeAll("\n");
            }
        }

        try self.terminal.print(self.renderBuffer.items, null);
        return self.nextImageId - 1;
    }

    fn renderChartText(
        self: *TerminalGraphics,
        chartType: ChartType,
        datasets: []const Set,
        title: ?[]const u8,
        xLabel: ?[]const u8,
        yLabel: ?[]const u8,
    ) !u32 {
        _ = chartType;
        _ = xLabel;
        _ = yLabel;

        self.renderBuffer.clearRetainingCapacity();
        const writer = self.renderBuffer.writer();

        if (title) |t| {
            try writer.print("Chart: {s}\n", .{t});
        }

        // Text representation of data
        for (datasets) |dataset| {
            try writer.print("Set: {s}\n", .{dataset.name});
            for (dataset.data) |point| {
                try writer.print("  {d:.2}", .{point.y});
                if (point.label) |label| {
                    try writer.print(" ({s})", .{label});
                }
                try writer.writeAll("\n");
            }
        }

        try self.terminal.print(self.renderBuffer.items, null);
        return self.nextImageId - 1;
    }

    fn generateChartImage(
        self: *TerminalGraphics,
        chartType: ChartType,
        datasets: []const Set,
        title: ?[]const u8,
        xLabel: ?[]const u8,
        yLabel: ?[]const u8,
    ) ![]u8 {
        _ = chartType;
        _ = title;
        _ = xLabel;
        _ = yLabel;

        const width = self.config.width;
        const height = self.config.height;
        const bytesPerPixel = 4; // RGBA
        const imageSize = width * height * bytesPerPixel;

        const imageData = try self.allocator.alloc(u8, imageSize);

        // Fill with background color
        @memset(imageData, 255); // White background

        // Simple chart rendering (would be much more sophisticated in real implementation)
        for (datasets) |dataset| {
            if (dataset.data.len < 2) continue;

            // Find bounds
            var minY: f64 = dataset.data[0].y;
            var maxY: f64 = dataset.data[0].y;

            for (dataset.data[1..]) |point| {
                minY = @min(minY, point.y);
                maxY = @max(maxY, point.y);
            }

            const yRange = maxY - minY;
            if (yRange == 0) continue;

            // Draw line chart
            for (0..dataset.data.len - 1) |i| {
                const x1 = (i * width) / dataset.data.len;
                const y1 = height - @as(u32, @intFromFloat(((dataset.data[i].y - minY) / yRange) * @as(f64, @floatFromInt(height))));
                const x2 = ((i + 1) * width) / dataset.data.len;
                const y2 = height - @as(u32, @intFromFloat(((dataset.data[i + 1].y - minY) / yRange) * @as(f64, @floatFromInt(height))));

                // Draw line (simplified)
                self.drawLineOnImage(imageData, width, height, x1, y1, x2, y2);
            }
        }

        return imageData;
    }

    fn drawLineOnImage(self: *TerminalGraphics, imageData: []u8, width: u32, height: u32, x1: u32, y1: u32, x2: u32, y2: u32) void {
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
                const pixelOffset = (y * width + x) * 4;
                if (pixelOffset + 3 < imageData.len) {
                    imageData[pixelOffset] = 0; // R
                    imageData[pixelOffset + 1] = 100; // G
                    imageData[pixelOffset + 2] = 200; // B
                    imageData[pixelOffset + 3] = 255; // A
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

    fn removeImageKitty(self: *TerminalGraphics, imageId: u32) !void {
        self.renderBuffer.clearRetainingCapacity();
        try self.renderBuffer.writer().print("\x1b_Gd=i,i={d}\x1b\\", .{imageId});
        try self.terminal.print(self.renderBuffer.items, null);
    }

    fn removeImageSixel(self: *TerminalGraphics, imageId: u32) !void {
        _ = self;
        _ = imageId;
        // Sixel doesn't have direct removal, would need screen management
    }

    fn renderProgressChart(self: *TerminalGraphics, progress: f32, history: []const f32, label: []const u8) !void {
        _ = progress; // Not used in this simplified implementation
        // Create dataset from history
        var dataPoints = try self.allocator.alloc(Point, history.len);
        defer self.allocator.free(dataPoints);

        for (history, 0..) |value, i| {
            dataPoints[i] = Point{
                .x = @floatFromInt(i),
                .y = value,
            };
        }

        const dataset = Set{
            .name = "Progress",
            .data = dataPoints,
            .color = terminal_abstraction.CliColors.SUCCESS,
        };

        const datasets = [_]Set{dataset};
        _ = try self.renderChart(.sparkline, &datasets, label, null, null);
    }

    fn renderProgressUnicode(self: *TerminalGraphics, progress: f32, history: []const f32, label: []const u8) !void {
        self.renderBuffer.clearRetainingCapacity();
        const writer = self.renderBuffer.writer();

        try writer.print("{s}: ", .{label});

        // Unicode progress bar
        const barWidth = 30;
        const filled = @as(u32, @intFromFloat(progress * @as(f32, @floatFromInt(barWidth))));

        try writer.writeAll("▕");
        for (0..filled) |_| try writer.writeAll("█");
        for (filled..barWidth) |_| try writer.writeAll("░");
        try writer.writeAll("▏");

        try writer.print(" {d:.1}%", .{progress * 100});

        // Add sparkline if history available
        if (history.len > 0) {
            try writer.writeAll(" ");
            try self.renderProgressSparkline(writer, history);
        }

        try self.terminal.print(self.renderBuffer.items, null);
    }

    fn renderProgressAscii(self: *TerminalGraphics, progress: f32, history: []const f32, label: []const u8) !void {
        self.renderBuffer.clearRetainingCapacity();
        const writer = self.renderBuffer.writer();

        try writer.print("{s}: [", .{label});

        const barWidth = 20;
        const filled = @as(u32, @intFromFloat(progress * @as(f32, @floatFromInt(barWidth))));

        for (0..filled) |_| try writer.writeAll("=");
        for (filled..barWidth) |_| try writer.writeAll("-");

        try writer.print("] {d:.1}%", .{progress * 100});

        if (history.len > 0) {
            try writer.print(" (avg: {d:.1}%)", .{self.calculateAverage(history) * 100});
        }

        try self.terminal.print(self.renderBuffer.items, null);
    }

    fn renderProgressText(self: *TerminalGraphics, progress: f32, label: []const u8) !void {
        try self.terminal.printf("{s}: {d:.1}%\n", .{ label, progress * 100 }, null);
    }

    fn renderProgressSparkline(self: *TerminalGraphics, writer: anytype, history: []const f32) !void {
        _ = self;

        const sparklineChars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
        const maxPoints = @min(20, history.len);
        const startIdx = if (history.len > 20) history.len - 20 else 0;

        try writer.writeAll("[");
        for (history[startIdx .. startIdx + maxPoints]) |value| {
            const charIdx: usize = @intFromFloat(value * 7.0);
            try writer.writeAll(sparklineChars[@min(charIdx, sparklineChars.len - 1)]);
        }
        try writer.writeAll("]");
    }

    fn renderTabHeaders(self: *TerminalGraphics, datasets: []const Set, activeTab: usize) !void {
        self.renderBuffer.clearRetainingCapacity();
        const writer = self.renderBuffer.writer();

        for (datasets, 0..) |dataset, i| {
            if (i == activeTab) {
                try writer.print("[{s}] ", .{dataset.name});
            } else {
                try writer.print(" {s}  ", .{dataset.name});
            }
        }
        try writer.writeAll("\n");

        try self.terminal.print(self.renderBuffer.items, null);
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
const Image = struct {
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

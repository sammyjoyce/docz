//! Sparkline widget for inline data visualization
//! Provides compact trend visualization using Unicode block characters
//! Perfect for showing metrics trends in small spaces

const std = @import("std");
const renderer_mod = @import("../../core/renderer.zig");
const bounds_mod = @import("../../core/bounds.zig");
const terminal_mod = @import("../../../term/unified.zig");

const Renderer = renderer_mod.Renderer;
const RenderContext = renderer_mod.RenderContext;
const Bounds = bounds_mod.Bounds;

pub const SparklineError = error{
    InvalidData,
    InsufficientSpace,
} || std.mem.Allocator.Error;

pub const Sparkline = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    data: []f64,
    config: Config,
    bounds: Bounds = Bounds.init(0, 0, 0, 0),

    pub const Config = struct {
        title: ?[]const u8 = null,
        show_value: bool = true,
        show_trend: bool = true,
        show_min_max: bool = false,
        style: Style = .unicode_blocks,
        color_mode: ColorMode = .auto,
        height: u32 = 1, // Number of terminal rows

        pub const Style = enum {
            unicode_blocks, // ▁▂▃▄▅▆▇█
            ascii_chars, // ._-^*
            dot_style, // ⋅•●
            bar_style, // |/\
        };

        pub const ColorMode = enum {
            none, // No color
            gradient, // Color gradient based on values
            trend, // Green up, red down
            threshold, // Color based on configurable thresholds
            auto, // Auto-select based on terminal capabilities
        };
    };

    // Unicode block characters for different heights
    const UNICODE_BLOCKS = [_][]const u8{
        " ", // 0/8
        "▁", // 1/8
        "▂", // 2/8
        "▃", // 3/8
        "▄", // 4/8
        "▅", // 5/8
        "▆", // 6/8
        "▇", // 7/8
        "█", // 8/8
    };

    // ASCII fallback characters
    const ASCII_CHARS = [_]u8{ ' ', '.', '_', '-', '^', '*', '*', '*', '*' };

    // Dot style characters
    const DOT_CHARS = [_][]const u8{ " ", "⋅", "⋅", "•", "•", "●", "●", "●", "●" };

    // Bar style characters
    const BAR_CHARS = [_]u8{ ' ', '/', '/', '|', '|', '\\', '\\', '|', '|' };

    pub fn init(allocator: std.mem.Allocator, data: []f64, config: Config) Self {
        return Self{
            .allocator = allocator,
            .data = data,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        // We don't own the data, so no cleanup needed
        _ = self;
    }

    pub fn setData(self: *Self, data: []f64) void {
        self.data = data;
    }

    pub fn render(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        self.bounds = ctx.bounds;

        if (self.data.len == 0) {
            try self.renderEmpty(renderer, ctx);
            return;
        }

        // Calculate sparkline area
        var sparkline_bounds = ctx.bounds;
        const current_y = ctx.bounds.y;

        // Render title if present
        if (self.config.title) |title| {
            try renderer.moveCursor(ctx.bounds.x, current_y);
            try renderer.setStyle(.{ .dim = true });
            try renderer.writeText("{s}: ", .{title});
            try renderer.resetStyle();

            // Adjust bounds for inline display
            const title_width = title.len + 2; // +2 for ": "
            sparkline_bounds.x += @intCast(title_width);
            sparkline_bounds.width -|= @intCast(title_width);
        }

        // Render sparkline
        try self.renderSparkline(renderer, sparkline_bounds);

        // Render current value and trend if requested
        if (self.config.show_value or self.config.show_trend) {
            try self.renderMetrics(renderer, ctx, current_y);
        }
    }

    fn renderEmpty(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        try renderer.moveCursor(ctx.bounds.x, ctx.bounds.y);

        if (self.config.title) |title| {
            try renderer.writeText("{s}: ", .{title});
        }

        try renderer.setStyle(.{ .dim = true });
        try renderer.writeText("(no data)");
        try renderer.resetStyle();
    }

    fn renderSparkline(self: *Self, renderer: *Renderer, bounds: Bounds) !void {
        if (bounds.width == 0 or self.data.len == 0) return;

        // Calculate data range
        const data_range = self.calculateRange();
        if (data_range.max == data_range.min) {
            // All values are the same
            try self.renderFlatLine(renderer, bounds, data_range.max);
            return;
        }

        // Prepare sparkline characters
        var sparkline_buffer = try self.allocator.alloc(u8, bounds.width * 4); // Max 4 bytes per Unicode char
        defer self.allocator.free(sparkline_buffer);

        var buffer_pos: usize = 0;

        // Generate sparkline
        const points_per_column = @max(1, self.data.len / bounds.width);

        for (0..bounds.width) |col| {
            const data_start = col * points_per_column;
            const data_end = @min(data_start + points_per_column, self.data.len);

            if (data_start >= self.data.len) break;

            // Calculate average for this column if multiple points
            var value_sum: f64 = 0;
            for (data_start..data_end) |i| {
                value_sum += self.data[i];
            }
            const avg_value = value_sum / @as(f64, @floatFromInt(data_end - data_start));

            // Normalize value to 0-8 range for block characters
            const normalized = (avg_value - data_range.min) / (data_range.max - data_range.min);
            const block_level = @as(u8, @intFromFloat(@round(normalized * 8.0)));

            // Get character based on style
            const char_bytes = self.getSparklineChar(block_level);

            // Copy to buffer
            if (buffer_pos + char_bytes.len <= sparkline_buffer.len) {
                @memcpy(sparkline_buffer[buffer_pos .. buffer_pos + char_bytes.len], char_bytes);
                buffer_pos += char_bytes.len;
            }
        }

        // Render the sparkline
        try renderer.moveCursor(bounds.x, bounds.y);

        // Apply color if configured
        if (self.shouldUseColor()) {
            try self.applySparklineColor(renderer, data_range);
        }

        try renderer.writeText("{s}", .{sparkline_buffer[0..buffer_pos]});
        try renderer.resetStyle();
    }

    fn renderFlatLine(self: *Self, renderer: *Renderer, bounds: Bounds, value: f64) !void {
        try renderer.moveCursor(bounds.x, bounds.y);

        // Use middle block for flat line
        const char_bytes = self.getSparklineChar(4);

        for (0..bounds.width) |_| {
            try renderer.writeText("{s}", .{char_bytes});
        }

        _ = value; // TODO: Could show the flat value
    }

    fn renderMetrics(self: *Self, renderer: *Renderer, ctx: RenderContext, y: u32) !void {
        const current_value = self.data[self.data.len - 1];

        // Position metrics at the end of the line
        var metrics_x = ctx.bounds.x + ctx.bounds.width;
        var metrics_text = std.ArrayList(u8).init(self.allocator);
        defer metrics_text.deinit();

        const writer = metrics_text.writer();

        // Current value
        if (self.config.show_value) {
            try writer.print(" {d:.1}", .{current_value});
        }

        // Trend indicator
        if (self.config.show_trend and self.data.len >= 2) {
            const prev_value = self.data[self.data.len - 2];
            const trend = current_value - prev_value;

            const trend_symbol = if (trend > 0) "↑" else if (trend < 0) "↓" else "→";
            const trend_color = if (trend > 0)
                terminal_mod.Color.green
            else if (trend < 0)
                terminal_mod.Color.red
            else
                terminal_mod.Color.white;

            try writer.print(" {s}", .{trend_symbol});

            // Color the trend symbol
            if (self.shouldUseColor()) {
                metrics_x -= @intCast(metrics_text.items.len);
                try renderer.moveCursor(metrics_x, y);
                try renderer.setForeground(trend_color);
                try renderer.writeText("{s}", .{metrics_text.items});
                try renderer.resetStyle();
                return;
            }
        }

        // Min/Max if requested
        if (self.config.show_min_max) {
            const range = self.calculateRange();
            try writer.print(" [{d:.1}-{d:.1}]", .{ range.min, range.max });
        }

        // Render metrics
        metrics_x -= @intCast(metrics_text.items.len);
        try renderer.moveCursor(metrics_x, y);
        try renderer.writeText("{s}", .{metrics_text.items});
    }

    fn getSparklineChar(self: *Self, level: u8) []const u8 {
        const safe_level = @min(level, 8);

        switch (self.config.style) {
            .unicode_blocks => return UNICODE_BLOCKS[safe_level],
            .ascii_chars => return &[_]u8{ASCII_CHARS[safe_level]},
            .dot_style => return DOT_CHARS[safe_level],
            .bar_style => return &[_]u8{BAR_CHARS[safe_level]},
        }
    }

    fn shouldUseColor(self: *Self) bool {
        switch (self.config.color_mode) {
            .none => return false,
            .auto => {
                // TODO: Detect terminal color capabilities
                return true;
            },
            else => return true,
        }
    }

    fn applySparklineColor(self: *Self, renderer: *Renderer, range: DataRange) !void {
        switch (self.config.color_mode) {
            .gradient => try self.applyGradientColor(renderer, range),
            .trend => try self.applyTrendColor(renderer),
            .threshold => try self.applyThresholdColor(renderer),
            else => {},
        }
    }

    fn applyGradientColor(self: *Self, renderer: *Renderer, range: DataRange) !void {
        _ = self;
        _ = range;

        // Simple gradient from red (low) to green (high)
        // In a real implementation, you'd calculate color based on the current value
        try renderer.setForeground(terminal_mod.Color.cyan);
    }

    fn applyTrendColor(self: *Self, renderer: *Renderer) !void {
        if (self.data.len < 2) return;

        const current = self.data[self.data.len - 1];
        const previous = self.data[self.data.len - 2];

        const color = if (current > previous)
            terminal_mod.Color.green
        else if (current < previous)
            terminal_mod.Color.red
        else
            terminal_mod.Color.white;

        try renderer.setForeground(color);
    }

    fn applyThresholdColor(self: *Self, renderer: *Renderer) !void {
        if (self.data.len == 0) return;

        const current = self.data[self.data.len - 1];

        // Simple threshold example (could be configurable)
        const color = if (current > 75)
            terminal_mod.Color.red
        else if (current > 50)
            terminal_mod.Color.yellow
        else
            terminal_mod.Color.green;

        try renderer.setForeground(color);
    }

    const DataRange = struct {
        min: f64,
        max: f64,
    };

    fn calculateRange(self: *Self) DataRange {
        if (self.data.len == 0) {
            return DataRange{ .min = 0, .max = 1 };
        }

        var min_val = self.data[0];
        var max_val = self.data[0];

        for (self.data[1..]) |value| {
            if (value < min_val) min_val = value;
            if (value > max_val) max_val = value;
        }

        // Ensure we have some range to work with
        if (min_val == max_val) {
            return DataRange{ .min = min_val - 0.5, .max = max_val + 0.5 };
        }

        return DataRange{ .min = min_val, .max = max_val };
    }

    pub fn handleInput(self: *Self, event: anytype) !void {
        // Sparklines are typically read-only, but could support interactions
        _ = self;
        _ = event;
    }

    // Utility functions for creating common sparkline configurations
    pub fn createMemoryUsageSparkline(allocator: std.mem.Allocator, data: []f64) Self {
        return Self.init(allocator, data, Config{
            .title = "Memory",
            .show_value = true,
            .show_trend = true,
            .color_mode = .threshold,
            .style = .unicode_blocks,
        });
    }

    pub fn createCpuUsageSparkline(allocator: std.mem.Allocator, data: []f64) Self {
        return Self.init(allocator, data, Config{
            .title = "CPU",
            .show_value = true,
            .show_trend = true,
            .color_mode = .gradient,
            .style = .unicode_blocks,
        });
    }

    pub fn createNetworkSparkline(allocator: std.mem.Allocator, data: []f64) Self {
        return Self.init(allocator, data, Config{
            .title = "Network",
            .show_value = true,
            .show_trend = false,
            .color_mode = .trend,
            .style = .unicode_blocks,
        });
    }

    pub fn createInlineSparkline(allocator: std.mem.Allocator, data: []f64, title: []const u8) Self {
        return Self.init(allocator, data, Config{
            .title = title,
            .show_value = false,
            .show_trend = false,
            .color_mode = .auto,
            .style = .unicode_blocks,
        });
    }
};

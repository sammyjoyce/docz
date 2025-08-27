//! Rich Progress Bar with Advanced Graphics
//! Utilizes Kitty Graphics Protocol, Sixel graphics, and Unicode for rich visualizations.
//! Features inline charts, sparklines, animated indicators, and terminal graphics.

const std = @import("std");
const term_shared = @import("term_shared");
const term_ansi = term_shared.ansi.color;
const term_cursor = term_shared.ansi.cursor;
const term_caps = term_shared.caps;
const graphics_manager = term_shared.graphics_manager;
const unified = term_shared.unified;

const Allocator = std.mem.Allocator;
const GraphicsManager = graphics_manager.GraphicsManager;

pub const ProgressStyle = enum {
    simple, // Basic text progress bar
    unicode, // Unicode block characters
    gradient, // Color gradient effect
    animated, // Animated with wave effect
    sparkline, // Mini chart showing progress history
    circular, // Circular progress indicator
    chart_bar, // Inline bar chart
    chart_line, // Inline line chart
};

pub const ChartPoint = struct {
    value: f32,
    label: ?[]const u8 = null,
    timestamp: i64,
};

/// Rich Progress Bar with advanced graphics capabilities
pub const RichProgressBar = struct {
    allocator: Allocator,
    caps: term_caps.TermCaps,
    graphics: ?*GraphicsManager,

    // Core properties
    style: ProgressStyle,
    width: u32,
    current_progress: f32,
    label: []const u8,

    // Display options
    show_percentage: bool,
    show_eta: bool,
    show_speed: bool,
    show_sparkline: bool,

    // Animation and timing
    animation_frame: u32,
    start_time: ?i64,
    last_update: i64,

    // Chart and history data
    history: std.ArrayList(ChartPoint),
    max_history: usize,

    // Rich graphics support
    use_graphics: bool,
    chart_image_id: ?u32,

    pub fn init(
        allocator: Allocator,
        style: ProgressStyle,
        width: u32,
        label: []const u8,
    ) RichProgressBar {
        const caps = term_caps.getTermCaps();

        return RichProgressBar{
            .allocator = allocator,
            .caps = caps,
            .graphics = null,
            .style = style,
            .width = width,
            .current_progress = 0.0,
            .label = label,
            .show_percentage = true,
            .show_eta = true,
            .show_speed = false,
            .show_sparkline = false,
            .animation_frame = 0,
            .start_time = null,
            .last_update = 0,
            .history = std.ArrayList(ChartPoint).init(allocator),
            .max_history = 100,
            .use_graphics = caps.supportsKittyGraphics or caps.supportsSixel,
            .chart_image_id = null,
        };
    }

    pub fn deinit(self: *RichProgressBar) void {
        self.history.deinit();
        if (self.graphics) |gm| {
            if (self.chart_image_id) |image_id| {
                gm.unloadImage(image_id) catch {};
            }
        }
    }

    pub fn setGraphicsManager(self: *RichProgressBar, gm: *GraphicsManager) void {
        self.graphics = gm;
    }

    pub fn configure(
        self: *RichProgressBar,
        options: struct {
            show_percentage: bool = true,
            show_eta: bool = true,
            show_speed: bool = false,
            show_sparkline: bool = false,
            max_history: usize = 100,
        },
    ) void {
        self.show_percentage = options.show_percentage;
        self.show_eta = options.show_eta;
        self.show_speed = options.show_speed;
        self.show_sparkline = options.show_sparkline;
        self.max_history = options.max_history;
    }

    /// Update progress and add to history
    pub fn setProgress(self: *RichProgressBar, progress: f32) !void {
        self.current_progress = std.math.clamp(progress, 0.0, 1.0);
        const now = std.time.timestamp();

        if (self.start_time == null) {
            self.start_time = now;
        }

        // Add to history for sparkline/chart visualization
        try self.history.append(ChartPoint{
            .value = self.current_progress,
            .timestamp = now,
        });

        // Limit history size
        if (self.history.items.len > self.max_history) {
            _ = self.history.orderedRemove(0);
        }

        self.last_update = now;

        // Update chart graphics if using advanced visualization
        if (self.use_graphics and (self.style == .chart_bar or self.style == .chart_line)) {
            try self.updateChartGraphics();
        }
    }

    /// Render the rich progress bar
    pub fn render(self: *RichProgressBar, writer: anytype) !void {
        self.animation_frame +%= 1;

        // Clear line and save cursor
        try writer.writeAll("\r\x1b[K");

        // Label with enhanced styling
        try self.renderLabel(writer);

        // Main progress visualization
        switch (self.style) {
            .simple => try self.renderSimpleBar(writer),
            .unicode => try self.renderUnicodeBar(writer),
            .gradient => try self.renderGradientBar(writer),
            .animated => try self.renderAnimatedBar(writer),
            .sparkline => try self.renderSparklineBar(writer),
            .circular => try self.renderCircularBar(writer),
            .chart_bar => try self.renderChartBar(writer),
            .chart_line => try self.renderChartLine(writer),
        }

        // Additional information
        try self.renderMetadata(writer);

        // Sparkline history if enabled
        if (self.show_sparkline and self.style != .sparkline) {
            try self.renderInlineSparkline(writer);
        }

        try term_ansi.resetStyle(writer, self.caps);
    }

    fn renderLabel(self: *RichProgressBar, writer: anytype) !void {
        // Enhanced label with icon
        const icon = switch (self.style) {
            .simple, .unicode => "▶",
            .gradient => "🌈",
            .animated => "✨",
            .sparkline => "📊",
            .circular => "🎯",
            .chart_bar => "📊",
            .chart_line => "📈",
        };

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }

        try writer.print("{s} {s}: ", .{ icon, self.label });
        try term_ansi.resetStyle(writer, self.caps);
    }

    fn renderSimpleBar(self: *RichProgressBar, writer: anytype) !void {
        const filled_chars = @as(u32, @intFromFloat(self.current_progress * @as(f32, @floatFromInt(self.width))));

        try writer.writeAll("[");

        // Filled portion
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 50, 205, 50);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 10);
        }
        for (0..filled_chars) |_| {
            try writer.writeAll("=");
        }

        // Empty portion
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 60, 60, 60);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 8);
        }
        for (filled_chars..self.width) |_| {
            try writer.writeAll("-");
        }

        try writer.writeAll("]");
    }

    fn renderUnicodeBar(self: *RichProgressBar, writer: anytype) !void {
        const filled_chars = @as(u32, @intFromFloat(self.current_progress * @as(f32, @floatFromInt(self.width))));
        const partial_progress = (self.current_progress * @as(f32, @floatFromInt(self.width))) - @as(f32, @floatFromInt(filled_chars));

        // Unicode block characters for smooth progress
        const blocks = [_][]const u8{ "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█" };
        const partial_block_idx = @as(usize, @intFromFloat(partial_progress * 8.0));

        try writer.writeAll("▕");

        // Filled blocks
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 50, 205, 50);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 10);
        }
        for (0..filled_chars) |_| {
            try writer.writeAll("█");
        }

        // Partial block for smooth animation
        if (filled_chars < self.width and partial_block_idx > 0 and partial_block_idx < blocks.len) {
            try writer.writeAll(blocks[partial_block_idx]);

            // Empty portion
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 60, 60, 60);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 8);
            }
            for ((filled_chars + 1)..self.width) |_| {
                try writer.writeAll("░");
            }
        } else {
            // Empty portion
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 60, 60, 60);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 8);
            }
            for (filled_chars..self.width) |_| {
                try writer.writeAll("░");
            }
        }

        try writer.writeAll("▏");
    }

    fn renderGradientBar(self: *RichProgressBar, writer: anytype) !void {
        const filled_chars = @as(u32, @intFromFloat(self.current_progress * @as(f32, @floatFromInt(self.width))));

        try writer.writeAll("▕");

        for (0..self.width) |i| {
            const pos = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.width));
            const is_filled = i < filled_chars;

            if (self.caps.supportsTrueColor() and is_filled) {
                // Rainbow gradient based on position
                const hue = pos * 120.0; // Green to red range
                const rgb = hsvToRgb(120.0 - hue, 0.8, 1.0); // Green = 120, Red = 0
                try term_ansi.setForegroundRgb(writer, self.caps, rgb[0], rgb[1], rgb[2]);
                try writer.writeAll("█");
            } else if (is_filled) {
                try term_ansi.setForeground256(writer, self.caps, 10);
                try writer.writeAll("█");
            } else {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 60, 60, 60);
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 8);
                }
                try writer.writeAll("░");
            }
        }

        try writer.writeAll("▏");
    }

    fn renderAnimatedBar(self: *RichProgressBar, writer: anytype) !void {
        const filled_chars = @as(u32, @intFromFloat(self.current_progress * @as(f32, @floatFromInt(self.width))));
        const wave_pos = self.animation_frame % (self.width * 2);

        try writer.writeAll("▕");

        for (0..self.width) |i| {
            const is_filled = i < filled_chars;
            const is_wave = (wave_pos >= i and wave_pos < i + 3) or (wave_pos >= (self.width * 2 - i) and wave_pos < (self.width * 2 - i + 3));

            if (self.caps.supportsTrueColor()) {
                if (is_filled and is_wave) {
                    // Bright white for wave effect
                    try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
                } else if (is_filled) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 50, 205, 50);
                } else {
                    try term_ansi.setForegroundRgb(writer, self.caps, 60, 60, 60);
                }
            } else {
                if (is_filled and is_wave) {
                    try term_ansi.setForeground256(writer, self.caps, 15);
                } else if (is_filled) {
                    try term_ansi.setForeground256(writer, self.caps, 10);
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 8);
                }
            }

            if (is_filled) {
                try writer.writeAll("█");
            } else {
                try writer.writeAll("░");
            }
        }

        try writer.writeAll("▏");
    }

    fn renderSparklineBar(self: *RichProgressBar, writer: anytype) !void {
        // Mini sparkline showing progress history
        if (self.history.items.len < 2) {
            return self.renderUnicodeBar(writer);
        }

        const sparkline_chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
        const data_points = @min(self.width, self.history.items.len);
        const start_idx = if (self.history.items.len > self.width)
            self.history.items.len - self.width
        else
            0;

        try writer.writeAll("▕");

        for (0..data_points) |i| {
            const data_idx = start_idx + i;
            const value = self.history.items[data_idx].value;
            const spark_idx = @as(usize, @intFromFloat(value * 7.0));

            if (self.caps.supportsTrueColor()) {
                // Color based on value
                const red = @as(u8, @intFromFloat(255.0 * (1.0 - value)));
                const green = @as(u8, @intFromFloat(255.0 * value));
                try term_ansi.setForegroundRgb(writer, self.caps, red, green, 0);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 10);
            }

            try writer.writeAll(sparkline_chars[@min(spark_idx, sparkline_chars.len - 1)]);
        }

        // Fill remaining width
        if (data_points < self.width) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 60, 60, 60);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 8);
            }
            for (data_points..self.width) |_| {
                try writer.writeAll("░");
            }
        }

        try writer.writeAll("▏");
    }

    fn renderCircularBar(self: *RichProgressBar, writer: anytype) !void {

        // Circular progress characters
        const circles = [_][]const u8{ "○", "◔", "◑", "◕", "●" };
        // Show multiple circles for longer width
        const num_circles = @min(self.width / 2, 5);

        for (0..num_circles) |i| {
            const circle_progress = self.current_progress * @as(f32, @floatFromInt(num_circles)) - @as(f32, @floatFromInt(i));
            const circle_level = @as(usize, @intFromFloat(std.math.clamp(circle_progress * 4.0, 0.0, 4.0)));

            if (self.caps.supportsTrueColor()) {
                const hue = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_circles))) * 360.0;
                const rgb = hsvToRgb(hue, 0.8, 1.0);
                try term_ansi.setForegroundRgb(writer, self.caps, rgb[0], rgb[1], rgb[2]);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 10);
            }

            if (circle_level >= circles.len) {
                try writer.writeAll(circles[circles.len - 1]);
            } else {
                try writer.writeAll(circles[circle_level]);
            }

            try writer.writeAll(" ");
        }
    }

    fn renderChartBar(self: *RichProgressBar, writer: anytype) !void {
        // Render inline bar chart if graphics supported, fallback to text
        if (self.use_graphics and self.graphics != null) {
            try self.renderGraphicalChart(writer, .bar);
        } else {
            try self.renderTextChart(writer, .bar);
        }
    }

    fn renderChartLine(self: *RichProgressBar, writer: anytype) !void {
        // Render inline line chart if graphics supported, fallback to text
        if (self.use_graphics and self.graphics != null) {
            try self.renderGraphicalChart(writer, .line);
        } else {
            try self.renderTextChart(writer, .line);
        }
    }

    fn renderGraphicalChart(self: *RichProgressBar, writer: anytype, chart_type: enum { bar, line }) !void {
        // In a full implementation, this would:
        // 1. Generate chart image data using graphics_manager
        // 2. Upload to terminal via Kitty/Sixel protocol
        // 3. Display inline with the progress bar

        // For now, fallback to text representation
        try self.renderTextChart(writer, chart_type);
    }

    fn renderTextChart(self: *RichProgressBar, writer: anytype, chart_type: enum { bar, line }) !void {
        if (self.history.items.len < 2) {
            return self.renderUnicodeBar(writer);
        }

        const chart_width = @min(self.width, 20);
        const data_points = @min(chart_width, self.history.items.len);
        const start_idx = if (self.history.items.len > chart_width)
            self.history.items.len - chart_width
        else
            0;

        switch (chart_type) {
            .bar => {
                // Mini bar chart
                const bars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };

                for (0..data_points) |i| {
                    const data_idx = start_idx + i;
                    const value = self.history.items[data_idx].value;
                    const bar_idx = @as(usize, @intFromFloat(value * 7.0));

                    if (self.caps.supportsTrueColor()) {
                        const progress_color = value * 120.0; // Green to yellow range
                        const rgb = hsvToRgb(progress_color, 0.8, 1.0);
                        try term_ansi.setForegroundRgb(writer, self.caps, rgb[0], rgb[1], rgb[2]);
                    } else {
                        try term_ansi.setForeground256(writer, self.caps, 10);
                    }

                    try writer.writeAll(bars[@min(bar_idx, bars.len - 1)]);
                }
            },
            .line => {
                // Mini line chart with connecting characters
                const line_chars = [_][]const u8{ "_", "⁻", "⁼", "¯" };

                for (0..data_points) |i| {
                    const data_idx = start_idx + i;
                    const value = self.history.items[data_idx].value;
                    const line_idx = @as(usize, @intFromFloat(value * 3.0));

                    if (self.caps.supportsTrueColor()) {
                        try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
                    } else {
                        try term_ansi.setForeground256(writer, self.caps, 12);
                    }

                    try writer.writeAll(line_chars[@min(line_idx, line_chars.len - 1)]);
                }
            },
        }
    }

    fn renderMetadata(self: *RichProgressBar, writer: anytype) !void {
        // Percentage
        if (self.show_percentage) {
            try term_ansi.resetStyle(writer, self.caps);
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 200, 200, 200);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 7);
            }
            try writer.print(" {d:.1}%", .{self.current_progress * 100.0});
        }

        // ETA
        if (self.show_eta and self.start_time != null and self.current_progress > 0.01) {
            const elapsed = self.last_update - self.start_time.?;
            const total_estimated = @as(f32, @floatFromInt(elapsed)) / self.current_progress;
            const remaining = @as(i64, @intFromFloat(total_estimated)) - elapsed;

            if (remaining > 0) {
                try writer.print(" ETA: {d}s", .{remaining});
            }
        }

        // Speed (items per second)
        if (self.show_speed and self.history.items.len >= 2) {
            const recent_items = @min(10, self.history.items.len);
            const start_idx = self.history.items.len - recent_items;
            const time_span = self.history.items[self.history.items.len - 1].timestamp -
                self.history.items[start_idx].timestamp;

            if (time_span > 0) {
                const progress_change = self.history.items[self.history.items.len - 1].value -
                    self.history.items[start_idx].value;
                const speed = progress_change / @as(f32, @floatFromInt(time_span));
                try writer.print(" {d:.2}/s", .{speed});
            }
        }
    }

    fn renderInlineSparkline(self: *RichProgressBar, writer: anytype) !void {
        if (self.history.items.len < 2) return;

        try writer.writeAll(" [");

        const sparkline_chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
        const data_points = @min(20, self.history.items.len);
        const start_idx = if (self.history.items.len > 20)
            self.history.items.len - 20
        else
            0;

        for (0..data_points) |i| {
            const data_idx = start_idx + i;
            const value = self.history.items[data_idx].value;
            const spark_idx = @as(usize, @intFromFloat(value * 7.0));

            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 12);
            }

            try writer.writeAll(sparkline_chars[@min(spark_idx, sparkline_chars.len - 1)]);
        }

        try writer.writeAll("]");
    }

    fn updateChartGraphics(self: *RichProgressBar) !void {
        // In a full implementation, this would generate chart graphics
        // using the GraphicsManager and update the display
        _ = self;
    }

    /// Clear the progress bar from the terminal
    pub fn clear(self: *RichProgressBar, writer: anytype) !void {
        _ = self;
        try writer.writeAll("\r\x1b[K");
    }

    /// Get current speed (progress per second)
    pub fn getCurrentSpeed(self: RichProgressBar) f32 {
        if (self.history.items.len < 2) return 0.0;

        const recent_items = @min(5, self.history.items.len);
        const start_idx = self.history.items.len - recent_items;
        const time_span = self.history.items[self.history.items.len - 1].timestamp -
            self.history.items[start_idx].timestamp;

        if (time_span > 0) {
            const progress_change = self.history.items[self.history.items.len - 1].value -
                self.history.items[start_idx].value;
            return progress_change / @as(f32, @floatFromInt(time_span));
        }

        return 0.0;
    }

    /// Get estimated time remaining
    pub fn getETA(self: RichProgressBar) ?i64 {
        if (self.start_time == null or self.current_progress <= 0.01) return null;

        const elapsed = self.last_update - self.start_time.?;
        const total_estimated = @as(f32, @floatFromInt(elapsed)) / self.current_progress;
        const remaining = @as(i64, @intFromFloat(total_estimated)) - elapsed;

        return if (remaining > 0) remaining else null;
    }
};

/// HSV to RGB conversion for color effects
fn hsvToRgb(h: f32, s: f32, v: f32) [3]u8 {
    const c = v * s;
    const x = c * (1.0 - @abs(@mod(h / 60.0, 2.0) - 1.0));
    const m = v - c;

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    if (h >= 0.0 and h < 60.0) {
        r = c;
        g = x;
    } else if (h >= 60.0 and h < 120.0) {
        r = x;
        g = c;
    } else if (h >= 120.0 and h < 180.0) {
        g = c;
        b = x;
    } else if (h >= 180.0 and h < 240.0) {
        g = x;
        b = c;
    } else if (h >= 240.0 and h < 300.0) {
        r = x;
        b = c;
    } else {
        r = c;
        b = x;
    }

    return [3]u8{
        @intFromFloat((r + m) * 255.0),
        @intFromFloat((g + m) * 255.0),
        @intFromFloat((b + m) * 255.0),
    };
}

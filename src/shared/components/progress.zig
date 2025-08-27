//! Progress Bar System
//!
//! This module provides a comprehensive progress bar system that consolidates
//! functionality from multiple implementations. It supports:
//! - Core progress calculation and state management
//! - Multiple rendering styles (ASCII, Unicode, gradients, animations)
//! - Terminal capability detection and adaptive rendering
//! - History tracking for sparklines and charts
//! - Color management (RGB, ANSI, palette)
//! - ETA and rate calculations
//! - Component-based and direct rendering APIs
//! - Adaptive renderer integration with caching
//! - Animated progress bars

const std = @import("std");
const Allocator = std.mem.Allocator;

// Component system integration
const base = @import("base.zig");
const Component = base.Component;
const ComponentState = base.ComponentState;
const RenderContext = base.RenderContext;
const Event = base.Event;

// Adaptive renderer integration
const adaptive_renderer = @import("../render/mod.zig");
const AdaptiveRenderer = adaptive_renderer.AdaptiveRenderer;
const RenderMode = adaptive_renderer.RenderTier;
const cacheKey = adaptive_renderer.cacheKey;

/// RGB color structure
pub const RGB = struct { r: u8, g: u8, b: u8 };

/// Color representation for progress bars
pub const Color = union(enum) {
    rgb: RGB,
    ansi: AnsiColor,
    palette: u8, // 256-color palette index

    pub const AnsiColor = enum(u8) {
        black = 30,
        red = 31,
        green = 32,
        yellow = 33,
        blue = 34,
        magenta = 35,
        cyan = 36,
        white = 37,
        bright_black = 90,
        bright_red = 91,
        bright_green = 92,
        bright_yellow = 93,
        bright_blue = 94,
        bright_magenta = 95,
        bright_cyan = 96,
        bright_white = 97,
    };
};

/// Terminal capabilities for adaptive rendering
pub const TermCaps = struct {
    supports_truecolor: bool = false,
    supports_unicode: bool = false,
    supports_kitty_graphics: bool = false,
    supports_sixel: bool = false,
    supports_256_colors: bool = false,
    supports_wide_chars: bool = false,

    /// Detect terminal capabilities
    pub fn detect() TermCaps {
        // This would normally detect actual terminal capabilities
        // For now, return conservative defaults that can be enhanced
        return .{
            .supports_truecolor = true,
            .supports_unicode = true,
            .supports_256_colors = true,
        };
    }
};

/// Comprehensive progress bar style enumeration
pub const ProgressStyle = enum {
    /// Automatically choose best style for terminal
    auto,
    /// Traditional ASCII progress bar: [====    ] 50%
    ascii,
    /// Unicode blocks: ████████░░░░
    unicode_blocks,
    /// Unicode with smooth transitions: ▓▓▓▓▓░░░
    unicode_smooth,
    /// Perceptual color gradient (requires truecolor)
    gradient,
    /// HSV rainbow colors across the bar
    rainbow,
    /// Animated progress with moving wave effect
    animated,
    /// Unicode mosaic rendering for advanced graphics
    mosaic,
    /// Kitty/Sixel graphics with advanced visualization
    graphical,
    /// Mini sparkline showing progress history
    sparkline,
    /// Circular progress indicator
    circular,
    /// Inline bar chart
    chart_bar,
    /// Inline line chart
    chart_line,
    /// Spinner with percentage: ⠋ 67%
    spinner,
    /// Dot animation: ●●●●●○○○○○
    dots,
    /// Simple text-based progress
    simple,
};

/// Core progress bar data structure with comprehensive features
pub const ProgressData = struct {
    /// Current progress value (0.0 to 1.0)
    value: f32 = 0.0,
    /// Optional label to display
    label: ?[]const u8 = null,
    /// Show percentage text
    show_percentage: bool = true,
    /// Show estimated time of arrival
    show_eta: bool = false,
    /// Show processing rate (bytes/sec, items/sec, etc.)
    show_rate: bool = false,
    /// Start time for ETA calculation
    start_time: ?i64 = null,
    /// Total expected value (for rate calculation)
    total: ?f64 = null,
    /// Current processed value (for rate calculation)
    current: ?f64 = null,
    /// Processing rate (calculated automatically)
    rate: f32 = 0.0,
    /// Custom color override
    color: ?Color = null,
    /// Background color override
    background_color: ?Color = null,
    /// Animation frame counter
    animation_frame: u32 = 0,
    /// History for sparklines/charts
    history: std.ArrayList(ChartPoint),
    /// Maximum history size
    max_history: usize = 100,

    /// Chart point for history tracking
    pub const ChartPoint = struct {
        value: f32,
        label: ?[]const u8 = null,
        timestamp: i64,
    };

    /// Initialize progress data
    pub fn init(allocator: Allocator) ProgressData {
        return ProgressData{
            .history = std.ArrayList(ChartPoint).init(allocator),
        };
    }

    /// Deinitialize progress data
    pub fn deinit(self: *ProgressData) void {
        self.history.deinit();
    }

    /// Validate progress data
    pub fn validate(self: *const ProgressData) !void {
        if (self.value < 0.0 or self.value > 1.0) {
            return error.InvalidProgressValue;
        }
    }

    /// Update progress value and add to history
    pub fn setProgress(self: *ProgressData, value: f32) !void {
        const new_value = std.math.clamp(value, 0.0, 1.0);
        const now = std.time.timestamp();

        if (self.start_time == null and new_value > 0.0) {
            self.start_time = now;
        }

        // Add to history for sparklines/charts
        try self.history.append(ChartPoint{
            .value = new_value,
            .timestamp = now,
        });

        // Limit history size
        if (self.history.items.len > self.max_history) {
            _ = self.history.orderedRemove(0);
        }

        self.value = new_value;
        self.animation_frame +%= 1;
    }

    /// Update current value and recalculate rate
    pub fn updateCurrent(self: *ProgressData, current_value: f64) !void {
        const now = std.time.timestamp();

        if (self.current) |prev_current| {
            const dt = @as(f32, @floatFromInt(now - (self.start_time orelse now)));
            if (dt > 0.0) {
                const delta = current_value - prev_current;
                self.rate = @as(f32, @floatFromInt(delta)) / dt;
            }
        }

        self.current = current_value;
        if (self.start_time == null) {
            self.start_time = now;
        }
    }

    /// Get estimated time remaining in seconds
    pub fn getETA(self: *const ProgressData) ?i64 {
        if (self.start_time == null or self.value <= 0.01) return null;

        const elapsed = std.time.timestamp() - self.start_time.?;
        const rate = self.value / @as(f32, @floatFromInt(elapsed));
        if (rate <= 0.0) return null;

        const remaining = (1.0 - self.value) / rate;
        return @intFromFloat(remaining);
    }

    /// Get current speed (progress per second)
    pub fn getCurrentSpeed(self: *const ProgressData) f32 {
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

    /// Format rate as human-readable string
    pub fn formatRate(self: *const ProgressData, allocator: Allocator) ![]const u8 {
        if (self.rate <= 0.0) return allocator.dupe(u8, "0 B/s");

        if (self.rate >= 1024 * 1024 * 1024) {
            return std.fmt.allocPrint(allocator, "{d:.1} GB/s", .{self.rate / (1024 * 1024 * 1024)});
        } else if (self.rate >= 1024 * 1024) {
            return std.fmt.allocPrint(allocator, "{d:.1} MB/s", .{self.rate / (1024 * 1024)});
        } else if (self.rate >= 1024) {
            return std.fmt.allocPrint(allocator, "{d:.1} KB/s", .{self.rate / 1024});
        } else {
            return std.fmt.allocPrint(allocator, "{d:.1} B/s", .{self.rate});
        }
    }
};

/// Utility functions for progress bar rendering
pub const Utility = struct {
    /// HSV to RGB conversion for color effects
    pub fn hsvToRgb(h: f32, s: f32, v: f32) Color {
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

        return Color{
            .rgb = .{
                .r = @intFromFloat((r + m) * 255.0),
                .g = @intFromFloat((g + m) * 255.0),
                .b = @intFromFloat((b + m) * 255.0),
            },
        };
    }
};

/// Progress bar configuration for component-based usage
pub const BarConfig = struct {
    progress: f32 = 0.0,
    label: ?[]const u8 = null,
    style: ProgressStyle = .auto,
    animated: bool = true,
    show_percentage: bool = true,
    show_eta: bool = false,
    show_rate: bool = false,
};

/// Component-based progress bar that integrates with component system
pub const ProgressBar = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    state: ComponentState,
    config: BarConfig,
    data: ProgressData,

    const vtable = Component.VTable{
        .init = init,
        .deinit = deinit,
        .getState = getState,
        .setState = setState,
        .render = render,
        .measure = measure,
        .handleEvent = handleEvent,
        .addChild = null,
        .removeChild = null,
        .getChildren = null,
        .update = update,
    };

    pub fn create(allocator: std.mem.Allocator, config: BarConfig) !*Component {
        const self = try allocator.create(Self);
        var data = ProgressData.init(allocator);
        try data.setProgress(config.progress);
        data.label = if (config.label) |l| try allocator.dupe(u8, l) else null;
        data.show_percentage = config.show_percentage;
        data.show_eta = config.show_eta;
        data.show_rate = config.show_rate;

        self.* = Self{
            .allocator = allocator,
            .state = ComponentState{},
            .config = config,
            .data = data,
        };

        const component = try allocator.create(Component);
        component.* = Component{
            .vtable = &vtable,
            .impl = self,
            .id = 0,
        };

        return component;
    }

    pub fn setProgress(self: *Self, progress_value: f32) !void {
        try self.data.setProgress(progress_value);
        self.state.markDirty();
    }

    // Component implementation

    fn init(impl: *anyopaque, allocator: std.mem.Allocator) anyerror!void {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(impl));
        self.state = ComponentState{};
    }

    fn deinit(impl: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        if (self.data.label) |label| {
            self.allocator.free(label);
        }
        self.data.deinit();
    }

    fn getState(impl: *anyopaque) *ComponentState {
        const self: *Self = @ptrCast(@alignCast(impl));
        return &self.state;
    }

    fn setState(impl: *anyopaque, state: ComponentState) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.state = state;
    }

    fn render(impl: *anyopaque, ctx: RenderContext) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Move to component position
        try ctx.terminal.moveTo(self.state.bounds.x, self.state.bounds.y);

        // Create a writer for the terminal
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        const writer = buffer.writer();
        var renderer = ProgressRenderer.init(self.allocator);

        // Render the progress bar
        try renderer.render(&self.data, self.config.style, writer, self.state.bounds.width);

        // Print the rendered progress bar
        try ctx.terminal.print(buffer.items, null);
    }

    fn measure(impl: *anyopaque, available: base.Rect) base.Rect {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Default width or use available width
        const width = if (self.state.bounds.width > 0) self.state.bounds.width else @min(available.width, 40);
        const height: u32 = 1; // Single line progress bar

        return base.Rect{
            .x = available.x,
            .y = available.y,
            .width = width,
            .height = height,
        };
    }

    fn handleEvent(impl: *anyopaque, event: Event) anyerror!bool {
        _ = impl;
        _ = event;
        return false; // Progress bars don't handle events
    }

    fn update(impl: *anyopaque, dt: f32) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = dt;

        // Update animation if needed
        if (self.config.animated) {
            self.state.markDirty();
        }
    }
};

/// Comprehensive progress bar renderer with multiple styles
pub const ProgressRenderer = struct {
    allocator: Allocator,
    caps: TermCaps,

    /// Initialize renderer
    pub fn init(allocator: Allocator) ProgressRenderer {
        return ProgressRenderer{
            .allocator = allocator,
            .caps = TermCaps.detect(),
        };
    }

    /// Render progress bar with specified style
    pub fn render(
        self: *ProgressRenderer,
        data: *const ProgressData,
        style: ProgressStyle,
        writer: anytype,
        width: u32,
    ) !void {
        switch (style) {
            .auto => try self.renderAuto(data, writer, width),
            .ascii => try self.renderAscii(data, writer, width),
            .unicode_blocks => try self.renderUnicodeBlocks(data, writer, width),
            .unicode_smooth => try self.renderUnicodeSmooth(data, writer, width),
            .gradient => try self.renderGradient(data, writer, width),
            .rainbow => try self.renderRainbow(data, writer, width),
            .animated => try self.renderAnimated(data, writer, width),
            .mosaic => try self.renderMosaic(data, writer, width),
            .graphical => try self.renderGraphical(data, writer, width),
            .sparkline => try self.renderSparkline(data, writer, width),
            .circular => try self.renderCircular(data, writer, width),
            .chart_bar => try self.renderChartBar(data, writer, width),
            .chart_line => try self.renderChartLine(data, writer, width),
            .spinner => try self.renderSpinner(data, writer, width),
            .dots => try self.renderDots(data, writer, width),
            .simple => try self.renderSimple(data, writer, width),
        }

        // Add metadata if enabled
        try self.renderMetadata(data, writer);
    }

    /// Auto-select best style based on terminal capabilities
    fn renderAuto(self: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        if (self.caps.supports_truecolor) {
            try self.renderGradient(data, writer, width);
        } else if (self.caps.supports_unicode) {
            try self.renderUnicodeSmooth(data, writer, width);
        } else {
            try self.renderAscii(data, writer, width);
        }
    }

    /// Render simple ASCII progress bar
    fn renderAscii(_: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        const filled_count = @as(u32, @intFromFloat(data.value * @as(f32, @floatFromInt(width))));

        // Label
        if (data.label) |label| {
            try writer.print("{s}: ", .{label});
        }

        // Progress bar
        try writer.writeByte('[');
        var i: u32 = 0;
        while (i < width) : (i += 1) {
            const char = if (i < filled_count) '=' else ' ';
            try writer.writeByte(char);
        }
        try writer.writeByte(']');
    }

    /// Render Unicode block progress bar
    fn renderUnicodeBlocks(_: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        const filled_count = @as(u32, @intFromFloat(data.value * @as(f32, @floatFromInt(width))));
        const partial_progress = (data.value * @as(f32, @floatFromInt(width))) - @as(f32, @floatFromInt(filled_count));

        // Unicode block characters for partial blocks
        const blocks = [_][]const u8{ "░", "▒", "▓", "█" };
        const partial_block_idx = @as(usize, @intFromFloat(partial_progress * @as(f32, @floatFromInt(blocks.len))));

        try writer.writeAll("▕");

        // Filled blocks
        var i: u32 = 0;
        while (i < filled_count) : (i += 1) {
            try writer.writeAll("█");
        }

        // Partial block for smooth animation
        if (filled_count < width and partial_block_idx > 0 and partial_block_idx < blocks.len) {
            try writer.writeAll(blocks[partial_block_idx]);

            // Empty portion
            var j = filled_count + 1;
            while (j < width) : (j += 1) {
                try writer.writeAll("░");
            }
        } else {
            // Empty portion
            var j = filled_count;
            while (j < width) : (j += 1) {
                try writer.writeAll("░");
            }
        }

        try writer.writeAll("▏");
    }

    /// Render smooth Unicode progress bar
    fn renderUnicodeSmooth(_: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        const filled_count = @as(u32, @intFromFloat(data.value * @as(f32, @floatFromInt(width))));
        const partial_progress = (data.value * @as(f32, @floatFromInt(width))) - @as(f32, @floatFromInt(filled_count));

        // Smooth Unicode characters
        const chars = [_][]const u8{ "░", "▒", "▓", "█" };
        const partial_char_idx = @as(usize, @intFromFloat(partial_progress * @as(f32, @floatFromInt(chars.len))));

        try writer.writeAll("▕");

        var i: u32 = 0;
        while (i < width) : (i += 1) {
            if (i < filled_count) {
                try writer.writeAll("█");
            } else if (i == filled_count and partial_char_idx > 0) {
                try writer.writeAll(chars[partial_char_idx]);
            } else {
                try writer.writeAll("░");
            }
        }

        try writer.writeAll("▏");
    }

    /// Render gradient progress bar
    fn renderGradient(self: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        if (!self.caps.supports_truecolor) {
            return self.renderUnicodeBlocks(data, writer, width);
        }

        try writer.writeAll("▕");

        var i: u32 = 0;
        while (i < width) : (i += 1) {
            const pos = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(width));
            const is_filled = pos < data.value;

            if (is_filled) {
                // Rainbow gradient based on position
                const hue = pos * 120.0; // Green to red range
                const rgb = Utility.hsvToRgb(120.0 - hue, 0.8, 1.0);
                switch (rgb) {
                    .rgb => |r| try writer.print("\x1b[38;2;{d};{d};{d}m█\x1b[0m", .{ r.r, r.g, r.b }),
                    else => try writer.writeAll("█"),
                }
            } else {
                try writer.writeAll("░");
            }
        }

        try writer.writeAll("▏");
    }

    /// Render rainbow progress bar
    fn renderRainbow(self: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        if (!self.caps.supports_truecolor) {
            return self.renderGradient(data, writer, width);
        }

        try writer.writeAll("▕");

        var i: u32 = 0;
        while (i < width) : (i += 1) {
            const pos = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(width));
            const is_filled = pos < data.value;

            if (is_filled) {
                // HSV rainbow based on position
                const hue = pos * 360.0;
                const rgb = Utility.hsvToRgb(hue, 0.8, 1.0);
                switch (rgb) {
                    .rgb => |r| try writer.print("\x1b[38;2;{d};{d};{d}m█\x1b[0m", .{ r.r, r.g, r.b }),
                    else => try writer.writeAll("█"),
                }
            } else {
                try writer.writeAll("░");
            }
        }

        try writer.writeAll("▏");
    }

    /// Render animated progress bar
    fn renderAnimated(self: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        const filled_count = @as(u32, @intFromFloat(data.value * @as(f32, @floatFromInt(width))));
        const wave_pos = data.animation_frame % (width * 2);

        try writer.writeAll("▕");

        var i: u32 = 0;
        while (i < width) : (i += 1) {
            const is_filled = i < filled_count;
            const is_wave = (wave_pos >= i and wave_pos < i + 3) or (wave_pos >= (width * 2 - i) and wave_pos < (width * 2 - i + 3));

            if (is_filled and is_wave) {
                if (self.caps.supports_truecolor) {
                    try writer.writeAll("\x1b[38;2;255;255;255m█\x1b[0m");
                } else {
                    try writer.writeAll("█");
                }
            } else if (is_filled) {
                try writer.writeAll("█");
            } else {
                try writer.writeAll("░");
            }
        }

        try writer.writeAll("▏");
    }

    /// Render sparkline progress bar
    fn renderSparkline(self: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        if (data.history.items.len < 2) {
            return self.renderUnicodeBlocks(data, writer, width);
        }

        const sparkline_chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
        const data_points = @min(width, data.history.items.len);
        const start_idx = if (data.history.items.len > width)
            data.history.items.len - width
        else
            0;

        try writer.writeAll("▕");

        var i: u32 = 0;
        while (i < data_points) : (i += 1) {
            const data_idx = start_idx + i;
            const value = data.history.items[data_idx].value;
            const spark_idx = @as(usize, @intFromFloat(value * 7.0));

            if (self.caps.supports_truecolor) {
                // Color based on value
                const red = @as(u8, @intFromFloat(255.0 * (1.0 - value)));
                const green = @as(u8, @intFromFloat(255.0 * value));
                try writer.print("\x1b[38;2;{d};{d};0m{s}\x1b[0m", .{ red, green, sparkline_chars[@min(spark_idx, sparkline_chars.len - 1)] });
            } else {
                try writer.writeAll(sparkline_chars[@min(spark_idx, sparkline_chars.len - 1)]);
            }
        }

        // Fill remaining width
        var j = data_points;
        while (j < width) : (j += 1) {
            try writer.writeAll("░");
        }

        try writer.writeAll("▏");
    }

    /// Render circular progress bar
    fn renderCircular(self: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        // Circular progress characters
        const circles = [_][]const u8{ "○", "◔", "◑", "◕", "●" };
        // Show multiple circles for longer width
        const num_circles = @min(width / 2, 5);

        var i: u32 = 0;
        while (i < num_circles) : (i += 1) {
            const circle_progress = data.value * @as(f32, @floatFromInt(num_circles)) - @as(f32, @floatFromInt(i));
            const circle_level = @as(usize, @intFromFloat(std.math.clamp(circle_progress * 4.0, 0.0, 4.0)));

            if (self.caps.supports_truecolor) {
                const hue = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_circles))) * 360.0;
                const rgb = Utility.hsvToRgb(hue, 0.8, 1.0);
                switch (rgb) {
                    .rgb => |r| try writer.print("\x1b[38;2;{d};{d};{d}m{s}\x1b[0m ", .{ r.r, r.g, r.b, if (circle_level >= circles.len) circles[circles.len - 1] else circles[circle_level] }),
                    else => try writer.print("{s} ", .{if (circle_level >= circles.len) circles[circles.len - 1] else circles[circle_level]}),
                }
            } else {
                try writer.print("{s} ", .{if (circle_level >= circles.len) circles[circles.len - 1] else circles[circle_level]});
            }
        }
    }

    /// Render spinner progress bar
    fn renderSpinner(_: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        _ = width;
        const spinner_chars = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
        const spinner_idx = (@as(u64, @intCast(std.time.timestamp())) / 100) % spinner_chars.len;

        try writer.print("{s} {d:.0}%", .{ spinner_chars[spinner_idx], data.value * 100 });
    }

    /// Render dots progress bar
    fn renderDots(_: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        const filled_dots = @as(u32, @intFromFloat(data.value * @as(f32, @floatFromInt(width))));

        var i: u32 = 0;
        while (i < width) : (i += 1) {
            if (i < filled_dots) {
                try writer.writeAll("●");
            } else {
                try writer.writeAll("○");
            }
        }
    }

    /// Render chart bar progress bar
    fn renderChartBar(self: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        if (data.history.items.len < 2) {
            return self.renderUnicodeBlocks(data, writer, width);
        }

        const chart_width = @min(width, 20);
        const data_points = @min(chart_width, data.history.items.len);
        const start_idx = if (data.history.items.len > chart_width)
            data.history.items.len - chart_width
        else
            0;

        // Mini bar chart
        const bars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };

        var i: u32 = 0;
        while (i < data_points) : (i += 1) {
            const data_idx = start_idx + i;
            const value = data.history.items[data_idx].value;
            const bar_idx = @as(usize, @intFromFloat(value * 7.0));

            if (self.caps.supports_truecolor) {
                const progress_color = value * 120.0; // Green to yellow range
                const rgb = Utility.hsvToRgb(progress_color, 0.8, 1.0);
                switch (rgb) {
                    .rgb => |r| try writer.print("\x1b[38;2;{d};{d};{d}m{s}\x1b[0m", .{ r.r, r.g, r.b, bars[@min(bar_idx, bars.len - 1)] }),
                    else => try writer.writeAll(bars[@min(bar_idx, bars.len - 1)]),
                }
            } else {
                try writer.writeAll(bars[@min(bar_idx, bars.len - 1)]);
            }
        }
    }

    /// Render chart line progress bar
    fn renderChartLine(self: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        if (data.history.items.len < 2) {
            return self.renderUnicodeBlocks(data, writer, width);
        }

        const chart_width = @min(width, 20);
        const data_points = @min(chart_width, data.history.items.len);
        const start_idx = if (data.history.items.len > chart_width)
            data.history.items.len - chart_width
        else
            0;

        // Mini line chart with connecting characters
        const line_chars = [_][]const u8{ "_", "⁻", "⁼", "¯" };

        var i: u32 = 0;
        while (i < data_points) : (i += 1) {
            const data_idx = start_idx + i;
            const value = data.history.items[data_idx].value;
            const line_idx = @as(usize, @intFromFloat(value * 3.0));

            if (self.caps.supports_truecolor) {
                try writer.print("\x1b[38;2;100;149;237m{s}\x1b[0m", .{line_chars[@min(line_idx, line_chars.len - 1)]});
            } else {
                try writer.writeAll(line_chars[@min(line_idx, line_chars.len - 1)]);
            }
        }
    }

    /// Render mosaic progress bar (placeholder)
    fn renderMosaic(self: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        // For now, fall back to Unicode blocks
        try self.renderUnicodeBlocks(data, writer, width);
    }

    /// Render graphical progress bar (placeholder)
    fn renderGraphical(self: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        // For now, fall back to gradient
        try self.renderGradient(data, writer, width);
    }

    /// Render simple progress bar
    fn renderSimple(_: *ProgressRenderer, data: *const ProgressData, writer: anytype, width: u32) !void {
        const filled_count = @as(u32, @intFromFloat(data.value * @as(f32, @floatFromInt(width))));

        var i: u32 = 0;
        while (i < width) : (i += 1) {
            const char = if (i < filled_count) '#' else '-';
            try writer.writeByte(char);
        }
    }

    /// Render metadata (percentage, ETA, rate)
    fn renderMetadata(self: *ProgressRenderer, data: *const ProgressData, writer: anytype) !void {
        // Percentage
        if (data.show_percentage) {
            try writer.print(" {d:.0}%", .{data.value * 100});
        }

        // ETA
        if (data.show_eta) {
            if (data.getETA()) |eta_seconds| {
                const eta_minutes = eta_seconds / 60;
                const eta_remaining_seconds = eta_seconds % 60;
                if (eta_minutes > 0) {
                    try writer.print(" ETA: {d}m{d}s", .{ eta_minutes, eta_remaining_seconds });
                } else {
                    try writer.print(" ETA: {d}s", .{eta_seconds});
                }
            } else {
                try writer.print(" ETA: --", .{});
            }
        }

        // Rate
        if (data.show_rate) {
            const rate_str = try data.formatRate(self.allocator);
            defer self.allocator.free(rate_str);
            try writer.print(" {s}", .{rate_str});
        }
    }
};

// Adaptive Renderer Integration

/// Progress bar data for adaptive renderer
pub const AdaptiveProgress = struct {
    value: f32, // 0.0 to 1.0
    label: ?[]const u8 = null,
    percentage: bool = true,
    eta: bool = false,
    eta_seconds: ?u64 = null,
    color: ?Color = null,
    background_color: ?Color = null,

    pub fn validate(self: AdaptiveProgress) !void {
        if (self.value < 0.0 or self.value > 1.0) {
            return error.InvalidProgressValue;
        }
    }

    /// Convert to ProgressData
    pub fn toProgressData(self: AdaptiveProgress, allocator: std.mem.Allocator) !ProgressData {
        var data = ProgressData.init(allocator);
        try data.setProgress(self.value);
        data.label = if (self.label) |l| try allocator.dupe(u8, l) else null;
        data.show_percentage = self.percentage;
        data.show_eta = self.eta;
        data.color = self.color;
        data.background_color = self.background_color;
        return data;
    }
};

/// Render progress bar using renderer
pub fn renderProgress(renderer: *@import("../render/Renderer.zig").Renderer, progress_data: AdaptiveProgress) !void {
    try progress_data.validate();

    const key = cacheKey("progress_{d}_{?s}_{}_{}_{?d}", .{ progress_data.value, progress_data.label, progress_data.percentage, progress_data.eta, progress_data.eta_seconds });

    if (renderer.cache.get(key, renderer.render_tier)) |cached| {
        try renderer.terminal.writeText(cached);
        return;
    }

    var output = std.ArrayList(u8).init(renderer.allocator);
    defer output.deinit();

    // Convert to ProgressData
    var data = try progress_data.toProgressData(renderer.allocator);
    defer data.deinit();

    // Choose style based on render tier
    const style = switch (renderer.render_tier) {
        .ultra => ProgressStyle.rainbow,
        .enhanced => ProgressStyle.unicode_smooth,
        .standard => ProgressStyle.ascii,
        .minimal => ProgressStyle.simple,
    };

    var progress_renderer = ProgressRenderer.init(renderer.allocator);
    try progress_renderer.render(&data, style, output.writer(), 40); // Default width

    const content = try output.toOwnedSlice();
    defer renderer.allocator.free(content);

    try renderer.cache.put(key, content, renderer.render_tier);
    try renderer.terminal.writeText(content);
}

/// Render progress bar from ProgressData
pub fn renderProgressData(renderer: *@import("../render/Renderer.zig").Renderer, data: *ProgressData) !void {
    const key = cacheKey("progress_data_{d}_{?s}_{}_{}_{}", .{ data.value, data.label, data.show_percentage, data.show_eta, data.show_rate });

    if (renderer.cache.get(key, renderer.render_tier)) |cached| {
        try renderer.terminal.writeText(cached);
        return;
    }

    var output = std.ArrayList(u8).init(renderer.allocator);
    defer output.deinit();

    // Choose style based on render tier
    const style = switch (renderer.render_tier) {
        .ultra => ProgressStyle.rainbow,
        .enhanced => ProgressStyle.unicode_smooth,
        .standard => ProgressStyle.ascii,
        .minimal => ProgressStyle.simple,
    };

    var progress_renderer = ProgressRenderer.init(renderer.allocator);
    try progress_renderer.render(data, style, output.writer(), 40); // Default width

    const content = try output.toOwnedSlice();
    defer renderer.allocator.free(content);

    try renderer.cache.put(key, content, renderer.render_tier);
    try renderer.terminal.writeText(content);
}

/// Create animated progress bar that updates over time
pub const Animated = struct {
    renderer: *@import("../render/Renderer.zig").Renderer,
    data: ProgressData,
    start_time: i64,

    pub fn init(renderer: *@import("../render/Renderer.zig").Renderer, progress: AdaptiveProgress) !Animated {
        const data = try progress.toProgressData(renderer.allocator);
        return Animated{
            .renderer = renderer,
            .data = data,
            .start_time = std.time.milliTimestamp(),
        };
    }

    pub fn deinit(self: *Animated) void {
        self.data.deinit();
    }

    pub fn update(self: *Animated, new_value: f32) !void {
        try self.data.setProgress(new_value);

        // Calculate ETA if enabled
        if (self.data.show_eta) {
            // ETA is calculated automatically in ProgressData.getETA()
        }

        // Clear line and render updated progress
        try self.renderer.terminal.writeText("\r\x1b[K");
        try renderProgressData(self.renderer, &self.data);
    }

    pub fn finish(self: *Animated) !void {
        try self.data.setProgress(1.0);
        try self.update(1.0);
        try self.renderer.terminal.writeText("\n");
    }
};

// Tests
test "progress bar rendering" {
    const testing = std.testing;

    var renderer = try AdaptiveRenderer.initWithMode(testing.allocator, .standard);
    defer renderer.deinit();

    const progress = AdaptiveProgress{
        .value = 0.75,
        .label = "Test Progress",
        .percentage = true,
    };

    try renderProgress(renderer, progress);

    // Test validation
    const invalid_progress = AdaptiveProgress{ .value = 1.5 };
    try testing.expectError(error.InvalidProgressValue, invalid_progress.validate());
}

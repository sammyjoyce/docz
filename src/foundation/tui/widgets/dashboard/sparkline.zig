//! Sparkline Widget - Compact Data Visualization
//!
//! A reusable widget for displaying time series data in a compact, inline format.
//! Supports multiple rendering modes and customizable styling.

const std = @import("std");
const engine_mod = @import("engine.zig");
const term_mod = @import("../../../term.zig");
const term_sgr = term_mod.ansi;
const Color = term_mod.color.Color;

pub const Sparkline = struct {
    allocator: std.mem.Allocator,
    data: []const f64,
    width: ?u16,
    height: ?u16,
    title: ?[]const u8,
    color: ?Color,
    background_color: ?Color,
    show_trend: bool,
    fill_area: bool,
    render_mode: RenderMode,
    min_value: ?f64,
    max_value: ?f64,
    style: Style,

    pub const RenderMode = union(enum) {
        graphics: GraphicsMode,
        unicode: UnicodeMode,
        ascii: AsciiMode,

        pub const GraphicsMode = struct {
            anti_aliasing: bool = true,
            smooth_lines: bool = true,
        };

        pub const UnicodeMode = struct {
            use_block_chars: bool = true,
            use_dots: bool = false,
        };

        pub const AsciiMode = struct {
            char_set: CharSet = .bars,

            pub const CharSet = enum {
                bars, // | / - \
                dots, // . o O @
                numbers, // 0-9
                letters, // a-z
            };
        };
    };

    pub const Style = struct {
        line_width: f32 = 1.0,
        point_size: f32 = 1.0,
        show_grid: bool = false,
        show_labels: bool = false,
        label_format: LabelFormat = .none,

        pub const LabelFormat = enum {
            none,
            value,
            percentage,
            index,
        };
    };

    pub fn init(allocator: std.mem.Allocator, capability_tier: engine_mod.DashboardEngine.CapabilityTier) !*Sparkline {
        const sparkline = try allocator.create(Sparkline);
        sparkline.* = .{
            .allocator = allocator,
            .data = &[_]f64{},
            .width = null,
            .height = null,
            .title = null,
            .color = null,
            .background_color = null,
            .show_trend = false,
            .fill_area = false,
            .render_mode = switch (capability_tier) {
                .high, .rich => .{ .graphics = .{} },
                .standard => .{ .unicode = .{} },
                .minimal => .{ .ascii = .{} },
            },
            .min_value = null,
            .max_value = null,
            .style = .{},
        };
        return sparkline;
    }

    pub fn deinit(self: *Sparkline) void {
        if (self.title) |title| {
            self.allocator.free(title);
        }
        self.allocator.destroy(self);
    }

    /// Set the data points for the sparkline
    pub fn setData(self: *Sparkline, data: []const f64) void {
        self.data = data;
    }

    /// Set the dimensions of the sparkline
    pub fn setDimensions(self: *Sparkline, width: ?u16, height: ?u16) void {
        self.width = width;
        self.height = height;
    }

    /// Set the title of the sparkline
    pub fn setTitle(self: *Sparkline, title: []const u8) !void {
        if (self.title) |old_title| {
            self.allocator.free(old_title);
        }
        self.title = try self.allocator.dupe(u8, title);
    }

    /// Set the color of the sparkline
    pub fn setColor(self: *Sparkline, color: ?Color) void {
        self.color = color;
    }

    /// Set the background color
    pub fn setBackgroundColor(self: *Sparkline, color: ?Color) void {
        self.background_color = color;
    }

    /// Enable or disable trend indicators
    pub fn setShowTrend(self: *Sparkline, show: bool) void {
        self.show_trend = show;
    }

    /// Enable or disable area filling
    pub fn setFillArea(self: *Sparkline, fill: bool) void {
        self.fill_area = fill;
    }

    /// Set custom min/max values for scaling
    pub fn setValueRange(self: *Sparkline, min_val: ?f64, max_val: ?f64) void {
        self.min_value = min_val;
        self.max_value = max_val;
    }

    /// Set the render mode
    pub fn setRenderMode(self: *Sparkline, mode: RenderMode) void {
        self.render_mode = mode;
    }

    /// Set the style configuration
    pub fn setStyle(self: *Sparkline, style: Style) void {
        self.style = style;
    }

    pub fn render(self: *Sparkline, render_pipeline: anytype, bounds: anytype) !void {
        switch (self.render_mode) {
            .graphics => try self.renderGraphics(bounds),
            .unicode => try self.renderUnicode(bounds),
            .ascii => try self.renderAscii(bounds),
        }
        _ = render_pipeline;
    }

    pub fn handleInput(self: *Sparkline, input: anytype) !bool {
        _ = self;
        _ = input;
        return false; // Sparklines don't handle input by default
    }

    fn renderGraphics(self: *Sparkline, bounds: anytype) !void {
        // Graphics mode - would use Kitty/Sixel for advanced rendering
        // For now, fall back to Unicode
        try self.renderUnicode(bounds);
    }

    fn renderUnicode(self: *Sparkline, bounds: anytype) !void {
        if (self.data.len == 0) {
            try self.renderEmpty(bounds);
            return;
        }

        const width = self.width orelse @as(u16, @intCast(bounds.width));
        _ = self.height orelse 1; // Height not used in single-line sparkline

        // Calculate value range
        const min_max = self.calculateMinMax();
        const value_range = min_max.max - min_max.min;
        if (value_range == 0) {
            try self.renderFlatLine(width);
            return;
        }

        // Unicode block characters for different heights
        const blocks = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };

        // Title
        if (self.title) |title| {
            try self.writeWithColor(title, null);
            try std.io.getStdOut().writer().writeAll("\n");
        }

        // Render sparkline
        try self.writeWithColor("▕", self.color);

        for (self.data, 0..) |value, i| {
            if (i >= width) break;

            const normalized = (value - min_max.min) / value_range;
            const block_index = @as(usize, @intFromFloat(std.math.clamp(normalized * @as(f64, @floatFromInt(blocks.len - 1)), 0, @as(f64, @floatFromInt(blocks.len - 1)))));

            try self.writeWithColor(blocks[block_index], self.color);
        }

        // Fill remaining width
        var remaining = width - @as(u16, @min(@as(u32, @intCast(width)), @as(u32, @intCast(self.data.len))));
        while (remaining > 0) : (remaining -= 1) {
            try self.writeWithColor("░", self.color);
        }

        try self.writeWithColor("▏", self.color);

        // Trend indicator
        if (self.show_trend and self.data.len >= 2) {
            const trend = self.calculateTrend();
            const trend_char = if (trend > 0.01) "↗" else if (trend < -0.01) "↘" else "→";
            try std.io.getStdOut().writer().print(" {s}", .{trend_char});
        }

        try std.io.getStdOut().writer().writeAll("\n");
    }

    fn renderAscii(self: *Sparkline, bounds: anytype) !void {
        if (self.data.len == 0) {
            try self.renderEmpty(bounds);
            return;
        }

        const width = self.width orelse @as(u16, @intCast(bounds.width));
        _ = self.height orelse 1; // Height not used in single-line sparkline

        // Calculate value range
        const min_max = self.calculateMinMax();
        const value_range = min_max.max - min_max.min;
        if (value_range == 0) {
            try self.renderFlatLine(width);
            return;
        }

        // ASCII characters based on mode
        const chars = switch (self.render_mode.ascii.char_set) {
            .bars => "|/-\\",
            .dots => ".oO@",
            .numbers => "0123456789",
            .letters => "abcdefghij",
        };

        // Title
        if (self.title) |title| {
            try self.writeWithColor(title, null);
            try std.io.getStdOut().writer().writeAll("\n");
        }

        // Render sparkline
        try self.writeWithColor("[", self.color);

        for (self.data, 0..) |value, i| {
            if (i >= width) break;

            const normalized = (value - min_max.min) / value_range;
            const char_index = @as(usize, @intFromFloat(std.math.clamp(normalized * @as(f64, @floatFromInt(chars.len - 1)), 0, @as(f64, @floatFromInt(chars.len - 1)))));
            const char = chars[char_index .. char_index + 1];

            try self.writeWithColor(char, self.color);
        }

        // Fill remaining width
        var remaining = width - @as(u16, @min(@as(u32, @intCast(width)), @as(u32, @intCast(self.data.len))));
        while (remaining > 0) : (remaining -= 1) {
            try self.writeWithColor("-", self.color);
        }

        try self.writeWithColor("]", self.color);

        // Trend indicator
        if (self.show_trend and self.data.len >= 2) {
            const trend = self.calculateTrend();
            const trend_char = if (trend > 0.01) "+" else if (trend < -0.01) "-" else "=";
            try std.io.getStdOut().writer().print(" {s}", .{trend_char});
        }

        try std.io.getStdOut().writer().writeAll("\n");
    }

    fn renderEmpty(self: *Sparkline, bounds: anytype) !void {
        const width = self.width orelse @as(u16, @intCast(bounds.width));

        if (self.title) |title| {
            try self.writeWithColor(title, null);
            try std.io.getStdOut().writer().writeAll("\n");
        }

        try self.writeWithColor("▕", self.color);
        var i: u16 = 0;
        while (i < width) : (i += 1) {
            try self.writeWithColor("░", self.color);
        }
        try self.writeWithColor("▏", self.color);
        try std.io.getStdOut().writer().writeAll(" (no data)\n");
    }

    fn renderFlatLine(self: *Sparkline, width: u16) !void {
        try self.writeWithColor("▕", self.color);
        var i: u16 = 0;
        while (i < width) : (i += 1) {
            try self.writeWithColor("─", self.color);
        }
        try self.writeWithColor("▏", self.color);
        try std.io.getStdOut().writer().writeAll("\n");
    }

    fn calculateMinMax(self: *const Sparkline) struct { min: f64, max: f64 } {
        if (self.min_value) |min_val| {
            if (self.max_value) |max_val| {
                return .{ .min = min_val, .max = max_val };
            }
        }

        var min_val: f64 = std.math.inf(f64);
        var max_val: f64 = -std.math.inf(f64);

        for (self.data) |value| {
            min_val = @min(min_val, value);
            max_val = @max(max_val, value);
        }

        // Use custom min/max if provided
        if (self.min_value) |custom_min| {
            min_val = custom_min;
        }
        if (self.max_value) |custom_max| {
            max_val = custom_max;
        }

        return .{ .min = min_val, .max = max_val };
    }

    fn calculateTrend(self: *const Sparkline) f64 {
        if (self.data.len < 2) return 0.0;

        const first_half = self.data[0..@max(1, self.data.len / 2)];
        const second_half = self.data[@max(1, self.data.len / 2)..];

        var first_avg: f64 = 0;
        for (first_half) |val| {
            first_avg += val;
        }
        first_avg /= @as(f64, @floatFromInt(first_half.len));

        var second_avg: f64 = 0;
        for (second_half) |val| {
            second_avg += val;
        }
        second_avg /= @as(f64, @floatFromInt(second_half.len));

        return (second_avg - first_avg) / first_avg;
    }

    fn writeWithColor(self: *const Sparkline, text: []const u8, color: ?Color) !void {
        _ = self; // Self not used but kept for consistency with other methods
        const writer = std.io.getStdOut().writer();
        const caps = term_mod.capabilities.getTermCaps();

        if (color) |c| {
            switch (c) {
                .rgb => |rgb| try term_sgr.setForegroundRgb(writer, caps, rgb.r, rgb.g, rgb.b),
                .ansi => |ansi| {
                    const color_code = @as(u16, @intFromEnum(ansi)) + 30;
                    try writer.print("\x1b[{d}m", .{color_code});
                },
                .palette => |pal| try term_sgr.setForeground256(writer, caps, pal),
            }
        }

        try writer.writeAll(text);

        if (color != null) {
            try term_sgr.resetStyle(writer, caps);
        }
    }
};

//! Progress Bar Style Implementations
//!
//! This module contains all the unique rendering styles for progress bars:
//! - ASCII, Unicode blocks, gradients, animations
//! - Sparklines, circular, charts (from CLI)
//! - Spinners, dots (from TUI)
//! - Rainbow, mosaic, graphical (from UI)

const std = @import("std");
const progress = @import("progress.zig");
const ProgressData = progress.ProgressData;
const ProgressStyle = progress.ProgressStyle;
const RenderContext = progress.RenderContext;
const Color = progress.Color;
const TermCaps = progress.TermCaps;
const ProgressUtils = progress.ProgressUtils;
const ProgressHistory = progress.ProgressHistory;

/// ASCII progress bar: [====    ] 50%
pub const AsciiStyle = struct {
    pub fn render(
        data: *const ProgressData,
        ctx: RenderContext,
        allocator: std.mem.Allocator,
    ) !void {
        const bar_width = @as(u32, @intCast(@max(10, @as(i32, @intCast(ctx.width)) -| 10))); // Reserve space for brackets and info
        const filled_chars = @as(u32, @intFromFloat(@as(f32, @floatFromInt(bar_width)) * data.value));

        // Label
        if (data.label) |label| {
            try ctx.writer.print("{s}: ", .{label});
        }

        // Progress bar
        try ctx.writer.writeAll("[");
        var i: u32 = 0;
        while (i < bar_width) : (i += 1) {
            const char = if (i < filled_chars) "=" else " ";
            try ctx.writer.writeAll(char);
        }
        try ctx.writer.writeAll("]");

        // Percentage
        if (data.show_percentage) {
            try ctx.writer.print(" {d:3.0}%", .{data.value * 100});
        }
    }

    pub fn getPreferredWidth() u32 {
        return 30;
    }

    pub fn isSupported(_: TermCaps) bool {
        return true;
    }
};

/// Unicode blocks: ████████░░░░
pub const UnicodeBlocksStyle = struct {
    pub fn render(
        data: *const ProgressData,
        ctx: RenderContext,
        allocator: std.mem.Allocator,
    ) !void {
        const bar_width = @as(u32, @intCast(@max(10, @as(i32, @intCast(ctx.width)) -| 6))); // Reserve space for info
        const filled_chars = @as(u32, @intFromFloat(@as(f32, @floatFromInt(bar_width)) * data.value));

        // Label
        if (data.label) |label| {
            try ctx.writer.print("{s}: ", .{label});
        }

        // Progress bar
        var i: u32 = 0;
        while (i < bar_width) : (i += 1) {
            const char = if (i < filled_chars) "█" else "░";
            try ctx.writer.writeAll(char);
        }

        // Percentage
        if (data.show_percentage) {
            try ctx.writer.print(" {d:3.0}%", .{data.value * 100});
        }
    }

    pub fn getPreferredWidth() u32 {
        return 30;
    }

    pub fn isSupported(caps: TermCaps) bool {
        return caps.supports_unicode;
    }
};

/// Unicode smooth transitions: ▓▓▓▓▓░░░
pub const UnicodeSmoothStyle = struct {
    pub fn render(
        data: *const ProgressData,
        ctx: RenderContext,
        allocator: std.mem.Allocator,
    ) !void {
        const bar_width = @as(u32, @intCast(@max(10, @as(i32, @intCast(ctx.width)) -| 6)));
        const filled_pixels = @as(f32, @floatFromInt(bar_width)) * data.value;

        // Label
        if (data.label) |label| {
            try ctx.writer.print("{s}: ", .{label});
        }

        // Progress bar with smooth transitions
        var i: u32 = 0;
        while (i < bar_width) : (i += 1) {
            const pos = @as(f32, @floatFromInt(i));
            var char: []const u8 = undefined;

            if (pos + 1.0 <= filled_pixels) {
                char = "█"; // Fully filled
            } else if (pos < filled_pixels) {
                const fraction = filled_pixels - pos;
                if (fraction > 0.75) {
                    char = "▓";
                } else if (fraction > 0.5) {
                    char = "▒";
                } else if (fraction > 0.25) {
                    char = "░";
                } else {
                    char = "░";
                }
            } else {
                char = "░"; // Empty
            }

            try ctx.writer.writeAll(char);
        }

        // Percentage
        if (data.show_percentage) {
            try ctx.writer.print(" {d:3.1}%", .{data.value * 100});
        }
    }

    pub fn getPreferredWidth() u32 {
        return 30;
    }

    pub fn isSupported(caps: TermCaps) bool {
        return caps.supports_unicode;
    }
};

/// Color gradient progress bar
pub const GradientStyle = struct {
    pub fn render(
        data: *const ProgressData,
        ctx: RenderContext,
        allocator: std.mem.Allocator,
    ) !void {
        if (!ctx.caps.supports_truecolor) {
            // Fallback to unicode blocks
            try UnicodeBlocksStyle.render(data, ctx, allocator);
            return;
        }

        const bar_width = @as(u32, @intCast(@max(10, @as(i32, @intCast(ctx.width)) -| 6)));
        const filled_chars = @as(u32, @intFromFloat(@as(f32, @floatFromInt(bar_width)) * data.value));

        // Label
        if (data.label) |label| {
            try ctx.writer.print("{s}: ", .{label});
        }

        // Gradient progress bar
        var i: u32 = 0;
        while (i < bar_width) : (i += 1) {
            if (i < filled_chars) {
                const pos = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(bar_width));
                const color = ProgressUtils.calculateGradientColor(pos, data.value);

                switch (color) {
                    .rgb => |rgb| try ctx.writer.print("\x1b[38;2;{d};{d};{d}m█\x1b[0m", .{ rgb.r, rgb.g, rgb.b }),
                    else => try ctx.writer.writeAll("█"),
                }
            } else {
                try ctx.writer.writeAll("░");
            }
        }

        // Percentage
        if (data.show_percentage) {
            try ctx.writer.print(" {d:3.1}%", .{data.value * 100});
        }
    }

    pub fn getPreferredWidth() u32 {
        return 30;
    }

    pub fn isSupported(caps: TermCaps) bool {
        return caps.supports_truecolor;
    }
};

/// Rainbow progress bar
pub const RainbowStyle = struct {
    pub fn render(
        data: *const ProgressData,
        ctx: RenderContext,
        allocator: std.mem.Allocator,
    ) !void {
        if (!ctx.caps.supports_truecolor) {
            try UnicodeBlocksStyle.render(data, ctx, allocator);
            return;
        }

        const bar_width = @as(u32, @intCast(@max(10, @as(i32, @intCast(ctx.width)) -| 6)));
        const filled_chars = @as(u32, @intFromFloat(@as(f32, @floatFromInt(bar_width)) * data.value));

        // Label
        if (data.label) |label| {
            try ctx.writer.print("{s}: ", .{label});
        }

        // Rainbow progress bar
        var i: u32 = 0;
        while (i < bar_width) : (i += 1) {
            if (i < filled_chars) {
                const pos = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(bar_width));
                const hue = @mod(pos * 360.0 + ctx.animation_time * 60.0, 360.0);
                const color = ProgressUtils.hsvToRgb(hue, 1.0, 1.0);

                switch (color) {
                    .rgb => |rgb| try ctx.writer.print("\x1b[38;2;{d};{d};{d}m█\x1b[0m", .{ rgb.r, rgb.g, rgb.b }),
                    else => try ctx.writer.writeAll("█"),
                }
            } else {
                try ctx.writer.writeAll("░");
            }
        }

        // Percentage
        if (data.show_percentage) {
            try ctx.writer.print(" {d:3.1}%", .{data.value * 100});
        }
    }

    pub fn getPreferredWidth() u32 {
        return 30;
    }

    pub fn isSupported(caps: TermCaps) bool {
        return caps.supports_truecolor;
    }
};

/// Animated progress bar with wave effect
pub const AnimatedStyle = struct {
    pub fn render(
        data: *const ProgressData,
        ctx: RenderContext,
        allocator: std.mem.Allocator,
    ) !void {
        const bar_width = @as(u32, @intCast(@max(10, @as(i32, @intCast(ctx.width)) -| 6)));
        const filled_chars = @as(u32, @intFromFloat(@as(f32, @floatFromInt(bar_width)) * data.value));

        // Label
        if (data.label) |label| {
            try ctx.writer.print("{s}: ", .{label});
        }

        // Animated wave effect
        const wave_pos = @as(u32, @intFromFloat(ctx.animation_time * 10.0)) % bar_width;

        var i: u32 = 0;
        while (i < bar_width) : (i += 1) {
            const is_filled = i < filled_chars;
            const is_wave = (i == wave_pos or i == (wave_pos + 1) % bar_width) and is_filled;

            if (is_wave) {
                try ctx.writer.writeAll("▓");
            } else if (is_filled) {
                try ctx.writer.writeAll("█");
            } else {
                try ctx.writer.writeAll("░");
            }
        }

        // Percentage
        if (data.show_percentage) {
            try ctx.writer.print(" {d:3.1}%", .{data.value * 100});
        }
    }

    pub fn getPreferredWidth() u32 {
        return 30;
    }

    pub fn isSupported(_: TermCaps) bool {
        return true;
    }
};

/// Sparkline progress bar
pub const SparklineStyle = struct {
    pub fn render(
        data: *const ProgressData,
        ctx: RenderContext,
        history: ?*const ProgressHistory,
        allocator: std.mem.Allocator,
    ) !void {
        if (history == null or history.?.entries.items.len < 2) {
            try UnicodeBlocksStyle.render(data, ctx, allocator);
            return;
        }

        const sparkline_chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
        const data_points = @min(ctx.width, history.?.entries.items.len);
        const start_idx = if (history.?.entries.items.len > ctx.width)
            history.?.entries.items.len - ctx.width
        else
            0;

        // Label
        if (data.label) |label| {
            try ctx.writer.print("{s}: ", .{label});
        }

        // Sparkline
        var i: u32 = 0;
        while (i < data_points) : (i += 1) {
            const data_idx = start_idx + i;
            const value = history.?.entries.items[data_idx].value;
            const spark_idx = @as(usize, @intFromFloat(value * 7.0));

            if (ctx.caps.supports_truecolor) {
                const red = @as(u8, @intFromFloat(255.0 * (1.0 - value)));
                const green = @as(u8, @intFromFloat(255.0 * value));
                try ctx.writer.print("\x1b[38;2;{d};{d};0m{s}\x1b[0m", .{ red, green, sparkline_chars[@min(spark_idx, sparkline_chars.len - 1)] });
            } else {
                try ctx.writer.writeAll(sparkline_chars[@min(spark_idx, sparkline_chars.len - 1)]);
            }
        }

        // Fill remaining width
        if (data_points < ctx.width) {
            var j: u32 = data_points;
            while (j < ctx.width) : (j += 1) {
                try ctx.writer.writeAll("░");
            }
        }

        // Percentage
        if (data.show_percentage) {
            try ctx.writer.print(" {d:3.1}%", .{data.value * 100});
        }
    }

    pub fn getPreferredWidth() u32 {
        return 40;
    }

    pub fn isSupported(caps: TermCaps) bool {
        return caps.supports_unicode;
    }
};

/// Circular progress indicator
pub const CircularStyle = struct {
    pub fn render(
        data: *const ProgressData,
        ctx: RenderContext,
        allocator: std.mem.Allocator,
    ) !void {
        const circles = [_][]const u8{ "○", "◔", "◑", "◕", "●" };
        const num_circles = @min(ctx.width / 2, 5);

        // Label
        if (data.label) |label| {
            try ctx.writer.print("{s}: ", .{label});
        }

        // Multiple circles for longer width
        var i: u32 = 0;
        while (i < num_circles) : (i += 1) {
            const circle_progress = data.value * @as(f32, @floatFromInt(num_circles)) - @as(f32, @floatFromInt(i));
            const circle_level = @as(usize, @intFromFloat(std.math.clamp(circle_progress * 4.0, 0.0, 4.0)));

            if (ctx.caps.supports_truecolor) {
                const hue = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(num_circles))) * 360.0;
                const color = ProgressUtils.hsvToRgb(hue, 0.8, 1.0);
                switch (color) {
                    .rgb => |rgb| try ctx.writer.print("\x1b[38;2;{d};{d};{d}m{s}\x1b[0m", .{ rgb.r, rgb.g, rgb.b, circles[circle_level] }),
                    else => try ctx.writer.writeAll(circles[circle_level]),
                }
            } else {
                try ctx.writer.writeAll(circles[circle_level]);
            }

            try ctx.writer.writeAll(" ");
        }

        // Percentage
        if (data.show_percentage) {
            try ctx.writer.print("{d:3.1}%", .{data.value * 100});
        }
    }

    pub fn getPreferredWidth() u32 {
        return 20;
    }

    pub fn isSupported(caps: TermCaps) bool {
        return caps.supports_unicode;
    }
};

/// Spinner with percentage
pub const SpinnerStyle = struct {
    pub fn render(
        data: *const ProgressData,
        ctx: RenderContext,
        allocator: std.mem.Allocator,
    ) !void {
        const spinner_chars = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
        const spinner_idx = @as(usize, @intFromFloat(ctx.animation_time * 10.0)) % spinner_chars.len;

        // Label
        if (data.label) |label| {
            try ctx.writer.print("{s}: ", .{label});
        }

        // Spinner
        try ctx.writer.writeAll(spinner_chars[spinner_idx]);
        try ctx.writer.writeAll(" ");

        // Percentage
        if (data.show_percentage) {
            try ctx.writer.print("{d:3.1}%", .{data.value * 100});
        }
    }

    pub fn getPreferredWidth() u32 {
        return 15;
    }

    pub fn isSupported(caps: TermCaps) bool {
        return caps.supports_unicode;
    }
};

/// Dot animation progress bar
pub const DotsStyle = struct {
    pub fn render(
        data: *const ProgressData,
        ctx: RenderContext,
        allocator: std.mem.Allocator,
    ) !void {
        const filled_dots = @as(u32, @intFromFloat(@as(f32, @floatFromInt(ctx.width)) * data.value));

        // Label
        if (data.label) |label| {
            try ctx.writer.print("{s}: ", .{label});
        }

        // Dots
        var i: u32 = 0;
        while (i < ctx.width) : (i += 1) {
            const char = if (i < filled_dots) "●" else "○";
            try ctx.writer.writeAll(char);
        }

        // Percentage
        if (data.show_percentage) {
            try ctx.writer.print(" {d:3.1}%", .{data.value * 100});
        }
    }

    pub fn getPreferredWidth() u32 {
        return 25;
    }

    pub fn isSupported(caps: TermCaps) bool {
        return caps.supports_unicode;
    }
};

/// Main style renderer that dispatches to specific style implementations
pub const StyleRenderer = struct {
    pub fn render(
        data: *const ProgressData,
        style: ProgressStyle,
        ctx: RenderContext,
        history: ?*const ProgressHistory,
        allocator: std.mem.Allocator,
    ) !void {
        switch (style) {
            .ascii => try AsciiStyle.render(data, ctx, allocator),
            .unicode_blocks => try UnicodeBlocksStyle.render(data, ctx, allocator),
            .unicode_smooth => try UnicodeSmoothStyle.render(data, ctx, allocator),
            .gradient => try GradientStyle.render(data, ctx, allocator),
            .rainbow => try RainbowStyle.render(data, ctx, allocator),
            .animated => try AnimatedStyle.render(data, ctx, allocator),
            .sparkline => try SparklineStyle.render(data, ctx, history, allocator),
            .circular => try CircularStyle.render(data, ctx, allocator),
            .spinner => try SpinnerStyle.render(data, ctx, allocator),
            .dots => try DotsStyle.render(data, ctx, allocator),
            .mosaic, .graphical, .chart_bar, .chart_line => {
                // These require more complex implementations, fallback to gradient for now
                try GradientStyle.render(data, ctx, allocator);
            },
            .auto => {
                const best_style = ProgressUtils.chooseBestStyle(ctx.caps);
                try render(data, best_style, ctx, history, allocator);
            },
        }
    }

    pub fn getPreferredWidth(style: ProgressStyle) u32 {
        return switch (style) {
            .ascii => AsciiStyle.getPreferredWidth(),
            .unicode_blocks => UnicodeBlocksStyle.getPreferredWidth(),
            .unicode_smooth => UnicodeSmoothStyle.getPreferredWidth(),
            .gradient => GradientStyle.getPreferredWidth(),
            .rainbow => RainbowStyle.getPreferredWidth(),
            .animated => AnimatedStyle.getPreferredWidth(),
            .sparkline => SparklineStyle.getPreferredWidth(),
            .circular => CircularStyle.getPreferredWidth(),
            .spinner => SpinnerStyle.getPreferredWidth(),
            .dots => DotsStyle.getPreferredWidth(),
            .mosaic, .graphical, .chart_bar, .chart_line => 40,
            .auto => 30,
        };
    }

    pub fn isSupported(style: ProgressStyle, caps: TermCaps) bool {
        return switch (style) {
            .ascii => AsciiStyle.isSupported(caps),
            .unicode_blocks => UnicodeBlocksStyle.isSupported(caps),
            .unicode_smooth => UnicodeSmoothStyle.isSupported(caps),
            .gradient => GradientStyle.isSupported(caps),
            .rainbow => RainbowStyle.isSupported(caps),
            .animated => AnimatedStyle.isSupported(caps),
            .sparkline => SparklineStyle.isSupported(caps),
            .circular => CircularStyle.isSupported(caps),
            .spinner => SpinnerStyle.isSupported(caps),
            .dots => DotsStyle.isSupported(caps),
            .mosaic => caps.supports_truecolor,
            .graphical => caps.supports_kitty_graphics or caps.supports_sixel,
            .chart_bar, .chart_line => caps.supports_unicode,
            .auto => true,
        };
    }
};</content>
</xai:function_call name="write">
<parameter name="filePath">src/shared/components/mod.zig
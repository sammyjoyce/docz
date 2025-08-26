//! Enhanced progress bar component using advanced terminal features
//! Supports multiple styles, animations, and terminal capabilities

const std = @import("std");
const term_ansi = @import("../../../term/ansi/color.zig");
const term_cursor = @import("../../../term/ansi/cursor.zig");
const term_caps = @import("../../../term/caps.zig");
const Allocator = std.mem.Allocator;

pub const ProgressBarStyle = enum {
    simple, // Basic ASCII progress bar
    unicode, // Unicode block characters
    gradient, // Color gradient effect
    animated, // Animated progress
    rainbow, // Rainbow colors
};

pub const ProgressBar = struct {
    allocator: Allocator,
    caps: term_caps.TermCaps,
    style: ProgressBarStyle,
    width: u32,
    current_progress: f32,
    label: []const u8,
    show_percentage: bool,
    show_eta: bool,
    animation_frame: u32,
    start_time: ?i64,

    pub fn init(
        allocator: Allocator,
        style: ProgressBarStyle,
        width: u32,
        label: []const u8,
    ) ProgressBar {
        return .{
            .allocator = allocator,
            .caps = term_caps.getTermCaps(),
            .style = style,
            .width = width,
            .current_progress = 0.0,
            .label = label,
            .show_percentage = true,
            .show_eta = true,
            .animation_frame = 0,
            .start_time = null,
        };
    }

    pub fn setProgress(self: *ProgressBar, progress: f32) void {
        self.current_progress = std.math.clamp(progress, 0.0, 1.0);
        if (self.start_time == null) {
            self.start_time = std.time.timestamp();
        }
    }

    pub fn configure(
        self: *ProgressBar,
        show_percentage: bool,
        show_eta: bool,
    ) void {
        self.show_percentage = show_percentage;
        self.show_eta = show_eta;
    }

    /// Render the progress bar
    pub fn render(self: *ProgressBar, writer: anytype) !void {
        self.animation_frame +%= 1;

        // Save cursor position and clear line
        try term_cursor.saveCursor(writer, self.caps);
        try writer.writeAll("\r");

        // Label
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 15);
        }
        try writer.print("{s}: ", .{self.label});

        // Progress bar based on style
        switch (self.style) {
            .simple => try self.renderSimpleBar(writer),
            .unicode => try self.renderUnicodeBar(writer),
            .gradient => try self.renderGradientBar(writer),
            .animated => try self.renderAnimatedBar(writer),
            .rainbow => try self.renderRainbowBar(writer),
        }

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
            const elapsed = std.time.timestamp() - self.start_time.?;
            const total_estimated = @as(f32, @floatFromInt(elapsed)) / self.current_progress;
            const remaining = @as(i64, @intFromFloat(total_estimated)) - elapsed;

            if (remaining > 0) {
                try writer.print(" ETA: {d}s", .{remaining});
            }
        }

        try term_ansi.resetStyle(writer, self.caps);
    }

    fn renderSimpleBar(self: *ProgressBar, writer: anytype) !void {
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
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 100, 100);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 8);
        }
        for (filled_chars..self.width) |_| {
            try writer.writeAll("-");
        }

        try term_ansi.resetStyle(writer, self.caps);
        try writer.writeAll("]");
    }

    fn renderUnicodeBar(self: *ProgressBar, writer: anytype) !void {
        const filled_chars = @as(u32, @intFromFloat(self.current_progress * @as(f32, @floatFromInt(self.width))));

        try writer.writeAll("▕");

        // Filled portion with Unicode blocks
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 50, 205, 50);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 10);
        }
        for (0..filled_chars) |_| {
            try writer.writeAll("█");
        }

        // Empty portion
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 60, 60, 60);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 8);
        }
        for (filled_chars..self.width) |_| {
            try writer.writeAll("░");
        }

        try term_ansi.resetStyle(writer, self.caps);
        try writer.writeAll("▏");
    }

    fn renderGradientBar(self: *ProgressBar, writer: anytype) !void {
        const filled_chars = @as(u32, @intFromFloat(self.current_progress * @as(f32, @floatFromInt(self.width))));

        try writer.writeAll("▕");

        // Gradient from red to green based on progress
        for (0..self.width) |i| {
            const pos = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.width));
            const is_filled = i < filled_chars;

            if (self.caps.supportsTrueColor()) {
                if (is_filled) {
                    // Gradient from red (0.0) to green (1.0)
                    const red = @as(u8, @intFromFloat(255.0 * (1.0 - pos)));
                    const green = @as(u8, @intFromFloat(255.0 * pos));
                    try term_ansi.setForegroundRgb(writer, self.caps, red, green, 0);
                } else {
                    try term_ansi.setForegroundRgb(writer, self.caps, 60, 60, 60);
                }
            } else {
                if (is_filled) {
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

        try term_ansi.resetStyle(writer, self.caps);
        try writer.writeAll("▏");
    }

    fn renderAnimatedBar(self: *ProgressBar, writer: anytype) !void {
        const filled_chars = @as(u32, @intFromFloat(self.current_progress * @as(f32, @floatFromInt(self.width))));
        const animation_pos = self.animation_frame % self.width;

        try writer.writeAll("▕");

        for (0..self.width) |i| {
            const is_filled = i < filled_chars;
            const is_wave_pos = i == animation_pos and is_filled;

            if (self.caps.supportsTrueColor()) {
                if (is_wave_pos) {
                    // Bright white for wave
                    try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
                } else if (is_filled) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 50, 205, 50);
                } else {
                    try term_ansi.setForegroundRgb(writer, self.caps, 60, 60, 60);
                }
            } else {
                if (is_wave_pos) {
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

        try term_ansi.resetStyle(writer, self.caps);
        try writer.writeAll("▏");
    }

    fn renderRainbowBar(self: *ProgressBar, writer: anytype) !void {
        const filled_chars = @as(u32, @intFromFloat(self.current_progress * @as(f32, @floatFromInt(self.width))));

        try writer.writeAll("▕");

        // Rainbow colors based on HSV color space
        for (0..self.width) |i| {
            const is_filled = i < filled_chars;

            if (self.caps.supportsTrueColor() and is_filled) {
                // HSV to RGB conversion for rainbow effect
                const hue = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.width))) * 360.0;
                const rgb = hsvToRgb(hue, 1.0, 1.0);
                try term_ansi.setForegroundRgb(writer, self.caps, rgb[0], rgb[1], rgb[2]);
            } else if (is_filled) {
                // Fallback color cycling for 256-color terminals
                const color_idx = @as(u8, @intCast((i % 6) + 9)); // Colors 9-14
                try term_ansi.setForeground256(writer, self.caps, color_idx);
            } else {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 60, 60, 60);
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

        try term_ansi.resetStyle(writer, self.caps);
        try writer.writeAll("▏");
    }

    /// Clear the progress bar from the terminal
    pub fn clear(self: *ProgressBar, writer: anytype) !void {
        try writer.writeAll("\r");

        // Calculate total line width to clear
        const total_width = self.label.len + self.width + 20; // Extra space for percentage/ETA
        for (0..total_width) |_| {
            try writer.writeAll(" ");
        }

        try writer.writeAll("\r");
    }
};

/// Convert HSV to RGB for rainbow progress bars
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

//! Minimal Unified Progress Bar Implementation
//!
//! A working minimal version of the unified progress bar system.

const std = @import("std");

/// Core progress data
pub const ProgressData = struct {
    value: f32 = 0.0,
    label: ?[]const u8 = null,
    show_percentage: bool = true,
    start_time: ?i64 = null,

    pub fn setProgress(self: *ProgressData, value: f32) void {
        self.value = std.math.clamp(value, 0.0, 1.0);
        if (self.start_time == null and value > 0.0) {
            self.start_time = std.time.timestamp();
        }
    }
};

/// Progress style enum
pub const ProgressStyle = enum {
    ascii,
    unicode,
    gradient,
    rainbow,
};

/// Terminal capabilities
pub const TermCaps = struct {
    supports_unicode: bool = false,
    supports_color: bool = false,

    pub fn detect() TermCaps {
        return .{
            .supports_unicode = true,
            .supports_color = true,
        };
    }
};

/// Simple progress renderer
pub const ProgressRenderer = struct {
    pub fn render(
        data: *const ProgressData,
        style: ProgressStyle,
        writer: anytype,
        width: u32,
        caps: TermCaps,
    ) !void {
        _ = style; // unused parameter
        _ = caps; // unused parameter
        const filled = @as(u32, @intFromFloat(data.value * @as(f32, @floatFromInt(width))));

        // Label
        if (data.label) |label| {
            try writer.print("{s}: ", .{label});
        }

        // Progress bar
        try writer.writeByte('[');
        var i: u32 = 0;
        while (i < width) : (i += 1) {
            const char = if (i < filled) '=' else ' ';
            try writer.writeByte(char);
        }
        try writer.writeByte(']');

        // Percentage
        if (data.show_percentage) {
            try writer.print(" {d:.0}%", .{data.value * 100});
        }
    }
};
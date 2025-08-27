//! CLI Adapter for Unified Progress Bar Component
//!
//! Simplified implementation that doesn't depend on external UI modules.

const std = @import("std");

// Type aliases for compatibility
pub const ProgressBarStyle = enum {
    simple,
    unicode,
    gradient,
    animated,
    rainbow,
};

/// Simplified CLI-compatible progress bar
pub const ProgressBar = struct {
    allocator: std.mem.Allocator,
    style: ProgressBarStyle,
    width: u32,
    label: []const u8,
    progress: f32,
    show_percentage: bool,
    show_eta: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        style: ProgressBarStyle,
        width: u32,
        label: []const u8,
    ) !ProgressBar {
        const label_copy = try allocator.dupe(u8, label);
        return ProgressBar{
            .allocator = allocator,
            .style = style,
            .width = width,
            .label = label_copy,
            .progress = 0.0,
            .show_percentage = true,
            .show_eta = false,
        };
    }

    pub fn deinit(self: *ProgressBar) void {
        self.allocator.free(self.label);
    }

    pub fn setProgress(self: *ProgressBar, progress: f32) void {
        self.progress = std.math.clamp(progress, 0.0, 1.0);
    }

    pub fn configure(self: *ProgressBar, show_percentage: bool, show_eta: bool) void {
        self.show_percentage = show_percentage;
        self.show_eta = show_eta;
    }

    /// Render to CLI writer
    pub fn render(self: *ProgressBar, writer: anytype) !void {
        const filled = @as(u32, @intFromFloat(self.progress * @as(f32, @floatFromInt(self.width))));
        const empty = self.width - filled;

        // Start with label if present
        if (self.label.len > 0) {
            try writer.print("{s} ", .{self.label});
        }

        // Draw progress bar
        switch (self.style) {
            .simple => {
                for (0..filled) |_| try writer.writeByte('=');
                for (0..empty) |_| try writer.writeByte(' ');
            },
            .unicode => {
                for (0..filled) |_| try writer.writeByte('█');
                for (0..empty) |_| try writer.writeByte('░');
            },
            .gradient => {
                const chars = [_]u8{ ' ', '░', '▒', '▓', '█' };
                for (0..self.width) |i| {
                    const pos = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.width));
                    const char_idx = if (pos <= self.progress)
                        @as(usize, @intFromFloat(pos * 4.0)) + 1
                    else
                        0;
                    try writer.writeByte(chars[char_idx]);
                }
            },
            .animated => {
                // Simple animation with spinner
                const spinner_chars = [_]u8{ '|', '/', '-', '\\' };
                const spinner = spinner_chars[@as(usize, @intFromFloat(std.math.floor(self.progress * 4.0))) % 4];
                try writer.writeByte(spinner);
                try writer.writeByte(' ');
                for (0..filled) |_| try writer.writeByte('=');
                for (0..empty) |_| try writer.writeByte(' ');
            },
            .rainbow => {
                // Rainbow progress bar (simplified)
                const colors = [_][]const u8{ "\x1b[31m", "\x1b[33m", "\x1b[32m", "\x1b[36m", "\x1b[34m", "\x1b[35m" };
                for (0..filled) |i| {
                    const color_idx = i % colors.len;
                    try writer.print("{s}█\x1b[0m", .{colors[color_idx]});
                }
                for (0..empty) |_| try writer.writeByte('░');
            },
        }

        // Add percentage if enabled
        if (self.show_percentage) {
            const percent = @as(u32, @intFromFloat(self.progress * 100.0));
            try writer.print(" {d}%", .{percent});
        }
    }

    pub fn clear(self: *ProgressBar, writer: anytype) !void {
        const total_width = self.width + self.label.len + 10; // Label + bar + percentage
        try writer.writeAll("\r");
        for (0..total_width) |_| {
            try writer.writeAll(" ");
        }
        try writer.writeAll("\r");
    }

    // Enhanced methods
    pub fn updateBytes(self: *ProgressBar, bytes: u64) void {
        _ = self;
        _ = bytes; // Simplified - could implement rate calculation here
    }

    pub fn setLabel(self: *ProgressBar, label: []const u8) void {
        self.allocator.free(self.label);
        self.label = self.allocator.dupe(u8, label) catch self.label;
    }

    pub fn enableRateDisplay(self: *ProgressBar, enable: bool) void {
        _ = self;
        _ = enable; // Simplified - could implement rate display here
    }

    pub fn setAnimationSpeed(self: *ProgressBar, speed: f32) void {
        _ = self;
        _ = speed; // Simplified - could use for animation timing
    }
};

// Convenience functions for common CLI usage patterns
pub fn createSimple(allocator: std.mem.Allocator, label: []const u8, width: u32) !ProgressBar {
    return ProgressBar.init(allocator, .simple, width, label);
}

pub fn createAnimated(allocator: std.mem.Allocator, label: []const u8, width: u32) !ProgressBar {
    return ProgressBar.init(allocator, .animated, width, label);
}

pub fn createRainbow(allocator: std.mem.Allocator, label: []const u8, width: u32) !ProgressBar {
    return ProgressBar.init(allocator, .rainbow, width, label);
}

/// Enhanced terminal capabilities with modern terminal features
/// This module provides improved color conversion and cursor control
/// following Zig 0.15.1 patterns and best practices.
const std = @import("std");

pub const color = @import("color.zig");
pub const cursor = @import("../control/cursor.zig");

// Re-export main types for convenience
pub const RgbColor = color.RgbColor;

pub const CursorStyle = cursor.CursorStyle;
pub const CursorController = cursor.CursorController;

// Utility functions combining color and cursor control
pub const TerminalEnhancer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TerminalEnhancer {
        return TerminalEnhancer{ .allocator = allocator };
    }

    /// Create a styled text sequence with position and color.
    pub fn styledTextAt(
        self: TerminalEnhancer,
        col: u32,
        row: u32,
        rgb_color: RgbColor,
        text: []const u8,
    ) ![]u8 {
        var result = std.ArrayListUnmanaged(u8){};
        errdefer result.deinit(self.allocator);

        // Move cursor to position
        const pos_seq = try cursor.cursorPositionString(self.allocator, row, col);
        defer self.allocator.free(pos_seq);
        try result.appendSlice(self.allocator, pos_seq);

        // Set color (simplified - would need full color sequence implementation)
        const color_seq = try std.fmt.allocPrint(self.allocator, "\x1b[38;2;{};{};{}m", .{ rgb_color.r, rgb_color.g, rgb_color.b });
        defer self.allocator.free(color_seq);
        try result.appendSlice(self.allocator, color_seq);

        // Add text
        try result.appendSlice(self.allocator, text);

        // Reset color
        try result.appendSlice(self.allocator, "\x1b[0m");

        return try result.toOwnedSlice(self.allocator);
    }

    /// Create a cursor sequence with style change at specific position.
    pub fn cursorWithStyleAt(
        self: TerminalEnhancer,
        col: u32,
        row: u32,
        style: CursorStyle,
    ) ![]u8 {
        var result = std.ArrayListUnmanaged(u8){};
        errdefer result.deinit(self.allocator);

        const pos_seq = try cursor.cursorPositionString(self.allocator, row, col);
        defer self.allocator.free(pos_seq);
        try result.appendSlice(self.allocator, pos_seq);

        const style_seq = try cursor.setCursorStyleString(self.allocator, style);
        defer self.allocator.free(style_seq);
        try result.appendSlice(self.allocator, style_seq);

        return try result.toOwnedSlice(self.allocator);
    }

    /// Batch multiple cursor operations.
    pub fn batchCursorOps(self: TerminalEnhancer, ops: []const CursorOp) ![]u8 {
        var result = std.ArrayListUnmanaged(u8){};
        errdefer result.deinit(self.allocator);

        for (ops) |op| {
            switch (op) {
                .move_to => |pos| {
                    const seq = try cursor.cursorPositionString(self.allocator, pos.row, pos.col);
                    defer self.allocator.free(seq);
                    try result.appendSlice(self.allocator, seq);
                },
                .move_by => |delta| {
                    if (delta.dx > 0) {
                        const seq = try cursor.cursorForwardString(self.allocator, @intCast(delta.dx));
                        defer self.allocator.free(seq);
                        try result.appendSlice(self.allocator, seq);
                    } else if (delta.dx < 0) {
                        const seq = try cursor.cursorBackwardString(self.allocator, @intCast(-delta.dx));
                        defer self.allocator.free(seq);
                        try result.appendSlice(self.allocator, seq);
                    }
                    if (delta.dy > 0) {
                        const seq = try cursor.cursorDownString(self.allocator, @intCast(delta.dy));
                        defer self.allocator.free(seq);
                        try result.appendSlice(self.allocator, seq);
                    } else if (delta.dy < 0) {
                        const seq = try cursor.cursorUpString(self.allocator, @intCast(-delta.dy));
                        defer self.allocator.free(seq);
                        try result.appendSlice(self.allocator, seq);
                    }
                },
                .set_style => |style| {
                    const seq = try cursor.setCursorStyleString(self.allocator, style);
                    defer self.allocator.free(seq);
                    try result.appendSlice(self.allocator, seq);
                },
                .save => {
                    try result.appendSlice(self.allocator, cursor.SAVE_CURSOR);
                },
                .restore => {
                    try result.appendSlice(self.allocator, cursor.RESTORE_CURSOR);
                },
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }
};

/// Operations that can be batched for cursor control.
pub const CursorOp = union(enum) {
    move_to: struct { col: u32, row: u32 },
    move_by: struct { dx: i32, dy: i32 },
    set_style: CursorStyle,
    save: void,
    restore: void,
};

/// Color analysis utilities with perceptual algorithms.
pub const ColorAnalysis = struct {
    /// Calculate perceptual difference between two colors.
    pub fn colorDistance(c1: RgbColor, c2: RgbColor) f32 {
        const dr = @as(f32, @floatFromInt(c1.r)) - @as(f32, @floatFromInt(c2.r));
        const dg = @as(f32, @floatFromInt(c1.g)) - @as(f32, @floatFromInt(c2.g));
        const db = @as(f32, @floatFromInt(c1.b)) - @as(f32, @floatFromInt(c2.b));

        // Perceptual weights
        const wr: f32 = 0.3;
        const wg: f32 = 0.59;
        const wb: f32 = 0.11;

        return @sqrt(wr * dr * dr + wg * dg * dg + wb * db * db);
    }

    /// Find the closest color in a palette.
    pub fn findClosestColor(target: RgbColor, palette: []const RgbColor) ?struct { RgbColor, f32 } {
        if (palette.len == 0) return null;

        var closest = palette[0];
        var min_distance = colorDistance(target, closest);

        for (palette[1..]) |rgb_color| {
            const distance = colorDistance(target, rgb_color);
            if (distance < min_distance) {
                closest = rgb_color;
                min_distance = distance;
            }
        }

        return .{ closest, min_distance };
    }

    /// Check if a color is considered "dark" (useful for theme adaptation).
    pub fn isDark(rgb_color: RgbColor) bool {
        const luminance = 0.299 * @as(f32, @floatFromInt(rgb_color.r)) +
            0.587 * @as(f32, @floatFromInt(rgb_color.g)) +
            0.114 * @as(f32, @floatFromInt(rgb_color.b));
        return luminance < 128.0;
    }

    /// Check if a color is considered "light".
    pub fn isLight(rgb_color: RgbColor) bool {
        return !isDark(rgb_color);
    }
};

test "terminal enhancer functionality" {
    const allocator = std.testing.allocator;
    const enhancer = TerminalEnhancer.init(allocator);

    // Test color analysis
    const red = RgbColor{ .r = 255, .g = 0, .b = 0 };
    const blue = RgbColor{ .r = 0, .g = 0, .b = 255 };
    const distance = ColorAnalysis.colorDistance(red, blue);
    try std.testing.expect(distance > 0);

    // Test dark/light detection
    const black = RgbColor{ .r = 0, .g = 0, .b = 0 };
    const white = RgbColor{ .r = 255, .g = 255, .b = 255 };
    try std.testing.expect(ColorAnalysis.isDark(black));
    try std.testing.expect(ColorAnalysis.isLight(white));

    // Test cursor operation batching
    const ops = [_]CursorOp{
        .save,
        .{ .move_to = .{ .col = 10, .row = 5 } },
        .{ .set_style = .steady_block },
        .restore,
    };

    const result = try enhancer.batchCursorOps(&ops);
    defer allocator.free(result);

    // Should contain all expected sequences
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b7") != null); // save
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[5;10H") != null); // move
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[2 q") != null); // style
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b8") != null); // restore
}

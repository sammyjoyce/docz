/// Enhanced terminal capabilities inspired by charmbracelet/x
/// This module provides improved color conversion and cursor control
/// following Zig 0.15.1 patterns and best practices.
const std = @import("std");

pub const enhanced_color_conversion = @import("enhanced_color_conversion.zig");
pub const enhanced_cursor_control = @import("enhanced_cursor_control.zig");

// Re-export main types for convenience
pub const Color = enhanced_color_conversion.Color;
pub const BasicColor = enhanced_color_conversion.BasicColor;
pub const IndexedColor = enhanced_color_conversion.IndexedColor;
pub const RGBColor = enhanced_color_conversion.RGBColor;
pub const RGBA = enhanced_color_conversion.RGBA;

pub const CursorStyle = enhanced_cursor_control.CursorStyle;
pub const CursorControl = enhanced_cursor_control.CursorControl;

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
        color: Color,
        text: []const u8,
    ) ![]u8 {
        var result = std.ArrayListUnmanaged(u8){};
        errdefer result.deinit(self.allocator);

        // Move cursor to position
        try result.appendSlice(self.allocator, CursorControl.cursorPosition(col, row));

        // Set color (simplified - would need full color sequence implementation)
        const indexed = enhanced_color_conversion.convert256(color);
        const color_seq = try std.fmt.allocPrint(self.allocator, "\x1b[38;5;{}m", .{indexed.value});
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

        try result.appendSlice(self.allocator, CursorControl.cursorPosition(col, row));
        try result.appendSlice(self.allocator, CursorControl.setCursorStyle(style));

        return try result.toOwnedSlice(self.allocator);
    }

    /// Batch multiple cursor operations.
    pub fn batchCursorOps(self: TerminalEnhancer, ops: []const CursorOp) ![]u8 {
        var result = std.ArrayListUnmanaged(u8){};
        errdefer result.deinit(self.allocator);

        for (ops) |op| {
            switch (op) {
                .move_to => |pos| {
                    try result.appendSlice(self.allocator, CursorControl.cursorPosition(pos.col, pos.row));
                },
                .move_by => |delta| {
                    if (delta.dx > 0) {
                        try result.appendSlice(self.allocator, CursorControl.cursorForward(@intCast(delta.dx)));
                    } else if (delta.dx < 0) {
                        try result.appendSlice(self.allocator, CursorControl.cursorBackward(@intCast(-delta.dx)));
                    }
                    if (delta.dy > 0) {
                        try result.appendSlice(self.allocator, CursorControl.cursorDown(@intCast(delta.dy)));
                    } else if (delta.dy < 0) {
                        try result.appendSlice(self.allocator, CursorControl.cursorUp(@intCast(-delta.dy)));
                    }
                },
                .set_style => |style| {
                    try result.appendSlice(self.allocator, CursorControl.setCursorStyle(style));
                },
                .save => {
                    try result.appendSlice(self.allocator, CursorControl.saveCursor);
                },
                .restore => {
                    try result.appendSlice(self.allocator, CursorControl.restoreCursor);
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

/// Color analysis utilities inspired by charmbracelet/x algorithms.
pub const ColorAnalysis = struct {
    /// Calculate perceptual difference between two colors.
    pub fn colorDistance(c1: Color, c2: Color) f32 {
        const rgba1 = c1.rgba();
        const rgba2 = c2.rgba();

        const dr = @as(f32, @floatFromInt(rgba1.r)) - @as(f32, @floatFromInt(rgba2.r));
        const dg = @as(f32, @floatFromInt(rgba1.g)) - @as(f32, @floatFromInt(rgba2.g));
        const db = @as(f32, @floatFromInt(rgba1.b)) - @as(f32, @floatFromInt(rgba2.b));

        // Perceptual weights
        const wr: f32 = 0.3;
        const wg: f32 = 0.59;
        const wb: f32 = 0.11;

        return @sqrt(wr * dr * dr + wg * dg * dg + wb * db * db);
    }

    /// Find the closest color in a palette.
    pub fn findClosestColor(target: Color, palette: []const Color) ?struct { Color, f32 } {
        if (palette.len == 0) return null;

        var closest = palette[0];
        var min_distance = colorDistance(target, closest);

        for (palette[1..]) |color| {
            const distance = colorDistance(target, color);
            if (distance < min_distance) {
                closest = color;
                min_distance = distance;
            }
        }

        return .{ closest, min_distance };
    }

    /// Check if a color is considered "dark" (useful for theme adaptation).
    pub fn isDark(color: Color) bool {
        const rgba = color.rgba();
        const luminance = 0.299 * @as(f32, @floatFromInt(rgba.r)) +
            0.587 * @as(f32, @floatFromInt(rgba.g)) +
            0.114 * @as(f32, @floatFromInt(rgba.b));
        return luminance < 128.0;
    }

    /// Check if a color is considered "light".
    pub fn isLight(color: Color) bool {
        return !isDark(color);
    }
};

test "terminal enhancer functionality" {
    const allocator = std.testing.allocator;
    const enhancer = TerminalEnhancer.init(allocator);

    // Test color analysis
    const red = Color{ .basic = .red };
    const blue = Color{ .basic = .blue };
    const distance = ColorAnalysis.colorDistance(red, blue);
    try std.testing.expect(distance > 0);

    // Test dark/light detection
    const black = Color{ .basic = .black };
    const white = Color{ .basic = .white };
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

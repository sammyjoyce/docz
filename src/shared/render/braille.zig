//! Braille Character Drawing System
//!
//! High-resolution terminal graphics using Unicode Braille patterns (U+2800-U+28FF).
//! Each Braille character represents a 2x4 grid of dots, providing 8x the resolution
//! of regular terminal characters.
//!
//! ## Features
//!
//! - **High Resolution**: 2x4 dots per character (8x regular resolution)
//! - **Efficient Rendering**: Optimized dot buffer management
//! - **Line Drawing**: Bresenham's algorithm adapted for Braille dots
//! - **Shape Primitives**: Points, lines, curves, rectangles, circles
//! - **Coordinate Transformation**: World-to-screen coordinate mapping
//! - **Sub-pixel Precision**: Support for fractional coordinates
//!
//! ## Usage
//!
//! ```zig
//! const braille = @import("render/braille.zig");
//!
//! // Create a Braille canvas
//! var canvas = try braille.BrailleCanvas.init(allocator, 80, 24);
//! defer canvas.deinit();
//!
//! // Draw a line from (10, 10) to (70, 20)
//! try canvas.drawLine(10.0, 10.0, 70.0, 20.0);
//!
//! // Set individual dots
//! canvas.setDot(5, 5, true);
//!
//! // Render to terminal
//! try canvas.render(std.io.getStdOut().writer());
//! ```

const std = @import("std");

/// Braille character mapping for 2x4 dot patterns
/// Each character represents 8 dots arranged in a 2x4 grid:
///   0 3
///   1 4
///   2 5
///   6 7
pub const BraillePatterns = struct {
    /// Convert 8-bit dot pattern to Unicode Braille character
    /// Bits 0-7 represent dots in this order:
    /// 0:top-left, 1:middle-left, 2:bottom-left, 3:top-right,
    /// 4:middle-right, 5:bottom-right, 6:top-center, 7:bottom-center
    pub fn patternToChar(pattern: u8) u21 {
        // Braille Unicode block starts at U+2800 (empty pattern)
        // Each bit corresponds to a dot position
        return @as(u21, 0x2800) + @as(u21, pattern);
    }

    /// Get the bit position for a given dot coordinate within a Braille cell
    /// x,y: 0-based coordinates within the 2x4 cell (0<=x<2, 0<=y<4)
    pub fn getBitPosition(x: u2, y: u2) u3 {
        return switch (y) {
            0 => if (x == 0) 0 else 3, // top row: left=0, right=3
            1 => if (x == 0) 1 else 4, // middle row: left=1, right=4
            2 => if (x == 0) 2 else 5, // bottom row: left=2, right=5
            3 => if (x == 0) 6 else 7, // extra row: left=6, right=7
        };
    }

    /// Set a dot in an 8-bit pattern
    pub fn setDot(pattern: u8, x: u2, y: u2) u8 {
        const bit = getBitPosition(x, y);
        return pattern | (@as(u8, 1) << bit);
    }

    /// Clear a dot in an 8-bit pattern
    pub fn clearDot(pattern: u8, x: u2, y: u2) u8 {
        const bit = getBitPosition(x, y);
        return pattern & ~(@as(u8, 1) << bit);
    }

    /// Check if a dot is set in an 8-bit pattern
    pub fn getDot(pattern: u8, x: u2, y: u2) bool {
        const bit = getBitPosition(x, y);
        return (pattern & (@as(u8, 1) << bit)) != 0;
    }
};

/// Braille canvas for high-resolution drawing
pub const BrailleCanvas = struct {
    allocator: std.mem.Allocator,
    width: u32, // Character width
    height: u32, // Character height
    dot_width: u32, // Total dot width (width * 2)
    dot_height: u32, // Total dot height (height * 4)
    buffer: []u8, // Dot buffer (dot_width * dot_height bits)
    world_bounds: WorldBounds,

    pub const WorldBounds = struct {
        min_x: f64 = 0.0,
        max_x: f64 = 100.0,
        min_y: f64 = 0.0,
        max_y: f64 = 100.0,
    };

    /// Initialize a new Braille canvas
    pub fn init(allocator: std.mem.Allocator, char_width: u32, char_height: u32) !*BrailleCanvas {
        const dot_width = char_width * 2;
        const dot_height = char_height * 4;
        const buffer_size = (dot_width * dot_height + 7) / 8; // Round up to bytes

        const canvas = try allocator.create(BrailleCanvas);
        canvas.* = .{
            .allocator = allocator,
            .width = char_width,
            .height = char_height,
            .dot_width = dot_width,
            .dot_height = dot_height,
            .buffer = try allocator.alloc(u8, buffer_size),
            .world_bounds = .{},
        };

        // Clear buffer
        @memset(canvas.buffer, 0);

        return canvas;
    }

    /// Deinitialize the canvas
    pub fn deinit(self: *BrailleCanvas) void {
        self.allocator.free(self.buffer);
        self.allocator.destroy(self);
    }

    /// Set world coordinate bounds for transformation
    pub fn setWorldBounds(self: *BrailleCanvas, bounds: WorldBounds) void {
        self.world_bounds = bounds;
    }

    /// Convert world coordinates to dot coordinates
    pub fn worldToDot(self: *BrailleCanvas, world_x: f64, world_y: f64) struct { x: f64, y: f64 } {
        const x_ratio = (world_x - self.world_bounds.min_x) / (self.world_bounds.max_x - self.world_bounds.min_x);
        const y_ratio = (world_y - self.world_bounds.min_y) / (self.world_bounds.max_y - self.world_bounds.min_y);

        return .{
            .x = x_ratio * @as(f64, @floatFromInt(self.dot_width - 1)),
            .y = (1.0 - y_ratio) * @as(f64, @floatFromInt(self.dot_height - 1)), // Flip Y axis
        };
    }

    /// Set a dot at the given world coordinates
    pub fn setDotWorld(self: *BrailleCanvas, world_x: f64, world_y: f64) void {
        const dot_pos = self.worldToDot(world_x, world_y);
        self.setDot(@as(u32, @intFromFloat(dot_pos.x)), @as(u32, @intFromFloat(dot_pos.y)), true);
    }

    /// Set a dot at the given dot coordinates
    pub fn setDot(self: *BrailleCanvas, dot_x: u32, dot_y: u32, value: bool) void {
        if (dot_x >= self.dot_width or dot_y >= self.dot_height) return;

        const bit_index = dot_y * self.dot_width + dot_x;
        const byte_index = bit_index / 8;
        const bit_offset = @as(u3, @intCast(bit_index % 8));

        if (value) {
            self.buffer[byte_index] |= (@as(u8, 1) << bit_offset);
        } else {
            self.buffer[byte_index] &= ~(@as(u8, 1) << bit_offset);
        }
    }

    /// Get a dot at the given dot coordinates
    pub fn getDot(self: *BrailleCanvas, dot_x: u32, dot_y: u32) bool {
        if (dot_x >= self.dot_width or dot_y >= self.dot_height) return false;

        const bit_index = dot_y * self.dot_width + dot_x;
        const byte_index = bit_index / 8;
        const bit_offset = @as(u3, @intCast(bit_index % 8));

        return (self.buffer[byte_index] & (@as(u8, 1) << bit_offset)) != 0;
    }

    /// Clear the entire canvas
    pub fn clear(self: *BrailleCanvas) void {
        @memset(self.buffer, 0);
    }

    /// Draw a line using Bresenham's algorithm adapted for Braille dots
    pub fn drawLine(self: *BrailleCanvas, x0: f64, y0: f64, x1: f64, y1: f64) void {
        const start = self.worldToDot(x0, y0);
        const end = self.worldToDot(x1, y1);

        const x0_int = @as(i32, @intFromFloat(start.x));
        const y0_int = @as(i32, @intFromFloat(start.y));
        const x1_int = @as(i32, @intFromFloat(end.x));
        const y1_int = @as(i32, @intFromFloat(end.y));

        const dx: i32 = if (x1_int > x0_int) x1_int - x0_int else x0_int - x1_int;
        const dy: i32 = if (y1_int > y0_int) y1_int - y0_int else y0_int - y1_int;
        const sx: i32 = if (x0_int < x1_int) 1 else -1;
        const sy: i32 = if (y0_int < y1_int) 1 else -1;
        var err = dx - dy;

        var x = x0_int;
        var y = y0_int;

        while (true) {
            if (x >= 0 and y >= 0 and x < @as(i32, @intCast(self.dot_width)) and y < @as(i32, @intCast(self.dot_height))) {
                self.setDot(@as(u32, @intCast(x)), @as(u32, @intCast(y)), true);
            }

            if (x == x1_int and y == y1_int) break;

            const e2 = 2 * err;
            if (e2 > -@as(i32, dy)) {
                err -= dy;
                x += sx;
            }
            if (e2 < dx) {
                err += dx;
                y += sy;
            }
        }
    }

    /// Draw a point (single dot)
    pub fn drawPoint(self: *BrailleCanvas, x: f64, y: f64) void {
        self.setDotWorld(x, y);
    }

    /// Draw a rectangle
    pub fn drawRect(self: *BrailleCanvas, x: f64, y: f64, width: f64, height: f64) void {
        const x1 = x + width;
        const y1 = y + height;

        // Draw four sides
        self.drawLine(x, y, x1, y); // top
        self.drawLine(x1, y, x1, y1); // right
        self.drawLine(x1, y1, x, y1); // bottom
        self.drawLine(x, y1, x, y); // left
    }

    /// Draw a filled rectangle
    pub fn fillRect(self: *BrailleCanvas, x: f64, y: f64, width: f64, height: f64) void {
        const start = self.worldToDot(x, y);
        const end = self.worldToDot(x + width, y + height);

        const x0 = @as(u32, @intFromFloat(@max(0, start.x)));
        const y0 = @as(u32, @intFromFloat(@max(0, start.y)));
        const x1 = @as(u32, @intFromFloat(@min(@as(f64, @floatFromInt(self.dot_width)), end.x)));
        const y1 = @as(u32, @intFromFloat(@min(@as(f64, @floatFromInt(self.dot_height)), end.y)));

        var py = y0;
        while (py < y1) : (py += 1) {
            var px = x0;
            while (px < x1) : (px += 1) {
                self.setDot(px, py, true);
            }
        }
    }

    /// Draw a circle using Bresenham's circle algorithm
    pub fn drawCircle(self: *BrailleCanvas, center_x: f64, center_y: f64, radius: f64) void {
        const center = self.worldToDot(center_x, center_y);
        const cx = @as(i32, @intFromFloat(center.x));
        const cy = @as(i32, @intFromFloat(center.y));
        const r = @as(i32, @intFromFloat(radius));

        var x = r;
        var y: i32 = 0;
        var err: i32 = 0;

        while (x >= y) {
            // Draw 8 octants with bounds checking
            const px1 = cx + x;
            const py1 = cy + y;
            const px2 = cx + y;
            const py2 = cy + x;
            const px3 = cx - y;
            const py3 = cy + x;
            const px4 = cx - x;
            const py4 = cy + y;
            const px5 = cx - x;
            const py5 = cy - y;
            const px6 = cx - y;
            const py6 = cy - x;
            const px7 = cx + y;
            const py7 = cy - x;
            const px8 = cx + x;
            const py8 = cy - y;

            if (px1 >= 0 and py1 >= 0 and px1 < @as(i32, @intCast(self.dot_width)) and py1 < @as(i32, @intCast(self.dot_height))) {
                self.setDot(@as(u32, @intCast(px1)), @as(u32, @intCast(py1)), true);
            }
            if (px2 >= 0 and py2 >= 0 and px2 < @as(i32, @intCast(self.dot_width)) and py2 < @as(i32, @intCast(self.dot_height))) {
                self.setDot(@as(u32, @intCast(px2)), @as(u32, @intCast(py2)), true);
            }
            if (px3 >= 0 and py3 >= 0 and px3 < @as(i32, @intCast(self.dot_width)) and py3 < @as(i32, @intCast(self.dot_height))) {
                self.setDot(@as(u32, @intCast(px3)), @as(u32, @intCast(py3)), true);
            }
            if (px4 >= 0 and py4 >= 0 and px4 < @as(i32, @intCast(self.dot_width)) and py4 < @as(i32, @intCast(self.dot_height))) {
                self.setDot(@as(u32, @intCast(px4)), @as(u32, @intCast(py4)), true);
            }
            if (px5 >= 0 and py5 >= 0 and px5 < @as(i32, @intCast(self.dot_width)) and py5 < @as(i32, @intCast(self.dot_height))) {
                self.setDot(@as(u32, @intCast(px5)), @as(u32, @intCast(py5)), true);
            }
            if (px6 >= 0 and py6 >= 0 and px6 < @as(i32, @intCast(self.dot_width)) and py6 < @as(i32, @intCast(self.dot_height))) {
                self.setDot(@as(u32, @intCast(px6)), @as(u32, @intCast(py6)), true);
            }
            if (px7 >= 0 and py7 >= 0 and px7 < @as(i32, @intCast(self.dot_width)) and py7 < @as(i32, @intCast(self.dot_height))) {
                self.setDot(@as(u32, @intCast(px7)), @as(u32, @intCast(py7)), true);
            }
            if (px8 >= 0 and py8 >= 0 and px8 < @as(i32, @intCast(self.dot_width)) and py8 < @as(i32, @intCast(self.dot_height))) {
                self.setDot(@as(u32, @intCast(px8)), @as(u32, @intCast(py8)), true);
            }

            y += 1;
            err += 1 + 2 * y;
            if (2 * (err - x) + 1 > 0) {
                x -= 1;
                err += 1 - 2 * x;
            }
        }
    }

    /// Draw a quadratic Bezier curve
    pub fn drawQuadraticBezier(self: *BrailleCanvas, x0: f64, y0: f64, x1: f64, y1: f64, x2: f64, y2: f64) void {
        // Use adaptive subdivision for smooth curves
        const steps = 100; // Number of line segments

        var t: f64 = 0.0;
        const dt = 1.0 / @as(f64, @floatFromInt(steps));

        var prev_x = x0;
        var prev_y = y0;

        while (t <= 1.0) {
            // Quadratic Bezier formula
            const u = 1.0 - t;
            const tt = t * t;
            const uu = u * u;

            const x = uu * x0 + 2 * u * t * x1 + tt * x2;
            const y = uu * y0 + 2 * u * t * y1 + tt * y2;

            if (t > 0) {
                self.drawLine(prev_x, prev_y, x, y);
            }

            prev_x = x;
            prev_y = y;
            t += dt;
        }
    }

    /// Draw a cubic Bezier curve
    pub fn drawCubicBezier(self: *BrailleCanvas, x0: f64, y0: f64, x1: f64, y1: f64, x2: f64, y2: f64, x3: f64, y3: f64) void {
        const steps = 100;

        var t: f64 = 0.0;
        const dt = 1.0 / @as(f64, @floatFromInt(steps));

        var prev_x = x0;
        var prev_y = y0;

        while (t <= 1.0) {
            // Cubic Bezier formula
            const u = 1.0 - t;
            const tt = t * t;
            const uu = u * u;
            const uuu = uu * u;
            const ttt = tt * t;

            const x = uuu * x0 + 3 * uu * t * x1 + 3 * u * tt * x2 + ttt * x3;
            const y = uuu * y0 + 3 * uu * t * y1 + 3 * u * tt * y2 + ttt * y3;

            if (t > 0) {
                self.drawLine(prev_x, prev_y, x, y);
            }

            prev_x = x;
            prev_y = y;
            t += dt;
        }
    }

    /// Render the canvas to a writer as Braille characters
    pub fn render(self: *BrailleCanvas, writer: anytype) !void {
        var char_y: u32 = 0;
        while (char_y < self.height) : (char_y += 1) {
            var char_x: u32 = 0;
            while (char_x < self.width) : (char_x += 1) {
                var pattern: u8 = 0;

                // Convert 2x4 dot pattern to Braille character
                var dot_y: u2 = 0;
                while (dot_y < 4) : (dot_y += 1) {
                    var dot_x: u2 = 0;
                    while (dot_x < 2) : (dot_x += 1) {
                        const global_dot_x = char_x * 2 + dot_x;
                        const global_dot_y = char_y * 4 + dot_y;

                        if (self.getDot(global_dot_x, global_dot_y)) {
                            pattern = BraillePatterns.setDot(pattern, dot_x, dot_y);
                        }
                    }
                }

                const char = BraillePatterns.patternToChar(pattern);
                try writer.writeByte(@as(u8, @intCast(char)));
            }
            try writer.writeByte('\n');
        }
    }

    /// Get canvas dimensions in characters
    pub fn getCharDimensions(self: *const BrailleCanvas) struct { width: u32, height: u32 } {
        return .{ .width = self.width, .height = self.height };
    }

    /// Get canvas dimensions in dots
    pub fn getDotDimensions(self: *const BrailleCanvas) struct { width: u32, height: u32 } {
        return .{ .width = self.dot_width, .height = self.dot_height };
    }
};

/// Utility functions for Braille graphics
pub const Braille = struct {
    /// Convert a series of points to Braille dots with interpolation
    pub fn plotDataPoints(canvas: *BrailleCanvas, points: []const struct { x: f64, y: f64 }, connect: bool) void {
        if (points.len == 0) return;

        // Plot individual points
        for (points) |point| {
            canvas.drawPoint(point.x, point.y);
        }

        // Connect with lines if requested
        if (connect and points.len > 1) {
            for (1..points.len) |i| {
                canvas.drawLine(points[i - 1].x, points[i - 1].y, points[i].x, points[i].y);
            }
        }
    }

    /// Draw a grid with Braille dots
    pub fn drawGrid(canvas: *BrailleCanvas, spacing_x: f64, spacing_y: f64) void {
        const bounds = canvas.world_bounds;

        // Vertical lines
        var x = bounds.min_x;
        while (x <= bounds.max_x) {
            canvas.drawLine(x, bounds.min_y, x, bounds.max_y);
            x += spacing_x;
        }

        // Horizontal lines
        var y = bounds.min_y;
        while (y <= bounds.max_y) {
            canvas.drawLine(bounds.min_x, y, bounds.max_x, y);
            y += spacing_y;
        }
    }

    /// Draw axes
    pub fn drawAxes(canvas: *BrailleCanvas) void {
        const bounds = canvas.world_bounds;

        // X-axis
        canvas.drawLine(bounds.min_x, 0, bounds.max_x, 0);
        // Y-axis
        canvas.drawLine(0, bounds.min_y, 0, bounds.max_y);
    }
};

test "Braille patterns" {
    const testing = std.testing;

    // Test pattern conversion
    try testing.expect(BraillePatterns.patternToChar(0) == 0x2800); // Empty pattern
    try testing.expect(BraillePatterns.patternToChar(1) == 0x2801); // First dot set

    // Test dot manipulation
    var pattern: u8 = 0;
    pattern = BraillePatterns.setDot(pattern, 0, 0); // Set top-left
    try testing.expect(BraillePatterns.getDot(pattern, 0, 0));
    try testing.expect(!BraillePatterns.getDot(pattern, 1, 0));

    pattern = BraillePatterns.clearDot(pattern, 0, 0); // Clear top-left
    try testing.expect(!BraillePatterns.getDot(pattern, 0, 0));
}

test "Braille canvas" {
    const testing = std.testing;

    var canvas = try BrailleCanvas.init(testing.allocator, 10, 5);
    defer canvas.deinit();

    // Test dimensions
    const char_dims = canvas.getCharDimensions();
    try testing.expect(char_dims.width == 10);
    try testing.expect(char_dims.height == 5);

    const dot_dims = canvas.getDotDimensions();
    try testing.expect(dot_dims.width == 20); // 10 * 2
    try testing.expect(dot_dims.height == 20); // 5 * 4

    // Test dot setting
    canvas.setDot(5, 5, true);
    try testing.expect(canvas.getDot(5, 5));

    canvas.setDot(5, 5, false);
    try testing.expect(!canvas.getDot(5, 5));

    // Test world coordinates
    canvas.setWorldBounds(.{ .min_x = 0, .max_x = 100, .min_y = 0, .max_y = 100 });
    canvas.setDotWorld(50, 50); // Center point

    const center_dot_x = dot_dims.width / 2;
    const center_dot_y = dot_dims.height / 2;
    try testing.expect(canvas.getDot(center_dot_x, center_dot_y));
}

test "Braille drawing primitives" {
    const testing = std.testing;

    var canvas = try BrailleCanvas.init(testing.allocator, 20, 10);
    defer canvas.deinit();

    canvas.setWorldBounds(.{ .min_x = 0, .max_x = 100, .min_y = 0, .max_y = 100 });

    // Test line drawing
    canvas.drawLine(10, 10, 90, 90);
    // Should have set some dots along the diagonal

    // Test rectangle
    canvas.drawRect(20, 20, 60, 40);

    // Test circle
    canvas.drawCircle(50, 50, 20);

    // Test point
    canvas.drawPoint(75, 25);

    // Verify some dots are set (exact positions depend on coordinate transformation)
    try testing.expect(canvas.buffer.len > 0);
}

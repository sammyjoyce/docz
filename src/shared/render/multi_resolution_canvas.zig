//! Unified multi-resolution canvas API that seamlessly switches between different
//! resolution modes (Braille, HalfBlock, FullBlock, Character) through a single interface.
//! Inspired by Ratatui's multi-resolution canvas system.

const std = @import("std");
const BrailleCanvas = @import("braille.zig").BrailleCanvas;
// UnicodeImageRenderer is not implemented yet, so we'll handle block rendering directly
// const UnicodeImageRenderer = @import("../term/unicode_image_renderer.zig");

// Use the existing modules that are available via the term module
const Color = @import("term_shared").ansi.color.Color;

/// Resolution modes for the canvas, ordered from highest to lowest fidelity
pub const ResolutionMode = enum {
    /// Braille characters - 2x4 dots per cell (8x resolution)
    braille,
    /// Half blocks - 1x2 blocks per cell (2x vertical resolution)
    half_block,
    /// Full blocks - 1x1 block per cell
    full_block,
    /// ASCII characters - basic text characters
    character,
    /// Automatic selection based on terminal capabilities
    auto,

    /// Get the effective resolution multiplier for this mode
    pub fn getResolution(self: ResolutionMode) struct { x: u32, y: u32 } {
        return switch (self) {
            .braille => .{ .x = 2, .y = 4 },
            .half_block => .{ .x = 1, .y = 2 },
            .full_block => .{ .x = 1, .y = 1 },
            .character => .{ .x = 1, .y = 1 },
            .auto => .{ .x = 1, .y = 1 }, // Will be determined at runtime
        };
    }

    /// Select the best resolution mode based on terminal capabilities
    pub fn selectBest(unicode_support: bool) ResolutionMode {
        // Braille is universally supported in Unicode terminals
        if (unicode_support) {
            return .braille;
        }
        // Fall back to ASCII for limited terminals
        return .character;
    }
};

/// Point in canvas coordinates (floating point for sub-pixel precision)
pub const Point = struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Point {
        return .{ .x = x, .y = y };
    }
};

/// Rectangle in canvas coordinates
pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn init(x: f32, y: f32, width: f32, height: f32) Rect {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn contains(self: Rect, point: Point) bool {
        return point.x >= self.x and point.x < self.x + self.width and
            point.y >= self.y and point.y < self.y + self.height;
    }
};

/// Drawing style configuration
pub const Style = struct {
    /// Foreground color (null for default)
    fg_color: ?Color = null,
    /// Background color (null for default)
    bg_color: ?Color = null,
    /// Line style for drawing operations
    line_style: LineStyle = .solid,
    /// Fill pattern for area operations
    fill_pattern: FillPattern = .solid,
};

/// Line styles for drawing operations
pub const LineStyle = enum {
    solid,
    dashed,
    dotted,
    double,
};

/// Fill patterns for area operations
pub const FillPattern = enum {
    solid,
    horizontal_lines,
    vertical_lines,
    diagonal_lines,
    cross_hatch,
    dots,
};

/// Unified multi-resolution canvas
pub const MultiResolutionCanvas = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    resolution_mode: ResolutionMode,
    current_style: Style,

    // Backend implementations
    braille_canvas: ?BrailleCanvas,
    block_buffer: ?[][]u8,
    char_buffer: ?[][]u8,

    const Self = @This();

    /// Initialize a new multi-resolution canvas
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, mode: ResolutionMode) !Self {
        // For now, just use the mode directly or default to braille if auto
        const effective_mode = if (mode == .auto)
            ResolutionMode.braille
        else
            mode;

        var self = Self{
            .allocator = allocator,
            .width = width,
            .height = height,
            .resolution_mode = effective_mode,
            .current_style = Style{},
            .braille_canvas = null,
            .block_buffer = null,
            .char_buffer = null,
        };

        // Initialize appropriate backend
        try self.initBackend();

        return self;
    }

    /// Initialize the appropriate backend based on resolution mode
    fn initBackend(self: *Self) !void {
        switch (self.resolution_mode) {
            .braille => {
                self.braille_canvas = try BrailleCanvas.init(self.allocator, self.width, self.height);
            },
            .half_block, .full_block => {
                self.block_buffer = try self.allocator.alloc([]u8, self.height);
                for (self.block_buffer.?) |*row| {
                    row.* = try self.allocator.alloc(u8, self.width);
                    @memset(row.*, ' ');
                }
            },
            .character => {
                self.char_buffer = try self.allocator.alloc([]u8, self.height);
                for (self.char_buffer.?) |*row| {
                    row.* = try self.allocator.alloc(u8, self.width);
                    @memset(row.*, ' ');
                }
            },
            .auto => unreachable, // Should be resolved in init
        }
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        if (self.braille_canvas) |*canvas| {
            canvas.deinit();
        }
        if (self.block_buffer) |buffer| {
            for (buffer) |row| {
                self.allocator.free(row);
            }
            self.allocator.free(buffer);
        }
        if (self.char_buffer) |buffer| {
            for (buffer) |row| {
                self.allocator.free(row);
            }
            self.allocator.free(buffer);
        }
    }

    /// Set the current drawing style
    pub fn setStyle(self: *Self, style: Style) void {
        self.current_style = style;
    }

    /// Clear the canvas
    pub fn clear(self: *Self) void {
        switch (self.resolution_mode) {
            .braille => if (self.braille_canvas) |*canvas| canvas.clear(),
            .half_block, .full_block => {
                if (self.block_buffer) |buffer| {
                    for (buffer) |row| {
                        @memset(row, ' ');
                    }
                }
            },
            .character => {
                if (self.char_buffer) |buffer| {
                    for (buffer) |row| {
                        @memset(row, ' ');
                    }
                }
            },
            .auto => unreachable,
        }
    }

    /// Set a pixel at the given coordinates
    pub fn setPixel(self: *Self, x: f32, y: f32) !void {
        switch (self.resolution_mode) {
            .braille => {
                if (self.braille_canvas) |*canvas| {
                    try canvas.setDot(@intFromFloat(x * 2), @intFromFloat(y * 4));
                }
            },
            .half_block => {
                if (self.block_buffer) |buffer| {
                    const cx = @as(u32, @intFromFloat(x));
                    const cy = @as(u32, @intFromFloat(y * 2));
                    if (cx < self.width and cy < self.height * 2) {
                        const row = cy / 2;
                        const is_upper = cy % 2 == 0;
                        const current = buffer[row][cx];

                        buffer[row][cx] = if (is_upper) {
                            if (current == ' ') '▀' else if (current == '▄') '█' else current;
                        } else {
                            if (current == ' ') '▄' else if (current == '▀') '█' else current;
                        };
                    }
                }
            },
            .full_block => {
                if (self.block_buffer) |buffer| {
                    const cx = @as(u32, @intFromFloat(x));
                    const cy = @as(u32, @intFromFloat(y));
                    if (cx < self.width and cy < self.height) {
                        buffer[cy][cx] = '█';
                    }
                }
            },
            .character => {
                if (self.char_buffer) |buffer| {
                    const cx = @as(u32, @intFromFloat(x));
                    const cy = @as(u32, @intFromFloat(y));
                    if (cx < self.width and cy < self.height) {
                        buffer[cy][cx] = '*';
                    }
                }
            },
            .auto => unreachable,
        }
    }

    /// Draw a line between two points
    pub fn drawLine(self: *Self, start: Point, end: Point) !void {
        switch (self.resolution_mode) {
            .braille => {
                if (self.braille_canvas) |*canvas| {
                    try canvas.drawLine(start.x * 2, start.y * 4, end.x * 2, end.y * 4);
                }
            },
            else => {
                // Bresenham's line algorithm for other modes
                try self.drawLineBresenham(start, end);
            },
        }
    }

    /// Bresenham's line algorithm for non-Braille modes
    fn drawLineBresenham(self: *Self, start: Point, end: Point) !void {
        const resolution = self.resolution_mode.getResolution();

        var x0 = @as(i32, @intFromFloat(start.x * @as(f32, @floatFromInt(resolution.x))));
        var y0 = @as(i32, @intFromFloat(start.y * @as(f32, @floatFromInt(resolution.y))));
        const x1 = @as(i32, @intFromFloat(end.x * @as(f32, @floatFromInt(resolution.x))));
        const y1 = @as(i32, @intFromFloat(end.y * @as(f32, @floatFromInt(resolution.y))));

        const dx = @abs(x1 - x0);
        const dy = @abs(y1 - y0);
        const sx: i32 = if (x0 < x1) 1 else -1;
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err = dx - dy;

        while (true) {
            try self.setPixel(@as(f32, @floatFromInt(x0)) / @as(f32, @floatFromInt(resolution.x)), @as(f32, @floatFromInt(y0)) / @as(f32, @floatFromInt(resolution.y)));

            if (x0 == x1 and y0 == y1) break;

            const e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                x0 += sx;
            }
            if (e2 < dx) {
                err += dx;
                y0 += sy;
            }
        }
    }

    /// Draw a rectangle
    pub fn drawRect(self: *Self, rect: Rect) !void {
        const tl = Point.init(rect.x, rect.y);
        const tr = Point.init(rect.x + rect.width, rect.y);
        const bl = Point.init(rect.x, rect.y + rect.height);
        const br = Point.init(rect.x + rect.width, rect.y + rect.height);

        try self.drawLine(tl, tr);
        try self.drawLine(tr, br);
        try self.drawLine(br, bl);
        try self.drawLine(bl, tl);
    }

    /// Fill a rectangle
    pub fn fillRect(self: *Self, rect: Rect) !void {
        switch (self.resolution_mode) {
            .braille => {
                if (self.braille_canvas) |*canvas| {
                    try canvas.drawRect(rect.x * 2, rect.y * 4, rect.width * 2, rect.height * 4);
                }
            },
            else => {
                // Fill row by row
                var y = rect.y;
                while (y < rect.y + rect.height) : (y += 1) {
                    try self.drawLine(Point.init(rect.x, y), Point.init(rect.x + rect.width, y));
                }
            },
        }
    }

    /// Draw a circle
    pub fn drawCircle(self: *Self, center: Point, radius: f32) !void {
        switch (self.resolution_mode) {
            .braille => {
                if (self.braille_canvas) |*canvas| {
                    try canvas.drawCircle(center.x * 2, center.y * 4, radius * 2);
                }
            },
            else => {
                // Midpoint circle algorithm
                try self.drawCircleMidpoint(center, radius);
            },
        }
    }

    /// Midpoint circle algorithm for non-Braille modes
    fn drawCircleMidpoint(self: *Self, center: Point, radius: f32) !void {
        const resolution = self.resolution_mode.getResolution();
        const rx = radius * @as(f32, @floatFromInt(resolution.x));
        _ = radius * @as(f32, @floatFromInt(resolution.y)); // ry not needed for circle

        var x: i32 = @intFromFloat(rx);
        var y: i32 = 0;
        var p: i32 = 1 - x;

        while (x >= y) {
            // Draw 8 octants
            const points = [_]Point{
                Point.init(center.x + @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(resolution.x)), center.y + @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(resolution.y))),
                Point.init(center.x - @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(resolution.x)), center.y + @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(resolution.y))),
                Point.init(center.x + @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(resolution.x)), center.y - @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(resolution.y))),
                Point.init(center.x - @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(resolution.x)), center.y - @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(resolution.y))),
                Point.init(center.x + @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(resolution.x)), center.y + @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(resolution.y))),
                Point.init(center.x - @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(resolution.x)), center.y + @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(resolution.y))),
                Point.init(center.x + @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(resolution.x)), center.y - @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(resolution.y))),
                Point.init(center.x - @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(resolution.x)), center.y - @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(resolution.y))),
            };

            for (points) |point| {
                try self.setPixel(point.x, point.y);
            }

            y += 1;
            if (p < 0) {
                p += 2 * y + 1;
            } else {
                x -= 1;
                p += 2 * (y - x) + 1;
            }
        }
    }

    /// Draw text at the specified position (character mode only)
    pub fn drawText(self: *Self, text: []const u8, pos: Point) !void {
        if (self.resolution_mode != .character and self.resolution_mode != .full_block) {
            return; // Text only works in character modes
        }

        if (self.char_buffer) |buffer| {
            const x = @as(u32, @intFromFloat(pos.x));
            const y = @as(u32, @intFromFloat(pos.y));

            if (y < self.height) {
                var i: u32 = 0;
                for (text) |char| {
                    if (x + i < self.width) {
                        buffer[y][x + i] = char;
                        i += 1;
                    } else {
                        break;
                    }
                }
            }
        }
    }

    /// Render the canvas to a writer
    pub fn render(self: *Self, writer: anytype) !void {
        switch (self.resolution_mode) {
            .braille => {
                if (self.braille_canvas) |*canvas| {
                    try canvas.render(writer);
                }
            },
            .half_block, .full_block => {
                if (self.block_buffer) |buffer| {
                    for (buffer) |row| {
                        try writer.writeAll(row);
                        try writer.writeByte('\n');
                    }
                }
            },
            .character => {
                if (self.char_buffer) |buffer| {
                    for (buffer) |row| {
                        try writer.writeAll(row);
                        try writer.writeByte('\n');
                    }
                }
            },
            .auto => unreachable,
        }
    }

    /// Get a string representation of the canvas
    pub fn toString(self: *Self) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        try self.render(buffer.writer());
        return buffer.toOwnedSlice();
    }

    /// Get the effective resolution of the canvas
    pub fn getEffectiveResolution(self: Self) struct { width: u32, height: u32 } {
        const res = self.resolution_mode.getResolution();
        return .{
            .width = self.width * res.x,
            .height = self.height * res.y,
        };
    }

    /// Convert canvas coordinates to terminal cell coordinates
    pub fn toTerminalCoords(_: Self, point: Point) struct { x: u32, y: u32 } {
        return .{
            .x = @intFromFloat(point.x),
            .y = @intFromFloat(point.y),
        };
    }

    /// Convert terminal cell coordinates to canvas coordinates
    pub fn fromTerminalCoords(self: Self, x: u32, y: u32) Point {
        _ = self;
        return Point.init(@floatFromInt(x), @floatFromInt(y));
    }
};

// Tests
test "MultiResolutionCanvas initialization" {
    const allocator = std.testing.allocator;

    var canvas = try MultiResolutionCanvas.init(allocator, 80, 24, .braille);
    defer canvas.deinit();

    try std.testing.expectEqual(@as(u32, 80), canvas.width);
    try std.testing.expectEqual(@as(u32, 24), canvas.height);
}

test "MultiResolutionCanvas drawing operations" {
    const allocator = std.testing.allocator;

    var canvas = try MultiResolutionCanvas.init(allocator, 40, 20, .half_block);
    defer canvas.deinit();

    // Test pixel setting
    try canvas.setPixel(10, 10);

    // Test line drawing
    try canvas.drawLine(Point.init(0, 0), Point.init(20, 10));

    // Test rectangle
    try canvas.drawRect(Rect.init(5, 5, 10, 10));

    // Test circle
    try canvas.drawCircle(Point.init(20, 10), 5);

    // Verify canvas can render
    const output = try canvas.toString();
    defer allocator.free(output);
    try std.testing.expect(output.len > 0);
}

test "MultiResolutionCanvas resolution modes" {
    const allocator = std.testing.allocator;

    const modes = [_]ResolutionMode{ .braille, .half_block, .full_block, .character };

    for (modes) |mode| {
        var canvas = try MultiResolutionCanvas.init(allocator, 20, 10, mode);
        defer canvas.deinit();

        // Each mode should support basic operations
        canvas.clear();
        try canvas.setPixel(5, 5);
        try canvas.drawLine(Point.init(0, 0), Point.init(10, 5));

        const output = try canvas.toString();
        defer allocator.free(output);
        try std.testing.expect(output.len > 0);
    }
}

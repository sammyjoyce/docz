//! Geometric bounds and positioning for TUI components
const std = @import("std");

/// Rectangular bounds for components
pub const Bounds = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,

    pub fn init(x: u32, y: u32, width: u32, height: u32) Bounds {
        return Bounds{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn contains(self: Bounds, x: u32, y: u32) bool {
        return x >= self.x and x < self.x + self.width and
            y >= self.y and y < self.y + self.height;
    }

    pub fn containsPoint(self: Bounds, point: Point) bool {
        return self.contains(point.x, point.y);
    }

    pub fn intersects(self: Bounds, other: Bounds) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }

    pub fn clamp(self: Bounds, other: Bounds) Bounds {
        const x1 = @max(self.x, other.x);
        const y1 = @max(self.y, other.y);
        const x2 = @min(self.x + self.width, other.x + other.width);
        const y2 = @min(self.y + self.height, other.y + other.height);

        return Bounds{
            .x = x1,
            .y = y1,
            .width = if (x2 > x1) x2 - x1 else 0,
            .height = if (y2 > y1) y2 - y1 else 0,
        };
    }

    pub fn center(self: Bounds) Point {
        return Point{
            .x = self.x + self.width / 2,
            .y = self.y + self.height / 2,
        };
    }

    pub fn area(self: Bounds) u32 {
        return self.width * self.height;
    }

    pub fn isEmpty(self: Bounds) bool {
        return self.width == 0 or self.height == 0;
    }
};

/// Point in 2D space
pub const Point = struct {
    x: u32,
    y: u32,

    pub fn init(x: u32, y: u32) Point {
        return Point{ .x = x, .y = y };
    }

    pub fn distance(self: Point, other: Point) f32 {
        const dx = @as(f32, @floatFromInt(if (self.x > other.x) self.x - other.x else other.x - self.x));
        const dy = @as(f32, @floatFromInt(if (self.y > other.y) self.y - other.y else other.y - self.y));
        return @sqrt(dx * dx + dy * dy);
    }

    pub fn add(self: Point, other: Point) Point {
        return Point{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    pub fn subtract(self: Point, other: Point) Point {
        return Point{
            .x = if (self.x > other.x) self.x - other.x else 0,
            .y = if (self.y > other.y) self.y - other.y else 0,
        };
    }
};

/// Terminal size information
pub const TerminalSize = struct {
    width: u32,
    height: u32,

    pub fn init(width: u32, height: u32) TerminalSize {
        return TerminalSize{ .width = width, .height = height };
    }

    pub fn toBounds(self: TerminalSize) Bounds {
        return Bounds.init(0, 0, self.width, self.height);
    }
};

/// Get current terminal size
pub fn getTerminalSize() TerminalSize {
    // Try to get actual terminal size
    var winsize: std.os.linux.winsize = undefined;
    if (std.os.linux.ioctl(std.os.STDOUT_FILENO, std.os.linux.T.IOCGWINSZ, @intFromPtr(&winsize)) == 0) {
        return TerminalSize.init(winsize.ws_col, winsize.ws_row);
    }

    // Fallback to standard size
    return TerminalSize.init(80, 24);
}

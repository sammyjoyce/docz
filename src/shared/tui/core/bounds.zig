//! Geometric bounds and positioning for TUI components
//! Types for bounds and points

const std = @import("std");

// Point in 2D space with u32 coordinates (for screen/cell coordinates)
pub const Point = struct {
    x: u32,
    y: u32,

    pub fn init(x: u32, y: u32) Point {
        return Point{ .x = x, .y = y };
    }
};

// Rectangular bounds with u32 coordinates (for screen/cell coordinates)
pub const Bounds = struct {
    x: u32,
    y: u32,
    width: u32,
    height: u32,

    pub fn init(x: u32, y: u32, width: u32, height: u32) Bounds {
        return Bounds{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }
};

// Rectangular bounds with i16/u16 coordinates (for rendering coordinates)
pub const BoundsI16 = struct {
    x: i16,
    y: i16,
    width: u16,
    height: u16,

    pub fn init(x: i16, y: i16, width: u16, height: u16) BoundsI16 {
        return BoundsI16{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
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

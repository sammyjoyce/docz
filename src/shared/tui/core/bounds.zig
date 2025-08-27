//! Geometric bounds and positioning for TUI components
//! Re-exports types from the shared types module

const std = @import("std");

// Re-export types for backward compatibility
pub const Bounds = @import("../../types.zig").BoundsU32;
pub const Point = @import("../../types.zig").PointU32;

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

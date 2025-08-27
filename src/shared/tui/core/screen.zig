//! Screen management and rendering for TUI components
//! Re-exports unified screen functionality from term module

const std = @import("std");
const terminal_screen = @import("../components/terminal_screen.zig");
const Bounds = @import("bounds.zig").Bounds;

// Re-export unified screen functionality
pub const Control = terminal_screen.Control;
pub const Screen = terminal_screen.Screen;
pub const Component = terminal_screen.Component;

// Re-export screen functions with debug.print for TUI compatibility
pub fn clearScreen() void {
    std.debug.print(Control.CLEAR_SCREEN);
    std.debug.print(Control.CURSOR_HOME);
}

pub fn moveCursor(row: u32, col: u32) void {
    std.debug.print("\x1b[{d};{d}H", .{ row + 1, col + 1 });
}

pub fn clearLines(count: u32) void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        std.debug.print(Control.CLEAR_LINE);
        if (i < count - 1) {
            std.debug.print("\n");
        }
    }
}

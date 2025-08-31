//! Screen Component - High-level wrapper for terminal screen functionality
//! Provides a clean, higher-level API for screen management operations
//! Wraps term/screen.zig functionality with additional convenience methods

const std = @import("std");
const term_screen = @import("../term/screen.zig");

/// Re-export screen types for convenience
pub const Control = term_screen.Control;
pub const Bounds = @import("../types.zig").BoundsU32;
pub const Component = term_screen.Component;
pub const Screen = term_screen.Screen;
pub const TermCaps = term_screen.TermCaps;

// ANSI-specific helpers removed from components to avoid direct dependency.

/// Terminal provides high-level terminal screen functionality
/// Wraps the low-level term/screen.zig with additional convenience methods
pub const Terminal = struct {
    const Self = @This();
    /// Clear the entire screen
    pub fn clear() void {
        writeControlSequence(Control.CLEAR_SCREEN);
        writeControlSequence(Control.CURSOR_HOME);
    }

    /// Clear the current line
    pub fn clearLine() void {
        writeControlSequence(Control.CLEAR_LINE);
    }

    /// Move cursor to home position (1,1)
    pub fn home() void {
        writeControlSequence(Control.CURSOR_HOME);
    }

    /// Save cursor position
    pub fn saveCursor() void {
        writeControlSequence(Control.SAVE_CURSOR);
    }

    /// Restore cursor position
    pub fn restoreCursor() void {
        writeControlSequence(Control.RESTORE_CURSOR);
    }

    /// Request cursor position report
    pub fn requestCursorPosition() void {
        writeControlSequence(Control.REQUEST_CURSOR_POSITION);
    }

    /// Create a new bounds rectangle
    pub fn createBounds(x: u32, y: u32, width: u32, height: u32) Bounds {
        return Bounds.init(x, y, width, height);
    }

    /// Check if bounds are empty
    pub fn isBoundsEmpty(bounds: Bounds) bool {
        return bounds.isEmpty();
    }

    /// Check if two bounds rectangles intersect
    pub fn boundsIntersect(a: Bounds, b: Bounds) bool {
        return a.intersects(b);
    }

    /// Clamp one bounds rectangle to another
    pub fn clampBounds(target: Bounds, clampTo: Bounds) Bounds {
        return target.clamp(clampTo);
    }

    /// Create a screen component
    pub fn createComponent(id: []const u8, bounds: Bounds, zIndex: i32) Component {
        return Component{
            .id = id,
            .bounds = bounds,
            .content = "",
            .visible = true,
            .dirty = true,
            .zIndex = zIndex,
        };
    }

    /// Create a screen with default settings
    pub fn createScreen(allocator: std.mem.Allocator, width: u32, height: u32, caps: TermCaps) Screen {
        return Screen.init(allocator, width, height, caps);
    }

    /// Clear screen and move cursor to home (convenience function)
    pub fn clearAndHome() void {
        Terminal.clear();
        Terminal.home();
    }

    /// Clear from cursor to end of screen
    pub fn clearToEnd() void {
        writeControlSequence("\x1b[0J");
    }

    /// Clear from cursor to start of screen
    pub fn clearToStart() void {
        writeControlSequence("\x1b[1J");
    }

    /// Clear entire screen (alternative method)
    pub fn clearAll() void {
        writeControlSequence("\x1b[2J");
    }

    /// Clear from cursor to end of line
    pub fn clearLineToEnd() void {
        writeControlSequence("\x1b[0K");
    }

    /// Clear from cursor to start of line
    pub fn clearLineToStart() void {
        writeControlSequence("\x1b[1K");
    }

    /// Clear entire line
    pub fn clearEntireLine() void {
        writeControlSequence("\x1b[2K");
    }

    /// Scroll up by n lines
    pub fn scrollUp(n: u32) void {
        if (n == 1) {
            writeControlSequence("\x1bM");
        } else {
            writeFormattedSequence("\x1b[{d}S", .{n});
        }
    }

    /// Scroll down by n lines
    pub fn scrollDown(n: u32) void {
        if (n == 1) {
            writeControlSequence("\x1bD");
        } else {
            writeFormattedSequence("\x1b[{d}T", .{n});
        }
    }

    /// Set scroll region
    pub fn setScrollRegion(top: u32, bottom: u32) void {
        writeFormattedSequence("\x1b[{d};{d}r", .{ top, bottom });
    }

    /// Reset scroll region to full screen
    pub fn resetScrollRegion() void {
        writeControlSequence("\x1b[r");
    }

    /// Move cursor to specific position
    pub fn moveCursor(row: u32, col: u32) void {
        if (row == 1 and col == 1) {
            Terminal.home();
        } else {
            writeFormattedSequence("\x1b[{d};{d}H", .{ row, col });
        }
    }

    /// Move cursor up by n lines
    pub fn moveCursorUp(n: u32) void {
        if (n == 1) {
            writeControlSequence("\x1b[A");
        } else {
            writeFormattedSequence("\x1b[{d}A", .{n});
        }
    }

    /// Move cursor down by n lines
    pub fn moveCursorDown(n: u32) void {
        if (n == 1) {
            writeControlSequence("\x1b[B");
        } else {
            writeFormattedSequence("\x1b[{d}B", .{n});
        }
    }

    /// Move cursor right by n columns
    pub fn moveCursorRight(n: u32) void {
        if (n == 1) {
            writeControlSequence("\x1b[C");
        } else {
            writeFormattedSequence("\x1b[{d}C", .{n});
        }
    }

    /// Move cursor left by n columns
    pub fn moveCursorLeft(n: u32) void {
        if (n == 1) {
            writeControlSequence("\x1b[D");
        } else {
            writeFormattedSequence("\x1b[{d}D", .{n});
        }
    }

    /// Hide cursor
    pub fn hideCursor() void {
        writeControlSequence("\x1b[?25l");
    }

    /// Show cursor
    pub fn showCursor() void {
        writeControlSequence("\x1b[?25h");
    }

    /// Save screen contents
    pub fn saveScreen() void {
        writeControlSequence("\x1b[?47h");
    }

    /// Restore screen contents
    pub fn restoreScreen() void {
        writeControlSequence("\x1b[?47l");
    }

    /// Enable alternative screen buffer
    pub fn enableAltScreen() void {
        writeControlSequence("\x1b[?1049h");
    }

    /// Disable alternative screen buffer
    pub fn disableAltScreen() void {
        writeControlSequence("\x1b[?1049l");
    }

    /// Set window title
    pub fn setTitle(title: []const u8) void {
        writeControlSequence("\x1b]0;");
        writeString(title);
        writeControlSequence("\x07");
    }

    /// Set background color
    pub fn setBackgroundColor(colorCode: u8) void {
        writeFormattedSequence("\x1b[{d}m", .{colorCode + 10});
    }

    /// Set foreground color
    pub fn setForegroundColor(colorCode: u8) void {
        writeFormattedSequence("\x1b[{d}m", .{colorCode});
    }

    /// Reset all text attributes
    pub fn resetAttributes() void {
        writeControlSequence("\x1b[0m");
    }

    /// Enable bold text
    pub fn enableBold() void {
        writeControlSequence("\x1b[1m");
    }

    /// Disable bold text
    pub fn disableBold() void {
        writeControlSequence("\x1b[22m");
    }

    /// Enable underline
    pub fn enableUnderline() void {
        writeControlSequence("\x1b[4m");
    }

    /// Disable underline
    pub fn disableUnderline() void {
        writeControlSequence("\x1b[24m");
    }

    /// Enable reverse video
    pub fn enableReverse() void {
        writeControlSequence("\x1b[7m");
    }

    /// Disable reverse video
    pub fn disableReverse() void {
        writeControlSequence("\x1b[27m");
    }

    /// Helper function to write control sequence
    fn writeControlSequence(sequence: []const u8) void {
        std.io.getStdOut().writeAll(sequence) catch {};
    }

    /// Helper function to write formatted control sequence
    fn writeFormattedSequence(comptime fmt: []const u8, args: anytype) void {
        std.io.getStdOut().writer().print(fmt, args) catch {};
    }

    /// Helper function to write string
    fn writeString(str: []const u8) void {
        std.io.getStdOut().writeAll(str) catch {};
    }
};

// Convenience functions for global screen operations
pub const clear = Terminal.clear;
pub const clearLine = Terminal.clearLine;
pub const home = Terminal.home;
pub const saveCursor = Terminal.saveCursor;
pub const restoreCursor = Terminal.restoreCursor;
pub const requestCursorPosition = Terminal.requestCursorPosition;
pub const createBounds = Terminal.createBounds;
pub const isBoundsEmpty = Terminal.isBoundsEmpty;
pub const boundsIntersect = Terminal.boundsIntersect;
pub const clampBounds = Terminal.clampBounds;
pub const createComponent = Terminal.createComponent;
pub const createScreen = Terminal.createScreen;
pub const clearAndHome = Terminal.clearAndHome;
pub const clearToEnd = Terminal.clearToEnd;
pub const clearToStart = Terminal.clearToStart;
pub const clearAll = Terminal.clearAll;
pub const clearLineToEnd = Terminal.clearLineToEnd;
pub const clearLineToStart = Terminal.clearLineToStart;
pub const clearEntireLine = Terminal.clearEntireLine;
pub const scrollUp = Terminal.scrollUp;
pub const scrollDown = Terminal.scrollDown;
pub const setScrollRegion = Terminal.setScrollRegion;
pub const resetScrollRegion = Terminal.resetScrollRegion;
pub const moveCursor = Terminal.moveCursor;
pub const moveCursorUp = Terminal.moveCursorUp;
pub const moveCursorDown = Terminal.moveCursorDown;
pub const moveCursorRight = Terminal.moveCursorRight;
pub const moveCursorLeft = Terminal.moveCursorLeft;
pub const hideCursor = Terminal.hideCursor;
pub const showCursor = Terminal.showCursor;
pub const saveScreen = Terminal.saveScreen;
pub const restoreScreen = Terminal.restoreScreen;
pub const enableAltScreen = Terminal.enableAltScreen;
pub const disableAltScreen = Terminal.disableAltScreen;
pub const setTitle = Terminal.setTitle;
pub const setBackgroundColor = Terminal.setBackgroundColor;
pub const setForegroundColor = Terminal.setForegroundColor;
pub const resetAttributes = Terminal.resetAttributes;
pub const enableBold = Terminal.enableBold;
pub const disableBold = Terminal.disableBold;
pub const enableUnderline = Terminal.enableUnderline;
pub const disableUnderline = Terminal.disableUnderline;
pub const enableReverse = Terminal.enableReverse;
pub const disableReverse = Terminal.disableReverse;

// Tests
test "Terminal functionality" {
    // Test screen clearing
    Terminal.clear();
    Terminal.clearLine();
    Terminal.clearAndHome();

    // Test cursor movement
    Terminal.home();
    Terminal.moveCursor(5, 10);
    Terminal.moveCursorUp(2);
    Terminal.moveCursorDown(1);
    Terminal.moveCursorLeft(3);
    Terminal.moveCursorRight(4);

    // Test cursor visibility
    Terminal.hideCursor();
    Terminal.showCursor();

    // Test cursor position management
    Terminal.saveCursor();
    Terminal.restoreCursor();

    // Test scrolling
    Terminal.scrollUp(1);
    Terminal.scrollDown(2);

    // Test scroll region
    Terminal.setScrollRegion(1, 10);
    Terminal.resetScrollRegion();

    // Test bounds operations
    const bounds1 = Terminal.createBounds(0, 0, 10, 10);
    const bounds2 = Terminal.createBounds(5, 5, 10, 10);
    _ = Terminal.isBoundsEmpty(bounds1);
    _ = Terminal.boundsIntersect(bounds1, bounds2);
    _ = Terminal.clampBounds(bounds1, bounds2);

    // Test text attributes
    Terminal.setForegroundColor(31); // Red
    Terminal.setBackgroundColor(44); // Blue background
    Terminal.resetAttributes();
    Terminal.enableBold();
    Terminal.disableBold();
    Terminal.enableUnderline();
    Terminal.disableUnderline();
    Terminal.enableReverse();
    Terminal.disableReverse();
}

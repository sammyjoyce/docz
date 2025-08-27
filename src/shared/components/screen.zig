//! Terminal Screen Component - High-level wrapper for terminal screen functionality
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

/// TerminalScreen provides high-level terminal screen functionality
/// Wraps the low-level term/screen.zig with additional convenience methods
pub const TerminalScreen = struct {
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
    pub fn clampBounds(target: Bounds, clamp_to: Bounds) Bounds {
        return target.clamp(clamp_to);
    }

    /// Create a screen component
    pub fn createComponent(id: []const u8, bounds: Bounds, z_index: i32) Component {
        return Component{
            .id = id,
            .bounds = bounds,
            .content = "",
            .visible = true,
            .dirty = true,
            .zIndex = z_index,
        };
    }

    /// Create a screen with default settings
    pub fn createScreen(allocator: std.mem.Allocator, width: u32, height: u32, caps: TermCaps) Screen {
        return Screen.init(allocator, width, height, caps);
    }

    /// Clear screen and move cursor to home (convenience function)
    pub fn clearAndHome() void {
        TerminalScreen.clear();
        TerminalScreen.home();
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
            TerminalScreen.home();
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
    pub fn setBackgroundColor(color_code: u8) void {
        writeFormattedSequence("\x1b[{d}m", .{color_code + 10});
    }

    /// Set foreground color
    pub fn setForegroundColor(color_code: u8) void {
        writeFormattedSequence("\x1b[{d}m", .{color_code});
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
pub const clear = TerminalScreen.clear;
pub const clearLine = TerminalScreen.clearLine;
pub const home = TerminalScreen.home;
pub const saveCursor = TerminalScreen.saveCursor;
pub const restoreCursor = TerminalScreen.restoreCursor;
pub const requestCursorPosition = TerminalScreen.requestCursorPosition;
pub const createBounds = TerminalScreen.createBounds;
pub const isBoundsEmpty = TerminalScreen.isBoundsEmpty;
pub const boundsIntersect = TerminalScreen.boundsIntersect;
pub const clampBounds = TerminalScreen.clampBounds;
pub const createComponent = TerminalScreen.createComponent;
pub const createScreen = TerminalScreen.createScreen;
pub const clearAndHome = TerminalScreen.clearAndHome;
pub const clearToEnd = TerminalScreen.clearToEnd;
pub const clearToStart = TerminalScreen.clearToStart;
pub const clearAll = TerminalScreen.clearAll;
pub const clearLineToEnd = TerminalScreen.clearLineToEnd;
pub const clearLineToStart = TerminalScreen.clearLineToStart;
pub const clearEntireLine = TerminalScreen.clearEntireLine;
pub const scrollUp = TerminalScreen.scrollUp;
pub const scrollDown = TerminalScreen.scrollDown;
pub const setScrollRegion = TerminalScreen.setScrollRegion;
pub const resetScrollRegion = TerminalScreen.resetScrollRegion;
pub const moveCursor = TerminalScreen.moveCursor;
pub const moveCursorUp = TerminalScreen.moveCursorUp;
pub const moveCursorDown = TerminalScreen.moveCursorDown;
pub const moveCursorRight = TerminalScreen.moveCursorRight;
pub const moveCursorLeft = TerminalScreen.moveCursorLeft;
pub const hideCursor = TerminalScreen.hideCursor;
pub const showCursor = TerminalScreen.showCursor;
pub const saveScreen = TerminalScreen.saveScreen;
pub const restoreScreen = TerminalScreen.restoreScreen;
pub const enableAltScreen = TerminalScreen.enableAltScreen;
pub const disableAltScreen = TerminalScreen.disableAltScreen;
pub const setTitle = TerminalScreen.setTitle;
pub const setBackgroundColor = TerminalScreen.setBackgroundColor;
pub const setForegroundColor = TerminalScreen.setForegroundColor;
pub const resetAttributes = TerminalScreen.resetAttributes;
pub const enableBold = TerminalScreen.enableBold;
pub const disableBold = TerminalScreen.disableBold;
pub const enableUnderline = TerminalScreen.enableUnderline;
pub const disableUnderline = TerminalScreen.disableUnderline;
pub const enableReverse = TerminalScreen.enableReverse;
pub const disableReverse = TerminalScreen.disableReverse;

// Tests
test "TerminalScreen basic functionality" {
    // Test screen clearing
    TerminalScreen.clear();
    TerminalScreen.clearLine();
    TerminalScreen.clearAndHome();

    // Test cursor movement
    TerminalScreen.home();
    TerminalScreen.moveCursor(5, 10);
    TerminalScreen.moveCursorUp(2);
    TerminalScreen.moveCursorDown(1);
    TerminalScreen.moveCursorLeft(3);
    TerminalScreen.moveCursorRight(4);

    // Test cursor visibility
    TerminalScreen.hideCursor();
    TerminalScreen.showCursor();

    // Test cursor position management
    TerminalScreen.saveCursor();
    TerminalScreen.restoreCursor();

    // Test scrolling
    TerminalScreen.scrollUp(1);
    TerminalScreen.scrollDown(2);

    // Test scroll region
    TerminalScreen.setScrollRegion(1, 10);
    TerminalScreen.resetScrollRegion();

    // Test bounds operations
    const bounds1 = TerminalScreen.createBounds(0, 0, 10, 10);
    const bounds2 = TerminalScreen.createBounds(5, 5, 10, 10);
    _ = TerminalScreen.isBoundsEmpty(bounds1);
    _ = TerminalScreen.boundsIntersect(bounds1, bounds2);
    _ = TerminalScreen.clampBounds(bounds1, bounds2);

    // Test text attributes
    TerminalScreen.setForegroundColor(31); // Red
    TerminalScreen.setBackgroundColor(44); // Blue background
    TerminalScreen.resetAttributes();
    TerminalScreen.enableBold();
    TerminalScreen.disableBold();
    TerminalScreen.enableUnderline();
    TerminalScreen.disableUnderline();
    TerminalScreen.enableReverse();
    TerminalScreen.disableReverse();
}

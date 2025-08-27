//! Terminal Cursor Component - High-level wrapper for terminal cursor functionality
//! Provides a clean, higher-level API for cursor control operations
//! Wraps term/ansi/cursor.zig functionality with additional convenience methods

const std = @import("std");
const term_cursor = @import("term_shared").cursor;

/// Re-export cursor style for convenience
pub const CursorStyle = term_cursor.CursorStyle;

/// TerminalCursor provides high-level terminal cursor functionality
/// Wraps the low-level term/ansi/cursor.zig with additional convenience methods
pub const TerminalCursor = struct {
    /// Move cursor up by n lines
    pub fn moveUp(n: u32) void {
        if (n == 1) {
            write("\x1b[A");
        } else {
            print("\x1b[{d}A", .{n});
        }
    }

    /// Move cursor down by n lines
    pub fn moveDown(n: u32) void {
        if (n == 1) {
            write("\x1b[B");
        } else {
            print("\x1b[{d}B", .{n});
        }
    }

    /// Move cursor right by n columns
    pub fn moveRight(n: u32) void {
        if (n == 1) {
            write("\x1b[C");
        } else {
            print("\x1b[{d}C", .{n});
        }
    }

    /// Move cursor left by n columns
    pub fn moveLeft(n: u32) void {
        if (n == 1) {
            write("\x1b[D");
        } else {
            print("\x1b[{d}D", .{n});
        }
    }

    /// Move cursor to next line (same column)
    pub fn nextLine(n: u32) void {
        if (n == 1) {
            write("\x1b[E");
        } else {
            print("\x1b[{d}E", .{n});
        }
    }

    /// Move cursor to previous line (same column)
    pub fn previousLine(n: u32) void {
        if (n == 1) {
            write("\x1b[F");
        } else {
            print("\x1b[{d}F", .{n});
        }
    }

    /// Move cursor to specific column on current line
    pub fn moveToColumn(col: u32) void {
        print("\x1b[{d}G", .{col});
    }

    /// Move cursor to specific position (row, col) - 1-based
    pub fn moveTo(row: u32, col: u32) void {
        if (row == 1 and col == 1) {
            write("\x1b[H");
        } else {
            print("\x1b[{d};{d}H", .{ row, col });
        }
    }

    /// Move cursor to home position (1, 1)
    pub fn home() void {
        write("\x1b[H");
    }

    /// Save current cursor position
    pub fn savePosition() void {
        write("\x1b7");
    }

    /// Restore saved cursor position
    pub fn restorePosition() void {
        write("\x1b8");
    }

    /// Save current cursor position (alternative method)
    pub fn savePositionAlt() void {
        write("\x1b[s");
    }

    /// Restore saved cursor position (alternative method)
    pub fn restorePositionAlt() void {
        write("\x1b[u");
    }

    /// Move cursor to beginning of next line
    pub fn carriageReturn() void {
        write("\r");
    }

    /// Move cursor to beginning of current line
    pub fn lineStart() void {
        write("\r");
    }

    /// Move cursor to beginning of line n lines up
    pub fn lineUp(n: u32) void {
        TerminalCursor.moveUp(n);
        lineStart();
    }

    /// Move cursor to beginning of line n lines down
    pub fn lineDown(n: u32) void {
        TerminalCursor.moveDown(n);
        lineStart();
    }

    /// Hide cursor
    pub fn hide() void {
        write("\x1b[?25l");
    }

    /// Show cursor
    pub fn show() void {
        write("\x1b[?25h");
    }

    /// Set cursor style
    pub fn setStyle(style: CursorStyle) void {
        print("\x1b[{d} q", .{@intFromEnum(style)});
    }

    /// Set cursor to blinking block
    pub fn blinkingBlock() void {
        TerminalCursor.setStyle(.blinking_block);
    }

    /// Set cursor to steady block
    pub fn steadyBlock() void {
        TerminalCursor.setStyle(.steady_block);
    }

    /// Set cursor to blinking underline
    pub fn blinkingUnderline() void {
        TerminalCursor.setStyle(.blinking_underline);
    }

    /// Set cursor to steady underline
    pub fn steadyUnderline() void {
        TerminalCursor.setStyle(.steady_underline);
    }

    /// Set cursor to blinking bar
    pub fn blinkingBar() void {
        TerminalCursor.setStyle(.blinking_bar);
    }

    /// Set cursor to steady bar
    pub fn steadyBar() void {
        TerminalCursor.setStyle(.steady_bar);
    }

    /// Move cursor with relative coordinates from current position
    pub fn moveRelative(row_delta: i32, col_delta: i32) void {
        if (row_delta > 0) {
            TerminalCursor.moveDown(@intCast(row_delta));
        } else if (row_delta < 0) {
            TerminalCursor.moveUp(@intCast(-row_delta));
        }

        if (col_delta > 0) {
            TerminalCursor.moveRight(@intCast(col_delta));
        } else if (col_delta < 0) {
            TerminalCursor.moveLeft(@intCast(-col_delta));
        }
    }

    /// Move cursor to a position relative to current position
    pub fn moveBy(delta_row: i32, delta_col: i32) void {
        moveRelative(delta_row, delta_col);
    }

    /// Get current cursor position (requests it from terminal)
    pub fn requestPosition() void {
        write("\x1b[6n");
    }

    /// Clear from cursor to end of line
    pub fn clearToEndOfLine() void {
        write("\x1b[0K");
    }

    /// Clear from cursor to start of line
    pub fn clearToStartOfLine() void {
        write("\x1b[1K");
    }

    /// Clear entire line
    pub fn clearLine() void {
        write("\x1b[2K");
    }

    /// Clear from cursor to end of screen
    pub fn clearToEndOfScreen() void {
        write("\x1b[0J");
    }

    /// Clear from cursor to start of screen
    pub fn clearToStartOfScreen() void {
        write("\x1b[1J");
    }

    /// Clear entire screen
    pub fn clearScreen() void {
        write("\x1b[2J");
    }

    /// Clear screen and move cursor to home
    pub fn clearScreenAndHome() void {
        write("\x1b[2J\x1b[H");
    }

    /// Scroll up by n lines
    pub fn scrollUp(n: u32) void {
        if (n == 1) {
            write("\x1bM");
        } else {
            print("\x1b[{d}S", .{n});
        }
    }

    /// Scroll down by n lines
    pub fn scrollDown(n: u32) void {
        if (n == 1) {
            write("\x1bD");
        } else {
            print("\x1b[{d}T", .{n});
        }
    }

    /// Set scroll region (top to bottom inclusive)
    pub fn setScrollRegion(top: u32, bottom: u32) void {
        print("\x1b[{d};{d}r", .{ top, bottom });
    }

    /// Reset scroll region to full screen
    pub fn resetScrollRegion() void {
        write("\x1b[r");
    }

    /// Insert n blank lines at cursor position
    pub fn insertLines(n: u32) void {
        if (n == 1) {
            write("\x1b[L");
        } else {
            print("\x1b[{d}L", .{n});
        }
    }

    /// Delete n lines at cursor position
    pub fn deleteLines(n: u32) void {
        if (n == 1) {
            write("\x1b[M");
        } else {
            print("\x1b[{d}M", .{n});
        }
    }

    /// Insert n blank characters at cursor position
    pub fn insertChars(n: u32) void {
        if (n == 1) {
            write("\x1b[@");
        } else {
            print("\x1b[{d}@", .{n});
        }
    }

    /// Delete n characters at cursor position
    pub fn deleteChars(n: u32) void {
        if (n == 1) {
            write("\x1b[P");
        } else {
            print("\x1b[{d}P", .{n});
        }
    }

    /// Erase n characters starting at cursor position
    pub fn eraseChars(n: u32) void {
        if (n == 1) {
            write("\x1b[X");
        } else {
            print("\x1b[{d}X", .{n});
        }
    }

    /// Move cursor to next tab stop
    pub fn nextTab() void {
        write("\x1b[I");
    }

    /// Move cursor to previous tab stop
    pub fn previousTab() void {
        write("\x1b[Z");
    }

    /// Set tab stop at current column
    pub fn setTabStop() void {
        write("\x1bH");
    }

    /// Clear tab stop at current column
    pub fn clearTabStop() void {
        write("\x1b[0g");
    }

    /// Clear all tab stops
    pub fn clearAllTabStops() void {
        write("\x1b[3g");
    }

    /// Helper function to write string directly
    fn write(str: []const u8) void {
        std.io.getStdOut().writeAll(str) catch {};
    }

    /// Helper function to print formatted string
    fn print(comptime fmt: []const u8, args: anytype) void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        stdout_writer.print(fmt, args) catch {};
        stdout_writer.flush() catch {};
    }
};

// Convenience functions for global cursor operations
pub const moveUp = TerminalCursor.moveUp;
pub const moveDown = TerminalCursor.moveDown;
pub const moveLeft = TerminalCursor.moveLeft;
pub const moveRight = TerminalCursor.moveRight;
pub const moveTo = TerminalCursor.moveTo;
pub const home = TerminalCursor.home;
pub const hide = TerminalCursor.hide;
pub const show = TerminalCursor.show;
pub const savePosition = TerminalCursor.savePosition;
pub const restorePosition = TerminalCursor.restorePosition;
pub const clearLine = TerminalCursor.clearLine;
pub const clearScreen = TerminalCursor.clearScreen;
pub const setStyle = TerminalCursor.setStyle;

// Tests
test "TerminalCursor basic functionality" {
    // Test cursor movement
    TerminalCursor.moveTo(5, 10);
    TerminalCursor.moveUp(2);
    TerminalCursor.moveDown(1);
    TerminalCursor.moveLeft(3);
    TerminalCursor.moveRight(4);
    TerminalCursor.home();

    // Test cursor visibility
    TerminalCursor.hide();
    TerminalCursor.show();

    // Test cursor styles
    TerminalCursor.blinkingBlock();
    TerminalCursor.steadyBlock();
    TerminalCursor.blinkingUnderline();
    TerminalCursor.steadyUnderline();

    // Test position management
    TerminalCursor.savePosition();
    TerminalCursor.restorePosition();

    // Test screen clearing
    TerminalCursor.clearLine();
    TerminalCursor.clearScreen();

    // Test relative movement
    TerminalCursor.moveRelative(2, -1);
    TerminalCursor.moveBy(-1, 3);
}

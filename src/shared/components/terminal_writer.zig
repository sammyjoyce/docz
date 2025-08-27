//! Terminal Writer Component - High-level wrapper for terminal output functionality
//! Provides a clean, higher-level API for terminal writing operations
//! Wraps term/writer.zig functionality with additional convenience methods

const std = @import("std");
const term_writer = @import("term_shared").writer;

/// TerminalWriter provides high-level terminal output functionality
/// Wraps the low-level term/writer.zig with additional convenience methods
pub const TerminalWriter = struct {
    /// Initialize the global terminal writer
    pub fn init() void {
        term_writer.Writer.init();
    }

    /// Deinitialize the global terminal writer
    pub fn deinit() void {
        term_writer.Writer.deinit();
    }

    /// Print formatted text to stdout
    pub fn print(comptime fmt: []const u8, args: anytype) void {
        term_writer.print(fmt, args);
    }

    /// Print text to stdout
    pub fn write(text: []const u8) void {
        term_writer.Writer.writeAll(text);
    }

    /// Print a single character to stdout
    pub fn writeChar(char: u8) void {
        term_writer.print("{c}", .{char});
    }

    /// Print a newline
    pub fn writeLine() void {
        term_writer.print("\n", .{});
    }

    /// Print text followed by a newline
    pub fn writeLineText(text: []const u8) void {
        term_writer.print("{s}\n", .{text});
    }

    /// Print formatted text followed by a newline
    pub fn printLine(comptime fmt: []const u8, args: anytype) void {
        term_writer.print(fmt ++ "\n", args);
    }

    /// Print a horizontal line of the specified character and length
    pub fn printHorizontalLine(char: u8, length: usize) void {
        var i: usize = 0;
        while (i < length) : (i += 1) {
            term_writer.print("{c}", .{char});
        }
    }

    /// Print a box of characters with specified dimensions
    pub fn printBox(width: usize, height: usize, border_char: u8, fill_char: ?u8) void {
        var y: usize = 0;
        while (y < height) : (y += 1) {
            var x: usize = 0;
            while (x < width) : (x += 1) {
                const char = if (y == 0 or y == height - 1 or x == 0 or x == width - 1)
                    border_char
                else if (fill_char) |fill|
                    fill
                else
                    ' ';
                term_writer.print("{c}", .{char});
            }
            if (y < height - 1) {
                term_writer.print("\n", .{});
            }
        }
    }

    /// Print centered text within a specified width
    pub fn printCentered(text: []const u8, width: usize) void {
        if (text.len >= width) {
            term_writer.print("{s}", .{text});
            return;
        }

        const padding = (width - text.len) / 2;
        var i: usize = 0;
        while (i < padding) : (i += 1) {
            term_writer.print(" ", .{});
        }
        term_writer.print("{s}", .{text});
        i = 0;
        while (i < width - text.len - padding) : (i += 1) {
            term_writer.print(" ", .{});
        }
    }

    /// Print text with left/right padding to fill a specified width
    pub fn printPadded(text: []const u8, width: usize, left_pad: usize, right_pad: usize) void {
        _ = left_pad; // Parameter reserved for future use
        _ = right_pad; // Parameter reserved for future use

        const total_padding = width - text.len;
        if (total_padding > 0) {
            const actual_left = total_padding / 2;
            const actual_right = total_padding - actual_left;

            for (0..actual_left) |_| {
                term_writer.print(" ", .{});
            }
            term_writer.print("{s}", .{text});
            for (0..actual_right) |_| {
                term_writer.print(" ", .{});
            }
        } else {
            term_writer.print("{s}", .{text});
        }
    }

    /// Print a progress bar
    pub fn printProgressBar(current: usize, total: usize, width: usize, filled_char: u8, empty_char: u8) void {
        if (total == 0) return;

        const percentage = @as(f64, @floatFromInt(current)) / @as(f64, @floatFromInt(total));
        const filled_width = @as(usize, @intFromFloat(percentage * @as(f64, @floatFromInt(width))));

        term_writer.print("[", .{});
        var i: usize = 0;
        while (i < width) : (i += 1) {
            if (i < filled_width) {
                term_writer.print("{c}", .{filled_char});
            } else {
                term_writer.print("{c}", .{empty_char});
            }
        }
        term_writer.print("]", .{});
    }

    /// Print with ANSI color codes
    pub fn printColored(comptime fmt: []const u8, args: anytype, color_code: u8) void {
        term_writer.print("\x1b[{d}m", .{color_code});
        term_writer.print(fmt, args);
        term_writer.print("\x1b[0m", .{});
    }

    /// Print with ANSI background color
    pub fn printWithBackground(comptime fmt: []const u8, args: anytype, bg_color_code: u8) void {
        term_writer.print("\x1b[{d}m", .{bg_color_code + 10});
        term_writer.print(fmt, args);
        term_writer.print("\x1b[0m", .{});
    }

    /// Print with both foreground and background colors
    pub fn printColoredWithBackground(comptime fmt: []const u8, args: anytype, fg_color: u8, bg_color: u8) void {
        term_writer.print("\x1b[{d};{d}m", .{ fg_color, bg_color + 10 });
        term_writer.print(fmt, args);
        term_writer.print("\x1b[0m", .{});
    }

    /// Clear the current line
    pub fn clearLine() void {
        term_writer.print("\x1b[2K", .{});
    }

    /// Clear from cursor to end of line
    pub fn clearToEndOfLine() void {
        term_writer.print("\x1b[0K", .{});
    }

    /// Clear from cursor to start of line
    pub fn clearToStartOfLine() void {
        term_writer.print("\x1b[1K", .{});
    }

    /// Clear the entire screen
    pub fn clearScreen() void {
        term_writer.print("\x1b[2J\x1b[H", .{});
    }

    /// Move cursor to home position (1,1)
    pub fn moveCursorHome() void {
        term_writer.print("\x1b[H", .{});
    }

    /// Move cursor to specific position (1-based)
    pub fn moveCursor(row: u32, col: u32) void {
        term_writer.print("\x1b[{d};{d}H", .{ row, col });
    }

    /// Save cursor position
    pub fn saveCursor() void {
        term_writer.print("\x1b7", .{});
    }

    /// Restore cursor position
    pub fn restoreCursor() void {
        term_writer.print("\x1b8", .{});
    }

    /// Hide cursor
    pub fn hideCursor() void {
        term_writer.print("\x1b[?25l", .{});
    }

    /// Show cursor
    pub fn showCursor() void {
        term_writer.print("\x1b[?25h", .{});
    }

    /// Flush the output
    pub fn flush() void {
        term_writer.Writer.flush();
    }
};

// Convenience functions for global writer instance
pub const print = TerminalWriter.print;
pub const write = TerminalWriter.write;
pub const writeChar = TerminalWriter.writeChar;
pub const writeLine = TerminalWriter.writeLine;
pub const writeLineText = TerminalWriter.writeLineText;
pub const printLine = TerminalWriter.printLine;
pub const printHorizontalLine = TerminalWriter.printHorizontalLine;
pub const printBox = TerminalWriter.printBox;
pub const printCentered = TerminalWriter.printCentered;
pub const printPadded = TerminalWriter.printPadded;
pub const printProgressBar = TerminalWriter.printProgressBar;
pub const printColored = TerminalWriter.printColored;
pub const printWithBackground = TerminalWriter.printWithBackground;
pub const printColoredWithBackground = TerminalWriter.printColoredWithBackground;
pub const clearLine = TerminalWriter.clearLine;
pub const clearToEndOfLine = TerminalWriter.clearToEndOfLine;
pub const clearToStartOfLine = TerminalWriter.clearToStartOfLine;
pub const clearScreen = TerminalWriter.clearScreen;
pub const moveCursorHome = TerminalWriter.moveCursorHome;
pub const moveCursor = TerminalWriter.moveCursor;
pub const saveCursor = TerminalWriter.saveCursor;
pub const restoreCursor = TerminalWriter.restoreCursor;
pub const hideCursor = TerminalWriter.hideCursor;
pub const showCursor = TerminalWriter.showCursor;
pub const flush = TerminalWriter.flush;

// Tests
test "TerminalWriter basic functionality" {
    // Initialize writer for testing
    TerminalWriter.init();
    defer TerminalWriter.deinit();

    // Test basic printing functions
    TerminalWriter.print("Hello", .{});
    TerminalWriter.write(" World");
    TerminalWriter.writeChar('!');
    TerminalWriter.writeLine();
    TerminalWriter.printLine("Test: {d}", .{42});
    TerminalWriter.writeLineText("Done");

    // Test utility functions
    TerminalWriter.printHorizontalLine('-', 10);
    TerminalWriter.writeLine();

    TerminalWriter.printCentered("Center", 10);
    TerminalWriter.writeLine();

    TerminalWriter.printProgressBar(5, 10, 20, '#', '-');
    TerminalWriter.writeLine();

    // Test color functions
    TerminalWriter.printColored("Red Text", .{}, 31);
    TerminalWriter.writeLine();

    TerminalWriter.printWithBackground("Background", .{}, 41);
    TerminalWriter.writeLine();

    // Test cursor functions
    TerminalWriter.saveCursor();
    TerminalWriter.moveCursor(5, 5);
    TerminalWriter.restoreCursor();
}

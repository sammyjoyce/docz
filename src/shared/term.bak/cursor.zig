//! Cursor System - High-Level API
//!
//! This module provides an interface for cursor control, combining
//! both output (cursor movement/styling) and input (position reports) functionality.
//!
//! Architecture:
//! - Output: control/cursor.zig (ANSI escape sequences, movement, styling)
//! - Input: input/cursor.zig (cursor position report parsing)
//! - High-level: THIS FILE (API that uses both)

const std = @import("std");
const control_cursor = @import("control/cursor.zig");
const input_cursor = @import("input/cursor.zig");
const writer_mod = @import("writer.zig");
const reader_mod = @import("reader.zig");

// ============================================================================
// RE-EXPORTS FROM CONTROL MODULE (Output/Movement/Styling)
// ============================================================================

// Core types
pub const CursorStyle = control_cursor.CursorStyle;
pub const PointerShape = control_cursor.PointerShape;
pub const CursorPosition = control_cursor.CursorPosition;
pub const CursorState = control_cursor.CursorState;
pub const TermCaps = control_cursor.TermCaps;
pub const RgbColor = control_cursor.RgbColor;

// Movement optimization
pub const CursorOptimizer = control_cursor.CursorOptimizer;
pub const TabStops = control_cursor.TabStops;
pub const Capabilities = control_cursor.Capabilities;
pub const OptimizerOptions = control_cursor.OptimizerOptions;

// Fluent builder API
pub const CursorBuilder = control_cursor.CursorBuilder;

// Constants
pub const SAVE_CURSOR = control_cursor.SAVE_CURSOR;
pub const RESTORE_CURSOR = control_cursor.RESTORE_CURSOR;
pub const HIDE_CURSOR = control_cursor.HIDE_CURSOR;
pub const SHOW_CURSOR = control_cursor.SHOW_CURSOR;
pub const REQUEST_CURSOR_POSITION_REPORT = control_cursor.REQUEST_CURSOR_POSITION_REPORT;
pub const REQUEST_EXTENDED_CURSOR_POSITION_REPORT = control_cursor.REQUEST_EXTENDED_CURSOR_POSITION_REPORT;

// Low-level functions (re-export for backward compatibility)
pub const saveCursorDECSC = control_cursor.saveCursorDECSC;
pub const restoreCursorDECRC = control_cursor.restoreCursorDECRC;
pub const saveCurrentCursorPosition = control_cursor.saveCurrentCursorPosition;
pub const restoreCurrentCursorPosition = control_cursor.restoreCurrentCursorPosition;
pub const requestCursorPositionReport = control_cursor.requestCursorPositionReport;
pub const requestExtendedCursorPositionReport = control_cursor.requestExtendedCursorPositionReport;
pub const cursorUp = control_cursor.cursorUp;
pub const cursorDown = control_cursor.cursorDown;
pub const cursorForward = control_cursor.cursorForward;
pub const cursorBackward = control_cursor.cursorBackward;
pub const cursorPosition = control_cursor.cursorPosition;
pub const cursorHomePosition = control_cursor.cursorHomePosition;
pub const setCursorStyle = control_cursor.setCursorStyle;
pub const hideCursor = control_cursor.hideCursor;
pub const showCursor = control_cursor.showCursor;
pub const moveCursorTo = control_cursor.moveCursorTo;
pub const moveCursorHome = control_cursor.moveCursorHome;

// ============================================================================
// RE-EXPORTS FROM INPUT MODULE (Position Reporting/Parsing)
// ============================================================================

pub const CursorPositionEvent = input_cursor.CursorPositionEvent;
pub const ParseResult = input_cursor.ParseResult;
pub const tryParseCPR = input_cursor.tryParseCPR;

// ============================================================================
// CURSOR CONTROLLER (Combines Input and Output)
// ============================================================================

/// Cursor controller that handles both input and output
pub fn CursorControllerFor(comptime Writer: type) type {
    return struct {
        /// Output controller for cursor movement and styling
        output: control_cursor.CursorControllerFor(Writer),
        /// Reader for receiving cursor position reports
        reader: ?*reader_mod.Reader = null,
        /// Current reported position from terminal
        reported_position: ?CursorPositionEvent = null,
        allocator: std.mem.Allocator,

        const Self = @This();

        /// Initialize cursor controller
        pub fn init(allocator: std.mem.Allocator, writer: Writer, caps: TermCaps) Self {
            return Self{
                .output = control_cursor.CursorControllerFor(Writer).init(allocator, writer, caps),
                .allocator = allocator,
            };
        }

        /// Set the reader for position reports
        pub fn setReader(self: *Self, terminal_reader: *reader_mod.Reader) void {
            self.reader = terminal_reader;
        }

        /// Deinitialize controller
        pub fn deinit(self: *Self) void {
            self.output.deinit();
        }

        // ========================================================================
        // OUTPUT OPERATIONS (delegated to output controller)
        // ========================================================================

        /// Move cursor to absolute position
        pub fn moveTo(self: *Self, col: u16, row: u16) !void {
            try self.output.moveTo(col, row);
        }

        /// Move cursor relative to current position
        pub fn moveRelative(self: *Self, delta_col: i16, delta_row: i16) !void {
            try self.output.moveRelative(delta_col, delta_row);
        }

        /// Move cursor up by n lines
        pub fn moveUp(self: *Self, n: u16) !void {
            try self.output.moveUp(n);
        }

        /// Move cursor down by n lines
        pub fn moveDown(self: *Self, n: u16) !void {
            try self.output.moveDown(n);
        }

        /// Move cursor right by n columns
        pub fn moveRight(self: *Self, n: u16) !void {
            try self.output.moveRight(n);
        }

        /// Move cursor left by n columns
        pub fn moveLeft(self: *Self, n: u16) !void {
            try self.output.moveLeft(n);
        }

        /// Show or hide cursor
        pub fn setVisible(self: *Self, visible: bool) !void {
            try self.output.setVisible(visible);
        }

        /// Set cursor shape if supported
        pub fn setShape(self: *Self, shape: CursorStyle) !void {
            try self.output.setShape(shape);
        }

        /// Set cursor color if supported
        pub fn setColor(self: *Self, cursor_color: ?RgbColor) !void {
            try self.output.setColor(cursor_color);
        }

        /// Save current cursor position
        pub fn savePosition(self: *Self) !void {
            try self.output.savePosition();
        }

        /// Restore saved cursor position
        pub fn restorePosition(self: *Self) !void {
            try self.output.restorePosition();
        }

        /// Reset cursor to terminal default
        pub fn reset(self: *Self) !void {
            try self.output.reset();
        }

        /// Flush any pending output
        pub fn flush(self: *Self) !void {
            try self.output.flush();
        }

        // ========================================================================
        // INPUT OPERATIONS (position queries)
        // ========================================================================

        /// Request cursor position from terminal and parse response
        pub fn queryPosition(self: *Self, timeout_ms: ?u64) !CursorPositionEvent {
            // Send position report request
            try self.output.requestPosition();
            try self.output.flush();

            // Read response if reader is available
            if (self.reader) |r| {
                const start_time = std.time.milliTimestamp();
                const timeout = timeout_ms orelse 1000; // Default 1 second timeout

                var buffer: [32]u8 = undefined;
                while (true) {
                    // Check timeout
                    if (timeout_ms != null) {
                        const elapsed = std.time.milliTimestamp() - start_time;
                        if (elapsed >= @as(i64, @intCast(timeout))) {
                            return error.Timeout;
                        }
                    }

                    // Try to read from terminal
                    const bytes_read = try r.readTimeout(&buffer, @intCast(@min(timeout, 100)));
                    if (bytes_read == 0) continue;

                    // Try to parse cursor position report
                    if (tryParseCPR(buffer[0..bytes_read])) |result| {
                        self.reported_position = result.event;
                        return result.event;
                    }
                }
            }

            return error.NoReaderAvailable;
        }

        /// Get last reported cursor position
        pub fn getLastReportedPosition(self: Self) ?CursorPositionEvent {
            return self.reported_position;
        }

        /// Synchronize internal state with terminal position
        pub fn syncWithTerminal(self: *Self, timeout_ms: ?u64) !void {
            const pos = try self.queryPosition(timeout_ms);
            self.output.state.position = CursorPosition.init(@intCast(pos.col), @intCast(pos.row));
        }

        // ========================================================================
        // COMPOSITE OPERATIONS (combine input and output)
        // ========================================================================

        /// Move cursor and verify it reached the target position
        pub fn moveToVerified(self: *Self, col: u16, row: u16, timeout_ms: ?u64) !bool {
            try self.moveTo(col, row);
            const reported = try self.queryPosition(timeout_ms);
            return reported.col == col and reported.row == row;
        }

        /// Get current position without changing it
        pub fn getCurrentPosition(self: *Self, timeout_ms: ?u64) !CursorPositionEvent {
            return try self.queryPosition(timeout_ms);
        }

        /// Save position with verification
        pub fn savePositionVerified(self: *Self, timeout_ms: ?u64) !void {
            const pos = try self.queryPosition(timeout_ms);
            try self.savePosition();
            self.reported_position = pos;
        }

        /// Restore position with verification
        pub fn restorePositionVerified(self: *Self, timeout_ms: ?u64) !bool {
            const saved_pos = self.reported_position orelse return error.NoSavedPosition;
            try self.restorePosition();
            const current = try self.queryPosition(timeout_ms);
            return current.col == saved_pos.col and current.row == saved_pos.row;
        }

        /// Get terminal dimensions by moving cursor and querying position
        pub fn getTerminalSize(self: *Self, timeout_ms: ?u64) !struct { width: u16, height: u16 } {
            // Save current position
            try self.savePosition();
            defer self.restorePosition() catch {}; // Best effort restore

            // Move to bottom-right corner (9999, 9999 will be clamped to actual size)
            try self.moveTo(9999, 9999);
            const bottom_right = try self.queryPosition(timeout_ms);

            return .{
                .width = @intCast(bottom_right.col + 1), // Convert to 1-based
                .height = @intCast(bottom_right.row + 1), // Convert to 1-based
            };
        }
    };
}

// Provide a default type alias for common use
pub const CursorController = CursorControllerFor(std.fs.File.Writer);

// ============================================================================
// CONVENIENCE FUNCTIONS
// ============================================================================

/// Hide cursor (no capabilities required)
pub fn hide(writer: anytype) !void {
    try writer.writeAll(HIDE_CURSOR);
}

/// Show cursor (no capabilities required)
pub fn show(writer: anytype) !void {
    try writer.writeAll(SHOW_CURSOR);
}

/// Save cursor position
pub fn save(writer: anytype) !void {
    try writer.writeAll(SAVE_CURSOR);
}

/// Restore cursor position
pub fn restore(writer: anytype) !void {
    try writer.writeAll(RESTORE_CURSOR);
}

/// Move cursor home
pub fn home(writer: anytype) !void {
    try writer.writeAll("\x1b[H");
}

/// Request cursor position
pub fn requestPosition(writer: anytype) !void {
    try writer.writeAll(REQUEST_CURSOR_POSITION_REPORT);
}

/// Parse a cursor position report from raw input
pub fn parsePositionReport(input: []const u8) ?CursorPositionEvent {
    if (tryParseCPR(input)) |result| {
        return result.event;
    }
    return null;
}

// ============================================================================
// TESTS
// ============================================================================

test "cursor module re-exports" {
    // Test that key types are accessible
    _ = CursorStyle;
    _ = CursorPosition;
    _ = CursorPositionEvent;
    _ = CursorController;
}

test "cursor position parsing" {
    const input = "\x1b[12;40R";
    const pos = parsePositionReport(input);
    try std.testing.expect(pos != null);
    try std.testing.expectEqual(@as(u32, 11), pos.?.row); // Zero-based
    try std.testing.expectEqual(@as(u32, 39), pos.?.col); // Zero-based
}

test "controller initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const test_writer = fbs.writer();

    const caps = TermCaps{};
    var controller = CursorController.init(allocator, test_writer, caps);
    defer controller.deinit();

    // Test that we can call output methods
    try controller.moveTo(10, 20);
    try controller.setVisible(false);
    try controller.reset();
}

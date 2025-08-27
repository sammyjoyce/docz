//! Comprehensive cursor control system inspired by Charmbracelet's cursor.go
//! Provides complete set of ANSI cursor manipulation sequences following VT standards
//! Compatible with Zig 0.15.1

const std = @import("std");

// Thread-local buffer for sequence generation to avoid allocation
threadlocal var sequence_buffer: [64]u8 = undefined;

/// Save cursor position (DECSC) - saves position and attributes
/// ESC 7
pub const save_cursor = "\x1b7";
pub const DECSC = save_cursor;

/// Restore cursor position (DECRC) - restores position and attributes
/// ESC 8
pub const restore_cursor = "\x1b8";
pub const DECRC = restore_cursor;

/// Save current cursor position for SCO console (SCOSC)
/// CSI s - saves position only, not attributes
pub const save_current_cursor_position = "\x1b[s";
pub const SCOSC = save_current_cursor_position;

/// Restore current cursor position for SCO console (SCORC)
/// CSI u - restores position only
pub const restore_current_cursor_position = "\x1b[u";
pub const SCORC = restore_current_cursor_position;

/// Request cursor position report (CPR)
/// CSI 6 n - terminal responds with CSI Pl ; Pc R where Pl=row, Pc=column
pub const request_cursor_position = "\x1b[6n";

/// Request extended cursor position report (DECXCPR)
/// CSI ? 6 n - includes page number in response: CSI ? Pl ; Pc ; Pp R
pub const request_extended_cursor_position = "\x1b[?6n";

/// Move cursor to home position (upper left corner)
/// CSI H or CSI 1 ; 1 H
pub const cursor_home_position = "\x1b[H";
pub const home_cursor_position = cursor_home_position;
pub const cursor_origin = "\x1b[1;1H";

/// Cursor movement directions
pub const CursorDirection = enum {
    up,
    down,
    forward, // right
    backward, // left
    next_line,
    previous_line,
};

/// Cursor movement functions with count parameter
pub fn cursorUp(n: u32) []const u8 {
    if (n <= 1) return CUU1;
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{}A", .{n}) catch CUU1;
}

pub fn cursorDown(n: u32) []const u8 {
    if (n <= 1) return CUD1;
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{}B", .{n}) catch CUD1;
}

pub fn cursorForward(n: u32) []const u8 {
    if (n <= 1) return CUF1;
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{}C", .{n}) catch CUF1;
}

pub fn cursorBackward(n: u32) []const u8 {
    if (n <= 1) return CUB1;
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{}D", .{n}) catch CUB1;
}

pub fn cursorNextLine(n: u32) []const u8 {
    if (n <= 1) return "\x1b[E";
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{}E", .{n}) catch "\x1b[E";
}

pub fn cursorPreviousLine(n: u32) []const u8 {
    if (n <= 1) return "\x1b[F";
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{}F", .{n}) catch "\x1b[F";
}

/// Single-step cursor movement constants
pub const CUU1 = "\x1b[A"; // cursor up 1
pub const CUD1 = "\x1b[B"; // cursor down 1
pub const CUF1 = "\x1b[C"; // cursor forward 1
pub const CUB1 = "\x1b[D"; // cursor backward 1

/// Aliases for common functions
pub const CUU = cursorUp;
pub const CUD = cursorDown;
pub const CUF = cursorForward;
pub const CUB = cursorBackward;
pub const CNL = cursorNextLine;
pub const CPL = cursorPreviousLine;

/// Cursor positioning functions
pub fn cursorPosition(col: u32, row: u32) []const u8 {
    if (row == 0 and col == 0) return cursor_home_position;

    if (row == 0) {
        return std.fmt.bufPrint(&sequence_buffer, "\x1b[;{}H", .{col}) catch cursor_home_position;
    } else if (col == 0) {
        return std.fmt.bufPrint(&sequence_buffer, "\x1b[{};H", .{row}) catch cursor_home_position;
    } else {
        return std.fmt.bufPrint(&sequence_buffer, "\x1b[{};{}H", .{ row, col }) catch cursor_home_position;
    }
}

/// Horizontal/Vertical position (HVP) - same effect as CUP
pub fn horizontalVerticalPosition(col: u32, row: u32) []const u8 {
    if (row == 0 and col == 0) return horizontal_vertical_home_position;

    if (row == 0) {
        return std.fmt.bufPrint(&sequence_buffer, "\x1b[;{}f", .{col}) catch horizontal_vertical_home_position;
    } else if (col == 0) {
        return std.fmt.bufPrint(&sequence_buffer, "\x1b[{};f", .{row}) catch horizontal_vertical_home_position;
    } else {
        return std.fmt.bufPrint(&sequence_buffer, "\x1b[{};{}f", .{ row, col }) catch horizontal_vertical_home_position;
    }
}

/// Aliases for positioning
pub const CUP = cursorPosition;
pub const HVP = horizontalVerticalPosition;
pub const horizontal_vertical_home_position = "\x1b[f";

/// Column and row positioning
pub fn cursorHorizontalAbsolute(col: u32) []const u8 {
    if (col == 0) return "\x1b[G";
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{}G", .{col}) catch "\x1b[G";
}

pub fn verticalPositionAbsolute(row: u32) []const u8 {
    if (row == 0) return "\x1b[d";
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{}d", .{row}) catch "\x1b[d";
}

pub fn verticalPositionRelative(n: u32) []const u8 {
    if (n <= 1) return "\x1b[e";
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{}e", .{n}) catch "\x1b[e";
}

pub fn horizontalPositionAbsolute(col: u32) []const u8 {
    if (col == 0) return "\x1b[`";
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{}G", .{col}) catch "\x1b[`";
}

pub fn horizontalPositionRelative(n: u32) []const u8 {
    if (n == 0) return "\x1b[a";
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{}a", .{n}) catch "\x1b[a";
}

/// Aliases
pub const CHA = cursorHorizontalAbsolute;
pub const VPA = verticalPositionAbsolute;
pub const VPR = verticalPositionRelative;
pub const HPA = horizontalPositionAbsolute;
pub const HPR = horizontalPositionRelative;

/// Tab control
pub fn cursorHorizontalForwardTab(n: u32) []const u8 {
    if (n <= 1) return "\x1b[I";
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{}I", .{n}) catch "\x1b[I";
}

pub fn cursorBackwardTab(n: u32) []const u8 {
    if (n <= 1) return "\x1b[Z";
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{}Z", .{n}) catch "\x1b[Z";
}

pub const CHT = cursorHorizontalForwardTab;
pub const CBT = cursorBackwardTab;

/// Character manipulation
pub fn eraseCharacter(n: u32) []const u8 {
    if (n <= 1) return "\x1b[X";
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{}X", .{n}) catch "\x1b[X";
}

pub const ECH = eraseCharacter;

/// Reverse Index - cursor up with scroll
pub const reverse_index = "\x1bM";
pub const RI = reverse_index;

/// Index - cursor down with scroll
pub const index = "\x1bD";
pub const IND = index;

/// Cursor style control (DECSCUSR)
pub const CursorStyle = enum(u8) {
    blinking_block = 0,
    blinking_block_default = 1,
    steady_block = 2,
    blinking_underline = 3,
    steady_underline = 4,
    blinking_bar = 5,
    steady_bar = 6,
};

pub fn setCursorStyle(style: CursorStyle) []const u8 {
    return std.fmt.bufPrint(&sequence_buffer, "\x1b[{} q", .{@intFromEnum(style)}) catch "\x1b[1 q";
}

pub const DECSCUSR = setCursorStyle;

/// Mouse pointer shape control (OSC 22)
pub fn setPointerShape(shape: []const u8) []u8 {
    var buf: [64]u8 = undefined;
    return std.fmt.bufPrint(&buf, "\x1b]22;{s}\x07", .{shape}) catch "\x1b]22;default\x07";
}

/// Common pointer shapes
pub const PointerShape = struct {
    pub const default = "default";
    pub const copy = "copy";
    pub const crosshair = "crosshair";
    pub const ew_resize = "ew-resize";
    pub const n_resize = "n-resize";
    pub const text = "text";
    pub const wait = "wait";
    pub const pointer = "pointer";
    pub const help = "help";
    pub const not_allowed = "not-allowed";
    pub const grab = "grab";
    pub const grabbing = "grabbing";
};

/// High-level cursor control API
pub const CursorController = struct {
    /// Save cursor position using modern method
    pub fn save() []const u8 {
        return save_cursor;
    }

    /// Restore cursor position
    pub fn restore() []const u8 {
        return restore_cursor;
    }

    /// Move cursor to specific position (1-indexed)
    pub fn moveTo(col: u32, row: u32) []const u8 {
        return cursorPosition(col, row);
    }

    /// Move cursor to home position
    pub fn home() []const u8 {
        return cursor_home_position;
    }

    /// Move cursor by relative amount
    pub fn moveBy(direction: CursorDirection, count: u32) []const u8 {
        return switch (direction) {
            .up => cursorUp(count),
            .down => cursorDown(count),
            .forward => cursorForward(count),
            .backward => cursorBackward(count),
            .next_line => cursorNextLine(count),
            .previous_line => cursorPreviousLine(count),
        };
    }

    /// Set cursor visual style
    pub fn setStyle(style: CursorStyle) []const u8 {
        return setCursorStyle(style);
    }

    /// Request current position (terminal will send response)
    pub fn requestPosition() []const u8 {
        return request_cursor_position;
    }

    /// Hide cursor
    pub fn hide() []const u8 {
        return "\x1b[?25l";
    }

    /// Show cursor
    pub fn show() []const u8 {
        return "\x1b[?25h";
    }
};

/// Convenience functions for common operations
pub fn moveToPosition(col: u32, row: u32) []const u8 {
    return CursorController.moveTo(col, row);
}

pub fn moveRelative(direction: CursorDirection, count: u32) []const u8 {
    return CursorController.moveBy(direction, count);
}

/// Comprehensive cursor manipulation with bounds checking
pub const SafeCursorController = struct {
    max_rows: u32 = 25,
    max_cols: u32 = 80,
    current_row: u32 = 1,
    current_col: u32 = 1,

    pub fn init(max_rows: u32, max_cols: u32) SafeCursorController {
        return SafeCursorController{
            .max_rows = max_rows,
            .max_cols = max_cols,
        };
    }

    pub fn moveTo(self: *SafeCursorController, col: u32, row: u32) ?[]const u8 {
        const safe_col = std.math.clamp(col, 1, self.max_cols);
        const safe_row = std.math.clamp(row, 1, self.max_rows);

        if (safe_col != col or safe_row != row) {
            return null; // Position was out of bounds
        }

        self.current_col = safe_col;
        self.current_row = safe_row;
        return cursorPosition(safe_col, safe_row);
    }

    pub fn moveBy(self: *SafeCursorController, direction: CursorDirection, count: u32) ?[]const u8 {
        var new_col = self.current_col;
        var new_row = self.current_row;

        switch (direction) {
            .up => new_row = if (new_row > count) new_row - count else 1,
            .down => new_row = @min(new_row + count, self.max_rows),
            .forward => new_col = @min(new_col + count, self.max_cols),
            .backward => new_col = if (new_col > count) new_col - count else 1,
            .next_line => {
                new_row = @min(new_row + count, self.max_rows);
                new_col = 1;
            },
            .previous_line => {
                new_row = if (new_row > count) new_row - count else 1;
                new_col = 1;
            },
        }

        if (new_col == self.current_col and new_row == self.current_row) {
            return null; // No movement would occur
        }

        self.current_col = new_col;
        self.current_row = new_row;
        return CursorController.moveBy(direction, count);
    }

    pub fn getCurrentPosition(self: SafeCursorController) struct { col: u32, row: u32 } {
        return .{ .col = self.current_col, .row = self.current_row };
    }
};

// Tests for cursor control functionality
test "cursor movement functions" {
    const testing = std.testing;

    // Test basic movement
    const up1 = cursorUp(1);
    try testing.expectEqualStrings(CUU1, up1);

    const up5 = cursorUp(5);
    try testing.expectEqualStrings("\x1b[5A", up5);

    const down3 = cursorDown(3);
    try testing.expectEqualStrings("\x1b[3B", down3);
}

test "cursor positioning" {
    const testing = std.testing;

    // Test home position
    const home = cursorPosition(0, 0);
    try testing.expectEqualStrings(cursor_home_position, home);

    // Test specific position
    const pos = cursorPosition(10, 5);
    try testing.expectEqualStrings("\x1b[5;10H", pos);
}

test "safe cursor controller" {
    const testing = std.testing;

    var controller = SafeCursorController.init(24, 80);

    // Test valid move
    const move1 = controller.moveTo(10, 5);
    try testing.expect(move1 != null);

    const pos = controller.getCurrentPosition();
    try testing.expectEqual(@as(u32, 10), pos.col);
    try testing.expectEqual(@as(u32, 5), pos.row);

    // Test bounds checking
    const invalid_move = controller.moveTo(100, 100); // Out of bounds
    try testing.expect(invalid_move == null);
}

test "cursor styles" {
    const testing = std.testing;

    const blinking_block = setCursorStyle(.blinking_block);
    try testing.expectEqualStrings("\x1b[0 q", blinking_block);

    const steady_bar = setCursorStyle(.steady_bar);
    try testing.expectEqualStrings("\x1b[6 q", steady_bar);
}

test "high level cursor API" {
    const testing = std.testing;

    // Test controller functions
    const save_seq = CursorController.save();
    try testing.expectEqualStrings(save_cursor, save_seq);

    const restore_seq = CursorController.restore();
    try testing.expectEqualStrings(restore_cursor, restore_seq);

    const home_seq = CursorController.home();
    try testing.expectEqualStrings(cursor_home_position, home_seq);

    const move_up = CursorController.moveBy(.up, 3);
    try testing.expectEqualStrings("\x1b[3A", move_up);
}

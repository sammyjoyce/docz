//! Unified Cursor Control System
//! Consolidated cursor positioning, styling, state management, and optimization
//! Compatible with Zig 0.15.1 and follows proper error handling patterns

const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("../ansi/passthrough.zig");
const color_mod = @import("../color/mod.zig");

pub const TermCaps = caps_mod.TermCaps;
pub const RgbColor = color_mod.types.RgbColor;

// ============================================================================
// CURSOR STYLES AND SHAPES
// ============================================================================

/// Cursor styles for DECSCUSR (Set Cursor Style)
pub const CursorStyle = enum(u8) {
    blinking_block_default = 0,
    blinking_block = 1,
    steady_block = 2,
    blinking_underline = 3,
    steady_underline = 4,
    blinking_bar = 5, // xterm
    steady_bar = 6, // xterm

    /// Get ANSI escape sequence for this cursor style
    pub fn toAnsiSequence(self: CursorStyle) []const u8 {
        return switch (self) {
            .blinking_block_default => "\x1b[0 q",
            .blinking_block => "\x1b[1 q",
            .steady_block => "\x1b[2 q",
            .blinking_underline => "\x1b[3 q",
            .steady_underline => "\x1b[4 q",
            .blinking_bar => "\x1b[5 q",
            .steady_bar => "\x1b[6 q",
        };
    }
};

/// Mouse pointer shapes for terminals that support it
pub const PointerShape = enum {
    default,
    text,
    pointer,
    help,
    wait,
    progress,
    crosshair,
    cell,
    vertical_text,
    alias,
    copy,
    no_drop,
    not_allowed,
    grab,
    grabbing,

    /// Get shape name for terminal escape sequence
    pub fn shapeName(self: PointerShape) []const u8 {
        return switch (self) {
            .default => "default",
            .text => "text",
            .pointer => "pointer",
            .help => "help",
            .wait => "wait",
            .progress => "progress",
            .crosshair => "crosshair",
            .cell => "cell",
            .vertical_text => "vertical-text",
            .alias => "alias",
            .copy => "copy",
            .no_drop => "no-drop",
            .not_allowed => "not-allowed",
            .grab => "grab",
            .grabbing => "grabbing",
        };
    }
};

// ============================================================================
// CURSOR POSITION AND STATE MANAGEMENT
// ============================================================================

/// Cursor position with 1-based coordinates (standard terminal convention)
pub const CursorPosition = struct {
    col: u16, // 1-based column
    row: u16, // 1-based row

    /// Create cursor position (converts from 0-based to 1-based)
    pub fn init(col: u16, row: u16) CursorPosition {
        return CursorPosition{
            .col = col + 1,
            .row = row + 1,
        };
    }

    /// Get as 0-based coordinates
    pub fn to0Based(self: CursorPosition) struct { col: u16, row: u16 } {
        return .{
            .col = if (self.col > 0) self.col - 1 else 0,
            .row = if (self.row > 0) self.row - 1 else 0,
        };
    }
};

/// Comprehensive cursor state management
pub const CursorState = struct {
    position: CursorPosition = CursorPosition{ .col = 1, .row = 1 },
    visible: bool = true,
    shape: CursorStyle = .blinking_block_default,
    blink: bool = true,
    color: ?RgbColor = null,

    /// Save current position for later restoration
    saved_positions: std.ArrayList(CursorPosition),

    pub fn init(allocator: std.mem.Allocator) CursorState {
        return CursorState{
            .saved_positions = std.ArrayList(CursorPosition).init(allocator),
        };
    }

    pub fn deinit(self: *CursorState, allocator: std.mem.Allocator) void {
        self.saved_positions.deinit();
        _ = allocator; // Unused but kept for API consistency
    }

    /// Save current position to stack
    pub fn savePosition(self: *CursorState, allocator: std.mem.Allocator) !void {
        try self.saved_positions.append(self.position);
        _ = allocator; // Unused but kept for API consistency
    }

    /// Restore last saved position
    pub fn restorePosition(self: *CursorState) ?CursorPosition {
        if (self.saved_positions.items.len == 0) return null;
        return self.saved_positions.pop();
    }
};

// ============================================================================
// ANSI ESCAPE SEQUENCE CONSTANTS
// ============================================================================

// Save and Restore Cursor
pub const SAVE_CURSOR = "\x1b7";
pub const DECSC = SAVE_CURSOR;
pub const RESTORE_CURSOR = "\x1b8";
pub const DECRC = RESTORE_CURSOR;
pub const SAVE_CURRENT_CURSOR_POSITION = "\x1b[s";
pub const SCOSC = SAVE_CURRENT_CURSOR_POSITION;
pub const RESTORE_CURRENT_CURSOR_POSITION = "\x1b[u";
pub const SCORC = RESTORE_CURRENT_CURSOR_POSITION;

// Cursor Movement
pub const CUU1 = "\x1b[A";
pub const CUD1 = "\x1b[B";
pub const CUF1 = "\x1b[C";
pub const CUB1 = "\x1b[D";
pub const CURSOR_HOME_POSITION = "\x1b[H";
pub const HORIZONTAL_VERTICAL_HOME_POSITION = "\x1b[f";

// Position Reporting
pub const REQUEST_CURSOR_POSITION_REPORT = "\x1b[6n";
pub const REQUEST_EXTENDED_CURSOR_POSITION_REPORT = "\x1b[?6n";

// Scrolling and Index
pub const REVERSE_INDEX = "\x1bM";
pub const RI = REVERSE_INDEX;
pub const INDEX = "\x1bD";
pub const IND = INDEX;

// Visibility
pub const HIDE_CURSOR = "\x1b[?25l";
pub const SHOW_CURSOR = "\x1b[?25h";

// Blinking
pub const ENABLE_BLINKING = "\x1b[?12h";
pub const DISABLE_BLINKING = "\x1b[?12l";

// ============================================================================
// WRITER-BASED API (Direct Terminal Output)
// ============================================================================

// Save and Restore Cursor Position
pub fn saveCursorDECSC(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, SAVE_CURSOR);
}

pub fn restoreCursorDECRC(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, RESTORE_CURSOR);
}

pub fn saveCurrentCursorPosition(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, SAVE_CURRENT_CURSOR_POSITION);
}

pub fn restoreCurrentCursorPosition(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, RESTORE_CURRENT_CURSOR_POSITION);
}

// Position Reporting
pub fn requestCursorPositionReport(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, REQUEST_CURSOR_POSITION_REPORT);
}

pub fn requestExtendedCursorPositionReport(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, REQUEST_EXTENDED_CURSOR_POSITION_REPORT);
}

// Cursor Movement
pub fn cursorUp(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) return;
    if (n == 1) {
        try passthrough.writeWithPassthrough(writer, caps, CUU1);
        return;
    }

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{n}) catch unreachable;
    _ = w.writeByte('A') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

pub fn cursorDown(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) return;
    if (n == 1) {
        try passthrough.writeWithPassthrough(writer, caps, CUD1);
        return;
    }

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{n}) catch unreachable;
    _ = w.writeByte('B') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

pub fn cursorForward(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) return;
    if (n == 1) {
        try passthrough.writeWithPassthrough(writer, caps, CUF1);
        return;
    }

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{n}) catch unreachable;
    _ = w.writeByte('C') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

pub fn cursorBackward(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) return;
    if (n == 1) {
        try passthrough.writeWithPassthrough(writer, caps, CUB1);
        return;
    }

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{n}) catch unreachable;
    _ = w.writeByte('D') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Line Movement
pub fn cursorNextLine(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) return;
    if (n == 1) {
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[E");
        return;
    }

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{n}) catch unreachable;
    _ = w.writeByte('E') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

pub fn cursorPreviousLine(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) return;
    if (n == 1) {
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[F");
        return;
    }

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{n}) catch unreachable;
    _ = w.writeByte('F') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Absolute Positioning
pub fn cursorHorizontalAbsolute(writer: anytype, caps: TermCaps, col: u32) !void {
    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    if (col > 0) {
        _ = std.fmt.format(w, "{d}", .{col}) catch unreachable;
    }
    _ = w.writeByte('G') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

pub fn cursorPosition(writer: anytype, caps: TermCaps, row: u32, col: u32) !void {
    if (row <= 1 and col <= 1) {
        try passthrough.writeWithPassthrough(writer, caps, CURSOR_HOME_POSITION);
        return;
    }

    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    if (row > 0) {
        _ = std.fmt.format(w, "{d}", .{row}) catch unreachable;
    }
    _ = w.writeByte(';') catch unreachable;
    if (col > 0) {
        _ = std.fmt.format(w, "{d}", .{col}) catch unreachable;
    }
    _ = w.writeByte('H') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

pub fn cursorHomePosition(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, CURSOR_HOME_POSITION);
}

// Vertical Positioning
pub fn verticalPositionAbsolute(writer: anytype, caps: TermCaps, row: u32) !void {
    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    if (row > 0) {
        _ = std.fmt.format(w, "{d}", .{row}) catch unreachable;
    }
    _ = w.writeByte('d') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

pub fn verticalPositionRelative(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n <= 1) {
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[e");
        return;
    }

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{n}) catch unreachable;
    _ = w.writeByte('e') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Horizontal Vertical Position
pub fn horizontalVerticalPosition(writer: anytype, caps: TermCaps, row: u32, col: u32) !void {
    if (row <= 1 and col <= 1) {
        try passthrough.writeWithPassthrough(writer, caps, HORIZONTAL_VERTICAL_HOME_POSITION);
        return;
    }

    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    if (row > 0) {
        _ = std.fmt.format(w, "{d}", .{row}) catch unreachable;
    }
    _ = w.writeByte(';') catch unreachable;
    if (col > 0) {
        _ = std.fmt.format(w, "{d}", .{col}) catch unreachable;
    }
    _ = w.writeByte('f') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Tab Handling
pub fn cursorHorizontalForwardTab(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n <= 1) {
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[I");
        return;
    }

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{n}) catch unreachable;
    _ = w.writeByte('I') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

pub fn cursorBackwardTab(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n <= 1) {
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[Z");
        return;
    }

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{n}) catch unreachable;
    _ = w.writeByte('Z') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Character Manipulation
pub fn eraseCharacter(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n <= 1) {
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[X");
        return;
    }

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{n}) catch unreachable;
    _ = w.writeByte('X') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Horizontal Positioning
pub fn horizontalPositionAbsolute(writer: anytype, caps: TermCaps, col: u32) !void {
    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    if (col > 0) {
        _ = std.fmt.format(w, "{d}", .{col}) catch unreachable;
    }
    _ = w.writeByte('`') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

pub fn horizontalPositionRelative(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n <= 1) {
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[a");
        return;
    }

    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{n}) catch unreachable;
    _ = w.writeByte('a') catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Scrolling and Index
pub fn reverseIndex(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, REVERSE_INDEX);
}

pub fn index(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, INDEX);
}

// Cursor Styling
pub fn setCursorStyle(writer: anytype, caps: TermCaps, style: CursorStyle) !void {
    try passthrough.writeWithPassthrough(writer, caps, style.toAnsiSequence());
}

pub fn setPointerShapeDirect(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, shape: PointerShape) !void {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try buf.appendSlice("\x1b]22;");
    try buf.appendSlice(shape.shapeName());
    try buf.append(0x07); // BEL

    try passthrough.writeWithPassthrough(writer, caps, buf.items);
}

// Visibility and Blinking
pub fn hideCursor(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, HIDE_CURSOR);
}

pub fn showCursor(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, SHOW_CURSOR);
}

pub fn enableBlinkingDirect(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, ENABLE_BLINKING);
}

pub fn disableBlinkingDirect(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, DISABLE_BLINKING);
}

// ============================================================================
// STRING-RETURNING API (For Building Complex Sequences)
// ============================================================================

/// Generate cursor up sequence as string
pub fn cursorUpString(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 1) {
        return allocator.dupe(u8, CUU1);
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}A", .{n});
}

/// Generate cursor down sequence as string
pub fn cursorDownString(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 1) {
        return allocator.dupe(u8, CUD1);
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}B", .{n});
}

/// Generate cursor forward sequence as string
pub fn cursorForwardString(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 1) {
        return allocator.dupe(u8, CUF1);
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}C", .{n});
}

/// Generate cursor backward sequence as string
pub fn cursorBackwardString(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 1) {
        return allocator.dupe(u8, CUB1);
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}D", .{n});
}

/// Generate cursor position sequence as string
pub fn cursorPositionString(allocator: std.mem.Allocator, row: u32, col: u32) ![]u8 {
    if (row <= 0 and col <= 0) {
        return allocator.dupe(u8, CURSOR_HOME_POSITION);
    }

    if (row <= 0) {
        return try std.fmt.allocPrint(allocator, "\x1b[;{}H", .{col});
    } else if (col <= 0) {
        return try std.fmt.allocPrint(allocator, "\x1b[{};H", .{row});
    } else {
        return try std.fmt.allocPrint(allocator, "\x1b[{};{}H", .{ row, col });
    }
}

/// Generate cursor style sequence as string
pub fn setCursorStyleString(allocator: std.mem.Allocator, style: CursorStyle) ![]u8 {
    return allocator.dupe(u8, style.toAnsiSequence());
}

/// Generate pointer shape sequence as string
pub fn setPointerShapeString(allocator: std.mem.Allocator, shape: PointerShape) ![]u8 {
    return try std.fmt.allocPrint(allocator, "\x1b]22;{s}\x07", .{shape.shapeName()});
}

// ============================================================================
// STATEFUL CURSOR CONTROLLER
// ============================================================================

/// Advanced cursor controller with modern terminal support
pub fn CursorControllerFor(comptime Writer: type) type {
    return struct {
        state: CursorState,
        writer: Writer,
        caps: TermCaps,
        supports_cursor_color: bool,
        supports_cursor_shapes: bool,
        supports_pointer_shapes: bool,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, writer: Writer, caps: TermCaps) Self {
            return Self{
                .state = CursorState.init(allocator),
                .writer = writer,
                .caps = caps,
                .supports_cursor_color = true, // Assume support by default
                .supports_cursor_shapes = true,
                .supports_pointer_shapes = false, // Less common
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.state.deinit(self.allocator);
        }

        /// Move cursor to absolute position
        pub fn moveTo(self: *Self, col: u16, row: u16) !void {
            self.state.position = CursorPosition.init(col, row);
            try cursorPosition(self.writer, self.caps, self.state.position.row, self.state.position.col);
        }

        /// Move cursor relative to current position
        pub fn moveRelative(self: *Self, delta_col: i16, delta_row: i16) !void {
            const current = self.state.position.to0Based();
            const new_col = @as(u16, @intCast(@max(0, @as(i32, current.col) + delta_col)));
            const new_row = @as(u16, @intCast(@max(0, @as(i32, current.row) + delta_row)));
            try self.moveTo(new_col, new_row);
        }

        /// Move cursor up by n lines
        pub fn moveUp(self: *Self, n: u16) !void {
            if (n == 0) return;
            try cursorUp(self.writer, self.caps, n);
            self.state.position.row = @max(1, @as(i32, self.state.position.row) - @as(i32, n));
        }

        /// Move cursor down by n lines
        pub fn moveDown(self: *Self, n: u16) !void {
            if (n == 0) return;
            try cursorDown(self.writer, self.caps, n);
            self.state.position.row = self.state.position.row + n;
        }

        /// Move cursor right by n columns
        pub fn moveRight(self: *Self, n: u16) !void {
            if (n == 0) return;
            try cursorForward(self.writer, self.caps, n);
            self.state.position.col = self.state.position.col + n;
        }

        /// Move cursor left by n columns
        pub fn moveLeft(self: *Self, n: u16) !void {
            if (n == 0) return;
            try cursorBackward(self.writer, self.caps, n);
            self.state.position.col = @max(1, @as(i32, self.state.position.col) - @as(i32, n));
        }

        /// Move to beginning of current line
        pub fn moveToLineStart(self: *Self) !void {
            try cursorHorizontalAbsolute(self.writer, self.caps, 1);
            self.state.position.col = 1;
        }

        /// Move to beginning of next line
        pub fn moveToNextLine(self: *Self, n: u16) !void {
            if (n == 0) return;
            if (n == 1) {
                try passthrough.writeWithPassthrough(self.writer, self.caps, "\x1b[E");
            } else {
                try cursorNextLine(self.writer, self.caps, n);
            }
            self.state.position.row = self.state.position.row + n;
            self.state.position.col = 1;
        }

        /// Move to beginning of previous line
        pub fn moveToPrevLine(self: *Self, n: u16) !void {
            if (n == 0) return;
            if (n == 1) {
                try passthrough.writeWithPassthrough(self.writer, self.caps, "\x1b[F");
            } else {
                try cursorPreviousLine(self.writer, self.caps, n);
            }
            self.state.position.row = @max(1, @as(i32, self.state.position.row) - @as(i32, n));
            self.state.position.col = 1;
        }

        /// Move to specific column on current row
        pub fn moveToColumn(self: *Self, col: u16) !void {
            try cursorHorizontalAbsolute(self.writer, self.caps, col + 1); // Convert to 1-based
            self.state.position.col = col + 1;
        }

        /// Show or hide cursor
        pub fn setVisible(self: *Self, visible: bool) !void {
            self.state.visible = visible;
            if (visible) {
                try showCursor(self.writer, self.caps);
            } else {
                try hideCursor(self.writer, self.caps);
            }
        }

        /// Set cursor shape if supported
        pub fn setShape(self: *Self, shape: CursorStyle) !void {
            if (!self.supports_cursor_shapes) return;

            self.state.shape = shape;
            try setCursorStyle(self.writer, self.caps, shape);
        }

        /// Set cursor color if supported
        pub fn setColor(self: *Self, cursor_color: ?RgbColor) !void {
            if (!self.supports_cursor_color) return;

            self.state.color = cursor_color;
            if (cursor_color) |c| {
                // Set cursor color using OSC escape sequence
                try self.writer.print("\x1b]12;#{:02x}{:02x}{:02x}\x1b\\", .{ c.r, c.g, c.b });
            } else {
                // Reset to default cursor color
                try passthrough.writeWithPassthrough(self.writer, self.caps, "\x1b]112\x1b\\");
            }
        }

        /// Set mouse pointer shape if supported
        pub fn setPointerShape(self: *Self, shape: PointerShape) !void {
            if (!self.supports_pointer_shapes) return;

            try setPointerShapeDirect(self.writer, self.caps, self.allocator, shape);
        }

        /// Save current cursor position
        pub fn savePosition(self: *Self) !void {
            try saveCurrentCursorPosition(self.writer, self.caps);
            try self.state.savePosition(self.allocator);
        }

        /// Restore saved cursor position
        pub fn restorePosition(self: *Self) !void {
            try restoreCurrentCursorPosition(self.writer, self.caps);
            if (self.state.restorePosition()) |pos| {
                self.state.position = pos;
            }
        }

        /// Save cursor position using DEC sequence (more reliable)
        pub fn saveDECPosition(self: *Self) !void {
            try saveCursorDECSC(self.writer, self.caps);
            try self.state.savePosition(self.allocator);
        }

        /// Restore cursor position using DEC sequence
        pub fn restoreDECPosition(self: *Self) !void {
            try restoreCursorDECRC(self.writer, self.caps);
            if (self.state.restorePosition()) |pos| {
                self.state.position = pos;
            }
        }

        /// Request current cursor position from terminal
        pub fn requestPosition(self: *Self) !void {
            try requestCursorPositionReport(self.writer, self.caps);
        }

        /// Set cursor to specific tab stop
        pub fn moveToTabStop(self: *Self, n: u16) !void {
            if (n == 0) return;
            try cursorHorizontalForwardTab(self.writer, self.caps, n);
        }

        /// Move backward to tab stop
        pub fn moveToBackTabStop(self: *Self, n: u16) !void {
            if (n == 0) return;
            try cursorBackwardTab(self.writer, self.caps, n);
        }

        /// Get current cursor state (for serialization/debugging)
        pub fn getState(self: *const Self) CursorState {
            return self.state;
        }

        /// Restore cursor state from saved state
        pub fn setState(self: *Self, new_state: CursorState) !void {
            // Restore position
            try self.moveTo(new_state.position.to0Based().col, new_state.position.to0Based().row);

            // Restore visibility
            try self.setVisible(new_state.visible);

            // Restore shape if changed
            if (new_state.shape != self.state.shape) {
                try self.setShape(new_state.shape);
            }

            // Restore color if changed
            if (new_state.color != self.state.color) {
                try self.setColor(new_state.color);
            }

            self.state = new_state;
        }

        /// Enable cursor blinking
        pub fn enableBlinking(self: *Self) !void {
            self.state.blink = true;
            try enableBlinkingDirect(self.writer, self.caps);
        }

        /// Disable cursor blinking
        pub fn disableBlinking(self: *Self) !void {
            self.state.blink = false;
            try disableBlinkingDirect(self.writer, self.caps);
        }

        /// Reset cursor to terminal default
        pub fn reset(self: *Self) !void {
            try self.setVisible(true);
            try self.setShape(.blinking_block_default);
            try self.setColor(null);
            try self.enableBlinking();
            try self.moveTo(0, 0);
        }

        /// Flush any pending output to ensure cursor changes are visible
        pub fn flush(self: *Self) !void {
            try self.writer.flush();
        }
    };
}

// Provide a default type alias for common use
pub const CursorController = CursorControllerFor(std.fs.File.Writer);

// ============================================================================
// CURSOR OPTIMIZATION SYSTEM
// ============================================================================

/// Tab stop manager for optimizing horizontal cursor movement
pub const TabStops = struct {
    stops: []bool,
    width: usize,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize with default tab stops every 8 columns
    pub fn init(allocator: std.mem.Allocator, width: usize) !Self {
        const stops = try allocator.alloc(bool, width);
        // Standard tab stops every 8 columns
        for (stops, 0..) |*stop, i| {
            stop.* = (i % 8) == 0;
        }

        return Self{
            .stops = stops,
            .width = width,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.stops);
    }

    /// Resize tab stops array
    pub fn resize(self: *Self, new_width: usize) !void {
        const new_stops = try self.allocator.alloc(bool, new_width);
        const copy_width = @min(self.width, new_width);

        // Copy existing stops
        @memcpy(new_stops[0..copy_width], self.stops[0..copy_width]);

        // Initialize new stops with standard 8-column pattern
        for (copy_width..new_width) |i| {
            new_stops[i] = (i % 8) == 0;
        }

        self.allocator.free(self.stops);
        self.stops = new_stops;
        self.width = new_width;
    }

    /// Find next tab stop at or after the given column
    pub fn next(self: Self, col: usize) usize {
        for (col..self.width) |i| {
            if (self.stops[i]) return i;
        }
        return self.width - 1;
    }

    /// Find previous tab stop at or before the given column
    pub fn prev(self: Self, col: usize) usize {
        var i = @min(col, self.width - 1);
        while (true) {
            if (self.stops[i]) return i;
            if (i == 0) break;
            i -= 1;
        }
        return 0;
    }

    /// Set tab stop at column
    pub fn set(self: *Self, col: usize) void {
        if (col < self.width) {
            self.stops[col] = true;
        }
    }

    /// Clear tab stop at column
    pub fn clear(self: *Self, col: usize) void {
        if (col < self.width) {
            self.stops[col] = false;
        }
    }

    /// Clear all tab stops
    pub fn clearAll(self: *Self) void {
        @memset(self.stops, false);
    }
};

/// Terminal capabilities for optimization decisions
pub const Capabilities = struct {
    /// Vertical Position Absolute (VPA)
    vpa: bool = true,
    /// Horizontal Position Absolute (HPA)
    hpa: bool = true,
    /// Cursor Horizontal Tab (CHT)
    cht: bool = true,
    /// Cursor Backward Tab (CBT)
    cbt: bool = true,
    /// Repeat Previous Character (REP)
    rep: bool = true,
    /// Erase Character (ECH)
    ech: bool = true,
    /// Insert Character (ICH)
    ich: bool = true,
    /// Scroll Down (SD)
    sd: bool = true,
    /// Scroll Up (SU)
    su: bool = true,

    /// Initialize capabilities for known terminal types
    pub fn forTerminal(term_type: []const u8) Capabilities {
        // Extract base terminal name
        const term_base = blk: {
            if (std.mem.indexOf(u8, term_type, "-")) |dash_pos| {
                break :blk term_type[0..dash_pos];
            }
            break :blk term_type;
        };

        return switch (std.hash_map.hashString(term_base)) {
            std.hash_map.hashString("xterm"), std.hash_map.hashString("tmux"), std.hash_map.hashString("foot"), std.hash_map.hashString("kitty"), std.hash_map.hashString("wezterm"), std.hash_map.hashString("contour"), std.hash_map.hashString("ghostty"), std.hash_map.hashString("rio"), std.hash_map.hashString("st") => Capabilities{}, // All supported

            std.hash_map.hashString("alacritty") => Capabilities{
                // Alacritty doesn't support CHT reliably in older versions
                .cht = false,
            },

            std.hash_map.hashString("screen") => Capabilities{
                // Screen doesn't support REP
                .rep = false,
            },

            std.hash_map.hashString("linux") => Capabilities{
                // Linux console has limited support
                .cht = false,
                .cbt = false,
                .rep = false,
                .sd = false,
                .su = false,
            },

            else => Capabilities{
                // Conservative defaults for unknown terminals
                .cht = false,
                .cbt = false,
                .rep = false,
            },
        };
    }
};

/// Cursor movement optimizer options
pub const OptimizerOptions = struct {
    /// Use relative cursor movements when possible
    relative_cursor: bool = true,
    /// Use hard tabs for optimization
    hard_tabs: bool = true,
    /// Use backspace characters for movement
    backspace: bool = true,
    /// Map newlines to CR+LF (ONLCR mode)
    map_nl: bool = false,
    /// Use alternate screen buffer
    alt_screen: bool = false,
};

/// Advanced cursor movement optimizer
pub const CursorOptimizer = struct {
    capabilities: Capabilities,
    tab_stops: TabStops,
    options: OptimizerOptions,
    screen_width: usize,
    screen_height: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, term_type: []const u8, width: usize, height: usize, options: OptimizerOptions) !Self {
        return Self{
            .capabilities = Capabilities.forTerminal(term_type),
            .tab_stops = try TabStops.init(allocator, width),
            .options = options,
            .screen_width = width,
            .screen_height = height,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tab_stops.deinit();
    }

    pub fn resize(self: *Self, width: usize, height: usize) !void {
        try self.tab_stops.resize(width);
        self.screen_width = width;
        self.screen_height = height;
    }

    /// Check if movement is considered "local" (worth optimizing)
    fn isLocal(self: Self, from_x: usize, from_y: usize, to_x: usize, to_y: usize) bool {
        const long_dist = 8; // Threshold for "long distance" movement

        return !(to_x > long_dist and
            to_x < self.screen_width - 1 - long_dist and
            (absDiff(to_y, from_y) + absDiff(to_x, from_x)) > long_dist);
    }

    /// Generate relative cursor movement sequence
    fn relativeMove(self: Self, allocator: std.mem.Allocator, from_x: usize, from_y: usize, to_x: usize, to_y: usize, use_tabs: bool, use_backspace: bool) ![]u8 {
        var seq = std.ArrayList(u8).init(allocator);
        errdefer seq.deinit();

        // Vertical movement
        if (to_y != from_y) {
            var ySeq: []const u8 = "";

            if (self.capabilities.vpa and !self.options.relative_cursor) {
                ySeq = try std.fmt.allocPrint(allocator, "\x1b[{d}d", .{to_y + 1});
            } else if (to_y > from_y) {
                const down_count = to_y - from_y;
                if (down_count == 1) {
                    ySeq = "\n";
                } else {
                    ySeq = try std.fmt.allocPrint(allocator, "\x1b[{d}B", .{down_count});
                }
            } else if (to_y < from_y) {
                const up_count = from_y - to_y;
                if (up_count == 1) {
                    ySeq = "\x1b[A";
                } else {
                    ySeq = try std.fmt.allocPrint(allocator, "\x1b[{d}A", .{up_count});
                }
            }

            try seq.appendSlice(ySeq);
        }

        // Horizontal movement
        if (to_x != from_x) {
            var xSeq: []const u8 = "";

            if (self.capabilities.hpa and !self.options.relative_cursor) {
                xSeq = try std.fmt.allocPrint(allocator, "\x1b[{d}G", .{to_x + 1});
            } else if (to_x > from_x) {
                var distance = to_x - from_x;
                var currentX = from_x;

                // Try using tabs if enabled
                if (use_tabs) {
                    var tabCount: usize = 0;
                    while (self.tab_stops.next(currentX) <= to_x and currentX < self.screen_width - 1) {
                        const next_tab = self.tab_stops.next(currentX);
                        if (next_tab == currentX) break; // No progress
                        currentX = next_tab;
                        tabCount += 1;
                    }

                    if (tabCount > 0) {
                        const tab_seq = try std.fmt.allocPrint(allocator, "{s}", .{"\t" ** @min(tabCount, 10)});
                        try seq.appendSlice(tab_seq);
                        distance = to_x - currentX;
                    }
                }

                if (distance > 0) {
                    if (distance == 1) {
                        xSeq = "\x1b[C";
                    } else {
                        xSeq = try std.fmt.allocPrint(allocator, "\x1b[{d}C", .{distance});
                    }
                }
            } else if (to_x < from_x) {
                var distance = from_x - to_x;
                var currentX = from_x;

                // Try backward tabs if supported
                if (use_tabs and self.capabilities.cbt) {
                    var tabCount: usize = 0;
                    while (self.tab_stops.prev(currentX) >= to_x and currentX > 0) {
                        const prev_tab = self.tab_stops.prev(currentX);
                        if (prev_tab == currentX) break; // No progress
                        currentX = prev_tab;
                        tabCount += 1;
                    }

                    if (tabCount > 0) {
                        const cbt_seq = try std.fmt.allocPrint(allocator, "\x1b[{d}Z", .{tabCount});
                        try seq.appendSlice(cbt_seq);
                        distance = currentX - to_x;
                    }
                }

                if (distance > 0) {
                    if (use_backspace and distance <= 4) {
                        // Use backspace for short distances
                        const bs_seq = try std.fmt.allocPrint(allocator, "{s}", .{"\x08" ** distance});
                        xSeq = bs_seq;
                    } else if (distance == 1) {
                        xSeq = "\x1b[D";
                    } else {
                        xSeq = try std.fmt.allocPrint(allocator, "\x1b[{d}D", .{distance});
                    }
                }
            }

            try seq.appendSlice(xSeq);
        }

        return seq.toOwnedSlice();
    }

    /// Generate optimized cursor movement sequence
    pub fn moveCursor(self: Self, allocator: std.mem.Allocator, from_x: usize, from_y: usize, to_x: usize, to_y: usize) ![]u8 {
        // Clamp coordinates to screen bounds
        const safe_from_x = @min(from_x, self.screen_width - 1);
        const safe_from_y = @min(from_y, self.screen_height - 1);
        const safe_to_x = @min(to_x, self.screen_width - 1);
        const safe_to_y = @min(to_y, self.screen_height - 1);

        // No movement needed
        if (safe_from_x == safe_to_x and safe_from_y == safe_to_y) {
            return try allocator.dupe(u8, "");
        }

        // Try direct positioning first for long distances
        if (!self.options.relative_cursor or !self.isLocal(safe_from_x, safe_from_y, safe_to_x, safe_to_y)) {
            return try std.fmt.allocPrint(allocator, "\x1b[{d};{d}H", .{ safe_to_y + 1, safe_to_x + 1 });
        }

        // Try different optimization combinations
        var bestSeq: []u8 = try std.fmt.allocPrint(allocator, "\x1b[{d};{d}H", .{ safe_to_y + 1, safe_to_x + 1 });

        // Method 1: Pure relative movement
        const rel_seq = self.relativeMove(allocator, safe_from_x, safe_from_y, safe_to_x, safe_to_y, false, false) catch bestSeq;
        if (rel_seq.len < bestSeq.len) {
            allocator.free(bestSeq);
            bestSeq = rel_seq;
        }

        // Method 2: Relative with tabs
        if (self.options.hard_tabs) {
            const tab_seq = self.relativeMove(allocator, safe_from_x, safe_from_y, safe_to_x, safe_to_y, true, false) catch bestSeq;
            if (tab_seq.len < bestSeq.len) {
                if (tab_seq.ptr != bestSeq.ptr) allocator.free(bestSeq);
                bestSeq = tab_seq;
            }
        }

        // Method 3: Relative with backspace
        if (self.options.backspace) {
            const bs_seq = self.relativeMove(allocator, safe_from_x, safe_from_y, safe_to_x, safe_to_y, false, true) catch bestSeq;
            if (bs_seq.len < bestSeq.len) {
                if (bs_seq.ptr != bestSeq.ptr) allocator.free(bestSeq);
                bestSeq = bs_seq;
            }
        }

        // Method 4: Carriage return + relative movement
        const cr_seq = blk: {
            var crBuf = std.ArrayList(u8).init(allocator);
            try crBuf.append('\r');
            const rel_part = self.relativeMove(allocator, 0, safe_from_y, safe_to_x, safe_to_y, self.options.hard_tabs, self.options.backspace) catch break :blk bestSeq;
            defer if (rel_part.ptr != bestSeq.ptr) allocator.free(rel_part);
            try crBuf.appendSlice(rel_part);
            break :blk try crBuf.toOwnedSlice();
        };

        if (cr_seq.len < bestSeq.len) {
            if (cr_seq.ptr != bestSeq.ptr) allocator.free(bestSeq);
            bestSeq = cr_seq;
        }

        return bestSeq;
    }

    /// Generate sequence to move to home position (0, 0)
    pub fn moveToHome(_: Self, allocator: std.mem.Allocator) ![]u8 {
        return try allocator.dupe(u8, "\x1b[H");
    }

    /// Generate sequence to save cursor position
    pub fn saveCursor(_: Self, allocator: std.mem.Allocator) ![]u8 {
        return try allocator.dupe(u8, "\x1b[s");
    }

    /// Generate sequence to restore cursor position
    pub fn restoreCursor(_: Self, allocator: std.mem.Allocator) ![]u8 {
        return try allocator.dupe(u8, "\x1b[u");
    }
};

/// Helper function to compute absolute difference between two usize values
fn absDiff(a: usize, b: usize) usize {
    return if (a >= b) a - b else b - a;
}

// ============================================================================
// FLUENT BUILDER API
// ============================================================================

/// CursorBuilder provides a fluent interface for building complex cursor movements
pub const CursorBuilder = struct {
    allocator: std.mem.Allocator,
    sequences: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) CursorBuilder {
        return CursorBuilder{
            .allocator = allocator,
            .sequences = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *CursorBuilder) void {
        for (self.sequences.items) |seq| {
            self.allocator.free(seq);
        }
        self.sequences.deinit();
    }

    pub fn up(self: *CursorBuilder, n: u32) !*CursorBuilder {
        const seq = try cursorUpString(self.allocator, n);
        try self.sequences.append(seq);
        return self;
    }

    pub fn down(self: *CursorBuilder, n: u32) !*CursorBuilder {
        const seq = try cursorDownString(self.allocator, n);
        try self.sequences.append(seq);
        return self;
    }

    pub fn left(self: *CursorBuilder, n: u32) !*CursorBuilder {
        const seq = try cursorBackwardString(self.allocator, n);
        try self.sequences.append(seq);
        return self;
    }

    pub fn right(self: *CursorBuilder, n: u32) !*CursorBuilder {
        const seq = try cursorForwardString(self.allocator, n);
        try self.sequences.append(seq);
        return self;
    }

    pub fn moveTo(self: *CursorBuilder, row: u32, col: u32) !*CursorBuilder {
        const seq = try cursorPositionString(self.allocator, row, col);
        try self.sequences.append(seq);
        return self;
    }

    pub fn home(self: *CursorBuilder) !*CursorBuilder {
        const seq = try self.allocator.dupe(u8, CURSOR_HOME_POSITION);
        try self.sequences.append(seq);
        return self;
    }

    pub fn save(self: *CursorBuilder) !*CursorBuilder {
        const seq = try self.allocator.dupe(u8, SAVE_CURSOR);
        try self.sequences.append(seq);
        return self;
    }

    pub fn restore(self: *CursorBuilder) !*CursorBuilder {
        const seq = try self.allocator.dupe(u8, RESTORE_CURSOR);
        try self.sequences.append(seq);
        return self;
    }

    pub fn style(self: *CursorBuilder, cursor_style: CursorStyle) !*CursorBuilder {
        const seq = try setCursorStyleString(self.allocator, cursor_style);
        try self.sequences.append(seq);
        return self;
    }

    pub fn build(self: *CursorBuilder) ![]u8 {
        return try std.mem.join(self.allocator, "", self.sequences.items);
    }
};

// ============================================================================
// CONVENIENCE FUNCTIONS AND ALIASES
// ============================================================================

// ANSI Standard Aliases
pub const CUU = cursorUp;
pub const CUD = cursorDown;
pub const CUF = cursorForward;
pub const CUB = cursorBackward;
pub const CNL = cursorNextLine;
pub const CPL = cursorPreviousLine;
pub const CHA = cursorHorizontalAbsolute;
pub const CUP = cursorPosition;
pub const CHT = cursorHorizontalForwardTab;
pub const ECH = eraseCharacter;
pub const CBT = cursorBackwardTab;
pub const VPA = verticalPositionAbsolute;
pub const VPR = verticalPositionRelative;
pub const HVP = horizontalVerticalPosition;
pub const DECSCUSR = setCursorStyle;
pub const HPA = horizontalPositionAbsolute;
pub const HPR = horizontalPositionRelative;

// Convenience functions without caps (for simple use cases)
pub fn moveCursorTo(writer: anytype, col: u16, row: u16) !void {
    try writer.print("\x1b[{};{}H", .{ row + 1, col + 1 });
}

pub fn moveCursorHome(writer: anytype) !void {
    try writer.writeAll(CURSOR_HOME_POSITION);
}

// ============================================================================
// COMMON POINTER SHAPES CONSTANTS
// ============================================================================

pub const PointerShapes = struct {
    pub const DEFAULT = "default";
    pub const COPY = "copy";
    pub const CROSSHAIR = "crosshair";
    pub const TEXT = "text";
    pub const WAIT = "wait";
    pub const EW_RESIZE = "ew-resize";
    pub const N_RESIZE = "n-resize";
    pub const NE_RESIZE = "ne-resize";
    pub const NW_RESIZE = "nw-resize";
    pub const S_RESIZE = "s-resize";
    pub const SE_RESIZE = "se-resize";
    pub const SW_RESIZE = "sw-resize";
    pub const W_RESIZE = "w-resize";
    pub const HAND = "hand";
    pub const HELP = "help";
};

// ============================================================================
// TESTS
// ============================================================================

test "cursor style enum values" {
    try std.testing.expect(@intFromEnum(CursorStyle.blinking_block_default) == 0);
    try std.testing.expect(@intFromEnum(CursorStyle.blinking_block) == 1);
    try std.testing.expect(@intFromEnum(CursorStyle.steady_block) == 2);
    try std.testing.expect(@intFromEnum(CursorStyle.steady_bar) == 6);
}

test "cursor position creation" {
    const pos = CursorPosition.init(5, 10);
    try std.testing.expectEqual(@as(u16, 6), pos.col); // 1-based
    try std.testing.expectEqual(@as(u16, 11), pos.row); // 1-based

    const zero_based = pos.to0Based();
    try std.testing.expectEqual(@as(u16, 5), zero_based.col);
    try std.testing.expectEqual(@as(u16, 10), zero_based.row);
}

test "cursor shape sequences" {
    try std.testing.expectEqualStrings("\x1b[2 q", CursorStyle.steady_block.toAnsiSequence());
    try std.testing.expectEqualStrings("\x1b[6 q", CursorStyle.steady_bar.toAnsiSequence());
}

test "cursor state management" {
    var cursor_state = CursorState.init(std.testing.allocator);
    defer cursor_state.deinit(std.testing.allocator);

    const pos1 = CursorPosition{ .col = 5, .row = 10 };
    cursor_state.position = pos1;

    try cursor_state.savePosition(std.testing.allocator);
    cursor_state.position = CursorPosition{ .col = 20, .row = 30 };

    const restored = cursor_state.restorePosition().?;
    try std.testing.expectEqual(pos1.col, restored.col);
    try std.testing.expectEqual(pos1.row, restored.row);
}

test "pointer shape names" {
    try std.testing.expectEqualStrings("pointer", PointerShape.pointer.shapeName());
    try std.testing.expectEqualStrings("crosshair", PointerShape.crosshair.shapeName());
    try std.testing.expectEqualStrings("not-allowed", PointerShape.not_allowed.shapeName());
}

test "cursor builder" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = CursorBuilder.init(allocator);
    defer builder.deinit();

    const result = try builder
        .save().?.moveTo(10, 20).?.down(3).?.right(5).?.restore().?.build();
    defer allocator.free(result);

    // Should contain save, move to 10,20, down 3, right 5, restore
    try testing.expect(std.mem.indexOf(u8, result, SAVE_CURSOR) != null);
    try testing.expect(std.mem.indexOf(u8, result, "\x1b[10;20H") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\x1b[3B") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\x1b[5C") != null);
    try testing.expect(std.mem.indexOf(u8, result, RESTORE_CURSOR) != null);
}

test "tab stops basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tabs = try TabStops.init(allocator, 40);
    defer tabs.deinit();

    try testing.expect(tabs.next(0) == 0);
    try testing.expect(tabs.next(1) == 8);
    try testing.expect(tabs.next(8) == 8);
    try testing.expect(tabs.next(9) == 16);

    try testing.expect(tabs.prev(16) == 16);
    try testing.expect(tabs.prev(15) == 8);
    try testing.expect(tabs.prev(7) == 0);
}

test "capabilities for different terminals" {
    const testing = std.testing;

    const xterm_caps = Capabilities.forTerminal("xterm-256color");
    try testing.expect(xterm_caps.vpa);
    try testing.expect(xterm_caps.hpa);

    const linux_caps = Capabilities.forTerminal("linux");
    try testing.expect(!linux_caps.cht);
    try testing.expect(!linux_caps.cbt);

    const alacritty_caps = Capabilities.forTerminal("alacritty");
    try testing.expect(!alacritty_caps.cht);
}

test "cursor movement optimization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var optimizer = try CursorOptimizer.init(allocator, "xterm", 80, 24, .{});
    defer optimizer.deinit();

    // Test simple movement
    const seq = try optimizer.moveCursor(allocator, 0, 0, 5, 0);
    defer allocator.free(seq);

    try testing.expect(seq.len > 0);
}

test "local vs long distance detection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var optimizer = try CursorOptimizer.init(allocator, "xterm", 80, 24, .{});
    defer optimizer.deinit();

    // Short distance should be local
    try testing.expect(optimizer.isLocal(0, 0, 5, 0));

    // Long distance should not be local
    try testing.expect(!optimizer.isLocal(0, 0, 40, 10));
}

test "tab optimization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var optimizer = try CursorOptimizer.init(allocator, "xterm", 80, 24, .{ .hard_tabs = true });
    defer optimizer.deinit();

    // Moving to a tab stop should be shorter than individual moves
    const seq = try optimizer.moveCursor(allocator, 0, 0, 16, 0);
    defer allocator.free(seq);

    try testing.expect(seq.len > 0);
    try testing.expect(seq.len <= 3); // Should be very short with tabs
}

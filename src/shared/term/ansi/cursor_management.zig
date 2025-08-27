const std = @import("std");
const advanced_color = @import("color_conversion_extra.zig");

/// Advanced cursor management for modern terminals
/// Supports cursor styling, positioning, visibility, and color changes
/// Cursor shape styles supported by modern terminals
pub const CursorShape = enum(u8) {
    default = 0, // Terminal default
    block_blink = 1, // Blinking block (default in most terminals)
    block_steady = 2, // Steady block
    underline_blink = 3, // Blinking underline
    underline_steady = 4, // Steady underline
    bar_blink = 5, // Blinking vertical bar (I-beam)
    bar_steady = 6, // Steady vertical bar (I-beam)

    /// Get ANSI escape sequence for this cursor shape
    pub fn toAnsiSequence(self: CursorShape) []const u8 {
        return switch (self) {
            .default => "\x1b[0 q",
            .block_blink => "\x1b[1 q",
            .block_steady => "\x1b[2 q",
            .underline_blink => "\x1b[3 q",
            .underline_steady => "\x1b[4 q",
            .bar_blink => "\x1b[5 q",
            .bar_steady => "\x1b[6 q",
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
    shape: CursorShape = .default,
    blink: bool = true,
    color: ?advanced_color.RGBColor = null,

    /// Save current position for later restoration
    saved_positions: std.ArrayList(CursorPosition),

    pub fn init(_: std.mem.Allocator) CursorState {
        return CursorState{
            .saved_positions = std.ArrayList(CursorPosition){},
        };
    }

    pub fn deinit(self: *CursorState, allocator: std.mem.Allocator) void {
        self.saved_positions.deinit(allocator);
    }

    /// Save current position to stack
    pub fn savePosition(self: *CursorState, allocator: std.mem.Allocator) !void {
        try self.saved_positions.append(allocator, self.position);
    }

    /// Restore last saved position
    pub fn restorePosition(self: *CursorState, allocator: std.mem.Allocator) ?CursorPosition {
        _ = allocator; // Unused but kept for API consistency
        if (self.saved_positions.items.len == 0) return null;
        return self.saved_positions.pop();
    }
};

/// Advanced cursor controller with modern terminal support
pub const CursorController = struct {
    state: CursorState,
    writer: *std.Io.Writer,
    supports_cursor_color: bool,
    supports_cursor_shapes: bool,
    supports_pointer_shapes: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, writer: *std.Io.Writer) CursorController {
        return CursorController{
            .state = CursorState.init(allocator),
            .writer = writer,
            .supports_cursor_color = true, // Assume support by default
            .supports_cursor_shapes = true,
            .supports_pointer_shapes = false, // Less common
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CursorController) void {
        self.state.deinit(self.allocator);
    }

    /// Move cursor to absolute position
    pub fn moveTo(self: *CursorController, col: u16, row: u16) !void {
        self.state.position = CursorPosition.init(col, row);
        try self.writer.print("\x1b[{};{}H", .{ self.state.position.row, self.state.position.col });
    }

    /// Move cursor relative to current position
    pub fn moveRelative(self: *CursorController, delta_col: i16, delta_row: i16) !void {
        const current = self.state.position.to0Based();
        const new_col = @as(u16, @intCast(@max(0, @as(i32, current.col) + delta_col)));
        const new_row = @as(u16, @intCast(@max(0, @as(i32, current.row) + delta_row)));
        try self.moveTo(new_col, new_row);
    }

    /// Move cursor up by n lines
    pub fn moveUp(self: *CursorController, n: u16) !void {
        if (n == 0) return;
        try self.writer.print("\x1b[{}A", .{n});
        self.state.position.row = @max(1, @as(i32, self.state.position.row) - @as(i32, n));
    }

    /// Move cursor down by n lines
    pub fn moveDown(self: *CursorController, n: u16) !void {
        if (n == 0) return;
        try self.writer.print("\x1b[{}B", .{n});
        self.state.position.row = self.state.position.row + n;
    }

    /// Move cursor right by n columns
    pub fn moveRight(self: *CursorController, n: u16) !void {
        if (n == 0) return;
        try self.writer.print("\x1b[{}C", .{n});
        self.state.position.col = self.state.position.col + n;
    }

    /// Move cursor left by n columns
    pub fn moveLeft(self: *CursorController, n: u16) !void {
        if (n == 0) return;
        try self.writer.print("\x1b[{}D", .{n});
        self.state.position.col = @max(1, @as(i32, self.state.position.col) - @as(i32, n));
    }

    /// Move to beginning of current line
    pub fn moveToLineStart(self: *CursorController) !void {
        try self.writer.writeAll("\x1b[G");
        self.state.position.col = 1;
    }

    /// Move to beginning of next line
    pub fn moveToNextLine(self: *CursorController, n: u16) !void {
        if (n == 0) return;
        if (n == 1) {
            try self.writer.writeAll("\x1b[E");
        } else {
            try self.writer.print("\x1b[{}E", .{n});
        }
        self.state.position.row = self.state.position.row + n;
        self.state.position.col = 1;
    }

    /// Move to beginning of previous line
    pub fn moveToPrevLine(self: *CursorController, n: u16) !void {
        if (n == 0) return;
        if (n == 1) {
            try self.writer.writeAll("\x1b[F");
        } else {
            try self.writer.print("\x1b[{}F", .{n});
        }
        self.state.position.row = @max(1, @as(i32, self.state.position.row) - @as(i32, n));
        self.state.position.col = 1;
    }

    /// Move to specific column on current row
    pub fn moveToColumn(self: *CursorController, col: u16) !void {
        try self.writer.print("\x1b[{}G", .{col + 1}); // Convert to 1-based
        self.state.position.col = col + 1;
    }

    /// Show or hide cursor
    pub fn setVisible(self: *CursorController, visible: bool) !void {
        self.state.visible = visible;
        if (visible) {
            try self.writer.writeAll("\x1b[?25h"); // Show cursor
        } else {
            try self.writer.writeAll("\x1b[?25l"); // Hide cursor
        }
    }

    /// Set cursor shape if supported
    pub fn setShape(self: *CursorController, shape: CursorShape) !void {
        if (!self.supports_cursor_shapes) return;

        self.state.shape = shape;
        try self.writer.writeAll(shape.toAnsiSequence());
    }

    /// Set cursor color if supported
    pub fn setColor(self: *CursorController, color: ?advanced_color.RGBColor) !void {
        if (!self.supports_cursor_color) return;

        self.state.color = color;
        if (color) |c| {
            // Set cursor color using OSC escape sequence
            try self.writer.print("\x1b]12;#{:02x}{:02x}{:02x}\x1b\\", .{ c.r, c.g, c.b });
        } else {
            // Reset to default cursor color
            try self.writer.writeAll("\x1b]112\x1b\\");
        }
    }

    /// Set mouse pointer shape if supported
    pub fn setPointerShape(self: *CursorController, shape: PointerShape) !void {
        if (!self.supports_pointer_shapes) return;

        try self.writer.print("\x1b]22;{s}\x1b\\", .{shape.shapeName()});
    }

    /// Save current cursor position
    pub fn savePosition(self: *CursorController) !void {
        try self.writer.writeAll("\x1b[s"); // Save position (ANSI)
        try self.state.savePosition(self.allocator);
    }

    /// Restore saved cursor position
    pub fn restorePosition(self: *CursorController) !void {
        try self.writer.writeAll("\x1b[u"); // Restore position (ANSI)
        if (self.state.restorePosition(self.allocator)) |pos| {
            self.state.position = pos;
        }
    }

    /// Save cursor position using DEC sequence (more reliable)
    pub fn saveDECPosition(self: *CursorController) !void {
        try self.writer.writeAll("\x1b7"); // Save cursor (DEC)
        try self.state.savePosition(self.allocator);
    }

    /// Restore cursor position using DEC sequence
    pub fn restoreDECPosition(self: *CursorController) !void {
        try self.writer.writeAll("\x1b8"); // Restore cursor (DEC)
        if (self.state.restorePosition(self.allocator)) |pos| {
            self.state.position = pos;
        }
    }

    /// Request current cursor position from terminal
    pub fn requestPosition(self: *CursorController) !void {
        try self.writer.writeAll("\x1b[6n"); // Device Status Report
        // Note: Response will be sent to stdin as "\x1b[row;colR"
        // Application needs to read and parse this response
    }

    /// Set cursor to specific tab stop
    pub fn moveToTabStop(self: *CursorController, n: u16) !void {
        if (n == 0) return;
        try self.writer.print("\x1b[{}I", .{n}); // Forward tab
    }

    /// Move backward to tab stop
    pub fn moveToBackTabStop(self: *CursorController, n: u16) !void {
        if (n == 0) return;
        try self.writer.print("\x1b[{}Z", .{n}); // Backward tab
    }

    /// Get current cursor state (for serialization/debugging)
    pub fn getState(self: *const CursorController) CursorState {
        return self.state;
    }

    /// Restore cursor state from saved state
    pub fn setState(self: *CursorController, new_state: CursorState) !void {
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
    pub fn enableBlinking(self: *CursorController) !void {
        self.state.blink = true;
        try self.writer.writeAll("\x1b[?12h");
    }

    /// Disable cursor blinking
    pub fn disableBlinking(self: *CursorController) !void {
        self.state.blink = false;
        try self.writer.writeAll("\x1b[?12l");
    }

    /// Reset cursor to terminal default
    pub fn reset(self: *CursorController) !void {
        try self.setVisible(true);
        try self.setShape(.default);
        try self.setColor(null);
        try self.enableBlinking();
        try self.moveTo(0, 0);
    }

    /// Flush any pending output to ensure cursor changes are visible
    pub fn flush(self: *CursorController) !void {
        try self.writer.flush();
    }
};

/// Convenience functions for common cursor operations
pub fn hideCursor(writer: *std.Io.Writer) !void {
    try writer.writeAll("\x1b[?25l");
}

pub fn showCursor(writer: *std.Io.Writer) !void {
    try writer.writeAll("\x1b[?25h");
}

pub fn setCursorShape(writer: *std.Io.Writer, shape: CursorShape) !void {
    try writer.writeAll(shape.toAnsiSequence());
}

pub fn moveCursorTo(writer: *std.Io.Writer, col: u16, row: u16) !void {
    try writer.print("\x1b[{};{}H", .{ row + 1, col + 1 });
}

pub fn moveCursorHome(writer: *std.Io.Writer) !void {
    try writer.writeAll("\x1b[H");
}

pub fn clearFromCursor(writer: *std.Io.Writer) !void {
    try writer.writeAll("\x1b[0J"); // Clear from cursor to end of screen
}

pub fn clearToCursor(writer: *std.Io.Writer) !void {
    try writer.writeAll("\x1b[1J"); // Clear from start of screen to cursor
}

pub fn clearScreen(writer: *std.Io.Writer) !void {
    try writer.writeAll("\x1b[2J"); // Clear entire screen
}

pub fn clearLine(writer: *std.Io.Writer) !void {
    try writer.writeAll("\x1b[2K"); // Clear entire line
}

pub fn clearToEndOfLine(writer: *std.Io.Writer) !void {
    try writer.writeAll("\x1b[0K"); // Clear from cursor to end of line
}

pub fn clearToStartOfLine(writer: *std.Io.Writer) !void {
    try writer.writeAll("\x1b[1K"); // Clear from start of line to cursor
}

// Tests
const testing = std.testing;

test "cursor position creation" {
    const pos = CursorPosition.init(5, 10);
    try testing.expectEqual(@as(u16, 6), pos.col); // 1-based
    try testing.expectEqual(@as(u16, 11), pos.row); // 1-based

    const zero_based = pos.to0Based();
    try testing.expectEqual(@as(u16, 5), zero_based.col);
    try testing.expectEqual(@as(u16, 10), zero_based.row);
}

test "cursor shape sequences" {
    try testing.expectEqualStrings("\x1b[2 q", CursorShape.block_steady.toAnsiSequence());
    try testing.expectEqualStrings("\x1b[6 q", CursorShape.bar_steady.toAnsiSequence());
}

test "cursor state management" {
    var cursor_state = CursorState.init(testing.allocator);
    defer cursor_state.deinit(testing.allocator);

    const pos1 = CursorPosition{ .col = 5, .row = 10 };
    cursor_state.position = pos1;

    try cursor_state.savePosition(testing.allocator);
    cursor_state.position = CursorPosition{ .col = 20, .row = 30 };

    const restored = cursor_state.restorePosition(testing.allocator).?;
    try testing.expectEqual(pos1.col, restored.col);
    try testing.expectEqual(pos1.row, restored.row);
}

test "pointer shape names" {
    try testing.expectEqualStrings("pointer", PointerShape.pointer.shapeName());
    try testing.expectEqualStrings("crosshair", PointerShape.crosshair.shapeName());
    try testing.expectEqualStrings("not-allowed", PointerShape.not_allowed.shapeName());
}

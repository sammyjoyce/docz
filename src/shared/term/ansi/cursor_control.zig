const std = @import("std");

/// Enhanced cursor control sequences based on standard ANSI/VT100 cursor control sequences
/// Provides comprehensive VT100/VT220/xterm cursor manipulation capabilities.

// ==== Save and Restore Cursor ====

/// SaveCursor (DECSC) saves the current cursor position
/// ESC 7
pub const SAVE_CURSOR = "\x1b7";
pub const DECSC = SAVE_CURSOR;

/// RestoreCursor (DECRC) restores the cursor position
/// ESC 8
pub const RESTORE_CURSOR = "\x1b8";
pub const DECRC = RESTORE_CURSOR;

/// SaveCurrentCursorPosition (SCOSC) saves cursor for SCO console mode
/// CSI s
pub const SAVE_CURRENT_CURSOR_POSITION = "\x1b[s";
pub const SCOSC = SAVE_CURRENT_CURSOR_POSITION;

/// RestoreCurrentCursorPosition (SCORC) restores cursor for SCO console mode
/// CSI u
pub const RESTORE_CURRENT_CURSOR_POSITION = "\x1b[u";
pub const SCORC = RESTORE_CURRENT_CURSOR_POSITION;

// ==== Cursor Movement ====

/// CursorUp (CUU) moves cursor up n cells
/// CSI n A
pub fn cursorUp(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 1) {
        return allocator.dupe(u8, CUU1);
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}A", .{n});
}

/// Shorthand for cursorUp
pub fn cuu(allocator: std.mem.Allocator, n: u32) ![]u8 {
    return cursorUp(allocator, n);
}

/// CUU1 moves cursor up one cell
pub const CUU1 = "\x1b[A";

/// CursorDown (CUD) moves cursor down n cells
/// CSI n B
pub fn cursorDown(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 1) {
        return allocator.dupe(u8, CUD1);
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}B", .{n});
}

/// Shorthand for cursorDown
pub fn cud(allocator: std.mem.Allocator, n: u32) ![]u8 {
    return cursorDown(allocator, n);
}

/// CUD1 moves cursor down one cell
pub const CUD1 = "\x1b[B";

/// CursorForward (CUF) moves cursor right n cells
/// CSI n C
pub fn cursorForward(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 1) {
        return allocator.dupe(u8, CUF1);
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}C", .{n});
}

/// Shorthand for cursorForward
pub fn cuf(allocator: std.mem.Allocator, n: u32) ![]u8 {
    return cursorForward(allocator, n);
}

/// CUF1 moves cursor right one cell
pub const CUF1 = "\x1b[C";

/// CursorBackward (CUB) moves cursor left n cells
/// CSI n D
pub fn cursorBackward(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 1) {
        return allocator.dupe(u8, CUB1);
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}D", .{n});
}

/// Shorthand for cursorBackward
pub fn cub(allocator: std.mem.Allocator, n: u32) ![]u8 {
    return cursorBackward(allocator, n);
}

/// CUB1 moves cursor left one cell
pub const CUB1 = "\x1b[D";

// ==== Line Movement ====

/// CursorNextLine (CNL) moves cursor to beginning of next line n times
/// CSI n E
pub fn cursorNextLine(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 1) {
        return allocator.dupe(u8, "\x1b[E");
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}E", .{n});
}

/// Shorthand for cursorNextLine
pub fn cnl(allocator: std.mem.Allocator, n: u32) ![]u8 {
    return cursorNextLine(allocator, n);
}

/// CursorPreviousLine (CPL) moves cursor to beginning of previous line n times
/// CSI n F
pub fn cursorPreviousLine(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 1) {
        return allocator.dupe(u8, "\x1b[F");
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}F", .{n});
}

/// Shorthand for cursorPreviousLine
pub fn cpl(allocator: std.mem.Allocator, n: u32) ![]u8 {
    return cursorPreviousLine(allocator, n);
}

// ==== Absolute Positioning ====

/// CursorHorizontalAbsolute (CHA) moves cursor to given column
/// CSI n G
pub fn cursorHorizontalAbsolute(allocator: std.mem.Allocator, col: u32) ![]u8 {
    if (col <= 0) {
        return allocator.dupe(u8, "\x1b[G");
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}G", .{col});
}

/// Shorthand for cursorHorizontalAbsolute
pub fn cha(allocator: std.mem.Allocator, col: u32) ![]u8 {
    return cursorHorizontalAbsolute(allocator, col);
}

/// CursorPosition (CUP) sets cursor to given row and column
/// CSI row ; col H
pub fn cursorPosition(allocator: std.mem.Allocator, row: u32, col: u32) ![]u8 {
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

/// Shorthand for cursorPosition
pub fn cup(allocator: std.mem.Allocator, row: u32, col: u32) ![]u8 {
    return cursorPosition(allocator, row, col);
}

/// CursorHomePosition moves cursor to upper left corner
pub const CURSOR_HOME_POSITION = "\x1b[H";

/// VerticalPositionAbsolute (VPA) moves cursor to given row
/// CSI n d
pub fn verticalPositionAbsolute(allocator: std.mem.Allocator, row: u32) ![]u8 {
    if (row <= 0) {
        return allocator.dupe(u8, "\x1b[d");
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}d", .{row});
}

/// Shorthand for verticalPositionAbsolute
pub fn vpa(allocator: std.mem.Allocator, row: u32) ![]u8 {
    return verticalPositionAbsolute(allocator, row);
}

/// VerticalPositionRelative (VPR) moves cursor down n rows relatively
/// CSI n e
pub fn verticalPositionRelative(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 1) {
        return allocator.dupe(u8, "\x1b[e");
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}e", .{n});
}

/// Shorthand for verticalPositionRelative
pub fn vpr(allocator: std.mem.Allocator, n: u32) ![]u8 {
    return verticalPositionRelative(allocator, n);
}

/// HorizontalVerticalPosition (HVP) moves cursor to given row and column
/// CSI row ; col f
pub fn horizontalVerticalPosition(allocator: std.mem.Allocator, row: u32, col: u32) ![]u8 {
    if (row <= 0 and col <= 0) {
        return allocator.dupe(u8, HORIZONTAL_VERTICAL_HOME_POSITION);
    }

    if (row <= 0) {
        return try std.fmt.allocPrint(allocator, "\x1b[;{}f", .{col});
    } else if (col <= 0) {
        return try std.fmt.allocPrint(allocator, "\x1b[{};f", .{row});
    } else {
        return try std.fmt.allocPrint(allocator, "\x1b[{};{}f", .{ row, col });
    }
}

/// Shorthand for horizontalVerticalPosition
pub fn hvp(allocator: std.mem.Allocator, row: u32, col: u32) ![]u8 {
    return horizontalVerticalPosition(allocator, row, col);
}

/// HorizontalVerticalHomePosition moves cursor to upper left corner
pub const HORIZONTAL_VERTICAL_HOME_POSITION = "\x1b[f";

// ==== Tab Handling ====

/// CursorHorizontalForwardTab (CHT) moves cursor to next tab stop n times
/// CSI n I
pub fn cursorHorizontalForwardTab(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 1) {
        return allocator.dupe(u8, "\x1b[I");
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}I", .{n});
}

/// Shorthand for cursorHorizontalForwardTab
pub fn cht(allocator: std.mem.Allocator, n: u32) ![]u8 {
    return cursorHorizontalForwardTab(allocator, n);
}

/// CursorBackwardTab (CBT) moves cursor to previous tab stop n times
/// CSI n Z
pub fn cursorBackwardTab(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 1) {
        return allocator.dupe(u8, "\x1b[Z");
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}Z", .{n});
}

/// Shorthand for cursorBackwardTab
pub fn cbt(allocator: std.mem.Allocator, n: u32) ![]u8 {
    return cursorBackwardTab(allocator, n);
}

// ==== Position Reporting ====

/// RequestCursorPositionReport requests current cursor position
/// CSI 6 n
pub const REQUEST_CURSOR_POSITION_REPORT = "\x1b[6n";

/// RequestExtendedCursorPositionReport (DECXCPR) requests cursor position with page
/// CSI ? 6 n
pub const REQUEST_EXTENDED_CURSOR_POSITION_REPORT = "\x1b[?6n";

// ==== Character Manipulation ====

/// EraseCharacter (ECH) erases n characters from screen
/// CSI n X
pub fn eraseCharacter(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 1) {
        return allocator.dupe(u8, "\x1b[X");
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}X", .{n});
}

/// Shorthand for eraseCharacter
pub fn ech(allocator: std.mem.Allocator, n: u32) ![]u8 {
    return eraseCharacter(allocator, n);
}

// ==== Cursor Style ====

/// Cursor styles for setCursorStyle
pub const CursorStyle = enum(u8) {
    blinking_block_default = 0,
    blinking_block = 1,
    steady_block = 2,
    blinking_underline = 3,
    steady_underline = 4,
    blinking_bar = 5,
    steady_bar = 6,
};

/// SetCursorStyle (DECSCUSR) changes cursor style
/// CSI Ps SP q
pub fn setCursorStyle(allocator: std.mem.Allocator, style: CursorStyle) ![]u8 {
    const style_num = @intFromEnum(style);
    return try std.fmt.allocPrint(allocator, "\x1b[{} q", .{style_num});
}

/// Shorthand for setCursorStyle
pub fn decscusr(allocator: std.mem.Allocator, style: CursorStyle) ![]u8 {
    return setCursorStyle(allocator, style);
}

// ==== Scrolling and Index ====

/// ReverseIndex (RI) moves cursor up one line, scrolls if at top
/// ESC M
pub const REVERSE_INDEX = "\x1bM";
pub const RI = REVERSE_INDEX;

/// Index (IND) moves cursor down one line, scrolls if at bottom
/// ESC D
pub const INDEX = "\x1bD";
pub const IND = INDEX;

// ==== Position Relative ====

/// HorizontalPositionAbsolute (HPA) moves cursor to given column
/// CSI n `
pub fn horizontalPositionAbsolute(allocator: std.mem.Allocator, col: u32) ![]u8 {
    if (col <= 0) {
        return allocator.dupe(u8, "\x1b[`");
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}`", .{col});
}

/// Shorthand for horizontalPositionAbsolute
pub fn hpa(allocator: std.mem.Allocator, col: u32) ![]u8 {
    return horizontalPositionAbsolute(allocator, col);
}

/// HorizontalPositionRelative (HPR) moves cursor right n columns relatively
/// CSI n a
pub fn horizontalPositionRelative(allocator: std.mem.Allocator, n: u32) ![]u8 {
    if (n <= 0) {
        return allocator.dupe(u8, "\x1b[a");
    }
    return try std.fmt.allocPrint(allocator, "\x1b[{}a", .{n});
}

/// Shorthand for horizontalPositionRelative
pub fn hpr(allocator: std.mem.Allocator, n: u32) ![]u8 {
    return horizontalPositionRelative(allocator, n);
}

// ==== Pointer/Mouse Cursor ====

/// SetPointerShape changes the mouse pointer cursor shape
/// OSC 22 ; Pt ST / OSC 22 ; Pt BEL
pub fn setPointerShape(allocator: std.mem.Allocator, shape: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "\x1b]22;{s}\x07", .{shape});
}

/// Common pointer shapes
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

// ==== Convenience Functions ====

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
        const seq = try cursorUp(self.allocator, n);
        try self.sequences.append(seq);
        return self;
    }

    pub fn down(self: *CursorBuilder, n: u32) !*CursorBuilder {
        const seq = try cursorDown(self.allocator, n);
        try self.sequences.append(seq);
        return self;
    }

    pub fn left(self: *CursorBuilder, n: u32) !*CursorBuilder {
        const seq = try cursorBackward(self.allocator, n);
        try self.sequences.append(seq);
        return self;
    }

    pub fn right(self: *CursorBuilder, n: u32) !*CursorBuilder {
        const seq = try cursorForward(self.allocator, n);
        try self.sequences.append(seq);
        return self;
    }

    pub fn moveTo(self: *CursorBuilder, row: u32, col: u32) !*CursorBuilder {
        const seq = try cursorPosition(self.allocator, row, col);
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
        const seq = try setCursorStyle(self.allocator, cursor_style);
        try self.sequences.append(seq);
        return self;
    }

    pub fn build(self: *CursorBuilder) ![]u8 {
        return try std.mem.join(self.allocator, "", self.sequences.items);
    }
};

// ==== Tests ====

test "cursor movement functions" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test cursor up
    {
        const seq1 = try cursorUp(allocator, 1);
        defer allocator.free(seq1);
        try testing.expectEqualSlices(u8, CUU1, seq1);

        const seq5 = try cursorUp(allocator, 5);
        defer allocator.free(seq5);
        try testing.expectEqualSlices(u8, "\x1b[5A", seq5);
    }

    // Test cursor position
    {
        const seq_home = try cursorPosition(allocator, 0, 0);
        defer allocator.free(seq_home);
        try testing.expectEqualSlices(u8, CURSOR_HOME_POSITION, seq_home);

        const seq_pos = try cursorPosition(allocator, 10, 20);
        defer allocator.free(seq_pos);
        try testing.expectEqualSlices(u8, "\x1b[10;20H", seq_pos);
    }

    // Test cursor style
    {
        const seq_block = try setCursorStyle(allocator, .steady_block);
        defer allocator.free(seq_block);
        try testing.expectEqualSlices(u8, "\x1b[2 q", seq_block);

        const seq_bar = try setCursorStyle(allocator, .blinking_bar);
        defer allocator.free(seq_bar);
        try testing.expectEqualSlices(u8, "\x1b[5 q", seq_bar);
    }

    // Test pointer shape
    {
        const seq_hand = try setPointerShape(allocator, PointerShapes.HAND);
        defer allocator.free(seq_hand);
        try testing.expectEqualSlices(u8, "\x1b]22;hand\x07", seq_hand);
    }
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

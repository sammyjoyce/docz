const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

// Cursor styles for DECSCUSR (Set Cursor Style)
pub const CursorStyle = enum(u8) {
    blinking_block_default = 0,
    blinking_block = 1,
    steady_block = 2,
    blinking_underline = 3,
    steady_underline = 4,
    blinking_bar = 5, // xterm
    steady_bar = 6, // xterm
};

// Enhanced cursor control functions following Charmbracelet patterns

// DECSC - Save cursor position (ESC 7)
pub fn saveCursorDECSC(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b7");
}

// DECRC - Restore cursor position (ESC 8)
pub fn restoreCursorDECRC(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b8");
}

// Request Cursor Position Report (CPR) - CSI 6 n
pub fn requestCursorPositionReport(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[6n");
}

// Request Extended Cursor Position Report (DECXCPR) - CSI ? 6 n
pub fn requestExtendedCursorPositionReport(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[?6n");
}

// Cursor Up (CUU) with optimized single-cell movement - CSI n A
pub fn cursorUp(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) return; // No movement
    if (n == 1) {
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[A");
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

// Cursor Down (CUD) with optimized single-cell movement - CSI n B
pub fn cursorDown(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) return; // No movement
    if (n == 1) {
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[B");
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

// Cursor Forward (CUF) with optimized single-cell movement - CSI n C
pub fn cursorForward(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) return; // No movement
    if (n == 1) {
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[C");
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

// Cursor Backward (CUB) with optimized single-cell movement - CSI n D
pub fn cursorBackward(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) return; // No movement
    if (n == 1) {
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[D");
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

// Cursor Next Line (CNL) - CSI n E
pub fn cursorNextLine(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) return; // No movement
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

// Cursor Previous Line (CPL) - CSI n F
pub fn cursorPreviousLine(writer: anytype, caps: TermCaps, n: u32) !void {
    if (n == 0) return; // No movement
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

// Cursor Horizontal Absolute (CHA) - CSI n G
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

// Cursor Position (CUP) - CSI row ; col H
pub fn cursorPosition(writer: anytype, caps: TermCaps, row: u32, col: u32) !void {
    if (row <= 1 and col <= 1) {
        // Home position optimization
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[H");
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

// Cursor Home Position - CSI H (equivalent to CSI 1;1H)
pub fn cursorHomePosition(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[H");
}

// Cursor Horizontal Forward Tab (CHT) - CSI n I
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

// Erase Character (ECH) - CSI n X
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

// Cursor Backward Tab (CBT) - CSI n Z
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

// Vertical Position Absolute (VPA) - CSI n d
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

// Vertical Position Relative (VPR) - CSI n e
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

// Horizontal Vertical Position (HVP) - CSI row ; col f
pub fn horizontalVerticalPosition(writer: anytype, caps: TermCaps, row: u32, col: u32) !void {
    if (row <= 1 and col <= 1) {
        // Home position optimization
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[f");
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

// Save Current Cursor Position (SCOSC) - CSI s
pub fn saveCurrentCursorPosition(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[s");
}

// Restore Current Cursor Position (SCORC) - CSI u
pub fn restoreCurrentCursorPosition(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[u");
}

// Set Cursor Style (DECSCUSR) - CSI Ps SP q
pub fn setCursorStyle(writer: anytype, caps: TermCaps, style: CursorStyle) !void {
    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{@intFromEnum(style)}) catch unreachable;
    _ = w.write(" q") catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Set Pointer Shape - OSC 22 ; shape BEL
pub fn setPointerShape(writer: anytype, caps: TermCaps, allocator: std.mem.Allocator, shape: []const u8) !void {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try buf.appendSlice("\x1b]22;");
    try buf.appendSlice(shape);
    try buf.append(0x07); // BEL

    try passthrough.writeWithPassthrough(writer, caps, buf.items);
}

// Reverse Index (RI) - ESC M
pub fn reverseIndex(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1bM");
}

// Horizontal Position Absolute (HPA) - CSI n `
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

// Horizontal Position Relative (HPR) - CSI n a
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

// Index (IND) - ESC D
pub fn index(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1bD");
}

// Convenience aliases matching Charmbracelet naming
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
pub const SCOSC = saveCurrentCursorPosition;
pub const SCORC = restoreCurrentCursorPosition;
pub const DECSCUSR = setCursorStyle;
pub const DECSC = saveCursorDECSC;
pub const DECRC = restoreCursorDECRC;
pub const HPA = horizontalPositionAbsolute;
pub const HPR = horizontalPositionRelative;
pub const IND = index;
pub const RI = reverseIndex;

// Constants for common sequences
pub const CUU1 = "\x1b[A";
pub const CUD1 = "\x1b[B";
pub const CUF1 = "\x1b[C";
pub const CUB1 = "\x1b[D";
pub const CURSOR_HOME = "\x1b[H";
pub const SAVE_CURSOR = "\x1b7";
pub const RESTORE_CURSOR = "\x1b8";
pub const REQUEST_CURSOR_POSITION = "\x1b[6n";
pub const REQUEST_EXTENDED_CURSOR_POSITION = "\x1b[?6n";

test "cursor style enum values" {
    try std.testing.expect(@intFromEnum(CursorStyle.blinking_block_default) == 0);
    try std.testing.expect(@intFromEnum(CursorStyle.blinking_block) == 1);
    try std.testing.expect(@intFromEnum(CursorStyle.steady_block) == 2);
    try std.testing.expect(@intFromEnum(CursorStyle.steady_bar) == 6);
}

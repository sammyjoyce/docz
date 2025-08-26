const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

fn writeCsi2(writer: anytype, caps: TermCaps, code: u8, a: u32, b: u32) !void {
    var tmp: [48]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d};{d}", .{ a, b }) catch unreachable;
    _ = w.writeByte(code) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

fn writeCsi1(writer: anytype, caps: TermCaps, code: u8, n: u32) !void {
    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{if (n == 0) 1 else n}) catch unreachable;
    _ = w.writeByte(code) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

fn writeCsi0(writer: anytype, caps: TermCaps, code: u8) !void {
    var tmp: [8]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = w.writeByte(code) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Cursor position (CUP): CSI row ; col H
pub fn setCursorPosition(writer: anytype, caps: TermCaps, row: u32, col: u32) !void {
    try writeCsi2(writer, caps, 'H', if (row == 0) 1 else row, if (col == 0) 1 else col);
}

// Cursor Up (CUU): CSI n A (n defaults to 1)
pub fn cursorUp(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'A', n);
}

// Cursor Down (CUD): CSI n B (n defaults to 1)
pub fn cursorDown(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'B', n);
}

// Cursor Forward (CUF): CSI n C (n defaults to 1)
pub fn cursorForward(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'C', n);
}

// Cursor Back (CUB): CSI n D (n defaults to 1)
pub fn cursorBack(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'D', n);
}

// Cursor Next Line (CNL): CSI n E
pub fn cursorNextLine(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'E', n);
}

// Cursor Previous Line (CPL): CSI n F
pub fn cursorPrevLine(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'F', n);
}

// Cursor Horizontal Absolute (CHA): CSI n G (column)
pub fn setCursorColumn(writer: anytype, caps: TermCaps, column: u32) !void {
    try writeCsi1(writer, caps, 'G', if (column == 0) 1 else column);
}

// Save/Restore cursor (CSI s / CSI u)
pub fn saveCursor(writer: anytype, caps: TermCaps) !void {
    try writeCsi0(writer, caps, 's');
}

pub fn restoreCursor(writer: anytype, caps: TermCaps) !void {
    try writeCsi0(writer, caps, 'u');
}

// Erase Character (ECH): CSI n X (default 1)
pub fn eraseCharacters(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'X', if (n == 0) 1 else n);
}

// Vertical Position Absolute (VPA): CSI n d (row, default 1)
pub fn setCursorRow(writer: anytype, caps: TermCaps, row: u32) !void {
    try writeCsi1(writer, caps, 'd', if (row == 0) 1 else row);
}

// Vertical Position Relative (VPR): CSI n e (down n rows, default 1)
pub fn cursorDownRelative(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'e', if (n == 0) 1 else n);
}

// Horizontal Vertical Position (HVP): CSI row ; col f
pub fn setCursorRowCol(writer: anytype, caps: TermCaps, row: u32, col: u32) !void {
    try writeCsi2(writer, caps, 'f', if (row == 0) 1 else row, if (col == 0) 1 else col);
}

// Cursor Horizontal Forward Tab (CHT): CSI n I (default 1)
pub fn cursorForwardTab(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'I', if (n == 0) 1 else n);
}

// Cursor Backward Tab (CBT): CSI n Z (default 1)
pub fn cursorBackwardTab(writer: anytype, caps: TermCaps, n: u32) !void {
    try writeCsi1(writer, caps, 'Z', if (n == 0) 1 else n);
}

// Index (IND): ESC D — move cursor down one line (scroll up at bottom)
pub fn index(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1bD");
}

// Reverse Index (RI): ESC M — move cursor up one line (scroll down at top)
pub fn reverseIndex(writer: anytype, caps: TermCaps) !void {
    try passthrough.writeWithPassthrough(writer, caps, "\x1bM");
}

const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

// XTerm Window Operations (XTWINOPS)
// CSI Ps ; Ps ; Ps t
// See: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h4-Functions-using-CSI-_-ordered-by-the-final-character-lparen-s-rparen:CSI-Ps;Ps;Ps-t.1EB0

pub const ResizeWindowWinOp: u32 = 4;
pub const RequestWindowSizeWinOp: u32 = 14; // report window size in pixels
pub const RequestCellSizeWinOp: u32 = 16; // report cell size in pixels

fn buildWindowOp(buf: []u8, p: u32, ps: []const u32) []const u8 {
    var fbs = std.io.fixedBufferStream(buf);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "{d}", .{p}) catch unreachable;
    for (ps) |v| {
        _ = std.fmt.format(w, ";{d}", .{v}) catch unreachable;
    }
    _ = w.write("t") catch unreachable;
    return fbs.getWritten();
}

pub fn windowOp(writer: anytype, caps: TermCaps, p: u32, ps: []const u32) !void {
    if (!caps.supportsXtwinops) return error.Unsupported;
    if (p == 0) return error.InvalidArgument;
    var tmp: [64]u8 = undefined;
    const seq = buildWindowOp(&tmp, p, ps);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Request window size in pixels. Terminal responds with CSI 4 ; height ; width t
pub fn requestWindowPixelSize(writer: anytype, caps: TermCaps) !void {
    try windowOp(writer, caps, RequestWindowSizeWinOp, &.{});
}

// Request cell size in pixels. Terminal responds with CSI 6 ; height ; width t
pub fn requestCellPixelSize(writer: anytype, caps: TermCaps) !void {
    try windowOp(writer, caps, RequestCellSizeWinOp, &.{});
}

// Resize window to height x width in pixels.
pub fn resizeWindowPixels(writer: anytype, caps: TermCaps, height: u32, width: u32) !void {
    if (height == 0 or width == 0) return error.InvalidArgument;
    var params = [_]u32{ height, width };
    try windowOp(writer, caps, ResizeWindowWinOp, &params);
}

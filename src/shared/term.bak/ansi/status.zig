const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

// Device Status Report (DSR)
// CSI Ps n (ANSI), CSI ? Ps n (DEC)
fn buildDsr(buf: []u8, dec: bool, statuses: []const u32) ![]const u8 {
    var fbs = std.io.fixedBufferStream(buf);
    var w = fbs.writer();
    try w.write("\x1b[");
    if (dec) try w.write("?");
    var first = true;
    for (statuses) |s| {
        if (!first) try w.write(";");
        first = false;
        try std.fmt.format(w, "{d}", .{s});
    }
    try w.write("n");
    return fbs.getWritten();
}

pub fn deviceStatusReport(writer: anytype, caps: TermCaps, dec: bool, statuses: []const u32) !void {
    var tmp: [48]u8 = undefined;
    const seq = try buildDsr(&tmp, dec, statuses);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Request cursor position (CPR): CSI 6 n
pub const RequestCursorPositionReport: []const u8 = "\x1b[6n";
// Request extended cursor position (DECXCPR): CSI ? 6 n
pub const RequestExtendedCursorPositionReport: []const u8 = "\x1b[?6n";
// Request light/dark preference (Contour extension): CSI ? 996 n
pub const RequestLightDarkReport: []const u8 = "\x1b[?996n";

// Build a Cursor Position Report (CPR): CSI Pl ; Pc R
pub fn cursorPositionReport(writer: anytype, caps: TermCaps, row: u32, col: u32) !void {
    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    const w = fbs.writer();
    const rr = if (row == 0) 1 else row;
    const cc = if (col == 0) 1 else col;
    try std.fmt.format(w, "\x1b[{d};{d}R", .{ rr, cc });
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Build an Extended Cursor Position Report (DECXCPR): CSI ? Pl ; Pc [; Pp] R
pub fn extendedCursorPositionReport(writer: anytype, caps: TermCaps, row: u32, col: u32, page: ?u32) !void {
    var tmp: [48]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    const rr = if (row == 0) 1 else row;
    const cc = if (col == 0) 1 else col;
    try w.write("\x1b[?");
    if (page) |p| {
        try std.fmt.format(w, "{d};{d};{d}R", .{ rr, cc, p });
    } else {
        try std.fmt.format(w, "{d};{d}R", .{ rr, cc });
    }
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Emit a Light/Dark report: CSI ? 997 ; 1 n (dark) or ; 2 n (light)
pub fn lightDarkReport(writer: anytype, caps: TermCaps, dark: bool) !void {
    const seq = if (dark) "\x1b[?997;1n" else "\x1b[?997;2n";
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

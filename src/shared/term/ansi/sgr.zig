const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

fn writeSgrList(writer: anytype, caps: TermCaps, list: []const u16) !void {
    var tmp: [96]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    try w.write("\x1b[");
    if (list.len == 0) {
        try w.write("0");
    } else {
        var i: usize = 0;
        while (i < list.len) : (i += 1) {
            if (i != 0) try w.write(";");
            try std.fmt.format(w, "{d}", .{list[i]});
        }
    }
    try w.write("m");
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Basic style helpers
pub fn resetStyle(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{});
}
pub fn bold(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{1});
}
pub fn faint(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{2});
}
pub fn italic(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{3});
}
pub fn underline(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{4});
}
pub fn blink(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{5});
}
pub fn rapidBlink(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{6});
}
pub fn inverse(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{7});
}
pub fn conceal(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{8});
}
pub fn strike(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{9});
}

// Style resets
pub fn normalIntensity(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{22});
}
pub fn noItalic(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{23});
}
pub fn noUnderline(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{24});
}
pub fn noBlink(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{25});
}
pub fn noInverse(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{27});
}
pub fn noConceal(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{28});
}
pub fn noStrike(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{29});
}

// 8-bit/Default colors
pub fn defaultForeground(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{39});
}
pub fn defaultBackground(writer: anytype, caps: TermCaps) !void {
    try writeSgrList(writer, caps, &.{49});
}

pub fn setForeground256(writer: anytype, caps: TermCaps, idx: u8) !void {
    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    try w.write("\x1b[38;5;");
    try std.fmt.format(w, "{d}", .{idx});
    try w.write("m");
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

pub fn setBackground256(writer: anytype, caps: TermCaps, idx: u8) !void {
    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    try w.write("\x1b[48;5;");
    try std.fmt.format(w, "{d}", .{idx});
    try w.write("m");
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

// Truecolor RGB (38;2 / 48;2). Returns error.Unsupported if caps deny truecolor.
pub fn setForegroundRgb(writer: anytype, caps: TermCaps, r: u8, g: u8, b: u8) !void {
    if (!caps.supportsTruecolor) return error.Unsupported;
    var tmp: [40]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    try w.write("\x1b[38;2;");
    try std.fmt.format(w, "{d};{d};{d}m", .{ r, g, b });
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

pub fn setBackgroundRgb(writer: anytype, caps: TermCaps, r: u8, g: u8, b: u8) !void {
    if (!caps.supportsTruecolor) return error.Unsupported;
    var tmp: [40]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    try w.write("\x1b[48;2;");
    try std.fmt.format(w, "{d};{d};{d}m", .{ r, g, b });
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

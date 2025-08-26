const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

pub const KittyFlags = struct {
    pub const DisambiguateEscapeCodes: u32 = 1 << 0;
    pub const ReportEventTypes: u32 = 1 << 1;
    pub const ReportAlternateKeys: u32 = 1 << 2;
    pub const ReportAllKeysAsEscapeCodes: u32 = 1 << 3;
    pub const ReportAssociatedKeys: u32 = 1 << 4;

    pub const All: u32 = DisambiguateEscapeCodes | ReportEventTypes |
        ReportAlternateKeys | ReportAllKeysAsEscapeCodes | ReportAssociatedKeys;
};

pub fn requestKittyKeyboard(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsKittyKeyboard) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[?u");
}

// mode: 1=set only provided flags; 2=set and keep existing; 3=unset provided
pub fn setKittyKeyboard(writer: anytype, caps: TermCaps, flags: u32, mode: u32) !void {
    if (!caps.supportsKittyKeyboard) return error.Unsupported;
    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[") catch unreachable;
    _ = std.fmt.format(w, "={d};{d}u", .{ flags, mode }) catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

pub fn pushKittyKeyboard(writer: anytype, caps: TermCaps, flags: u32) !void {
    if (!caps.supportsKittyKeyboard) return error.Unsupported;
    var tmp: [24]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[>") catch unreachable;
    if (flags != 0) _ = std.fmt.format(w, "{d}", .{flags}) catch unreachable;
    _ = w.write("u") catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

pub fn disableKittyKeyboard(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsKittyKeyboard) return error.Unsupported;
    try passthrough.writeWithPassthrough(writer, caps, "\x1b[>u");
}

pub fn popKittyKeyboard(writer: anytype, caps: TermCaps, count: u32) !void {
    if (!caps.supportsKittyKeyboard) return error.Unsupported;
    var tmp: [24]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[<") catch unreachable;
    if (count != 0) _ = std.fmt.format(w, "{d}", .{count}) catch unreachable;
    _ = w.write("u") catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

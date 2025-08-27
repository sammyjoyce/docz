const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("passthrough.zig");

pub const TermCaps = caps_mod.TermCaps;

fn writeKeyModifierOptions(writer: anytype, caps: TermCaps, pp: u32, pv: ?u32) !void {
    // Formats:
    //  CSI > Pp m           (reset)
    //  CSI > Pp ; Pv m      (set)
    var tmp: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[>") catch unreachable;
    if (pp > 0) _ = std.fmt.format(w, "{d}", .{pp}) catch unreachable;
    if (pv) |v| {
        _ = w.write(";") catch unreachable;
        _ = std.fmt.format(w, "{d}", .{v}) catch unreachable;
    }
    _ = w.write("m") catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

pub fn setModifyOtherKeys1(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsModifyOtherKeys) return error.Unsupported;
    try writeKeyModifierOptions(writer, caps, 4, 1);
}

pub fn setModifyOtherKeys2(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsModifyOtherKeys) return error.Unsupported;
    try writeKeyModifierOptions(writer, caps, 4, 2);
}

pub fn resetModifyOtherKeys(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsModifyOtherKeys) return error.Unsupported;
    try writeKeyModifierOptions(writer, caps, 4, null);
}

pub fn queryModifyOtherKeys(writer: anytype, caps: TermCaps) !void {
    // Query form: CSI ? 4 m
    var tmp: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&tmp);
    var w = fbs.writer();
    _ = w.write("\x1b[?4m") catch unreachable;
    try passthrough.writeWithPassthrough(writer, caps, fbs.getWritten());
}

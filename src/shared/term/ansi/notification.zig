const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

fn sanitize(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    for (s) |ch| {
        if (ch == 0x1b or ch == 0x07) continue;
        try out.append(ch);
    }
    return try out.toOwnedSlice();
}

fn appendDec(buf: *std.ArrayList(u8), n: u32) !void {
    var tmp: [10]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{n});
    try buf.appendSlice(s);
}

fn oscTerminator() []const u8 {
    return if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel")) seqcfg.osc.bel else seqcfg.osc.st;
}

fn buildOscNotification(alloc: std.mem.Allocator, message: []const u8) ![]u8 {
    const st = oscTerminator();
    const clean = try sanitize(alloc, message);
    defer alloc.free(clean);

    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, seqcfg.osc.ops.notification);
    try buf.append(';');
    try buf.appendSlice(clean);
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

pub fn writeNotification(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    message: []const u8,
) !void {
    if (!caps.supportsNotifyOsc9) return error.Unsupported;
    const seq = try buildOscNotification(alloc, message);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

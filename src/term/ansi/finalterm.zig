const std = @import("std");
const caps_mod = @import("../caps.zig");
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

fn buildFinalTerm(
    alloc: std.mem.Allocator,
    subcode: []const u8,
    param: ?[]const u8,
) ![]u8 {
    const st = oscTerminator();
    const clean_param = if (param) |p| blk: {
        const c = try sanitize(alloc, p);
        break :blk c;
    } else null;
    defer if (clean_param) |p| alloc.free(p);

    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, seqcfg.osc.ops.finalterm);
    try buf.append(';');
    try buf.appendSlice(subcode);
    if (clean_param) |p| {
        try buf.append(';');
        try buf.appendSlice(p);
    }
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

pub fn writeFinalTerm(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    subcode: []const u8,
    param: ?[]const u8,
) !void {
    if (!caps.supportsFinalTermOsc133) return error.Unsupported;
    const seq = try buildFinalTerm(alloc, subcode, param);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Convenience helpers for common markers
pub fn promptStart(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    try writeFinalTerm(writer, alloc, caps, "A", null);
}

pub fn promptEnd(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    try writeFinalTerm(writer, alloc, caps, "B", null);
}

pub fn commandStart(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    try writeFinalTerm(writer, alloc, caps, "C", null);
}

pub fn commandEnd(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    try writeFinalTerm(writer, alloc, caps, "D", null);
}

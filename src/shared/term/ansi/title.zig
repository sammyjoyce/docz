const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

pub const TitleKind = enum { both, icon, title };

fn oscCode(kind: TitleKind) u32 {
    return switch (kind) {
        .both => seqcfg.osc.ops.title.both,
        .icon => seqcfg.osc.ops.title.icon,
        .title => seqcfg.osc.ops.title.title,
    };
}

fn sanitizeTitle(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    // Remove ESC and BEL to avoid premature termination
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

fn buildOscTitle(
    alloc: std.mem.Allocator,
    kind: TitleKind,
    text: []const u8,
) ![]u8 {
    const st = if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel")) seqcfg.osc.bel else seqcfg.osc.st;
    const clean = try sanitizeTitle(alloc, text);
    defer alloc.free(clean);

    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, oscCode(kind));
    try buf.append(';');
    try buf.appendSlice(clean);
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

pub fn writeTitle(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    kind: TitleKind,
    text: []const u8,
) !void {
    if (!caps.supportsTitleOsc012) return error.Unsupported;
    const seq = try buildOscTitle(alloc, kind, text);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn writeWindowTitle(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    text: []const u8,
) !void {
    try writeTitle(writer, alloc, caps, .title, text);
}

pub fn writeIconTitle(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    text: []const u8,
) !void {
    try writeTitle(writer, alloc, caps, .icon, text);
}

pub fn writeBothTitles(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    text: []const u8,
) !void {
    try writeTitle(writer, alloc, caps, .both, text);
}

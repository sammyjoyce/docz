const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

fn oscTerminator() []const u8 {
    return if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel"))
        seqcfg.osc.bel
    else
        seqcfg.osc.st;
}

fn sanitize(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    // Filter out ESC and BEL to avoid premature termination or injection
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    try out.ensureTotalCapacity(s.len);
    for (s) |ch| {
        if (ch == 0x1b or ch == 0x07) continue;
        out.appendAssumeCapacity(ch);
    }
    return try out.toOwnedSlice();
}

fn appendDec(buf: *std.ArrayList(u8), n: u32) !void {
    var tmp: [12]u8 = undefined;
    const w = try std.fmt.bufPrint(&tmp, "{d}", .{n});
    try buf.appendSlice(w);
}

fn buildOscColor(
    alloc: std.mem.Allocator,
    code: u32,
    payload: []const u8,
) ![]u8 {
    const st = oscTerminator();
    const clean = try sanitize(alloc, payload);
    defer alloc.free(clean);

    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, code);
    try buf.append(';');
    try buf.appendSlice(clean);
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

fn buildOscQuery(alloc: std.mem.Allocator, code: u32) ![]u8 {
    const st = oscTerminator();
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, code);
    try buf.appendSlice(";?");
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

fn buildOscReset(alloc: std.mem.Allocator, code: u32) ![]u8 {
    const st = oscTerminator();
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, 100 + code);
    // OSC 110/111/112 are resets for 10/11/12 respectively
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

inline fn colorCode(kind: enum { fg, bg, cursor }) u32 {
    return switch (kind) {
        .fg => seqcfg.osc.ops.color.foreground,
        .bg => seqcfg.osc.ops.color.background,
        .cursor => seqcfg.osc.ops.color.cursor,
    };
}

// Foreground color (OSC 10)
pub fn setForegroundColor(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    color: []const u8,
) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscColor(alloc, colorCode(.fg), color);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn requestForegroundColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscQuery(alloc, colorCode(.fg));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn resetForegroundColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscReset(alloc, colorCode(.fg));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Background color (OSC 11)
pub fn setBackgroundColor(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    color: []const u8,
) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscColor(alloc, colorCode(.bg), color);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn requestBackgroundColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscQuery(alloc, colorCode(.bg));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn resetBackgroundColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscReset(alloc, colorCode(.bg));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Cursor color (OSC 12)
pub fn setCursorColor(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    color: []const u8,
) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscColor(alloc, colorCode(.cursor), color);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn requestCursorColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscQuery(alloc, colorCode(.cursor));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn resetCursorColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscReset(alloc, colorCode(.cursor));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

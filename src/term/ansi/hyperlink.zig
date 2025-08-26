const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

fn appendDec(buf: *std.ArrayList(u8), n: u32) !void {
    var tmp: [10]u8 = undefined;
    const written = try std.fmt.bufPrint(&tmp, "{d}", .{n});
    try buf.appendSlice(written);
}

fn oscTerminator() []const u8 {
    return if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel"))
        seqcfg.osc.bel
    else
        seqcfg.osc.st;
}

fn buildOsc8Link(alloc: std.mem.Allocator, url: []const u8, text: []const u8) ![]u8 {
    // OSC <code:8> ; params ; url <ST/BEL> text OSC 8 ;; <ST/BEL>
    const st = oscTerminator();
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, seqcfg.osc.ops.hyperlink);
    try buf.appendSlice(";;");
    try buf.appendSlice(url);
    try buf.appendSlice(st);
    try buf.appendSlice(text);
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, seqcfg.osc.ops.hyperlink);
    try buf.appendSlice(";;");
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

pub fn writeHyperlink(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps, url: []const u8, text: []const u8) !void {
    if (!caps.supportsHyperlinkOsc8) {
        // Fallback: plain text + URL in parens
        if (std.mem.eql(u8, text, url)) {
            try writer.writeAll(text);
        } else {
            try writer.writeAll(text);
            try writer.writeAll(" (");
            try writer.writeAll(url);
            try writer.writeAll(")");
        }
        return;
    }

    const seq = try buildOsc8Link(alloc, url, text);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

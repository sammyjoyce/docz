const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

fn appendDec(buf: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, n: u32) !void {
    var tmp: [10]u8 = undefined;
    const written = try std.fmt.bufPrint(&tmp, "{d}", .{n});
    try buf.appendSlice(alloc, written);
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
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);
    try buf.appendSlice(alloc, "\x1b]");
    try appendDec(&buf, alloc, seqcfg.osc.ops.hyperlink);
    try buf.appendSlice(alloc, ";;");
    try buf.appendSlice(alloc, url);
    try buf.appendSlice(alloc, st);
    try buf.appendSlice(alloc, text);
    try buf.appendSlice(alloc, "\x1b]");
    try appendDec(&buf, alloc, seqcfg.osc.ops.hyperlink);
    try buf.appendSlice(alloc, ";;");
    try buf.appendSlice(alloc, st);
    return try buf.toOwnedSlice(alloc);
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

/// Start an OSC 8 hyperlink sequence
/// Used by unified terminal interface
pub fn startHyperlink(writer: anytype, caps: TermCaps, url: []const u8, extra_param: []const u8) !void {
    _ = extra_param; // unused parameter for compatibility
    if (!caps.supportsHyperlinkOsc8) return;

    const st = oscTerminator();
    try writer.writeAll("\x1b]");
    try writer.print("{d}", .{seqcfg.osc.ops.hyperlink});
    try writer.writeAll(";;");
    try writer.writeAll(url);
    try writer.writeAll(st);
}

/// Start an OSC 8 hyperlink sequence with allocator parameter
/// Used by advanced renderer - allocator parameter included for API compatibility
pub fn startHyperlinkWithAllocator(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps, url: []const u8, extra_param: ?[]const u8) !void {
    _ = alloc; // allocator not needed for start sequence
    _ = extra_param; // unused parameter for compatibility
    try startHyperlink(writer, caps, url, "");
}

/// End an OSC 8 hyperlink sequence
pub fn endHyperlink(writer: anytype, caps: TermCaps) !void {
    if (!caps.supportsHyperlinkOsc8) return;

    const st = oscTerminator();
    try writer.writeAll("\x1b]");
    try writer.print("{d}", .{seqcfg.osc.ops.hyperlink});
    try writer.writeAll(";;");
    try writer.writeAll(st);
}

const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

pub const Selection = enum { clipboard, primary };

fn selectionChar(sel: Selection) u8 {
    return switch (sel) {
        .clipboard => 'c',
        .primary => 'p',
    };
}

fn calcBase64Len(n: usize) usize {
    // Round up to next multiple of 3, times 4
    return ((n + 2) / 3) * 4;
}

fn appendDec(buf: *std.ArrayList(u8), n: u32) !void {
    var tmp: [12]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{n});
    try buf.appendSlice(s);
}

fn buildOsc52Clipboard(
    alloc: std.mem.Allocator,
    sel: Selection,
    data: []const u8,
) ![]u8 {
    // OSC <code:52> ; <sel-char> ; <base64(data)> <ST/BEL>
    const st = if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel")) seqcfg.osc.bel else seqcfg.osc.st;

    // Base64 encode the payload without newlines
    const b64_len = calcBase64Len(data.len);
    var b64_buf = try alloc.alloc(u8, b64_len);
    defer alloc.free(b64_buf);
    const encoded_len = std.base64.standard.Encoder.encode(b64_buf, data);
    const b64 = b64_buf[0..encoded_len];

    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    try out.appendSlice("\x1b]");
    try appendDec(&out, seqcfg.osc.ops.clipboard);
    try out.append(';');
    const sel_char = switch (sel) {
        .clipboard => seqcfg.clipboard.selection.clipboard[0],
        .primary => seqcfg.clipboard.selection.primary[0],
    };
    try out.append(sel_char);
    try out.append(';');
    try out.appendSlice(b64);
    try out.appendSlice(st);
    return try out.toOwnedSlice();
}

// Writes an OSC 52 clipboard sequence (with tmux/screen passthrough if needed).
// Returns error.Unsupported if the terminal does not support OSC 52 per caps.
pub fn writeClipboard(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    data: []const u8,
    sel: Selection,
) !void {
    if (!caps.supportsClipboardOsc52) return error.Unsupported;
    const seq = try buildOsc52Clipboard(alloc, sel, data);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Convenience wrapper for the common clipboard selection.
pub fn writeClipboardDefault(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    data: []const u8,
) !void {
    try writeClipboard(writer, alloc, caps, data, .clipboard);
}

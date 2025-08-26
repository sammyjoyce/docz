const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

fn oscTerminator() []const u8 {
    // iTerm2 sequences generally accept either ST or BEL. Respect config.
    return if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel")) seqcfg.osc.bel else seqcfg.osc.st;
}

fn sanitize(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    // Filter control chars that could break OSC framing
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    try out.ensureTotalCapacity(s.len);
    for (s) |ch| {
        if (ch == 0x1b or ch == 0x07) continue; // ESC, BEL
        out.appendAssumeCapacity(ch);
    }
    return try out.toOwnedSlice();
}

fn buildIterm2(alloc: std.mem.Allocator, payload: []const u8) ![]u8 {
    const st = oscTerminator();
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    // OSC 1337 ; payload
    var tmp: [16]u8 = undefined;
    const code = try std.fmt.bufPrint(&tmp, "{d}", .{seqcfg.osc.ops.iterm2});
    try buf.appendSlice(code);
    try buf.append(';');
    try buf.appendSlice(payload);
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

// Write a raw iTerm2 OSC 1337 sequence with the provided data payload.
pub fn writeITerm2(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps, payload: []const u8) !void {
    if (!caps.supportsITerm2Osc1337) return error.Unsupported;
    const clean = try sanitize(alloc, payload);
    defer alloc.free(clean);
    const seq = try buildIterm2(alloc, clean);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub const ITerm2FileOptions = struct {
    name: ?[]const u8 = null, // file name; will be base64-encoded
    size: ?u64 = null, // file size in bytes
    width: ?[]const u8 = null, // e.g. "auto", "80", "100px", "50%"
    height: ?[]const u8 = null,
    preserve_aspect_ratio: bool = true, // preserve aspect ratio (default true)
    inline_display: bool = true, // display inline (true) or download only (false)
    do_not_move_cursor: bool = false, // wezterm extension
};

fn base64EncodeAlloc(alloc: std.mem.Allocator, data: []const u8) ![]u8 {
    const out_len = ((data.len + 2) / 3) * 4;
    var out = try alloc.alloc(u8, out_len);
    const n = std.base64.standard.Encoder.encode(out, data);
    return out[0..n];
}

fn buildITerm2FilePayload(alloc: std.mem.Allocator, opts: ITerm2FileOptions, content_b64: []const u8) ![]u8 {
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();

    try buf.appendSlice("File=");
    var first = true;
    inline for (.{@as(?[]const u8, null)}) |_| {} // keep Zig happy
    if (opts.name) |name_in| {
        const name_b64 = try base64EncodeAlloc(alloc, name_in);
        defer alloc.free(name_b64);
        if (!first) try buf.append(';') else first = false;
        try buf.appendSlice("name=");
        try buf.appendSlice(name_b64);
    }
    if (opts.size) |sz| {
        if (!first) try buf.append(';') else first = false;
        var tmp: [32]u8 = undefined;
        const s = try std.fmt.bufPrint(&tmp, "size={d}", .{sz});
        try buf.appendSlice(s);
    }
    if (opts.width) |w| {
        if (!first) try buf.append(';') else first = false;
        try buf.appendSlice("width=");
        try buf.appendSlice(w);
    }
    if (opts.height) |h| {
        if (!first) try buf.append(';') else first = false;
        try buf.appendSlice("height=");
        try buf.appendSlice(h);
    }
    if (!opts.preserve_aspect_ratio) {
        if (!first) try buf.append(';') else first = false;
        try buf.appendSlice("preserveAspectRatio=0");
    }
    if (opts.inline_display) {
        if (!first) try buf.append(';') else first = false;
        try buf.appendSlice("inline=1");
    }
    if (opts.do_not_move_cursor) {
        if (!first) try buf.append(';') else first = false;
        try buf.appendSlice("doNotMoveCursor=1");
    }

    // Append data delimiter and payload
    try buf.append(':');
    try buf.appendSlice(content_b64);
    return try buf.toOwnedSlice();
}

// writeITerm2Image writes an iTerm2 Inline Image (OSC 1337 File=...).
// The content is raw bytes; it will be base64-encoded.
pub fn writeITerm2Image(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    opts: ITerm2FileOptions,
    content: []const u8,
) !void {
    if (!caps.supportsITerm2Osc1337) return error.Unsupported;
    // Encode content
    const content_b64 = try base64EncodeAlloc(alloc, content);
    defer alloc.free(content_b64);

    // Build payload and sequence
    const payload = try buildITerm2FilePayload(alloc, opts, content_b64);
    defer alloc.free(payload);
    try writeITerm2(writer, alloc, caps, payload);
}

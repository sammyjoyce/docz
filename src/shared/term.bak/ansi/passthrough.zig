const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

fn escapeEsc(buf: []u8, s: []const u8) []u8 {
    // Duplicate ESC (0x1b) characters for tmux passthrough
    var i: usize = 0;
    var j: usize = 0;
    while (i < s.len and j < buf.len) : (i += 1) {
        buf[j] = s[i];
        j += 1;
        if (s[i] == 0x1b and j < buf.len) {
            buf[j] = 0x1b;
            j += 1;
        }
    }
    return buf[0..j];
}

fn writeTmuxPassthrough(writer: anytype, seq: []const u8) !void {
    // tmux passthrough uses DCS with configurable prefix/suffix and optional ESC-doubling
    try writer.writeAll(seqcfg.wrappers.tmux.prefix);
    // Allocate a temp buffer up to 2x payload for ESC doubling (if enabled)
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    if (seqcfg.wrappers.tmux.escape_esc) {
        const tmp = try alloc.alloc(u8, seq.len * 2);
        const escaped = escapeEsc(tmp, seq);
        try writer.writeAll(escaped);
    } else {
        try writer.writeAll(seq);
    }
    try writer.writeAll(seqcfg.wrappers.tmux.suffix);
}

fn writeScreenPassthrough(writer: anytype, seq: []const u8, chunk_limit: usize) !void {
    // screen passthrough with configurable prefix/suffix and optional chunking
    if (!seqcfg.wrappers.screen.chunking or chunk_limit == 0 or seq.len <= chunk_limit) {
        try writer.writeAll(seqcfg.wrappers.screen.prefix);
        try writer.writeAll(seq);
        try writer.writeAll(seqcfg.wrappers.screen.suffix);
        return;
    }
    var off: usize = 0;
    while (off < seq.len) : (off += chunk_limit) {
        const end = @min(seq.len, off + chunk_limit);
        try writer.writeAll(seqcfg.wrappers.screen.prefix);
        try writer.writeAll(seq[off..end]);
        try writer.writeAll(seqcfg.wrappers.screen.suffix);
    }
}

pub fn writeWithPassthrough(writer: anytype, caps: TermCaps, seq: []const u8) !void {
    if (caps.needsTmuxPassthrough) return writeTmuxPassthrough(writer, seq);
    if (caps.needsScreenPassthrough) return writeScreenPassthrough(writer, seq, caps.screenChunkLimit);
    try writer.writeAll(seq);
}

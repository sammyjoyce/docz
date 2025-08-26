const std = @import("std");
const caps_mod = @import("../caps.zig");
const wmod = @import("width.zig");

pub const WidthMethod = caps_mod.WidthMethod;

inline fn utf8DecodeAt(s: []const u8, i: usize) struct { cp: u32, n: usize } {
    return wmod.utf8DecodeAt(s, i);
}

inline fn skipAnsiAt(s: []const u8, i: usize) usize {
    return wmod.skipAnsiAt(s, i);
}

inline fn cpWidth(cp: u32, method: WidthMethod) u2 {
    return wmod.cpWidth(cp, method);
}

// truncate cuts a string to the given visible width, appending tail if truncated.
// It preserves ANSI escape sequences without counting them toward width.
pub fn truncate(alloc: std.mem.Allocator, s: []const u8, length: usize, tail: []const u8, method: WidthMethod) ![]u8 {
    if (wmod.stringWidth(s, method) <= length) {
        // No truncation needed; return a copy for a consistent API.
        return std.mem.dupe(alloc, u8, s);
    }

    const tail_w = wmod.stringWidth(tail, method);
    var budget: isize = @as(isize, @intCast(if (length > tail_w) length - tail_w else 0));
    if (budget <= 0) return alloc.alloc(u8, 0);

    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    var i: usize = 0;
    var curw: usize = 0;
    var ignoring = false;

    while (i < s.len) {
        const skipped = skipAnsiAt(s, i);
        if (skipped != 0) {
            // Always preserve escapes
            try out.appendSlice(s[i .. i + skipped]);
            i += skipped;
            continue;
        }

        const dec = utf8DecodeAt(s, i);
        const w = cpWidth(dec.cp, method);
        if (!ignoring and (@as(isize, @intCast(curw)) + @as(isize, w) > budget)) {
            ignoring = true;
            try out.appendSlice(tail);
        }
        if (!ignoring) {
            try out.appendSlice(s[i .. i + dec.n]);
            curw += w;
        }
        i += dec.n;
    }

    return try out.toOwnedSlice();
}

// truncateLeft removes n visible cells from the left and optionally prefixes the result.
pub fn truncateLeft(alloc: std.mem.Allocator, s: []const u8, n: usize, prefix: []const u8, method: WidthMethod) ![]u8 {
    if (n == 0) return std.mem.dupe(alloc, u8, s);

    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();

    // First, skip n visible cells (copying only escapes), then copy rest.
    var i: usize = 0;
    var skipped_cells: usize = 0;
    var emitted_prefix = false;

    while (i < s.len) {
        const esc = skipAnsiAt(s, i);
        if (esc != 0) {
            // Preserve escapes while skipping
            if (skipped_cells < n) {
                try out.appendSlice(s[i .. i + esc]);
            } else {
                // After cutting, keep escapes too
                try out.appendSlice(s[i .. i + esc]);
            }
            i += esc;
            continue;
        }

        const dec = utf8DecodeAt(s, i);
        const w = cpWidth(dec.cp, method);
        if (skipped_cells < n) {
            skipped_cells += w;
            if (skipped_cells > n and !emitted_prefix) {
                try out.appendSlice(prefix);
                emitted_prefix = true;
            } else if (skipped_cells == n and !emitted_prefix) {
                try out.appendSlice(prefix);
                emitted_prefix = true;
            }
        } else {
            if (!emitted_prefix) {
                try out.appendSlice(prefix);
                emitted_prefix = true;
            }
            try out.appendSlice(s[i .. i + dec.n]);
        }
        i += dec.n;
    }

    return try out.toOwnedSlice();
}

// cut returns substring by visible cell indices [left, right).
pub fn cut(alloc: std.mem.Allocator, s: []const u8, left: usize, right: usize, method: WidthMethod) ![]u8 {
    if (right <= left) return alloc.alloc(u8, 0);
    // First truncate to right, then truncateLeft by left.
    var tmp = try truncate(alloc, s, right, "", method);
    defer alloc.free(tmp);
    return try truncateLeft(alloc, tmp, left, "", method);
}


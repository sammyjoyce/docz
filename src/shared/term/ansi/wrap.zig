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

fn runeInBreakpoints(cp: u32, breakpoints: []const u8) bool {
    // Only matches ASCII single-byte breakpoints.
    if (cp > 0x7F) return false;
    return std.mem.indexOfScalar(u8, breakpoints, @as(u8, @intCast(cp))) != null;
}

// Hardwrap: break anywhere once limit reached. If preserve_space, leading spaces are kept.
pub fn hardwrap(alloc: std.mem.Allocator, s: []const u8, limit: usize, preserve_space: bool, method: WidthMethod) ![]u8 {
    if (limit < 1) return std.mem.dupe(alloc, u8, s);
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();

    var i: usize = 0;
    var linew: usize = 0;
    var new_line_forced = false;

    while (i < s.len) {
        const esc = skipAnsiAt(s, i);
        if (esc != 0) {
            try out.appendSlice(s[i .. i + esc]);
            i += esc;
            continue;
        }
        // Newline resets width
        if (s[i] == '\n') {
            try out.append('\n');
            linew = 0;
            new_line_forced = false;
            i += 1;
            continue;
        }

        const dec = utf8DecodeAt(s, i);
        const w = cpWidth(dec.cp, method);
        if (linew + w > limit) {
            try out.append('\n');
            linew = 0;
            new_line_forced = true;
        }
        if (!preserve_space and linew == 0 and dec.n == 1) {
            const ch = s[i];
            if (ch == ' ' or ch == '\t') {
                i += 1;
                continue;
            }
        }
        if (linew == 0 and new_line_forced and dec.n == 1) {
            const ch = s[i];
            if (ch == ' ' or ch == '\t') {
                i += 1;
                continue;
            }
            new_line_forced = false;
        }
        try out.appendSlice(s[i .. i + dec.n]);
        linew += w;
        i += dec.n;
    }

    return try out.toOwnedSlice();
}

// Wordwrap: never break a word; only wrap at whitespace or provided breakpoints (hyphen always allowed via breakpoints param by caller).
pub fn wordwrap(alloc: std.mem.Allocator, s: []const u8, limit: usize, breakpoints: []const u8, method: WidthMethod) ![]u8 {
    if (limit < 1) return std.mem.dupe(alloc, u8, s);
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();

    var word = std.ArrayList(u8).init(alloc);
    defer word.deinit();
    var space = std.ArrayList(u8).init(alloc);
    defer space.deinit();

    var linew: usize = 0;
    var wordw: usize = 0;
    var spacew: usize = 0;

    var i: usize = 0;
    while (i < s.len) {
        const esc = skipAnsiAt(s, i);
        if (esc != 0) {
            try word.appendSlice(s[i .. i + esc]);
            i += esc;
            continue;
        }

        if (s[i] == '\n') {
            if (word.items.len > 0) {
                try out.appendSlice(space.items);
                space.clearRetainingCapacity();
                linew += spacew;
                spacew = 0;
                try out.appendSlice(word.items);
                word.clearRetainingCapacity();
                linew += wordw;
                wordw = 0;
            }
            try out.append('\n');
            linew = 0;
            i += 1;
            continue;
        }

        const dec = utf8DecodeAt(s, i);
        const w = cpWidth(dec.cp, method);
        const is_space = (dec.n == 1 and (s[i] == ' ' or s[i] == '\t'));
        if (is_space) {
            if (word.items.len > 0) {
                try out.appendSlice(space.items);
                space.clearRetainingCapacity();
                linew += spacew;
                spacew = 0;
                try out.appendSlice(word.items);
                word.clearRetainingCapacity();
                linew += wordw;
                wordw = 0;
            }
            try space.appendSlice(s[i .. i + dec.n]);
            spacew += w;
            i += dec.n;
            continue;
        }

        if (runeInBreakpoints(dec.cp, breakpoints)) {
            // Breakpoint: attach to current line if fits; otherwise treat as part of next word
            try out.appendSlice(space.items);
            space.clearRetainingCapacity();
            linew += spacew;
            spacew = 0;
            if (linew + wordw + w > limit and wordw < limit) {
                try out.append('\n');
                linew = 0;
            } else {
                try out.appendSlice(word.items);
                word.clearRetainingCapacity();
                linew += wordw;
                wordw = 0;
                try out.appendSlice(s[i .. i + dec.n]);
                linew += w;
            }
            i += dec.n;
            continue;
        }

        // accumulate in word buffer
        try word.appendSlice(s[i .. i + dec.n]);
        wordw += w;
        if (linew + spacew + wordw > limit and wordw < limit) {
            try out.append('\n');
            linew = 0;
            space.clearRetainingCapacity();
            spacew = 0;
        }
        i += dec.n;
    }

    // flush tail
    try out.appendSlice(space.items);
    try out.appendSlice(word.items);
    return try out.toOwnedSlice();
}

// Wrap: prefers word boundaries but may break a word when necessary.
pub fn wrap(alloc: std.mem.Allocator, s: []const u8, limit: usize, breakpoints: []const u8, method: WidthMethod) ![]u8 {
    if (limit < 1) return std.mem.dupe(alloc, u8, s);
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();

    var word = std.ArrayList(u8).init(alloc);
    defer word.deinit();
    var space = std.ArrayList(u8).init(alloc);
    defer space.deinit();

    var linew: usize = 0;
    var wordw: usize = 0;
    var spacew: usize = 0;

    var i: usize = 0;
    while (i < s.len) {
        const esc = skipAnsiAt(s, i);
        if (esc != 0) {
            try word.appendSlice(s[i .. i + esc]);
            i += esc;
            continue;
        }
        if (s[i] == '\n') {
            if (word.items.len > 0) {
                try out.appendSlice(space.items);
                space.clearRetainingCapacity();
                linew += spacew;
                spacew = 0;
                try out.appendSlice(word.items);
                word.clearRetainingCapacity();
                linew += wordw;
                wordw = 0;
            }
            try out.append('\n');
            linew = 0;
            i += 1;
            continue;
        }

        const dec = utf8DecodeAt(s, i);
        const w = cpWidth(dec.cp, method);
        const is_space = (dec.n == 1 and (s[i] == ' ' or s[i] == '\t'));
        if (is_space) {
            // emit buffered word
            if (word.items.len > 0) {
                try out.appendSlice(space.items);
                linew += spacew;
                space.clearRetainingCapacity();
                spacew = 0;
                try out.appendSlice(word.items);
                linew += wordw;
                word.clearRetainingCapacity();
                wordw = 0;
            }
            try space.appendSlice(s[i .. i + dec.n]);
            spacew += w;
            i += dec.n;
            continue;
        }

        if (runeInBreakpoints(dec.cp, breakpoints)) {
            // treat breakpoint as a 1-width symbol
            try out.appendSlice(space.items);
            linew += spacew;
            space.clearRetainingCapacity();
            spacew = 0;
            if (linew + wordw + w > limit) {
                // move word to next line if it doesn't fit
                if (wordw >= limit) {
                    // hard break the word
                    try out.appendSlice(word.items);
                    word.clearRetainingCapacity();
                    linew = (wordw + w) % limit; // approximate
                } else {
                    try out.append('\n');
                    linew = 0;
                }
            } else {
                try out.appendSlice(word.items);
                linew += wordw;
                word.clearRetainingCapacity();
            }
            try out.appendSlice(s[i .. i + dec.n]);
            linew += w;
            i += dec.n;
            continue;
        }

        // accumulate
        try word.appendSlice(s[i .. i + dec.n]);
        wordw += w;
        if (linew + spacew + wordw > limit) {
            if (wordw < limit) {
                try out.append('\n');
                linew = 0;
                space.clearRetainingCapacity();
                spacew = 0;
            } else if (wordw == limit) {
                try out.appendSlice(word.items);
                word.clearRetainingCapacity();
                wordw = 0;
                try out.append('\n');
                linew = 0;
            } else {
                // hard break inside word: emit what fits
                var cursor: usize = 0;
                var acc: usize = linew + spacew;
                if (space.items.len > 0) {
                    try out.appendSlice(space.items);
                    space.clearRetainingCapacity();
                    spacew = 0;
                }
                while (cursor < word.items.len and acc < limit) {
                    const e2 = skipAnsiAt(word.items, cursor);
                    if (e2 != 0) {
                        try out.appendSlice(word.items[cursor .. cursor + e2]);
                        cursor += e2;
                        continue;
                    }
                    const d2 = utf8DecodeAt(word.items, cursor);
                    const w2 = cpWidth(d2.cp, method);
                    if (acc + w2 > limit) break;
                    try out.appendSlice(word.items[cursor .. cursor + d2.n]);
                    acc += w2;
                    cursor += d2.n;
                }
                try out.append('\n');
                linew = 0;
                // keep remainder of word in buffer
                if (cursor > 0) {
                    const remain = if (cursor < word.items.len) word.items[cursor..] else &[_]u8{};
                    // reinitialize word with remainder
                    word.deinit();
                    word = std.ArrayList(u8).init(alloc);
                    if (remain.len > 0) {
                        try word.appendSlice(remain);
                    }
                    wordw = wmod.stringWidth(word.items, method);
                }
            }
        }
        i += dec.n;
    }

    // flush
    if (space.items.len > 0) try out.appendSlice(space.items);
    if (word.items.len > 0) try out.appendSlice(word.items);
    return try out.toOwnedSlice();
}

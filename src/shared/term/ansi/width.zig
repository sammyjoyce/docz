const std = @import("std");
const caps_mod = @import("../caps.zig");

pub const WidthMethod = caps_mod.WidthMethod;

// Minimal UTF-8 decoder. Returns codepoint and byte length.
pub inline fn utf8DecodeAt(s: []const u8, i: usize) struct { cp: u32, n: usize } {
    const b0: u8 = s[i];
    if (b0 < 0x80) return .{ .cp = b0, .n = 1 };
    if ((b0 & 0xE0) == 0xC0 and i + 1 < s.len) {
        const b1 = s[i + 1];
        if ((b1 & 0xC0) != 0x80) return .{ .cp = 0xFFFD, .n = 1 };
        const cp: u32 = (@as(u32, b0 & 0x1F) << 6) | @as(u32, b1 & 0x3F);
        return .{ .cp = cp, .n = 2 };
    }
    if ((b0 & 0xF0) == 0xE0 and i + 2 < s.len) {
        const b1 = s[i + 1];
        const b2 = s[i + 2];
        if ((b1 & 0xC0) != 0x80 or (b2 & 0xC0) != 0x80) return .{ .cp = 0xFFFD, .n = 1 };
        const cp: u32 = (@as(u32, b0 & 0x0F) << 12) | (@as(u32, b1 & 0x3F) << 6) | @as(u32, b2 & 0x3F);
        return .{ .cp = cp, .n = 3 };
    }
    if ((b0 & 0xF8) == 0xF0 and i + 3 < s.len) {
        const b1 = s[i + 1];
        const b2 = s[i + 2];
        const b3 = s[i + 3];
        if ((b1 & 0xC0) != 0x80 or (b2 & 0xC0) != 0x80 or (b3 & 0xC0) != 0x80)
            return .{ .cp = 0xFFFD, .n = 1 };
        const cp: u32 = (@as(u32, b0 & 0x07) << 18) | (@as(u32, b1 & 0x3F) << 12) |
            (@as(u32, b2 & 0x3F) << 6) | @as(u32, b3 & 0x3F);
        return .{ .cp = cp, .n = 4 };
    }
    return .{ .cp = 0xFFFD, .n = 1 };
}

// Simple ANSI escape sequence skipper.
// Returns number of bytes consumed if an escape starts at i, otherwise 0.
pub inline fn skipAnsiAt(s: []const u8, i: usize) usize {
    if (i >= s.len) return 0;
    const b = s[i];
    // C1 CSI (single byte)
    if (b == 0x9B) {
        var j: usize = i + 1;
        while (j < s.len) : (j += 1) {
            const ch = s[j];
            if (ch >= 0x40 and ch <= 0x7E) return j + 1 - i;
        }
        return s.len - i;
    }
    if (b != 0x1B) return 0;
    if (i + 1 >= s.len) return 1; // lone ESC
    const b1 = s[i + 1];
    switch (b1) {
        '[' => { // CSI ... final (0x40..0x7E)
            var j: usize = i + 2;
            while (j < s.len) : (j += 1) {
                const ch = s[j];
                if (ch >= 0x40 and ch <= 0x7E) return j + 1 - i;
            }
            return s.len - i;
        },
        ']' => { // OSC ... BEL or ST (ESC \\)
            var j: usize = i + 2;
            while (j < s.len) : (j += 1) {
                const ch = s[j];
                if (ch == 0x07) return j + 1 - i; // BEL
                if (ch == 0x1B and j + 1 < s.len and s[j + 1] == '\\') return j + 2 - i; // ST
            }
            return s.len - i;
        },
        'P' => { // DCS ... ST
            var j: usize = i + 2;
            while (j + 1 < s.len) : (j += 1) {
                if (s[j] == 0x1B and s[j + 1] == '\\') return j + 2 - i;
            }
            return s.len - i;
        },
        else => {
            // 2-byte ESC sequence fallback
            return @min(s.len - i, 2);
        },
    }
}

inline fn isCombining(cp: u32) bool {
    // Core combining mark ranges and variation selectors.
    return (cp >= 0x0300 and cp <= 0x036F) or
        (cp >= 0x1AB0 and cp <= 0x1AFF) or
        (cp >= 0x1DC0 and cp <= 0x1DFF) or
        (cp >= 0x20D0 and cp <= 0x20FF) or
        (cp == 0x200D) or // ZWJ
        (cp >= 0xFE00 and cp <= 0xFE0F) or
        (cp >= 0xE0100 and cp <= 0xE01EF);
}

inline fn isWide(cp: u32) bool {
    // Approximate East Asian Wide/Fullwidth ranges (subset).
    return (cp >= 0x1100 and cp <= 0x115F) or
        (cp == 0x2329 or cp == 0x232A) or
        (cp >= 0x2E80 and cp <= 0x303E) or
        (cp >= 0x3040 and cp <= 0xA4CF) or
        (cp >= 0xAC00 and cp <= 0xD7A3) or
        (cp >= 0xF900 and cp <= 0xFAFF) or
        (cp >= 0xFE10 and cp <= 0xFE19) or
        (cp >= 0xFE30 and cp <= 0xFE6B) or
        (cp >= 0xFF01 and cp <= 0xFF60) or
        (cp >= 0xFFE0 and cp <= 0xFFE6) or
        (cp >= 0x1F300 and cp <= 0x1F9FF) or
        (cp >= 0x20000 and cp <= 0x3FFFD);
}

pub inline fn cpWidth(cp: u32, method: WidthMethod) u2 {
    _ = method; // both methods share width calc here; grapheme-vs-wcwidth is approximated
    if (cp == 0) return 0;
    if (cp < 0x20 or (cp >= 0x7F and cp < 0xA0)) return 0; // control chars
    if (isCombining(cp)) return 0;
    if (isWide(cp)) return 2;
    return 1;
}

// stripAnsi removes ANSI escape sequences from the input. Returns an owned slice.
pub fn stripAnsi(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const skip = skipAnsiAt(s, i);
        if (skip != 0) {
            i += skip - 1;
            continue;
        }
        try out.append(s[i]);
    }
    return try out.toOwnedSlice();
}

// stringWidth computes the printed cell width of a string, ignoring ANSI escapes.
pub fn stringWidth(s: []const u8, method: WidthMethod) usize {
    if (s.len == 0) return 0;
    var w: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const skip = skipAnsiAt(s, i);
        if (skip != 0) {
            i += skip - 1;
            continue;
        }
        const dec = utf8DecodeAt(s, i);
        w += cpWidth(dec.cp, method);
        i += dec.n - 1;
    }
    return w;
}

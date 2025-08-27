const std = @import("std");
const types = @import("types.zig");

pub const CursorPositionEvent = types.CursorPositionEvent;

pub const ParseResult = struct {
    event: CursorPositionEvent,
    len: usize,
};

inline fn isCsiPrefix(seq: []const u8) bool {
    return (seq.len >= 2 and seq[0] == 0x1b and seq[1] == '[') or
        (seq.len >= 1 and seq[0] == 0x9b);
}

fn parseUintAt(s: []const u8, start: usize) ?struct { value: u32, end: usize } {
    var i = start;
    if (i >= s.len) return null;
    var v: u64 = 0;
    var any = false;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c < '0' or c > '9') break;
        any = true;
        v = v * 10 + (c - '0');
        if (v > std.math.maxInt(u32)) return null;
    }
    if (!any) return null;
    return .{ .value = @as(u32, @intCast(v)), .end = i };
}

// tryParseCPR parses a Cursor Position Report:
//   CSI <row> ; <col> R
// and DECXCPR:
//   CSI ? <row> ; <col> ; <page> R
pub fn tryParseCPR(seq: []const u8) ?ParseResult {
    if (!isCsiPrefix(seq)) return null;
    var i: usize = if (seq[0] == 0x9b) 1 else 2;

    var is_decx: bool = false;
    if (i < seq.len and seq[i] == '?') {
        is_decx = true;
        i += 1;
    }

    const p_row = parseUintAt(seq, i) orelse return null;
    i = p_row.end;
    if (i >= seq.len or seq[i] != ';') return null;
    i += 1;

    const p_col = parseUintAt(seq, i) orelse return null;
    i = p_col.end;

    var page: ?u32 = null;
    if (is_decx) {
        if (i >= seq.len or seq[i] != ';') return null;
        i += 1;
        const p_page = parseUintAt(seq, i) orelse return null;
        i = p_page.end;
        page = p_page.value;
    }

    if (i >= seq.len or seq[i] != 'R') return null;
    i += 1;

    // Convert to zero-based
    const row0: u32 = if (p_row.value == 0) 0 else p_row.value - 1;
    const col0: u32 = if (p_col.value == 0) 0 else p_col.value - 1;

    return .{ .event = .{ .row = row0, .col = col0, .page = page }, .len = i };
}

test "parse CPR" {
    const seq: []const u8 = "\x1b[12;40R";
    const res = tryParseCPR(seq) orelse return error.Unexpected;
    try std.testing.expectEqual(@as(u32, 11), res.event.row);
    try std.testing.expectEqual(@as(u32, 39), res.event.col);
    try std.testing.expect(res.event.page == null);
}

test "parse DECXCPR" {
    const seq: []const u8 = "\x1b[?15;80;2R";
    const res = tryParseCPR(seq) orelse return error.Unexpected;
    try std.testing.expectEqual(@as(u32, 14), res.event.row);
    try std.testing.expectEqual(@as(u32, 79), res.event.col);
    try std.testing.expectEqual(@as(u32, 2), res.event.page.?);
}

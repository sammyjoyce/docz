const std = @import("std");
const types = @import("types.zig");

pub const ClipboardEvent = types.ClipboardEvent;
pub const ClipboardSelection = types.ClipboardSelection;

pub const ParseResult = struct {
    event: ClipboardEvent,
    len: usize,
};

inline fn isOscPrefix(seq: []const u8) bool {
    return (seq.len >= 2 and seq[0] == 0x1b and seq[1] == ']') or
        (seq.len >= 1 and seq[0] == 0x9d);
}

// tryParse parses OSC52 read responses:
//   OSC 52 ; c ; <base64> ST|BEL
//   OSC 52 ; p ; <base64> ST|BEL
pub fn tryParse(alloc: std.mem.Allocator, seq: []const u8) ?ParseResult {
    if (!isOscPrefix(seq)) return null;
    var i: usize = if (seq[0] == 0x9d) 1 else 2;
    if (i >= seq.len or seq[i] != '5') return null;
    i += 1;
    if (i >= seq.len or seq[i] != '2') return null;
    i += 1;
    if (i >= seq.len or seq[i] != ';') return null;
    i += 1;
    if (i >= seq.len) return null;
    const sel_ch = seq[i];
    if (sel_ch != 'c' and sel_ch != 'p') return null;
    const sel: ClipboardSelection = if (sel_ch == 'p') .primary else .system;
    i += 1;
    if (i >= seq.len or seq[i] != ';') return null;
    i += 1;

    // Data until ST (ESC \) or BEL
    const data_start = i;
    var data_end = i;
    while (i < seq.len) : (i += 1) {
        const ch = seq[i];
        if (ch == 0x07) { // BEL
            data_end = i;
            i += 1;
            break;
        }
        if (ch == 0x1b and i + 1 < seq.len and seq[i + 1] == '\\') {
            data_end = i;
            i += 2; // consume ESC \
            break;
        }
    }
    if (data_end <= data_start) return null;

    const b64 = seq[data_start..data_end];
    // Decode into a freshly allocated buffer.
    const dec = std.base64.standard.Decoder;
    const out_len = dec.calcSizeForSlice(b64) catch return null;
    const buf = alloc.alloc(u8, out_len) catch return null;
    errdefer alloc.free(buf);
    dec.decode(buf, b64) catch {
        alloc.free(buf);
        return null;
    };
    return .{ .event = .{ .content = buf, .selection = sel }, .len = i };
}

test "parse OSC 52 system clipboard bel" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const seq: []const u8 = "\x1b]52;c;SGVsbG8h\x07"; // "Hello!"
    const res = tryParse(alloc, seq) orelse return error.Unexpected;
    try std.testing.expectEqualStrings("Hello!", res.event.content);
    try std.testing.expectEqual(ClipboardSelection.system, res.event.selection);
    alloc.free(res.event.content);
}

test "parse OSC 52 primary clipboard st" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const seq: []const u8 = "\x1b]52;p;VGVzdA==\x1b\\"; // "Test"
    const res = tryParse(alloc, seq) orelse return error.Unexpected;
    try std.testing.expectEqualStrings("Test", res.event.content);
    try std.testing.expectEqual(ClipboardSelection.primary, res.event.selection);
    alloc.free(res.event.content);
}

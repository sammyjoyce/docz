const std = @import("std");
// Bracketed paste markers.
const BracketedPasteStart: []const u8 = "\x1b[200~";
const BracketedPasteEnd: []const u8 = "\x1b[201~";

pub const PasteEvent = enum { start, end };

pub const ParseResult = struct { event: PasteEvent, len: usize };

pub fn tryParse(seq: []const u8) ?ParseResult {
    if (seq.len >= BracketedPasteStart.len and std.mem.startsWith(u8, seq, BracketedPasteStart))
        return .{ .event = .start, .len = BracketedPasteStart.len };
    if (seq.len >= BracketedPasteEnd.len and std.mem.startsWith(u8, seq, BracketedPasteEnd))
        return .{ .event = .end, .len = BracketedPasteEnd.len };
    return null;
}

test "parse bracketed paste markers" {
    const s1: []const u8 = "\x1b[200~";
    const st = tryParse(s1) orelse return error.Unexpected;
    try std.testing.expectEqual(PasteEvent.start, st.event);
    const s2: []const u8 = "\x1b[201~";
    const en = tryParse(s2) orelse return error.Unexpected;
    try std.testing.expectEqual(PasteEvent.end, en.event);
}

const std = @import("std");
const types = @import("types.zig");

pub const FocusEvent = types.FocusEvent;

pub const ParseResult = struct { event: FocusEvent, len: usize };

// Focus in/out sequences when DECSET 1004 is enabled.
// Consolidated from ansi/focus.zig
pub const FOCUS_IN: []const u8 = "\x1b[I";
pub const FOCUS_OUT: []const u8 = "\x1b[O";

// Re-export for compatibility
pub const Focus = FOCUS_IN;
pub const Blur = FOCUS_OUT;

pub fn tryParse(seq: []const u8) ?ParseResult {
    if (seq.len >= FOCUS_IN.len and std.mem.startsWith(u8, seq, FOCUS_IN))
        return .{ .event = .focus, .len = FOCUS_IN.len };
    if (seq.len >= FOCUS_OUT.len and std.mem.startsWith(u8, seq, FOCUS_OUT))
        return .{ .event = .blur, .len = FOCUS_OUT.len };
    return null;
}

test "parse focus in/out" {
    const s1: []const u8 = "\x1b[I";
    const fi = tryParse(s1) orelse return error.Unexpected;
    try std.testing.expectEqual(FocusEvent.focus, fi.event);
    const s2: []const u8 = "\x1b[O";
    const fo = tryParse(s2) orelse return error.Unexpected;
    try std.testing.expectEqual(FocusEvent.blur, fo.event);
}

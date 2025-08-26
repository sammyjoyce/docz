const std = @import("std");
const types = @import("types.zig");

pub const MouseEvent = types.MouseEvent;
pub const MouseButton = types.MouseButton;
pub const MouseAction = types.MouseAction;
pub const Modifiers = types.Modifiers;

pub const ParseResult = struct {
    event: MouseEvent,
    // Number of bytes consumed from the input slice.
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

fn decodeButton(cb: u32, final_ch: u8) struct { btn: MouseButton, act: MouseAction, mods: Modifiers } {
    const mods: Modifiers = .{
        .shift = (cb & 0x04) != 0,
        .alt = (cb & 0x08) != 0,
        .ctrl = (cb & 0x10) != 0,
    };

    const is_motion = (cb & 0x20) != 0;
    const is_wheel = (cb & 0x40) != 0;
    const base: u32 = cb & 0x03;

    // Default mapping
    var btn: MouseButton = .none;
    var act: MouseAction = .press;

    if (is_wheel) {
        // Wheel events are reported as press-only.
        act = .press;
        switch (base) {
            0 => btn = .wheel_up,
            1 => btn = .wheel_down,
            2 => btn = .wheel_left,
            else => btn = .wheel_right,
        }
        return .{ .btn = btn, .act = act, .mods = mods };
    }

    if (final_ch == 'm') {
        // SGR release
        act = .release;
        switch (base) {
            0 => btn = .left,
            1 => btn = .middle,
            2 => btn = .right,
            else => btn = .none,
        }
        return .{ .btn = btn, .act = act, .mods = mods };
    }

    // final_ch == 'M' (press or motion)
    if (is_motion) {
        if (base == 3) {
            // Motion with no buttons pressed
            btn = .none;
            act = .move;
        } else {
            // Drag with button held
            act = .drag;
            btn = switch (base) {
                0 => .left,
                1 => .middle,
                else => .right,
            };
        }
        return .{ .btn = btn, .act = act, .mods = mods };
    }

    // Plain press
    act = .press;
    btn = switch (base) {
        0 => .left,
        1 => .middle,
        2 => .right,
        else => .none,
    };
    return .{ .btn = btn, .act = act, .mods = mods };
}

// tryParseSgr attempts to parse an SGR mouse report (1006/1016).
// Examples:
//   ESC [ < Cb ; Cx ; Cy M
//   ESC [ < Cb ; Cx ; Cy m
//   ESC [ < Cb ; Cx ; Cy ; Px ; Py M
pub fn tryParseSgr(seq: []const u8) ?ParseResult {
    if (!isCsiPrefix(seq)) return null;

    var i: usize = if (seq[0] == 0x9b) 1 else 2;
    if (i >= seq.len or seq[i] != '<') return null;
    i += 1;

    const p_cb = parseUintAt(seq, i) orelse return null;
    i = p_cb.end;
    if (i >= seq.len or seq[i] != ';') return null;
    i += 1;

    const p_x = parseUintAt(seq, i) orelse return null;
    i = p_x.end;
    if (i >= seq.len or seq[i] != ';') return null;
    i += 1;

    const p_y = parseUintAt(seq, i) orelse return null;
    i = p_y.end;

    var px: ?u32 = null;
    var py: ?u32 = null;

    if (i < seq.len and seq[i] == ';') {
        i += 1;
        const p_px = parseUintAt(seq, i) orelse return null;
        i = p_px.end;
        if (i >= seq.len or seq[i] != ';') return null;
        i += 1;
        const p_py = parseUintAt(seq, i) orelse return null;
        i = p_py.end;
        px = p_px.value;
        py = p_py.value;
    }

    if (i >= seq.len) return null;
    const final_ch = seq[i];
    if (final_ch != 'M' and final_ch != 'm') return null;
    i += 1;

    const decoded = decodeButton(p_cb.value, final_ch);

    // Convert to zero-based cell coordinates.
    const x0: u32 = if (p_x.value == 0) 0 else p_x.value - 1;
    const y0: u32 = if (p_y.value == 0) 0 else p_y.value - 1;

    const ev: MouseEvent = .{
        .button = decoded.btn,
        .action = decoded.act,
        .x = x0,
        .y = y0,
        .pixel_x = px,
        .pixel_y = py,
        .mods = decoded.mods,
    };

    return .{ .event = ev, .len = i };
}

test "parse SGR mouse press" {
    const seq: []const u8 = "\x1b[<0;12;5M";
    const res = tryParseSgr(seq) orelse return error.Unexpected;
    try std.testing.expectEqual(@as(usize, seq.len), res.len);
    try std.testing.expectEqual(MouseButton.left, res.event.button);
    try std.testing.expectEqual(MouseAction.press, res.event.action);
    try std.testing.expectEqual(@as(u32, 11), res.event.x); // zero-based
    try std.testing.expectEqual(@as(u32, 4), res.event.y);
}

test "parse SGR mouse release" {
    const seq: []const u8 = "\x1b[<0;3;9m";
    const res = tryParseSgr(seq) orelse return error.Unexpected;
    try std.testing.expectEqual(MouseAction.release, res.event.action);
    try std.testing.expectEqual(MouseButton.left, res.event.button);
}

test "parse SGR mouse drag" {
    const seq: []const u8 = "\x1b[<32;10;7M"; // motion bit + left
    const res = tryParseSgr(seq) orelse return error.Unexpected;
    try std.testing.expectEqual(MouseAction.drag, res.event.action);
    try std.testing.expectEqual(MouseButton.left, res.event.button);
}

test "parse SGR mouse move (no buttons)" {
    const seq: []const u8 = "\x1b[<35;1;1M"; // 32 + 3
    const res = tryParseSgr(seq) orelse return error.Unexpected;
    try std.testing.expectEqual(MouseAction.move, res.event.action);
    try std.testing.expectEqual(MouseButton.none, res.event.button);
}

test "parse SGR wheel" {
    const seq: []const u8 = "\x1b[<64;5;6M"; // wheel up
    const res = tryParseSgr(seq) orelse return error.Unexpected;
    try std.testing.expectEqual(MouseButton.wheel_up, res.event.button);
}

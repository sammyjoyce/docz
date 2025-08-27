/// Enhanced keyboard event handling with modern terminal protocol support
/// Provides comprehensive key event types with support for modern terminal protocols.
/// Compatible with Zig 0.15.1
const std = @import("std");
const types = @import("types.zig");

// Re-export types from the local types module
pub const Key = types.Key;
pub const KeyEvent = types.KeyEvent;
pub const Modifiers = types.Modifiers;

/// Legacy alias for backward compatibility
pub const KeyMod = Modifiers;

/// Parse a single character into a key event
pub fn parseChar(ch: u8, allocator: std.mem.Allocator) !KeyEvent {
    var text_buf: [1]u8 = undefined;

    const key: Key = switch (ch) {
        0x00 => .null,
        0x01 => .ctrl_a,
        0x02 => .ctrl_b,
        0x03 => .ctrl_c,
        0x04 => .ctrl_d,
        0x05 => .ctrl_e,
        0x06 => .ctrl_f,
        0x07 => .ctrl_g,
        0x08 => .backspace,
        0x09 => .tab,
        0x0A => .enter,
        0x0B => .ctrl_k,
        0x0C => .ctrl_l,
        0x0D => .ctrl_m,
        0x0E => .ctrl_n,
        0x0F => .ctrl_o,
        0x10 => .ctrl_p,
        0x11 => .ctrl_q,
        0x12 => .ctrl_r,
        0x13 => .ctrl_s,
        0x14 => .ctrl_t,
        0x15 => .ctrl_u,
        0x16 => .ctrl_v,
        0x17 => .ctrl_w,
        0x18 => .ctrl_x,
        0x19 => .ctrl_y,
        0x1A => .ctrl_z,
        0x1B => .escape,
        0x1C => .ctrl_backslash,
        0x1D => .ctrl_close_bracket,
        0x1E => .ctrl_caret,
        0x1F => .ctrl_underscore,
        0x20 => .space,
        0x7F => .delete,
        else => .unknown,
    };

    const text = if (ch >= 0x20 and ch < 0x7F) blk: {
        text_buf[0] = ch;
        break :blk try allocator.dupe(u8, text_buf[0..1]);
    } else try allocator.dupe(u8, "");

    return KeyEvent{
        .text = text,
        .code = key,
        .mod = KeyMod{},
    };
}

/// Parse escape sequence into key events
pub fn parseEscapeSequence(seq: []const u8, allocator: std.mem.Allocator) !?KeyEvent {
    if (seq.len < 2 or seq[0] != 0x1B) return null;

    const text = try allocator.dupe(u8, "");

    return switch (seq[1]) {
        '[' => parseCSISequence(seq, allocator, text),
        'O' => parseSSSequence(seq, allocator, text),
        else => blk: {
            // Alt + key combination
            if (seq.len >= 2) {
                const base_key = try parseChar(seq[1], allocator);
                defer allocator.free(base_key.text);

                break :blk KeyEvent{
                    .text = text,
                    .code = base_key.code,
                    .mod = .{ .alt = true },
                };
            }
            break :blk null;
        },
    };
}

/// Parse CSI (Control Sequence Introducer) sequences
fn parseCSISequence(seq: []const u8, allocator: std.mem.Allocator, text: []const u8) ?KeyEvent {
    if (seq.len < 3) return null;

    // Find final character
    var i: usize = 2; // Skip "ESC["
    while (i < seq.len) {
        const ch = seq[i];
        if (ch >= 0x40 and ch <= 0x7E) break; // Final character range
        i += 1;
    }

    if (i >= seq.len) return null;

    const final_char = seq[i];
    const key: Key = switch (final_char) {
        'A' => .up,
        'B' => .down,
        'C' => .right,
        'D' => .left,
        'H' => .home,
        'F' => .end,
        'P' => .f1,
        'Q' => .f2,
        'R' => .f3,
        'S' => .f4,
        '~' => parseTildeKey(seq[2..i]) orelse .unknown,
        else => .unknown,
    };

    _ = allocator; // Mark as used to avoid warning

    return KeyEvent{
        .text = text,
        .code = key,
        .mod = .{},
    };
}

/// Parse SS3 (Single Shift 3) sequences
fn parseSSSequence(seq: []const u8, _: std.mem.Allocator, text: []const u8) ?KeyEvent {
    if (seq.len < 3) return null;

    const key: Key = switch (seq[2]) {
        'P' => .f1,
        'Q' => .f2,
        'R' => .f3,
        'S' => .f4,
        'H' => .home,
        'F' => .end,
        'A' => .up,
        'B' => .down,
        'C' => .right,
        'D' => .left,
        else => .unknown,
    };

    return KeyEvent{
        .text = text,
        .code = key,
        .mod = .{},
    };
}

/// Parse tilde-terminated sequences like ESC[15~
fn parseTildeKey(params: []const u8) ?Key {
    const num = std.fmt.parseInt(u32, params, 10) catch return null;

    return switch (num) {
        1 => .home,
        2 => .insert_key,
        3 => .delete_key,
        4 => .end,
        5 => .page_up,
        6 => .page_down,
        15 => .f5,
        17 => .f6,
        18 => .f7,
        19 => .f8,
        20 => .f9,
        21 => .f10,
        23 => .f11,
        24 => .f12,
        else => null,
    };
}

// Tests
test "basic character parsing" {
    const key = try parseChar('a', std.testing.allocator);
    defer std.testing.allocator.free(key.text);

    try std.testing.expectEqualSlices(u8, "a", key.text);
    try std.testing.expectEqual(Key.unknown, key.code);
    try std.testing.expect(key.isPrintable());
}

test "control character parsing" {
    const key = try parseChar(0x03, std.testing.allocator); // Ctrl+C
    defer std.testing.allocator.free(key.text);

    try std.testing.expectEqual(Key.ctrl_c, key.code);
    try std.testing.expect(key.isControl());
    try std.testing.expect(!key.isPrintable());
}

test "escape sequence parsing" {
    const seq = "\x1b[A"; // Up arrow
    const key = try parseEscapeSequence(seq, std.testing.allocator);

    try std.testing.expect(key != null);
    if (key) |k| {
        defer std.testing.allocator.free(k.text);
        try std.testing.expectEqual(Key.up, k.code);
    }
}

test "alt key combination" {
    const seq = "\x1ba"; // Alt+a
    const key = try parseEscapeSequence(seq, std.testing.allocator);

    try std.testing.expect(key != null);
    if (key) |k| {
        defer std.testing.allocator.free(k.text);
        try std.testing.expect(k.mod.alt);
    }
}

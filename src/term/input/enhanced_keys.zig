const std = @import("std");
const types = @import("types.zig");

pub const Modifiers = types.Modifiers;

// Extended key definitions for comprehensive input handling
pub const Key = enum {
    // ASCII printable characters (handled separately)
    // Control characters
    null,
    ctrl_a,
    ctrl_b,
    ctrl_c,
    ctrl_d,
    ctrl_e,
    ctrl_f,
    ctrl_g,
    backspace, // ctrl_h
    tab, // ctrl_i
    enter, // ctrl_j (LF) / ctrl_m (CR)
    ctrl_k,
    ctrl_l,
    ctrl_m, // Also Enter/CR
    ctrl_n,
    ctrl_o,
    ctrl_p,
    ctrl_q,
    ctrl_r,
    ctrl_s,
    ctrl_t,
    ctrl_u,
    ctrl_v,
    ctrl_w,
    ctrl_x,
    ctrl_y,
    ctrl_z,
    escape, // ESC
    ctrl_backslash,
    ctrl_close_bracket,
    ctrl_caret,
    ctrl_underscore,
    space,
    delete, // DEL (0x7F)

    // Function keys
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,

    // Arrow keys
    up,
    down,
    left,
    right,

    // Navigation keys
    home,
    end,
    page_up,
    page_down,
    insert,

    // Keypad keys
    kp_0,
    kp_1,
    kp_2,
    kp_3,
    kp_4,
    kp_5,
    kp_6,
    kp_7,
    kp_8,
    kp_9,
    kp_decimal,
    kp_divide,
    kp_multiply,
    kp_subtract,
    kp_add,
    kp_enter,
    kp_equal,

    // Application keypad mode
    app_up,
    app_down,
    app_left,
    app_right,
    app_home,
    app_end,

    // Media keys
    media_play,
    media_pause,
    media_stop,
    media_next,
    media_prev,
    volume_up,
    volume_down,
    volume_mute,

    // Special sequences
    focus_in,
    focus_out,
    mouse_event,

    // Unknown/unsupported key
    unknown,
};

// Key event with comprehensive information
pub const KeyEvent = struct {
    key: Key,
    // For printable characters, this contains the actual UTF-8 character
    char: ?u21 = null,
    // Modifier keys pressed
    mods: Modifiers = .{},
    // Raw escape sequence that generated this event (for debugging)
    raw: []const u8,

    pub fn isPrintable(self: KeyEvent) bool {
        return self.char != null and self.char.? >= 32 and self.char.? != 127;
    }

    pub fn isControl(self: KeyEvent) bool {
        return switch (self.key) {
            .ctrl_a, .ctrl_b, .ctrl_c, .ctrl_d, .ctrl_e, .ctrl_f, .ctrl_g, .backspace, .tab, .enter, .ctrl_k, .ctrl_l, .ctrl_m, .ctrl_n, .ctrl_o, .ctrl_p, .ctrl_q, .ctrl_r, .ctrl_s, .ctrl_t, .ctrl_u, .ctrl_v, .ctrl_w, .ctrl_x, .ctrl_y, .ctrl_z, .escape, .ctrl_backslash, .ctrl_close_bracket, .ctrl_caret, .ctrl_underscore, .delete => true,
            else => false,
        };
    }
};

// Input event types
pub const InputEvent = union(enum) {
    key: KeyEvent,
    mouse: types.MouseEvent,
    focus: types.FocusEvent,
    cursor_position: types.CursorPositionEvent,
    clipboard: types.ClipboardEvent,
    paste_start,
    paste_end,
    unknown: []const u8,
};

// Input parser state machine
pub const InputParser = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator) InputParser {
        return InputParser{
            .allocator = allocator,
            .buffer = std.ArrayListUnmanaged(u8){},
        };
    }

    pub fn deinit(self: *InputParser) void {
        self.buffer.deinit(self.allocator);
    }

    // Parse input bytes and return any complete events
    pub fn parse(self: *InputParser, data: []const u8) ![]InputEvent {
        try self.buffer.appendSlice(self.allocator, data);

        var events = std.ArrayListUnmanaged(InputEvent){};
        errdefer events.deinit(self.allocator);

        var pos: usize = 0;
        while (pos < self.buffer.items.len) {
            if (try self.tryParseEvent(self.buffer.items[pos..])) |result| {
                try events.append(self.allocator, result.event);
                pos += result.consumed;
            } else {
                pos += 1;
            }
        }

        // Remove consumed bytes from buffer
        if (pos > 0) {
            std.mem.copyForwards(u8, self.buffer.items[0..], self.buffer.items[pos..]);
            self.buffer.shrinkRetainingCapacity(self.buffer.items.len - pos);
        }

        return try events.toOwnedSlice(self.allocator);
    }

    const ParseResult = struct {
        event: InputEvent,
        consumed: usize,
    };

    fn tryParseEvent(self: *InputParser, data: []const u8) !?ParseResult {
        if (data.len == 0) return null;

        const first = data[0];

        // Handle single-byte sequences first
        if (first < 0x80) {
            if (first == 0x1B) { // ESC
                return try self.parseEscapeSequence(data);
            } else {
                // Regular ASCII character or control character
                const key_event = try self.parseAsciiChar(first, data[0..1]);
                return ParseResult{
                    .event = .{ .key = key_event },
                    .consumed = 1,
                };
            }
        } else {
            // UTF-8 multi-byte character
            const seq_len = std.unicode.utf8ByteSequenceLength(first) catch return null;
            if (data.len < seq_len) return null; // Need more bytes

            const codepoint = std.unicode.utf8Decode(data[0..seq_len]) catch return null;
            const key_event = KeyEvent{
                .key = .unknown,
                .char = codepoint,
                .raw = data[0..seq_len],
            };
            return ParseResult{
                .event = .{ .key = key_event },
                .consumed = seq_len,
            };
        }
    }

    fn parseAsciiChar(_: *InputParser, ch: u8, raw: []const u8) !KeyEvent {
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

        const char: ?u21 = if (ch >= 0x20 and ch < 0x7F) ch else null;

        return KeyEvent{
            .key = key,
            .char = char,
            .raw = raw,
        };
    }

    fn parseEscapeSequence(self: *InputParser, data: []const u8) !?ParseResult {
        if (data.len < 2) return null; // Need at least ESC + one more char

        return switch (data[1]) {
            '[' => try self.parseCsiSequence(data),
            'O' => try self.parseSs3Sequence(data),
            ']' => try self.parseOscSequence(data),
            else => {
                // Alt + key combination
                if (data.len >= 2) {
                    var key_event = try self.parseAsciiChar(data[1], data[0..2]);
                    key_event.mods.alt = true;
                    return ParseResult{
                        .event = .{ .key = key_event },
                        .consumed = 2,
                    };
                }
                return null;
            },
        };
    }

    fn parseCsiSequence(self: *InputParser, data: []const u8) !?ParseResult {

        // Find the end of the CSI sequence
        var i: usize = 2; // Skip "ESC["
        while (i < data.len) {
            const ch = data[i];
            if ((ch >= 0x40 and ch <= 0x7E)) { // Final character
                break;
            }
            i += 1;
        }

        if (i >= data.len) return null; // Incomplete sequence

        const sequence = data[0 .. i + 1];
        const final_char = data[i];

        // Parse common CSI sequences
        return switch (final_char) {
            'A' => ParseResult{ .event = .{ .key = .{ .key = .up, .raw = sequence } }, .consumed = i + 1 },
            'B' => ParseResult{ .event = .{ .key = .{ .key = .down, .raw = sequence } }, .consumed = i + 1 },
            'C' => ParseResult{ .event = .{ .key = .{ .key = .right, .raw = sequence } }, .consumed = i + 1 },
            'D' => ParseResult{ .event = .{ .key = .{ .key = .left, .raw = sequence } }, .consumed = i + 1 },
            'H' => ParseResult{ .event = .{ .key = .{ .key = .home, .raw = sequence } }, .consumed = i + 1 },
            'F' => ParseResult{ .event = .{ .key = .{ .key = .end, .raw = sequence } }, .consumed = i + 1 },
            'P' => ParseResult{ .event = .{ .key = .{ .key = .f1, .raw = sequence } }, .consumed = i + 1 },
            'Q' => ParseResult{ .event = .{ .key = .{ .key = .f2, .raw = sequence } }, .consumed = i + 1 },
            'R' => ParseResult{ .event = .{ .key = .{ .key = .f3, .raw = sequence } }, .consumed = i + 1 },
            'S' => ParseResult{ .event = .{ .key = .{ .key = .f4, .raw = sequence } }, .consumed = i + 1 },
            '~' => try self.parseTildeSequence(sequence),
            'M', 'm' => try self.parseMouseSequence(sequence),
            else => ParseResult{ .event = .{ .unknown = sequence }, .consumed = i + 1 },
        };
    }

    fn parseTildeSequence(_: *InputParser, sequence: []const u8) !ParseResult {

        // Parse sequences like ESC[2~, ESC[15~, etc.
        const params = sequence[2 .. sequence.len - 1]; // Skip "ESC[" and "~"

        const num = std.fmt.parseInt(u32, params, 10) catch {
            return ParseResult{ .event = .{ .unknown = sequence }, .consumed = sequence.len };
        };

        const key: Key = switch (num) {
            1 => .home,
            2 => .insert,
            3 => .delete,
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
            else => .unknown,
        };

        return ParseResult{
            .event = .{ .key = .{ .key = key, .raw = sequence } },
            .consumed = sequence.len,
        };
    }

    fn parseMouseSequence(_: *InputParser, _: []const u8) !ParseResult {

        // TODO: Implement mouse parsing
        return ParseResult{
            .event = .{ .unknown = "mouse" },
            .consumed = 1,
        };
    }

    fn parseSs3Sequence(_: *InputParser, data: []const u8) !?ParseResult {
        if (data.len < 3) return null;

        const sequence = data[0..3];
        const key: Key = switch (data[2]) {
            'P' => .f1,
            'Q' => .f2,
            'R' => .f3,
            'S' => .f4,
            'H' => .home,
            'F' => .end,
            'A' => .app_up,
            'B' => .app_down,
            'C' => .app_right,
            'D' => .app_left,
            else => .unknown,
        };

        return ParseResult{
            .event = .{ .key = .{ .key = key, .raw = sequence } },
            .consumed = 3,
        };
    }

    fn parseOscSequence(_: *InputParser, data: []const u8) !?ParseResult {

        // For now, consume the basic sequence
        return ParseResult{
            .event = .{ .unknown = data[0..@min(data.len, 10)] },
            .consumed = @min(data.len, 10),
        };
    }
};

test "basic key parsing" {
    var parser = InputParser.init(std.testing.allocator);
    defer parser.deinit();

    const events = try parser.parse("a");
    defer std.testing.allocator.free(events);

    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .key);
    try std.testing.expect(events[0].key.char == 'a');
}

test "control key parsing" {
    var parser = InputParser.init(std.testing.allocator);
    defer parser.deinit();

    const events = try parser.parse("\x03"); // Ctrl+C
    defer std.testing.allocator.free(events);

    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .key);
    try std.testing.expect(events[0].key.key == .ctrl_c);
}

test "escape sequence parsing" {
    var parser = InputParser.init(std.testing.allocator);
    defer parser.deinit();

    const events = try parser.parse("\x1b[A"); // Up arrow
    defer std.testing.allocator.free(events);

    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .key);
    try std.testing.expect(events[0].key.key == .up);
}

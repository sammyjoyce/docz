/// Input parser combining mouse and keyboard handling
/// Provides a comprehensive input parsing system for terminal events.
/// Compatible with Zig 0.15.1
const std = @import("std");
const types = @import("types.zig");

pub const MouseEvent = types.MouseEvent;
pub const KeyEvent = types.KeyEvent;
pub const KeyPressEvent = types.KeyPressEvent;
pub const KeyReleaseEvent = types.KeyReleaseEvent;

/// Parse a single character into a key event
pub fn parseChar(ch: u8, allocator: std.mem.Allocator) !KeyEvent {
    var text_buf: [1]u8 = undefined;

    const key: types.Key = switch (ch) {
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
        .mod = .{},
    };
}

/// Parse SGR mouse event from parameters
pub fn parseSGRMouseEvent(final_char: u8, params: []const u32) ?MouseEvent {
    _ = final_char; // Mark as used to avoid warning
    if (params.len < 3) return null;

    const button_code = params[0];
    const col = params[1];
    const row = params[2];

    // Decode button and modifiers
    const base_button = button_code & 0x3;
    const modifiers = types.Modifiers{
        .shift = (button_code & 0x04) != 0,
        .alt = (button_code & 0x08) != 0,
        .ctrl = (button_code & 0x10) != 0,
        .meta = (button_code & 0x20) != 0,
    };

    // Determine button type
    var button: types.MouseButton = .none;
    var action: types.MouseAction = if ((button_code & 0x40) != 0) .release else .press;

    // Handle wheel events
    if ((button_code & 0x40) != 0) {
        button = switch (base_button) {
            0 => .wheel_up,
            1 => .wheel_down,
            2 => .wheel_left,
            3 => .wheel_right,
            else => .none,
        };
        action = .press; // Wheel events are always press
    } else {
        // Regular button events
        button = switch (base_button) {
            0 => .left,
            1 => .middle,
            2 => .right,
            3 => .none, // Release or motion
            else => .none,
        };

        // Detect motion vs button events
        if (button == .none and (button_code & 0x20) != 0) {
            action = .move;
        }
    }

    return MouseEvent{
        .button = button,
        .action = action,
        .x = col - 1,
        .y = row - 1,
        .mods = modifiers,
        .timestamp = std.time.microTimestamp(),
    };
}

/// Parse escape sequence into key events
pub fn parseEscapeSequence(seq: []const u8, allocator: std.mem.Allocator) !?KeyEvent {
    if (seq.len < 2 or seq[0] != 0x1B) return null;

    const text = try allocator.dupe(u8, "");

    return switch (seq[1]) {
        '[' => parseCSISequenceKey(seq, allocator, text),
        'O' => parseSSSequenceKey(seq, allocator, text),
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
fn parseCSISequenceKey(seq: []const u8, allocator: std.mem.Allocator, text: []const u8) ?KeyEvent {
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
    const key: types.Key = switch (final_char) {
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
fn parseSSSequenceKey(seq: []const u8, _: std.mem.Allocator, text: []const u8) ?KeyEvent {
    if (seq.len < 3) return null;

    const key: types.Key = switch (seq[2]) {
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
fn parseTildeKey(params: []const u8) ?types.Key {
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

/// Unified input event type
pub const InputEvent = union(enum) {
    key_press: KeyPressEvent,
    key_release: KeyReleaseEvent,
    mouse: MouseEvent,
    focus_in,
    focus_out,
    paste_start,
    paste_end,
    window_size: struct { width: u16, height: u16 },
    unknown: []const u8,

    pub fn format(self: InputEvent, writer: *std.Io.Writer) !void {
        switch (self) {
            .key_press => |e| try e.format(writer),
            .key_release => |e| try e.format(writer),
            .mouse => |e| try e.format(writer),
            .focus_in => try writer.print("focus_in", .{}),
            .focus_out => try writer.print("focus_out", .{}),
            .paste_start => try writer.print("paste_start", .{}),
            .paste_end => try writer.print("paste_end", .{}),
            .window_size => |size| try writer.print("resize({d}x{d})", .{ size.width, size.height }),
            .unknown => |data| try writer.print("unknown({s})", .{data}),
        }
    }
};

/// Input parser state machine
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

    /// Parse input data and return completed events
    pub fn parse(self: *InputParser, data: []const u8) ![]InputEvent {
        try self.buffer.appendSlice(self.allocator, data);

        var events = std.ArrayListUnmanaged(InputEvent){};
        errdefer {
            for (events.items) |event| {
                switch (event) {
                    .key_press => |e| self.allocator.free(e.text),
                    .key_release => |e| self.allocator.free(e.text),
                    .unknown => |e| self.allocator.free(e),
                    else => {},
                }
            }
            events.deinit(self.allocator);
        }

        var pos: usize = 0;
        while (pos < self.buffer.items.len) {
            if (try self.tryParseEvent(self.buffer.items[pos..])) |result| {
                try events.append(self.allocator, result.event);
                pos += result.consumed;
            } else {
                // Skip unknown byte
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

        // Handle escape sequences
        if (first == 0x1B) {
            return try self.parseEscapeSequence(data);
        }

        // Handle regular characters
        if (first < 0x80) {
            const key_event = try parseChar(first, self.allocator);
            return ParseResult{
                .event = .{ .key_press = key_event },
                .consumed = 1,
            };
        }

        // Handle UTF-8 multi-byte characters
        const seq_len = std.unicode.utf8ByteSequenceLength(first) catch return null;
        if (data.len < seq_len) return null;

        const codepoint = std.unicode.utf8Decode(data[0..seq_len]) catch return null;
        var text_buf: [4]u8 = undefined;
        const text_len = std.unicode.utf8Encode(codepoint, &text_buf) catch return null;
        const text = try self.allocator.dupe(u8, text_buf[0..text_len]);

        const key_event = KeyEvent{
            .text = text,
            .code = .unknown,
            .mod = .{},
        };

        return ParseResult{
            .event = .{ .key_press = key_event },
            .consumed = seq_len,
        };
    }

    fn parseEscapeSequence(self: *InputParser, data: []const u8) !?ParseResult {
        if (data.len < 2) return null;

        return switch (data[1]) {
            '[' => try self.parseCSI(data),
            'O' => try self.parseSSSequence(data),
            ']' => try self.parseOSC(data),
            else => {
                // Alt + key combination
                if (data.len >= 2) {
                    var key_event = try parseChar(data[1], self.allocator);
                    key_event.mod.alt = true;
                    return ParseResult{
                        .event = .{ .key_press = key_event },
                        .consumed = 2,
                    };
                }
                return null;
            },
        };
    }

    fn parseCSI(self: *InputParser, data: []const u8) !?ParseResult {
        // Find the end of CSI sequence
        var i: usize = 2; // Skip "ESC["
        var params = std.ArrayListUnmanaged(u32){};
        defer params.deinit(self.allocator);

        // Parse parameters
        var current_param: u32 = 0;
        var has_param = false;

        while (i < data.len) {
            const ch = data[i];

            if (ch >= '0' and ch <= '9') {
                current_param = current_param * 10 + (ch - '0');
                has_param = true;
            } else if (ch == ';') {
                if (has_param) {
                    try params.append(self.allocator, current_param);
                    current_param = 0;
                    has_param = false;
                } else {
                    try params.append(self.allocator, 0);
                }
            } else if (ch >= 0x40 and ch <= 0x7E) {
                // Final character
                if (has_param) {
                    try params.append(self.allocator, current_param);
                }
                break;
            } else if (ch == '<') {
                // SGR mouse mode
                i += 1;
                continue;
            }

            i += 1;
        }

        if (i >= data.len) return null; // Incomplete sequence

        const final_char = data[i];
        const sequence = data[0 .. i + 1];

        // Handle mouse events
        if ((final_char == 'M' or final_char == 'm') and data.len > 2 and data[2] == '<') {
            if (parseSGRMouseEvent(final_char, params.items)) |mouse_event| {
                return ParseResult{
                    .event = .{ .mouse = mouse_event },
                    .consumed = i + 1,
                };
            }
        }

        // Handle keyboard events
        if (try self.parseCSIKeyboard(sequence, final_char, params.items)) |key_event| {
            return ParseResult{
                .event = .{ .key_press = key_event },
                .consumed = i + 1,
            };
        }

        // Handle special events
        if (try self.parseCSISpecial(sequence, final_char, params.items)) |special_event| {
            return ParseResult{
                .event = special_event,
                .consumed = i + 1,
            };
        }

        // Unknown sequence
        const unknown_data = try self.allocator.dupe(u8, sequence);
        return ParseResult{
            .event = .{ .unknown = unknown_data },
            .consumed = i + 1,
        };
    }

    fn parseCSIKeyboard(self: *InputParser, _: []const u8, final_char: u8, params: []const u32) !?KeyEvent {
        const text = try self.allocator.dupe(u8, "");

        const key: types.Key = switch (final_char) {
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
            '~' => if (params.len > 0) switch (params[0]) {
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
                else => .unknown,
            } else .unknown,
            else => return null,
        };

        return KeyEvent{
            .text = text,
            .code = key,
            .mod = .{},
        };
    }

    fn parseCSISpecial(_: *InputParser, _: []const u8, final_char: u8, params: []const u32) !?InputEvent {
        return switch (final_char) {
            't' => {
                // Window operations
                if (params.len >= 3 and params[0] == 8) {
                    // Window size report
                    return InputEvent{ .window_size = .{
                        .height = @as(u16, @intCast(params[1])),
                        .width = @as(u16, @intCast(params[2])),
                    } };
                }
                return null;
            },
            else => null,
        };
    }

    fn parseSSSequence(self: *InputParser, data: []const u8) !?ParseResult {
        if (data.len < 3) return null;

        const text = try self.allocator.dupe(u8, "");
        const key_event = parseSSSequenceKey(data, self.allocator, text);
        if (key_event) |event| {
            return ParseResult{
                .event = .{ .key_press = event },
                .consumed = 3,
            };
        }

        return null;
    }

    fn parseOSC(self: *InputParser, data: []const u8) !?ParseResult {
        // Find OSC terminator (BEL or ST)
        var i: usize = 2; // Skip "ESC]"
        while (i < data.len) {
            if (data[i] == 0x07) { // BEL
                break;
            }
            if (data[i] == 0x1B and i + 1 < data.len and data[i + 1] == '\\') { // ST
                i += 1;
                break;
            }
            i += 1;
        }

        if (i >= data.len) return null; // Incomplete sequence

        const sequence = data[0 .. i + 1];

        // Check for specific OSC sequences
        if (std.mem.startsWith(u8, sequence, "\x1b]0;")) {
            // Window title - ignore for now
            return ParseResult{
                .event = .{ .unknown = try self.allocator.dupe(u8, "title_change") },
                .consumed = i + 1,
            };
        }

        if (std.mem.startsWith(u8, sequence, "\x1b]52;")) {
            // Clipboard operation - could be implemented later
            return ParseResult{
                .event = .{ .unknown = try self.allocator.dupe(u8, "clipboard") },
                .consumed = i + 1,
            };
        }

        const unknown_data = try self.allocator.dupe(u8, sequence);
        return ParseResult{
            .event = .{ .unknown = unknown_data },
            .consumed = i + 1,
        };
    }
};

// Tests
test "basic character parsing" {
    var parser = InputParser.init(std.testing.allocator);
    defer parser.deinit();

    const events = try parser.parse("a");
    defer {
        for (events) |event| {
            switch (event) {
                .key_press => |e| std.testing.allocator.free(e.text),
                else => {},
            }
        }
        std.testing.allocator.free(events);
    }

    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .key_press);
    try std.testing.expectEqualStrings("a", events[0].key_press.text);
}

test "escape sequence parsing" {
    var parser = InputParser.init(std.testing.allocator);
    defer parser.deinit();

    const events = try parser.parse("\x1b[A"); // Up arrow
    defer {
        for (events) |event| {
            switch (event) {
                .key_press => |e| std.testing.allocator.free(e.text),
                else => {},
            }
        }
        std.testing.allocator.free(events);
    }

    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .key_press);
    try std.testing.expectEqual(types.Key.up, events[0].key_press.code);
}

test "mouse event parsing" {
    var parser = InputParser.init(std.testing.allocator);
    defer parser.deinit();

    const events = try parser.parse("\x1b[<0;12;5M"); // Left click at (11, 4)
    defer {
        for (events) |event| {
            switch (event) {
                .key_press => |e| std.testing.allocator.free(e.text),
                .unknown => |e| std.testing.allocator.free(e),
                else => {},
            }
        }
        std.testing.allocator.free(events);
    }

    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .mouse);

    const mouse = events[0].mouse.mouse();
    try std.testing.expectEqual(@as(i32, 11), mouse.x);
    try std.testing.expectEqual(@as(i32, 4), mouse.y);
}

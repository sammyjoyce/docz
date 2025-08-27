/// Unified input parser combining enhanced mouse and keyboard handling
/// Provides a comprehensive input parsing system for terminal events.
/// Compatible with Zig 0.15.1
const std = @import("std");
const enhanced_mouse = @import("mouse.zig");
const enhanced_keyboard = @import("keyboard.zig");

pub const MouseEvent = enhanced_mouse.MouseEvent;
pub const KeyEvent = enhanced_keyboard.KeyEvent;
pub const KeyPressEvent = enhanced_keyboard.KeyPressEvent;
pub const KeyReleaseEvent = enhanced_keyboard.KeyReleaseEvent;

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
            const key_event = try enhanced_keyboard.parseChar(first, self.allocator);
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

        const key_event = enhanced_keyboard.KeyEvent{
            .text = text,
            .code = .unknown,
            .mod = enhanced_keyboard.KeyMod{},
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
                    var key_event = try enhanced_keyboard.parseChar(data[1], self.allocator);
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
            if (enhanced_mouse.parseSGRMouseEvent(final_char, params.items)) |mouse_event| {
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

    fn parseCSIKeyboard(self: *InputParser, _: []const u8, final_char: u8, params: []const u32) !?enhanced_keyboard.KeyEvent {
        const text = try self.allocator.dupe(u8, "");

        const key: enhanced_keyboard.Key = switch (final_char) {
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

        return enhanced_keyboard.KeyEvent{
            .text = text,
            .code = key,
            .mod = enhanced_keyboard.KeyMod{},
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

        const key_event = enhanced_keyboard.parseEscapeSequence(data[0..3], self.allocator) catch return null;
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
    try std.testing.expectEqual(enhanced_keyboard.Key.up, events[0].key_press.code);
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

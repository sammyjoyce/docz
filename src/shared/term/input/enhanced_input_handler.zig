/// Enhanced input event handler with advanced parsing capabilities
/// Provides advanced input parsing with multi-event support and bracketed paste
/// Compatible with Zig 0.15.1 and follows proper error handling patterns
const std = @import("std");

/// Input event types
pub const Event = union(enum) {
    key_press: KeyEvent,
    paste: PasteEvent,
    paste_start: void,
    paste_end: void,
    mouse: MouseEvent,
    resize: ResizeEvent,
    focus_in: void,
    focus_out: void,
    unknown: UnknownEvent,

    pub fn format(self: Event, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .key_press => |key| try writer.print("KeyPress({s})", .{key.key}),
            .paste => |paste| try writer.print("Paste({d} runes)", .{paste.content.len}),
            .paste_start => try writer.writeAll("PasteStart"),
            .paste_end => try writer.writeAll("PasteEnd"),
            .mouse => |mouse| try writer.print("Mouse({s} at {d},{d})", .{ @tagName(mouse.action), mouse.x, mouse.y }),
            .resize => |resize| try writer.print("Resize({d}x{d})", .{ resize.width, resize.height }),
            .focus_in => try writer.writeAll("FocusIn"),
            .focus_out => try writer.writeAll("FocusOut"),
            .unknown => |unknown| try writer.print("Unknown({s})", .{unknown.sequence}),
        }
    }
};

/// Key press event
pub const KeyEvent = struct {
    key: []const u8,
    modifiers: KeyModifiers = .{},

    pub const KeyModifiers = struct {
        ctrl: bool = false,
        alt: bool = false,
        shift: bool = false,
        meta: bool = false,
    };
};

/// Paste event containing pasted text
pub const PasteEvent = struct {
    content: []const u21, // Unicode codepoints
    allocator: std.mem.Allocator,

    pub fn deinit(self: *PasteEvent) void {
        self.allocator.free(self.content);
    }

    /// Convert paste content to UTF-8 string
    pub fn toUtf8(self: PasteEvent, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        for (self.content) |codepoint| {
            var buf: [4]u8 = undefined;
            const len = try std.unicode.utf8Encode(codepoint, &buf);
            try result.appendSlice(buf[0..len]);
        }

        return result.toOwnedSlice();
    }
};

/// Mouse event
pub const MouseEvent = struct {
    action: MouseAction,
    x: u16,
    y: u16,
    button: MouseButton = .none,
    modifiers: KeyEvent.KeyModifiers = .{},

    pub const MouseAction = enum {
        press,
        release,
        motion,
        drag,
        wheel_up,
        wheel_down,
        wheel_left,
        wheel_right,
    };

    pub const MouseButton = enum {
        none,
        left,
        right,
        middle,
        button4,
        button5,
    };
};

/// Resize event
pub const ResizeEvent = struct {
    width: u16,
    height: u16,
};

/// Unknown/unparsed sequence
pub const UnknownEvent = struct {
    sequence: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *UnknownEvent) void {
        self.allocator.free(self.sequence);
    }
};

/// Multi-event container for when one input generates multiple events
pub const MultiEvent = struct {
    events: []Event,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *MultiEvent) void {
        for (self.events) |*event| {
            switch (event.*) {
                .paste => |*paste| paste.deinit(),
                .unknown => |*unknown| unknown.deinit(),
                else => {},
            }
        }
        self.allocator.free(self.events);
    }
};

/// Enhanced input event parser with logging support
pub const EnhancedInputParser = struct {
    allocator: std.mem.Allocator,
    paste_buffer: ?std.ArrayList(u8) = null,
    logger: ?Logger = null,

    const Self = @This();

    /// Simple logger interface
    pub const Logger = struct {
        logFn: *const fn (ctx: ?*anyopaque, comptime format: []const u8, args: anytype) void,
        context: ?*anyopaque = null,

        pub fn log(self: Logger, comptime format: []const u8, args: anytype) void {
            self.logFn(self.context, format, args);
        }
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.paste_buffer) |*buffer| {
            buffer.deinit();
        }
    }

    pub fn setLogger(self: *Self, logger: Logger) void {
        self.logger = logger;
    }

    /// Parse input sequence into events
    pub fn parseSequence(self: *Self, input: []const u8) ![]Event {
        if (self.logger) |logger| {
            logger.log("input: parsing {d} bytes: {s}", .{ input.len, std.fmt.fmtSliceEscapeLower(input) });
        }

        var events = std.ArrayList(Event).init(self.allocator);
        errdefer {
            for (events.items) |*event| {
                switch (event.*) {
                    .paste => |*paste| paste.deinit(),
                    .unknown => |*unknown| unknown.deinit(),
                    else => {},
                }
            }
            events.deinit();
        }

        var i: usize = 0;
        while (i < input.len) {
            const bytes_consumed, const event = try self.parseOneEvent(input[i..]);

            if (event) |ev| {
                // Handle bracketed paste mode
                if (self.paste_buffer != null) {
                    switch (ev) {
                        .paste_end => {
                            // Convert accumulated paste data to runes
                            const paste_data = try self.finalizePaste();
                            try events.append(.{ .paste = paste_data });
                            try events.append(.{ .paste_end = {} });
                        },
                        .paste_start => {
                            try events.append(ev);
                        },
                        else => {
                            // Accumulate data during paste
                            try self.accumulatePasteData(input[i .. i + bytes_consumed]);
                        },
                    }
                } else {
                    switch (ev) {
                        .paste_start => {
                            self.paste_buffer = std.ArrayList(u8).init(self.allocator);
                            try events.append(ev);
                        },
                        else => {
                            try events.append(ev);
                        },
                    }
                }
            }

            i += @max(1, bytes_consumed);
        }

        return events.toOwnedSlice();
    }

    /// Parse a single event from input
    fn parseOneEvent(self: *Self, input: []const u8) !struct { usize, ?Event } {
        if (input.len == 0) return .{ 0, null };

        // ESC sequences
        if (input[0] == 0x1B) {
            return try self.parseEscapeSequence(input);
        }

        // Control characters
        if (input[0] < 0x20) {
            return try self.parseControlChar(input);
        }

        // Regular printable characters
        return try self.parseRegularChar(input);
    }

    /// Parse escape sequences
    fn parseEscapeSequence(self: *Self, input: []const u8) !struct { usize, ?Event } {
        if (input.len < 2) return .{ 1, .{ .unknown = .{ .sequence = try self.allocator.dupe(u8, input), .allocator = self.allocator } } };

        // CSI sequences (ESC [)
        if (input[1] == '[') {
            return try self.parseCSISequence(input);
        }

        // OSC sequences (ESC ])
        if (input[1] == ']') {
            return try self.parseOSCSequence(input);
        }

        // Simple ESC + char combinations
        if (input.len >= 2) {
            const key_name = try std.fmt.allocPrint(self.allocator, "alt+{c}", .{input[1]});
            return .{ 2, .{ .key_press = .{ .key = key_name, .modifiers = .{ .alt = true } } } };
        }

        return .{ 1, .{ .unknown = .{ .sequence = try self.allocator.dupe(u8, input[0..1]), .allocator = self.allocator } } };
    }

    /// Parse CSI (Control Sequence Introducer) sequences
    fn parseCSISequence(self: *Self, input: []const u8) !struct { usize, ?Event } {
        // Find the end of the CSI sequence
        var end: usize = 2; // Start after "ESC["
        while (end < input.len) {
            const c = input[end];
            if (c >= 0x40 and c <= 0x7E) { // Final character
                end += 1;
                break;
            }
            end += 1;
        }

        if (end > input.len) {
            return .{ input.len, .{ .unknown = .{ .sequence = try self.allocator.dupe(u8, input), .allocator = self.allocator } } };
        }

        const sequence = input[0..end];

        // Mouse sequences
        if (sequence.len >= 6 and sequence[2] == 'M') {
            return try self.parseMouseEvent(sequence);
        }

        // Window resize
        if (std.mem.eql(u8, sequence, "\x1b[8;")) {
            // This is incomplete - need full implementation
            return .{ end, null };
        }

        // Focus events
        if (std.mem.eql(u8, sequence, "\x1b[I")) {
            return .{ end, .{ .focus_in = {} } };
        }
        if (std.mem.eql(u8, sequence, "\x1b[O")) {
            return .{ end, .{ .focus_out = {} } };
        }

        // Bracketed paste
        if (std.mem.startsWith(u8, sequence, "\x1b[200~")) {
            return .{ end, .{ .paste_start = {} } };
        }
        if (std.mem.startsWith(u8, sequence, "\x1b[201~")) {
            return .{ end, .{ .paste_end = {} } };
        }

        // Arrow keys and function keys
        if (sequence.len >= 3) {
            const final_char = sequence[sequence.len - 1];
            switch (final_char) {
                'A' => return .{ end, .{ .key_press = .{ .key = try self.allocator.dupe(u8, "up") } } },
                'B' => return .{ end, .{ .key_press = .{ .key = try self.allocator.dupe(u8, "down") } } },
                'C' => return .{ end, .{ .key_press = .{ .key = try self.allocator.dupe(u8, "right") } } },
                'D' => return .{ end, .{ .key_press = .{ .key = try self.allocator.dupe(u8, "left") } } },
                'H' => return .{ end, .{ .key_press = .{ .key = try self.allocator.dupe(u8, "home") } } },
                'F' => return .{ end, .{ .key_press = .{ .key = try self.allocator.dupe(u8, "end") } } },
                else => {},
            }
        }

        return .{ end, .{ .unknown = .{ .sequence = try self.allocator.dupe(u8, sequence), .allocator = self.allocator } } };
    }

    /// Parse OSC (Operating System Command) sequences
    fn parseOSCSequence(self: *Self, input: []const u8) !struct { usize, ?Event } {
        // Find terminator (BEL or ST)
        var end: usize = 2; // Start after "ESC]"
        while (end < input.len) {
            if (input[end] == 0x07) { // BEL
                end += 1;
                break;
            }
            if (end + 1 < input.len and input[end] == 0x1B and input[end + 1] == '\\') { // ST
                end += 2;
                break;
            }
            end += 1;
        }

        return .{ end, .{ .unknown = .{ .sequence = try self.allocator.dupe(u8, input[0..end]), .allocator = self.allocator } } };
    }

    /// Parse control characters
    fn parseControlChar(self: *Self, input: []const u8) !struct { usize, ?Event } {
        const char = input[0];

        const key_name = switch (char) {
            0x01 => "ctrl+a",
            0x02 => "ctrl+b",
            0x03 => "ctrl+c",
            0x04 => "ctrl+d",
            0x05 => "ctrl+e",
            0x06 => "ctrl+f",
            0x07 => "ctrl+g",
            0x08 => "backspace",
            0x09 => "tab",
            0x0A => "enter",
            0x0B => "ctrl+k",
            0x0C => "ctrl+l",
            0x0D => "enter",
            0x0E => "ctrl+n",
            0x0F => "ctrl+o",
            0x10 => "ctrl+p",
            0x11 => "ctrl+q",
            0x12 => "ctrl+r",
            0x13 => "ctrl+s",
            0x14 => "ctrl+t",
            0x15 => "ctrl+u",
            0x16 => "ctrl+v",
            0x17 => "ctrl+w",
            0x18 => "ctrl+x",
            0x19 => "ctrl+y",
            0x1A => "ctrl+z",
            0x1B => "escape",
            0x1C => "ctrl+\\",
            0x1D => "ctrl+]",
            0x1E => "ctrl+^",
            0x1F => "ctrl+_",
            else => null,
        };

        if (key_name) |name| {
            return .{ 1, .{ .key_press = .{
                .key = try self.allocator.dupe(u8, name),
                .modifiers = if (std.mem.startsWith(u8, name, "ctrl+")) .{ .ctrl = true } else .{},
            } } };
        }

        return .{ 1, .{ .unknown = .{ .sequence = try self.allocator.dupe(u8, input[0..1]), .allocator = self.allocator } } };
    }

    /// Parse regular printable characters
    fn parseRegularChar(self: *Self, input: []const u8) !struct { usize, ?Event } {
        // Handle UTF-8 sequences
        const seq_len = std.unicode.utf8ByteSequenceLength(input[0]) catch 1;
        const end = @min(seq_len, input.len);

        const char_data = input[0..end];

        // Convert to string for the key name
        const key_name = try self.allocator.dupe(u8, char_data);

        return .{ end, .{ .key_press = .{ .key = key_name } } };
    }

    /// Parse mouse event from CSI sequence
    fn parseMouseEvent(self: *Self, sequence: []const u8) !struct { usize, ?Event } {
        // Basic mouse parsing - would need full implementation for production use
        if (sequence.len >= 6) {
            const button_byte = sequence[3];
            const x = sequence[4] -% 32; // Remove bias
            const y = sequence[5] -% 32;

            const button: MouseEvent.MouseButton = switch (button_byte & 0x03) {
                0 => .left,
                1 => .middle,
                2 => .right,
                else => .none,
            };

            const action: MouseEvent.MouseAction = if (button_byte & 0x20 != 0) .motion else .press;

            return .{ sequence.len, .{ .mouse = .{
                .action = action,
                .x = x,
                .y = y,
                .button = button,
            } } };
        }

        return .{ sequence.len, .{ .unknown = .{ .sequence = try self.allocator.dupe(u8, sequence), .allocator = self.allocator } } };
    }

    /// Accumulate paste data
    fn accumulatePasteData(self: *Self, data: []const u8) !void {
        if (self.paste_buffer) |*buffer| {
            try buffer.appendSlice(data);
        }
    }

    /// Finalize paste and convert to runes
    fn finalizePaste(self: *Self) !PasteEvent {
        if (self.paste_buffer) |buffer| {
            defer {
                buffer.deinit();
                self.paste_buffer = null;
            }

            var runes = std.ArrayList(u21).init(self.allocator);
            errdefer runes.deinit();

            var i: usize = 0;
            while (i < buffer.items.len) {
                const seq_len = std.unicode.utf8ByteSequenceLength(buffer.items[i]) catch 1;
                if (i + seq_len > buffer.items.len) break;

                const codepoint = std.unicode.utf8Decode(buffer.items[i .. i + seq_len]) catch {
                    i += 1;
                    continue;
                };

                try runes.append(codepoint);
                i += seq_len;
            }

            return PasteEvent{
                .content = try runes.toOwnedSlice(),
                .allocator = self.allocator,
            };
        }

        return PasteEvent{
            .content = &[_]u21{},
            .allocator = self.allocator,
        };
    }
};

// Tests
test "basic key parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var parser = EnhancedInputParser.init(allocator);
    defer parser.deinit();

    const events = try parser.parseSequence("a");
    defer {
        for (events) |*event| {
            switch (event.*) {
                .key_press => |*key| allocator.free(key.key),
                else => {},
            }
        }
        allocator.free(events);
    }

    try testing.expect(events.len == 1);
    try testing.expect(events[0] == .key_press);
    try testing.expectEqualStrings("a", events[0].key_press.key);
}

test "control character parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var parser = EnhancedInputParser.init(allocator);
    defer parser.deinit();

    const events = try parser.parseSequence("\x03"); // Ctrl+C
    defer {
        for (events) |*event| {
            switch (event.*) {
                .key_press => |*key| allocator.free(key.key),
                else => {},
            }
        }
        allocator.free(events);
    }

    try testing.expect(events.len == 1);
    try testing.expect(events[0] == .key_press);
    try testing.expectEqualStrings("ctrl+c", events[0].key_press.key);
    try testing.expect(events[0].key_press.modifiers.ctrl);
}

test "arrow key parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var parser = EnhancedInputParser.init(allocator);
    defer parser.deinit();

    const events = try parser.parseSequence("\x1b[A"); // Up arrow
    defer {
        for (events) |*event| {
            switch (event.*) {
                .key_press => |*key| allocator.free(key.key),
                else => {},
            }
        }
        allocator.free(events);
    }

    try testing.expect(events.len == 1);
    try testing.expect(events[0] == .key_press);
    try testing.expectEqualStrings("up", events[0].key_press.key);
}

test "paste event handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var parser = EnhancedInputParser.init(allocator);
    defer parser.deinit();

    // Simulate bracketed paste
    const events = try parser.parseSequence("\x1b[200~Hello\x1b[201~");
    defer {
        for (events) |*event| {
            switch (event.*) {
                .paste => |*paste| paste.deinit(),
                else => {},
            }
        }
        allocator.free(events);
    }

    try testing.expect(events.len >= 2);
    try testing.expect(events[0] == .paste_start);

    // Find the paste event
    var found_paste = false;
    for (events) |event| {
        if (event == .paste) {
            found_paste = true;
            break;
        }
    }
    try testing.expect(found_paste);
}

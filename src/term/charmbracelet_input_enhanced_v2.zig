/// Enhanced input handling inspired by charmbracelet/x input module
/// Provides comprehensive key and event handling with modern terminal protocol support
/// Compatible with Zig 0.15.1 patterns
const std = @import("std");

/// Key modifiers that can be combined
pub const KeyMod = packed struct(u8) {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
    meta: bool = false,
    hyper: bool = false,
    super: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,

    pub fn contains(self: KeyMod, other: KeyMod) bool {
        const self_bits = @as(u8, @bitCast(self));
        const other_bits = @as(u8, @bitCast(other));
        return (self_bits & other_bits) == other_bits;
    }

    pub fn isEmpty(self: KeyMod) bool {
        return @as(u8, @bitCast(self)) == 0;
    }
};

/// Extended key code constants
pub const KeyExtended: u21 = 0x110000; // Beyond Unicode range

/// Special key symbols following charmbracelet/x pattern
pub const Key = enum(u32) {
    // Special keys
    up = KeyExtended + 1,
    down,
    right,
    left,
    begin,
    find,
    insert,
    delete,
    select,
    page_up,
    page_down,
    home,
    end,

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

    // Special names for common keys
    backspace = 0x7F,
    tab = 0x09,
    enter = 0x0D,
    return_ = 0x0D,
    escape = 0x1B,
    esc = 0x1B,
    space = 0x20,

    // Return code for extended sequences that contain text
    extended = KeyExtended,

    _,
};

/// Comprehensive key event structure
pub const KeyStruct = struct {
    text: []const u8 = "", // Actual character text if printable
    mod: KeyMod = .{}, // Modifier keys
    code: u32, // Key code (rune or special key)
    shifted_code: u32 = 0, // Shifted key code (Kitty protocol)
    base_code: u32 = 0, // Base code (Kitty protocol)
    is_repeat: bool = false, // Key repeat flag (Kitty protocol)

    pub fn toString(self: KeyStruct) []const u8 {
        if (self.text.len > 0 and !std.mem.eql(u8, self.text, " ")) {
            return self.text;
        }
        return self.keystroke();
    }

    /// Get keystroke representation with modifiers
    pub fn keystroke(self: KeyStruct) []const u8 {
        // This would build a string with modifiers in a real implementation
        // For now, simplified
        if (self.code == @intFromEnum(Key.up)) return "up";
        if (self.code == @intFromEnum(Key.down)) return "down";
        if (self.code == @intFromEnum(Key.left)) return "left";
        if (self.code == @intFromEnum(Key.right)) return "right";
        if (self.code == @intFromEnum(Key.enter)) return "enter";
        if (self.code == @intFromEnum(Key.escape)) return "esc";
        if (self.code == @intFromEnum(Key.space)) return "space";
        if (self.code == @intFromEnum(Key.tab)) return "tab";
        if (self.code == @intFromEnum(Key.backspace)) return "backspace";

        // Default fallback
        return "unknown";
    }
};

/// Key press event
pub const KeyPressEvent = struct {
    key: KeyStruct,

    pub fn toString(self: KeyPressEvent) []const u8 {
        return self.key.toString();
    }

    pub fn keystroke(self: KeyPressEvent) []const u8 {
        return self.key.keystroke();
    }

    pub fn getKey(self: KeyPressEvent) KeyStruct {
        return self.key;
    }
};

/// Mouse button types
pub const MouseButton = enum(u8) {
    none = 0,
    left = 1,
    middle = 2,
    right = 3,
    wheel_up = 4,
    wheel_down = 5,
    wheel_left = 6,
    wheel_right = 7,
    backward = 8,
    forward = 9,
    button10 = 10,
    button11 = 11,

    pub fn format(self: MouseButton, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        const str = switch (self) {
            .none => "none",
            .left => "left",
            .middle => "middle",
            .right => "right",
            .wheel_up => "wheel-up",
            .wheel_down => "wheel-down",
            .wheel_left => "wheel-left",
            .wheel_right => "wheel-right",
            .backward => "backward",
            .forward => "forward",
            .button10 => "button10",
            .button11 => "button11",
        };
        try writer.print("{s}", .{str});
    }
};

/// Base mouse event
pub const Mouse = struct {
    x: i32,
    y: i32,
    button: MouseButton,
    mod: KeyMod,
};

/// Mouse event types
pub const MouseClickEvent = Mouse;
pub const MouseReleaseEvent = Mouse;
pub const MouseWheelEvent = Mouse;
pub const MouseMotionEvent = Mouse;

/// Focus events
pub const FocusEvent = enum {
    focus_in,
    focus_out,
};

/// Generic event type
pub const Event = union(enum) {
    key_press: KeyPressEvent,
    mouse_click: MouseClickEvent,
    mouse_release: MouseReleaseEvent,
    mouse_wheel: MouseWheelEvent,
    mouse_motion: MouseMotionEvent,
    focus: FocusEvent,
    unknown: []const u8,
};

/// Input parser for terminal escape sequences
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

    /// Parse input data and return events
    pub fn parse(self: *InputParser, data: []const u8) ![]Event {
        try self.buffer.appendSlice(self.allocator, data);

        var events = std.ArrayListUnmanaged(Event){};
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

        // Remove consumed bytes
        if (pos > 0) {
            std.mem.copyForwards(u8, self.buffer.items[0..], self.buffer.items[pos..]);
            self.buffer.shrinkRetainingCapacity(self.buffer.items.len - pos);
        }

        return try events.toOwnedSlice(self.allocator);
    }

    const ParseResult = struct {
        event: Event,
        consumed: usize,
    };

    fn tryParseEvent(self: *InputParser, data: []const u8) !?ParseResult {
        if (data.len == 0) return null;

        const first = data[0];

        if (first < 0x80) {
            if (first == 0x1B) { // ESC
                return try self.parseEscapeSequence(data);
            } else {
                // Regular ASCII/control character
                const key_event = self.parseAsciiChar(first, data[0..1]);
                return ParseResult{
                    .event = .{ .key_press = .{ .key = key_event } },
                    .consumed = 1,
                };
            }
        } else {
            // UTF-8 multi-byte character
            const seq_len = std.unicode.utf8ByteSequenceLength(first) catch return null;
            if (data.len < seq_len) return null;

            const key_event = KeyStruct{
                .code = @intFromEnum(Key.extended),
                .text = data[0..seq_len],
            };
            return ParseResult{
                .event = .{ .key_press = .{ .key = key_event } },
                .consumed = seq_len,
            };
        }
    }

    fn parseAsciiChar(_: *InputParser, ch: u8, raw: []const u8) KeyStruct {
        const code: u32 = switch (ch) {
            0x08 => @intFromEnum(Key.backspace),
            0x09 => @intFromEnum(Key.tab),
            0x0A, 0x0D => @intFromEnum(Key.enter),
            0x1B => @intFromEnum(Key.escape),
            0x20 => @intFromEnum(Key.space),
            0x7F => @intFromEnum(Key.delete),
            else => ch,
        };

        const text: []const u8 = if (ch >= 0x20 and ch < 0x7F) raw else "";

        return KeyStruct{
            .code = code,
            .text = text,
        };
    }

    fn parseEscapeSequence(self: *InputParser, data: []const u8) !?ParseResult {
        if (data.len < 2) return null;

        return switch (data[1]) {
            '[' => try self.parseCsiSequence(data),
            'O' => try self.parseSs3Sequence(data),
            else => {
                // Alt + key combination
                if (data.len >= 2) {
                    var key_event = self.parseAsciiChar(data[1], data[1..2]);
                    key_event.mod.alt = true;
                    return ParseResult{
                        .event = .{ .key_press = .{ .key = key_event } },
                        .consumed = 2,
                    };
                }
                return null;
            },
        };
    }

    fn parseCsiSequence(self: *InputParser, data: []const u8) !?ParseResult {
        // Find end of CSI sequence
        var i: usize = 2; // Skip "ESC["
        while (i < data.len) {
            const ch = data[i];
            if (ch >= 0x40 and ch <= 0x7E) { // Final character
                break;
            }
            i += 1;
        }

        if (i >= data.len) return null; // Incomplete

        const sequence = data[0 .. i + 1];
        const final_char = data[i];

        // Parse common CSI sequences
        const key_code: u32 = switch (final_char) {
            'A' => @intFromEnum(Key.up),
            'B' => @intFromEnum(Key.down),
            'C' => @intFromEnum(Key.right),
            'D' => @intFromEnum(Key.left),
            'H' => @intFromEnum(Key.home),
            'F' => @intFromEnum(Key.end),
            '~' => try self.parseTildeKey(sequence),
            'M', 'm' => return try self.parseMouseSequence(sequence),
            else => @intFromEnum(Key.extended),
        };

        const key_event = KeyStruct{
            .code = key_code,
        };

        return ParseResult{
            .event = .{ .key_press = .{ .key = key_event } },
            .consumed = i + 1,
        };
    }

    fn parseTildeKey(_: *InputParser, sequence: []const u8) !u32 {
        // Parse sequences like ESC[2~, ESC[15~, etc.
        const params = sequence[2 .. sequence.len - 1]; // Skip "ESC[" and "~"

        const num = std.fmt.parseInt(u32, params, 10) catch {
            return @intFromEnum(Key.extended);
        };

        return switch (num) {
            1 => @intFromEnum(Key.home),
            2 => @intFromEnum(Key.insert),
            3 => @intFromEnum(Key.delete),
            4 => @intFromEnum(Key.end),
            5 => @intFromEnum(Key.page_up),
            6 => @intFromEnum(Key.page_down),
            15 => @intFromEnum(Key.f5),
            17 => @intFromEnum(Key.f6),
            18 => @intFromEnum(Key.f7),
            19 => @intFromEnum(Key.f8),
            20 => @intFromEnum(Key.f9),
            21 => @intFromEnum(Key.f10),
            23 => @intFromEnum(Key.f11),
            24 => @intFromEnum(Key.f12),
            else => @intFromEnum(Key.extended),
        };
    }

    fn parseMouseSequence(self: *InputParser, sequence: []const u8) !ParseResult {
        // Parse SGR mouse sequence ESC[<...M or ESC[<...m
        if (sequence.len > 3 and sequence[2] == '<') {
            return try self.parseSGRMouse(sequence);
        } else {
            // X10 mouse format - simplified for now
            return ParseResult{
                .event = .{ .unknown = sequence },
                .consumed = sequence.len,
            };
        }
    }

    fn parseSGRMouse(_: *InputParser, sequence: []const u8) !ParseResult {
        // Extract parameters from ESC[<cb;cx;cy[Mm] - simplified
        const x = 1; // Simplified
        const y = 1; // Simplified
        const is_release = sequence[sequence.len - 1] == 'm';

        const mouse = Mouse{
            .x = x,
            .y = y,
            .button = .left,
            .mod = .{},
        };

        const event: Event = if (is_release)
            .{ .mouse_release = mouse }
        else
            .{ .mouse_click = mouse };

        return ParseResult{
            .event = event,
            .consumed = sequence.len,
        };
    }

    fn parseSs3Sequence(_: *InputParser, data: []const u8) !?ParseResult {
        if (data.len < 3) return null;

        const key_code: u32 = switch (data[2]) {
            'P' => @intFromEnum(Key.f1),
            'Q' => @intFromEnum(Key.f2),
            'R' => @intFromEnum(Key.f3),
            'S' => @intFromEnum(Key.f4),
            'H' => @intFromEnum(Key.home),
            'F' => @intFromEnum(Key.end),
            'A' => @intFromEnum(Key.up), // Application mode
            'B' => @intFromEnum(Key.down),
            'C' => @intFromEnum(Key.right),
            'D' => @intFromEnum(Key.left),
            else => @intFromEnum(Key.extended),
        };

        const key_event = KeyStruct{
            .code = key_code,
        };

        return ParseResult{
            .event = .{ .key_press = .{ .key = key_event } },
            .consumed = 3,
        };
    }
};

// Tests
test "basic key parsing" {
    const testing = std.testing;

    var parser = InputParser.init(testing.allocator);
    defer parser.deinit();

    const events = try parser.parse("a");
    defer testing.allocator.free(events);

    try testing.expect(events.len == 1);
    try testing.expect(events[0] == .key_press);
    try testing.expectEqualStrings("a", events[0].key_press.key.text);
}

test "escape sequence parsing" {
    const testing = std.testing;

    var parser = InputParser.init(testing.allocator);
    defer parser.deinit();

    const events = try parser.parse("\x1b[A");
    defer testing.allocator.free(events);

    try testing.expect(events.len == 1);
    try testing.expect(events[0] == .key_press);
    try testing.expectEqual(@as(u32, @intFromEnum(Key.up)), events[0].key_press.key.code);
}

test "modifier key parsing" {
    const testing = std.testing;

    var parser = InputParser.init(testing.allocator);
    defer parser.deinit();

    const events = try parser.parse("\x1ba"); // Alt+a
    defer testing.allocator.free(events);

    try testing.expect(events.len == 1);
    try testing.expect(events[0] == .key_press);
    try testing.expect(events[0].key_press.key.mod.alt);
}

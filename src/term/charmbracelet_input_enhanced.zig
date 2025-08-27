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

    // Keypad keys
    keypad_enter,
    keypad_equal,
    keypad_multiply,
    keypad_plus,
    keypad_comma,
    keypad_minus,
    keypad_decimal,
    keypad_divide,
    keypad_0,
    keypad_1,
    keypad_2,
    keypad_3,
    keypad_4,
    keypad_5,
    keypad_6,
    keypad_7,
    keypad_8,
    keypad_9,

    // Keypad extensions (Kitty protocol)
    keypad_sep,
    keypad_up,
    keypad_down,
    keypad_left,
    keypad_right,
    keypad_page_up,
    keypad_page_down,
    keypad_home,
    keypad_end,
    keypad_insert,
    keypad_delete,
    keypad_begin,

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
    f21,
    f22,
    f23,
    f24,
    f25,
    f26,
    f27,
    f28,
    f29,
    f30,
    f31,
    f32,
    f33,
    f34,
    f35,
    f36,
    f37,
    f38,
    f39,
    f40,
    f41,
    f42,
    f43,
    f44,
    f45,
    f46,
    f47,
    f48,
    f49,
    f50,
    f51,
    f52,
    f53,
    f54,
    f55,
    f56,
    f57,
    f58,
    f59,
    f60,
    f61,
    f62,
    f63,

    // Kitty keyboard protocol special keys
    caps_lock,
    scroll_lock,
    num_lock,
    print_screen,
    pause,
    menu,

    // Media keys
    media_play,
    media_pause,
    media_play_pause,
    media_reverse,
    media_stop,
    media_fast_forward,
    media_rewind,
    media_next,
    media_prev,
    media_record,

    // Volume keys
    lower_vol,
    raise_vol,
    mute,

    // Modifier keys
    left_shift,
    left_alt,
    left_ctrl,
    left_super,
    left_hyper,
    left_meta,
    right_shift,
    right_alt,
    right_ctrl,
    right_super,
    right_hyper,
    right_meta,
    iso_level3_shift,
    iso_level5_shift,

    // Special names for common keys
    backspace = 0x7F,
    tab = 0x09,
    enter = 0x0D,
    return_ = 0x0D, // Same as enter
    escape = 0x1B,
    esc = 0x1B, // Same as escape
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

/// Key release event
pub const KeyReleaseEvent = struct {
    key: KeyStruct,

    pub fn toString(self: KeyReleaseEvent) []const u8 {
        return self.key.toString();
    }

    pub fn keystroke(self: KeyReleaseEvent) []const u8 {
        return self.key.keystroke();
    }

    pub fn getKey(self: KeyReleaseEvent) KeyStruct {
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

    pub fn format(self: Mouse, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (self.mod.ctrl) try writer.print("ctrl+", .{});
        if (self.mod.alt) try writer.print("alt+", .{});
        if (self.mod.shift) try writer.print("shift+", .{});
        if (self.mod.meta) try writer.print("meta+", .{});
        if (self.mod.hyper) try writer.print("hyper+", .{});
        if (self.mod.super) try writer.print("super+", .{});

        try writer.print("{}", .{self.button});
    }
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

/// Paste events
pub const PasteStartEvent = struct {};
pub const PasteEndEvent = struct {};

/// Generic event type
pub const Event = union(enum) {
    key_press: KeyPressEvent,
    key_release: KeyReleaseEvent,
    mouse_click: MouseClickEvent,
    mouse_release: MouseReleaseEvent,
    mouse_wheel: MouseWheelEvent,
    mouse_motion: MouseMotionEvent,
    focus: FocusEvent,
    paste_start: PasteStartEvent,
    paste_end: PasteEndEvent,
    unknown: []const u8,
};

/// Input parser for terminal escape sequences
pub const InputParser = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) InputParser {
        return InputParser{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *InputParser) void {
        self.buffer.deinit();
    }

    /// Parse input data and return events
    pub fn parse(self: *InputParser, data: []const u8) ![]Event {
        try self.buffer.appendSlice(data);

        var events = std.ArrayList(Event).init(self.allocator);
        errdefer events.deinit();

        var pos: usize = 0;
        while (pos < self.buffer.items.len) {
            if (try self.tryParseEvent(self.buffer.items[pos..])) |result| {
                try events.append(result.event);
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

        return try events.toOwnedSlice();
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
            ']' => try self.parseOscSequence(data),
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
            // X10 mouse format
            return try self.parseX10Mouse(sequence);
        }
    }

    fn parseSGRMouse(_: *InputParser, sequence: []const u8) !ParseResult {
        // Extract parameters from ESC[<cb;cx;cy[Mm]
        const param_str = sequence[3 .. sequence.len - 1];
        var params = std.ArrayList(u32).init(std.heap.page_allocator);
        defer params.deinit();

        var iter = std.mem.split(u8, param_str, ";");
        while (iter.next()) |param| {
            const val = std.fmt.parseInt(u32, param, 10) catch 0;
            try params.append(val);
        }

        if (params.items.len < 3) {
            return ParseResult{
                .event = .{ .unknown = sequence },
                .consumed = sequence.len,
            };
        }

        const cb = params.items[0];
        const x = @as(i32, @intCast(params.items[1])) - 1; // Convert to 0-based
        const y = @as(i32, @intCast(params.items[2])) - 1;
        const is_release = sequence[sequence.len - 1] == 'm';

        const button_info = parseMouseButton(cb);
        const mouse = Mouse{
            .x = x,
            .y = y,
            .button = button_info.button,
            .mod = button_info.mod,
        };

        const event: Event = if (isWheel(button_info.button))
            .{ .mouse_wheel = mouse }
        else if (is_release)
            .{ .mouse_release = mouse }
        else
            .{ .mouse_click = mouse };

        return ParseResult{
            .event = event,
            .consumed = sequence.len,
        };
    }

    fn parseX10Mouse(_: *InputParser, sequence: []const u8) !ParseResult {
        // Basic X10 mouse parsing - simplified
        return ParseResult{
            .event = .{ .unknown = sequence },
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

    fn parseOscSequence(_: *InputParser, data: []const u8) !?ParseResult {
        // OSC sequences are complex - for now just consume
        return ParseResult{
            .event = .{ .unknown = data[0..@min(data.len, 10)] },
            .consumed = @min(data.len, 10),
        };
    }
};

/// Parse mouse button encoding
fn parseMouseButton(b: u32) struct { button: MouseButton, mod: KeyMod } {
    const bit_shift = 0b0000_0100;
    const bit_alt = 0b0000_1000;
    const bit_ctrl = 0b0001_0000;
    const bit_wheel = 0b0100_0000;
    const bit_add = 0b1000_0000;
    const bits_mask = 0b0000_0011;

    var mod = KeyMod{};
    if ((b & bit_alt) != 0) mod.alt = true;
    if ((b & bit_ctrl) != 0) mod.ctrl = true;
    if ((b & bit_shift) != 0) mod.shift = true;

    const button: MouseButton = if ((b & bit_add) != 0)
        @as(MouseButton, @enumFromInt(@as(u8, @intCast(@intFromEnum(MouseButton.backward) + (b & bits_mask)))))
    else if ((b & bit_wheel) != 0)
        @as(MouseButton, @enumFromInt(@as(u8, @intCast(@intFromEnum(MouseButton.wheel_up) + (b & bits_mask)))))
    else
        @as(MouseButton, @enumFromInt(@as(u8, @intCast(@intFromEnum(MouseButton.left) + (b & bits_mask)))));

    return .{ .button = button, .mod = mod };
}

/// Check if button is a wheel event
fn isWheel(btn: MouseButton) bool {
    return @intFromEnum(btn) >= @intFromEnum(MouseButton.wheel_up) and
        @intFromEnum(btn) <= @intFromEnum(MouseButton.wheel_right);
}

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

test "mouse event parsing" {
    const testing = std.testing;

    var parser = InputParser.init(testing.allocator);
    defer parser.deinit();

    const events = try parser.parse("\x1b[<0;5;10M");
    defer testing.allocator.free(events);

    try testing.expect(events.len == 1);
    try testing.expect(events[0] == .mouse_click);
    try testing.expectEqual(@as(i32, 4), events[0].mouse_click.x);
    try testing.expectEqual(@as(i32, 9), events[0].mouse_click.y);
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

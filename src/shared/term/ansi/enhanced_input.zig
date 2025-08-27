const std = @import("std");

// Advanced Input handling system with modern terminal features
// Supports extended keys, modifiers, proper event types, and modern keyboard protocols

/// Extended key constants for special keys beyond basic characters
pub const KeyExtended: u21 = std.unicode.max_codepoint + 1;

/// Special keys enumeration
pub const KeyCode = enum(u21) {
    // Navigation keys
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
    kp_enter,
    kp_equal,
    kp_multiply,
    kp_plus,
    kp_comma,
    kp_minus,
    kp_decimal,
    kp_divide,
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

    // Kitty keyboard protocol extensions
    kp_sep,
    kp_up,
    kp_down,
    kp_left,
    kp_right,
    kp_page_up,
    kp_page_down,
    kp_home,
    kp_end,
    kp_insert,
    kp_delete,
    kp_begin,

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

    // System keys
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
    volume_down,
    volume_up,
    mute,

    // Modifier keys (when pressed individually)
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

    // Common ASCII keys with special names
    backspace = 0x7F,
    tab = 0x09,
    enter = 0x0D,
    escape = 0x1B,
    space = 0x20,

    // Aliases - can't use 'return' as it's a keyword
    ret = 0x0D, // Same value as enter
    esc = 0x1B, // Same value as escape

    pub fn toString(self: KeyCode) []const u8 {
        return switch (self) {
            .up => "up",
            .down => "down",
            .left => "left",
            .right => "right",
            .begin => "begin",
            .find => "find",
            .insert => "insert",
            .delete => "delete",
            .select => "select",
            .page_up => "pgup",
            .page_down => "pgdown",
            .home => "home",
            .end => "end",
            .kp_enter => "kpenter",
            .kp_equal => "kpequal",
            .kp_multiply => "kpmul",
            .kp_plus => "kpplus",
            .kp_comma => "kpcomma",
            .kp_minus => "kpminus",
            .kp_decimal => "kpperiod",
            .kp_divide => "kpdiv",
            .kp_0 => "kp0",
            .kp_1 => "kp1",
            .kp_2 => "kp2",
            .kp_3 => "kp3",
            .kp_4 => "kp4",
            .kp_5 => "kp5",
            .kp_6 => "kp6",
            .kp_7 => "kp7",
            .kp_8 => "kp8",
            .kp_9 => "kp9",
            .kp_sep => "kpsep",
            .kp_up => "kpup",
            .kp_down => "kpdown",
            .kp_left => "kpleft",
            .kp_right => "kpright",
            .kp_page_up => "kppgup",
            .kp_page_down => "kppgdown",
            .kp_home => "kphome",
            .kp_end => "kpend",
            .kp_insert => "kpinsert",
            .kp_delete => "kpdelete",
            .kp_begin => "kpbegin",
            .f1 => "f1",
            .f2 => "f2",
            .f3 => "f3",
            .f4 => "f4",
            .f5 => "f5",
            .f6 => "f6",
            .f7 => "f7",
            .f8 => "f8",
            .f9 => "f9",
            .f10 => "f10",
            .f11 => "f11",
            .f12 => "f12",
            .f13 => "f13",
            .f14 => "f14",
            .f15 => "f15",
            .f16 => "f16",
            .f17 => "f17",
            .f18 => "f18",
            .f19 => "f19",
            .f20 => "f20",
            .f21 => "f21",
            .f22 => "f22",
            .f23 => "f23",
            .f24 => "f24",
            .f25 => "f25",
            .f26 => "f26",
            .f27 => "f27",
            .f28 => "f28",
            .f29 => "f29",
            .f30 => "f30",
            .f31 => "f31",
            .f32 => "f32",
            .f33 => "f33",
            .f34 => "f34",
            .f35 => "f35",
            .f36 => "f36",
            .f37 => "f37",
            .f38 => "f38",
            .f39 => "f39",
            .f40 => "f40",
            .f41 => "f41",
            .f42 => "f42",
            .f43 => "f43",
            .f44 => "f44",
            .f45 => "f45",
            .f46 => "f46",
            .f47 => "f47",
            .f48 => "f48",
            .f49 => "f49",
            .f50 => "f50",
            .f51 => "f51",
            .f52 => "f52",
            .f53 => "f53",
            .f54 => "f54",
            .f55 => "f55",
            .f56 => "f56",
            .f57 => "f57",
            .f58 => "f58",
            .f59 => "f59",
            .f60 => "f60",
            .f61 => "f61",
            .f62 => "f62",
            .f63 => "f63",
            .caps_lock => "capslock",
            .scroll_lock => "scrolllock",
            .num_lock => "numlock",
            .print_screen => "printscreen",
            .pause => "pause",
            .menu => "menu",
            .media_play => "mediaplay",
            .media_pause => "mediapause",
            .media_play_pause => "mediaplaypause",
            .media_reverse => "mediareverse",
            .media_stop => "mediastop",
            .media_fast_forward => "mediafastforward",
            .media_rewind => "mediarewind",
            .media_next => "medianext",
            .media_prev => "mediaprev",
            .media_record => "mediarecord",
            .volume_down => "volumedown",
            .volume_up => "volumeup",
            .mute => "mute",
            .left_shift => "leftshift",
            .left_alt => "leftalt",
            .left_ctrl => "leftctrl",
            .left_super => "leftsuper",
            .left_hyper => "lefthyper",
            .left_meta => "leftmeta",
            .right_shift => "rightshift",
            .right_alt => "rightalt",
            .right_ctrl => "rightctrl",
            .right_super => "rightsuper",
            .right_hyper => "righthyper",
            .right_meta => "rightmeta",
            .iso_level3_shift => "isolevel3shift",
            .iso_level5_shift => "isolevel5shift",
            .enter => "enter",
            .tab => "tab",
            .backspace => "backspace",
            .escape => "esc",
            .space => "space",
            .ret => "enter",
            .esc => "esc",
        };
    }
};

/// Modifier key flags
pub const KeyMod = packed struct {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
    meta: bool = false,
    hyper: bool = false,
    super: bool = false,

    pub fn isEmpty(self: KeyMod) bool {
        const val: u8 = @bitCast(self);
        return val == 0;
    }

    pub fn contains(self: KeyMod, mod: KeyMod) bool {
        const self_val: u8 = @bitCast(self);
        const mod_val: u8 = @bitCast(mod);
        return (self_val & mod_val) == mod_val;
    }

    pub fn toString(self: KeyMod, allocator: std.mem.Allocator) ![]u8 {
        var parts = std.ArrayList([]const u8).init(allocator);
        defer parts.deinit();

        // Order is important for consistency
        if (self.ctrl) try parts.append("ctrl");
        if (self.alt) try parts.append("alt");
        if (self.shift) try parts.append("shift");
        if (self.meta) try parts.append("meta");
        if (self.hyper) try parts.append("hyper");
        if (self.super) try parts.append("super");

        return try std.mem.join(allocator, "+", parts.items);
    }
};

/// Enhanced key representation with extended information
pub const Key = struct {
    /// Text content for printable characters
    text: []const u8 = "",
    /// Modifier keys pressed
    mod: KeyMod = .{},
    /// Key code (special key or character)
    code: u21,
    /// Shifted code for enhanced keyboard protocols
    shifted_code: u21 = 0,
    /// Base code for international keyboards (US layout equivalent)
    base_code: u21 = 0,
    /// Whether this is a key repeat event
    is_repeat: bool = false,

    pub fn isExtended(self: Key) bool {
        return self.code >= KeyExtended;
    }

    pub fn isSpecial(self: Key) bool {
        return self.isExtended() or
            self.code == @intFromEnum(KeyCode.backspace) or
            self.code == @intFromEnum(KeyCode.tab) or
            self.code == @intFromEnum(KeyCode.enter) or
            self.code == @intFromEnum(KeyCode.escape);
    }

    pub fn isPrintable(self: Key) bool {
        return self.text.len > 0 and !self.isSpecial();
    }

    /// Get string representation (text if printable, otherwise keystroke)
    pub fn toString(self: Key, allocator: std.mem.Allocator) ![]u8 {
        if (self.text.len > 0 and !self.isSpecial()) {
            return try allocator.dupe(u8, self.text);
        }
        return self.keystroke(allocator);
    }

    /// Get keystroke representation (modifiers + key name)
    pub fn keystroke(self: Key, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        // Add modifiers (excluding self-modifiers)
        if (self.mod.ctrl and !self.isModifierKey(.ctrl)) {
            try result.appendSlice("ctrl+");
        }
        if (self.mod.alt and !self.isModifierKey(.alt)) {
            try result.appendSlice("alt+");
        }
        if (self.mod.shift and !self.isModifierKey(.shift)) {
            try result.appendSlice("shift+");
        }
        if (self.mod.meta and !self.isModifierKey(.meta)) {
            try result.appendSlice("meta+");
        }
        if (self.mod.hyper and !self.isModifierKey(.hyper)) {
            try result.appendSlice("hyper+");
        }
        if (self.mod.super and !self.isModifierKey(.super)) {
            try result.appendSlice("super+");
        }

        // Add key name
        if (self.isExtended()) {
            const key_code = @as(KeyCode, @enumFromInt(self.code));
            try result.appendSlice(key_code.toString());
        } else {
            const code = if (self.base_code != 0) self.base_code else self.code;
            switch (code) {
                @intFromEnum(KeyCode.space) => try result.appendSlice("space"),
                @intFromEnum(KeyCode.backspace) => try result.appendSlice("backspace"),
                @intFromEnum(KeyCode.tab) => try result.appendSlice("tab"),
                @intFromEnum(KeyCode.enter) => try result.appendSlice("enter"),
                @intFromEnum(KeyCode.escape) => try result.appendSlice("esc"),
                else => {
                    if (self.code == KeyExtended) {
                        // Extended with multiple runes
                        try result.appendSlice(self.text);
                    } else {
                        // Single character
                        var utf8_buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(code, &utf8_buf) catch {
                            try result.appendSlice("<invalid>");
                            return result.toOwnedSlice();
                        };
                        try result.appendSlice(utf8_buf[0..len]);
                    }
                },
            }
        }

        return try result.toOwnedSlice();
    }

    fn isModifierKey(self: Key, mod_type: enum { ctrl, alt, shift, meta, hyper, super }) bool {
        return switch (mod_type) {
            .ctrl => self.code == @intFromEnum(KeyCode.left_ctrl) or self.code == @intFromEnum(KeyCode.right_ctrl),
            .alt => self.code == @intFromEnum(KeyCode.left_alt) or self.code == @intFromEnum(KeyCode.right_alt),
            .shift => self.code == @intFromEnum(KeyCode.left_shift) or self.code == @intFromEnum(KeyCode.right_shift),
            .meta => self.code == @intFromEnum(KeyCode.left_meta) or self.code == @intFromEnum(KeyCode.right_meta),
            .hyper => self.code == @intFromEnum(KeyCode.left_hyper) or self.code == @intFromEnum(KeyCode.right_hyper),
            .super => self.code == @intFromEnum(KeyCode.left_super) or self.code == @intFromEnum(KeyCode.right_super),
        };
    }
};

/// Key event types
pub const KeyPressEvent = struct {
    key: Key,

    pub fn toString(self: KeyPressEvent, allocator: std.mem.Allocator) ![]u8 {
        return self.key.toString(allocator);
    }

    pub fn keystroke(self: KeyPressEvent, allocator: std.mem.Allocator) ![]u8 {
        return self.key.keystroke(allocator);
    }
};

pub const KeyReleaseEvent = struct {
    key: Key,

    pub fn toString(self: KeyReleaseEvent, allocator: std.mem.Allocator) ![]u8 {
        return self.key.toString(allocator);
    }

    pub fn keystroke(self: KeyReleaseEvent, allocator: std.mem.Allocator) ![]u8 {
        return self.key.keystroke(allocator);
    }
};

/// Generic key event interface
pub const KeyEvent = union(enum) {
    press: KeyPressEvent,
    release: KeyReleaseEvent,

    pub fn key(self: KeyEvent) Key {
        return switch (self) {
            .press => |e| e.key,
            .release => |e| e.key,
        };
    }

    pub fn toString(self: KeyEvent, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .press => |e| e.toString(allocator),
            .release => |e| e.toString(allocator),
        };
    }

    pub fn keystroke(self: KeyEvent, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .press => |e| e.keystroke(allocator),
            .release => |e| e.keystroke(allocator),
        };
    }

    pub fn isPress(self: KeyEvent) bool {
        return switch (self) {
            .press => true,
            .release => false,
        };
    }

    pub fn isRelease(self: KeyEvent) bool {
        return switch (self) {
            .press => false,
            .release => true,
        };
    }
};

/// Convenience constructors
pub fn simpleKey(code: u21) Key {
    return Key{ .code = code };
}

pub fn keyWithMod(code: u21, mod: KeyMod) Key {
    return Key{ .code = code, .mod = mod };
}

pub fn textKey(text: []const u8) Key {
    const code = if (text.len == 1) @as(u21, text[0]) else KeyExtended;
    return Key{ .text = text, .code = code };
}

pub fn specialKey(key_code: KeyCode) Key {
    return Key{ .code = @intFromEnum(key_code) };
}

pub fn specialKeyWithMod(key_code: KeyCode, mod: KeyMod) Key {
    return Key{ .code = @intFromEnum(key_code), .mod = mod };
}

/// Create key press event
pub fn keyPress(key: Key) KeyEvent {
    return KeyEvent{ .press = KeyPressEvent{ .key = key } };
}

/// Create key release event
pub fn keyRelease(key: Key) KeyEvent {
    return KeyEvent{ .release = KeyReleaseEvent{ .key = key } };
}

/// Common modifier combinations
pub const ctrl = KeyMod{ .ctrl = true };
pub const alt = KeyMod{ .alt = true };
pub const shift = KeyMod{ .shift = true };
pub const ctrl_shift = KeyMod{ .ctrl = true, .shift = true };
pub const alt_shift = KeyMod{ .alt = true, .shift = true };
pub const ctrl_alt = KeyMod{ .ctrl = true, .alt = true };
pub const ctrl_alt_shift = KeyMod{ .ctrl = true, .alt = true, .shift = true };

/// Mouse events (for completeness)
pub const MouseButton = enum {
    left,
    right,
    middle,
    back,
    forward,
};

pub const MouseEvent = union(enum) {
    press: struct {
        button: MouseButton,
        x: u16,
        y: u16,
        mod: KeyMod = .{},
    },
    release: struct {
        button: MouseButton,
        x: u16,
        y: u16,
        mod: KeyMod = .{},
    },
    move: struct {
        x: u16,
        y: u16,
        mod: KeyMod = .{},
    },
    scroll: struct {
        delta_x: i16,
        delta_y: i16,
        x: u16,
        y: u16,
        mod: KeyMod = .{},
    },
};

/// Combined input event
pub const InputEvent = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,

    pub fn toString(self: InputEvent, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .key => |e| e.toString(allocator),
            .mouse => try allocator.dupe(u8, "<mouse>"),
        };
    }
};

// Parser state for ANSI sequence parsing
pub const ParserState = enum {
    normal,
    escape,
    csi,
    osc,
    dcs,
};

/// ANSI escape sequence parser for terminal input
pub const InputParser = struct {
    state: ParserState = .normal,
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) InputParser {
        return InputParser{
            .buffer = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *InputParser) void {
        self.buffer.deinit();
    }

    pub fn reset(self: *InputParser) void {
        self.state = .normal;
        self.buffer.clearRetainingCapacity();
    }

    /// Parse input bytes and return any complete events
    pub fn parse(self: *InputParser, input: []const u8) !std.ArrayList(InputEvent) {
        var events = std.ArrayList(InputEvent).init(self.allocator);

        for (input) |byte| {
            if (try self.parseByte(byte)) |event| {
                try events.append(event);
            }
        }

        return events;
    }

    /// Parse single byte, returning event if complete sequence found
    fn parseByte(self: *InputParser, byte: u8) !?InputEvent {
        switch (self.state) {
            .normal => {
                if (byte == 0x1B) { // ESC
                    self.state = .escape;
                    try self.buffer.append(byte);
                    return null;
                } else {
                    // Regular character
                    return self.parseRegularChar(byte);
                }
            },
            .escape => {
                try self.buffer.append(byte);

                if (byte == '[') {
                    self.state = .csi;
                    return null;
                } else if (byte == ']') {
                    self.state = .osc;
                    return null;
                } else {
                    // Alt + key combination
                    const event = self.parseAltSequence();
                    self.reset();
                    return event;
                }
            },
            .csi => {
                try self.buffer.append(byte);

                // Check for CSI sequence terminator
                if (byte >= 0x40 and byte <= 0x7E) {
                    const event = try self.parseCsiSequence();
                    self.reset();
                    return event;
                }
                return null;
            },
            .osc => {
                try self.buffer.append(byte);

                // OSC sequences end with BEL (0x07) or ESC \ (0x1B 0x5C)
                if (byte == 0x07) {
                    self.reset(); // Ignore OSC sequences for now
                    return null;
                } else if (self.buffer.items.len >= 2 and
                    self.buffer.items[self.buffer.items.len - 2] == 0x1B and
                    byte == 0x5C)
                {
                    self.reset(); // Ignore OSC sequences for now
                    return null;
                }
                return null;
            },
            .dcs => {
                // DCS sequences - not implemented yet
                try self.buffer.append(byte);
                if (byte == 0x9C) { // ST (String Terminator)
                    self.reset();
                }
                return null;
            },
        }
    }

    fn parseRegularChar(self: *InputParser, byte: u8) InputEvent {
        _ = self; // Parser not needed for regular chars

        const key = switch (byte) {
            0x09 => specialKey(.tab),
            0x0D => specialKey(.enter),
            0x1B => specialKey(.escape),
            0x7F => specialKey(.backspace),
            0x20 => specialKey(.space),
            else => simpleKey(@as(u21, byte)),
        };

        return keyPress(key);
    }

    fn parseAltSequence(self: *InputParser) InputEvent {
        if (self.buffer.items.len >= 2) {
            const char_byte = self.buffer.items[1];
            var key = simpleKey(@as(u21, char_byte));
            key.mod.alt = true;
            return keyPress(key);
        }

        // Fallback - just ESC
        return keyPress(specialKey(.escape));
    }

    fn parseCsiSequence(self: *InputParser) !InputEvent {
        const seq = self.buffer.items;
        if (seq.len < 3) return keyPress(specialKey(.escape));

        // Simple parsing for common sequences
        // Real implementation would need comprehensive ANSI parsing

        if (std.mem.eql(u8, seq, "\x1B[A")) return keyPress(specialKey(.up));
        if (std.mem.eql(u8, seq, "\x1B[B")) return keyPress(specialKey(.down));
        if (std.mem.eql(u8, seq, "\x1B[C")) return keyPress(specialKey(.right));
        if (std.mem.eql(u8, seq, "\x1B[D")) return keyPress(specialKey(.left));
        if (std.mem.eql(u8, seq, "\x1B[H")) return keyPress(specialKey(.home));
        if (std.mem.eql(u8, seq, "\x1B[F")) return keyPress(specialKey(.end));

        // Function keys
        if (std.mem.eql(u8, seq, "\x1BOP")) return keyPress(specialKey(.f1));
        if (std.mem.eql(u8, seq, "\x1BOQ")) return keyPress(specialKey(.f2));
        if (std.mem.eql(u8, seq, "\x1BOR")) return keyPress(specialKey(.f3));
        if (std.mem.eql(u8, seq, "\x1BOS")) return keyPress(specialKey(.f4));

        if (std.mem.startsWith(u8, seq, "\x1B[") and std.mem.endsWith(u8, seq, "~")) {
            const middle = seq[2 .. seq.len - 1];
            if (std.mem.eql(u8, middle, "2")) return keyPress(specialKey(.insert));
            if (std.mem.eql(u8, middle, "3")) return keyPress(specialKey(.delete));
            if (std.mem.eql(u8, middle, "5")) return keyPress(specialKey(.page_up));
            if (std.mem.eql(u8, middle, "6")) return keyPress(specialKey(.page_down));
        }

        // Default fallback
        return keyPress(specialKey(.escape));
    }
};

// Tests
test "key representation and modifiers" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test basic key
    const key_a = simpleKey('a');
    try testing.expect(key_a.code == 'a');
    try testing.expect(!key_a.isSpecial());

    // Test key with modifiers
    const ctrl_c = keyWithMod('c', ctrl);
    try testing.expect(ctrl_c.code == 'c');
    try testing.expect(ctrl_c.mod.ctrl);

    // Test keystroke representation
    const keystroke = try ctrl_c.keystroke(allocator);
    defer allocator.free(keystroke);
    try testing.expect(std.mem.eql(u8, keystroke, "ctrl+c"));
}

test "special keys" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const enter_key = specialKey(.enter);
    try testing.expect(enter_key.code == @intFromEnum(KeyCode.enter));
    try testing.expect(enter_key.isSpecial());

    const keystroke = try enter_key.keystroke(allocator);
    defer allocator.free(keystroke);
    try testing.expect(std.mem.eql(u8, keystroke, "enter"));
}

test "key events" {
    const testing = std.testing;

    const key = simpleKey('x');
    const press_event = keyPress(key);
    const release_event = keyRelease(key);

    try testing.expect(press_event.isPress());
    try testing.expect(!press_event.isRelease());
    try testing.expect(release_event.isRelease());
    try testing.expect(!release_event.isPress());
}

test "input parser basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var parser = InputParser.init(allocator);
    defer parser.deinit();

    // Test normal character
    var events = try parser.parse("a");
    defer events.deinit();

    try testing.expect(events.items.len == 1);
    try testing.expect(events.items[0].key.key().code == 'a');

    // Test escape sequence
    parser.reset();
    events = try parser.parse("\x1B[A");
    defer events.deinit();

    try testing.expect(events.items.len == 1);
    try testing.expect(events.items[0].key.key().code == @intFromEnum(KeyCode.up));
}

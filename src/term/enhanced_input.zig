const std = @import("std");

/// Enhanced input system based on charmbracelet/x/input with Zig 0.15.1 compatibility
/// Supports comprehensive key events, mouse events, and modern terminal features
/// Key modifier flags
pub const KeyMod = packed struct {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
    meta: bool = false,
    hyper: bool = false,
    super: bool = false,

    pub fn isEmpty(self: KeyMod) bool {
        const as_int: u8 = @bitCast(self);
        return as_int == 0;
    }

    pub fn contains(self: KeyMod, other: KeyMod) bool {
        const self_int: u8 = @bitCast(self);
        const other_int: u8 = @bitCast(other);
        return (self_int & other_int) == other_int;
    }

    pub fn toString(self: KeyMod, allocator: std.mem.Allocator) ![]u8 {
        var parts = std.ArrayList([]const u8).init(allocator);
        defer parts.deinit();

        if (self.ctrl) try parts.append("ctrl");
        if (self.alt) try parts.append("alt");
        if (self.shift) try parts.append("shift");
        if (self.meta) try parts.append("meta");
        if (self.hyper) try parts.append("hyper");
        if (self.super) try parts.append("super");

        if (parts.items.len == 0) return allocator.dupe(u8, "");

        return std.mem.join(allocator, "+", parts.items);
    }
};

/// Extended key codes beyond normal unicode range
pub const ExtendedKeyCodes = struct {
    pub const KEY_EXTENDED: u21 = std.unicode.max_codepoint + 1;

    // Navigation keys
    pub const UP = KEY_EXTENDED + 1;
    pub const DOWN = KEY_EXTENDED + 2;
    pub const RIGHT = KEY_EXTENDED + 3;
    pub const LEFT = KEY_EXTENDED + 4;
    pub const BEGIN = KEY_EXTENDED + 5;
    pub const FIND = KEY_EXTENDED + 6;
    pub const INSERT = KEY_EXTENDED + 7;
    pub const DELETE = KEY_EXTENDED + 8;
    pub const SELECT = KEY_EXTENDED + 9;
    pub const PAGE_UP = KEY_EXTENDED + 10;
    pub const PAGE_DOWN = KEY_EXTENDED + 11;
    pub const HOME = KEY_EXTENDED + 12;
    pub const END = KEY_EXTENDED + 13;

    // Keypad keys
    pub const KP_ENTER = KEY_EXTENDED + 20;
    pub const KP_EQUAL = KEY_EXTENDED + 21;
    pub const KP_MULTIPLY = KEY_EXTENDED + 22;
    pub const KP_PLUS = KEY_EXTENDED + 23;
    pub const KP_COMMA = KEY_EXTENDED + 24;
    pub const KP_MINUS = KEY_EXTENDED + 25;
    pub const KP_DECIMAL = KEY_EXTENDED + 26;
    pub const KP_DIVIDE = KEY_EXTENDED + 27;
    pub const KP_0 = KEY_EXTENDED + 28;
    pub const KP_1 = KEY_EXTENDED + 29;
    pub const KP_2 = KEY_EXTENDED + 30;
    pub const KP_3 = KEY_EXTENDED + 31;
    pub const KP_4 = KEY_EXTENDED + 32;
    pub const KP_5 = KEY_EXTENDED + 33;
    pub const KP_6 = KEY_EXTENDED + 34;
    pub const KP_7 = KEY_EXTENDED + 35;
    pub const KP_8 = KEY_EXTENDED + 36;
    pub const KP_9 = KEY_EXTENDED + 37;

    // Function keys F1-F63
    pub const F1 = KEY_EXTENDED + 100;
    pub const F2 = KEY_EXTENDED + 101;
    pub const F3 = KEY_EXTENDED + 102;
    pub const F4 = KEY_EXTENDED + 103;
    pub const F5 = KEY_EXTENDED + 104;
    pub const F6 = KEY_EXTENDED + 105;
    pub const F7 = KEY_EXTENDED + 106;
    pub const F8 = KEY_EXTENDED + 107;
    pub const F9 = KEY_EXTENDED + 108;
    pub const F10 = KEY_EXTENDED + 109;
    pub const F11 = KEY_EXTENDED + 110;
    pub const F12 = KEY_EXTENDED + 111;
    pub const F13 = KEY_EXTENDED + 112;
    pub const F14 = KEY_EXTENDED + 113;
    pub const F15 = KEY_EXTENDED + 114;
    pub const F16 = KEY_EXTENDED + 115;
    pub const F17 = KEY_EXTENDED + 116;
    pub const F18 = KEY_EXTENDED + 117;
    pub const F19 = KEY_EXTENDED + 118;
    pub const F20 = KEY_EXTENDED + 119;
    // ... more function keys available up to F63

    // System keys
    pub const CAPS_LOCK = KEY_EXTENDED + 200;
    pub const SCROLL_LOCK = KEY_EXTENDED + 201;
    pub const NUM_LOCK = KEY_EXTENDED + 202;
    pub const PRINT_SCREEN = KEY_EXTENDED + 203;
    pub const PAUSE = KEY_EXTENDED + 204;
    pub const MENU = KEY_EXTENDED + 205;

    // Media keys
    pub const MEDIA_PLAY = KEY_EXTENDED + 220;
    pub const MEDIA_PAUSE = KEY_EXTENDED + 221;
    pub const MEDIA_STOP = KEY_EXTENDED + 222;
    pub const MEDIA_NEXT = KEY_EXTENDED + 223;
    pub const MEDIA_PREV = KEY_EXTENDED + 224;
    pub const MEDIA_RECORD = KEY_EXTENDED + 225;

    // Audio keys
    pub const VOLUME_UP = KEY_EXTENDED + 240;
    pub const VOLUME_DOWN = KEY_EXTENDED + 241;
    pub const MUTE = KEY_EXTENDED + 242;

    // Individual modifier keys
    pub const LEFT_SHIFT = KEY_EXTENDED + 260;
    pub const RIGHT_SHIFT = KEY_EXTENDED + 261;
    pub const LEFT_CTRL = KEY_EXTENDED + 262;
    pub const RIGHT_CTRL = KEY_EXTENDED + 263;
    pub const LEFT_ALT = KEY_EXTENDED + 264;
    pub const RIGHT_ALT = KEY_EXTENDED + 265;
    pub const LEFT_SUPER = KEY_EXTENDED + 266;
    pub const RIGHT_SUPER = KEY_EXTENDED + 267;

    // Common key names
    pub const BACKSPACE: u21 = 0x7F;
    pub const TAB: u21 = 0x09;
    pub const ENTER: u21 = 0x0D;
    pub const ESCAPE: u21 = 0x1B;
    pub const SPACE: u21 = 0x20;

    /// Get string representation of key code
    pub fn toString(code: u21) []const u8 {
        return switch (code) {
            UP => "up",
            DOWN => "down",
            LEFT => "left",
            RIGHT => "right",
            HOME => "home",
            END => "end",
            PAGE_UP => "pgup",
            PAGE_DOWN => "pgdown",
            INSERT => "insert",
            DELETE => "delete",
            F1 => "f1",
            F2 => "f2",
            F3 => "f3",
            F4 => "f4",
            F5 => "f5",
            F6 => "f6",
            F7 => "f7",
            F8 => "f8",
            F9 => "f9",
            F10 => "f10",
            F11 => "f11",
            F12 => "f12",
            BACKSPACE => "backspace",
            TAB => "tab",
            ENTER => "enter",
            ESCAPE => "esc",
            SPACE => "space",
            CAPS_LOCK => "capslock",
            MEDIA_PLAY => "mediaplay",
            MEDIA_PAUSE => "mediapause",
            VOLUME_UP => "volumeup",
            VOLUME_DOWN => "volumedown",
            MUTE => "mute",
            else => "unknown",
        };
    }
};

/// Mouse button identifiers
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

    pub fn toString(self: MouseButton) []const u8 {
        return switch (self) {
            .none => "none",
            .left => "left",
            .middle => "middle",
            .right => "right",
            .wheel_up => "wheelup",
            .wheel_down => "wheeldown",
            .wheel_left => "wheelleft",
            .wheel_right => "wheelright",
            .backward => "backward",
            .forward => "forward",
            .button10 => "button10",
            .button11 => "button11",
        };
    }

    pub fn isWheel(self: MouseButton) bool {
        return self == .wheel_up or self == .wheel_down or
            self == .wheel_left or self == .wheel_right;
    }
};

/// Core key information
pub const Key = struct {
    /// Printable text representation (empty for special keys)
    text: []const u8 = "",
    /// Modifier keys pressed
    mod: KeyMod = .{},
    /// Key code (unicode or extended)
    code: u21 = 0,
    /// Shifted version of the key (Kitty protocol)
    shifted_code: u21 = 0,
    /// Base layout key code (PC-101 layout)
    base_code: u21 = 0,
    /// Whether this is a repeat event
    is_repeat: bool = false,

    /// Get string representation of the key
    pub fn toString(self: Key, allocator: std.mem.Allocator) ![]u8 {
        // If we have printable text, use that (except for space)
        if (self.text.len > 0 and !std.mem.eql(u8, self.text, " ")) {
            return allocator.dupe(u8, self.text);
        }

        return self.toKeystroke(allocator);
    }

    /// Get keystroke representation with modifiers
    pub fn toKeystroke(self: Key, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        // Add modifiers in order: ctrl, alt, shift, meta, hyper, super
        if (self.mod.ctrl and self.code != ExtendedKeyCodes.LEFT_CTRL and
            self.code != ExtendedKeyCodes.RIGHT_CTRL)
        {
            try result.appendSlice("ctrl+");
        }
        if (self.mod.alt and self.code != ExtendedKeyCodes.LEFT_ALT and
            self.code != ExtendedKeyCodes.RIGHT_ALT)
        {
            try result.appendSlice("alt+");
        }
        if (self.mod.shift and self.code != ExtendedKeyCodes.LEFT_SHIFT and
            self.code != ExtendedKeyCodes.RIGHT_SHIFT)
        {
            try result.appendSlice("shift+");
        }
        if (self.mod.meta) {
            try result.appendSlice("meta+");
        }
        if (self.mod.hyper) {
            try result.appendSlice("hyper+");
        }
        if (self.mod.super and self.code != ExtendedKeyCodes.LEFT_SUPER and
            self.code != ExtendedKeyCodes.RIGHT_SUPER)
        {
            try result.appendSlice("super+");
        }

        // Add the key name
        const key_name = ExtendedKeyCodes.toString(self.code);
        if (!std.mem.eql(u8, key_name, "unknown")) {
            try result.appendSlice(key_name);
        } else {
            // Use base code if available, otherwise use main code
            const display_code = if (self.base_code != 0) self.base_code else self.code;

            switch (display_code) {
                ExtendedKeyCodes.SPACE => try result.appendSlice("space"),
                ExtendedKeyCodes.KEY_EXTENDED => try result.appendSlice(self.text),
                else => {
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(display_code, &buf) catch 1;
                    try result.appendSlice(buf[0..len]);
                },
            }
        }

        return result.toOwnedSlice();
    }
};

/// Mouse event information
pub const Mouse = struct {
    x: i32,
    y: i32,
    button: MouseButton,
    mod: KeyMod = .{},

    pub fn toString(self: Mouse, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        // Add modifiers
        if (self.mod.ctrl) try result.appendSlice("ctrl+");
        if (self.mod.alt) try result.appendSlice("alt+");
        if (self.mod.shift) try result.appendSlice("shift+");

        // Add button name
        const button_name = self.button.toString();
        if (!std.mem.eql(u8, button_name, "none")) {
            try result.appendSlice(button_name);
        }

        return result.toOwnedSlice();
    }
};

/// Different types of input events
pub const InputEvent = union(enum) {
    key_press: Key,
    key_release: Key,
    mouse_click: Mouse,
    mouse_release: Mouse,
    mouse_wheel: Mouse,
    mouse_motion: Mouse,
    focus_in,
    focus_out,
    paste_start,
    paste_end,
    paste_data: []const u8,

    pub fn toString(self: InputEvent, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .key_press => |k| k.toString(allocator),
            .key_release => |k| k.toString(allocator),
            .mouse_click => |m| m.toString(allocator),
            .mouse_release => |m| m.toString(allocator),
            .mouse_wheel => |m| m.toString(allocator),
            .mouse_motion => |m| {
                const base = try m.toString(allocator);
                defer allocator.free(base);
                if (m.button != .none) {
                    return std.fmt.allocPrint(allocator, "{s}+motion", .{base});
                } else {
                    return std.fmt.allocPrint(allocator, "motion", .{});
                }
            },
            .focus_in => allocator.dupe(u8, "focus_in"),
            .focus_out => allocator.dupe(u8, "focus_out"),
            .paste_start => allocator.dupe(u8, "paste_start"),
            .paste_end => allocator.dupe(u8, "paste_end"),
            .paste_data => |data| std.fmt.allocPrint(allocator, "paste:{s}", .{data}),
        };
    }
};

/// Enhanced input parser for modern terminal sequences
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

    /// Parse input bytes into events
    pub fn parse(self: *InputParser, input: []const u8) ![]InputEvent {
        var events = std.ArrayList(InputEvent).init(self.allocator);
        errdefer events.deinit();

        for (input) |byte| {
            try self.buffer.append(byte);

            if (try self.tryParseEvent()) |event| {
                try events.append(event);
                self.buffer.clearAndFree();
            }
        }

        return events.toOwnedSlice();
    }

    fn tryParseEvent(self: *InputParser) !?InputEvent {
        if (self.buffer.items.len == 0) return null;

        // Check for escape sequences
        if (self.buffer.items[0] == 0x1B) {
            return self.parseEscapeSequence();
        }

        // Single character input
        if (self.buffer.items.len == 1) {
            const byte = self.buffer.items[0];
            return self.parseCharacter(byte);
        }

        return null;
    }

    fn parseEscapeSequence(self: *InputParser) !?InputEvent {
        const buf = self.buffer.items;
        if (buf.len < 2) return null; // Need at least ESC + one more char

        // CSI sequences: ESC [ ...
        if (buf[1] == '[') {
            return self.parseCSISequence();
        }

        // Alt + key sequences
        if (buf.len == 2) {
            const key = Key{
                .code = buf[1],
                .mod = .{ .alt = true },
                .text = if (std.ascii.isPrint(buf[1])) buf[1..2] else "",
            };
            return InputEvent{ .key_press = key };
        }

        return null;
    }

    fn parseCSISequence(self: *InputParser) !?InputEvent {
        const buf = self.buffer.items;
        if (buf.len < 3) return null; // Need at least ESC [ + terminator

        // Look for terminator
        var terminator_pos: ?usize = null;
        for (buf[2..], 2..) |byte, i| {
            if (byte >= 0x40 and byte <= 0x7E) { // CSI terminators
                terminator_pos = i;
                break;
            }
        }

        const term_pos = terminator_pos orelse return null;
        const terminator = buf[term_pos];

        // Parse parameters
        const params_str = buf[2..term_pos];
        var params = std.ArrayList(i32).init(self.allocator);
        defer params.deinit();

        var param_iter = std.mem.split(u8, params_str, ";");
        while (param_iter.next()) |param_str| {
            const param = std.fmt.parseInt(i32, param_str, 10) catch 0;
            try params.append(param);
        }

        // Parse based on terminator
        switch (terminator) {
            'A' => return self.createKeyEvent(ExtendedKeyCodes.UP, .{}),
            'B' => return self.createKeyEvent(ExtendedKeyCodes.DOWN, .{}),
            'C' => return self.createKeyEvent(ExtendedKeyCodes.RIGHT, .{}),
            'D' => return self.createKeyEvent(ExtendedKeyCodes.LEFT, .{}),
            'H' => return self.createKeyEvent(ExtendedKeyCodes.HOME, .{}),
            'F' => return self.createKeyEvent(ExtendedKeyCodes.END, .{}),
            'M' => return self.parseX10Mouse(),
            '~' => return self.parseSpecialKey(params.items),
            '<' => {
                // SGR mouse format: ESC [ < param1 ; param2 ; param3 m/M
                return self.parseSgrMouse(params.items, buf[buf.len - 1]);
            },
            else => return null,
        }
    }

    fn parseSpecialKey(_: *InputParser, params: []const i32) !?InputEvent {
        if (params.len == 0) return null;

        const code = switch (params[0]) {
            1 => ExtendedKeyCodes.HOME,
            2 => ExtendedKeyCodes.INSERT,
            3 => ExtendedKeyCodes.DELETE,
            4 => ExtendedKeyCodes.END,
            5 => ExtendedKeyCodes.PAGE_UP,
            6 => ExtendedKeyCodes.PAGE_DOWN,
            11 => ExtendedKeyCodes.F1,
            12 => ExtendedKeyCodes.F2,
            13 => ExtendedKeyCodes.F3,
            14 => ExtendedKeyCodes.F4,
            15 => ExtendedKeyCodes.F5,
            17 => ExtendedKeyCodes.F6,
            18 => ExtendedKeyCodes.F7,
            19 => ExtendedKeyCodes.F8,
            20 => ExtendedKeyCodes.F9,
            21 => ExtendedKeyCodes.F10,
            23 => ExtendedKeyCodes.F11,
            24 => ExtendedKeyCodes.F12,
            else => return null,
        };

        // Parse modifiers from second parameter
        var mod = KeyMod{};
        if (params.len > 1) {
            const mod_param = params[1];
            if (mod_param & 1 != 0) mod.shift = true;
            if (mod_param & 2 != 0) mod.alt = true;
            if (mod_param & 4 != 0) mod.ctrl = true;
        }

        return InputEvent{ .key_press = Key{ .code = code, .mod = mod } };
    }

    fn parseX10Mouse(self: *InputParser) !?InputEvent {
        const buf = self.buffer.items;
        if (buf.len < 6) return null; // ESC [ M + 3 bytes

        const b = buf[3] - 32;
        const x = @as(i32, buf[4]) - 32 - 1; // Convert to 0-based
        const y = @as(i32, buf[5]) - 32 - 1;

        const mod = self.parseMouseMod(b);
        const button = self.parseMouseButton(b);
        const is_motion = (b & 0x20) != 0;
        const is_release = !is_motion and (b & 0x03) == 0x03;

        const mouse = Mouse{
            .x = x,
            .y = y,
            .button = button,
            .mod = mod,
        };

        if (button.isWheel()) {
            return InputEvent{ .mouse_wheel = mouse };
        } else if (is_motion) {
            return InputEvent{ .mouse_motion = mouse };
        } else if (is_release) {
            return InputEvent{ .mouse_release = mouse };
        } else {
            return InputEvent{ .mouse_click = mouse };
        }
    }

    fn parseMouseMod(_: *InputParser, b: u8) KeyMod {
        return KeyMod{
            .shift = (b & 0x04) != 0,
            .alt = (b & 0x08) != 0,
            .ctrl = (b & 0x10) != 0,
        };
    }

    fn parseMouseButton(_: *InputParser, b: u8) MouseButton {
        const btn_bits = b & 0x03;
        const wheel = (b & 0x40) != 0;
        const additional = (b & 0x80) != 0;

        if (additional) {
            return @enumFromInt(@as(u8, @intFromEnum(MouseButton.backward)) + btn_bits);
        } else if (wheel) {
            return @enumFromInt(@as(u8, @intFromEnum(MouseButton.wheel_up)) + btn_bits);
        } else {
            return @enumFromInt(@as(u8, @intFromEnum(MouseButton.left)) + btn_bits);
        }
    }

    /// Parse SGR (Select Graphic Rendition) mouse events
    /// Format: ESC [ < button ; x ; y m/M
    /// 'm' indicates button release, 'M' indicates button press/drag
    fn parseSgrMouse(self: *InputParser, params: []const i32, terminator: u8) !?InputEvent {
        _ = self;
        if (params.len < 3) return null; // Need at least button, x, y

        const button_param = params[0];
        const x = params[1] - 1; // Convert to 0-based coordinates
        const y = params[2] - 1; // Convert to 0-based coordinates

        // Parse button and modifiers from first parameter
        const base_button = button_param & 0x03;
        const is_wheel = (button_param & 0x40) != 0;
        const is_motion = (button_param & 0x20) != 0;
        const is_release = terminator == 'm';

        // Parse modifiers from button parameter
        const mod = KeyMod{
            .shift = (button_param & 0x04) != 0,
            .alt = (button_param & 0x08) != 0,
            .ctrl = (button_param & 0x10) != 0,
        };

        // Determine button type
        var button: MouseButton = undefined;
        if (is_wheel) {
            // Wheel events: 64-67 (up, down, left, right)
            button = switch (button_param) {
                64 => MouseButton.wheel_up,
                65 => MouseButton.wheel_down,
                66 => MouseButton.wheel_left,
                67 => MouseButton.wheel_right,
                else => MouseButton.wheel_up,
            };
        } else if (button_param >= 128) {
            // Additional buttons (8-11)
            button = MouseButton.backward;
        } else {
            // Standard buttons (left, middle, right)
            button = switch (base_button) {
                0 => MouseButton.left,
                1 => MouseButton.middle,
                2 => MouseButton.right,
                else => MouseButton.left,
            };
        }

        const mouse = Mouse{
            .x = x,
            .y = y,
            .button = button,
            .mod = mod,
        };

        // Determine event type based on parameters and terminator
        if (button.isWheel()) {
            return InputEvent{ .mouse_wheel = mouse };
        } else if (is_motion) {
            return InputEvent{ .mouse_motion = mouse };
        } else if (is_release) {
            return InputEvent{ .mouse_release = mouse };
        } else {
            return InputEvent{ .mouse_click = mouse };
        }
    }

    fn parseCharacter(self: *InputParser, byte: u8) !?InputEvent {
        _ = self;
        const key = Key{
            .code = byte,
            .text = if (std.ascii.isPrint(byte)) &[_]u8{byte} else "",
        };
        return InputEvent{ .key_press = key };
    }

    fn createKeyEvent(self: *InputParser, code: u21, mod: KeyMod) !InputEvent {
        _ = self;
        const key = Key{
            .code = code,
            .mod = mod,
        };
        return InputEvent{ .key_press = key };
    }
};

// Helper functions for creating common events

pub fn createKeyPress(code: u21, mod: KeyMod) InputEvent {
    return InputEvent{ .key_press = Key{ .code = code, .mod = mod } };
}

pub fn createMouseClick(x: i32, y: i32, button: MouseButton, mod: KeyMod) InputEvent {
    return InputEvent{ .mouse_click = Mouse{
        .x = x,
        .y = y,
        .button = button,
        .mod = mod,
    } };
}

pub fn createCharPress(char: u8) InputEvent {
    return InputEvent{ .key_press = Key{
        .code = char,
        .text = if (std.ascii.isPrint(char)) &[_]u8{char} else "",
    } };
}

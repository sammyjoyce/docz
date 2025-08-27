const std = @import("std");
const enhanced_keys = @import("enhanced_keys.zig");

/// Enhanced input system with advanced terminal features and Zig 0.15.1 compatibility
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

    /// Convert from enhanced_keys Modifiers to KeyMod
    pub fn fromEnhancedModifiers(mods: enhanced_keys.Modifiers) KeyMod {
        return KeyMod{
            .ctrl = mods.ctrl,
            .alt = mods.alt,
            .shift = mods.shift,
        };
    }

    /// Convert to enhanced_keys Modifiers
    pub fn toEnhancedModifiers(self: KeyMod) enhanced_keys.Modifiers {
        return enhanced_keys.Modifiers{
            .ctrl = self.ctrl,
            .alt = self.alt,
            .shift = self.shift,
        };
    }
};

/// Interface for key mapping functionality
/// Implementations should provide dynamic sequence-to-key mapping
pub const KeyMapping = struct {
    /// Context pointer for the implementation
    ptr: *anyopaque,
    /// Function to map a sequence to an extended key code (u21)
    mapSequenceFn: *const fn (ptr: *anyopaque, sequence: []const u8) ?u21,

    /// Map an escape sequence to an extended key code (u21)
    /// Returns null if the sequence is not recognized
    pub fn mapSequence(self: KeyMapping, sequence: []const u8) ?u21 {
        return self.mapSequenceFn(self.ptr, sequence);
    }
};

/// Translation utilities between extended key codes and enum-based keys
pub const KeyTranslation = struct {
    /// Convert extended key code (u21) to enum-based key
    pub fn extendedToEnum(extended_code: u21) ?enhanced_keys.Key {
        return switch (extended_code) {
            // Navigation keys
            ExtendedKeyCodes.UP => .up,
            ExtendedKeyCodes.DOWN => .down,
            ExtendedKeyCodes.LEFT => .left,
            ExtendedKeyCodes.RIGHT => .right,
            ExtendedKeyCodes.HOME => .home,
            ExtendedKeyCodes.END => .end,
            ExtendedKeyCodes.PAGE_UP => .page_up,
            ExtendedKeyCodes.PAGE_DOWN => .page_down,
            ExtendedKeyCodes.INSERT => .insert,
            ExtendedKeyCodes.DELETE => .delete,

            // Function keys
            ExtendedKeyCodes.F1 => .f1,
            ExtendedKeyCodes.F2 => .f2,
            ExtendedKeyCodes.F3 => .f3,
            ExtendedKeyCodes.F4 => .f4,
            ExtendedKeyCodes.F5 => .f5,
            ExtendedKeyCodes.F6 => .f6,
            ExtendedKeyCodes.F7 => .f7,
            ExtendedKeyCodes.F8 => .f8,
            ExtendedKeyCodes.F9 => .f9,
            ExtendedKeyCodes.F10 => .f10,
            ExtendedKeyCodes.F11 => .f11,
            ExtendedKeyCodes.F12 => .f12,

            // Keypad keys
            ExtendedKeyCodes.KP_0 => .kp_0,
            ExtendedKeyCodes.KP_1 => .kp_1,
            ExtendedKeyCodes.KP_2 => .kp_2,
            ExtendedKeyCodes.KP_3 => .kp_3,
            ExtendedKeyCodes.KP_4 => .kp_4,
            ExtendedKeyCodes.KP_5 => .kp_5,
            ExtendedKeyCodes.KP_6 => .kp_6,
            ExtendedKeyCodes.KP_7 => .kp_7,
            ExtendedKeyCodes.KP_8 => .kp_8,
            ExtendedKeyCodes.KP_9 => .kp_9,
            ExtendedKeyCodes.KP_DECIMAL => .kp_decimal,
            ExtendedKeyCodes.KP_DIVIDE => .kp_divide,
            ExtendedKeyCodes.KP_MULTIPLY => .kp_multiply,
            ExtendedKeyCodes.KP_SUBTRACT => .kp_subtract,
            ExtendedKeyCodes.KP_ADD => .kp_add,
            ExtendedKeyCodes.KP_ENTER => .kp_enter,
            ExtendedKeyCodes.KP_EQUAL => .kp_equal,

            // Common ASCII keys
            ExtendedKeyCodes.BACKSPACE => .backspace,
            ExtendedKeyCodes.TAB => .tab,
            ExtendedKeyCodes.ENTER => .enter,
            ExtendedKeyCodes.ESCAPE => .escape,
            ExtendedKeyCodes.SPACE => .space,

            // Control keys
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
            0x0D => .enter,
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
            0x7F => .delete,

            else => null,
        };
    }

    /// Convert enum-based key to extended key code (u21)
    pub fn enumToExtended(enum_key: enhanced_keys.Key) ?u21 {
        return switch (enum_key) {
            // Navigation keys
            .up => ExtendedKeyCodes.UP,
            .down => ExtendedKeyCodes.DOWN,
            .left => ExtendedKeyCodes.LEFT,
            .right => ExtendedKeyCodes.RIGHT,
            .home => ExtendedKeyCodes.HOME,
            .end => ExtendedKeyCodes.END,
            .page_up => ExtendedKeyCodes.PAGE_UP,
            .page_down => ExtendedKeyCodes.PAGE_DOWN,
            .insert => ExtendedKeyCodes.INSERT,
            .delete => ExtendedKeyCodes.DELETE,

            // Function keys
            .f1 => ExtendedKeyCodes.F1,
            .f2 => ExtendedKeyCodes.F2,
            .f3 => ExtendedKeyCodes.F3,
            .f4 => ExtendedKeyCodes.F4,
            .f5 => ExtendedKeyCodes.F5,
            .f6 => ExtendedKeyCodes.F6,
            .f7 => ExtendedKeyCodes.F7,
            .f8 => ExtendedKeyCodes.F8,
            .f9 => ExtendedKeyCodes.F9,
            .f10 => ExtendedKeyCodes.F10,
            .f11 => ExtendedKeyCodes.F11,
            .f12 => ExtendedKeyCodes.F12,

            // Keypad keys
            .kp_0 => ExtendedKeyCodes.KP_0,
            .kp_1 => ExtendedKeyCodes.KP_1,
            .kp_2 => ExtendedKeyCodes.KP_2,
            .kp_3 => ExtendedKeyCodes.KP_3,
            .kp_4 => ExtendedKeyCodes.KP_4,
            .kp_5 => ExtendedKeyCodes.KP_5,
            .kp_6 => ExtendedKeyCodes.KP_6,
            .kp_7 => ExtendedKeyCodes.KP_7,
            .kp_8 => ExtendedKeyCodes.KP_8,
            .kp_9 => ExtendedKeyCodes.KP_9,
            .kp_decimal => ExtendedKeyCodes.KP_DECIMAL,
            .kp_divide => ExtendedKeyCodes.KP_DIVIDE,
            .kp_multiply => ExtendedKeyCodes.KP_MULTIPLY,
            .kp_subtract => ExtendedKeyCodes.KP_SUBTRACT,
            .kp_add => ExtendedKeyCodes.KP_ADD,
            .kp_enter => ExtendedKeyCodes.KP_ENTER,
            .kp_equal => ExtendedKeyCodes.KP_EQUAL,

            // Common ASCII keys
            .backspace => ExtendedKeyCodes.BACKSPACE,
            .tab => ExtendedKeyCodes.TAB,
            .enter => ExtendedKeyCodes.ENTER,
            .escape => ExtendedKeyCodes.ESCAPE,
            .space => ExtendedKeyCodes.SPACE,

            // Control keys
            .ctrl_a => 0x01,
            .ctrl_b => 0x02,
            .ctrl_c => 0x03,
            .ctrl_d => 0x04,
            .ctrl_e => 0x05,
            .ctrl_f => 0x06,
            .ctrl_g => 0x07,
            .ctrl_k => 0x0B,
            .ctrl_l => 0x0C,
            .ctrl_m => 0x0D,
            .ctrl_n => 0x0E,
            .ctrl_o => 0x0F,
            .ctrl_p => 0x10,
            .ctrl_q => 0x11,
            .ctrl_r => 0x12,
            .ctrl_s => 0x13,
            .ctrl_t => 0x14,
            .ctrl_u => 0x15,
            .ctrl_v => 0x16,
            .ctrl_w => 0x17,
            .ctrl_x => 0x18,
            .ctrl_y => 0x19,
            .ctrl_z => 0x1A,
            .ctrl_backslash => 0x1C,
            .ctrl_close_bracket => 0x1D,
            .ctrl_caret => 0x1E,
            .ctrl_underscore => 0x1F,

            else => null,
        };
    }

    /// Convert KeyMod to enhanced_keys Modifiers
    pub fn keyModToModifiers(key_mod: KeyMod) enhanced_keys.Modifiers {
        return key_mod.toEnhancedModifiers();
    }

    /// Convert enhanced_keys Modifiers to KeyMod
    pub fn modifiersToKeyMod(mods: enhanced_keys.Modifiers) KeyMod {
        return KeyMod.fromEnhancedModifiers(mods);
    }
};

/// Extended key codes beyond normal unicode range
pub const ExtendedKeyCodes = struct {
    pub const KEY_EXTENDED: u21 = 0x10FFFF + 1;

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
    unknown: []const u8,

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
            .unknown => |data| std.fmt.allocPrint(allocator, "unknown:{x}", .{std.fmt.fmtSliceHexLower(data)}),
        };
    }
};

/// Enhanced input parser for modern terminal sequences
pub const InputParser = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),
    /// Optional key mapping for dynamic sequence resolution
    key_mapping: ?KeyMapping = null,

    /// Initialize parser without key mapping (backward compatible)
    pub fn init(allocator: std.mem.Allocator) InputParser {
        return InputParser{
            .allocator = allocator,
            .buffer = std.ArrayListUnmanaged(u8){},
            .key_mapping = null,
        };
    }

    /// Initialize parser with key mapping support
    pub fn initWithMapping(allocator: std.mem.Allocator, key_mapping: KeyMapping) InputParser {
        return InputParser{
            .allocator = allocator,
            .buffer = std.ArrayListUnmanaged(u8){},
            .key_mapping = key_mapping,
        };
    }

    /// Set key mapping for dynamic sequence resolution
    pub fn setKeyMapping(self: *InputParser, key_mapping: KeyMapping) void {
        self.key_mapping = key_mapping;
    }

    /// Clear key mapping (return to hardcoded mappings only)
    pub fn clearKeyMapping(self: *InputParser) void {
        self.key_mapping = null;
    }

    pub fn deinit(self: *InputParser) void {
        self.buffer.deinit(self.allocator);
    }

    /// Parse input bytes into events
    pub fn parse(self: *InputParser, input: []const u8) ![]InputEvent {
        try self.buffer.appendSlice(self.allocator, input);

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

        // Check dynamic mapping first for the full buffer
        if (self.key_mapping) |mapping| {
            if (mapping.mapSequence(data)) |extended_code| {
                return ParseResult{
                    .event = InputEvent{ .key_press = Key{
                        .code = extended_code,
                        .mod = .{}, // Dynamic mapping doesn't specify modifiers
                        .text = if (std.ascii.isPrint(@intCast(extended_code))) &[_]u8{@intCast(extended_code)} else "",
                    }},
                    .consumed = data.len,
                };
            }
        }

        // Check for escape sequences
        if (data[0] == 0x1B) {
            return try self.parseEscapeSequence(data);
        }

        // Single character input
        if (data.len >= 1) {
            const byte = data[0];
            const key_event = try self.parseCharacter(byte);
            return ParseResult{
                .event = key_event,
                .consumed = 1,
            };
        }

        return null;
    }

    fn parseEscapeSequence(self: *InputParser, data: []const u8) !?ParseResult {
        if (data.len < 2) return null; // Need at least ESC + one more char

        // Check dynamic mapping for the full escape sequence
        if (self.key_mapping) |mapping| {
            if (mapping.mapSequence(data)) |extended_code| {
                return ParseResult{
                    .event = InputEvent{ .key_press = Key{
                        .code = extended_code,
                        .mod = .{}, // Dynamic mapping doesn't specify modifiers
                        .text = if (std.ascii.isPrint(@intCast(extended_code))) &[_]u8{@intCast(extended_code)} else "",
                    }},
                    .consumed = data.len,
                };
            }
        }

        // CSI sequences: ESC [ ...
        if (data[1] == '[') {
            return try self.parseCSISequence(data);
        }

        // Alt + key sequences
        if (data.len >= 2) {
            const key = Key{
                .code = data[1],
                .mod = .{ .alt = true },
                .text = if (std.ascii.isPrint(data[1])) data[1..2] else "",
            };
            return ParseResult{
                .event = InputEvent{ .key_press = key },
                .consumed = 2,
            };
        }

        return null;
    }

    fn parseCSISequence(self: *InputParser, data: []const u8) !?ParseResult {
        if (data.len < 3) return null; // Need at least ESC [ + terminator

        // Check dynamic mapping for the full CSI sequence first
        if (self.key_mapping) |mapping| {
            if (mapping.mapSequence(data)) |extended_code| {
                return ParseResult{
                    .event = InputEvent{ .key_press = Key{
                        .code = extended_code,
                        .mod = .{}, // Dynamic mapping doesn't specify modifiers
                        .text = if (std.ascii.isPrint(@intCast(extended_code))) &[_]u8{@intCast(extended_code)} else "",
                    }},
                    .consumed = data.len,
                };
            }
        }

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

        // Parse parameters
        const params_str = data[2..i];
        var params = std.ArrayListUnmanaged(i32){};
        defer params.deinit(self.allocator);

        var param_iter = std.mem.splitScalar(u8, params_str, ';');
        while (param_iter.next()) |param_str| {
            const param = std.fmt.parseInt(i32, param_str, 10) catch 0;
            try params.append(self.allocator, param);
        }

        // Parse based on terminator
        switch (final_char) {
            'A' => return ParseResult{ .event = .{ .key_press = .{ .code = ExtendedKeyCodes.UP, .mod = .{} } }, .consumed = i + 1 },
            'B' => return ParseResult{ .event = .{ .key_press = .{ .code = ExtendedKeyCodes.DOWN, .mod = .{} } }, .consumed = i + 1 },
            'C' => return ParseResult{ .event = .{ .key_press = .{ .code = ExtendedKeyCodes.RIGHT, .mod = .{} } }, .consumed = i + 1 },
            'D' => return ParseResult{ .event = .{ .key_press = .{ .code = ExtendedKeyCodes.LEFT, .mod = .{} } }, .consumed = i + 1 },
            'H' => return ParseResult{ .event = .{ .key_press = .{ .code = ExtendedKeyCodes.HOME, .mod = .{} } }, .consumed = i + 1 },
            'F' => return ParseResult{ .event = .{ .key_press = .{ .code = ExtendedKeyCodes.END, .mod = .{} } }, .consumed = i + 1 },
            'M', 'm' => return try self.parseMouseSequence(sequence),
            '~' => return try self.parseSpecialKey(sequence, params.items),
            '<' => {
                // SGR mouse format: ESC [ < param1 ; param2 ; param3 m/M
                return try self.parseSgrMouse(params.items, data[data.len - 1], i + 1);
            },
            else => return ParseResult{ .event = .{ .unknown = sequence }, .consumed = i + 1 },
        }
    }

    fn parseSpecialKey(self: *InputParser, sequence: []const u8, params: []const i32) !ParseResult {
        // Check dynamic mapping for the full sequence first
        if (self.key_mapping) |mapping| {
            if (mapping.mapSequence(sequence)) |extended_code| {
                return ParseResult{
                    .event = InputEvent{ .key_press = Key{
                        .code = extended_code,
                        .mod = .{}, // Dynamic mapping doesn't specify modifiers
                        .text = if (std.ascii.isPrint(@intCast(extended_code))) &[_]u8{@intCast(extended_code)} else "",
                    }},
                    .consumed = sequence.len,
                };
            }
        }

        if (params.len == 0) {
            return ParseResult{ .event = .{ .unknown = sequence }, .consumed = sequence.len };
        }

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
            else => return ParseResult{ .event = .{ .unknown = sequence }, .consumed = sequence.len },
        };

        // Parse modifiers from second parameter
        var mod = KeyMod{};
        if (params.len > 1) {
            const mod_param = params[1];
            if (mod_param & 1 != 0) mod.shift = true;
            if (mod_param & 2 != 0) mod.alt = true;
            if (mod_param & 4 != 0) mod.ctrl = true;
        }

        return ParseResult{
            .event = InputEvent{ .key_press = Key{ .code = code, .mod = mod } },
            .consumed = sequence.len,
        };
    }

    fn parseMouseSequence(self: *InputParser, sequence: []const u8) !ParseResult {
        if (sequence.len < 6) {
            return ParseResult{ .event = .{ .unknown = sequence }, .consumed = sequence.len };
        }

        const b = sequence[3] - 32;
        const x = @as(i32, sequence[4]) - 32 - 1; // Convert to 0-based
        const y = @as(i32, sequence[5]) - 32 - 1;

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

        const event = if (button.isWheel()) InputEvent{ .mouse_wheel = mouse } else if (is_motion) InputEvent{ .mouse_motion = mouse } else if (is_release) InputEvent{ .mouse_release = mouse } else InputEvent{ .mouse_click = mouse };

        return ParseResult{
            .event = event,
            .consumed = sequence.len,
        };
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
    fn parseSgrMouse(self: *InputParser, params: []const i32, terminator: u8, consumed: usize) !ParseResult {
        _ = self;
        if (params.len < 3) {
            return ParseResult{ .event = .{ .unknown = "incomplete sgr mouse" }, .consumed = consumed };
        }

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
        const event = if (button.isWheel()) InputEvent{ .mouse_wheel = mouse } else if (is_motion) InputEvent{ .mouse_motion = mouse } else if (is_release) InputEvent{ .mouse_release = mouse } else InputEvent{ .mouse_click = mouse };

        return ParseResult{
            .event = event,
            .consumed = consumed,
        };
    }

    fn parseCharacter(self: *InputParser, byte: u8) !InputEvent {
        _ = self;
        const key = Key{
            .code = byte,
            .text = if (std.ascii.isPrint(byte)) &[_]u8{byte} else "",
        };
        return InputEvent{ .key_press = key };
    }

    fn createKeyEvent(self: *InputParser, code: u21, mod: KeyMod) InputEvent {
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

// Test implementation of KeyMapping interface for testing
const TestKeyMapper = struct {
    map: std.StringHashMap(u21),

    fn mapSequence(ptr: *anyopaque, sequence: []const u8) ?u21 {
        const self = @as(*TestKeyMapper, @ptrCast(@alignCast(ptr)));
        return self.map.get(sequence);
    }

    fn init(allocator: std.mem.Allocator) !TestKeyMapper {
        var map = std.StringHashMap(u21).init(allocator);
        try map.put("\x1b[test~", ExtendedKeyCodes.F13);
        try map.put("\x1b[custom]", ExtendedKeyCodes.F14);
        return TestKeyMapper{ .map = map };
    }

    fn deinit(self: *TestKeyMapper) void {
        self.map.deinit();
    }
};

test "key mapping interface integration" {
    var test_mapper = try TestKeyMapper.init(std.testing.allocator);
    defer test_mapper.deinit();

    const key_mapping = KeyMapping{
        .ptr = &test_mapper,
        .mapSequenceFn = TestKeyMapper.mapSequence,
    };

    var parser = InputParser.initWithMapping(std.testing.allocator, key_mapping);
    defer parser.deinit();

    // Test custom mapping
    const events = try parser.parse("\x1b[test~");
    defer std.testing.allocator.free(events);

    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .key_press);
    try std.testing.expectEqual(ExtendedKeyCodes.F13, events[0].key_press.code);
}

test "backward compatibility without mapping" {
    // Test that existing functionality still works without key mapping
    var parser = InputParser.init(std.testing.allocator);
    defer parser.deinit();

    // Test regular ASCII
    const events1 = try parser.parse("a");
    defer std.testing.allocator.free(events1);
    try std.testing.expect(events1.len == 1);
    try std.testing.expect(events1[0].key_press.code == 'a');

    // Test escape sequence
    const events2 = try parser.parse("\x1b[A");
    defer std.testing.allocator.free(events2);
    try std.testing.expect(events2.len == 1);
    try std.testing.expect(events2[0].key_press.code == ExtendedKeyCodes.UP);
}

test "dynamic mapping fallback" {
    var test_mapper = try TestKeyMapper.init(std.testing.allocator);
    defer test_mapper.deinit();

    const key_mapping = KeyMapping{
        .ptr = &test_mapper,
        .mapSequenceFn = TestKeyMapper.mapSequence,
    };

    var parser = InputParser.initWithMapping(std.testing.allocator, key_mapping);
    defer parser.deinit();

    // Test that up arrow is mapped to hardcoded value (dynamic mapping doesn't override)
    const events = try parser.parse("\x1b[A");
    defer std.testing.allocator.free(events);

    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .key_press);
    try std.testing.expect(events[0].key_press.code == ExtendedKeyCodes.UP);
}

test "key translation utilities" {
    // Test extended to enum conversion
    const up_enum = KeyTranslation.extendedToEnum(ExtendedKeyCodes.UP);
    try std.testing.expect(up_enum != null);
    try std.testing.expectEqual(enhanced_keys.Key.up, up_enum.?);

    // Test enum to extended conversion
    const up_extended = KeyTranslation.enumToExtended(.up);
    try std.testing.expect(up_extended != null);
    try std.testing.expectEqual(ExtendedKeyCodes.UP, up_extended.?);

    // Test round trip
    const f13_enum = KeyTranslation.extendedToEnum(ExtendedKeyCodes.F13);
    try std.testing.expect(f13_enum != null);
    try std.testing.expectEqual(enhanced_keys.Key.f13, f13_enum.?);

    const f13_extended = KeyTranslation.enumToExtended(.f13);
    try std.testing.expect(f13_extended != null);
    try std.testing.expectEqual(ExtendedKeyCodes.F13, f13_extended.?);
}

test "modifier translation" {
    const key_mod = KeyMod{ .ctrl = true, .alt = true, .shift = false };
    const enhanced_mods = key_mod.toEnhancedModifiers();

    try std.testing.expect(enhanced_mods.ctrl);
    try std.testing.expect(enhanced_mods.alt);
    try std.testing.expect(!enhanced_mods.shift);

    const converted_back = KeyMod.fromEnhancedModifiers(enhanced_mods);
    try std.testing.expect(converted_back.ctrl);
    try std.testing.expect(converted_back.alt);
    try std.testing.expect(!converted_back.shift);
}

const std = @import("std");

// Re-export unified types for backward compatibility
pub const Modifiers = @import("../../types.zig").Modifiers;

// Extended key definitions for comprehensive input handling
pub const Key = enum(u32) {
    // Control characters (0x00-0x1F, 0x7F)
    null = 0x00,
    ctrl_a = 0x01,
    ctrl_b = 0x02,
    ctrl_c = 0x03,
    ctrl_d = 0x04,
    ctrl_e = 0x05,
    ctrl_f = 0x06,
    ctrl_g = 0x07,
    backspace = 0x08, // ctrl_h
    tab = 0x09, // ctrl_i
    enter = 0x0A, // ctrl_j (LF)
    ctrl_k = 0x0B,
    ctrl_l = 0x0C,
    ctrl_m = 0x0D, // Also Enter/CR
    ctrl_n = 0x0E,
    ctrl_o = 0x0F,
    ctrl_p = 0x10,
    ctrl_q = 0x11,
    ctrl_r = 0x12,
    ctrl_s = 0x13,
    ctrl_t = 0x14,
    ctrl_u = 0x15,
    ctrl_v = 0x16,
    ctrl_w = 0x17,
    ctrl_x = 0x18,
    ctrl_y = 0x19,
    ctrl_z = 0x1A,
    escape = 0x1B, // ESC
    ctrl_backslash = 0x1C,
    ctrl_close_bracket = 0x1D,
    ctrl_caret = 0x1E,
    ctrl_underscore = 0x1F,
    space = 0x20,
    delete = 0x7F, // DEL

    // Extended keys start from unicode.MaxRune + 1
    key_extended = std.unicode.max_unicode + 1,

    // Special keys
    up,
    down,
    right,
    left,
    begin,
    find,
    insert_key, // renamed to avoid conflict with builtin
    delete_key,
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

    // Keypad navigation (Kitty keyboard protocol)
    kp_separator,
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

    // Modifier keys (for Kitty keyboard protocol)
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

    // Special event markers
    focus_in,
    focus_out,
    paste_start,
    paste_end,

    // Unknown key
    unknown,

    pub fn getName(self: Key) []const u8 {
        return switch (self) {
            .null => "null",
            .ctrl_a => "ctrl+a",
            .ctrl_b => "ctrl+b",
            .ctrl_c => "ctrl+c",
            .ctrl_d => "ctrl+d",
            .ctrl_e => "ctrl+e",
            .ctrl_f => "ctrl+f",
            .ctrl_g => "ctrl+g",
            .backspace => "backspace",
            .tab => "tab",
            .enter => "enter",
            .ctrl_k => "ctrl+k",
            .ctrl_l => "ctrl+l",
            .ctrl_m => "ctrl+m",
            .ctrl_n => "ctrl+n",
            .ctrl_o => "ctrl+o",
            .ctrl_p => "ctrl+p",
            .ctrl_q => "ctrl+q",
            .ctrl_r => "ctrl+r",
            .ctrl_s => "ctrl+s",
            .ctrl_t => "ctrl+t",
            .ctrl_u => "ctrl+u",
            .ctrl_v => "ctrl+v",
            .ctrl_w => "ctrl+w",
            .ctrl_x => "ctrl+x",
            .ctrl_y => "ctrl+y",
            .ctrl_z => "ctrl+z",
            .escape => "esc",
            .ctrl_backslash => "ctrl+\\",
            .ctrl_close_bracket => "ctrl+]",
            .ctrl_caret => "ctrl+^",
            .ctrl_underscore => "ctrl+_",
            .space => "space",
            .delete => "delete",
            .up => "up",
            .down => "down",
            .right => "right",
            .left => "left",
            .begin => "begin",
            .find => "find",
            .insert_key => "insert",
            .delete_key => "delete",
            .select => "select",
            .page_up => "pgup",
            .page_down => "pgdown",
            .home => "home",
            .end => "end",
            .kp_enter => "kp_enter",
            .kp_equal => "kp_equal",
            .kp_multiply => "kp_multiply",
            .kp_plus => "kp_plus",
            .kp_comma => "kp_comma",
            .kp_minus => "kp_minus",
            .kp_decimal => "kp_decimal",
            .kp_divide => "kp_divide",
            .kp_0 => "kp_0",
            .kp_1 => "kp_1",
            .kp_2 => "kp_2",
            .kp_3 => "kp_3",
            .kp_4 => "kp_4",
            .kp_5 => "kp_5",
            .kp_6 => "kp_6",
            .kp_7 => "kp_7",
            .kp_8 => "kp_8",
            .kp_9 => "kp_9",
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
            .caps_lock => "caps_lock",
            .scroll_lock => "scroll_lock",
            .num_lock => "num_lock",
            .print_screen => "print_screen",
            .pause => "pause",
            .menu => "menu",
            .media_play => "media_play",
            .media_pause => "media_pause",
            .media_play_pause => "media_play_pause",
            .media_reverse => "media_reverse",
            .media_stop => "media_stop",
            .media_fast_forward => "media_fast_forward",
            .media_rewind => "media_rewind",
            .media_next => "media_next",
            .media_prev => "media_prev",
            .media_record => "media_record",
            .lower_vol => "lower_vol",
            .raise_vol => "raise_vol",
            .mute => "mute",
            .left_shift => "left_shift",
            .left_alt => "left_alt",
            .left_ctrl => "left_ctrl",
            .left_super => "left_super",
            .left_hyper => "left_hyper",
            .left_meta => "left_meta",
            .right_shift => "right_shift",
            .right_alt => "right_alt",
            .right_ctrl => "right_ctrl",
            .right_super => "right_super",
            .right_hyper => "right_hyper",
            .right_meta => "right_meta",
            .iso_level3_shift => "iso_level3_shift",
            .iso_level5_shift => "iso_level5_shift",
            .focus_in => "focus_in",
            .focus_out => "focus_out",
            .paste_start => "paste_start",
            .paste_end => "paste_end",
            else => "unknown",
        };
    }
};

// Re-export unified types for backward compatibility
pub const MouseButton = @import("../../types.zig").MouseButton;

// Re-export unified types for backward compatibility
pub const MouseAction = @import("../../types.zig").MouseAction;

// Re-export unified types for backward compatibility
pub const MouseEvent = @import("../../types.zig").MouseEvent;

// Cursor position report (CPR / DECXCPR).
pub const CursorPositionEvent = struct {
    // Zero-based row/col.
    row: u32,
    col: u32,
    // Optional page for DECXCPR.
    page: ?u32 = null,
};

// Focus event when DECSET 1004 is enabled.
pub const FocusEvent = enum {
    focus,
    blur,
};

// Key event with comprehensive information
pub const KeyEvent = struct {
    /// Text contains the actual characters received for printable keys
    text: []const u8,

    /// Modifier keys pressed
    mod: Modifiers,

    /// Key code pressed
    code: Key,

    /// Shifted version of the key (Kitty keyboard protocol)
    shifted_code: ?Key = null,

    /// Base key according to PC-101 layout (Kitty keyboard protocol)
    base_code: ?Key = null,

    /// Whether this is a repeat event (Kitty keyboard protocol)
    is_repeat: bool = false,

    /// Check if the key represents printable character(s)
    pub fn isPrintable(self: KeyEvent) bool {
        return self.text.len > 0 and !std.mem.eql(u8, self.text, " ");
    }

    /// Check if this is a control character
    pub fn isControl(self: KeyEvent) bool {
        return switch (self.code) {
            .null, .ctrl_a, .ctrl_b, .ctrl_c, .ctrl_d, .ctrl_e, .ctrl_f, .ctrl_g, .backspace, .tab, .enter, .ctrl_k, .ctrl_l, .ctrl_m, .ctrl_n, .ctrl_o, .ctrl_p, .ctrl_q, .ctrl_r, .ctrl_s, .ctrl_t, .ctrl_u, .ctrl_v, .ctrl_w, .ctrl_x, .ctrl_y, .ctrl_z, .escape, .ctrl_backslash, .ctrl_close_bracket, .ctrl_caret, .ctrl_underscore, .delete => true,
            else => false,
        };
    }

    /// Get string representation for easy matching
    pub fn getKeystroke(self: KeyEvent, allocator: std.mem.Allocator) ![]const u8 {
        if (self.isPrintable()) {
            return try allocator.dupe(u8, self.text);
        }

        var result = std.ArrayListUnmanaged(u8){};
        defer result.deinit(allocator);

        // Add modifiers in consistent order
        if (self.mod.ctrl and self.code != .left_ctrl and self.code != .right_ctrl) {
            try result.appendSlice(allocator, "ctrl+");
        }
        if (self.mod.alt and self.code != .left_alt and self.code != .right_alt) {
            try result.appendSlice(allocator, "alt+");
        }
        if (self.mod.shift and self.code != .left_shift and self.code != .right_shift) {
            try result.appendSlice(allocator, "shift+");
        }
        if (self.mod.meta and self.code != .left_meta and self.code != .right_meta) {
            try result.appendSlice(allocator, "meta+");
        }
        if (self.mod.hyper and self.code != .left_hyper and self.code != .right_hyper) {
            try result.appendSlice(allocator, "hyper+");
        }
        if (self.mod.super and self.code != .left_super and self.code != .right_super) {
            try result.appendSlice(allocator, "super+");
        }

        // Use base code if available (for international keyboards)
        const key_code = self.base_code orelse self.code;

        if (key_code == .space) {
            try result.appendSlice(allocator, "space");
        } else if (key_code == .key_extended) {
            // Multi-rune key, use the text representation
            try result.appendSlice(allocator, self.text);
        } else {
            try result.appendSlice(allocator, key_code.getName());
        }

        return try result.toOwnedSlice(allocator);
    }

    pub fn format(self: KeyEvent, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (self.isPrintable()) {
            try writer.print("{s}", .{self.text});
            return;
        }

        // Build keystroke representation
        if (self.mod.ctrl and self.code != .left_ctrl and self.code != .right_ctrl) {
            try writer.print("ctrl+", .{});
        }
        if (self.mod.alt and self.code != .left_alt and self.code != .right_alt) {
            try writer.print("alt+", .{});
        }
        if (self.mod.shift and self.code != .left_shift and self.code != .right_shift) {
            try writer.print("shift+", .{});
        }
        if (self.mod.meta and self.code != .left_meta and self.code != .right_meta) {
            try writer.print("meta+", .{});
        }
        if (self.mod.hyper and self.code != .left_hyper and self.code != .right_hyper) {
            try writer.print("hyper+", .{});
        }
        if (self.mod.super and self.code != .left_super and self.code != .right_super) {
            try writer.print("super+", .{});
        }

        const key_code = self.base_code orelse self.code;
        try writer.print("{s}", .{key_code.getName()});
    }
};

// Key press event
pub const KeyPressEvent = KeyEvent;

// Key release event (Kitty keyboard protocol)
pub const KeyReleaseEvent = KeyEvent;

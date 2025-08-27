//! Unified Input System for Terminal Applications
//!
//! This module provides a comprehensive, unified input handling system that consolidates
//! keyboard, mouse, and other input events into a single, consistent API. It replaces
//! the fragmented input systems across term/input/ and tui/core/input/ with a single
//! cohesive system that works across CLI and TUI applications.
//!
//! Key Features:
//! - Single event system for all input types
//! - Consistent keyboard and mouse handling
//! - Comprehensive terminal input sequence parsing
//! - Clean API for both term and TUI layers
//! - Eliminates duplicate event definitions
//! - Modern terminal protocol support (SGR, Kitty, etc.)

const std = @import("std");
const caps = @import("term/caps.zig");
const ansi_mode = @import("term/ansi/mode.zig");

/// ============================================================================
/// UNIFIED EVENT SYSTEM
/// ============================================================================

/// Unified input event types that work across CLI and TUI
pub const Event = union(enum) {
    /// Keyboard press event
    key_press: KeyPressEvent,
    /// Keyboard release event (Kitty protocol)
    key_release: KeyReleaseEvent,
    /// Mouse press event
    mouse_press: MousePressEvent,
    /// Mouse release event
    mouse_release: MouseReleaseEvent,
    /// Mouse move/drag event
    mouse_move: MouseMoveEvent,
    /// Mouse scroll event
    mouse_scroll: MouseScrollEvent,
    /// Paste event (bracketed paste)
    paste: PasteEvent,
    /// Window focus gained
    focus_gained,
    /// Window focus lost
    focus_lost,
    /// Window resize event
    resize: ResizeEvent,

    /// Key press event data
    pub const KeyPressEvent = struct {
        key: Key,
        text: ?[]const u8 = null,
        modifiers: Modifiers = .{},
        repeat: bool = false,
        timestamp: i64 = 0,
    };

    /// Key release event data
    pub const KeyReleaseEvent = struct {
        key: Key,
        modifiers: Modifiers = .{},
        timestamp: i64 = 0,
    };

    /// Mouse press event data
    pub const MousePressEvent = struct {
        button: MouseButton,
        x: u32,
        y: u32,
        modifiers: Modifiers = .{},
        timestamp: i64 = 0,
    };

    /// Mouse release event data
    pub const MouseReleaseEvent = struct {
        button: MouseButton,
        x: u32,
        y: u32,
        modifiers: Modifiers = .{},
        timestamp: i64 = 0,
    };

    /// Mouse move event data
    pub const MouseMoveEvent = struct {
        x: u32,
        y: u32,
        modifiers: Modifiers = .{},
        timestamp: i64 = 0,
    };

    /// Mouse scroll event data
    pub const MouseScrollEvent = struct {
        delta_x: f32,
        delta_y: f32,
        x: u32,
        y: u32,
        modifiers: Modifiers = .{},
        timestamp: i64 = 0,
    };

    /// Paste event data
    pub const PasteEvent = struct {
        text: []const u8,
        bracketed: bool = false,
        timestamp: i64 = 0,
    };

    /// Window resize event data
    pub const ResizeEvent = struct {
        width: u32,
        height: u32,
        timestamp: i64 = 0,
    };

    /// Clean up event resources
    pub fn deinit(self: *Event, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .key_press => |*key| if (key.text) |text| allocator.free(text),
            .paste => |*paste| allocator.free(paste.text),
            else => {},
        }
    }

    /// Get timestamp from event
    pub fn timestamp(self: Event) i64 {
        return switch (self) {
            .key_press => |e| e.timestamp,
            .key_release => |e| e.timestamp,
            .mouse_press => |e| e.timestamp,
            .mouse_release => |e| e.timestamp,
            .mouse_move => |e| e.timestamp,
            .mouse_scroll => |e| e.timestamp,
            .paste => |e| e.timestamp,
            .resize => |e| e.timestamp,
            .focus_gained, .focus_lost => std.time.microTimestamp(),
        };
    }
};

/// ============================================================================
/// KEYBOARD SYSTEM
/// ============================================================================

/// Comprehensive key definitions
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
    backspace = 0x08,
    tab = 0x09,
    enter = 0x0A,
    ctrl_k = 0x0B,
    ctrl_l = 0x0C,
    ctrl_m = 0x0D,
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
    escape = 0x1B,
    ctrl_backslash = 0x1C,
    ctrl_close_bracket = 0x1D,
    ctrl_caret = 0x1E,
    ctrl_underscore = 0x1F,
    space = 0x20,
    delete = 0x7F,

    // Extended keys start from unicode.MaxRune + 1
    key_extended = std.unicode.max_unicode + 1,

    // Navigation keys
    up,
    down,
    right,
    left,
    home,
    end,
    page_up,
    page_down,
    insert,
    begin,
    find,
    select,

    // Function keys
    f1, f2, f3, f4, f5, f6, f7, f8, f9, f10,
    f11, f12, f13, f14, f15, f16, f17, f18, f19, f20,
    f21, f22, f23, f24, f25, f26, f27, f28, f29, f30,
    f31, f32, f33, f34, f35, f36, f37, f38, f39, f40,
    f41, f42, f43, f44, f45, f46, f47, f48, f49, f50,
    f51, f52, f53, f54, f55, f56, f57, f58, f59, f60,
    f61, f62, f63,

    // Keypad keys
    kp_enter,
    kp_equal,
    kp_multiply,
    kp_plus,
    kp_comma,
    kp_minus,
    kp_decimal,
    kp_divide,
    kp_0, kp_1, kp_2, kp_3, kp_4,
    kp_5, kp_6, kp_7, kp_8, kp_9,

    // Keypad navigation (Kitty keyboard protocol)
    kp_separator,
    kp_up, kp_down, kp_left, kp_right,
    kp_page_up, kp_page_down, kp_home, kp_end,
    kp_insert, kp_delete, kp_begin,

    // Kitty keyboard protocol special keys
    caps_lock, scroll_lock, num_lock,
    print_screen, pause, menu,

    // Media keys
    media_play, media_pause, media_play_pause,
    media_reverse, media_stop, media_fast_forward, media_rewind,
    media_next, media_prev, media_record,

    // Volume keys
    lower_vol, raise_vol, mute,

    // Modifier keys (for Kitty keyboard protocol)
    left_shift, left_alt, left_ctrl, left_super, left_hyper, left_meta,
    right_shift, right_alt, right_ctrl, right_super, right_hyper, right_meta,
    iso_level3_shift, iso_level5_shift,

    // Special event markers
    focus_in, focus_out, paste_start, paste_end,

    // Unknown key
    unknown,

    /// Get human-readable name for key
    pub fn getName(self: Key) []const u8 {
        return switch (self) {
            .null => "null",
            .ctrl_a => "ctrl+a", .ctrl_b => "ctrl+b", .ctrl_c => "ctrl+c",
            .ctrl_d => "ctrl+d", .ctrl_e => "ctrl+e", .ctrl_f => "ctrl+f",
            .ctrl_g => "ctrl+g", .backspace => "backspace", .tab => "tab",
            .enter => "enter", .ctrl_k => "ctrl+k", .ctrl_l => "ctrl+l",
            .ctrl_m => "ctrl+m", .ctrl_n => "ctrl+n", .ctrl_o => "ctrl+o",
            .ctrl_p => "ctrl+p", .ctrl_q => "ctrl+q", .ctrl_r => "ctrl+r",
            .ctrl_s => "ctrl+s", .ctrl_t => "ctrl+t", .ctrl_u => "ctrl+u",
            .ctrl_v => "ctrl+v", .ctrl_w => "ctrl+w", .ctrl_x => "ctrl+x",
            .ctrl_y => "ctrl+y", .ctrl_z => "ctrl+z", .escape => "esc",
            .ctrl_backslash => "ctrl+\\", .ctrl_close_bracket => "ctrl+]",
            .ctrl_caret => "ctrl+^", .ctrl_underscore => "ctrl+_",
            .space => "space", .delete => "delete",
            .up => "up", .down => "down", .right => "right", .left => "left",
            .home => "home", .end => "end", .page_up => "pgup", .page_down => "pgdown",
            .insert => "insert", .begin => "begin", .find => "find", .select => "select",
            .f1 => "f1", .f2 => "f2", .f3 => "f3", .f4 => "f4", .f5 => "f5",
            .f6 => "f6", .f7 => "f7", .f8 => "f8", .f9 => "f9", .f10 => "f10",
            .f11 => "f11", .f12 => "f12", .f13 => "f13", .f14 => "f14", .f15 => "f15",
            .f16 => "f16", .f17 => "f17", .f18 => "f18", .f19 => "f19", .f20 => "f20",
            .f21 => "f21", .f22 => "f22", .f23 => "f23", .f24 => "f24",
            .kp_enter => "kp_enter", .kp_equal => "kp_equal", .kp_multiply => "kp_multiply",
            .kp_plus => "kp_plus", .kp_comma => "kp_comma", .kp_minus => "kp_minus",
            .kp_decimal => "kp_decimal", .kp_divide => "kp_divide",
            .kp_0 => "kp_0", .kp_1 => "kp_1", .kp_2 => "kp_2", .kp_3 => "kp_3",
            .kp_4 => "kp_4", .kp_5 => "kp_5", .kp_6 => "kp_6", .kp_7 => "kp_7",
            .kp_8 => "kp_8", .kp_9 => "kp_9",
            .kp_separator => "kp_separator", .kp_up => "kp_up", .kp_down => "kp_down",
            .kp_left => "kp_left", .kp_right => "kp_right", .kp_page_up => "kp_page_up",
            .kp_page_down => "kp_page_down", .kp_home => "kp_home", .kp_end => "kp_end",
            .kp_insert => "kp_insert", .kp_delete => "kp_delete", .kp_begin => "kp_begin",
            .caps_lock => "caps_lock", .scroll_lock => "scroll_lock", .num_lock => "num_lock",
            .print_screen => "print_screen", .pause => "pause", .menu => "menu",
            .media_play => "media_play", .media_pause => "media_pause",
            .media_play_pause => "media_play_pause", .media_reverse => "media_reverse",
            .media_stop => "media_stop", .media_fast_forward => "media_fast_forward",
            .media_rewind => "media_rewind", .media_next => "media_next",
            .media_prev => "media_prev", .media_record => "media_record",
            .lower_vol => "lower_vol", .raise_vol => "raise_vol", .mute => "mute",
            .left_shift => "left_shift", .left_alt => "left_alt", .left_ctrl => "left_ctrl",
            .left_super => "left_super", .left_hyper => "left_hyper", .left_meta => "left_meta",
            .right_shift => "right_shift", .right_alt => "right_alt", .right_ctrl => "right_ctrl",
            .right_super => "right_super", .right_hyper => "right_hyper", .right_meta => "right_meta",
            .iso_level3_shift => "iso_level3_shift", .iso_level5_shift => "iso_level5_shift",
            .focus_in => "focus_in", .focus_out => "focus_out",
            .paste_start => "paste_start", .paste_end => "paste_end",
            .unknown => "unknown",
            else => "unknown",
        };
    }
};

/// ============================================================================
/// EXTENDED KEY CODES
/// ============================================================================

/// Extended key codes beyond normal unicode range for advanced keyboard protocols
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

/// ============================================================================
/// COLOR EVENT SYSTEM
/// ============================================================================

/// Color event types for terminal color queries (OSC responses)
pub const ColorEvent = union(enum) {
    foreground: Color,
    background: Color,
    cursor: Color,
};

/// RGB color representation
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    /// Parse color from OSC response format (e.g., "rgb:ffff/0000/0000")
    pub fn parseOscColor(response: []const u8) ?Color {
        // Handle rgb:rrrr/gggg/bbbb format
        if (std.mem.startsWith(u8, response, "rgb:")) {
            const color_part = response[4..];
            var parts = std.mem.splitSequence(u8, color_part, "/");

            const r_str = parts.next() orelse return null;
            const g_str = parts.next() orelse return null;
            const b_str = parts.next() orelse return null;

            // Convert 16-bit hex values to 8-bit
            const r16 = std.fmt.parseInt(u16, r_str, 16) catch return null;
            const g16 = std.fmt.parseInt(u16, g_str, 16) catch return null;
            const b16 = std.fmt.parseInt(u16, b_str, 16) catch return null;

            return Color{
                .r = @intCast(r16 >> 8),
                .g = @intCast(g16 >> 8),
                .b = @intCast(b16 >> 8),
            };
        }

        // Handle #rrggbb hex format
        if (std.mem.startsWith(u8, response, "#") and response.len == 7) {
            const hex_part = response[1..];
            const rgb = std.fmt.parseInt(u24, hex_part, 16) catch return null;

            return Color{
                .r = @intCast((rgb >> 16) & 0xFF),
                .g = @intCast((rgb >> 8) & 0xFF),
                .b = @intCast(rgb & 0xFF),
            };
        }

        return null;
    }

    /// Convert color to hex string format (#rrggbb)
    pub fn toHex(self: Color) [7]u8 {
        var buf: [7]u8 = undefined;
        buf[0] = '#';
        _ = std.fmt.bufPrint(buf[1..], "{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b }) catch unreachable;
        return buf;
    }

    /// Determine if the color is considered "dark" using HSL lightness
    pub fn isDark(self: Color) bool {
        const lightness = self.getLightness();
        return lightness < 0.5;
    }

    /// Calculate HSL lightness value (0.0 to 1.0)
    pub fn getLightness(self: Color) f64 {
        const r_norm = @as(f64, @floatFromInt(self.r)) / 255.0;
        const g_norm = @as(f64, @floatFromInt(self.g)) / 255.0;
        const b_norm = @as(f64, @floatFromInt(self.b)) / 255.0;

        const max_val = @max(r_norm, @max(g_norm, b_norm));
        const min_val = @min(r_norm, @min(g_norm, b_norm));

        return (max_val + min_val) / 2.0;
    }
};

/// Parse OSC 10/11/12 color response
/// Format: ESC ] code ; color ST  or  ESC ] code ; color BEL
pub fn parseOscColorResponse(seq: []const u8) ?ColorEvent {
    if (seq.len < 8) return null; // Minimum: "\x1b]10;?\x07"

    if (!std.mem.startsWith(u8, seq, "\x1b]")) return null;

    // Find the terminator (ST or BEL)
    const end_pos = blk: {
        if (std.mem.indexOf(u8, seq, "\x1b\\")) |pos| break :blk pos; // ST
        if (std.mem.indexOf(u8, seq, "\x07")) |pos| break :blk pos; // BEL
        return null;
    };

    const content = seq[2..end_pos]; // Skip ESC ]
    const semicolon_pos = std.mem.indexOf(u8, content, ";") orelse return null;

    const code_str = content[0..semicolon_pos];
    const color_str = content[semicolon_pos + 1 ..];

    const code = std.fmt.parseInt(u8, code_str, 10) catch return null;
    const color = Color.parseOscColor(color_str) orelse return null;

    return switch (code) {
        10 => ColorEvent{ .foreground = color },
        11 => ColorEvent{ .background = color },
        12 => ColorEvent{ .cursor = color },
        else => null,
    };
}

/// ============================================================================
/// CLIPBOARD EVENT SYSTEM
/// ============================================================================

/// Clipboard selection kinds.
pub const ClipboardSelection = enum { system, primary };

/// ClipboardEvent decoded from OSC 52 read responses.
pub const ClipboardEvent = struct {
    content: []const u8,
    selection: ClipboardSelection = .system,
};

/// Parse OSC 52 clipboard response
/// Format: OSC 52 ; c ; <base64> ST|BEL
/// Format: OSC 52 ; p ; <base64> ST|BEL
pub fn parseOscClipboardResponse(allocator: std.mem.Allocator, seq: []const u8) ?ClipboardEvent {
    if (seq.len < 8) return null; // Minimum: "\x1b]52;c;?\x07"

    if (!std.mem.startsWith(u8, seq, "\x1b]")) return null;

    // Find the terminator (ST or BEL)
    const end_pos = blk: {
        if (std.mem.indexOf(u8, seq, "\x1b\\")) |pos| break :blk pos; // ST
        if (std.mem.indexOf(u8, seq, "\x07")) |pos| break :blk pos; // BEL
        return null;
    };

    const content = seq[2..end_pos]; // Skip ESC ]
    if (!std.mem.startsWith(u8, content, "52;")) return null;

    const data_part = content[3..]; // Skip "52;"
    var parts = std.mem.splitSequence(u8, data_part, ";");

    const sel_ch = parts.next() orelse return null;
    if (sel_ch.len != 1) return null;

    const sel: ClipboardSelection = if (sel_ch[0] == 'p') .primary else .system;
    const b64 = parts.next() orelse return null;

    // Decode base64
    const dec = std.base64.standard.Decoder;
    const out_len = dec.calcSizeForSlice(b64) catch return null;
    const buf = allocator.alloc(u8, out_len) catch return null;
    errdefer allocator.free(buf);
    dec.decode(buf, b64) catch {
        allocator.free(buf);
        return null;
    };

    return ClipboardEvent{
        .content = buf,
        .selection = sel,
    };
}

/// ============================================================================
/// MOUSE SYSTEM
/// ============================================================================

/// Mouse button enumeration
pub const MouseButton = enum(u8) {
    none = 255,
    left = 0,
    middle = 1,
    right = 2,
    button4 = 3,
    button5 = 4,
    button6 = 5,
    button7 = 6,
    wheel_up = 64,
    wheel_down = 65,
    wheel_left = 66,
    wheel_right = 67,
    touch_1 = 128,
    touch_2 = 129,
    touch_3 = 130,
};

/// Mouse tracking modes
pub const MouseMode = enum {
    none,
    basic,
    normal,
    button_event,
    any_event,
    sgr_basic,
    sgr_pixel,
    urxvt,
    dec_locator,
};

/// ============================================================================
/// MODIFIERS
/// ============================================================================

/// Input modifiers (keyboard and mouse)
pub const Modifiers = struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    meta: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,
    scroll_lock: bool = false,
    hyper: bool = false,
    super: bool = false,

    /// Create modifiers from keyboard byte (CSI parameters)
    pub fn fromKeyboardByte(byte: u8) Modifiers {
        return Modifiers{
            .shift = (byte & 0x01) != 0,
            .alt = (byte & 0x02) != 0,
            .ctrl = (byte & 0x04) != 0,
            .super = (byte & 0x08) != 0,
            .hyper = (byte & 0x10) != 0,
            .meta = (byte & 0x20) != 0,
        };
    }

    /// Create modifiers from mouse byte
    pub fn fromMouseByte(byte: u8) Modifiers {
        return Modifiers{
            .shift = (byte & 0x04) != 0,
            .alt = (byte & 0x08) != 0,
            .ctrl = (byte & 0x10) != 0,
            .meta = (byte & 0x20) != 0,
            .caps_lock = (byte & 0x40) != 0,
            .num_lock = (byte & 0x80) != 0,
        };
    }

    /// Convert to byte representation
    pub fn toByte(self: Modifiers) u8 {
        var result: u8 = 0;
        if (self.shift) result |= 0x04;
        if (self.alt) result |= 0x08;
        if (self.ctrl) result |= 0x10;
        if (self.meta) result |= 0x20;
        if (self.caps_lock) result |= 0x40;
        if (self.num_lock) result |= 0x80;
        return result;
    }

    /// Check if any modifier is pressed
    pub fn any(self: Modifiers) bool {
        return self.shift or self.ctrl or self.alt or self.meta or
               self.caps_lock or self.num_lock or self.scroll_lock or
               self.hyper or self.super;
    }
};

/// ============================================================================
/// INPUT FEATURES AND CONFIGURATION
/// ============================================================================

/// Input features that can be enabled
pub const InputFeatures = packed struct {
    raw_mode: bool = true,
    mouse_events: bool = true,
    bracketed_paste: bool = true,
    focus_events: bool = true,
    kitty_keyboard: bool = false,
    extended_mouse: bool = false,
    urxvt_mouse: bool = false,
    sgr_pixel_mouse: bool = false,
};

/// Configuration for input handling
pub const InputConfig = struct {
    features: InputFeatures = .{},
    buffer_size: usize = 4096,
    poll_timeout_ms: u32 = 100,
    enable_debug_logging: bool = false,
    double_click_threshold_ms: i64 = 300,
    drag_threshold_pixels: u32 = 3,
};

/// ============================================================================
/// UNIFIED INPUT MANAGER
/// ============================================================================

/// Unified input manager that provides consistent input handling
pub const InputManager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: InputConfig,
    caps: caps.TermCaps,
    parser: InputParser,

    // Terminal state
    raw_mode_enabled: bool = false,
    mouse_enabled: bool = false,
    bracketed_paste_enabled: bool = false,
    focus_events_enabled: bool = false,

    // Input buffering
    input_buffer: std.ArrayList(u8),
    buffer_pos: usize = 0,

    // Event queue for non-blocking reads
    event_queue: std.ArrayList(Event),
    queue_mutex: std.Thread.Mutex = .{},
    queue_condition: std.Thread.Condition = .{},

    // Feature detection
    supports_kitty_keyboard: bool = false,
    supports_extended_mouse: bool = false,
    supports_sgr_pixel_mouse: bool = false,

    pub fn init(allocator: std.mem.Allocator, config: InputConfig) !Self {
        const terminal_caps = try caps.detectCaps(allocator);
        const input_parser = InputParser.init(allocator);

        return Self{
            .allocator = allocator,
            .config = config,
            .caps = terminal_caps,
            .parser = input_parser,
            .input_buffer = std.ArrayList(u8).init(allocator),
            .event_queue = std.ArrayList(Event).init(allocator),
            .supports_kitty_keyboard = terminal_caps.supportsKittyKeyboard,
            .supports_extended_mouse = terminal_caps.supportsSgrMouse,
            .supports_sgr_pixel_mouse = terminal_caps.supportsSgrPixelMouse,
        };
    }

    pub fn deinit(self: *Self) void {
        // Restore terminal state
        self.disableFeatures() catch {};

        // Clean up resources
        self.parser.deinit();
        self.input_buffer.deinit();

        // Clean up queued events
        for (self.event_queue.items) |*event| {
            event.deinit(self.allocator);
        }
        self.event_queue.deinit();
    }

    /// Enable input features based on configuration and terminal capabilities
    pub fn enableFeatures(self: *Self) !void {
        if (self.config.features.raw_mode and !self.raw_mode_enabled) {
            try self.enableRawMode();
        }

        if (self.config.features.mouse_events and !self.mouse_enabled) {
            if (self.config.features.sgr_pixel_mouse and self.supports_sgr_pixel_mouse) {
                try self.enableSgrPixelMouse();
            } else if (self.config.features.extended_mouse and self.supports_extended_mouse) {
                try self.enableExtendedMouse();
            } else {
                try self.enableBasicMouse();
            }
        }

        if (self.config.features.bracketed_paste and !self.bracketed_paste_enabled and self.caps.supportsBracketedPaste) {
            try self.enableBracketedPaste();
        }

        if (self.config.features.focus_events and !self.focus_events_enabled and self.caps.supportsFocusEvents) {
            try self.enableFocusEvents();
        }

        if (self.config.features.kitty_keyboard and !self.supports_kitty_keyboard) {
            // Kitty keyboard protocol would be enabled here
        }
    }

    /// Disable all enabled features
    pub fn disableFeatures(self: *Self) !void {
        if (self.raw_mode_enabled) {
            try self.disableRawMode();
        }
        if (self.mouse_enabled) {
            try self.disableMouse();
        }
        if (self.bracketed_paste_enabled) {
            try self.disableBracketedPaste();
        }
        if (self.focus_events_enabled) {
            try self.disableFocusEvents();
        }
    }

    /// Read next input event (blocking)
    pub fn nextEvent(self: *Self) !Event {
        while (true) {
            // Check event queue first
            if (self.event_queue.items.len > 0) {
                self.queue_mutex.lock();
                defer self.queue_mutex.unlock();
                return self.event_queue.orderedRemove(0);
            }

            // Read more input
            try self.fillBuffer();

            // Parse available events
            const events = try self.parseBuffer();
            defer {
                for (events) |event| {
                    event.deinit(self.allocator);
                }
                self.allocator.free(events);
            }

            // Convert and queue events
            for (events) |event| {
                const converted = try self.convertUnifiedEvent(event);
                self.queue_mutex.lock();
                try self.event_queue.append(converted);
                self.queue_mutex.unlock();
            }

            if (self.event_queue.items.len > 0) {
                self.queue_mutex.lock();
                defer self.queue_mutex.unlock();
                return self.event_queue.orderedRemove(0);
            }
        }
    }

    /// Poll for events with timeout
    pub fn pollEvent(self: *Self) ?Event {
        if (self.event_queue.items.len > 0) {
            self.queue_mutex.lock();
            defer self.queue_mutex.unlock();
            return self.event_queue.orderedRemove(0);
        }

        // Try to parse existing buffer
        if (self.buffer_pos < self.input_buffer.items.len) {
            if (self.parseNextEvent()) |event| {
                return event;
            }
        }

        return null;
    }

    /// Send raw input data for processing
    pub fn processInput(self: *Self, data: []const u8) !void {
        try self.input_buffer.appendSlice(data);

        const events = try self.parseBuffer();
        defer {
            for (events) |event| {
                event.deinit(self.allocator);
            }
            self.allocator.free(events);
        }

        // Convert and queue events
        for (events) |event| {
            const converted = try self.convertUnifiedEvent(event);
            self.queue_mutex.lock();
            try self.event_queue.append(converted);
            self.queue_mutex.unlock();
        }
    }

    // Internal methods

    fn enableRawMode(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.enableAltScreen(stdout, self.caps);
        try ansi_mode.hideCursor(stdout, self.caps);
        try stdout.flush();
        self.raw_mode_enabled = true;
    }

    fn disableRawMode(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.disableAltScreen(stdout, self.caps);
        try ansi_mode.showCursor(stdout, self.caps);
        try stdout.flush();
        self.raw_mode_enabled = false;
    }

    fn enableBasicMouse(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.enableX10Mouse(stdout, self.caps);
        try stdout.flush();
        self.mouse_enabled = true;
    }

    fn enableExtendedMouse(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.enableSgrMouse(stdout, self.caps);
        try stdout.flush();
        self.mouse_enabled = true;
    }

    fn enableSgrPixelMouse(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.enableSgrPixelMouse(stdout, self.caps);
        try stdout.flush();
        self.mouse_enabled = true;
    }

    fn disableMouse(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.disableMouse(stdout, self.caps);
        try stdout.flush();
        self.mouse_enabled = false;
    }

    fn enableBracketedPaste(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.enableBracketedPaste(stdout, self.caps);
        try stdout.flush();
        self.bracketed_paste_enabled = true;
    }

    fn disableBracketedPaste(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.disableBracketedPaste(stdout, self.caps);
        try stdout.flush();
        self.bracketed_paste_enabled = false;
    }

    fn enableFocusEvents(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.enableFocusEvents(stdout, self.caps);
        try stdout.flush();
        self.focus_events_enabled = true;
    }

    fn disableFocusEvents(self: *Self) !void {
        var stdout_writer = std.fs.File.stdout().writer(&[_]u8{});
        const stdout = &stdout_writer.interface;

        try ansi_mode.disableFocusEvents(stdout, self.caps);
        try stdout.flush();
        self.focus_events_enabled = false;
    }

    fn fillBuffer(self: *Self) !void {
        const stdin = std.fs.File.stdin();
        var temp_buf: [1024]u8 = undefined;

        const bytes_read = try stdin.read(&temp_buf);
        if (bytes_read > 0) {
            try self.input_buffer.appendSlice(temp_buf[0..bytes_read]);
        }
    }

    fn parseBuffer(self: *Self) ![]UnifiedEvent {
        const data = self.input_buffer.items[self.buffer_pos..];
        if (data.len == 0) return &[_]UnifiedEvent{};

        const events = try self.parser.parse(data);
        self.buffer_pos = self.input_buffer.items.len;

        return events;
    }

    fn parseNextEvent(self: *Self) ?Event {
        const data = self.input_buffer.items[self.buffer_pos..];
        if (data.len == 0) return null;

        // Try to parse one event
        var temp_parser = InputParser.init(self.allocator);
        defer temp_parser.deinit();

        const events = temp_parser.parse(data) catch return null;
        defer {
            for (events) |event| {
                switch (event) {
                    .key_press => |e| self.allocator.free(e.text),
                    .key_release => |e| self.allocator.free(e.text),
                    .unknown => |e| self.allocator.free(e),
                    else => {},
                }
            }
            self.allocator.free(events);
        }

        if (events.len > 0) {
            const event = events[0];
            const converted = self.convertUnifiedEvent(event) catch return null;

            // Advance buffer position (simplified)
            self.buffer_pos += 1;

            return converted;
        }

        return null;
    }

    fn convertUnifiedEvent(self: *Self, event: UnifiedEvent) !Event {
        const timestamp = std.time.microTimestamp();

        return switch (event) {
            .key_press => |key| Event{
                .key_press = .{
                    .key = key.code,
                    .text = if (key.text.len > 0) try self.allocator.dupe(u8, key.text) else null,
                    .modifiers = key.mod,
                    .timestamp = timestamp,
                },
            },
            .key_release => |key| Event{
                .key_release = .{
                    .key = key.code,
                    .modifiers = key.mod,
                    .timestamp = timestamp,
                },
            },
            .mouse => |mouse| {
                const mouse_data = mouse.mouse();
                switch (mouse) {
                    .press => Event{
                        .mouse_press = .{
                            .button = mouse_data.button,
                            .x = @as(u32, @intCast(mouse_data.x)),
                            .y = @as(u32, @intCast(mouse_data.y)),
                            .modifiers = mouse_data.modifiers,
                            .timestamp = timestamp,
                        },
                    },
                    .release => Event{
                        .mouse_release = .{
                            .button = mouse_data.button,
                            .x = @as(u32, @intCast(mouse_data.x)),
                            .y = @as(u32, @intCast(mouse_data.y)),
                            .modifiers = mouse_data.modifiers,
                            .timestamp = timestamp,
                        },
                    },
                    .drag, .motion => Event{
                        .mouse_move = .{
                            .x = @as(u32, @intCast(mouse_data.x)),
                            .y = @as(u32, @intCast(mouse_data.y)),
                            .modifiers = mouse_data.modifiers,
                            .timestamp = timestamp,
                        },
                    },
                    .scroll => |scroll| Event{
                        .mouse_scroll = .{
                            .delta_x = if (scroll.direction == .left) -1 else if (scroll.direction == .right) 1 else 0,
                            .delta_y = if (scroll.direction == .up) -1 else if (scroll.direction == .down) 1 else 0,
                            .x = @as(u32, @intCast(mouse_data.x)),
                            .y = @as(u32, @intCast(mouse_data.y)),
                            .modifiers = mouse_data.modifiers,
                            .timestamp = timestamp,
                        },
                    },
                }
            },
            .focus_in => .focus_gained,
            .focus_out => .focus_lost,
            .paste_start => Event{
                .paste = .{
                    .text = "",
                    .bracketed = true,
                    .timestamp = timestamp,
                },
            },
            .paste_end => Event{
                .paste = .{
                    .text = "",
                    .bracketed = true,
                    .timestamp = timestamp,
                },
            },
            .window_size => |size| Event{
                .resize = .{
                    .width = size.width,
                    .height = size.height,
                    .timestamp = timestamp,
                },
            },
            .unknown => |data| {
                // Try to interpret unknown sequences
                if (std.mem.eql(u8, data, "focus_in")) {
                    return .focus_gained;
                } else if (std.mem.eql(u8, data, "focus_out")) {
                    return .focus_lost;
                } else {
                    // For unknown events, create a key_press with unknown key
                    return Event{
                        .key_press = .{
                            .key = .unknown,
                            .text = try self.allocator.dupe(u8, data),
                            .timestamp = timestamp,
                        },
                    };
                }
            },
        };
    }
};

/// ============================================================================
/// UNIFIED INPUT PARSER
/// ============================================================================

/// Internal unified event types (before conversion to public Event)
const UnifiedEvent = union(enum) {
    key_press: KeyPressEvent,
    key_release: KeyReleaseEvent,
    mouse: MouseEvent,
    focus_in,
    focus_out,
    paste_start,
    paste_end,
    window_size: struct { width: u16, height: u16 },
    unknown: []const u8,

    pub const KeyPressEvent = struct {
        code: Key,
        text: []const u8,
        mod: Modifiers,
    };

    pub const KeyReleaseEvent = struct {
        code: Key,
        text: []const u8,
        mod: Modifiers,
    };

    pub const MouseEvent = union(enum) {
        press: MouseData,
        release: MouseData,
        drag: MouseData,
        motion: MouseData,
        scroll: ScrollData,

        pub fn mouse(self: MouseEvent) MouseData {
            return switch (self) {
                .press => |m| m,
                .release => |m| m,
                .drag => |m| m,
                .motion => |m| m,
                .scroll => |s| s.mouse,
            };
        }
    };

    pub const MouseData = struct {
        button: MouseButton,
        x: i32,
        y: i32,
        modifiers: Modifiers,
    };

    pub const ScrollData = struct {
        direction: ScrollDirection,
        mouse: MouseData,
    };

    pub const ScrollDirection = enum {
        up, down, left, right,
    };
};

/// Unified input parser combining enhanced mouse and keyboard handling
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
    pub fn parse(self: *InputParser, data: []const u8) ![]UnifiedEvent {
        try self.buffer.appendSlice(self.allocator, data);

        var events = std.ArrayListUnmanaged(UnifiedEvent){};
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
        event: UnifiedEvent,
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
            const key_event = try self.parseChar(first);
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

        const key_event = UnifiedEvent.KeyPressEvent{
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
                    var key_event = try self.parseChar(data[1]);
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
            if (try self.parseMouseEvent(final_char, params.items)) |mouse_event| {
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

    fn parseMouseEvent(_: *InputParser, final_char: u8, params: []const u32) !?UnifiedEvent.MouseEvent {
        if (params.len < 3) return null;

        const button_byte = params[0];
        const x = @as(i32, @intCast(params[1] - 1)); // 1-based to 0-based
        const y = @as(i32, @intCast(params[2] - 1)); // 1-based to 0-based

        // Decode button and modifiers
        const button = @as(MouseButton, @enumFromInt(button_byte & 0x3));
        const action = if (final_char == 'M') "press" else "release";
        const modifiers = Modifiers.fromMouseByte(button_byte);

        const mouse_data = UnifiedEvent.MouseData{
            .button = button,
            .x = x,
            .y = y,
            .modifiers = modifiers,
        };

        // Check for scroll events
        if (button_byte >= 64 and button_byte <= 67) {
            const direction: UnifiedEvent.ScrollDirection = switch (button_byte) {
                64 => .up,    // wheel up
                65 => .down,  // wheel down
                66 => .right, // wheel right
                67 => .left,  // wheel left
                else => return null,
            };

            return UnifiedEvent.MouseEvent{
                .scroll = .{
                    .direction = direction,
                    .mouse = mouse_data,
                },
            };
        }

        // Regular mouse event
        if (std.mem.eql(u8, action, "press")) {
            return UnifiedEvent.MouseEvent{ .press = mouse_data };
        } else if (std.mem.eql(u8, action, "release")) {
            return UnifiedEvent.MouseEvent{ .release = mouse_data };
        } else {
            return null;
        }
    }

    fn parseCSIKeyboard(self: *InputParser, _: []const u8, final_char: u8, params: []const u32) !?UnifiedEvent.KeyPressEvent {
        const text = try self.allocator.dupe(u8, "");

        const key: Key = switch (final_char) {
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
            } else .unknown,
            else => .unknown,
        };

        return UnifiedEvent.KeyPressEvent{
            .text = text,
            .code = key,
            .mod = .{},
        };
    }

    fn parseCSISpecial(_: *InputParser, _: []const u8, final_char: u8, params: []const u32) !?UnifiedEvent {
        return switch (final_char) {
            't' => {
                // Window operations
                if (params.len >= 3 and params[0] == 8) {
                    // Window size report
                    return UnifiedEvent{ .window_size = .{
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

        const key_event = try self.parseEscapeSequence(data[0..3]);
        if (key_event) |event| {
            return ParseResult{
                .event = .{ .key_press = event.event.key_press },
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
            const unknown_data = try self.allocator.dupe(u8, "title_change");
            return ParseResult{
                .event = .{ .unknown = unknown_data },
                .consumed = i + 1,
            };
        }

        if (std.mem.startsWith(u8, sequence, "\x1b]52;")) {
            // Clipboard operation - could be implemented later
            const unknown_data = try self.allocator.dupe(u8, "clipboard");
            return ParseResult{
                .event = .{ .unknown = unknown_data },
                .consumed = i + 1,
            };
        }

        const unknown_data = try self.allocator.dupe(u8, sequence);
        return ParseResult{
            .event = .{ .unknown = unknown_data },
            .consumed = i + 1,
        };
    }

    fn parseChar(self: *InputParser, ch: u8) !UnifiedEvent.KeyPressEvent {
        var text_buf: [1]u8 = undefined;

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

        text_buf[0] = ch;
        const text = try self.allocator.dupe(u8, text_buf[0..1]);

        return UnifiedEvent.KeyPressEvent{
            .text = text,
            .code = key,
            .mod = .{},
        };
    }
};

/// ============================================================================
/// UTILITY FUNCTIONS
/// ============================================================================

/// Utility functions for working with input events
pub const InputUtils = struct {
    /// Check if a key event matches specific criteria
    pub fn keyMatches(event: Event.KeyPressEvent, key: Key, modifiers: ?Modifiers) bool {
        if (event.key != key) return false;

        if (modifiers) |mods| {
            return std.meta.eql(event.modifiers, mods);
        }

        return true;
    }

    /// Get display text for a key event
    pub fn getKeyDisplayText(event: Event.KeyPressEvent) []const u8 {
        if (event.text) |text| {
            return text;
        }

        return event.key.getName();
    }

    /// Convert key combination to string representation
    pub fn keyComboToString(key: Key, modifiers: Modifiers) []const u8 {
        var buf: [64]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();

        if (modifiers.ctrl) writer.print("Ctrl+", .{}) catch {};
        if (modifiers.alt) writer.print("Alt+", .{}) catch {};
        if (modifiers.shift) writer.print("Shift+", .{}) catch {};
        if (modifiers.meta) writer.print("Meta+", .{}) catch {};
        if (modifiers.hyper) writer.print("Hyper+", .{}) catch {};
        if (modifiers.super) writer.print("Super+", .{}) catch {};

        const key_str = key.getName();
        writer.print("{s}", .{key_str}) catch {};

        return buf[0..fbs.pos];
    }

    /// Check if event is a mouse event
    pub fn isMouseEvent(event: Event) bool {
        return switch (event) {
            .mouse_press, .mouse_release, .mouse_move, .mouse_scroll => true,
            else => false,
        };
    }

    /// Check if event is a keyboard event
    pub fn isKeyboardEvent(event: Event) bool {
        return switch (event) {
            .key_press, .key_release => true,
            else => false,
        };
    }
};

// Tests
test "unified input system initialization" {
    var manager = try InputManager.init(std.testing.allocator, .{});
    defer manager.deinit();

    try std.testing.expect(!manager.raw_mode_enabled);
    try std.testing.expect(!manager.mouse_enabled);
}

test "input event conversion" {
    const allocator = std.testing.allocator;

    // Test key press conversion
    const unified_key = UnifiedEvent{
        .key_press = .{
            .code = .enter,
            .text = "enter",
            .mod = .{},
        },
    };

    var manager = try InputManager.init(std.testing.allocator, .{});
    defer manager.deinit();

    const converted = try manager.convertUnifiedEvent(unified_key);
    defer converted.deinit(allocator);

    try std.testing.expect(converted == .key_press);
    try std.testing.expect(converted.key_press.key == .enter);
    try std.testing.expectEqualStrings("enter", converted.key_press.text.?);
}

test "input utils" {
    const event = Event.KeyPressEvent{
        .key = .enter,
        .modifiers = .{ .ctrl = true },
    };

    try std.testing.expect(InputUtils.keyMatches(event, .enter, .{ .ctrl = true }));
    try std.testing.expect(!InputUtils.keyMatches(event, .enter, .{ .alt = true }));

    const display_text = InputUtils.getKeyDisplayText(event);
    try std.testing.expectEqualStrings("enter", display_text);
}
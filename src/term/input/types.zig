const std = @import("std");

// Modifier keys carried in mouse/key events.
pub const Modifiers = struct {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
};

// Buttons reported by terminal mouse tracking.
pub const MouseButton = enum {
    none,
    left,
    middle,
    right,
    wheel_up,
    wheel_down,
    wheel_left,
    wheel_right,
};

// High-level mouse action.
pub const MouseAction = enum {
    press,
    release,
    drag,
    move,
};

// MouseEvent decoded from SGR 1006/1016 reports.
pub const MouseEvent = struct {
    button: MouseButton,
    action: MouseAction,
    // Zero-based cell coordinates.
    x: u32,
    y: u32,
    // Optional pixel coordinates if SGR-pixel (1016) is enabled.
    pixel_x: ?u32 = null,
    pixel_y: ?u32 = null,
    mods: Modifiers = .{},
};

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

// Clipboard selection kinds.
pub const ClipboardSelection = enum { system, primary };

// ClipboardEvent decoded from OSC 52 read responses.
pub const ClipboardEvent = struct {
    content: []const u8,
    selection: ClipboardSelection = .system,
};

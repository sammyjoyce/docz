// Single source of truth for UI events.

pub const Event = union(enum) {
    Key: KeyEvent,
    Mouse: MouseEvent,
    Resize: ResizeEvent,
    Tick: u64, // monotonic ns
    Focus: bool,
    Custom: struct { tag: u32, payload: ?*anyopaque },
};

pub const KeyEvent = struct {
    code: KeyCode,
    mods: Modifiers = .{},
    ch: ?u21 = null, // for .char inputs
};

pub const KeyCode = enum {
    char,
    enter,
    escape,
    tab,
    backspace,
    delete,
    arrow_up,
    arrow_down,
    arrow_left,
    arrow_right,
    home,
    end,
    page_up,
    page_down,
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
};

pub const Modifiers = struct { ctrl: bool = false, alt: bool = false, shift: bool = false };

pub const MouseEvent = struct {
    x: u32,
    y: u32,
    button: MouseButton,
    action: MouseAction,
    mods: Modifiers = .{},
};

pub const MouseButton = enum { left, right, middle, wheel_up, wheel_down };
pub const MouseAction = enum { press, release, move, drag };

pub const ResizeEvent = struct { w: u32, h: u32 };

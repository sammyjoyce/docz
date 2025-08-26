/// Enhanced mouse event handling inspired by charmbracelet/x input module
/// Provides comprehensive mouse event types and parsing for modern terminal applications.
/// Compatible with Zig 0.15.1
const std = @import("std");

/// Key modifiers that can be held during mouse events
pub const KeyMod = packed struct(u8) {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
    meta: bool = false,
    hyper: bool = false,
    super: bool = false,
    _reserved: u2 = 0,

    pub fn contains(self: KeyMod, other: KeyMod) bool {
        const self_bits = @as(u8, @bitCast(self));
        const other_bits = @as(u8, @bitCast(other));
        return (self_bits & other_bits) == other_bits;
    }

    pub fn isEmpty(self: KeyMod) bool {
        return @as(u8, @bitCast(self)) == 0;
    }
};

/// Mouse button types based on X11 mouse button codes
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

    pub fn format(self: MouseButton, writer: *std.Io.Writer) !void {
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

/// Base mouse event structure
pub const Mouse = struct {
    x: i32,
    y: i32,
    button: MouseButton,
    mod: KeyMod,

    pub fn format(self: Mouse, writer: *std.Io.Writer) !void {
        if (self.mod.ctrl) try writer.print("ctrl+", .{});
        if (self.mod.alt) try writer.print("alt+", .{});
        if (self.mod.shift) try writer.print("shift+", .{});
        if (self.mod.meta) try writer.print("meta+", .{});
        if (self.mod.hyper) try writer.print("hyper+", .{});
        if (self.mod.super) try writer.print("super+", .{});

        try self.button.format(writer);
    }
};

/// Interface for all mouse events
pub const MouseEvent = union(enum) {
    click: MouseClickEvent,
    release: MouseReleaseEvent,
    wheel: MouseWheelEvent,
    motion: MouseMotionEvent,

    pub fn mouse(self: MouseEvent) Mouse {
        return switch (self) {
            .click => |e| Mouse(e),
            .release => |e| Mouse(e),
            .wheel => |e| Mouse(e),
            .motion => |e| Mouse(e),
        };
    }

    pub fn format(self: MouseEvent, writer: *std.Io.Writer) !void {
        switch (self) {
            .click => |e| try e.format(writer),
            .release => |e| try e.format(writer),
            .wheel => |e| try e.format(writer),
            .motion => |e| try e.format(writer),
        }
    }
};

/// Mouse button click event
pub const MouseClickEvent = Mouse;

/// Mouse button release event  
pub const MouseReleaseEvent = Mouse;

/// Mouse wheel event
pub const MouseWheelEvent = Mouse;

/// Mouse motion event
pub const MouseMotionEvent = Mouse;

/// Parse SGR-encoded mouse events
/// SGR extended mouse events look like: ESC [ < Cb ; Cx ; Cy (M or m)
/// where:
/// - Cb is the encoded button code
/// - Cx is the x-coordinate of the mouse
/// - Cy is the y-coordinate of the mouse
/// - M is for button press, m is for button release
pub fn parseSGRMouseEvent(cmd_final: u8, params: []const u32) ?MouseEvent {
    if (params.len < 3) return null;

    const cb = params[0];
    const x = @as(i32, @intCast(params[1])) - 1; // Convert to 0-based
    const y = @as(i32, @intCast(params[2])) - 1; // Convert to 0-based

    const release = cmd_final == 'm';
    const mod, const btn, const is_motion = parseMouseButton(cb);

    const m = Mouse{
        .x = x,
        .y = y,
        .button = btn,
        .mod = mod,
    };

    // Wheel buttons don't have release events
    if (isWheel(m.button)) {
        return MouseEvent{ .wheel = MouseWheelEvent(m) };
    } else if (!is_motion and release) {
        return MouseEvent{ .release = MouseReleaseEvent(m) };
    } else if (is_motion) {
        return MouseEvent{ .motion = MouseMotionEvent(m) };
    }
    
    return MouseEvent{ .click = MouseClickEvent(m) };
}

/// Parse X10-encoded mouse events (legacy format)
/// X10 mouse events look like: ESC [M Cb Cx Cy
const x10_mouse_byte_offset = 32;

pub fn parseX10MouseEvent(buf: []const u8) ?MouseEvent {
    if (buf.len < 6) return null; // ESC [M + 3 bytes

    const v = buf[3..6];
    var b = @as(i32, v[0]);
    if (b >= x10_mouse_byte_offset) {
        b -= x10_mouse_byte_offset;
    }

    const mod, const btn, const is_release, const is_motion = parseMouseButtonX10(@as(u32, @intCast(b)));

    // Convert to 0-based coordinates  
    const x = @as(i32, v[1]) - x10_mouse_byte_offset - 1;
    const y = @as(i32, v[2]) - x10_mouse_byte_offset - 1;

    const m = Mouse{
        .x = x,
        .y = y,
        .button = btn,
        .mod = mod,
    };

    if (isWheel(m.button)) {
        return MouseEvent{ .wheel = MouseWheelEvent(m) };
    } else if (is_motion) {
        return MouseEvent{ .motion = MouseMotionEvent(m) };
    } else if (is_release) {
        return MouseEvent{ .release = MouseReleaseEvent(m) };
    }
    
    return MouseEvent{ .click = MouseClickEvent(m) };
}

/// Parse mouse button encoding for SGR format
fn parseMouseButton(b: u32) struct { KeyMod, MouseButton, bool } {
    // Mouse bit shifts
    const bit_shift = 0b0000_0100;
    const bit_alt = 0b0000_1000;
    const bit_ctrl = 0b0001_0000;
    const bit_motion = 0b0010_0000;
    const bit_wheel = 0b0100_0000;
    const bit_add = 0b1000_0000; // Additional buttons 8-11
    const bits_mask = 0b0000_0011;

    // Parse modifiers
    var mod = KeyMod{};
    if ((b & bit_alt) != 0) mod.alt = true;
    if ((b & bit_ctrl) != 0) mod.ctrl = true;
    if ((b & bit_shift) != 0) mod.shift = true;

    // Parse button
    var btn: MouseButton = .none;
    if ((b & bit_add) != 0) {
        btn = @enumFromInt(@intFromEnum(MouseButton.backward) + (b & bits_mask));
    } else if ((b & bit_wheel) != 0) {
        btn = @enumFromInt(@intFromEnum(MouseButton.wheel_up) + (b & bits_mask));
    } else {
        btn = @enumFromInt(@intFromEnum(MouseButton.left) + (b & bits_mask));
    }

    // Check for motion
    const is_motion = (b & bit_motion) != 0 and !isWheel(btn);

    return .{ mod, btn, is_motion };
}

/// Parse mouse button encoding for X10 format  
fn parseMouseButtonX10(b: u32) struct { KeyMod, MouseButton, bool, bool } {
    const bit_shift = 0b0000_0100;
    const bit_alt = 0b0000_1000;
    const bit_ctrl = 0b0001_0000;
    const bit_motion = 0b0010_0000;
    const bit_wheel = 0b0100_0000;
    const bit_add = 0b1000_0000;
    const bits_mask = 0b0000_0011;

    // Parse modifiers
    var mod = KeyMod{};
    if ((b & bit_alt) != 0) mod.alt = true;
    if ((b & bit_ctrl) != 0) mod.ctrl = true;
    if ((b & bit_shift) != 0) mod.shift = true;

    // Parse button
    var btn: MouseButton = .none;
    var is_release = false;
    
    if ((b & bit_add) != 0) {
        btn = @enumFromInt(@intFromEnum(MouseButton.backward) + (b & bits_mask));
    } else if ((b & bit_wheel) != 0) {
        btn = @enumFromInt(@intFromEnum(MouseButton.wheel_up) + (b & bits_mask));
    } else {
        btn = @enumFromInt(@intFromEnum(MouseButton.left) + (b & bits_mask));
        // X10 reports button release as 0b0000_0011 (3)
        if ((b & bits_mask) == bits_mask) {
            btn = .none;
            is_release = true;
        }
    }

    // Motion bit doesn't get reported for wheel events
    const is_motion = (b & bit_motion) != 0 and !isWheel(btn);

    return .{ mod, btn, is_release, is_motion };
}

/// Check if button is a wheel event
fn isWheel(btn: MouseButton) bool {
    return @intFromEnum(btn) >= @intFromEnum(MouseButton.wheel_up) and 
           @intFromEnum(btn) <= @intFromEnum(MouseButton.wheel_right);
}

// Tests
test "SGR mouse click parsing" {
    const params = [_]u32{ 0, 12, 5 }; // Left button at (11, 4) zero-based
    const event = parseSGRMouseEvent('M', &params);
    
    try std.testing.expect(event != null);
    try std.testing.expect(event.? == .click);
    
    const m = event.?.mouse();
    try std.testing.expectEqual(@as(i32, 11), m.x);
    try std.testing.expectEqual(@as(i32, 4), m.y);
    try std.testing.expectEqual(MouseButton.left, m.button);
}

test "SGR mouse wheel parsing" {
    const params = [_]u32{ 64, 5, 6 }; // Wheel up at (4, 5) zero-based
    const event = parseSGRMouseEvent('M', &params);
    
    try std.testing.expect(event != null);
    try std.testing.expect(event.? == .wheel);
    
    const m = event.?.mouse();
    try std.testing.expectEqual(MouseButton.wheel_up, m.button);
}

test "SGR mouse release parsing" {
    const params = [_]u32{ 0, 3, 9 }; // Left button release
    const event = parseSGRMouseEvent('m', &params);
    
    try std.testing.expect(event != null);
    try std.testing.expect(event.? == .release);
    
    const m = event.?.mouse();
    try std.testing.expectEqual(MouseButton.left, m.button);
}

test "modifier key parsing" {
    const params = [_]u32{ 0x04 | 0x08 | 0x10, 1, 1 }; // Shift + Alt + Ctrl
    const event = parseSGRMouseEvent('M', &params);
    
    try std.testing.expect(event != null);
    
    const m = event.?.mouse();
    try std.testing.expect(m.mod.shift);
    try std.testing.expect(m.mod.alt); 
    try std.testing.expect(m.mod.ctrl);
}
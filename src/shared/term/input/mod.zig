//! Terminal input handling module.
//! Provides keyboard, mouse, and clipboard input management with advanced
//! event handling and cross-platform support.
//!
//! This module now serves as a compatibility layer that re-exports the unified
//! input system from src/shared/input.zig for backward compatibility.

const std = @import("std");

// Re-export unified input system
pub const input = @import("../../input.zig");

// Re-export all unified types for convenience
pub const Event = input.Event;
pub const Key = input.Key;
pub const Modifiers = input.Modifiers;
pub const MouseButton = input.MouseButton;
pub const MouseMode = input.MouseMode;
pub const InputManager = input.InputManager;
pub const InputConfig = input.InputConfig;
pub const InputFeatures = input.InputFeatures;
pub const InputParser = input.InputParser;
pub const InputUtils = input.InputUtils;

// Legacy compatibility - keep existing module exports for backward compatibility
pub const input_extended = @import("input_extended.zig");
pub const input_handler = @import("input_handler.zig");
pub const input_parser = @import("input_parser.zig");
pub const input_driver = @import("input_driver.zig");
pub const keyboard = @import("keyboard.zig");
pub const keys = @import("keys.zig");
pub const key_mapping = @import("key_mapping.zig");
pub const kitty_keyboard = @import("kitty_keyboard.zig");
pub const mouse = @import("mouse.zig");
pub const clipboard = @import("clipboard.zig");
pub const cursor = @import("cursor.zig");

// Legacy event types for backward compatibility
pub const EventType = enum {
    key_press,
    key_release,
    mouse_move,
    mouse_button,
    mouse_wheel,
    clipboard_paste,
    resize,
    focus,
    blur,
};

/// Legacy key event data (for backward compatibility)
pub const KeyEvent = struct {
    code: u32,
    modifiers: Modifiers,
    text: ?[]const u8 = null,
};

/// Legacy mouse move event data
pub const MouseMoveEvent = struct {
    x: i32,
    y: i32,
    modifiers: Modifiers,
};

/// Legacy mouse button event data
pub const MouseButtonEvent = struct {
    button: MouseButton,
    pressed: bool,
    x: i32,
    y: i32,
    modifiers: Modifiers,
};

/// Legacy mouse wheel event data
pub const MouseWheelEvent = struct {
    delta_x: f32,
    delta_y: f32,
    x: i32,
    y: i32,
    modifiers: Modifiers,
};

/// Legacy clipboard event data
pub const ClipboardEvent = struct {
    text: []const u8,
};

/// Legacy window resize event data
pub const ResizeEvent = struct {
    width: u32,
    height: u32,
};

/// Legacy input handler interface (for backward compatibility)
pub const InputHandler = struct {
    allocator: std.mem.Allocator,
    unified_manager: InputManager,

    /// Initialize input handler
    pub fn init(allocator: std.mem.Allocator) !InputHandler {
        const config = InputConfig{};
        const manager = try InputManager.init(allocator, config);
        return InputHandler{
            .allocator = allocator,
            .unified_manager = manager,
        };
    }

    /// Poll for input events
    pub fn pollEvent(self: *InputHandler) ?Event {
        const unified_event = self.unified_manager.pollEvent() orelse return null;
        return convertToLegacyEvent(unified_event);
    }

    /// Wait for next input event
    pub fn waitEvent(self: *InputHandler) !Event {
        const unified_event = try self.unified_manager.nextEvent();
        return convertToLegacyEvent(unified_event) orelse error.InvalidInput;
    }

    /// Cleanup input handler
    pub fn deinit(self: *InputHandler) void {
        self.unified_manager.deinit();
    }
};

/// Convert unified event to legacy event format
fn convertToLegacyEvent(unified: input.Event) ?Event {
    return switch (unified) {
        .key_press => |key| Event{
            .type = .key_press,
            .timestamp = key.timestamp,
            .data = .{
                .key_press = KeyEvent{
                    .code = @intFromEnum(key.key),
                    .modifiers = key.modifiers,
                    .text = key.text,
                },
            },
        },
        .key_release => |key| Event{
            .type = .key_release,
            .timestamp = key.timestamp,
            .data = .{
                .key_release = KeyEvent{
                    .code = @intFromEnum(key.key),
                    .modifiers = key.modifiers,
                    .text = null,
                },
            },
        },
        .mouse_press => |mouse_press| Event{
            .type = .mouse_button,
            .timestamp = mouse_press.timestamp,
            .data = .{
                .mouse_button = MouseButtonEvent{
                    .button = mouse_press.button,
                    .pressed = true,
                    .x = @as(i32, @intCast(mouse_press.x)),
                    .y = @as(i32, @intCast(mouse_press.y)),
                    .modifiers = mouse_press.modifiers,
                },
            },
        },
        .mouse_release => |mouse_release| Event{
            .type = .mouse_button,
            .timestamp = mouse_release.timestamp,
            .data = .{
                .mouse_button = MouseButtonEvent{
                    .button = mouse_release.button,
                    .pressed = false,
                    .x = @as(i32, @intCast(mouse_release.x)),
                    .y = @as(i32, @intCast(mouse_release.y)),
                    .modifiers = mouse_release.modifiers,
                },
            },
        },
        .mouse_move => |mouse_move| Event{
            .type = .mouse_move,
            .timestamp = mouse_move.timestamp,
            .data = .{
                .mouse_move = MouseMoveEvent{
                    .x = @as(i32, @intCast(mouse_move.x)),
                    .y = @as(i32, @intCast(mouse_move.y)),
                    .modifiers = mouse_move.modifiers,
                },
            },
        },
        .mouse_scroll => |mouse_scroll| Event{
            .type = .mouse_wheel,
            .timestamp = mouse_scroll.timestamp,
            .data = .{
                .mouse_wheel = MouseWheelEvent{
                    .delta_x = mouse_scroll.delta_x,
                    .delta_y = mouse_scroll.delta_y,
                    .x = @as(i32, @intCast(mouse_scroll.x)),
                    .y = @as(i32, @intCast(mouse_scroll.y)),
                    .modifiers = mouse_scroll.modifiers,
                },
            },
        },
        .paste => |paste| Event{
            .type = .clipboard_paste,
            .timestamp = paste.timestamp,
            .data = .{
                .clipboard_paste = ClipboardEvent{
                    .text = paste.text,
                },
            },
        },
        .resize => |resize| Event{
            .type = .resize,
            .timestamp = resize.timestamp,
            .data = .{
                .resize = ResizeEvent{
                    .width = resize.width,
                    .height = resize.height,
                },
            },
        },
        .focus_gained => Event{
            .type = .focus,
            .timestamp = std.time.microTimestamp(),
            .data = .focus,
        },
        .focus_lost => Event{
            .type = .blur,
            .timestamp = std.time.microTimestamp(),
            .data = .blur,
        },
    };
}

test "input module exports" {
    // Basic test to ensure module compiles
    std.testing.refAllDecls(@This());
}

//! Terminal input handling module.
//! Provides keyboard, mouse, and clipboard input management with advanced
//! event handling and cross-platform support.

const std = @import("std");

// Core input functionality
pub const enhanced_input = @import("enhanced_input.zig");
pub const enhanced_input_handler = @import("enhanced_input_handler.zig");
pub const enhanced_input_parser = @import("enhanced_input_parser.zig");
pub const advanced_input_driver = @import("advanced_input_driver.zig");

// Import for event parsing
const enhanced_input_parser_mod = @import("enhanced_input_parser.zig");

// Keyboard handling
pub const enhanced_keyboard = @import("enhanced_keyboard.zig");
pub const enhanced_keys = @import("enhanced_keys.zig");
pub const key_mapping = @import("key_mapping.zig");
// Kitty keyboard support
pub const kitty_keyboard = @import("kitty_keyboard.zig");

// Mouse handling
pub const enhanced_mouse = @import("enhanced_mouse.zig");
// TODO: Implement mouse events and tracker
// pub const mouse_events = @import("mouse_events.zig");
// pub const mouse_tracker = @import("mouse_tracker.zig");

// Clipboard support
pub const clipboard = @import("clipboard.zig");

// Event system
// TODO: Implement input events and color events
// pub const input_events = @import("input_events.zig");
// pub const color_events = @import("color_events.zig");

// Cursor input
pub const cursor = @import("cursor.zig");

/// Input event types
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

/// Generic input event structure
pub const Event = struct {
    type: EventType,
    timestamp: i64,
    data: union(EventType) {
        key_press: KeyEvent,
        key_release: KeyEvent,
        mouse_move: MouseMoveEvent,
        mouse_button: MouseButtonEvent,
        mouse_wheel: MouseWheelEvent,
        clipboard_paste: ClipboardEvent,
        resize: ResizeEvent,
        focus: void,
        blur: void,
    },
};

/// Key event data
pub const KeyEvent = struct {
    code: u32,
    modifiers: Modifiers,
    text: ?[]const u8 = null,
};

/// Mouse move event data
pub const MouseMoveEvent = struct {
    x: i32,
    y: i32,
    modifiers: Modifiers,
};

/// Mouse button event data
pub const MouseButtonEvent = struct {
    button: MouseButton,
    pressed: bool,
    x: i32,
    y: i32,
    modifiers: Modifiers,
};

/// Mouse wheel event data
pub const MouseWheelEvent = struct {
    delta_x: f32,
    delta_y: f32,
    x: i32,
    y: i32,
    modifiers: Modifiers,
};

/// Clipboard event data
pub const ClipboardEvent = struct {
    text: []const u8,
};

/// Window resize event data
pub const ResizeEvent = struct {
    width: u32,
    height: u32,
};

/// Modifier keys state
pub const Modifiers = struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    meta: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,
};

/// Mouse button enumeration
pub const MouseButton = enum {
    left,
    middle,
    right,
    button4,
    button5,
};

/// Input handler interface
pub const InputHandler = struct {
    allocator: std.mem.Allocator,

    /// Initialize input handler
    pub fn init(allocator: std.mem.Allocator) !InputHandler {
        return InputHandler{
            .allocator = allocator,
        };
    }

    /// Poll for input events
    pub fn pollEvent(self: *InputHandler) ?Event {
        // Try to read available input without blocking
        const stdin = std.fs.File.stdin();
        var buffer: [1024]u8 = undefined;

        const bytes_read = stdin.read(&buffer) catch return null;
        if (bytes_read == 0) return null;

        const input = buffer[0..bytes_read];
        return self.parseInput(input);
    }

    /// Wait for next input event
    pub fn waitEvent(self: *InputHandler) !Event {
        // Block until input is available
        const stdin = std.fs.File.stdin();
        var buffer: [1]u8 = undefined;

        // Read at least one byte to ensure we have input
        const bytes_read = try stdin.read(&buffer);
        if (bytes_read == 0) return error.EndOfStream;

        // Read more data if available
        var input_buffer = std.ArrayList(u8).init(self.allocator);
        defer input_buffer.deinit();

        try input_buffer.appendSlice(buffer[0..bytes_read]);

        // Try to read more data without blocking
        while (true) {
            const additional_bytes = stdin.read(&buffer) catch break;
            if (additional_bytes == 0) break;
            try input_buffer.appendSlice(buffer[0..additional_bytes]);
        }

        const event = self.parseInput(input_buffer.items);
        return event orelse error.InvalidInput;
    }

    /// Parse raw input bytes into an event
    fn parseInput(self: *InputHandler, input: []const u8) ?Event {
        // Use enhanced input parser for complex sequences
        var parser = enhanced_input_parser_mod.EnhancedInputParser.init(self.allocator);
        defer parser.deinit();

        const events = parser.parseSequence(input) catch return null;
        defer self.allocator.free(events);

        if (events.len == 0) return null;

        // Convert first event to our Event type
        const first_event = events[0];
        return switch (first_event) {
            .key_press => |key| Event{
                .type = .key_press,
                .timestamp = std.time.microTimestamp(),
                .data = .{
                    .key_press = KeyEvent{
                        .code = 0, // TODO: Map key to code
                        .modifiers = Modifiers{
                            .shift = key.modifiers.shift,
                            .ctrl = key.modifiers.ctrl,
                            .alt = key.modifiers.alt,
                            .meta = key.modifiers.meta,
                        },
                        .text = if (key.key.len == 1) key.key else null,
                    },
                },
            },
            .mouse => |mouse| Event{
                .type = .mouse_button,
                .timestamp = std.time.microTimestamp(),
                .data = .{ .mouse_button = MouseButtonEvent{
                    .button = switch (mouse.button) {
                        .left => .left,
                        .middle => .middle,
                        .right => .right,
                        else => .left,
                    },
                    .pressed = mouse.action == .press,
                    .x = mouse.x,
                    .y = mouse.y,
                    .modifiers = Modifiers{
                        .shift = mouse.modifiers.shift,
                        .ctrl = mouse.modifiers.ctrl,
                        .alt = mouse.modifiers.alt,
                    },
                } },
            },
            .paste => |paste| Event{
                .type = .clipboard_paste,
                .timestamp = std.time.microTimestamp(),
                .data = .{ .clipboard_paste = ClipboardEvent{
                    .text = paste.content,
                } },
            },
            else => null,
        };
    }

    /// Cleanup input handler
    pub fn deinit(self: *InputHandler) void {
        _ = self;
        // Cleanup resources
    }
};

test "input module exports" {
    // Basic test to ensure module compiles
    std.testing.refAllDecls(@This());
}

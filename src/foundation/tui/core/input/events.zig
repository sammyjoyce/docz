//! Event handling system for TUI components
//! Uses the foundation input system for comprehensive input support
const std = @import("std");
const shared = @import("../../../mod.zig");
const shared_input = shared.components.input;

// Re-export shared input types
pub const InputEvent = shared_input.Event;
pub const InputManager = shared_input.InputManager;
pub const InputConfig = shared_input.InputConfig;
pub const InputFeatures = shared_input.InputFeatures;
pub const Key = shared_input.Key;
pub const Modifiers = shared_input.Modifiers;

/// TUI event system with comprehensive input support
pub const EventSystem = struct {
    allocator: std.mem.Allocator,
    input_manager: InputManager,
    focus_handlers: std.ArrayListUnmanaged(FocusHandler),
    paste_handlers: std.ArrayListUnmanaged(PasteHandler),
    window_resize_handlers: std.ArrayListUnmanaged(WindowResizeHandler),
    keyboard_handlers: std.ArrayListUnmanaged(KeyboardHandler),
    mouse_handlers: std.ArrayListUnmanaged(MouseHandler),

    pub fn init(allocator: std.mem.Allocator, config: InputConfig) !EventSystem {
        const input_manager = try InputManager.init(allocator, config);
        return EventSystem{
            .allocator = allocator,
            .input_manager = input_manager,
            .focus_handlers = std.ArrayListUnmanaged(FocusHandler){},
            .paste_handlers = std.ArrayListUnmanaged(PasteHandler){},
            .window_resize_handlers = std.ArrayListUnmanaged(WindowResizeHandler){},
            .keyboard_handlers = std.ArrayListUnmanaged(KeyboardHandler){},
            .mouse_handlers = std.ArrayListUnmanaged(MouseHandler){},
        };
    }

    pub fn deinit(self: *EventSystem) void {
        self.input_manager.deinit();
        self.focus_handlers.deinit(self.allocator);
        self.paste_handlers.deinit(self.allocator);
        self.window_resize_handlers.deinit(self.allocator);
        self.keyboard_handlers.deinit(self.allocator);
        self.mouse_handlers.deinit(self.allocator);
    }

    /// Process raw input data and dispatch events
    pub fn processInput(self: *EventSystem, data: []const u8) !void {
        try self.input_manager.processInput(data);

        // Process any queued events
        while (self.input_manager.pollEvent()) |event| {
            try self.dispatchEvent(event);
        }
    }

    /// Enable input features
    pub fn enableFeatures(self: *EventSystem) !void {
        try self.input_manager.enableFeatures();
    }

    /// Read next event (blocking)
    pub fn nextEvent(self: *EventSystem) !InputEvent {
        return try self.input_manager.nextEvent();
    }

    /// Poll for events
    pub fn pollEvent(self: *EventSystem) ?InputEvent {
        return self.input_manager.pollEvent();
    }

    fn dispatchEvent(self: *EventSystem, event: InputEvent) !void {
        switch (event) {
            .key_press => |key_event| {
                for (self.keyboard_handlers.items) |handler| {
                    if (handler.func(.{ .key_press = key_event })) break;
                }
            },
            .key_release => |key_event| {
                for (self.keyboard_handlers.items) |handler| {
                    if (handler.func(.{ .key_release = key_event })) break;
                }
            },
            .mouse_press, .mouse_release, .mouse_move, .mouse_scroll => {
                for (self.mouse_handlers.items) |handler| {
                    if (handler.func(event)) break;
                }
            },
            .focus_gained => {
                for (self.focus_handlers.items) |handler| {
                    handler.func(true);
                }
            },
            .focus_lost => {
                for (self.focus_handlers.items) |handler| {
                    handler.func(false);
                }
            },
            .paste => |paste_event| {
                for (self.paste_handlers.items) |handler| {
                    handler.func(paste_event.text);
                }
            },
            .resize => |resize_event| {
                for (self.window_resize_handlers.items) |handler| {
                    handler.func(resize_event.width, resize_event.height);
                }
            },
        }
    }

    /// Register focus event handler
    pub fn addFocusHandler(self: *EventSystem, handler: FocusHandler) !void {
        try self.focus_handlers.append(self.allocator, handler);
    }

    /// Register paste event handler
    pub fn addPasteHandler(self: *EventSystem, handler: PasteHandler) !void {
        try self.paste_handlers.append(self.allocator, handler);
    }

    /// Register window resize handler
    pub fn addWindowResizeHandler(self: *EventSystem, handler: WindowResizeHandler) !void {
        try self.window_resize_handlers.append(self.allocator, handler);
    }

    /// Register keyboard event handler
    pub fn addKeyboardHandler(self: *EventSystem, handler: KeyboardHandler) !void {
        try self.keyboard_handlers.append(self.allocator, handler);
    }

    /// Register mouse event handler
    pub fn addMouseHandler(self: *EventSystem, handler: MouseHandler) !void {
        try self.mouse_handlers.append(self.allocator, handler);
    }

    /// Get current focus state
    pub fn hasFocus(self: *const EventSystem) bool {
        // With the unified input system, focus state is handled through events
        // This is a placeholder implementation
        _ = self;
        return true;
    }

    /// Check if currently in bracketed paste mode
    pub fn isPasting(self: *const EventSystem) bool {
        // With the unified input system, paste state is handled through events
        // This is a placeholder implementation
        _ = self;
        return false;
    }
};

/// Rich event types for handlers
pub const RichKeyEvent = union(enum) {
    key_press: shared_input.Event.KeyPressEvent,
    key_release: shared_input.Event.KeyReleaseEvent,
};

/// Handler function types
pub const FocusHandler = struct {
    func: *const fn (has_focus: bool) void,
};

pub const PasteHandler = struct {
    func: *const fn (content: []const u8) void,
};

pub const WindowResizeHandler = struct {
    func: *const fn (width: u32, height: u32) void,
};

pub const KeyboardHandler = struct {
    func: *const fn (event: RichKeyEvent) bool, // Returns true if handled
};

pub const MouseHandler = struct {
    func: *const fn (event: InputEvent) bool, // Returns true if handled
};

/// Utility functions for backward compatibility with existing TUI widgets
pub const Compat = struct {
    /// Convert key event to legacy key event (for backward compatibility)
    pub fn toLegacyKeyEvent(event: shared_input.Event.KeyPressEvent) ?@import("../events.zig").KeyEvent {
        const legacy_events = @import("../events.zig");

        const key: legacy_events.KeyEvent.Key = switch (event.code) {
            .escape => .escape,
            .enter => .enter,
            .tab => .tab,
            .backspace => .backspace,
            .delete_key => .delete,
            .up => .arrow_up,
            .down => .arrow_down,
            .left => .arrow_left,
            .right => .arrow_right,
            .f1 => .f1,
            .f2 => .f2,
            .f3 => .f3,
            .f4 => .f4,
            .f5 => .f5,
            .f6 => .f6,
            .f7 => .f7,
            .f8 => .f8,
            .f9 => .f9,
            .f10 => .f10,
            .f11 => .f11,
            .f12 => .f12,
            .home => .home,
            .end => .end,
            .page_up => .page_up,
            .page_down => .page_down,
            .insert_key => .insert,
            else => {
                // Try to extract character from text
                if (event.text.len == 1) {
                    return legacy_events.KeyEvent{
                        .key = .character,
                        .character = event.text[0],
                        .modifiers = .{
                            .ctrl = event.mod.ctrl,
                            .shift = event.mod.shift,
                            .alt = event.mod.alt,
                            .super = event.mod.super,
                        },
                    };
                }
                return null;
            },
        };

        return legacy_events.KeyEvent{
            .key = key,
            .modifiers = .{
                .ctrl = event.mod.ctrl,
                .shift = event.mod.shift,
                .alt = event.mod.alt,
                .super = event.mod.super,
            },
        };
    }

    /// Convert mouse event to legacy mouse event (for backward compatibility)
    pub fn toLegacyMouseEvent(event: shared_input.Event) ?@import("../events.zig").MouseEvent {
        const legacy_events = @import("../events.zig");

        const button: legacy_events.MouseEvent.Button = switch (event) {
            .mouse_press => |m| switch (m.button) {
                .left => .left,
                .right => .right,
                .middle => .middle,
                else => return null,
            },
            .mouse_release => |m| switch (m.button) {
                .left => .left,
                .right => .right,
                .middle => .middle,
                else => return null,
            },
            .mouse_scroll => |s| if (s.delta_y > 0) .scroll_up else .scroll_down,
            else => return null,
        };

        const action: legacy_events.MouseEvent.Action = switch (event) {
            .mouse_press => .press,
            .mouse_release => .release,
            .mouse_move => .drag,
            .mouse_scroll => .scroll,
            else => return null,
        };

        // Extract position and modifiers from the shared event
        const x, const y, const modifiers = switch (event) {
            .mouse_press => |m| .{ m.x, m.y, m.modifiers },
            .mouse_release => |m| .{ m.x, m.y, m.modifiers },
            .mouse_move => |m| .{ m.x, m.y, m.modifiers },
            .mouse_scroll => |m| .{ m.x, m.y, m.modifiers },
            else => return null,
        };

        return legacy_events.MouseEvent{
            .button = button,
            .action = action,
            .x = x,
            .y = y,
            .modifiers = .{
                .ctrl = modifiers.ctrl,
                .shift = modifiers.shift,
                .alt = modifiers.alt,
            },
        };
    }
};

// Tests
test "enhanced event system initialization" {
    const config = InputConfig{};
    var event_system = try EventSystem.init(std.testing.allocator, config);
    defer event_system.deinit();

    try std.testing.expect(event_system.hasFocus());
    try std.testing.expect(!event_system.isPasting());
}

test "focus event handling" {
    const config = InputConfig{};
    var event_system = try EventSystem.init(std.testing.allocator, config);
    defer event_system.deinit();

    const TestContext = struct {
        focus_received: bool = false,

        fn handle(ctx: *@This(), has_focus: bool) void {
            _ = has_focus;
            ctx.focus_received = true;
        }
    };

    var test_ctx = TestContext{};
    _ = &test_ctx; // Make it mutable

    const handler = FocusHandler{
        .func = struct {
            fn handle(has_focus: bool) void {
                _ = has_focus;
                // Just a placeholder handler for testing registration
            }
        }.handle,
    };

    try event_system.addFocusHandler(handler);

    // Test handler registration
    try std.testing.expect(event_system.focus_handlers.items.len == 1);
}

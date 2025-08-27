//! Enhanced event handling system for TUI components
//! Uses the unified input system from @src/shared/components for comprehensive input support
const std = @import("std");
const components_mod = @import("../../../components/mod.zig");

// Re-export unified input types
pub const InputEvent = components_mod.InputEvent;
pub const InputManager = components_mod.InputManager;
pub const InputConfig = components_mod.InputConfig;
pub const InputFeatures = components_mod.InputFeatures;
pub const Key = components_mod.Key;
pub const Modifiers = components_mod.Modifiers;

/// Enhanced TUI event system with comprehensive input support
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
        return self.has_focus;
    }

    /// Check if currently in bracketed paste mode
    pub fn isPasting(self: *const EventSystem) bool {
        return self.is_pasting;
    }
};

/// Rich event types for handlers
pub const RichKeyEvent = union(enum) {
    key_press: InputEvent.KeyPressEvent,
    key_release: InputEvent.KeyReleaseEvent,
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
    /// Convert enhanced key event to legacy key event (for backward compatibility)
    pub fn toLegacyKeyEvent(enhanced: InputEvent.KeyPressEvent) ?@import("../events.zig").KeyEvent {
        const legacy_events = @import("../events.zig");

        const key: legacy_events.KeyEvent.Key = switch (enhanced.code) {
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
                if (enhanced.text.len == 1) {
                    return legacy_events.KeyEvent{
                        .key = .character,
                        .character = enhanced.text[0],
                        .modifiers = .{
                            .ctrl = enhanced.mod.ctrl,
                            .shift = enhanced.mod.shift,
                            .alt = enhanced.mod.alt,
                            .super = enhanced.mod.super,
                        },
                    };
                }
                return null;
            },
        };

        return legacy_events.KeyEvent{
            .key = key,
            .modifiers = .{
                .ctrl = enhanced.mod.ctrl,
                .shift = enhanced.mod.shift,
                .alt = enhanced.mod.alt,
                .super = enhanced.mod.super,
            },
        };
    }

    /// Convert enhanced mouse event to legacy mouse event (for backward compatibility)
    pub fn toLegacyMouseEvent(enhanced: InputEvent) ?@import("../events.zig").MouseEvent {
        const legacy_events = @import("../events.zig");
        const mouse = enhanced.mouse();

        const button: legacy_events.MouseEvent.Button = switch (enhanced) {
            .mouse => |m| switch (m.button) {
                .left => .left,
                .right => .right,
                .middle => .middle,
                else => return null,
            },
            .scroll => |s| if (s.direction == .up) .scroll_up else .scroll_down,
            else => return null,
        };

        const action: legacy_events.MouseEvent.Action = switch (enhanced) {
            .mouse => |m| switch (m.action) {
                .press => .press,
                .release => .release,
                .drag => .drag,
            },
            .scroll => .scroll,
            else => return null,
        };

        return legacy_events.MouseEvent{
            .button = button,
            .action = action,
            .x = @as(u32, @intCast(mouse.x)),
            .y = @as(u32, @intCast(mouse.y)),
            .modifiers = .{
                .ctrl = mouse.modifiers.ctrl,
                .shift = mouse.modifiers.shift,
                .alt = mouse.modifiers.alt,
            },
        };
    }
};

// Tests
test "enhanced event system initialization" {
    var event_system = EventSystem.init(std.testing.allocator);
    defer event_system.deinit();

    try std.testing.expect(event_system.hasFocus());
    try std.testing.expect(!event_system.isPasting());
}

test "focus event handling" {
    var event_system = EventSystem.init(std.testing.allocator);
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

//! Enhanced mouse event handling for TUI applications
//! Provides pixel-precise mouse tracking and rich interaction support
const std = @import("std");
const shared = @import("../../../mod.zig");
const unified_input = shared.components.input;
const term_mouse = unified_input;
const caps_mod = @import("term_shared").capabilities;

// Re-export unified mouse types
pub const MouseButton = unified_input.MouseButton;
pub const MouseMode = unified_input.MouseMode;
pub const UnifiedMouse = unified_input.Mouse;

// Re-export legacy mouse types for backward compatibility
pub const MouseEvent = unified_input.MouseEvent;
pub const MouseAction = unified_input.MouseAction;
pub const MouseProtocol = caps_mod.MouseProtocol;

/// Rich mouse controller with pixel precision support
pub const TUIMouse = struct {
    handlers: std.ArrayListUnmanaged(MouseHandler),
    click_handlers: std.ArrayListUnmanaged(ClickHandler),
    drag_handlers: std.ArrayListUnmanaged(DragHandler),
    scroll_handlers: std.ArrayListUnmanaged(ScrollHandler),
    allocator: std.mem.Allocator,

    // Mouse state tracking
    last_click_pos: ?Position = null,
    last_click_time: i64 = 0,
    is_dragging: bool = false,
    drag_start_pos: ?Position = null,

    // Configuration
    double_click_threshold_ms: i64 = 300,
    drag_threshold_pixels: u32 = 3,

    pub fn init(allocator: std.mem.Allocator) TUIMouse {
        return TUIMouse{
            .handlers = std.ArrayListUnmanaged(MouseHandler){},
            .click_handlers = std.ArrayListUnmanaged(ClickHandler){},
            .drag_handlers = std.ArrayListUnmanaged(DragHandler){},
            .scroll_handlers = std.ArrayListUnmanaged(ScrollHandler){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TUIMouse) void {
        self.handlers.deinit(self.allocator);
        self.click_handlers.deinit(self.allocator);
        self.drag_handlers.deinit(self.allocator);
        self.scroll_handlers.deinit(self.allocator);
    }

    /// Register general mouse event handler
    pub fn addHandler(self: *TUIMouse, handler: MouseHandler) !void {
        try self.handlers.append(self.allocator, handler);
    }

    /// Register click-specific handler
    pub fn addClickHandler(self: *TUIMouse, handler: ClickHandler) !void {
        try self.click_handlers.append(self.allocator, handler);
    }

    /// Register drag-specific handler
    pub fn addDragHandler(self: *TUIMouse, handler: DragHandler) !void {
        try self.drag_handlers.append(self.allocator, handler);
    }

    /// Register scroll-specific handler
    pub fn addScrollHandler(self: *TUIMouse, handler: ScrollHandler) !void {
        try self.scroll_handlers.append(self.allocator, handler);
    }

    /// Process mouse event and dispatch to appropriate handlers
    pub fn processMouseEvent(self: *TUIMouse, event: unified_input.Event) !void {
        const now = std.time.milliTimestamp();

        // Dispatch to general handlers first
        for (self.handlers.items) |handler| {
            if (handler.func(event)) return; // Handler consumed the event
        }

        // Process specific event types
        switch (event) {
            .mouse_press, .mouse_release, .mouse_move => try self.processMouseClick(event, now),
            .mouse_scroll => |scroll| try self.processMouseScroll(scroll),
            else => {},
        }
    }

    fn processMouseClick(self: *TUIMouse, event: unified_input.Event, now: i64) !void {
        const position, const button, const modifiers = switch (event) {
            .mouse_press => |m| .{ Position{ .x = @as(i32, @intCast(m.x)), .y = @as(i32, @intCast(m.y)) }, m.button, m.modifiers },
            .mouse_release => |m| .{ Position{ .x = @as(i32, @intCast(m.x)), .y = @as(i32, @intCast(m.y)) }, m.button, m.modifiers },
            .mouse_move => |m| .{ Position{ .x = @as(i32, @intCast(m.x)), .y = @as(i32, @intCast(m.y)) }, .left, m.modifiers },
            else => return,
        };

        switch (event) {
            .mouse_press => {
                // Check for drag start
                self.drag_start_pos = position;
                self.is_dragging = false;

                // Handle click
                const is_double_click = self.checkDoubleClick(position, now);
                const click_event = ClickEvent{
                    .position = position,
                    .button = button,
                    .modifiers = modifiers,
                    .is_double_click = is_double_click,
                };

                for (self.click_handlers.items) |handler| {
                    if (handler.func(click_event)) return;
                }

                self.last_click_pos = position;
                self.last_click_time = now;
            },
            .release => {
                if (self.is_dragging) {
                    // End drag
                    const drag_event = DragEvent{
                        .start_pos = self.drag_start_pos.?,
                        .end_pos = position,
                        .current_pos = position,
                        .button = button,
                        .modifiers = modifiers,
                        .action = DragEvent.Action.end,
                    };

                    for (self.drag_handlers.items) |handler| {
                        if (handler.func(drag_event)) return;
                    }
                }

                self.is_dragging = false;
                self.drag_start_pos = null;
            },
            .drag => {
                if (self.drag_start_pos) |start_pos| {
                    // Check if drag threshold is exceeded
                    const dx = if (position.x > start_pos.x) position.x - start_pos.x else start_pos.x - position.x;
                    const dy = if (position.y > start_pos.y) position.y - start_pos.y else start_pos.y - position.y;

                    if (!self.is_dragging and (dx > self.drag_threshold_pixels or dy > self.drag_threshold_pixels)) {
                        // Start drag
                        self.is_dragging = true;
                        const drag_start = DragEvent{
                            .start_pos = start_pos,
                            .end_pos = position,
                            .current_pos = position,
                            .button = button,
                            .modifiers = modifiers,
                            .action = DragEvent.Action.start,
                        };

                        for (self.drag_handlers.items) |handler| {
                            if (handler.func(drag_start)) return;
                        }
                    } else if (self.is_dragging) {
                        // Continue drag
                        const drag_continue = DragEvent{
                            .start_pos = start_pos,
                            .end_pos = position,
                            .current_pos = position,
                            .button = button,
                            .modifiers = modifiers,
                            .action = DragEvent.Action.drag,
                        };

                        for (self.drag_handlers.items) |handler| {
                            if (handler.func(drag_continue)) return;
                        }
                    }
                }
            },
        }
    }

    fn processMouseScroll(self: *TUIMouse, scroll: term_mouse.Scroll) !void {
        const scroll_event = ScrollEvent{
            .position = Position{ .x = scroll.x, .y = scroll.y },
            .direction = scroll.direction,
            .modifiers = scroll.modifiers,
        };

        for (self.scroll_handlers.items) |handler| {
            if (handler.func(scroll_event)) return;
        }
    }

    fn checkDoubleClick(self: *TUIMouse, position: Position, now: i64) bool {
        if (self.last_click_pos) |last_pos| {
            const time_diff = now - self.last_click_time;
            const dx = if (position.x > last_pos.x) position.x - last_pos.x else last_pos.x - position.x;
            const dy = if (position.y > last_pos.y) position.y - last_pos.y else last_pos.y - position.y;

            return time_diff <= self.double_click_threshold_ms and
                dx <= self.drag_threshold_pixels and
                dy <= self.drag_threshold_pixels;
        }
        return false;
    }

    /// Enable mouse tracking with specified protocol
    pub fn enableMouseTracking(writer: anytype, protocol: MouseProtocol, term_caps: anytype) !void {
        const term_mod = @import("term_shared");
        const TermCaps = term_mod.caps.TermCaps;
        const mode_mod = term_mod.ansi.mode;

        // Convert from local MouseProtocol to mode.MouseProtocol
        const mode_protocol = switch (protocol) {
            .x10 => mode_mod.MouseProtocol.x10,
            .normal => mode_mod.MouseProtocol.normal,
            .button_event => mode_mod.MouseProtocol.button_event,
            .any_event => mode_mod.MouseProtocol.any_event,
            .sgr => mode_mod.MouseProtocol.sgr,
            .sgr_pixels => mode_mod.MouseProtocol.sgr_pixels,
        };

        try mode_mod.enableMouseTracking(writer, mode_protocol, @as(TermCaps, term_caps));
    }

    /// Disable mouse tracking
    pub fn disableMouseTracking(writer: anytype, term_caps: anytype) !void {
        const term_mod = @import("term_shared");
        const TermCaps = term_mod.caps.TermCaps;
        try term_mod.ansi.mode.disableMouseTracking(writer, @as(TermCaps, term_caps));
    }
};

/// Mouse position
pub const Position = struct {
    x: i32,
    y: i32,
};

/// Click event with double-click detection
pub const ClickEvent = struct {
    position: Position,
    button: MouseButton,
    modifiers: term_mouse.Modifiers,
    is_double_click: bool,
};

/// Drag event with start/end positions
pub const DragEvent = struct {
    start_pos: Position,
    end_pos: Position,
    current_pos: Position,
    button: MouseButton,
    modifiers: term_mouse.Modifiers,
    action: Action,

    pub const Action = enum { start, drag, end };
};

/// Scroll event
pub const ScrollEvent = struct {
    position: Position,
    direction: term_mouse.ScrollDirection,
    modifiers: term_mouse.Modifiers,
};

/// Handler function types
pub const MouseHandler = struct {
    func: *const fn (event: MouseEvent) bool, // Returns true if handled
};

pub const ClickHandler = struct {
    func: *const fn (event: ClickEvent) bool, // Returns true if handled
};

pub const DragHandler = struct {
    func: *const fn (event: DragEvent) bool, // Returns true if handled
};

pub const ScrollHandler = struct {
    func: *const fn (event: ScrollEvent) bool, // Returns true if handled
};

/// Mouse-aware widget trait
pub const MouseAware = struct {
    mouse_controller: *TUIMouse,

    pub fn init(mouse_controller: *TUIMouse) MouseAware {
        return MouseAware{
            .mouse_controller = mouse_controller,
        };
    }

    pub fn onClick(self: *MouseAware, event: ClickEvent) void {
        _ = self;
        _ = event;
        // Default implementation does nothing
    }

    pub fn onDrag(self: *MouseAware, event: DragEvent) void {
        _ = self;
        _ = event;
        // Default implementation does nothing
    }

    pub fn onScroll(self: *MouseAware, event: ScrollEvent) void {
        _ = self;
        _ = event;
        // Default implementation does nothing
    }
};

// Alias for backward compatibility
pub const Mouse = TUIMouse;

// Tests
test "mouse controller initialization" {
    var mouse_controller = TUIMouse.init(std.testing.allocator);
    defer mouse_controller.deinit();

    try std.testing.expect(!mouse_controller.is_dragging);
    try std.testing.expect(mouse_controller.drag_start_pos == null);
}

test "double-click detection" {
    var mouse_controller = TUIMouse.init(std.testing.allocator);
    defer mouse_controller.deinit();

    const pos1 = Position{ .x = 10, .y = 20 };
    const pos2 = Position{ .x = 11, .y = 21 }; // Close position

    const now = std.time.milliTimestamp();

    // First click
    mouse_controller.last_click_pos = pos1;
    mouse_controller.last_click_time = now - 100; // 100ms ago

    // Second click - should be detected as double-click
    const is_double = mouse_controller.checkDoubleClick(pos2, now);
    try std.testing.expect(is_double);

    // Third click after long delay - should not be double-click
    const is_double_late = mouse_controller.checkDoubleClick(pos2, now + 500);
    try std.testing.expect(!is_double_late);
}

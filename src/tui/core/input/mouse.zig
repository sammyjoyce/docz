//! Enhanced mouse event handling for TUI applications
//! Provides pixel-precise mouse tracking and advanced interaction support
const std = @import("std");
const term_mouse = @import("../../../term/input/enhanced_mouse.zig");

// Re-export enhanced mouse types
pub const MouseEvent = term_mouse.MouseEvent;
pub const MouseButton = term_mouse.MouseButton;
pub const MouseAction = term_mouse.MouseAction;
pub const MouseProtocol = term_mouse.MouseProtocol;

/// Enhanced mouse manager with pixel precision support
pub const MouseManager = struct {
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
    
    pub fn init(allocator: std.mem.Allocator) MouseManager {
        return MouseManager{
            .handlers = std.ArrayListUnmanaged(MouseHandler){},
            .click_handlers = std.ArrayListUnmanaged(ClickHandler){},
            .drag_handlers = std.ArrayListUnmanaged(DragHandler){},
            .scroll_handlers = std.ArrayListUnmanaged(ScrollHandler){},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *MouseManager) void {
        self.handlers.deinit(self.allocator);
        self.click_handlers.deinit(self.allocator);
        self.drag_handlers.deinit(self.allocator);
        self.scroll_handlers.deinit(self.allocator);
    }
    
    /// Register general mouse event handler
    pub fn addHandler(self: *MouseManager, handler: MouseHandler) !void {
        try self.handlers.append(self.allocator, handler);
    }
    
    /// Register click-specific handler
    pub fn addClickHandler(self: *MouseManager, handler: ClickHandler) !void {
        try self.click_handlers.append(self.allocator, handler);
    }
    
    /// Register drag-specific handler  
    pub fn addDragHandler(self: *MouseManager, handler: DragHandler) !void {
        try self.drag_handlers.append(self.allocator, handler);
    }
    
    /// Register scroll-specific handler
    pub fn addScrollHandler(self: *MouseManager, handler: ScrollHandler) !void {
        try self.scroll_handlers.append(self.allocator, handler);
    }
    
    /// Process mouse event and dispatch to appropriate handlers
    pub fn processMouseEvent(self: *MouseManager, event: MouseEvent) !void {
        const now = std.time.milliTimestamp();
        
        // Dispatch to general handlers first
        for (self.handlers.items) |handler| {
            if (handler.func(event)) return; // Handler consumed the event
        }
        
        // Process specific event types
        switch (event) {
            .mouse => |m| try self.processMouseClick(m, now),
            .scroll => |s| try self.processMouseScroll(s),
            else => {},
        }
    }
    
    fn processMouseClick(self: *MouseManager, mouse: term_mouse.Mouse, now: i64) !void {
        const pos = Position{ .x = mouse.x, .y = mouse.y };
        
        switch (mouse.action) {
            .press => {
                // Check for drag start
                self.drag_start_pos = pos;
                self.is_dragging = false;
                
                // Handle click
                const is_double_click = self.checkDoubleClick(pos, now);
                const click_event = ClickEvent{
                    .position = pos,
                    .button = mouse.button,
                    .modifiers = mouse.modifiers,
                    .is_double_click = is_double_click,
                };
                
                for (self.click_handlers.items) |handler| {
                    if (handler.func(click_event)) return;
                }
                
                self.last_click_pos = pos;
                self.last_click_time = now;
            },
            .release => {
                if (self.is_dragging) {
                    // End drag
                    const drag_event = DragEvent{
                        .start_pos = self.drag_start_pos.?,
                        .end_pos = pos,
                        .current_pos = pos,
                        .button = mouse.button,
                        .modifiers = mouse.modifiers,
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
                    const dx = if (pos.x > start_pos.x) pos.x - start_pos.x else start_pos.x - pos.x;
                    const dy = if (pos.y > start_pos.y) pos.y - start_pos.y else start_pos.y - pos.y;
                    
                    if (!self.is_dragging and (dx > self.drag_threshold_pixels or dy > self.drag_threshold_pixels)) {
                        // Start drag
                        self.is_dragging = true;
                        const drag_start = DragEvent{
                            .start_pos = start_pos,
                            .end_pos = pos,
                            .current_pos = pos,
                            .button = mouse.button,
                            .modifiers = mouse.modifiers,
                            .action = DragEvent.Action.start,
                        };
                        
                        for (self.drag_handlers.items) |handler| {
                            if (handler.func(drag_start)) return;
                        }
                    } else if (self.is_dragging) {
                        // Continue drag
                        const drag_continue = DragEvent{
                            .start_pos = start_pos,
                            .end_pos = pos,
                            .current_pos = pos,
                            .button = mouse.button,
                            .modifiers = mouse.modifiers,
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
    
    fn processMouseScroll(self: *MouseManager, scroll: term_mouse.Scroll) !void {
        const scroll_event = ScrollEvent{
            .position = Position{ .x = scroll.x, .y = scroll.y },
            .direction = scroll.direction,
            .modifiers = scroll.modifiers,
        };
        
        for (self.scroll_handlers.items) |handler| {
            if (handler.func(scroll_event)) return;
        }
    }
    
    fn checkDoubleClick(self: *MouseManager, pos: Position, now: i64) bool {
        if (self.last_click_pos) |last_pos| {
            const time_diff = now - self.last_click_time;
            const dx = if (pos.x > last_pos.x) pos.x - last_pos.x else last_pos.x - pos.x;
            const dy = if (pos.y > last_pos.y) pos.y - last_pos.y else last_pos.y - pos.y;
            
            return time_diff <= self.double_click_threshold_ms and 
                   dx <= self.drag_threshold_pixels and 
                   dy <= self.drag_threshold_pixels;
        }
        return false;
    }
    
    /// Enable mouse tracking with specified protocol
    pub fn enableMouseTracking(writer: anytype, protocol: MouseProtocol) !void {
        switch (protocol) {
            .x10 => try writer.writeAll("\x1b[?9h"),
            .normal => try writer.writeAll("\x1b[?1000h"),
            .button_event => try writer.writeAll("\x1b[?1002h"),
            .any_event => try writer.writeAll("\x1b[?1003h"),
            .sgr => {
                try writer.writeAll("\x1b[?1006h"); // SGR mode
                try writer.writeAll("\x1b[?1000h"); // Enable mouse
            },
            .sgr_pixels => {
                try writer.writeAll("\x1b[?1016h"); // SGR pixel mode
                try writer.writeAll("\x1b[?1006h"); // SGR mode  
                try writer.writeAll("\x1b[?1000h"); // Enable mouse
            },
        }
    }
    
    /// Disable mouse tracking
    pub fn disableMouseTracking(writer: anytype) !void {
        try writer.writeAll("\x1b[?1016l"); // Disable SGR pixel mode
        try writer.writeAll("\x1b[?1006l"); // Disable SGR mode
        try writer.writeAll("\x1b[?1003l"); // Disable any event
        try writer.writeAll("\x1b[?1002l"); // Disable button event
        try writer.writeAll("\x1b[?1000l"); // Disable mouse
        try writer.writeAll("\x1b[?9l");    // Disable X10
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
    mouse_manager: *MouseManager,
    
    pub fn init(mouse_manager: *MouseManager) MouseAware {
        return MouseAware{
            .mouse_manager = mouse_manager,
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

// Tests
test "mouse manager initialization" {
    var mouse_manager = MouseManager.init(std.testing.allocator);
    defer mouse_manager.deinit();
    
    try std.testing.expect(!mouse_manager.is_dragging);
    try std.testing.expect(mouse_manager.drag_start_pos == null);
}

test "double-click detection" {
    var mouse_manager = MouseManager.init(std.testing.allocator);
    defer mouse_manager.deinit();
    
    const pos1 = Position{ .x = 10, .y = 20 };
    const pos2 = Position{ .x = 11, .y = 21 }; // Close position
    
    const now = std.time.milliTimestamp();
    
    // First click
    mouse_manager.last_click_pos = pos1;
    mouse_manager.last_click_time = now - 100; // 100ms ago
    
    // Second click - should be detected as double-click
    const is_double = mouse_manager.checkDoubleClick(pos2, now);
    try std.testing.expect(is_double);
    
    // Third click after long delay - should not be double-click
    const is_double_late = mouse_manager.checkDoubleClick(pos2, now + 500);
    try std.testing.expect(!is_double_late);
}
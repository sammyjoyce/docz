const std = @import("std");
const types = @import("types.zig");

/// Mouse event types and handling
/// Provides comprehensive mouse event management with gesture recognition
pub const MouseEventType = enum {
    click,
    double_click,
    triple_click,
    drag_start,
    drag_move,
    drag_end,
    wheel_scroll,
    gesture_pinch,
    gesture_zoom,
    hover,
    enter,
    leave,
};

/// Mouse gesture recognition
pub const MouseGesture = struct {
    type: GestureType,
    start_pos: types.MouseEvent,
    current_pos: types.MouseEvent,
    velocity_x: f32 = 0,
    velocity_y: f32 = 0,
    scale: f32 = 1.0, // For pinch/zoom gestures

    pub const GestureType = enum {
        none,
        drag,
        pinch,
        zoom,
        swipe,
    };
};

/// Mouse event with enhanced metadata
pub const EnhancedMouseEvent = struct {
    base_event: types.MouseEvent,
    event_type: MouseEventType,
    gesture: ?MouseGesture = null,
    click_count: u8 = 1,
    timestamp: i64,
    source: EventSource = .mouse,

    pub const EventSource = enum {
        mouse,
        touchpad,
        touchscreen,
        stylus,
    };
};

/// Mouse event tracker for gesture recognition and multi-click detection
pub const MouseEventTracker = struct {
    allocator: std.mem.Allocator,

    // Click detection
    last_click_time: i64 = 0,
    last_click_pos: struct { x: u32, y: u32 } = .{ .x = 0, .y = 0 },
    click_count: u8 = 0,
    double_click_threshold_ms: u32 = 400,
    click_distance_threshold: u32 = 3,

    // Drag detection
    drag_start_pos: ?struct { x: u32, y: u32 } = null,
    is_dragging: bool = false,
    drag_threshold: u32 = 5,

    // Gesture detection
    gesture_start_time: ?i64 = null,
    gesture_start_pos: ?struct { x: u32, y: u32 } = null,
    last_motion_time: i64 = 0,
    last_motion_pos: struct { x: u32, y: u32 } = .{ .x = 0, .y = 0 },

    // Hover detection
    hover_pos: ?struct { x: u32, y: u32 } = null,
    hover_start_time: ?i64 = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Process a mouse event and return enhanced event with gesture information
    pub fn processEvent(self: *Self, mouse_event: types.MouseEvent) EnhancedMouseEvent {
        const now = std.time.microTimestamp();
        var event_type = MouseEventType.click;
        var click_count: u8 = 1;

        switch (mouse_event.action) {
            .press => {
                // Detect multi-click
                const time_diff = @divFloor(now - self.last_click_time, 1000); // Convert to ms
                const pos_diff_x = if (mouse_event.x > self.last_click_pos.x) mouse_event.x - self.last_click_pos.x else self.last_click_pos.x - mouse_event.x;
                const pos_diff_y = if (mouse_event.y > self.last_click_pos.y) mouse_event.y - self.last_click_pos.y else self.last_click_pos.y - mouse_event.y;

                if (time_diff < self.double_click_threshold_ms and
                    pos_diff_x <= self.click_distance_threshold and
                    pos_diff_y <= self.click_distance_threshold)
                {
                    self.click_count += 1;
                    if (self.click_count == 2) {
                        event_type = .double_click;
                    } else if (self.click_count == 3) {
                        event_type = .triple_click;
                    }
                    if (self.click_count > 3) self.click_count = 1; // Reset after triple
                } else {
                    self.click_count = 1;
                }

                click_count = self.click_count;
                self.last_click_time = now;
                self.last_click_pos = .{ .x = mouse_event.x, .y = mouse_event.y };

                // Start potential drag
                self.drag_start_pos = .{ .x = mouse_event.x, .y = mouse_event.y };
                self.is_dragging = false;
            },
            .release => {
                if (self.is_dragging) {
                    event_type = .drag_end;
                }
                self.drag_start_pos = null;
                self.is_dragging = false;
            },
            .drag, .move => {
                // Check if this should be a drag event
                if (self.drag_start_pos) |start_pos| {
                    const distance_x = if (mouse_event.x > start_pos.x) mouse_event.x - start_pos.x else start_pos.x - mouse_event.x;
                    const distance_y = if (mouse_event.y > start_pos.y) mouse_event.y - start_pos.y else start_pos.y - mouse_event.y;

                    if (!self.is_dragging and (distance_x > self.drag_threshold or distance_y > self.drag_threshold)) {
                        self.is_dragging = true;
                        event_type = .drag_start;
                    } else if (self.is_dragging) {
                        event_type = .drag_move;
                    }
                }

                // Calculate velocity for motion events
                if (mouse_event.action == .move) {
                    const time_diff_s = @as(f32, @floatFromInt(now - self.last_motion_time)) / 1_000_000.0;
                    if (time_diff_s > 0.001) { // Avoid division by very small numbers
                        const dx = @as(f32, @floatFromInt(@as(i64, @intCast(mouse_event.x)) - @as(i64, @intCast(self.last_motion_pos.x))));
                        const dy = @as(f32, @floatFromInt(@as(i64, @intCast(mouse_event.y)) - @as(i64, @intCast(self.last_motion_pos.y))));

                        if (self.is_dragging) {
                            // Gesture information could be added here in the future
                        }
                    }

                    self.last_motion_time = now;
                    self.last_motion_pos = .{ .x = mouse_event.x, .y = mouse_event.y };
                }
            },
        }

        // Handle wheel events
        if (mouse_event.button == .wheel_up or mouse_event.button == .wheel_down) {
            event_type = .wheel_scroll;
        }

        return EnhancedMouseEvent{
            .base_event = mouse_event,
            .event_type = event_type,
            .gesture = gesture,
            .click_count = click_count,
            .timestamp = now,
        };
    }

    /// Set double-click detection threshold
    pub fn setDoubleClickThreshold(self: *Self, threshold_ms: u32) void {
        self.double_click_threshold_ms = threshold_ms;
    }

    /// Set click distance threshold for multi-click detection
    pub fn setClickDistanceThreshold(self: *Self, threshold: u32) void {
        self.click_distance_threshold = threshold;
    }

    /// Set drag threshold distance
    pub fn setDragThreshold(self: *Self, threshold: u32) void {
        self.drag_threshold = threshold;
    }
};

/// Mouse event queue for buffering events
pub const MouseEventQueue = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(EnhancedMouseEvent),
    max_size: usize = 100,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .events = std.ArrayList(EnhancedMouseEvent).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.events.deinit();
    }

    /// Add event to queue
    pub fn push(self: *Self, event: EnhancedMouseEvent) !void {
        try self.events.append(event);

        // Remove oldest events if queue is full
        while (self.events.items.len > self.max_size) {
            _ = self.events.orderedRemove(0);
        }
    }

    /// Get next event from queue
    pub fn pop(self: *Self) ?EnhancedMouseEvent {
        if (self.events.items.len == 0) return null;
        return self.events.orderedRemove(0);
    }

    /// Peek at next event without removing it
    pub fn peek(self: *Self) ?EnhancedMouseEvent {
        if (self.events.items.len == 0) return null;
        return self.events.items[0];
    }

    /// Clear all events
    pub fn clear(self: *Self) void {
        self.events.clearRetainingCapacity();
    }

    /// Get number of queued events
    pub fn count(self: Self) usize {
        return self.events.items.len;
    }
};

test "mouse event tracker initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tracker = MouseEventTracker.init(allocator);
    try testing.expect(!tracker.is_dragging);
    try testing.expect(tracker.click_count == 0);
}

test "mouse event queue" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var queue = MouseEventQueue.init(allocator);
    defer queue.deinit();

    const event = EnhancedMouseEvent{
        .base_event = types.MouseEvent{
            .button = .left,
            .action = .press,
            .x = 10,
            .y = 20,
            .mods = .{},
        },
        .event_type = .click,
        .timestamp = 0,
    };

    try queue.push(event);
    try testing.expect(queue.count() == 1);

    const popped = queue.pop();
    try testing.expect(popped != null);
    try testing.expect(queue.count() == 0);
}

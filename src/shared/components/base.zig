//! Component-Based UI Architecture
//!
//! This module provides a component system that can be used by both CLI and TUI
//! interfaces, enabling code reuse and consistent behavior across different presentation modes.

const std = @import("std");
const term_shared = @import("term_shared");
const term = term_shared.term;
const graphics = term_shared.graphics;
const theme_manager = @import("theme_manager");

const Terminal = term.Terminal;
const Color = term.Color;
const Style = term.Style;
const Point = term.Point;
const Rect = term.Rect;
const GraphicsManager = graphics.Graphics;

/// Unique identifier for components
pub const ComponentId = u32;

/// Event types that components can handle
pub const Event = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    resize: ResizeEvent,
    focus: FocusEvent,
    custom: CustomEvent,

    pub const KeyEvent = struct {
        key: Key,
        modifiers: KeyModifiers,

        pub const Key = enum {
            char,
            enter,
            escape,
            tab,
            backspace,
            delete,
            up,
            down,
            left,
            right,
            PAGE_UP,
            PAGE_DOWN,
            HOME,
            END,
            F1,
            F2,
            F3,
            F4,
            F5,
            F6,
            F7,
            F8,
            F9,
            F10,
            F11,
            F12,
        };

        pub const KeyModifiers = packed struct {
            ctrl: bool = false,
            alt: bool = false,
            shift: bool = false,
        };
    };

    pub const MouseEvent = struct {
        pos: Point,
        button: MouseButton,
        action: MouseAction,

        pub const MouseButton = enum {
            left,
            right,
            middle,
            WHEEL_UP,
            WHEEL_DOWN,
        };

        pub const MouseAction = enum {
            PRESS,
            RELEASE,
            MOVE,
        };
    };

    pub const ResizeEvent = struct {
        newSize: Rect,
    };

    pub const FocusEvent = struct {
        gained: bool,
    };

    pub const CustomEvent = struct {
        name: []const u8,
        data: ?*anyopaque,
    };
};

/// Component state management
pub const ComponentState = struct {
    visible: bool = true,
    enabled: bool = true,
    focused: bool = false,
    dirty: bool = true, // Needs redraw
    bounds: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    zIndex: i32 = 0,

    pub fn markDirty(self: *ComponentState) void {
        self.dirty = true;
    }

    pub fn clearDirty(self: *ComponentState) void {
        self.dirty = false;
    }
};

/// Context passed to component methods
pub const Render = struct {
    terminal: *Terminal,
    graphics: ?*GraphicsManager,
    parentBounds: Rect,
    clipRegion: ?Rect,
    theme: *Theme,
    frameTime: i64, // For animations

    pub fn clipped(self: Render, clip_bounds: Rect) Render {
        const intersection = if (self.clipRegion) |existing|
            intersectRects(existing, clip_bounds)
        else
            clip_bounds;

        return Render{
            .terminal = self.terminal,
            .graphics = self.graphics,
            .parentBounds = self.parentBounds,
            .clipRegion = intersection,
            .theme = self.theme,
            .frameTime = self.frameTime,
        };
    }
};

/// Theme system for consistent styling - now uses centralized theme manager
pub const Theme = theme_manager.ColorScheme;

/// Base component interface using vtable pattern for polymorphism
pub const Component = struct {
    const Self = @This();

    /// Virtual table for component methods
    pub const VTable = struct {
        // Lifecycle
        init: *const fn (impl: *anyopaque, allocator: std.mem.Allocator) anyerror!void,
        deinit: *const fn (impl: *anyopaque) void,

        // State management
        getState: *const fn (impl: *anyopaque) *ComponentState,
        setState: *const fn (impl: *anyopaque, state: ComponentState) void,

        // Rendering
        render: *const fn (impl: *anyopaque, ctx: Render) anyerror!void,
        measure: *const fn (impl: *anyopaque, available: Rect) Rect,

        // Event handling
        handleEvent: *const fn (impl: *anyopaque, event: Event) anyerror!bool,

        // Layout and children
        addChild: ?*const fn (impl: *anyopaque, child: *Component) anyerror!void,
        removeChild: ?*const fn (impl: *anyopaque, child: *Component) void,
        getChildren: ?*const fn (impl: *anyopaque) []const *Component,

        // Animation
        update: ?*const fn (impl: *anyopaque, dt: f32) anyerror!void,
    };

    vtable: *const VTable,
    impl: *anyopaque,
    id: ComponentId,

    // Public interface methods
    pub inline fn init(self: *Self, allocator: std.mem.Allocator) !void {
        return self.vtable.init(self.impl, allocator);
    }

    pub inline fn deinit(self: *Self) void {
        return self.vtable.deinit(self.impl);
    }

    pub inline fn getState(self: *Self) *ComponentState {
        return self.vtable.getState(self.impl);
    }

    pub inline fn setState(self: *Self, state: ComponentState) void {
        return self.vtable.setState(self.impl, state);
    }

    pub inline fn render(self: *Self, ctx: Render) !void {
        const state = self.getState();
        if (!state.visible) return;

        return self.vtable.render(self.impl, ctx);
    }

    pub inline fn measure(self: *Self, available: Rect) Rect {
        return self.vtable.measure(self.impl, available);
    }

    pub inline fn handleEvent(self: *Self, event: Event) !bool {
        const state = self.getState();
        if (!state.enabled) return false;

        return self.vtable.handleEvent(self.impl, event);
    }

    pub inline fn addChild(self: *Self, child: *Component) !void {
        if (self.vtable.addChild) |add_fn| {
            return add_fn(self.impl, child);
        }
        return error.ChildrenNotSupported;
    }

    pub inline fn removeChild(self: *Self, child: *Component) void {
        if (self.vtable.removeChild) |remove_fn| {
            remove_fn(self.impl, child);
        }
    }

    pub inline fn getChildren(self: *Self) []const *Component {
        if (self.vtable.getChildren) |get_fn| {
            return get_fn(self.impl);
        }
        return &[_]*Component{};
    }

    pub inline fn update(self: *Self, dt: f32) !void {
        if (self.vtable.update) |update_fn| {
            return update_fn(self.impl, dt);
        }
    }

    /// Helper to mark component as dirty for re-rendering
    pub fn markDirty(self: *Self) void {
        self.getState().markDirty();
    }

    /// Helper to check if component needs rendering
    pub fn isDirty(self: *Self) bool {
        return self.getState().dirty;
    }

    /// Helper to set component bounds
    pub fn setBounds(self: *Self, bounds: Rect) void {
        var state = self.getState();
        if (!rectsEqual(state.bounds, bounds)) {
            state.bounds = bounds;
            state.markDirty();
        }
    }

    /// Helper to check if point is within component bounds
    pub fn containsPoint(self: *Self, point: Point) bool {
        const bounds = self.getState().bounds;
        return point.x >= bounds.x and
            point.x < bounds.x + @as(i32, @intCast(bounds.width)) and
            point.y >= bounds.y and
            point.y < bounds.y + @as(i32, @intCast(bounds.height));
    }
};

/// Component registry for handling component lifecycle and events
pub const ComponentRegistry = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    components: std.ArrayList(*Component),
    focusedComponent: ?*Component,
    nextId: ComponentId,
    theme: *Theme,

    pub fn init(allocator: std.mem.Allocator, theme: *Theme) Self {
        return Self{
            .allocator = allocator,
            .components = std.ArrayList(*Component).init(allocator),
            .focusedComponent = null,
            .nextId = 1,
            .theme = theme,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.components.items) |component| {
            component.deinit();
            self.allocator.destroy(component);
        }
        self.components.deinit();
    }

    pub fn addComponent(self: *Self, component: *Component) !void {
        component.id = self.nextId;
        self.nextId += 1;

        try component.init(self.allocator);
        try self.components.append(component);
    }

    pub fn removeComponent(self: *Self, component: *Component) void {
        for (self.components.items, 0..) |c, i| {
            if (c == component) {
                _ = self.components.swapRemove(i);
                c.deinit();
                self.allocator.destroy(c);
                break;
            }
        }
    }

    pub fn setFocus(self: *Self, component: ?*Component) void {
        if (self.focusedComponent) |focused| {
            var state = focused.getState();
            state.focused = false;
            state.markDirty();
        }

        self.focusedComponent = component;

        if (component) |comp| {
            var state = comp.getState();
            state.focused = true;
            state.markDirty();
        }
    }

    pub fn handleEvent(self: *Self, event: Event) !bool {
        // Try focused component first
        if (self.focusedComponent) |focused| {
            if (try focused.handleEvent(event)) return true;
        }

        // Then try other components in reverse z-order (top to bottom)
        const sorted_components = try self.allocator.dupe(*Component, self.components.items);
        defer self.allocator.free(sorted_components);

        std.sort.sort(*Component, sorted_components, {}, compareZIndex);

        for (sorted_components) |component| {
            if (component != self.focusedComponent) {
                if (try component.handleEvent(event)) return true;
            }
        }

        return false;
    }

    pub fn render(self: *Self, ctx: Render) !void {
        // Sort components by z-index for proper layering
        const sorted_components = try self.allocator.dupe(*Component, self.components.items);
        defer self.allocator.free(sorted_components);

        std.sort.sort(*Component, sorted_components, {}, compareZIndexReverse);

        for (sorted_components) |component| {
            if (component.isDirty()) {
                try component.render(ctx);
                component.getState().clearDirty();
            }
        }
    }

    pub fn update(self: *Self, dt: f32) !void {
        for (self.components.items) |component| {
            try component.update(dt);
        }
    }

    pub fn getTheme(self: *Self) *Theme {
        return self.theme;
    }

    fn compareZIndex(context: void, a: *Component, b: *Component) bool {
        _ = context;
        return a.getState().zIndex < b.getState().zIndex;
    }

    fn compareZIndexReverse(context: void, a: *Component, b: *Component) bool {
        _ = context;
        return a.getState().zIndex > b.getState().zIndex;
    }
};

// Utility functions

fn intersectRects(a: Rect, b: Rect) ?Rect {
    const left = @max(a.x, b.x);
    const top = @max(a.y, b.y);
    const right = @min(a.x + @as(i32, @intCast(a.width)), b.x + @as(i32, @intCast(b.width)));
    const bottom = @min(a.y + @as(i32, @intCast(a.height)), b.y + @as(i32, @intCast(b.height)));

    if (left >= right or top >= bottom) return null;

    return Rect{
        .x = left,
        .y = top,
        .width = @as(u32, @intCast(right - left)),
        .height = @as(u32, @intCast(bottom - top)),
    };
}

fn rectsEqual(a: Rect, b: Rect) bool {
    return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height;
}

/// Animation utilities
pub const Animation = struct {
    pub fn easeOut(t: f32) f32 {
        return 1.0 - (1.0 - t) * (1.0 - t);
    }

    pub fn easeIn(t: f32) f32 {
        return t * t;
    }

    pub fn easeInOut(t: f32) f32 {
        if (t < 0.5) {
            return 2.0 * t * t;
        } else {
            return 1.0 - 2.0 * (1.0 - t) * (1.0 - t);
        }
    }

    pub fn interpolate(start: f32, end: f32, t: f32) f32 {
        return start + (end - start) * t;
    }
};

test "component state" {
    var state = ComponentState{};
    try std.testing.expect(state.dirty);

    state.clearDirty();
    try std.testing.expect(!state.dirty);

    state.markDirty();
    try std.testing.expect(state.dirty);
}

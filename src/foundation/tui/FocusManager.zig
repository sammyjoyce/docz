//! Focus Manager for TUI components
//!
//! This module provides focus management for UI components,
//! tracking which component has focus and handling focus navigation.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Focusable component interface
pub const Focusable = struct {
    id: []const u8,
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        onFocus: *const fn (ptr: *anyopaque) void,
        onBlur: *const fn (ptr: *anyopaque) void,
        canFocus: *const fn (ptr: *anyopaque) bool,
    };

    pub fn focus(self: Focusable) void {
        self.vtable.onFocus(self.ptr);
    }

    pub fn blur(self: Focusable) void {
        self.vtable.onBlur(self.ptr);
    }

    pub fn canFocus(self: Focusable) bool {
        return self.vtable.canFocus(self.ptr);
    }
};

/// Focus navigation direction
pub const Direction = enum {
    next,
    previous,
    up,
    down,
    left,
    right,
};

/// Focus Manager
pub const FocusManager = struct {
    allocator: Allocator,
    components: std.ArrayList(Focusable),
    current_index: ?usize,
    focus_trap: bool,
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// Initialize the focus manager
    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = Self{
            .allocator = allocator,
            .components = std.ArrayList(Focusable).init(allocator),
            .current_index = null,
            .focus_trap = false,
            .mutex = std.Thread.Mutex{},
        };

        return self;
    }

    /// Deinitialize the focus manager
    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Blur current component if any
        if (self.current_index) |index| {
            if (index < self.components.items.len) {
                self.components.items[index].blur();
            }
        }

        self.components.deinit();
        self.allocator.destroy(self);
    }

    /// Register a focusable component
    pub fn registerComponent(self: *Self, component: Focusable) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if component already registered
        for (self.components.items) |existing| {
            if (std.mem.eql(u8, existing.id, component.id)) {
                return; // Already registered
            }
        }

        try self.components.append(component);

        // If this is the first component and it can focus, focus it
        if (self.components.items.len == 1 and self.current_index == null) {
            if (component.canFocus()) {
                self.current_index = 0;
                component.focus();
            }
        }
    }

    /// Unregister a focusable component
    pub fn unregisterComponent(self: *Self, id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.components.items, 0..) |component, i| {
            if (std.mem.eql(u8, component.id, id)) {
                // If this component has focus, move focus away
                if (self.current_index) |current| {
                    if (current == i) {
                        component.blur();
                        // Try to focus next component
                        if (i + 1 < self.components.items.len) {
                            self.current_index = i; // Will be i after removal
                        } else if (i > 0) {
                            self.current_index = i - 1;
                        } else {
                            self.current_index = null;
                        }
                    } else if (current > i) {
                        // Adjust index after removal
                        self.current_index = current - 1;
                    }
                }

                _ = self.components.swapRemove(i);

                // Focus new component at adjusted index
                if (self.current_index) |new_index| {
                    if (new_index < self.components.items.len) {
                        self.components.items[new_index].focus();
                    }
                }
                break;
            }
        }
    }

    /// Set focus to a specific component by ID
    pub fn focusComponent(self: *Self, id: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.components.items, 0..) |component, i| {
            if (std.mem.eql(u8, component.id, id)) {
                if (component.canFocus()) {
                    // Blur current component
                    if (self.current_index) |current| {
                        if (current < self.components.items.len) {
                            self.components.items[current].blur();
                        }
                    }

                    // Focus new component
                    self.current_index = i;
                    component.focus();
                    return true;
                }
                break;
            }
        }

        return false;
    }

    /// Move focus in the specified direction
    pub fn moveFocus(self: *Self, direction: Direction) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.components.items.len == 0) return false;

        _ = self.current_index orelse {
            // No current focus, try to focus first focusable component
            for (self.components.items, 0..) |component, i| {
                if (component.canFocus()) {
                    self.current_index = i;
                    component.focus();
                    return true;
                }
            }
            return false;
        };

        // Handle directional navigation
        switch (direction) {
            .next => return self.focusNext(),
            .previous => return self.focusPrevious(),
            else => {
                // For spatial navigation (up/down/left/right),
                // we'd need position information which we don't have here.
                // Fall back to next/previous for now.
                return if (direction == .down or direction == .right)
                    self.focusNext()
                else
                    self.focusPrevious();
            },
        }
    }

    /// Focus the next focusable component
    fn focusNext(self: *Self) bool {
        if (self.components.items.len == 0) return false;

        const start = self.current_index orelse 0;
        var i = start;

        while (true) {
            i = (i + 1) % self.components.items.len;

            if (self.components.items[i].canFocus()) {
                // Blur current
                if (self.current_index) |current| {
                    if (current < self.components.items.len) {
                        self.components.items[current].blur();
                    }
                }

                // Focus new
                self.current_index = i;
                self.components.items[i].focus();
                return true;
            }

            // Wrapped around without finding focusable component
            if (i == start) break;
        }

        return false;
    }

    /// Focus the previous focusable component
    fn focusPrevious(self: *Self) bool {
        if (self.components.items.len == 0) return false;

        const start = self.current_index orelse 0;
        var i = start;

        while (true) {
            i = if (i == 0) self.components.items.len - 1 else i - 1;

            if (self.components.items[i].canFocus()) {
                // Blur current
                if (self.current_index) |current| {
                    if (current < self.components.items.len) {
                        self.components.items[current].blur();
                    }
                }

                // Focus new
                self.current_index = i;
                self.components.items[i].focus();
                return true;
            }

            // Wrapped around without finding focusable component
            if (i == start) break;
        }

        return false;
    }

    /// Get the currently focused component ID
    pub fn getCurrentFocus(self: *Self) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.current_index) |index| {
            if (index < self.components.items.len) {
                return self.components.items[index].id;
            }
        }

        return null;
    }

    /// Check if a component has focus
    pub fn hasFocus(self: *Self, id: []const u8) bool {
        if (self.getCurrentFocus()) |focused_id| {
            return std.mem.eql(u8, focused_id, id);
        }
        return false;
    }

    /// Enable or disable focus trap
    /// When enabled, focus cannot leave the registered components
    pub fn setFocusTrap(self: *Self, enabled: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.focus_trap = enabled;
    }

    /// Clear focus from all components
    pub fn clearFocus(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.current_index) |index| {
            if (index < self.components.items.len) {
                self.components.items[index].blur();
            }
            self.current_index = null;
        }
    }
};

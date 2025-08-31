//! TUI screen management.
//!
//! Provides screen lifecycle, layout management, and component coordination
//! for terminal UI screens.

const std = @import("std");
const ui = @import("../ui.zig");
const render = @import("../render.zig");
const App = @import("App.zig");

const Self = @This();

/// Screen configuration
pub const Config = struct {
    /// Screen title (shown in terminal title bar if supported)
    title: []const u8 = "",
    /// Whether this screen can be resized
    resizable: bool = true,
    /// Minimum width in columns
    min_width: u32 = 20,
    /// Minimum height in rows
    min_height: u32 = 5,
};

/// Screen state
pub const State = enum {
    inactive,
    active,
    suspended,
    closing,
};

/// Screen error set
pub const Error = error{
    InvalidState,
    LayoutFailed,
    ComponentError,
    OutOfMemory,
};

/// Screen manager for TUI applications
allocator: std.mem.Allocator,
config: Config,
state: State,
components: std.ArrayList(*ui.Component),
layout: ?*ui.Layout,
bounds: ui.Rect,
dirty: bool,
focus_index: ?usize,
app: ?*App,

/// Initialize a new screen
pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
    return .{
        .allocator = allocator,
        .config = config,
        .state = .inactive,
        .components = std.ArrayList(*ui.Component).init(allocator),
        .layout = null,
        .bounds = .{ .x = 0, .y = 0, .width = 80, .height = 24 },
        .dirty = true,
        .focus_index = null,
        .app = null,
    };
}

/// Deinitialize the screen
pub fn deinit(self: *Self) void {
    self.components.deinit();
}

/// Add a component to the screen
pub fn addComponent(self: *Self, component: *ui.Component) !void {
    try self.components.append(component);
    self.dirty = true;

    // Set first component as focused if none selected
    if (self.focus_index == null and self.components.items.len > 0) {
        self.focus_index = 0;
    }
}

/// Remove a component from the screen
pub fn removeComponent(self: *Self, component: *ui.Component) void {
    for (self.components.items, 0..) |c, i| {
        if (c == component) {
            _ = self.components.swapRemove(i);
            self.dirty = true;

            // Update focus if needed
            if (self.focus_index) |idx| {
                if (idx == i) {
                    self.focus_index = if (self.components.items.len > 0) 0 else null;
                } else if (idx > i) {
                    self.focus_index = idx - 1;
                }
            }
            break;
        }
    }
}

/// Set the layout manager for this screen
pub fn setLayout(self: *Self, layout: *ui.Layout) void {
    self.layout = layout;
    self.dirty = true;
}

/// Activate the screen
pub fn activate(self: *Self, app: *App) Error!void {
    if (self.state != .inactive and self.state != .suspended) {
        return Error.InvalidState;
    }

    self.app = app;
    self.state = .active;
    self.dirty = true;

    // Set terminal title if configured
    if (self.config.title.len > 0) {
        // Would set terminal title here
    }

    // Notify components of activation
    for (self.components.items) |component| {
        if (comptime @hasDecl(@TypeOf(component.*), "onActivate")) {
            try component.onActivate();
        }
    }
}

/// Deactivate the screen
pub fn deactivate(self: *Self) Error!void {
    if (self.state != .active) {
        return Error.InvalidState;
    }

    self.state = .inactive;

    // Notify components of deactivation
    for (self.components.items) |component| {
        if (comptime @hasDecl(@TypeOf(component.*), "onDeactivate")) {
            try component.onDeactivate();
        }
    }

    self.app = null;
}

/// Suspend the screen (e.g., when switching to another screen)
pub fn suspendScreen(self: *Self) Error!void {
    if (self.state != .active) {
        return Error.InvalidState;
    }

    self.state = .suspended;

    // Notify components of suspension
    for (self.components.items) |component| {
        if (comptime @hasDecl(@TypeOf(component.*), "onSuspend")) {
            try component.onSuspend();
        }
    }
}

/// Resume the screen from suspension
pub fn resumeScreen(self: *Self) Error!void {
    if (self.state != .suspended) {
        return Error.InvalidState;
    }

    self.state = .active;
    self.dirty = true;

    // Notify components of resumption
    for (self.components.items) |component| {
        if (comptime @hasDecl(@TypeOf(component.*), "onResume")) {
            try component.onResume();
        }
    }
}

/// Handle a resize event
pub fn resize(self: *Self, width: u32, height: u32) Error!void {
    if (!self.config.resizable) {
        return;
    }

    // Enforce minimum dimensions
    const new_width = @max(width, self.config.min_width);
    const new_height = @max(height, self.config.min_height);

    if (new_width != self.bounds.width or new_height != self.bounds.height) {
        self.bounds.width = new_width;
        self.bounds.height = new_height;
        self.dirty = true;

        // Relayout components
        try self.performLayout();
    }
}

/// Perform layout of all components
pub fn performLayout(self: *Self) Error!void {
    if (self.layout) |layout| {
        // Use custom layout manager
        try layout.layout(self.components.items, self.bounds, self.allocator);
    } else {
        // Default layout: stack vertically
        const component_height = if (self.components.items.len > 0)
            self.bounds.height / @as(u32, @intCast(self.components.items.len))
        else
            self.bounds.height;

        for (self.components.items, 0..) |component, i| {
            const component_bounds = ui.Rect{
                .x = self.bounds.x,
                .y = self.bounds.y + @as(u32, @intCast(i)) * component_height,
                .width = self.bounds.width,
                .height = component_height,
            };
            _ = try component.layout(component_bounds, self.allocator);
        }
    }

    self.dirty = false;
}

/// Handle an input event
pub fn handleEvent(self: *Self, event: ui.Event) Error!void {
    if (self.state != .active) {
        return;
    }

    // Handle screen-level events
    switch (event) {
        .key => |key| {
            // Tab navigation between components
            if (key.code == '\t') {
                if (key.shift) {
                    self.focusPrevious();
                } else {
                    self.focusNext();
                }
                return;
            }
        },
        else => {},
    }

    // Dispatch to focused component
    if (self.focus_index) |idx| {
        if (idx < self.components.items.len) {
            const component = self.components.items[idx];
            try component.event(event);
        }
    }
}

/// Focus the next component
pub fn focusNext(self: *Self) void {
    if (self.components.items.len == 0) return;

    if (self.focus_index) |idx| {
        self.focus_index = (idx + 1) % self.components.items.len;
    } else {
        self.focus_index = 0;
    }

    self.updateFocus();
}

/// Focus the previous component
pub fn focusPrevious(self: *Self) void {
    if (self.components.items.len == 0) return;

    if (self.focus_index) |idx| {
        if (idx == 0) {
            self.focus_index = self.components.items.len - 1;
        } else {
            self.focus_index = idx - 1;
        }
    } else {
        self.focus_index = self.components.items.len - 1;
    }

    self.updateFocus();
}

/// Update focus state of components
fn updateFocus(self: *Self) void {
    for (self.components.items, 0..) |component, i| {
        const focused = self.focus_index != null and self.focus_index.? == i;
        if (comptime @hasDecl(@TypeOf(component.*), "setFocused")) {
            component.setFocused(focused);
        }
    }
}

/// Render the screen
pub fn render(self: *Self, ctx: *render.RenderContext) Error!void {
    if (self.state != .active) {
        return;
    }

    // Perform layout if needed
    if (self.dirty) {
        try self.performLayout();
    }

    // Render all components
    for (self.components.items) |component| {
        try component.draw(ctx);
    }
}

/// Check if the screen needs redrawing
pub fn needsRedraw(self: *const Self) bool {
    if (self.dirty) return true;

    // Check if any component needs redraw
    for (self.components.items) |component| {
        if (comptime @hasDecl(@TypeOf(component.*), "needsRedraw")) {
            if (component.needsRedraw()) return true;
        }
    }

    return false;
}

/// Mark the screen as needing redraw
pub fn markDirty(self: *Self) void {
    self.dirty = true;
}

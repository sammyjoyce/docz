//! Improved Widget Composition Pattern
//! Trait-like interface similar to Ratatui's approach with Zig comptime features

const std = @import("std");
const unified_renderer = @import("unified_renderer.zig");
const Allocator = std.mem.Allocator;

// Re-export core types
pub const Rect = unified_renderer.Rect;
pub const Size = unified_renderer.Size;
pub const Point = unified_renderer.Point;
pub const InputEvent = unified_renderer.InputEvent;
pub const Theme = unified_renderer.Theme;

/// Widget message system for inter-widget communication
pub const Message = union(enum) {
    /// Widget state changed
    state_changed: struct {
        widget_id: []const u8,
        new_state: []const u8,
    },
    /// Widget requests focus
    request_focus: struct {
        widget_id: []const u8,
    },
    /// Widget was clicked
    clicked: struct {
        widget_id: []const u8,
        position: Point,
    },
    /// Custom message with data
    custom: struct {
        widget_id: []const u8,
        message_type: []const u8,
        data: []const u8,
    },
};

/// Widget constraints for layout
pub const Constraints = struct {
    min_width: u16 = 0,
    max_width: u16 = std.math.maxInt(u16),
    min_height: u16 = 0,
    max_height: u16 = std.math.maxInt(u16),

    pub fn fixed(width: u16, height: u16) Constraints {
        return .{
            .min_width = width,
            .max_width = width,
            .min_height = height,
            .max_height = height,
        };
    }

    pub fn loose(min_width: u16, min_height: u16) Constraints {
        return .{
            .min_width = min_width,
            .max_height = min_height,
        };
    }
};

/// Widget layout information
pub const LayoutInfo = struct {
    size: Size,
    position: Point,
    constraints: Constraints,
};

/// Widget VTable - defines the interface all widgets must implement
pub const WidgetVTable = struct {
    /// Render the widget to the terminal
    render: *const fn (ctx: *anyopaque, renderer: *unified_renderer.UnifiedRenderer, area: Rect) anyerror!void,

    /// Handle input events
    handle_input: *const fn (ctx: *anyopaque, event: InputEvent, area: Rect) anyerror!bool,

    /// Calculate the widget's desired size
    measure: *const fn (ctx: *anyopaque, constraints: Constraints) Size,

    /// Get widget type name for debugging
    get_type_name: *const fn (ctx: *anyopaque) []const u8,
};

/// Core Widget interface - all widgets implement this
pub const Widget = struct {
    /// Pointer to the actual widget implementation
    ptr: *anyopaque,

    /// VTable defining the widget's behavior
    vtable: *const WidgetVTable,

    /// Unique identifier for the widget
    id: []const u8,

    /// Current bounds of the widget
    bounds: Rect,

    /// Whether the widget is visible
    visible: bool = true,

    /// Whether the widget is focused
    focused: bool = false,

    /// User data associated with the widget
    user_data: ?*anyopaque = null,

    /// Layout information
    layout_info: LayoutInfo,

    pub fn init(
        ptr: *anyopaque,
        vtable: *const WidgetVTable,
        id: []const u8,
        bounds: Rect,
    ) Widget {
        return .{
            .ptr = ptr,
            .vtable = vtable,
            .id = id,
            .bounds = bounds,
            .layout_info = .{
                .size = .{ .width = bounds.width, .height = bounds.height },
                .position = .{ .x = bounds.x, .y = bounds.y },
                .constraints = .{},
            },
        };
    }

    /// Render the widget
    pub fn render(self: *Widget, renderer: *unified_renderer.UnifiedRenderer) !void {
        if (!self.visible) return;

        try self.vtable.render(self.ptr, renderer, self.bounds);
    }

    /// Handle input event
    pub fn handleInput(self: *Widget, event: InputEvent) !bool {
        if (!self.visible) return false;

        return try self.vtable.handle_input(self.ptr, event, self.bounds);
    }

    /// Measure the widget's desired size
    pub fn measure(self: *Widget, constraints: Constraints) Size {
        return self.vtable.measure(self.ptr, constraints);
    }

    /// Set widget bounds
    pub fn setBounds(self: *Widget, bounds: Rect) void {
        const old_bounds = self.bounds;
        self.bounds = bounds;
        self.layout_info.size = .{ .width = bounds.width, .height = bounds.height };
        self.layout_info.position = .{ .x = bounds.x, .y = bounds.y };
    }

    /// Set focus state
    pub fn setFocus(self: *Widget, focused: bool) void {
        self.focused = focused;
    }

    /// Set visibility
    pub fn setVisible(self: *Widget, visible: bool) void {
        self.visible = visible;
    }

    /// Get widget type name
    pub fn getTypeName(self: Widget) []const u8 {
        return self.vtable.get_type_name(self.ptr);
    }
};

/// Container widget for composition
pub const Container = struct {
    /// Child widgets
    children: std.ArrayList(*Widget),

    /// Layout direction
    direction: enum { horizontal, vertical } = .vertical,

    /// Spacing between children
    spacing: u16 = 0,

    /// Container padding
    padding: struct {
        top: u16 = 0,
        right: u16 = 0,
        bottom: u16 = 0,
        left: u16 = 0,
    } = .{},

    /// Background style
    background: ?unified_renderer.Color = null,

    /// Border style
    border: ?struct {
        color: unified_renderer.Color,
        style: enum { single, double, rounded } = .single,
    } = null,

    allocator: Allocator,

    pub fn init(allocator: Allocator) Container {
        return .{
            .children = std.ArrayList(*Widget).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Container) void {
        self.children.deinit();
    }

    pub fn addChild(self: *Container, child: *Widget) !void {
        try self.children.append(child);
    }

    pub fn removeChild(self: *Container, child: *Widget) void {
        for (self.children.items, 0..) |c, i| {
            if (c == child) {
                _ = self.children.orderedRemove(i);
                break;
            }
        }
    }

    pub fn layout(self: *Container, available: Rect) void {
        const content_area = Rect{
            .x = available.x + self.padding.left,
            .y = available.y + self.padding.top,
            .width = available.width -| self.padding.left -| self.padding.right,
            .height = available.height -| self.padding.top -| self.padding.bottom,
        };

        switch (self.direction) {
            .vertical => self.layoutVertical(content_area),
            .horizontal => self.layoutHorizontal(content_area),
        }
    }

    fn layoutVertical(self: *Container, area: Rect) void {
        if (self.children.items.len == 0) return;

        const total_spacing = self.spacing * (self.children.items.len - 1);
        const available_height = area.height -| total_spacing;
        const child_height = available_height / @as(u16, @intCast(self.children.items.len));

        var y = area.y;
        for (self.children.items) |child| {
            const child_bounds = Rect{
                .x = area.x,
                .y = y,
                .width = area.width,
                .height = child_height,
            };
            child.setBounds(child_bounds);
            y += child_height + self.spacing;
        }
    }

    fn layoutHorizontal(self: *Container, area: Rect) void {
        if (self.children.items.len == 0) return;

        const total_spacing = self.spacing * (self.children.items.len - 1);
        const available_width = area.width -| total_spacing;
        const child_width = available_width / @as(u16, @intCast(self.children.items.len));

        var x = area.x;
        for (self.children.items) |child| {
            const child_bounds = Rect{
                .x = x,
                .y = area.y,
                .width = child_width,
                .height = area.height,
            };
            child.setBounds(child_bounds);
            x += child_width + self.spacing;
        }
    }

    pub fn render(self: *Container, renderer: *unified_renderer.UnifiedRenderer, area: Rect) !void {
        // Draw background
        if (self.background) |bg| {
            try renderer.drawText(area.x, area.y, " " ** area.width, null, bg);
            for (0..area.height) |i| {
                try renderer.drawText(area.x, area.y + @as(i16, @intCast(i)), " " ** area.width, null, bg);
            }
        }

        // Draw border
        if (self.border) |border| {
            try renderer.drawBox(area, true, null);
        }

        // Layout children
        self.layout(area);

        // Render children
        for (self.children.items) |child| {
            try child.render(renderer);
        }
    }

    pub fn handleInput(self: *Container, event: InputEvent, area: Rect) !bool {
        // Layout children first to ensure correct bounds
        self.layout(area);

        // Pass input to children (in reverse order for proper event handling)
        var i = self.children.items.len;
        while (i > 0) {
            i -= 1;
            const child = self.children.items[i];
            if (try child.handleInput(event)) {
                return true;
            }
        }

        return false;
    }

    pub fn measure(self: *Container, constraints: Constraints) Size {
        var total_width: u16 = 0;
        var total_height: u16 = 0;
        const total_spacing = self.spacing * (self.children.items.len -| 1);

        switch (self.direction) {
            .vertical => {
                for (self.children.items) |child| {
                    const child_size = child.measure(constraints);
                    total_width = @max(total_width, child_size.width);
                    total_height += child_size.height;
                }
                total_height += total_spacing;
            },
            .horizontal => {
                for (self.children.items) |child| {
                    const child_size = child.measure(constraints);
                    total_width += child_size.width;
                    total_height = @max(total_height, child_size.height);
                }
                total_width += total_spacing;
            },
        }

        // Add padding
        total_width += self.padding.left + self.padding.right;
        total_height += self.padding.top + self.padding.bottom;

        return .{
            .width = std.math.clamp(total_width, constraints.min_width, constraints.max_width),
            .height = std.math.clamp(total_height, constraints.min_height, constraints.max_height),
        };
    }
};

/// Helper functions for creating widgets
pub const WidgetBuilder = struct {
    /// Create a text widget
    pub fn text(allocator: Allocator, content: []const u8, id: []const u8, bounds: Rect) !*Widget {
        const TextWidget = struct {
            content: []const u8,
            allocator: Allocator,

            pub fn render(ctx: *anyopaque, renderer: *unified_renderer.UnifiedRenderer, area: Rect) !void {
                const self: *@This() = @ptrCast(@alignCast(ctx));
                try renderer.drawText(area.x, area.y, self.content, null, null);
            }

            pub fn handleInput(ctx: *anyopaque, event: InputEvent, area: Rect) !bool {
                _ = ctx;
                _ = event;
                _ = area;
                return false;
            }

            pub fn measure(ctx: *anyopaque, constraints: Constraints) Size {
                const self: *@This() = @ptrCast(@alignCast(ctx));
                const width = @as(u16, @intCast(@min(self.content.len, constraints.max_width)));
                const height = 1;
                return .{
                    .width = std.math.clamp(width, constraints.min_width, constraints.max_width),
                    .height = std.math.clamp(height, constraints.min_height, constraints.max_height),
                };
            }

            pub fn getTypeName(ctx: *anyopaque) []const u8 {
                _ = ctx;
                return "TextWidget";
            }
        };

        const widget_impl = try allocator.create(TextWidget);
        widget_impl.* = .{
            .content = try allocator.dupe(u8, content),
            .allocator = allocator,
        };

        const vtable = try allocator.create(WidgetVTable);
        vtable.* = .{
            .render = TextWidget.render,
            .handle_input = TextWidget.handleInput,
            .measure = TextWidget.measure,
            .get_type_name = TextWidget.getTypeName,
        };

        const widget = try allocator.create(Widget);
        widget.* = Widget.init(widget_impl, vtable, try allocator.dupe(u8, id), bounds);

        return widget;
    }

    /// Create a button widget
    pub fn button(allocator: Allocator, label: []const u8, id: []const u8, bounds: Rect, on_click: ?*const fn (*Widget) void) !*Widget {
        const ButtonWidget = struct {
            label: []const u8,
            on_click: ?*const fn (*Widget) void,
            allocator: Allocator,

            pub fn render(ctx: *anyopaque, renderer: *unified_renderer.UnifiedRenderer, area: Rect) !void {
                const self: *@This() = @ptrCast(@alignCast(ctx));

                // Draw button background
                const button_text = try std.fmt.allocPrint(self.allocator, "[ {s} ]", .{self.label});
                defer self.allocator.free(button_text);

                try renderer.drawText(area.x, area.y, button_text, unified_renderer.Color.WHITE, unified_renderer.Color.BLUE);
            }

            pub fn handleInput(ctx: *anyopaque, event: InputEvent, area: Rect) !bool {
                const self: *@This() = @ptrCast(@alignCast(ctx));

                switch (event) {
                    .key => |key_event| {
                        if (key_event.key == .enter or key_event.key == .char and key_event.key.char == ' ') {
                            if (self.on_click) |callback| {
                                callback(null);
                            }
                            return true;
                        }
                    },
                    .mouse => |mouse_event| {
                        if (mouse_event.action == .press and mouse_event.button == .left) {
                            const mouse_point = Point{ .x = @intCast(mouse_event.x), .y = @intCast(mouse_event.y) };
                            if (area.contains(mouse_point)) {
                                if (self.on_click) |callback| {
                                    callback(null);
                                }
                                return true;
                            }
                        }
                    },
                    else => {},
                }

                return false;
            }

            pub fn measure(ctx: *anyopaque, constraints: Constraints) Size {
                const self: *@This() = @ptrCast(@alignCast(ctx));
                const width = @as(u16, @intCast(self.label.len + 4)); // [ label ]
                const height = 1;
                return .{
                    .width = std.math.clamp(width, constraints.min_width, constraints.max_width),
                    .height = std.math.clamp(height, constraints.min_height, constraints.max_height),
                };
            }

            pub fn getTypeName(ctx: *anyopaque) []const u8 {
                _ = ctx;
                return "ButtonWidget";
            }
        };

        const widget_impl = try allocator.create(ButtonWidget);
        widget_impl.* = .{
            .label = try allocator.dupe(u8, label),
            .on_click = on_click,
            .allocator = allocator,
        };

        const vtable = try allocator.create(WidgetVTable);
        vtable.* = .{
            .render = ButtonWidget.render,
            .handle_input = ButtonWidget.handleInput,
            .measure = ButtonWidget.measure,
            .get_type_name = ButtonWidget.getTypeName,
        };

        const widget = try allocator.create(Widget);
        widget.* = Widget.init(widget_impl, vtable, try allocator.dupe(u8, id), bounds);

        return widget;
    }

    /// Create a container widget
    pub fn container(allocator: Allocator, id: []const u8, bounds: Rect, direction: enum { horizontal, vertical }) !*Widget {
        const ContainerWidget = struct {
            container: Container,

            pub fn render(ctx: *anyopaque, renderer: *unified_renderer.UnifiedRenderer, area: Rect) !void {
                const self: *@This() = @ptrCast(@alignCast(ctx));
                try self.container.render(renderer, area);
            }

            pub fn handleInput(ctx: *anyopaque, event: InputEvent, area: Rect) !bool {
                const self: *@This() = @ptrCast(@alignCast(ctx));
                return try self.container.handleInput(event, area);
            }

            pub fn measure(ctx: *anyopaque, constraints: Constraints) Size {
                const self: *@This() = @ptrCast(@alignCast(ctx));
                return self.container.measure(constraints);
            }

            pub fn getTypeName(ctx: *anyopaque) []const u8 {
                _ = ctx;
                return "ContainerWidget";
            }
        };

        const widget_impl = try allocator.create(ContainerWidget);
        widget_impl.* = .{
            .container = Container.init(allocator),
        };

        // Set container direction
        widget_impl.container.direction = direction;

        const vtable = try allocator.create(WidgetVTable);
        vtable.* = .{
            .render = ContainerWidget.render,
            .handle_input = ContainerWidget.handleInput,
            .measure = ContainerWidget.measure,
            .get_type_name = ContainerWidget.getTypeName,
        };

        const widget = try allocator.create(Widget);
        widget.* = Widget.init(widget_impl, vtable, try allocator.dupe(u8, id), bounds);

        return widget;
    }
};

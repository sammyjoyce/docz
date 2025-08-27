//! Container Widget Implementation
//! Example of a composition widget using the improved widget interface

const std = @import("std");
const widget_interface = @import("../../core/widget_interface.zig");
const unified_renderer = @import("../../core/unified_renderer.zig");
const Allocator = std.mem.Allocator;

/// Container widget implementation that wraps the Container struct
pub const ContainerWidget = struct {
    container: widget_interface.Container,
    allocator: Allocator,

    /// Create a new container widget
    pub fn init(allocator: Allocator, direction: enum { horizontal, vertical }) !*ContainerWidget {
        const widget = try allocator.create(ContainerWidget);
        widget.* = .{
            .container = widget_interface.Container.init(allocator),
            .allocator = allocator,
        };
        widget.container.direction = direction;
        return widget;
    }

    /// Create a Widget interface for this container
    pub fn createWidget(self: *ContainerWidget, id: []const u8, bounds: widget_interface.Rect) !*widget_interface.Widget {
        const vtable = try self.allocator.create(widget_interface.WidgetVTable);
        vtable.* = .{
            .render = render,
            .handle_input = handleInput,
            .measure = measure,
            .get_type_name = getTypeName,
        };

        const widget = try self.allocator.create(widget_interface.Widget);
        widget.* = widget_interface.Widget.init(self, vtable, try self.allocator.dupe(u8, id), bounds);

        return widget;
    }

    /// Render the container
    pub fn render(ctx: *anyopaque, renderer: *unified_renderer.UnifiedRenderer, area: widget_interface.Rect) !void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        try self.container.render(renderer, area);
    }

    /// Handle input events
    pub fn handleInput(ctx: *anyopaque, event: widget_interface.InputEvent, area: widget_interface.Rect) !bool {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        return try self.container.handleInput(event, area);
    }

    /// Measure the container's desired size
    pub fn measure(ctx: *anyopaque, constraints: widget_interface.Constraints) widget_interface.Size {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        return self.container.measure(constraints);
    }

    /// Get widget type name
    pub fn getTypeName(ctx: *anyopaque) []const u8 {
        _ = ctx;
        return "ContainerWidget";
    }

    /// Add a child widget
    pub fn addChild(self: *ContainerWidget, child: *widget_interface.Widget) !void {
        try self.container.addChild(child);
    }

    /// Remove a child widget
    pub fn removeChild(self: *ContainerWidget, child: *widget_interface.Widget) void {
        self.container.removeChild(child);
    }

    /// Set container direction
    pub fn setDirection(self: *ContainerWidget, direction: enum { horizontal, vertical }) void {
        self.container.direction = direction;
    }

    /// Set spacing between children
    pub fn setSpacing(self: *ContainerWidget, spacing: u16) void {
        self.container.spacing = spacing;
    }

    /// Set padding
    pub fn setPadding(self: *ContainerWidget, top: u16, right: u16, bottom: u16, left: u16) void {
        self.container.padding = .{
            .top = top,
            .right = right,
            .bottom = bottom,
            .left = left,
        };
    }

    /// Set background color
    pub fn setBackground(self: *ContainerWidget, color: unified_renderer.Color) void {
        self.container.background = color;
    }

    /// Set border
    pub fn setBorder(self: *ContainerWidget, color: unified_renderer.Color, style: enum { single, double, rounded }) void {
        self.container.border = .{
            .color = color,
            .style = style,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *ContainerWidget) void {
        self.container.deinit();
        self.allocator.destroy(self);
    }
};

/// Convenience function to create a container widget
pub fn createContainer(
    allocator: Allocator,
    id: []const u8,
    bounds: widget_interface.Rect,
    direction: enum { horizontal, vertical },
) !*widget_interface.Widget {
    const container = try ContainerWidget.init(allocator, direction);
    return try container.createWidget(id, bounds);
}
//! Button Widget Implementation
//! Example of a custom widget using the improved widget interface

const std = @import("std");
const widget_interface = @import("../../core/widget_interface.zig");
const unified_renderer = @import("../../core/unified_renderer.zig");
const Allocator = std.mem.Allocator;

/// Button widget state
pub const ButtonState = struct {
    label: []const u8,
    enabled: bool = true,
    pressed: bool = false,
    on_click: ?*const fn (*widget_interface.Widget) void = null,
};

/// Button widget implementation
pub const ButtonWidget = struct {
    state: ButtonState,
    allocator: Allocator,

    /// Create a new button widget
    pub fn init(allocator: Allocator, label: []const u8, on_click: ?*const fn (*widget_interface.Widget) void) !*ButtonWidget {
        const widget = try allocator.create(ButtonWidget);
        widget.* = .{
            .state = .{
                .label = try allocator.dupe(u8, label),
                .on_click = on_click,
            },
            .allocator = allocator,
        };
        return widget;
    }

    /// Create a Widget interface for this button
    pub fn createWidget(self: *ButtonWidget, id: []const u8, bounds: widget_interface.Rect) !*widget_interface.Widget {
        const vtable = try self.allocator.create(widget_interface.WidgetVTable);
        vtable.* = .{
            .render = render,
            .handle_input = handleInput,
            .measure = measure,
            .get_type_name = getTypeName,
            .on_focus_change = onFocusChange,
        };

        const widget = try self.allocator.create(widget_interface.Widget);
        widget.* = widget_interface.Widget.init(self, vtable, try self.allocator.dupe(u8, id), bounds);

        return widget;
    }

    /// Render the button
    pub fn render(ctx: *anyopaque, renderer: *unified_renderer.UnifiedRenderer, area: widget_interface.Rect) !void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        // Choose colors based on state
        const bg_color = if (self.state.pressed)
            unified_renderer.Color.BLUE
        else if (renderer.focused_widget != null and renderer.focused_widget.?.ptr == ctx)
            unified_renderer.Color.CYAN
        else
            unified_renderer.Color.GRAY;

        const fg_color = if (self.state.enabled)
            unified_renderer.Color.WHITE
        else
            unified_renderer.Color.GRAY;

        // Draw button background
        const button_text = try std.fmt.allocPrint(self.allocator, "[ {s} ]", .{self.state.label});
        defer self.allocator.free(button_text);

        try renderer.drawText(area.x, area.y, button_text, fg_color, bg_color);
    }

    /// Handle input events
    pub fn handleInput(ctx: *anyopaque, event: widget_interface.InputEvent, area: widget_interface.Rect) !bool {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        if (!self.state.enabled) return false;

        switch (event) {
            .key => |key_event| {
                if (key_event.key == .enter or (key_event.key == .char and key_event.key.char == ' ')) {
                    try self.handleClick();
                    return true;
                }
            },
            .mouse => |mouse_event| {
                if (mouse_event.action == .press and mouse_event.button == .left) {
                    const mouse_point = widget_interface.Point{
                        .x = @intCast(mouse_event.x),
                        .y = @intCast(mouse_event.y),
                    };

                    if (area.contains(mouse_point)) {
                        try self.handleClick();
                        return true;
                    }
                }
            },
            else => {},
        }

        return false;
    }

    /// Measure the button's desired size
    pub fn measure(ctx: *anyopaque, constraints: widget_interface.Constraints) widget_interface.Size {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        const width = @as(u16, @intCast(self.state.label.len + 4)); // [ label ]
        const height = 1;

        return .{
            .width = std.math.clamp(width, constraints.min_width, constraints.max_width),
            .height = std.math.clamp(height, constraints.min_height, constraints.max_height),
        };
    }

    /// Get widget type name
    pub fn getTypeName(ctx: *anyopaque) []const u8 {
        _ = ctx;
        return "ButtonWidget";
    }

    /// Handle focus changes
    pub fn onFocusChange(ctx: *anyopaque, focused: bool) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        // Could update visual state here
        _ = self;
        _ = focused;
    }

    /// Handle button click
    fn handleClick(self: *ButtonWidget) !void {
        if (self.state.on_click) |callback| {
            // In a real implementation, we'd pass the actual widget
            // For now, we'll pass null and let the callback handle it
            callback(null);
        }
    }

    /// Set button label
    pub fn setLabel(self: *ButtonWidget, label: []const u8) !void {
        self.allocator.free(self.state.label);
        self.state.label = try self.allocator.dupe(u8, label);
    }

    /// Set enabled state
    pub fn setEnabled(self: *ButtonWidget, enabled: bool) void {
        self.state.enabled = enabled;
    }

    /// Set click handler
    pub fn setOnClick(self: *ButtonWidget, on_click: ?*const fn (*widget_interface.Widget) void) void {
        self.state.on_click = on_click;
    }

    /// Clean up resources
    pub fn deinit(self: *ButtonWidget) void {
        self.allocator.free(self.state.label);
        self.allocator.destroy(self);
    }
};

/// Convenience function to create a button widget
pub fn createButton(
    allocator: Allocator,
    id: []const u8,
    label: []const u8,
    bounds: widget_interface.Rect,
    on_click: ?*const fn (*widget_interface.Widget) void,
) !*widget_interface.Widget {
    const button = try ButtonWidget.init(allocator, label, on_click);
    return try button.createWidget(id, bounds);
}
</xai:function_call name="write">
<parameter name="filePath">src/shared/tui/widgets/core/text_input_widget.zig
//! Text Input Widget Implementation
//! Example of a custom widget using the improved widget interface

const std = @import("std");
const widget_interface = @import("../../core/widget_interface.zig");
const renderer_mod = @import("../../core/renderer.zig");
const Allocator = std.mem.Allocator;

/// Text input widget state
pub const TextInputState = struct {
    content: std.ArrayList(u8),
    cursor_pos: usize,
    placeholder: []const u8,
    is_password: bool = false,
    max_length: ?usize = null,
    on_change: ?*const fn (*widget_interface.Widget, []const u8) void = null,
};

/// Text input widget implementation
pub const TextInput = struct {
    state: TextInputState,
    allocator: Allocator,

    /// Create a new text input widget
    pub fn init(allocator: Allocator, placeholder: []const u8) !*TextInput {
        const widget = try allocator.create(TextInput);
        widget.* = .{
            .state = .{
                .content = std.ArrayList(u8).init(allocator),
                .cursor_pos = 0,
                .placeholder = try allocator.dupe(u8, placeholder),
            },
            .allocator = allocator,
        };
        return widget;
    }

    /// Create a Widget interface for this text input
    pub fn createWidget(self: *TextInput, id: []const u8, bounds: widget_interface.Rect) !*widget_interface.Widget {
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

    /// Render the text input
    pub fn render(ctx: *anyopaque, renderer: *renderer_mod.Renderer, area: widget_interface.Rect) !void {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        // Draw border
        const border_ctx = renderer_mod.Render{
            .bounds = area.toBounds(),
            .style = .{},
            .zIndex = 0,
            .clipRegion = null,
        };
        try renderer.drawBox(border_ctx, .{});

        // Calculate inner area
        const inner_area = widget_interface.Rect{
            .x = area.x + 1,
            .y = area.y + 1,
            .width = area.width -| 2,
            .height = area.height -| 2,
        };

        // Draw content or placeholder
        const display_text = if (self.state.content.items.len > 0)
            self.state.content.items
        else
            self.state.placeholder;

        const fg_color = if (self.state.content.items.len > 0)
            renderer_mod.Style.Color{ .palette = 15 } // White
        else
            renderer_mod.Style.Color{ .palette = 8 }; // Gray

        // Handle text that might be longer than the available space
        const max_display_len = @min(display_text.len, inner_area.width);
        const display_slice = display_text[0..max_display_len];

        const text_ctx = renderer_mod.Render{
            .bounds = inner_area.toBounds(),
            .style = .{ .fg_color = fg_color },
            .zIndex = 0,
            .clipRegion = null,
        };
        try renderer.drawText(text_ctx, display_slice);

        // Note: Cursor drawing would need to be handled differently with the new renderer
        // This is a simplified version - proper cursor handling would require more work
    }

    /// Handle input events
    pub fn handleInput(ctx: *anyopaque, event: widget_interface.InputEvent, area: widget_interface.Rect) !bool {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        switch (event) {
            .key => |key_event| {
                switch (key_event.key) {
                    .char => |ch| {
                        try self.insertChar(ch);
                        return true;
                    },
                    .backspace => {
                        self.deleteChar();
                        return true;
                    },
                    .delete => {
                        self.deleteForward();
                        return true;
                    },
                    .arrow_left => {
                        self.moveCursorLeft();
                        return true;
                    },
                    .arrow_right => {
                        self.moveCursorRight();
                        return true;
                    },
                    .home => {
                        self.moveCursorHome();
                        return true;
                    },
                    .end => {
                        self.moveCursorEnd();
                        return true;
                    },
                    else => {},
                }
            },
            .mouse => |mouse_event| {
                if (mouse_event.action == .press and mouse_event.button == .left) {
                    const mouse_point = widget_interface.Point{
                        .x = @intCast(mouse_event.x),
                        .y = @intCast(mouse_event.y),
                    };

                    if (area.contains(mouse_point)) {
                        // Calculate cursor position based on mouse click
                        const inner_x = mouse_point.x - area.x - 1;
                        const clicked_pos = @min(@as(usize, @intCast(inner_x)), self.state.content.items.len);
                        self.state.cursor_pos = clicked_pos;
                        return true;
                    }
                }
            },
            else => {},
        }

        return false;
    }

    /// Measure the widget's desired size
    pub fn measure(ctx: *anyopaque, constraints: widget_interface.Constraints) widget_interface.Size {
        const self: *@This() = @ptrCast(@alignCast(ctx));

        // Base size for input field
        const min_width = @as(u16, @intCast(self.state.placeholder.len + 4)); // placeholder + borders + padding
        const width = std.math.clamp(min_width, constraints.min_width, constraints.max_width);
        const height = std.math.clamp(3, constraints.min_height, constraints.max_height); // 1 line + borders

        return .{
            .width = width,
            .height = height,
        };
    }

    /// Get widget type name
    pub fn getTypeName(ctx: *anyopaque) []const u8 {
        _ = ctx;
        return "TextInput";
    }

    /// Handle focus changes
    pub fn onFocusChange(ctx: *anyopaque, focused: bool) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        // Could update visual state here
        _ = self;
        _ = focused;
    }

    /// Insert character at cursor position
    fn insertChar(self: *TextInput, ch: u8) !void {
        if (self.state.max_length) |max| {
            if (self.state.content.items.len >= max) return;
        }

        try self.state.content.insert(self.state.cursor_pos, ch);
        self.state.cursor_pos += 1;

        // Notify listener
        if (self.state.on_change) |callback| {
            callback(null, self.state.content.items);
        }
    }

    /// Delete character before cursor
    fn deleteChar(self: *TextInput) void {
        if (self.state.cursor_pos > 0) {
            _ = self.state.content.orderedRemove(self.state.cursor_pos - 1);
            self.state.cursor_pos -= 1;

            // Notify listener
            if (self.state.on_change) |callback| {
                callback(null, self.state.content.items);
            }
        }
    }

    /// Delete character after cursor
    fn deleteForward(self: *TextInput) void {
        if (self.state.cursor_pos < self.state.content.items.len) {
            _ = self.state.content.orderedRemove(self.state.cursor_pos);

            // Notify listener
            if (self.state.on_change) |callback| {
                callback(null, self.state.content.items);
            }
        }
    }

    /// Move cursor left
    fn moveCursorLeft(self: *TextInput) void {
        if (self.state.cursor_pos > 0) {
            self.state.cursor_pos -= 1;
        }
    }

    /// Move cursor right
    fn moveCursorRight(self: *TextInput) void {
        if (self.state.cursor_pos < self.state.content.items.len) {
            self.state.cursor_pos += 1;
        }
    }

    /// Move cursor to home
    fn moveCursorHome(self: *TextInput) void {
        self.state.cursor_pos = 0;
    }

    /// Move cursor to end
    fn moveCursorEnd(self: *TextInput) void {
        self.state.cursor_pos = self.state.content.items.len;
    }

    /// Get current text
    pub fn getText(self: TextInput) []const u8 {
        return self.state.content.items;
    }

    /// Set text content
    pub fn setText(self: *TextInput, text: []const u8) !void {
        self.state.content.clearAndFree();
        try self.state.content.appendSlice(text);
        self.state.cursor_pos = @min(self.state.cursor_pos, self.state.content.items.len);

        // Notify listener
        if (self.state.on_change) |callback| {
            callback(null, self.state.content.items);
        }
    }

    /// Set placeholder text
    pub fn setPlaceholder(self: *TextInput, placeholder: []const u8) !void {
        self.allocator.free(self.state.placeholder);
        self.state.placeholder = try self.allocator.dupe(u8, placeholder);
    }

    /// Set change callback
    pub fn setOnChange(self: *TextInput, on_change: ?*const fn (*widget_interface.Widget, []const u8) void) void {
        self.state.on_change = on_change;
    }

    /// Set max length
    pub fn setMaxLength(self: *TextInput, max_length: ?usize) void {
        self.state.max_length = max_length;
    }

    /// Set password mode
    pub fn setPassword(self: *TextInput, is_password: bool) void {
        self.state.is_password = is_password;
    }

    /// Clean up resources
    pub fn deinit(self: *TextInput) void {
        self.state.content.deinit();
        self.allocator.free(self.state.placeholder);
        self.allocator.destroy(self);
    }
};

/// Convenience function to create a text input widget
pub fn createTextInput(
    allocator: Allocator,
    id: []const u8,
    placeholder: []const u8,
    bounds: widget_interface.Rect,
) !*widget_interface.Widget {
    const text_input = try TextInput.init(allocator, placeholder);
    return try text_input.createWidget(id, bounds);
}

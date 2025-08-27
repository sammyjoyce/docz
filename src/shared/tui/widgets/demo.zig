//! Demo Widget for Unified TUI System
//! Shows how to create widgets using the new unified architecture

const std = @import("std");
const renderer_mod = @import("../core/renderer.zig");

const Widget = renderer_mod.Widget;
const UnifiedRenderer = renderer_mod.UnifiedRenderer;
const InputEvent = renderer_mod.InputEvent;
const Rect = renderer_mod.Rect;
const Size = renderer_mod.Size;
const Color = @import("../../term/unified.zig").Color;

/// A demo panel widget that showcases TUI capabilities
pub const DemoPanel = struct {
    const Self = @This();

    // Widget base
    widget: Widget,

    // Panel-specific data
    allocator: std.mem.Allocator,
    title: []const u8,
    content: std.ArrayList([]const u8),
    selected_line: usize,

    pub fn init(allocator: std.mem.Allocator, bounds: Rect, title: []const u8) !*Self {
        const self = try allocator.create(Self);

        self.* = Self{
            .widget = Widget.init(bounds),
            .allocator = allocator,
            .title = try allocator.dupe(u8, title),
            .content = std.ArrayList([]const u8).init(allocator),
            .selected_line = 0,
        };

        // Set up widget function pointers
        self.widget.render = renderImpl;
        self.widget.handleInput = handleInputImpl;
        self.widget.measure = measureImpl;

        // Add some demo content
        try self.addLine("📊 Unified TUI System Demo");
        try self.addLine("✨ Progressive Enhancement");
        try self.addLine("🎨 Theme System Integration");
        try self.addLine("⚡ Advanced Terminal Features");
        try self.addLine("🖱️  Mouse & Keyboard Support");
        try self.addLine("📐 Layout Engine");
        try self.addLine("🎯 Focus Management");

        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.content.items) |line| {
            self.allocator.free(line);
        }
        self.content.deinit();
        self.allocator.free(self.title);
        self.allocator.destroy(self);
    }

    pub fn asWidget(self: *Self) *Widget {
        return &self.widget;
    }

    pub fn addLine(self: *Self, text: []const u8) !void {
        try self.content.append(try self.allocator.dupe(u8, text));
    }

    fn renderImpl(widget: *Widget, renderer: *UnifiedRenderer) !void {
        const self: *Self = @fieldParentPtr("widget", widget);
        const theme = renderer.getTheme();

        // Draw panel background and border
        try renderer.drawBox(widget.bounds, true, self.title);

        // Calculate content area (inside border)
        const content_bounds = Rect{
            .x = widget.bounds.x + 1,
            .y = widget.bounds.y + 1,
            .width = widget.bounds.width - 2,
            .height = widget.bounds.height - 2,
        };

        // Draw content lines
        const visible_lines = @min(self.content.items.len, content_bounds.height);
        for (0..visible_lines) |i| {
            const line = self.content.items[i];
            const y = content_bounds.y + @as(i16, @intCast(i));

            // Highlight selected line
            const color = if (i == self.selected_line and widget.focused)
                theme.selected
            else
                theme.foreground;
            const background = if (i == self.selected_line and widget.focused)
                theme.focused
            else
                null;

            // Truncate line to fit width
            const max_len = @min(line.len, content_bounds.width);
            const display_text = line[0..max_len];

            try renderer.drawText(content_bounds.x, y, display_text, color, background);

            // Fill rest of line if selected
            if (i == self.selected_line and widget.focused and max_len < content_bounds.width) {
                const padding = content_bounds.width - max_len;
                var pad_buffer: [256]u8 = undefined;
                @memset(pad_buffer[0..@min(padding, pad_buffer.len)], ' ');
                const pad_text = pad_buffer[0..@min(padding, pad_buffer.len)];
                try renderer.drawText(content_bounds.x + @as(i16, @intCast(max_len)), y, pad_text, color, background);
            }
        }

        // Draw focus indicator
        if (widget.focused) {
            const terminal = renderer.getTerminal();
            if (terminal.hasFeature(.truecolor)) {
                const focus_color = Color.rgb(100, 149, 237); // Cornflower blue
                try renderer.drawText(widget.bounds.x + @as(i16, @intCast(widget.bounds.width)) - 3, widget.bounds.y, "●", focus_color, null);
            } else {
                try renderer.drawText(widget.bounds.x + @as(i16, @intCast(widget.bounds.width)) - 3, widget.bounds.y, "*", theme.focused, null);
            }
        }
    }

    fn handleInputImpl(widget: *Widget, input: InputEvent) !bool {
        const self: *Self = @fieldParentPtr("widget", widget);

        switch (input) {
            .key => |key_event| {
                switch (key_event.key) {
                    .arrow_up => {
                        if (self.selected_line > 0) {
                            self.selected_line -= 1;
                        }
                        return true;
                    },
                    .arrow_down => {
                        if (self.selected_line + 1 < self.content.items.len) {
                            self.selected_line += 1;
                        }
                        return true;
                    },
                    .home => {
                        self.selected_line = 0;
                        return true;
                    },
                    .end => {
                        self.selected_line = if (self.content.items.len > 0)
                            self.content.items.len - 1
                        else
                            0;
                        return true;
                    },
                    .enter => {
                        // Could trigger an action on the selected item
                        return true;
                    },
                    else => {},
                }
            },
            .mouse => |mouse_event| {
                if (widget.bounds.contains(.{ .x = @intCast(mouse_event.x), .y = @intCast(mouse_event.y) })) {
                    switch (mouse_event.action) {
                        .press => {
                            // Calculate which line was clicked
                            const rel_y = @as(i16, @intCast(mouse_event.y)) - (widget.bounds.y + 1);
                            if (rel_y >= 0 and rel_y < @as(i16, @intCast(self.content.items.len))) {
                                self.selected_line = @as(usize, @intCast(rel_y));
                            }
                            return true;
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }

        return false;
    }

    fn measureImpl(widget: *Widget, available: Size) Size {
        const self: *Self = @fieldParentPtr("widget", widget);

        // Calculate preferred size based on content
        var max_width: u16 = self.title.len + 4; // Title + border
        for (self.content.items) |line| {
            max_width = @max(max_width, @as(u16, @intCast(line.len + 2))); // Content + border
        }

        const preferred_height: u16 = @as(u16, @intCast(self.content.items.len + 2)); // Content + border

        return Size{
            .width = @min(max_width, available.width),
            .height = @min(preferred_height, available.height),
        };
    }
};

/// A simple button widget
pub const Button = struct {
    const Self = @This();

    // Widget base
    widget: Widget,

    // Button-specific data
    allocator: std.mem.Allocator,
    text: []const u8,
    pressed: bool,
    on_click: ?*const fn () void,

    pub fn init(allocator: std.mem.Allocator, bounds: Rect, text: []const u8) !*Self {
        const self = try allocator.create(Self);

        self.* = Self{
            .widget = Widget.init(bounds),
            .allocator = allocator,
            .text = try allocator.dupe(u8, text),
            .pressed = false,
            .on_click = null,
        };

        // Set up widget function pointers
        self.widget.render = renderButtonImpl;
        self.widget.handleInput = handleButtonInputImpl;
        self.widget.measure = measureButtonImpl;

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.text);
        self.allocator.destroy(self);
    }

    pub fn asWidget(self: *Self) *Widget {
        return &self.widget;
    }

    pub fn setOnClick(self: *Self, callback: *const fn () void) void {
        self.on_click = callback;
    }

    fn renderButtonImpl(widget: *Widget, renderer: *UnifiedRenderer) !void {
        const self: *Self = @fieldParentPtr("widget", widget);
        const theme = renderer.getTheme();

        // Choose colors based on state
        const bg_color = if (self.pressed)
            theme.selected
        else if (widget.focused)
            theme.focused
        else
            theme.accent;

        const fg_color = if (widget.focused or self.pressed)
            theme.background
        else
            theme.foreground;

        // Draw button background
        for (0..widget.bounds.height) |row| {
            const y = widget.bounds.y + @as(i16, @intCast(row));
            var buffer: [256]u8 = undefined;
            @memset(buffer[0..@min(widget.bounds.width, buffer.len)], ' ');
            const bg_text = buffer[0..@min(widget.bounds.width, buffer.len)];
            try renderer.drawText(widget.bounds.x, y, bg_text, fg_color, bg_color);
        }

        // Draw button text (centered)
        const text_x = widget.bounds.x + @as(i16, @intCast((widget.bounds.width - @min(self.text.len, widget.bounds.width)) / 2));
        const text_y = widget.bounds.y + @as(i16, @intCast(widget.bounds.height / 2));
        const display_text = self.text[0..@min(self.text.len, widget.bounds.width)];
        try renderer.drawText(text_x, text_y, display_text, fg_color, bg_color);

        // Draw border for focused button
        if (widget.focused) {
            try renderer.drawBox(widget.bounds, true, null);
        }
    }

    fn handleButtonInputImpl(widget: *Widget, input: InputEvent) !bool {
        const self: *Self = @fieldParentPtr("widget", widget);

        switch (input) {
            .key => |key_event| {
                switch (key_event.key) {
                    .enter => {
                        if (self.on_click) |callback| {
                            callback();
                        }
                        return true;
                    },
                    else => {},
                }
            },
            .mouse => |mouse_event| {
                if (widget.bounds.contains(.{ .x = @intCast(mouse_event.x), .y = @intCast(mouse_event.y) })) {
                    switch (mouse_event.action) {
                        .press => {
                            self.pressed = true;
                            return true;
                        },
                        .release => {
                            if (self.pressed) {
                                self.pressed = false;
                                if (self.on_click) |callback| {
                                    callback();
                                }
                            }
                            return true;
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }

        return false;
    }

    fn measureButtonImpl(widget: *Widget, available: Size) Size {
        const self: *Self = @fieldParentPtr("widget", widget);

        return Size{
            .width = @min(@as(u16, @intCast(self.text.len + 4)), available.width), // Text + padding
            .height = @min(3, available.height), // Fixed height for buttons
        };
    }
};

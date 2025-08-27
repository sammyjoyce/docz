//! Unified TUI Renderer
//! Consolidates the fragmented TUI systems from src/tui/ and src/ui/
//! Provides a single, coherent interface with progressive enhancement

const std = @import("std");
const unified_terminal = @import("../../cli/core/unified_terminal.zig");
const graphics_manager = @import("../term/graphics_manager.zig");

const Allocator = std.mem.Allocator;
const UnifiedTerminal = unified_terminal.UnifiedTerminal;
const Color = unified_terminal.Color;
const GraphicsManager = graphics_manager.GraphicsManager;

/// Widget rendering interface
pub const Widget = struct {
    const Self = @This();

    // Core widget data
    bounds: Rect,
    visible: bool,
    focused: bool,

    // Function pointers for widget behavior
    render: *const fn (self: *Widget, renderer: *UnifiedRenderer) anyerror!void,
    handleInput: *const fn (self: *Widget, input: InputEvent) anyerror!bool,
    measure: *const fn (self: *Widget, available: Size) Size,

    // Optional advanced features
    onFocusChanged: ?*const fn (self: *Widget, focused: bool) void,
    onBoundsChanged: ?*const fn (self: *Widget, old_bounds: Rect) void,

    pub fn init(bounds: Rect) Widget {
        return Widget{
            .bounds = bounds,
            .visible = true,
            .focused = false,
            .render = defaultRender,
            .handleInput = defaultHandleInput,
            .measure = defaultMeasure,
            .onFocusChanged = null,
            .onBoundsChanged = null,
        };
    }

    fn defaultRender(self: *Widget, renderer: *UnifiedRenderer) !void {
        _ = self;
        _ = renderer;
        // Default empty render
    }

    fn defaultHandleInput(self: *Widget, input: InputEvent) !bool {
        _ = self;
        _ = input;
        return false; // Not handled
    }

    fn defaultMeasure(self: *Widget, available: Size) Size {
        _ = self;
        return available;
    }
};

/// Geometric primitives
pub const Point = struct {
    x: i16,
    y: i16,
};

pub const Size = struct {
    width: u16,
    height: u16,
};

pub const Rect = struct {
    x: i16,
    y: i16,
    width: u16,
    height: u16,

    pub fn contains(self: Rect, point: Point) bool {
        return point.x >= self.x and
            point.x < self.x + @as(i16, @intCast(self.width)) and
            point.y >= self.y and
            point.y < self.y + @as(i16, @intCast(self.height));
    }

    pub fn intersects(self: Rect, other: Rect) bool {
        return !(self.x + @as(i16, @intCast(self.width)) <= other.x or
            other.x + @as(i16, @intCast(other.width)) <= self.x or
            self.y + @as(i16, @intCast(self.height)) <= other.y or
            other.y + @as(i16, @intCast(other.height)) <= self.y);
    }
};

/// Input event types
pub const InputEvent = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    resize: Size,
    focus: bool,

    pub const KeyEvent = struct {
        key: Key,
        modifiers: Modifiers,
    };

    pub const MouseEvent = struct {
        x: u16,
        y: u16,
        button: MouseButton,
        action: MouseAction,
    };

    pub const Key = enum {
        char,
        enter,
        escape,
        tab,
        backspace,
        delete,
        arrow_up,
        arrow_down,
        arrow_left,
        arrow_right,
        home,
        end,
        page_up,
        page_down,
        f1,
        f2,
        f3,
        f4,
        f5,
        f6,
        f7,
        f8,
        f9,
        f10,
        f11,
        f12,
    };

    pub const Modifiers = struct {
        ctrl: bool = false,
        alt: bool = false,
        shift: bool = false,
    };

    pub const MouseButton = enum {
        left,
        right,
        middle,
        wheel_up,
        wheel_down,
    };

    pub const MouseAction = enum {
        press,
        release,
        move,
        drag,
    };
};

/// Layout system
pub const Layout = struct {
    pub const Direction = enum {
        horizontal,
        vertical,
    };

    pub const Alignment = enum {
        start,
        center,
        end,
        stretch,
    };

    /// Simple flex layout implementation
    pub fn flexLayout(
        container: Rect,
        children: []Widget,
        direction: Direction,
        alignment: Alignment,
    ) void {
        if (children.len == 0) return;

        const available_space = switch (direction) {
            .horizontal => container.width,
            .vertical => container.height,
        };

        const child_size = available_space / @as(u16, @intCast(children.len));

        for (children, 0..) |*child, i| {
            const index = @as(u16, @intCast(i));
            switch (direction) {
                .horizontal => {
                    child.bounds = Rect{
                        .x = container.x + @as(i16, @intCast(index * child_size)),
                        .y = container.y,
                        .width = child_size,
                        .height = container.height,
                    };
                },
                .vertical => {
                    child.bounds = Rect{
                        .x = container.x,
                        .y = container.y + @as(i16, @intCast(index * child_size)),
                        .width = container.width,
                        .height = child_size,
                    };
                },
            }

            // Apply alignment
            switch (alignment) {
                .start => {}, // Already positioned at start
                .center => {
                    // Center the widget in its allocated space
                    const measured = child.measure(child, Size{ .width = child.bounds.width, .height = child.bounds.height });
                    switch (direction) {
                        .horizontal => {
                            const extra_height = child.bounds.height - measured.height;
                            child.bounds.y += @as(i16, @intCast(extra_height / 2));
                            child.bounds.height = measured.height;
                        },
                        .vertical => {
                            const extra_width = child.bounds.width - measured.width;
                            child.bounds.x += @as(i16, @intCast(extra_width / 2));
                            child.bounds.width = measured.width;
                        },
                    }
                },
                .end => {
                    // Align to end of allocated space
                    const measured = child.measure(child, Size{ .width = child.bounds.width, .height = child.bounds.height });
                    switch (direction) {
                        .horizontal => {
                            child.bounds.y += @as(i16, @intCast(child.bounds.height - measured.height));
                            child.bounds.height = measured.height;
                        },
                        .vertical => {
                            child.bounds.x += @as(i16, @intCast(child.bounds.width - measured.width));
                            child.bounds.width = measured.width;
                        },
                    }
                },
                .stretch => {}, // Already stretched to fill space
            }
        }
    }
};

/// Theme system with progressive enhancement
pub const Theme = struct {
    // Basic colors
    background: Color,
    foreground: Color,
    accent: Color,

    // State colors
    focused: Color,
    selected: Color,
    disabled: Color,

    // Status colors
    success: Color,
    warning: Color,
    danger: Color,

    pub fn defaultLight() Theme {
        return Theme{
            .background = Color.WHITE,
            .foreground = Color.BLACK,
            .accent = Color.BLUE,
            .focused = Color.CYAN,
            .selected = Color.YELLOW,
            .disabled = Color.GRAY,
            .success = Color.GREEN,
            .warning = Color.ORANGE,
            .danger = Color.RED,
        };
    }

    pub fn defaultDark() Theme {
        return Theme{
            .background = Color.BLACK,
            .foreground = Color.WHITE,
            .accent = Color.CYAN,
            .focused = Color.BLUE,
            .selected = Color.PURPLE,
            .disabled = Color.GRAY,
            .success = Color.GREEN,
            .warning = Color.ORANGE,
            .danger = Color.RED,
        };
    }
};

/// Unified renderer that consolidates TUI systems
pub const UnifiedRenderer = struct {
    const Self = @This();

    allocator: Allocator,
    terminal: UnifiedTerminal,
    theme: Theme,
    widgets: std.ArrayList(*Widget),
    focused_widget: ?*Widget,
    needs_redraw: bool,

    pub fn init(allocator: Allocator, theme: Theme) !Self {
        const terminal = try UnifiedTerminal.init(allocator);

        return Self{
            .allocator = allocator,
            .terminal = terminal,
            .theme = theme,
            .widgets = std.ArrayList(*Widget).init(allocator),
            .focused_widget = null,
            .needs_redraw = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.widgets.deinit();
        self.terminal.deinit();
    }

    /// Add a widget to the renderer
    pub fn addWidget(self: *Self, widget: *Widget) !void {
        try self.widgets.append(widget);

        // Focus the first widget if none is focused
        if (self.focused_widget == null) {
            self.setFocus(widget);
        }

        self.needs_redraw = true;
    }

    /// Remove a widget from the renderer
    pub fn removeWidget(self: *Self, widget: *Widget) void {
        for (self.widgets.items, 0..) |w, i| {
            if (w == widget) {
                _ = self.widgets.orderedRemove(i);

                // Update focus if removing focused widget
                if (self.focused_widget == widget) {
                    if (self.widgets.items.len > 0) {
                        self.setFocus(self.widgets.items[0]);
                    } else {
                        self.focused_widget = null;
                    }
                }

                self.needs_redraw = true;
                break;
            }
        }
    }

    /// Set focus to a specific widget
    pub fn setFocus(self: *Self, widget: *Widget) void {
        if (self.focused_widget) |old_focus| {
            old_focus.focused = false;
            if (old_focus.onFocusChanged) |callback| {
                callback(old_focus, false);
            }
        }

        widget.focused = true;
        self.focused_widget = widget;

        if (widget.onFocusChanged) |callback| {
            callback(widget, true);
        }

        self.needs_redraw = true;
    }

    /// Handle input events
    pub fn handleInput(self: *Self, event: InputEvent) !bool {
        // Try focused widget first
        if (self.focused_widget) |widget| {
            if (try widget.handleInput(widget, event)) {
                return true;
            }
        }

        // Try other widgets in reverse order (top-most first)
        var i: usize = self.widgets.items.len;
        while (i > 0) {
            i -= 1;
            const widget = self.widgets.items[i];
            if (widget != self.focused_widget) {
                if (try widget.handleInput(widget, event)) {
                    self.setFocus(widget);
                    return true;
                }
            }
        }

        // Handle system events
        switch (event) {
            .resize => |size| {
                self.handleResize(size);
                return true;
            },
            .key => |key_event| {
                return self.handleSystemKey(key_event);
            },
            else => {},
        }

        return false;
    }

    fn handleResize(self: *Self, size: Size) void {
        _ = size;
        // Trigger layout recalculation
        self.needs_redraw = true;
    }

    fn handleSystemKey(self: *Self, key_event: InputEvent.KeyEvent) bool {
        switch (key_event.key) {
            .tab => {
                // Cycle focus between widgets
                if (self.widgets.items.len > 1) {
                    var next_index: usize = 0;

                    if (self.focused_widget) |current| {
                        for (self.widgets.items, 0..) |widget, i| {
                            if (widget == current) {
                                next_index = (i + 1) % self.widgets.items.len;
                                break;
                            }
                        }
                    }

                    self.setFocus(self.widgets.items[next_index]);
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    /// Render all widgets to the terminal
    pub fn render(self: *Self) !void {
        if (!self.needs_redraw) return;

        try self.terminal.beginSynchronizedOutput();
        defer self.terminal.endSynchronizedOutput() catch {};

        // Clear screen
        try self.terminal.clearScreen();

        // Set theme background
        try self.terminal.setBackground(self.theme.background);
        try self.terminal.setForeground(self.theme.foreground);

        // Render all widgets in order
        for (self.widgets.items) |widget| {
            if (widget.visible) {
                try widget.render(widget, self);
            }
        }

        try self.terminal.resetStyles();
        try self.terminal.flush();

        self.needs_redraw = false;
    }

    /// Force a redraw on the next render cycle
    pub fn invalidate(self: *Self) void {
        self.needs_redraw = true;
    }

    /// Get the current theme
    pub fn getTheme(self: Self) Theme {
        return self.theme;
    }

    /// Set a new theme
    pub fn setTheme(self: *Self, theme: Theme) void {
        self.theme = theme;
        self.needs_redraw = true;
    }

    /// Get terminal capabilities for progressive enhancement
    pub fn getTerminal(self: *Self) *UnifiedTerminal {
        return &self.terminal;
    }

    /// Draw text at a specific position with optional styling
    pub fn drawText(self: *Self, x: i16, y: i16, text: []const u8, color: ?Color, background: ?Color) !void {
        try self.terminal.moveCursor(@intCast(y), @intCast(x));

        if (color) |fg| {
            try self.terminal.setForeground(fg);
        }

        if (background) |bg| {
            try self.terminal.setBackground(bg);
        }

        const w = self.terminal.writer();
        try w.writeAll(text);

        if (color != null or background != null) {
            try self.terminal.resetStyles();
        }
    }

    /// Draw a box with optional borders
    pub fn drawBox(self: *Self, bounds: Rect, border: bool, title: ?[]const u8) !void {
        if (border) {
            // Draw border using Unicode box-drawing characters
            const BoxChars = struct {
                const top_left = "┌";
                const top_right = "┐";
                const bottom_left = "└";
                const bottom_right = "┘";
                const horizontal = "─";
                const vertical = "│";
            };

            // Top border
            try self.drawText(bounds.x, bounds.y, BoxChars.top_left, null, null);
            for (1..bounds.width - 1) |i| {
                try self.drawText(bounds.x + @as(i16, @intCast(i)), bounds.y, BoxChars.horizontal, null, null);
            }
            try self.drawText(bounds.x + @as(i16, @intCast(bounds.width)) - 1, bounds.y, BoxChars.top_right, null, null);

            // Sides
            for (1..bounds.height - 1) |i| {
                try self.drawText(bounds.x, bounds.y + @as(i16, @intCast(i)), BoxChars.vertical, null, null);
                try self.drawText(bounds.x + @as(i16, @intCast(bounds.width)) - 1, bounds.y + @as(i16, @intCast(i)), BoxChars.vertical, null, null);
            }

            // Bottom border
            try self.drawText(bounds.x, bounds.y + @as(i16, @intCast(bounds.height)) - 1, BoxChars.bottom_left, null, null);
            for (1..bounds.width - 1) |i| {
                try self.drawText(bounds.x + @as(i16, @intCast(i)), bounds.y + @as(i16, @intCast(bounds.height)) - 1, BoxChars.horizontal, null, null);
            }
            try self.drawText(bounds.x + @as(i16, @intCast(bounds.width)) - 1, bounds.y + @as(i16, @intCast(bounds.height)) - 1, BoxChars.bottom_right, null, null);

            // Title
            if (title) |t| {
                const title_x = bounds.x + @as(i16, @intCast((bounds.width - @min(t.len, bounds.width - 4)) / 2));
                try self.drawText(title_x, bounds.y, " ", null, null);
                try self.drawText(title_x + 1, bounds.y, t[0..@min(t.len, bounds.width - 4)], null, null);
                try self.drawText(title_x + 1 + @as(i16, @intCast(@min(t.len, bounds.width - 4))), bounds.y, " ", null, null);
            }
        }
    }
};

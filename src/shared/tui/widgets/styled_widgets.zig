//! Styled widgets that integrate with the Stylize trait system
//! Provides enhanced versions of common widgets with fluent styling APIs

const std = @import("std");
const stylize = @import("../core/stylize.zig");
const renderer = @import("../core/renderer.zig");
const widget_interface = @import("../core/widget_interface.zig");

/// Enhanced Button widget with fluent styling APIs
pub const StyledButton = struct {
    label: []const u8,
    bounds: widget_interface.Rect,
    style: stylize.Style = stylize.Style{},
    hover_style: stylize.Style = stylize.Style{},
    pressed_style: stylize.Style = stylize.Style{},
    disabled_style: stylize.Style = stylize.Style{},
    state: State = .normal,
    allocator: std.mem.Allocator,

    pub const State = enum {
        normal,
        hover,
        pressed,
        disabled,
    };

    pub fn init(allocator: std.mem.Allocator, label: []const u8, bounds: widget_interface.Rect) !StyledButton {
        return StyledButton{
            .label = label,
            .bounds = bounds,
            .allocator = allocator,
        };
    }

    pub fn render(self: *const StyledButton, renderer_ctx: anytype) !void {
        const active_style = switch (self.state) {
            .normal => self.style,
            .hover => self.hover_style,
            .pressed => self.pressed_style,
            .disabled => self.disabled_style,
        };

        // Convert to renderer style and apply
        const render_style = active_style.toRendererStyle();
        try renderer_ctx.applyStyle(render_style);

        // Draw button
        try renderer_ctx.drawBox(self.bounds);
        try renderer_ctx.drawText(self.bounds.x + 2, self.bounds.y + 1, self.label);

        try renderer_ctx.resetStyle();
    }

    // Fluent styling methods
    pub fn getStyle(self: *const StyledButton) stylize.Style {
        return self.style;
    }

    pub fn setStyle(self: *StyledButton, style: stylize.Style) *StyledButton {
        self.style = style;
        return self;
    }

    pub fn styled(self: *StyledButton, style: stylize.Style) *StyledButton {
        const current = self.getStyle();
        return self.setStyle(current.merge(style));
    }

    pub fn fg(self: *StyledButton, color: stylize.Style.Color) *StyledButton {
        var current = self.getStyle();
        current.fg_color = color;
        return self.setStyle(current);
    }

    pub fn bg(self: *StyledButton, color: stylize.Style.Color) *StyledButton {
        var current = self.getStyle();
        current.bg_color = color;
        return self.setStyle(current);
    }

    pub fn bold(self: *StyledButton) *StyledButton {
        var current = self.getStyle();
        current.bold = true;
        return self.setStyle(current);
    }

    pub fn italic(self: *StyledButton) *StyledButton {
        var current = self.getStyle();
        current.italic = true;
        return self.setStyle(current);
    }

    pub fn underline(self: *StyledButton) *StyledButton {
        var current = self.getStyle();
        current.underline = true;
        return self.setStyle(current);
    }

    // Color convenience methods
    pub fn red(self: *StyledButton) *StyledButton { return self.fg(stylize.Style.Color{ .ansi = 1 }); }
    pub fn green(self: *StyledButton) *StyledButton { return self.fg(stylize.Style.Color{ .ansi = 2 }); }
    pub fn blue(self: *StyledButton) *StyledButton { return self.fg(stylize.Style.Color{ .ansi = 4 }); }
    pub fn yellow(self: *StyledButton) *StyledButton { return self.fg(stylize.Style.Color{ .ansi = 3 }); }
    pub fn cyan(self: *StyledButton) *StyledButton { return self.fg(stylize.Style.Color{ .ansi = 6 }); }
    pub fn white(self: *StyledButton) *StyledButton { return self.fg(stylize.Style.Color{ .ansi = 7 }); }
    pub fn gray(self: *StyledButton) *StyledButton { return self.fg(stylize.Style.Color{ .ansi = 8 }); }

    pub fn on_red(self: *StyledButton) *StyledButton { return self.bg(stylize.Style.Color{ .ansi = 1 }); }
    pub fn on_green(self: *StyledButton) *StyledButton { return self.bg(stylize.Style.Color{ .ansi = 2 }); }
    pub fn on_blue(self: *StyledButton) *StyledButton { return self.bg(stylize.Style.Color{ .ansi = 4 }); }
    pub fn on_white(self: *StyledButton) *StyledButton { return self.bg(stylize.Style.Color{ .ansi = 7 }); }

    // Button-specific styling methods
    pub fn onHover(self: *StyledButton, style: stylize.Style) *StyledButton {
        self.hover_style = style;
        return self;
    }

    pub fn onPress(self: *StyledButton, style: stylize.Style) *StyledButton {
        self.pressed_style = style;
        return self;
    }

    pub fn onDisabled(self: *StyledButton, style: stylize.Style) *StyledButton {
        self.disabled_style = style;
        return self;
    }
};

/// Enhanced Text widget with fluent styling APIs
pub const StyledText = struct {
    content: []const u8,
    bounds: widget_interface.Rect,
    style: stylize.Style = stylize.Style{},
    alignment: Alignment = .left,
    wrap: bool = false,
    allocator: std.mem.Allocator,

    pub const Alignment = enum {
        left,
        center,
        right,
    };

    pub fn init(allocator: std.mem.Allocator, content: []const u8, bounds: widget_interface.Rect) !StyledText {
        return StyledText{
            .content = content,
            .bounds = bounds,
            .allocator = allocator,
        };
    }

    pub fn render(self: *const StyledText, renderer_ctx: anytype) !void {
        const render_style = self.style.toRendererStyle();
        try renderer_ctx.applyStyle(render_style);

        const x = switch (self.alignment) {
            .left => self.bounds.x,
            .center => self.bounds.x + (self.bounds.width - @as(u16, @intCast(self.content.len))) / 2,
            .right => self.bounds.x + self.bounds.width - @as(u16, @intCast(self.content.len)),
        };

        if (self.wrap) {
            // Wrap text implementation
            try renderer_ctx.drawWrappedText(x, self.bounds.y, self.bounds.width, self.content);
        } else {
            try renderer_ctx.drawText(x, self.bounds.y, self.content);
        }

        try renderer_ctx.resetStyle();
    }

    // Fluent styling methods
    pub fn getStyle(self: *const StyledText) stylize.Style {
        return self.style;
    }

    pub fn setStyle(self: *StyledText, style: stylize.Style) *StyledText {
        self.style = style;
        return self;
    }

    pub fn styled(self: *StyledText, style: stylize.Style) *StyledText {
        const current = self.getStyle();
        return self.setStyle(current.merge(style));
    }

    pub fn fg(self: *StyledText, color: stylize.Style.Color) *StyledText {
        var current = self.getStyle();
        current.fg_color = color;
        return self.setStyle(current);
    }

    pub fn bg(self: *StyledText, color: stylize.Style.Color) *StyledText {
        var current = self.getStyle();
        current.bg_color = color;
        return self.setStyle(current);
    }

    pub fn bold(self: *StyledText) *StyledText {
        var current = self.getStyle();
        current.bold = true;
        return self.setStyle(current);
    }

    pub fn italic(self: *StyledText) *StyledText {
        var current = self.getStyle();
        current.italic = true;
        return self.setStyle(current);
    }

    pub fn underline(self: *StyledText) *StyledText {
        var current = self.getStyle();
        current.underline = true;
        return self.setStyle(current);
    }

    // Color convenience methods
    pub fn green(self: *StyledText) *StyledText { return self.fg(stylize.Style.Color{ .ansi = 2 }); }
    pub fn red(self: *StyledText) *StyledText { return self.fg(stylize.Style.Color{ .ansi = 1 }); }
    pub fn blue(self: *StyledText) *StyledText { return self.fg(stylize.Style.Color{ .ansi = 4 }); }

    // Text-specific methods
    pub fn setAlignment(self: *StyledText, alignment: Alignment) *StyledText {
        self.alignment = alignment;
        return self;
    }

    pub fn enableWrap(self: *StyledText) *StyledText {
        self.wrap = true;
        return self;
    }
};
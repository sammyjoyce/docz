//! Shared UI Context and Utilities
//!
//! This module provides shared UI context that adapts to different modes
//! and common UI utilities for components.

const std = @import("std");
const base = @import("base.zig");
const term = @import("../term/term.zig");
const graphics = @import("../term/graphics_manager.zig");
const notification = @import("notification.zig");
const progress = @import("progress.zig");

const Component = base.Component;
const Registry = base.Registry;
const Render = base.Render;
const Event = base.Event;
const Theme = base.Theme;
const ComponentError = base.ComponentError;
const NotificationLevel = term.NotificationLevel;
const Terminal = term.Terminal;
const Color = term.Color;

/// Context mode determines how components are rendered
pub const UIMode = enum {
    /// Command-line interface mode (single operation, immediate output)
    cli,
    /// Terminal user interface mode (interactive, event-driven)
    tui,
    /// Hybrid mode (CLI with some interactive elements)
    hybrid,
};

/// Shared UI context that adapts to different modes
pub const UI = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    terminal: Terminal,
    graphics: ?graphics.GraphicsManager,
    componentManager: Registry,
    mode: UIMode,
    theme: Theme,

    pub fn init(allocator: std.mem.Allocator, mode: UIMode) !Self {
        var terminal = try Terminal.init(allocator);
        const graphicsManager = graphics.GraphicsManager.init(allocator, &terminal);
        const componentManager = Registry.init(allocator, &terminal);
        const theme = Theme.forTerminal(&terminal);

        return Self{
            .allocator = allocator,
            .terminal = terminal,
            .graphics = graphicsManager,
            .componentManager = componentManager,
            .mode = mode,
            .theme = theme,
        };
    }

    pub fn deinit(self: *Self) void {
        self.componentManager.deinit();
        if (self.graphics) |*gfx| gfx.deinit();
        self.terminal.deinit();
    }

    /// Create a render context for components
    pub fn createRender(self: *Self, bounds: term.Rect) Render {
        return Render{
            .terminal = &self.terminal,
            .graphics = if (self.graphics) |*gfx| gfx else null,
            .parentBounds = bounds,
            .clipRegion = null,
            .theme = &self.theme,
            .frameTime = std.time.timestamp(),
        };
    }

    /// Show a notification using the best available method
    pub fn notify(self: *Self, level: NotificationLevel, title: []const u8, message: []const u8) ComponentError!void {
        switch (self.mode) {
            .cli, .hybrid => {
                // For CLI mode, use immediate terminal notification
                self.terminal.notification(level, title, message) catch return ComponentError.RenderFailed;
            },
            .tui => {
                // For TUI mode, create a notification component
                const notificationComponent = Notification.create(self.allocator, Config{
                    .level = level,
                    .title = self.allocator.dupe(u8, title) catch return ComponentError.OutOfMemory,
                    .message = self.allocator.dupe(u8, message) catch return ComponentError.OutOfMemory,
                    .duration = 3000,
                    .autoDismiss = true,
                }) catch |e| return e;

                try self.componentManager.addComponent(notificationComponent);
            },
        }
    }

    /// Show a progress bar using the best method for the current mode
    pub fn showProgress(self: *Self, progressValue: f32, label: ?[]const u8) ComponentError!?*Component {
        switch (self.mode) {
            .cli => {
                // For CLI mode, create an inline progress bar
                const progressComponent = progress.ProgressBar.create(self.allocator, .{
                    .progress = progressValue,
                    .label = label,
                    .style = .auto,
                    .animated = false, // No animation in CLI mode
                }) catch |e| return e;

                const ctx = self.createRender(term.Rect{ .x = 0, .y = 0, .width = 80, .height = 1 });
                progressComponent.render(ctx) catch return ComponentError.RenderFailed;
                self.terminal.flush() catch return ComponentError.RenderFailed;

                return progressComponent;
            },
            .tui, .hybrid => {
                // For TUI mode, add to component manager
                const progressComponent = progress.ProgressBar.create(self.allocator, .{
                    .progress = progressValue,
                    .label = label,
                    .style = .auto,
                    .animated = true,
                }) catch |e| return e;

                try self.componentManager.addComponent(progressComponent);
                return progressComponent;
            },
        }
    }

    /// Update a progress bar's value
    pub fn updateProgress(self: *Self, progressComponent: *Component, progressValue: f32) ComponentError!void {
        const progress_impl: *progress.ProgressBar = @ptrCast(@alignCast(progressComponent.impl));
        try progress_impl.setProgress(progressValue);

        if (self.mode == .cli) {
            const ctx = self.createRender(term.Rect{ .x = 0, .y = 0, .width = 80, .height = 1 });
            progressComponent.render(ctx) catch return ComponentError.RenderFailed;
            self.terminal.flush() catch return ComponentError.RenderFailed;
        }
    }

    /// Handle input events (mainly for TUI mode)
    pub fn handleEvent(self: *Self, event: Event) ComponentError!bool {
        return self.componentManager.handleEvent(event);
    }

    /// Render all components (mainly for TUI mode)
    pub fn render(self: *Self, bounds: term.Rect) ComponentError!void {
        const ctx = self.createRender(bounds);
        try self.componentManager.render(ctx);
    }

    /// Update animations and time-based components
    pub fn update(self: *Self, dt: f32) ComponentError!void {
        try self.componentManager.update(dt);
    }

    /// Clear the screen
    pub fn clear(self: *Self) !void {
        try self.terminal.clear();
    }

    /// Set the UI mode
    pub fn setMode(self: *Self, mode: UIMode) void {
        self.mode = mode;
    }

    /// Get terminal capabilities
    pub fn getCapabilities(self: *Self) term.TermCaps {
        return self.terminal.getCapabilities();
    }
};

/// Notification component for TUI mode
pub const Notification = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    state: base.State,
    config: Config,
    creationTime: i64,
    animationProgress: f32 = 0.0,

    const vtable = Component.VTable{
        .init = init,
        .deinit = deinit,
        .getState = getState,
        .setState = setState,
        .render = render,
        .measure = measure,
        .handleEvent = handleEvent,
        .addChild = null,
        .removeChild = null,
        .getChildren = null,
        .update = update,
    };

    pub fn create(allocator: std.mem.Allocator, config: Config) ComponentError!*Component {
        const self = allocator.create(Self) catch return ComponentError.OutOfMemory;
        self.* = Self{
            .allocator = allocator,
            .state = base.State{},
            .config = config,
            .creationTime = std.time.timestamp(),
        };

        const component = allocator.create(Component) catch return ComponentError.OutOfMemory;
        component.* = Component{
            .vtable = &vtable,
            .impl = self,
            .id = 0,
        };

        return component;
    }

    fn init(impl: *anyopaque, allocator: std.mem.Allocator) ComponentError!void {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(impl));
        self.state = base.State{
            .zIndex = 1000, // High z-index for notifications
        };
    }

    fn deinit(impl: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.allocator.free(self.config.title);
        self.allocator.free(self.config.message);
    }

    fn getState(impl: *anyopaque) *base.State {
        const self: *Self = @ptrCast(@alignCast(impl));
        return &self.state;
    }

    fn setState(impl: *anyopaque, state: base.State) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.state = state;
    }

    fn render(impl: *anyopaque, ctx: Render) ComponentError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Get notification colors based on level
        const level_color = switch (self.config.level) {
            .info => ctx.theme.colors.primary,
            .success => ctx.theme.colors.success,
            .warning => ctx.theme.colors.warning,
            .@"error" => ctx.theme.colors.errorColor,
            .debug => Color{ .rgb = .{ .r = 138, .g = 43, .b = 226 } },
        };

        const level_icon = switch (self.config.level) {
            .info => "ℹ",
            .success => "✓",
            .warning => "⚠",
            .@"error" => "✗",
            .debug => "🐛",
        };

        // Animation for slide-in effect
        const elapsed = @as(f32, @floatFromInt(std.time.timestamp() - self.creationTime)) / 1000.0;
        const animation_t = @min(1.0, elapsed / 0.3); // 300ms slide-in
        const eased_t = base.Animation.easeOut(animation_t);

        // Calculate position with animation
        const target_y = self.state.bounds.y;
        const start_y = target_y - 5;
        const current_y = @as(i32, @intFromFloat(@as(f32, @floatFromInt(start_y)) + (@as(f32, @floatFromInt(target_y - start_y)) * eased_t)));

        // Move to animated position
        ctx.terminal.moveTo(self.state.bounds.x, current_y) catch return ComponentError.RenderFailed;

        // Render notification content
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();

        content.writer().print("┌─ {s} {s} ", .{ level_icon, self.config.title }) catch return ComponentError.RenderFailed;

        // Add padding to fill width
        const content_width = self.config.title.len + 6; // Icon + title + spacing
        const padding_needed = @max(0, self.state.bounds.width -| content_width -| 3); // -3 for border chars
        var i: u32 = 0;
        while (i < padding_needed) : (i += 1) {
            content.append('─') catch return ComponentError.RenderFailed;
        }
        content.append('┐') catch return ComponentError.RenderFailed;

        // Render title line
        const title_style = term.Style{ .fg_color = level_color, .bold = true };
        ctx.terminal.print(content.items, title_style) catch return ComponentError.RenderFailed;

        // Move to next line for message
        ctx.terminal.moveTo(self.state.bounds.x, current_y + 1) catch return ComponentError.RenderFailed;

        const message_style = term.Style{ .fg_color = ctx.theme.colors.foreground };
        ctx.terminal.printf("│ {s}", .{self.config.message}, message_style) catch return ComponentError.RenderFailed;

        // Add padding for message line
        const message_padding = @max(0, self.state.bounds.width -| self.config.message.len -| 3);
        i = 0;
        while (i < message_padding) : (i += 1) {
            ctx.terminal.print(" ", message_style) catch return ComponentError.RenderFailed;
        }
        ctx.terminal.print("│", title_style) catch return ComponentError.RenderFailed;

        // Bottom border
        ctx.terminal.moveTo(self.state.bounds.x, current_y + 2) catch return ComponentError.RenderFailed;
        ctx.terminal.print("└", title_style) catch return ComponentError.RenderFailed;
        i = 0;
        while (i < self.state.bounds.width - 2) : (i += 1) {
            ctx.terminal.print("─", title_style) catch return ComponentError.RenderFailed;
        }
        ctx.terminal.print("┘", title_style) catch return ComponentError.RenderFailed;
    }

    fn measure(impl: *anyopaque, available: term.Rect) term.Rect {
        const self: *Self = @ptrCast(@alignCast(impl));

        const width = @max(self.config.title.len + 10, // Title + icon + padding
            @min(self.config.message.len + 4, available.width) // Message + padding, clamped to available
            );

        return term.Rect{
            .x = available.x,
            .y = available.y,
            .width = @min(width, available.width),
            .height = 3, // Title line + message line + border
        };
    }

    fn handleEvent(impl: *anyopaque, event: Event) ComponentError!bool {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Allow dismissing notifications with Escape or Enter
        switch (event) {
            .key => |key_event| {
                if (key_event.key == .escape or key_event.key == .enter) {
                    self.config.autoDismiss = true;
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    fn update(impl: *anyopaque, dt: f32) ComponentError!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = dt;

        // Check if notification should be auto-dismissed
        if (self.config.autoDismiss) {
            const elapsed = @as(u32, @intCast(std.time.timestamp() - self.creationTime)) * 1000;
            if (elapsed > self.config.duration) {
                self.state.visible = false;
            }
        }

        self.state.markDirty(); // Keep animating
    }
};

/// Config for notification components
pub const Config = struct {
    level: NotificationLevel,
    title: []const u8,
    message: []const u8,
    duration: u32 = 3000, // milliseconds
    autoDismiss: bool = true,
};

/// Utility functions for common UI operations
/// Create a styled text span
pub fn createTextStyle(color: ?Color, bold: bool) term.Style {
    return term.Style{
        .fg_color = color,
        .bold = bold,
    };
}

/// Create a colored border
pub const BorderStyle = struct {
    color: Color,
    style: enum { single, double, rounded },

    pub fn getChars(self: BorderStyle) BorderCharacters {
        return switch (self.style) {
            .single => BorderCharacters{
                .topLeft = "┌",
                .topRight = "┐",
                .bottomLeft = "└",
                .bottomRight = "┘",
                .horizontal = "─",
                .vertical = "│",
            },
            .double => BorderCharacters{
                .topLeft = "╔",
                .topRight = "╗",
                .bottomLeft = "╚",
                .bottomRight = "╝",
                .horizontal = "═",
                .vertical = "║",
            },
            .rounded => BorderCharacters{
                .topLeft = "╭",
                .topRight = "╮",
                .bottomLeft = "╰",
                .bottomRight = "╯",
                .horizontal = "─",
                .vertical = "│",
            },
        };
    }
};

pub const BorderCharacters = struct {
    topLeft: []const u8,
    topRight: []const u8,
    bottomLeft: []const u8,
    bottomRight: []const u8,
    horizontal: []const u8,
    vertical: []const u8,
};

/// Draw a border around a rectangle
pub fn drawBorder(terminal: *Terminal, bounds: term.Rect, border: BorderStyle) !void {
    const chars = border.getChars();
    const style = term.Style{ .fg_color = border.color };

    // Top border
    try terminal.moveTo(bounds.x, bounds.y);
    try terminal.print(chars.topLeft, style);
    var x: u32 = 1;
    while (x < bounds.width - 1) : (x += 1) {
        try terminal.print(chars.horizontal, style);
    }
    try terminal.print(chars.topRight, style);

    // Side borders
    var y: u32 = 1;
    while (y < bounds.height - 1) : (y += 1) {
        try terminal.moveTo(bounds.x, bounds.y + @as(i32, @intCast(y)));
        try terminal.print(chars.vertical, style);
        try terminal.moveTo(bounds.x + @as(i32, @intCast(bounds.width)) - 1, bounds.y + @as(i32, @intCast(y)));
        try terminal.print(chars.vertical, style);
    }

    // Bottom border
    try terminal.moveTo(bounds.x, bounds.y + @as(i32, @intCast(bounds.height)) - 1);
    try terminal.print(chars.bottomLeft, style);
    x = 1;
    while (x < bounds.width - 1) : (x += 1) {
        try terminal.print(chars.horizontal, style);
    }
    try terminal.print(chars.bottomRight, style);
}

/// Center text within a rectangle
pub fn centerText(terminal: *Terminal, bounds: term.Rect, text: []const u8, style: ?term.Style) !void {
    const text_width = text.len;
    const x_offset = if (bounds.width > text_width) (bounds.width - text_width) / 2 else 0;
    const y_offset = bounds.height / 2;

    try terminal.moveTo(bounds.x + @as(i32, @intCast(x_offset)), bounds.y + @as(i32, @intCast(y_offset)));
    try terminal.print(text, style);
}

test "ui context creation" {
    var ui_ctx = try UI.init(std.testing.allocator, .cli);
    defer ui_ctx.deinit();

    try std.testing.expect(ui_ctx.mode == .cli);
}

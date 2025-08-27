//! Shared UI Components and Utilities
//!
//! This module provides components and utilities that can be used across both
//! CLI and TUI interfaces, enabling code reuse and consistent behavior.

const std = @import("std");
const component_mod = @import("component.zig");
const unified = @import("../term/unified.zig");
const graphics = @import("../term/graphics_manager.zig");

// Re-export core components
pub const Component = component_mod.Component;
pub const ComponentRegistry = component_mod.ComponentRegistry;
pub const ComponentState = component_mod.ComponentState;
pub const RenderContext = component_mod.RenderContext;
pub const Event = component_mod.Event;
pub const Theme = component_mod.Theme;

// Re-export terminal types
pub const Terminal = unified.Terminal;
pub const Color = unified.Color;
pub const Style = unified.Style;
pub const Point = unified.Point;
pub const Rect = unified.Rect;
pub const NotificationLevel = unified.NotificationLevel;

// Component imports
pub const ProgressBar = @import("components/ProgressBar.zig").Progress;

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
    componentManager: ComponentRegistry,
    mode: UIMode,
    theme: Theme,

    pub fn init(allocator: std.mem.Allocator, mode: UIMode) !Self {
        var terminal = try Terminal.init(allocator);
        const graphics_manager = graphics.GraphicsManager.init(allocator, &terminal);
        const component_manager = ComponentRegistry.init(allocator, &terminal);
        const theme = Theme.forTerminal(&terminal);

        return Self{
            .allocator = allocator,
            .terminal = terminal,
            .graphics = graphics_manager,
            .componentManager = component_manager,
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
    pub fn createRenderContext(self: *Self, bounds: Rect) RenderContext {
        return RenderContext{
            .terminal = &self.terminal,
            .graphics = if (self.graphics) |*gfx| gfx else null,
            .parent_bounds = bounds,
            .clip_region = null,
            .theme = &self.theme,
            .frame_time = std.time.timestamp(),
        };
    }

    /// Show a notification using the best available method
    pub fn notify(self: *Self, level: NotificationLevel, title: []const u8, message: []const u8) !void {
        switch (self.mode) {
            .cli, .hybrid => {
                // For CLI mode, use immediate terminal notification
                try self.terminal.notification(level, title, message);
            },
            .tui => {
                // For TUI mode, create a notification component
                const notification = try NotificationComponent.create(self.allocator, NotificationConfig{
                    .level = level,
                    .title = try self.allocator.dupe(u8, title),
                    .message = try self.allocator.dupe(u8, message),
                    .duration = 3000, // 3 seconds
                    .autoDismiss = true,
                });

                try self.componentManager.addComponent(notification);
            },
        }
    }

    /// Show a progress bar using the best method for the current mode
    pub fn showProgress(self: *Self, progress: f32, label: ?[]const u8) !?*Component {
        switch (self.mode) {
            .cli => {
                // For CLI mode, create a simple inline progress bar
                const progress_bar = try ProgressBar.create(self.allocator, .{
                    .progress = progress,
                    .label = label,
                    .style = .auto,
                    .animated = false, // No animation in CLI mode
                });

                // Render immediately
                const ctx = self.createRenderContext(Rect{ .x = 0, .y = 0, .width = 80, .height = 1 });
                try progress_bar.render(ctx);
                try self.terminal.flush();

                return progress_bar;
            },
            .tui, .hybrid => {
                // For TUI mode, add to component manager
                const progress_bar = try ProgressBar.create(self.allocator, .{
                    .progress = progress,
                    .label = label,
                    .style = .auto,
                    .animated = true,
                });

                try self.componentManager.addComponent(progress_bar);
                return progress_bar;
            },
        }
    }

    /// Update a progress bar's value
    pub fn updateProgress(self: *Self, progress_component: *Component, progress: f32) void {
        // Extract the ProgressBar from the component
        const progress_bar: *ProgressBar = @ptrCast(@alignCast(progress_component.impl));
        progress_bar.setProgress(progress);

        if (self.mode == .cli) {
            // In CLI mode, re-render immediately
            const ctx = self.createRenderContext(Rect{ .x = 0, .y = 0, .width = 80, .height = 1 });
            progress_component.render(ctx) catch {};
            self.terminal.flush() catch {};
        }
    }

    /// Handle input events (mainly for TUI mode)
    pub fn handleEvent(self: *Self, event: Event) !bool {
        return self.componentManager.handleEvent(event);
    }

    /// Render all components (mainly for TUI mode)
    pub fn render(self: *Self, bounds: Rect) !void {
        const ctx = self.createRenderContext(bounds);
        try self.component_manager.render(ctx);
    }

    /// Update animations and time-based components
    pub fn update(self: *Self, dt: f32) !void {
        try self.component_manager.update(dt);
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
    pub fn getCapabilities(self: *Self) unified.TermCaps {
        return self.terminal.getCapabilities();
    }
};

/// Notification component for TUI mode
pub const NotificationComponent = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    state: ComponentState,
    config: NotificationConfig,
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

    pub fn create(allocator: std.mem.Allocator, config: NotificationConfig) !*Component {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .state = ComponentState{},
            .config = config,
            .creationTime = std.time.timestamp(),
        };

        const component = try allocator.create(Component);
        component.* = Component{
            .vtable = &vtable,
            .impl = self,
            .id = 0,
        };

        return component;
    }

    fn init(impl: *anyopaque, allocator: std.mem.Allocator) anyerror!void {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(impl));
        self.state = ComponentState{
            .z_index = 1000, // High z-index for notifications
        };
    }

    fn deinit(impl: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.allocator.free(self.config.title);
        self.allocator.free(self.config.message);
    }

    fn getState(impl: *anyopaque) *ComponentState {
        const self: *Self = @ptrCast(@alignCast(impl));
        return &self.state;
    }

    fn setState(impl: *anyopaque, state: ComponentState) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.state = state;
    }

    fn render(impl: *anyopaque, ctx: RenderContext) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Get notification colors based on level
        const level_color = switch (self.config.level) {
            .info => ctx.theme.colors.primary,
            .success => ctx.theme.colors.success,
            .warning => ctx.theme.colors.warning,
            .@"error" => ctx.theme.colors.error_color,
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
        const eased_t = component_mod.Animation.easeOut(animation_t);

        // Calculate position with animation
        const target_y = self.state.bounds.y;
        const start_y = target_y - 5;
        const current_y = @as(i32, @intFromFloat(@as(f32, @floatFromInt(start_y)) + (@as(f32, @floatFromInt(target_y - start_y)) * eased_t)));

        // Move to animated position
        try ctx.terminal.moveTo(self.state.bounds.x, current_y);

        // Render notification content
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();

        try content.writer().print("┌─ {s} {s} ", .{ level_icon, self.config.title });

        // Add padding to fill width
        const content_width = self.config.title.len + 6; // Icon + title + spacing
        const padding_needed = @max(0, self.state.bounds.width -| content_width -| 3); // -3 for border chars
        var i: u32 = 0;
        while (i < padding_needed) : (i += 1) {
            try content.append('─');
        }
        try content.append('┐');

        // Render title line
        const title_style = Style{ .fg_color = level_color, .bold = true };
        try ctx.terminal.print(content.items, title_style);

        // Move to next line for message
        try ctx.terminal.moveTo(self.state.bounds.x, current_y + 1);

        const message_style = Style{ .fg_color = ctx.theme.colors.foreground };
        try ctx.terminal.printf("│ {s}", .{self.config.message}, message_style);

        // Add padding for message line
        const message_padding = @max(0, self.state.bounds.width -| self.config.message.len -| 3);
        i = 0;
        while (i < message_padding) : (i += 1) {
            try ctx.terminal.print(" ", message_style);
        }
        try ctx.terminal.print("│", title_style);

        // Bottom border
        try ctx.terminal.moveTo(self.state.bounds.x, current_y + 2);
        try ctx.terminal.print("└", title_style);
        i = 0;
        while (i < self.state.bounds.width - 2) : (i += 1) {
            try ctx.terminal.print("─", title_style);
        }
        try ctx.terminal.print("┘", title_style);
    }

    fn measure(impl: *anyopaque, available: Rect) Rect {
        const self: *Self = @ptrCast(@alignCast(impl));

        const width = @max(self.config.title.len + 10, // Title + icon + padding
            @min(self.config.message.len + 4, available.width) // Message + padding, clamped to available
            );

        return Rect{
            .x = available.x,
            .y = available.y,
            .width = @min(width, available.width),
            .height = 3, // Title line + message line + border
        };
    }

    fn handleEvent(impl: *anyopaque, event: Event) anyerror!bool {
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

    fn update(impl: *anyopaque, dt: f32) anyerror!void {
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

/// Configuration for notification components
pub const NotificationConfig = struct {
    level: NotificationLevel,
    title: []const u8,
    message: []const u8,
    duration: u32 = 3000, // milliseconds
    autoDismiss: bool = true,
};

/// Utility functions for common UI operations
/// Create a styled text span
pub fn createTextStyle(color: ?Color, bold: bool) Style {
    return Style{
        .fg_color = color,
        .bold = bold,
    };
}

/// Create a colored border
pub const BorderStyle = struct {
    color: Color,
    style: enum { single, double, rounded },

    pub fn getChars(self: BorderStyle) BorderChars {
        return switch (self.style) {
            .single => BorderChars{
                .topLeft = "┌",
                .topRight = "┐",
                .bottomLeft = "└",
                .bottomRight = "┘",
                .horizontal = "─",
                .vertical = "│",
            },
            .double => BorderChars{
                .topLeft = "╔",
                .topRight = "╗",
                .bottomLeft = "╚",
                .bottomRight = "╝",
                .horizontal = "═",
                .vertical = "║",
            },
            .rounded => BorderChars{
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

pub const BorderChars = struct {
    topLeft: []const u8,
    topRight: []const u8,
    bottomLeft: []const u8,
    bottomRight: []const u8,
    horizontal: []const u8,
    vertical: []const u8,
};

/// Draw a border around a rectangle
pub fn drawBorder(terminal: *Terminal, bounds: Rect, border: BorderStyle) !void {
    const chars = border.getChars();
    const style = Style{ .fg_color = border.color };

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
pub fn centerText(terminal: *Terminal, bounds: Rect, text: []const u8, style: ?Style) !void {
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

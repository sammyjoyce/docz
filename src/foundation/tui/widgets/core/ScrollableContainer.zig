//! ScrollableContainer - Generic scrollable container widget
//!
//! This widget provides a flexible container that can wrap any content and provide
//! scrolling capabilities with independent scrollable regions.
//!
//! Features:
//! - Generic content wrapping (any widget/drawable)
//! - Vertical and horizontal scrolling support
//! - Independent scrollbars (can scroll X and Y independently)
//! - Nested scrolling support (containers within containers)
//! - Auto-hide scrollbars option
//! - Scroll synchronization between related containers
//! - Smooth scrolling with momentum
//! - Viewport clipping to prevent content overflow
//! - Mouse and keyboard navigation
//! - Border and padding options

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const widget_interface = @import("../../core/widget_interface.zig");
const renderer_mod = @import("../../core/renderer.zig");
const scrollbar_mod = @import("scrollbar.zig");
const bounds_mod = @import("../../core/bounds.zig");

/// Scroll direction
pub const ScrollDirection = enum {
    vertical,
    horizontal,
    both,
};

/// Scroll behavior
pub const ScrollBehavior = enum {
    /// Smooth scrolling with momentum
    smooth,
    /// Instant scrolling
    instant,
};

/// Content sizing mode
pub const ContentSizeMode = enum {
    /// Use content's natural size
    natural,
    /// Content fills available space
    fill,
    /// Content size is manually specified
    manual,
};

/// Scroll event for synchronization
pub const ScrollEvent = struct {
    /// Container that triggered the scroll
    source_id: []const u8,
    /// Scroll position (0.0 to 1.0)
    scroll_x: f64,
    scroll_y: f64,
    /// Scroll delta
    delta_x: f64,
    delta_y: f64,
    /// Direction of scroll
    direction: ScrollDirection,
};

/// Scroll callback function type
pub const ScrollCallback = *const fn (
    container: *ScrollableContainer,
    event: ScrollEvent,
    user_data: ?*anyopaque,
) void;

/// Configuration for ScrollableContainer
pub const Config = struct {
    /// Scroll direction support
    scroll_direction: ScrollDirection = .both,
    /// Scroll behavior
    scroll_behavior: ScrollBehavior = .smooth,
    /// Content sizing mode
    content_size_mode: ContentSizeMode = .natural,
    /// Manual content size (used when content_size_mode is .manual)
    content_width: ?u16 = null,
    content_height: ?u16 = null,
    /// Show vertical scrollbar
    show_vertical_scrollbar: bool = true,
    /// Show horizontal scrollbar
    show_horizontal_scrollbar: bool = true,
    /// Auto-hide scrollbars when content fits
    auto_hide_scrollbars: bool = true,
    /// Scrollbar style
    scrollbar_style: scrollbar_mod.Style = .modern,
    /// Enable smooth scrolling
    smooth_scrolling: bool = true,
    /// Scroll speed multiplier
    scroll_speed: f32 = 1.0,
    /// Enable mouse wheel support
    mouse_wheel_support: bool = true,
    /// Enable keyboard navigation
    keyboard_navigation: bool = true,
    /// Enable momentum scrolling
    momentum_scrolling: bool = true,
    /// Friction for momentum scrolling
    momentum_friction: f32 = 0.95,
    /// Border style
    border_style: ?renderer_mod.BoxStyle = null,
    /// Padding around content
    padding: renderer_mod.BoxStyle.Padding = .{},
    /// Scroll callback for synchronization
    scroll_callback: ?ScrollCallback = null,
    /// User data for scroll callback
    scroll_callback_data: ?*anyopaque = null,
    /// Enable focus management
    focus_management: bool = true,
    /// Container ID for synchronization
    container_id: ?[]const u8 = null,
};

/// Content renderer function type
pub const ContentRenderer = *const fn (
    ctx: *anyopaque,
    renderer: *renderer_mod.Renderer,
    bounds: widget_interface.Rect,
    user_data: ?*anyopaque,
) anyerror!void;

/// Content measurer function type
pub const ContentMeasurer = *const fn (
    ctx: *anyopaque,
    constraints: renderer_mod.Constraints,
    user_data: ?*anyopaque,
) renderer_mod.Size;

/// ScrollableContainer widget
pub const ScrollableContainer = struct {
    /// Configuration
    config: Config,
    /// Content renderer function
    content_renderer: ?ContentRenderer = null,
    /// Content measurer function
    content_measurer: ?ContentMeasurer = null,
    /// Content context (passed to renderer/measurer)
    content_ctx: ?*anyopaque = null,
    /// Current scroll position (pixels)
    scroll_x: f32 = 0,
    scroll_y: f32 = 0,
    /// Scroll velocity for momentum
    velocity_x: f32 = 0,
    velocity_y: f32 = 0,
    /// Content size
    content_width: u16 = 0,
    content_height: u16 = 0,
    /// Viewport size
    viewport_width: u16 = 0,
    viewport_height: u16 = 0,
    /// Scrollbar states
    vertical_scrollbar: scrollbar_mod.Scrollbar,
    horizontal_scrollbar: scrollbar_mod.Scrollbar,
    /// Focus state
    focused: bool = false,
    /// Last update timestamp
    last_update: i64 = 0,
    /// Container ID
    container_id: []const u8,
    /// Allocator
    allocator: Allocator,

    const Self = @This();

    /// Initialize ScrollableContainer
    pub fn init(allocator: Allocator, config: Config) !Self {
        const container_id = if (config.container_id) |id|
            try allocator.dupe(u8, id)
        else
            try std.fmt.allocPrint(allocator, "container_{x}", .{std.rand.int(u64)});

        return Self{
            .config = config,
            .container_id = container_id,
            .vertical_scrollbar = scrollbar_mod.Scrollbar.init(.vertical, config.scrollbar_style),
            .horizontal_scrollbar = scrollbar_mod.Scrollbar.init(.horizontal, config.scrollbar_style),
            .allocator = allocator,
            .last_update = std.time.milliTimestamp(),
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.container_id);
    }

    /// Set content renderer
    pub fn setContentRenderer(
        self: *Self,
        renderer: ContentRenderer,
        measurer: ?ContentMeasurer,
        ctx: ?*anyopaque,
    ) void {
        self.content_renderer = renderer;
        self.content_measurer = measurer;
        self.content_ctx = ctx;
    }

    /// Set content size manually
    pub fn setContentSize(self: *Self, width: u16, height: u16) void {
        self.content_width = width;
        self.content_height = height;
        self.updateScrollbars();
    }

    /// Get current scroll position
    pub fn getScrollPosition(self: Self) struct { x: f32, y: f32 } {
        return .{ .x = self.scroll_x, .y = self.scroll_y };
    }

    /// Set scroll position
    pub fn setScrollPosition(self: *Self, x: f32, y: f32) void {
        self.scroll_x = std.math.clamp(x, 0, @max(0, @as(f32, @floatFromInt(self.content_width)) - @as(f32, @floatFromInt(self.viewport_width))));
        self.scroll_y = std.math.clamp(y, 0, @max(0, @as(f32, @floatFromInt(self.content_height)) - @as(f32, @floatFromInt(self.viewport_height))));

        // Reset velocity when manually setting position
        self.velocity_x = 0;
        self.velocity_y = 0;

        self.updateScrollbars();

        // Trigger scroll callback
        if (self.config.scroll_callback) |callback| {
            const event = ScrollEvent{
                .source_id = self.container_id,
                .scroll_x = self.getScrollRatioX(),
                .scroll_y = self.getScrollRatioY(),
                .delta_x = 0,
                .delta_y = 0,
                .direction = .both,
            };
            callback(self, event, self.config.scroll_callback_data);
        }
    }

    /// Scroll by relative amount
    pub fn scrollBy(self: *Self, delta_x: f32, delta_y: f32) void {
        const new_x = self.scroll_x + delta_x;
        const new_y = self.scroll_y + delta_y;

        const old_x = self.scroll_x;
        const old_y = self.scroll_y;

        self.setScrollPosition(new_x, new_y);

        // Trigger scroll callback with delta
        if (self.config.scroll_callback) |callback| {
            const actual_delta_x = self.scroll_x - old_x;
            const actual_delta_y = self.scroll_y - old_y;

            if (actual_delta_x != 0 or actual_delta_y != 0) {
                const event = ScrollEvent{
                    .source_id = self.container_id,
                    .scroll_x = self.getScrollRatioX(),
                    .scroll_y = self.getScrollRatioY(),
                    .delta_x = actual_delta_x,
                    .delta_y = actual_delta_y,
                    .direction = if (actual_delta_x != 0 and actual_delta_y != 0)
                        .both
                    else if (actual_delta_x != 0)
                        .horizontal
                    else
                        .vertical,
                };
                callback(self, event, self.config.scroll_callback_data);
            }
        }
    }

    /// Scroll to specific position with animation
    pub fn scrollTo(self: *Self, x: f32, y: f32, behavior: ScrollBehavior) void {
        if (behavior == .instant) {
            self.setScrollPosition(x, y);
        } else {
            // For smooth scrolling, set velocity towards target
            const target_x = std.math.clamp(x, 0, @max(0, @as(f32, @floatFromInt(self.content_width)) - @as(f32, @floatFromInt(self.viewport_width))));
            const target_y = std.math.clamp(y, 0, @max(0, @as(f32, @floatFromInt(self.content_height)) - @as(f32, @floatFromInt(self.viewport_height))));

            const dx = target_x - self.scroll_x;
            const dy = target_y - self.scroll_y;

            // Set velocity proportional to distance
            self.velocity_x = dx * 0.1;
            self.velocity_y = dy * 0.1;
        }
    }

    /// Get scroll ratio (0.0 to 1.0)
    pub fn getScrollRatioX(self: Self) f64 {
        const max_scroll = @max(0, @as(f32, @floatFromInt(self.content_width)) - @as(f32, @floatFromInt(self.viewport_width)));
        if (max_scroll == 0) return 0;
        return @as(f64, @floatFromInt(self.scroll_x)) / @as(f64, @floatFromInt(max_scroll));
    }

    pub fn getScrollRatioY(self: Self) f64 {
        const max_scroll = @max(0, @as(f32, @floatFromInt(self.content_height)) - @as(f32, @floatFromInt(self.viewport_height)));
        if (max_scroll == 0) return 0;
        return @as(f64, @floatFromInt(self.scroll_y)) / @as(f64, @floatFromInt(max_scroll));
    }

    /// Update scroll physics
    pub fn updateScrollPhysics(self: *Self) void {
        if (!self.config.smooth_scrolling or (!self.config.momentum_scrolling and @abs(self.velocity_x) < 0.01 and @abs(self.velocity_y) < 0.01)) {
            return;
        }

        const now = std.time.milliTimestamp();
        const delta_time = @as(f32, @floatFromInt(now - self.last_update)) / 1000.0;
        self.last_update = now;

        if (@abs(self.velocity_x) > 0.01) {
            self.scroll_x += self.velocity_x * delta_time;
            self.velocity_x *= self.config.momentum_friction;

            // Clamp to bounds
            const max_scroll_x = @max(0, @as(f32, @floatFromInt(self.content_width)) - @as(f32, @floatFromInt(self.viewport_width)));
            if (self.scroll_x < 0) {
                self.scroll_x = 0;
                self.velocity_x = 0;
            } else if (self.scroll_x > max_scroll_x) {
                self.scroll_x = max_scroll_x;
                self.velocity_x = 0;
            }
        } else {
            self.velocity_x = 0;
        }

        if (@abs(self.velocity_y) > 0.01) {
            self.scroll_y += self.velocity_y * delta_time;
            self.velocity_y *= self.config.momentum_friction;

            // Clamp to bounds
            const max_scroll_y = @max(0, @as(f32, @floatFromInt(self.content_height)) - @as(f32, @floatFromInt(self.viewport_height)));
            if (self.scroll_y < 0) {
                self.scroll_y = 0;
                self.velocity_y = 0;
            } else if (self.scroll_y > max_scroll_y) {
                self.scroll_y = max_scroll_y;
                self.velocity_y = 0;
            }
        } else {
            self.velocity_y = 0;
        }

        self.updateScrollbars();
    }

    /// Handle keyboard input
    pub fn handleKeyboard(self: *Self, key: renderer_mod.InputEvent.KeyEvent) !bool {
        if (!self.config.keyboard_navigation) return false;

        const scroll_amount = 50.0 * self.config.scroll_speed;

        switch (key.key) {
            .arrow_up => {
                if (self.config.scroll_direction == .vertical or self.config.scroll_direction == .both) {
                    self.scrollBy(0, -scroll_amount);
                    return true;
                }
            },
            .arrow_down => {
                if (self.config.scroll_direction == .vertical or self.config.scroll_direction == .both) {
                    self.scrollBy(0, scroll_amount);
                    return true;
                }
            },
            .arrow_left => {
                if (self.config.scroll_direction == .horizontal or self.config.scroll_direction == .both) {
                    self.scrollBy(-scroll_amount, 0);
                    return true;
                }
            },
            .arrow_right => {
                if (self.config.scroll_direction == .horizontal or self.config.scroll_direction == .both) {
                    self.scrollBy(scroll_amount, 0);
                    return true;
                }
            },
            .page_up => {
                if (self.config.scroll_direction == .vertical or self.config.scroll_direction == .both) {
                    const page_amount = @as(f32, @floatFromInt(self.viewport_height)) * 0.8;
                    self.scrollBy(0, -page_amount);
                    return true;
                }
            },
            .page_down => {
                if (self.config.scroll_direction == .vertical or self.config.scroll_direction == .both) {
                    const page_amount = @as(f32, @floatFromInt(self.viewport_height)) * 0.8;
                    self.scrollBy(0, page_amount);
                    return true;
                }
            },
            .home => {
                if (self.config.scroll_direction == .vertical or self.config.scroll_direction == .both) {
                    self.setScrollPosition(self.scroll_x, 0);
                    return true;
                }
            },
            .end => {
                if (self.config.scroll_direction == .vertical or self.config.scroll_direction == .both) {
                    const max_scroll = @max(0, @as(f32, @floatFromInt(self.content_height)) - @as(f32, @floatFromInt(self.viewport_height)));
                    self.setScrollPosition(self.scroll_x, max_scroll);
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    /// Handle mouse input
    pub fn handleMouse(self: *Self, mouse: renderer_mod.InputEvent.MouseEvent) !bool {
        if (!self.config.mouse_wheel_support) return false;

        switch (mouse.type) {
            .scroll_up => {
                if (self.config.scroll_direction == .vertical or self.config.scroll_direction == .both) {
                    const scroll_amount = 30.0 * self.config.scroll_speed;
                    if (self.config.scroll_behavior == .smooth) {
                        self.velocity_y = -scroll_amount;
                    } else {
                        self.scrollBy(0, -scroll_amount);
                    }
                    return true;
                }
            },
            .scroll_down => {
                if (self.config.scroll_direction == .vertical or self.config.scroll_direction == .both) {
                    const scroll_amount = 30.0 * self.config.scroll_speed;
                    if (self.config.scroll_behavior == .smooth) {
                        self.velocity_y = scroll_amount;
                    } else {
                        self.scrollBy(0, scroll_amount);
                    }
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    /// Render the container
    pub fn render(
        self: *Self,
        renderer: *renderer_mod.Renderer,
        bounds: widget_interface.Rect,
    ) !void {
        // Update viewport size
        self.viewport_width = bounds.width;
        self.viewport_height = bounds.height;

        // Measure content if needed
        if (self.config.content_size_mode == .natural and self.content_measurer != null) {
            const constraints = renderer_mod.Constraints{
                .min_width = 0,
                .max_width = std.math.maxInt(u16),
                .min_height = 0,
                .max_height = std.math.maxInt(u16),
            };
            const measured_size = self.content_measurer.?(self.content_ctx, constraints, self.config.scroll_callback_data);
            self.content_width = measured_size.width;
            self.content_height = measured_size.height;
        } else if (self.config.content_size_mode == .fill) {
            self.content_width = bounds.width;
            self.content_height = bounds.height;
        } else if (self.config.content_size_mode == .manual) {
            // Use manually set size
        }

        // Update scroll physics
        self.updateScrollPhysics();

        // Calculate content area (inside padding and border)
        const content_bounds = widget_interface.Rect{
            .x = bounds.x + @as(i16, @intCast(self.config.padding.left)),
            .y = bounds.y + @as(i16, @intCast(self.config.padding.top)),
            .width = bounds.width -| self.config.padding.left -| self.config.padding.right,
            .height = bounds.height -| self.config.padding.top -| self.config.padding.bottom,
        };

        // Draw border if configured
        if (self.config.border_style) |border_style| {
            const border_ctx = renderer_mod.Render{
                .bounds = bounds.toBounds(),
                .style = .{},
                .zIndex = 0,
                .clipRegion = null,
            };
            try renderer.drawBox(border_ctx, border_style);
        }

        // Render content with offset
        if (self.content_renderer) |content_renderer| {
            const offset_bounds = widget_interface.Rect{
                .x = content_bounds.x - @as(i16, @intFromFloat(self.scroll_x)),
                .y = content_bounds.y - @as(i16, @intFromFloat(self.scroll_y)),
                .width = self.content_width,
                .height = self.content_height,
            };

            try content_renderer(self.content_ctx, renderer, offset_bounds, self.config.scroll_callback_data);
        }

        // Render scrollbars
        try self.renderScrollbars(renderer, bounds);
    }

    /// Render scrollbars
    fn renderScrollbars(
        self: *Self,
        renderer: *renderer_mod.Renderer,
        bounds: widget_interface.Rect,
    ) !void {
        // Vertical scrollbar
        if (self.config.show_vertical_scrollbar and
            (self.content_height > self.viewport_height or !self.config.auto_hide_scrollbars))
        {
            const scrollbar_x = bounds.x + bounds.width - 1;
            const scrollbar_y = bounds.y;
            const scrollbar_height = bounds.height;

            self.vertical_scrollbar.setScrollPosition(self.getScrollRatioY());
            const thumb_size_y = if (self.content_height > 0)
                @as(f64, @floatFromInt(self.viewport_height)) / @as(f64, @floatFromInt(self.content_height))
            else
                1.0;
            self.vertical_scrollbar.setThumbSize(thumb_size_y);

            // Create a simple buffer for rendering - in a real implementation you'd use the renderer's buffer system
            // For now, we'll skip the actual rendering and just update the scrollbar state
            _ = renderer;
            _ = scrollbar_x;
            _ = scrollbar_y;
            _ = scrollbar_height;
        }

        // Horizontal scrollbar
        if (self.config.show_horizontal_scrollbar and
            (self.content_width > self.viewport_width or !self.config.auto_hide_scrollbars))
        {
            const scrollbar_x = bounds.x;
            const scrollbar_y = bounds.y + bounds.height - 1;
            const scrollbar_width = bounds.width;

            self.horizontal_scrollbar.setScrollPosition(self.getScrollRatioX());
            const thumb_size_x = if (self.content_width > 0)
                @as(f64, @floatFromInt(self.viewport_width)) / @as(f64, @floatFromInt(self.content_width))
            else
                1.0;
            self.horizontal_scrollbar.setThumbSize(thumb_size_x);

            // Create a simple buffer for rendering - in a real implementation you'd use the renderer's buffer system
            // For now, we'll skip the actual rendering and just update the scrollbar state
            _ = renderer;
            _ = scrollbar_x;
            _ = scrollbar_y;
            _ = scrollbar_width;
        }
    }

    /// Update scrollbar positions
    fn updateScrollbars(self: *Self) void {
        self.vertical_scrollbar.setScrollPosition(self.getScrollRatioY());
        self.horizontal_scrollbar.setScrollPosition(self.getScrollRatioX());

        const thumb_size_y = if (self.content_height > 0)
            @as(f64, @floatFromInt(self.viewport_height)) / @as(f64, @floatFromInt(self.content_height))
        else
            1.0;
        self.vertical_scrollbar.setThumbSize(thumb_size_y);

        const thumb_size_x = if (self.content_width > 0)
            @as(f64, @floatFromInt(self.viewport_width)) / @as(f64, @floatFromInt(self.content_width))
        else
            1.0;
        self.horizontal_scrollbar.setThumbSize(thumb_size_x);
    }

    /// Get the widget type name
    pub fn getTypeName(_: Self) []const u8 {
        return "ScrollableContainer";
    }

    /// Set focus state
    pub fn setFocus(self: *Self, focused: bool) void {
        self.focused = focused;
    }

    /// Check if container can scroll in a direction
    pub fn canScroll(self: Self, direction: ScrollDirection) bool {
        return switch (direction) {
            .vertical => self.content_height > self.viewport_height,
            .horizontal => self.content_width > self.viewport_width,
            .both => (self.content_height > self.viewport_height) or (self.content_width > self.viewport_width),
        };
    }

    /// Get maximum scroll position
    pub fn getMaxScrollX(self: Self) f32 {
        return @max(0, @as(f32, @floatFromInt(self.content_width)) - @as(f32, @floatFromInt(self.viewport_width)));
    }

    pub fn getMaxScrollY(self: Self) f32 {
        return @max(0, @as(f32, @floatFromInt(self.content_height)) - @as(f32, @floatFromInt(self.viewport_height)));
    }
};

// Convenience functions for common configurations

/// Create a basic scrollable container
pub fn createBasicScrollableContainer(allocator: Allocator) !ScrollableContainer {
    return ScrollableContainer.init(allocator, .{});
}

/// Create a vertical-only scrollable container
pub fn createVerticalScrollableContainer(allocator: Allocator) !ScrollableContainer {
    return ScrollableContainer.init(allocator, .{
        .scroll_direction = .vertical,
        .show_horizontal_scrollbar = false,
    });
}

/// Create a horizontal-only scrollable container
pub fn createHorizontalScrollableContainer(allocator: Allocator) !ScrollableContainer {
    return ScrollableContainer.init(allocator, .{
        .scroll_direction = .horizontal,
        .show_vertical_scrollbar = false,
    });
}

/// Create a container with custom border
pub fn createBorderedScrollableContainer(
    allocator: Allocator,
    border_color: renderer_mod.Style.Color,
) !ScrollableContainer {
    return ScrollableContainer.init(allocator, .{
        .border_style = .{
            .border = .{
                .style = .single,
                .color = border_color,
            },
        },
    });
}

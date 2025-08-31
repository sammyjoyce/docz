//! TUI RenderEngine Abstraction Layer
//!
//! This provides a rendering interface that leverages the rich terminal capabilities
//! available in foundation/term while maintaining compatibility with limited terminals through
//! progressive enhancement. Also includes a widget system for building
//! interactive terminal user interfaces.

const std = @import("std");
const bounds_mod = @import("bounds.zig");
const tui_mod = @import("../../tui.zig");

pub const Point = bounds_mod.Point;
pub const Bounds = bounds_mod.Bounds;
pub const TerminalCapabilities = tui_mod.TerminalCapabilities;

// Additional geometric types for widget system
pub const Size = struct {
    width: u16,
    height: u16,
};

// Re-export Rect as BoundsI16 for backward compatibility
pub const Rect = @import("../../types.zig").BoundsI16;

/// Style information for rendering
pub const Style = struct {
    fg_color: ?Color = null,
    bg_color: ?Color = null,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    strikethrough: bool = false,

    pub const Color = union(enum) {
        ansi: u8, // 0-15 ANSI colors
        palette: u8, // 0-255 palette colors
        rgb: RGB, // RGB truecolor

        pub const RGB = struct {
            r: u8,
            g: u8,
            b: u8,
        };
    };
};

/// Graphics/Image data for rendering
pub const Image = struct {
    format: Format,
    data: []const u8,
    width: u32,
    height: u32,

    pub const Format = enum {
        kitty,
        sixel,
        ascii_art,
    };
};

/// Box styling for borders and backgrounds
pub const BoxStyle = struct {
    border: ?BorderStyle = null,
    background: ?Style.Color = null,
    padding: Padding = .{},

    pub const BorderStyle = struct {
        style: LineStyle = .single,
        color: ?Style.Color = null,

        pub const LineStyle = enum {
            single, // ┌─┐
            double, // ╔═╗
            rounded, // ╭─╮
            thick, // ┏━┓
            dotted, // ┌┄┐
        };
    };

    pub const Padding = struct {
        top: u32 = 0,
        right: u32 = 0,
        bottom: u32 = 0,
        left: u32 = 0,
    };
};

/// Context for rendering operations
pub const Render = struct {
    bounds: Bounds,
    style: Style = .{},
    zIndex: i32 = 0,
    clipRegion: ?Bounds = null,

    /// Create a context clipped to a smaller region
    pub fn clipped(self: Render, clip_bounds: Bounds) Render {
        const intersection = if (self.clipRegion) |existing|
            existing.intersection(clip_bounds)
        else
            clip_bounds;

        return Render{
            .bounds = self.bounds.intersection(intersection),
            .style = self.style,
            .zIndex = self.zIndex,
            .clipRegion = intersection,
        };
    }

    /// Offset the context by a certain amount
    pub fn offset(self: Render, dx: i32, dy: i32) Render {
        return Render{
            .bounds = self.bounds.offset(dx, dy),
            .style = self.style,
            .zIndex = self.zIndex,
            .clipRegion = if (self.clipRegion) |clip| clip.offset(dx, dy) else null,
        };
    }
};

/// Abstract renderer interface
pub const RenderEngine = struct {
    const Self = @This();

    /// Function pointers for renderer implementation
    vtable: *const VTable,
    impl: *anyopaque,

    pub const VTable = struct {
        // Core rendering operations
        begin_frame: *const fn (impl: *anyopaque) anyerror!void,
        end_frame: *const fn (impl: *anyopaque) anyerror!void,
        clear: *const fn (impl: *anyopaque, bounds: Bounds) anyerror!void,

        // Text rendering
        draw_text: *const fn (impl: *anyopaque, ctx: Render, text: []const u8) anyerror!void,
        measure_text: *const fn (impl: *anyopaque, text: []const u8, style: Style) anyerror!Point,

        // Shape rendering
        draw_box: *const fn (impl: *anyopaque, ctx: Render, box_style: BoxStyle) anyerror!void,
        draw_line: *const fn (impl: *anyopaque, ctx: Render, from: Point, to: Point) anyerror!void,
        fill_rect: *const fn (impl: *anyopaque, ctx: Render, color: Style.Color) anyerror!void,

        // Extended features (may be no-ops on limited terminals)
        draw_image: *const fn (impl: *anyopaque, ctx: Render, image: Image) anyerror!void,
        set_hyperlink: *const fn (impl: *anyopaque, url: []const u8) anyerror!void,
        clear_hyperlink: *const fn (impl: *anyopaque) anyerror!void,
        copy_to_clipboard: *const fn (impl: *anyopaque, text: []const u8) anyerror!void,
        send_notification: *const fn (impl: *anyopaque, title: []const u8, body: []const u8) anyerror!void,

        // Cursor and viewport management
        set_cursor_position: *const fn (impl: *anyopaque, pos: Point) anyerror!void,
        get_cursor_position: *const fn (impl: *anyopaque) anyerror!Point,
        show_cursor: *const fn (impl: *anyopaque, visible: bool) anyerror!void,

        // Capabilities query
        get_capabilities: *const fn (impl: *anyopaque) TerminalCapabilities,

        // Cleanup
        deinit: *const fn (impl: *anyopaque) void,
    };

    // Public interface methods
    pub inline fn beginFrame(self: *Self) !void {
        return self.vtable.begin_frame(self.impl);
    }

    pub inline fn endFrame(self: *Self) !void {
        return self.vtable.end_frame(self.impl);
    }

    pub inline fn clear(self: *Self, bounds: Bounds) !void {
        return self.vtable.clear(self.impl, bounds);
    }

    pub inline fn drawText(self: *Self, ctx: Render, text: []const u8) !void {
        return self.vtable.draw_text(self.impl, ctx, text);
    }

    pub inline fn measureText(self: *Self, text: []const u8, style: Style) !Point {
        return self.vtable.measure_text(self.impl, text, style);
    }

    pub inline fn drawBox(self: *Self, ctx: Render, box_style: BoxStyle) !void {
        return self.vtable.draw_box(self.impl, ctx, box_style);
    }

    pub inline fn drawLine(self: *Self, ctx: Render, from: Point, to: Point) !void {
        return self.vtable.draw_line(self.impl, ctx, from, to);
    }

    pub inline fn fillRect(self: *Self, ctx: Render, color: Style.Color) !void {
        return self.vtable.fill_rect(self.impl, ctx, color);
    }

    pub inline fn drawImage(self: *Self, ctx: Render, image: Image) !void {
        return self.vtable.draw_image(self.impl, ctx, image);
    }

    pub inline fn setHyperlink(self: *Self, url: []const u8) !void {
        return self.vtable.set_hyperlink(self.impl, url);
    }

    pub inline fn clearHyperlink(self: *Self) !void {
        return self.vtable.clear_hyperlink(self.impl);
    }

    pub inline fn copyToClipboard(self: *Self, text: []const u8) !void {
        return self.vtable.copy_to_clipboard(self.impl, text);
    }

    pub inline fn sendNotification(self: *Self, title: []const u8, body: []const u8) !void {
        return self.vtable.send_notification(self.impl, title, body);
    }

    pub inline fn setCursorPosition(self: *Self, pos: Point) !void {
        return self.vtable.set_cursor_position(self.impl, pos);
    }

    pub inline fn getCursorPosition(self: *Self) !Point {
        return self.vtable.get_cursor_position(self.impl);
    }

    pub inline fn showCursor(self: *Self, visible: bool) !void {
        return self.vtable.show_cursor(self.impl, visible);
    }

    pub inline fn getCapabilities(self: *Self) TerminalCapabilities {
        return self.vtable.get_capabilities(self.impl);
    }

    pub inline fn deinit(self: *Self) void {
        return self.vtable.deinit(self.impl);
    }

    /// Convenience methods that combine multiple operations
    /// Draw text with automatic measurement and styling
    pub fn drawStyledText(self: *Self, ctx: Render, text: []const u8) !Point {
        try self.drawText(ctx, text);
        return self.measureText(text, ctx.style);
    }

    /// Draw a bordered box with content
    pub fn drawTextBox(self: *Self, ctx: Render, text: []const u8, box_style: BoxStyle) !void {
        // Draw the box background and border
        try self.drawBox(ctx, box_style);

        // Calculate content area (inside padding)
        const content_bounds = Bounds{
            .x = ctx.bounds.x + @as(i32, @intCast(box_style.padding.left)),
            .y = ctx.bounds.y + @as(i32, @intCast(box_style.padding.top)),
            .width = ctx.bounds.width - box_style.padding.left - box_style.padding.right,
            .height = ctx.bounds.height - box_style.padding.top - box_style.padding.bottom,
        };

        const content_ctx = Render{
            .bounds = content_bounds,
            .style = ctx.style,
            .zIndex = ctx.zIndex,
            .clipRegion = ctx.clipRegion,
        };

        // Draw the text content
        try self.drawText(content_ctx, text);
    }

    /// Draw a notification with progressive enhancement
    pub fn drawNotification(self: *Self, ctx: Render, title: []const u8, message: []const u8, level: NotificationLevel) !void {
        const caps = self.getCapabilities();

        // Try system notification first if supported
        if (caps.supportsNotifyOsc9) {
            try self.sendNotification(title, message);
        }

        // Create styled box for in-terminal notification
        const level_color = getLevelColor(level, caps);
        const box_style = BoxStyle{
            .border = .{
                .style = .rounded,
                .color = level_color,
            },
            .padding = .{ .top = 1, .right = 2, .bottom = 1, .left = 2 },
        };

        const notification_style = Style{
            .fg_color = level_color,
            .bold = true,
        };

        const notification_ctx = Render{
            .bounds = ctx.bounds,
            .style = notification_style,
            .zIndex = ctx.zIndex + 1000, // High z-index for notifications
            .clipRegion = ctx.clipRegion,
        };

        // Format notification text
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const icon = getLevelIcon(level);
        const notification_text = try std.fmt.allocPrint(allocator, "{s} {s}\n{s}", .{ icon, title, message });

        try self.drawTextBox(notification_ctx, notification_text, box_style);
    }
};

/// Notification level for styled notifications
pub const NotificationLevel = enum {
    info,
    success,
    warning,
    error_,
    debug,
};

fn getLevelIcon(level: NotificationLevel) []const u8 {
    return switch (level) {
        .info => "ℹ",
        .success => "✓",
        .warning => "⚠",
        .error_ => "✗",
        .debug => "🐛",
    };
}

fn getLevelColor(level: NotificationLevel, caps: TerminalCapabilities) Style.Color {
    if (caps.supportsTruecolor) {
        return switch (level) {
            .info => .{ .rgb = .{ .r = 100, .g = 149, .b = 237 } }, // Cornflower blue
            .success => .{ .rgb = .{ .r = 50, .g = 205, .b = 50 } }, // Lime green
            .warning => .{ .rgb = .{ .r = 255, .g = 215, .b = 0 } }, // Gold
            .error_ => .{ .rgb = .{ .r = 220, .g = 20, .b = 60 } }, // Crimson
            .debug => .{ .rgb = .{ .r = 138, .g = 43, .b = 226 } }, // Blue violet
        };
    } else {
        return switch (level) {
            .info => .{ .palette = 12 }, // Bright blue
            .success => .{ .palette = 10 }, // Bright green
            .warning => .{ .palette = 11 }, // Bright yellow
            .error_ => .{ .palette = 9 }, // Bright red
            .debug => .{ .palette = 13 }, // Bright magenta
        };
    }
}

/// Factory function to create appropriate renderer based on terminal capabilities
pub fn createRenderEngine(allocator: std.mem.Allocator) !RenderEngine {
    // Try to detect terminal capabilities, use safe defaults on error
    const caps = tui_mod.detectCapabilities() catch blk: {
        // If capability detection fails, create safe fallback capabilities
        break :blk TerminalCapabilities{
            .supportsTruecolor = false,
            .supportsHyperlinkOsc8 = false,
            .supportsClipboardOsc52 = false,
            .supportsWorkingDirOsc7 = false,
            .supportsTitleOsc012 = false,
            .supportsNotifyOsc9 = false,
            .supportsFinalTermOsc133 = false,
            .supportsITerm2Osc1337 = false,
            .supportsColorOsc10_12 = false,
            .supportsKittyKeyboard = false,
            .supportsKittyGraphics = false,
            .supportsSixel = false,
            .supportsModifyOtherKeys = false,
            .supportsXtwinops = false,
            .supportsBracketedPaste = false,
            .supportsFocusEvents = false,
            .supportsSgrMouse = false,
            .supportsSgrPixelMouse = false,
            .supportsLightDarkReport = false,
            .supportsLinuxPaletteOscP = false,
            .supportsDeviceAttributes = false,
            .supportsCursorStyle = false,
            .supportsCursorPositionReport = false,
            .supportsPointerShape = false,
            .needsTmuxPassthrough = false,
            .needsScreenPassthrough = false,
            .screenChunkLimit = 4096,
            .widthMethod = .grapheme,
        };
    };

    // Determine if terminal has extended capabilities that warrant RichRenderEngine
    const hasExtendedCapabilities =
        caps.supportsTruecolor or
        caps.supportsKittyGraphics or
        caps.supportsSixel or
        caps.supportsHyperlinkOsc8 or
        caps.supportsClipboardOsc52 or
        caps.supportsNotifyOsc9 or
        caps.supportsColorOsc10_12 or
        caps.supportsXtwinops;

    // Choose renderer based on capabilities
    if (hasExtendedCapabilities) {
        // Try RichRenderEngine first for terminals with extended capabilities
        const rich_renderer = @import("renderers/rich.zig");
        const rich = rich_renderer.RichRenderEngine.init(allocator, caps) catch {
            // If RichRenderEngine fails, fall back to FallbackRenderer
            const fallback_renderer = @import("renderers/fallback.zig");
            return try fallback_renderer.create(allocator, caps);
        };
        return rich.toRenderEngine();
    } else {
        // Use FallbackRenderer for limited terminals
        const fallback_renderer = @import("renderers/fallback.zig");
        return try fallback_renderer.create(allocator, caps);
    }
}

// ============================================================================
// WIDGET SYSTEM
// ============================================================================

/// Input event types for widget interaction
pub const InputEvent = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    resize: Size,
    focus: bool,

    pub const KeyEvent = struct {
        key: Key,
        modifiers: Modifiers,
    };

    // Re-export shared types for backward compatibility
    pub const MouseEvent = @import("../../types.zig").MouseEvent;

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

    // Re-export unified types for backward compatibility
    pub const Modifiers = @import("../../types.zig").Modifiers;

    // Re-export unified types for backward compatibility
    pub const MouseButton = @import("../../types.zig").MouseButton;
    pub const MouseAction = @import("../../types.zig").MouseAction;
};

/// Theme system for consistent styling
pub const Theme = struct {
    // Basic colors
    background: Style.Color,
    foreground: Style.Color,
    accent: Style.Color,

    // State colors
    focused: Style.Color,
    selected: Style.Color,
    disabled: Style.Color,

    // Status colors
    success: Style.Color,
    warning: Style.Color,
    danger: Style.Color,

    pub fn defaultLight() Theme {
        return Theme{
            .background = .{ .palette = 15 }, // White
            .foreground = .{ .palette = 0 }, // Black
            .accent = .{ .palette = 12 }, // Blue
            .focused = .{ .palette = 14 }, // Cyan
            .selected = .{ .palette = 11 }, // Yellow
            .disabled = .{ .palette = 8 }, // Gray
            .success = .{ .palette = 10 }, // Green
            .warning = .{ .palette = 214 }, // Orange
            .danger = .{ .palette = 9 }, // Red
        };
    }

    pub fn defaultDark() Theme {
        return Theme{
            .background = .{ .palette = 0 }, // Black
            .foreground = .{ .palette = 15 }, // White
            .accent = .{ .palette = 14 }, // Cyan
            .focused = .{ .palette = 12 }, // Blue
            .selected = .{ .palette = 13 }, // Purple
            .disabled = .{ .palette = 8 }, // Gray
            .success = .{ .palette = 10 }, // Green
            .warning = .{ .palette = 214 }, // Orange
            .danger = .{ .palette = 9 }, // Red
        };
    }
};

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
pub const WidgetLayout = struct {
    size: Size,
    position: Point,
    constraints: Constraints,
};

/// Widget VTable - defines the interface all widgets must implement
pub const WidgetVTable = struct {
    /// Render the widget to the terminal
    render: *const fn (ctx: *anyopaque, renderer: *RenderEngine, area: Rect) anyerror!void,

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
    layout_info: WidgetLayout,

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
    pub fn render(self: *Widget, renderer: *RenderEngine) !void {
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
    background: ?Style.Color = null,

    /// Border style
    border: ?struct {
        color: Style.Color,
        style: enum { single, double, rounded } = .single,
    } = null,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Container {
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

    pub fn render(self: *Container, renderer: *RenderEngine, area: Rect) !void {
        // Draw background
        if (self.background) |bg| {
            const bg_style = Style{ .bg_color = bg };
            const bg_ctx = Render{
                .bounds = area.toBounds(),
                .style = bg_style,
                .zIndex = 0,
                .clipRegion = null,
            };
            try renderer.fillRect(bg_ctx, bg);
        }

        // Draw border
        if (self.border) |border| {
            const border_style = BoxStyle{
                .border = .{
                    .style = switch (border.style) {
                        .single => .single,
                        .double => .double,
                        .rounded => .rounded,
                    },
                    .color = border.color,
                },
            };
            const border_ctx = Render{
                .bounds = area.toBounds(),
                .style = .{},
                .zIndex = 0,
                .clipRegion = null,
            };
            try renderer.drawBox(border_ctx, border_style);
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

/// Layout system with flexbox-style alignment
pub const Layout = struct {
    pub const Direction = enum {
        horizontal,
        vertical,
    };

    pub const Alignment = enum {
        /// Align items to the start of the container
        start,
        /// Center items within the container
        center,
        /// Align items to the end of the container
        end,
        /// Stretch items to fill the container
        stretch,
        /// Distribute items with equal spacing between them (no space at edges)
        space_between,
        /// Distribute items with equal spacing around each item (half space at edges)
        space_around,
        /// Distribute items with equal spacing including edges
        space_evenly,
    };

    /// Advanced flex layout implementation with space distribution modes
    ///
    /// Supports both traditional alignment and CSS Flexbox-style space distribution:
    /// - `start`: Align items to the start of the container
    /// - `center`: Center items within the container
    /// - `end`: Align items to the end of the container
    /// - `stretch`: Stretch items to fill the container
    /// - `space_between`: Equal spacing between items, no space at edges
    /// - `space_around`: Equal spacing around items, half space at edges
    /// - `space_evenly`: Equal spacing including edges
    ///
    /// ## Example
    /// ```zig
    /// var widgets = [_]Widget{ widget1, widget2, widget3 };
    /// Layout.flexLayout(container_rect, &widgets, .horizontal, .space_between);
    /// ```
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

        const item_count = children.len;

        // Calculate spacing and positioning for complex flex modes
        var spacing: u16 = 0;
        var start_offset: u16 = 0;
        const child_size: u16 = available_space / @as(u16, @intCast(item_count));

        if (item_count > 1) {
            switch (alignment) {
                .space_between => {
                    // Equal spacing between items, no space at edges
                    // Child size remains the same, spacing is calculated from remaining space
                    const total_item_space = child_size * @as(u16, @intCast(item_count));
                    const remaining_space = available_space - total_item_space;
                    spacing = remaining_space / @as(u16, @intCast(item_count - 1));
                },
                .space_around => {
                    // Equal spacing around items, half space at edges
                    // Child size remains the same, spacing is calculated from remaining space
                    const total_item_space = child_size * @as(u16, @intCast(item_count));
                    const remaining_space = available_space - total_item_space;
                    spacing = remaining_space / @as(u16, @intCast(item_count));
                    start_offset = spacing / 2;
                },
                .space_evenly => {
                    // Equal spacing including edges
                    // Child size remains the same, spacing is calculated from remaining space
                    const total_item_space = child_size * @as(u16, @intCast(item_count));
                    const remaining_space = available_space - total_item_space;
                    spacing = remaining_space / @as(u16, @intCast(item_count + 1));
                    start_offset = spacing;
                },
                else => {
                    // Traditional alignment modes - equal space distribution
                    spacing = 0;
                    start_offset = 0;
                },
            }
        }

        // Position children based on alignment mode
        var current_pos = switch (direction) {
            .horizontal => container.x + @as(i16, @intCast(start_offset)),
            .vertical => container.y + @as(i16, @intCast(start_offset)),
        };

        for (children) |*child| {
            switch (direction) {
                .horizontal => {
                    child.bounds = Rect{
                        .x = current_pos,
                        .y = container.y,
                        .width = child_size,
                        .height = container.height,
                    };
                    current_pos += @as(i16, @intCast(child_size + spacing));
                },
                .vertical => {
                    child.bounds = Rect{
                        .x = container.x,
                        .y = current_pos,
                        .width = container.width,
                        .height = child_size,
                    };
                    current_pos += @as(i16, @intCast(child_size + spacing));
                },
            }

            // Apply alignment adjustments
            switch (alignment) {
                .start => {}, // Already positioned at start
                .center => {
                    // Center the widget in its allocated space
                    const measured = child.measure(child.layout_info.constraints);
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
                    const measured = child.measure(child.layout_info.constraints);
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
                .space_between, .space_around, .space_evenly => {
                    // For space modes, items are positioned with calculated spacing
                    // Additional alignment within each item's space can be applied here if needed
                },
            }
        }
    }
};

/// Unified renderer that consolidates TUI systems
pub const Renderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    renderer: RenderEngine,
    theme: Theme,
    widgets: std.ArrayList(*Widget),
    focused_widget: ?*Widget,
    needs_redraw: bool,

    pub fn init(allocator: std.mem.Allocator, theme: Theme) !Self {
        const renderer = try createRenderEngine(allocator);

        return Self{
            .allocator = allocator,
            .renderer = renderer,
            .theme = theme,
            .widgets = std.ArrayList(*Widget).init(allocator),
            .focused_widget = null,
            .needs_redraw = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.widgets.deinit();
        self.renderer.deinit();
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
        }

        widget.focused = true;
        self.focused_widget = widget;
        self.needs_redraw = true;
    }

    /// Handle input events
    pub fn handleInput(self: *Self, event: InputEvent) !bool {
        // Try focused widget first
        if (self.focused_widget) |widget| {
            if (try widget.handleInput(event)) {
                return true;
            }
        }

        // Try other widgets in reverse order (top-most first)
        var i: usize = self.widgets.items.len;
        while (i > 0) {
            i -= 1;
            const widget = self.widgets.items[i];
            if (widget != self.focused_widget) {
                if (try widget.handleInput(event)) {
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

        try self.renderer.beginFrame();
        defer self.renderer.endFrame() catch |err| {
            std.log.warn("Failed to end render frame: {any}", .{err});
        };

        // Clear screen
        const screen_bounds = Bounds{ .x = 0, .y = 0, .width = 80, .height = 24 }; // Default, should be configurable
        try self.renderer.clear(screen_bounds);

        // Render all widgets in order
        for (self.widgets.items) |widget| {
            if (widget.visible) {
                try widget.render(&self.renderer);
            }
        }

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

    /// Get the underlying renderer for direct operations
    pub fn getRenderEngine(self: *Self) *RenderEngine {
        return &self.renderer;
    }
};

/// Helper functions for creating widgets
pub const WidgetBuilder = struct {
    /// Create a text widget
    pub fn text(allocator: std.mem.Allocator, content: []const u8, id: []const u8, bounds: Rect) !*Widget {
        const TextWidget = struct {
            content: []const u8,
            allocator: std.mem.Allocator,

            pub fn render(ctx: *anyopaque, renderer: *RenderEngine, area: Rect) !void {
                const self: *@This() = @ptrCast(@alignCast(ctx));
                const render_ctx = Render{
                    .bounds = area.toBounds(),
                    .style = .{},
                    .zIndex = 0,
                    .clipRegion = null,
                };
                try renderer.drawText(render_ctx, self.content);
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
    pub fn button(allocator: std.mem.Allocator, label: []const u8, id: []const u8, bounds: Rect, on_click: ?*const fn (*Widget) void) !*Widget {
        const ButtonWidget = struct {
            label: []const u8,
            on_click: ?*const fn (*Widget) void,
            allocator: std.mem.Allocator,

            pub fn render(ctx: *anyopaque, renderer: *RenderEngine, area: Rect) !void {
                const self: *@This() = @ptrCast(@alignCast(ctx));

                // Draw button background
                const button_text = try std.fmt.allocPrint(self.allocator, "[ {s} ]", .{self.label});
                defer self.allocator.free(button_text);

                const render_ctx = Render{
                    .bounds = area.toBounds(),
                    .style = Style{
                        .bg_color = .{ .palette = 12 }, // Blue
                        .fg_color = .{ .palette = 15 }, // White
                    },
                    .zIndex = 0,
                    .clipRegion = null,
                };
                try renderer.drawText(render_ctx, button_text);
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
    pub fn container(allocator: std.mem.Allocator, id: []const u8, bounds: Rect, direction: enum { horizontal, vertical }) !*Widget {
        const ContainerWidget = struct {
            container: Container,

            pub fn render(ctx: *anyopaque, renderer: *RenderEngine, area: Rect) !void {
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

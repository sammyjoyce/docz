//! Renderer System
//!
//! This module provides a single interface for all rendering needs
//! in the terminal UI system. It uses a strategy pattern to adapt rendering
//! based on terminal capabilities and provides progressive enhancement.
//!
//! The renderer consolidates functionality from:
//! - Renderer (text rendering with capability detection)
//! - Renderer (widget-based TUI rendering)
//! - Graphics Renderer (graphics rendering)

const std = @import("std");
const term = @import("../term.zig");
const theme_mod = @import("../theme.zig");
const Allocator = std.mem.Allocator;

/// Unified renderer that adapts to terminal capabilities and provides
/// progressive enhancement for all rendering needs
pub const Renderer = struct {
    const Self = @This();

    allocator: Allocator,
    terminal: *anyopaque, // Terminal handle
    capabilities: TermCaps,
    renderTier: RenderTier,
    graphics: ?*anyopaque, // Graphics instance
    cache: Cache,
    theme: *theme_mod.Theme,

    // Widget system support
    widgets: std.ArrayList(*Widget),
    focusedWidget: ?*Widget,
    needsRedraw: bool,

    /// Rendering tier based on terminal capabilities
    pub const RenderTier = enum {
        /// Full graphics, true color, animations, features
        ultra,
        /// 256 colors, Unicode blocks, basic graphics
        rich,
        /// 16 colors, Unicode characters, standard features
        standard,
        /// Plain text only, maximum compatibility
        minimal,

        pub fn fromCapabilities(term_caps: TermCaps) RenderTier {
            if ((term_caps.supportsKittyGraphics or term_caps.supportsSixel) and term_caps.supportsTruecolor) {
                return .ultra;
            } else if (term_caps.supportsTruecolor) {
                return .rich;
            } else {
                return .standard; // Assume Unicode support for modern terminals
            }
        }

        pub fn description(self: RenderTier) []const u8 {
            return switch (self) {
                .ultra => "Ultra (Graphics, True Color, Animations)",
                .rich => "Rich (256 Colors, Unicode Blocks)",
                .standard => "Standard (16 Colors, Unicode)",
                .minimal => "Minimal (Plain Text Only)",
            };
        }
    };

    /// Cache for rendered content to avoid recomputation
    pub const Cache = struct {
        allocator: Allocator,
        entries: std.HashMap(u64, Entry, std.HashMap.DefaultRender(u64), 80),

        const Entry = struct {
            content: []u8,
            timestamp: i64,
            renderTier: RenderTier,
        };

        pub fn init(allocator: Allocator) Cache {
            return Cache{
                .allocator = allocator,
                .entries = std.HashMap(u64, Entry, std.HashMap.DefaultRender(u64), 80).init(allocator),
            };
        }

        pub fn deinit(self: *Cache) void {
            var iterator = self.entries.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.value_ptr.content);
            }
            self.entries.deinit();
        }

        pub fn get(self: *const Cache, key: u64, render_tier: RenderTier) ?[]const u8 {
            const entry = self.entries.get(key) orelse return null;
            if (entry.renderTier != render_tier) return null;
            return entry.content;
        }

        pub fn put(self: *Cache, key: u64, content: []const u8, render_tier: RenderTier) !void {
            const now = std.time.milliTimestamp();
            const owned_content = try self.allocator.dupe(u8, content);

            const result = try self.entries.getOrPut(key);
            if (result.found_existing) {
                self.allocator.free(result.value_ptr.content);
            }

            result.value_ptr.* = Entry{
                .content = owned_content,
                .timestamp = now,
                .renderTier = render_tier,
            };
        }
    };

    /// Terminal capabilities
    pub const TermCaps = struct {
        supportsTruecolor: bool = false,
        supportsUnicode: bool = true,
        supportsKittyGraphics: bool = false,
        supportsSixel: bool = false,
        supportsSgrMouse: bool = false,

        pub fn supportsSynchronizedOutput(self: TermCaps) bool {
            _ = self;
            return false; // Conservative default
        }
    };

    /// Convert RGB to nearest 256-color palette index
    pub fn rgbToPaletteColor(rgb: struct { r: u8, g: u8, b: u8 }) u8 {
        const r6 = rgb.r * 5 / 255;
        const g6 = rgb.g * 5 / 255;
        const b6 = rgb.b * 5 / 255;
        return 16 + (r6 * 36) + (g6 * 6) + b6;
    }

    // ============================================================================
    // WIDGET SYSTEM INTEGRATION
    // ============================================================================

    /// Point for widget positioning
    pub const Point = struct {
        x: i16,
        y: i16,
    };

    /// Bounds for widget layout
    pub const Bounds = struct {
        x: i16,
        y: i16,
        width: u16,
        height: u16,

        pub fn init(x: i16, y: i16, width: u16, height: u16) Bounds {
            return .{ .x = x, .y = y, .width = width, .height = height };
        }

        pub fn intersection(self: Bounds, other: Bounds) Bounds {
            const x = @max(self.x, other.x);
            const y = @max(self.y, other.y);
            const x2 = @min(self.x + @as(i16, @intCast(self.width)), other.x + @as(i16, @intCast(other.width)));
            const y2 = @min(self.y + @as(i16, @intCast(self.height)), other.y + @as(i16, @intCast(other.height)));
            if (x2 <= x or y2 <= y) {
                return .{ .x = x, .y = y, .width = 0, .height = 0 };
            }
            return .{ .x = x, .y = y, .width = @intCast(x2 - x), .height = @intCast(y2 - y) };
        }

        pub fn offset(self: Bounds, dx: i32, dy: i32) Bounds {
            return .{
                .x = @intCast(@as(i32, self.x) + dx),
                .y = @intCast(@as(i32, self.y) + dy),
                .width = self.width,
                .height = self.height,
            };
        }
    };

    /// Size for widget layout
    pub const Size = struct {
        width: u16,
        height: u16,
    };

    /// Rect for widget positioning and sizing
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

        pub fn toBounds(self: Rect) Bounds {
            return Bounds{
                .x = self.x,
                .y = self.y,
                .width = self.width,
                .height = self.height,
            };
        }
    };

    /// Style information for rendering
    pub const Style = struct {
        fgColor: ?Style.Color = null,
        bgColor: ?Style.Color = null,
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

    /// Alias for backward compatibility
    pub const StyleColor = Style.Color;

    /// Render context for widget rendering operations
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

        // Re-export unified types for backward compatibility
        pub const MouseEvent = @import("../types.zig").MouseEvent;

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
        pub const Modifiers = @import("../types.zig").Modifiers;

        // Re-export unified types for backward compatibility
        pub const MouseButton = @import("../types.zig").MouseButton;
        pub const MouseAction = @import("../types.zig").MouseAction;
    };

    /// Widget constraints for layout
    pub const Constraints = struct {
        minWidth: u16 = 0,
        maxWidth: u16 = std.math.maxInt(u16),
        minHeight: u16 = 0,
        maxHeight: u16 = std.math.maxInt(u16),

        pub fn fixed(width: u16, height: u16) Constraints {
            return .{
                .minWidth = width,
                .maxWidth = width,
                .minHeight = height,
                .maxHeight = height,
            };
        }

        pub fn loose(min_width: u16, min_height: u16) Constraints {
            return .{
                .minWidth = min_width,
                .maxHeight = min_height,
            };
        }
    };

    /// Widget layout information
    pub const Layout = struct {
        size: Size,
        position: Point,
        constraints: Constraints,
    };

    /// Widget VTable - defines the interface all widgets must implement
    pub const WidgetVTable = struct {
        /// Render the widget to the terminal
        render: *const fn (ctx: *anyopaque, renderer: *Renderer, area: Rect) anyerror!void,

        /// Handle input events
        handleInput: *const fn (ctx: *anyopaque, event: InputEvent, area: Rect) anyerror!bool,

        /// Calculate the widget's desired size
        measure: *const fn (ctx: *anyopaque, constraints: Constraints) Size,

        /// Get widget type name for debugging
        getTypeName: *const fn (ctx: *anyopaque) []const u8,
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
        userData: ?*anyopaque = null,

        /// Layout information
        layout: Layout,

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
                .layout = .{
                    .size = .{ .width = bounds.width, .height = bounds.height },
                    .position = .{ .x = bounds.x, .y = bounds.y },
                    .constraints = .{},
                },
            };
        }

        /// Render the widget
        pub fn render(self: *Widget, renderer: *Renderer) !void {
            if (!self.visible) return;

            try self.vtable.render(self.ptr, renderer, self.bounds);
        }

        /// Handle input event
        pub fn handleInput(self: *Widget, event: InputEvent) !bool {
            if (!self.visible) return false;

            return try self.vtable.handleInput(self.ptr, event, self.bounds);
        }

        /// Measure the widget's desired size
        pub fn measure(self: *Widget, constraints: Constraints) Size {
            return self.vtable.measure(self.ptr, constraints);
        }

        /// Set widget bounds
        pub fn setBounds(self: *Widget, bounds: Rect) void {
            self.bounds = bounds;
            self.layout.size = .{ .width = bounds.width, .height = bounds.height };
            self.layout.position = .{ .x = bounds.x, .y = bounds.y };
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
            return self.vtable.getTypeName(self.ptr);
        }
    };

    /// Container widget for composition
    pub const Container = struct {
        /// Child widgets
        children: std.array_list.Managed(*Widget),

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
                .children = std.array_list.Managed(*Widget).init(allocator),
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

        pub fn render(self: *Container, renderer: *Renderer, area: Rect) !void {
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
                .width = std.math.clamp(total_width, constraints.minWidth, constraints.maxWidth),
                .height = std.math.clamp(total_height, constraints.minHeight, constraints.maxHeight),
            };
        }
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

    /// Set color based on renderer capabilities (from adaptive_renderer)
    pub fn setRendererColor(self: *Renderer, color: theme_mod.Theme.Color, writer: anytype) !void {
        const term_caps = self.capabilities;

        switch (self.renderTier) {
            .ultra, .rich => {
                if (term_caps.supportsTruecolor) {
                    try term.sgr.setForegroundRgb(writer, term_caps, color.rgb.r, color.rgb.g, color.rgb.b);
                } else {
                    try term.sgr.setForeground256(writer, term_caps, color.ansi256);
                }
            },
            .standard => {
                try term.sgr.setForeground256(writer, term_caps, color.ansi256);
            },
            .minimal => {
                try writer.print("\x1b[{d}m", .{30 + color.ansi16});
            },
        }
    }

    /// Reset color and style
    pub fn resetRendererColor(self: *Renderer, writer: anytype) !void {
        const term_caps = self.capabilities;
        try term.sgr.resetStyle(writer, term_caps);
    }

    /// Initialize renderer with automatic capability detection
    pub fn init(allocator: Allocator) !*Renderer {
        const terminal = try term.Terminal.init(allocator);
        const capabilities = terminal.caps;
        const render_tier = RenderTier.fromCapabilities(capabilities);

        const renderer = try allocator.create(Renderer);
        renderer.* = Renderer{
            .allocator = allocator,
            .terminal = terminal,
            .capabilities = capabilities,
            .render_tier = render_tier,
            .graphics = null, // Initialize on demand
            .cache = Cache.init(allocator),
            .theme = try theme_mod.Theme.createDark(allocator),
            .widgets = std.array_list.Managed(*Widget).init(allocator),
            .focused_widget = null,
            .needs_redraw = true,
        };

        return renderer;
    }

    /// Initialize with explicit render tier (for testing or forced modes)
    pub fn initWithTier(allocator: Allocator, tier: RenderTier) !*Renderer {
        const terminal = try term.Terminal.init(allocator);
        const capabilities = terminal.caps;

        const renderer = try allocator.create(Renderer);
        renderer.* = Renderer{
            .allocator = allocator,
            .terminal = terminal,
            .capabilities = capabilities,
            .render_tier = tier,
            .graphics = null,
            .cache = Cache.init(allocator),
            .theme = try theme_mod.Theme.createDark(allocator),
            .widgets = std.array_list.Managed(*Widget).init(allocator),
            .focused_widget = null,
            .needs_redraw = true,
        };

        return renderer;
    }

    /// Initialize with custom theme
    pub fn initWithTheme(allocator: Allocator, theme: *theme_mod.Theme) !*Renderer {
        const terminal = try term.Terminal.init(allocator);
        const capabilities = terminal.caps;
        const render_tier = RenderTier.fromCapabilities(capabilities);

        const renderer = try allocator.create(Renderer);
        renderer.* = Renderer{
            .allocator = allocator,
            .terminal = terminal,
            .capabilities = capabilities,
            .render_tier = render_tier,
            .graphics = null,
            .cache = Cache.init(allocator),
            .theme = theme,
            .widgets = std.array_list.Managed(*Widget).init(allocator),
            .focused_widget = null,
            .needs_redraw = true,
        };

        return renderer;
    }

    pub fn deinit(self: *Renderer) void {
        if (self.graphics) |gm| {
            gm.deinit();
            self.allocator.destroy(gm);
        }
        self.widgets.deinit();
        self.cache.deinit();
        self.terminal.deinit();
        self.allocator.destroy(self);
    }

    /// Get current terminal dimensions
    pub fn getSize(self: *const Renderer) !struct { width: u16, height: u16 } {
        return try self.terminal.getTerminalSize();
    }

    /// Clear screen with proper handling for all render tiers
    pub fn clearScreen(self: *Renderer) !void {
        try self.terminal.clearScreen();
    }

    /// Clear a specific region
    pub fn clear(self: *Renderer, bounds: Bounds) !void {
        for (0..bounds.height) |y| {
            try self.moveCursor(@intCast(bounds.x), @intCast(bounds.y + y));
            for (0..bounds.width) |_| {
                try self.terminal.writeText(" ");
            }
        }
    }

    /// Move cursor to position (0-based coordinates)
    pub fn moveCursor(self: *Renderer, x: u16, y: u16) !void {
        try self.terminal.moveCursor(x, y);
    }

    /// Write text with optional color and style
    pub fn writeText(self: *Renderer, text: []const u8, color: ?term.Color, bold: bool) !void {
        if (color) |c| {
            try self.terminal.setForegroundColor(c);
        }

        if (bold and self.renderTier != .minimal) {
            try self.terminal.setBold(true);
        }

        try self.terminal.writeText(text);

        if (bold and self.renderTier != .minimal) {
            try self.terminal.setBold(false);
        }

        if (color != null) {
            try self.terminal.resetColor();
        }
    }

    /// Start synchronized output for flicker-free updates (if supported)
    pub fn beginSynchronized(self: *Renderer) !void {
        if (self.renderTier == .ultra) {
            try self.terminal.beginSynchronizedOutput();
        }
    }

    /// End synchronized output
    pub fn endSynchronized(self: *Renderer) !void {
        if (self.renderTier == .ultra) {
            try self.terminal.endSynchronizedOutput();
        }
    }

    /// Flush output buffer
    pub fn flush(self: *Renderer) !void {
        try self.terminal.flush();
    }

    /// Get information about current rendering capabilities
    pub fn getCapabilities(self: *const Renderer) Capabilities {
        return Capabilities{
            .tier = self.renderTier,
            .supportsTruecolor = self.capabilities.supportsTruecolor,
            .supports256Color = self.capabilities.supportsTruecolor, // Use truecolor as proxy for 256 color
            .supportsUnicode = self.capabilities.supportsUnicode,
            .supportsGraphics = self.capabilities.supportsKittyGraphics or self.capabilities.supportsSixel,
            .supportsMouse = self.capabilities.supportsSgrMouse,
            .supportsSynchronized = self.capabilities.supportsSynchronizedOutput(),
            .terminalName = "detected", // Would need to be detected separately
        };
    }

    pub const Capabilities = struct {
        tier: RenderTier,
        supportsTruecolor: bool,
        supports256Color: bool,
        supportsUnicode: bool,
        supportsGraphics: bool,
        supportsMouse: bool,
        supportsSynchronized: bool,
        terminalName: []const u8,

        pub fn print(self: Capabilities, writer: anytype) !void {
            try writer.print("Rendering Tier: {s}\n", .{self.tier.description()});
            try writer.print("Terminal: {s}\n", .{self.terminalName});
            try writer.print("Features:\n");
            try writer.print("  True Color: {any}\n", .{self.supportsTruecolor});
            try writer.print("  256 Colors: {any}\n", .{self.supports256Color});
            try writer.print("  Unicode: {any}\n", .{self.supportsUnicode});
            try writer.print("  Graphics: {any}\n", .{self.supportsGraphics});
            try writer.print("  Mouse: {any}\n", .{self.supportsMouse});
            try writer.print("  Synchronized: {any}\n", .{self.supportsSynchronized});
        }
    };

    /// Get or create graphics instance for rendering
    pub fn getGraphics(self: *Renderer) !*anyopaque {
        if (self.graphics) |g| {
            return g;
        }

        // TODO: Initialize graphics properly
        const g = try self.allocator.create(u8);
        g.* = 0;
        self.graphics = g;
        return g;
    }

    /// Set current theme
    pub fn setTheme(self: *Renderer, theme: *theme_mod.Theme) void {
        self.theme = theme;
    }

    /// Get current theme
    pub fn getTheme(self: *const Renderer) *theme_mod.Theme {
        return self.theme;
    }

    /// Get terminal for direct access (for use cases)
    pub fn getTerminal(self: *Renderer) *anyopaque {
        return &self.terminal;
    }

    /// Get cache for direct access (for caching)
    pub fn getCache(self: *Renderer) *Cache {
        return &self.cache;
    }

    /// Generate cache key for content
    pub fn cacheKey(comptime fmt: []const u8, args: anytype) u64 {
        var hasher = std.hash.Wyhash.init(0);
        const content = std.fmt.allocPrint(std.heap.page_allocator, fmt, args) catch return 0;
        defer std.heap.page_allocator.free(content);
        hasher.update(content);
        return hasher.final();
    }

    // ============================================================================
    // WIDGET SYSTEM METHODS
    // ============================================================================

    /// Add a widget to the renderer
    pub fn addWidget(self: *Renderer, widget: *Widget) !void {
        try self.widgets.append(widget);

        // Focus the first widget if none is focused
        if (self.focusedWidget == null) {
            self.setFocus(widget);
        }

        self.needsRedraw = true;
    }

    /// Remove a widget from the renderer
    pub fn removeWidget(self: *Renderer, widget: *Widget) void {
        for (self.widgets.items, 0..) |w, i| {
            if (w == widget) {
                _ = self.widgets.orderedRemove(i);

                // Update focus if removing focused widget
                if (self.focusedWidget == widget) {
                    if (self.widgets.items.len > 0) {
                        self.setFocus(self.widgets.items[0]);
                    } else {
                        self.focusedWidget = null;
                    }
                }

                self.needsRedraw = true;
                break;
            }
        }
    }

    /// Set focus to a specific widget
    pub fn setFocus(self: *Renderer, widget: *Widget) void {
        if (self.focusedWidget) |old_focus| {
            old_focus.focused = false;
        }

        widget.focused = true;
        self.focusedWidget = widget;
        self.needsRedraw = true;
    }

    /// Handle input events
    pub fn handleInput(self: *Renderer, event: InputEvent) !bool {
        // Try focused widget first
        if (self.focusedWidget) |widget| {
            if (try widget.handleInput(event)) {
                return true;
            }
        }

        // Try other widgets in reverse order (top-most first)
        var i: usize = self.widgets.items.len;
        while (i > 0) {
            i -= 1;
            const widget = self.widgets.items[i];
            if (widget != self.focusedWidget) {
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

    fn handleResize(self: *Renderer, size: Size) void {
        _ = size;
        // Trigger layout recalculation
        self.needsRedraw = true;
    }

    fn handleSystemKey(self: *Renderer, key_event: InputEvent.KeyEvent) bool {
        switch (key_event.key) {
            .tab => {
                // Cycle focus between widgets
                if (self.widgets.items.len > 1) {
                    var next_index: usize = 0;

                    if (self.focusedWidget) |current| {
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
    pub fn renderWidgets(self: *Renderer) !void {
        if (!self.needsRedraw) return;

        try self.beginSynchronized();
        defer self.endSynchronized() catch {};

        // Clear screen
        const screen_bounds = Bounds.init(0, 0, 80, 24); // Default, should be configurable
        try self.clear(screen_bounds);

        // Render all widgets in order
        for (self.widgets.items) |widget| {
            if (widget.visible) {
                try widget.render(self);
            }
        }

        self.needsRedraw = false;
    }

    /// Force a redraw on the next render cycle
    pub fn invalidate(self: *Renderer) void {
        self.needsRedraw = true;
    }

    /// Get the underlying renderer for operations
    pub fn getRenderer(self: *Renderer) *Renderer {
        return self;
    }

    // ============================================================================
    // ADDITIONAL RENDERING METHODS FOR WIDGET SYSTEM
    // ============================================================================

    /// Draw text with style context
    pub fn drawText(self: *Renderer, ctx: Render, text: []const u8) !void {
        // Move cursor to position
        try self.moveCursor(@intCast(ctx.bounds.x), @intCast(ctx.bounds.y));

        // Apply style
        if (ctx.style.fgColor) |color| {
            try self.applyStyleColor(color);
        }
        if (ctx.style.bold) {
            try self.terminal.setBold(true);
        }
        if (ctx.style.italic) {
            try self.terminal.setItalic(true);
        }
        if (ctx.style.underline) {
            try self.terminal.setUnderline(true);
        }
        if (ctx.style.strikethrough) {
            try self.terminal.setStrikethrough(true);
        }

        try self.terminal.writeText(text);

        // Reset style
        try self.terminal.resetStyle();
    }

    /// Measure text with style
    pub fn measureText(self: *Renderer, text: []const u8, style: Style) !Point {
        _ = self;
        _ = style;
        // Simple implementation - each character is 1x1
        return Point{
            .x = @intCast(text.len),
            .y = 1,
        };
    }

    /// Draw a box with style
    pub fn drawBox(self: *Renderer, ctx: Render, box_style: BoxStyle) !void {
        if (box_style.border) |border| {
            const border_chars = switch (border.style) {
                .single => .{ '┌', '─', '┐', '│', '└', '┘' },
                .double => .{ '╔', '═', '╗', '║', '╚', '╝' },
                .rounded => .{ '╭', '─', '╮', '│', '╰', '╯' },
                .thick => .{ '┏', '━', '┓', '┃', '┗', '┛' },
                .dotted => .{ '┌', '┄', '┐', '┊', '└', '┘' },
            };

            // Draw corners
            try self.moveCursor(@intCast(ctx.bounds.x), @intCast(ctx.bounds.y));
            try self.terminal.writeText(&[_]u8{border_chars[0]});
            try self.moveCursor(@intCast(ctx.bounds.x + ctx.bounds.width - 1), @intCast(ctx.bounds.y));
            try self.terminal.writeText(&[_]u8{border_chars[2]});
            try self.moveCursor(@intCast(ctx.bounds.x), @intCast(ctx.bounds.y + ctx.bounds.height - 1));
            try self.terminal.writeText(&[_]u8{border_chars[4]});
            try self.moveCursor(@intCast(ctx.bounds.x + ctx.bounds.width - 1), @intCast(ctx.bounds.y + ctx.bounds.height - 1));
            try self.terminal.writeText(&[_]u8{border_chars[5]});

            // Draw horizontal lines
            for (1..ctx.bounds.width - 1) |i| {
                try self.moveCursor(@intCast(ctx.bounds.x + i), @intCast(ctx.bounds.y));
                try self.terminal.writeText(&[_]u8{border_chars[1]});
                try self.moveCursor(@intCast(ctx.bounds.x + i), @intCast(ctx.bounds.y + ctx.bounds.height - 1));
                try self.terminal.writeText(&[_]u8{border_chars[1]});
            }

            // Draw vertical lines
            for (1..ctx.bounds.height - 1) |i| {
                try self.moveCursor(@intCast(ctx.bounds.x), @intCast(ctx.bounds.y + i));
                try self.terminal.writeText(&[_]u8{border_chars[3]});
                try self.moveCursor(@intCast(ctx.bounds.x + ctx.bounds.width - 1), @intCast(ctx.bounds.y + i));
                try self.terminal.writeText(&[_]u8{border_chars[3]});
            }
        }

        // Fill background if specified
        if (box_style.background) |bg| {
            try self.fillRect(ctx, bg);
        }
    }

    /// Draw a line
    pub fn drawLine(self: *Renderer, ctx: Render, from: Point, to: Point) !void {
        _ = ctx;
        // Simple line drawing implementation
        const dx = @abs(to.x - from.x);
        const dy = @abs(to.y - from.y);
        const sx: i16 = if (from.x < to.x) 1 else -1;
        const sy: i16 = if (from.y < to.y) 1 else -1;
        var err = dx - dy;

        var x = from.x;
        var y = from.y;

        while (true) {
            try self.moveCursor(@intCast(x), @intCast(y));
            try self.terminal.writeText("█");

            if (x == to.x and y == to.y) break;

            const e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                x += sx;
            }
            if (e2 < dx) {
                err += dx;
                y += sy;
            }
        }
    }

    /// Fill a rectangle
    pub fn fillRect(self: *Renderer, ctx: Render, color: Style.Color) !void {
        try self.applyStyleColor(color);

        for (0..ctx.bounds.height) |y| {
            try self.moveCursor(@intCast(ctx.bounds.x), @intCast(ctx.bounds.y + y));
            for (0..ctx.bounds.width) |_| {
                try self.terminal.writeText("█");
            }
        }

        try self.terminal.resetStyle();
    }

    /// Apply style color
    fn applyStyleColor(self: *Renderer, color: Style.Color) !void {
        switch (color) {
            .ansi => |c| try self.terminal.setForegroundColor(.{ .ansi = c }),
            .palette => |c| try self.terminal.setForegroundColor(.{ .palette = c }),
            .rgb => |rgb| try self.terminal.setForegroundColor(.{ .rgb = .{ .r = rgb.r, .g = rgb.g, .b = rgb.b } }),
        }
    }
};

/// Generate cache key for content (standalone function)
pub fn cacheKey(comptime fmt: []const u8, args: anytype) u64 {
    return Renderer.cacheKey(fmt, args);
}

/// Legacy type alias for backward compatibility
pub const AdaptiveRenderer = Renderer;

/// Convenience functions for backward compatibility
pub fn initAdaptive(allocator: std.mem.Allocator) !*AdaptiveRenderer {
    return Renderer.init(allocator);
}

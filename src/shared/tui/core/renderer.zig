//! TUI Renderer Abstraction Layer
//!
//! This provides a unified rendering interface that leverages the rich terminal capabilities
//! available in src/shared/term while maintaining compatibility with basic terminals through
//! progressive enhancement.

const std = @import("std");
const term_caps = @import("term_shared").caps;
const bounds_mod = @import("bounds.zig");

pub const Point = bounds_mod.Point;
pub const Bounds = bounds_mod.Bounds;
pub const TermCaps = term_caps.TermCaps;

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
    clip_region: ?Bounds = null,

    /// Create a context clipped to a smaller region
    pub fn clipped(self: Render, clip_bounds: Bounds) Render {
        const intersection = if (self.clip_region) |existing|
            existing.intersection(clip_bounds)
        else
            clip_bounds;

        return Render{
            .bounds = self.bounds.intersection(intersection),
            .style = self.style,
            .zIndex = self.zIndex,
            .clip_region = intersection,
        };
    }

    /// Offset the context by a certain amount
    pub fn offset(self: Render, dx: i32, dy: i32) Render {
        return Render{
            .bounds = self.bounds.offset(dx, dy),
            .style = self.style,
            .zIndex = self.zIndex,
            .clip_region = if (self.clip_region) |clip| clip.offset(dx, dy) else null,
        };
    }
};

/// Abstract renderer interface
pub const Renderer = struct {
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

        // Advanced features (may be no-ops on basic terminals)
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
        get_capabilities: *const fn (impl: *anyopaque) TermCaps,

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

    pub inline fn getCapabilities(self: *Self) TermCaps {
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
            .clip_region = ctx.clip_region,
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
            .clip_region = ctx.clip_region,
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

fn getLevelColor(level: NotificationLevel, caps: TermCaps) Style.Color {
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
pub fn createRenderer(allocator: std.mem.Allocator) !*Renderer {
    const caps = term_caps.detectCaps(allocator) catch term_caps.TermCaps{
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

    // Import renderer implementations
    const enhanced_renderer = @import("renderers/enhanced.zig");
    const basic_renderer = @import("renderers/basic.zig");

    // Choose renderer based on capabilities
    if (caps.supportsTruecolor or caps.supportsKittyGraphics or caps.supportsSixel) {
        return try enhanced_renderer.create(allocator, caps);
    } else {
        return try basic_renderer.create(allocator, caps);
    }
}

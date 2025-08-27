//! Rich TUI Renderer
//!
//! This renderer leverages rich terminal capabilities including:
//! - Truecolor support
//! - Graphics protocols (Kitty/Sixel)
//! - Hyperlinks (OSC 8)
//! - Clipboard integration (OSC 52)
//! - System notifications (OSC 9)
//! - Rich cursor control
//! - Proper multiplexer passthrough

const std = @import("std");
const renderer_mod = @import("../renderer.zig");
const term_mod = @import("term_shared");
const term_caps = term_mod.caps;
const components = @import("../../../components/mod.zig");

// Import terminal capabilities modules
const term_ansi_color = term_mod.ansi.color;
const term_ansi_enhanced_color = term_mod.ansi.color;
const term_ansi_cursor = term_mod.cursor;
const term_ansi_mode = term_mod.ansi.mode;
const term_ansi_screen = term_mod.ansi.screen;
const term_ansi_hyperlink = term_mod.ansi.hyperlink;
const term_ansi_clipboard = term_mod.ansi.clipboard;
const term_ansi_notification = term_mod.ansi.notification;
const term_ansi_graphics = term_mod.ansi.graphics;

const Renderer = renderer_mod.Renderer;
const Render = renderer_mod.Render;
const Style = renderer_mod.Style;
const BoxStyle = renderer_mod.BoxStyle;
const Image = renderer_mod.Image;
const Point = renderer_mod.Point;
const Bounds = renderer_mod.Bounds;
const TermCaps = renderer_mod.TermCaps;

/// Rich renderer implementation
pub const RichRenderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    caps: TermCaps,
    writer: std.fs.File.Writer,
    current_style: Style,
    cursor_visible: bool,
    current_hyperlink: ?[]const u8,
    frame_in_progress: bool,

    /// Buffer for building output sequences
    output_buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, caps: TermCaps) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .caps = caps,
            .writer = std.fs.File.stdout().writer(undefined),
            .current_style = Style{},
            .cursor_visible = true,
            .current_hyperlink = null,
            .frame_in_progress = false,
            .output_buffer = std.ArrayList(u8).init(allocator),
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.output_buffer.deinit();
        if (self.current_hyperlink) |url| {
            self.allocator.free(url);
        }
        self.allocator.destroy(self);
    }

    pub fn toRenderer(self: *Self) Renderer {
        return Renderer{
            .vtable = &vtable,
            .impl = self,
        };
    }

    const vtable = Renderer.VTable{
        .begin_frame = beginFrame,
        .end_frame = endFrame,
        .clear = clear,
        .draw_text = drawText,
        .measure_text = measureText,
        .draw_box = drawBox,
        .draw_line = drawLine,
        .fill_rect = fillRect,
        .draw_image = drawImage,
        .set_hyperlink = setHyperlink,
        .clear_hyperlink = clearHyperlink,
        .copy_to_clipboard = copyToClipboard,
        .send_notification = sendNotification,
        .set_cursor_position = setCursorPosition,
        .get_cursor_position = getCursorPosition,
        .show_cursor = showCursor,
        .get_capabilities = getCapabilities,
        .deinit = deinitVTable,
    };

    // VTable implementations
    fn beginFrame(impl: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.frame_in_progress = true;
        self.output_buffer.clearRetainingCapacity();

        // Enable alternative screen buffer if supported
        if (self.caps.supportsXtwinops) {
            try term_ansi_screen.enableAlternateScreen(self.writer, self.caps);
        }
    }

    fn endFrame(impl: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        if (!self.frame_in_progress) return;

        // Flush all buffered output
        if (self.output_buffer.items.len > 0) {
            try self.writer.writeAll(self.output_buffer.items);
            self.output_buffer.clearRetainingCapacity();
        }

        // Reset styles to clean state
        try term_ansi_color.resetStyle(self.writer, self.caps);

        self.frame_in_progress = false;
    }

    fn clear(impl: *anyopaque, bounds: Bounds) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Clear the specified region
        var y = bounds.y;
        while (y < bounds.y + @as(i32, @intCast(bounds.height))) : (y += 1) {
            try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(y), @intCast(bounds.x));

            // Clear the line within the bounds
            var x: u32 = 0;
            while (x < bounds.width) : (x += 1) {
                try self.output_buffer.append(' ');
            }
        }
    }

    fn drawText(impl: *anyopaque, ctx: Render, text: []const u8) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Apply styles if they've changed
        try self.applyStyle(ctx.style);

        // Position cursor
        try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(ctx.bounds.y), @intCast(ctx.bounds.x));

        // Handle text wrapping and clipping
        const lines = std.mem.split(u8, text, "\n");
        var current_y: i32 = ctx.bounds.y;
        var line_iter = lines;

        while (line_iter.next()) |line| {
            if (current_y >= ctx.bounds.y + @as(i32, @intCast(ctx.bounds.height))) break;

            // Clip line to bounds
            const max_width = if (ctx.clip_region) |clip|
                @min(ctx.bounds.width, @as(u32, @intCast(@max(0, clip.x + @as(i32, @intCast(clip.width)) - ctx.bounds.x))))
            else
                ctx.bounds.width;

            const clipped_line = if (line.len > max_width) line[0..max_width] else line;

            try self.output_buffer.appendSlice(clipped_line);
            current_y += 1;

            // Move to next line if not the last line
            if (line_iter.buffer.len > 0) {
                try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(current_y), @intCast(ctx.bounds.x));
            }
        }
    }

    fn measureText(impl: *anyopaque, text: []const u8, style: Style) anyerror!Point {
        _ = impl;
        _ = style;

        const lines = std.mem.split(u8, text, "\n");
        var max_width: u32 = 0;
        var height: u32 = 0;
        var line_iter = lines;

        while (line_iter.next()) |line| {
            // Use grapheme-aware width calculation
            const line_width = std.unicode.utf8CountCodepoints(line) catch line.len;
            max_width = @max(max_width, @as(u32, @intCast(line_width)));
            height += 1;
        }

        return Point{ .x = @intCast(max_width), .y = @intCast(height) };
    }

    fn drawBox(impl: *anyopaque, ctx: Render, box_style: BoxStyle) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Fill background if specified
        if (box_style.background) |bg_color| {
            try self.fillRectImpl(ctx, bg_color);
        }

        // Draw border if specified
        if (box_style.border) |border| {
            try self.drawBorder(ctx, border);
        }
    }

    fn drawLine(impl: *anyopaque, ctx: Render, from: Point, to: Point) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Apply line style
        try self.applyStyle(ctx.style);

        // Simple line drawing using Unicode box drawing characters
        const dx = to.x - from.x;
        const dy = to.y - from.y;

        if (dx == 0) {
            // Vertical line
            const start_y = @min(from.y, to.y);
            const end_y = @max(from.y, to.y);
            var y = start_y;
            while (y <= end_y) : (y += 1) {
                try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(y), @intCast(from.x));
                try self.output_buffer.appendSlice("│");
            }
        } else if (dy == 0) {
            // Horizontal line
            try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(from.y), @intCast(@min(from.x, to.x)));
            const length = @abs(dx);
            var i: i32 = 0;
            while (i < length) : (i += 1) {
                try self.output_buffer.appendSlice("─");
            }
        } else {
            // Diagonal line - use simple character approximation
            const steps = @max(@abs(dx), @abs(dy));
            var i: i32 = 0;
            while (i <= steps) : (i += 1) {
                const x = from.x + (dx * i) / steps;
                const y = from.y + (dy * i) / steps;
                try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(y), @intCast(x));
                try self.output_buffer.appendSlice("·");
            }
        }
    }

    fn fillRect(impl: *anyopaque, ctx: Render, color: Style.Color) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        try self.fillRectImpl(ctx, color);
    }

    fn drawImage(impl: *anyopaque, ctx: Render, image: Image) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        switch (image.format) {
            .kitty => {
                if (self.caps.supportsKittyGraphics) {
                    try self.drawKittyImage(ctx, image);
                } else {
                    try self.drawFallbackImage(ctx, image);
                }
            },
            .sixel => {
                if (self.caps.supportsSixel) {
                    try self.drawSixelImage(ctx, image);
                } else {
                    try self.drawFallbackImage(ctx, image);
                }
            },
            .ascii_art => {
                // Position cursor and draw ASCII art
                try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(ctx.bounds.y), @intCast(ctx.bounds.x));
                try self.output_buffer.appendSlice(image.data);
            },
        }
    }

    fn setHyperlink(impl: *anyopaque, url: []const u8) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (!self.caps.supportsHyperlinkOsc8) return;

        // Store current hyperlink for clearing later
        if (self.current_hyperlink) |old_url| {
            self.allocator.free(old_url);
        }
        self.current_hyperlink = try self.allocator.dupe(u8, url);

        try term_ansi_hyperlink.startHyperlinkWithAllocator(self.writer, self.allocator, self.caps, url, null);
    }

    fn clearHyperlink(impl: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (!self.caps.supportsHyperlinkOsc8) return;

        if (self.current_hyperlink) |url| {
            self.allocator.free(url);
            self.current_hyperlink = null;
        }

        try term_ansi_hyperlink.endHyperlink(self.writer, self.caps);
    }

    fn copyToClipboard(impl: *anyopaque, text: []const u8) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (!self.caps.supportsClipboardOsc52) return;

        try term_ansi_clipboard.setClipboard(self.writer, self.allocator, self.caps, text);
    }

    fn sendNotification(impl: *anyopaque, title: []const u8, body: []const u8) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (!self.caps.supportsNotifyOsc9) return;

        // Use system notification through components layer
        try components.SystemNotification.send(self.writer, self.allocator, self.caps, title, body);
    }

    fn setCursorPosition(impl: *anyopaque, pos: Point) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(pos.y), @intCast(pos.x));
    }

    fn getCursorPosition(impl: *anyopaque) anyerror!Point {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (!self.caps.supportsCursorPositionReport) {
            return error.Unsupported;
        }

        // This would normally involve sending a cursor position report request
        // and parsing the response, but for now we'll return a placeholder
        return Point{ .x = 0, .y = 0 };
    }

    fn showCursor(impl: *anyopaque, visible: bool) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (visible != self.cursor_visible) {
            if (visible) {
                try term_ansi_mode.showCursor(self.writer, self.caps);
            } else {
                try term_ansi_mode.hideCursor(self.writer, self.caps);
            }
            self.cursor_visible = visible;
        }
    }

    fn getCapabilities(impl: *anyopaque) TermCaps {
        const self: *Self = @ptrCast(@alignCast(impl));
        return self.caps;
    }

    fn deinitVTable(impl: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.deinit();
    }

    // Helper methods
    fn applyStyle(self: *Self, style: Style) !void {
        // Only update if style has changed
        if (std.meta.eql(style, self.current_style)) return;

        // Reset to clean state
        try term_ansi_color.resetStyle(self.writer, self.caps);

        // Apply foreground color
        if (style.fg_color) |fg| {
            try self.setColor(fg, true);
        }

        // Apply background color
        if (style.bg_color) |bg| {
            try self.setColor(bg, false);
        }

        // Apply text attributes
        if (style.bold) {
            try term_ansi_color.bold(self.writer, self.caps);
        }
        if (style.italic) {
            try term_ansi_color.italic(self.writer, self.caps);
        }
        if (style.underline) {
            try term_ansi_color.underline(self.writer, self.caps);
        }
        if (style.strikethrough) {
            try term_ansi_color.strikethrough(self.writer, self.caps);
        }

        self.current_style = style;
    }

    fn setColor(self: *Self, color: Style.Color, is_foreground: bool) !void {
        switch (color) {
            .ansi => |ansi_color| {
                if (is_foreground) {
                    try term_ansi_color.setForegroundColor(self.writer, self.caps, ansi_color);
                } else {
                    try term_ansi_color.setBackgroundColor(self.writer, self.caps, ansi_color);
                }
            },
            .palette => |palette_color| {
                if (is_foreground) {
                    try term_ansi_color.setForegroundColor256(self.writer, self.caps, palette_color);
                } else {
                    try term_ansi_color.setBackgroundColor256(self.writer, self.caps, palette_color);
                }
            },
            .rgb => |rgb| {
                if (self.caps.supportsTruecolor) {
                    if (is_foreground) {
                        try term_ansi_enhanced_color.setForegroundColorRgb(self.writer, self.allocator, self.caps, rgb.r, rgb.g, rgb.b);
                    } else {
                        try term_ansi_enhanced_color.setBackgroundColorRgb(self.writer, self.allocator, self.caps, rgb.r, rgb.g, rgb.b);
                    }
                } else {
                    // Fallback to closest 256-color palette color
                    const palette_color = rgbTo256Color(rgb);
                    if (is_foreground) {
                        try term_ansi_color.setForegroundColor256(self.writer, self.caps, palette_color);
                    } else {
                        try term_ansi_color.setBackgroundColor256(self.writer, self.caps, palette_color);
                    }
                }
            },
        }
    }

    fn fillRectImpl(self: *Self, ctx: Render, color: Style.Color) !void {
        const fill_style = Style{ .bg_color = color };
        try self.applyStyle(fill_style);

        var y = ctx.bounds.y;
        while (y < ctx.bounds.y + @as(i32, @intCast(ctx.bounds.height))) : (y += 1) {
            try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(y), @intCast(ctx.bounds.x));

            var x: u32 = 0;
            while (x < ctx.bounds.width) : (x += 1) {
                try self.output_buffer.append(' ');
            }
        }
    }

    fn drawBorder(self: *Self, ctx: Render, border: BoxStyle.BorderStyle) !void {
        const border_chars = getBorderChars(border.style);

        if (border.color) |color| {
            const border_style = Style{ .fg_color = color };
            try self.applyStyle(border_style);
        }

        const bounds = ctx.bounds;

        // Top border
        try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(bounds.y), @intCast(bounds.x));
        try self.output_buffer.appendSlice(border_chars.top_left);
        var x: u32 = 1;
        while (x < bounds.width - 1) : (x += 1) {
            try self.output_buffer.appendSlice(border_chars.horizontal);
        }
        if (bounds.width > 1) {
            try self.output_buffer.appendSlice(border_chars.top_right);
        }

        // Side borders
        var y: u32 = 1;
        while (y < bounds.height - 1) : (y += 1) {
            try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(bounds.y + @as(i32, @intCast(y))), @intCast(bounds.x));
            try self.output_buffer.appendSlice(border_chars.vertical);

            if (bounds.width > 1) {
                try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(bounds.y + @as(i32, @intCast(y))), @intCast(bounds.x + @as(i32, @intCast(bounds.width - 1))));
                try self.output_buffer.appendSlice(border_chars.vertical);
            }
        }

        // Bottom border
        if (bounds.height > 1) {
            try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(bounds.y + @as(i32, @intCast(bounds.height - 1))), @intCast(bounds.x));
            try self.output_buffer.appendSlice(border_chars.bottom_left);
            x = 1;
            while (x < bounds.width - 1) : (x += 1) {
                try self.output_buffer.appendSlice(border_chars.horizontal);
            }
            if (bounds.width > 1) {
                try self.output_buffer.appendSlice(border_chars.bottom_right);
            }
        }
    }

    fn drawKittyImage(self: *Self, ctx: Render, image: Image) !void {
        // Position cursor
        try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(ctx.bounds.y), @intCast(ctx.bounds.x));

        // Draw using Kitty graphics protocol
        try term_ansi_graphics.transmitKittyImage(
            self.writer,
            self.allocator,
            self.caps,
            image.data,
            image.width,
            image.height,
            .png, // Assume PNG for now
        );
    }

    fn drawSixelImage(self: *Self, ctx: Render, image: Image) !void {
        // Position cursor
        try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(ctx.bounds.y), @intCast(ctx.bounds.x));

        // Sixel data should be pre-encoded
        try self.output_buffer.appendSlice(image.data);
    }

    fn drawFallbackImage(self: *Self, ctx: Render, image: Image) !void {
        // Fallback to ASCII representation
        _ = image;
        try term_ansi_cursor.setCursor(self.writer, self.caps, @intCast(ctx.bounds.y), @intCast(ctx.bounds.x));
        try self.output_buffer.appendSlice("[IMAGE]");
    }
};

const BorderChars = struct {
    top_left: []const u8,
    top_right: []const u8,
    bottom_left: []const u8,
    bottom_right: []const u8,
    horizontal: []const u8,
    vertical: []const u8,
};

fn getBorderChars(style: BoxStyle.BorderStyle.LineStyle) BorderChars {
    return switch (style) {
        .single => BorderChars{
            .top_left = "┌",
            .top_right = "┐",
            .bottom_left = "└",
            .bottom_right = "┘",
            .horizontal = "─",
            .vertical = "│",
        },
        .double => BorderChars{
            .top_left = "╔",
            .top_right = "╗",
            .bottom_left = "╚",
            .bottom_right = "╝",
            .horizontal = "═",
            .vertical = "║",
        },
        .rounded => BorderChars{
            .top_left = "╭",
            .top_right = "╮",
            .bottom_left = "╰",
            .bottom_right = "╯",
            .horizontal = "─",
            .vertical = "│",
        },
        .thick => BorderChars{
            .top_left = "┏",
            .top_right = "┓",
            .bottom_left = "┗",
            .bottom_right = "┛",
            .horizontal = "━",
            .vertical = "┃",
        },
        .dotted => BorderChars{
            .top_left = "┌",
            .top_right = "┐",
            .bottom_left = "└",
            .bottom_right = "┘",
            .horizontal = "┄",
            .vertical = "┆",
        },
    };
}

/// Convert RGB color to closest 256-color palette entry
fn rgbTo256Color(rgb: Style.Color.RGB) u8 {
    // Simple approximation - in reality you'd want a proper color distance calculation
    if (rgb.r == rgb.g and rgb.g == rgb.b) {
        // Grayscale
        const gray_level = rgb.r / 10;
        return @as(u8, @intCast(232 + @min(23, gray_level)));
    } else {
        // Color cube
        const r = rgb.r / 43; // 6 levels (0-5)
        const g = rgb.g / 43;
        const b = rgb.b / 43;
        return @as(u8, @intCast(16 + 36 * r + 6 * g + b));
    }
}

/// Factory function to create rich renderer
pub fn create(allocator: std.mem.Allocator, caps: TermCaps) !*Renderer {
    const rich = try RichRenderer.init(allocator, caps);
    const renderer = try allocator.create(Renderer);
    renderer.* = rich.toRenderer();
    return renderer;
}

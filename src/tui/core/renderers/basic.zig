//! Basic TUI Renderer
//!
//! This renderer provides fallback functionality for terminals with limited capabilities.
//! It uses only basic ANSI escape sequences and simple text output.

const std = @import("std");
const renderer_mod = @import("../renderer.zig");

const Renderer = renderer_mod.Renderer;
const RenderContext = renderer_mod.RenderContext;
const Style = renderer_mod.Style;
const BoxStyle = renderer_mod.BoxStyle;
const Image = renderer_mod.Image;
const Point = renderer_mod.Point;
const Bounds = renderer_mod.Bounds;
const TermCaps = renderer_mod.TermCaps;

/// Basic renderer implementation for limited terminals
pub const BasicRenderer = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    caps: TermCaps,
    writer: std.fs.File.Writer,
    current_style: Style,
    cursor_visible: bool,
    frame_in_progress: bool,
    
    pub fn init(allocator: std.mem.Allocator, caps: TermCaps) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .caps = caps,
            .writer = std.io.getStdOut().writer(),
            .current_style = Style{},
            .cursor_visible = true,
            .frame_in_progress = false,
        };
        
        return self;
    }
    
    pub fn deinit(self: *Self) void {
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
    }
    
    fn endFrame(impl: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        if (!self.frame_in_progress) return;
        
        // Reset styles
        try self.writer.writeAll("\x1b[0m");
        
        self.frame_in_progress = false;
    }
    
    fn clear(impl: *anyopaque, bounds: Bounds) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        
        // Clear the specified region with simple spaces
        var y = bounds.y;
        while (y < bounds.y + @as(i32, @intCast(bounds.height))) : (y += 1) {
            try self.setCursor(@intCast(y), @intCast(bounds.x));
            
            var x: u32 = 0;
            while (x < bounds.width) : (x += 1) {
                try self.writer.writeByte(' ');
            }
        }
    }
    
    fn drawText(impl: *anyopaque, ctx: RenderContext, text: []const u8) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        
        // Apply basic styles
        try self.applyBasicStyle(ctx.style);
        
        // Position cursor
        try self.setCursor(@intCast(ctx.bounds.y), @intCast(ctx.bounds.x));
        
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
            
            try self.writer.writeAll(clipped_line);
            current_y += 1;
            
            // Move to next line if not the last line
            if (line_iter.buffer.len > 0) {
                try self.setCursor(@intCast(current_y), @intCast(ctx.bounds.x));
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
            // Simple byte length approximation
            max_width = @max(max_width, @as(u32, @intCast(line.len)));
            height += 1;
        }
        
        return Point{ .x = @as(i32, @intCast(max_width)), .y = @as(i32, @intCast(height)) };
    }
    
    fn drawBox(impl: *anyopaque, ctx: RenderContext, box_style: BoxStyle) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        
        // Fill background with spaces if specified
        if (box_style.background) |_| {
            try self.fillRectImpl(ctx);
        }
        
        // Draw simple ASCII border if specified
        if (box_style.border) |border| {
            try self.drawBasicBorder(ctx, border);
        }
    }
    
    fn drawLine(impl: *anyopaque, ctx: RenderContext, from: Point, to: Point) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        
        // Apply line style
        try self.applyBasicStyle(ctx.style);
        
        // Simple line drawing using ASCII characters
        const dx = to.x - from.x;
        const dy = to.y - from.y;
        
        if (dx == 0) {
            // Vertical line
            const start_y = @min(from.y, to.y);
            const end_y = @max(from.y, to.y);
            var y = start_y;
            while (y <= end_y) : (y += 1) {
                try self.setCursor(@intCast(y), @intCast(from.x));
                try self.writer.writeByte('|');
            }
        } else if (dy == 0) {
            // Horizontal line
            try self.setCursor(@intCast(from.y), @intCast(@min(from.x, to.x)));
            const length = @abs(dx);
            var i: i32 = 0;
            while (i < length) : (i += 1) {
                try self.writer.writeByte('-');
            }
        } else {
            // Diagonal line - use simple character approximation
            const steps = @max(@abs(dx), @abs(dy));
            var i: i32 = 0;
            while (i <= steps) : (i += 1) {
                const x = from.x + (dx * i) / steps;
                const y = from.y + (dy * i) / steps;
                try self.setCursor(@intCast(y), @intCast(x));
                try self.writer.writeByte('*');
            }
        }
    }
    
    fn fillRect(impl: *anyopaque, ctx: RenderContext, color: Style.Color) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = color; // Can't use color in basic mode
        try self.fillRectImpl(ctx);
    }
    
    fn drawImage(impl: *anyopaque, ctx: RenderContext, image: Image) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        
        switch (image.format) {
            .ascii_art => {
                // Position cursor and draw ASCII art
                try self.setCursor(@intCast(ctx.bounds.y), @intCast(ctx.bounds.x));
                try self.writer.writeAll(image.data);
            },
            .kitty, .sixel => {
                // Fallback to placeholder text
                try self.setCursor(@intCast(ctx.bounds.y), @intCast(ctx.bounds.x));
                try self.writer.writeAll("[IMAGE]");
            },
        }
    }
    
    fn setHyperlink(impl: *anyopaque, url: []const u8) anyerror!void {
        // Not supported in basic mode
        _ = impl;
        _ = url;
    }
    
    fn clearHyperlink(impl: *anyopaque) anyerror!void {
        // Not supported in basic mode
        _ = impl;
    }
    
    fn copyToClipboard(impl: *anyopaque, text: []const u8) anyerror!void {
        // Not supported in basic mode - could print a message
        _ = impl;
        _ = text;
    }
    
    fn sendNotification(impl: *anyopaque, title: []const u8, body: []const u8) anyerror!void {
        // Not supported in basic mode - could use terminal bell
        const self: *Self = @ptrCast(@alignCast(impl));
        _ = title;
        _ = body;
        
        // Ring the terminal bell as a basic notification
        try self.writer.writeByte(0x07);
    }
    
    fn setCursorPosition(impl: *anyopaque, pos: Point) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        try self.setCursor(@intCast(pos.y), @intCast(pos.x));
    }
    
    fn getCursorPosition(impl: *anyopaque) anyerror!Point {
        // Not supported in basic mode
        _ = impl;
        return error.Unsupported;
    }
    
    fn showCursor(impl: *anyopaque, visible: bool) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        
        if (visible != self.cursor_visible) {
            if (visible) {
                try self.writer.writeAll("\x1b[?25h");
            } else {
                try self.writer.writeAll("\x1b[?25l");
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
    fn setCursor(self: *Self, row: u32, col: u32) !void {
        try self.writer.print("\x1b[{d};{d}H", .{ row + 1, col + 1 });
    }
    
    fn applyBasicStyle(self: *Self, style: Style) !void {
        // Only update if style has changed
        if (std.meta.eql(style, self.current_style)) return;
        
        // Reset to clean state
        try self.writer.writeAll("\x1b[0m");
        
        // Apply basic 16-color ANSI colors only
        if (style.fg_color) |fg| {
            try self.setBasicColor(fg, true);
        }
        
        if (style.bg_color) |bg| {
            try self.setBasicColor(bg, false);
        }
        
        // Apply text attributes
        if (style.bold) {
            try self.writer.writeAll("\x1b[1m");
        }
        if (style.italic) {
            try self.writer.writeAll("\x1b[3m");
        }
        if (style.underline) {
            try self.writer.writeAll("\x1b[4m");
        }
        if (style.strikethrough) {
            try self.writer.writeAll("\x1b[9m");
        }
        
        self.current_style = style;
    }
    
    fn setBasicColor(self: *Self, color: Style.Color, is_foreground: bool) !void {
        const ansi_color: u8 = switch (color) {
            .ansi => |ansi| @min(ansi, 15), // Clamp to basic 16 colors
            .palette => |palette| @min(palette, 15), // Clamp to basic 16 colors
            .rgb => |rgb| self.rgbToBasicColor(rgb), // Convert to nearest basic color
        };
        
        if (is_foreground) {
            if (ansi_color < 8) {
                try self.writer.print("\x1b[{d}m", .{30 + ansi_color});
            } else {
                try self.writer.print("\x1b[{d}m", .{90 + (ansi_color - 8)});
            }
        } else {
            if (ansi_color < 8) {
                try self.writer.print("\x1b[{d}m", .{40 + ansi_color});
            } else {
                try self.writer.print("\x1b[{d}m", .{100 + (ansi_color - 8)});
            }
        }
    }
    
    fn rgbToBasicColor(self: *Self, rgb: Style.Color.RGB) u8 {
        _ = self;
        
        // Simple approximation to nearest basic ANSI color
        const r_thresh: u8 = 128;
        const g_thresh: u8 = 128;
        const b_thresh: u8 = 128;
        
        var color: u8 = 0;
        if (rgb.r > r_thresh) color |= 1;
        if (rgb.g > g_thresh) color |= 2;
        if (rgb.b > b_thresh) color |= 4;
        
        // Add bright bit if colors are very bright
        if (rgb.r > 192 or rgb.g > 192 or rgb.b > 192) {
            color |= 8;
        }
        
        return color;
    }
    
    fn fillRectImpl(self: *Self, ctx: RenderContext) !void {
        var y = ctx.bounds.y;
        while (y < ctx.bounds.y + @as(i32, @intCast(ctx.bounds.height))) : (y += 1) {
            try self.setCursor(@intCast(y), @intCast(ctx.bounds.x));
            
            var x: u32 = 0;
            while (x < ctx.bounds.width) : (x += 1) {
                try self.writer.writeByte(' ');
            }
        }
    }
    
    fn drawBasicBorder(self: *Self, ctx: RenderContext, border: BoxStyle.BorderStyle) !void {
        // Use simple ASCII characters for borders
        _ = border.style; // All styles look the same in basic mode
        _ = border.color; // Can't use color in basic mode
        
        const bounds = ctx.bounds;
        
        // Top border
        try self.setCursor(@intCast(bounds.y), @intCast(bounds.x));
        try self.writer.writeByte('+');
        var x: u32 = 1;
        while (x < bounds.width - 1) : (x += 1) {
            try self.writer.writeByte('-');
        }
        if (bounds.width > 1) {
            try self.writer.writeByte('+');
        }
        
        // Side borders
        var y: u32 = 1;
        while (y < bounds.height - 1) : (y += 1) {
            try self.setCursor(@intCast(bounds.y + @as(i32, @intCast(y))), @intCast(bounds.x));
            try self.writer.writeByte('|');
            
            if (bounds.width > 1) {
                try self.setCursor(@intCast(bounds.y + @as(i32, @intCast(y))), @intCast(bounds.x + @as(i32, @intCast(bounds.width - 1))));
                try self.writer.writeByte('|');
            }
        }
        
        // Bottom border
        if (bounds.height > 1) {
            try self.setCursor(@intCast(bounds.y + @as(i32, @intCast(bounds.height - 1))), @intCast(bounds.x));
            try self.writer.writeByte('+');
            x = 1;
            while (x < bounds.width - 1) : (x += 1) {
                try self.writer.writeByte('-');
            }
            if (bounds.width > 1) {
                try self.writer.writeByte('+');
            }
        }
    }
};

/// Factory function to create basic renderer
pub fn create(allocator: std.mem.Allocator, caps: TermCaps) !*Renderer {
    const basic = try BasicRenderer.init(allocator, caps);
    const renderer = try allocator.create(Renderer);
    renderer.* = basic.toRenderer();
    return renderer;
}
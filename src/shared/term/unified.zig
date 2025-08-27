//! Unified Terminal Interface
//!
//! This module provides a high-level, unified interface to all terminal capabilities,
//! bridging the gap between CLI and TUI components while enabling progressive enhancement
//! based on detected terminal features.

const std = @import("std");
const caps_mod = @import("caps.zig");
const ansi_color = @import("ansi/color.zig");
const ansi_cursor = @import("ansi/cursor.zig");
const ansi_graphics = @import("ansi/graphics.zig");
const ansi_clipboard = @import("ansi/clipboard.zig");
const ansi_hyperlinks = @import("ansi/hyperlink.zig");
const ansi_notifications = @import("ansi/notification.zig");

pub const TermCaps = caps_mod.TermCaps;

/// Unified color representation that adapts to terminal capabilities
pub const Color = union(enum) {
    ansi: u8, // 0-15 ANSI colors
    palette: u8, // 0-255 palette colors
    rgb: RGB, // RGB truecolor

    pub const RGB = struct {
        r: u8,
        g: u8,
        b: u8,
    };

    /// Get the best color representation for the given terminal capabilities
    pub fn adapt(self: Color, caps: TermCaps) Color {
        return switch (self) {
            .rgb => |rgb| if (caps.supportsTruecolor) self else .{ .palette = rgbToPalette(rgb) },
            .palette => |p| if (caps.supportsTruecolor or p <= 15) self else .{ .ansi = p % 16 },
            .ansi => self,
        };
    }

    fn rgbToPalette(rgb: RGB) u8 {
        // Convert RGB to closest 256-color palette entry
        if (rgb.r == rgb.g and rgb.g == rgb.b) {
            // Grayscale
            if (rgb.r < 8) return 16;
            if (rgb.r > 248) return 231;
            return @as(u8, @intFromFloat(232 + (@as(f32, @floatFromInt(rgb.r)) - 8) / 247 * 23));
        } else {
            // Color cube
            const r = @min(5, @as(u8, @intFromFloat(@as(f32, @floatFromInt(rgb.r)) / 255 * 5)));
            const g = @min(5, @as(u8, @intFromFloat(@as(f32, @floatFromInt(rgb.g)) / 255 * 5)));
            const b = @min(5, @as(u8, @intFromFloat(@as(f32, @floatFromInt(rgb.b)) / 255 * 5)));
            return 16 + (36 * r) + (6 * g) + b;
        }
    }
};

/// Text styling options
pub const Style = struct {
    fg_color: ?Color = null,
    bg_color: ?Color = null,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    strikethrough: bool = false,

    /// Apply this style to the output
    pub fn apply(self: Style, writer: anytype, caps: TermCaps) !void {
        if (self.bold) try writer.writeAll("\x1b[1m");
        if (self.italic) try writer.writeAll("\x1b[3m");
        if (self.underline) try writer.writeAll("\x1b[4m");
        if (self.strikethrough) try writer.writeAll("\x1b[9m");

        if (self.fg_color) |color| {
            const adapted = color.adapt(caps);
            switch (adapted) {
                .rgb => |rgb| if (caps.supportsTruecolor) {
                    try ansi_color.setForegroundRgb(writer, caps, rgb.r, rgb.g, rgb.b);
                },
                .palette => |p| try ansi_color.setForeground256(writer, caps, p),
                .ansi => |a| try ansi_color.setForeground16(writer, caps, a),
            }
        }

        if (self.bg_color) |color| {
            const adapted = color.adapt(caps);
            switch (adapted) {
                .rgb => |rgb| if (caps.supportsTruecolor) {
                    try ansi_color.setBackgroundRgb(writer, caps, rgb.r, rgb.g, rgb.b);
                },
                .palette => |p| try ansi_color.setBackground256(writer, caps, p),
                .ansi => |a| try ansi_color.setBackground16(writer, caps, a),
            }
        }
    }

    /// Reset all styling
    pub fn reset(writer: anytype, caps: TermCaps) !void {
        try ansi_color.resetStyle(writer, caps);
    }
};

/// Image data for advanced graphics rendering
pub const Image = struct {
    data: []const u8,
    width: u32,
    height: u32,
    format: Format,

    pub const Format = enum {
        png,
        jpeg,
        gif,
        rgb24,
        rgba32,
    };
};

/// Point in 2D space
pub const Point = struct {
    x: i32,
    y: i32,
};

/// Rectangle bounds
pub const Rect = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
};

/// Notification severity levels
pub const NotificationLevel = enum {
    info,
    success,
    warning,
    @"error",
    debug,
};

/// Main terminal interface that provides unified access to all capabilities
pub const Terminal = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    caps: TermCaps,
    writer: *std.Io.Writer,
    stdout_buffer: [4096]u8,
    buffer: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator) !Self {
        const caps = caps_mod.detectCaps(allocator) catch caps_mod.TermCaps{
            .supportsTruecolor = false,
            .supportsKittyGraphics = false,
            .supportsSixel = false,
            .supportsHyperlinkOsc8 = false,
            .supportsClipboardOsc52 = false,
            .supportsNotifyOsc9 = false,
            .supportsTitleOsc012 = false,
            .supportsWorkingDirOsc7 = false,
            .supportsFinalTermOsc133 = false,
            .supportsITerm2Osc1337 = false,
            .supportsColorOsc10_12 = false,
            .supportsKittyKeyboard = false,
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

        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const writer = &stdout_writer.interface;

        return Self{
            .allocator = allocator,
            .caps = caps,
            .writer = writer,
            .stdout_buffer = stdout_buffer,
            .buffer = std.ArrayListUnmanaged(u8){},
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Get terminal capabilities
    pub fn getCapabilities(self: *Self) TermCaps {
        return self.caps;
    }

    /// Clear the screen
    pub fn clear(self: *Self) !void {
        try self.writer.writeAll("\x1b[2J\x1b[H");
        try self.flush();
    }

    /// Clear current line
    pub fn clearLine(self: *Self) !void {
        try self.writer.writeAll("\x1b[2K");
        try self.flush();
    }

    /// Move cursor to position
    pub fn moveTo(self: *Self, x: i32, y: i32) !void {
        try ansi_cursor.gotoXY(self.writer, self.caps, @as(u16, @intCast(x)), @as(u16, @intCast(y)));
    }

    /// Hide/show cursor
    pub fn showCursor(self: *Self, visible: bool) !void {
        if (visible) {
            try ansi_cursor.showCursor(self.writer, self.caps);
        } else {
            try ansi_cursor.hideCursor(self.writer, self.caps);
        }
    }

    /// Print text with optional styling
    pub fn print(self: *Self, text: []const u8, style: ?Style) !void {
        if (style) |s| {
            try s.apply(self.writer, self.caps);
            try self.writer.writeAll(text);
            try Style.reset(self.writer, self.caps);
        } else {
            try self.writer.writeAll(text);
        }
        try self.flush();
    }

    /// Print formatted text with optional styling
    pub fn printf(self: *Self, comptime fmt: []const u8, args: anytype, style: ?Style) !void {
        self.buffer.clearRetainingCapacity();
        try std.fmt.format(self.buffer.writer(self.allocator), fmt, args);
        try self.print(self.buffer.items, style);
    }

    /// Create a hyperlink (with fallback to plain text)
    pub fn hyperlink(self: *Self, url: []const u8, text: []const u8, style: ?Style) !void {
        if (self.caps.supportsHyperlinkOsc8) {
            try ansi_hyperlinks.startHyperlink(self.writer, self.caps, url, "");
            try self.print(text, style);
            try ansi_hyperlinks.endHyperlink(self.writer, self.caps);
        } else {
            try self.print(text, style);
            if (style) |s| try s.apply(self.writer, self.caps);
            try self.writer.print(" ({s})", .{url});
            if (style != null) try Style.reset(self.writer, self.caps);
        }
    }

    /// Copy text to clipboard (with capability detection)
    pub fn copyToClipboard(self: *Self, text: []const u8) !void {
        if (self.caps.supportsClipboardOsc52) {
            try ansi_clipboard.setClipboard(self.writer, self.caps, text);
        } else {
            // Fallback: just notify user
            try self.notification(.info, "Copy", "Text ready to copy manually");
        }
    }

    /// Send system notification (with fallback to terminal output)
    pub fn notification(self: *Self, level: NotificationLevel, title: []const u8, message: []const u8) !void {
        if (self.caps.supportsNotifyOsc9) {
            try ansi_notifications.sendNotification(self.writer, self.caps, message);
        } else {
            // Fallback to styled terminal output
            const icon = switch (level) {
                .info => "ℹ",
                .success => "✓",
                .warning => "⚠",
                .@"error" => "✗",
                .debug => "🐛",
            };

            const color = switch (level) {
                .info => Color{ .rgb = .{ .r = 100, .g = 149, .b = 237 } },
                .success => Color{ .rgb = .{ .r = 50, .g = 205, .b = 50 } },
                .warning => Color{ .rgb = .{ .r = 255, .g = 215, .b = 0 } },
                .@"error" => Color{ .rgb = .{ .r = 220, .g = 20, .b = 60 } },
                .debug => Color{ .rgb = .{ .r = 138, .g = 43, .b = 226 } },
            };

            const style = Style{ .fg_color = color, .bold = true };
            try self.printf("{s} {s}: {s}\n", .{ icon, title, message }, style);
        }
    }

    /// Render an image using best available protocol
    pub fn renderImage(self: *Self, image: Image, pos: Point, max_size: ?Point) !void {
        const display_width = if (max_size) |ms| @min(ms.x, @as(i32, @intCast(image.width))) else @as(i32, @intCast(image.width));
        const display_height = if (max_size) |ms| @min(ms.y, @as(i32, @intCast(image.height))) else @as(i32, @intCast(image.height));

        // Move to position
        try self.moveTo(pos.x, pos.y);

        if (self.caps.supportsKittyGraphics) {
            try self.renderImageKitty(image, display_width, display_height);
        } else if (self.caps.supportsSixel) {
            try self.renderImageSixel(image, display_width, display_height);
        } else {
            try self.renderImageAscii(image, display_width, display_height);
        }
    }

    fn renderImageKitty(self: *Self, image: Image, width: i32, height: i32) !void {
        // Use Kitty Graphics Protocol
        const format_code = switch (image.format) {
            .png => "f=100",
            .jpeg => "f=100", // Let Kitty auto-detect
            .gif => "f=100",
            .rgb24 => "f=24",
            .rgba32 => "f=32",
        };

        const encoded = try self.allocator.alloc(u8, std.base64.Encoder.calcSize(image.data.len));
        defer self.allocator.free(encoded);
        _ = std.base64.standard.Encoder.encode(encoded, image.data);

        try self.writer.print("\x1b_G{s},s={d},v={d};{s}\x1b\\", .{ format_code, width, height, encoded });
    }

    fn renderImageSixel(self: *Self, image: Image, width: i32, height: i32) !void {
        // Sixel graphics protocol implementation
        // Format: ESC P parameters q "image_data" ESC \

        const allocator = std.heap.page_allocator; // Use a more appropriate allocator in production

        // Start Sixel sequence: ESC P 0;0;0 q (0;0;0 = aspect ratio)
        try self.writer.writeAll("\x1bP0;0;0q");

        switch (image.format) {
            .rgb24 => try self.encodeSixelRgb24(allocator, image, @intCast(width), @intCast(height)),
            .rgba32 => try self.encodeSixelRgba32(allocator, image, @intCast(width), @intCast(height)),
            else => {
                // For other formats, render as ASCII art fallback
                try self.writer.writeAll("\x1b\\");
                return self.renderImageAscii(image, width, height);
            },
        }

        // End Sixel sequence
        try self.writer.writeAll("\x1b\\");
    }

    /// Encode RGB24 image data as Sixel
    fn encodeSixelRgb24(self: *Self, allocator: std.mem.Allocator, image: Image, target_width: u32, target_height: u32) !void {
        const src_width = image.width;
        const src_height = image.height;
        const rgb_data = image.data;

        if (rgb_data.len != src_width * src_height * 3) return error.InvalidImageData;

        // Simple color quantization to 16 colors for Sixel
        const palette_size = 16;
        var palette: [palette_size][3]u8 = undefined;
        var color_count: u8 = 0;

        // Initialize basic color palette (simplified)
        const basic_colors = [_][3]u8{
            .{ 0, 0, 0 }, // Black
            .{ 255, 0, 0 }, // Red
            .{ 0, 255, 0 }, // Green
            .{ 255, 255, 0 }, // Yellow
            .{ 0, 0, 255 }, // Blue
            .{ 255, 0, 255 }, // Magenta
            .{ 0, 255, 255 }, // Cyan
            .{ 255, 255, 255 }, // White
            .{ 128, 128, 128 }, // Gray
            .{ 128, 0, 0 }, // Dark red
            .{ 0, 128, 0 }, // Dark green
            .{ 128, 128, 0 }, // Dark yellow
            .{ 0, 0, 128 }, // Dark blue
            .{ 128, 0, 128 }, // Dark magenta
            .{ 0, 128, 128 }, // Dark cyan
            .{ 192, 192, 192 }, // Light gray
        };

        // Set up palette
        for (basic_colors, 0..) |color, i| {
            palette[i] = color;
            // Define color in Sixel format: #Pc;2;Pr;Pg;Pb
            try self.writer.print("#{d};2;{d};{d};{d}", .{ i, color[0] * 100 / 255, color[1] * 100 / 255, color[2] * 100 / 255 });
        }
        color_count = basic_colors.len;

        // Convert image to indexed color and render
        try self.encodeSixelIndexed(allocator, rgb_data, src_width, src_height, target_width, target_height, &palette, color_count);
    }

    /// Encode RGBA32 image data as Sixel
    fn encodeSixelRgba32(self: *Self, allocator: std.mem.Allocator, image: Image, target_width: u32, target_height: u32) !void {
        const src_width = image.width;
        const src_height = image.height;
        const rgba_data = image.data;

        if (rgba_data.len != src_width * src_height * 4) return error.InvalidImageData;

        // Convert RGBA to RGB (ignore alpha for now)
        const rgb_data = try allocator.alloc(u8, src_width * src_height * 3);
        defer allocator.free(rgb_data);

        var i: usize = 0;
        var j: usize = 0;
        while (i < rgba_data.len) : (i += 4) {
            rgb_data[j] = rgba_data[i]; // R
            rgb_data[j + 1] = rgba_data[i + 1]; // G
            rgb_data[j + 2] = rgba_data[i + 2]; // B
            j += 3;
        }

        // Create temporary RGB image and encode
        const rgb_image = Image{
            .data = rgb_data,
            .width = src_width,
            .height = src_height,
            .format = .rgb24,
        };

        try self.encodeSixelRgb24(allocator, rgb_image, target_width, target_height);
    }

    /// Core Sixel encoding for indexed color data
    fn encodeSixelIndexed(self: *Self, allocator: std.mem.Allocator, rgb_data: []const u8, src_width: u32, src_height: u32, target_width: u32, target_height: u32, palette: *const [16][3]u8, color_count: u8) !void {
        _ = target_width;
        _ = target_height;

        // Quantize image to palette colors
        const indexed_data = try allocator.alloc(u8, src_width * src_height);
        defer allocator.free(indexed_data);

        for (0..src_height) |y| {
            for (0..src_width) |x| {
                const pixel_idx = (y * src_width + x) * 3;
                const r = rgb_data[pixel_idx];
                const g = rgb_data[pixel_idx + 1];
                const b = rgb_data[pixel_idx + 2];

                // Find closest palette color
                var best_color: u8 = 0;
                var min_distance: u32 = std.math.maxInt(u32);

                for (0..color_count) |i| {
                    const dr = @as(i32, r) - @as(i32, palette[i][0]);
                    const dg = @as(i32, g) - @as(i32, palette[i][1]);
                    const db = @as(i32, b) - @as(i32, palette[i][2]);
                    const distance = @as(u32, @intCast(dr * dr + dg * dg + db * db));

                    if (distance < min_distance) {
                        min_distance = distance;
                        best_color = @intCast(i);
                    }
                }

                indexed_data[y * src_width + x] = best_color;
            }
        }

        // Encode Sixel data in bands of 6 pixels height
        const band_height = 6;
        const num_bands = (src_height + band_height - 1) / band_height;

        for (0..num_bands) |band| {
            const band_start = band * band_height;
            const band_end = @min(band_start + band_height, src_height);

            // For each color in the band
            for (0..color_count) |color| {
                var has_pixels = false;
                var sixel_line = try std.ArrayList(u8).initCapacity(allocator, src_width + 10);
                defer sixel_line.deinit();

                // Color selection
                try sixel_line.appendSlice(try std.fmt.allocPrint(allocator, "#{d}", .{color}));

                for (0..src_width) |x| {
                    var sixel_char: u8 = 0;

                    // Build sixel character from 6 vertical pixels
                    for (band_start..band_end) |y| {
                        const bit_pos = y - band_start;
                        if (indexed_data[y * src_width + x] == color) {
                            sixel_char |= @as(u8, 1) << @intCast(bit_pos);
                            has_pixels = true;
                        }
                    }

                    // Convert to Sixel character (add 63 to make printable)
                    try sixel_line.append(sixel_char + 63);
                }

                if (has_pixels) {
                    try self.writer.writeAll(sixel_line.items);
                    if (allocator.alloc(u8, 0)) |s| allocator.free(s);
                }
            }

            // New line for next band
            if (band < num_bands - 1) {
                try self.writer.writeAll("-");
            }
        }
    }

    fn renderImageAscii(self: *Self, image: Image, width: i32, height: i32) !void {
        // ASCII art fallback
        _ = image;
        const ascii_width = @min(40, width);
        const ascii_height = @min(20, height);

        // Simple pattern for demonstration
        var y: i32 = 0;
        while (y < ascii_height) : (y += 1) {
            var x: i32 = 0;
            while (x < ascii_width) : (x += 1) {
                const char = if ((x + y) % 3 == 0) "█" else if ((x + y) % 2 == 0) "▓" else "░";
                try self.writer.writeAll(char);
            }
            if (y < ascii_height - 1) try self.writer.writeAll("\n");
        }
    }

    /// Flush all pending output
    pub fn flush(self: *Self) !void {
        try self.writer.flush();
    }

    /// Create a scoped context that automatically restores cursor position
    pub fn scopedContext(self: *Self) !ScopedContext {
        return ScopedContext.init(self);
    }
};

/// RAII-style context that saves and restores terminal state
pub const ScopedContext = struct {
    terminal: *Terminal,

    fn init(terminal: *Terminal) !ScopedContext {
        try ansi_cursor.saveCursor(terminal.writer, terminal.caps);
        return ScopedContext{ .terminal = terminal };
    }

    pub fn deinit(self: *ScopedContext) void {
        ansi_cursor.restoreCursor(self.terminal.writer, self.terminal.caps) catch {};
    }
};

/// Convenience functions for common terminal operations
/// Create a style for text
pub fn createStyle(fg: ?Color, bg: ?Color, bold: bool) Style {
    return Style{
        .fg_color = fg,
        .bg_color = bg,
        .bold = bold,
    };
}

/// Create color from hex string (#RRGGBB or RRGGBB)
pub fn colorFromHex(hex: []const u8) !Color {
    const hex_clean = if (hex.len > 0 and hex[0] == '#') hex[1..] else hex;
    if (hex_clean.len != 6) return error.InvalidHexColor;

    const r = try std.fmt.parseInt(u8, hex_clean[0..2], 16);
    const g = try std.fmt.parseInt(u8, hex_clean[2..4], 16);
    const b = try std.fmt.parseInt(u8, hex_clean[4..6], 16);

    return Color{ .rgb = .{ .r = r, .g = g, .b = b } };
}

/// Quick access to common colors
pub const Colors = struct {
    pub const BLACK = Color{ .ansi = 0 };
    pub const RED = Color{ .ansi = 1 };
    pub const GREEN = Color{ .ansi = 2 };
    pub const YELLOW = Color{ .ansi = 3 };
    pub const BLUE = Color{ .ansi = 4 };
    pub const MAGENTA = Color{ .ansi = 5 };
    pub const CYAN = Color{ .ansi = 6 };
    pub const WHITE = Color{ .ansi = 7 };
    pub const BRIGHT_BLACK = Color{ .ansi = 8 };
    pub const BRIGHT_RED = Color{ .ansi = 9 };
    pub const BRIGHT_GREEN = Color{ .ansi = 10 };
    pub const BRIGHT_YELLOW = Color{ .ansi = 11 };
    pub const BRIGHT_BLUE = Color{ .ansi = 12 };
    pub const BRIGHT_MAGENTA = Color{ .ansi = 13 };
    pub const BRIGHT_CYAN = Color{ .ansi = 14 };
    pub const BRIGHT_WHITE = Color{ .ansi = 15 };
};

/// Dashboard-specific enhancements for the unified terminal interface
/// These methods provide optimized support for dashboard widgets and data visualization
/// Dashboard rendering modes based on terminal capabilities
pub const DashboardMode = struct {
    graphics: GraphicsMode,
    colors: ColorMode,
    interactions: InteractionMode,
    notifications: NotificationMode,

    pub const GraphicsMode = enum {
        kitty_graphics, // Full Kitty graphics protocol
        sixel_graphics, // Sixel graphics support
        unicode_enhanced, // Unicode blocks with wide char support
        ascii_fallback, // Basic ASCII art
        text_only, // Text-only mode
    };

    pub const ColorMode = enum {
        truecolor, // 24-bit RGB colors
        palette_256, // 256-color palette
        ansi_16, // 16 ANSI colors
        monochrome, // No colors
    };

    pub const InteractionMode = enum {
        full_mouse, // Full mouse support with pixel precision
        basic_mouse, // Basic mouse click support
        keyboard_only, // Keyboard navigation only
    };

    pub const NotificationMode = enum {
        system, // OS system notifications
        terminal, // In-terminal notifications only
        none, // No notifications
    };

    /// Detect the best dashboard rendering mode for current terminal
    pub fn detect(caps: TermCaps) DashboardMode {
        return DashboardMode{
            .graphics = if (caps.supportsKittyGraphics) .kitty_graphics else if (caps.supportsSixel) .sixel_graphics else if (caps.supportsUnicode) .unicode_enhanced else .ascii_fallback,
            .colors = if (caps.supportsTrueColor) .truecolor else if (caps.supports256Color) .palette_256 else .ansi_16,
            .interactions = if (caps.supportsSgrPixelMouse) .full_mouse else if (caps.supportsSgrMouse) .basic_mouse else .keyboard_only,
            .notifications = if (caps.supportsNotifyOsc9) .system else .terminal,
        };
    }
};

/// Enhanced Terminal interface with dashboard-specific methods
pub const DashboardTerminal = struct {
    const Self = @This();

    terminal: Terminal,
    mode: DashboardMode,
    performance_buffer: std.ArrayListUnmanaged(u8),
    last_render_hash: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const terminal = try Terminal.init(allocator);
        const mode = DashboardMode.detect(terminal.caps);

        return Self{
            .terminal = terminal,
            .mode = mode,
            .performance_buffer = std.ArrayListUnmanaged(u8){},
        };
    }

    pub fn deinit(self: *Self) void {
        self.performance_buffer.deinit(self.terminal.allocator);
        self.terminal.deinit();
    }

    /// Get the underlying terminal instance
    pub fn getTerminal(self: *Self) *Terminal {
        return &self.terminal;
    }

    /// Get dashboard rendering capabilities
    pub fn getMode(self: *Self) DashboardMode {
        return self.mode;
    }

    /// Optimized chart data rendering with caching
    pub fn renderChartData(self: *Self, data: []const f64, bounds: Rect, style: ChartStyle) !void {
        // Create a hash of the input data to check if we need to re-render
        const data_hash = self.hashData(data, bounds, style);
        if (data_hash == self.last_render_hash) {
            return; // Skip rendering if data hasn't changed
        }
        self.last_render_hash = data_hash;

        switch (self.mode.graphics) {
            .kitty_graphics => try self.renderChartKitty(data, bounds, style),
            .sixel_graphics => try self.renderChartSixel(data, bounds, style),
            .unicode_enhanced => try self.renderChartUnicode(data, bounds, style),
            .ascii_fallback => try self.renderChartAscii(data, bounds, style),
            .text_only => try self.renderChartText(data, bounds, style),
        }
    }

    /// Enhanced clipboard operations with multiple format support
    pub fn copyTableData(self: *Self, data: []const []const []const u8, format: ClipboardFormat) !void {
        self.performance_buffer.clearRetainingCapacity();
        const writer = self.performance_buffer.writer(self.terminal.allocator);

        switch (format) {
            .tsv => {
                for (data, 0..) |row, row_idx| {
                    for (row, 0..) |cell, col_idx| {
                        if (col_idx > 0) try writer.writeAll("\t");
                        try writer.writeAll(cell);
                    }
                    if (row_idx < data.len - 1) try writer.writeAll("\n");
                }
            },
            .csv => {
                for (data, 0..) |row, row_idx| {
                    for (row, 0..) |cell, col_idx| {
                        if (col_idx > 0) try writer.writeAll(",");

                        // Escape CSV if needed
                        if (std.mem.indexOf(u8, cell, ",") != null or
                            std.mem.indexOf(u8, cell, "\"") != null or
                            std.mem.indexOf(u8, cell, "\n") != null)
                        {
                            try writer.writeAll("\"");
                            for (cell) |char| {
                                if (char == '"') try writer.writeAll("\"\"") else try writer.writeByte(char);
                            }
                            try writer.writeAll("\"");
                        } else {
                            try writer.writeAll(cell);
                        }
                    }
                    if (row_idx < data.len - 1) try writer.writeAll("\n");
                }
            },
            .markdown => {
                if (data.len == 0) return;

                // Headers
                const headers = data[0];
                try writer.writeAll("| ");
                for (headers, 0..) |header, i| {
                    try writer.writeAll(header);
                    if (i < headers.len - 1) try writer.writeAll(" | ");
                }
                try writer.writeAll(" |\n");

                // Separator
                try writer.writeAll("| ");
                for (headers, 0..) |_, i| {
                    try writer.writeAll("---");
                    if (i < headers.len - 1) try writer.writeAll(" | ");
                }
                try writer.writeAll(" |\n");

                // Data rows
                for (data[1..]) |row| {
                    try writer.writeAll("| ");
                    for (row, 0..) |cell, i| {
                        try writer.writeAll(cell);
                        if (i < row.len - 1) try writer.writeAll(" | ");
                    }
                    try writer.writeAll(" |\n");
                }
            },
        }

        try self.terminal.copyToClipboard(self.performance_buffer.items);
    }

    pub const ClipboardFormat = enum {
        tsv, // Tab-separated values
        csv, // Comma-separated values
        markdown, // Markdown table format
    };

    /// Smart notification system that adapts to terminal capabilities
    pub fn dashboardNotification(self: *Self, level: NotificationLevel, title: []const u8, message: []const u8, duration_ms: ?u32) !void {
        switch (self.mode.notifications) {
            .system => {
                // Send system notification
                try self.terminal.notification(level, title, message);
            },
            .terminal => {
                // Enhanced in-terminal notification with optional auto-dismiss
                try self.renderInTerminalNotification(level, title, message, duration_ms);
            },
            .none => {
                // Just log to a status area or ignore
            },
        }
    }

    fn renderInTerminalNotification(self: *Self, level: NotificationLevel, title: []const u8, message: []const u8, duration_ms: ?u32) !void {
        // Enhanced notification rendering with better styling
        const border_style = switch (level) {
            .info => Style{ .fg_color = Colors.BLUE },
            .success => Style{ .fg_color = Colors.GREEN },
            .warning => Style{ .fg_color = Colors.YELLOW },
            .@"error" => Style{ .fg_color = Colors.RED, .bold = true },
            .debug => Style{ .fg_color = Colors.MAGENTA },
        };

        // Save cursor position
        var ctx = try self.terminal.scopedContext();
        defer ctx.deinit();

        // Move to notification area (top right)
        try self.terminal.moveTo(60, 1); // TODO: Make this configurable

        // Render notification box
        try self.terminal.print("╭─ ", border_style);
        try self.terminal.print(title, Style{ .bold = true });
        try self.terminal.print(" ─╮", border_style);

        try self.terminal.moveTo(60, 2);
        try self.terminal.print("│ ", border_style);
        try self.terminal.print(message, null);
        try self.terminal.print(" │", border_style);

        try self.terminal.moveTo(60, 3);
        try self.terminal.print("╰", border_style);
        for (0..title.len + message.len) |_| {
            try self.terminal.print("─", border_style);
        }
        try self.terminal.print("╯", border_style);

        if (duration_ms) |duration| {
            // TODO: Implement auto-dismiss timer
            _ = duration;
        }
    }

    pub const ChartStyle = struct {
        color_scheme: ColorScheme = .default,
        show_grid: bool = true,
        show_axes: bool = true,
        line_style: LineStyle = .solid,

        pub const ColorScheme = enum {
            default,
            monochrome,
            rainbow,
            heat_map,
            cool_blue,
            warm_red,
        };

        pub const LineStyle = enum {
            solid,
            dashed,
            dotted,
            bold,
        };
    };

    // Chart rendering implementations for different modes
    fn renderChartKitty(self: *Self, data: []const f64, bounds: Rect, style: ChartStyle) !void {
        // Generate chart image and use Kitty graphics protocol
        const image = try self.generateChartImage(data, bounds, style);
        defer self.terminal.allocator.free(image.data);

        try self.terminal.renderImage(image, Point{ .x = bounds.x, .y = bounds.y }, Point{ .x = bounds.width, .y = bounds.height });
    }

    fn renderChartSixel(self: *Self, data: []const f64, bounds: Rect, style: ChartStyle) !void {
        // Similar to Kitty but use Sixel protocol
        _ = self;
        _ = data;
        _ = bounds;
        _ = style;
        // TODO: Implement Sixel chart rendering
    }

    fn renderChartUnicode(self: *Self, data: []const f64, bounds: Rect, style: ChartStyle) !void {
        // Use Unicode block characters for chart rendering
        if (data.len == 0) return;

        const chart_height = @as(u32, @intCast(bounds.height)) - 2; // Leave space for axes
        const chart_width = @as(u32, @intCast(bounds.width)) - 4; // Leave space for Y axis labels

        // Find data range
        var min_val = data[0];
        var max_val = data[0];
        for (data[1..]) |value| {
            if (value < min_val) min_val = value;
            if (value > max_val) max_val = value;
        }

        const range = max_val - min_val;
        if (range == 0) return;

        // Render chart using Unicode blocks
        for (0..chart_height) |row| {
            try self.terminal.moveTo(bounds.x, bounds.y + @as(i32, @intCast(row)));

            const y_value = max_val - ((@as(f64, @floatFromInt(row)) / @as(f64, @floatFromInt(chart_height))) * range);

            for (0..chart_width) |col| {
                const data_index = (col * data.len) / chart_width;
                if (data_index < data.len) {
                    const value = data[data_index];
                    const block_char = if (value >= y_value) "█" else " ";

                    const color = self.getColorForValue(value, min_val, max_val, style.color_scheme);
                    try self.terminal.print(block_char, Style{ .fg_color = color });
                } else {
                    try self.terminal.print(" ", null);
                }
            }
        }
    }

    fn renderChartAscii(self: *Self, data: []const f64, bounds: Rect, style: ChartStyle) !void {
        // ASCII fallback chart rendering
        _ = style;

        if (data.len == 0) return;

        const chart_height = @as(u32, @intCast(bounds.height)) - 2;
        const chart_width = @as(u32, @intCast(bounds.width)) - 4;

        // Find data range
        var min_val = data[0];
        var max_val = data[0];
        for (data[1..]) |value| {
            if (value < min_val) min_val = value;
            if (value > max_val) max_val = value;
        }

        const range = max_val - min_val;
        if (range == 0) return;

        // Render ASCII chart
        for (0..chart_height) |row| {
            try self.terminal.moveTo(bounds.x, bounds.y + @as(i32, @intCast(row)));

            const y_value = max_val - ((@as(f64, @floatFromInt(row)) / @as(f64, @floatFromInt(chart_height))) * range);

            for (0..chart_width) |col| {
                const data_index = (col * data.len) / chart_width;
                if (data_index < data.len) {
                    const value = data[data_index];
                    const char = if (value >= y_value) "#" else " ";
                    try self.terminal.print(char, null);
                } else {
                    try self.terminal.print(" ", null);
                }
            }
        }
    }

    fn renderChartText(self: *Self, data: []const f64, bounds: Rect, style: ChartStyle) !void {
        // Text-only chart representation
        _ = style;

        try self.terminal.moveTo(bounds.x, bounds.y);
        try self.terminal.print("Chart Data: ", Style{ .bold = true });

        for (data, 0..) |value, i| {
            if (i > 0) try self.terminal.print(", ", null);
            try self.terminal.printf("{d:.2}", .{value}, null);

            if ((i + 1) % 10 == 0) {
                try self.terminal.moveTo(bounds.x, bounds.y + @as(i32, @intCast(i / 10)) + 1);
            }
        }
    }

    fn generateChartImage(self: *Self, data: []const f64, bounds: Rect, style: ChartStyle) !Image {
        // Generate a simple chart image for Kitty graphics
        const width = @as(u32, @intCast(bounds.width)) * 8; // 8 pixels per cell
        const height = @as(u32, @intCast(bounds.height)) * 16; // 16 pixels per cell

        const image_data = try self.terminal.allocator.alloc(u8, width * height * 3); // RGB
        @memset(image_data, 255); // White background

        // Simple line drawing (this is a basic implementation)
        if (data.len > 1) {
            var min_val = data[0];
            var max_val = data[0];
            for (data[1..]) |value| {
                if (value < min_val) min_val = value;
                if (value > max_val) max_val = value;
            }

            const range = max_val - min_val;
            if (range > 0) {
                for (0..data.len - 1) |i| {
                    const x1 = (i * width) / data.len;
                    const y1 = height - @as(u32, @intFromFloat((data[i] - min_val) / range * @as(f64, @floatFromInt(height))));
                    const x2 = ((i + 1) * width) / data.len;
                    const y2 = height - @as(u32, @intFromFloat((data[i + 1] - min_val) / range * @as(f64, @floatFromInt(height))));

                    // Draw line (simplified Bresenham)
                    self.drawLine(image_data, width, height, x1, y1, x2, y2, style.color_scheme);
                }
            }
        }

        return Image{
            .data = image_data,
            .width = width,
            .height = height,
            .format = .rgb24,
        };
    }

    fn drawLine(self: *Self, image_data: []u8, width: u32, height: u32, x1: u32, y1: u32, x2: u32, y2: u32, color_scheme: ChartStyle.ColorScheme) void {
        _ = self;
        _ = color_scheme;

        // Simple line drawing (this is a basic implementation)
        const dx = @as(i32, @intCast(x2)) - @as(i32, @intCast(x1));
        const dy = @as(i32, @intCast(y2)) - @as(i32, @intCast(y1));
        const steps = @max(@abs(dx), @abs(dy));

        if (steps == 0) return;

        for (0..@as(u32, @intCast(steps))) |step| {
            const x = x1 + @as(u32, @intCast((dx * @as(i32, @intCast(step))) / steps));
            const y = y1 + @as(u32, @intCast((dy * @as(i32, @intCast(step))) / steps));

            if (x < width and y < height) {
                const pixel_offset = (y * width + x) * 3;
                if (pixel_offset + 2 < image_data.len) {
                    image_data[pixel_offset] = 0; // R
                    image_data[pixel_offset + 1] = 100; // G
                    image_data[pixel_offset + 2] = 200; // B
                }
            }
        }
    }

    fn getColorForValue(self: *Self, value: f64, min_val: f64, max_val: f64, scheme: ChartStyle.ColorScheme) Color {
        _ = self;

        const normalized = if (max_val > min_val) (value - min_val) / (max_val - min_val) else 0.5;

        return switch (scheme) {
            .default => Color{ .rgb = .{ .r = 100, .g = 149, .b = 237 } },
            .monochrome => Colors.WHITE,
            .rainbow => {
                // Simple rainbow mapping
                const hue = normalized * 360;
                if (hue < 60) return Color{ .rgb = .{ .r = 255, .g = @as(u8, @intFromFloat(hue * 255 / 60)), .b = 0 } };
                if (hue < 120) return Color{ .rgb = .{ .r = @as(u8, @intFromFloat((120 - hue) * 255 / 60)), .g = 255, .b = 0 } };
                if (hue < 180) return Color{ .rgb = .{ .r = 0, .g = 255, .b = @as(u8, @intFromFloat((hue - 120) * 255 / 60)) } };
                if (hue < 240) return Color{ .rgb = .{ .r = 0, .g = @as(u8, @intFromFloat((240 - hue) * 255 / 60)), .b = 255 } };
                if (hue < 300) return Color{ .rgb = .{ .r = @as(u8, @intFromFloat((hue - 240) * 255 / 60)), .g = 0, .b = 255 } };
                return Color{ .rgb = .{ .r = 255, .g = 0, .b = @as(u8, @intFromFloat((360 - hue) * 255 / 60)) } };
            },
            .heat_map => {
                const r = @as(u8, @intFromFloat(normalized * 255));
                const g = @as(u8, @intFromFloat(normalized * 127));
                return Color{ .rgb = .{ .r = r, .g = g, .b = 0 } };
            },
            .cool_blue => {
                const intensity = @as(u8, @intFromFloat(normalized * 255));
                return Color{ .rgb = .{ .r = 0, .g = intensity / 2, .b = intensity } };
            },
            .warm_red => {
                const intensity = @as(u8, @intFromFloat(normalized * 255));
                return Color{ .rgb = .{ .r = intensity, .g = intensity / 3, .b = 0 } };
            },
        };
    }

    fn hashData(self: *Self, data: []const f64, bounds: Rect, style: ChartStyle) u64 {
        _ = self;

        // Simple hash combining data, bounds, and style
        var hasher = std.hash_map.Wyhash.init(0);

        // Hash data
        for (data) |value| {
            const value_bytes = std.mem.asBytes(&value);
            hasher.update(value_bytes);
        }

        // Hash bounds
        hasher.update(std.mem.asBytes(&bounds.x));
        hasher.update(std.mem.asBytes(&bounds.y));
        hasher.update(std.mem.asBytes(&bounds.width));
        hasher.update(std.mem.asBytes(&bounds.height));

        // Hash style (simplified)
        hasher.update(std.mem.asBytes(&style.color_scheme));
        hasher.update(std.mem.asBytes(&style.show_grid));
        hasher.update(std.mem.asBytes(&style.show_axes));

        return hasher.final();
    }

    /// Performance monitoring for dashboard updates
    pub fn startPerformanceTimer(self: *Self) std.time.Timer {
        _ = self;
        return std.time.Timer.start() catch unreachable;
    }

    pub fn logPerformanceMetric(self: *Self, timer: std.time.Timer, operation: []const u8) void {
        _ = self;
        const elapsed_ns = timer.read();
        const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;

        if (elapsed_ms > 16.0) { // Log slow operations (> 16ms for 60 FPS)
            std.log.warn("Slow dashboard operation '{}': {d:.2}ms", .{ operation, elapsed_ms });
        }
    }
};

/// Utility functions for dashboard development
pub fn createDashboardColors() [8]Color {
    return [_]Color{
        Color{ .rgb = .{ .r = 31, .g = 119, .b = 180 } }, // Blue
        Color{ .rgb = .{ .r = 255, .g = 127, .b = 14 } }, // Orange
        Color{ .rgb = .{ .r = 44, .g = 160, .b = 44 } }, // Green
        Color{ .rgb = .{ .r = 214, .g = 39, .b = 40 } }, // Red
        Color{ .rgb = .{ .r = 148, .g = 103, .b = 189 } }, // Purple
        Color{ .rgb = .{ .r = 140, .g = 86, .b = 75 } }, // Brown
        Color{ .rgb = .{ .r = 227, .g = 119, .b = 194 } }, // Pink
        Color{ .rgb = .{ .r = 127, .g = 127, .b = 127 } }, // Gray
    };
}

test "color adaptation" {
    const caps_true = TermCaps{
        .supportsTruecolor = true,
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
    const caps_256 = TermCaps{
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

    const rgb_color = Color{ .rgb = .{ .r = 255, .g = 128, .b = 64 } };

    const adapted_true = rgb_color.adapt(caps_true);
    const adapted_256 = rgb_color.adapt(caps_256);

    try std.testing.expect(adapted_true == .rgb);
    try std.testing.expect(adapted_256 == .palette);
}

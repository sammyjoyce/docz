const std = @import("std");
const print = std.debug.print;

// Enhanced terminal background/foreground color management
// Supports XParseColor rgb:/rgba: formats, hex colors, and terminal queries
// Provides comprehensive color management for modern terminals

/// Color representation for terminal operations
pub const Color = struct {
    r: u16,
    g: u16,
    b: u16,
    a: u16 = 0xFFFF,

    pub fn fromRGB(r: u8, g: u8, b: u8) Color {
        return Color{
            .r = @as(u16, r) << 8 | r,
            .g = @as(u16, g) << 8 | g,
            .b = @as(u16, b) << 8 | b,
        };
    }

    pub fn fromRGBA(r: u8, g: u8, b: u8, a: u8) Color {
        return Color{
            .r = @as(u16, r) << 8 | r,
            .g = @as(u16, g) << 8 | g,
            .b = @as(u16, b) << 8 | b,
            .a = @as(u16, a) << 8 | a,
        };
    }

    pub fn fromHex(hex_str: []const u8) !Color {
        var hex = hex_str;
        if (std.mem.startsWith(u8, hex, "#")) {
            hex = hex[1..];
        }

        if (hex.len != 6 and hex.len != 8) {
            return error.InvalidHexLength;
        }

        const rgb_val = try std.fmt.parseInt(u32, hex[0..6], 16);
        const r = @as(u8, @truncate((rgb_val >> 16) & 0xFF));
        const g = @as(u8, @truncate((rgb_val >> 8) & 0xFF));
        const b = @as(u8, @truncate(rgb_val & 0xFF));

        if (hex.len == 8) {
            const a_val = try std.fmt.parseInt(u8, hex[6..8], 16);
            return fromRGBA(r, g, b, a_val);
        } else {
            return fromRGB(r, g, b);
        }
    }
};

/// HexColor provides hex string formatting for colors
pub const HexColor = struct {
    color: Color,

    pub fn init(color: Color) HexColor {
        return HexColor{ .color = color };
    }

    pub fn fromHex(hex_str: []const u8) !HexColor {
        const color = try Color.fromHex(hex_str);
        return init(color);
    }

    /// Format as hex string (#RRGGBB)
    pub fn toHex(self: HexColor, allocator: std.mem.Allocator) ![]u8 {
        const r = @as(u8, @truncate(self.color.r >> 8));
        const g = @as(u8, @truncate(self.color.g >> 8));
        const b = @as(u8, @truncate(self.color.b >> 8));
        return try std.fmt.allocPrint(allocator, "#{x:0>2}{x:0>2}{x:0>2}", .{ r, g, b });
    }

    /// Format as hex string with alpha (#RRGGBBAA)
    pub fn toHexAlpha(self: HexColor, allocator: std.mem.Allocator) ![]u8 {
        const r = @as(u8, @truncate(self.color.r >> 8));
        const g = @as(u8, @truncate(self.color.g >> 8));
        const b = @as(u8, @truncate(self.color.b >> 8));
        const a = @as(u8, @truncate(self.color.a >> 8));
        return try std.fmt.allocPrint(allocator, "#{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{ r, g, b, a });
    }
};

/// XParseColor RGB format color (rgb:RRRR/GGGG/BBBB)
pub const XRGBColor = struct {
    color: Color,

    pub fn init(color: Color) XRGBColor {
        return XRGBColor{ .color = color };
    }

    pub fn toString(self: XRGBColor, allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, "rgb:{x:0>4}/{x:0>4}/{x:0>4}", .{
            self.color.r,
            self.color.g,
            self.color.b,
        });
    }

    pub fn fromString(rgb_str: []const u8) !XRGBColor {
        if (!std.mem.startsWith(u8, rgb_str, "rgb:")) {
            return error.InvalidFormat;
        }

        const parts_str = rgb_str[4..];
        var parts = std.mem.splitSequence(u8, parts_str, "/");

        const r_str = parts.next() orelse return error.InvalidFormat;
        const g_str = parts.next() orelse return error.InvalidFormat;
        const b_str = parts.next() orelse return error.InvalidFormat;

        const r = try std.fmt.parseInt(u16, r_str, 16);
        const g = try std.fmt.parseInt(u16, g_str, 16);
        const b = try std.fmt.parseInt(u16, b_str, 16);

        return XRGBColor{
            .color = Color{ .r = r, .g = g, .b = b },
        };
    }
};

/// XParseColor RGBA format color (rgba:RRRR/GGGG/BBBB/AAAA)
pub const XRGBAColor = struct {
    color: Color,

    pub fn init(color: Color) XRGBAColor {
        return XRGBAColor{ .color = color };
    }

    pub fn toString(self: XRGBAColor, allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, "rgba:{x:0>4}/{x:0>4}/{x:0>4}/{x:0>4}", .{
            self.color.r,
            self.color.g,
            self.color.b,
            self.color.a,
        });
    }

    pub fn fromString(rgba_str: []const u8) !XRGBAColor {
        if (!std.mem.startsWith(u8, rgba_str, "rgba:")) {
            return error.InvalidFormat;
        }

        const parts_str = rgba_str[5..];
        var parts = std.mem.splitSequence(u8, parts_str, "/");

        const r_str = parts.next() orelse return error.InvalidFormat;
        const g_str = parts.next() orelse return error.InvalidFormat;
        const b_str = parts.next() orelse return error.InvalidFormat;
        const a_str = parts.next() orelse return error.InvalidFormat;

        const r = try std.fmt.parseInt(u16, r_str, 16);
        const g = try std.fmt.parseInt(u16, g_str, 16);
        const b = try std.fmt.parseInt(u16, b_str, 16);
        const a = try std.fmt.parseInt(u16, a_str, 16);

        return XRGBAColor{
            .color = Color{ .r = r, .g = g, .b = b, .a = a },
        };
    }
};

/// OSC (Operating System Command) sequences for terminal color operations
pub const OSC = struct {
    /// Set terminal foreground color (OSC 10)
    pub fn setForegroundColor(allocator: std.mem.Allocator, color_str: []const u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "\x1b]10;{s}\x07", .{color_str});
    }

    /// Request terminal foreground color (OSC 10)
    pub const request_foreground_color = "\x1b]10;?\x07";

    /// Reset terminal foreground color (OSC 110)
    pub const reset_foreground_color = "\x1b]110\x07";

    /// Set terminal background color (OSC 11)
    pub fn setBackgroundColor(allocator: std.mem.Allocator, color_str: []const u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "\x1b]11;{s}\x07", .{color_str});
    }

    /// Request terminal background color (OSC 11)
    pub const request_background_color = "\x1b]11;?\x07";

    /// Reset terminal background color (OSC 111)
    pub const reset_background_color = "\x1b]111\x07";

    /// Set terminal cursor color (OSC 12)
    pub fn setCursorColor(allocator: std.mem.Allocator, color_str: []const u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "\x1b]12;{s}\x07", .{color_str});
    }

    /// Request terminal cursor color (OSC 12)
    pub const request_cursor_color = "\x1b]12;?\x07";

    /// Reset terminal cursor color (OSC 112)
    pub const reset_cursor_color = "\x1b]112\x07";
};

/// Background color detection and analysis utilities
pub const BackgroundDetection = struct {
    /// Analyze color brightness using relative luminance (sRGB)
    /// Returns value between 0.0 (darkest) and 1.0 (brightest)
    pub fn getLuminance(color: Color) f64 {
        // Convert to 8-bit values
        const r = @as(f64, @floatFromInt(color.r >> 8)) / 255.0;
        const g = @as(f64, @floatFromInt(color.g >> 8)) / 255.0;
        const b = @as(f64, @floatFromInt(color.b >> 8)) / 255.0;

        // Apply gamma correction
        const r_linear = if (r <= 0.03928) r / 12.92 else std.math.pow(f64, (r + 0.055) / 1.055, 2.4);
        const g_linear = if (g <= 0.03928) g / 12.92 else std.math.pow(f64, (g + 0.055) / 1.055, 2.4);
        const b_linear = if (b <= 0.03928) b / 12.92 else std.math.pow(f64, (b + 0.055) / 1.055, 2.4);

        // Calculate relative luminance
        return 0.2126 * r_linear + 0.7152 * g_linear + 0.0722 * b_linear;
    }

    /// Determine if a color is considered "dark" (luminance < 0.5)
    pub fn isDark(color: Color) bool {
        return getLuminance(color) < 0.5;
    }

    /// Determine if a color is considered "light" (luminance >= 0.5)
    pub fn isLight(color: Color) bool {
        return !isDark(color);
    }

    /// Calculate contrast ratio between two colors
    /// Returns ratio from 1:1 (no contrast) to 21:1 (maximum contrast)
    pub fn getContrastRatio(color1: Color, color2: Color) f64 {
        const l1 = getLuminance(color1);
        const l2 = getLuminance(color2);

        const lighter = @max(l1, l2);
        const darker = @min(l1, l2);

        return (lighter + 0.05) / (darker + 0.05);
    }

    /// Check if contrast meets WCAG accessibility guidelines
    pub fn meetsWCAGContrast(fg_color: Color, bg_color: Color, level: WCAGLevel) bool {
        const ratio = getContrastRatio(fg_color, bg_color);
        return switch (level) {
            .AA_normal => ratio >= 4.5,
            .AA_large => ratio >= 3.0,
            .AAA_normal => ratio >= 7.0,
            .AAA_large => ratio >= 4.5,
        };
    }

    /// WCAG contrast levels
    pub const WCAGLevel = enum {
        AA_normal, // Normal text - 4.5:1 minimum
        AA_large, // Large text - 3:1 minimum
        AAA_normal, // Enhanced normal text - 7:1 minimum
        AAA_large, // Enhanced large text - 4.5:1 minimum
    };

    /// Suggest optimal foreground color for a background
    pub fn suggestForegroundColor(bg_color: Color) Color {
        return if (isDark(bg_color))
            Color.fromRGB(255, 255, 255) // White text on dark background
        else
            Color.fromRGB(0, 0, 0); // Black text on light background
    }

    /// Parse color response from terminal OSC query
    /// Handles both hex and XParseColor formats
    pub fn parseColorResponse(response: []const u8) !Color {
        if (response.len < 4) return error.InvalidResponse;

        // Expected format: ESC ] code ; color BEL/ST
        if (!std.mem.startsWith(u8, response, "\x1b]")) {
            return error.InvalidResponse;
        }

        // Find semicolon separator
        const semi_pos = std.mem.indexOf(u8, response, ";") orelse return error.InvalidResponse;

        // Find terminator
        var end_pos: usize = response.len;
        if (std.mem.lastIndexOf(u8, response, "\x07")) |bel_pos| {
            end_pos = bel_pos;
        } else if (std.mem.lastIndexOf(u8, response, "\x1b\\")) |st_pos| {
            end_pos = st_pos;
        }

        if (end_pos <= semi_pos + 1) return error.InvalidResponse;

        const color_str = response[semi_pos + 1 .. end_pos];

        // Try different color format parsers
        if (std.mem.startsWith(u8, color_str, "#")) {
            return Color.fromHex(color_str);
        } else if (std.mem.startsWith(u8, color_str, "rgb:")) {
            const xrgb = try XRGBColor.fromString(color_str);
            return xrgb.color;
        } else if (std.mem.startsWith(u8, color_str, "rgba:")) {
            const xrgba = try XRGBAColor.fromString(color_str);
            return xrgba.color;
        }

        return error.UnsupportedColorFormat;
    }
};

/// Advanced terminal background manager with detection capabilities
pub const BackgroundManager = struct {
    allocator: std.mem.Allocator,
    detected_bg: ?Color,
    detected_fg: ?Color,

    pub fn init(allocator: std.mem.Allocator) BackgroundManager {
        return BackgroundManager{
            .allocator = allocator,
            .detected_bg = null,
            .detected_fg = null,
        };
    }

    /// Query terminal for current background color
    /// Note: This requires reading the response from terminal input
    pub fn queryBackgroundColor(_: *BackgroundManager, writer: anytype) !void {
        try writer.writeAll(OSC.request_background_color);
        try writer.flush();
    }

    /// Query terminal for current foreground color
    pub fn queryForegroundColor(_: *BackgroundManager, writer: anytype) !void {
        try writer.writeAll(OSC.request_foreground_color);
        try writer.flush();
    }

    /// Process color response from terminal
    pub fn processColorResponse(self: *BackgroundManager, response: []const u8) !void {
        const color = try BackgroundDetection.parseColorResponse(response);

        // Determine if this is background or foreground based on OSC code
        if (std.mem.indexOf(u8, response, "]10;")) |_| {
            // Foreground color response
            self.detected_fg = color;
        } else if (std.mem.indexOf(u8, response, "]11;")) |_| {
            // Background color response
            self.detected_bg = color;
        }
    }

    /// Get detected background color
    pub fn getBackground(self: BackgroundManager) ?Color {
        return self.detected_bg;
    }

    /// Get detected foreground color
    pub fn getForeground(self: BackgroundManager) ?Color {
        return self.detected_fg;
    }

    /// Check if terminal has dark theme
    pub fn hasDarkTheme(self: BackgroundManager) ?bool {
        if (self.detected_bg) |bg| {
            return BackgroundDetection.isDark(bg);
        }
        return null;
    }

    /// Get optimal text color for current background
    pub fn getOptimalTextColor(self: BackgroundManager) ?Color {
        if (self.detected_bg) |bg| {
            return BackgroundDetection.suggestForegroundColor(bg);
        }
        return null;
    }

    /// Check contrast between detected colors
    pub fn checkContrast(self: BackgroundManager, level: BackgroundDetection.WCAGLevel) ?bool {
        if (self.detected_fg) |fg| {
            if (self.detected_bg) |bg| {
                return BackgroundDetection.meetsWCAGContrast(fg, bg, level);
            }
        }
        return null;
    }

    /// Adaptive color scheme based on detected background
    pub fn getAdaptiveColors(self: BackgroundManager) AdaptiveColorScheme {
        if (self.detected_bg) |bg| {
            const is_dark = BackgroundDetection.isDark(bg);
            if (is_dark) {
                return AdaptiveColorScheme{
                    .primary = Color.fromRGB(255, 255, 255),
                    .secondary = Color.fromRGB(200, 200, 200),
                    .accent = Color.fromRGB(100, 150, 255),
                    .muted = Color.fromRGB(128, 128, 128),
                    .success = Color.fromRGB(100, 255, 100),
                    .warning = Color.fromRGB(255, 200, 100),
                    .err = Color.fromRGB(255, 100, 100),
                };
            } else {
                return AdaptiveColorScheme{
                    .primary = Color.fromRGB(0, 0, 0),
                    .secondary = Color.fromRGB(64, 64, 64),
                    .accent = Color.fromRGB(0, 100, 200),
                    .muted = Color.fromRGB(128, 128, 128),
                    .success = Color.fromRGB(0, 150, 0),
                    .warning = Color.fromRGB(200, 150, 0),
                    .err = Color.fromRGB(200, 0, 0),
                };
            }
        }

        // Default neutral scheme
        return AdaptiveColorScheme{
            .primary = Color.fromRGB(128, 128, 128),
            .secondary = Color.fromRGB(96, 96, 96),
            .accent = Color.fromRGB(64, 128, 192),
            .muted = Color.fromRGB(160, 160, 160),
            .success = Color.fromRGB(64, 192, 64),
            .warning = Color.fromRGB(192, 160, 64),
            .err = Color.fromRGB(192, 64, 64),
        };
    }
};

/// Adaptive color scheme for different terminal themes
pub const AdaptiveColorScheme = struct {
    primary: Color,
    secondary: Color,
    accent: Color,
    muted: Color,
    success: Color,
    warning: Color,
    err: Color, // renamed from 'error' as it's a reserved keyword
};

/// Enhanced writer interface with new Zig 0.15.1 std.Io.Writer API
pub const TerminalColorWriter = struct {
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,

    pub fn init(writer: *std.Io.Writer, allocator: std.mem.Allocator) TerminalColorWriter {
        return TerminalColorWriter{
            .writer = writer,
            .allocator = allocator,
        };
    }

    /// Set foreground color using various color formats
    pub fn setForeground(self: TerminalColorWriter, color: anytype) !void {
        const color_str = switch (@TypeOf(color)) {
            HexColor => try color.toHex(self.allocator),
            XRGBColor => try color.toString(self.allocator),
            XRGBAColor => try color.toString(self.allocator),
            []const u8 => color,
            else => @compileError("Unsupported color type"),
        };
        defer if (@TypeOf(color) != []const u8) self.allocator.free(color_str);

        const seq = try OSC.setForegroundColor(self.allocator, color_str);
        defer self.allocator.free(seq);
        try self.writer.write(seq);
        try self.writer.flush();
    }

    /// Set background color using various color formats
    pub fn setBackground(self: TerminalColorWriter, color: anytype) !void {
        const color_str = switch (@TypeOf(color)) {
            HexColor => try color.toHex(self.allocator),
            XRGBColor => try color.toString(self.allocator),
            XRGBAColor => try color.toString(self.allocator),
            []const u8 => color,
            else => @compileError("Unsupported color type"),
        };
        defer if (@TypeOf(color) != []const u8) self.allocator.free(color_str);

        const seq = try OSC.setBackgroundColor(self.allocator, color_str);
        defer self.allocator.free(seq);
        try self.writer.write(seq);
        try self.writer.flush();
    }

    /// Set cursor color using various color formats
    pub fn setCursor(self: TerminalColorWriter, color: anytype) !void {
        const color_str = switch (@TypeOf(color)) {
            HexColor => try color.toHex(self.allocator),
            XRGBColor => try color.toString(self.allocator),
            XRGBAColor => try color.toString(self.allocator),
            []const u8 => color,
            else => @compileError("Unsupported color type"),
        };
        defer if (@TypeOf(color) != []const u8) self.allocator.free(color_str);

        const seq = try OSC.setCursorColor(self.allocator, color_str);
        defer self.allocator.free(seq);
        try self.writer.write(seq);
        try self.writer.flush();
    }

    /// Request foreground color from terminal
    pub fn requestForeground(self: TerminalColorWriter) !void {
        try self.writer.write(OSC.request_foreground_color);
        try self.writer.flush();
    }

    /// Request background color from terminal
    pub fn requestBackground(self: TerminalColorWriter) !void {
        try self.writer.write(OSC.request_background_color);
        try self.writer.flush();
    }

    /// Request cursor color from terminal
    pub fn requestCursor(self: TerminalColorWriter) !void {
        try self.writer.write(OSC.request_cursor_color);
        try self.writer.flush();
    }

    /// Reset all colors to defaults
    pub fn resetAll(self: TerminalColorWriter) !void {
        try self.writer.write(OSC.reset_foreground_color);
        try self.writer.write(OSC.reset_background_color);
        try self.writer.write(OSC.reset_cursor_color);
        try self.writer.flush();
    }
};

// Tests
test "color parsing and formatting" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test hex color parsing
    const hex_color = try HexColor.fromHex("#FF0000");
    const hex_str = try hex_color.toHex(allocator);
    defer allocator.free(hex_str);
    try testing.expectEqualStrings("#ff0000", hex_str);

    // Test XParseColor RGB format
    const color = Color.fromRGB(255, 128, 64);
    const xrgb = XRGBColor.init(color);
    const xrgb_str = try xrgb.toString(allocator);
    defer allocator.free(xrgb_str);
    try testing.expectEqualStrings("rgb:ffff/8080/4040", xrgb_str);

    // Test XParseColor RGBA format
    const rgba_color = Color.fromRGBA(255, 128, 64, 200);
    const xrgba = XRGBAColor.init(rgba_color);
    const xrgba_str = try xrgba.toString(allocator);
    defer allocator.free(xrgba_str);
    try testing.expectEqualStrings("rgba:ffff/8080/4040/c8c8", xrgba_str);
}

test "xparsecolor parsing" {
    const testing = std.testing;

    // Test RGB parsing
    const xrgb = try XRGBColor.fromString("rgb:ff00/8000/4000");
    try testing.expectEqual(@as(u16, 0xff00), xrgb.color.r);
    try testing.expectEqual(@as(u16, 0x8000), xrgb.color.g);
    try testing.expectEqual(@as(u16, 0x4000), xrgb.color.b);

    // Test RGBA parsing
    const xrgba = try XRGBAColor.fromString("rgba:ff00/8000/4000/c800");
    try testing.expectEqual(@as(u16, 0xff00), xrgba.color.r);
    try testing.expectEqual(@as(u16, 0x8000), xrgba.color.g);
    try testing.expectEqual(@as(u16, 0x4000), xrgba.color.b);
    try testing.expectEqual(@as(u16, 0xc800), xrgba.color.a);
}

test "OSC sequence generation" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const fg_seq = try OSC.setForegroundColor(allocator, "#FF0000");
    defer allocator.free(fg_seq);
    try testing.expectEqualStrings("\x1b]10;#FF0000\x07", fg_seq);

    const bg_seq = try OSC.setBackgroundColor(allocator, "rgb:ff00/0000/0000");
    defer allocator.free(bg_seq);
    try testing.expectEqualStrings("\x1b]11;rgb:ff00/0000/0000\x07", bg_seq);
}

// === ENHANCED BACKGROUND DETECTION TESTS ===

test "luminance calculation" {
    const testing = std.testing;

    // Test pure colors
    const white = Color.fromRGB(255, 255, 255);
    const white_luminance = BackgroundDetection.getLuminance(white);
    try testing.expect(white_luminance > 0.9); // White should be very bright

    const black = Color.fromRGB(0, 0, 0);
    const black_luminance = BackgroundDetection.getLuminance(black);
    try testing.expect(black_luminance < 0.1); // Black should be very dark

    const red = Color.fromRGB(255, 0, 0);
    const red_luminance = BackgroundDetection.getLuminance(red);
    try testing.expect(red_luminance > 0.1 and red_luminance < 0.5); // Red should be medium-dark
}

test "dark and light detection" {
    const testing = std.testing;

    const dark_gray = Color.fromRGB(64, 64, 64);
    try testing.expect(BackgroundDetection.isDark(dark_gray));
    try testing.expect(!BackgroundDetection.isLight(dark_gray));

    const light_gray = Color.fromRGB(192, 192, 192);
    try testing.expect(!BackgroundDetection.isDark(light_gray));
    try testing.expect(BackgroundDetection.isLight(light_gray));
}

test "contrast ratio calculation" {
    const testing = std.testing;

    const white = Color.fromRGB(255, 255, 255);
    const black = Color.fromRGB(0, 0, 0);

    const contrast = BackgroundDetection.getContrastRatio(white, black);
    try testing.expect(contrast > 20.0); // Should be close to 21:1 (maximum contrast)

    // Same color should have 1:1 contrast
    const same_contrast = BackgroundDetection.getContrastRatio(white, white);
    try testing.expect(same_contrast >= 1.0 and same_contrast <= 1.1);
}

test "WCAG contrast compliance" {
    const testing = std.testing;

    const white = Color.fromRGB(255, 255, 255);
    const black = Color.fromRGB(0, 0, 0);

    // White on black should meet all WCAG levels
    try testing.expect(BackgroundDetection.meetsWCAGContrast(white, black, .AA_normal));
    try testing.expect(BackgroundDetection.meetsWCAGContrast(white, black, .AA_large));
    try testing.expect(BackgroundDetection.meetsWCAGContrast(white, black, .AAA_normal));
    try testing.expect(BackgroundDetection.meetsWCAGContrast(white, black, .AAA_large));

    // Low contrast colors should fail strict requirements
    const light_gray = Color.fromRGB(200, 200, 200);
    const medium_gray = Color.fromRGB(128, 128, 128);
    try testing.expect(!BackgroundDetection.meetsWCAGContrast(light_gray, medium_gray, .AAA_normal));
}

test "foreground color suggestion" {
    const testing = std.testing;

    const dark_bg = Color.fromRGB(32, 32, 32);
    const suggested_fg = BackgroundDetection.suggestForegroundColor(dark_bg);
    try testing.expect(BackgroundDetection.isLight(suggested_fg)); // Should suggest light text

    const light_bg = Color.fromRGB(240, 240, 240);
    const suggested_fg2 = BackgroundDetection.suggestForegroundColor(light_bg);
    try testing.expect(BackgroundDetection.isDark(suggested_fg2)); // Should suggest dark text
}

test "color response parsing" {
    const testing = std.testing;

    // Test hex format response
    const hex_response = "\x1b]11;#ff0000\x07";
    const hex_color = try BackgroundDetection.parseColorResponse(hex_response);
    try testing.expect(hex_color.r >> 8 == 255);
    try testing.expect(hex_color.g >> 8 == 0);
    try testing.expect(hex_color.b >> 8 == 0);

    // Test XParseColor RGB format response
    const rgb_response = "\x1b]11;rgb:ff00/8000/4000\x07";
    const rgb_color = try BackgroundDetection.parseColorResponse(rgb_response);
    try testing.expect(rgb_color.r == 0xff00);
    try testing.expect(rgb_color.g == 0x8000);
    try testing.expect(rgb_color.b == 0x4000);

    // Test invalid responses
    try testing.expectError(error.InvalidResponse, BackgroundDetection.parseColorResponse("invalid"));
    try testing.expectError(error.InvalidResponse, BackgroundDetection.parseColorResponse("\x1b]11"));
}

test "background manager functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var manager = BackgroundManager.init(allocator);

    // Initially no colors detected
    try testing.expect(manager.getBackground() == null);
    try testing.expect(manager.getForeground() == null);
    try testing.expect(manager.hasDarkTheme() == null);

    // Simulate processing a background color response
    const bg_response = "\x1b]11;#2d2d2d\x07"; // Dark background
    try manager.processColorResponse(bg_response);

    try testing.expect(manager.getBackground() != null);
    try testing.expect(manager.hasDarkTheme() == true);

    const optimal_text = manager.getOptimalTextColor();
    try testing.expect(optimal_text != null);
    try testing.expect(BackgroundDetection.isLight(optimal_text.?)); // Should be light text for dark bg
}

test "adaptive color scheme generation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var manager = BackgroundManager.init(allocator);

    // Test with dark background
    const dark_bg_response = "\x1b]11;#1a1a1a\x07";
    try manager.processColorResponse(dark_bg_response);

    const dark_scheme = manager.getAdaptiveColors();
    try testing.expect(BackgroundDetection.isLight(dark_scheme.primary)); // Primary text should be light

    // Test with light background
    manager.detected_bg = Color.fromRGB(240, 240, 240);
    const light_scheme = manager.getAdaptiveColors();
    try testing.expect(BackgroundDetection.isDark(light_scheme.primary)); // Primary text should be dark

    // Test default scheme (no background detected)
    manager.detected_bg = null;
    const default_scheme = manager.getAdaptiveColors();
    // Default scheme should have reasonable values
    try testing.expect(default_scheme.primary.r > 0 and default_scheme.primary.r < 0xFFFF);
}

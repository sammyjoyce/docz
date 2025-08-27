//! Color Scheme Definition and Management
//! Represents a complete color scheme with all semantic colors

const std = @import("std");

/// RGB color representation
pub const RGB = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RGB {
        return .{ .r = r, .g = g, .b = b };
    }

    /// Convert to HSL for calculations
    pub fn toHSL(self: RGB) HSL {
        const r_norm = @as(f32, @floatFromInt(self.r)) / 255.0;
        const g_norm = @as(f32, @floatFromInt(self.g)) / 255.0;
        const b_norm = @as(f32, @floatFromInt(self.b)) / 255.0;

        const max = @max(r_norm, @max(g_norm, b_norm));
        const min = @min(r_norm, @min(g_norm, b_norm));
        const delta = max - min;

        var h: f32 = 0;
        var s: f32 = 0;
        const l = (max + min) / 2.0;

        if (delta > 0) {
            s = if (l < 0.5) delta / (max + min) else delta / (2 - max - min);

            if (max == r_norm) {
                h = ((g_norm - b_norm) / delta) + if (g_norm < b_norm) 6 else 0;
            } else if (max == g_norm) {
                h = ((b_norm - r_norm) / delta) + 2;
            } else {
                h = ((r_norm - g_norm) / delta) + 4;
            }
            h = h / 6.0;
        }

        return .{ .h = h * 360, .s = s, .l = l };
    }

    /// Convert to hex string
    pub fn toHex(self: RGB, allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, "#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b });
    }

    /// Parse from hex string
    pub fn fromHex(hex: []const u8) !RGB {
        var clean_hex = hex;
        if (hex[0] == '#') {
            clean_hex = hex[1..];
        }

        if (clean_hex.len != 6) return error.InvalidHexColor;

        const r = try std.fmt.parseInt(u8, clean_hex[0..2], 16);
        const g = try std.fmt.parseInt(u8, clean_hex[2..4], 16);
        const b = try std.fmt.parseInt(u8, clean_hex[4..6], 16);

        return RGB.init(r, g, b);
    }
};

/// HSL color representation for calculations
pub const HSL = struct {
    h: f32, // Hue (0-360)
    s: f32, // Saturation (0-1)
    l: f32, // Lightness (0-1)

    pub fn toRGB(self: HSL) RGB {
        const h_norm = self.h / 360.0;

        if (self.s == 0) {
            const v = @as(u8, @intFromFloat(self.l * 255));
            return RGB.init(v, v, v);
        }

        const q = if (self.l < 0.5) self.l * (1 + self.s) else self.l + self.s - (self.l * self.s);
        const p = 2 * self.l - q;

        const r = hueToRGB(p, q, h_norm + 1.0 / 3.0);
        const g = hueToRGB(p, q, h_norm);
        const b = hueToRGB(p, q, h_norm - 1.0 / 3.0);

        return RGB.init(
            @as(u8, @intFromFloat(r * 255)),
            @as(u8, @intFromFloat(g * 255)),
            @as(u8, @intFromFloat(b * 255)),
        );
    }

    fn hueToRGB(p: f32, q: f32, t_raw: f32) f32 {
        var t = t_raw;
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1.0 / 6.0) return p + (q - p) * 6 * t;
        if (t < 0.5) return q;
        if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6;
        return p;
    }
};

/// Color with multiple fallback representations
pub const Color = struct {
    rgb: RGB,
    ansi256: u8,
    ansi16: u8,
    name: []const u8,

    pub fn init(name: []const u8, rgb: RGB, ansi256: u8, ansi16: u8) Color {
        return .{
            .rgb = rgb,
            .ansi256 = ansi256,
            .ansi16 = ansi16,
            .name = name,
        };
    }
};

/// Complete color scheme
pub const ColorScheme = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    description: []const u8,
    author: []const u8,
    version: []const u8,

    // Core colors
    background: Color,
    foreground: Color,
    cursor: Color,
    selection: Color,

    // ANSI colors
    black: Color,
    red: Color,
    green: Color,
    yellow: Color,
    blue: Color,
    magenta: Color,
    cyan: Color,
    white: Color,

    // Bright ANSI colors
    bright_black: Color,
    bright_red: Color,
    bright_green: Color,
    bright_yellow: Color,
    bright_blue: Color,
    bright_magenta: Color,
    bright_cyan: Color,
    bright_white: Color,

    // Semantic colors
    primary: Color,
    secondary: Color,
    tertiary: Color,
    success: Color,
    warning: Color,
    error_color: Color,
    info: Color,

    // UI colors
    border: Color,
    shadow: Color,
    highlight: Color,
    dimmed: Color,
    accent: Color,

    // Additional metadata
    is_dark: bool,
    contrast_ratio: f32,
    wcag_level: []const u8, // "AA", "AAA", or "Fail"

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .name = "",
            .description = "",
            .author = "",
            .version = "1.0.0",
            .background = Color.init("background", RGB.init(0, 0, 0), 0, 0),
            .foreground = Color.init("foreground", RGB.init(255, 255, 255), 15, 15),
            .cursor = Color.init("cursor", RGB.init(255, 255, 255), 15, 15),
            .selection = Color.init("selection", RGB.init(64, 64, 128), 17, 4),
            .black = Color.init("black", RGB.init(0, 0, 0), 0, 0),
            .red = Color.init("red", RGB.init(187, 0, 0), 1, 1),
            .green = Color.init("green", RGB.init(0, 187, 0), 2, 2),
            .yellow = Color.init("yellow", RGB.init(187, 187, 0), 3, 3),
            .blue = Color.init("blue", RGB.init(0, 0, 187), 4, 4),
            .magenta = Color.init("magenta", RGB.init(187, 0, 187), 5, 5),
            .cyan = Color.init("cyan", RGB.init(0, 187, 187), 6, 6),
            .white = Color.init("white", RGB.init(187, 187, 187), 7, 7),
            .bright_black = Color.init("bright_black", RGB.init(85, 85, 85), 8, 8),
            .bright_red = Color.init("bright_red", RGB.init(255, 85, 85), 9, 9),
            .bright_green = Color.init("bright_green", RGB.init(85, 255, 85), 10, 10),
            .bright_yellow = Color.init("bright_yellow", RGB.init(255, 255, 85), 11, 11),
            .bright_blue = Color.init("bright_blue", RGB.init(85, 85, 255), 12, 12),
            .bright_magenta = Color.init("bright_magenta", RGB.init(255, 85, 255), 13, 13),
            .bright_cyan = Color.init("bright_cyan", RGB.init(85, 255, 255), 14, 14),
            .bright_white = Color.init("bright_white", RGB.init(255, 255, 255), 15, 15),
            .primary = Color.init("primary", RGB.init(0, 123, 255), 33, 12),
            .secondary = Color.init("secondary", RGB.init(108, 117, 125), 102, 8),
            .tertiary = Color.init("tertiary", RGB.init(173, 181, 189), 145, 7),
            .success = Color.init("success", RGB.init(40, 167, 69), 34, 2),
            .warning = Color.init("warning", RGB.init(255, 193, 7), 220, 11),
            .error_color = Color.init("error", RGB.init(220, 53, 69), 196, 1),
            .info = Color.init("info", RGB.init(23, 162, 184), 38, 6),
            .border = Color.init("border", RGB.init(108, 117, 125), 102, 8),
            .shadow = Color.init("shadow", RGB.init(0, 0, 0), 0, 0),
            .highlight = Color.init("highlight", RGB.init(255, 255, 0), 226, 11),
            .dimmed = Color.init("dimmed", RGB.init(108, 117, 125), 102, 8),
            .accent = Color.init("accent", RGB.init(0, 123, 255), 33, 12),
            .is_dark = true,
            .contrast_ratio = 7.0,
            .wcag_level = "AA",
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Create default theme
    pub fn createDefault(allocator: std.mem.Allocator) !*Self {
        const theme = try Self.init(allocator);
        theme.name = "Default";
        theme.description = "Standard balanced theme";
        theme.author = "System";
        return theme;
    }

    /// Create dark theme
    pub fn createDark(allocator: std.mem.Allocator) !*Self {
        const theme = try Self.init(allocator);
        theme.name = "Dark";
        theme.description = "Dark mode theme";
        theme.author = "System";
        theme.background = Color.init("background", RGB.init(30, 30, 30), 234, 0);
        theme.foreground = Color.init("foreground", RGB.init(220, 220, 220), 253, 15);
        theme.is_dark = true;
        return theme;
    }

    /// Create light theme
    pub fn createLight(allocator: std.mem.Allocator) !*Self {
        const theme = try Self.init(allocator);
        theme.name = "Light";
        theme.description = "Light mode theme";
        theme.author = "System";
        theme.background = Color.init("background", RGB.init(255, 255, 255), 231, 15);
        theme.foreground = Color.init("foreground", RGB.init(35, 35, 35), 235, 0);
        theme.is_dark = false;
        return theme;
    }

    /// Create high contrast theme
    pub fn createHighContrast(allocator: std.mem.Allocator) !*Self {
        const theme = try Self.init(allocator);
        theme.name = "High Contrast";
        theme.description = "Maximum contrast for accessibility";
        theme.author = "System";
        theme.background = Color.init("background", RGB.init(0, 0, 0), 0, 0);
        theme.foreground = Color.init("foreground", RGB.init(255, 255, 255), 231, 15);
        theme.contrast_ratio = 21.0;
        theme.wcag_level = "AAA";
        return theme;
    }

    /// Create Solarized Dark theme
    pub fn createSolarizedDark(allocator: std.mem.Allocator) !*Self {
        const theme = try Self.init(allocator);
        theme.name = "Solarized Dark";
        theme.description = "Popular Solarized dark variant";
        theme.author = "Ethan Schoonover";
        theme.background = Color.init("background", RGB.init(0, 43, 54), 234, 0);
        theme.foreground = Color.init("foreground", RGB.init(131, 148, 150), 245, 7);
        theme.is_dark = true;
        return theme;
    }

    /// Create Solarized Light theme
    pub fn createSolarizedLight(allocator: std.mem.Allocator) !*Self {
        const theme = try Self.init(allocator);
        theme.name = "Solarized Light";
        theme.description = "Popular Solarized light variant";
        theme.author = "Ethan Schoonover";
        theme.background = Color.init("background", RGB.init(253, 246, 227), 230, 15);
        theme.foreground = Color.init("foreground", RGB.init(101, 123, 131), 244, 8);
        theme.is_dark = false;
        return theme;
    }

    /// Create empty theme for customization
    pub fn createEmpty(allocator: std.mem.Allocator) !*Self {
        return try Self.init(allocator);
    }

    /// Serialize to ZON format
    pub fn toZon(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        const writer = buffer.writer();

        try writer.writeAll(".{\n");
        try writer.print("    .name = \"{s}\",\n", .{self.name});
        try writer.print("    .description = \"{s}\",\n", .{self.description});
        try writer.print("    .author = \"{s}\",\n", .{self.author});
        try writer.print("    .version = \"{s}\",\n", .{self.version});
        try writer.print("    .is_dark = {},\n", .{self.is_dark});

        // Write colors
        try writer.writeAll("    .colors = .{\n");
        try self.writeColorToZon(writer, "background", self.background);
        try self.writeColorToZon(writer, "foreground", self.foreground);
        try self.writeColorToZon(writer, "cursor", self.cursor);
        try self.writeColorToZon(writer, "selection", self.selection);
        // ... write all other colors
        try writer.writeAll("    },\n");

        try writer.writeAll("}\n");

        return buffer.toOwnedSlice();
    }

    fn writeColorToZon(self: *Self, writer: anytype, name: []const u8, color: Color) !void {
        _ = self;
        try writer.print("        .{s} = .{{ .r = {}, .g = {}, .b = {}, .ansi256 = {}, .ansi16 = {} }},\n", .{
            name,
            color.rgb.r,
            color.rgb.g,
            color.rgb.b,
            color.ansi256,
            color.ansi16,
        });
    }

    /// Parse from ZON format
    pub fn fromZon(allocator: std.mem.Allocator, content: []const u8) !*Self {
        _ = content;
        // TODO: Implement ZON parsing
        return try Self.init(allocator);
    }

    /// Calculate contrast ratio between two colors
    pub fn calculateContrast(color1: RGB, color2: RGB) f32 {
        const lum1 = calculateLuminance(color1);
        const lum2 = calculateLuminance(color2);

        const lighter = @max(lum1, lum2);
        const darker = @min(lum1, lum2);

        return (lighter + 0.05) / (darker + 0.05);
    }

    fn calculateLuminance(color: RGB) f32 {
        const r = gammaCorrect(@as(f32, @floatFromInt(color.r)) / 255.0);
        const g = gammaCorrect(@as(f32, @floatFromInt(color.g)) / 255.0);
        const b = gammaCorrect(@as(f32, @floatFromInt(color.b)) / 255.0);

        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    fn gammaCorrect(value: f32) f32 {
        if (value <= 0.03928) {
            return value / 12.92;
        } else {
            return std.math.pow(f32, (value + 0.055) / 1.055, 2.4);
        }
    }
};

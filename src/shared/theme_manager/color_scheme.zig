//! Color Scheme Definition and Management
//! Represents a complete color scheme with all semantic colors

const std = @import("std");
const color_mod = @import("../term/ansi/color.zig");

// Re-export color types from the primary color module
pub const RGB = color_mod.RgbColor;
pub const HSL = color_mod.Hsl;

/// Color with multiple fallback representations for terminal compatibility
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
    brightBlack: Color,
    brightRed: Color,
    brightGreen: Color,
    brightYellow: Color,
    brightBlue: Color,
    brightMagenta: Color,
    brightCyan: Color,
    brightWhite: Color,

    // Semantic colors
    primary: Color,
    secondary: Color,
    tertiary: Color,
    success: Color,
    warning: Color,
    errorColor: Color,
    info: Color,

    // UI colors
    border: Color,
    shadow: Color,
    highlight: Color,
    dimmed: Color,
    accent: Color,

    // Additional metadata
    isDark: bool,
    contrastRatio: f32,
    wcagLevel: []const u8, // "AA", "AAA", or "Fail"

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
            .brightBlack = Color.init("bright_black", RGB.init(85, 85, 85), 8, 8),
            .brightRed = Color.init("bright_red", RGB.init(255, 85, 85), 9, 9),
            .brightGreen = Color.init("bright_green", RGB.init(85, 255, 85), 10, 10),
            .brightYellow = Color.init("bright_yellow", RGB.init(255, 255, 85), 11, 11),
            .brightBlue = Color.init("bright_blue", RGB.init(85, 85, 255), 12, 12),
            .brightMagenta = Color.init("bright_magenta", RGB.init(255, 85, 255), 13, 13),
            .brightCyan = Color.init("bright_cyan", RGB.init(85, 255, 255), 14, 14),
            .brightWhite = Color.init("bright_white", RGB.init(255, 255, 255), 15, 15),
            .primary = Color.init("primary", RGB.init(0, 123, 255), 33, 12),
            .secondary = Color.init("secondary", RGB.init(108, 117, 125), 102, 8),
            .tertiary = Color.init("tertiary", RGB.init(173, 181, 189), 145, 7),
            .success = Color.init("success", RGB.init(40, 167, 69), 34, 2),
            .warning = Color.init("warning", RGB.init(255, 193, 7), 220, 11),
            .errorColor = Color.init("error", RGB.init(220, 53, 69), 196, 1),
            .info = Color.init("info", RGB.init(23, 162, 184), 38, 6),
            .border = Color.init("border", RGB.init(108, 117, 125), 102, 8),
            .shadow = Color.init("shadow", RGB.init(0, 0, 0), 0, 0),
            .highlight = Color.init("highlight", RGB.init(255, 255, 0), 226, 11),
            .dimmed = Color.init("dimmed", RGB.init(108, 117, 125), 102, 8),
            .accent = Color.init("accent", RGB.init(0, 123, 255), 33, 12),
            .isDark = true,
            .contrastRatio = 7.0,
            .wcagLevel = "AA",
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
        theme.isDark = true;
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
        theme.isDark = false;
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
        theme.contrastRatio = 21.0;
        theme.wcagLevel = "AAA";
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
        theme.isDark = true;
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
        theme.isDark = false;
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
        try writer.print("    .isDark = {},\n", .{self.isDark});

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

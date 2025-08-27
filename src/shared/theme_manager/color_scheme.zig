//! Color Scheme Definition and Management
//! Represents a complete color scheme with all semantic colors

const std = @import("std");
const Color = @import("color.zig").Color;

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
            .background = Color.fromRgb("background", 0, 0, 0, 1.0),
            .foreground = Color.fromRgb("foreground", 255, 255, 255, 1.0),
            .cursor = Color.fromRgb("cursor", 255, 255, 255, 1.0),
            .selection = Color.fromRgb("selection", 64, 64, 128, 1.0),
            .black = Color.fromRgb("black", 0, 0, 0, 1.0),
            .red = Color.fromRgb("red", 187, 0, 0, 1.0),
            .green = Color.fromRgb("green", 0, 187, 0, 1.0),
            .yellow = Color.fromRgb("yellow", 187, 187, 0, 1.0),
            .blue = Color.fromRgb("blue", 0, 0, 187, 1.0),
            .magenta = Color.fromRgb("magenta", 187, 0, 187, 1.0),
            .cyan = Color.fromRgb("cyan", 0, 187, 187, 1.0),
            .white = Color.fromRgb("white", 187, 187, 187, 1.0),
            .brightBlack = Color.fromRgb("bright_black", 85, 85, 85, 1.0),
            .brightRed = Color.fromRgb("bright_red", 255, 85, 85, 1.0),
            .brightGreen = Color.fromRgb("bright_green", 85, 255, 85, 1.0),
            .brightYellow = Color.fromRgb("bright_yellow", 255, 255, 85, 1.0),
            .brightBlue = Color.fromRgb("bright_blue", 85, 85, 255, 1.0),
            .brightMagenta = Color.fromRgb("bright_magenta", 255, 85, 255, 1.0),
            .brightCyan = Color.fromRgb("bright_cyan", 85, 255, 255, 1.0),
            .brightWhite = Color.fromRgb("bright_white", 255, 255, 255, 1.0),
            .primary = Color.fromRgb("primary", 0, 123, 255, 1.0),
            .secondary = Color.fromRgb("secondary", 108, 117, 125, 1.0),
            .tertiary = Color.fromRgb("tertiary", 173, 181, 189, 1.0),
            .success = Color.fromRgb("success", 40, 167, 69, 1.0),
            .warning = Color.fromRgb("warning", 255, 193, 7, 1.0),
            .errorColor = Color.fromRgb("error", 220, 53, 69, 1.0),
            .info = Color.fromRgb("info", 23, 162, 184, 1.0),
            .border = Color.fromRgb("border", 108, 117, 125, 1.0),
            .shadow = Color.fromRgb("shadow", 0, 0, 0, 1.0),
            .highlight = Color.fromRgb("highlight", 255, 255, 0, 1.0),
            .dimmed = Color.fromRgb("dimmed", 108, 117, 125, 1.0),
            .accent = Color.fromRgb("accent", 0, 123, 255, 1.0),
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
        theme.background = Color.fromRgb("background", 30, 30, 30, 1.0);
        theme.foreground = Color.fromRgb("foreground", 220, 220, 220, 1.0);
        theme.isDark = true;
        return theme;
    }

    /// Create light theme
    pub fn createLight(allocator: std.mem.Allocator) !*Self {
        const theme = try Self.init(allocator);
        theme.name = "Light";
        theme.description = "Light mode theme";
        theme.author = "System";
        theme.background = Color.fromRgb("background", 255, 255, 255, 1.0);
        theme.foreground = Color.fromRgb("foreground", 35, 35, 35, 1.0);
        theme.isDark = false;
        return theme;
    }

    /// Create high contrast theme
    pub fn createHighContrast(allocator: std.mem.Allocator) !*Self {
        const theme = try Self.init(allocator);
        theme.name = "High Contrast";
        theme.description = "Maximum contrast for accessibility";
        theme.author = "System";
        theme.background = Color.fromRgb("background", 0, 0, 0, 1.0);
        theme.foreground = Color.fromRgb("foreground", 255, 255, 255, 1.0);
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
        theme.background = Color.fromRgb("background", 0, 43, 54, 1.0);
        theme.foreground = Color.fromRgb("foreground", 131, 148, 150, 1.0);
        theme.isDark = true;
        return theme;
    }

    /// Create Solarized Light theme
    pub fn createSolarizedLight(allocator: std.mem.Allocator) !*Self {
        const theme = try Self.init(allocator);
        theme.name = "Solarized Light";
        theme.description = "Popular Solarized light variant";
        theme.author = "Ethan Schoonover";
        theme.background = Color.fromRgb("background", 253, 246, 227, 1.0);
        theme.foreground = Color.fromRgb("foreground", 101, 123, 131, 1.0);
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
        try writer.print("        .{s} = .{{ .name = \"{s}\", .r = {}, .g = {}, .b = {}, .alpha = {} }},\n", .{
            name,
            color.name,
            color.rgb.r,
            color.rgb.g,
            color.rgb.b,
            color.alpha,
        });
    }

    /// Parse from ZON format
    pub fn fromZon(allocator: std.mem.Allocator, content: []const u8) !*Self {
        _ = content;
        // TODO: Implement ZON parsing
        return try Self.init(allocator);
    }

    /// Calculate contrast ratio between two colors
    pub fn calculateContrast(color1: Color, color2: Color) f32 {
        return color1.contrastRatio(color2);
    }
};

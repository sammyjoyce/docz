//! Color Scheme Definition and Management
//! Represents a complete color scheme with all semantic colors

const std = @import("std");
const ThemeColor = @import("color.zig");
const Color = ThemeColor.Color;
pub const RGB = ThemeColor.Rgb;

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
    focus: Color,
    subtle: Color,
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
            .focus = Color.fromRgb("focus", 0, 123, 255, 1.0),
            .subtle = Color.fromRgb("subtle", 108, 117, 125, 1.0),
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
        try writer.print("    .contrastRatio = {d},\n", .{self.contrastRatio});
        try writer.print("    .wcagLevel = \"{s}\",\n", .{self.wcagLevel});

        // Write colors
        try writer.writeAll("    .colors = .{\n");

        // Core colors
        try self.writeColorToZon(writer, "background", self.background);
        try self.writeColorToZon(writer, "foreground", self.foreground);
        try self.writeColorToZon(writer, "cursor", self.cursor);
        try self.writeColorToZon(writer, "selection", self.selection);

        // ANSI colors
        try self.writeColorToZon(writer, "black", self.black);
        try self.writeColorToZon(writer, "red", self.red);
        try self.writeColorToZon(writer, "green", self.green);
        try self.writeColorToZon(writer, "yellow", self.yellow);
        try self.writeColorToZon(writer, "blue", self.blue);
        try self.writeColorToZon(writer, "magenta", self.magenta);
        try self.writeColorToZon(writer, "cyan", self.cyan);
        try self.writeColorToZon(writer, "white", self.white);

        // Bright ANSI colors
        try self.writeColorToZon(writer, "brightBlack", self.brightBlack);
        try self.writeColorToZon(writer, "brightRed", self.brightRed);
        try self.writeColorToZon(writer, "brightGreen", self.brightGreen);
        try self.writeColorToZon(writer, "brightYellow", self.brightYellow);
        try self.writeColorToZon(writer, "brightBlue", self.brightBlue);
        try self.writeColorToZon(writer, "brightMagenta", self.brightMagenta);
        try self.writeColorToZon(writer, "brightCyan", self.brightCyan);
        try self.writeColorToZon(writer, "brightWhite", self.brightWhite);

        // Semantic colors
        try self.writeColorToZon(writer, "primary", self.primary);
        try self.writeColorToZon(writer, "secondary", self.secondary);
        try self.writeColorToZon(writer, "tertiary", self.tertiary);
        try self.writeColorToZon(writer, "success", self.success);
        try self.writeColorToZon(writer, "warning", self.warning);
        try self.writeColorToZon(writer, "errorColor", self.errorColor);
        try self.writeColorToZon(writer, "info", self.info);

        // UI colors
        try self.writeColorToZon(writer, "border", self.border);
        try self.writeColorToZon(writer, "shadow", self.shadow);
        try self.writeColorToZon(writer, "highlight", self.highlight);
        try self.writeColorToZon(writer, "dimmed", self.dimmed);
        try self.writeColorToZon(writer, "accent", self.accent);

        try writer.writeAll("    },\n");
        try writer.writeAll("}\n");

        return buffer.toOwnedSlice();
    }

    fn writeColorToZon(self: *Self, writer: anytype, name: []const u8, color: Color) !void {
        _ = self;
        const rgb = color.rgb();
        try writer.print("        .{s} = .{{ .name = \"{s}\", .r = {}, .g = {}, .b = {}, .alpha = {} }},\n", .{
            name,
            color.name,
            rgb.r,
            rgb.g,
            rgb.b,
            color.alpha,
        });
    }

    /// Parse from ZON format
    pub fn fromZon(allocator: std.mem.Allocator, content: []const u8) !*Self {
        // Define structs to match the ZON format
        const ZonColor = struct {
            name: []const u8,
            r: u8,
            g: u8,
            b: u8,
            alpha: f32 = 1.0,
        };

        const ZonColors = struct {
            background: ZonColor,
            foreground: ZonColor,
            cursor: ZonColor,
            selection: ZonColor,
            black: ZonColor,
            red: ZonColor,
            green: ZonColor,
            yellow: ZonColor,
            blue: ZonColor,
            magenta: ZonColor,
            cyan: ZonColor,
            white: ZonColor,
            brightBlack: ZonColor,
            brightRed: ZonColor,
            brightGreen: ZonColor,
            brightYellow: ZonColor,
            brightBlue: ZonColor,
            brightMagenta: ZonColor,
            brightCyan: ZonColor,
            brightWhite: ZonColor,
            focus: ZonColor,
            subtle: ZonColor,
            tertiary: ZonColor,
            success: ZonColor,
            warning: ZonColor,
            errorColor: ZonColor,
            info: ZonColor,
            border: ZonColor,
            shadow: ZonColor,
            highlight: ZonColor,
            dimmed: ZonColor,
            accent: ZonColor,
        };

        const ZonTheme = struct {
            name: []const u8 = "",
            description: []const u8 = "",
            author: []const u8 = "",
            version: []const u8 = "1.0.0",
            isDark: bool = true,
            contrastRatio: f32 = 7.0,
            wcagLevel: []const u8 = "AA",
            colors: ZonColors,
        };

        // Parse the ZON content
        const parsed = try std.zig.parseFromSlice(ZonTheme, allocator, content, .{});
        defer std.zig.parseFree(ZonTheme, allocator, parsed);

        // Create the ColorScheme instance
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Helper to safely dupe strings
        const dupeString = struct {
            fn call(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
                return try alloc.dupe(u8, s);
            }
        }.call;

        // Convert all colors first
        const background = try zonColorToColor(allocator, parsed.colors.background);
        const foreground = try zonColorToColor(allocator, parsed.colors.foreground);
        const cursor = try zonColorToColor(allocator, parsed.colors.cursor);
        const selection = try zonColorToColor(allocator, parsed.colors.selection);
        const black = try zonColorToColor(allocator, parsed.colors.black);
        const red = try zonColorToColor(allocator, parsed.colors.red);
        const green = try zonColorToColor(allocator, parsed.colors.green);
        const yellow = try zonColorToColor(allocator, parsed.colors.yellow);
        const blue = try zonColorToColor(allocator, parsed.colors.blue);
        const magenta = try zonColorToColor(allocator, parsed.colors.magenta);
        const cyan = try zonColorToColor(allocator, parsed.colors.cyan);
        const white = try zonColorToColor(allocator, parsed.colors.white);
        const brightBlack = try zonColorToColor(allocator, parsed.colors.brightBlack);
        const brightRed = try zonColorToColor(allocator, parsed.colors.brightRed);
        const brightGreen = try zonColorToColor(allocator, parsed.colors.brightGreen);
        const brightYellow = try zonColorToColor(allocator, parsed.colors.brightYellow);
        const brightBlue = try zonColorToColor(allocator, parsed.colors.brightBlue);
        const brightMagenta = try zonColorToColor(allocator, parsed.colors.brightMagenta);
        const brightCyan = try zonColorToColor(allocator, parsed.colors.brightCyan);
        const brightWhite = try zonColorToColor(allocator, parsed.colors.brightWhite);
        const focus = try zonColorToColor(allocator, parsed.colors.focus);
        const subtle = try zonColorToColor(allocator, parsed.colors.subtle);
        const tertiary = try zonColorToColor(allocator, parsed.colors.tertiary);
        const success = try zonColorToColor(allocator, parsed.colors.success);
        const warning = try zonColorToColor(allocator, parsed.colors.warning);
        const errorColor = try zonColorToColor(allocator, parsed.colors.errorColor);
        const info = try zonColorToColor(allocator, parsed.colors.info);
        const border = try zonColorToColor(allocator, parsed.colors.border);
        const shadow = try zonColorToColor(allocator, parsed.colors.shadow);
        const highlight = try zonColorToColor(allocator, parsed.colors.highlight);
        const dimmed = try zonColorToColor(allocator, parsed.colors.dimmed);
        const accent = try zonColorToColor(allocator, parsed.colors.accent);

        self.* = .{
            .allocator = allocator,
            .name = try dupeString(allocator, parsed.name),
            .description = try dupeString(allocator, parsed.description),
            .author = try dupeString(allocator, parsed.author),
            .version = try dupeString(allocator, parsed.version),
            .isDark = parsed.isDark,
            .contrastRatio = parsed.contrastRatio,
            .wcagLevel = try dupeString(allocator, parsed.wcagLevel),

            // Use the converted colors
            .background = background,
            .foreground = foreground,
            .cursor = cursor,
            .selection = selection,
            .black = black,
            .red = red,
            .green = green,
            .yellow = yellow,
            .blue = blue,
            .magenta = magenta,
            .cyan = cyan,
            .white = white,
            .brightBlack = brightBlack,
            .brightRed = brightRed,
            .brightGreen = brightGreen,
            .brightYellow = brightYellow,
            .brightBlue = brightBlue,
            .brightMagenta = brightMagenta,
            .brightCyan = brightCyan,
            .brightWhite = brightWhite,
            .focus = focus,
            .subtle = subtle,
            .tertiary = tertiary,
            .success = success,
            .warning = warning,
            .errorColor = errorColor,
            .info = info,
            .border = border,
            .shadow = shadow,
            .highlight = highlight,
            .dimmed = dimmed,
            .accent = accent,
        };

        return self;
    }

    /// Helper function to convert ZonColor to Color
    fn zonColorToColor(allocator: std.mem.Allocator, zonColor: anytype) Color {
        const name = try allocator.dupe(u8, zonColor.name);
        return Color.fromRgb(name, zonColor.r, zonColor.g, zonColor.b, zonColor.alpha);
    }

    /// Calculate contrast ratio between two colors
    pub fn calculateContrast(color1: RGB, color2: RGB) f32 {
        // WCAG relative luminance contrast ratio
        const rf1: f32 = gamma(@as(f32, @floatFromInt(color1.r)) / 255.0);
        const gf1: f32 = gamma(@as(f32, @floatFromInt(color1.g)) / 255.0);
        const bf1: f32 = gamma(@as(f32, @floatFromInt(color1.b)) / 255.0);
        const l1 = 0.2126 * rf1 + 0.7152 * gf1 + 0.0722 * bf1;

        const rf2: f32 = gamma(@as(f32, @floatFromInt(color2.r)) / 255.0);
        const gf2: f32 = gamma(@as(f32, @floatFromInt(color2.g)) / 255.0);
        const bf2: f32 = gamma(@as(f32, @floatFromInt(color2.b)) / 255.0);
        const l2 = 0.2126 * rf2 + 0.7152 * gf2 + 0.0722 * bf2;

        const hi = @max(l1, l2);
        const lo = @min(l1, l2);
        return (hi + 0.05) / (lo + 0.05);
    }

    fn gamma(v: f32) f32 {
        if (v <= 0.03928) return v / 12.92;
        return std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
    }
};

test "ZON parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const zonContent =
        \\.{
        \\    .name = "Test Theme",
        \\    .description = "A test theme",
        \\    .author = "Test Author",
        \\    .version = "1.0.0",
        \\    .isDark = true,
        \\    .contrastRatio = 7.0,
        \\    .wcagLevel = "AA",
        \\    .colors = .{
        \\        .background = .{ .name = "background", .r = 30, .g = 30, .b = 30, .alpha = 1.0 },
        \\        .foreground = .{ .name = "foreground", .r = 220, .g = 220, .b = 220, .alpha = 1.0 },
        \\        .cursor = .{ .name = "cursor", .r = 255, .g = 255, .b = 255, .alpha = 1.0 },
        \\        .selection = .{ .name = "selection", .r = 64, .g = 64, .b = 128, .alpha = 1.0 },
        \\        .black = .{ .name = "black", .r = 0, .g = 0, .b = 0, .alpha = 1.0 },
        \\        .red = .{ .name = "red", .r = 187, .g = 0, .b = 0, .alpha = 1.0 },
        \\        .green = .{ .name = "green", .r = 0, .g = 187, .b = 0, .alpha = 1.0 },
        \\        .yellow = .{ .name = "yellow", .r = 187, .g = 187, .b = 0, .alpha = 1.0 },
        \\        .blue = .{ .name = "blue", .r = 0, .g = 0, .b = 187, .alpha = 1.0 },
        \\        .magenta = .{ .name = "magenta", .r = 187, .g = 0, .b = 187, .alpha = 1.0 },
        \\        .cyan = .{ .name = "cyan", .r = 0, .g = 187, .b = 187, .alpha = 1.0 },
        \\        .white = .{ .name = "white", .r = 187, .g = 187, .b = 187, .alpha = 1.0 },
        \\        .brightBlack = .{ .name = "bright_black", .r = 85, .g = 85, .b = 85, .alpha = 1.0 },
        \\        .brightRed = .{ .name = "bright_red", .r = 255, .g = 85, .b = 85, .alpha = 1.0 },
        \\        .brightGreen = .{ .name = "bright_green", .r = 85, .g = 255, .b = 85, .alpha = 1.0 },
        \\        .brightYellow = .{ .name = "bright_yellow", .r = 255, .g = 255, .b = 85, .alpha = 1.0 },
        \\        .brightBlue = .{ .name = "bright_blue", .r = 85, .g = 85, .b = 255, .alpha = 1.0 },
        \\        .brightMagenta = .{ .name = "bright_magenta", .r = 255, .g = 85, .b = 255, .alpha = 1.0 },
        \\        .brightCyan = .{ .name = "bright_cyan", .r = 85, .g = 255, .b = 255, .alpha = 1.0 },
        \\        .brightWhite = .{ .name = "bright_white", .r = 255, .g = 255, .b = 255, .alpha = 1.0 },
        \\        .focus = .{ .name = "focus", .r = 0, .g = 123, .b = 255, .alpha = 1.0 },
        \\        .subtle = .{ .name = "subtle", .r = 108, .g = 117, .b = 125, .alpha = 1.0 },
        \\        .tertiary = .{ .name = "tertiary", .r = 173, .g = 181, .b = 189, .alpha = 1.0 },
        \\        .success = .{ .name = "success", .r = 40, .g = 167, .b = 69, .alpha = 1.0 },
        \\        .warning = .{ .name = "warning", .r = 255, .g = 193, .b = 7, .alpha = 1.0 },
        \\        .errorColor = .{ .name = "error", .r = 220, .g = 53, .b = 69, .alpha = 1.0 },
        \\        .info = .{ .name = "info", .r = 23, .g = 162, .b = 184, .alpha = 1.0 },
        \\        .border = .{ .name = "border", .r = 108, .g = 117, .b = 125, .alpha = 1.0 },
        \\        .shadow = .{ .name = "shadow", .r = 0, .g = 0, .b = 0, .alpha = 1.0 },
        \\        .highlight = .{ .name = "highlight", .r = 255, .g = 255, .b = 0, .alpha = 1.0 },
        \\        .dimmed = .{ .name = "dimmed", .r = 108, .g = 117, .b = 125, .alpha = 1.0 },
        \\        .accent = .{ .name = "accent", .r = 0, .g = 123, .b = 255, .alpha = 1.0 },
        \\    },
        \\}
    ;

    const theme = try ColorScheme.fromZon(allocator, zonContent);
    defer theme.deinit();

    // Verify parsed values
    try testing.expectEqualStrings("Test Theme", theme.name);
    try testing.expectEqualStrings("A test theme", theme.description);
    try testing.expectEqualStrings("Test Author", theme.author);
    try testing.expectEqualStrings("1.0.0", theme.version);
    try testing.expect(theme.isDark);
    try testing.expectEqual(@as(f32, 7.0), theme.contrastRatio);
    try testing.expectEqualStrings("AA", theme.wcagLevel);

    // Verify some colors
    try testing.expectEqual(@as(u8, 30), theme.background.rgb().r);
    try testing.expectEqual(@as(u8, 30), theme.background.rgb().g);
    try testing.expectEqual(@as(u8, 30), theme.background.rgb().b);

    try testing.expectEqual(@as(u8, 220), theme.foreground.rgb().r);
    try testing.expectEqual(@as(u8, 220), theme.foreground.rgb().g);
    try testing.expectEqual(@as(u8, 220), theme.foreground.rgb().b);

    try testing.expectEqual(@as(u8, 0), theme.focus.rgb().r);
    try testing.expectEqual(@as(u8, 123), theme.focus.rgb().g);
    try testing.expectEqual(@as(u8, 255), theme.focus.rgb().b);
}

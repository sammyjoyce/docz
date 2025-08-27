//! Color Palettes and Themes
//! Predefined color palettes and theme management
//! Consolidates palette definitions and theme operations

const std = @import("std");
const types = @import("types.zig");
const conversions = @import("conversions.zig");
const distance = @import("distance.zig");

pub const RGB = types.RGB;
pub const HSL = types.HSL;
pub const Ansi16 = types.Ansi16;
pub const Ansi256 = types.Ansi256;

// === STANDARD PALETTES ===

pub const StandardPalette = struct {
    name: []const u8,
    colors: []const RGB,
    description: []const u8,
};

/// ANSI 16-color palette
pub const ansi16_palette = [_]RGB{
    RGB.init(0, 0, 0), // Black
    RGB.init(205, 49, 49), // Red
    RGB.init(13, 188, 121), // Green
    RGB.init(229, 229, 16), // Yellow
    RGB.init(36, 114, 200), // Blue
    RGB.init(188, 63, 188), // Magenta
    RGB.init(17, 168, 205), // Cyan
    RGB.init(229, 229, 229), // White
    RGB.init(102, 102, 102), // Bright Black
    RGB.init(241, 76, 76), // Bright Red
    RGB.init(35, 209, 139), // Bright Green
    RGB.init(245, 245, 67), // Bright Yellow
    RGB.init(59, 142, 234), // Bright Blue
    RGB.init(214, 112, 214), // Bright Magenta
    RGB.init(41, 184, 219), // Bright Cyan
    RGB.init(255, 255, 255), // Bright White
};

/// Web-safe 216 colors (6x6x6 RGB cube)
pub fn generateWebSafePalette(allocator: std.mem.Allocator) ![]RGB {
    var palette = try allocator.alloc(RGB, 216);
    var index: usize = 0;

    const levels = [_]u8{ 0x00, 0x33, 0x66, 0x99, 0xCC, 0xFF };
    for (levels) |r| {
        for (levels) |g| {
            for (levels) |b| {
                palette[index] = RGB.init(r, g, b);
                index += 1;
            }
        }
    }

    return palette;
}

/// Generate the full ANSI 256-color palette
pub fn generateAnsi256Palette(allocator: std.mem.Allocator) ![]RGB {
    const palette = try allocator.alloc(RGB, 256);

    // 0-15: Basic 16 colors
    for (ansi16_palette, 0..) |color, i| {
        palette[i] = color;
    }

    // 16-231: 216-color cube
    var index: usize = 16;
    const levels = [_]u8{ 0, 95, 135, 175, 215, 255 };
    for (levels) |r| {
        for (levels) |g| {
            for (levels) |b| {
                palette[index] = RGB.init(r, g, b);
                index += 1;
            }
        }
    }

    // 232-255: Grayscale
    for (232..256) |i| {
        const gray = @as(u8, @intCast(8 + (i - 232) * 10));
        palette[i] = RGB.init(gray, gray, gray);
    }

    return palette;
}

// === THEME PALETTES ===

pub const Theme = struct {
    name: []const u8,
    background: RGB,
    foreground: RGB,
    cursor: RGB,
    selection: RGB,

    // ANSI colors
    black: RGB,
    red: RGB,
    green: RGB,
    yellow: RGB,
    blue: RGB,
    magenta: RGB,
    cyan: RGB,
    white: RGB,
    bright_black: RGB,
    bright_red: RGB,
    bright_green: RGB,
    bright_yellow: RGB,
    bright_blue: RGB,
    bright_magenta: RGB,
    bright_cyan: RGB,
    bright_white: RGB,

    // Extended colors
    comment: ?RGB = null,
    keyword: ?RGB = null,
    string: ?RGB = null,
    function: ?RGB = null,
    variable: ?RGB = null,
    constant: ?RGB = null,
    type: ?RGB = null,
    error_color: ?RGB = null,
    warning: ?RGB = null,
    info: ?RGB = null,
};

pub const solarized_dark = Theme{
    .name = "Solarized Dark",
    .background = RGB.init(0, 43, 54),
    .foreground = RGB.init(131, 148, 150),
    .cursor = RGB.init(131, 148, 150),
    .selection = RGB.init(7, 54, 66),

    .black = RGB.init(7, 54, 66),
    .red = RGB.init(220, 50, 47),
    .green = RGB.init(133, 153, 0),
    .yellow = RGB.init(181, 137, 0),
    .blue = RGB.init(38, 139, 210),
    .magenta = RGB.init(211, 54, 130),
    .cyan = RGB.init(42, 161, 152),
    .white = RGB.init(238, 232, 213),
    .bright_black = RGB.init(0, 43, 54),
    .bright_red = RGB.init(203, 75, 22),
    .bright_green = RGB.init(88, 110, 117),
    .bright_yellow = RGB.init(101, 123, 131),
    .bright_blue = RGB.init(131, 148, 150),
    .bright_magenta = RGB.init(108, 113, 196),
    .bright_cyan = RGB.init(147, 161, 161),
    .bright_white = RGB.init(253, 246, 227),

    .comment = RGB.init(88, 110, 117),
    .keyword = RGB.init(133, 153, 0),
    .string = RGB.init(42, 161, 152),
    .function = RGB.init(38, 139, 210),
    .variable = RGB.init(181, 137, 0),
    .constant = RGB.init(211, 54, 130),
    .type = RGB.init(108, 113, 196),
};

pub const solarized_light = Theme{
    .name = "Solarized Light",
    .background = RGB.init(253, 246, 227),
    .foreground = RGB.init(101, 123, 131),
    .cursor = RGB.init(101, 123, 131),
    .selection = RGB.init(238, 232, 213),

    .black = RGB.init(238, 232, 213),
    .red = RGB.init(220, 50, 47),
    .green = RGB.init(133, 153, 0),
    .yellow = RGB.init(181, 137, 0),
    .blue = RGB.init(38, 139, 210),
    .magenta = RGB.init(211, 54, 130),
    .cyan = RGB.init(42, 161, 152),
    .white = RGB.init(7, 54, 66),
    .bright_black = RGB.init(253, 246, 227),
    .bright_red = RGB.init(203, 75, 22),
    .bright_green = RGB.init(147, 161, 161),
    .bright_yellow = RGB.init(131, 148, 150),
    .bright_blue = RGB.init(101, 123, 131),
    .bright_magenta = RGB.init(108, 113, 196),
    .bright_cyan = RGB.init(88, 110, 117),
    .bright_white = RGB.init(0, 43, 54),

    .comment = RGB.init(147, 161, 161),
    .keyword = RGB.init(133, 153, 0),
    .string = RGB.init(42, 161, 152),
    .function = RGB.init(38, 139, 210),
    .variable = RGB.init(181, 137, 0),
    .constant = RGB.init(211, 54, 130),
    .type = RGB.init(108, 113, 196),
};

pub const dracula = Theme{
    .name = "Dracula",
    .background = RGB.init(40, 42, 54),
    .foreground = RGB.init(248, 248, 242),
    .cursor = RGB.init(248, 248, 242),
    .selection = RGB.init(68, 71, 90),

    .black = RGB.init(33, 34, 44),
    .red = RGB.init(255, 85, 85),
    .green = RGB.init(80, 250, 123),
    .yellow = RGB.init(241, 250, 140),
    .blue = RGB.init(139, 233, 253),
    .magenta = RGB.init(255, 121, 198),
    .cyan = RGB.init(139, 233, 253),
    .white = RGB.init(248, 248, 242),
    .bright_black = RGB.init(98, 114, 164),
    .bright_red = RGB.init(255, 110, 110),
    .bright_green = RGB.init(105, 255, 148),
    .bright_yellow = RGB.init(255, 255, 165),
    .bright_blue = RGB.init(164, 255, 255),
    .bright_magenta = RGB.init(255, 146, 223),
    .bright_cyan = RGB.init(164, 255, 255),
    .bright_white = RGB.init(255, 255, 255),

    .comment = RGB.init(98, 114, 164),
    .keyword = RGB.init(255, 121, 198),
    .string = RGB.init(241, 250, 140),
    .function = RGB.init(80, 250, 123),
    .variable = RGB.init(248, 248, 242),
    .constant = RGB.init(189, 147, 249),
    .type = RGB.init(139, 233, 253),
    .error_color = RGB.init(255, 85, 85),
};

pub const monokai = Theme{
    .name = "Monokai",
    .background = RGB.init(39, 40, 34),
    .foreground = RGB.init(248, 248, 242),
    .cursor = RGB.init(248, 248, 240),
    .selection = RGB.init(73, 72, 62),

    .black = RGB.init(39, 40, 34),
    .red = RGB.init(249, 38, 114),
    .green = RGB.init(166, 226, 46),
    .yellow = RGB.init(244, 191, 117),
    .blue = RGB.init(102, 217, 239),
    .magenta = RGB.init(174, 129, 255),
    .cyan = RGB.init(161, 239, 228),
    .white = RGB.init(248, 248, 242),
    .bright_black = RGB.init(117, 113, 94),
    .bright_red = RGB.init(252, 41, 117),
    .bright_green = RGB.init(169, 229, 49),
    .bright_yellow = RGB.init(247, 194, 120),
    .bright_blue = RGB.init(105, 220, 242),
    .bright_magenta = RGB.init(177, 132, 255),
    .bright_cyan = RGB.init(164, 242, 231),
    .bright_white = RGB.init(248, 248, 242),

    .comment = RGB.init(117, 113, 94),
    .keyword = RGB.init(249, 38, 114),
    .string = RGB.init(230, 219, 116),
    .function = RGB.init(166, 226, 46),
    .variable = RGB.init(248, 248, 242),
    .constant = RGB.init(174, 129, 255),
    .type = RGB.init(102, 217, 239),
};

pub const themes = [_]*const Theme{
    &solarized_dark,
    &solarized_light,
    &dracula,
    &monokai,
};

// === PALETTE UTILITIES ===

/// Generate a gradient palette between two colors
pub fn generateGradient(
    allocator: std.mem.Allocator,
    start: RGB,
    end: RGB,
    steps: usize,
) ![]RGB {
    if (steps == 0) return error.InvalidSteps;

    const gradient = try allocator.alloc(RGB, steps);

    if (steps == 1) {
        gradient[0] = start;
        return gradient;
    }

    const dr = @as(f32, @floatFromInt(@as(i16, end.r) - @as(i16, start.r))) / @as(f32, @floatFromInt(steps - 1));
    const dg = @as(f32, @floatFromInt(@as(i16, end.g) - @as(i16, start.g))) / @as(f32, @floatFromInt(steps - 1));
    const db = @as(f32, @floatFromInt(@as(i16, end.b) - @as(i16, start.b))) / @as(f32, @floatFromInt(steps - 1));

    for (gradient, 0..) |*color, i| {
        const fi = @as(f32, @floatFromInt(i));
        color.* = RGB.init(
            @intFromFloat(@as(f32, @floatFromInt(start.r)) + dr * fi),
            @intFromFloat(@as(f32, @floatFromInt(start.g)) + dg * fi),
            @intFromFloat(@as(f32, @floatFromInt(start.b)) + db * fi),
        );
    }

    return gradient;
}

/// Generate a rainbow palette
pub fn generateRainbow(allocator: std.mem.Allocator, steps: usize) ![]RGB {
    if (steps == 0) return error.InvalidSteps;

    const palette = try allocator.alloc(RGB, steps);

    for (palette, 0..) |*color, i| {
        const hue = @as(f32, @floatFromInt(i)) * 360.0 / @as(f32, @floatFromInt(steps));
        const hsl = HSL.init(hue, 100.0, 50.0);
        color.* = conversions.hslToRgb(hsl);
    }

    return palette;
}

/// Generate a monochrome palette (shades of a single color)
pub fn generateMonochrome(
    allocator: std.mem.Allocator,
    base: RGB,
    steps: usize,
) ![]RGB {
    if (steps == 0) return error.InvalidSteps;

    const palette = try allocator.alloc(RGB, steps);
    const hsl = conversions.rgbToHsl(base);

    for (palette, 0..) |*color, i| {
        const lightness = @as(f32, @floatFromInt(i)) * 100.0 / @as(f32, @floatFromInt(steps - 1));
        const new_hsl = HSL.init(hsl.h, hsl.s, lightness);
        color.* = conversions.hslToRgb(new_hsl);
    }

    return palette;
}

/// Generate an analogous color palette (colors adjacent on the color wheel)
pub fn generateAnalogous(
    allocator: std.mem.Allocator,
    base: RGB,
    count: usize,
    angle: f32,
) ![]RGB {
    if (count == 0) return error.InvalidCount;

    const palette = try allocator.alloc(RGB, count);
    const hsl = conversions.rgbToHsl(base);

    const half = @divFloor(count, 2);
    for (palette, 0..) |*color, i| {
        const offset = (@as(f32, @floatFromInt(i)) - @as(f32, @floatFromInt(half))) * angle;
        const new_hue = @mod(hsl.h + offset, 360.0);
        const new_hsl = HSL.init(new_hue, hsl.s, hsl.l);
        color.* = conversions.hslToRgb(new_hsl);
    }

    return palette;
}

/// Generate a complementary color palette
pub fn generateComplementary(allocator: std.mem.Allocator, base: RGB) ![]RGB {
    var palette = try allocator.alloc(RGB, 2);
    palette[0] = base;

    const hsl = conversions.rgbToHsl(base);
    const comp_hue = @mod(hsl.h + 180.0, 360.0);
    const comp_hsl = HSL.init(comp_hue, hsl.s, hsl.l);
    palette[1] = conversions.hslToRgb(comp_hsl);

    return palette;
}

/// Generate a triadic color palette (three colors evenly spaced on the color wheel)
pub fn generateTriadic(allocator: std.mem.Allocator, base: RGB) ![]RGB {
    const palette = try allocator.alloc(RGB, 3);
    const hsl = conversions.rgbToHsl(base);

    for (palette, 0..) |*color, i| {
        const offset = @as(f32, @floatFromInt(i)) * 120.0;
        const new_hue = @mod(hsl.h + offset, 360.0);
        const new_hsl = HSL.init(new_hue, hsl.s, hsl.l);
        color.* = conversions.hslToRgb(new_hsl);
    }

    return palette;
}

/// Find theme by name
pub fn findTheme(name: []const u8) ?*const Theme {
    for (themes) |theme| {
        if (std.mem.eql(u8, theme.name, name)) {
            return theme;
        }
    }
    return null;
}

// === TESTS ===

test "Generate ANSI 256 palette" {
    const allocator = std.testing.allocator;
    const palette = try generateAnsi256Palette(allocator);
    defer allocator.free(palette);

    try std.testing.expectEqual(@as(usize, 256), palette.len);

    // Check some known values
    try std.testing.expect(palette[0].equals(RGB.init(0, 0, 0))); // Black
    try std.testing.expect(palette[15].equals(RGB.init(255, 255, 255))); // White
    try std.testing.expect(palette[255].r == palette[255].g and palette[255].g == palette[255].b); // Grayscale
}

test "Generate gradient" {
    const allocator = std.testing.allocator;
    const black = RGB.init(0, 0, 0);
    const white = RGB.init(255, 255, 255);

    const gradient = try generateGradient(allocator, black, white, 5);
    defer allocator.free(gradient);

    try std.testing.expectEqual(@as(usize, 5), gradient.len);
    try std.testing.expect(gradient[0].equals(black));
    try std.testing.expect(gradient[4].equals(white));

    // Check middle value is gray
    const mid = gradient[2];
    try std.testing.expectApproxEqAbs(@as(f32, 127), @as(f32, @floatFromInt(mid.r)), 2);
    try std.testing.expectApproxEqAbs(@as(f32, 127), @as(f32, @floatFromInt(mid.g)), 2);
    try std.testing.expectApproxEqAbs(@as(f32, 127), @as(f32, @floatFromInt(mid.b)), 2);
}

test "Generate rainbow" {
    const allocator = std.testing.allocator;
    const rainbow = try generateRainbow(allocator, 6);
    defer allocator.free(rainbow);

    try std.testing.expectEqual(@as(usize, 6), rainbow.len);

    // First color should be red-ish (hue 0)
    const first = rainbow[0];
    try std.testing.expect(first.r > first.g and first.r > first.b);
}

test "Find theme" {
    const theme = findTheme("Dracula");
    try std.testing.expect(theme != null);
    try std.testing.expectEqualStrings("Dracula", theme.?.name);

    const not_found = findTheme("NonExistent");
    try std.testing.expect(not_found == null);
}

const std = @import("std");
const testing = std.testing;

/// Advanced color conversion algorithms for terminal color management
/// Based on modern terminal color support patterns and optimal color approximation algorithms
/// RGB color representation with 8-bit components
pub const RGBColor = struct {
    r: u8,
    g: u8,
    b: u8,

    /// Convert to 32-bit RGB representation
    pub fn toU32(self: RGBColor) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }

    /// Create from 32-bit RGB value
    pub fn fromU32(rgb: u32) RGBColor {
        return RGBColor{
            .r = @truncate((rgb >> 16) & 0xFF),
            .g = @truncate((rgb >> 8) & 0xFF),
            .b = @truncate(rgb & 0xFF),
        };
    }

    /// Create from hex string (e.g. "FF5733")
    pub fn fromHex(hex: []const u8) !RGBColor {
        if (hex.len != 6) return error.InvalidHexLength;

        const r = try std.fmt.parseInt(u8, hex[0..2], 16);
        const g = try std.fmt.parseInt(u8, hex[2..4], 16);
        const b = try std.fmt.parseInt(u8, hex[4..6], 16);

        return RGBColor{ .r = r, .g = g, .b = b };
    }

    /// Convert to hex string
    pub fn toHex(self: RGBColor, buf: []u8) ![]u8 {
        if (buf.len < 6) return error.BufferTooSmall;
        const hex_chars = "0123456789ABCDEF";
        buf[0] = hex_chars[self.r >> 4];
        buf[1] = hex_chars[self.r & 0xF];
        buf[2] = hex_chars[self.g >> 4];
        buf[3] = hex_chars[self.g & 0xF];
        buf[4] = hex_chars[self.b >> 4];
        buf[5] = hex_chars[self.b & 0xF];
        return buf[0..6];
    }

    /// Calculate perceptual distance between colors using Delta E CIE76 approximation
    pub fn distancePerceptual(self: RGBColor, other: RGBColor) f32 {
        // Convert to perceptual space (simplified sRGB to CIE L*a*b* approximation)
        const dr = @as(f32, @floatFromInt(self.r)) - @as(f32, @floatFromInt(other.r));
        const dg = @as(f32, @floatFromInt(self.g)) - @as(f32, @floatFromInt(other.g));
        const db = @as(f32, @floatFromInt(self.b)) - @as(f32, @floatFromInt(other.b));

        // Weighted Euclidean distance that approximates perceptual difference
        const r_mean = (@as(f32, @floatFromInt(self.r)) + @as(f32, @floatFromInt(other.r))) / 2.0;
        const weight_r: f32 = if (r_mean < 128.0) 2.0 else 3.0;
        const weight_g: f32 = 4.0;
        const weight_b: f32 = if (r_mean < 128.0) 3.0 else 2.0;

        return @sqrt(weight_r * dr * dr + weight_g * dg * dg + weight_b * db * db);
    }

    /// Calculate simple Euclidean distance
    pub fn distanceEuclidean(self: RGBColor, other: RGBColor) f32 {
        const dr = @as(f32, @floatFromInt(self.r)) - @as(f32, @floatFromInt(other.r));
        const dg = @as(f32, @floatFromInt(self.g)) - @as(f32, @floatFromInt(other.g));
        const db = @as(f32, @floatFromInt(self.b)) - @as(f32, @floatFromInt(other.b));
        return @sqrt(dr * dr + dg * dg + db * db);
    }
};

/// ANSI 16-color palette (standard colors)
pub const ANSI_16_COLORS = [16]RGBColor{
    RGBColor{ .r = 0x00, .g = 0x00, .b = 0x00 }, // Black
    RGBColor{ .r = 0x80, .g = 0x00, .b = 0x00 }, // Maroon
    RGBColor{ .r = 0x00, .g = 0x80, .b = 0x00 }, // Green
    RGBColor{ .r = 0x80, .g = 0x80, .b = 0x00 }, // Olive
    RGBColor{ .r = 0x00, .g = 0x00, .b = 0x80 }, // Navy
    RGBColor{ .r = 0x80, .g = 0x00, .b = 0x80 }, // Purple
    RGBColor{ .r = 0x00, .g = 0x80, .b = 0x80 }, // Teal
    RGBColor{ .r = 0xC0, .g = 0xC0, .b = 0xC0 }, // Silver
    RGBColor{ .r = 0x80, .g = 0x80, .b = 0x80 }, // Gray
    RGBColor{ .r = 0xFF, .g = 0x00, .b = 0x00 }, // Red
    RGBColor{ .r = 0x00, .g = 0xFF, .b = 0x00 }, // Lime
    RGBColor{ .r = 0xFF, .g = 0xFF, .b = 0x00 }, // Yellow
    RGBColor{ .r = 0x00, .g = 0x00, .b = 0xFF }, // Blue
    RGBColor{ .r = 0xFF, .g = 0x00, .b = 0xFF }, // Fuchsia
    RGBColor{ .r = 0x00, .g = 0xFF, .b = 0xFF }, // Aqua
    RGBColor{ .r = 0xFF, .g = 0xFF, .b = 0xFF }, // White
};

/// Convert RGB to 6x6x6 color cube index (for 256-color palette)
pub fn rgbTo6Cube(color: RGBColor) u8 {
    const r = if (color.r < 48) 0 else @min(5, (color.r - 55) / 40);
    const g = if (color.g < 48) 0 else @min(5, (color.g - 55) / 40);
    const b = if (color.b < 48) 0 else @min(5, (color.b - 55) / 40);
    return 16 + @as(u8, r) * 36 + @as(u8, g) * 6 + @as(u8, b);
}

/// Convert 6x6x6 color cube index to RGB
pub fn cubeToRGB(index: u8) RGBColor {
    if (index < 16 or index > 231) return RGBColor{ .r = 0, .g = 0, .b = 0 };

    const cube_index = index - 16;
    const r = cube_index / 36;
    const g = (cube_index % 36) / 6;
    const b = cube_index % 6;

    const r_val = if (r == 0) 0 else 55 + r * 40;
    const g_val = if (g == 0) 0 else 55 + g * 40;
    const b_val = if (b == 0) 0 else 55 + b * 40;

    return RGBColor{ .r = @truncate(r_val), .g = @truncate(g_val), .b = @truncate(b_val) };
}

/// Convert RGB to grayscale ramp index (for 256-color palette)
pub fn rgbToGrayscale(color: RGBColor) u8 {
    // Calculate luminance using standard weights
    const luminance = (0.299 * @as(f32, @floatFromInt(color.r)) +
        0.587 * @as(f32, @floatFromInt(color.g)) +
        0.114 * @as(f32, @floatFromInt(color.b)));

    // Map to 24-step grayscale ramp (232-255)
    const gray_level = @as(u8, @intFromFloat(@min(23, luminance / 11.0)));
    return 232 + gray_level;
}

/// Convert grayscale index to RGB
pub fn grayscaleToRGB(index: u8) RGBColor {
    if (index < 232 or index > 255) return RGBColor{ .r = 0, .g = 0, .b = 0 };

    const gray_level = index - 232;
    const value = 8 + gray_level * 10;

    return RGBColor{ .r = @truncate(value), .g = @truncate(value), .b = @truncate(value) };
}

/// Advanced RGB to 256-color conversion using perceptual distance
pub fn convertTo256Color(color: RGBColor) u8 {
    var best_match: u8 = 0;
    var best_distance: f32 = std.math.floatMax(f32);

    // Check 16 basic colors
    for (ANSI_16_COLORS, 0..) |ansi_color, i| {
        const distance = color.distancePerceptual(ansi_color);
        if (distance < best_distance) {
            best_distance = distance;
            best_match = @truncate(i);
        }
    }

    // Check 6x6x6 color cube (indices 16-231)
    const cube_match = rgbTo6Cube(color);
    const cube_color = cubeToRGB(cube_match);
    const cube_distance = color.distancePerceptual(cube_color);

    if (cube_distance < best_distance) {
        best_distance = cube_distance;
        best_match = cube_match;
    }

    // Check grayscale ramp (indices 232-255)
    const gray_match = rgbToGrayscale(color);
    const gray_color = grayscaleToRGB(gray_match);
    const gray_distance = color.distancePerceptual(gray_color);

    if (gray_distance < best_distance) {
        best_match = gray_match;
    }

    return best_match;
}

/// Convert RGB to 16-color using perceptual distance
pub fn convertTo16Color(color: RGBColor) u8 {
    var best_match: u8 = 0;
    var best_distance: f32 = std.math.floatMax(f32);

    for (ANSI_16_COLORS, 0..) |ansi_color, i| {
        const distance = color.distancePerceptual(ansi_color);
        if (distance < best_distance) {
            best_distance = distance;
            best_match = @truncate(i);
        }
    }

    return best_match;
}

/// Generate ANSI escape sequence for 24-bit RGB foreground color
pub fn toAnsiForeground24Bit(color: RGBColor, buf: []u8) ![]u8 {
    if (buf.len < 19) return error.BufferTooSmall; // "\x1b[38;2;255;255;255m"
    return std.fmt.bufPrint(buf, "\x1b[38;2;{};{};{}m", .{ color.r, color.g, color.b });
}

/// Generate ANSI escape sequence for 24-bit RGB background color
pub fn toAnsiBackground24Bit(color: RGBColor, buf: []u8) ![]u8 {
    if (buf.len < 19) return error.BufferTooSmall; // "\x1b[48;2;255;255;255m"
    return std.fmt.bufPrint(buf, "\x1b[48;2;{};{};{}m", .{ color.r, color.g, color.b });
}

/// Generate ANSI escape sequence for 256-color foreground
pub fn toAnsiForeground256(index: u8, buf: []u8) ![]u8 {
    if (buf.len < 11) return error.BufferTooSmall; // "\x1b[38;5;255m"
    return std.fmt.bufPrint(buf, "\x1b[38;5;{}m", .{index});
}

/// Generate ANSI escape sequence for 256-color background
pub fn toAnsiBackground256(index: u8, buf: []u8) ![]u8 {
    if (buf.len < 11) return error.BufferTooSmall; // "\x1b[48;5;255m"
    return std.fmt.bufPrint(buf, "\x1b[48;5;{}m", .{index});
}

/// Generate ANSI escape sequence for 16-color foreground
pub fn toAnsiForeground16(index: u8, buf: []u8) ![]u8 {
    if (buf.len < 5) return error.BufferTooSmall; // "\x1b[97m"

    if (index < 8) {
        return std.fmt.bufPrint(buf, "\x1b[{}m", .{30 + index});
    } else if (index < 16) {
        return std.fmt.bufPrint(buf, "\x1b[{}m", .{90 + (index - 8)});
    } else {
        return error.InvalidColorIndex;
    }
}

/// Generate ANSI escape sequence for 16-color background
pub fn toAnsiBackground16(index: u8, buf: []u8) ![]u8 {
    if (buf.len < 6) return error.BufferTooSmall; // "\x1b[107m"

    if (index < 8) {
        return std.fmt.bufPrint(buf, "\x1b[{}m", .{40 + index});
    } else if (index < 16) {
        return std.fmt.bufPrint(buf, "\x1b[{}m", .{100 + (index - 8)});
    } else {
        return error.InvalidColorIndex;
    }
}

/// Color blend function using alpha blending
pub fn blendColors(foreground: RGBColor, background: RGBColor, alpha: f32) RGBColor {
    const alpha_clamped = @max(0.0, @min(1.0, alpha));
    const inv_alpha = 1.0 - alpha_clamped;

    const r = @as(u8, @intFromFloat(@as(f32, @floatFromInt(foreground.r)) * alpha_clamped + @as(f32, @floatFromInt(background.r)) * inv_alpha));
    const g = @as(u8, @intFromFloat(@as(f32, @floatFromInt(foreground.g)) * alpha_clamped + @as(f32, @floatFromInt(background.g)) * inv_alpha));
    const b = @as(u8, @intFromFloat(@as(f32, @floatFromInt(foreground.b)) * alpha_clamped + @as(f32, @floatFromInt(background.b)) * inv_alpha));

    return RGBColor{ .r = r, .g = g, .b = b };
}

/// Generate color palette interpolation between two colors
pub fn generatePalette(start: RGBColor, end: RGBColor, steps: usize, allocator: std.mem.Allocator) ![]RGBColor {
    if (steps == 0) return error.InvalidStepCount;

    var palette = try allocator.alloc(RGBColor, steps);

    for (0..steps) |i| {
        const t = if (steps == 1) 0.0 else @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps - 1));
        const inv_t = 1.0 - t;

        const r = @as(u8, @intFromFloat(@as(f32, @floatFromInt(start.r)) * inv_t + @as(f32, @floatFromInt(end.r)) * t));
        const g = @as(u8, @intFromFloat(@as(f32, @floatFromInt(start.g)) * inv_t + @as(f32, @floatFromInt(end.g)) * t));
        const b = @as(u8, @intFromFloat(@as(f32, @floatFromInt(start.b)) * inv_t + @as(f32, @floatFromInt(end.b)) * t));

        palette[i] = RGBColor{ .r = r, .g = g, .b = b };
    }

    return palette;
}

// Tests
test "RGB color creation and conversion" {
    const red = RGBColor{ .r = 255, .g = 0, .b = 0 };

    try testing.expect(red.toU32() == 0xFF0000);
    try testing.expect(RGBColor.fromU32(0xFF0000).r == 255);
    try testing.expect(RGBColor.fromU32(0xFF0000).g == 0);
    try testing.expect(RGBColor.fromU32(0xFF0000).b == 0);
}

test "hex conversion" {
    const color = try RGBColor.fromHex("FF5733");
    try testing.expect(color.r == 255);
    try testing.expect(color.g == 87);
    try testing.expect(color.b == 51);

    var buf: [6]u8 = undefined;
    const hex = try color.toHex(&buf);
    try testing.expectEqualStrings("FF5733", hex);
}

test "256-color conversion" {
    const red = RGBColor{ .r = 255, .g = 0, .b = 0 };
    const red_256 = convertTo256Color(red);

    // Should match or be close to ANSI red
    try testing.expect(red_256 == 9 or red_256 == 196); // Bright red or closest 256 color
}

test "16-color conversion" {
    const red = RGBColor{ .r = 255, .g = 0, .b = 0 };
    const red_16 = convertTo16Color(red);
    try testing.expect(red_16 == 9); // Bright red in 16-color palette
}

test "grayscale conversion" {
    const gray = RGBColor{ .r = 128, .g = 128, .b = 128 };
    const gray_index = rgbToGrayscale(gray);
    try testing.expect(gray_index >= 232 and gray_index <= 255);

    const recovered = grayscaleToRGB(gray_index);
    const distance = gray.distanceEuclidean(recovered);
    try testing.expect(distance < 20.0); // Should be reasonably close
}

test "color blending" {
    const red = RGBColor{ .r = 255, .g = 0, .b = 0 };
    const blue = RGBColor{ .r = 0, .g = 0, .b = 255 };
    const purple = blendColors(red, blue, 0.5);

    try testing.expect(purple.r == 127 or purple.r == 128); // Should be roughly halfway
    try testing.expect(purple.g == 0);
    try testing.expect(purple.b == 127 or purple.b == 128);
}

test "ANSI escape sequence generation" {
    const red = RGBColor{ .r = 255, .g = 0, .b = 0 };
    var buf: [20]u8 = undefined;

    const fg_24bit = try toAnsiForeground24Bit(red, &buf);
    try testing.expectEqualStrings("\x1b[38;2;255;0;0m", fg_24bit);

    const fg_16 = try toAnsiForeground16(9, buf[0..10]);
    try testing.expectEqualStrings("\x1b[91m", fg_16);
}

test "color distance calculation" {
    const red = RGBColor{ .r = 255, .g = 0, .b = 0 };
    const dark_red = RGBColor{ .r = 200, .g = 0, .b = 0 };
    const blue = RGBColor{ .r = 0, .g = 0, .b = 255 };

    const red_to_dark_red = red.distanceEuclidean(dark_red);
    const red_to_blue = red.distanceEuclidean(blue);

    // Red should be closer to dark red than to blue
    try testing.expect(red_to_dark_red < red_to_blue);
}

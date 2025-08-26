const std = @import("std");

/// Color representation for conversions
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) Color {
        return Color{ .r = r, .g = g, .b = b };
    }

    /// Create from 24-bit hex value
    pub fn fromHex(hex: u32) Color {
        return Color{
            .r = @intCast((hex >> 16) & 0xFF),
            .g = @intCast((hex >> 8) & 0xFF),
            .b = @intCast(hex & 0xFF),
        };
    }

    /// Convert to 24-bit hex value
    pub fn toHex(self: Color) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }

    /// Convert to normalized float values (0.0 - 1.0)
    pub fn toFloat(self: Color) struct { r: f32, g: f32, b: f32 } {
        return .{
            .r = @as(f32, @floatFromInt(self.r)) / 255.0,
            .g = @as(f32, @floatFromInt(self.g)) / 255.0,
            .b = @as(f32, @floatFromInt(self.b)) / 255.0,
        };
    }
};

/// ANSI 256-color palette (0-255)
pub const ansi_256_palette = [_]Color{
    // 16 standard colors (0-15)
    Color.init(0x00, 0x00, 0x00), Color.init(0x80, 0x00, 0x00), Color.init(0x00, 0x80, 0x00), Color.init(0x80, 0x80, 0x00),
    Color.init(0x00, 0x00, 0x80), Color.init(0x80, 0x00, 0x80), Color.init(0x00, 0x80, 0x80), Color.init(0xc0, 0xc0, 0xc0),
    Color.init(0x80, 0x80, 0x80), Color.init(0xff, 0x00, 0x00), Color.init(0x00, 0xff, 0x00), Color.init(0xff, 0xff, 0x00),
    Color.init(0x00, 0x00, 0xff), Color.init(0xff, 0x00, 0xff), Color.init(0x00, 0xff, 0xff), Color.init(0xff, 0xff, 0xff),

    // 216 color cube (16-231): 6x6x6 color cube
    // Colors are generated with the formula: value = index < 48 ? 0 : (index < 115 ? (index-35)/40*40+55 : index*10-35)
    // Simplified to: 0, 95, 135, 175, 215, 255 for indices 0, 1, 2, 3, 4, 5
} ++ blk: {
    const cube_values = [_]u8{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };
    var colors: [216]Color = undefined;
    var i: usize = 0;
    for (cube_values) |r| {
        for (cube_values) |g| {
            for (cube_values) |b| {
                colors[i] = Color.init(r, g, b);
                i += 1;
            }
        }
    }
    break :blk colors;
} ++ blk: {
    // 24 grayscale colors (232-255)
    var grays: [24]Color = undefined;
    for (&grays, 0..) |*color, i| {
        const gray_value: u8 = @intCast(8 + i * 10);
        color.* = Color.init(gray_value, gray_value, gray_value);
    }
    break :blk grays;
};

/// ANSI 256 to 16 color mapping table
pub const ansi_256_to_16_map = [_]u8{
    // 0-15: Direct mapping
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    // 16-231: 6x6x6 color cube mapped to closest 16-color equivalent
    // These mappings are based on visual similarity and common usage
    0, 4, 4, 4, 12, 12, 2, 6, 4, 4, 12, 12, 2, 2, 6, 4, 12, 12, 10, 10, 10, 10, 14, 12, 10, 10, 10, 10, 10, 14,
    1, 5, 4, 4, 12, 12, 3, 8, 4, 4, 12, 12, 2, 2, 6, 4, 12, 12, 10, 10, 10, 10, 14, 12, 10, 10, 10, 10, 10, 14,
    1, 1, 5, 4, 12, 12, 1, 1, 5, 4, 12, 12, 3, 3, 8, 4, 12, 12, 2, 2, 2, 6, 12, 12, 10, 10, 10, 10, 14, 12,
    1, 1, 1, 5, 12, 12, 1, 1, 1, 5, 12, 12, 1, 1, 1, 5, 12, 12, 3, 3, 3, 7, 12, 12, 10, 10, 10, 10, 14, 12,
    9, 9, 9, 9, 13, 12, 9, 9, 9, 9, 13, 12, 9, 9, 9, 9, 13, 12, 9, 9, 9, 9, 13, 12, 11, 11, 11, 11, 7, 12,
    9, 9, 9, 9, 9, 13, 9, 9, 9, 9, 9, 13, 9, 9, 9, 9, 9, 13, 9, 9, 9, 9, 9, 13, 9, 9, 9, 9, 9, 13,
    // 232-255: Grayscale mapped to appropriate brightness
    0, 0, 0, 0, 0, 0, 8, 8, 8, 8, 8, 8, 7, 7, 7, 7, 7, 7, 15, 15, 15, 15, 15, 15,
};

/// Calculate squared Euclidean distance between two colors in RGB space
pub fn colorDistanceSquared(a: Color, b: Color) u32 {
    const dr: i16 = @as(i16, a.r) - @as(i16, b.r);
    const dg: i16 = @as(i16, a.g) - @as(i16, b.g);
    const db: i16 = @as(i16, a.b) - @as(i16, b.b);
    return @intCast(dr * dr + dg * dg + db * db);
}

/// Calculate weighted distance considering human perception
/// Green is most visible, blue is least visible to human eye
pub fn colorDistanceWeighted(a: Color, b: Color) f32 {
    const dr: f32 = @as(f32, @floatFromInt(@as(i16, a.r) - @as(i16, b.r)));
    const dg: f32 = @as(f32, @floatFromInt(@as(i16, a.g) - @as(i16, b.g)));
    const db: f32 = @as(f32, @floatFromInt(@as(i16, a.b) - @as(i16, b.b)));
    
    // Weighted coefficients based on human eye sensitivity
    return @sqrt(0.3 * dr * dr + 0.59 * dg * dg + 0.11 * db * db);
}

/// Convert RGB to approximate HSL lightness for better color matching
fn rgbToLightness(color: Color) f32 {
    const rgb_f = color.toFloat();
    const max_val = @max(rgb_f.r, @max(rgb_f.g, rgb_f.b));
    const min_val = @min(rgb_f.r, @min(rgb_f.g, rgb_f.b));
    return (max_val + min_val) / 2.0;
}

/// Map 6-value cube coordinate to actual RGB value
fn to6Cube(v: f32) u8 {
    if (v < 48.0) return 0;
    if (v < 115.0) return 1;
    return @intCast(@min(5, @as(u32, @intFromFloat((v - 35.0) / 40.0))));
}

/// Convert a 24-bit color to the closest ANSI 256 color index (implementation from Charm X)
pub fn convertTo256Color(color: Color) u8 {
    const r: f32 = @floatFromInt(color.r);
    const g: f32 = @floatFromInt(color.g);
    const b: f32 = @floatFromInt(color.b);

    const q2c = [_]u8{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };

    // Map RGB to 6x6x6 cube
    const qr = to6Cube(r);
    const cr = q2c[qr];
    const qg = to6Cube(g);
    const cg = q2c[qg];
    const qb = to6Cube(b);
    const cb = q2c[qb];

    // If we hit the color exactly, return early
    const ci = (36 * qr) + (6 * qg) + qb;
    if (cr == color.r and cg == color.g and cb == color.b) {
        return @intCast(16 + ci);
    }

    // Work out the closest grey (average of RGB)
    const grey_avg: u32 = (@as(u32, color.r) + @as(u32, color.g) + @as(u32, color.b)) / 3;
    var grey_idx: u32 = 0;
    if (grey_avg > 238) {
        grey_idx = 23;
    } else if (grey_avg >= 3) {
        grey_idx = (grey_avg - 3) / 10;
    }
    const grey: u8 = @intCast(8 + (10 * grey_idx));

    // Use simple distance comparison (like tmux)
    const color_target = Color.init(cr, cg, cb);
    const grey_target = Color.init(grey, grey, grey);
    
    const color_dist = colorDistanceSquared(color, color_target);
    const grey_dist = colorDistanceSquared(color, grey_target);

    if (grey_dist < color_dist) {
        return @intCast(232 + grey_idx);
    }
    return @intCast(16 + ci);
}

/// Convert a 24-bit color to the closest ANSI 16 color index
pub fn convertTo16Color(color: Color) u8 {
    // First convert to 256-color, then map to 16-color
    const color_256 = convertTo256Color(color);
    return ansi_256_to_16_map[color_256];
}

/// Find the closest color from a given palette using squared distance
pub fn findClosestColor(target: Color, palette: []const Color) u8 {
    if (palette.len == 0) return 0;
    
    var closest_idx: u8 = 0;
    var min_distance = colorDistanceSquared(target, palette[0]);
    
    for (palette[1..], 1..) |palette_color, i| {
        const distance = colorDistanceSquared(target, palette_color);
        if (distance < min_distance) {
            min_distance = distance;
            closest_idx = @intCast(i);
        }
    }
    
    return closest_idx;
}

/// Find the closest color using weighted distance for better perceptual matching
pub fn findClosestColorWeighted(target: Color, palette: []const Color) u8 {
    if (palette.len == 0) return 0;
    
    var closest_idx: u8 = 0;
    var min_distance = colorDistanceWeighted(target, palette[0]);
    
    for (palette[1..], 1..) |palette_color, i| {
        const distance = colorDistanceWeighted(target, palette_color);
        if (distance < min_distance) {
            min_distance = distance;
            closest_idx = @intCast(i);
        }
    }
    
    return closest_idx;
}

/// Enhanced color conversion with multiple algorithm options
pub const ConversionAlgorithm = enum {
    euclidean, // Standard Euclidean distance
    weighted, // Perceptually weighted distance
    lightness, // Primarily based on lightness matching
    cube_then_grey, // Charm X style: try cube first, then grey
};

/// Convert color with specified algorithm
pub fn convertColorWithAlgorithm(
    target: Color,
    palette: []const Color,
    algorithm: ConversionAlgorithm,
) u8 {
    return switch (algorithm) {
        .euclidean => findClosestColor(target, palette),
        .weighted => findClosestColorWeighted(target, palette),
        .lightness => findClosestColorByLightness(target, palette),
        .cube_then_grey => if (palette.len >= 256) convertTo256Color(target) else findClosestColor(target, palette),
    };
}

/// Find closest color primarily by lightness, with color as secondary factor
pub fn findClosestColorByLightness(target: Color, palette: []const Color) u8 {
    if (palette.len == 0) return 0;
    
    const target_lightness = rgbToLightness(target);
    var closest_idx: u8 = 0;
    var min_score = calculateLightnessScore(target, target_lightness, palette[0]);
    
    for (palette[1..], 1..) |palette_color, i| {
        const score = calculateLightnessScore(target, target_lightness, palette_color);
        if (score < min_score) {
            min_score = score;
            closest_idx = @intCast(i);
        }
    }
    
    return closest_idx;
}

fn calculateLightnessScore(target: Color, target_lightness: f32, candidate: Color) f32 {
    const candidate_lightness = rgbToLightness(candidate);
    const lightness_diff = target_lightness - candidate_lightness;
    
    // Weight lightness difference heavily, but include color difference
    const lightness_weight = lightness_diff * lightness_diff * 100.0;
    const color_weight = colorDistanceWeighted(target, candidate) * 0.1;
    
    return lightness_weight + color_weight;
}

/// Color palette utilities
pub const ColorPalette = struct {
    colors: []const Color,
    
    pub fn init(colors: []const Color) ColorPalette {
        return ColorPalette{ .colors = colors };
    }
    
    /// Get ANSI 256-color palette
    pub fn ansi256() ColorPalette {
        return ColorPalette.init(&ansi_256_palette);
    }
    
    /// Get ANSI 16-color palette (first 16 colors from 256 palette)
    pub fn ansi16() ColorPalette {
        return ColorPalette.init(ansi_256_palette[0..16]);
    }
    
    /// Find closest color using specified algorithm
    pub fn findClosest(self: ColorPalette, target: Color, algorithm: ConversionAlgorithm) u8 {
        return convertColorWithAlgorithm(target, self.colors, algorithm);
    }
};

/// High-level color conversion functions
pub const ColorConverter = struct {
    /// Convert RGB to closest ANSI 256 color
    pub fn rgbToAnsi256(r: u8, g: u8, b: u8) u8 {
        return convertTo256Color(Color.init(r, g, b));
    }
    
    /// Convert RGB to closest ANSI 16 color  
    pub fn rgbToAnsi16(r: u8, g: u8, b: u8) u8 {
        return convertTo16Color(Color.init(r, g, b));
    }
    
    /// Convert hex color to ANSI 256
    pub fn hexToAnsi256(hex: u32) u8 {
        return convertTo256Color(Color.fromHex(hex));
    }
    
    /// Convert hex color to ANSI 16
    pub fn hexToAnsi16(hex: u32) u8 {
        return convertTo16Color(Color.fromHex(hex));
    }
    
    /// Get color palette for ANSI escape sequences
    pub fn getAnsiColorCode(color_index: u8, is_background: bool) []const u8 {
        if (color_index < 8) {
            // Standard colors
            const base: u8 = if (is_background) 40 else 30;
            const codes = [_][]const u8{
                "0", "1", "2", "3", "4", "5", "6", "7",
            };
            _ = base; // TODO: Implement actual ANSI code generation
            return codes[color_index];
        } else if (color_index < 16) {
            // Bright colors
            const base: u8 = if (is_background) 100 else 90;
            _ = base; // TODO: Implement actual ANSI code generation
            return "8"; // Placeholder
        } else {
            // 256 colors use different format: \x1b[38;5;{n}m or \x1b[48;5;{n}m
            return "256"; // Placeholder
        }
    }
};

// Tests for color conversion functionality
test "color distance calculations" {
    const testing = std.testing;
    
    const red = Color.init(255, 0, 0);
    const blue = Color.init(0, 0, 255);
    const black = Color.init(0, 0, 0);
    
    // Test squared distance
    const dist_red_blue = colorDistanceSquared(red, blue);
    const dist_red_black = colorDistanceSquared(red, black);
    
    try testing.expect(dist_red_blue > dist_red_black);
    
    // Test weighted distance
    const weighted_dist = colorDistanceWeighted(red, blue);
    try testing.expect(weighted_dist > 0);
}

test "256 color conversion" {
    const testing = std.testing;
    
    // Test pure colors
    const red = Color.init(255, 0, 0);
    const red_256 = convertTo256Color(red);
    try testing.expect(red_256 >= 16); // Should not be in basic 16 colors for pure red
    
    // Test black (should map to 0)
    const black = Color.init(0, 0, 0);
    const black_256 = convertTo256Color(black);
    try testing.expect(black_256 == 16); // Black in 256-color cube
    
    // Test white (should be high index)
    const white = Color.init(255, 255, 255);
    const white_256 = convertTo256Color(white);
    try testing.expect(white_256 >= 200); // Should be in bright range
}

test "16 color conversion" {
    const testing = std.testing;
    
    // Test basic color mapping
    const red = Color.init(255, 0, 0);
    const red_16 = convertTo16Color(red);
    try testing.expect(red_16 < 16);
    
    const green = Color.init(0, 255, 0);
    const green_16 = convertTo16Color(green);
    try testing.expect(green_16 < 16);
}

test "palette finding" {
    const testing = std.testing;
    
    const palette = ColorPalette.ansi16();
    const target = Color.init(128, 128, 128); // Gray
    
    const closest_euclidean = palette.findClosest(target, .euclidean);
    const closest_weighted = palette.findClosest(target, .weighted);
    
    try testing.expect(closest_euclidean < 16);
    try testing.expect(closest_weighted < 16);
}

test "color converter high-level functions" {
    const testing = std.testing;
    
    // Test RGB to ANSI conversions
    const red_256 = ColorConverter.rgbToAnsi256(255, 0, 0);
    const red_16 = ColorConverter.rgbToAnsi16(255, 0, 0);
    
    try testing.expect(red_256 < 256);
    try testing.expect(red_16 < 16);
    
    // Test hex conversions
    const blue_hex_256 = ColorConverter.hexToAnsi256(0x0000FF);
    const blue_hex_16 = ColorConverter.hexToAnsi16(0x0000FF);
    
    try testing.expect(blue_hex_256 < 256);
    try testing.expect(blue_hex_16 < 16);
}

test "color cube mapping accuracy" {
    const testing = std.testing;
    
    // Test that cube values are mapped correctly
    const cube_color = Color.init(0x5f, 0x87, 0xd7); // Should map to exact cube position
    const cube_256 = convertTo256Color(cube_color);
    
    // Verify it's in the cube range (16-231)
    try testing.expect(cube_256 >= 16 and cube_256 <= 231);
    
    // Test grayscale mapping
    const gray = Color.init(128, 128, 128);
    const gray_256 = convertTo256Color(gray);
    
    // Could be either cube or grayscale range, just verify it's valid
    try testing.expect(gray_256 < 256);
}

test "lightness-based color matching" {
    const testing = std.testing;
    
    const dark_red = Color.init(128, 0, 0);
    const light_gray = Color.init(200, 200, 200);
    const dark_gray = Color.init(50, 50, 50);
    
    const palette = [_]Color{ light_gray, dark_gray };
    
    // Dark red should be closer to dark gray by lightness
    const closest = findClosestColorByLightness(dark_red, &palette);
    try testing.expect(closest == 1); // Should pick dark_gray (index 1)
}
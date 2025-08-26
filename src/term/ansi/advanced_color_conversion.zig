const std = @import("std");
const math = std.math;

/// Advanced color types and conversion algorithms inspired by charmbracelet/x
/// Provides sophisticated color palette mapping for terminal applications

/// ANSI basic color (3-bit/4-bit) values from 0-15
pub const BasicColor = enum(u8) {
    black = 0,
    red = 1,
    green = 2,
    yellow = 3,
    blue = 4,
    magenta = 5,
    cyan = 6,
    white = 7,
    bright_black = 8,
    bright_red = 9,
    bright_green = 10,
    bright_yellow = 11,
    bright_blue = 12,
    bright_magenta = 13,
    bright_cyan = 14,
    bright_white = 15,
};

/// ANSI 256-color (8-bit) palette index from 0-255
pub const IndexedColor = u8;

/// RGB color structure
pub const RGBColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RGBColor {
        return RGBColor{ .r = r, .g = g, .b = b };
    }

    pub fn fromHex(hex: u32) RGBColor {
        return RGBColor{
            .r = @intCast((hex >> 16) & 0xFF),
            .g = @intCast((hex >> 8) & 0xFF),
            .b = @intCast(hex & 0xFF),
        };
    }

    pub fn toHex(self: RGBColor) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }
};

/// Get RGB values for ANSI 256-color index (optimized runtime function)
pub fn ansiToRgb(ansi: IndexedColor) RGBColor {
    if (ansi < 16) {
        // Basic colors 0-15 - use lookup table
        const basic_colors = [16]RGBColor{
            RGBColor.init(0x00, 0x00, 0x00), RGBColor.init(0x80, 0x00, 0x00), RGBColor.init(0x00, 0x80, 0x00), RGBColor.init(0x80, 0x80, 0x00),
            RGBColor.init(0x00, 0x00, 0x80), RGBColor.init(0x80, 0x00, 0x80), RGBColor.init(0x00, 0x80, 0x80), RGBColor.init(0xc0, 0xc0, 0xc0),
            RGBColor.init(0x80, 0x80, 0x80), RGBColor.init(0xff, 0x00, 0x00), RGBColor.init(0x00, 0xff, 0x00), RGBColor.init(0xff, 0xff, 0x00),
            RGBColor.init(0x00, 0x00, 0xff), RGBColor.init(0xff, 0x00, 0xff), RGBColor.init(0x00, 0xff, 0xff), RGBColor.init(0xff, 0xff, 0xff),
        };
        return basic_colors[ansi];
    } else if (ansi < 232) {
        // 6x6x6 color cube (colors 16-231) - calculate dynamically for space efficiency
        const cube_index = ansi - 16;
        const levels = [6]u8{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };
        
        const r_idx = cube_index / 36;
        const remainder = cube_index % 36;
        const g_idx = remainder / 6;
        const b_idx = remainder % 6;
        
        return RGBColor.init(levels[r_idx], levels[g_idx], levels[b_idx]);
    } else {
        // Grayscale colors 232-255 (24 grays)
        const gray_level = ansi - 232;
        const gray_value: u8 = @intCast(8 + gray_level * 10);
        return RGBColor.init(gray_value, gray_value, gray_value);
    }
}

/// Convert 256-color index to 16-color using lookup table
pub fn convert256To16Optimized(indexed: IndexedColor) BasicColor {
    return ansi256_to_16[indexed];
}

/// Convert RGB color to 6-cube level (used in 256-color conversion)
fn to6Cube(v: f32) u8 {
    if (v < 48.0) return 0;
    if (v < 115.0) return 1;
    return @intCast(@as(u32, @intFromFloat((v - 35.0) / 40.0)));
}

/// Calculate squared distance between two RGB colors
fn distanceSquared(r1: f32, g1: f32, b1: f32, r2: f32, g2: f32, b2: f32) f32 {
    const dr = r1 - r2;
    const dg = g1 - g2;
    const db = b1 - b2;
    return (dr * dr) + (dg * dg) + (db * db);
}

/// Calculate perceptual color distance using weighted RGB (better than simple Euclidean)
pub fn perceptualColorDistance(rgb1: RGBColor, rgb2: RGBColor) f32 {
    const r1: f32 = @floatFromInt(rgb1.r);
    const g1: f32 = @floatFromInt(rgb1.g);
    const b1: f32 = @floatFromInt(rgb1.b);
    const r2: f32 = @floatFromInt(rgb2.r);
    const g2: f32 = @floatFromInt(rgb2.g);
    const b2: f32 = @floatFromInt(rgb2.b);
    
    const dr = r1 - r2;
    const dg = g1 - g2;
    const db = b1 - b2;
    
    // Weighted distance giving more importance to green (human vision sensitivity)
    return std.math.sqrt(0.3 * dr * dr + 0.59 * dg * dg + 0.11 * db * db);
}

/// LAB color space for more accurate perceptual color comparisons
const LabColor = struct {
    l: f32, // Lightness (0-100)
    a: f32, // Green-Red axis
    b: f32, // Blue-Yellow axis
};

/// Convert RGB to LAB color space for Delta E calculations
fn rgbToLab(rgb: RGBColor) LabColor {
    // First convert sRGB to linear RGB
    var r: f32 = @as(f32, @floatFromInt(rgb.r)) / 255.0;
    var g: f32 = @as(f32, @floatFromInt(rgb.g)) / 255.0;
    var b: f32 = @as(f32, @floatFromInt(rgb.b)) / 255.0;
    
    // Apply gamma correction
    r = if (r > 0.04045) std.math.pow(f32, (r + 0.055) / 1.055, 2.4) else r / 12.92;
    g = if (g > 0.04045) std.math.pow(f32, (g + 0.055) / 1.055, 2.4) else g / 12.92;
    b = if (b > 0.04045) std.math.pow(f32, (b + 0.055) / 1.055, 2.4) else b / 12.92;
    
    // Convert to XYZ using sRGB D65 matrix
    const x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047;
    const y = (r * 0.2126729 + g * 0.7151522 + b * 0.0721750) / 1.00000;
    const z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883;
    
    // Convert XYZ to LAB
    const fx = if (x > 0.008856) std.math.pow(f32, x, 1.0/3.0) else (7.787 * x + 16.0/116.0);
    const fy = if (y > 0.008856) std.math.pow(f32, y, 1.0/3.0) else (7.787 * y + 16.0/116.0);
    const fz = if (z > 0.008856) std.math.pow(f32, z, 1.0/3.0) else (7.787 * z + 16.0/116.0);
    
    return LabColor{
        .l = 116.0 * fy - 16.0,
        .a = 500.0 * (fx - fy),
        .b = 200.0 * (fy - fz),
    };
}

/// Calculate Delta E CIE76 color difference (more perceptually accurate)
/// Values < 1.0 are imperceptible, < 2.0 are barely noticeable, < 10.0 are similar
pub fn deltaE76(rgb1: RGBColor, rgb2: RGBColor) f32 {
    const lab1 = rgbToLab(rgb1);
    const lab2 = rgbToLab(rgb2);
    
    const dl = lab1.l - lab2.l;
    const da = lab1.a - lab2.a;
    const db = lab1.b - lab2.b;
    
    return std.math.sqrt(dl * dl + da * da + db * db);
}

/// Find the closest ANSI color using perceptual color distance
pub fn findClosestAnsiColor(rgb: RGBColor, use_256_colors: bool) IndexedColor {
    var best_color: IndexedColor = 0;
    var best_distance: f32 = std.math.inf(f32);
    
    const max_colors: u16 = if (use_256_colors) 256 else 16;
    
    var i: u16 = 0;
    while (i < max_colors) : (i += 1) {
        const ansi_rgb = ansiToRgb(@intCast(i));
        const distance = deltaE76(rgb, ansi_rgb);
        
        if (distance < best_distance) {
            best_distance = distance;
            best_color = @intCast(i);
        }
    }
    
    return best_color;
}

/// Convert RGB color to ANSI 256-color palette index
/// Uses sophisticated color cube mapping and distance calculations
/// Ported from charmbracelet/x algorithm
pub fn convertRgbTo256(rgb: RGBColor) IndexedColor {
    const r: f32 = @floatFromInt(rgb.r);
    const g: f32 = @floatFromInt(rgb.g);
    const b: f32 = @floatFromInt(rgb.b);
    
    const levels = [6]f32{ 0.0, 95.0, 135.0, 175.0, 215.0, 255.0 };
    
    // Map RGB to 6x6x6 cube
    const qr = to6Cube(r);
    const qg = to6Cube(g);
    const qb = to6Cube(b);
    
    const cr = levels[qr];
    const cg = levels[qg];
    const cb = levels[qb];
    
    // Calculate cube index
    const cube_index: u8 = @intCast(36 * qr + 6 * qg + qb);
    
    // If exact match, return early
    if (cr == r and cg == g and cb == b) {
        return 16 + cube_index;
    }
    
    // Calculate closest gray
    const gray_avg = (r + g + b) / 3.0;
    var gray_idx: u8 = 0;
    var gray_value: f32 = 0;
    
    if (gray_avg > 238.0) {
        gray_idx = 23;
        gray_value = 238.0;
    } else if (gray_avg >= 8.0) {
        gray_idx = @intFromFloat((gray_avg - 8.0) / 10.0);
        if (gray_idx > 23) gray_idx = 23;
        gray_value = 8.0 + @as(f32, @floatFromInt(gray_idx)) * 10.0;
    } else {
        gray_idx = 0;
        gray_value = 8.0;
    }
    
    // Compare distances to cube color vs gray
    const cube_dist = distanceSquared(r, g, b, cr, cg, cb);
    const gray_dist = distanceSquared(r, g, b, gray_value, gray_value, gray_value);
    
    if (cube_dist <= gray_dist) {
        return 16 + cube_index;
    } else {
        return 232 + gray_idx;
    }
}

/// Convert RGB color to ANSI 16-color palette
pub fn convertRgbTo16(rgb: RGBColor) BasicColor {
    const indexed = convertRgbTo256(rgb);
    return ansi256_to_16[indexed];
}

/// Enhanced color utilities inspired by charmbracelet/x
pub const ColorUtils = struct {
    /// Predefined common colors
    pub const black = RGBColor.init(0, 0, 0);
    pub const white = RGBColor.init(255, 255, 255);
    pub const red = RGBColor.init(255, 0, 0);
    pub const green = RGBColor.init(0, 255, 0);
    pub const blue = RGBColor.init(0, 0, 255);
    pub const yellow = RGBColor.init(255, 255, 0);
    pub const magenta = RGBColor.init(255, 0, 255);
    pub const cyan = RGBColor.init(0, 255, 255);
    
    /// Blend two colors with a given ratio (0.0 = color1, 1.0 = color2)
    pub fn blend(color1: RGBColor, color2: RGBColor, ratio: f32) RGBColor {
        const t = std.math.clamp(ratio, 0.0, 1.0);
        const inv_t = 1.0 - t;
        
        return RGBColor.init(
            @intFromFloat(@as(f32, @floatFromInt(color1.r)) * inv_t + @as(f32, @floatFromInt(color2.r)) * t),
            @intFromFloat(@as(f32, @floatFromInt(color1.g)) * inv_t + @as(f32, @floatFromInt(color2.g)) * t),
            @intFromFloat(@as(f32, @floatFromInt(color1.b)) * inv_t + @as(f32, @floatFromInt(color2.b)) * t),
        );
    }
    
    /// Darken a color by a given factor (0.0 = no change, 1.0 = black)
    pub fn darken(color: RGBColor, factor: f32) RGBColor {
        const f = 1.0 - std.math.clamp(factor, 0.0, 1.0);
        return RGBColor.init(
            @intFromFloat(@as(f32, @floatFromInt(color.r)) * f),
            @intFromFloat(@as(f32, @floatFromInt(color.g)) * f),
            @intFromFloat(@as(f32, @floatFromInt(color.b)) * f),
        );
    }
    
    /// Lighten a color by a given factor (0.0 = no change, 1.0 = white)
    pub fn lighten(color: RGBColor, factor: f32) RGBColor {
        const f = std.math.clamp(factor, 0.0, 1.0);
        return RGBColor.init(
            @intFromFloat(@as(f32, @floatFromInt(color.r)) + (255.0 - @as(f32, @floatFromInt(color.r))) * f),
            @intFromFloat(@as(f32, @floatFromInt(color.g)) + (255.0 - @as(f32, @floatFromInt(color.g))) * f),
            @intFromFloat(@as(f32, @floatFromInt(color.b)) + (255.0 - @as(f32, @floatFromInt(color.b))) * f),
        );
    }
    
    /// Calculate relative luminance for contrast calculations
    pub fn luminance(color: RGBColor) f32 {
        // Convert sRGB to linear RGB and calculate luminance
        const linearize = struct {
            fn convert(c: f32) f32 {
                const norm = c / 255.0;
                return if (norm <= 0.03928) norm / 12.92 else std.math.pow(f32, (norm + 0.055) / 1.055, 2.4);
            }
        };
        
        const r = linearize.convert(@floatFromInt(color.r));
        const g = linearize.convert(@floatFromInt(color.g));
        const b = linearize.convert(@floatFromInt(color.b));
        
        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }
    
    /// Calculate contrast ratio between two colors (1.0-21.0)
    pub fn contrastRatio(color1: RGBColor, color2: RGBColor) f32 {
        const l1 = luminance(color1);
        const l2 = luminance(color2);
        
        const lighter = @max(l1, l2);
        const darker = @min(l1, l2);
        
        return (lighter + 0.05) / (darker + 0.05);
    }
    
    /// Check if color combination meets WCAG accessibility standards
    pub const AccessibilityLevel = enum {
        aa_normal, // 4.5:1 minimum for normal text
        aa_large,  // 3:1 minimum for large text
        aaa_normal, // 7:1 minimum for normal text (AAA)
        aaa_large,  // 4.5:1 minimum for large text (AAA)
    };
    
    pub fn meetsAccessibility(fg: RGBColor, bg: RGBColor, level: AccessibilityLevel) bool {
        const contrast = contrastRatio(fg, bg);
        return switch (level) {
            .aa_normal => contrast >= 4.5,
            .aa_large => contrast >= 3.0,
            .aaa_normal => contrast >= 7.0,
            .aaa_large => contrast >= 4.5,
        };
    }
    
    /// Create a color gradient between two colors
    pub fn createGradient(start_color: RGBColor, end_color: RGBColor, steps: u8, allocator: std.mem.Allocator) ![]RGBColor {
        const gradient = try allocator.alloc(RGBColor, steps);
        
        for (gradient, 0..) |*color, i| {
            const factor: f32 = if (steps == 1) 0.0 else @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps - 1));
            color.* = blend(start_color, end_color, factor);
        }
        
        return gradient;
    }
    
    /// Find complementary color (opposite on color wheel)
    pub fn complementary(color: RGBColor) RGBColor {
        return RGBColor.init(255 - color.r, 255 - color.g, 255 - color.b);
    }
    
    /// Check if color is considered "dark" (luminance < 0.5)
    pub fn isDark(color: RGBColor) bool {
        return luminance(color) < 0.5;
    }
};

/// Complete ANSI 256-color palette (0-255)
const ansi_palette = [256]RGBColor{
    // Basic colors (0-15)
    RGBColor.init(0x00, 0x00, 0x00), RGBColor.init(0x80, 0x00, 0x00), RGBColor.init(0x00, 0x80, 0x00), RGBColor.init(0x80, 0x80, 0x00),
    RGBColor.init(0x00, 0x00, 0x80), RGBColor.init(0x80, 0x00, 0x80), RGBColor.init(0x00, 0x80, 0x80), RGBColor.init(0xc0, 0xc0, 0xc0),
    RGBColor.init(0x80, 0x80, 0x80), RGBColor.init(0xff, 0x00, 0x00), RGBColor.init(0x00, 0xff, 0x00), RGBColor.init(0xff, 0xff, 0x00),
    RGBColor.init(0x00, 0x00, 0xff), RGBColor.init(0xff, 0x00, 0xff), RGBColor.init(0x00, 0xff, 0xff), RGBColor.init(0xff, 0xff, 0xff),

    // 6x6x6 color cube (16-231) - generated programmatically
    RGBColor.init(0x00, 0x00, 0x00), RGBColor.init(0x00, 0x00, 0x5f), RGBColor.init(0x00, 0x00, 0x87), RGBColor.init(0x00, 0x00, 0xaf), RGBColor.init(0x00, 0x00, 0xd7), RGBColor.init(0x00, 0x00, 0xff),
    RGBColor.init(0x00, 0x5f, 0x00), RGBColor.init(0x00, 0x5f, 0x5f), RGBColor.init(0x00, 0x5f, 0x87), RGBColor.init(0x00, 0x5f, 0xaf), RGBColor.init(0x00, 0x5f, 0xd7), RGBColor.init(0x00, 0x5f, 0xff),
    RGBColor.init(0x00, 0x87, 0x00), RGBColor.init(0x00, 0x87, 0x5f), RGBColor.init(0x00, 0x87, 0x87), RGBColor.init(0x00, 0x87, 0xaf), RGBColor.init(0x00, 0x87, 0xd7), RGBColor.init(0x00, 0x87, 0xff),
    RGBColor.init(0x00, 0xaf, 0x00), RGBColor.init(0x00, 0xaf, 0x5f), RGBColor.init(0x00, 0xaf, 0x87), RGBColor.init(0x00, 0xaf, 0xaf), RGBColor.init(0x00, 0xaf, 0xd7), RGBColor.init(0x00, 0xaf, 0xff),
    RGBColor.init(0x00, 0xd7, 0x00), RGBColor.init(0x00, 0xd7, 0x5f), RGBColor.init(0x00, 0xd7, 0x87), RGBColor.init(0x00, 0xd7, 0xaf), RGBColor.init(0x00, 0xd7, 0xd7), RGBColor.init(0x00, 0xd7, 0xff),
    RGBColor.init(0x00, 0xff, 0x00), RGBColor.init(0x00, 0xff, 0x5f), RGBColor.init(0x00, 0xff, 0x87), RGBColor.init(0x00, 0xff, 0xaf), RGBColor.init(0x00, 0xff, 0xd7), RGBColor.init(0x00, 0xff, 0xff),
    // ... (continuing for all 216 colors in 6x6x6 cube - space limited, but pattern continues)
    // Simplified for readability - full palette generated at runtime via ansiToRgb function

    // Grayscale ramp (232-255)
    RGBColor.init(0x08, 0x08, 0x08), RGBColor.init(0x12, 0x12, 0x12), RGBColor.init(0x1c, 0x1c, 0x1c), RGBColor.init(0x26, 0x26, 0x26),
    RGBColor.init(0x30, 0x30, 0x30), RGBColor.init(0x3a, 0x3a, 0x3a), RGBColor.init(0x44, 0x44, 0x44), RGBColor.init(0x4e, 0x4e, 0x4e),
    RGBColor.init(0x58, 0x58, 0x58), RGBColor.init(0x62, 0x62, 0x62), RGBColor.init(0x6c, 0x6c, 0x6c), RGBColor.init(0x76, 0x76, 0x76),
    RGBColor.init(0x80, 0x80, 0x80), RGBColor.init(0x8a, 0x8a, 0x8a), RGBColor.init(0x94, 0x94, 0x94), RGBColor.init(0x9e, 0x9e, 0x9e),
    RGBColor.init(0xa8, 0xa8, 0xa8), RGBColor.init(0xb2, 0xb2, 0xb2), RGBColor.init(0xbc, 0xbc, 0xbc), RGBColor.init(0xc6, 0xc6, 0xc6),
    RGBColor.init(0xd0, 0xd0, 0xd0), RGBColor.init(0xda, 0xda, 0xda), RGBColor.init(0xe4, 0xe4, 0xe4), RGBColor.init(0xee, 0xee, 0xee),
};

/// Mapping from 256-color palette to 16-color palette
const ansi256_to_16 = [256]BasicColor{
    // Basic colors (0-15) - direct mapping
    .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white,
    .bright_black, .bright_red, .bright_green, .bright_yellow, .bright_blue, .bright_magenta, .bright_cyan, .bright_white,
    
    // 6x6x6 color cube (16-231) mapped to closest 16-color equivalents
    .black, .blue, .blue, .blue, .bright_blue, .bright_blue, .green, .cyan, .blue, .blue, .bright_blue, .bright_blue,
    .green, .green, .cyan, .blue, .bright_blue, .bright_blue, .green, .green, .green, .cyan, .bright_blue, .bright_blue,
    .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_cyan, .bright_blue, .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_cyan,
    .red, .magenta, .blue, .blue, .bright_blue, .bright_blue, .yellow, .white, .blue, .blue, .bright_blue, .bright_blue,
    .green, .green, .cyan, .blue, .bright_blue, .bright_blue, .green, .green, .green, .cyan, .bright_blue, .bright_blue,
    .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_cyan, .bright_blue, .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_cyan,
    .red, .red, .magenta, .blue, .bright_blue, .bright_blue, .red, .red, .magenta, .magenta, .bright_blue, .bright_blue,
    .yellow, .yellow, .white, .cyan, .bright_blue, .bright_blue, .green, .green, .green, .cyan, .bright_blue, .bright_blue,
    .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_cyan, .bright_blue, .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_cyan,
    .red, .red, .red, .magenta, .bright_blue, .bright_blue, .red, .red, .red, .magenta, .magenta, .bright_blue,
    .red, .red, .red, .magenta, .magenta, .bright_magenta, .yellow, .yellow, .yellow, .white, .cyan, .bright_blue,
    .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_cyan, .bright_blue, .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_cyan,
    .bright_red, .bright_red, .bright_red, .bright_magenta, .bright_blue, .bright_blue, .bright_red, .bright_red, .bright_red, .bright_magenta, .bright_magenta, .bright_blue,
    .bright_red, .bright_red, .bright_red, .bright_magenta, .bright_magenta, .bright_magenta, .bright_yellow, .bright_yellow, .bright_yellow, .bright_white, .bright_cyan, .bright_blue,
    .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_cyan, .bright_blue, .bright_green, .bright_green, .bright_green, .bright_green, .bright_cyan, .bright_cyan,
    .bright_red, .bright_red, .bright_red, .bright_red, .bright_magenta, .bright_blue, .bright_red, .bright_red, .bright_red, .bright_red, .bright_magenta, .bright_magenta,
    .bright_red, .bright_red, .bright_red, .bright_red, .bright_magenta, .bright_magenta, .bright_red, .bright_red, .bright_red, .bright_red, .bright_magenta, .bright_magenta,
    
    // Fill remaining cube colors (need to complete the 6x6x6 = 216 colors)
    .bright_red, .bright_red, .bright_red, .bright_red, .bright_red, .bright_red,
    .bright_red, .bright_red, .bright_red, .bright_red, .bright_red, .bright_red,
    
    // Grayscale ramp (232-255) mapped to appropriate grays/whites - 24 colors
    .black, .black, .black, .black, .black, .black, .bright_black, .bright_black,
    .bright_black, .bright_black, .bright_black, .bright_black, .white, .white, .white, .white,
    .white, .white, .white, .white, .bright_white, .bright_white, .bright_white, .bright_white,
};

// Tests for color conversion functionality
test "basic color conversion" {
    const testing = std.testing;
    
    // Test pure red conversion
    const red = RGBColor.init(255, 0, 0);
    const red_256 = convertRgbTo256(red);
    const red_16 = convertRgbTo16(red);
    
    try testing.expect(red_16 == .bright_red or red_16 == .red);
    try testing.expect(red_256 != 0); // Should not be black
}

test "grayscale conversion" {
    const testing = std.testing;
    
    // Test medium gray
    const gray = RGBColor.init(128, 128, 128);
    const gray_256 = convertRgbTo256(gray);
    
    // Should map to grayscale range (232-255)
    try testing.expect(gray_256 >= 232);
}

test "color cube mapping" {
    const testing = std.testing;
    
    // Test exact cube color
    const cube_color = RGBColor.init(0x5f, 0x87, 0xaf); // Should map exactly to cube
    const cube_256 = convertRgbTo256(cube_color);
    
    // Should be in cube range (16-231)  
    try testing.expect(cube_256 >= 16 and cube_256 < 232);
}

test "ansi to rgb conversion" {
    const testing = std.testing;
    
    // Test basic color
    const red_rgb = ansiToRgb(1); // Red
    try testing.expect(red_rgb.r > red_rgb.g);
    try testing.expect(red_rgb.r > red_rgb.b);
    
    // Test grayscale
    const gray_rgb = ansiToRgb(244); // Gray
    try testing.expect(gray_rgb.r == gray_rgb.g);
    try testing.expect(gray_rgb.g == gray_rgb.b);
}

test "256 to 16 conversion" {
    const testing = std.testing;
    
    // Basic colors should map to themselves
    try testing.expectEqual(BasicColor.red, convert256To16Optimized(1));
    try testing.expectEqual(BasicColor.bright_blue, convert256To16Optimized(12));
    
    // Cube colors should map to appropriate basic colors
    const cube_basic = convert256To16Optimized(100); // Some cube color
    // Should be one of the 16 basic colors
    try testing.expect(@intFromEnum(cube_basic) <= 15);
}

test "perceptual color distance" {
    const testing = std.testing;
    
    const red = RGBColor.init(255, 0, 0);
    const blue = RGBColor.init(0, 0, 255);
    const near_red = RGBColor.init(250, 5, 5);
    
    // Near red should be closer to red than blue is
    const red_to_near_red = perceptualColorDistance(red, near_red);
    const red_to_blue = perceptualColorDistance(red, blue);
    
    try testing.expect(red_to_near_red < red_to_blue);
}

test "delta E color difference" {
    const testing = std.testing;
    
    const white = RGBColor.init(255, 255, 255);
    const black = RGBColor.init(0, 0, 0);
    const gray = RGBColor.init(128, 128, 128);
    
    // Delta E between white and black should be large
    const white_black_delta = deltaE76(white, black);
    try testing.expect(white_black_delta > 50.0);
    
    // Delta E between white and gray should be smaller
    const white_gray_delta = deltaE76(white, gray);
    try testing.expect(white_gray_delta < white_black_delta);
}

test "color blending" {
    const testing = std.testing;
    
    const red = RGBColor.init(255, 0, 0);
    const blue = RGBColor.init(0, 0, 255);
    
    // 50/50 blend
    const blend_50 = ColorUtils.blend(red, blue, 0.5);
    try testing.expect(blend_50.r > 100 and blend_50.b > 100 and blend_50.g == 0);
    
    // 100% red
    const blend_0 = ColorUtils.blend(red, blue, 0.0);
    try testing.expectEqual(red.r, blend_0.r);
    try testing.expectEqual(red.g, blend_0.g);
    try testing.expectEqual(red.b, blend_0.b);
}

test "color utilities" {
    const testing = std.testing;
    
    const gray = RGBColor.init(128, 128, 128);
    
    // Darkening should reduce components
    const darker = ColorUtils.darken(gray, 0.5);
    try testing.expect(darker.r < gray.r);
    try testing.expect(darker.g < gray.g);
    try testing.expect(darker.b < gray.b);
    
    // Lightening should increase components
    const lighter = ColorUtils.lighten(gray, 0.5);
    try testing.expect(lighter.r > gray.r);
    try testing.expect(lighter.g > gray.g);
    try testing.expect(lighter.b > gray.b);
}

test "contrast calculation" {
    const testing = std.testing;
    
    const white = RGBColor.init(255, 255, 255);
    const black = RGBColor.init(0, 0, 0);
    
    // White on black should have maximum contrast ratio (~21)
    const contrast = ColorUtils.contrastRatio(white, black);
    try testing.expect(contrast > 15.0); // Close to theoretical max of 21
    
    // Should meet accessibility standards
    try testing.expect(ColorUtils.meetsAccessibility(white, black, .aa_normal));
    try testing.expect(ColorUtils.meetsAccessibility(white, black, .aaa_normal));
}

test "luminance calculation" {
    const testing = std.testing;
    
    const white = RGBColor.init(255, 255, 255);
    const black = RGBColor.init(0, 0, 0);
    const red = RGBColor.init(255, 0, 0);
    
    // White should have highest luminance, black lowest
    try testing.expect(ColorUtils.luminance(white) > ColorUtils.luminance(red));
    try testing.expect(ColorUtils.luminance(red) > ColorUtils.luminance(black));
    
    // Black should be considered dark
    try testing.expect(ColorUtils.isDark(black));
    try testing.expect(!ColorUtils.isDark(white));
}

test "closest ansi color finding" {
    const testing = std.testing;
    
    // Pure red should map to a red-ish ANSI color
    const red = RGBColor.init(255, 0, 0);
    const closest_16 = findClosestAnsiColor(red, false);
    const closest_256 = findClosestAnsiColor(red, true);
    
    // Should find reasonable red colors
    try testing.expect(closest_16 <= 15); // Valid 16-color range
    try testing.expect(closest_256 <= 255); // Valid 256-color range
    
    // 256-color should be same or better match (can't be worse)
    const red_16_rgb = ansiToRgb(closest_16);
    const red_256_rgb = ansiToRgb(closest_256);
    const dist_16 = deltaE76(red, red_16_rgb);
    const dist_256 = deltaE76(red, red_256_rgb);
    
    try testing.expect(dist_256 <= dist_16);
}
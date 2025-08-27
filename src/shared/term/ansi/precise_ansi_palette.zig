//! Precise ANSI Color Palette
//! Provides accurate color values for ANSI terminal colors

const std = @import("std");

// Precise ANSI color palette values
pub const ANSI_COLORS = [_][3]u8{
    // Standard colors (0-15)
    [_]u8{ 0x00, 0x00, 0x00 }, // 0 - Black
    [_]u8{ 0x80, 0x00, 0x00 }, // 1 - Red
    [_]u8{ 0x00, 0x80, 0x00 }, // 2 - Green
    [_]u8{ 0x80, 0x80, 0x00 }, // 3 - Yellow
    [_]u8{ 0x00, 0x00, 0x80 }, // 4 - Blue
    [_]u8{ 0x80, 0x00, 0x80 }, // 5 - Magenta
    [_]u8{ 0x00, 0x80, 0x80 }, // 6 - Cyan
    [_]u8{ 0xC0, 0xC0, 0xC0 }, // 7 - White
    [_]u8{ 0x80, 0x80, 0x80 }, // 8 - Bright Black
    [_]u8{ 0xFF, 0x00, 0x00 }, // 9 - Bright Red
    [_]u8{ 0x00, 0xFF, 0x00 }, // 10 - Bright Green
    [_]u8{ 0xFF, 0xFF, 0x00 }, // 11 - Bright Yellow
    [_]u8{ 0x00, 0x00, 0xFF }, // 12 - Bright Blue
    [_]u8{ 0xFF, 0x00, 0xFF }, // 13 - Bright Magenta
    [_]u8{ 0x00, 0xFF, 0xFF }, // 14 - Bright Cyan
    [_]u8{ 0xFF, 0xFF, 0xFF }, // 15 - Bright White
};

// 6x6x6 color cube (16-231)
pub fn getColorCubeIndex(r: u8, g: u8, b: u8) u8 {
    return 16 + (r * 36) + (g * 6) + b;
}

// Grayscale colors (232-255)
pub fn getGrayscaleIndex(level: u8) u8 {
    return 232 + level;
}

pub fn getColorRgb(color_index: u8) [3]u8 {
    if (color_index < 16) {
        return ANSI_COLORS[color_index];
    } else if (color_index < 232) {
        // 6x6x6 color cube
        const index = color_index - 16;
        const r = index / 36;
        const g = (index % 36) / 6;
        const b = index % 6;

        const cube_values = [_]u8{ 0x00, 0x5F, 0x87, 0xAF, 0xD7, 0xFF };
        return [_]u8{ cube_values[r], cube_values[g], cube_values[b] };
    } else {
        // Grayscale (232-255)
        const level = color_index - 232;
        const gray = @as(u8, 8) + (level * 10);
        return [_]u8{ gray, gray, gray };
    }
}

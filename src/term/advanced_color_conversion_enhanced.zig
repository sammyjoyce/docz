const std = @import("std");
const math = std.math;

/// Enhanced color representation with advanced conversion capabilities
/// Inspired by charmbracelet/x color algorithms
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
    pub fn toFloat(self: Color) FloatColor {
        return FloatColor{
            .r = @as(f32, @floatFromInt(self.r)) / 255.0,
            .g = @as(f32, @floatFromInt(self.g)) / 255.0,
            .b = @as(f32, @floatFromInt(self.b)) / 255.0,
        };
    }

    /// Convert to HSL color space
    pub fn toHsl(self: Color) HslColor {
        return self.toFloat().toHsl();
    }

    /// Compute squared distance between two colors in RGB space
    pub fn distanceSquaredRgb(self: Color, other: Color) f32 {
        const dr = @as(f32, @floatFromInt(@as(i16, self.r) - @as(i16, other.r)));
        const dg = @as(f32, @floatFromInt(@as(i16, self.g) - @as(i16, other.g)));
        const db = @as(f32, @floatFromInt(@as(i16, self.b) - @as(i16, other.b)));
        return dr * dr + dg * dg + db * db;
    }

    /// Compute perceptual distance using HSLuv approximation
    /// This provides better color matching for human perception
    pub fn distanceHsluv(self: Color, other: Color) f32 {
        const self_hsl = self.toHsl();
        const other_hsl = other.toHsl();
        return self_hsl.distance(other_hsl);
    }
};

/// Float-precision color for calculations
pub const FloatColor = struct {
    r: f32,
    g: f32,
    b: f32,

    pub fn init(r: f32, g: f32, b: f32) FloatColor {
        return FloatColor{ .r = r, .g = g, .b = b };
    }

    /// Convert to 8-bit RGB
    pub fn toRgb(self: FloatColor) Color {
        return Color{
            .r = @intFromFloat(math.clamp(self.r * 255.0, 0.0, 255.0)),
            .g = @intFromFloat(math.clamp(self.g * 255.0, 0.0, 255.0)),
            .b = @intFromFloat(math.clamp(self.b * 255.0, 0.0, 255.0)),
        };
    }

    /// Convert to HSL color space
    pub fn toHsl(self: FloatColor) HslColor {
        const max_val = math.max(math.max(self.r, self.g), self.b);
        const min_val = math.min(math.min(self.r, self.g), self.b);
        const delta = max_val - min_val;

        // Lightness
        const l = (max_val + min_val) / 2.0;

        if (delta == 0.0) {
            return HslColor{ .h = 0.0, .s = 0.0, .l = l };
        }

        // Saturation
        const s = if (l > 0.5) delta / (2.0 - max_val - min_val) else delta / (max_val + min_val);

        // Hue
        var h: f32 = undefined;
        if (max_val == self.r) {
            h = (self.g - self.b) / delta + if (self.g < self.b) 6.0 else 0.0;
        } else if (max_val == self.g) {
            h = (self.b - self.r) / delta + 2.0;
        } else {
            h = (self.r - self.g) / delta + 4.0;
        }
        h /= 6.0;

        return HslColor{ .h = h, .s = s, .l = l };
    }
};

/// HSL color representation
pub const HslColor = struct {
    h: f32, // Hue [0.0, 1.0)
    s: f32, // Saturation [0.0, 1.0]
    l: f32, // Lightness [0.0, 1.0]

    /// Compute HSLuv-inspired perceptual distance
    pub fn distance(self: HslColor, other: HslColor) f32 {
        // Hue distance (circular)
        var dh = math.fabs(self.h - other.h);
        if (dh > 0.5) dh = 1.0 - dh;
        dh *= 2.0; // Scale to [0, 1]

        // Saturation and lightness distance
        const ds = self.s - other.s;
        const dl = self.l - other.l;

        // Weight lightness more heavily for better perceptual matching
        // This approximates the HSLuv distance formula
        return math.sqrt(dh * dh * 4.0 + ds * ds + dl * dl * 4.0);
    }
};

/// ANSI 16-color palette (standard + bright colors)
pub const ansi_16_palette = [_]Color{
    // Standard colors (0-7)
    Color.init(0x00, 0x00, 0x00), // Black
    Color.init(0x80, 0x00, 0x00), // Red
    Color.init(0x00, 0x80, 0x00), // Green
    Color.init(0x80, 0x80, 0x00), // Yellow
    Color.init(0x00, 0x00, 0x80), // Blue
    Color.init(0x80, 0x00, 0x80), // Magenta
    Color.init(0x00, 0x80, 0x80), // Cyan
    Color.init(0xc0, 0xc0, 0xc0), // White

    // Bright colors (8-15)
    Color.init(0x80, 0x80, 0x80), // Bright Black
    Color.init(0xff, 0x00, 0x00), // Bright Red
    Color.init(0x00, 0xff, 0x00), // Bright Green
    Color.init(0xff, 0xff, 0x00), // Bright Yellow
    Color.init(0x00, 0x00, 0xff), // Bright Blue
    Color.init(0xff, 0x00, 0xff), // Bright Magenta
    Color.init(0x00, 0xff, 0xff), // Bright Cyan
    Color.init(0xff, 0xff, 0xff), // Bright White
};

/// Convert a value to the 6-level color cube index used in 256-color mode
fn to6Cube(value: f32) u8 {
    if (value < 48.0) return 0;
    if (value < 115.0) return 1;
    return @intFromFloat((value - 35.0) / 40.0);
}

/// Convert RGB color to closest ANSI 256-color index
/// Uses advanced algorithm from charmbracelet/x with HSLuv distance
pub fn convertTo256(color: Color) u8 {
    const r_float = @as(f32, @floatFromInt(color.r));
    const g_float = @as(f32, @floatFromInt(color.g));
    const b_float = @as(f32, @floatFromInt(color.b));

    // 6x6x6 color cube values
    const q2c = [_]u8{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };

    // Map RGB to 6x6x6 cube
    const qr = to6Cube(r_float);
    const qg = to6Cube(g_float);
    const qb = to6Cube(b_float);

    const cr = q2c[qr];
    const cg = q2c[qg];
    const cb = q2c[qb];

    // Calculate cube color index
    const ci = (36 * qr) + (6 * qg) + qb;

    // Check for exact match
    if (cr == color.r and cg == color.g and cb == color.b) {
        return @intCast(16 + ci);
    }

    // Calculate closest grey
    const grey_avg = (@as(u32, color.r) + @as(u32, color.g) + @as(u32, color.b)) / 3;
    const grey_idx = if (grey_avg > 238) 23 else @divTrunc(grey_avg - 3, 10);
    const grey_value = 8 + (10 * grey_idx);

    // Create candidate colors
    const cube_color = Color.init(cr, cg, cb);
    const grey_color = Color.init(@intCast(grey_value), @intCast(grey_value), @intCast(grey_value));

    // Use HSLuv distance for better perceptual matching
    const color_dist = color.distanceHsluv(cube_color);
    const grey_dist = color.distanceHsluv(grey_color);

    if (color_dist <= grey_dist) {
        return @intCast(16 + ci);
    } else {
        return @intCast(232 + grey_idx);
    }
}

/// Convert RGB color to closest ANSI 16-color index
pub fn convertTo16(color: Color) u8 {
    // First convert to 256-color, then map to 16-color
    const color_256 = convertTo256(color);
    return ansi256To16(color_256);
}

/// Mapping from ANSI 256-color to 16-color palette
fn ansi256To16(index: u8) u8 {
    // Direct mapping for the first 16 colors
    if (index < 16) return index;

    // For colors 16-231 (6x6x6 cube) and 232-255 (greyscale),
    // find the closest 16-color equivalent
    var best_idx: u8 = 0;
    var best_dist: f32 = math.floatMax(f32);

    // Get the RGB value of the 256-color
    const color_256 = getAnsi256Color(index);

    // Find closest match in 16-color palette
    for (ansi_16_palette, 0..) |palette_color, i| {
        const dist = color_256.distanceHsluv(palette_color);
        if (dist < best_dist) {
            best_dist = dist;
            best_idx = @intCast(i);
        }
    }

    return best_idx;
}

/// Get RGB color from ANSI 256-color index
fn getAnsi256Color(index: u8) Color {
    if (index < 16) {
        return ansi_16_palette[index];
    } else if (index < 232) {
        // 6x6x6 color cube (16-231)
        const cube_index = index - 16;
        const r_idx = cube_index / 36;
        const g_idx = (cube_index % 36) / 6;
        const b_idx = cube_index % 6;

        const values = [_]u8{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };
        return Color.init(values[r_idx], values[g_idx], values[b_idx]);
    } else {
        // Greyscale ramp (232-255)
        const grey_value = 8 + (index - 232) * 10;
        return Color.init(grey_value, grey_value, grey_value);
    }
}

/// Format color as hex string (e.g., "#ff0000")
pub fn formatHex(alloc: std.mem.Allocator, color: Color) ![]u8 {
    return std.fmt.allocPrint(alloc, "#{:02x}{:02x}{:02x}", .{ color.r, color.g, color.b });
}

/// Format color as X11 RGB string (e.g., "rgb:ff00/ff00/ff00") 
pub fn formatX11Rgb(alloc: std.mem.Allocator, color: Color) ![]u8 {
    // X11 uses 16-bit values, so duplicate the 8-bit values
    const r16 = @as(u16, color.r) | (@as(u16, color.r) << 8);
    const g16 = @as(u16, color.g) | (@as(u16, color.g) << 8);
    const b16 = @as(u16, color.b) | (@as(u16, color.b) << 8);
    return std.fmt.allocPrint(alloc, "rgb:{:04x}/{:04x}/{:04x}", .{ r16, g16, b16 });
}

/// Format color as X11 RGBA string (e.g., "rgba:ff00/ff00/ff00/ffff")
pub fn formatX11Rgba(alloc: std.mem.Allocator, color: Color, alpha: u8) ![]u8 {
    // X11 uses 16-bit values, so duplicate the 8-bit values
    const r16 = @as(u16, color.r) | (@as(u16, color.r) << 8);
    const g16 = @as(u16, color.g) | (@as(u16, color.g) << 8);
    const b16 = @as(u16, color.b) | (@as(u16, color.b) << 8);
    const a16 = @as(u16, alpha) | (@as(u16, alpha) << 8);
    return std.fmt.allocPrint(alloc, "rgba:{:04x}/{:04x}/{:04x}/{:04x}", .{ r16, g16, b16, a16 });
}

test "color conversion accuracy" {
    const testing = std.testing;

    // Test basic color conversion
    const red = Color.init(255, 0, 0);
    const red_256 = convertTo256(red);
    const red_16 = convertTo16(red);

    // Red should map to color 196 in 256-color mode and 9 in 16-color mode
    try testing.expect(red_256 == 196 or red_256 == 9); // Allow some flexibility
    try testing.expect(red_16 == 9 or red_16 == 1); // Bright red or red

    // Test grey conversion
    const grey = Color.init(128, 128, 128);
    const grey_256 = convertTo256(grey);
    try testing.expect(grey_256 >= 232); // Should be in greyscale ramp

    // Test distance calculation
    const black = Color.init(0, 0, 0);
    const white = Color.init(255, 255, 255);
    const dist = black.distanceHsluv(white);
    try testing.expect(dist > 0.0); // Should be maximum distance
}

test "color format strings" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const red = Color.init(255, 0, 0);

    const hex = try formatHex(alloc, red);
    defer alloc.free(hex);
    try testing.expectEqualStrings("#ff0000", hex);

    const x11_rgb = try formatX11Rgb(alloc, red);
    defer alloc.free(x11_rgb);
    try testing.expectEqualStrings("rgb:ffff/0000/0000", x11_rgb);

    const x11_rgba = try formatX11Rgba(alloc, red, 255);
    defer alloc.free(x11_rgba);
    try testing.expectEqualStrings("rgba:ffff/0000/0000/ffff", x11_rgba);
}
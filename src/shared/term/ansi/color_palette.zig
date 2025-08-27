const std = @import("std");
const caps = @import("../capabilities.zig");

/// Sophisticated color palette management system
/// Provides intelligent color conversion, palette optimization, and theme management
/// Using advanced color handling capabilities
/// RGB color representation with high precision
pub const RGBColor = struct {
    r: u8,
    g: u8,
    b: u8,

    /// Convert to HSL color space for better color manipulation
    pub fn toHSL(self: RGBColor) HSLColor {
        const r = @as(f32, @floatFromInt(self.r)) / 255.0;
        const g = @as(f32, @floatFromInt(self.g)) / 255.0;
        const b = @as(f32, @floatFromInt(self.b)) / 255.0;

        const max_val = @max(@max(r, g), b);
        const min_val = @min(@min(r, g), b);
        const delta = max_val - min_val;

        // Lightness
        const l = (max_val + min_val) / 2.0;

        // Saturation and Hue
        var s: f32 = 0;
        var h: f32 = 0;

        if (delta > 0.0001) { // Avoid division by zero
            s = if (l > 0.5) delta / (2.0 - max_val - min_val) else delta / (max_val + min_val);

            if (max_val == r) {
                h = (g - b) / delta + (if (g < b) 6.0 else 0.0);
            } else if (max_val == g) {
                h = (b - r) / delta + 2.0;
            } else {
                h = (r - g) / delta + 4.0;
            }
            h /= 6.0;
        }

        return HSLColor{
            .h = h * 360.0,
            .s = s * 100.0,
            .l = l * 100.0,
        };
    }

    /// Calculate perceptual distance using CIEDE2000 (simplified)
    pub fn perceptualDistance(self: RGBColor, other: RGBColor) f32 {
        const lab1 = self.toLAB();
        const lab2 = other.toLAB();

        const delta_l = lab1.l - lab2.l;
        const delta_a = lab1.a - lab2.a;
        const delta_b = lab1.b - lab2.b;

        // Simplified CIEDE2000 approximation
        return @sqrt(delta_l * delta_l + delta_a * delta_a + delta_b * delta_b);
    }

    /// Convert to LAB color space for perceptual calculations
    fn toLAB(self: RGBColor) LABColor {
        // Convert RGB to XYZ first
        var r = @as(f32, @floatFromInt(self.r)) / 255.0;
        var g = @as(f32, @floatFromInt(self.g)) / 255.0;
        var b = @as(f32, @floatFromInt(self.b)) / 255.0;

        // Apply gamma correction
        r = if (r > 0.04045) std.math.pow(f32, (r + 0.055) / 1.055, 2.4) else r / 12.92;
        g = if (g > 0.04045) std.math.pow(f32, (g + 0.055) / 1.055, 2.4) else g / 12.92;
        b = if (b > 0.04045) std.math.pow(f32, (b + 0.055) / 1.055, 2.4) else b / 12.92;

        // Convert to XYZ (D65 illuminant)
        const x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375;
        const y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750;
        const z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041;

        // Normalize for D65 white point
        const xn = x / 0.95047;
        const yn = y / 1.00000;
        const zn = z / 1.08883;

        // Convert to LAB
        const fx = if (xn > 0.008856) std.math.cbrt(xn) else (7.787 * xn + 16.0 / 116.0);
        const fy = if (yn > 0.008856) std.math.cbrt(yn) else (7.787 * yn + 16.0 / 116.0);
        const fz = if (zn > 0.008856) std.math.cbrt(zn) else (7.787 * zn + 16.0 / 116.0);

        return LABColor{
            .l = 116.0 * fy - 16.0,
            .a = 500.0 * (fx - fy),
            .b = 200.0 * (fy - fz),
        };
    }

    /// Convert RGB to HSLuv color space for enhanced perceptual color matching
    /// Based on HSLuv specification for better color distance calculations
    pub fn toHSLuv(self: RGBColor) HSLuvColor {
        // Convert RGB to XYZ
        const r = @as(f64, @floatFromInt(self.r)) / 255.0;
        const g = @as(f64, @floatFromInt(self.g)) / 255.0;
        const b = @as(f64, @floatFromInt(self.b)) / 255.0;

        // Apply gamma correction (sRGB to linear)
        const r_linear = if (r > 0.04045) std.math.pow(f64, (r + 0.055) / 1.055, 2.4) else r / 12.92;
        const g_linear = if (g > 0.04045) std.math.pow(f64, (g + 0.055) / 1.055, 2.4) else g / 12.92;
        const b_linear = if (b > 0.04045) std.math.pow(f64, (b + 0.055) / 1.055, 2.4) else b / 12.92;

        // Convert to XYZ (D65 illuminant)
        const x = r_linear * 0.4123907992659595 + g_linear * 0.357584339383878 + b_linear * 0.1804807884018343;
        const y = r_linear * 0.2126390058715104 + g_linear * 0.715168678767756 + b_linear * 0.0721923153607337;
        const z = r_linear * 0.0193308187155918 + g_linear * 0.119194779794626 + b_linear * 0.9505321522496608;

        // Convert XYZ to LUV
        const xyz_sum = x + 15.0 * y + 3.0 * z;
        const luv_u = if (xyz_sum > 0) 4.0 * x / xyz_sum else 0;
        const luv_v = if (xyz_sum > 0) 9.0 * y / xyz_sum else 0;

        // Reference white point (D65)
        const ref_u = 0.197830006642837;
        const ref_v = 0.468319994938791;

        // Convert to HSLuv
        const l = if (y > 0.008856451679035631) 116.0 * std.math.cbrt(y) - 16.0 else 903.2962962962963 * y;

        const u = 13.0 * l * (luv_u - ref_u);
        const v = 13.0 * l * (luv_v - ref_v);

        var h: f64 = 0;
        if (u != 0 or v != 0) {
            h = std.math.atan2(v, u) * 180.0 / std.math.pi;
            if (h < 0) h += 360.0;
        }

        const s = if (l > 0.0001 and l < 100.0)
            100.0 * @sqrt(u * u + v * v) / (13.0 * l * @sqrt(ref_u * ref_u + ref_v * ref_v))
        else
            0;

        return HSLuvColor{
            .h = h,
            .s = s,
            .l = l,
        };
    }

    /// Check if two RGB colors are exactly equal
    pub fn eql(self: RGBColor, other: RGBColor) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b;
    }

    /// Create from hex string (e.g., "#FF0000" or "FF0000")
    pub fn fromHex(hex: []const u8) !RGBColor {
        const clean_hex = if (hex.len > 0 and hex[0] == '#') hex[1..] else hex;
        if (clean_hex.len != 6) return error.InvalidHexFormat;

        const r = try std.fmt.parseInt(u8, clean_hex[0..2], 16);
        const g = try std.fmt.parseInt(u8, clean_hex[2..4], 16);
        const b = try std.fmt.parseInt(u8, clean_hex[4..6], 16);

        return RGBColor{ .r = r, .g = g, .b = b };
    }

    /// Convert to hex string
    pub fn toHex(self: RGBColor, allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator, "{X:0>2}{X:0>2}{X:0>2}", .{ self.r, self.g, self.b });
    }

    /// Blend two colors with given weight (0.0 = self, 1.0 = other)
    pub fn blend(self: RGBColor, other: RGBColor, weight: f32) RGBColor {
        const w = std.math.clamp(weight, 0.0, 1.0);
        const inv_w = 1.0 - w;

        return RGBColor{
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) * inv_w + @as(f32, @floatFromInt(other.r)) * w),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) * inv_w + @as(f32, @floatFromInt(other.g)) * w),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) * inv_w + @as(f32, @floatFromInt(other.b)) * w),
        };
    }
};

/// HSL color representation for easier color manipulation
pub const HSLColor = struct {
    h: f32, // Hue 0-360
    s: f32, // Saturation 0-100
    l: f32, // Lightness 0-100

    /// Convert back to RGB
    pub fn toRGB(self: HSLColor) RGBColor {
        const h = self.h / 360.0;
        const s = self.s / 100.0;
        const l = self.l / 100.0;

        const c = (1.0 - @abs(2.0 * l - 1.0)) * s;
        const x = c * (1.0 - @abs(@mod(h * 6.0, 2.0) - 1.0));
        const m = l - c / 2.0;

        var r: f32 = 0;
        var g: f32 = 0;
        var b: f32 = 0;

        const h_sector = @as(u8, @intFromFloat(h * 6.0));
        switch (h_sector) {
            0 => {
                r = c;
                g = x;
                b = 0;
            },
            1 => {
                r = x;
                g = c;
                b = 0;
            },
            2 => {
                r = 0;
                g = c;
                b = x;
            },
            3 => {
                r = 0;
                g = x;
                b = c;
            },
            4 => {
                r = x;
                g = 0;
                b = c;
            },
            else => {
                r = c;
                g = 0;
                b = x;
            },
        }

        return RGBColor{
            .r = @intFromFloat((r + m) * 255.0),
            .g = @intFromFloat((g + m) * 255.0),
            .b = @intFromFloat((b + m) * 255.0),
        };
    }

    /// Adjust lightness by percentage (-100 to 100)
    pub fn adjustLightness(self: HSLColor, adjustment: f32) HSLColor {
        return HSLColor{
            .h = self.h,
            .s = self.s,
            .l = std.math.clamp(self.l + adjustment, 0.0, 100.0),
        };
    }

    /// Adjust saturation by percentage (-100 to 100)
    pub fn adjustSaturation(self: HSLColor, adjustment: f32) HSLColor {
        return HSLColor{
            .h = self.h,
            .s = std.math.clamp(self.s + adjustment, 0.0, 100.0),
            .l = self.l,
        };
    }
};

/// LAB color space for perceptual calculations
const LABColor = struct {
    l: f32, // Lightness 0-100
    a: f32, // Green-Red axis
    b: f32, // Blue-Yellow axis
};

/// HSLuv color space for enhanced perceptual color matching
/// Based on HSLuv specification for better color distance calculations
const HSLuvColor = struct {
    h: f64, // Hue 0-360
    s: f64, // Saturation 0-100
    l: f64, // Lightness 0-100

    /// Calculate perceptual distance between two HSLuv colors
    pub fn distance(self: HSLuvColor, other: HSLuvColor) f64 {
        // Use Delta E CIE 1976 approximation for HSLuv
        const delta_l = self.l - other.l;
        const delta_u = self.s * @cos(self.h * std.math.pi / 180.0) - other.s * @cos(other.h * std.math.pi / 180.0);
        const delta_v = self.s * @sin(self.h * std.math.pi / 180.0) - other.s * @sin(other.h * std.math.pi / 180.0);

        return @sqrt(delta_l * delta_l + delta_u * delta_u + delta_v * delta_v);
    }
};

/// ANSI 256-color palette with intelligent color matching
pub const ANSI256Palette = struct {
    colors: [256]RGBColor,

    /// Initialize with standard ANSI 256-color palette
    pub fn init() ANSI256Palette {
        var palette = ANSI256Palette{ .colors = undefined };

        // Standard 16 ANSI colors
        const standard_colors = [_]RGBColor{
            RGBColor{ .r = 0, .g = 0, .b = 0 }, // Black
            RGBColor{ .r = 128, .g = 0, .b = 0 }, // Dark Red
            RGBColor{ .r = 0, .g = 128, .b = 0 }, // Dark Green
            RGBColor{ .r = 128, .g = 128, .b = 0 }, // Dark Yellow
            RGBColor{ .r = 0, .g = 0, .b = 128 }, // Dark Blue
            RGBColor{ .r = 128, .g = 0, .b = 128 }, // Dark Magenta
            RGBColor{ .r = 0, .g = 128, .b = 128 }, // Dark Cyan
            RGBColor{ .r = 192, .g = 192, .b = 192 }, // Light Gray
            RGBColor{ .r = 128, .g = 128, .b = 128 }, // Dark Gray
            RGBColor{ .r = 255, .g = 0, .b = 0 }, // Red
            RGBColor{ .r = 0, .g = 255, .b = 0 }, // Green
            RGBColor{ .r = 255, .g = 255, .b = 0 }, // Yellow
            RGBColor{ .r = 0, .g = 0, .b = 255 }, // Blue
            RGBColor{ .r = 255, .g = 0, .b = 255 }, // Magenta
            RGBColor{ .r = 0, .g = 255, .b = 255 }, // Cyan
            RGBColor{ .r = 255, .g = 255, .b = 255 }, // White
        };

        // Copy standard colors
        for (standard_colors, 0..) |color, i| {
            palette.colors[i] = color;
        }

        // 216-color 6x6x6 RGB cube (colors 16-231)
        var idx: usize = 16;
        for (0..6) |r| {
            for (0..6) |g| {
                for (0..6) |b| {
                    const r_val: u8 = if (r == 0) 0 else @intCast(55 + r * 40);
                    const g_val: u8 = if (g == 0) 0 else @intCast(55 + g * 40);
                    const b_val: u8 = if (b == 0) 0 else @intCast(55 + b * 40);
                    palette.colors[idx] = RGBColor{ .r = r_val, .g = g_val, .b = b_val };
                    idx += 1;
                }
            }
        }

        // 24-color grayscale ramp (colors 232-255)
        for (0..24) |i| {
            const gray: u8 = @intCast(8 + i * 10);
            palette.colors[232 + i] = RGBColor{ .r = gray, .g = gray, .b = gray };
        }

        return palette;
    }

    /// Find closest color in palette using perceptual distance
    pub fn findClosest(self: ANSI256Palette, target: RGBColor) u8 {
        var best_idx: u8 = 0;
        var best_distance: f32 = std.math.inf(f32);

        for (self.colors, 0..) |color, idx| {
            const distance = target.perceptualDistance(color);
            if (distance < best_distance) {
                best_distance = distance;
                best_idx = @intCast(idx);
            }
        }

        return best_idx;
    }

    /// Enhanced color conversion using HSLuv-based algorithm
    /// This provides better perceptual color matching for ANSI 256 colors
    pub fn convertTo256Enhanced(self: ANSI256Palette, target: RGBColor) u8 {
        // First try exact match for standard colors and exact cube matches
        const target_hsl = target.toHSL();

        // Check for exact matches in standard 16 colors (0-15)
        for (0..16) |i| {
            if (target.eql(self.colors[i])) {
                return @intCast(i);
            }
        }

        // Convert RGB to HSLuv for better perceptual matching
        const target_hsluv = target.toHSLuv();

        // For colors 16-231 (6x6x6 color cube), find closest using HSLuv distance
        var best_cube_idx: u8 = 16;
        var best_cube_distance: f64 = std.math.inf(f64);

        // Map HSLuv to 6x6x6 cube coordinates
        const h_norm = target_hsluv.h / 360.0;
        const s_norm = target_hsluv.s / 100.0;
        const l_norm = target_hsluv.l / 100.0;

        // Find the closest cube point
        const r_steps: [6]u8 = .{ 0, 95, 135, 175, 215, 255 };
        const g_steps: [6]u8 = .{ 0, 95, 135, 175, 215, 255 };
        const b_steps: [6]u8 = .{ 0, 95, 135, 175, 215, 255 };

        // Calculate cube coordinates
        const r_idx = @min(5, @as(u32, @intFromFloat(l_norm * 5.0)));
        const g_idx = @min(5, @as(u32, @intFromFloat(s_norm * 5.0)));
        const b_idx = @min(5, @as(u32, @intFromFloat(h_norm * 5.0)));

        const cube_r = r_steps[r_idx];
        const cube_g = g_steps[g_idx];
        const cube_b = b_steps[b_idx];

        // Check if this is an exact match
        if (cube_r == target.r and cube_g == target.g and cube_b == target.b) {
            const cube_idx = 16 + (r_idx * 36) + (g_idx * 6) + b_idx;
            return @intCast(cube_idx);
        }

        // For grayscale colors (232-255), use lightness-based mapping
        if (target_hsl.s < 10.0) { // Consider it grayscale if saturation is low
            const gray_avg = (target.r + target.g + target.b) / 3;
            if (gray_avg <= 8) return 232;
            if (gray_avg >= 238) return 255;

            const gray_idx = (gray_avg - 8) / 10;
            return @intCast(232 + @min(23, gray_idx));
        }

        // Use HSLuv distance to find the best cube match
        for (0..6) |r| {
            for (0..6) |g| {
                for (0..6) |b| {
                    const idx = 16 + (r * 36) + (g * 6) + b;
                    const cube_color = self.colors[idx];
                    const cube_hsluv = cube_color.toHSLuv();

                    const distance = target_hsluv.distance(cube_hsluv);
                    if (distance < best_cube_distance) {
                        best_cube_distance = distance;
                        best_cube_idx = @intCast(idx);
                    }
                }
            }
        }

        // Check if grayscale is closer
        const gray_avg = (target.r + target.g + target.b) / 3;
        if (gray_avg >= 8 and gray_avg <= 238) {
            const gray_idx = (gray_avg - 8) / 10;
            const gray_color_idx = 232 + @min(23, gray_idx);
            const gray_color = self.colors[gray_color_idx];
            const gray_distance = target.perceptualDistance(gray_color);

            if (gray_distance < best_cube_distance) {
                return @intCast(gray_color_idx);
            }
        }

        return best_cube_idx;
    }

    /// Get RGB color for ANSI color index
    pub fn getRGB(self: ANSI256Palette, index: u8) RGBColor {
        return self.colors[index];
    }
};

/// Theme-aware color palette manager
pub const ColorPalette = struct {
    allocator: std.mem.Allocator,
    ansi_palette: ANSI256Palette,
    capabilities: caps.TermCaps,
    current_theme: Theme = .auto,
    custom_colors: std.StringHashMap(RGBColor),

    const Self = @This();

    pub const Theme = enum {
        auto, // Detect from terminal
        light, // Light theme
        dark, // Dark theme
        custom, // User-defined theme
    };

    pub fn init(allocator: std.mem.Allocator, capabilities: caps.TermCaps) Self {
        return Self{
            .allocator = allocator,
            .ansi_palette = ANSI256Palette.init(),
            .capabilities = capabilities,
            .custom_colors = std.StringHashMap(RGBColor).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.custom_colors.deinit();
    }

    /// Convert any color to the best available format for current terminal
    pub fn adaptColor(self: Self, color: RGBColor) TerminalColor {
        if (self.capabilities.supports_truecolor) {
            return TerminalColor{ .rgb = color };
        } else if (self.capabilities.supports_256_color) {
            // Use enhanced HSLuv-based conversion for better perceptual accuracy
            const index = self.ansi_palette.convertTo256Enhanced(color);
            return TerminalColor{ .ansi256 = index };
        } else {
            // Convert to nearest 16-color ANSI
            const ansi256_index = self.ansi_palette.convertTo256Enhanced(color);
            const ansi16_index = self.convertTo16Color(ansi256_index);
            return TerminalColor{ .ansi16 = ansi16_index };
        }
    }

    /// Convert any color using the enhanced HSLuv-based algorithm
    pub fn adaptColorEnhanced(self: Self, color: RGBColor) TerminalColor {
        return self.adaptColor(color);
    }

    /// Convert 256-color index to 16-color approximation
    fn convertTo16Color(self: Self, ansi256_index: u8) u8 {
        _ = self;
        if (ansi256_index < 16) {
            return ansi256_index;
        } else if (ansi256_index >= 232) {
            // Grayscale ramp - convert to black/white/gray
            const gray_level = ansi256_index - 232;
            return if (gray_level < 8) 0 else if (gray_level < 16) 8 else 15;
        } else {
            // 6x6x6 color cube - approximate to nearest basic color
            const cube_index = ansi256_index - 16;
            const r = cube_index / 36;
            const g = (cube_index % 36) / 6;
            const b = cube_index % 6;

            // Convert to 16-color approximation
            const r16 = if (r >= 3) 1 else 0;
            const g16 = if (g >= 3) 1 else 0;
            const b16 = if (b >= 3) 1 else 0;

            return @intCast(r16 * 4 + g16 * 2 + b16 + (if (r + g + b > 9) @as(u32, 8) else 0));
        }
    }

    /// Define a named color in the palette
    pub fn defineColor(self: *Self, name: []const u8, color: RGBColor) !void {
        try self.custom_colors.put(try self.allocator.dupe(u8, name), color);
    }

    /// Get a named color from the palette
    pub fn getNamedColor(self: Self, name: []const u8) ?TerminalColor {
        if (self.custom_colors.get(name)) |color| {
            return self.adaptColor(color);
        }

        // Check for standard color names
        return self.getStandardColor(name);
    }

    /// Get standard color by name (red, green, blue, etc.)
    fn getStandardColor(self: Self, name: []const u8) ?TerminalColor {
        const color_map = std.ComptimeStringMap(RGBColor, .{
            .{ "black", RGBColor{ .r = 0, .g = 0, .b = 0 } },
            .{ "red", RGBColor{ .r = 255, .g = 0, .b = 0 } },
            .{ "green", RGBColor{ .r = 0, .g = 255, .b = 0 } },
            .{ "yellow", RGBColor{ .r = 255, .g = 255, .b = 0 } },
            .{ "blue", RGBColor{ .r = 0, .g = 0, .b = 255 } },
            .{ "magenta", RGBColor{ .r = 255, .g = 0, .b = 255 } },
            .{ "cyan", RGBColor{ .r = 0, .g = 255, .b = 255 } },
            .{ "white", RGBColor{ .r = 255, .g = 255, .b = 255 } },
            .{ "gray", RGBColor{ .r = 128, .g = 128, .b = 128 } },
            .{ "grey", RGBColor{ .r = 128, .g = 128, .b = 128 } },
        });

        if (color_map.get(name)) |color| {
            return self.adaptColor(color);
        }

        return null;
    }

    /// Generate a color scheme based on a base color
    pub fn generateColorScheme(self: Self, allocator: std.mem.Allocator, base_color: RGBColor) !ColorScheme {
        _ = allocator;
        const base_hsl = base_color.toHSL();
        const complement_hue = if (base_hsl.h >= 180) base_hsl.h - 180 else base_hsl.h + 180;

        // Create intermediate colors
        const secondary_hsl = base_hsl.adjustLightness(-20);
        const accent_hsl = HSLColor{ .h = complement_hue, .s = base_hsl.s, .l = base_hsl.l };
        const success_hsl = HSLColor{ .h = 120, .s = 50, .l = 50 };
        const warning_hsl = HSLColor{ .h = 45, .s = 80, .l = 60 };
        const err_hsl = HSLColor{ .h = 0, .s = 70, .l = 55 };
        const info_hsl = HSLColor{ .h = 200, .s = 60, .l = 55 };
        const muted_hsl = base_hsl.adjustSaturation(-30).adjustLightness(20);

        return ColorScheme{
            .primary = self.adaptColor(base_color),
            .secondary = self.adaptColor(secondary_hsl.toRGB()),
            .accent = self.adaptColor(accent_hsl.toRGB()),
            .success = self.adaptColor(success_hsl.toRGB()),
            .warning = self.adaptColor(warning_hsl.toRGB()),
            .err = self.adaptColor(err_hsl.toRGB()),
            .info = self.adaptColor(info_hsl.toRGB()),
            .muted = self.adaptColor(muted_hsl.toRGB()),
        };
    }
};

/// Terminal-adapted color representation
pub const TerminalColor = union(enum) {
    rgb: RGBColor, // 24-bit true color
    ansi256: u8, // 256-color palette index
    ansi16: u8, // 16-color ANSI index

    /// Get ANSI escape sequence for foreground color
    pub fn toANSIForeground(self: TerminalColor, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .rgb => |color| try std.fmt.allocPrint(allocator, "\x1b[38;2;{};{};{}m", .{ color.r, color.g, color.b }),
            .ansi256 => |idx| try std.fmt.allocPrint(allocator, "\x1b[38;5;{}m", .{idx}),
            .ansi16 => |idx| if (idx < 8)
                try std.fmt.allocPrint(allocator, "\x1b[3{}m", .{idx})
            else
                try std.fmt.allocPrint(allocator, "\x1b[9{}m", .{idx - 8}),
        };
    }

    /// Get ANSI escape sequence for background color
    pub fn toANSIBackground(self: TerminalColor, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .rgb => |color| try std.fmt.allocPrint(allocator, "\x1b[48;2;{};{};{}m", .{ color.r, color.g, color.b }),
            .ansi256 => |idx| try std.fmt.allocPrint(allocator, "\x1b[48;5;{}m", .{idx}),
            .ansi16 => |idx| if (idx < 8)
                try std.fmt.allocPrint(allocator, "\x1b[4{}m", .{idx})
            else
                try std.fmt.allocPrint(allocator, "\x1b[10{}m", .{idx - 8}),
        };
    }
};

/// Pre-defined color scheme for applications
pub const ColorScheme = struct {
    primary: TerminalColor,
    secondary: TerminalColor,
    accent: TerminalColor,
    success: TerminalColor,
    warning: TerminalColor,
    err: TerminalColor,
    info: TerminalColor,
    muted: TerminalColor,
};

// Tests
test "RGB to HSL conversion" {
    const testing = std.testing;

    const red = RGBColor{ .r = 255, .g = 0, .b = 0 };
    const hsl = red.toHSL();

    try testing.expectApproxEqAbs(hsl.h, 0.0, 1.0);
    try testing.expectApproxEqAbs(hsl.s, 100.0, 1.0);
    try testing.expectApproxEqAbs(hsl.l, 50.0, 1.0);
}

test "hex color parsing" {
    const testing = std.testing;

    const color = try RGBColor.fromHex("#FF0080");
    try testing.expect(color.r == 255);
    try testing.expect(color.g == 0);
    try testing.expect(color.b == 128);

    const color2 = try RGBColor.fromHex("00FF80");
    try testing.expect(color2.r == 0);
    try testing.expect(color2.g == 255);
    try testing.expect(color2.b == 128);
}

test "ANSI 256 palette initialization" {
    const testing = std.testing;

    const palette = ANSI256Palette.init();

    // Test standard colors
    try testing.expect(palette.colors[0].r == 0); // Black
    try testing.expect(palette.colors[9].r == 255); // Bright Red
    try testing.expect(palette.colors[15].r == 255); // White

    // Test grayscale ramp
    const dark_gray = palette.colors[232];
    const light_gray = palette.colors[255];
    try testing.expect(dark_gray.r == dark_gray.g and dark_gray.g == dark_gray.b);
    try testing.expect(light_gray.r > dark_gray.r);
}

test "color distance calculation" {
    const testing = std.testing;

    const red = RGBColor{ .r = 255, .g = 0, .b = 0 };
    const green = RGBColor{ .r = 0, .g = 255, .b = 0 };
    const dark_red = RGBColor{ .r = 128, .g = 0, .b = 0 };

    const red_green_dist = red.perceptualDistance(green);
    const red_dark_red_dist = red.perceptualDistance(dark_red);

    try testing.expect(red_dark_red_dist < red_green_dist);
}

test "color blending" {
    const testing = std.testing;

    const red = RGBColor{ .r = 255, .g = 0, .b = 0 };
    const blue = RGBColor{ .r = 0, .g = 0, .b = 255 };

    const blend = red.blend(blue, 0.5);
    try testing.expect(blend.r == 127); // Should be halfway between 255 and 0
    try testing.expect(blend.g == 0);
    try testing.expect(blend.b == 127); // Should be halfway between 0 and 255
}

test "enhanced HSLuv color conversion" {
    const testing = std.testing;

    const palette = ANSI256Palette.init();
    const red = RGBColor{ .r = 255, .g = 0, .b = 0 };

    // Test enhanced conversion
    const index = palette.convertTo256Enhanced(red);
    try testing.expect(index >= 0 and index <= 255);

    // Test HSLuv conversion
    const hsluv = red.toHSLuv();
    try testing.expect(hsluv.h >= 0.0 and hsluv.h <= 360.0);
    try testing.expect(hsluv.s >= 0.0 and hsluv.s <= 100.0);
    try testing.expect(hsluv.l >= 0.0 and hsluv.l <= 100.0);

    // Test HSLuv distance
    const blue = RGBColor{ .r = 0, .g = 0, .b = 255 };
    const blue_hsluv = blue.toHSLuv();
    const distance = hsluv.distance(blue_hsluv);
    try testing.expect(distance > 0.0);
}

test "RGB equality check" {
    const testing = std.testing;

    const color1 = RGBColor{ .r = 255, .g = 128, .b = 64 };
    const color2 = RGBColor{ .r = 255, .g = 128, .b = 64 };
    const color3 = RGBColor{ .r = 254, .g = 128, .b = 64 };

    try testing.expect(color1.eql(color2));
    try testing.expect(!color1.eql(color3));
}

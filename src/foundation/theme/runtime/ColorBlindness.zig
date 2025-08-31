//! Color Blindness Simulation and Adaptation
//! Simulates various types of color blindness and adapts themes accordingly

const std = @import("std");
const ColorScheme = @import("ColorScheme.zig").ColorScheme;
const ThemeColor = @import("color.zig");
const Color = ThemeColor.Color;
const RGB = ThemeColor.Rgb;

pub const ColorBlindness = struct {
    allocator: std.mem.Allocator,

    pub const ColorBlindnessType = enum {
        protanopia, // Red-blind (1% of males)
        protanomaly, // Red-weak (1% of males)
        deuteranopia, // Green-blind (1% of males)
        deuteranomaly, // Green-weak (6% of males)
        tritanopia, // Blue-blind (0.001% of population)
        tritanomaly, // Blue-weak (0.01% of population)
        achromatopsia, // Total color blindness (0.00003% of population)
        achromatomaly, // Partial color blindness
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    /// Simulate color blindness on a theme
    pub fn simulateColorBlindness(self: *Self, theme: *ColorScheme, cb_type: ColorBlindnessType) !*ColorScheme {
        const simulated = try ColorScheme.init(self.allocator);
        simulated.* = theme.*;
        simulated.name = try std.fmt.allocPrint(self.allocator, "{s} ({s} simulation)", .{ theme.name, @tagName(cb_type) });
        simulated.description = try std.fmt.allocPrint(self.allocator, "Color blindness simulation of {s}", .{theme.name});

        // Simulate color blindness on all colors
        simulated.background = self.simulateColorBlindnessOnColor(theme.background, cb_type);
        simulated.foreground = self.simulateColorBlindnessOnColor(theme.foreground, cb_type);
        simulated.primary = self.simulateColorBlindnessOnColor(theme.primary, cb_type);
        simulated.secondary = self.simulateColorBlindnessOnColor(theme.secondary, cb_type);
        simulated.success = self.simulateColorBlindnessOnColor(theme.success, cb_type);
        simulated.warning = self.simulateColorBlindnessOnColor(theme.warning, cb_type);
        simulated.errorColor = self.simulateColorBlindnessOnColor(theme.errorColor, cb_type);
        simulated.info = self.simulateColorBlindnessOnColor(theme.info, cb_type);

        // Simulate ANSI colors
        simulated.red = self.simulateColorBlindnessOnColor(theme.red, cb_type);
        simulated.green = self.simulateColorBlindnessOnColor(theme.green, cb_type);
        simulated.blue = self.simulateColorBlindnessOnColor(theme.blue, cb_type);
        simulated.yellow = self.simulateColorBlindnessOnColor(theme.yellow, cb_type);
        simulated.magenta = self.simulateColorBlindnessOnColor(theme.magenta, cb_type);
        simulated.cyan = self.simulateColorBlindnessOnColor(theme.cyan, cb_type);

        return simulated;
    }

    /// Adapt a theme for better color blindness accessibility
    pub fn adaptForColorBlindness(self: *Self, theme: *ColorScheme, cb_type: ColorBlindnessType) !*ColorScheme {
        const adapted = try ColorScheme.init(self.allocator);
        adapted.* = theme.*;
        adapted.name = try std.fmt.allocPrint(self.allocator, "{s} ({s} adapted)", .{ theme.name, @tagName(cb_type) });
        adapted.description = try std.fmt.allocPrint(self.allocator, "Color blindness adapted version of {s}", .{theme.name});

        switch (cb_type) {
            .protanopia, .protanomaly => {
                // Red-blind: enhance green/blue distinction
                adapted.errorColor = self.shiftToOrange(theme.errorColor);
                adapted.success = self.enhanceBlue(theme.success);
            },
            .deuteranopia, .deuteranomaly => {
                // Green-blind: enhance red/blue distinction
                adapted.success = self.shiftToBlue(theme.success);
                adapted.warning = self.enhanceOrange(theme.warning);
            },
            .tritanopia, .tritanomaly => {
                // Blue-blind: enhance red/green distinction
                adapted.info = self.shiftToGreen(theme.info);
                adapted.primary = self.shiftToRed(theme.primary);
            },
            .achromatopsia, .achromatomaly => {
                // Total color blindness: use patterns/brightness only
                adapted = try self.createMonochromeTheme(theme);
            },
        }

        return adapted;
    }

    /// Check if two colors are distinguishable for a given color blindness type
    pub fn areColorsDistinguishable(self: *Self, color1: RGB, color2: RGB, cb_type: ColorBlindnessType) bool {
        const sim1 = self.simulateColorBlindnessOnRGB(color1, cb_type);
        const sim2 = self.simulateColorBlindnessOnRGB(color2, cb_type);

        // Calculate color distance in RGB space
        const dr = @as(f32, @floatFromInt(@as(i32, sim1.r) - @as(i32, sim2.r)));
        const dg = @as(f32, @floatFromInt(@as(i32, sim1.g) - @as(i32, sim2.g)));
        const db = @as(f32, @floatFromInt(@as(i32, sim1.b) - @as(i32, sim2.b)));

        const distance = @sqrt(dr * dr + dg * dg + db * db);

        // Threshold for distinguishability (empirically determined)
        return distance > 30.0;
    }

    // Helper functions

    fn simulateColorBlindnessOnColor(self: *Self, color: Color, cb_type: ColorBlindnessType) Color {
        const simulated_rgb = self.simulateColorBlindnessOnRGB(color.rgb(), cb_type);
        return Color.fromRgb(color.name, simulated_rgb.r, simulated_rgb.g, simulated_rgb.b, color.alpha);
    }

    fn simulateColorBlindnessOnRGB(self: *Self, rgb: RGB, cb_type: ColorBlindnessType) RGB {
        _ = self;
        // Convert to linear RGB
        const r_lin = gammaExpand(@as(f32, @floatFromInt(rgb.r)) / 255.0);
        const g_lin = gammaExpand(@as(f32, @floatFromInt(rgb.g)) / 255.0);
        const b_lin = gammaExpand(@as(f32, @floatFromInt(rgb.b)) / 255.0);

        // Apply color blindness simulation matrix
        const matrix = switch (cb_type) {
            .protanopia => [_][3]f32{
                .{ 0.567, 0.433, 0.000 },
                .{ 0.558, 0.442, 0.000 },
                .{ 0.000, 0.242, 0.758 },
            },
            .protanomaly => [_][3]f32{
                .{ 0.817, 0.183, 0.000 },
                .{ 0.333, 0.667, 0.000 },
                .{ 0.000, 0.125, 0.875 },
            },
            .deuteranopia => [_][3]f32{
                .{ 0.625, 0.375, 0.000 },
                .{ 0.700, 0.300, 0.000 },
                .{ 0.000, 0.300, 0.700 },
            },
            .deuteranomaly => [_][3]f32{
                .{ 0.800, 0.200, 0.000 },
                .{ 0.258, 0.742, 0.000 },
                .{ 0.000, 0.142, 0.858 },
            },
            .tritanopia => [_][3]f32{
                .{ 0.950, 0.050, 0.000 },
                .{ 0.000, 0.433, 0.567 },
                .{ 0.000, 0.475, 0.525 },
            },
            .tritanomaly => [_][3]f32{
                .{ 0.967, 0.033, 0.000 },
                .{ 0.000, 0.733, 0.267 },
                .{ 0.000, 0.183, 0.817 },
            },
            .achromatopsia => [_][3]f32{
                .{ 0.299, 0.587, 0.114 },
                .{ 0.299, 0.587, 0.114 },
                .{ 0.299, 0.587, 0.114 },
            },
            .achromatomaly => [_][3]f32{
                .{ 0.618, 0.320, 0.062 },
                .{ 0.163, 0.775, 0.062 },
                .{ 0.163, 0.320, 0.516 },
            },
        };

        // Apply matrix transformation
        const new_r = matrix[0][0] * r_lin + matrix[0][1] * g_lin + matrix[0][2] * b_lin;
        const new_g = matrix[1][0] * r_lin + matrix[1][1] * g_lin + matrix[1][2] * b_lin;
        const new_b = matrix[2][0] * r_lin + matrix[2][1] * g_lin + matrix[2][2] * b_lin;

        // Convert back to sRGB
        return .{
            .r = @as(u8, @intFromFloat(@min(255, @max(0, gammaCompress(new_r) * 255)))),
            .g = @as(u8, @intFromFloat(@min(255, @max(0, gammaCompress(new_g) * 255)))),
            .b = @as(u8, @intFromFloat(@min(255, @max(0, gammaCompress(new_b) * 255)))),
        };
    }

    fn gammaExpand(value: f32) f32 {
        if (value <= 0.04045) {
            return value / 12.92;
        } else {
            return std.math.pow(f32, (value + 0.055) / 1.055, 2.4);
        }
    }

    fn gammaCompress(value: f32) f32 {
        if (value <= 0.0031308) {
            return value * 12.92;
        } else {
            return 1.055 * std.math.pow(f32, value, 1.0 / 2.4) - 0.055;
        }
    }

    fn shiftToOrange(self: *Self, color: Color) Color {
        _ = self;
        // Shift reds toward orange for better protanopia visibility
        const hsl = rgbToHsl(color.rgb());
        var adjusted = hsl;
        if (hsl.h < 30 or hsl.h > 330) { // Red range
            adjusted.h = 30; // Orange
        }
        const rgb = hslToRgb(adjusted);
        return Color.fromRgb(color.name, rgb.r, rgb.g, rgb.b, color.alpha);
    }

    fn enhanceBlue(self: *Self, color: Color) Color {
        _ = self;
        // Enhance blue component for protanopia
        var adjusted = color.rgb();
        adjusted.b = @min(255, adjusted.b + 50);
        return Color.fromRgb(color.name, adjusted.r, adjusted.g, adjusted.b, color.alpha);
    }

    fn shiftToBlue(self: *Self, color: Color) Color {
        _ = self;
        // Shift greens toward blue for deuteranopia
        const hsl = rgbToHsl(color.rgb());
        var adjusted = hsl;
        if (hsl.h > 90 and hsl.h < 150) { // Green range
            adjusted.h = 210; // Blue
        }
        const rgb = hslToRgb(adjusted);
        return Color.fromRgb(color.name, rgb.r, rgb.g, rgb.b, color.alpha);
    }

    fn enhanceOrange(self: *Self, color: Color) Color {
        _ = self;
        // Enhance orange for deuteranopia
        const hsl = rgbToHsl(color.rgb());
        var adjusted = hsl;
        if (hsl.h > 30 and hsl.h < 90) { // Yellow range
            adjusted.h = 30; // Orange
            adjusted.s = @min(1.0, adjusted.s * 1.2);
        }
        const rgb = hslToRgb(adjusted);
        return Color.fromRgb(color.name, rgb.r, rgb.g, rgb.b, color.alpha);
    }

    fn shiftToGreen(self: *Self, color: Color) Color {
        _ = self;
        // Shift blues toward green for tritanopia
        const hsl = rgbToHsl(color.rgb());
        var adjusted = hsl;
        if (hsl.h > 180 and hsl.h < 270) { // Blue range
            adjusted.h = 120; // Green
        }
        const rgb = hslToRgb(adjusted);
        return Color.fromRgb(color.name, rgb.r, rgb.g, rgb.b, color.alpha);
    }

    fn shiftToRed(self: *Self, color: Color) Color {
        _ = self;
        // Shift blues toward red for tritanopia
        const hsl = rgbToHsl(color.rgb());
        var adjusted = hsl;
        if (hsl.h > 180 and hsl.h < 270) { // Blue range
            adjusted.h = 0; // Red
        }
        const rgb = hslToRgb(adjusted);
        return Color.fromRgb(color.name, rgb.r, rgb.g, rgb.b, color.alpha);
    }

    fn createMonochromeTheme(self: *Self, theme: *ColorScheme) !*ColorScheme {
        const mono = try ColorScheme.init(self.allocator);
        mono.* = theme.*;

        // Convert all colors to grayscale with different brightness levels
        mono.background = self.toGrayscale(theme.background, 0.0);
        mono.foreground = self.toGrayscale(theme.foreground, 1.0);
        mono.primary = self.toGrayscale(theme.primary, 0.8);
        mono.secondary = self.toGrayscale(theme.secondary, 0.6);
        mono.success = self.toGrayscale(theme.success, 0.7);
        mono.warning = self.toGrayscale(theme.warning, 0.85);
        mono.errorColor = self.toGrayscale(theme.errorColor, 0.9);
        mono.info = self.toGrayscale(theme.info, 0.65);

        return mono;
    }

    fn toGrayscale(self: *Self, color: Color, brightness: f32) Color {
        _ = self;
        const gray_value = @as(u8, @intFromFloat(brightness * 255));
        return Color.fromRgb(color.name, gray_value, gray_value, gray_value, color.alpha);
    }
};

// Local helpers for HSL conversion
fn rgbToHsl(c: RGB) ThemeColor.Hsl {
    const rf: f32 = @as(f32, @floatFromInt(c.r)) / 255.0;
    const gf: f32 = @as(f32, @floatFromInt(c.g)) / 255.0;
    const bf: f32 = @as(f32, @floatFromInt(c.b)) / 255.0;
    const maxc = @max(rf, @max(gf, bf));
    const minc = @min(rf, @min(gf, bf));
    const delta = maxc - minc;
    var h: f32 = 0.0;
    var s: f32 = 0.0;
    const l: f32 = (maxc + minc) / 2.0;
    if (delta != 0.0) {
        s = if (l > 0.5) delta / (2.0 - maxc - minc) else delta / (maxc + minc);
        if (maxc == rf) {
            h = (gf - bf) / delta + (if (gf < bf) 6.0 else 0.0);
        } else if (maxc == gf) {
            h = (bf - rf) / delta + 2.0;
        } else {
            h = (rf - gf) / delta + 4.0;
        }
        h *= 60.0;
    }
    return .{ .h = h, .s = s, .l = l };
}

fn hslToRgb(hsl: ThemeColor.Hsl) RGB {
    if (hsl.s == 0.0) {
        const v = @as(u8, @intFromFloat(@round(hsl.l * 255.0)));
        return .{ .r = v, .g = v, .b = v };
    }
    const c = (1.0 - @abs(2.0 * hsl.l - 1.0)) * hsl.s;
    var hh = hsl.h;
    while (hh < 0.0) hh += 360.0;
    while (hh >= 360.0) hh -= 360.0;
    const hprime = hh / 60.0;
    const x = c * (1.0 - @abs(@mod(hprime, 2.0) - 1.0));
    var rf: f32 = 0.0;
    var gf: f32 = 0.0;
    var bf: f32 = 0.0;
    if (hprime < 1.0) {
        rf = c;
        gf = x;
        bf = 0.0;
    } else if (hprime < 2.0) {
        rf = x;
        gf = c;
        bf = 0.0;
    } else if (hprime < 3.0) {
        rf = 0.0;
        gf = c;
        bf = x;
    } else if (hprime < 4.0) {
        rf = 0.0;
        gf = x;
        bf = c;
    } else if (hprime < 5.0) {
        rf = x;
        gf = 0.0;
        bf = c;
    } else {
        rf = c;
        gf = 0.0;
        bf = x;
    }
    const m = hsl.l - c / 2.0;
    const r = @as(u8, @intFromFloat(@round((rf + m) * 255.0)));
    const g = @as(u8, @intFromFloat(@round((gf + m) * 255.0)));
    const b = @as(u8, @intFromFloat(@round((bf + m) * 255.0)));
    return .{ .r = r, .g = g, .b = b };
}

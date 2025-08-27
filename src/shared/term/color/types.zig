//! Core Color Types
//! Unified color type definitions for all color spaces
//! Consolidates duplicated RGB, HSL, HSV, Lab, XYZ definitions

const std = @import("std");

// === ERROR TYPES ===

pub const ColorError = error{
    InvalidHexColor,
    InvalidColorFormat,
    InvalidColorSpace,
    InvalidColorString,
    InvalidComponent,
    OutOfRange,
    ConversionError,
    PaletteNotFound,
    InvalidPaletteIndex,
};

// === RGB COLOR SPACE ===

/// 24-bit RGB color (8 bits per channel)
pub const RGB = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RGB {
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn fromHex(hex: u32) RGB {
        return .{
            .r = @intCast((hex >> 16) & 0xFF),
            .g = @intCast((hex >> 8) & 0xFF),
            .b = @intCast(hex & 0xFF),
        };
    }

    pub fn toHex(self: RGB) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }

    pub fn toNormalized(self: RGB) RGBf {
        return .{
            .r = @as(f32, @floatFromInt(self.r)) / 255.0,
            .g = @as(f32, @floatFromInt(self.g)) / 255.0,
            .b = @as(f32, @floatFromInt(self.b)) / 255.0,
        };
    }

    pub fn equals(self: RGB, other: RGB) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b;
    }

    pub fn format(self: RGB, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("RGB({d},{d},{d})", .{ self.r, self.g, self.b });
    }
};

/// RGBA color with alpha channel
pub const RGBA = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn init(r: u8, g: u8, b: u8, a: u8) RGBA {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn fromRGB(rgb: RGB, alpha: u8) RGBA {
        return .{ .r = rgb.r, .g = rgb.g, .b = rgb.b, .a = alpha };
    }

    pub fn toRGB(self: RGBA) RGB {
        return RGB.init(self.r, self.g, self.b);
    }

    pub fn format(self: RGBA, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("RGBA({d},{d},{d},{d})", .{ self.r, self.g, self.b, self.a });
    }
};

/// Normalized RGB color (floating point 0.0-1.0)
pub const RGBf = struct {
    r: f32,
    g: f32,
    b: f32,

    pub fn init(r: f32, g: f32, b: f32) RGBf {
        return .{
            .r = std.math.clamp(r, 0.0, 1.0),
            .g = std.math.clamp(g, 0.0, 1.0),
            .b = std.math.clamp(b, 0.0, 1.0),
        };
    }

    pub fn toRGB(self: RGBf) RGB {
        return RGB.init(
            @intFromFloat(self.r * 255.0),
            @intFromFloat(self.g * 255.0),
            @intFromFloat(self.b * 255.0),
        );
    }

    pub fn format(self: RGBf, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("RGBf({d:.3},{d:.3},{d:.3})", .{ self.r, self.g, self.b });
    }
};

// === HSL COLOR SPACE ===

/// HSL color space (Hue, Saturation, Lightness)
pub const HSL = struct {
    h: f32, // 0-360 degrees
    s: f32, // 0-100 percent
    l: f32, // 0-100 percent

    pub fn init(h: f32, s: f32, l: f32) HSL {
        return .{
            .h = @mod(h, 360.0),
            .s = std.math.clamp(s, 0.0, 100.0),
            .l = std.math.clamp(l, 0.0, 100.0),
        };
    }

    pub fn format(self: HSL, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("HSL({d:.1}°,{d:.1}%,{d:.1}%)", .{ self.h, self.s, self.l });
    }
};

// === HSV COLOR SPACE ===

/// HSV color space (Hue, Saturation, Value/Brightness)
pub const HSV = struct {
    h: f32, // 0-360 degrees
    s: f32, // 0-100 percent
    v: f32, // 0-100 percent

    pub fn init(h: f32, s: f32, v: f32) HSV {
        return .{
            .h = @mod(h, 360.0),
            .s = std.math.clamp(s, 0.0, 100.0),
            .v = std.math.clamp(v, 0.0, 100.0),
        };
    }

    pub fn format(self: HSV, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("HSV({d:.1}°,{d:.1}%,{d:.1}%)", .{ self.h, self.s, self.v });
    }
};

// === LAB COLOR SPACE ===

/// CIE L*a*b* color space (perceptually uniform)
pub const Lab = struct {
    l: f32, // 0-100 lightness
    a: f32, // -128 to 127 green-red
    b: f32, // -128 to 127 blue-yellow

    pub fn init(l: f32, a: f32, b: f32) Lab {
        return .{
            .l = std.math.clamp(l, 0.0, 100.0),
            .a = std.math.clamp(a, -128.0, 127.0),
            .b = std.math.clamp(b, -128.0, 127.0),
        };
    }

    pub fn format(self: Lab, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("Lab({d:.1},{d:.1},{d:.1})", .{ self.l, self.a, self.b });
    }
};

// === XYZ COLOR SPACE ===

/// CIE XYZ color space (tristimulus values)
pub const XYZ = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) XYZ {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn format(self: XYZ, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("XYZ({d:.3},{d:.3},{d:.3})", .{ self.x, self.y, self.z });
    }
};

// === TERMINAL COLOR TYPES ===

/// ANSI 16-color palette index (0-15)
pub const Ansi16 = enum(u4) {
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

    pub fn toRGB(self: Ansi16) RGB {
        return switch (self) {
            .black => RGB.init(0, 0, 0),
            .red => RGB.init(205, 49, 49),
            .green => RGB.init(13, 188, 121),
            .yellow => RGB.init(229, 229, 16),
            .blue => RGB.init(36, 114, 200),
            .magenta => RGB.init(188, 63, 188),
            .cyan => RGB.init(17, 168, 205),
            .white => RGB.init(229, 229, 229),
            .bright_black => RGB.init(102, 102, 102),
            .bright_red => RGB.init(241, 76, 76),
            .bright_green => RGB.init(35, 209, 139),
            .bright_yellow => RGB.init(245, 245, 67),
            .bright_blue => RGB.init(59, 142, 234),
            .bright_magenta => RGB.init(214, 112, 214),
            .bright_cyan => RGB.init(41, 184, 219),
            .bright_white => RGB.init(255, 255, 255),
        };
    }
};

/// 256-color palette index (0-255)
pub const Ansi256 = struct {
    index: u8,

    pub fn init(index: u8) Ansi256 {
        return .{ .index = index };
    }

    pub fn fromRGB(rgb: RGB) Ansi256 {
        // This will be implemented in conversions.zig
        _ = rgb;
        return .{ .index = 0 };
    }

    pub fn toRGB(self: Ansi256) RGB {
        // Basic implementation - full algorithm in conversions.zig
        if (self.index < 16) {
            const ansi16: Ansi16 = @enumFromInt(@as(u4, @intCast(self.index)));
            return ansi16.toRGB();
        }
        // Placeholder for 216-color cube and grayscale
        return RGB.init(0, 0, 0);
    }
};

/// Terminal color representation
pub const TerminalColor = union(enum) {
    default,
    ansi16: Ansi16,
    ansi256: Ansi256,
    rgb: RGB,

    pub fn format(self: TerminalColor, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            .default => try writer.writeAll("default"),
            .ansi16 => |c| try writer.print("ansi16({d})", .{@intFromEnum(c)}),
            .ansi256 => |c| try writer.print("ansi256({d})", .{c.index}),
            .rgb => |c| try writer.print("rgb({d},{d},{d})", .{ c.r, c.g, c.b }),
        }
    }

    pub fn toRGB(self: TerminalColor) ?RGB {
        return switch (self) {
            .default => null,
            .ansi16 => |c| c.toRGB(),
            .ansi256 => |c| c.toRGB(),
            .rgb => |c| c,
        };
    }
};

// === COLOR CONSTANTS ===

pub const named_colors = struct {
    pub const black = RGB.init(0, 0, 0);
    pub const white = RGB.init(255, 255, 255);
    pub const red = RGB.init(255, 0, 0);
    pub const green = RGB.init(0, 255, 0);
    pub const blue = RGB.init(0, 0, 255);
    pub const yellow = RGB.init(255, 255, 0);
    pub const cyan = RGB.init(0, 255, 255);
    pub const magenta = RGB.init(255, 0, 255);
    pub const gray = RGB.init(128, 128, 128);
    pub const orange = RGB.init(255, 165, 0);
    pub const purple = RGB.init(128, 0, 128);
    pub const brown = RGB.init(165, 42, 42);
};

// === TESTS ===

test "RGB conversions" {
    const rgb = RGB.init(255, 128, 64);
    const hex = rgb.toHex();
    try std.testing.expectEqual(@as(u32, 0xFF8040), hex);

    const rgb2 = RGB.fromHex(0xFF8040);
    try std.testing.expect(rgb.equals(rgb2));

    const normalized = rgb.toNormalized();
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), normalized.r, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.502), normalized.g, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.251), normalized.b, 0.01);
}

test "ANSI16 colors" {
    const red = Ansi16.red;
    const rgb = red.toRGB();
    try std.testing.expectEqual(@as(u8, 205), rgb.r);
    try std.testing.expectEqual(@as(u8, 49), rgb.g);
    try std.testing.expectEqual(@as(u8, 49), rgb.b);
}

test "TerminalColor formatting" {
    const colors = [_]TerminalColor{
        .default,
        .{ .ansi16 = .red },
        .{ .ansi256 = Ansi256.init(196) },
        .{ .rgb = RGB.init(255, 0, 0) },
    };

    for (colors) |color| {
        var buf: [100]u8 = undefined;
        const result = try std.fmt.bufPrint(&buf, "{}", .{color});
        try std.testing.expect(result.len > 0);
    }
}

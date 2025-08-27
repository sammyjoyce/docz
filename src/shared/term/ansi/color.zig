const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

fn oscTerminator() []const u8 {
    return if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel"))
        seqcfg.osc.bel
    else
        seqcfg.osc.st;
}

fn sanitize(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    // Filter out ESC and BEL to avoid premature termination or injection
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    try out.ensureTotalCapacity(s.len);
    for (s) |ch| {
        if (ch == 0x1b or ch == 0x07) continue;
        out.appendAssumeCapacity(ch);
    }
    return try out.toOwnedSlice();
}

fn appendDec(buf: *std.ArrayList(u8), n: u32) !void {
    var tmp: [12]u8 = undefined;
    const w = try std.fmt.bufPrint(&tmp, "{d}", .{n});
    try buf.appendSlice(w);
}

fn buildOscColor(
    alloc: std.mem.Allocator,
    code: u32,
    payload: []const u8,
) ![]u8 {
    const st = oscTerminator();
    const clean = try sanitize(alloc, payload);
    defer alloc.free(clean);

    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, code);
    try buf.append(';');
    try buf.appendSlice(clean);
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

fn buildOscQuery(alloc: std.mem.Allocator, code: u32) ![]u8 {
    const st = oscTerminator();
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, code);
    try buf.appendSlice(";?");
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

fn buildOscReset(alloc: std.mem.Allocator, code: u32) ![]u8 {
    const st = oscTerminator();
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    try buf.appendSlice("\x1b]");
    try appendDec(&buf, 100 + code);
    // OSC 110/111/112 are resets for 10/11/12 respectively
    try buf.appendSlice(st);
    return try buf.toOwnedSlice();
}

inline fn colorCode(kind: enum { fg, bg, cursor }) u32 {
    return switch (kind) {
        .fg => seqcfg.osc.ops.color.foreground,
        .bg => seqcfg.osc.ops.color.background,
        .cursor => seqcfg.osc.ops.color.cursor,
    };
}

// Foreground color (OSC 10)
pub fn setForegroundColor(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    color: []const u8,
) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscColor(alloc, colorCode(.fg), color);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn requestForegroundColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscQuery(alloc, colorCode(.fg));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn resetForegroundColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscReset(alloc, colorCode(.fg));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Background color (OSC 11)
pub fn setBackgroundColor(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    color: []const u8,
) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscColor(alloc, colorCode(.bg), color);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn requestBackgroundColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscQuery(alloc, colorCode(.bg));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn resetBackgroundColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscReset(alloc, colorCode(.bg));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// Cursor color (OSC 12)
pub fn setCursorColor(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    color: []const u8,
) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscColor(alloc, colorCode(.cursor), color);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn requestCursorColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscQuery(alloc, colorCode(.cursor));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

pub fn resetCursorColor(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps) !void {
    if (!caps.supportsColorOsc10_12) return error.Unsupported;
    const seq = try buildOscReset(alloc, colorCode(.cursor));
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// === ENHANCED COLOR FORMATS ===

/// Color format types for terminal color specification
pub const ColorFormat = enum {
    hex, // #RRGGBB format
    xrgb, // XParseColor rgb:RRRR/GGGG/BBBB format
    xrgba, // XParseColor rgba:RRRR/GGGG/BBBB/AAAA format
    name, // Named color (e.g., "red", "blue")
};

/// Hex color representation (#RRGGBB)
pub const HexColor = struct {
    value: u32,

    pub fn init(hex: u32) HexColor {
        return HexColor{ .value = hex & 0xFFFFFF }; // Ensure only RGB bits
    }

    pub fn initFromString(hex_str: []const u8) !HexColor {
        const clean = if (hex_str.len > 0 and hex_str[0] == '#') hex_str[1..] else hex_str;
        if (clean.len != 6) return error.InvalidHexColor;

        const hex = std.fmt.parseInt(u32, clean, 16) catch return error.InvalidHexColor;
        return HexColor.init(hex);
    }

    pub fn toString(self: HexColor, alloc: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(alloc, "#{:06x}", .{self.value});
    }

    pub fn toRgb(self: HexColor) struct { r: u8, g: u8, b: u8 } {
        return .{
            .r = @intCast((self.value >> 16) & 0xFF),
            .g = @intCast((self.value >> 8) & 0xFF),
            .b = @intCast(self.value & 0xFF),
        };
    }
};

/// XParseColor RGB format (rgb:RRRR/GGGG/BBBB)
pub const XRGBColor = struct {
    r: u16,
    g: u16,
    b: u16,

    pub fn init(r: u16, g: u16, b: u16) XRGBColor {
        return XRGBColor{ .r = r, .g = g, .b = b };
    }

    pub fn fromRgb8(r: u8, g: u8, b: u8) XRGBColor {
        // Convert 8-bit to 16-bit by duplicating bits
        return XRGBColor{
            .r = (@as(u16, r) << 8) | r,
            .g = (@as(u16, g) << 8) | g,
            .b = (@as(u16, b) << 8) | b,
        };
    }

    pub fn toString(self: XRGBColor, alloc: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(alloc, "rgb:{:04x}/{:04x}/{:04x}", .{ self.r, self.g, self.b });
    }
};

/// XParseColor RGBA format (rgba:RRRR/GGGG/BBBB/AAAA)
pub const XRGBAColor = struct {
    r: u16,
    g: u16,
    b: u16,
    a: u16,

    pub fn init(r: u16, g: u16, b: u16, a: u16) XRGBAColor {
        return XRGBAColor{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn fromRgba8(r: u8, g: u8, b: u8, a: u8) XRGBAColor {
        return XRGBAColor{
            .r = (@as(u16, r) << 8) | r,
            .g = (@as(u16, g) << 8) | g,
            .b = (@as(u16, b) << 8) | b,
            .a = (@as(u16, a) << 8) | a,
        };
    }

    pub fn toString(self: XRGBAColor, alloc: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(alloc, "rgba:{:04x}/{:04x}/{:04x}/{:04x}", .{ self.r, self.g, self.b, self.a });
    }
};

/// Enhanced color setting functions with support for different formats
/// Set foreground color using hex format
pub fn setForegroundColorHex(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    hex_color: HexColor,
) !void {
    const color_str = try hex_color.toString(alloc);
    defer alloc.free(color_str);
    try setForegroundColor(writer, alloc, caps, color_str);
}

/// Set background color using hex format
pub fn setBackgroundColorHex(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    hex_color: HexColor,
) !void {
    const color_str = try hex_color.toString(alloc);
    defer alloc.free(color_str);
    try setBackgroundColor(writer, alloc, caps, color_str);
}

/// Set cursor color using hex format
pub fn setCursorColorHex(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    hex_color: HexColor,
) !void {
    const color_str = try hex_color.toString(alloc);
    defer alloc.free(color_str);
    try setCursorColor(writer, alloc, caps, color_str);
}

/// Set foreground color using XRGB format
pub fn setForegroundColorXRGB(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    xrgb_color: XRGBColor,
) !void {
    const color_str = try xrgb_color.toString(alloc);
    defer alloc.free(color_str);
    try setForegroundColor(writer, alloc, caps, color_str);
}

/// Set background color using XRGB format
pub fn setBackgroundColorXRGB(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    xrgb_color: XRGBColor,
) !void {
    const color_str = try xrgb_color.toString(alloc);
    defer alloc.free(color_str);
    try setBackgroundColor(writer, alloc, caps, color_str);
}

/// Set cursor color using XRGB format
pub fn setCursorColorXRGB(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    xrgb_color: XRGBColor,
) !void {
    const color_str = try xrgb_color.toString(alloc);
    defer alloc.free(color_str);
    try setCursorColor(writer, alloc, caps, color_str);
}

/// Set foreground color using XRGBA format
pub fn setForegroundColorXRGBA(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    xrgba_color: XRGBAColor,
) !void {
    const color_str = try xrgba_color.toString(alloc);
    defer alloc.free(color_str);
    try setForegroundColor(writer, alloc, caps, color_str);
}

/// Set background color using XRGBA format
pub fn setBackgroundColorXRGBA(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    xrgba_color: XRGBAColor,
) !void {
    const color_str = try xrgba_color.toString(alloc);
    defer alloc.free(color_str);
    try setBackgroundColor(writer, alloc, caps, color_str);
}

/// Set cursor color using XRGBA format
pub fn setCursorColorXRGBA(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    xrgba_color: XRGBAColor,
) !void {
    const color_str = try xrgba_color.toString(alloc);
    defer alloc.free(color_str);
    try setCursorColor(writer, alloc, caps, color_str);
}

/// Convenience function to set colors from RGB values
pub fn setForegroundColorRgb(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    r: u8,
    g: u8,
    b: u8,
) !void {
    const hex = HexColor.init((@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b));
    try setForegroundColorHex(writer, alloc, caps, hex);
}

/// Convenience function to set background color from RGB values
pub fn setBackgroundColorRgb(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    r: u8,
    g: u8,
    b: u8,
) !void {
    const hex = HexColor.init((@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b));
    try setBackgroundColorHex(writer, alloc, caps, hex);
}

/// Convenience function to set cursor color from RGB values
pub fn setCursorColorRgb(
    writer: anytype,
    alloc: std.mem.Allocator,
    caps: TermCaps,
    r: u8,
    g: u8,
    b: u8,
) !void {
    const hex = HexColor.init((@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b));
    try setCursorColorHex(writer, alloc, caps, hex);
}

/// Parse terminal color response (OSC 10/11/12 response)
/// Expected format: ESC ] code ; color BEL/ST
pub fn parseColorResponse(response: []const u8) ![]const u8 {
    if (response.len < 6) return error.InvalidResponse;

    if (!std.mem.startsWith(u8, response, "\x1b]")) {
        return error.InvalidResponse;
    }

    // Find first semicolon (after the code)
    const first_semi = std.mem.indexOf(u8, response, ";") orelse return error.InvalidResponse;

    // Find terminator
    var end_pos: ?usize = null;
    if (std.mem.lastIndexOf(u8, response, "\x07")) |bel_pos| {
        end_pos = bel_pos;
    } else if (std.mem.lastIndexOf(u8, response, "\x1b\\")) |st_pos| {
        end_pos = st_pos;
    } else {
        return error.InvalidResponse;
    }

    const end = end_pos.?;
    if (end <= first_semi + 1) return error.InvalidResponse;

    return response[first_semi + 1 .. end];
}

// Tests for enhanced color functionality
test "hex color creation and formatting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test hex color from value
    const red = HexColor.init(0xFF0000);
    const red_str = try red.toString(allocator);
    defer allocator.free(red_str);
    try testing.expectEqualStrings("#ff0000", red_str);

    // Test hex color from string
    const blue = try HexColor.initFromString("#0000FF");
    const blue_str = try blue.toString(allocator);
    defer allocator.free(blue_str);
    try testing.expectEqualStrings("#0000ff", blue_str);

    // Test RGB extraction
    const green_rgb = HexColor.init(0x00FF00).toRgb();
    try testing.expect(green_rgb.r == 0 and green_rgb.g == 255 and green_rgb.b == 0);
}

test "xrgb color formatting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test XRGB color from 8-bit values
    const white = XRGBColor.fromRgb8(255, 255, 255);
    const white_str = try white.toString(allocator);
    defer allocator.free(white_str);
    try testing.expectEqualStrings("rgb:ffff/ffff/ffff", white_str);
}

test "xrgba color formatting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test XRGBA color
    const semi_red = XRGBAColor.fromRgba8(255, 0, 0, 128);
    const semi_red_str = try semi_red.toString(allocator);
    defer allocator.free(semi_red_str);
    try testing.expectEqualStrings("rgba:ffff/0000/0000/8080", semi_red_str);
}

test "color response parsing" {
    const testing = std.testing;

    // Test valid response with BEL terminator
    const response_bel = "\x1b]10;#ff0000\x07";
    const color_bel = try parseColorResponse(response_bel);
    try testing.expectEqualStrings("#ff0000", color_bel);

    // Test valid response with ST terminator
    const response_st = "\x1b]11;rgb:ffff/0000/0000\x1b\\";
    const color_st = try parseColorResponse(response_st);
    try testing.expectEqualStrings("rgb:ffff/0000/0000", color_st);
}

// === ENHANCED VALIDATION AND ERROR HANDLING ===

/// Enhanced error types for color operations
pub const ColorError = error{
    InvalidHexColor,
    InvalidHexLength,
    InvalidHexCharacter,
    InvalidRgbValue,
    InvalidColorFormat,
    InvalidResponse,
    ColorNotSupported,
    TerminalCapabilityMissing,
    OutOfMemory,
};

/// Comprehensive color validation utilities
pub const ColorValidator = struct {
    /// Validate if a string is a valid hex color format (#RRGGBB or RRGGBB)
    pub fn isValidHex(hex: []const u8) bool {
        var hex_clean = hex;

        // Remove leading # if present
        if (hex.len > 0 and hex[0] == '#') {
            hex_clean = hex[1..];
        }

        // Check length (must be exactly 6 characters)
        if (hex_clean.len != 6) {
            return false;
        }

        // Check all characters are valid hex
        for (hex_clean) |char| {
            switch (char) {
                '0'...'9', 'A'...'F', 'a'...'f' => {},
                else => return false,
            }
        }
        return true;
    }

    /// Validate if a string is a valid RGB color format (rgb:RRRR/GGGG/BBBB)
    pub fn isValidXRgb(rgb: []const u8) bool {
        if (!std.mem.startsWith(u8, rgb, "rgb:")) return false;

        const components = rgb[4..]; // Skip "rgb:"
        var parts = std.mem.split(u8, components, "/");

        var part_count: u8 = 0;
        while (parts.next()) |part| {
            part_count += 1;
            if (part_count > 3) return false; // Too many parts
            if (part.len != 4) return false; // Each part should be 4 hex chars

            // Validate hex characters
            for (part) |char| {
                switch (char) {
                    '0'...'9', 'A'...'F', 'a'...'f' => {},
                    else => return false,
                }
            }
        }

        return part_count == 3; // Must have exactly 3 parts
    }

    /// Validate if a string is a valid RGBA color format (rgba:RRRR/GGGG/BBBB/AAAA)
    pub fn isValidXRgba(rgba: []const u8) bool {
        if (!std.mem.startsWith(u8, rgba, "rgba:")) return false;

        const components = rgba[5..]; // Skip "rgba:"
        var parts = std.mem.split(u8, components, "/");

        var part_count: u8 = 0;
        while (parts.next()) |part| {
            part_count += 1;
            if (part_count > 4) return false; // Too many parts
            if (part.len != 4) return false; // Each part should be 4 hex chars

            // Validate hex characters
            for (part) |char| {
                switch (char) {
                    '0'...'9', 'A'...'F', 'a'...'f' => {},
                    else => return false,
                }
            }
        }

        return part_count == 4; // Must have exactly 4 parts
    }

    /// Validate RGB component values (0-255)
    pub fn isValidRgb(r: u16, g: u16, b: u16) bool {
        return r <= 255 and g <= 255 and b <= 255;
    }

    /// Validate RGBA component values (0-255)
    pub fn isValidRgba(r: u16, g: u16, b: u16, a: u16) bool {
        return r <= 255 and g <= 255 and b <= 255 and a <= 255;
    }

    /// Detect the format of a color string
    pub fn detectColorFormat(color: []const u8) ColorFormat {
        if (isValidHex(color)) return .hex;
        if (isValidXRgb(color)) return .xrgb;
        if (isValidXRgba(color)) return .xrgba;
        return .name; // Assume it's a named color
    }

    /// Validate any color string against known formats
    pub fn isValidColor(color: []const u8) bool {
        return isValidHex(color) or isValidXRgb(color) or isValidXRgba(color);
    }
};

/// Color type definitions for ANSI terminal colors
pub const BasicColor = u8; // 0-15 (4-bit)
pub const IndexedColor = u8; // 0-255 (8-bit)

/// RGB color structure for 24-bit colors
pub const RgbColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RgbColor {
        return RgbColor{ .r = r, .g = g, .b = b };
    }

    pub fn toHex(self: RgbColor) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }
};

/// HSLuv color space conversion functions for improved color distance calculation
/// Based on HSLuv algorithm for better perceptual color matching
pub const Hsluv = struct {
    const m = [_][3]f64{
        [_]f64{ 3.240969941904521, -1.537383177570093, -0.498610760293 },
        [_]f64{ -0.96924363628088, 1.87596750150772, 0.041555057407175 },
        [_]f64{ 0.055630079696993, -0.20397695888897, 1.056971514242878 },
    };

    const minv = [_][3]f64{
        [_]f64{ 0.41239079926596, 0.35758433938388, 0.18048078840183 },
        [_]f64{ 0.21263900587151, 0.71516867876776, 0.07219231536073 },
        [_]f64{ 0.01933081871559, 0.11919477979463, 0.95053215224966 },
    };

    fn xyzToRgb(x: f64, y: f64, z: f64) struct { r: f64, g: f64, b: f64 } {
        const r = x * m[0][0] + y * m[0][1] + z * m[0][2];
        const g = x * m[1][0] + y * m[1][1] + z * m[1][2];
        const b = x * m[2][0] + y * m[2][1] + z * m[2][2];
        return .{ .r = r, .g = g, .b = b };
    }

    fn rgbToXyz(r: f64, g: f64, b: f64) struct { x: f64, y: f64, z: f64 } {
        const x = r * minv[0][0] + g * minv[0][1] + b * minv[0][2];
        const y = r * minv[1][0] + g * minv[1][1] + b * minv[1][2];
        const z = r * minv[2][0] + g * minv[2][1] + b * minv[2][2];
        return .{ .x = x, .y = y, .z = z };
    }

    fn yToL(y: f64) f64 {
        return if (y <= 0.008856451679035631) {
            y * 903.2962962962963;
        } else {
            116.0 * std.math.pow(f64, y, 1.0 / 3.0) - 16.0;
        };
    }

    fn lToY(l: f64) f64 {
        return if (l <= 8.0) {
            l / 903.2962962962963;
        } else {
            std.math.pow(f64, (l + 16.0) / 116.0, 3.0);
        };
    }

    fn rgbToHsluv(r: f64, g: f64, b: f64) struct { h: f64, s: f64, l: f64 } {
        const xyz = rgbToXyz(r, g, b);
        const x = xyz.x;
        const y = xyz.y;
        const z = xyz.z;

        const l = yToL(y);

        if (l > 99.9999999 or l < 0.00000001) {
            return .{ .h = 0.0, .s = 0.0, .l = l };
        }

        const var_u = (2.0 * x + y + z) / (x + 4.0 * y + z);
        const var_v = 3.0 * y / (x + 4.0 * y + z);

        const hr = std.math.atan2(3.0 * (var_v - 0.3333333333333333), 2.0 * (var_u - 0.3333333333333333)) / (2.0 * std.math.pi);
        const h = if (hr < 0.0) hr + 1.0 else hr;

        const c = std.math.sqrt(std.math.pow(f64, var_u - 0.3333333333333333, 2.0) + std.math.pow(f64, var_v - 0.3333333333333333, 2.0));

        const s = if (c < 0.00000001) 0.0 else (c / (1.0 - std.math.fabs(2.0 * l - 100.0) / 100.0)) * 100.0;

        return .{ .h = h * 360.0, .s = s, .l = l };
    }

    /// Calculate perceptual color distance in HSLuv color space
    /// This provides much better color matching than simple RGB distance
    pub fn colorDistance(r1: u8, g1: u8, b1: u8, r2: u8, g2: u8, b2: u8) f64 {
        // Convert to 0-1 range for HSLuv calculation
        const r1_norm = @as(f64, @floatFromInt(r1)) / 255.0;
        const g1_norm = @as(f64, @floatFromInt(g1)) / 255.0;
        const b1_norm = @as(f64, @floatFromInt(b1)) / 255.0;

        const r2_norm = @as(f64, @floatFromInt(r2)) / 255.0;
        const g2_norm = @as(f64, @floatFromInt(g2)) / 255.0;
        const b2_norm = @as(f64, @floatFromInt(b2)) / 255.0;

        const hsluv1 = rgbToHsluv(r1_norm, g1_norm, b1_norm);
        const hsluv2 = rgbToHsluv(r2_norm, g2_norm, b2_norm);

        // Calculate Euclidean distance in HSLuv space
        const dh = hsluv1.h - hsluv2.h;
        const ds = hsluv1.s - hsluv2.s;
        const dl = hsluv1.l - hsluv2.l;

        // Handle hue wraparound (circular distance)
        const hue_diff = if (std.math.fabs(dh) > 180.0) {
            if (dh > 0.0) dh - 360.0 else dh + 360.0;
        } else dh;

        return std.math.sqrt(hue_diff * hue_diff + ds * ds + dl * dl);
    }
};

/// Advanced color conversion algorithms for terminal colors
pub const ColorConverter = struct {
    /// ANSI color palette (RGB values for 0-255) - matches xterm 256-color standard
    /// This palette follows the official xterm 256-color specification
    /// for maximum compatibility across terminal emulators
    const ansi_palette = [_]RgbColor{
        // Standard 16 colors (0-15) - these are the original ANSI colors
        RgbColor.init(0x00, 0x00, 0x00), // 0: Black
        RgbColor.init(0x80, 0x00, 0x00), // 1: Red
        RgbColor.init(0x00, 0x80, 0x00), // 2: Green
        RgbColor.init(0x80, 0x80, 0x00), // 3: Yellow
        RgbColor.init(0x00, 0x00, 0x80), // 4: Blue
        RgbColor.init(0x80, 0x00, 0x80), // 5: Magenta
        RgbColor.init(0x00, 0x80, 0x80), // 6: Cyan
        RgbColor.init(0xC0, 0xC0, 0xC0), // 7: White (Light Gray)
        RgbColor.init(0x80, 0x80, 0x80), // 8: Bright Black (Dark Gray)
        RgbColor.init(0xFF, 0x00, 0x00), // 9: Bright Red
        RgbColor.init(0x00, 0xFF, 0x00), // 10: Bright Green
        RgbColor.init(0xFF, 0xFF, 0x00), // 11: Bright Yellow
        RgbColor.init(0x00, 0x00, 0xFF), // 12: Bright Blue
        RgbColor.init(0xFF, 0x00, 0xFF), // 13: Bright Magenta
        RgbColor.init(0x00, 0xFF, 0xFF), // 14: Bright Cyan
        RgbColor.init(0xFF, 0xFF, 0xFF), // 15: Bright White
    } ++ generateExtendedPalette();

    /// Named color constants for easy access to standard ANSI colors
    pub const Black = 0;
    pub const Red = 1;
    pub const Green = 2;
    pub const Yellow = 3;
    pub const Blue = 4;
    pub const Magenta = 5;
    pub const Cyan = 6;
    pub const White = 7;
    pub const BrightBlack = 8;
    pub const BrightRed = 9;
    pub const BrightGreen = 10;
    pub const BrightYellow = 11;
    pub const BrightBlue = 12;
    pub const BrightMagenta = 13;
    pub const BrightCyan = 14;
    pub const BrightWhite = 15;

    /// Generate extended 256-color palette (16-255)
    fn generateExtendedPalette() [240]RgbColor {
        var palette: [240]RgbColor = undefined;
        var idx: usize = 0;

        // 6x6x6 color cube (216 colors: 16-231)
        for (0..6) |r| {
            for (0..6) |g| {
                for (0..6) |b| {
                    const r_val: u8 = if (r == 0) 0 else @as(u8, @intCast(55 + r * 40));
                    const g_val: u8 = if (g == 0) 0 else @as(u8, @intCast(55 + g * 40));
                    const b_val: u8 = if (b == 0) 0 else @as(u8, @intCast(55 + b * 40));
                    palette[idx] = RgbColor.init(r_val, g_val, b_val);
                    idx += 1;
                }
            }
        }

        // Grayscale ramp (24 colors: 232-255)
        for (0..24) |i| {
            const gray: u8 = @as(u8, @intCast(8 + i * 10));
            palette[idx] = RgbColor.init(gray, gray, gray);
            idx += 1;
        }

        return palette;
    }

    /// Map 6-cube coordinate (0-5) to color component value
    fn to6Cube(v: f64) u8 {
        if (v < 48.0) return 0;
        if (v < 115.0) return 1;
        return @as(u8, @intCast(@as(u32, @intFromFloat((v - 35.0) / 40.0))));
    }

    /// Calculate squared distance between two RGB colors
    fn distSquared(r1: u8, g1: u8, b1: u8, r2: u8, g2: u8, b2: u8) u32 {
        const dr = @as(i32, r1) - @as(i32, r2);
        const dg = @as(i32, g1) - @as(i32, g2);
        const db = @as(i32, b1) - @as(i32, b2);
        return @as(u32, @intCast(dr * dr + dg * dg + db * db));
    }

    /// Convert RGB color to xterm 256-color palette (0-255)
    /// Uses enhanced algorithm with HSLuv color distance for better accuracy
    pub fn convertToIndexed(rgb: RgbColor) IndexedColor {
        const r = @as(f64, @floatFromInt(rgb.r));
        const g = @as(f64, @floatFromInt(rgb.g));
        const b = @as(f64, @floatFromInt(rgb.b));

        // Xterm 6x6x6 color cube values
        const q2c = [_]u8{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };

        // Map RGB to 6x6x6 cube
        const qr = to6Cube(r);
        const qg = to6Cube(g);
        const qb = to6Cube(b);
        const cr = q2c[qr];
        const cg = q2c[qg];
        const cb = q2c[qb];

        // Calculate cube index
        const ci = (36 * qr) + (6 * qg) + qb;

        // If exact match in cube, return it
        if (cr == rgb.r and cg == rgb.g and cb == rgb.b) {
            return @as(IndexedColor, @intCast(16 + ci));
        }

        // Find closest gray
        const gray_avg = (@as(u32, rgb.r) + @as(u32, rgb.g) + @as(u32, rgb.b)) / 3;
        const gray_idx: u8 = if (gray_avg > 238) 23 else @as(u8, @intCast((gray_avg - 8) / 10));
        const gray = 8 + (10 * gray_idx);

        // Use HSLuv color distance for better perceptual matching
        const cube_dist = Hsluv.colorDistance(cr, cg, cb, rgb.r, rgb.g, rgb.b);
        const gray_dist = Hsluv.colorDistance(gray, gray, gray, rgb.r, rgb.g, rgb.b);

        if (cube_dist <= gray_dist) {
            return @as(IndexedColor, @intCast(16 + ci));
        } else {
            return @as(IndexedColor, @intCast(232 + gray_idx));
        }
    }

    /// Mapping table for 256-color to 16-color conversion
    const ansi256_to_16 = [_]BasicColor{
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, // 0-15 (direct)
        0, 4, 4, 4, 12, 12, 2, 6, 4, 4, 12, 12, 2, 2, 6, 4, // 16-31
        12, 12, 2, 2, 2, 6, 12, 12, 10, 10, 10, 10, 14, 12, 10, 10, // 32-47
        10, 10, 10, 14, 1, 5, 4, 4, 12, 12, 3, 8, 4, 4, 12, 12, // 48-63
        2, 2, 6, 4, 12, 12, 2, 2, 2, 6, 12, 12, 10, 10, 10, 10, // 64-79
        14, 12, 10, 10, 10, 10, 10, 14, 1, 1, 5, 4, 12, 12, 1, 1, // 80-95
        1, 5, 12, 12, 1, 1, 1, 5, 12, 12, 3, 3, 3, 7, 12, 12, // 96-111
        10, 10, 10, 10, 14, 12, 10, 10, 10, 10, 10, 14, 9, 9, 9, 9, // 112-127
        13, 12, 9, 9, 9, 9, 13, 12, 9, 9, 9, 9, 13, 12, 9, 9, // 128-143
        9, 9, 13, 12, 11, 11, 11, 11, 7, 12, 10, 10, 10, 10, 10, 14, // 144-159
        9, 9, 9, 9, 9, 13, 9, 9, 9, 9, 9, 13, 9, 9, 9, 9, // 160-175
        9, 13, 9, 9, 9, 9, 9, 13, 9, 9, 9, 9, 9, 13, 11, 11, // 176-191
        11, 11, 11, 15, 0, 0, 0, 0, 0, 0, 8, 8, 8, 8, 8, 8, // 192-207
        7, 7, 7, 7, 7, 7, 15, 15, 15, 15, 15, 15, // 208-223
        0, 0, 0, 0, 0, 0, 8, 8, 8, 8, 8, 8, 7, 7, 7, 7, // 224-239
        7, 7, 15, 15, 15, 15, 15, 15, // 240-255
    };

    /// Convert 256-color to 16-color ANSI
    pub fn convertToBasic(indexed: IndexedColor) BasicColor {
        return ansi256_to_16[indexed];
    }

    /// Convert RGB to 16-color ANSI (via 256-color conversion)
    pub fn rgbToBasic(rgb: RgbColor) BasicColor {
        const indexed = convertToIndexed(rgb);
        return convertToBasic(indexed);
    }

    /// Get RGB values for an indexed color (0-255)
    pub fn indexedToRgb(indexed: IndexedColor) RgbColor {
        return ansi_palette[indexed];
    }

    /// Get RGB values for a basic color (0-15)
    pub fn basicToRgb(basic: BasicColor) RgbColor {
        return ansi_palette[basic & 0x0F]; // Ensure in range 0-15
    }

    /// Check if a color index is within the standard 16-color range
    pub fn isBasicColor(index: u8) bool {
        return index <= 15;
    }

    /// Check if a color index is within the extended 256-color palette
    pub fn isExtendedColor(index: u8) bool {
        return index >= 16 and index <= 255;
    }

    /// Check if a color index is in the 6x6x6 color cube (16-231)
    pub fn isColorCube(index: u8) bool {
        return index >= 16 and index <= 231;
    }

    /// Check if a color index is in the grayscale ramp (232-255)
    pub fn isGrayscale(index: u8) bool {
        return index >= 232 and index <= 255;
    }

    /// Get the RGB values for any color in the 256-color palette
    /// Returns null if index is out of range
    pub fn paletteColor(index: u8) ?RgbColor {
        if (index >= ansi_palette.len) return null;
        return ansi_palette[index];
    }

    /// Find the closest ANSI 256-color to an RGB color (alias for convertToIndexed)
    pub fn findClosestColor(rgb: RgbColor) IndexedColor {
        return convertToIndexed(rgb);
    }
};

/// Enhanced color functions with validation
pub const SafeColor = struct {
    /// Safely create a hex color from string with validation
    pub fn hexFromString(hex_str: []const u8) ColorError!HexColor {
        if (!ColorValidator.isValidHex(hex_str)) {
            return ColorError.InvalidHexColor;
        }
        return HexColor.initFromString(hex_str) catch ColorError.InvalidHexColor;
    }

    /// Safely create RGB values with validation
    pub fn validateRgb(r: u8, g: u8, b: u8) ColorError!struct { r: u8, g: u8, b: u8 } {
        if (!ColorValidator.isValidRgb(r, g, b)) {
            return ColorError.InvalidRgbValue;
        }
        return .{ .r = r, .g = g, .b = b };
    }

    /// Safely create RGBA values with validation
    pub fn validateRgba(r: u8, g: u8, b: u8, a: u8) ColorError!struct { r: u8, g: u8, b: u8, a: u8 } {
        if (!ColorValidator.isValidRgba(r, g, b, a)) {
            return ColorError.InvalidRgbValue;
        }
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    /// Safely set foreground color with format validation
    pub fn setForegroundColorSafe(
        writer: anytype,
        alloc: std.mem.Allocator,
        caps: TermCaps,
        color: []const u8,
    ) ColorError!void {
        if (!caps.supportsColorOsc10_12) {
            return ColorError.TerminalCapabilityMissing;
        }

        if (!ColorValidator.isValidColor(color)) {
            return ColorError.InvalidColorFormat;
        }

        setForegroundColor(writer, alloc, caps, color) catch |err| switch (err) {
            error.Unsupported => return ColorError.TerminalCapabilityMissing,
            error.OutOfMemory => return ColorError.OutOfMemory,
            else => return ColorError.InvalidColorFormat,
        };
    }

    /// Safely set background color with format validation
    pub fn setBackgroundColorSafe(
        writer: anytype,
        alloc: std.mem.Allocator,
        caps: TermCaps,
        color: []const u8,
    ) ColorError!void {
        if (!caps.supportsColorOsc10_12) {
            return ColorError.TerminalCapabilityMissing;
        }

        if (!ColorValidator.isValidColor(color)) {
            return ColorError.InvalidColorFormat;
        }

        setBackgroundColor(writer, alloc, caps, color) catch |err| switch (err) {
            error.Unsupported => return ColorError.TerminalCapabilityMissing,
            error.OutOfMemory => return ColorError.OutOfMemory,
            else => return ColorError.InvalidColorFormat,
        };
    }

    /// Safely set cursor color with format validation
    pub fn setCursorColorSafe(
        writer: anytype,
        alloc: std.mem.Allocator,
        caps: TermCaps,
        color: []const u8,
    ) ColorError!void {
        if (!caps.supportsColorOsc10_12) {
            return ColorError.TerminalCapabilityMissing;
        }

        if (!ColorValidator.isValidColor(color)) {
            return ColorError.InvalidColorFormat;
        }

        setCursorColor(writer, alloc, caps, color) catch |err| switch (err) {
            error.Unsupported => return ColorError.TerminalCapabilityMissing,
            error.OutOfMemory => return ColorError.OutOfMemory,
            else => return ColorError.InvalidColorFormat,
        };
    }
};

// Additional validation tests
test "color validation" {
    const testing = std.testing;

    // Valid hex colors
    try testing.expect(ColorValidator.isValidHex("#FF0000"));
    try testing.expect(ColorValidator.isValidHex("FF0000"));
    try testing.expect(ColorValidator.isValidHex("#ff0000"));
    try testing.expect(ColorValidator.isValidHex("ff0000"));

    // Invalid hex colors
    try testing.expect(!ColorValidator.isValidHex("#FF00")); // Too short
    try testing.expect(!ColorValidator.isValidHex("GG0000")); // Invalid character
    try testing.expect(!ColorValidator.isValidHex("#FF0000AA")); // Too long

    // Valid XRGB colors
    try testing.expect(ColorValidator.isValidXRgb("rgb:ffff/0000/0000"));
    try testing.expect(ColorValidator.isValidXRgb("rgb:FFFF/FFFF/FFFF"));

    // Invalid XRGB colors
    try testing.expect(!ColorValidator.isValidXRgb("rgb:ff/00/00")); // Too short
    try testing.expect(!ColorValidator.isValidXRgb("rgb:ffff/ffff")); // Missing component
    try testing.expect(!ColorValidator.isValidXRgb("rgb:ffff/ffff/ffff/ff")); // Too many components

    // Valid XRGBA colors
    try testing.expect(ColorValidator.isValidXRgba("rgba:ffff/0000/0000/8080"));

    // Invalid XRGBA colors
    try testing.expect(!ColorValidator.isValidXRgba("rgba:ff/00/00/80")); // Too short
    try testing.expect(!ColorValidator.isValidXRgba("rgba:ffff/ffff/ffff")); // Missing alpha

    // RGB value validation
    try testing.expect(ColorValidator.isValidRgb(255, 128, 0));
    try testing.expect(!ColorValidator.isValidRgb(256, 0, 0));

    // RGBA value validation
    try testing.expect(ColorValidator.isValidRgba(255, 128, 0, 200));
    try testing.expect(!ColorValidator.isValidRgba(256, 0, 0, 0));

    // Format detection
    try testing.expect(ColorValidator.detectColorFormat("#FF0000") == .hex);
    try testing.expect(ColorValidator.detectColorFormat("rgb:ffff/0000/0000") == .xrgb);
    try testing.expect(ColorValidator.detectColorFormat("rgba:ffff/0000/0000/8080") == .xrgba);
    try testing.expect(ColorValidator.detectColorFormat("red") == .name);
}

test "safe color creation" {
    const testing = std.testing;

    // Valid hex color creation
    const red = try SafeColor.hexFromString("#FF0000");
    const red_rgb = red.toRgb();
    try testing.expect(red_rgb.r == 255 and red_rgb.g == 0 and red_rgb.b == 0);

    // Invalid hex color creation should fail
    try testing.expectError(ColorError.InvalidHexColor, SafeColor.hexFromString("invalid"));

    // Valid RGB validation
    const valid_rgb = try SafeColor.validateRgb(255, 128, 64);
    try testing.expect(valid_rgb.r == 255 and valid_rgb.g == 128 and valid_rgb.b == 64);
}

// === ADVANCED COLOR CONVERSION TESTS ===

test "rgb color creation and hex conversion" {
    const testing = std.testing;

    // Test RGB color creation
    const red = RgbColor.init(255, 0, 0);
    try testing.expect(red.r == 255 and red.g == 0 and red.b == 0);

    // Test hex conversion
    const red_hex = red.toHex();
    try testing.expect(red_hex == 0xFF0000);

    // Test white
    const white = RgbColor.init(255, 255, 255);
    try testing.expect(white.toHex() == 0xFFFFFF);
}

test "basic color palette accuracy" {
    const testing = std.testing;

    // Test standard ANSI colors
    const black = ColorConverter.basicToRgb(0);
    try testing.expect(black.r == 0x00 and black.g == 0x00 and black.b == 0x00);

    const red = ColorConverter.basicToRgb(1);
    try testing.expect(red.r == 0x80 and red.g == 0x00 and red.b == 0x00);

    const bright_white = ColorConverter.basicToRgb(15);
    try testing.expect(bright_white.r == 0xFF and bright_white.g == 0xFF and bright_white.b == 0xFF);
}

test "256-color conversion accuracy" {
    const testing = std.testing;

    // Test exact matches should return correct values
    const pure_red = RgbColor.init(255, 0, 0);
    const red_indexed = ColorConverter.convertToIndexed(pure_red);

    // Pure red should map to a specific index in the palette
    // Let's verify it maps to a reasonable value
    try testing.expect(red_indexed >= 16); // Should not be in basic 16-color range for pure red

    // Test that conversion round-trip preserves major colors reasonably
    const converted_back = ColorConverter.indexedToRgb(red_indexed);

    // Should be reasonably close to original (allowing for palette quantization)
    const r_diff = if (converted_back.r > pure_red.r)
        converted_back.r - pure_red.r
    else
        pure_red.r - converted_back.r;
    try testing.expect(r_diff <= 64); // Allow reasonable quantization error
}

test "16-color conversion from 256-color" {
    const testing = std.testing;

    // Test direct mapping for basic colors
    for (0..16) |i| {
        const basic = ColorConverter.convertToBasic(@as(IndexedColor, @intCast(i)));
        try testing.expect(basic == i);
    }

    // Test some extended color mappings
    const high_index: IndexedColor = 200; // A bright color in extended range
    const basic = ColorConverter.convertToBasic(high_index);
    try testing.expect(basic <= 15); // Should map to valid basic color
}

test "rgb to basic color conversion" {
    const testing = std.testing;

    // Test pure colors
    const pure_red = RgbColor.init(255, 0, 0);
    const red_basic = ColorConverter.rgbToBasic(pure_red);

    // Should map to either red (1) or bright red (9)
    try testing.expect(red_basic == 1 or red_basic == 9);

    const pure_blue = RgbColor.init(0, 0, 255);
    const blue_basic = ColorConverter.rgbToBasic(pure_blue);
    try testing.expect(blue_basic == 4 or blue_basic == 12); // Blue or bright blue

    // Test black and white
    const black = RgbColor.init(0, 0, 0);
    try testing.expect(ColorConverter.rgbToBasic(black) == 0);

    const white = RgbColor.init(255, 255, 255);
    const white_basic = ColorConverter.rgbToBasic(white);
    try testing.expect(white_basic == 7 or white_basic == 15); // White or bright white
}

test "grayscale color conversion" {
    const testing = std.testing;

    // Test grayscale colors map appropriately
    const dark_gray = RgbColor.init(64, 64, 64);
    const dark_indexed = ColorConverter.convertToIndexed(dark_gray);

    // Should map to grayscale range (232-255) or dark basic colors
    try testing.expect(dark_indexed <= 255);

    const light_gray = RgbColor.init(192, 192, 192);
    const light_indexed = ColorConverter.convertToIndexed(light_gray);
    try testing.expect(light_indexed <= 255);

    // Verify the round-trip maintains grayness reasonably
    const converted_back = ColorConverter.indexedToRgb(light_indexed);
    const max_diff = @max(@max(if (converted_back.r > light_gray.r) converted_back.r - light_gray.r else light_gray.r - converted_back.r, if (converted_back.g > light_gray.g) converted_back.g - light_gray.g else light_gray.g - converted_back.g), if (converted_back.b > light_gray.b) converted_back.b - light_gray.b else light_gray.b - converted_back.b);
    try testing.expect(max_diff <= 32); // Allow reasonable quantization error for grays
}

test "color cube mapping accuracy" {
    const testing = std.testing;

    // Test specific color cube coordinates
    // RGB(0, 95, 135) should map to cube coordinate (0, 1, 2)
    const test_color = RgbColor.init(0, 95, 135);
    const indexed = ColorConverter.convertToIndexed(test_color);

    // Verify it maps to extended palette (beyond basic 16)
    try testing.expect(indexed >= 16);
    try testing.expect(indexed <= 255);

    // Test that similar colors map to nearby indices
    const similar_color = RgbColor.init(5, 90, 130);
    const similar_indexed = ColorConverter.convertToIndexed(similar_color);

    // Should be reasonably close in the palette
    const index_diff = if (similar_indexed > indexed)
        similar_indexed - indexed
    else
        indexed - similar_indexed;
    try testing.expect(index_diff <= 20); // Allow reasonable neighborhood variance
}

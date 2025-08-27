const std = @import("std");

/// Error types for color parsing and formatting
pub const ColorError = error{
    InvalidHexFormat,
    InvalidHexLength,
    InvalidHexCharacter,
    InvalidRGBValue,
    OutOfMemory,
};

/// RGBA color components
pub const RGBA = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn init(r: u8, g: u8, b: u8) RGBA {
        return RGBA{ .r = r, .g = g, .b = b, .a = 255 };
    }

    pub fn initWithAlpha(r: u8, g: u8, b: u8, a: u8) RGBA {
        return RGBA{ .r = r, .g = g, .b = b, .a = a };
    }
};

/// A structured color type that can be formatted as a hex string
/// Supports both 6-character hex (#RRGGBB) and 8-character hex (#RRGGBBAA)
pub const HexColor = struct {
    rgba: RGBA,

    const Self = @This();

    /// Create a HexColor from RGB components
    pub fn fromRgb(r: u8, g: u8, b: u8) Self {
        return Self{ .rgba = RGBA.init(r, g, b) };
    }

    /// Create a HexColor from RGBA components
    pub fn fromRgba(r: u8, g: u8, b: u8, a: u8) Self {
        return Self{ .rgba = RGBA.initWithAlpha(r, g, b, a) };
    }

    /// Parse a hex color string (#RRGGBB or #RRGGBBAA or RRGGBB or RRGGBBAA)
    pub fn fromHex(hex: []const u8) ColorError!Self {
        var hex_clean = hex;

        // Remove leading # if present
        if (hex.len > 0 and hex[0] == '#') {
            hex_clean = hex[1..];
        }

        // Validate length
        if (hex_clean.len != 6 and hex_clean.len != 8) {
            return ColorError.InvalidHexLength;
        }

        // Parse components
        const r = try parseHexByte(hex_clean[0..2]);
        const g = try parseHexByte(hex_clean[2..4]);
        const b = try parseHexByte(hex_clean[4..6]);
        const a = if (hex_clean.len == 8) try parseHexByte(hex_clean[6..8]) else 255;

        return Self{ .rgba = RGBA.initWithAlpha(r, g, b, a) };
    }

    /// Format the color as a hex string (without #)
    pub fn toHex(self: Self, allocator: std.mem.Allocator) ![]u8 {
        if (self.rgba.a == 255) {
            return try std.fmt.allocPrint(allocator, "{X:0>2}{X:0>2}{X:0>2}", .{ self.rgba.r, self.rgba.g, self.rgba.b });
        } else {
            return try std.fmt.allocPrint(allocator, "{X:0>2}{X:0>2}{X:0>2}{X:0>2}", .{ self.rgba.r, self.rgba.g, self.rgba.b, self.rgba.a });
        }
    }

    /// Format the color as a hex string with # prefix
    pub fn toHexWithPrefix(self: Self, allocator: std.mem.Allocator) ![]u8 {
        const hex = try self.toHex(allocator);
        defer allocator.free(hex);
        return try std.fmt.allocPrint(allocator, "#{s}", .{hex});
    }

    /// Get RGBA components
    pub fn getRgba(self: Self) RGBA {
        return self.rgba;
    }
};

/// A color type that formats as XParseColor rgb: string (rgb:RRRR/GGGG/BBBB)
/// Uses 16-bit values for better color precision
pub const XRGBColor = struct {
    rgba: RGBA,

    const Self = @This();

    pub fn fromRgb(r: u8, g: u8, b: u8) Self {
        return Self{ .rgba = RGBA.init(r, g, b) };
    }

    pub fn fromRgba(r: u8, g: u8, b: u8, a: u8) Self {
        return Self{ .rgba = RGBA.initWithAlpha(r, g, b, a) };
    }

    /// Format the color as an XParseColor rgb: string
    pub fn toXRgb(self: Self, allocator: std.mem.Allocator) ![]u8 {
        // Convert 8-bit values to 16-bit for X11 color format
        const r16: u16 = (@as(u16, self.rgba.r) << 8) | self.rgba.r;
        const g16: u16 = (@as(u16, self.rgba.g) << 8) | self.rgba.g;
        const b16: u16 = (@as(u16, self.rgba.b) << 8) | self.rgba.b;

        return try std.fmt.allocPrint(allocator, "rgb:{X:0>4}/{X:0>4}/{X:0>4}", .{ r16, g16, b16 });
    }

    pub fn getRgba(self: Self) RGBA {
        return self.rgba;
    }
};

/// A color type that formats as XParseColor rgba: string (rgba:RRRR/GGGG/BBBB/AAAA)
pub const XRGBAColor = struct {
    rgba: RGBA,

    const Self = @This();

    pub fn fromRgb(r: u8, g: u8, b: u8) Self {
        return Self{ .rgba = RGBA.init(r, g, b) };
    }

    pub fn fromRgba(r: u8, g: u8, b: u8, a: u8) Self {
        return Self{ .rgba = RGBA.initWithAlpha(r, g, b, a) };
    }

    /// Format the color as an XParseColor rgba: string
    pub fn toXRgba(self: Self, allocator: std.mem.Allocator) ![]u8 {
        // Convert 8-bit values to 16-bit for X11 color format
        const r16: u16 = (@as(u16, self.rgba.r) << 8) | self.rgba.r;
        const g16: u16 = (@as(u16, self.rgba.g) << 8) | self.rgba.g;
        const b16: u16 = (@as(u16, self.rgba.b) << 8) | self.rgba.b;
        const a16: u16 = (@as(u16, self.rgba.a) << 8) | self.rgba.a;

        return try std.fmt.allocPrint(allocator, "rgba:{X:0>4}/{X:0>4}/{X:0>4}/{X:0>4}", .{ r16, g16, b16, a16 });
    }

    pub fn getRgba(self: Self) RGBA {
        return self.rgba;
    }
};

// Helper function to parse a 2-character hex string to a byte
fn parseHexByte(hex: []const u8) ColorError!u8 {
    if (hex.len != 2) return ColorError.InvalidHexLength;

    var result: u8 = 0;
    for (hex) |char| {
        result <<= 4;
        switch (char) {
            '0'...'9' => result |= char - '0',
            'A'...'F' => result |= char - 'A' + 10,
            'a'...'f' => result |= char - 'a' + 10,
            else => return ColorError.InvalidHexCharacter,
        }
    }
    return result;
}

// Color format validation utilities
pub const ColorValidator = struct {
    /// Validate if a string is a valid hex color format
    pub fn isValidHex(hex: []const u8) bool {
        var hex_clean = hex;

        // Remove leading # if present
        if (hex.len > 0 and hex[0] == '#') {
            hex_clean = hex[1..];
        }

        // Check length
        if (hex_clean.len != 6 and hex_clean.len != 8) {
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

    /// Validate RGB component values (0-255)
    pub fn isValidRgb(r: u16, g: u16, b: u16) bool {
        return r <= 255 and g <= 255 and b <= 255;
    }

    /// Validate RGBA component values (0-255)
    pub fn isValidRgba(r: u16, g: u16, b: u16, a: u16) bool {
        return r <= 255 and g <= 255 and b <= 255 and a <= 255;
    }
};

// Tests
test "HexColor creation and formatting" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Test RGB creation
    const red = HexColor.fromRgb(255, 0, 0);
    const red_hex = try red.toHex(alloc);
    try testing.expectEqualStrings("FF0000", red_hex);

    // Test RGBA creation
    const blue_alpha = HexColor.fromRgba(0, 0, 255, 128);
    const blue_hex = try blue_alpha.toHex(alloc);
    try testing.expectEqualStrings("0000FF80", blue_hex);

    // Test hex parsing
    const green = try HexColor.fromHex("#00FF00");
    const green_rgba = green.getRgba();
    try testing.expect(green_rgba.r == 0 and green_rgba.g == 255 and green_rgba.b == 0);
}

test "XRGBColor formatting" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const white = XRGBColor.fromRgb(255, 255, 255);
    const white_xrgb = try white.toXRgb(alloc);
    try testing.expectEqualStrings("rgb:FFFF/FFFF/FFFF", white_xrgb);
}

test "XRGBAColor formatting" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const black_alpha = XRGBAColor.fromRgba(0, 0, 0, 128);
    const black_xrgba = try black_alpha.toXRgba(alloc);
    try testing.expectEqualStrings("rgba:0000/0000/0000/8080", black_xrgba);
}

test "Color validation" {
    const testing = std.testing;

    // Valid hex colors
    try testing.expect(ColorValidator.isValidHex("#FF0000"));
    try testing.expect(ColorValidator.isValidHex("FF0000"));
    try testing.expect(ColorValidator.isValidHex("#FF0000AA"));
    try testing.expect(ColorValidator.isValidHex("ff0000aa"));

    // Invalid hex colors
    try testing.expect(!ColorValidator.isValidHex("#FF00"));
    try testing.expect(!ColorValidator.isValidHex("GG0000"));
    try testing.expect(!ColorValidator.isValidHex("#FF0000AAA"));

    // RGB validation
    try testing.expect(ColorValidator.isValidRgb(255, 128, 0));
    try testing.expect(!ColorValidator.isValidRgb(256, 0, 0));
}

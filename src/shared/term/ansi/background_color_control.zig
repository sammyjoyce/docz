const std = @import("std");
const Color = @import("color_conversion_enhanced.zig").Color;
const RGBColor = @import("color_conversion_enhanced.zig").RGBColor;
const RGBA = @import("color_conversion_enhanced.zig").RGBA;

/// Terminal background and foreground color control based on standard ANSI OSC sequences
/// Supports OSC (Operating System Command) sequences for setting and querying terminal colors.

// ==== Color Format Types ====

/// HexColor represents a color that can be formatted as a hex string
pub const HexColor = struct {
    color: ?RGBColor,

    pub fn init(hex_string: []const u8) HexColor {
        return HexColor{
            .color = parseHexColor(hex_string),
        };
    }

    pub fn initFromRGB(rgb: RGBColor) HexColor {
        return HexColor{
            .color = rgb,
        };
    }

    pub fn rgba(self: HexColor) RGBA {
        if (self.color) |c| {
            return c.rgba();
        }
        return RGBA.init(0, 0, 0, 0);
    }

    pub fn hex(self: HexColor) []const u8 {
        if (self.color) |_| {
            // Would need allocator to format properly, returning placeholder
            return "#000000"; // In real implementation, format toHex() as hex string
        }
        return "";
    }

    pub fn toString(self: HexColor, allocator: std.mem.Allocator) ![]u8 {
        if (self.color) |c| {
            return try std.fmt.allocPrint(allocator, "#{:0>6x}", .{c.toHex()});
        }
        return try allocator.dupe(u8, "");
    }
};

/// XRGBColor represents a color in XParseColor rgb: format
pub const XRGBColor = struct {
    color: ?RGBColor,

    pub fn init(rgb: ?RGBColor) XRGBColor {
        return XRGBColor{ .color = rgb };
    }

    pub fn rgba(self: XRGBColor) RGBA {
        if (self.color) |c| {
            return c.rgba();
        }
        return RGBA.init(0, 0, 0, 0);
    }

    pub fn toString(self: XRGBColor, allocator: std.mem.Allocator) ![]u8 {
        if (self.color) |c| {
            const rgba_val = c.rgba();
            // Convert 8-bit to 16-bit for X11 format
            const r16 = (@as(u16, rgba_val.r) << 8) | rgba_val.r;
            const g16 = (@as(u16, rgba_val.g) << 8) | rgba_val.g;
            const b16 = (@as(u16, rgba_val.b) << 8) | rgba_val.b;
            return try std.fmt.allocPrint(allocator, "rgb:{:0>4x}/{:0>4x}/{:0>4x}", .{ r16, g16, b16 });
        }
        return try allocator.dupe(u8, "");
    }
};

/// XRGBAColor represents a color in XParseColor rgba: format
pub const XRGBAColor = struct {
    color: ?RGBColor,

    pub fn init(rgb: ?RGBColor) XRGBAColor {
        return XRGBAColor{ .color = rgb };
    }

    pub fn rgba(self: XRGBAColor) RGBA {
        if (self.color) |c| {
            return c.rgba();
        }
        return RGBA.init(0, 0, 0, 0);
    }

    pub fn toString(self: XRGBAColor, allocator: std.mem.Allocator) ![]u8 {
        if (self.color) |c| {
            const rgba_val = c.rgba();
            // Convert 8-bit to 16-bit for X11 format
            const r16 = (@as(u16, rgba_val.r) << 8) | rgba_val.r;
            const g16 = (@as(u16, rgba_val.g) << 8) | rgba_val.g;
            const b16 = (@as(u16, rgba_val.b) << 8) | rgba_val.b;
            const a16 = (@as(u16, rgba_val.a) << 8) | rgba_val.a;
            return try std.fmt.allocPrint(allocator, "rgba:{:0>4x}/{:0>4x}/{:0>4x}/{:0>4x}", .{ r16, g16, b16, a16 });
        }
        return try allocator.dupe(u8, "");
    }
};

// ==== Foreground Color Control ====

/// SetForegroundColor sets the default terminal foreground color
/// OSC 10 ; color ST / OSC 10 ; color BEL
pub fn setForegroundColor(allocator: std.mem.Allocator, color_spec: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "\x1b]10;{s}\x07", .{color_spec});
}

/// RequestForegroundColor requests the current default terminal foreground color
/// OSC 10 ; ? ST / OSC 10 ; ? BEL
pub const REQUEST_FOREGROUND_COLOR = "\x1b]10;?\x07";

/// ResetForegroundColor resets the default terminal foreground color
/// OSC 110 ST / OSC 110 BEL
pub const RESET_FOREGROUND_COLOR = "\x1b]110\x07";

// ==== Background Color Control ====

/// SetBackgroundColor sets the default terminal background color
/// OSC 11 ; color ST / OSC 11 ; color BEL
pub fn setBackgroundColor(allocator: std.mem.Allocator, color_spec: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "\x1b]11;{s}\x07", .{color_spec});
}

/// RequestBackgroundColor requests the current default terminal background color
/// OSC 11 ; ? ST / OSC 11 ; ? BEL
pub const REQUEST_BACKGROUND_COLOR = "\x1b]11;?\x07";

/// ResetBackgroundColor resets the default terminal background color
/// OSC 111 ST / OSC 111 BEL
pub const RESET_BACKGROUND_COLOR = "\x1b]111\x07";

// ==== Cursor Color Control ====

/// SetCursorColor sets the terminal cursor color
/// OSC 12 ; color ST / OSC 12 ; color BEL
pub fn setCursorColor(allocator: std.mem.Allocator, color_spec: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "\x1b]12;{s}\x07", .{color_spec});
}

/// RequestCursorColor requests the current terminal cursor color
/// OSC 12 ; ? ST / OSC 12 ; ? BEL
pub const REQUEST_CURSOR_COLOR = "\x1b]12;?\x07";

/// ResetCursorColor resets the terminal cursor color
/// OSC 112 ST / OSC 112 BEL
pub const RESET_CURSOR_COLOR = "\x1b]112\x07";

// ==== Palette Color Control ====

/// SetPaletteColor sets a specific color in the terminal palette
/// OSC 4 ; index ; color ST / OSC 4 ; index ; color BEL
pub fn setPaletteColor(allocator: std.mem.Allocator, index: u8, color_spec: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "\x1b]4;{};{s}\x07", .{ index, color_spec });
}

/// RequestPaletteColor requests a specific color from the terminal palette
/// OSC 4 ; index ; ? ST / OSC 4 ; index ; ? BEL
pub fn requestPaletteColor(allocator: std.mem.Allocator, index: u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "\x1b]4;{};?\x07", .{index});
}

/// ResetPaletteColor resets a specific color in the terminal palette
/// OSC 104 ; index ST / OSC 104 ; index BEL
pub fn resetPaletteColor(allocator: std.mem.Allocator, index: u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "\x1b]104;{}\x07", .{index});
}

/// ResetAllPaletteColors resets all colors in the terminal palette
/// OSC 104 ST / OSC 104 BEL
pub const RESET_ALL_PALETTE_COLORS = "\x1b]104\x07";

// ==== Convenience Functions ====

/// Set foreground color using HexColor format
pub fn setForegroundColorHex(allocator: std.mem.Allocator, color: HexColor) ![]u8 {
    const color_str = try color.toString(allocator);
    defer allocator.free(color_str);
    return try setForegroundColor(allocator, color_str);
}

/// Set background color using HexColor format
pub fn setBackgroundColorHex(allocator: std.mem.Allocator, color: HexColor) ![]u8 {
    const color_str = try color.toString(allocator);
    defer allocator.free(color_str);
    return try setBackgroundColor(allocator, color_str);
}

/// Set foreground color using XRGBColor format
pub fn setForegroundColorXRGB(allocator: std.mem.Allocator, color: XRGBColor) ![]u8 {
    const color_str = try color.toString(allocator);
    defer allocator.free(color_str);
    return try setForegroundColor(allocator, color_str);
}

/// Set background color using XRGBColor format
pub fn setBackgroundColorXRGB(allocator: std.mem.Allocator, color: XRGBColor) ![]u8 {
    const color_str = try color.toString(allocator);
    defer allocator.free(color_str);
    return try setBackgroundColor(allocator, color_str);
}

/// Set foreground color using XRGBAColor format
pub fn setForegroundColorXRGBA(allocator: std.mem.Allocator, color: XRGBAColor) ![]u8 {
    const color_str = try color.toString(allocator);
    defer allocator.free(color_str);
    return try setForegroundColor(allocator, color_str);
}

/// Set background color using XRGBAColor format
pub fn setBackgroundColorXRGBA(allocator: std.mem.Allocator, color: XRGBAColor) ![]u8 {
    const color_str = try color.toString(allocator);
    defer allocator.free(color_str);
    return try setBackgroundColor(allocator, color_str);
}

/// Set foreground color using RGB values
pub fn setForegroundColorRGB(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
    const rgb = RGBColor.init(r, g, b);
    const hex_color = HexColor.initFromRGB(rgb);
    return try setForegroundColorHex(allocator, hex_color);
}

/// Set background color using RGB values
pub fn setBackgroundColorRGB(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
    const rgb = RGBColor.init(r, g, b);
    const hex_color = HexColor.initFromRGB(rgb);
    return try setBackgroundColorHex(allocator, hex_color);
}

// ==== Color Parsing Utilities ====

/// Parse a hex color string like "#FF5533" or "FF5533"
fn parseHexColor(hex_string: []const u8) ?RGBColor {
    var hex = hex_string;

    // Remove leading # if present
    if (hex.len > 0 and hex[0] == '#') {
        hex = hex[1..];
    }

    // Must be exactly 6 characters for RGB
    if (hex.len != 6) {
        return null;
    }

    const value = std.fmt.parseUnsigned(u32, hex, 16) catch return null;
    return RGBColor.fromHex(value);
}

/// Parse an RGB color string like "rgb:1234/5678/9abc"
fn parseRGBColor(rgb_string: []const u8) ?RGBColor {
    if (!std.mem.startsWith(u8, rgb_string, "rgb:")) {
        return null;
    }

    const color_part = rgb_string[4..];
    var iterator = std.mem.split(u8, color_part, "/");

    const r_str = iterator.next() orelse return null;
    const g_str = iterator.next() orelse return null;
    const b_str = iterator.next() orelse return null;

    // Parse 16-bit hex values and convert to 8-bit
    const r16 = std.fmt.parseUnsigned(u16, r_str, 16) catch return null;
    const g16 = std.fmt.parseUnsigned(u16, g_str, 16) catch return null;
    const b16 = std.fmt.parseUnsigned(u16, b_str, 16) catch return null;

    const r8: u8 = @intCast(r16 >> 8);
    const g8: u8 = @intCast(g16 >> 8);
    const b8: u8 = @intCast(b16 >> 8);

    return RGBColor.init(r8, g8, b8);
}

/// ColorTheme provides common color themes for terminal customization
pub const ColorTheme = struct {
    pub const Theme = struct {
        name: []const u8,
        background: RGBColor,
        foreground: RGBColor,
        cursor: ?RGBColor = null,
    };

    pub const DARK = Theme{
        .name = "Dark",
        .background = RGBColor.init(0x1e, 0x1e, 0x1e),
        .foreground = RGBColor.init(0xf8, 0xf8, 0xf2),
        .cursor = RGBColor.init(0xf8, 0xf8, 0xf0),
    };

    pub const LIGHT = Theme{
        .name = "Light",
        .background = RGBColor.init(0xf8, 0xf8, 0xf8),
        .foreground = RGBColor.init(0x27, 0x28, 0x22),
        .cursor = RGBColor.init(0x27, 0x28, 0x22),
    };

    pub const DRACULA = Theme{
        .name = "Dracula",
        .background = RGBColor.init(0x28, 0x2a, 0x36),
        .foreground = RGBColor.init(0xf8, 0xf8, 0xf2),
        .cursor = RGBColor.init(0xf8, 0xf8, 0xf0),
    };

    pub const MONOKAI = Theme{
        .name = "Monokai",
        .background = RGBColor.init(0x27, 0x28, 0x22),
        .foreground = RGBColor.init(0xf8, 0xf8, 0xf2),
        .cursor = RGBColor.init(0xf9, 0x26, 0x72),
    };

    pub const SOLARIZED_DARK = Theme{
        .name = "Solarized Dark",
        .background = RGBColor.init(0x00, 0x2b, 0x36),
        .foreground = RGBColor.init(0x83, 0x94, 0x96),
        .cursor = RGBColor.init(0x83, 0x94, 0x96),
    };

    pub const SOLARIZED_LIGHT = Theme{
        .name = "Solarized Light",
        .background = RGBColor.init(0xfd, 0xf6, 0xe3),
        .foreground = RGBColor.init(0x65, 0x7b, 0x83),
        .cursor = RGBColor.init(0x65, 0x7b, 0x83),
    };

    /// Apply a color theme to the terminal
    pub fn apply(theme: Theme, allocator: std.mem.Allocator) ![]u8 {
        var sequences = std.ArrayList([]const u8).init(allocator);
        defer {
            for (sequences.items) |seq| {
                allocator.free(seq);
            }
            sequences.deinit();
        }

        // Set background
        const bg_seq = try setBackgroundColorRGB(allocator, theme.background.r, theme.background.g, theme.background.b);
        try sequences.append(bg_seq);

        // Set foreground
        const fg_seq = try setForegroundColorRGB(allocator, theme.foreground.r, theme.foreground.g, theme.foreground.b);
        try sequences.append(fg_seq);

        // Set cursor if specified
        if (theme.cursor) |cursor_color| {
            const cursor_seq = try setCursorColorRGB(allocator, cursor_color.r, cursor_color.g, cursor_color.b);
            try sequences.append(cursor_seq);
        }

        return try std.mem.join(allocator, "", sequences.items);
    }
};

/// Set cursor color using RGB values
fn setCursorColorRGB(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
    const rgb = RGBColor.init(r, g, b);
    const hex_color = HexColor.initFromRGB(rgb);
    const color_str = try hex_color.toString(allocator);
    defer allocator.free(color_str);
    return try setCursorColor(allocator, color_str);
}

// ==== Tests ====

test "color format conversion" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test HexColor
    {
        const red_rgb = RGBColor.init(255, 0, 0);
        const hex_color = HexColor.initFromRGB(red_rgb);
        const hex_str = try hex_color.toString(allocator);
        defer allocator.free(hex_str);
        try testing.expectEqualSlices(u8, "#ff0000", hex_str);
    }

    // Test XRGBColor
    {
        const green_rgb = RGBColor.init(0, 255, 0);
        const xrgb_color = XRGBColor.init(green_rgb);
        const xrgb_str = try xrgb_color.toString(allocator);
        defer allocator.free(xrgb_str);
        try testing.expectEqualSlices(u8, "rgb:0000/ffff/0000", xrgb_str);
    }
}

test "color control sequences" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test foreground color setting
    {
        const fg_seq = try setForegroundColor(allocator, "#ff0000");
        defer allocator.free(fg_seq);
        try testing.expectEqualSlices(u8, "\x1b]10;#ff0000\x07", fg_seq);
    }

    // Test background color setting
    {
        const bg_seq = try setBackgroundColor(allocator, "rgb:0000/ffff/0000");
        defer allocator.free(bg_seq);
        try testing.expectEqualSlices(u8, "\x1b]11;rgb:0000/ffff/0000\x07", bg_seq);
    }

    // Test palette color setting
    {
        const pal_seq = try setPaletteColor(allocator, 5, "#ff00ff");
        defer allocator.free(pal_seq);
        try testing.expectEqualSlices(u8, "\x1b]4;5;#ff00ff\x07", pal_seq);
    }

    // Test RGB convenience function
    {
        const rgb_seq = try setForegroundColorRGB(allocator, 128, 64, 255);
        defer allocator.free(rgb_seq);
        // Should contain the OSC sequence with hex color
        try testing.expect(std.mem.indexOf(u8, rgb_seq, "\x1b]10;") != null);
        try testing.expect(std.mem.indexOf(u8, rgb_seq, "\x07") != null);
    }
}

test "color themes" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test theme application
    {
        const theme_seq = try ColorTheme.DRACULA.apply(allocator);
        defer allocator.free(theme_seq);

        // Should contain background and foreground sequences
        try testing.expect(std.mem.indexOf(u8, theme_seq, "\x1b]11;") != null); // Background
        try testing.expect(std.mem.indexOf(u8, theme_seq, "\x1b]10;") != null); // Foreground
        try testing.expect(std.mem.indexOf(u8, theme_seq, "\x1b]12;") != null); // Cursor
    }
}

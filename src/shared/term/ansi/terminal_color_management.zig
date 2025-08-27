const std = @import("std");

/// Terminal color management for foreground, background, and cursor colors
/// Implements OSC sequences for querying and setting terminal colors
///
/// This enables applications to:
/// - Query current terminal colors to adapt themes
/// - Set custom colors that persist across applications
/// - Reset colors to defaults
/// - Support for multiple color formats (hex, X11 rgb/rgba)
/// - Full ANSI 256-color palette support
/// - HSL color space conversion
///
/// See: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands
/// Color format types for terminal color specifications
pub const ColorFormat = enum {
    hex, // #rrggbb
    x11_rgb, // rgb:rrrr/gggg/bbbb
    x11_rgba, // rgba:rrrr/gggg/bbbb/aaaa
    named, // CSS color names
    ansi256, // ANSI 256 color index
};

/// Terminal color types that can be queried/set
pub const TerminalColorType = enum(u8) {
    foreground = 10,
    background = 11,
    cursor = 12,
    highlight_foreground = 17,
    highlight_background = 19,

    pub fn toCode(self: TerminalColorType) u8 {
        return @intFromEnum(self);
    }
};

/// RGB color representation
pub const RgbColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RgbColor {
        return RgbColor{ .r = r, .g = g, .b = b };
    }

    pub fn fromHex(hex: u32) RgbColor {
        return RgbColor{
            .r = @truncate((hex >> 16) & 0xFF),
            .g = @truncate((hex >> 8) & 0xFF),
            .b = @truncate(hex & 0xFF),
        };
    }

    pub fn toHex(self: RgbColor) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | @as(u32, self.b);
    }

    pub fn distance(self: RgbColor, other: RgbColor) u32 {
        const dr = @as(i32, self.r) - @as(i32, other.r);
        const dg = @as(i32, self.g) - @as(i32, other.g);
        const db = @as(i32, self.b) - @as(i32, other.b);
        return @intCast(dr * dr + dg * dg + db * db);
    }

    pub fn toHsl(self: RgbColor) HslColor {
        return rgbToHsl(self.r, self.g, self.b);
    }
};

/// HSL color representation
pub const HslColor = struct {
    h: f32, // Hue: 0.0 - 360.0
    s: f32, // Saturation: 0.0 - 1.0
    l: f32, // Lightness: 0.0 - 1.0

    pub fn init(h: f32, s: f32, l: f32) HslColor {
        return HslColor{ .h = h, .s = s, .l = l };
    }

    pub fn toRgb(self: HslColor) RgbColor {
        return hslToRgb(self.h, self.s, self.l);
    }
};

/// ANSI 256 Color Palette
pub const Ansi256Palette = struct {
    // Standard 16 colors (0-15)
    pub const STANDARD_COLORS = [16]RgbColor{
        RgbColor.init(0x00, 0x00, 0x00), // 0: black
        RgbColor.init(0x80, 0x00, 0x00), // 1: red
        RgbColor.init(0x00, 0x80, 0x00), // 2: green
        RgbColor.init(0x80, 0x80, 0x00), // 3: yellow
        RgbColor.init(0x00, 0x00, 0x80), // 4: blue
        RgbColor.init(0x80, 0x00, 0x80), // 5: magenta
        RgbColor.init(0x00, 0x80, 0x80), // 6: cyan
        RgbColor.init(0xc0, 0xc0, 0xc0), // 7: white
        RgbColor.init(0x80, 0x80, 0x80), // 8: bright black
        RgbColor.init(0xff, 0x00, 0x00), // 9: bright red
        RgbColor.init(0x00, 0xff, 0x00), // 10: bright green
        RgbColor.init(0xff, 0xff, 0x00), // 11: bright yellow
        RgbColor.init(0x00, 0x00, 0xff), // 12: bright blue
        RgbColor.init(0xff, 0x00, 0xff), // 13: bright magenta
        RgbColor.init(0x00, 0xff, 0xff), // 14: bright cyan
        RgbColor.init(0xff, 0xff, 0xff), // 15: bright white
    };

    // RGB values for 6x6x6 color cube (16-231)
    pub const CUBE_STEPS = [6]u8{ 0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff };

    // Grayscale values (232-255)
    pub fn getGrayscaleValue(index: u8) u8 {
        if (index < 232 or index > 255) return 0;
        return 8 + (index - 232) * 10;
    }

    /// Convert ANSI 256 color index to RGB
    pub fn indexToRgb(index: u8) RgbColor {
        if (index < 16) {
            // Standard 16 colors
            return STANDARD_COLORS[index];
        } else if (index < 232) {
            // 216 color cube: 6x6x6
            const cube_index = index - 16;
            const r_idx = cube_index / 36;
            const g_idx = (cube_index % 36) / 6;
            const b_idx = cube_index % 6;
            return RgbColor.init(
                CUBE_STEPS[r_idx],
                CUBE_STEPS[g_idx],
                CUBE_STEPS[b_idx],
            );
        } else {
            // 24 grayscale colors
            const gray = getGrayscaleValue(index);
            return RgbColor.init(gray, gray, gray);
        }
    }

    /// Find nearest ANSI 256 color index for RGB
    pub fn rgbToNearestIndex(r: u8, g: u8, b: u8) u8 {
        const rgb = RgbColor.init(r, g, b);
        var best_index: u8 = 0;
        var best_distance: u32 = std.math.maxInt(u32);

        // Check all 256 colors
        var i: u16 = 0;
        while (i < 256) : (i += 1) {
            const palette_color = indexToRgb(@truncate(i));
            const dist = rgb.distance(palette_color);
            if (dist < best_distance) {
                best_distance = dist;
                best_index = @truncate(i);
            }
        }

        return best_index;
    }

    /// Get color cube index for RGB values
    pub fn rgbToCubeIndex(r: u8, g: u8, b: u8) ?u8 {
        // Find nearest cube steps
        const r_idx = nearestCubeStep(r);
        const g_idx = nearestCubeStep(g);
        const b_idx = nearestCubeStep(b);

        // Calculate cube index
        const cube_index: u8 = @truncate(16 + r_idx * 36 + g_idx * 6 + b_idx);
        return cube_index;
    }

    fn nearestCubeStep(value: u8) u8 {
        var best_idx: u8 = 0;
        var best_diff: u16 = 255;

        for (CUBE_STEPS, 0..) |step, idx| {
            const diff = if (value > step) value - step else step - value;
            if (diff < best_diff) {
                best_diff = diff;
                best_idx = @truncate(idx);
            }
        }

        return best_idx;
    }

    /// Check if RGB is grayscale
    pub fn isGrayscale(r: u8, g: u8, b: u8) bool {
        return r == g and g == b;
    }

    /// Get nearest grayscale index
    pub fn nearestGrayscaleIndex(gray: u8) u8 {
        if (gray < 8) return 16; // Use black from standard colors
        if (gray > 238) return 231; // Use white from standard colors

        // Find nearest grayscale in range 232-255
        const adjusted = gray - 8;
        const index = adjusted / 10;
        const remainder = adjusted % 10;

        if (remainder < 5) {
            return 232 + index;
        } else {
            return 232 + index + 1;
        }
    }
};

/// Convert RGB to HSL color space
pub fn rgbToHsl(r: u8, g: u8, b: u8) HslColor {
    const rf = @as(f32, @floatFromInt(r)) / 255.0;
    const gf = @as(f32, @floatFromInt(g)) / 255.0;
    const bf = @as(f32, @floatFromInt(b)) / 255.0;

    const max = @max(rf, @max(gf, bf));
    const min = @min(rf, @min(gf, bf));
    const delta = max - min;

    // Calculate lightness
    const l = (max + min) / 2.0;

    if (delta == 0.0) {
        // Achromatic (gray)
        return HslColor.init(0.0, 0.0, l);
    }

    // Calculate saturation
    const s = if (l < 0.5)
        delta / (max + min)
    else
        delta / (2.0 - max - min);

    // Calculate hue
    var h: f32 = 0.0;
    if (max == rf) {
        h = (gf - bf) / delta + (if (gf < bf) 6.0 else 0.0);
    } else if (max == gf) {
        h = (bf - rf) / delta + 2.0;
    } else {
        h = (rf - gf) / delta + 4.0;
    }
    h = h * 60.0;

    return HslColor.init(h, s, l);
}

/// Convert HSL to RGB color space
pub fn hslToRgb(h: f32, s: f32, l: f32) RgbColor {
    if (s == 0.0) {
        // Achromatic (gray)
        const gray: u8 = @intFromFloat(l * 255.0);
        return RgbColor.init(gray, gray, gray);
    }

    const q = if (l < 0.5)
        l * (1.0 + s)
    else
        l + s - l * s;
    const p = 2.0 * l - q;

    const h_normalized = h / 360.0;
    const r = hueToRgb(p, q, h_normalized + 1.0 / 3.0);
    const g = hueToRgb(p, q, h_normalized);
    const b = hueToRgb(p, q, h_normalized - 1.0 / 3.0);

    return RgbColor.init(
        @intFromFloat(r * 255.0),
        @intFromFloat(g * 255.0),
        @intFromFloat(b * 255.0),
    );
}

fn hueToRgb(p: f32, q: f32, t_input: f32) f32 {
    var t = t_input;
    if (t < 0.0) t += 1.0;
    if (t > 1.0) t -= 1.0;

    if (t < 1.0 / 6.0) {
        return p + (q - p) * 6.0 * t;
    } else if (t < 1.0 / 2.0) {
        return q;
    } else if (t < 2.0 / 3.0) {
        return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    } else {
        return p;
    }
}

/// Format a color as hex string (#rrggbb)
pub fn formatColorHex(alloc: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
    return std.fmt.allocPrint(alloc, "#{:02x}{:02x}{:02x}", .{ r, g, b });
}

/// Format a color as X11 RGB string (rgb:rrrr/gggg/bbbb)
pub fn formatColorX11Rgb(alloc: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
    // X11 uses 16-bit values, duplicate 8-bit values
    const r16 = @as(u16, r) | (@as(u16, r) << 8);
    const g16 = @as(u16, g) | (@as(u16, g) << 8);
    const b16 = @as(u16, b) | (@as(u16, b) << 8);
    return std.fmt.allocPrint(alloc, "rgb:{:04x}/{:04x}/{:04x}", .{ r16, g16, b16 });
}

/// Format a color as X11 RGBA string (rgba:rrrr/gggg/bbbb/aaaa)
pub fn formatColorX11Rgba(alloc: std.mem.Allocator, r: u8, g: u8, b: u8, a: u8) ![]u8 {
    // X11 uses 16-bit values, duplicate 8-bit values
    const r16 = @as(u16, r) | (@as(u16, r) << 8);
    const g16 = @as(u16, g) | (@as(u16, g) << 8);
    const b16 = @as(u16, b) | (@as(u16, b) << 8);
    const a16 = @as(u16, a) | (@as(u16, a) << 8);
    return std.fmt.allocPrint(alloc, "rgba:{:04x}/{:04x}/{:04x}/{:04x}", .{ r16, g16, b16, a16 });
}

/// Format ANSI 256 color escape sequence for foreground
pub fn formatAnsi256Fg(index: u8) []const u8 {
    return std.fmt.comptimePrint("\x1b[38;5;{}m", .{index});
}

/// Format ANSI 256 color escape sequence for background
pub fn formatAnsi256Bg(index: u8) []const u8 {
    return std.fmt.comptimePrint("\x1b[48;5;{}m", .{index});
}

/// Dynamic ANSI 256 color formatting
pub fn formatAnsi256FgDynamic(alloc: std.mem.Allocator, index: u8) ![]u8 {
    return std.fmt.allocPrint(alloc, "\x1b[38;5;{}m", .{index});
}

pub fn formatAnsi256BgDynamic(alloc: std.mem.Allocator, index: u8) ![]u8 {
    return std.fmt.allocPrint(alloc, "\x1b[48;5;{}m", .{index});
}

/// Set terminal color using OSC sequence
/// OSC Ps ; Pt BEL/ST
pub fn setTerminalColor(alloc: std.mem.Allocator, color_type: TerminalColorType, color: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();

    try result.appendSlice("\x1b]");

    // Add color code
    const code = color_type.toCode();
    if (code >= 10) {
        try result.append('1');
        try result.append('0' + (code - 10));
    } else {
        try result.append('0' + code);
    }

    try result.append(';');
    try result.appendSlice(color);
    try result.appendSlice("\x07"); // BEL terminator

    return try result.toOwnedSlice();
}

/// Set foreground color
pub fn setForegroundColor(alloc: std.mem.Allocator, color: []const u8) ![]u8 {
    return setTerminalColor(alloc, .foreground, color);
}

/// Set background color
pub fn setBackgroundColor(alloc: std.mem.Allocator, color: []const u8) ![]u8 {
    return setTerminalColor(alloc, .background, color);
}

/// Set cursor color
pub fn setCursorColor(alloc: std.mem.Allocator, color: []const u8) ![]u8 {
    return setTerminalColor(alloc, .cursor, color);
}

/// Set foreground color from RGB values
pub fn setForegroundColorRgb(alloc: std.mem.Allocator, r: u8, g: u8, b: u8, format: ColorFormat) ![]u8 {
    const color_str = switch (format) {
        .hex => try formatColorHex(alloc, r, g, b),
        .x11_rgb => try formatColorX11Rgb(alloc, r, g, b),
        .x11_rgba => try formatColorX11Rgba(alloc, r, g, b, 255),
        .ansi256 => {
            const index = Ansi256Palette.rgbToNearestIndex(r, g, b);
            return try formatAnsi256FgDynamic(alloc, index);
        },
        .named => return error.NamedColorsNotSupported,
    };
    defer alloc.free(color_str);

    if (format == .ansi256) {
        return color_str; // Already formatted as escape sequence
    }

    return setForegroundColor(alloc, color_str);
}

/// Set background color from RGB values
pub fn setBackgroundColorRgb(alloc: std.mem.Allocator, r: u8, g: u8, b: u8, format: ColorFormat) ![]u8 {
    const color_str = switch (format) {
        .hex => try formatColorHex(alloc, r, g, b),
        .x11_rgb => try formatColorX11Rgb(alloc, r, g, b),
        .x11_rgba => try formatColorX11Rgba(alloc, r, g, b, 255),
        .ansi256 => {
            const index = Ansi256Palette.rgbToNearestIndex(r, g, b);
            return try formatAnsi256BgDynamic(alloc, index);
        },
        .named => return error.NamedColorsNotSupported,
    };
    defer alloc.free(color_str);

    if (format == .ansi256) {
        return color_str; // Already formatted as escape sequence
    }

    return setBackgroundColor(alloc, color_str);
}

/// Set cursor color from RGB values
pub fn setCursorColorRgb(alloc: std.mem.Allocator, r: u8, g: u8, b: u8, format: ColorFormat) ![]u8 {
    const color_str = switch (format) {
        .hex => try formatColorHex(alloc, r, g, b),
        .x11_rgb => try formatColorX11Rgb(alloc, r, g, b),
        .x11_rgba => try formatColorX11Rgba(alloc, r, g, b, 255),
        .ansi256 => try formatColorHex(alloc, r, g, b), // Use hex for cursor color
        .named => return error.NamedColorsNotSupported,
    };
    defer alloc.free(color_str);

    return setCursorColor(alloc, color_str);
}

/// Set foreground color using ANSI 256 index
pub fn setForegroundAnsi256(alloc: std.mem.Allocator, index: u8) ![]u8 {
    return formatAnsi256FgDynamic(alloc, index);
}

/// Set background color using ANSI 256 index
pub fn setBackgroundAnsi256(alloc: std.mem.Allocator, index: u8) ![]u8 {
    return formatAnsi256BgDynamic(alloc, index);
}

/// Request current terminal color
/// OSC Ps ; ? BEL/ST
pub fn requestTerminalColor(alloc: std.mem.Allocator, color_type: TerminalColorType) ![]u8 {
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();

    try result.appendSlice("\x1b]");

    // Add color code
    const code = color_type.toCode();
    if (code >= 10) {
        try result.append('1');
        try result.append('0' + (code - 10));
    } else {
        try result.append('0' + code);
    }

    try result.appendSlice(";?\x07");

    return try result.toOwnedSlice();
}

/// Request foreground color
pub fn requestForegroundColor(alloc: std.mem.Allocator) ![]u8 {
    return requestTerminalColor(alloc, .foreground);
}

/// Request background color
pub fn requestBackgroundColor(alloc: std.mem.Allocator) ![]u8 {
    return requestTerminalColor(alloc, .background);
}

/// Request cursor color
pub fn requestCursorColor(alloc: std.mem.Allocator) ![]u8 {
    return requestTerminalColor(alloc, .cursor);
}

/// Reset terminal color to default
/// OSC Ps+100 BEL/ST
pub fn resetTerminalColor(alloc: std.mem.Allocator, color_type: TerminalColorType) ![]u8 {
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();

    try result.appendSlice("\x1b]");

    // Reset code is original code + 100
    const reset_code = color_type.toCode() + 100;
    if (reset_code >= 100) {
        const hundreds = reset_code / 100;
        const remainder = reset_code % 100;
        try result.append('0' + @as(u8, @intCast(hundreds)));
        if (remainder >= 10) {
            try result.append('0' + @as(u8, @intCast(remainder / 10)));
        }
        try result.append('0' + @as(u8, @intCast(remainder % 10)));
    }

    try result.appendSlice("\x07");

    return try result.toOwnedSlice();
}

/// Reset foreground color to default
pub fn resetForegroundColor(alloc: std.mem.Allocator) ![]u8 {
    return resetTerminalColor(alloc, .foreground);
}

/// Reset background color to default
pub fn resetBackgroundColor(alloc: std.mem.Allocator) ![]u8 {
    return resetTerminalColor(alloc, .background);
}

/// Reset cursor color to default
pub fn resetCursorColor(alloc: std.mem.Allocator) ![]u8 {
    return resetTerminalColor(alloc, .cursor);
}

/// Color response parser
pub const ColorResponse = struct {
    r: u8,
    g: u8,
    b: u8,
    format: ColorFormat,
};

/// Parse color response from terminal
/// Expected formats:
/// - OSC 10 ; rgb:rrrr/gggg/bbbb BEL  (X11 RGB)
/// - OSC 10 ; #rrggbb BEL             (Hex)
pub fn parseColorResponse(response: []const u8) ?ColorResponse {
    // Find OSC sequence start
    const osc_start = std.mem.indexOf(u8, response, "\x1b]1");
    if (osc_start == null) return null;

    // Find semicolon separator
    const semi_pos = std.mem.indexOfScalarPos(u8, response, osc_start.? + 3, ';');
    if (semi_pos == null) return null;

    // Find terminator (BEL or ST)
    var end_pos = std.mem.indexOfScalarPos(u8, response, semi_pos.? + 1, '\x07'); // BEL
    if (end_pos == null) {
        const st_pos = std.mem.indexOfPos(u8, response, semi_pos.? + 1, "\x1b\\");
        if (st_pos != null) {
            end_pos = st_pos;
        }
    }
    if (end_pos == null) return null;

    const color_str = response[semi_pos.? + 1 .. end_pos.?];

    // Parse different color formats
    if (color_str.len >= 7 and color_str[0] == '#') {
        // Hex format: #rrggbb
        const r = std.fmt.parseInt(u8, color_str[1..3], 16) catch return null;
        const g = std.fmt.parseInt(u8, color_str[3..5], 16) catch return null;
        const b = std.fmt.parseInt(u8, color_str[5..7], 16) catch return null;
        return ColorResponse{ .r = r, .g = g, .b = b, .format = .hex };
    } else if (std.mem.startsWith(u8, color_str, "rgb:")) {
        // X11 RGB format: rgb:rrrr/gggg/bbbb
        var parts = std.mem.split(u8, color_str[4..], "/");

        const r_str = parts.next() orelse return null;
        const g_str = parts.next() orelse return null;
        const b_str = parts.next() orelse return null;

        // X11 uses 16-bit values, take high 8 bits
        const r16 = std.fmt.parseInt(u16, r_str, 16) catch return null;
        const g16 = std.fmt.parseInt(u16, g_str, 16) catch return null;
        const b16 = std.fmt.parseInt(u16, b_str, 16) catch return null;

        const r = @as(u8, @truncate(r16 >> 8));
        const g = @as(u8, @truncate(g16 >> 8));
        const b = @as(u8, @truncate(b16 >> 8));

        return ColorResponse{ .r = r, .g = g, .b = b, .format = .x11_rgb };
    }

    return null;
}

/// High-level terminal color manager with ANSI 256 support
pub const TerminalColorManager = struct {
    alloc: std.mem.Allocator,
    use_ansi256: bool = false,

    pub fn init(alloc: std.mem.Allocator) TerminalColorManager {
        return TerminalColorManager{
            .alloc = alloc,
            .use_ansi256 = false,
        };
    }

    pub fn initWith256(alloc: std.mem.Allocator) TerminalColorManager {
        return TerminalColorManager{
            .alloc = alloc,
            .use_ansi256 = true,
        };
    }

    /// Set dark theme colors
    pub fn setDarkTheme(self: *TerminalColorManager) ![]u8 {
        if (self.use_ansi256) {
            // Use ANSI 256 colors for dark theme
            const bg_seq = try setBackgroundAnsi256(self.alloc, 234); // Dark gray
            defer self.alloc.free(bg_seq);

            const fg_seq = try setForegroundAnsi256(self.alloc, 252); // Light gray
            defer self.alloc.free(fg_seq);

            var result = std.ArrayList(u8).init(self.alloc);
            errdefer result.deinit();

            try result.appendSlice(bg_seq);
            try result.appendSlice(fg_seq);

            return try result.toOwnedSlice();
        } else {
            const bg_seq = try setBackgroundColor(self.alloc, "#1a1a1a");
            defer self.alloc.free(bg_seq);

            const fg_seq = try setForegroundColor(self.alloc, "#e0e0e0");
            defer self.alloc.free(fg_seq);

            const cursor_seq = try setCursorColor(self.alloc, "#ffffff");
            defer self.alloc.free(cursor_seq);

            // Combine all sequences
            var result = std.ArrayList(u8).init(self.alloc);
            errdefer result.deinit();

            try result.appendSlice(bg_seq);
            try result.appendSlice(fg_seq);
            try result.appendSlice(cursor_seq);

            return try result.toOwnedSlice();
        }
    }

    /// Set light theme colors
    pub fn setLightTheme(self: *TerminalColorManager) ![]u8 {
        if (self.use_ansi256) {
            // Use ANSI 256 colors for light theme
            const bg_seq = try setBackgroundAnsi256(self.alloc, 231); // Near white
            defer self.alloc.free(bg_seq);

            const fg_seq = try setForegroundAnsi256(self.alloc, 235); // Dark gray
            defer self.alloc.free(fg_seq);

            var result = std.ArrayList(u8).init(self.alloc);
            errdefer result.deinit();

            try result.appendSlice(bg_seq);
            try result.appendSlice(fg_seq);

            return try result.toOwnedSlice();
        } else {
            const bg_seq = try setBackgroundColor(self.alloc, "#f8f8f8");
            defer self.alloc.free(bg_seq);

            const fg_seq = try setForegroundColor(self.alloc, "#2a2a2a");
            defer self.alloc.free(fg_seq);

            const cursor_seq = try setCursorColor(self.alloc, "#000000");
            defer self.alloc.free(cursor_seq);

            // Combine all sequences
            var result = std.ArrayList(u8).init(self.alloc);
            errdefer result.deinit();

            try result.appendSlice(bg_seq);
            try result.appendSlice(fg_seq);
            try result.appendSlice(cursor_seq);

            return try result.toOwnedSlice();
        }
    }

    /// Set gradient background using ANSI 256 colors
    pub fn setGradientBackground(self: *TerminalColorManager, start_idx: u8, end_idx: u8, steps: u8) ![]u8 {
        _ = self;
        _ = start_idx;
        _ = end_idx;
        _ = steps;
        // This would create a gradient effect by outputting multiple background colors
        // Implementation depends on terminal capabilities and desired effect
        return error.NotImplemented;
    }

    /// Create color palette display
    pub fn displayAnsi256Palette(self: *TerminalColorManager) ![]u8 {
        var result = std.ArrayList(u8).init(self.alloc);
        errdefer result.deinit();

        // Display standard 16 colors
        try result.appendSlice("Standard colors (0-15):\n");
        var i: u8 = 0;
        while (i < 16) : (i += 1) {
            const seq = try formatAnsi256BgDynamic(self.alloc, i);
            defer self.alloc.free(seq);
            try result.appendSlice(seq);
            try result.appendSlice("  ");
            if ((i + 1) % 8 == 0) {
                try result.appendSlice("\x1b[0m\n");
            }
        }

        // Display color cube
        try result.appendSlice("\nColor cube (16-231):\n");
        i = 16;
        while (i < 232) : (i += 1) {
            const seq = try formatAnsi256BgDynamic(self.alloc, i);
            defer self.alloc.free(seq);
            try result.appendSlice(seq);
            try result.appendSlice("  ");
            if ((i - 15) % 36 == 0) {
                try result.appendSlice("\x1b[0m\n");
            }
        }

        // Display grayscale
        try result.appendSlice("\nGrayscale (232-255):\n");
        i = 232;
        while (i <= 255) : (i += 1) {
            const seq = try formatAnsi256BgDynamic(self.alloc, i);
            defer self.alloc.free(seq);
            try result.appendSlice(seq);
            try result.appendSlice("  ");
        }
        try result.appendSlice("\x1b[0m\n");

        return try result.toOwnedSlice();
    }

    /// Reset all colors to defaults
    pub fn resetAllColors(self: *TerminalColorManager) ![]u8 {
        const reset_bg = try resetBackgroundColor(self.alloc);
        defer self.alloc.free(reset_bg);

        const reset_fg = try resetForegroundColor(self.alloc);
        defer self.alloc.free(reset_fg);

        const reset_cursor = try resetCursorColor(self.alloc);
        defer self.alloc.free(reset_cursor);

        // Combine all sequences
        var result = std.ArrayList(u8).init(self.alloc);
        errdefer result.deinit();

        try result.appendSlice(reset_bg);
        try result.appendSlice(reset_fg);
        try result.appendSlice(reset_cursor);
        try result.appendSlice("\x1b[0m"); // Reset all attributes

        return try result.toOwnedSlice();
    }

    /// Query current background color
    pub fn queryBackground(self: *TerminalColorManager) ![]u8 {
        return requestBackgroundColor(self.alloc);
    }

    /// Query current foreground color
    pub fn queryForeground(self: *TerminalColorManager) ![]u8 {
        return requestForegroundColor(self.alloc);
    }

    /// Set color from HSL values
    pub fn setColorHsl(
        self: *TerminalColorManager,
        color_type: TerminalColorType,
        h: f32,
        s: f32,
        l: f32,
    ) ![]u8 {
        const rgb = hslToRgb(h, s, l);
        const format: ColorFormat = if (self.use_ansi256) .ansi256 else .hex;

        return switch (color_type) {
            .foreground => try setForegroundColorRgb(self.alloc, rgb.r, rgb.g, rgb.b, format),
            .background => try setBackgroundColorRgb(self.alloc, rgb.r, rgb.g, rgb.b, format),
            .cursor => try setCursorColorRgb(self.alloc, rgb.r, rgb.g, rgb.b, format),
            else => error.UnsupportedColorType,
        };
    }

    /// Get color as RGB from ANSI 256 index
    pub fn getAnsi256Rgb(self: *TerminalColorManager, index: u8) RgbColor {
        _ = self;
        return Ansi256Palette.indexToRgb(index);
    }

    /// Find best ANSI 256 match for RGB
    pub fn findBestAnsi256(self: *TerminalColorManager, r: u8, g: u8, b: u8) u8 {
        _ = self;
        return Ansi256Palette.rgbToNearestIndex(r, g, b);
    }
};

/// Constants for common sequences
pub const REQUEST_FOREGROUND_COLOR = "\x1b]10;?\x07";
pub const REQUEST_BACKGROUND_COLOR = "\x1b]11;?\x07";
pub const REQUEST_CURSOR_COLOR = "\x1b]12;?\x07";
pub const RESET_FOREGROUND_COLOR = "\x1b]110\x07";
pub const RESET_BACKGROUND_COLOR = "\x1b]111\x07";
pub const RESET_CURSOR_COLOR = "\x1b]112\x07";
pub const RESET_ALL_ATTRIBUTES = "\x1b[0m";

// ============================================================================
// Tests
// ============================================================================

test "color formatting" {
    const testing = std.testing;
    const alloc = testing.allocator;

    // Test hex formatting
    const hex = try formatColorHex(alloc, 255, 128, 64);
    defer alloc.free(hex);
    try testing.expectEqualStrings("#ff8040", hex);

    // Test X11 RGB formatting
    const x11_rgb = try formatColorX11Rgb(alloc, 255, 0, 0);
    defer alloc.free(x11_rgb);
    try testing.expectEqualStrings("rgb:ffff/0000/0000", x11_rgb);

    // Test X11 RGBA formatting
    const x11_rgba = try formatColorX11Rgba(alloc, 128, 128, 128, 128);
    defer alloc.free(x11_rgba);
    try testing.expectEqualStrings("rgba:8080/8080/8080/8080", x11_rgba);
}

test "ANSI 256 color palette" {
    const testing = std.testing;

    // Test standard colors
    const black = Ansi256Palette.indexToRgb(0);
    try testing.expectEqual(@as(u8, 0x00), black.r);
    try testing.expectEqual(@as(u8, 0x00), black.g);
    try testing.expectEqual(@as(u8, 0x00), black.b);

    const bright_red = Ansi256Palette.indexToRgb(9);
    try testing.expectEqual(@as(u8, 0xff), bright_red.r);
    try testing.expectEqual(@as(u8, 0x00), bright_red.g);
    try testing.expectEqual(@as(u8, 0x00), bright_red.b);

    // Test color cube
    const cube_color = Ansi256Palette.indexToRgb(16); // First cube color
    try testing.expectEqual(@as(u8, 0x00), cube_color.r);
    try testing.expectEqual(@as(u8, 0x00), cube_color.g);
    try testing.expectEqual(@as(u8, 0x00), cube_color.b);

    // Test grayscale
    const gray = Ansi256Palette.indexToRgb(240);
    const expected_gray = Ansi256Palette.getGrayscaleValue(240);
    try testing.expectEqual(expected_gray, gray.r);
    try testing.expectEqual(expected_gray, gray.g);
    try testing.expectEqual(expected_gray, gray.b);
}

test "RGB to ANSI 256 conversion" {
    const testing = std.testing;

    // Test exact match
    const red_idx = Ansi256Palette.rgbToNearestIndex(255, 0, 0);
    try testing.expectEqual(@as(u8, 9), red_idx); // Bright red

    // Test grayscale detection
    const gray_idx = Ansi256Palette.rgbToNearestIndex(128, 128, 128);
    const palette_color = Ansi256Palette.indexToRgb(gray_idx);
    const dist = RgbColor.init(128, 128, 128).distance(palette_color);
    try testing.expect(dist < 1000); // Should be reasonably close
}

test "HSL to RGB conversion" {
    const testing = std.testing;

    // Test pure red
    const red = hslToRgb(0.0, 1.0, 0.5);
    try testing.expectEqual(@as(u8, 255), red.r);
    try testing.expectEqual(@as(u8, 0), red.g);
    try testing.expectEqual(@as(u8, 0), red.b);

    // Test gray (no saturation)
    const gray = hslToRgb(0.0, 0.0, 0.5);
    try testing.expectEqual(@as(u8, 127), gray.r);
    try testing.expectEqual(@as(u8, 127), gray.g);
    try testing.expectEqual(@as(u8, 127), gray.b);
}

test "RGB to HSL conversion" {
    const testing = std.testing;

    // Test pure red
    const red_hsl = rgbToHsl(255, 0, 0);
    try testing.expectApproxEqAbs(@as(f32, 0.0), red_hsl.h, 0.1);
    try testing.expectApproxEqAbs(@as(f32, 1.0), red_hsl.s, 0.01);
    try testing.expectApproxEqAbs(@as(f32, 0.5), red_hsl.l, 0.01);

    // Test gray
    const gray_hsl = rgbToHsl(128, 128, 128);
    try testing.expectApproxEqAbs(@as(f32, 0.0), gray_hsl.s, 0.01);
}

test "color setting sequences with ANSI 256" {
    const testing = std.testing;
    const alloc = testing.allocator;

    // Test ANSI 256 foreground
    const fg_256 = try setForegroundAnsi256(alloc, 196);
    defer alloc.free(fg_256);
    try testing.expectEqualStrings("\x1b[38;5;196m", fg_256);

    // Test ANSI 256 background
    const bg_256 = try setBackgroundAnsi256(alloc, 21);
    defer alloc.free(bg_256);
    try testing.expectEqualStrings("\x1b[48;5;21m", bg_256);
}

test "terminal color manager with ANSI 256" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var manager = TerminalColorManager.initWith256(alloc);

    const dark_theme = try manager.setDarkTheme();
    defer alloc.free(dark_theme);
    try testing.expect(dark_theme.len > 0);

    const light_theme = try manager.setLightTheme();
    defer alloc.free(light_theme);
    try testing.expect(light_theme.len > 0);

    // Test HSL color setting
    const hsl_color = try manager.setColorHsl(.foreground, 120.0, 0.5, 0.5);
    defer alloc.free(hsl_color);
    try testing.expect(hsl_color.len > 0);

    // Test finding best ANSI 256 match
    const best_idx = manager.findBestAnsi256(200, 100, 50);
    try testing.expect(best_idx < 256);

    // Test getting RGB from index
    const rgb = manager.getAnsi256Rgb(196);
    try testing.expect(rgb.r > 0 or rgb.g > 0 or rgb.b > 0);
}

test "color response parsing" {
    const testing = std.testing;

    // Test hex response parsing
    const hex_response = "\x1b]11;#ff0000\x07";
    const hex_parsed = parseColorResponse(hex_response);
    try testing.expect(hex_parsed != null);
    try testing.expect(hex_parsed.?.r == 255);
    try testing.expect(hex_parsed.?.g == 0);
    try testing.expect(hex_parsed.?.b == 0);
    try testing.expect(hex_parsed.?.format == .hex);

    // Test X11 RGB response parsing
    const x11_response = "\x1b]10;rgb:8080/4040/2020\x07";
    const x11_parsed = parseColorResponse(x11_response);
    try testing.expect(x11_parsed != null);
    try testing.expect(x11_parsed.?.r == 128); // 0x8080 >> 8 = 0x80 = 128
    try testing.expect(x11_parsed.?.g == 64); // 0x4040 >> 8 = 0x40 = 64
    try testing.expect(x11_parsed.?.b == 32); // 0x2020 >> 8 = 0x20 = 32
    try testing.expect(x11_parsed.?.format == .x11_rgb);
}

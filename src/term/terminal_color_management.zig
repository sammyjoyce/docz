const std = @import("std");

/// Terminal color management for foreground, background, and cursor colors
/// Implements OSC sequences for querying and setting terminal colors
/// 
/// This enables applications to:
/// - Query current terminal colors to adapt themes
/// - Set custom colors that persist across applications  
/// - Reset colors to defaults
/// - Support for multiple color formats (hex, X11 rgb/rgba)
///
/// See: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Operating-System-Commands

/// Color format types for terminal color specifications
pub const ColorFormat = enum {
    hex,        // #rrggbb
    x11_rgb,    // rgb:rrrr/gggg/bbbb  
    x11_rgba,   // rgba:rrrr/gggg/bbbb/aaaa
    named,      // CSS color names
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
        .named => return error.NamedColorsNotSupported,
    };
    defer alloc.free(color_str);
    
    return setForegroundColor(alloc, color_str);
}

/// Set background color from RGB values
pub fn setBackgroundColorRgb(alloc: std.mem.Allocator, r: u8, g: u8, b: u8, format: ColorFormat) ![]u8 {
    const color_str = switch (format) {
        .hex => try formatColorHex(alloc, r, g, b),
        .x11_rgb => try formatColorX11Rgb(alloc, r, g, b),
        .x11_rgba => try formatColorX11Rgba(alloc, r, g, b, 255),
        .named => return error.NamedColorsNotSupported,
    };
    defer alloc.free(color_str);
    
    return setBackgroundColor(alloc, color_str);
}

/// Set cursor color from RGB values
pub fn setCursorColorRgb(alloc: std.mem.Allocator, r: u8, g: u8, b: u8, format: ColorFormat) ![]u8 {
    const color_str = switch (format) {
        .hex => try formatColorHex(alloc, r, g, b),
        .x11_rgb => try formatColorX11Rgb(alloc, r, g, b),
        .x11_rgba => try formatColorX11Rgba(alloc, r, g, b, 255),
        .named => return error.NamedColorsNotSupported,
    };
    defer alloc.free(color_str);
    
    return setCursorColor(alloc, color_str);
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

/// High-level terminal color manager
pub const TerminalColorManager = struct {
    alloc: std.mem.Allocator,
    
    pub fn init(alloc: std.mem.Allocator) TerminalColorManager {
        return TerminalColorManager{ .alloc = alloc };
    }
    
    /// Set dark theme colors
    pub fn setDarkTheme(self: *TerminalColorManager) ![]u8 {
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
    
    /// Set light theme colors
    pub fn setLightTheme(self: *TerminalColorManager) ![]u8 {
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
};

/// Constants for common sequences
pub const REQUEST_FOREGROUND_COLOR = "\x1b]10;?\x07";
pub const REQUEST_BACKGROUND_COLOR = "\x1b]11;?\x07";
pub const REQUEST_CURSOR_COLOR = "\x1b]12;?\x07";
pub const RESET_FOREGROUND_COLOR = "\x1b]110\x07";
pub const RESET_BACKGROUND_COLOR = "\x1b]111\x07";
pub const RESET_CURSOR_COLOR = "\x1b]112\x07";

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

test "color setting sequences" {
    const testing = std.testing;
    const alloc = testing.allocator;
    
    // Test setting background color
    const bg_seq = try setBackgroundColor(alloc, "#123456");
    defer alloc.free(bg_seq);
    try testing.expectEqualStrings("\x1b]11;#123456\x07", bg_seq);
    
    // Test setting foreground color from RGB
    const fg_seq = try setForegroundColorRgb(alloc, 255, 0, 0, .hex);
    defer alloc.free(fg_seq);
    try testing.expectEqualStrings("\x1b]10;#ff0000\x07", fg_seq);
}

test "color request sequences" {
    const testing = std.testing;
    const alloc = testing.allocator;
    
    const bg_request = try requestBackgroundColor(alloc);
    defer alloc.free(bg_request);
    try testing.expectEqualStrings(REQUEST_BACKGROUND_COLOR, bg_request);
    
    const fg_request = try requestForegroundColor(alloc);
    defer alloc.free(fg_request);
    try testing.expectEqualStrings(REQUEST_FOREGROUND_COLOR, fg_request);
    
    const cursor_request = try requestCursorColor(alloc);
    defer alloc.free(cursor_request);
    try testing.expectEqualStrings(REQUEST_CURSOR_COLOR, cursor_request);
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
    try testing.expect(x11_parsed.?.g == 64);  // 0x4040 >> 8 = 0x40 = 64
    try testing.expect(x11_parsed.?.b == 32);  // 0x2020 >> 8 = 0x20 = 32
    try testing.expect(x11_parsed.?.format == .x11_rgb);
}

test "color reset sequences" {
    const testing = std.testing;
    const alloc = testing.allocator;
    
    const reset_bg = try resetBackgroundColor(alloc);
    defer alloc.free(reset_bg);
    try testing.expectEqualStrings(RESET_BACKGROUND_COLOR, reset_bg);
    
    const reset_fg = try resetForegroundColor(alloc);
    defer alloc.free(reset_fg);
    try testing.expectEqualStrings(RESET_FOREGROUND_COLOR, reset_fg);
}

test "terminal color manager" {
    const testing = std.testing;
    const alloc = testing.allocator;
    
    var manager = TerminalColorManager.init(alloc);
    
    const dark_theme = try manager.setDarkTheme();
    defer alloc.free(dark_theme);
    try testing.expect(dark_theme.len > 0);
    
    const light_theme = try manager.setLightTheme();
    defer alloc.free(light_theme);
    try testing.expect(light_theme.len > 0);
    
    const reset_all = try manager.resetAllColors();
    defer alloc.free(reset_all);
    try testing.expect(reset_all.len > 0);
    
    const query_bg = try manager.queryBackground();
    defer alloc.free(query_bg);
    try testing.expectEqualStrings(REQUEST_BACKGROUND_COLOR, query_bg);
}
const std = @import("std");

/// Color event types for terminal color queries (OSC responses)
pub const ColorEvent = union(enum) {
    foreground: Color,
    background: Color,
    cursor: Color,
};

/// RGB color representation
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    /// Parse color from OSC response format (e.g., "rgb:ffff/0000/0000")
    pub fn parseOscColor(response: []const u8) ?Color {
        // Handle rgb:rrrr/gggg/bbbb format
        if (std.mem.startsWith(u8, response, "rgb:")) {
            const color_part = response[4..];
            var parts = std.mem.splitSequence(u8, color_part, "/");
            
            const r_str = parts.next() orelse return null;
            const g_str = parts.next() orelse return null;
            const b_str = parts.next() orelse return null;
            
            // Convert 16-bit hex values to 8-bit
            const r16 = std.fmt.parseInt(u16, r_str, 16) catch return null;
            const g16 = std.fmt.parseInt(u16, g_str, 16) catch return null;
            const b16 = std.fmt.parseInt(u16, b_str, 16) catch return null;
            
            return Color{
                .r = @intCast(r16 >> 8),
                .g = @intCast(g16 >> 8),
                .b = @intCast(b16 >> 8),
            };
        }
        
        // Handle #rrggbb hex format
        if (std.mem.startsWith(u8, response, "#") and response.len == 7) {
            const hex_part = response[1..];
            const rgb = std.fmt.parseInt(u24, hex_part, 16) catch return null;
            
            return Color{
                .r = @intCast((rgb >> 16) & 0xFF),
                .g = @intCast((rgb >> 8) & 0xFF),
                .b = @intCast(rgb & 0xFF),
            };
        }
        
        return null;
    }
    
    /// Convert color to hex string format (#rrggbb)
    pub fn toHex(self: Color) [7]u8 {
        var buf: [7]u8 = undefined;
        buf[0] = '#';
        _ = std.fmt.bufPrint(buf[1..], "{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b }) catch unreachable;
        return buf;
    }
    
    /// Determine if the color is considered "dark" using HSL lightness
    pub fn isDark(self: Color) bool {
        const lightness = self.getLightness();
        return lightness < 0.5;
    }
    
    /// Calculate HSL lightness value (0.0 to 1.0)
    pub fn getLightness(self: Color) f64 {
        const r_norm = @as(f64, @floatFromInt(self.r)) / 255.0;
        const g_norm = @as(f64, @floatFromInt(self.g)) / 255.0;
        const b_norm = @as(f64, @floatFromInt(self.b)) / 255.0;
        
        const max_val = @max(r_norm, @max(g_norm, b_norm));
        const min_val = @min(r_norm, @min(g_norm, b_norm));
        
        return (max_val + min_val) / 2.0;
    }
};

/// Parse OSC 10/11/12 color response
/// Format: ESC ] code ; color ST  or  ESC ] code ; color BEL
pub fn parseOscResponse(seq: []const u8) ?ColorEvent {
    if (seq.len < 8) return null; // Minimum: "\x1b]10;?\x07"
    
    if (!std.mem.startsWith(u8, seq, "\x1b]")) return null;
    
    // Find the terminator (ST or BEL)
    const end_pos = blk: {
        if (std.mem.indexOf(u8, seq, "\x1b\\")) |pos| break :blk pos; // ST
        if (std.mem.indexOf(u8, seq, "\x07")) |pos| break :blk pos;   // BEL
        return null;
    };
    
    const content = seq[2..end_pos]; // Skip ESC ]
    const semicolon_pos = std.mem.indexOf(u8, content, ";") orelse return null;
    
    const code_str = content[0..semicolon_pos];
    const color_str = content[semicolon_pos + 1..];
    
    const code = std.fmt.parseInt(u8, code_str, 10) catch return null;
    const color = Color.parseOscColor(color_str) orelse return null;
    
    return switch (code) {
        10 => ColorEvent{ .foreground = color },
        11 => ColorEvent{ .background = color },
        12 => ColorEvent{ .cursor = color },
        else => null,
    };
}

test "parse OSC color response" {
    // Test foreground color response
    const fg_response = "\x1b]10;rgb:ffff/0000/0000\x07";
    const fg_event = parseOscResponse(fg_response).?;
    try std.testing.expectEqual(ColorEvent.foreground, std.meta.activeTag(fg_event));
    const fg_color = switch (fg_event) {
        .foreground => |c| c,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(u8, 255), fg_color.r);
    try std.testing.expectEqual(@as(u8, 0), fg_color.g);
    try std.testing.expectEqual(@as(u8, 0), fg_color.b);
    
    // Test background color response with hex format
    const bg_response = "\x1b]11;#00ff00\x1b\\";
    const bg_event = parseOscResponse(bg_response).?;
    try std.testing.expectEqual(ColorEvent.background, std.meta.activeTag(bg_event));
    
    // Test invalid sequence
    const invalid_response = "\x1b]99;invalid\x07";
    try std.testing.expectEqual(@as(?ColorEvent, null), parseOscResponse(invalid_response));
}

test "color hex conversion" {
    const red = Color{ .r = 255, .g = 0, .b = 0 };
    const hex = red.toHex();
    try std.testing.expectEqualStrings("#ff0000", &hex);
}

test "color darkness detection" {
    const black = Color{ .r = 0, .g = 0, .b = 0 };
    const white = Color{ .r = 255, .g = 255, .b = 255 };
    const gray = Color{ .r = 128, .g = 128, .b = 128 };
    
    try std.testing.expect(black.isDark());
    try std.testing.expect(!white.isDark());
    try std.testing.expect(!gray.isDark()); // 0.5 lightness is not considered dark
}
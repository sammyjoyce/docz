//! Terminal Color Operations
//! ANSI escape sequences and terminal color control
//! Consolidates all terminal-specific color functionality

const std = @import("std");
const types = @import("types.zig");
const conversions = @import("conversions.zig");
const distance = @import("distance.zig");

pub const RGB = types.RGB;
pub const TerminalColor = types.TerminalColor;
pub const Ansi16 = types.Ansi16;
pub const Ansi256 = types.Ansi256;

// === ANSI ESCAPE SEQUENCES ===

pub const ColorLayer = enum {
    foreground,
    background,
};

/// Generate ANSI escape sequence for a color
pub fn toAnsiSequence(color: TerminalColor, layer: ColorLayer) []const u8 {
    return switch (layer) {
        .foreground => switch (color) {
            .default => "\x1b[39m",
            .ansi16 => |c| formatAnsi16Fg(c),
            .ansi256 => |c| formatAnsi256Fg(c.index),
            .rgb => |c| formatRgbFg(c),
        },
        .background => switch (color) {
            .default => "\x1b[49m",
            .ansi16 => |c| formatAnsi16Bg(c),
            .ansi256 => |c| formatAnsi256Bg(c.index),
            .rgb => |c| formatRgbBg(c),
        },
    };
}

fn formatAnsi16Fg(color: Ansi16) []const u8 {
    const code = @intFromEnum(color);
    return switch (code) {
        0 => "\x1b[30m",
        1 => "\x1b[31m",
        2 => "\x1b[32m",
        3 => "\x1b[33m",
        4 => "\x1b[34m",
        5 => "\x1b[35m",
        6 => "\x1b[36m",
        7 => "\x1b[37m",
        8 => "\x1b[90m",
        9 => "\x1b[91m",
        10 => "\x1b[92m",
        11 => "\x1b[93m",
        12 => "\x1b[94m",
        13 => "\x1b[95m",
        14 => "\x1b[96m",
        15 => "\x1b[97m",
    };
}

fn formatAnsi16Bg(color: Ansi16) []const u8 {
    const code = @intFromEnum(color);
    return switch (code) {
        0 => "\x1b[40m",
        1 => "\x1b[41m",
        2 => "\x1b[42m",
        3 => "\x1b[43m",
        4 => "\x1b[44m",
        5 => "\x1b[45m",
        6 => "\x1b[46m",
        7 => "\x1b[47m",
        8 => "\x1b[100m",
        9 => "\x1b[101m",
        10 => "\x1b[102m",
        11 => "\x1b[103m",
        12 => "\x1b[104m",
        13 => "\x1b[105m",
        14 => "\x1b[106m",
        15 => "\x1b[107m",
    };
}

fn formatAnsi256Fg(index: u8) []const u8 {
    var buf: [20]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "\x1b[38;5;{d}m", .{index}) catch unreachable;
    return result;
}

fn formatAnsi256Bg(index: u8) []const u8 {
    var buf: [20]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "\x1b[48;5;{d}m", .{index}) catch unreachable;
    return result;
}

fn formatRgbFg(rgb: RGB) []const u8 {
    var buf: [30]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "\x1b[38;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }) catch unreachable;
    return result;
}

fn formatRgbBg(rgb: RGB) []const u8 {
    var buf: [30]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "\x1b[48;2;{d};{d};{d}m", .{ rgb.r, rgb.g, rgb.b }) catch unreachable;
    return result;
}

// === DYNAMIC ESCAPE SEQUENCE GENERATION ===

pub const AnsiBuilder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) AnsiBuilder {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *AnsiBuilder) void {
        self.buffer.deinit();
    }

    pub fn setForeground(self: *AnsiBuilder, color: TerminalColor) !void {
        try self.appendColorSequence(color, .foreground);
    }

    pub fn setBackground(self: *AnsiBuilder, color: TerminalColor) !void {
        try self.appendColorSequence(color, .background);
    }

    pub fn reset(self: *AnsiBuilder) !void {
        try self.buffer.appendSlice("\x1b[0m");
    }

    pub fn bold(self: *AnsiBuilder) !void {
        try self.buffer.appendSlice("\x1b[1m");
    }

    pub fn italic(self: *AnsiBuilder) !void {
        try self.buffer.appendSlice("\x1b[3m");
    }

    pub fn underline(self: *AnsiBuilder) !void {
        try self.buffer.appendSlice("\x1b[4m");
    }

    pub fn blink(self: *AnsiBuilder) !void {
        try self.buffer.appendSlice("\x1b[5m");
    }

    pub fn reverse(self: *AnsiBuilder) !void {
        try self.buffer.appendSlice("\x1b[7m");
    }

    pub fn strikethrough(self: *AnsiBuilder) !void {
        try self.buffer.appendSlice("\x1b[9m");
    }

    pub fn text(self: *AnsiBuilder, str: []const u8) !void {
        try self.buffer.appendSlice(str);
    }

    pub fn build(self: *AnsiBuilder) []const u8 {
        return self.buffer.items;
    }

    fn appendColorSequence(self: *AnsiBuilder, color: TerminalColor, layer: ColorLayer) !void {
        switch (layer) {
            .foreground => switch (color) {
                .default => try self.buffer.appendSlice("\x1b[39m"),
                .ansi16 => |c| {
                    const code = @intFromEnum(c);
                    if (code < 8) {
                        try self.buffer.writer().print("\x1b[{d}m", .{30 + code});
                    } else {
                        try self.buffer.writer().print("\x1b[{d}m", .{82 + code});
                    }
                },
                .ansi256 => |c| {
                    try self.buffer.writer().print("\x1b[38;5;{d}m", .{c.index});
                },
                .rgb => |c| {
                    try self.buffer.writer().print("\x1b[38;2;{d};{d};{d}m", .{ c.r, c.g, c.b });
                },
            },
            .background => switch (color) {
                .default => try self.buffer.appendSlice("\x1b[49m"),
                .ansi16 => |c| {
                    const code = @intFromEnum(c);
                    if (code < 8) {
                        try self.buffer.writer().print("\x1b[{d}m", .{40 + code});
                    } else {
                        try self.buffer.writer().print("\x1b[{d}m", .{92 + code});
                    }
                },
                .ansi256 => |c| {
                    try self.buffer.writer().print("\x1b[48;5;{d}m", .{c.index});
                },
                .rgb => |c| {
                    try self.buffer.writer().print("\x1b[48;2;{d};{d};{d}m", .{ c.r, c.g, c.b });
                },
            },
        }
    }
};

// === COLOR DOWNGRADE ===

pub const ColorMode = enum {
    no_color,
    ansi16,
    ansi256,
    true_color,
};

/// Downgrade a color to the specified mode
pub fn downgradeColor(color: TerminalColor, mode: ColorMode) TerminalColor {
    return switch (mode) {
        .no_color => .default,
        .ansi16 => switch (color) {
            .default, .ansi16 => color,
            .ansi256 => |c| blk: {
                const rgb = conversions.ansi256ToRgb(c.index);
                break :blk .{ .ansi16 = findClosestAnsi16(rgb) };
            },
            .rgb => |c| .{ .ansi16 = findClosestAnsi16(c) },
        },
        .ansi256 => switch (color) {
            .default, .ansi16, .ansi256 => color,
            .rgb => |c| .{ .ansi256 = conversions.rgbToAnsi256(c) },
        },
        .true_color => color,
    };
}

fn findClosestAnsi16(rgb: RGB) Ansi16 {
    const ansi16_colors = [_]struct { color: Ansi16, rgb: RGB }{
        .{ .color = .black, .rgb = RGB.init(0, 0, 0) },
        .{ .color = .red, .rgb = RGB.init(205, 49, 49) },
        .{ .color = .green, .rgb = RGB.init(13, 188, 121) },
        .{ .color = .yellow, .rgb = RGB.init(229, 229, 16) },
        .{ .color = .blue, .rgb = RGB.init(36, 114, 200) },
        .{ .color = .magenta, .rgb = RGB.init(188, 63, 188) },
        .{ .color = .cyan, .rgb = RGB.init(17, 168, 205) },
        .{ .color = .white, .rgb = RGB.init(229, 229, 229) },
        .{ .color = .bright_black, .rgb = RGB.init(102, 102, 102) },
        .{ .color = .bright_red, .rgb = RGB.init(241, 76, 76) },
        .{ .color = .bright_green, .rgb = RGB.init(35, 209, 139) },
        .{ .color = .bright_yellow, .rgb = RGB.init(245, 245, 67) },
        .{ .color = .bright_blue, .rgb = RGB.init(59, 142, 234) },
        .{ .color = .bright_magenta, .rgb = RGB.init(214, 112, 214) },
        .{ .color = .bright_cyan, .rgb = RGB.init(41, 184, 219) },
        .{ .color = .bright_white, .rgb = RGB.init(255, 255, 255) },
    };

    var best_color = Ansi16.black;
    var best_distance = distance.rgbWeighted(rgb, ansi16_colors[0].rgb);

    for (ansi16_colors[1..]) |entry| {
        const dist = distance.rgbWeighted(rgb, entry.rgb);
        if (dist < best_distance) {
            best_distance = dist;
            best_color = entry.color;
        }
    }

    return best_color;
}

// === COLOR PARSING ===

pub fn parseHex(str: []const u8) !RGB {
    var hex_str = str;

    // Remove leading # if present
    if (hex_str.len > 0 and hex_str[0] == '#') {
        hex_str = hex_str[1..];
    }

    // Support both 3 and 6 character hex
    if (hex_str.len == 3) {
        const r = try std.fmt.parseInt(u8, hex_str[0..1], 16) * 17;
        const g = try std.fmt.parseInt(u8, hex_str[1..2], 16) * 17;
        const b = try std.fmt.parseInt(u8, hex_str[2..3], 16) * 17;
        return RGB.init(r, g, b);
    } else if (hex_str.len == 6) {
        const r = try std.fmt.parseInt(u8, hex_str[0..2], 16);
        const g = try std.fmt.parseInt(u8, hex_str[2..4], 16);
        const b = try std.fmt.parseInt(u8, hex_str[4..6], 16);
        return RGB.init(r, g, b);
    }

    return error.InvalidHexColor;
}

pub fn parseRgb(str: []const u8) !RGB {
    // Parse "rgb(r,g,b)" or "r,g,b" format
    var clean = str;

    // Remove rgb() wrapper if present
    if (std.mem.startsWith(u8, clean, "rgb(") and std.mem.endsWith(u8, clean, ")")) {
        clean = clean[4 .. clean.len - 1];
    }

    // Split by comma
    var iter = std.mem.tokenize(u8, clean, ", ");

    const r_str = iter.next() orelse return error.InvalidColorFormat;
    const g_str = iter.next() orelse return error.InvalidColorFormat;
    const b_str = iter.next() orelse return error.InvalidColorFormat;

    const r = try std.fmt.parseInt(u8, r_str, 10);
    const g = try std.fmt.parseInt(u8, g_str, 10);
    const b = try std.fmt.parseInt(u8, b_str, 10);

    return RGB.init(r, g, b);
}

// === CONTRAST CALCULATIONS ===

/// Calculate relative luminance (for WCAG contrast ratio)
pub fn relativeLuminance(rgb: RGB) f32 {
    var r = @as(f32, @floatFromInt(rgb.r)) / 255.0;
    var g = @as(f32, @floatFromInt(rgb.g)) / 255.0;
    var b = @as(f32, @floatFromInt(rgb.b)) / 255.0;

    // Apply gamma correction
    if (r <= 0.03928) {
        r = r / 12.92;
    } else {
        r = std.math.pow(f32, (r + 0.055) / 1.055, 2.4);
    }

    if (g <= 0.03928) {
        g = g / 12.92;
    } else {
        g = std.math.pow(f32, (g + 0.055) / 1.055, 2.4);
    }

    if (b <= 0.03928) {
        b = b / 12.92;
    } else {
        b = std.math.pow(f32, (b + 0.055) / 1.055, 2.4);
    }

    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Calculate WCAG contrast ratio between two colors
pub fn contrastRatio(fg: RGB, bg: RGB) f32 {
    const l1 = relativeLuminance(fg);
    const l2 = relativeLuminance(bg);

    const lighter = @max(l1, l2);
    const darker = @min(l1, l2);

    return (lighter + 0.05) / (darker + 0.05);
}

/// Check if contrast meets WCAG AA standard (4.5:1 for normal text, 3:1 for large text)
pub fn meetsWcagAa(fg: RGB, bg: RGB, large_text: bool) bool {
    const ratio = contrastRatio(fg, bg);
    return if (large_text) ratio >= 3.0 else ratio >= 4.5;
}

/// Check if contrast meets WCAG AAA standard (7:1 for normal text, 4.5:1 for large text)
pub fn meetsWcagAaa(fg: RGB, bg: RGB, large_text: bool) bool {
    const ratio = contrastRatio(fg, bg);
    return if (large_text) ratio >= 4.5 else ratio >= 7.0;
}

// === TESTS ===

test "ANSI sequence generation" {
    const red = TerminalColor{ .ansi16 = .red };
    const seq_fg = toAnsiSequence(red, .foreground);
    try std.testing.expectEqualStrings("\x1b[31m", seq_fg);

    const seq_bg = toAnsiSequence(red, .background);
    try std.testing.expectEqualStrings("\x1b[41m", seq_bg);
}

test "AnsiBuilder" {
    const allocator = std.testing.allocator;
    var builder = AnsiBuilder.init(allocator);
    defer builder.deinit();

    try builder.setForeground(.{ .ansi16 = .red });
    try builder.bold();
    try builder.text("Hello");
    try builder.reset();

    const result = builder.build();
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result, "Hello") != null);
}

test "Color downgrade" {
    const rgb_color = TerminalColor{ .rgb = RGB.init(255, 128, 64) };

    // Downgrade to 256 colors
    const color256 = downgradeColor(rgb_color, .ansi256);
    try std.testing.expect(color256 == .ansi256);

    // Downgrade to 16 colors
    const color16 = downgradeColor(rgb_color, .ansi16);
    try std.testing.expect(color16 == .ansi16);

    // No color
    const no_color = downgradeColor(rgb_color, .no_color);
    try std.testing.expect(no_color == .default);
}

test "Hex color parsing" {
    const color1 = try parseHex("#FF8040");
    try std.testing.expectEqual(@as(u8, 255), color1.r);
    try std.testing.expectEqual(@as(u8, 128), color1.g);
    try std.testing.expectEqual(@as(u8, 64), color1.b);

    const color2 = try parseHex("FA0");
    try std.testing.expectEqual(@as(u8, 255), color2.r);
    try std.testing.expectEqual(@as(u8, 170), color2.g);
    try std.testing.expectEqual(@as(u8, 0), color2.b);
}

test "RGB color parsing" {
    const color1 = try parseRgb("rgb(255, 128, 64)");
    try std.testing.expectEqual(@as(u8, 255), color1.r);
    try std.testing.expectEqual(@as(u8, 128), color1.g);
    try std.testing.expectEqual(@as(u8, 64), color1.b);

    const color2 = try parseRgb("255,128,64");
    try std.testing.expectEqual(@as(u8, 255), color2.r);
    try std.testing.expectEqual(@as(u8, 128), color2.g);
    try std.testing.expectEqual(@as(u8, 64), color2.b);
}

test "WCAG contrast calculations" {
    const white = RGB.init(255, 255, 255);
    const black = RGB.init(0, 0, 0);

    const ratio = contrastRatio(white, black);
    try std.testing.expectApproxEqAbs(@as(f32, 21.0), ratio, 0.1);

    try std.testing.expect(meetsWcagAaa(white, black, false));
    try std.testing.expect(meetsWcagAaa(white, black, true));
}

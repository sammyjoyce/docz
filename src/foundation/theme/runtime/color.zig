//! Color Management System (theme/runtime)
//! Aligns theme colors with term.color union (.rgb/.ansi/.ansi256) and removes
//! dependence on local color_types. Provides metadata (name, alpha) and
//! utilities for contrast and transformations.

const std = @import("std");
const term = @import("../../term.zig");

pub const Rgb = struct { r: u8, g: u8, b: u8 };
pub const Hsl = struct { h: f32, s: f32, l: f32 };

/// Theme color with name/alpha metadata and standardized value
pub const Color = struct {
    name: []const u8,
    value: term.color.Color, // .rgb/.ansi/.ansi256/.default
    alpha: f32 = 1.0,

    const Self = @This();

    pub fn fromRgb(name: []const u8, r: u8, g: u8, b: u8, alpha: f32) Self {
        return .{ .name = name, .value = .{ .rgb = .{ .r = r, .g = g, .b = b } }, .alpha = alpha };
    }

    pub fn fromAnsi(name: []const u8, idx: u8, alpha: f32) Self {
        return .{ .name = name, .value = .{ .ansi = idx }, .alpha = alpha };
    }

    pub fn fromAnsi256(name: []const u8, idx: u8, alpha: f32) Self {
        return .{ .name = name, .value = .{ .ansi256 = idx }, .alpha = alpha };
    }

    pub fn fromHex(name: []const u8, hex: []const u8, alpha: f32) !Self {
        const rgb_col = try parseHexColor(hex);
        return fromRgb(name, rgb_col.r, rgb_col.g, rgb_col.b, alpha);
    }

    pub fn toHex(self: Self, allocator: std.mem.Allocator) ![]u8 {
        const rgb_col = self.rgb();
        return try std.fmt.allocPrint(allocator, "#{X:0>2}{X:0>2}{X:0>2}", .{ rgb_col.r, rgb_col.g, rgb_col.b });
    }

    pub fn rgb(self: Self) Rgb {
        return switch (self.value) {
            .rgb => |c| .{ .r = c.r, .g = c.g, .b = c.b },
            .ansi => |idx| ansi16ToRgb(idx),
            .ansi256 => |idx| ansi256ToRgb(idx),
            .default => .{ .r = 0, .g = 0, .b = 0 },
        };
    }

    pub fn ansi256(self: Self) u8 {
        return switch (self.value) {
            .ansi256 => |i| i,
            .ansi => |i| ansi16ToAnsi256(i),
            .rgb => |c| rgbToAnsi256(.{ .r = c.r, .g = c.g, .b = c.b }),
            .default => 0,
        };
    }

    pub fn ansi16(self: Self) u8 {
        return switch (self.value) {
            .ansi => |i| i,
            .ansi256 => |i| ansi256ToAnsi16(i),
            .rgb => |c| ansi256ToAnsi16(rgbToAnsi256(.{ .r = c.r, .g = c.g, .b = c.b })),
            .default => 0,
        };
    }

    pub fn luminance(self: Self) f32 {
        const c = self.rgb();
        const rf: f32 = gamma(@as(f32, @floatFromInt(c.r)) / 255.0);
        const gf: f32 = gamma(@as(f32, @floatFromInt(c.g)) / 255.0);
        const bf: f32 = gamma(@as(f32, @floatFromInt(c.b)) / 255.0);
        return 0.2126 * rf + 0.7152 * gf + 0.0722 * bf;
    }

    pub fn contrastRatio(self: Self, other: Self) f32 {
        const l1 = self.luminance();
        const l2 = other.luminance();
        const hi = @max(l1, l2);
        const lo = @min(l1, l2);
        return (hi + 0.05) / (lo + 0.05);
    }

    pub fn lighten(self: Self, factor: f32, allocator: std.mem.Allocator) !Self {
        const hsl = rgbToHsl(self.rgb());
        var nh = hsl;
        nh.l = @min(1.0, hsl.l * (1.0 + factor));
        const nrgb = hslToRgb(nh);
        const new_name = try std.fmt.allocPrint(allocator, "{s}_lighter", .{self.name});
        return fromRgb(new_name, nrgb.r, nrgb.g, nrgb.b, self.alpha);
    }

    pub fn darken(self: Self, factor: f32, allocator: std.mem.Allocator) !Self {
        const hsl = rgbToHsl(self.rgb());
        var nh = hsl;
        nh.l = @max(0.0, hsl.l * (1.0 - factor));
        const nrgb = hslToRgb(nh);
        const new_name = try std.fmt.allocPrint(allocator, "{s}_darker", .{self.name});
        return fromRgb(new_name, nrgb.r, nrgb.g, nrgb.b, self.alpha);
    }

    pub fn isDark(self: Self) bool {
        return self.luminance() < 0.5;
    }
    pub fn isLight(self: Self) bool {
        return self.luminance() >= 0.5;
    }
};

// --- Helpers -----------------------------------------------------------------

fn gamma(v: f32) f32 {
    if (v <= 0.03928) return v / 12.92;
    return std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

fn parseHexColor(s: []const u8) !Rgb {
    const hex = if (s.len > 0 and s[0] == '#') s[1..] else s;
    if (hex.len != 6) return error.InvalidHexLength;
    const r = try parseHexByte(hex[0..2]);
    const g = try parseHexByte(hex[2..4]);
    const b = try parseHexByte(hex[4..6]);
    return .{ .r = r, .g = g, .b = b };
}

fn parseHexNibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => error.InvalidHexDigit,
    };
}

fn parseHexByte(pair: []const u8) !u8 {
    if (pair.len != 2) return error.InvalidHexLength;
    const hi = try parseHexNibble(pair[0]);
    const lo = try parseHexNibble(pair[1]);
    return (hi << 4) | lo;
}

fn rgbToAnsi256(rgb: Rgb) u8 {
    const r = rgb.r;
    const g = rgb.g;
    const b = rgb.b;
    if (r == g and g == b) {
        if (r < 8) return 16;
        if (r > 248) return 231;
        const step: i32 = (@as(i32, r) - 8) / 10;
        const idx: i32 = 232 + step;
        return @as(u8, @intCast(idx));
    }
    const ri: u8 = @intCast(@min(5, @as(u8, @intFromFloat(@floor(@as(f32, @floatFromInt(r)) / 51.0)))));
    const gi: u8 = @intCast(@min(5, @as(u8, @intFromFloat(@floor(@as(f32, @floatFromInt(g)) / 51.0)))));
    const bi: u8 = @intCast(@min(5, @as(u8, @intFromFloat(@floor(@as(f32, @floatFromInt(b)) / 51.0)))));
    return @as(u8, 16 + 36 * ri + 6 * gi + bi);
}

fn ansi256ToAnsi16(idx256: u8) u8 {
    if (idx256 < 16) return idx256;
    if (idx256 >= 232) {
        const level = idx256 - 232;
        return if (level < 12) 0 else 15;
    }
    const i = idx256 - 16;
    const r = (i / 36) % 6;
    const g = (i / 6) % 6;
    const b = i % 6;
    const bright = (r + g + b) >= 9;
    const base: u8 = if (bright) 8 else 0;
    if (r >= g and r >= b) return base + 1;
    if (g >= r and g >= b) return base + 2;
    return base + 4;
}

fn ansi16ToAnsi256(idx: u8) u8 {
    // Map 16-color to the closest 256-color index
    return switch (idx) {
        0...15 => idx,
        else => 0,
    };
}

fn ansi256ToRgb(idx: u8) Rgb {
    if (idx < 16) return ansi16ToRgb(idx);
    if (idx >= 232) {
        const level = 8 + 10 * (idx - 232);
        return .{ .r = level, .g = level, .b = level };
    }
    const i = idx - 16;
    const r = 51 * ((i / 36) % 6);
    const g = 51 * ((i / 6) % 6);
    const b = 51 * (i % 6);
    return .{ .r = @intCast(r), .g = @intCast(g), .b = @intCast(b) };
}

fn ansi16ToRgb(idx: u8) Rgb {
    const table = [_]Rgb{
        .{ .r = 0, .g = 0, .b = 0 },       // 0 black
        .{ .r = 205, .g = 0, .b = 0 },     // 1 red
        .{ .r = 0, .g = 205, .b = 0 },     // 2 green
        .{ .r = 205, .g = 205, .b = 0 },   // 3 yellow
        .{ .r = 0, .g = 0, .b = 238 },     // 4 blue
        .{ .r = 205, .g = 0, .b = 205 },   // 5 magenta
        .{ .r = 0, .g = 205, .b = 205 },   // 6 cyan
        .{ .r = 229, .g = 229, .b = 229 }, // 7 white
        .{ .r = 127, .g = 127, .b = 127 }, // 8 bright black
        .{ .r = 255, .g = 0, .b = 0 },     // 9 bright red
        .{ .r = 0, .g = 255, .b = 0 },     // 10 bright green
        .{ .r = 255, .g = 255, .b = 0 },   // 11 bright yellow
        .{ .r = 92, .g = 92, .b = 255 },   // 12 bright blue
        .{ .r = 255, .g = 0, .b = 255 },   // 13 bright magenta
        .{ .r = 0, .g = 255, .b = 255 },   // 14 bright cyan
        .{ .r = 255, .g = 255, .b = 255 }, // 15 bright white
    };
    return if (idx < table.len) table[idx] else table[0];
}

fn rgbToHsl(c: Rgb) Hsl {
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

fn hslToRgb(hsl: Hsl) Rgb {
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
        rf = c; gf = x; bf = 0.0;
    } else if (hprime < 2.0) {
        rf = x; gf = c; bf = 0.0;
    } else if (hprime < 3.0) {
        rf = 0.0; gf = c; bf = x;
    } else if (hprime < 4.0) {
        rf = 0.0; gf = x; bf = c;
    } else if (hprime < 5.0) {
        rf = x; gf = 0.0; bf = c;
    } else {
        rf = c; gf = 0.0; bf = x;
    }
    const m = hsl.l - c / 2.0;
    const r = @as(u8, @intFromFloat(@round((rf + m) * 255.0)));
    const g = @as(u8, @intFromFloat(@round((gf + m) * 255.0)));
    const b = @as(u8, @intFromFloat(@round((bf + m) * 255.0)));
    return .{ .r = r, .g = g, .b = b };
}

// --- Predefined --------------------------------------------------------------

pub const Colors = struct {
    pub const BLACK = Color.fromRgb("black", 0, 0, 0, 1.0);
    pub const WHITE = Color.fromRgb("white", 255, 255, 255, 1.0);
    pub const RED = Color.fromRgb("red", 255, 0, 0, 1.0);
    pub const GREEN = Color.fromRgb("green", 0, 255, 0, 1.0);
    pub const BLUE = Color.fromRgb("blue", 0, 0, 255, 1.0);
    pub const YELLOW = Color.fromRgb("yellow", 255, 255, 0, 1.0);
    pub const MAGENTA = Color.fromRgb("magenta", 255, 0, 255, 1.0);
    pub const CYAN = Color.fromRgb("cyan", 0, 255, 255, 1.0);

    pub const BRIGHT_BLACK = Color.fromRgb("bright_black", 128, 128, 128, 1.0);
    pub const BRIGHT_RED = Color.fromRgb("bright_red", 255, 128, 128, 1.0);
    pub const BRIGHT_GREEN = Color.fromRgb("bright_green", 128, 255, 128, 1.0);
    pub const BRIGHT_BLUE = Color.fromRgb("bright_blue", 128, 128, 255, 1.0);
    pub const BRIGHT_YELLOW = Color.fromRgb("bright_yellow", 255, 255, 128, 1.0);
    pub const BRIGHT_MAGENTA = Color.fromRgb("bright_magenta", 255, 128, 255, 1.0);
    pub const BRIGHT_CYAN = Color.fromRgb("bright_cyan", 128, 255, 255, 1.0);
    pub const BRIGHT_WHITE = Color.fromRgb("bright_white", 255, 255, 255, 1.0);
};

// --- Tests -------------------------------------------------------------------

test "color creation and conversion" {
    const testing = std.testing;
    const red = Color.fromRgb("red", 255, 0, 0, 1.0);
    try testing.expect(red.rgb().r == 255);
    const lighter = try red.lighten(0.2, testing.allocator);
    try testing.expect(lighter.rgb().r >= red.rgb().r);
}

test "color accessibility" {
    const testing = std.testing;
    const black = Color.fromRgb("black", 0, 0, 0, 1.0);
    const white = Color.fromRgb("white", 255, 255, 255, 1.0);
    const contrast = black.contrastRatio(white);
    try testing.expect(contrast > 10.0);
}

//! Basic color primitives for the theme runtime.
//! Defines RGB/HSL types and conversions with a minimal, self-contained API.

const std = @import("std");

/// 24-bit RGB color
pub const RGB = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RGB {
        return .{ .r = r, .g = g, .b = b };
    }

    /// Convert to HSL (range: h in [0,360), s,l in [0,1])
    pub fn toHSL(self: RGB) HSL {
        const rf: f32 = @as(f32, @floatFromInt(self.r)) / 255.0;
        const gf: f32 = @as(f32, @floatFromInt(self.g)) / 255.0;
        const bf: f32 = @as(f32, @floatFromInt(self.b)) / 255.0;

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
};

/// Hue-Saturation-Lightness
pub const HSL = struct {
    h: f32, // [0,360)
    s: f32, // [0,1]
    l: f32, // [0,1]

    pub fn init(h: f32, s: f32, l: f32) HSL {
        var hh = h;
        // Normalize hue to [0,360)
        while (hh < 0.0) hh += 360.0;
        while (hh >= 360.0) hh -= 360.0;
        return .{ .h = hh, .s = @max(0.0, @min(1.0, s)), .l = @max(0.0, @min(1.0, l)) };
    }

    pub fn toRGB(self: HSL) RGB {
        if (self.s == 0.0) {
            const v = @as(u8, @intFromFloat(@round(self.l * 255.0)));
            return .{ .r = v, .g = v, .b = v };
        }

        const c = (1.0 - @abs(2.0 * self.l - 1.0)) * self.s;
        const hprime = self.h / 60.0;
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

        const m = self.l - c / 2.0;
        const r = @as(u8, @intFromFloat(@round((rf + m) * 255.0)));
        const g = @as(u8, @intFromFloat(@round((gf + m) * 255.0)));
        const b = @as(u8, @intFromFloat(@round((bf + m) * 255.0)));
        return .{ .r = r, .g = g, .b = b };
    }
};

/// Parse 6-hex digits (with optional leading '#') into RGB
pub fn parseHexColor(s: []const u8) !RGB {
    const hex = if (s.len > 0 and (s[0] == '#' or s[0] == '0'))
        s[(if (s[0] == '#') 1 else 0)..]
    else
        s;
    if (hex.len != 6) return error.InvalidHexLength;

    const r = try parseHexByte(hex[0..2]);
    const g = try parseHexByte(hex[2..4]);
    const b = try parseHexByte(hex[4..6]);
    return RGB.init(r, g, b);
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

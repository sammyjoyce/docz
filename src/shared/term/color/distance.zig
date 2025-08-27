//! Color Distance Algorithms
//! Various methods for calculating perceptual color distance
//! Used for finding closest matching colors in palettes

const std = @import("std");
const types = @import("types.zig");
const conversions = @import("conversions.zig");

pub const RGB = types.RGB;
pub const Lab = types.Lab;
pub const HSL = types.HSL;

// === DISTANCE ALGORITHMS ===

/// Simple Euclidean distance in RGB space (fast but not perceptually accurate)
pub fn rgbEuclidean(a: RGB, b: RGB) f32 {
    const dr = @as(f32, @floatFromInt(@as(i16, a.r) - @as(i16, b.r)));
    const dg = @as(f32, @floatFromInt(@as(i16, a.g) - @as(i16, b.g)));
    const db = @as(f32, @floatFromInt(@as(i16, a.b) - @as(i16, b.b)));
    return @sqrt(dr * dr + dg * dg + db * db);
}

/// Weighted RGB distance (better perceptual accuracy)
pub fn rgbWeighted(a: RGB, b: RGB) f32 {
    const r_mean = (@as(f32, @floatFromInt(a.r)) + @as(f32, @floatFromInt(b.r))) / 2.0;
    const dr = @as(f32, @floatFromInt(@as(i16, a.r) - @as(i16, b.r)));
    const dg = @as(f32, @floatFromInt(@as(i16, a.g) - @as(i16, b.g)));
    const db = @as(f32, @floatFromInt(@as(i16, a.b) - @as(i16, b.b)));

    const weight_r = 2.0 + r_mean / 256.0;
    const weight_g = 4.0;
    const weight_b = 2.0 + (255.0 - r_mean) / 256.0;

    return @sqrt(weight_r * dr * dr + weight_g * dg * dg + weight_b * db * db);
}

/// CIE76 Delta E distance in Lab color space (good perceptual accuracy)
pub fn deltaE76(a: Lab, b: Lab) f32 {
    const dl = a.l - b.l;
    const da = a.a - b.a;
    const db = a.b - b.b;
    return @sqrt(dl * dl + da * da + db * db);
}

/// CIE94 Delta E distance (improved perceptual accuracy)
pub fn deltaE94(lab1: Lab, lab2: Lab) f32 {
    const kL: f32 = 1.0; // Lightness weight
    const kC: f32 = 1.0; // Chroma weight
    const kH: f32 = 1.0; // Hue weight
    const k1: f32 = 0.045; // Graphics arts constant
    const k2: f32 = 0.015; // Graphics arts constant

    const dl = lab1.l - lab2.l;
    const da = lab1.a - lab2.a;
    const db = lab1.b - lab2.b;

    const c1 = @sqrt(lab1.a * lab1.a + lab1.b * lab1.b);
    const c2 = @sqrt(lab2.a * lab2.a + lab2.b * lab2.b);
    const dc = c1 - c2;

    const dh_sq = da * da + db * db - dc * dc;
    const dh = if (dh_sq > 0) @sqrt(dh_sq) else 0;

    const sl = 1.0;
    const sc = 1.0 + k1 * c1;
    const sh = 1.0 + k2 * c1;

    const dl_scaled = dl / (kL * sl);
    const dc_scaled = dc / (kC * sc);
    const dh_scaled = dh / (kH * sh);

    return @sqrt(dl_scaled * dl_scaled + dc_scaled * dc_scaled + dh_scaled * dh_scaled);
}

/// CIE2000 Delta E distance (best perceptual accuracy, most complex)
pub fn deltaE2000(lab1: Lab, lab2: Lab) f32 {
    const kL: f32 = 1.0;
    const kC: f32 = 1.0;
    const kH: f32 = 1.0;

    // Calculate a' (adjusted a*)
    const c1_star = @sqrt(lab1.a * lab1.a + lab1.b * lab1.b);
    const c2_star = @sqrt(lab2.a * lab2.a + lab2.b * lab2.b);
    const c_bar_star = (c1_star + c2_star) / 2.0;

    const c_bar_star_7 = std.math.pow(f32, c_bar_star, 7);
    const g = 0.5 * (1.0 - @sqrt(c_bar_star_7 / (c_bar_star_7 + std.math.pow(f32, 25, 7))));

    const a1_prime = lab1.a * (1.0 + g);
    const a2_prime = lab2.a * (1.0 + g);

    // Calculate C' and h'
    const c1_prime = @sqrt(a1_prime * a1_prime + lab1.b * lab1.b);
    const c2_prime = @sqrt(a2_prime * a2_prime + lab2.b * lab2.b);

    const h1_prime = if (c1_prime == 0) 0 else std.math.atan2(f32, lab1.b, a1_prime) * 180.0 / std.math.pi;
    const h2_prime = if (c2_prime == 0) 0 else std.math.atan2(f32, lab2.b, a2_prime) * 180.0 / std.math.pi;

    // Calculate deltas
    const dl_prime = lab2.l - lab1.l;
    const dc_prime = c2_prime - c1_prime;

    var dh_prime = h2_prime - h1_prime;
    if (dh_prime > 180.0) dh_prime -= 360.0;
    if (dh_prime < -180.0) dh_prime += 360.0;

    const dH_prime = 2.0 * @sqrt(c1_prime * c2_prime) * @sin(dh_prime * std.math.pi / 360.0);

    // Calculate averages
    const l_bar_prime = (lab1.l + lab2.l) / 2.0;
    const c_bar_prime = (c1_prime + c2_prime) / 2.0;

    var h_bar_prime = (h1_prime + h2_prime) / 2.0;
    if (@abs(h1_prime - h2_prime) > 180.0) {
        if (h_bar_prime < 180.0) {
            h_bar_prime += 180.0;
        } else {
            h_bar_prime -= 180.0;
        }
    }

    // Calculate T
    const t = 1.0 - 0.17 * @cos((h_bar_prime - 30.0) * std.math.pi / 180.0) +
        0.24 * @cos(2.0 * h_bar_prime * std.math.pi / 180.0) +
        0.32 * @cos((3.0 * h_bar_prime + 6.0) * std.math.pi / 180.0) -
        0.20 * @cos((4.0 * h_bar_prime - 63.0) * std.math.pi / 180.0);

    // Calculate RT (rotation term)
    const delta_theta = 30.0 * @exp(-std.math.pow(f32, (h_bar_prime - 275.0) / 25.0, 2));
    const c_bar_prime_7 = std.math.pow(f32, c_bar_prime, 7);
    const rc = 2.0 * @sqrt(c_bar_prime_7 / (c_bar_prime_7 + std.math.pow(f32, 25, 7)));
    const rt = -@sin(2.0 * delta_theta * std.math.pi / 180.0) * rc;

    // Calculate SL, SC, SH
    const sl = 1.0 + (0.015 * std.math.pow(f32, l_bar_prime - 50.0, 2)) /
        @sqrt(20.0 + std.math.pow(f32, l_bar_prime - 50.0, 2));
    const sc = 1.0 + 0.045 * c_bar_prime;
    const sh = 1.0 + 0.015 * c_bar_prime * t;

    // Final calculation
    const dl_scaled = dl_prime / (kL * sl);
    const dc_scaled = dc_prime / (kC * sc);
    const dh_scaled = dH_prime / (kH * sh);

    const de = @sqrt(
        dl_scaled * dl_scaled +
            dc_scaled * dc_scaled +
            dh_scaled * dh_scaled +
            rt * dc_scaled * dh_scaled,
    );

    return de;
}

/// HSL-based color distance (good for hue-sensitive comparisons)
pub fn hslDistance(a: HSL, b: HSL) f32 {
    // Normalize hue difference to -180 to 180
    var dh = a.h - b.h;
    if (dh > 180.0) dh -= 360.0;
    if (dh < -180.0) dh += 360.0;
    dh = dh / 180.0; // Normalize to -1 to 1

    const ds = (a.s - b.s) / 100.0; // Normalize to -1 to 1
    const dl = (a.l - b.l) / 100.0; // Normalize to -1 to 1

    // Weight hue more when colors are more saturated
    const avg_saturation = (a.s + b.s) / 200.0;
    const hue_weight = avg_saturation;

    return @sqrt(
        hue_weight * dh * dh +
            ds * ds +
            dl * dl * 2.0, // Weight lightness more heavily
    );
}

// === PALETTE MATCHING ===

/// Find the closest color in a palette using the specified distance algorithm
pub const DistanceAlgorithm = enum {
    rgb_euclidean,
    rgb_weighted,
    delta_e76,
    delta_e94,
    delta_e2000,
    hsl,
};

pub fn findClosestColor(
    target: RGB,
    palette: []const RGB,
    algorithm: DistanceAlgorithm,
) struct { color: RGB, index: usize, distance: f32 } {
    if (palette.len == 0) {
        return .{ .color = target, .index = 0, .distance = 0 };
    }

    var best_color = palette[0];
    var best_index: usize = 0;
    var best_distance: f32 = std.math.inf(f32);

    for (palette, 0..) |color, i| {
        const distance = switch (algorithm) {
            .rgb_euclidean => rgbEuclidean(target, color),
            .rgb_weighted => rgbWeighted(target, color),
            .delta_e76 => blk: {
                const lab1 = conversions.rgbToLab(target);
                const lab2 = conversions.rgbToLab(color);
                break :blk deltaE76(lab1, lab2);
            },
            .delta_e94 => blk: {
                const lab1 = conversions.rgbToLab(target);
                const lab2 = conversions.rgbToLab(color);
                break :blk deltaE94(lab1, lab2);
            },
            .delta_e2000 => blk: {
                const lab1 = conversions.rgbToLab(target);
                const lab2 = conversions.rgbToLab(color);
                break :blk deltaE2000(lab1, lab2);
            },
            .hsl => blk: {
                const hsl1 = conversions.rgbToHsl(target);
                const hsl2 = conversions.rgbToHsl(color);
                break :blk hslDistance(hsl1, hsl2);
            },
        };

        if (distance < best_distance) {
            best_distance = distance;
            best_color = color;
            best_index = i;
        }
    }

    return .{ .color = best_color, .index = best_index, .distance = best_distance };
}

/// Check if two colors are perceptually similar
pub fn areColorsSimilar(a: RGB, b: RGB, threshold: f32) bool {
    const lab1 = conversions.rgbToLab(a);
    const lab2 = conversions.rgbToLab(b);
    return deltaE2000(lab1, lab2) < threshold;
}

// === TESTS ===

test "RGB distance calculations" {
    const black = RGB.init(0, 0, 0);
    const white = RGB.init(255, 255, 255);
    const red = RGB.init(255, 0, 0);
    const green = RGB.init(0, 255, 0);

    // Euclidean distance
    const dist_bw = rgbEuclidean(black, white);
    try std.testing.expectApproxEqAbs(@as(f32, 441.67), dist_bw, 0.1);

    // Same color should have distance 0
    const dist_same = rgbEuclidean(red, red);
    try std.testing.expectEqual(@as(f32, 0), dist_same);

    // Weighted distance should be different
    const dist_weighted = rgbWeighted(red, green);
    try std.testing.expect(dist_weighted > 0);
}

test "Lab distance calculations" {
    const red = RGB.init(255, 0, 0);
    const orange = RGB.init(255, 128, 0);

    const lab_red = conversions.rgbToLab(red);
    const lab_orange = conversions.rgbToLab(orange);

    const de76 = deltaE76(lab_red, lab_orange);
    const de94 = deltaE94(lab_red, lab_orange);
    const de2000 = deltaE2000(lab_red, lab_orange);

    // All should give positive distances
    try std.testing.expect(de76 > 0);
    try std.testing.expect(de94 > 0);
    try std.testing.expect(de2000 > 0);

    // DE2000 typically gives smaller values than DE76
    try std.testing.expect(de2000 < de76);
}

test "Find closest color in palette" {
    const palette = [_]RGB{
        RGB.init(255, 0, 0), // Red
        RGB.init(0, 255, 0), // Green
        RGB.init(0, 0, 255), // Blue
        RGB.init(255, 255, 0), // Yellow
        RGB.init(255, 0, 255), // Magenta
        RGB.init(0, 255, 255), // Cyan
    };

    const orange = RGB.init(255, 128, 0);
    const result = findClosestColor(orange, &palette, .rgb_weighted);

    // Orange should be closest to red or yellow
    try std.testing.expect(result.index == 0 or result.index == 3);
}

test "Color similarity check" {
    const color1 = RGB.init(255, 0, 0);
    const color2 = RGB.init(254, 1, 0); // Very close to color1
    const color3 = RGB.init(0, 255, 0); // Very different

    try std.testing.expect(areColorsSimilar(color1, color2, 5.0));
    try std.testing.expect(!areColorsSimilar(color1, color3, 5.0));
}

//! Color Management System
//! Implements color conversion and management techniques
//! Provides perceptual color matching and palette optimization

const std = @import("std");
const color_palette = @import("color_palette.zig");

/// Color Manager with HSLuv-based algorithms
/// Provides color conversion and palette management
pub const Color = struct {
    allocator: std.mem.Allocator,
    palette: color_palette.ANSI256Palette,
    color_cache: std.AutoHashMap(color_palette.RGBColor, color_palette.TerminalColor),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .palette = color_palette.ANSI256Palette.init(),
            .color_cache = std.AutoHashMap(color_palette.RGBColor, color_palette.TerminalColor).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.color_cache.deinit();
    }

    /// Convert color using HSLuv-based algorithm with caching
    pub fn convertColorCached(self: *Self, color: color_palette.RGBColor) !color_palette.TerminalColor {
        // Check cache first
        if (self.color_cache.get(color)) |cached| {
            return cached;
        }

        // Convert using algorithm
        const converted = color_palette.TerminalColor{ .ansi256 = self.palette.convertTo256Enhanced(color) };

        // Cache the result
        try self.color_cache.put(color, converted);

        return converted;
    }

    /// Generate an optimized color palette from a set of colors
    /// Uses HSLuv-based clustering for better perceptual grouping
    pub fn generateOptimizedPalette(
        self: *Self,
        colors: []const color_palette.RGBColor,
        target_size: u8,
    ) ![]color_palette.RGBColor {
        if (target_size == 0 or colors.len == 0) {
            return try self.allocator.alloc(color_palette.RGBColor, 0);
        }

        // Convert all colors to HSLuv for better perceptual clustering
        var hsluv_colors = std.ArrayList(color_palette.HSLuvColor).init(self.allocator);
        defer hsluv_colors.deinit();

        for (colors) |color| {
            try hsluv_colors.append(color.toHSLuv());
        }

        // Simple clustering algorithm based on HSLuv distance
        var centroids = std.ArrayList(color_palette.HSLuvColor).init(self.allocator);
        defer centroids.deinit();

        // Initialize centroids using furthest point clustering
        try centroids.append(hsluv_colors.items[0]);

        for (1..target_size) |_| {
            var max_distance: f64 = 0;
            var best_candidate = hsluv_colors.items[0];

            for (hsluv_colors.items) |candidate| {
                var min_distance: f64 = std.math.inf(f64);

                for (centroids.items) |centroid| {
                    const distance = candidate.distance(centroid);
                    if (distance < min_distance) {
                        min_distance = distance;
                    }
                }

                if (min_distance > max_distance) {
                    max_distance = min_distance;
                    best_candidate = candidate;
                }
            }

            try centroids.append(best_candidate);
        }

        // Convert centroids back to RGB
        var result = std.ArrayList(color_palette.RGBColor).init(self.allocator);
        errdefer result.deinit();

        for (centroids.items) |centroid| {
            // Convert HSLuv back to RGB (simplified conversion)
            const rgb = centroid.toRGB();
            try result.append(rgb);
        }

        return result.toOwnedSlice();
    }

    /// Find the best color match from a custom palette
    pub fn findBestMatchInPalette(
        self: *Self,
        target: color_palette.RGBColor,
        custom_palette: []const color_palette.RGBColor,
    ) ?color_palette.RGBColor {
        _ = self;
        if (custom_palette.len == 0) return null;

        var best_match = custom_palette[0];
        var best_distance: f64 = std.math.inf(f64);

        const target_hsluv = target.toHSLuv();

        for (custom_palette) |candidate| {
            const candidate_hsluv = candidate.toHSLuv();
            const distance = target_hsluv.distance(candidate_hsluv);

            if (distance < best_distance) {
                best_distance = distance;
                best_match = candidate;
            }
        }

        return best_match;
    }

    /// Analyze color distribution and provide color statistics
    pub fn analyzeColorDistribution(
        self: *Self,
        colors: []const color_palette.RGBColor,
    ) !ColorDistributionAnalysis {
        if (colors.len == 0) {
            return ColorDistributionAnalysis{
                .total_colors = 0,
                .unique_colors = 0,
                .most_saturated = null,
                .least_saturated = null,
                .brightest = null,
                .darkest = null,
                .average_hsluv = null,
            };
        }

        var unique_colors = std.AutoHashMap(color_palette.RGBColor, void).init(self.allocator);
        defer unique_colors.deinit();

        var total_h: f64 = 0;
        var total_s: f64 = 0;
        var total_l: f64 = 0;
        var count: f64 = 0;

        var most_saturated: ?color_palette.RGBColor = null;
        var least_saturated: ?color_palette.RGBColor = null;
        var brightest: ?color_palette.RGBColor = null;
        var darkest: ?color_palette.RGBColor = null;

        var max_saturation: f64 = -1;
        var min_saturation: f64 = std.math.inf(f64);
        var max_lightness: f64 = -1;
        var min_lightness: f64 = std.math.inf(f64);

        for (colors) |color| {
            try unique_colors.put(color, {});

            const hsluv = color.toHSLuv();
            total_h += hsluv.h;
            total_s += hsluv.s;
            total_l += hsluv.l;
            count += 1;

            if (hsluv.s > max_saturation) {
                max_saturation = hsluv.s;
                most_saturated = color;
            }

            if (hsluv.s < min_saturation) {
                min_saturation = hsluv.s;
                least_saturated = color;
            }

            if (hsluv.l > max_lightness) {
                max_lightness = hsluv.l;
                brightest = color;
            }

            if (hsluv.l < min_lightness) {
                min_lightness = hsluv.l;
                darkest = color;
            }
        }

        const average_hsluv = if (count > 0) color_palette.HSLuvColor{
            .h = total_h / count,
            .s = total_s / count,
            .l = total_l / count,
        } else null;

        return ColorDistributionAnalysis{
            .total_colors = colors.len,
            .unique_colors = unique_colors.count(),
            .most_saturated = most_saturated,
            .least_saturated = least_saturated,
            .brightest = brightest,
            .darkest = darkest,
            .average_hsluv = average_hsluv,
        };
    }
};

/// Color distribution analysis results
pub const ColorDistributionAnalysis = struct {
    total_colors: usize,
    unique_colors: usize,
    most_saturated: ?color_palette.RGBColor,
    least_saturated: ?color_palette.RGBColor,
    brightest: ?color_palette.RGBColor,
    darkest: ?color_palette.RGBColor,
    average_hsluv: ?color_palette.HSLuvColor,
};

/// Helper function to convert HSLuv back to RGB (simplified)
fn hsluvToRGB(hsluv: anytype) color_palette.RGBColor {
    // This is a simplified conversion - in practice you'd want a full HSLuv implementation
    // For now, we'll use the existing HSL to RGB conversion as an approximation
    const hsl = color_palette.HSLColor{
        .h = @floatCast(hsluv.h),
        .s = @floatCast(hsluv.s),
        .l = @floatCast(hsluv.l),
    };
    return hsl.toRGB();
}

// Tests for enhanced color management
test "color conversion caching" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var manager = Color.init(allocator);
    defer manager.deinit();

    const red = color_palette.RGBColor{ .r = 255, .g = 0, .b = 0 };

    // First conversion
    const result1 = try manager.convertColorCached(red);
    try testing.expect(result1.ansi256 >= 0 and result1.ansi256 <= 255);

    // Second conversion should use cache
    const result2 = try manager.convertColorCached(red);
    try testing.expect(result1.ansi256 == result2.ansi256);
}

test "color distribution analysis" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var manager = Color.init(allocator);
    defer manager.deinit();

    const colors = [_]color_palette.RGBColor{
        color_palette.RGBColor{ .r = 255, .g = 0, .b = 0 }, // Red
        color_palette.RGBColor{ .r = 0, .g = 255, .b = 0 }, // Green
        color_palette.RGBColor{ .r = 0, .g = 0, .b = 255 }, // Blue
        color_palette.RGBColor{ .r = 255, .g = 0, .b = 0 }, // Red (duplicate)
    };

    const analysis = try manager.analyzeColorDistribution(&colors);

    try testing.expect(analysis.total_colors == 4);
    try testing.expect(analysis.unique_colors == 3);
    try testing.expect(analysis.most_saturated != null);
    try testing.expect(analysis.average_hsluv != null);
}

test "palette optimization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var manager = Color.init(allocator);
    defer manager.deinit();

    const colors = [_]color_palette.RGBColor{
        color_palette.RGBColor{ .r = 255, .g = 0, .b = 0 },
        color_palette.RGBColor{ .r = 255, .g = 10, .b = 10 },
        color_palette.RGBColor{ .r = 255, .g = 20, .b = 20 },
        color_palette.RGBColor{ .r = 0, .g = 255, .b = 0 },
        color_palette.RGBColor{ .r = 10, .g = 255, .b = 10 },
        color_palette.RGBColor{ .r = 20, .g = 255, .b = 20 },
    };

    const optimized = try manager.generateOptimizedPalette(&colors, 2);
    defer allocator.free(optimized);

    try testing.expect(optimized.len == 2);
}

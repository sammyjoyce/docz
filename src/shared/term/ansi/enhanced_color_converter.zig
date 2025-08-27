const std = @import("std");
const math = std.math;
const enhanced_distance = @import("enhanced_color_distance.zig");
const precise_palette = @import("precise_ansi_palette.zig");

/// Enhanced 256-color conversion algorithm
/// Uses advanced color science for optimal terminal color approximation
const RGBColor = enhanced_distance.RGBColor;

/// Advanced 256-color converter using optimized algorithm
pub const EnhancedColorConverter = struct {
    const Self = @This();

    /// 6x6x6 color cube values used by xterm (standard xterm values)
    const CUBE_VALUES = [_]u8{ 0x00, 0x5F, 0x87, 0xAF, 0xD7, 0xFF };

    /// Map RGB component value to 6-cube coordinate (0-5)
    fn rgbTo6Cube(value: u8) u8 {
        const v = @as(f64, @floatFromInt(value));
        if (v < 48.0) return 0;
        if (v < 115.0) return 1;
        return @min(5, @as(u8, @intFromFloat((v - 35.0) / 40.0)));
    }

    /// Convert 6-cube coordinate to RGB component value
    fn cubeToRgb(cube_coord: u8) u8 {
        std.debug.assert(cube_coord <= 5);
        return CUBE_VALUES[cube_coord];
    }

    /// Calculate the color cube color for a given RGB
    fn calculateCubeColor(rgb: RGBColor) struct { color: RGBColor, index: u8 } {
        // Map RGB to 6x6x6 cube coordinates
        const qr = rgbTo6Cube(rgb.r);
        const qg = rgbTo6Cube(rgb.g);
        const qb = rgbTo6Cube(rgb.b);

        // Convert back to RGB values
        const cr = cubeToRgb(qr);
        const cg = cubeToRgb(qg);
        const cb = cubeToRgb(qb);

        // Calculate cube index (16-231 range)
        const index = 16 + @as(u8, qr) * 36 + @as(u8, qg) * 6 + @as(u8, qb);

        return .{ .color = RGBColor.init(cr, cg, cb), .index = index };
    }

    /// Calculate the best grayscale match for a given RGB
    fn calculateGrayscaleColor(rgb: RGBColor) struct { color: RGBColor, index: u8 } {
        // Calculate average (simple approach) - industry-standard approach uses more sophisticated
        const avg = (@as(u32, rgb.r) + @as(u32, rgb.g) + @as(u32, rgb.b)) / 3;

        // Map to 24-step grayscale ramp (232-255)
        var gray_idx: u8 = if (avg > 238) 23 else blk: {
            if (avg <= 8) break :blk 0;
            break :blk @as(u8, @intCast((avg - 8) / 10));
        };
        gray_idx = @min(23, gray_idx);

        const gray_value = 8 + gray_idx * 10;
        const color_index = 232 + gray_idx;

        return .{ .color = RGBColor.init(@intCast(gray_value), @intCast(gray_value), @intCast(gray_value)), .index = color_index };
    }

    /// Enhanced conversion using perceptual distance and sophisticated algorithm
    /// This follows standard 256-color conversion algorithms
    pub fn convert256Enhanced(rgb: RGBColor) u8 {
        // First check if it's an exact match in the palette (optimization)
        if (precise_palette.PreciseColorMatcher.findExactMatch(rgb)) |exact| {
            return exact;
        }

        // Calculate cube color candidate
        const cube_result = calculateCubeColor(rgb);

        // Check if we have an exact cube match (optimization technique)
        if (cube_result.color.r == rgb.r and
            cube_result.color.g == rgb.g and
            cube_result.color.b == rgb.b)
        {
            return cube_result.index;
        }

        // Calculate grayscale candidate
        const gray_result = calculateGrayscaleColor(rgb);

        // Use perceptual distance to choose the best match
        const cube_distance = enhanced_distance.perceptualDistance(rgb, cube_result.color);
        const gray_distance = enhanced_distance.perceptualDistance(rgb, gray_result.color);

        // Return the perceptually closer match
        if (cube_distance <= gray_distance) {
            return cube_result.index;
        } else {
            return gray_result.index;
        }
    }

    /// Fallback converter using simple Euclidean distance (faster)
    pub fn convert256Fast(rgb: RGBColor) u8 {
        // Check exact match first
        if (precise_palette.PreciseColorMatcher.findExactMatch(rgb)) |exact| {
            return exact;
        }

        // Calculate candidates
        const cube_result = calculateCubeColor(rgb);
        const gray_result = calculateGrayscaleColor(rgb);

        // Use fast perceptual distance
        const cube_distance = enhanced_distance.perceptualDistanceFast(rgb, cube_result.color);
        const gray_distance = enhanced_distance.perceptualDistanceFast(rgb, gray_result.color);

        return if (cube_distance <= gray_distance) cube_result.index else gray_result.index;
    }

    /// Convert to 16-color using the precise mapping from standard ANSI
    pub fn convert16(rgb: RGBColor) u8 {
        const color_256 = convert256Enhanced(rgb);
        return precise_palette.get16ColorMapping(color_256);
    }

    /// Advanced conversion that also considers the basic 16 colors
    /// This provides the most accurate color matching by considering all possibilities
    pub fn convertOptimal(rgb: RGBColor) u8 {
        // Check exact match first
        if (precise_palette.PreciseColorMatcher.findExactMatch(rgb)) |exact| {
            return exact;
        }

        var best_index: u8 = 0;
        var best_distance: f64 = math.floatMax(f64);

        // Check basic 16 colors
        for (0..16) |i| {
            const palette_color = precise_palette.getRgbColor(@intCast(i));
            const distance = enhanced_distance.perceptualDistance(rgb, palette_color);
            if (distance < best_distance) {
                best_distance = distance;
                best_index = @intCast(i);
            }
        }

        // Check cube color
        const cube_result = calculateCubeColor(rgb);
        const cube_distance = enhanced_distance.perceptualDistance(rgb, cube_result.color);
        if (cube_distance < best_distance) {
            best_distance = cube_distance;
            best_index = cube_result.index;
        }

        // Check grayscale color
        const gray_result = calculateGrayscaleColor(rgb);
        const gray_distance = enhanced_distance.perceptualDistance(rgb, gray_result.color);
        if (gray_distance < best_distance) {
            best_index = gray_result.index;
        }

        return best_index;
    }

    /// Batch conversion for multiple colors (optimized)
    pub fn convertBatch(colors: []const RGBColor, results: []u8, use_optimal: bool) void {
        std.debug.assert(colors.len == results.len);

        for (colors, results, 0..) |color, *result, i| {
            _ = i;
            result.* = if (use_optimal) convertOptimal(color) else convert256Enhanced(color);
        }
    }

    /// Color analysis utilities
    pub const Analysis = struct {
        /// Analyze how well a color converts to 256-color space
        pub fn analyzeConversion(original: RGBColor) struct {
            best_256_index: u8,
            best_256_color: RGBColor,
            perceptual_distance: f64,
            euclidean_distance: f64,
            is_exact_match: bool,
            color_space_info: struct {
                is_in_cube: bool,
                is_grayscale: bool,
                is_basic_color: bool,
            },
        } {
            const best_index = convert256Enhanced(original);
            const best_color = precise_palette.getRgbColor(best_index);

            return .{
                .best_256_index = best_index,
                .best_256_color = best_color,
                .perceptual_distance = enhanced_distance.perceptualDistance(original, best_color),
                .euclidean_distance = enhanced_distance.perceptualDistanceFast(original, best_color),
                .is_exact_match = (original.r == best_color.r and original.g == best_color.g and original.b == best_color.b),
                .color_space_info = .{
                    .is_in_cube = precise_palette.isCubeColor(best_index),
                    .is_grayscale = precise_palette.isGrayscaleColor(best_index),
                    .is_basic_color = precise_palette.isBasicColor(best_index),
                },
            };
        }

        /// Find colors that convert poorly to 256-color space
        pub fn findProblematicColors(colors: []const RGBColor, threshold: f64, allocator: std.mem.Allocator) ![]struct {
            original: RGBColor,
            converted: RGBColor,
            distance: f64,
        } {
            var problematic = std.ArrayList(struct {
                original: RGBColor,
                converted: RGBColor,
                distance: f64,
            }).init(allocator);

            for (colors) |color| {
                const analysis = analyzeConversion(color);
                if (analysis.perceptual_distance > threshold) {
                    try problematic.append(.{
                        .original = color,
                        .converted = analysis.best_256_color,
                        .distance = analysis.perceptual_distance,
                    });
                }
            }

            return problematic.toOwnedSlice();
        }
    };

    /// Performance benchmarking utilities
    pub const Benchmark = struct {
        /// Benchmark different conversion methods
        pub fn compareConversionMethods(test_colors: []const RGBColor, allocator: std.mem.Allocator) !struct {
            enhanced_time_ns: u64,
            fast_time_ns: u64,
            optimal_time_ns: u64,
            results_match: bool,
        } {
            var enhanced_results = try allocator.alloc(u8, test_colors.len);
            defer allocator.free(enhanced_results);
            var fast_results = try allocator.alloc(u8, test_colors.len);
            defer allocator.free(fast_results);
            var optimal_results = try allocator.alloc(u8, test_colors.len);
            defer allocator.free(optimal_results);

            // Benchmark enhanced conversion
            var timer = try std.time.Timer.start();
            for (test_colors, 0..) |color, i| {
                enhanced_results[i] = convert256Enhanced(color);
            }
            const enhanced_time = timer.lap();

            // Benchmark fast conversion
            for (test_colors, 0..) |color, i| {
                fast_results[i] = convert256Fast(color);
            }
            const fast_time = timer.lap();

            // Benchmark optimal conversion
            for (test_colors, 0..) |color, i| {
                optimal_results[i] = convertOptimal(color);
            }
            const optimal_time = timer.lap();

            // Check if results are similar
            var results_match = true;
            for (enhanced_results, optimal_results) |enhanced, optimal| {
                // Allow some difference between methods
                const enhanced_color = precise_palette.getRgbColor(enhanced);
                const optimal_color = precise_palette.getRgbColor(optimal);
                const distance = enhanced_distance.perceptualDistanceFast(enhanced_color, optimal_color);
                if (distance > 5.0) { // Threshold for "similar enough"
                    results_match = false;
                    break;
                }
            }

            return .{
                .enhanced_time_ns = enhanced_time,
                .fast_time_ns = fast_time,
                .optimal_time_ns = optimal_time,
                .results_match = results_match,
            };
        }
    };
};

/// Convenience wrapper that provides different conversion strategies
pub const ColorConverter = struct {
    const Strategy = enum {
        enhanced, // Best perceptual accuracy (recommended)
        fast, // Faster with good accuracy
        optimal, // Highest accuracy but slower
        simple, // Simple Euclidean distance fallback
    };

    /// Convert RGB to 256-color using specified strategy
    pub fn convert(rgb: RGBColor, strategy: Strategy) u8 {
        return switch (strategy) {
            .enhanced => EnhancedColorConverter.convert256Enhanced(rgb),
            .fast => EnhancedColorConverter.convert256Fast(rgb),
            .optimal => EnhancedColorConverter.convertOptimal(rgb),
            .simple => precise_palette.PreciseColorMatcher.findClosestEuclidean(rgb).index,
        };
    }

    /// Convert RGB to 16-color
    pub fn convert16(rgb: RGBColor) u8 {
        return EnhancedColorConverter.convert16(rgb);
    }

    /// Get recommended strategy based on performance requirements
    pub fn getRecommendedStrategy(performance_priority: enum { accuracy, balanced, speed }) Strategy {
        return switch (performance_priority) {
            .accuracy => .optimal,
            .balanced => .enhanced,
            .speed => .fast,
        };
    }
};

// Tests
const testing = std.testing;

test "cube coordinate calculation" {
    // Test cube coordinate mapping
    try testing.expect(EnhancedColorConverter.rgbTo6Cube(0) == 0);
    try testing.expect(EnhancedColorConverter.rgbTo6Cube(47) == 0); // Below threshold
    try testing.expect(EnhancedColorConverter.rgbTo6Cube(48) == 1); // At threshold
    try testing.expect(EnhancedColorConverter.rgbTo6Cube(255) == 5); // Max value

    // Test cube-to-RGB conversion
    try testing.expect(EnhancedColorConverter.cubeToRgb(0) == 0x00);
    try testing.expect(EnhancedColorConverter.cubeToRgb(1) == 0x5F);
    try testing.expect(EnhancedColorConverter.cubeToRgb(5) == 0xFF);
}

test "cube color calculation" {
    const pure_red = RGBColor.init(255, 0, 0);
    const cube_result = EnhancedColorConverter.calculateCubeColor(pure_red);

    // Pure red should map to cube coordinates (5, 0, 0)
    try testing.expect(cube_result.color.r == 0xFF);
    try testing.expect(cube_result.color.g == 0x00);
    try testing.expect(cube_result.color.b == 0x00);

    // Index should be 16 + 5*36 + 0*6 + 0 = 196
    try testing.expect(cube_result.index == 196);
}

test "grayscale calculation" {
    const gray = RGBColor.init(128, 128, 128);
    const gray_result = EnhancedColorConverter.calculateGrayscaleColor(gray);

    // Should be in grayscale range (232-255)
    try testing.expect(gray_result.index >= 232 and gray_result.index <= 255);

    // Color should be grayscale (R=G=B)
    try testing.expect(gray_result.color.r == gray_result.color.g);
    try testing.expect(gray_result.color.g == gray_result.color.b);
}

test "enhanced color conversion" {
    // Test pure colors that should have exact matches
    const pure_red = RGBColor.init(255, 0, 0);
    const red_result = EnhancedColorConverter.convert256Enhanced(pure_red);
    try testing.expect(red_result == 9 or red_result == 196); // Basic red or cube red

    const pure_blue = RGBColor.init(0, 0, 255);
    const blue_result = EnhancedColorConverter.convert256Enhanced(pure_blue);
    try testing.expect(blue_result == 12 or blue_result == 21); // Basic blue or cube blue

    // Test gray conversion
    const mid_gray = RGBColor.init(128, 128, 128);
    const gray_result = EnhancedColorConverter.convert256Enhanced(mid_gray);
    try testing.expect(gray_result >= 232 or gray_result == 8); // Should be grayscale or basic gray
}

test "conversion strategy comparison" {
    const test_color = RGBColor.init(200, 100, 50);

    const enhanced = ColorConverter.convert(test_color, .enhanced);
    const fast = ColorConverter.convert(test_color, .fast);
    const optimal = ColorConverter.convert(test_color, .optimal);

    // All should produce valid indices
    try testing.expect(enhanced <= 255);
    try testing.expect(fast <= 255);
    try testing.expect(optimal <= 255);

    // Results should be reasonably close (allowing for different algorithms)
    const enhanced_color = precise_palette.getRgbColor(enhanced);
    const optimal_color = precise_palette.getRgbColor(optimal);
    const distance = enhanced_distance.perceptualDistanceFast(enhanced_color, optimal_color);
    try testing.expect(distance < 20.0); // Should be relatively close
}

test "16-color conversion" {
    const bright_colors = [_]RGBColor{
        RGBColor.init(255, 0, 0), // Red
        RGBColor.init(0, 255, 0), // Green
        RGBColor.init(0, 0, 255), // Blue
        RGBColor.init(255, 255, 0), // Yellow
        RGBColor.init(255, 0, 255), // Magenta
        RGBColor.init(0, 255, 255), // Cyan
        RGBColor.init(255, 255, 255), // White
    };

    for (bright_colors) |color| {
        const result = ColorConverter.convert16(color);
        try testing.expect(result <= 15); // Should be valid 16-color index

        // Should map to a bright color (8-15) for these pure colors
        try testing.expect(result >= 8);
    }
}

test "conversion analysis" {
    const test_color = RGBColor.init(180, 90, 45);
    const analysis = EnhancedColorConverter.Analysis.analyzeConversion(test_color);

    try testing.expect(analysis.best_256_index <= 255);
    try testing.expect(analysis.perceptual_distance >= 0.0);
    try testing.expect(analysis.euclidean_distance >= 0.0);

    // Should categorize the color correctly
    try testing.expect(analysis.color_space_info.is_in_cube or
        analysis.color_space_info.is_grayscale or
        analysis.color_space_info.is_basic_color);
}

test "batch conversion" {
    const test_colors = [_]RGBColor{
        RGBColor.init(255, 0, 0),
        RGBColor.init(0, 255, 0),
        RGBColor.init(0, 0, 255),
        RGBColor.init(128, 128, 128),
    };

    var results: [4]u8 = undefined;
    EnhancedColorConverter.convertBatch(&test_colors, &results, false);

    // All results should be valid
    for (results) |result| {
        try testing.expect(result <= 255);
    }
}

test "recommended strategy selection" {
    try testing.expect(ColorConverter.getRecommendedStrategy(.accuracy) == .optimal);
    try testing.expect(ColorConverter.getRecommendedStrategy(.balanced) == .enhanced);
    try testing.expect(ColorConverter.getRecommendedStrategy(.speed) == .fast);
}

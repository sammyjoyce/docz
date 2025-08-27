const std = @import("std");
const Sparkline = @import("src/shared/tui/widgets/dashboard/sparkline.zig").Sparkline;
const engine_mod = @import("src/shared/tui/widgets/dashboard/engine.zig");

test "sparklineInit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sparkline = try Sparkline.init(allocator, .standard);
    defer sparkline.deinit();

    try std.testing.expectEqual(sparkline.data.len, 0);
    try std.testing.expectEqual(sparkline.width, null);
    try std.testing.expectEqual(sparkline.height, null);
    try std.testing.expectEqual(sparkline.show_trend, false);
    try std.testing.expectEqual(sparkline.fill_area, false);
}

test "sparklineDataConfig" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sparkline = try Sparkline.init(allocator, .standard);
    defer sparkline.deinit();

    const test_data = [_]f64{ 1.0, 3.0, 2.0, 5.0, 4.0 };
    sparkline.setData(&test_data);

    try std.testing.expectEqual(sparkline.data.len, 5);
    try std.testing.expectEqual(sparkline.data[0], 1.0);
    try std.testing.expectEqual(sparkline.data[4], 4.0);
}

test "sparklineDimensionsTitle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sparkline = try Sparkline.init(allocator, .standard);
    defer sparkline.deinit();

    sparkline.setDimensions(20, 1);
    try sparkline.setTitle("Test Sparkline");

    try std.testing.expectEqual(sparkline.width, 20);
    try std.testing.expectEqual(sparkline.height, 1);
    try std.testing.expectEqualSlices(u8, "Test Sparkline", sparkline.title.?);
}

test "sparklineTrendCalc" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sparkline = try Sparkline.init(allocator, .standard);
    defer sparkline.deinit();

    // Increasing trend
    const increasing_data = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    sparkline.setData(&increasing_data);
    const increasing_trend = sparkline.calculateTrend();
    try std.testing.expect(increasing_trend > 0);

    // Decreasing trend
    const decreasing_data = [_]f64{ 5.0, 4.0, 3.0, 2.0, 1.0 };
    sparkline.setData(&decreasing_data);
    const decreasing_trend = sparkline.calculateTrend();
    try std.testing.expect(decreasing_trend < 0);

    // Flat trend
    const flat_data = [_]f64{ 3.0, 3.0, 3.0, 3.0, 3.0 };
    sparkline.setData(&flat_data);
    const flat_trend = sparkline.calculateTrend();
    try std.testing.expect(std.math.approxEqAbs(f64, flat_trend, 0.0, 0.01));
}

test "sparklineMinMaxCalc" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sparkline = try Sparkline.init(allocator, .standard);
    defer sparkline.deinit();

    const test_data = [_]f64{ 1.0, 5.0, 2.0, 8.0, 3.0 };
    sparkline.setData(&test_data);

    const min_max = sparkline.calculateMinMax();
    try std.testing.expectEqual(min_max.min, 1.0);
    try std.testing.expectEqual(min_max.max, 8.0);
}

test "sparklineCustomValueRange" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sparkline = try Sparkline.init(allocator, .standard);
    defer sparkline.deinit();

    const test_data = [_]f64{ 1.0, 5.0, 2.0, 8.0, 3.0 };
    sparkline.setData(&test_data);
    sparkline.setValueRange(0.0, 10.0);

    const min_max = sparkline.calculateMinMax();
    try std.testing.expectEqual(min_max.min, 0.0);
    try std.testing.expectEqual(min_max.max, 10.0);
}

test "sparklineRenderModeConfig" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sparkline = try Sparkline.init(allocator, .standard);
    defer sparkline.deinit();

    // Test Unicode mode
    sparkline.setRenderMode(.{ .unicode = .{} });
    try std.testing.expect(sparkline.render_mode == .unicode);

    // Test ASCII mode
    sparkline.setRenderMode(.{ .ascii = .{} });
    try std.testing.expect(sparkline.render_mode == .ascii);

    // Test Graphics mode
    sparkline.setRenderMode(.{ .graphics = .{} });
    try std.testing.expect(sparkline.render_mode == .graphics);
}

test "sparkline_empty_data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sparkline = try Sparkline.init(allocator, .standard);
    defer sparkline.deinit();

    // Empty data should be handled gracefully
    const min_max = sparkline.calculateMinMax();
    try std.testing.expect(std.math.isInf(min_max.min));
    try std.testing.expect(std.math.isInf(min_max.max) and min_max.max < 0);

    const trend = sparkline.calculateTrend();
    try std.testing.expectEqual(trend, 0.0);
}
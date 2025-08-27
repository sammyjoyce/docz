const std = @import("std");
const testing = std.testing;
const BorderMerger = @import("../src/shared/render/border_merger.zig").BorderMerger;
const Point = @import("../src/shared/render/border_merger.zig").Point;

test "borderMergerInitializationAndCleanup" {
    const allocator = testing.allocator;

    var merger = try BorderMerger.init(allocator);
    defer merger.deinit();

    try testing.expect(merger.widgets.items.len == 0);
    try testing.expect(merger.merge_map.count() == 0);
}

test "borderMergerWidgetRegistration" {
    const allocator = testing.allocator;

    var merger = try BorderMerger.init(allocator);
    defer merger.deinit();

    const widget = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 0, .y = 0, .width = 10, .height = 5 },
        .style = .single,
    };

    try merger.addWidget(widget);
    try testing.expect(merger.widgets.items.len == 1);
    try testing.expectEqual(widget.rect.x, merger.widgets.items[0].rect.x);
}

test "borderMergerDetectsHorizontalAdjacency" {
    const allocator = testing.allocator;

    var merger = try BorderMerger.init(allocator);
    defer merger.deinit();

    // Two widgets side by side
    const widgetA = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 0, .y = 0, .width = 10, .height = 5 },
        .style = .single,
    };
    const widgetB = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 10, .y = 0, .width = 10, .height = 5 },
        .style = .single,
    };

    try merger.addWidget(widgetA);
    try merger.addWidget(widgetB);
    try merger.calculateMergePoints();

    // Should have merge points along the shared vertical edge
    try testing.expect(merger.merge_map.count() > 0);
}

test "borderMergerDetectsVerticalAdjacency" {
    const allocator = testing.allocator;

    var merger = try BorderMerger.init(allocator);
    defer merger.deinit();

    // Two widgets stacked vertically
    const widgetA = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 0, .y = 0, .width = 10, .height = 5 },
        .style = .single,
    };
    const widgetB = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 0, .y = 5, .width = 10, .height = 5 },
        .style = .single,
    };

    try merger.addWidget(widgetA);
    try merger.addWidget(widgetB);
    try merger.calculateMergePoints();

    // Should have merge points along the shared horizontal edge
    try testing.expect(merger.merge_map.count() > 0);
}

test "border_merger_junction type determination" {
    const allocator = testing.allocator;

    var merger = try BorderMerger.init(allocator);
    defer merger.deinit();

    // Create a T-junction with three widgets
    const widgetTop = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 5, .y = 0, .width = 10, .height = 5 },
        .style = .single,
    };
    const widgetLeft = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 0, .y = 5, .width = 10, .height = 5 },
        .style = .single,
    };
    const widgetRight = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 10, .y = 5, .width = 10, .height = 5 },
        .style = .single,
    };

    try merger.addWidget(widgetTop);
    try merger.addWidget(widgetLeft);
    try merger.addWidget(widgetRight);
    try merger.calculateMergePoints();

    // Should detect T-junction at the intersection point
    try testing.expect(merger.merge_map.count() > 0);
}

test "borderMergerCharacterMappingForDifferentStyles" {
    // Test single style
    try testing.expectEqual(@as(u21, '┌'), BorderMerger.getJunctionChar(.top_left, .single));
    try testing.expectEqual(@as(u21, '┼'), BorderMerger.getJunctionChar(.cross, .single));
    try testing.expectEqual(@as(u21, '├'), BorderMerger.getJunctionChar(.tee_right, .single));

    // Test double style
    try testing.expectEqual(@as(u21, '╔'), BorderMerger.getJunctionChar(.top_left, .double));
    try testing.expectEqual(@as(u21, '╬'), BorderMerger.getJunctionChar(.cross, .double));
    try testing.expectEqual(@as(u21, '╠'), BorderMerger.getJunctionChar(.tee_right, .double));

    // Test rounded style
    try testing.expectEqual(@as(u21, '╭'), BorderMerger.getJunctionChar(.top_left, .rounded));
    try testing.expectEqual(@as(u21, '╯'), BorderMerger.getJunctionChar(.bottom_right, .rounded));

    // Test thick style
    try testing.expectEqual(@as(u21, '┏'), BorderMerger.getJunctionChar(.top_left, .thick));
    try testing.expectEqual(@as(u21, '╋'), BorderMerger.getJunctionChar(.cross, .thick));
}

test "borderMergerClearFunctionality" {
    const allocator = testing.allocator;

    var merger = try BorderMerger.init(allocator);
    defer merger.deinit();

    const widget = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 0, .y = 0, .width = 10, .height = 5 },
        .style = .single,
    };

    try merger.addWidget(widget);
    try merger.calculateMergePoints();

    merger.clear();

    try testing.expect(merger.widgets.items.len == 0);
    try testing.expect(merger.merge_map.count() == 0);
}

test "borderMergerComplexGridLayout" {
    const allocator = testing.allocator;

    var merger = try BorderMerger.init(allocator);
    defer merger.deinit();

    // Create a 2x2 grid
    const widgets = [_]BorderMerger.WidgetBoundary{
        .{ .rect = .{ .x = 0, .y = 0, .width = 10, .height = 5 }, .style = .single },
        .{ .rect = .{ .x = 10, .y = 0, .width = 10, .height = 5 }, .style = .single },
        .{ .rect = .{ .x = 0, .y = 5, .width = 10, .height = 5 }, .style = .single },
        .{ .rect = .{ .x = 10, .y = 5, .width = 10, .height = 5 }, .style = .single },
    };

    for (widgets) |widget| {
        try merger.addWidget(widget);
    }

    try merger.calculateMergePoints();

    // Should have merge points at all intersections
    // Including the center cross where all four widgets meet
    try testing.expect(merger.merge_map.count() > 0);

    // Check for center cross junction
    const centerPoint = Point{ .x = 10, .y = 5 };
    const junction = merger.merge_map.get(centerPoint);
    try testing.expect(junction != null);
}
const std = @import("std");
const testing = std.testing;
const BorderMerger = @import("src/shared/tui/core/border_merger.zig").BorderMerger;
const Point = @import("src/shared/tui/core/bounds.zig").Point;

test "BorderMerger initialization and cleanup" {
    const allocator = testing.allocator;

    var merger = BorderMerger.init(allocator);
    defer merger.deinit();

    try testing.expect(merger.widgets.items.len == 0);
    try testing.expect(merger.merge_map.count() == 0);
}

test "BorderMerger widget registration" {
    const allocator = testing.allocator;

    var merger = BorderMerger.init(allocator);
    defer merger.deinit();

    const widget = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 0, .y = 0, .width = 10, .height = 5 },
        .style = .single,
    };

    try merger.addWidget(widget);
    try testing.expect(merger.widgets.items.len == 1);
    try testing.expectEqual(widget.rect.x, merger.widgets.items[0].rect.x);
}

test "BorderMerger detects horizontal adjacency" {
    const allocator = testing.allocator;

    var merger = BorderMerger.init(allocator);
    defer merger.deinit();

    // Two widgets side by side
    const widget_a = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 0, .y = 0, .width = 10, .height = 5 },
        .style = .single,
    };
    const widget_b = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 10, .y = 0, .width = 10, .height = 5 },
        .style = .single,
    };

    try merger.addWidget(widget_a);
    try merger.addWidget(widget_b);
    try merger.calculateMergePoints();

    // Should have merge points along the shared vertical edge
    try testing.expect(merger.merge_map.count() > 0);
}

test "BorderMerger detects vertical adjacency" {
    const allocator = testing.allocator;

    var merger = BorderMerger.init(allocator);
    defer merger.deinit();

    // Two widgets stacked vertically
    const widget_a = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 0, .y = 0, .width = 10, .height = 5 },
        .style = .single,
    };
    const widget_b = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 0, .y = 5, .width = 10, .height = 5 },
        .style = .single,
    };

    try merger.addWidget(widget_a);
    try merger.addWidget(widget_b);
    try merger.calculateMergePoints();

    // Should have merge points along the shared horizontal edge
    try testing.expect(merger.merge_map.count() > 0);
}

test "BorderMerger junction type determination" {
    const allocator = testing.allocator;

    var merger = BorderMerger.init(allocator);
    defer merger.deinit();

    // Create a T-junction with three widgets
    const widget_top = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 5, .y = 0, .width = 10, .height = 5 },
        .style = .single,
    };
    const widget_left = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 0, .y = 5, .width = 10, .height = 5 },
        .style = .single,
    };
    const widget_right = BorderMerger.WidgetBoundary{
        .rect = .{ .x = 10, .y = 5, .width = 10, .height = 5 },
        .style = .single,
    };

    try merger.addWidget(widget_top);
    try merger.addWidget(widget_left);
    try merger.addWidget(widget_right);
    try merger.calculateMergePoints();

    // Should detect T-junction at the intersection point
    try testing.expect(merger.merge_map.count() > 0);
}

test "BorderMerger character mapping for different styles" {
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

test "BorderMerger clear functionality" {
    const allocator = testing.allocator;

    var merger = BorderMerger.init(allocator);
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

test "BorderMerger complex grid layout" {
    const allocator = testing.allocator;

    var merger = BorderMerger.init(allocator);
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
    const center_point = Point{ .x = 10, .y = 5 };
    const junction = merger.merge_map.get(center_point);
    try testing.expect(junction != null);
}
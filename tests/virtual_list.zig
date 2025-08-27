//! Tests for VirtualList widget
//! 
//! Tests virtual scrolling, data source abstraction, search,
//! and performance with large datasets.

const std = @import("std");
const testing = std.testing;
const tui = @import("../src/shared/tui/mod.zig");
const VirtualList = tui.widgets.VirtualList;
const Item = tui.widgets.Item;
const Config = tui.widgets.Config;
const DataSource = tui.widgets.DataSource;
const ArrayDataSource = tui.widgets.ArrayDataSource;
const Bounds = tui.core.Bounds;

test "virtualListInitialization" {
    const allocator = testing.allocator;
    
    const items = [_]Item{
        .{ .content = "Item 1" },
        .{ .content = "Item 2" },
        .{ .content = "Item 3" },
    };
    
    const data_source = ArrayDataSource.init(&items);
    const config = Config{};
    
    var list = try VirtualList.init(allocator, data_source, config);
    defer list.deinit();
    
    try testing.expectEqual(@as(usize, 0), list.visible_start);
    try testing.expectEqual(@as(usize, 0), list.visible_end);
    try testing.expectEqual(@as(f32, 0), list.scroll_position);
    try testing.expectEqual(@as(?usize, null), list.selected_index);
}

test "virtualListDataSource" {
    const allocator = testing.allocator;
    
    const items = [_]Item{
        .{ .content = "Apple", .icon = "🍎" },
        .{ .content = "Banana", .icon = "🍌" },
        .{ .content = "Cherry", .icon = "🍒" },
        .{ .content = "Date", .icon = "🌴" },
        .{ .content = "Elderberry", .icon = "🫐" },
    };
    
    const data_source = ArrayDataSource.init(&items);
    
    try testing.expectEqual(@as(usize, 5), data_source.getCount());
    
    const item = data_source.getItem(2, allocator).?;
    try testing.expectEqualStrings("Cherry", item.content);
    try testing.expectEqualStrings("🍒", item.icon.?);
}

test "virtualListVisibleRangeCalculation" {
    const allocator = testing.allocator;
    
    const items = try allocator.alloc(Item, 100);
    defer allocator.free(items);
    
    for (items, 0..) |*item, i| {
        item.* = .{
            .content = try std.fmt.allocPrint(allocator, "Item {d}", .{i}),
        };
    }
    defer for (items) |item| {
        allocator.free(item.content);
    };
    
    const data_source = ArrayDataSource.init(items);
    const config = Config{
        .overscan = 3,
    };
    
    var list = try VirtualList.init(allocator, data_source, config);
    defer list.deinit();
    
    // Set viewport
    list.viewport = Bounds{
        .x = 0,
        .y = 0,
        .width = 80,
        .height = 10,
    };
    
    // Update visible range
    list.updateVisibleRange();
    
    try testing.expectEqual(@as(usize, 0), list.visible_start);
    try testing.expectEqual(@as(usize, 13), list.visible_end); // viewport height + overscan
    
    // Scroll down
    list.scroll_position = 10;
    list.updateVisibleRange();
    
    try testing.expectEqual(@as(usize, 7), list.visible_start); // scroll - overscan
    try testing.expectEqual(@as(usize, 23), list.visible_end); // scroll + viewport + overscan
}

test "virtualListKeyboardNavigation" {
    const allocator = testing.allocator;
    
    const items = [_]Item{
        .{ .content = "Item 1" },
        .{ .content = "Item 2" },
        .{ .content = "Item 3" },
        .{ .content = "Item 4" },
        .{ .content = "Item 5" },
    };
    
    const data_source = ArrayDataSource.init(&items);
    const config = Config{
        .keyboard_navigation = true,
    };
    
    var list = try VirtualList.init(allocator, data_source, config);
    defer list.deinit();
    
    list.viewport = Bounds{
        .x = 0,
        .y = 0,
        .width = 80,
        .height = 3,
    };
    
    // Initial state - nothing selected
    try testing.expectEqual(@as(?usize, null), list.selected_index);
    
    // Press down arrow - select first item
    try list.handleKeyboard(.arrow_down);
    try testing.expectEqual(@as(?usize, 0), list.selected_index);
    
    // Press down arrow again - select second item
    try list.handleKeyboard(.arrow_down);
    try testing.expectEqual(@as(?usize, 1), list.selected_index);
    
    // Press up arrow - go back to first item
    try list.handleKeyboard(.arrow_up);
    try testing.expectEqual(@as(?usize, 0), list.selected_index);
    
    // Press End - jump to last item
    try list.handleKeyboard(.end);
    try testing.expectEqual(@as(?usize, 4), list.selected_index);
    
    // Press Home - jump to first item
    try list.handleKeyboard(.home);
    try testing.expectEqual(@as(?usize, 0), list.selected_index);
}

test "virtualListSearchFunctionality" {
    const allocator = testing.allocator;
    
    const items = [_]Item{
        .{ .content = "Apple" },
        .{ .content = "Banana" },
        .{ .content = "Cherry" },
        .{ .content = "Date" },
        .{ .content = "Apricot" },
    };
    
    const data_source = ArrayDataSource.init(&items);
    const config = Config{};
    
    var list = try VirtualList.init(allocator, data_source, config);
    defer list.deinit();
    
    // Search for items containing "a"
    try list.search("a");
    
    // Should have filtered indices
    try testing.expect(list.filtered_indices != null);
    const filtered = list.filtered_indices.?;
    
    // Banana, Date should match (case-sensitive search)
    try testing.expectEqual(@as(usize, 2), filtered.items.len);
    try testing.expectEqual(@as(usize, 1), filtered.items[0]); // Banana
    try testing.expectEqual(@as(usize, 3), filtered.items[1]); // Date
    
    // Clear search
    try list.search("");
    try testing.expectEqual(@as(?std.ArrayList(usize), null), list.filtered_indices);
}

test "virtual_list_scroll physics" {
    const allocator = testing.allocator;
    
    const items = try allocator.alloc(Item, 1000);
    defer allocator.free(items);
    
    for (items, 0..) |*item, i| {
        item.* = .{
            .content = try std.fmt.allocPrint(allocator, "Item {d}", .{i}),
        };
    }
    defer for (items) |item| {
        allocator.free(item.content);
    };
    
    const data_source = ArrayDataSource.init(items);
    const config = Config{
        .smooth_scrolling = true,
        .scroll_speed = 1.0,
    };
    
    var list = try VirtualList.init(allocator, data_source, config);
    defer list.deinit();
    
    list.viewport = Bounds{
        .x = 0,
        .y = 0,
        .width = 80,
        .height = 10,
    };
    
    // Apply scroll velocity
    list.scroll_velocity = 100;
    const initial_position = list.scroll_position;
    
    // Update physics
    list.updateScrollPhysics();
    
    // Position should have changed
    try testing.expect(list.scroll_position > initial_position);
    
    // Velocity should have decreased due to friction
    try testing.expect(list.scroll_velocity < 100);
}

test "virtual_list_ensure visible" {
    const allocator = testing.allocator;
    
    const items = try allocator.alloc(Item, 100);
    defer allocator.free(items);
    
    for (items, 0..) |*item, i| {
        item.* = .{
            .content = try std.fmt.allocPrint(allocator, "Item {d}", .{i}),
        };
    }
    defer for (items) |item| {
        allocator.free(item.content);
    };
    
    const data_source = ArrayDataSource.init(items);
    const config = Config{};
    
    var list = try VirtualList.init(allocator, data_source, config);
    defer list.deinit();
    
    list.viewport = Bounds{
        .x = 0,
        .y = 0,
        .width = 80,
        .height = 10,
    };
    
    // Ensure item 50 is visible
    list.ensureVisible(50);
    
    // Scroll position should have adjusted
    try testing.expect(list.scroll_position > 0);
    try testing.expect(list.scroll_position <= 50);
    
    // Item 50 should be in visible range
    const visible_start = @as(usize, @intFromFloat(list.scroll_position));
    const visible_end = visible_start + list.viewport.height;
    try testing.expect(50 >= visible_start);
    try testing.expect(50 < visible_end);
}

test "virtualListPerformanceWithLargeDataset" {
    const allocator = testing.allocator;
    
    // Create a large dataset
    const item_count = 100_000;
    const items = try allocator.alloc(Item, item_count);
    defer allocator.free(items);
    
    for (items, 0..) |*item, i| {
        item.* = .{
            .content = try std.fmt.allocPrint(allocator, "Item {d}", .{i}),
        };
    }
    defer for (items) |item| {
        allocator.free(item.content);
    };
    
    const data_source = ArrayDataSource.init(items);
    const config = Config{
        .cache_size = 100,
        .prefetch_distance = 20,
    };
    
    var list = try VirtualList.init(allocator, data_source, config);
    defer list.deinit();
    
    list.viewport = Bounds{
        .x = 0,
        .y = 0,
        .width = 80,
        .height = 30,
    };
    
    // Test that we can handle scrolling through large dataset
    const start_time = std.time.milliTimestamp();
    
    // Simulate scrolling through dataset
    var position: f32 = 0;
    while (position < @as(f32, @floatFromInt(item_count - 30))) : (position += 100) {
        list.scroll_position = position;
        list.updateVisibleRange();
        
        // Verify visible range is reasonable
        try testing.expect(list.visible_end - list.visible_start <= 40); // viewport + overscan
    }
    
    const elapsed = std.time.milliTimestamp() - start_time;
    
    // Should complete quickly even with large dataset
    try testing.expect(elapsed < 1000); // Less than 1 second
}

test "virtualListMouseHandling" {
    const allocator = testing.allocator;
    
    const items = [_]Item{
        .{ .content = "Item 1" },
        .{ .content = "Item 2" },
        .{ .content = "Item 3" },
        .{ .content = "Item 4" },
        .{ .content = "Item 5" },
    };
    
    const data_source = ArrayDataSource.init(&items);
    const config = Config{
        .mouse_support = true,
        .smooth_scrolling = true,
    };
    
    var list = try VirtualList.init(allocator, data_source, config);
    defer list.deinit();
    
    list.viewport = Bounds{
        .x = 10,
        .y = 5,
        .width = 40,
        .height = 3,
    };
    
    // Test scroll up
    const scroll_up = .{
        .type = .scroll_up,
        .x = 15,
        .y = 6,
    };
    try list.handleMouse(scroll_up);
    try testing.expect(list.scroll_velocity < 0); // Negative velocity for scrolling up
    
    // Test scroll down
    const scroll_down = .{
        .type = .scroll_down,
        .x = 15,
        .y = 6,
    };
    try list.handleMouse(scroll_down);
    try testing.expect(list.scroll_velocity > 0); // Positive velocity for scrolling down
    
    // Test click to select
    list.scroll_position = 0;
    const click = .{
        .type = .press,
        .x = 15,
        .y = 6, // Second visible item (viewport.y + 1)
    };
    try list.handleMouse(click);
    try testing.expectEqual(@as(?usize, 1), list.selected_index);
}
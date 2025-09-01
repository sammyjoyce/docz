const std = @import("std");
const testing = std.testing;
const SelectMenu = @import("../src/foundation/cli/components/base/SelectMenu.zig").SelectMenu;
const SelectMenuItem = @import("../src/foundation/cli/components/base/SelectMenu.zig").SelectMenuItem;
const SelectionMode = @import("../src/foundation/cli/components/base/SelectMenu.zig").SelectionMode;
const MenuAction = @import("../src/foundation/cli/components/base/SelectMenu.zig").MenuAction;

test "SelectMenuItem initialization" {
    const item = SelectMenuItem.init("test_id", "Test Item");
    try testing.expectEqualStrings(item.id, "test_id");
    try testing.expectEqualStrings(item.displayText, "Test Item");
    try testing.expect(item.description == null);
    try testing.expect(item.icon == null);
    try testing.expect(item.disabled == false);
    try testing.expect(item.selected == false);
}

test "SelectMenuItem builder methods" {
    const base = SelectMenuItem.init("id", "Display");

    const with_desc = base.withDescription("Description text");
    try testing.expectEqualStrings(with_desc.description.?, "Description text");

    const with_icon = base.withIcon("✓");
    try testing.expectEqualStrings(with_icon.icon.?, "✓");

    const with_link = base.withHyperlink("https://example.com");
    try testing.expectEqualStrings(with_link.hyperlink.?, "https://example.com");

    const disabled = base.asDisabled();
    try testing.expect(disabled.disabled == true);
}

test "SelectMenuItem chaining builder methods" {
    const item = SelectMenuItem.init("complex", "Complex Item")
        .withDescription("This is a complex item")
        .withIcon("⚡")
        .withHyperlink("https://test.com")
        .asDisabled();

    try testing.expectEqualStrings(item.id, "complex");
    try testing.expectEqualStrings(item.displayText, "Complex Item");
    try testing.expectEqualStrings(item.description.?, "This is a complex item");
    try testing.expectEqualStrings(item.icon.?, "⚡");
    try testing.expectEqualStrings(item.hyperlink.?, "https://test.com");
    try testing.expect(item.disabled == true);
}

test "SelectMenu initialization with single selection" {
    const allocator = testing.allocator;

    // Mock input manager
    var input_buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&input_buffer);
    const input_alloc = fba.allocator();

    var input = try @import("../src/foundation/term.zig").input.Input.init(input_alloc);
    defer input.deinit();

    var menu = try SelectMenu.init(allocator, &input, "Test Menu", .single);
    defer menu.deinit();

    try testing.expectEqualStrings(menu.title, "Test Menu");
    try testing.expect(menu.selectionMode == .single);
    try testing.expect(menu.items.items.len == 0);
    try testing.expect(menu.currentIndex == 0);
}

test "SelectMenu add single item" {
    const allocator = testing.allocator;

    var input_buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&input_buffer);
    const input_alloc = fba.allocator();

    var input = try @import("../src/foundation/term.zig").input.Input.init(input_alloc);
    defer input.deinit();

    var menu = try SelectMenu.init(allocator, &input, "Test Menu", .single);
    defer menu.deinit();

    const item = SelectMenuItem.init("item1", "First Item");
    try menu.addItem(item);

    try testing.expect(menu.items.items.len == 1);
    try testing.expectEqualStrings(menu.items.items[0].id, "item1");
}

test "SelectMenu add multiple items" {
    const allocator = testing.allocator;

    var input_buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&input_buffer);
    const input_alloc = fba.allocator();

    var input = try @import("../src/foundation/term.zig").input.Input.init(input_alloc);
    defer input.deinit();

    var menu = try SelectMenu.init(allocator, &input, "Test Menu", .multiple);
    defer menu.deinit();

    const items = [_]SelectMenuItem{
        SelectMenuItem.init("item1", "First Item"),
        SelectMenuItem.init("item2", "Second Item").withDescription("Description"),
        SelectMenuItem.init("item3", "Third Item").withIcon("★"),
    };

    try menu.addItems(&items);

    try testing.expect(menu.items.items.len == 3);
    try testing.expectEqualStrings(menu.items.items[0].id, "item1");
    try testing.expectEqualStrings(menu.items.items[1].id, "item2");
    try testing.expectEqualStrings(menu.items.items[2].id, "item3");
    try testing.expect(menu.items.items[1].description != null);
    try testing.expect(menu.items.items[2].icon != null);
}

test "SelectMenu getCurrentItem" {
    const allocator = testing.allocator;

    var input_buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&input_buffer);
    const input_alloc = fba.allocator();

    var input = try @import("../src/foundation/term.zig").input.Input.init(input_alloc);
    defer input.deinit();

    var menu = try SelectMenu.init(allocator, &input, "Test Menu", .single);
    defer menu.deinit();

    // Empty menu should return null
    try testing.expect(menu.getCurrentItem() == null);

    // Add items
    const items = [_]SelectMenuItem{
        SelectMenuItem.init("item1", "First Item"),
        SelectMenuItem.init("item2", "Second Item"),
    };
    try menu.addItems(&items);

    // Should return first item by default
    const current = menu.getCurrentItem();
    try testing.expect(current != null);
    try testing.expectEqualStrings(current.?.id, "item1");
}

test "SelectMenu getSelectedItems for single selection" {
    const allocator = testing.allocator;

    var input_buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&input_buffer);
    const input_alloc = fba.allocator();

    var input = try @import("../src/foundation/term.zig").input.Input.init(input_alloc);
    defer input.deinit();

    var menu = try SelectMenu.init(allocator, &input, "Test Menu", .single);
    defer menu.deinit();

    var items = [_]SelectMenuItem{
        SelectMenuItem.init("item1", "First Item"),
        SelectMenuItem.init("item2", "Second Item"),
    };
    items[0].selected = true;
    try menu.addItems(&items);

    const selected = try menu.getSelectedItems(allocator);
    defer allocator.free(selected);

    try testing.expect(selected.len == 1);
    try testing.expectEqualStrings(selected[0].id, "item1");
}

test "SelectMenu getSelectedItems for multiple selection" {
    const allocator = testing.allocator;

    var input_buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&input_buffer);
    const input_alloc = fba.allocator();

    var input = try @import("../src/foundation/term.zig").input.Input.init(input_alloc);
    defer input.deinit();

    var menu = try SelectMenu.init(allocator, &input, "Test Menu", .multiple);
    defer menu.deinit();

    var items = [_]SelectMenuItem{
        SelectMenuItem.init("item1", "First Item"),
        SelectMenuItem.init("item2", "Second Item"),
        SelectMenuItem.init("item3", "Third Item"),
    };
    items[0].selected = true;
    items[2].selected = true;
    try menu.addItems(&items);

    const selected = try menu.getSelectedItems(allocator);
    defer allocator.free(selected);

    try testing.expect(selected.len == 2);
    try testing.expectEqualStrings(selected[0].id, "item1");
    try testing.expectEqualStrings(selected[1].id, "item3");
}

test "SelectMenu with disabled items" {
    const allocator = testing.allocator;

    var input_buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&input_buffer);
    const input_alloc = fba.allocator();

    var input = try @import("../src/foundation/term.zig").input.Input.init(input_alloc);
    defer input.deinit();

    var menu = try SelectMenu.init(allocator, &input, "Test Menu", .single);
    defer menu.deinit();

    const items = [_]SelectMenuItem{
        SelectMenuItem.init("item1", "Enabled Item"),
        SelectMenuItem.init("item2", "Disabled Item").asDisabled(),
        SelectMenuItem.init("item3", "Another Enabled"),
    };
    try menu.addItems(&items);

    try testing.expect(menu.items.items[0].disabled == false);
    try testing.expect(menu.items.items[1].disabled == true);
    try testing.expect(menu.items.items[2].disabled == false);
}

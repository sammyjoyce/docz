//! Basic test for ScrollableTextArea widget

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// Import the widget
const tui = @import("../src/shared/tui/mod.zig");
const ScrollableTextArea = tui.widgets.ScrollableTextArea;
const WordWrapMode = tui.widgets.WordWrapMode;
const Selection = tui.widgets.Selection;

test "ScrollableTextArea initialization" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var text_area = try ScrollableTextArea.init(allocator, .{});
    defer text_area.deinit();

    // Test initial state
    try testing.expectEqual(@as(usize, 0), text_area.lines.items.len);
    try testing.expectEqual(@as(usize, 0), text_area.cursor_line);
    try testing.expectEqual(@as(usize, 0), text_area.cursor_col);
    try testing.expect(!text_area.focused);
    try testing.expect(!text_area.modified);
}

test "ScrollableTextArea set text" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var text_area = try ScrollableTextArea.init(allocator, .{});
    defer text_area.deinit();

    const test_text = "Hello\nWorld\nThis is a test";
    try text_area.setText(test_text);

    // Check that text was set correctly
    try testing.expectEqualStrings(test_text, text_area.getText());
    try testing.expectEqual(@as(usize, 3), text_area.lines.items.len);
    try testing.expectEqualStrings("Hello", text_area.lines.items[0]);
    try testing.expectEqualStrings("World", text_area.lines.items[1]);
    try testing.expectEqualStrings("This is a test", text_area.lines.items[2]);
    try testing.expect(text_area.modified);
}

test "ScrollableTextArea cursor movement" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var text_area = try ScrollableTextArea.init(allocator, .{});
    defer text_area.deinit();

    const test_text = "Hello\nWorld";
    try text_area.setText(test_text);

    // Test cursor positioning
    text_area.setCursor(1, 2); // Line 1, column 2 ("r" in "World")
    try testing.expectEqual(@as(usize, 1), text_area.cursor_line);
    try testing.expectEqual(@as(usize, 2), text_area.cursor_col);
}

test "ScrollableTextArea search" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var text_area = try ScrollableTextArea.init(allocator, .{});
    defer text_area.deinit();

    const test_text = "Hello world\nThis is a test\nWorld peace";
    try text_area.setText(test_text);

    // Search for "world"
    try text_area.search("world");

    // Should find 2 matches (case insensitive search)
    try testing.expectEqual(@as(usize, 2), text_area.search_matches.items.len);

    // First match should be at line 0, columns 6-10 ("world")
    try testing.expectEqual(@as(usize, 0), text_area.search_matches.items[0].line);
    try testing.expectEqual(@as(usize, 6), text_area.search_matches.items[0].start_col);
    try testing.expectEqual(@as(usize, 11), text_area.search_matches.items[0].end_col);
}

test "ScrollableTextArea configuration" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var text_area = try ScrollableTextArea.init(allocator, .{
        .show_line_numbers = false,
        .word_wrap = .word,
        .read_only = true,
        .tab_width = 8,
    });
    defer text_area.deinit();

    // Check configuration
    try testing.expect(!text_area.config.show_line_numbers);
    try testing.expectEqual(WordWrapMode.word, text_area.config.word_wrap);
    try testing.expect(text_area.config.read_only);
    try testing.expectEqual(@as(u8, 8), text_area.config.tab_width);
}

test "ScrollableTextArea selection" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var text_area = try ScrollableTextArea.init(allocator, .{});
    defer text_area.deinit();

    const test_text = "Hello world\nThis is a test";
    try text_area.setText(test_text);

    // Set selection from line 0, col 6 to line 1, col 4 ("world\nThis")
    const selection = Selection{
        .start_line = 0,
        .start_col = 6,
        .end_line = 1,
        .end_col = 4,
    };
    text_area.setSelection(selection);

    // Check selection
    const current_selection = text_area.getSelection();
    try testing.expect(current_selection != null);
    try testing.expectEqual(@as(usize, 0), current_selection.?.start_line);
    try testing.expectEqual(@as(usize, 6), current_selection.?.start_col);
    try testing.expectEqual(@as(usize, 1), current_selection.?.end_line);
    try testing.expectEqual(@as(usize, 4), current_selection.?.end_col);

    // Test selection normalization
    const reversed_selection = Selection{
        .start_line = 1,
        .start_col = 4,
        .end_line = 0,
        .end_col = 6,
    };
    text_area.setSelection(reversed_selection);
    const normalized = text_area.getSelection();
    try testing.expect(normalized != null);
    try testing.expectEqual(@as(usize, 0), normalized.?.start_line);
    try testing.expectEqual(@as(usize, 6), normalized.?.start_col);
}
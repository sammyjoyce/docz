const std = @import("std");
const testing = std.testing;

// Import the cursor modules directly for testing
const cursor = @import("../src/shared/term/cursor.zig");
const control_cursor = @import("../src/shared/term/control/cursor.zig");
const input_cursor = @import("../src/shared/term/input/cursor.zig");

test "cursor consolidation - all modules accessible" {
    // Test that we can access cursor types from module
    _ = cursor.CursorStyle;
    _ = cursor.CursorPosition;
    _ = cursor.CursorPositionEvent;

    // Test that we can access cursor functions
    _ = cursor.hide;
    _ = cursor.show;
    _ = cursor.save;
    _ = cursor.restore;

    // Test that input parsing is available
    _ = cursor.tryParseCPR;
    _ = cursor.parsePositionReport;

    // Test that control module is still accessible
    _ = control_cursor.CursorStyle;
    _ = control_cursor.CursorPosition;

    // Test input module cursor parsing is still accessible
    _ = input_cursor.tryParseCPR;
    _ = input_cursor.CursorPositionEvent;
}

test "cursor position parsing works" {
    // Test parsing a standard cursor position report
    const input = "\x1b[12;40R";
    const result = cursor.parsePositionReport(input);

    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 11), result.?.row); // Zero-based
    try testing.expectEqual(@as(u32, 39), result.?.col); // Zero-based
}

test "cursor style enum values correct" {
    const CursorStyle = cursor.CursorStyle;

    try testing.expect(@intFromEnum(CursorStyle.blinking_block_default) == 0);
    try testing.expect(@intFromEnum(CursorStyle.blinking_block) == 1);
    try testing.expect(@intFromEnum(CursorStyle.steady_block) == 2);
    try testing.expect(@intFromEnum(CursorStyle.steady_bar) == 6);
}

test "cursor position creation and conversion" {
    const CursorPosition = cursor.CursorPosition;

    const pos = CursorPosition.init(5, 10);
    try testing.expectEqual(@as(u16, 6), pos.col); // 1-based
    try testing.expectEqual(@as(u16, 11), pos.row); // 1-based

    const zero_based = pos.to0Based();
    try testing.expectEqual(@as(u16, 5), zero_based.col);
    try testing.expectEqual(@as(u16, 10), zero_based.row);
}

test "cursorBuilderFluentApi" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = cursor.CursorBuilder.init(allocator);
    defer builder.deinit();

    const result = try builder
        .save().?.moveTo(10, 20).?.down(3).?.right(5).?.restore().?.build();
    defer allocator.free(result);

    // Should contain save, move, and restore sequences
    try testing.expect(std.mem.indexOf(u8, result, cursor.SAVE_CURSOR) != null);
    try testing.expect(std.mem.indexOf(u8, result, cursor.RESTORE_CURSOR) != null);
}

test "cursor controller compiles with proper writer type" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const test_writer = fbs.writer();

    // Create a controller with the specific writer type
    const ControllerType = cursor.CursorControllerFor(@TypeOf(test_writer));
    const caps = cursor.TermCaps{};

    var controller = ControllerType.init(allocator, test_writer, caps);
    defer controller.deinit();

    // Test that we can call basic methods
    try controller.moveTo(10, 20);
    try controller.setVisible(false);
    try controller.reset();
}

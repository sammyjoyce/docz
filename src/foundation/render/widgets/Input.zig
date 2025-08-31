const std = @import("std");
const Context = @import("../Context.zig");
const Surface = @import("../surface.zig");

pub const Rect = struct { x: i32, y: i32, w: u32, h: u32 };

/// Draw input with optional label. Caret is rendered as '|' at byte index cursor.
pub fn input(context: *Context, rectangle: Rect, label: []const u8, text: []const u8, cursor: usize) !void {
    if (rectangle.w == 0 or rectangle.h == 0) return;
    var x: i32 = rectangle.x;
    const y: i32 = rectangle.y;

    // label and a space
    var labelIndex: usize = 0;
    while (labelIndex < label.len and x < rectangle.x + @as(i32, @intCast(rectangle.w))) : (labelIndex += 1) {
        try context.putChar(x, y, label[labelIndex]);
        x += 1;
    }
    if (x < rectangle.x + @as(i32, @intCast(rectangle.w))) {
        try context.putChar(x, y, ' ');
        x += 1;
    }

    // draw text clipped
    var textIndex: usize = 0;
    while (textIndex < text.len and x < rectangle.x + @as(i32, @intCast(rectangle.w))) : (textIndex += 1) {
        try context.putChar(x, y, text[textIndex]);
        x += 1;
        // After placing byte textIndex, if textIndex+1 == cursor and room remains, draw caret
        if (textIndex + 1 == cursor and x < rectangle.x + @as(i32, @intCast(rectangle.w))) {
            try context.putChar(x, y, '|');
            x += 1;
        }
    }
    // If cursor at start with empty text, show caret
    if (text.len == 0 and cursor == 0 and x < rectangle.x + @as(i32, @intCast(rectangle.w))) {
        try context.putChar(x, y, '|');
    }
}

test "drawInput renders label, text and caret (golden)" {
    const allocator = std.testing.allocator;
    var surface = try Surface.MemorySurface.init(allocator, 10, 1);
    defer surface.deinit(allocator);
    var context = Context.init(surface, allocator);
    try input(&context, .{ .x = 0, .y = 0, .w = 10, .h = 1 }, "<", "hi", 1);
    const dump = try surface.toString(allocator);
    defer allocator.free(dump);
    const expected = "< h|i     \n";
    try std.testing.expectEqualStrings(expected, dump);
}

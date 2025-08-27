const std = @import("std");
const render = @import("../../render/mod.zig");
const ui = @import("../../ui/mod.zig");

/// Draw input with optional label. Caret is rendered as '|' at byte index cursor.
pub fn input(ctx: *render.Context, rect: ui.layout.Rect, label: []const u8, text: []const u8, cursor: usize) !void {
    if (rect.w == 0 or rect.h == 0) return;
    var x: i32 = rect.x;
    const y: i32 = rect.y;

    // label and a space
    var i: usize = 0;
    while (i < label.len and x < rect.x + @as(i32, @intCast(rect.w))) : (i += 1) {
        try ctx.putChar(x, y, label[i]);
        x += 1;
    }
    if (x < rect.x + @as(i32, @intCast(rect.w))) {
        try ctx.putChar(x, y, ' ');
        x += 1;
    }

    // draw text clipped
    var t: usize = 0;
    while (t < text.len and x < rect.x + @as(i32, @intCast(rect.w))) : (t += 1) {
        try ctx.putChar(x, y, text[t]);
        x += 1;
        // After placing byte t, if t+1 == cursor and room remains, draw caret
        if (t + 1 == cursor and x < rect.x + @as(i32, @intCast(rect.w))) {
            try ctx.putChar(x, y, '|');
            x += 1;
        }
    }
    // If cursor at start with empty text, show caret
    if (text.len == 0 and cursor == 0 and x < rect.x + @as(i32, @intCast(rect.w))) {
        try ctx.putChar(x, y, '|');
    }
}

test "drawInput renders label, text and caret (golden)" {
    const allocator = std.testing.allocator;
    var surface = try render.MemorySurface.init(allocator, 10, 1);
    defer {
        surface.deinit(allocator);
        allocator.destroy(surface);
    }
    var ctx = render.Context.init(surface, null);
    try input(&ctx, .{ .x = 0, .y = 0, .w = 10, .h = 1 }, "<", "hi", 1);
    const dump = try surface.toString(allocator);
    defer allocator.free(dump);
    const expected = "< h|i     \n";
    try std.testing.expectEqualStrings(expected, dump);
}

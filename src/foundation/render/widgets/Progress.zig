const std = @import("std");
const Context = @import("../Context.zig");
const Surface = @import("../surface.zig");

/// Draw a single-line progress bar into the given rectangle.
/// Layout: optional label, space, then bar composed of '=' for filled and '-' for unfilled.
pub const Rect = struct { x: i32, y: i32, w: u32, h: u32 };

pub fn progress(context: *Context, rectangle: Rect, value: f32, label: ?[]const u8) !void {
    if (rectangle.w == 0 or rectangle.h == 0) return;
    var x: i32 = rectangle.x;
    const y: i32 = rectangle.y;

    if (label) |labelText| {
        var labelIndex: usize = 0;
        while (labelIndex < labelText.len and x < rectangle.x + @as(i32, @intCast(rectangle.w))) : (labelIndex += 1) {
            try context.putChar(x, y, labelText[labelIndex]);
            x += 1;
        }
        if (x < rectangle.x + @as(i32, @intCast(rectangle.w))) {
            try context.putChar(x, y, ' ');
            x += 1;
        }
    }

    // Remaining width for the bar
    const totalWidth: i32 = rectangle.x + @as(i32, @intCast(rectangle.w)) - x;
    if (totalWidth <= 0) return;
    const clampedValue = if (value < 0.0) 0.0 else if (value > 1.0) 1.0 else value;
    const filledWidth: i32 = @intFromFloat(@floor(clampedValue * @as(f32, @floatFromInt(totalWidth)) + 0.5));

    var barIndex: i32 = 0;
    while (barIndex < totalWidth) : (barIndex += 1) {
        const character: u21 = if (barIndex < filledWidth) '=' else '-';
        try context.putChar(x + barIndex, y, character);
    }
}

test "drawProgress with label clips and fills proportionally" {
    const allocator = std.testing.allocator;
    var surface = try Surface.MemorySurface.init(allocator, 12, 1);
    defer surface.deinit(allocator);
    var context = Context.init(surface, allocator);
    try progress(&context, .{ .x = 0, .y = 0, .w = 12, .h = 1 }, 0.25, "P:");
    const dump = try surface.toString(allocator);
    defer allocator.free(dump);
    // Layout: "P:" + space + bar of width 9 with ~2-3 filled
    // With rounding, expect 2 filled in 9
    try std.testing.expectEqualStrings("P: ==-------\n", dump);
}

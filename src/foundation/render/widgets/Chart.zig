const std = @import("std");
const Context = @import("../Context.zig");
const Surface = @import("../surface.zig");

pub const Rect = struct { x: i32, y: i32, w: u32, h: u32 };

/// Draw a single-line sparkline using block characters based on values 0..1.
pub fn sparkline(context: *Context, rectangle: Rect, values: []const f32) !void {
    if (rectangle.w == 0 or rectangle.h == 0) return;
    if (values.len == 0) return;
    const blocks = [_]u21{ '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█' };
    const y: i32 = rectangle.y;
    const columnsMax: usize = @intCast(rectangle.w);
    const step: f32 = @as(f32, @floatFromInt(values.len)) / @as(f32, @floatFromInt(columnsMax));
    var x: usize = 0;
    while (x < columnsMax) : (x += 1) {
        const indexFloat = @as(f32, @floatFromInt(x)) * step;
        const listIndex = @min(@as(usize, @intFromFloat(indexFloat)), if (values.len == 0) 0 else values.len - 1);
        const value = clampZeroOne(values[listIndex]);
        const blockIndex: usize = @intCast(@max(0, @min(blocks.len - 1, @as(i32, @intFromFloat(@floor(value * @as(f32, @floatFromInt(blocks.len))))))));
        try context.putChar(rectangle.x + @as(i32, @intCast(x)), y, blocks[blockIndex]);
    }
}

fn clampZeroOne(value: f32) f32 {
    return if (value < 0.0) 0.0 else if (value > 1.0) 1.0 else value;
}

test "drawSparkline renders gradient blocks for values (golden)" {
    const allocator = std.testing.allocator;
    var surface = try Surface.MemorySurface.init(allocator, 3, 1);
    defer surface.deinit(allocator);
    var context = Context.init(surface, allocator);
    const values = [_]f32{ 0.0, 0.5, 1.0 };
    try sparkline(&context, .{ .x = 0, .y = 0, .w = 3, .h = 1 }, values[0..]);
    const dump = try surface.toString(allocator);
    defer allocator.free(dump);
    try std.testing.expectEqualStrings("▁▅█\n", dump);
}

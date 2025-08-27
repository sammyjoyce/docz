const std = @import("std");
const render = @import("../../render/mod.zig");
const ui = @import("../../ui/mod.zig");

/// Draw a single-line sparkline using block characters based on values 0..1.
pub fn sparkline(ctx: *render.Context, rect: ui.layout.Rect, values: []const f32) !void {
    if (rect.w == 0 or rect.h == 0) return;
    if (values.len == 0) return;
    const blocks = [_]u21{ '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█' };
    const y: i32 = rect.y;
    const colsMax: usize = @intCast(rect.w);
    const step: f32 = @as(f32, @floatFromInt(values.len)) / @as(f32, @floatFromInt(colsMax));
    var x: usize = 0;
    while (x < colsMax) : (x += 1) {
        const idxf = @as(f32, @floatFromInt(x)) * step;
        const li = @min(@as(usize, @intFromFloat(idxf)), if (values.len == 0) 0 else values.len - 1);
        const v = clampZeroOne(values[li]);
        const bi: usize = @intCast(@max(0, @min(blocks.len - 1, @as(i32, @intFromFloat(@floor(v * @as(f32, @floatFromInt(blocks.len))))))));
        try ctx.putChar(rect.x + @as(i32, @intCast(x)), y, blocks[bi]);
    }
}

fn clampZeroOne(v: f32) f32 {
    return if (v < 0.0) 0.0 else if (v > 1.0) 1.0 else v;
}

test "drawSparkline renders gradient blocks for values (golden)" {
    const allocator = std.testing.allocator;
    var surface = try render.MemorySurface.init(allocator, 3, 1);
    defer {
        surface.deinit(allocator);
        allocator.destroy(surface);
    }
    var ctx = render.Context.init(surface, null);
    const vals = [_]f32{ 0.0, 0.5, 1.0 };
    try sparkline(&ctx, .{ .x = 0, .y = 0, .w = 3, .h = 1 }, vals[0..]);
    const dump = try surface.toString(allocator);
    defer allocator.free(dump);
    try std.testing.expectEqualStrings("▁▅█\n", dump);
}

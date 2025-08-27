const std = @import("std");
const shared = @import("shared");
const render = shared.render;

test "memoryRendererPaintsAndProducesExpectedDumpPlusSpans" {
    const allocator = std.testing.allocator;
    var mr = try render.MemoryRenderer.init(allocator, 10, 3);
    defer mr.deinit();

    const spans = try mr.renderWith(struct {
        fn paint(p: *render.Painter) !void {
            try p.putChar(0, 0, 'A');
            try p.putChar(1, 0, 'B');
            try p.putChar(2, 0, 'C');
            try p.putChar(9, 2, 'Z');
        }
    }.paint);
    defer allocator.free(spans);

    // Check there are changed regions
    try std.testing.expect(spans.len >= 2);

    const dump = try mr.dump();
    defer allocator.free(dump);

    const expected =
        "ABC       \n" ++
        "          \n" ++
        "         Z\n";
    try std.testing.expectEqualStrings(expected, dump);
}

test "coalesceDirtySpansIntoVerticalRectangles" {
    const allocator = std.testing.allocator;
    const diff_surface = render.diff_surface;
    const coalesce = render.coalesceSpansToRects;

    var spans = [_]diff_surface.DirtySpan{
        .{ .y = 0, .x = 2, .len = 5 },
        .{ .y = 1, .x = 2, .len = 5 },
        .{ .y = 3, .x = 0, .len = 1 },
    };
    const rects = try coalesce(allocator, spans[0..]);
    defer allocator.free(rects);

    try std.testing.expect(rects.len == 2);
    var found = false;
    for (rects) |r| {
        if (r.x == 2 and r.y == 0 and r.w == 5 and r.h == 2) found = true;
    }
    try std.testing.expect(found);
}

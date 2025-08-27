const std = @import("std");
const diffSurface = @import("diff_surface.zig");

pub const Rect = struct { x: u32, y: u32, w: u32, h: u32 };

/// Coalesce line-based dirty spans into vertical rectangles where possible.
/// Strategy: for each span (y,x,len), attempt to extend downward as long as
/// the next row contains an identical span at the same x with same len.
/// Returns a list of non-overlapping rectangles covering all spans.
pub fn coalesceSpansToRects(
    allocator: std.mem.Allocator,
    spans: []const diffSurface.Span,
) ![]Rect {
    if (spans.len == 0) return &[_]Rect{};

    // Index spans by row for quick lookup
    var rows = std.AutoHashMap(u32, std.ArrayList(usize)).init(allocator);
    defer {
        var it = rows.valueIterator();
        while (it.next()) |lst| lst.deinit();
        rows.deinit();
    }
    for (spans, 0..) |s, idx| {
        const g = try rows.getOrPut(s.y);
        if (!g.found_existing) g.value_ptr.* = std.ArrayList(usize).init(allocator);
        try g.value_ptr.append(idx);
    }

    var consumed = try allocator.alloc(bool, spans.len);
    defer allocator.free(consumed);
    @memset(consumed, false);

    var rects = std.array_list.Managed(Rect).init(allocator);
    errdefer rects.deinit();

    // Helper to find a span with same x,len in a row
    const findInRow = struct {
        fn f(list: *const std.ArrayList(usize), spans_: []const diffSurface.Span, x: u32, len: u32, consumed_: []bool) ?usize {
            for (list.items) |idx| {
                if (!consumed_[idx]) {
                    const s = spans_[idx];
                    if (s.x == x and s.len == len) return idx;
                }
            }
            return null;
        }
    }.f;

    // Iterate in original order to preserve stability
    for (spans, 0..) |s, i| {
        if (consumed[i]) continue;
        var rect = Rect{ .x = s.x, .y = s.y, .w = s.len, .h = 1 };
        consumed[i] = true;

        // Try to extend downward
        var nextRow = s.y + 1;
        while (true) {
            const next = rows.get(nextRow) orelse break;
            const idxOpt = findInRow(next, spans, rect.x, rect.w, consumed);
            if (idxOpt) |idx| {
                consumed[idx] = true;
                rect.h += 1;
                nextRow += 1;
            } else break;
        }

        try rects.append(rect);
    }

    return rects.toOwnedSlice();
}

test "coalesce vertical spans into single rect" {
    const allocator = std.testing.allocator;
    const spans = [_]diffSurface.Span{
        .{ .y = 0, .x = 2, .len = 5 },
        .{ .y = 1, .x = 2, .len = 5 },
        .{ .y = 3, .x = 0, .len = 1 },
    };
    const rects = try coalesceSpansToRects(allocator, spans[0..]);
    defer allocator.free(rects);
    // Expect two rects, one with h=2 for the first two spans
    try std.testing.expect(rects.len == 2);
    // Find the rect at x=2, y=0
    var found = false;
    for (rects) |r| {
        if (r.x == 2 and r.y == 0 and r.w == 5 and r.h == 2) found = true;
    }
    try std.testing.expect(found);
}

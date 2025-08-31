const std = @import("std");
const surface_mod = @import("surface.zig");

pub const Span = struct { y: u32, x: u32, len: u32 };

/// Compute dirty spans between two equal-sized surfaces by comparing per-cell chars.
pub fn computeDirtySpans(
    allocator: std.mem.Allocator,
    a: *surface_mod.Surface,
    b: *surface_mod.Surface,
) ![]Span {
    const da = a.size();
    const db = b.size();
    if (da.w != db.w or da.h != db.h) return error.SizeMismatch;

    // Snapshot both surfaces to strings and compare line-wise.
    // Note: this is simple but sufficient for early tests; later, access raw cells directly.
    const snapA = try a.toString(allocator);
    defer allocator.free(snapA);
    const snapB = try b.toString(allocator);
    defer allocator.free(snapB);

    var spans = std.array_list.Managed(Span).init(allocator);
    errdefer spans.deinit();

    var offset: usize = 0;
    var y: u32 = 0;
    while (y < da.h) : (y += 1) {
        var x: u32 = 0;
        while (x < da.w) {
            const ia = offset + @as(usize, @intCast(x));
            const ca = snapA[ia];
            const cb = snapB[ia];
            if (ca != cb) {
                // start span
                const startX = x;
                var len: u32 = 0;
                while (x < da.w) : (x += 1) {
                    const j = offset + @as(usize, @intCast(x));
                    if (snapA[j] == snapB[j]) break;
                    len += 1;
                }
                try spans.append(.{ .y = y, .x = startX, .len = len });
            } else {
                x += 1;
            }
        }
        // skip newline at end of row
        offset += @as(usize, @intCast(da.w + 1));
    }

    return spans.toOwnedSlice();
}

test "computeDirtySpans detects changed spans line-wise" {
    const allocator = std.testing.allocator;
    var surfaceA = try surface_mod.MemorySurface.init(allocator, 5, 2);
    defer {
        surfaceA.deinit(allocator);
        allocator.destroy(surfaceA);
    }
    var surfaceB = try surface_mod.MemorySurface.init(allocator, 5, 2);
    defer {
        surfaceB.deinit(allocator);
        allocator.destroy(surfaceB);
    }

    // Make a difference: write 'X' at (1,0) and (4,1) in surfaceB
    try surfaceB.putChar(1, 0, 'X');
    try surfaceB.putChar(4, 1, 'Y');

    const spans = try computeDirtySpans(allocator, surfaceA, surfaceB);
    defer allocator.free(spans);
    // Expect two spans on two lines
    try std.testing.expect(spans.len >= 2);
}

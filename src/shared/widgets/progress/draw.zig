const std = @import("std");
const render = @import("../../render/mod.zig");
const ui = @import("../../ui/mod.zig");

/// Draw a single-line progress bar into the given rect.
/// Layout: optional label, space, then bar composed of '=' for filled and '-' for unfilled.
pub fn progress(ctx: *render.Context, rect: ui.layout.Rect, value: f32, label: ?[]const u8) !void {
    if (rect.w == 0 or rect.h == 0) return;
    var x: i32 = rect.x;
    const y: i32 = rect.y;

    if (label) |l| {
        var i: usize = 0;
        while (i < l.len and x < rect.x + @as(i32, @intCast(rect.w))) : (i += 1) {
            try ctx.putChar(x, y, l[i]);
            x += 1;
        }
        if (x < rect.x + @as(i32, @intCast(rect.w))) {
            try ctx.putChar(x, y, ' ');
            x += 1;
        }
    }

    // Remaining width for the bar
    const total: i32 = rect.x + @as(i32, @intCast(rect.w)) - x;
    if (total <= 0) return;
    const clamped = if (value < 0.0) 0.0 else if (value > 1.0) 1.0 else value;
    const filled: i32 = @intFromFloat(@floor(clamped * @as(f32, @floatFromInt(total)) + 0.5));

    var i32_i: i32 = 0;
    while (i32_i < total) : (i32_i += 1) {
        const ch: u21 = if (i32_i < filled) '=' else '-';
        try ctx.putChar(x + i32_i, y, ch);
    }
}

test "drawProgress with label clips and fills proportionally" {
    const allocator = std.testing.allocator;
    var surface = try render.MemorySurface.init(allocator, 12, 1);
    defer {
        surface.deinit(allocator);
        allocator.destroy(surface);
    }
    var ctx = render.Context.init(surface, null);
    try progress(&ctx, .{ .x = 0, .y = 0, .w = 12, .h = 1 }, 0.25, "P:");
    const dump = try surface.toString(allocator);
    defer allocator.free(dump);
    // Layout: "P:" + space + bar of width 9 with ~2-3 filled
    // With rounding, expect 2 filled in 9
    try std.testing.expectEqualStrings("P: ==-------\n", dump);
}

const std = @import("std");
const render = @import("../../render/mod.zig");

pub const Severity = enum { info, success, warning, @"error", debug, critical };

pub fn notification(ctx: *render.Context, rect: Rect, sev: Severity, title: []const u8, message: []const u8) !void {
    // Minimal paint: icon + title on first line; message on second (if fits)
    const icon = switch (sev) {
        .info => "i",
        .success => "+",
        .warning => "!",
        .@"error" => "x",
        .debug => "*",
        .critical => "#",
    };

    // line 0: [icon] space title
    var x: i32 = rect.x;
    var y: i32 = rect.y;
    if (rect.w == 0 or rect.h == 0) return;

    try writeClipped(ctx, rect, x, y, "[", 1);
    x += 1;
    try writeClipped(ctx, rect, x, y, icon, icon.len);
    x += @intCast(icon.len);
    try writeClipped(ctx, rect, x, y, "] ", 2);
    x += 2;
    try writeClipped(ctx, rect, x, y, title, title.len);

    // line 1: message (if there is vertical space)
    if (rect.h >= 2) {
        x = rect.x;
        y = rect.y + 1;
        try writeClipped(ctx, rect, x, y, message, message.len);
    }
}

pub const Rect = struct { x: i32, y: i32, w: u32, h: u32 };

fn writeClipped(ctx: *render.Context, rect: Rect, start_x: i32, start_y: i32, text: []const u8, len: usize) !void {
    var x = start_x;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (x >= rect.x + @as(i32, @intCast(rect.w))) break;
        if (x >= rect.x and start_y >= rect.y and start_y < rect.y + @as(i32, @intCast(rect.h))) {
            try ctx.putChar(x, start_y, text[i]);
        }
        x += 1;
    }
}

test "notification renderer draws icon, title, and message" {
    const allocator = std.testing.allocator;
    var surface = try render.MemorySurface.init(allocator, 20, 3);
    defer {
        surface.deinit(allocator);
        allocator.destroy(surface);
    }

    var ctx = render.Context.init(surface, null);

    const r = Rect{ .x = 0, .y = 0, .w = 20, .h = 3 };
    try notification(&ctx, r, .warning, "Title", "Message here");

    const dump = try surface.toString(allocator);
    defer allocator.free(dump);

    const expected =
        "[!] Title          \n" ++
        "Message here       \n" ++
        "                    \n";

    // Normalize lengths: our MemorySurface encodes spaces as ' '
    try std.testing.expectEqualStrings(expected, dump);
}

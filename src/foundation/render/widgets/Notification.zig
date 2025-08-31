const std = @import("std");
const Context = @import("../Context.zig");
const Surface = @import("../surface.zig");

pub const Severity = enum { info, success, warning, @"error", debug, critical };

pub fn notification(context: *Context, rectangle: Rectangle, severity: Severity, title: []const u8, message: []const u8) !void {
    // Minimal paint: icon + title on first line; message on second (if fits)
    const icon = switch (severity) {
        .info => "i",
        .success => "+",
        .warning => "!",
        .@"error" => "x",
        .debug => "*",
        .critical => "#",
    };

    // line 0: [icon] space title
    var x: i32 = rectangle.x;
    var y: i32 = rectangle.y;
    if (rectangle.w == 0 or rectangle.h == 0) return;

    try writeClipped(context, rectangle, x, y, "[", 1);
    x += 1;
    try writeClipped(context, rectangle, x, y, icon, icon.len);
    x += @intCast(icon.len);
    try writeClipped(context, rectangle, x, y, "] ", 2);
    x += 2;
    try writeClipped(context, rectangle, x, y, title, title.len);

    // line 1: message (if there is vertical space)
    if (rectangle.h >= 2) {
        x = rectangle.x;
        y = rectangle.y + 1;
        try writeClipped(context, rectangle, x, y, message, message.len);
    }
}

pub const Rectangle = struct { x: i32, y: i32, w: u32, h: u32 };
pub const Rect = Rectangle;

fn writeClipped(context: *Context, rectangle: Rectangle, startX: i32, startY: i32, text: []const u8, length: usize) !void {
    var x = startX;
    var textIndex: usize = 0;
    while (textIndex < length) : (textIndex += 1) {
        if (x >= rectangle.x + @as(i32, @intCast(rectangle.w))) break;
        if (x >= rectangle.x and startY >= rectangle.y and startY < rectangle.y + @as(i32, @intCast(rectangle.h))) {
            try context.putChar(x, startY, text[textIndex]);
        }
        x += 1;
    }
}

test "notification renderer draws icon, title, and message" {
    const allocator = std.testing.allocator;
    var surface = try Surface.MemorySurface.init(allocator, 20, 3);
    defer surface.deinit(allocator);

    var context = Context.init(surface, allocator);

    const rectangle = Rectangle{ .x = 0, .y = 0, .w = 20, .h = 3 };
    try notification(&context, rectangle, .warning, "Title", "Message here");

    const dump = try surface.toString(allocator);
    defer allocator.free(dump);

    const expected =
        "[!] Title          \n" ++
        "Message here       \n" ++
        "                    \n";

    // Normalize lengths: our MemorySurface encodes spaces as ' '
    try std.testing.expectEqualStrings(expected, dump);
}

const std = @import("std");
const Surface = @import("surface.zig").Surface;

const Self = @This();

surface: *Surface,
allocator: std.mem.Allocator,

pub fn init(surface: *Surface, allocator: std.mem.Allocator) Self {
    return .{
        .surface = surface,
        .allocator = allocator,
    };
}

pub fn putChar(self: *Self, x: i32, y: i32, ch: u21) !void {
    return self.surface.putChar(x, y, ch);
}

pub fn size(self: *const Self) Surface.Dim {
    return self.surface.size();
}

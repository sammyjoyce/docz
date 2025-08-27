const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var list: std.ArrayList(u8) = .init(allocator);
    defer list.deinit();

    try list.appendSlice("test");
    const writer = list.writer();
    try writer.writeAll(" works");

    std.debug.print("ArrayList: {s}\n", .{list.items});
}

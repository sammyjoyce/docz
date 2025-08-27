const std = @import("std");

test "arrayList basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var list: std.ArrayList(u8) = .init(allocator);
    defer list.deinit();

    try list.appendSlice("test");
    const writer = list.writer();
    try writer.writeAll(" works");

    try std.testing.expectEqualSlices(u8, "test works", list.items);
}

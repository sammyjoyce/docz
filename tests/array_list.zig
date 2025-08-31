const std = @import("std");

test "arrayListFunctionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var list = std.ArrayList(u8){};
    defer list.deinit(allocator);

    try list.appendSlice(allocator, "test");
    const writer = list.writer(allocator);
    try writer.writeAll(" works");

    try std.testing.expectEqualSlices(u8, "test works", list.items);
}

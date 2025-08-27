const std = @import("std");

 test "arrayListInitMethods" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test different ArrayList initialization methods

    // Method 1
    var list1 = std.ArrayList(u8).init(allocator);
    defer list1.deinit();

    // Method 2
    var list2: std.ArrayList(u8) = undefined;
    list2 = std.ArrayList(u8).init(allocator);
    defer list2.deinit();

    // Verify both methods work
    try std.testing.expect(list1.capacity == 0);
    try std.testing.expect(list2.capacity == 0);
}

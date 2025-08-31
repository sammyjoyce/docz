const std = @import("std");

test "arrayListInitMethods" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test different ArrayList initialization methods

    // Method 1
    var list1 = std.ArrayList(u8){};
    defer list1.deinit(allocator);

    // Method 2
    var list2: std.ArrayList(u8) = undefined;
    list2 = std.ArrayList(u8){};
    defer list2.deinit(allocator);

    // Verify both methods work
    try std.testing.expect(list1.capacity == 0);
    try std.testing.expect(list2.capacity == 0);
}

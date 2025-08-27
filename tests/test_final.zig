const std = @import("std");

pub fn main() !void {
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

    std.debug.print("ArrayList init works\n", .{});
}

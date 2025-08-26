const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const allocator = std.testing.allocator;

const table = @import("src/markdown_agent/common/table.zig");

test "table validation - basic functionality" {
    // Create a simple table
    const headers = [_][]const u8{ "Name", "Age" };
    const row1 = [_][]const u8{ "John", "25" };
    const rows = [_][]const []const u8{&row1};
    const alignments = [_]table.Alignment{ .left, .right };
    
    var test_table = try table.createTable(allocator, &headers, &rows, &alignments);
    defer test_table.deinit(allocator);
    
    const config = table.ValidationConfig{};
    var result = try table.validateTable(allocator, &test_table, config);
    defer result.deinit(allocator);
    
    try expect(result.is_valid);
    try expectEqual(@as(usize, 0), result.issues.len);
}

test "table repair - basic functionality" {
    // Create a table with alignment mismatch - first create it normally, then modify alignments
    const headers = [_][]const u8{ "Name", "Age", "City" };
    const row1 = [_][]const u8{ "John", "25", "NYC" };
    const rows = [_][]const []const u8{&row1};
    const alignments = [_]table.Alignment{ .left, .right, .left }; // Proper alignments first
    
    var test_table = try table.createTable(allocator, &headers, &rows, &alignments);
    defer test_table.deinit(allocator);
    
    // Now artificially create a mismatched alignment array to test repair
    allocator.free(test_table.alignments);
    test_table.alignments = try allocator.alloc(table.Alignment, 2); // Wrong size
    test_table.alignments[0] = .left;
    test_table.alignments[1] = .right;
    
    const config = table.RepairConfig{ .normalize_alignments = true };
    
    const repairs_made = try table.repairTable(allocator, &test_table, config);
    try expect(repairs_made > 0);
    
    // Verify alignments were normalized
    try expectEqual(@as(usize, 3), test_table.alignments.len);
}
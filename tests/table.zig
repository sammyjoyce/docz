const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const allocator = std.testing.allocator;

const table = @import("agents/markdown/lib/table.zig");

  test "tableValidation" {
    // Create a table
    const headers = [_][]const u8{ "Name", "Age" };
    const row1 = [_][]const u8{ "John", "25" };
    const rows = [_][]const []const u8{&row1};
    const alignments = [_]table.Alignment{ .left, .right };

    var testTable = try table.createTable(allocator, &headers, &rows, &alignments);
    defer testTable.deinit(allocator);

    const config = table.ValidationConfig{};
    var result = try table.validateTable(allocator, &testTable, config);
    defer result.deinit(allocator);

    try expect(result.is_valid);
    try expectEqual(@as(usize, 0), result.issues.len);
}

  test "tableRepair" {
    // Create a table with alignment mismatch - first create it normally, then modify alignments
    const headers = [_][]const u8{ "Name", "Age", "City" };
    const row1 = [_][]const u8{ "John", "25", "NYC" };
    const rows = [_][]const []const u8{&row1};
    const alignments = [_]table.Alignment{ .left, .right, .left }; // Correct alignments first

    var testTable = try table.createTable(allocator, &headers, &rows, &alignments);
    defer testTable.deinit(allocator);

    // Now artificially create a mismatched alignment array to test repair
    allocator.free(testTable.alignments);
    testTable.alignments = try allocator.alloc(table.Alignment, 2); // Wrong size
    testTable.alignments[0] = .left;
    testTable.alignments[1] = .right;

    const config = table.RepairConfig{ .normalize_alignments = true };

    const repairsMade = try table.repairTable(allocator, &testTable, config);
    try expect(repairsMade > 0);

    // Verify alignments were normalized
    try expectEqual(@as(usize, 3), testTable.alignments.len);
}

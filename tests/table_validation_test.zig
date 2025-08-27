const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectError = std.testing.expectError;
const allocator = std.testing.allocator;

const table = @import("agents/markdown/common/table.zig");

test "table validation - valid table passes validation" {
    // Create a well-formed table
    const headers = [_][]const u8{ "Name", "Age", "City" };
    const row1 = [_][]const u8{ "John", "25", "NYC" };
    const row2 = [_][]const u8{ "Jane", "30", "LA" };
    const rows = [_][]const []const u8{ &row1, &row2 };
    const alignments = [_]table.Alignment{ .left, .center, .right };

    var testTable = try table.createTable(allocator, &headers, &rows, &alignments);
    defer testTable.deinit(allocator);

    const config = table.ValidationConfig{};
    var result = try table.validateTable(allocator, &testTable, config);
    defer result.deinit(allocator);

    try expect(result.is_valid);
    try expectEqual(@as(usize, 0), result.issues.len);
}

test "table validation - detects inconsistent column count" {
    // Create a table with inconsistent column counts
    const headers = [_][]const u8{ "Name", "Age", "City" };
    const row1 = [_][]const u8{ "John", "25" }; // Missing city
    const row2 = [_][]const u8{ "Jane", "30", "LA", "Extra" }; // Extra column
    const rows = [_][]const []const u8{ &row1, &row2 };
    const alignments = [_]table.Alignment{ .left, .center, .right };

    var testTable = try table.createTable(allocator, &headers, &rows, &alignments);
    defer testTable.deinit(allocator);

    const config = table.ValidationConfig{};
    var result = try table.validateTable(allocator, &testTable, config);
    defer result.deinit(allocator);

    try expect(!result.is_valid);
    try expect(result.issues.len >= 2); // Should detect both row issues

    // Check that column consistency issues are detected
    var foundConsistencyIssues = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .inconsistent_column_count) {
            foundConsistencyIssues = true;
            break;
        }
    }
    try expect(foundConsistencyIssues);
}

test "table validation - detects empty cells" {
    // Create a table with empty cells
    const headers = [_][]const u8{ "Name", "Age", "City" };
    const row1 = [_][]const u8{ "John", "", "NYC" }; // Empty age
    const row2 = [_][]const u8{ "", "30", "" }; // Empty name and city
    const rows = [_][]const []const u8{ &row1, &row2 };
    const alignments = [_]table.Alignment{ .left, .center, .right };

    var testTable = try table.createTable(allocator, &headers, &rows, &alignments);
    defer testTable.deinit(allocator);

    const config = table.ValidationConfig{ .check_empty_cells = true };
    var result = try table.validateTable(allocator, &testTable, config);
    defer result.deinit(allocator);

    try expect(result.is_valid); // Empty cells are warnings, not errors
    try expect(result.issues.len >= 3); // Should detect 3 empty cells

    // Check that empty cell issues are detected
    var foundEmptyCellIssues = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .empty_cells) {
            foundEmptyCellIssues = true;
            break;
        }
    }
    try expect(foundEmptyCellIssues);
}

test "table validation - detects alignment mismatch" {
    // Create a table with mismatched alignment count
    const headers = [_][]const u8{ "Name", "Age", "City" };
    const row1 = [_][]const u8{ "John", "25", "NYC" };
    const rows = [_][]const []const u8{&row1};
    const alignments = [_]table.Alignment{ .left, .center }; // Only 2 alignments for 3 columns

    var testTable = try table.createTable(allocator, &headers, &rows, &alignments);
    defer testTable.deinit(allocator);

    const config = table.ValidationConfig{};
    var result = try table.validateTable(allocator, &testTable, config);
    defer result.deinit(allocator);

    try expect(!result.is_valid);

    // Check that alignment issue is detected
    var foundAlignmentIssue = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .invalid_alignment) {
            foundAlignmentIssue = true;
            break;
        }
    }
    try expect(foundAlignmentIssue);
}

test "table repair - fixes column consistency" {
    // Create a table with inconsistent column counts
    const headers = [_][]const u8{ "Name", "Age", "City" };
    const row1 = [_][]const u8{ "John", "25" }; // Missing city
    const row2 = [_][]const u8{ "Jane", "30", "LA", "Extra" }; // Extra column
    const rows = [_][]const []const u8{ &row1, &row2 };
    const alignments = [_]table.Alignment{ .left, .center, .right };

    var testTable = try table.createTable(allocator, &headers, &rows, &alignments);
    defer testTable.deinit(allocator);

    const config = table.RepairConfig{
        .fix_column_consistency = true,
        .empty_cell_placeholder = "-",
    };

    const repairs_made = try table.repairTable(allocator, &testTable, config);
    try expect(repairs_made > 0);

    // Verify all rows now have correct column count
    try expectEqual(@as(usize, 3), testTable.headers.len);
    for (testTable.rows) |row| {
        try expectEqual(@as(usize, 3), row.len);
    }

    // Check that missing cell was filled with placeholder
    try expectEqualSlices(u8, "-", testTable.rows[0][2]); // Should be placeholder for missing city
}

test "table repair - trims whitespace" {
    // Create a table with excessive whitespace
    const headers = [_][]const u8{ "  Name  ", "Age", " City " };
    const row1 = [_][]const u8{ " John ", "  25  ", "NYC  " };
    const rows = [_][]const []const u8{&row1};
    const alignments = [_]table.Alignment{ .left, .center, .right };

    var testTable = try table.createTable(allocator, &headers, &rows, &alignments);
    defer testTable.deinit(allocator);

    const config = table.RepairConfig{
        .trim_whitespace = true,
    };

    const repairs_made = try table.repairTable(allocator, &testTable, config);
    try expect(repairs_made > 0);

    // Verify whitespace was trimmed
    try expectEqualSlices(u8, "Name", testTable.headers[0]);
    try expectEqualSlices(u8, "City", testTable.headers[2]);
    try expectEqualSlices(u8, "John", testTable.rows[0][0]);
    try expectEqualSlices(u8, "25", testTable.rows[0][1]);
    try expectEqualSlices(u8, "NYC", testTable.rows[0][2]);
}

test "table repair - fills empty cells" {
    // Create a table with empty cells
    const headers = [_][]const u8{ "Name", "Age", "City" };
    const row1 = [_][]const u8{ "John", "", "NYC" }; // Empty age
    const row2 = [_][]const u8{ "", "30", "" }; // Empty name and city
    const rows = [_][]const []const u8{ &row1, &row2 };
    const alignments = [_]table.Alignment{ .left, .center, .right };

    var testTable = try table.createTable(allocator, &headers, &rows, &alignments);
    defer testTable.deinit(allocator);

    const config = table.RepairConfig{
        .fill_empty_cells = true,
        .empty_cell_placeholder = "N/A",
    };

    const repairs_made = try table.repairTable(allocator, &testTable, config);
    try expect(repairs_made > 0);

    // Verify empty cells were filled
    try expectEqualSlices(u8, "N/A", testTable.rows[0][1]); // Age should be N/A
    try expectEqualSlices(u8, "N/A", testTable.rows[1][0]); // Name should be N/A
    try expectEqualSlices(u8, "N/A", testTable.rows[1][2]); // City should be N/A
}

test "table repair - normalizes alignments" {
    // Create a table with mismatched alignment count
    const headers = [_][]const u8{ "Name", "Age", "City" };
    const row1 = [_][]const u8{ "John", "25", "NYC" };
    const rows = [_][]const []const u8{&row1};
    const alignments = [_]table.Alignment{ .left, .center }; // Only 2 alignments for 3 columns

    var testTable = try table.createTable(allocator, &headers, &rows, &alignments);
    defer testTable.deinit(allocator);

    const config = table.RepairConfig{
        .normalize_alignments = true,
    };

    const repairs_made = try table.repairTable(allocator, &testTable, config);
    try expect(repairs_made > 0);

    // Verify alignments were normalized
    try expectEqual(@as(usize, 3), testTable.alignments.len);
    try expectEqual(table.Alignment.left, testTable.alignments[0]);
    try expectEqual(table.Alignment.center, testTable.alignments[1]);
    try expectEqual(table.Alignment.left, testTable.alignments[2]); // Should default to left
}

test "table validate and repair combined" {
    // Create a problematic table
    const headers = [_][]const u8{ "  Name  ", "Age", "City" };
    const row1 = [_][]const u8{ " John ", "25" }; // Missing city, extra whitespace
    const row2 = [_][]const u8{ "", "30", "LA", "Extra" }; // Empty name, extra column
    const rows = [_][]const []const u8{ &row1, &row2 };
    const alignments = [_]table.Alignment{ .left, .center }; // Missing alignment

    var testTable = try table.createTable(allocator, &headers, &rows, &alignments);
    defer testTable.deinit(allocator);

    const validation_config = table.ValidationConfig{};
    const repair_config = table.RepairConfig{
        .fix_column_consistency = true,
        .trim_whitespace = true,
        .fill_empty_cells = true,
        .empty_cell_placeholder = "N/A",
        .normalize_alignments = true,
    };

    // First, validate to see issues
    var initialResult = try table.validateTable(allocator, &testTable, validation_config);
    defer initialResult.deinit(allocator);

    try expect(!initialResult.is_valid);
    try expect(initialResult.issues.len > 0);

    // Perform combined validate and repair
    var combinedResult = try table.validateAndRepairTable(allocator, &testTable, validation_config, repair_config);
    defer combinedResult[0].deinit(allocator);

    const finalValidation = combinedResult[0];
    const repairsMade = combinedResult[1];

    try expect(repairsMade > 0);
    try expect(finalValidation.is_valid or finalValidation.issues.len < initialResult.issues.len);

    // Verify table structure is fixed
    try expectEqual(@as(usize, 3), testTable.headers.len);
    try expectEqual(@as(usize, 3), testTable.alignments.len);
    for (testTable.rows) |row| {
        try expectEqual(@as(usize, 3), row.len);
    }

    // Verify headers were trimmed
    try expectEqualSlices(u8, "Name", testTable.headers[0]);

    // Verify empty cells were filled
    try expectEqualSlices(u8, "N/A", testTable.rows[1][0]); // Empty name should be N/A
}

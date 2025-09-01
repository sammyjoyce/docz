//! Unit tests for Markdown agent JSON tools

const std = @import("std");
const testing = std.testing;
const tools = @import("../agents/markdown/tools/io.zig");

test "io tool - read_file success" {
    const allocator = testing.allocator;

    // Create test file
    const test_path = "test_markdown.md";
    const test_content = "# Test\nContent";
    try std.fs.cwd().writeFile(test_path, test_content);
    defer std.fs.cwd().deleteFile(test_path) catch {};

    // Create request
    var request = std.json.ObjectMap.init(allocator);
    defer request.deinit();
    try request.put("command", .{ .string = "read_file" });
    try request.put("file_path", .{ .string = test_path });

    const params = std.json.Value{ .object = request };

    // Execute tool
    const result = try tools.execute(allocator, params);
    defer if (result == .object) result.object.deinit();

    // Verify response
    try testing.expect(result == .object);
    const success = result.object.get("success");
    try testing.expect(success != null);
    try testing.expect(success.?.bool == true);
}

test "io tool - missing command" {
    const allocator = testing.allocator;

    var request = std.json.ObjectMap.init(allocator);
    defer request.deinit();

    const params = std.json.Value{ .object = request };

    // Should return error response
    const result = tools.execute(allocator, params) catch |err| {
        try testing.expect(err == tools.Error.MissingCommand);
        return;
    };
    _ = result;
    return error.TestExpectedError;
}

test "validate tool - basic validation" {
    const allocator = testing.allocator;
    const validate = @import("../agents/markdown/tools/validate.zig");

    var request = std.json.ObjectMap.init(allocator);
    defer request.deinit();
    try request.put("command", .{ .string = "validate_links" });
    try request.put("content", .{ .string = "[test](http://example.com)" });

    const params = std.json.Value{ .object = request };

    const result = try validate.execute(allocator, params);
    defer if (result == .object) result.object.deinit();

    try testing.expect(result == .object);
}

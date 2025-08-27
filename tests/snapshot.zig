const std = @import("std");
const testing = std.testing;
const snapshot = @import("../src/shared/testing/snapshot.zig");

test "snapshot example - basic text" {
    const allocator = testing.allocator;

    // Simple text content
    const content =
        \\Hello, World!
        \\This is a snapshot test.
        \\Line 3 with some content.
    ;

    // Compare with snapshot
    const result = try snapshot.expectSnapshot(allocator, "example_basic", content);
    try snapshot.expectSnapshotPass(result);
}

test "snapshotExampleAnsiColoredText" {
    const allocator = testing.allocator;

    // Content with ANSI escape sequences
    const content =
        \\┌─ Title ─┐
        \\│ \x1b[31mRed\x1b[0m text │
        \\│ \x1b[32mGreen\x1b[0m text│
        \\└─────────┘
    ;

    const result = try snapshot.expectSnapshot(allocator, "example_ansi", content);
    try snapshot.expectSnapshotPass(result);
}

test "snapshotExampleTuiComponentOutput" {
    const allocator = testing.allocator;

    // Simulate TUI component output
    const output = try snapshot.captureOutput(allocator, struct {
        fn renderComponent(writer: anytype) !void {
            try writer.writeAll("┌─ Component ─┐\n");
            try writer.writeAll("│ Status: OK  │\n");
            try writer.writeAll("│ Progress:   │\n");
            try writer.writeAll("│ ████████░░ │\n");
            try writer.writeAll("└─────────────┘\n");
        }
    }.renderComponent, .{});

    defer allocator.free(output);

    const result = try snapshot.expectSnapshot(allocator, "example_tui", output);
    try snapshot.expectSnapshotPass(result);
}

test "snapshotExampleUsingTestTerminal" {
    const allocator = testing.allocator;

    // Use TestTerminal for more complex scenarios
    const output = try snapshot.withTestTerminal(allocator, struct {
        fn testFunction(terminal: *snapshot.TestTerminal) !void {
            const writer = terminal.writer();
            try writer.writeAll("Header\n");
            try writer.writeAll("======\n");
            try writer.writeAll("\n");
            try writer.writeAll("This is a test with\n");
            try writer.writeAll("multiple lines and\n");
            try writer.writeAll("various content.\n");
        }
    }.testFunction);

    defer allocator.free(output);

    const result = try snapshot.expectSnapshot(allocator, "example_terminal", output);
    try snapshot.expectSnapshotPass(result);
}

test "snapshot example - custom config" {
    const allocator = testing.allocator;

    // Create tester with custom configuration
    const config = snapshot.SnapshotConfig{
        .preserve_ansi = false, // Strip ANSI sequences
        .normalize_line_endings = true,
        .trim_trailing_whitespace = true,
    };

    var tester = try snapshot.SnapshotTester.init(allocator, config);
    defer tester.deinit();

    const content =
        \\Line with trailing spaces   \x1b[31m
        \\Another line\x1b[0m
        \\
    ;

    const result = try tester.expectSnapshot("example_config", content);
    try snapshot.expectSnapshotPass(result);
}
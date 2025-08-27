//! Snapshot Testing Framework for TUI Components
//!
//! This module provides comprehensive snapshot testing capabilities for terminal
//! user interface components. It supports capturing output, comparing with saved
//! snapshots, and generating diffs for mismatches.
//!
//! Features:
//! - Capture TUI/CLI output to strings
//! - Save snapshots to files (tests/snapshots/)
//! - Compare current output with saved snapshots
//! - Update mode to regenerate snapshots
//! - Diff display for mismatches
//! - ANSI escape sequence handling
//! - Environment variable control (UPDATE_SNAPSHOTS=1)

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const fs = std.fs;
const mem = std.mem;
const fmt = std.fmt;
const process = std.process;

/// Configuration for snapshot testing behavior
pub const SnapshotConfig = struct {
    /// Directory where snapshots are stored (relative to project root)
    snapshot_dir: []const u8 = "tests/snapshots",

    /// Whether to preserve ANSI escape sequences in snapshots
    preserve_ansi: bool = true,

    /// Whether to normalize line endings (convert \r\n to \n)
    normalize_line_endings: bool = true,

    /// Whether to trim trailing whitespace from lines
    trim_trailing_whitespace: bool = true,

    /// File extension for snapshot files
    file_extension: []const u8 = ".txt",

    /// Whether to use colored diff output
    use_color: bool = true,
};

/// Errors that can occur during snapshot operations
pub const SnapshotError = error{
    /// Snapshot file not found
    SnapshotNotFound,

    /// Failed to read snapshot file
    ReadFailed,

    /// Failed to write snapshot file
    WriteFailed,

    /// Snapshot mismatch
    Mismatch,

    /// Invalid snapshot name
    InvalidName,

    /// Directory creation failed
    DirCreateFailed,

    /// Environment variable error
    EnvVarError,
};

/// Result of a snapshot comparison
pub const SnapshotResult = union(enum) {
    /// Snapshot matches
    pass: void,

    /// Snapshot mismatch with diff information
    fail: struct {
        /// Expected content (from snapshot file)
        expected: []const u8,

        /// Actual content (from test)
        actual: []const u8,

        /// Formatted diff
        diff: []const u8,
    },

    /// Snapshot created (for new snapshots)
    created: []const u8,

    /// Snapshot updated
    updated: []const u8,
};

/// Test terminal for capturing TUI output
pub const TestTerminal = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    /// Create a new test terminal
    pub fn init(allocator: std.mem.Allocator) !TestTerminal {
        const buffer = std.ArrayList(u8).init(allocator);
        return TestTerminal{
            .allocator = allocator,
            .buffer = buffer,
        };
    }

    /// Deinitialize the test terminal
    pub fn deinit(self: *TestTerminal) void {
        self.buffer.deinit();
    }

    /// Get the captured output as a string
    pub fn getOutput(self: *TestTerminal) []const u8 {
        return self.buffer.items;
    }

    /// Clear the captured output
    pub fn clear(self: *TestTerminal) void {
        self.buffer.clearRetainingCapacity();
    }

    /// Get a writer for capturing output
    pub fn writer(self: *TestTerminal) std.ArrayList(u8).Writer {
        return self.buffer.writer();
    }

    /// Write raw bytes to the terminal
    pub fn write(self: *TestTerminal, bytes: []const u8) !usize {
        return try self.writer.write(bytes);
    }

    /// Write a formatted string to the terminal
    pub fn writeFmt(self: *TestTerminal, comptime format: []const u8, args: anytype) !void {
        try self.writer.print(format, args);
    }
};

/// Main snapshot testing API
pub const SnapshotTester = struct {
    allocator: std.mem.Allocator,
    config: SnapshotConfig,
    update_mode: bool,

    /// Create a new snapshot tester
    pub fn init(allocator: std.mem.Allocator, config: SnapshotConfig) !SnapshotTester {
        const update_mode = try shouldUpdateSnapshots();
        return SnapshotTester{
            .allocator = allocator,
            .config = config,
            .update_mode = update_mode,
        };
    }

    /// Compare actual output with a saved snapshot
    pub fn expectSnapshot(
        self: *SnapshotTester,
        test_name: []const u8,
        actual: []const u8,
    ) !SnapshotResult {
        const snapshot_path = try self.getSnapshotPath(test_name);

        // Normalize the actual content
        const normalized_actual = try self.normalizeContent(actual);
        defer self.allocator.free(normalized_actual);

        // Check if snapshot exists
        const snapshot_exists = fs.accessAbsolute(snapshot_path, .{}) catch false;

        if (!snapshot_exists) {
            if (self.update_mode) {
                // Create new snapshot
                try self.saveSnapshot(snapshot_path, normalized_actual);
                return SnapshotResult{ .created = try self.allocator.dupe(u8, snapshot_path) };
            } else {
                return SnapshotError.SnapshotNotFound;
            }
        }

        // Read existing snapshot
        const expected = try fs.selfExePathAlloc(self.allocator, snapshot_path);
        defer self.allocator.free(expected);
        const expected_content = try fs.readFileAlloc(self.allocator, expected, std.math.maxInt(usize));
        defer self.allocator.free(expected_content);

        // Normalize expected content
        const normalized_expected = try self.normalizeContent(expected_content);
        defer self.allocator.free(normalized_expected);

        // Compare contents
        if (mem.eql(u8, normalized_actual, normalized_expected)) {
            return SnapshotResult.pass;
        }

        if (self.update_mode) {
            // Update snapshot
            try self.saveSnapshot(snapshot_path, normalized_actual);
            return SnapshotResult{ .updated = try self.allocator.dupe(u8, snapshot_path) };
        }

        // Generate diff and return failure
        const diff = try self.generateDiff(normalized_expected, normalized_actual);
        return SnapshotResult{
            .fail = .{
                .expected = try self.allocator.dupe(u8, normalized_expected),
                .actual = try self.allocator.dupe(u8, normalized_actual),
                .diff = diff,
            },
        };
    }

    /// Update or create a snapshot
    pub fn updateSnapshot(
        self: *SnapshotTester,
        test_name: []const u8,
        content: []const u8,
    ) ![]const u8 {
        const snapshot_path = try self.getSnapshotPath(test_name);
        const normalized_content = try self.normalizeContent(content);
        defer self.allocator.free(normalized_content);

        try self.saveSnapshot(snapshot_path, normalized_content);
        return try self.allocator.dupe(u8, snapshot_path);
    }

    /// Get the full path for a snapshot file
    fn getSnapshotPath(self: *SnapshotTester, test_name: []const u8) ![]const u8 {
        // Sanitize test name for filename
        const sanitized_name = try self.sanitizeTestName(test_name);
        defer self.allocator.free(sanitized_name);

        // Build full path
        const path = try fs.path.join(self.allocator, &[_][]const u8{
            self.config.snapshot_dir,
            sanitized_name,
        });
        defer self.allocator.free(path);

        const full_path = try fmt.allocPrint(self.allocator, "{s}{s}", .{
            path,
            self.config.file_extension,
        });

        return full_path;
    }

    /// Sanitize test name for use as filename
    fn sanitizeTestName(self: *SnapshotTester, name: []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        for (name) |c| {
            switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9', '_', '-' => try result.append(c),
                ' ' => try result.append('_'),
                else => {
                    // Convert other characters to hex
                    try result.writer().print("_{x}", .{c});
                },
            }
        }

        return result.toOwnedSlice();
    }

    /// Normalize content according to configuration
    fn normalizeContent(self: *SnapshotTester, content: []const u8) ![]const u8 {
        var result = try self.allocator.dupe(u8, content);

        // Strip ANSI sequences if not preserving
        if (!self.config.preserve_ansi) {
            result = try self.stripAnsiSequences(result);
        }

        // Normalize line endings
        if (self.config.normalize_line_endings) {
            result = try self.normalizeLineEndings(result);
        }

        // Trim trailing whitespace
        if (self.config.trim_trailing_whitespace) {
            result = try self.trimTrailingWhitespace(result);
        }

        return result;
    }

    /// Strip ANSI escape sequences from content
    fn stripAnsiSequences(self: *SnapshotTester, content: []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var i: usize = 0;
        while (i < content.len) {
            if (content[i] == '\x1b' and i + 1 < content.len and content[i + 1] == '[') {
                // Skip ANSI escape sequence
                i += 2;
                while (i < content.len and content[i] != 'm') {
                    i += 1;
                }
                if (i < content.len) i += 1; // Skip the 'm'
            } else {
                try result.append(content[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice();
    }

    /// Normalize line endings to LF
    fn normalizeLineEndings(self: *SnapshotTester, content: []const u8) ![]const u8 {
        return try std.mem.replaceOwned(u8, self.allocator, content, "\r\n", "\n");
    }

    /// Trim trailing whitespace from each line
    fn trimTrailingWhitespace(self: *SnapshotTester, content: []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var lines = mem.split(u8, content, "\n");
        var first = true;

        while (lines.next()) |line| {
            if (!first) try result.append('\n');
            first = false;

            // Trim trailing whitespace
            const trimmed = mem.trimRight(u8, line, &std.ascii.whitespace);
            try result.appendSlice(trimmed);
        }

        return result.toOwnedSlice();
    }

    /// Save content to snapshot file
    fn saveSnapshot(self: *SnapshotTester, path: []const u8, content: []const u8) !void {
        _ = self; // Mark self as used

        // Ensure directory exists
        const dir_path = fs.path.dirname(path) orelse return SnapshotError.InvalidName;
        try fs.cwd().makePath(dir_path);

        // Write file
        try fs.cwd().writeFile(path, content);
    }

    /// Generate a diff between expected and actual content
    fn generateDiff(self: *SnapshotTester, expected: []const u8, actual: []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        const writer = result.writer();

        if (self.config.use_color) {
            try writer.writeAll("\n\x1b[31m--- Expected\x1b[0m\n");
            try writer.writeAll("\n\x1b[32m+++ Actual\x1b[0m\n");
        } else {
            try writer.writeAll("\n--- Expected\n");
            try writer.writeAll("\n+++ Actual\n");
        }

        try writer.writeAll("\n@@ Diff @@\n\n");

        // Simple line-by-line diff
        var expected_lines = mem.split(u8, expected, "\n");
        var actual_lines = mem.split(u8, actual, "\n");

        var expected_line = expected_lines.next();
        var actual_line = actual_lines.next();
        var line_num: usize = 1;

        while (expected_line != null or actual_line != null) {
            const has_expected = expected_line != null;
            const has_actual = actual_line != null;

            if (has_expected and has_actual) {
                if (mem.eql(u8, expected_line.?, actual_line.?)) {
                    // Lines match
                    try writer.print("  {d: >4} | {s}\n", .{ line_num, expected_line.? });
                } else {
                    // Lines differ
                    if (self.config.use_color) {
                        try writer.print("\x1b[31m- {d: >4} | {s}\x1b[0m\n", .{ line_num, expected_line.? });
                        try writer.print("\x1b[32m+ {d: >4} | {s}\x1b[0m\n", .{ line_num, actual_line.? });
                    } else {
                        try writer.print("- {d: >4} | {s}\n", .{ line_num, expected_line.? });
                        try writer.print("+ {d: >4} | {s}\n", .{ line_num, actual_line.? });
                    }
                }
            } else if (has_expected) {
                // Line only in expected
                if (self.config.use_color) {
                    try writer.print("\x1b[31m- {d: >4} | {s}\x1b[0m\n", .{ line_num, expected_line.? });
                } else {
                    try writer.print("- {d: >4} | {s}\n", .{ line_num, expected_line.? });
                }
            } else if (has_actual) {
                // Line only in actual
                if (self.config.use_color) {
                    try writer.print("\x1b[32m+ {d: >4} | {s}\x1b[0m\n", .{ line_num, actual_line.? });
                } else {
                    try writer.print("+ {d: >4} | {s}\n", .{ line_num, actual_line.? });
                }
            }

            if (expected_line != null) expected_line = expected_lines.next();
            if (actual_line != null) actual_line = actual_lines.next();
            line_num += 1;
        }

        return result.toOwnedSlice();
    }
};

/// Check if snapshots should be updated based on environment variable
fn shouldUpdateSnapshots() !bool {
    const env_var = process.getEnvVarOwned(testing.allocator, "UPDATE_SNAPSHOTS") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return false,
        else => return SnapshotError.EnvVarError,
    };
    defer testing.allocator.free(env_var);

    return mem.eql(u8, env_var, "1") or mem.eql(u8, env_var, "true");
}

/// Convenience function to create a snapshot tester with default config
pub fn createTester(allocator: std.mem.Allocator) !SnapshotTester {
    return try SnapshotTester.init(allocator, SnapshotConfig{});
}

/// Convenience function for expectSnapshot with default config
pub fn expectSnapshot(
    allocator: std.mem.Allocator,
    test_name: []const u8,
    actual: []const u8,
) !SnapshotResult {
    var tester = try createTester(allocator);
    return try tester.expectSnapshot(test_name, actual);
}

/// Convenience function for updateSnapshot with default config
pub fn updateSnapshot(
    allocator: std.mem.Allocator,
    test_name: []const u8,
    content: []const u8,
) ![]const u8 {
    var tester = try createTester(allocator);
    return try tester.updateSnapshot(test_name, content);
}

// ============================================================================
// TEST HELPERS
// ============================================================================

/// Helper for testing TUI components that render to a writer
pub fn captureOutput(
    allocator: std.mem.Allocator,
    comptime renderFn: anytype,
    args: anytype,
) ![]const u8 {
    var terminal = try TestTerminal.init(allocator);
    defer terminal.deinit();

    try @call(.auto, renderFn, .{terminal.writer()} ++ args);

    return try allocator.dupe(u8, terminal.getOutput());
}

/// Helper for testing components with a test terminal
pub fn withTestTerminal(
    allocator: std.mem.Allocator,
    comptime testFn: fn(*TestTerminal) anyerror!void,
) ![]const u8 {
    var terminal = try TestTerminal.init(allocator);
    defer terminal.deinit();

    // Call the test function with the terminal
    try testFn(&terminal);

    return try allocator.dupe(u8, terminal.getOutput());
}

// ============================================================================
// INTEGRATION WITH STD TESTING
// ============================================================================

/// Integration with std.testing.expect for snapshot results
pub fn expectSnapshotPass(result: SnapshotResult) !void {
    switch (result) {
        .pass => return,
        .created => |path| {
            std.debug.print("Snapshot created: {s}\n", .{path});
            return;
        },
        .updated => |path| {
            std.debug.print("Snapshot updated: {s}\n", .{path});
            return;
        },
        .fail => |fail| {
            std.debug.print("Snapshot mismatch:\n{s}\n", .{fail.diff});
            return error.TestExpectedEqual;
        },
    }
}

test "snapshot basic functionality" {
    const allocator = testing.allocator;

    // Test basic snapshot creation and matching
    const content = "Hello, World!\nThis is a test.";
    const result = try expectSnapshot(allocator, "basic_test", content);

    switch (result) {
        .pass, .created, .updated => {},
        .fail => return error.TestUnexpectedResult,
    }
}

test "snapshot with ANSI sequences" {
    const allocator = testing.allocator;

    // Test ANSI sequence handling
    const content = "\x1b[31mRed\x1b[0m text";
    const result = try expectSnapshot(allocator, "ansi_test", content);

    switch (result) {
        .pass, .created, .updated => {},
        .fail => return error.TestUnexpectedResult,
    }
}

test "test terminal capture" {
    const allocator = testing.allocator;

    const output = try captureOutput(allocator, struct {
        fn render(writer: anytype) !void {
            try writer.writeAll("Line 1\n");
            try writer.writeAll("Line 2\n");
        }
    }.render, .{});

    defer allocator.free(output);

    try testing.expectEqualStrings("Line 1\nLine 2\n", output);
}
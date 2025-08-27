//! Myers Diff Algorithm Implementation
//!
//! This module implements the Myers diff algorithm, an efficient O(ND) algorithm
//! for computing the shortest edit script between two sequences. The algorithm
//! finds the minimum number of insertions and deletions needed to transform
//! one sequence into another.
//!
//! ## Algorithm Overview
//!
//! The Myers algorithm works by:
//! 1. Modeling the problem as finding a path through an edit graph
//! 2. Using dynamic programming to find the shortest path
//! 3. Maintaining a frontier of reachable positions at each edit distance
//! 4. The algorithm terminates when it finds a path that reaches the end
//!
//! ## Usage
//!
//! ```zig
//! const diff = @import("diff.zig");
//!
//! // Character-based diff
//! const ops = try diff.computeChars(allocator, "hello", "hello world");
//! defer allocator.free(ops);
//!
//! // Line-based diff
//! const lines1 = try splitLines(allocator, text1);
//! defer allocator.free(lines1);
//! const lines2 = try splitLines(allocator, text2);
//! defer allocator.free(lines2);
//!
//! const line_ops = try diff.computeLines(allocator, lines1, lines2);
//! defer allocator.free(line_ops);
//! ```
//!
//! ## Performance
//!
//! - Time complexity: O(ND) where D is the edit distance
//! - Space complexity: O(N) for the algorithm, O(D) for temporary storage
//! - Very efficient for sequences with small edit distances
//! - Best case: O(N) when sequences are identical

const std = @import("std");

/// Represents a single diff operation
pub const DiffOp = enum {
    /// Elements are equal (no change needed)
    equal,
    /// Element needs to be inserted into the first sequence
    insert,
    /// Element needs to be deleted from the first sequence
    delete,

    /// Returns a string representation of the operation
    pub fn asString(self: DiffOp) []const u8 {
        return switch (self) {
            .equal => "equal",
            .insert => "insert",
            .delete => "delete",
        };
    }
};

/// Represents a single diff operation with its value
pub const DiffOperation = struct {
    /// The operation type
    op: DiffOp,
    /// The value associated with this operation
    /// For equal: the common element
    /// For insert: the element to insert
    /// For delete: the element to delete
    value: []const u8,

    /// Create a new diff operation
    pub fn init(op: DiffOp, value: []const u8) DiffOperation {
        return DiffOperation{
            .op = op,
            .value = value,
        };
    }
};

/// Error set for diff operations
pub const DiffError = error{
    /// Out of memory during diff computation
    OutOfMemory,
    /// Invalid input parameters
    InvalidInput,
};

/// Configuration for diff computation
pub const DiffConfig = struct {
    /// Whether to ignore whitespace differences
    ignore_whitespace: bool = false,
    /// Whether to ignore case differences
    ignore_case: bool = false,
    /// Maximum number of operations to compute (0 = unlimited)
    max_operations: usize = 0,
};

/// Internal structure for Myers algorithm implementation
const MyersState = struct {
    allocator: std.mem.Allocator,
    a: []const []const u8,
    b: []const []const u8,
    m: usize,
    n: usize,
    max_d: usize,
    v: std.ArrayList(isize),
    trace: std.ArrayList(std.ArrayList(isize)),

    fn init(allocator: std.mem.Allocator, a: []const []const u8, b: []const []const u8) !MyersState {
        const m = a.len;
        const n = b.len;
        const max_d = m + n;

        var v = std.ArrayList(isize).initCapacity(allocator, 2 * max_d + 1) catch return DiffError.OutOfMemory;
        var trace = std.ArrayList(std.ArrayList(isize)).initCapacity(allocator, max_d + 1) catch {
            v.deinit();
            return DiffError.OutOfMemory;
        };

        return MyersState{
            .allocator = allocator,
            .a = a,
            .b = b,
            .m = m,
            .n = n,
            .max_d = max_d,
            .v = v,
            .trace = trace,
        };
    }

    fn deinit(self: *MyersState) void {
        self.v.deinit();
        for (self.trace.items) |*t| {
            t.deinit();
        }
        self.trace.deinit();
    }

    /// Check if two elements are equal, considering configuration options
    fn elementsEqual(self: *const MyersState, config: DiffConfig, i: usize, j: usize) bool {
        const elem_a = self.a[i];
        const elem_b = self.b[j];

        if (config.ignore_whitespace) {
            // Compare ignoring whitespace
            const trimmed_a = std.mem.trim(u8, elem_a, &std.ascii.whitespace);
            const trimmed_b = std.mem.trim(u8, elem_b, &std.ascii.whitespace);
            return compareStrings(config, trimmed_a, trimmed_b);
        } else {
            return compareStrings(config, elem_a, elem_b);
        }
    }

    fn compareStrings(config: DiffConfig, s1: []const u8, s2: []const u8) bool {
        if (config.ignore_case) {
            return std.ascii.eqlIgnoreCase(s1, s2);
        } else {
            return std.mem.eql(u8, s1, s2);
        }
    }

    /// Find the shortest edit script using Myers algorithm
    fn shortestEdit(self: *MyersState, config: DiffConfig) !?usize {
        // Initialize V array
        try self.v.resize(2 * self.max_d + 1);
        @memset(self.v.items, 0);

        // Initialize trace
        for (0..self.max_d + 1) |_| {
            try self.trace.append(std.ArrayList(isize).init(self.allocator));
        }

        // Copy initial V to trace
        try self.trace.items[0].appendSlice(self.v.items);

        var d: usize = 0;
        while (d <= self.max_d) : (d += 1) {
            // Check operation limit
            if (config.max_operations > 0 and d >= config.max_operations) {
                return null;
            }

            var k = -@as(isize, @intCast(d));
            while (k <= @as(isize, @intCast(d))) : (k += 2) {
                const index = @as(usize, @intCast(k + @as(isize, @intCast(self.max_d))));

                var x: usize = undefined;
                if (k == -@as(isize, @intCast(d))) {
                    x = @as(usize, @intCast(self.v.items[@as(usize, @intCast((k + 1) + @as(isize, @intCast(self.max_d))))]));
                } else if (k == @as(isize, @intCast(d))) {
                    x = @as(usize, @intCast(self.v.items[@as(usize, @intCast((k - 1) + @as(isize, @intCast(self.max_d))))] + 1));
                } else {
                    const prev_x1 = @as(usize, @intCast(self.v.items[@as(usize, @intCast((k - 1) + @as(isize, @intCast(self.max_d))))]));
                    const prev_x2 = @as(usize, @intCast(self.v.items[@as(usize, @intCast((k + 1) + @as(isize, @intCast(self.max_d))))]));
                    x = if (prev_x1 > prev_x2) prev_x1 else prev_x2 + 1;
                }

                var y = @as(isize, @intCast(x)) - k;

                // Follow diagonal
                while (x < self.m and @as(usize, @intCast(y)) < self.n and
                    self.elementsEqual(config, x, @as(usize, @intCast(y))))
                {
                    x += 1;
                    y += 1;
                }

                self.v.items[index] = @as(isize, @intCast(x));

                // Check if we've reached the end
                if (x >= self.m and @as(usize, @intCast(y)) >= self.n) {
                    // Copy current V to trace
                    try self.trace.items[d].appendSlice(self.v.items);
                    return d;
                }
            }

            // Copy current V to trace
            try self.trace.items[d].appendSlice(self.v.items);
        }

        return null; // No solution found within limits
    }

    /// Backtrack through the trace to build the diff operations
    fn backtrack(self: *MyersState, d: usize) !std.ArrayList(DiffOperation) {
        var operations = std.ArrayList(DiffOperation).init(self.allocator);

        var x = self.m;
        var y = self.n;

        var current_d = d;
        while (current_d > 0) {
            const prev_v = self.trace.items[current_d - 1].items;

            var k = @as(isize, @intCast(x)) - @as(isize, @intCast(y));
            const index = @as(usize, @intCast(k + @as(isize, @intCast(self.max_d))));

            var prev_k: isize = undefined;

            if (k == -@as(isize, @intCast(current_d))) {
                prev_k = k + 1;
            } else if (k == @as(isize, @intCast(current_d))) {
                prev_k = k - 1;
            } else {
                const prev_index1 = @as(usize, @intCast((k - 1) + @as(isize, @intCast(self.max_d))));
                const prev_index2 = @as(usize, @intCast((k + 1) + @as(isize, @intCast(self.max_d))));

                if (prev_v[prev_index1] > prev_v[prev_index2]) {
                    prev_k = k - 1;
                } else {
                    prev_k = k + 1;
                }
            }

            const prev_index = @as(usize, @intCast(prev_k + @as(isize, @intCast(self.max_d))));
            const prev_x = @as(usize, @intCast(prev_v[prev_index]));

            var prev_y = @as(isize, @intCast(prev_x)) - prev_k;

            // Follow diagonal backward
            while (x > prev_x and y > @as(usize, @intCast(prev_y))) {
                x -= 1;
                y -= 1;
                try operations.insert(0, DiffOperation.init(.equal, self.a[x]));
            }

            if (current_d > 0) {
                if (x == prev_x) {
                    // Insert
                    y -= 1;
                    try operations.insert(0, DiffOperation.init(.insert, self.b[y]));
                } else {
                    // Delete
                    x -= 1;
                    try operations.insert(0, DiffOperation.init(.delete, self.a[x]));
                }
            }

            current_d -= 1;
        }

        // Add remaining equal elements
        while (x > 0 and y > 0) {
            x -= 1;
            y -= 1;
            try operations.insert(0, DiffOperation.init(.equal, self.a[x]));
        }

        return operations;
    }
};

/// Compute the diff between two sequences of strings
/// Returns a list of operations that transform sequence 'a' into sequence 'b'
pub fn compute(
    allocator: std.mem.Allocator,
    a: []const []const u8,
    b: []const []const u8,
    config: DiffConfig,
) ![]DiffOperation {
    if (a.len == 0 and b.len == 0) {
        return allocator.alloc(DiffOperation, 0);
    }

    var state = try MyersState.init(allocator, a, b);
    defer state.deinit();

    const d = (try state.shortestEdit(config)) orelse {
        // If no solution found within limits, return empty diff
        return allocator.alloc(DiffOperation, 0);
    };

    var operations = try state.backtrack(d);
    defer operations.deinit();

    return try allocator.dupe(DiffOperation, operations.items);
}

/// Compute character-based diff between two strings
/// Splits strings into individual characters and computes diff
pub fn computeChars(
    allocator: std.mem.Allocator,
    a: []const u8,
    b: []const u8,
    config: DiffConfig,
) ![]DiffOperation {
    // Convert strings to arrays of single-character strings
    var a_chars = std.ArrayList([]const u8).initCapacity(allocator, a.len) catch return DiffError.OutOfMemory;
    defer a_chars.deinit();

    var b_chars = std.ArrayList([]const u8).initCapacity(allocator, b.len) catch return DiffError.OutOfMemory;
    defer b_chars.deinit();

    // Split a into characters
    for (a) |char| {
        const char_slice = try allocator.alloc(u8, 1);
        char_slice[0] = char;
        try a_chars.append(char_slice);
    }

    // Split b into characters
    for (b) |char| {
        const char_slice = try allocator.alloc(u8, 1);
        char_slice[0] = char;
        try b_chars.append(char_slice);
    }

    // Compute diff
    const operations = try compute(allocator, a_chars.items, b_chars.items, config);

    // Clean up temporary character arrays
    for (a_chars.items) |char_slice| {
        allocator.free(char_slice);
    }
    for (b_chars.items) |char_slice| {
        allocator.free(char_slice);
    }

    return operations;
}

/// Compute line-based diff between two texts
/// Splits texts by newlines and computes diff
pub fn computeLines(
    allocator: std.mem.Allocator,
    a: []const u8,
    b: []const u8,
    config: DiffConfig,
) ![]DiffOperation {
    // Split texts into lines
    var a_lines = std.ArrayList([]const u8).init(allocator);
    defer a_lines.deinit();

    var b_lines = std.ArrayList([]const u8).init(allocator);
    defer b_lines.deinit();

    var a_iter = std.mem.split(u8, a, "\n");
    while (a_iter.next()) |line| {
        try a_lines.append(line);
    }

    var b_iter = std.mem.split(u8, b, "\n");
    while (b_iter.next()) |line| {
        try b_lines.append(line);
    }

    // Compute diff
    const operations = try compute(allocator, a_lines.items, b_lines.items, config);

    // Note: We don't free the line slices here as they are views into the original strings
    // The caller is responsible for managing the original string memory

    return operations;
}

/// Convenience function for simple character-based diff with default config
pub fn diffChars(
    allocator: std.mem.Allocator,
    a: []const u8,
    b: []const u8,
) ![]DiffOperation {
    return try computeChars(allocator, a, b, DiffConfig{});
}

/// Convenience function for simple line-based diff with default config
pub fn diffLines(
    allocator: std.mem.Allocator,
    a: []const u8,
    b: []const u8,
) ![]DiffOperation {
    return try computeLines(allocator, a, b, DiffConfig{});
}

/// Utility function to split text into lines
/// Returns an array of string slices that must be freed by the caller
pub fn splitLines(
    allocator: std.mem.Allocator,
    text: []const u8,
) ![][]const u8 {
    var lines = std.ArrayList([]const u8).init(allocator);
    errdefer lines.deinit();

    var iter = std.mem.split(u8, text, "\n");
    while (iter.next()) |line| {
        try lines.append(line);
    }

    return try lines.toOwnedSlice();
}

/// Format diff operations as a unified diff format string
pub fn formatUnified(
    allocator: std.mem.Allocator,
    operations: []const DiffOperation,
    context_lines: usize,
) ![]u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    var line_a: usize = 1;
    var line_b: usize = 1;

    var i: usize = 0;
    while (i < operations.len) {
        const op = operations[i];

        switch (op.op) {
            .equal => {
                // Count consecutive equal operations
                var equal_count: usize = 1;
                while (i + equal_count < operations.len and operations[i + equal_count].op == .equal) {
                    equal_count += 1;
                }

                // Add context lines before changes
                const context_start = if (equal_count > context_lines * 2) equal_count - context_lines else 0;
                for (context_start..equal_count) |j| {
                    try std.fmt.format(output.writer(), " {s}\n", .{operations[i + j].value});
                    line_a += 1;
                    line_b += 1;
                }

                i += equal_count;
            },
            .delete, .insert => {
                // Find the range of changes
                var change_start = i;
                var deletions: usize = 0;
                var insertions: usize = 0;

                while (i < operations.len and (operations[i].op == .delete or operations[i].op == .insert)) {
                    switch (operations[i].op) {
                        .delete => deletions += 1,
                        .insert => insertions += 1,
                        .equal => break,
                    }
                    i += 1;
                }

                // Format hunk header
                try std.fmt.format(output.writer(), "@@ -{},{} +{},{} @@\n", .{
                    line_a, deletions, line_b, insertions,
                });

                // Add deletions
                for (change_start..i) |j| {
                    if (operations[j].op == .delete) {
                        try std.fmt.format(output.writer(), "-{s}\n", .{operations[j].value});
                        line_a += 1;
                    }
                }

                // Add insertions
                for (change_start..i) |j| {
                    if (operations[j].op == .insert) {
                        try std.fmt.format(output.writer(), "+{s}\n", .{operations[j].value});
                        line_b += 1;
                    }
                }
            },
        }
    }

    return try output.toOwnedSlice();
}

/// Free memory allocated for diff operations
pub fn freeOperations(allocator: std.mem.Allocator, operations: []DiffOperation) void {
    allocator.free(operations);
}

test "basic diff functionality" {
    const testing = std.testing;

    // Test identical sequences
    {
        const a = &[_][]const u8{ "line1", "line2", "line3" };
        const b = &[_][]const u8{ "line1", "line2", "line3" };

        const ops = try compute(testing.allocator, a, b, DiffConfig{});
        defer testing.allocator.free(ops);

        try testing.expectEqual(@as(usize, 3), ops.len);
        for (ops) |op| {
            try testing.expectEqual(DiffOp.equal, op.op);
        }
    }

    // Test simple insertion
    {
        const a = &[_][]const u8{ "line1", "line2" };
        const b = &[_][]const u8{ "line1", "inserted", "line2" };

        const ops = try compute(testing.allocator, a, b, DiffConfig{});
        defer testing.allocator.free(ops);

        try testing.expectEqual(@as(usize, 3), ops.len);
        try testing.expectEqual(DiffOp.equal, ops[0].op);
        try testing.expectEqual(DiffOp.insert, ops[1].op);
        try testing.expectEqual(DiffOp.equal, ops[2].op);
    }

    // Test simple deletion
    {
        const a = &[_][]const u8{ "line1", "deleted", "line2" };
        const b = &[_][]const u8{ "line1", "line2" };

        const ops = try compute(testing.allocator, a, b, DiffConfig{});
        defer testing.allocator.free(ops);

        try testing.expectEqual(@as(usize, 3), ops.len);
        try testing.expectEqual(DiffOp.equal, ops[0].op);
        try testing.expectEqual(DiffOp.delete, ops[1].op);
        try testing.expectEqual(DiffOp.equal, ops[2].op);
    }
}

test "character diff" {
    const testing = std.testing;

    const ops = try diffChars(testing.allocator, "abc", "abxc");
    defer testing.allocator.free(ops);

    try testing.expectEqual(@as(usize, 4), ops.len);
    try testing.expectEqual(DiffOp.equal, ops[0].op); // 'a'
    try testing.expectEqual(DiffOp.equal, ops[1].op); // 'b'
    try testing.expectEqual(DiffOp.insert, ops[2].op); // 'x'
    try testing.expectEqual(DiffOp.equal, ops[3].op); // 'c'
}

test "line diff" {
    const testing = std.testing;

    const text1 = "line1\nline2\nline3";
    const text2 = "line1\ninserted\nline2\nline3";

    const ops = try diffLines(testing.allocator, text1, text2);
    defer testing.allocator.free(ops);

    try testing.expectEqual(@as(usize, 4), ops.len);
    try testing.expectEqual(DiffOp.equal, ops[0].op); // "line1"
    try testing.expectEqual(DiffOp.insert, ops[1].op); // "inserted"
    try testing.expectEqual(DiffOp.equal, ops[2].op); // "line2"
    try testing.expectEqual(DiffOp.equal, ops[3].op); // "line3"
}

test "unified diff format" {
    const testing = std.testing;

    const operations = [_]DiffOperation{
        DiffOperation.init(.equal, "line1"),
        DiffOperation.init(.insert, "inserted"),
        DiffOperation.init(.equal, "line2"),
        DiffOperation.init(.delete, "deleted"),
        DiffOperation.init(.equal, "line3"),
    };

    const unified = try formatUnified(testing.allocator, &operations, 3);
    defer testing.allocator.free(unified);

    // Check that it contains expected unified diff format elements
    try testing.expect(std.mem.indexOf(u8, unified, "@@") != null);
    try testing.expect(std.mem.indexOf(u8, unified, "+inserted") != null);
    try testing.expect(std.mem.indexOf(u8, unified, "-deleted") != null);
}

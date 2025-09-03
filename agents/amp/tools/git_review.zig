//! Git Review tool for comprehensive code review automation.
//!
//! Based on specs/amp/prompts/amp-git-review.md specification.
//! Provides comprehensive code review automation and suggestions by analyzing git diffs.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Input parameters for git review
const GitReviewInput = struct {
    /// Git reference to compare against (default: HEAD~1)
    base_ref: []const u8 = "HEAD~1",
    /// Git reference to review (default: HEAD)
    head_ref: []const u8 = "HEAD",
    /// Working directory for git operations (default: current directory)
    cwd: ?[]const u8 = null,
    /// Include staged changes in review (default: false)
    include_staged: bool = false,
    /// Include unstaged changes in review (default: false)
    include_unstaged: bool = false,
    /// Maximum lines of context to show around changes (default: 3)
    context_lines: u32 = 3,
    /// Focus review on specific file patterns (glob patterns)
    file_patterns: []const []const u8 = &[_][]const u8{},
    /// Skip files matching these patterns (glob patterns)
    ignore_patterns: []const []const u8 = &[_][]const u8{},
};

/// Output structure for git review
const GitReviewOutput = struct {
    /// High-level summary of changes
    summary: []const u8,
    /// Tour of changes - best starting point for review
    tour_of_changes: []const u8,
    /// File-by-file review analysis
    file_reviews: []FileReview,
    /// Overall review statistics
    stats: ReviewStats,
    /// Any errors or warnings encountered
    warnings: []const []const u8 = &[_][]const u8{},

    pub fn deinit(self: GitReviewOutput, allocator: std.mem.Allocator) void {
        allocator.free(self.summary);
        allocator.free(self.tour_of_changes);
        for (self.file_reviews) |review| {
            allocator.free(review.file_path);
            allocator.free(review.analysis);
            for (review.security_issues) |issue| {
                allocator.free(issue);
            }
            allocator.free(review.security_issues);
            for (review.performance_issues) |issue| {
                allocator.free(issue);
            }
            allocator.free(review.performance_issues);
            for (review.quality_suggestions) |suggestion| {
                allocator.free(suggestion);
            }
            allocator.free(review.quality_suggestions);
        }
        allocator.free(self.file_reviews);
        for (self.warnings) |warning| {
            allocator.free(warning);
        }
        if (self.warnings.ptr != &[_][]const u8{}) {
            allocator.free(self.warnings);
        }
    }
};

const FileReview = struct {
    /// File path relative to repository root
    file_path: []const u8,
    /// Type of change (modified, added, deleted, renamed)
    change_type: []const u8,
    /// Lines added count
    lines_added: u32,
    /// Lines removed count
    lines_removed: u32,
    /// Review analysis of the file
    analysis: []const u8,
    /// Security concerns found
    security_issues: []const []const u8 = &[_][]const u8{},
    /// Performance concerns found
    performance_issues: []const []const u8 = &[_][]const u8{},
    /// Code quality suggestions
    quality_suggestions: []const []const u8 = &[_][]const u8{},
};

const ReviewStats = struct {
    /// Total files changed
    files_changed: u32,
    /// Total lines added across all files
    total_lines_added: u32,
    /// Total lines removed across all files
    total_lines_removed: u32,
    /// Number of security issues found
    security_issues_count: u32,
    /// Number of performance issues found
    performance_issues_count: u32,
    /// Overall complexity rating (1-10)
    complexity_rating: u32,
};

/// Execute git review analysis with performance tracking
pub fn run(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    return execute(allocator, params);
}

/// Execute git review analysis
pub fn execute(allocator: std.mem.Allocator, input_json: std.json.Value) toolsMod.ToolError!std.json.Value {
    // Parse input parameters from JSON value
    const input = std.json.parseFromValue(GitReviewInput, allocator, input_json, .{}) catch |err| {
        return switch (err) {
            error.UnknownField, error.MissingField, error.InvalidEnumTag, error.InvalidNumber => toolsMod.ToolError.InvalidInput,
            else => toolsMod.ToolError.ProcessingFailed,
        };
    };
    defer input.deinit();

    const params = input.value;

    // Get git diff output
    const diff_result = getGitDiff(allocator, params) catch |err| {
        return switch (err) {
            error.GitNotFound => toolsMod.ToolError.ExecutionFailed,
            error.GitExecutionFailed => toolsMod.ToolError.ExecutionFailed,
            error.GitCommandFailed => toolsMod.ToolError.ExecutionFailed,
            else => toolsMod.ToolError.UnexpectedError,
        };
    };
    defer allocator.free(diff_result);

    if (diff_result.len == 0) {
        // No changes to review
        const output = GitReviewOutput{
            .summary = "No changes detected between the specified references",
            .tour_of_changes = "No modifications to review",
            .file_reviews = &[_]FileReview{},
            .stats = ReviewStats{
                .files_changed = 0,
                .total_lines_added = 0,
                .total_lines_removed = 0,
                .security_issues_count = 0,
                .performance_issues_count = 0,
                .complexity_rating = 1,
            },
        };

        const ResponseMapper = toolsMod.JsonReflector.mapper(GitReviewOutput);
        return ResponseMapper.toJsonValue(allocator, output);
    }

    // Parse diff and analyze changes
    const analysis = try analyzeDiff(allocator, diff_result, params);
    defer analysis.deinit(allocator);

    // Generate comprehensive review
    const review = try generateReview(allocator, analysis);
    defer review.deinit(allocator);

    // Serialize output to JSON Value
    const ResponseMapper = toolsMod.JsonReflector.mapper(GitReviewOutput);
    return ResponseMapper.toJsonValue(allocator, review);
}

/// Get git diff output between references
fn getGitDiff(allocator: std.mem.Allocator, params: GitReviewInput) ![]const u8 {
    var args = try std.ArrayList([]const u8).initCapacity(allocator, 8);
    defer args.deinit(allocator);

    try args.append(allocator, "git");
    try args.append(allocator, "diff");

    // Add context lines
    const context_arg = try std.fmt.allocPrint(allocator, "--unified={d}", .{params.context_lines});
    defer allocator.free(context_arg);
    try args.append(allocator, context_arg);

    // Add references or special cases
    if (params.include_unstaged) {
        // Show unstaged changes only
        // git diff shows unstaged changes by default
    } else if (params.include_staged) {
        // Show staged changes
        try args.append(allocator, "--cached");
    } else {
        // Show changes between refs
        try args.append(allocator, params.base_ref);
        try args.append(allocator, params.head_ref);
    }

    // Execute git command
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = args.items,
        .cwd = params.cwd,
        .max_output_bytes = 1024 * 1024 * 10, // 10MB max
    }) catch |err| {
        return switch (err) {
            error.FileNotFound => error.GitNotFound,
            else => error.GitExecutionFailed,
        };
    };

    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (result.term != .Exited or result.term.Exited != 0) {
        return error.GitCommandFailed;
    }

    return try allocator.dupe(u8, result.stdout);
}

/// Analysis result from parsing git diff
const DiffAnalysis = struct {
    files: []FileChange,

    fn deinit(self: DiffAnalysis, allocator: std.mem.Allocator) void {
        for (self.files) |file| {
            allocator.free(file.path);
            allocator.free(file.diff_content);
        }
        allocator.free(self.files);
    }
};

const FileChange = struct {
    path: []const u8,
    change_type: ChangeType,
    lines_added: u32,
    lines_removed: u32,
    diff_content: []const u8,
};

const ChangeType = enum {
    modified,
    added,
    deleted,
    renamed,

    fn toString(self: ChangeType) []const u8 {
        return switch (self) {
            .modified => "modified",
            .added => "added",
            .deleted => "deleted",
            .renamed => "renamed",
        };
    }
};

/// Parse git diff output and analyze changes
fn analyzeDiff(allocator: std.mem.Allocator, diff_output: []const u8, _: GitReviewInput) !DiffAnalysis {
    var files = try std.ArrayList(FileChange).initCapacity(allocator, 16);
    defer files.deinit(allocator);

    var lines = std.mem.splitScalar(u8, diff_output, '\n');
    var current_file: ?FileChange = null;
    var current_diff = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer current_diff.deinit(allocator);

    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "diff --git")) {
            // Save previous file if exists
            if (current_file) |file| {
                var completed_file = file;
                completed_file.diff_content = try current_diff.toOwnedSlice(allocator);
                try files.append(allocator, completed_file);
                current_diff = try std.ArrayList(u8).initCapacity(allocator, 1024);
            }

            // Parse new file path from "diff --git a/path b/path"
            const a_pos = std.mem.indexOf(u8, line, "a/");
            const b_pos = std.mem.indexOf(u8, line, "b/");
            if (a_pos != null and b_pos != null) {
                const start = a_pos.? + 2;
                const space_pos = std.mem.indexOf(u8, line[start..], " ");
                if (space_pos) |pos| {
                    const path = try allocator.dupe(u8, line[start .. start + pos]);
                    current_file = FileChange{
                        .path = path,
                        .change_type = .modified, // Default, will be updated
                        .lines_added = 0,
                        .lines_removed = 0,
                        .diff_content = "",
                    };
                }
            }
        } else if (std.mem.startsWith(u8, line, "new file mode")) {
            if (current_file) |*file| {
                file.change_type = .added;
            }
        } else if (std.mem.startsWith(u8, line, "deleted file mode")) {
            if (current_file) |*file| {
                file.change_type = .deleted;
            }
        } else if (std.mem.startsWith(u8, line, "+") and !std.mem.startsWith(u8, line, "+++")) {
            if (current_file) |*file| {
                file.lines_added += 1;
            }
        } else if (std.mem.startsWith(u8, line, "-") and !std.mem.startsWith(u8, line, "---")) {
            if (current_file) |*file| {
                file.lines_removed += 1;
            }
        }

        // Add line to current diff content
        try current_diff.appendSlice(allocator, line);
        try current_diff.append(allocator, '\n');
    }

    // Save last file
    if (current_file) |file| {
        var completed_file = file;
        completed_file.diff_content = try current_diff.toOwnedSlice(allocator);
        try files.append(allocator, completed_file);
    }

    return DiffAnalysis{
        .files = try files.toOwnedSlice(allocator),
    };
}

/// Generate comprehensive code review
fn generateReview(allocator: std.mem.Allocator, analysis: DiffAnalysis) !GitReviewOutput {
    var file_reviews = try std.ArrayList(FileReview).initCapacity(allocator, 16);
    defer file_reviews.deinit(allocator);

    var total_added: u32 = 0;
    var total_removed: u32 = 0;
    var total_security_issues: u32 = 0;
    var total_performance_issues: u32 = 0;

    // Analyze each file
    for (analysis.files) |file| {
        total_added += file.lines_added;
        total_removed += file.lines_removed;

        const file_analysis = try analyzeFile(allocator, file);
        defer file_analysis.deinit(allocator);

        total_security_issues += @intCast(file_analysis.security_issues.len);
        total_performance_issues += @intCast(file_analysis.performance_issues.len);

        try file_reviews.append(allocator, FileReview{
            .file_path = try allocator.dupe(u8, file.path),
            .change_type = file.change_type.toString(),
            .lines_added = file.lines_added,
            .lines_removed = file.lines_removed,
            .analysis = file_analysis.analysis,
            .security_issues = file_analysis.security_issues,
            .performance_issues = file_analysis.performance_issues,
            .quality_suggestions = file_analysis.quality_suggestions,
        });
    }

    // Generate summary
    const summary = try generateSummary(allocator, analysis);

    // Generate tour of changes
    const tour = try generateTourOfChanges(allocator, analysis);

    // Calculate complexity rating
    const complexity = calculateComplexity(analysis);

    return GitReviewOutput{
        .summary = summary,
        .tour_of_changes = tour,
        .file_reviews = try file_reviews.toOwnedSlice(allocator),
        .stats = ReviewStats{
            .files_changed = @intCast(analysis.files.len),
            .total_lines_added = total_added,
            .total_lines_removed = total_removed,
            .security_issues_count = total_security_issues,
            .performance_issues_count = total_performance_issues,
            .complexity_rating = complexity,
        },
    };
}

const FileAnalysisResult = struct {
    analysis: []const u8,
    security_issues: [][]const u8,
    performance_issues: [][]const u8,
    quality_suggestions: [][]const u8,

    fn deinit(self: FileAnalysisResult, allocator: std.mem.Allocator) void {
        allocator.free(self.analysis);
        for (self.security_issues) |issue| {
            allocator.free(issue);
        }
        allocator.free(self.security_issues);
        for (self.performance_issues) |issue| {
            allocator.free(issue);
        }
        allocator.free(self.performance_issues);
        for (self.quality_suggestions) |suggestion| {
            allocator.free(suggestion);
        }
        allocator.free(self.quality_suggestions);
    }
};

/// Analyze individual file changes
fn analyzeFile(allocator: std.mem.Allocator, file: FileChange) !FileAnalysisResult {
    var security_issues = try std.ArrayList([]const u8).initCapacity(allocator, 8);
    var performance_issues = try std.ArrayList([]const u8).initCapacity(allocator, 8);
    var quality_suggestions = try std.ArrayList([]const u8).initCapacity(allocator, 8);

    defer security_issues.deinit(allocator);
    defer performance_issues.deinit(allocator);
    defer quality_suggestions.deinit(allocator);

    // Basic analysis based on file type and changes
    const file_ext = std.fs.path.extension(file.path);
    const is_code_file = isCodeFile(file_ext);

    var analysis_parts = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer analysis_parts.deinit(allocator);

    // Describe the change
    switch (file.change_type) {
        .added => {
            try analysis_parts.appendSlice(allocator, "New file added");
            if (is_code_file) {
                try quality_suggestions.append(allocator, try allocator.dupe(u8, "Consider adding unit tests for new functionality"));
            }
        },
        .deleted => {
            try analysis_parts.appendSlice(allocator, "File deleted");
            try quality_suggestions.append(allocator, try allocator.dupe(u8, "Verify that dependencies on this file have been updated"));
        },
        .modified => {
            try analysis_parts.appendSlice(allocator, try std.fmt.allocPrint(allocator, "Modified with {d} additions and {d} deletions", .{ file.lines_added, file.lines_removed }));
        },
        .renamed => {
            try analysis_parts.appendSlice(allocator, "File renamed");
        },
    }

    // Analyze diff content for security patterns
    if (containsSecurityPattern(file.diff_content)) {
        try security_issues.append(allocator, try allocator.dupe(u8, "Potential security-sensitive changes detected - review carefully for vulnerabilities"));
    }

    // Analyze for performance patterns
    if (containsPerformancePattern(file.diff_content)) {
        try performance_issues.append(allocator, try allocator.dupe(u8, "Changes may impact performance - consider profiling or load testing"));
    }

    // Add general suggestions based on change size
    const change_size = file.lines_added + file.lines_removed;
    if (change_size > 100) {
        try quality_suggestions.append(allocator, try allocator.dupe(u8, "Large change - consider breaking into smaller, focused commits"));
    }

    return FileAnalysisResult{
        .analysis = try analysis_parts.toOwnedSlice(allocator),
        .security_issues = try security_issues.toOwnedSlice(allocator),
        .performance_issues = try performance_issues.toOwnedSlice(allocator),
        .quality_suggestions = try quality_suggestions.toOwnedSlice(allocator),
    };
}

fn isCodeFile(extension: []const u8) bool {
    const code_extensions = [_][]const u8{ ".zig", ".c", ".cpp", ".h", ".hpp", ".rs", ".go", ".js", ".ts", ".py", ".java", ".kt", ".swift" };
    for (code_extensions) |ext| {
        if (std.mem.eql(u8, extension, ext)) return true;
    }
    return false;
}

fn containsSecurityPattern(diff_content: []const u8) bool {
    const security_patterns = [_][]const u8{ "password", "secret", "token", "key", "auth", "crypto", "hash", "sql", "query", "exec", "eval", "unsafe", "buffer", "malloc", "free" };

    for (security_patterns) |pattern| {
        if (std.ascii.indexOfIgnoreCase(diff_content, pattern) != null) {
            return true;
        }
    }
    return false;
}

fn containsPerformancePattern(diff_content: []const u8) bool {
    const performance_patterns = [_][]const u8{ "loop", "for", "while", "recursive", "algorithm", "sort", "search", "cache", "memory", "allocat", "thread", "lock", "sync", "async" };

    for (performance_patterns) |pattern| {
        if (std.ascii.indexOfIgnoreCase(diff_content, pattern) != null) {
            return true;
        }
    }
    return false;
}

fn generateSummary(allocator: std.mem.Allocator, analysis: DiffAnalysis) ![]const u8 {
    if (analysis.files.len == 0) {
        return try allocator.dupe(u8, "No changes detected");
    }

    var added_count: u32 = 0;
    var modified_count: u32 = 0;
    var deleted_count: u32 = 0;

    for (analysis.files) |file| {
        switch (file.change_type) {
            .added => added_count += 1,
            .modified => modified_count += 1,
            .deleted => deleted_count += 1,
            .renamed => modified_count += 1,
        }
    }

    return try std.fmt.allocPrint(allocator, "Review covers {d} files: {d} modified, {d} added, {d} deleted", .{ analysis.files.len, modified_count, added_count, deleted_count });
}

fn generateTourOfChanges(allocator: std.mem.Allocator, analysis: DiffAnalysis) ![]const u8 {
    if (analysis.files.len == 0) {
        return try allocator.dupe(u8, "No changes to tour");
    }

    // Find the most significant change (highest line count)
    var max_changes: u32 = 0;
    var primary_file: ?FileChange = null;

    for (analysis.files) |file| {
        const change_count = file.lines_added + file.lines_removed;
        if (change_count > max_changes) {
            max_changes = change_count;
            primary_file = file;
        }
    }

    if (primary_file) |file| {
        return try std.fmt.allocPrint(allocator, "Start with `{s}` - the most significant change with {d} additions and {d} deletions. " ++
            "This file represents the core of the changes and will help understand the overall modification pattern.", .{ file.path, file.lines_added, file.lines_removed });
    }

    return try std.fmt.allocPrint(allocator, "Begin with `{s}` as the starting point for review", .{analysis.files[0].path});
}

fn calculateComplexity(analysis: DiffAnalysis) u32 {
    if (analysis.files.len == 0) return 1;

    var total_changes: u32 = 0;
    var file_count: u32 = 0;

    for (analysis.files) |file| {
        total_changes += file.lines_added + file.lines_removed;
        file_count += 1;
    }

    // Simple complexity calculation based on change volume and file count
    const avg_changes = if (file_count > 0) total_changes / file_count else 0;

    if (file_count > 20 or avg_changes > 200) return 10;
    if (file_count > 10 or avg_changes > 100) return 8;
    if (file_count > 5 or avg_changes > 50) return 6;
    if (file_count > 2 or avg_changes > 20) return 4;
    return 2;
}

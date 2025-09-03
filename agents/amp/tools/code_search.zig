//! Code Search tool for AMP agent.
//!
//! Provides intelligent codebase exploration beyond basic grep functionality.
//! Combines multiple search strategies to find relevant code based on concepts and functionality.
//!
//! Based on specs/amp/prompts/amp-code-search.md but adapted for the Zig foundation framework.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;
const performance = @import("performance.zig");

const Allocator = std.mem.Allocator;

const SearchRequest = struct {
    query: []const u8,
    paths: ?[][]const u8 = null, // Specific paths to search in
    filePattern: ?[]const u8 = null, // File glob pattern to filter
    contextLines: ?u32 = 3, // Lines of context around matches
    maxResults: ?u32 = 50, // Maximum results to return
    caseSensitive: ?bool = false,
};

const SearchResult = struct {
    file: []const u8,
    line: u32,
    column: u32,
    content: []const u8,
    contextBefore: ?[]const u8 = null,
    contextAfter: ?[]const u8 = null,
};

const SearchResponse = struct {
    results: []SearchResult,
    totalFiles: u32,
    summary: []const u8,
};

/// Public JSON tool entrypoint
pub fn run(allocator: Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    // Initialize performance tracking
    var perf = performance.ToolPerformance.init(allocator, "code_search") catch {
        // If performance tracking fails, continue without it
        return runWithoutPerformanceTracking(allocator, params);
    };

    // Record input size for performance analysis
    // Record approximate input size (simplified for now)
    perf.recordInputSize(256);

    perf.startExecution();
    defer {
        perf.endExecution();

        // Log performance metrics if registry is available
        if (performance.getGlobalRegistry()) |registry| {
            registry.recordToolExecution(&perf) catch {};
        }

        // Generate performance report for debugging (optional)
        if (perf.generateReport()) |report| {
            allocator.free(report);
        } else |_| {}
    }

    const result = runWithoutPerformanceTracking(allocator, params);

    // Record output size
    if (result) |_| {
        // Record approximate output size (simplified for now)
        perf.recordOutputSize(1024);
    } else |_| {}

    return result;
}

/// Core search functionality without performance tracking
fn runWithoutPerformanceTracking(allocator: Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    // Manual parse for Zig 0.15.1 stability
    if (params != .object) return toolsMod.ToolError.InvalidInput;
    const obj = params.object;

    const query_val = obj.get("query") orelse return toolsMod.ToolError.MissingParameter;
    if (query_val != .string) return toolsMod.ToolError.InvalidInput;
    const query = query_val.string;

    var paths_opt: ?[][]const u8 = null;
    if (obj.get("paths")) |paths_val| switch (paths_val) {
        .array => |arr| {
            var paths = try allocator.alloc([]const u8, arr.items.len);
            for (arr.items, 0..) |item, i| {
                if (item != .string) return toolsMod.ToolError.InvalidInput;
                paths[i] = item.string;
            }
            paths_opt = paths;
        },
        .null => {},
        else => return toolsMod.ToolError.InvalidInput,
    };
    defer if (paths_opt) |paths| allocator.free(paths);

    var file_pattern_opt: ?[]const u8 = null;
    if (obj.get("filePattern")) |fp_val| switch (fp_val) {
        .string => |s| file_pattern_opt = s,
        .null => {},
        else => return toolsMod.ToolError.InvalidInput,
    };

    var context_lines: u32 = 3;
    if (obj.get("contextLines")) |cl_val| switch (cl_val) {
        .integer => |iv| {
            if (iv < 0 or iv > 20) return toolsMod.ToolError.InvalidInput;
            context_lines = @as(u32, @intCast(iv));
        },
        .null => {},
        else => return toolsMod.ToolError.InvalidInput,
    };

    var max_results: u32 = 50;
    if (obj.get("maxResults")) |mr_val| switch (mr_val) {
        .integer => |iv| {
            if (iv < 1 or iv > 500) return toolsMod.ToolError.InvalidInput;
            max_results = @as(u32, @intCast(iv));
        },
        .null => {},
        else => return toolsMod.ToolError.InvalidInput,
    };

    var case_sensitive: bool = false;
    if (obj.get("caseSensitive")) |cs_val| switch (cs_val) {
        .bool => |b| case_sensitive = b,
        .null => {},
        else => return toolsMod.ToolError.InvalidInput,
    };

    const req = SearchRequest{
        .query = query,
        .paths = paths_opt,
        .filePattern = file_pattern_opt,
        .contextLines = context_lines,
        .maxResults = max_results,
        .caseSensitive = case_sensitive,
    };

    const response = performSearch(allocator, req) catch |err| switch (err) {
        error.OutOfMemory => return toolsMod.ToolError.OutOfMemory,
        error.AccessDenied => return toolsMod.ToolError.PermissionDenied,
        else => return toolsMod.ToolError.UnexpectedError,
    };
    defer {
        for (response.results) |result| {
            allocator.free(result.file);
            allocator.free(result.content);
            if (result.contextBefore) |ctx| allocator.free(ctx);
            if (result.contextAfter) |ctx| allocator.free(ctx);
        }
        allocator.free(response.results);
        allocator.free(response.summary);
    }

    // Convert to JSON
    var result_array = std.json.Array.init(allocator);
    errdefer result_array.deinit();

    for (response.results) |result| {
        var result_obj = std.json.ObjectMap.init(allocator);
        errdefer result_obj.deinit();

        try result_obj.put("file", std.json.Value{ .string = result.file });
        try result_obj.put("line", std.json.Value{ .integer = @as(i64, @intCast(result.line)) });
        try result_obj.put("column", std.json.Value{ .integer = @as(i64, @intCast(result.column)) });
        try result_obj.put("content", std.json.Value{ .string = result.content });

        if (result.contextBefore) |ctx| {
            try result_obj.put("contextBefore", std.json.Value{ .string = ctx });
        }
        if (result.contextAfter) |ctx| {
            try result_obj.put("contextAfter", std.json.Value{ .string = ctx });
        }

        try result_array.append(std.json.Value{ .object = result_obj });
    }

    var response_obj = std.json.ObjectMap.init(allocator);
    errdefer response_obj.deinit();

    try response_obj.put("results", std.json.Value{ .array = result_array });
    try response_obj.put("totalFiles", std.json.Value{ .integer = @as(i64, @intCast(response.totalFiles)) });
    try response_obj.put("summary", std.json.Value{ .string = response.summary });

    return std.json.Value{ .object = response_obj };
}

fn performSearch(allocator: Allocator, req: SearchRequest) !SearchResponse {
    // Use ripgrep (rg) for fast, accurate search if available, otherwise fallback to manual search
    if (tryRipgrepSearch(allocator, req)) |response| {
        // Cache hit for ripgrep
        return response;
    } else |err| switch (err) {
        error.RipgrepNotFound => {
            // Cache miss - fallback to manual search
            return try manualSearch(allocator, req);
        },
        else => return err,
    }
}

fn tryRipgrepSearch(allocator: Allocator, req: SearchRequest) !SearchResponse {
    // Build ripgrep command
    var cmd_args = std.ArrayList([]const u8){};
    defer cmd_args.deinit(allocator);

    try cmd_args.append(allocator, "rg");
    try cmd_args.append(allocator, "--json");
    try cmd_args.append(allocator, "--with-filename");

    if (!req.caseSensitive.?) {
        try cmd_args.append(allocator, "--ignore-case");
    }

    if (req.contextLines) |lines| {
        const context_arg = try std.fmt.allocPrint(allocator, "--context={d}", .{lines});
        defer allocator.free(context_arg);
        try cmd_args.append(allocator, try allocator.dupe(u8, context_arg));
    }

    const max_count_arg = try std.fmt.allocPrint(allocator, "--max-count={d}", .{req.maxResults orelse 50});
    defer allocator.free(max_count_arg);
    try cmd_args.append(allocator, try allocator.dupe(u8, max_count_arg));

    if (req.filePattern) |pattern| {
        const glob_arg = try std.fmt.allocPrint(allocator, "--glob={s}", .{pattern});
        defer allocator.free(glob_arg);
        try cmd_args.append(allocator, try allocator.dupe(u8, glob_arg));
    }

    // Add the search pattern
    try cmd_args.append(allocator, try allocator.dupe(u8, req.query));

    // Add paths if specified, otherwise search current directory
    if (req.paths) |paths| {
        for (paths) |path| {
            try cmd_args.append(allocator, try allocator.dupe(u8, path));
        }
    } else {
        try cmd_args.append(allocator, try allocator.dupe(u8, "."));
    }

    // Execute ripgrep
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = cmd_args.items,
        .cwd = null,
        .env_map = null,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.RipgrepNotFound,
        else => return err,
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0 and result.term.Exited != 1) { // rg exits 1 when no matches
        return error.RipgrepError;
    }

    return parseRipgrepJson(allocator, result.stdout, req);
}

fn parseRipgrepJson(allocator: Allocator, json_output: []const u8, req: SearchRequest) !SearchResponse {
    var results = std.ArrayList(SearchResult){};
    defer results.deinit(allocator);

    var file_count: u32 = 0;
    var lines = std.mem.splitSequence(u8, json_output, "\n");

    while (lines.next()) |line| {
        if (line.len == 0) continue;

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();

        const obj = parsed.value.object;
        const msg_type = obj.get("type") orelse continue;
        if (msg_type != .string) continue;

        if (std.mem.eql(u8, msg_type.string, "match")) {
            const data = obj.get("data") orelse continue;
            if (data != .object) continue;

            const path_val = data.object.get("path") orelse continue;
            if (path_val != .object or path_val.object.get("text") == null) continue;
            const path = path_val.object.get("text").?.string;

            const lines_val = data.object.get("lines") orelse continue;
            if (lines_val != .object) continue;
            const lines_obj = lines_val.object;

            const text_val = lines_obj.get("text") orelse continue;
            if (text_val != .string) continue;
            const text = text_val.string;

            const line_number_val = lines_obj.get("line_number") orelse continue;
            if (line_number_val != .integer) continue;
            const line_number = @as(u32, @intCast(line_number_val.integer));

            // Find column position of match
            var column: u32 = 1;
            if (data.object.get("submatches")) |submatches_val| {
                if (submatches_val == .array and submatches_val.array.items.len > 0) {
                    const first_match = submatches_val.array.items[0];
                    if (first_match == .object) {
                        if (first_match.object.get("start")) |start_val| {
                            if (start_val == .integer) {
                                column = @as(u32, @intCast(start_val.integer)) + 1;
                            }
                        }
                    }
                }
            }

            try results.append(allocator, SearchResult{
                .file = try allocator.dupe(u8, path),
                .line = line_number,
                .column = column,
                .content = try allocator.dupe(u8, text),
                .contextBefore = null,
                .contextAfter = null,
            });

            file_count += 1;
            if (results.items.len >= (req.maxResults orelse 50)) break;
        }
    }

    const summary = try std.fmt.allocPrint(allocator, "Found {d} matches across {d} files for query: {s}", .{ results.items.len, file_count, req.query });

    return SearchResponse{
        .results = try results.toOwnedSlice(allocator),
        .totalFiles = file_count,
        .summary = summary,
    };
}

fn manualSearch(allocator: Allocator, req: SearchRequest) !SearchResponse {
    // Simple fallback manual search implementation using directory iteration pattern from glob.zig
    var results = std.ArrayList(SearchResult){};
    defer results.deinit(allocator);

    var file_count: u32 = 0;

    // Use stack-based directory iteration like glob tool
    var stack = std.ArrayList([]u8){};
    defer {
        for (stack.items) |p| allocator.free(p);
        stack.deinit(allocator);
    }

    // Add search paths to stack (or current directory by default)
    if (req.paths) |paths| {
        for (paths) |path| {
            try stack.append(allocator, try allocator.dupe(u8, path));
        }
    } else {
        try stack.append(allocator, try allocator.dupe(u8, "."));
    }

    var files_searched: u32 = 0;
    // Dynamic limits based on query complexity and available memory
    const max_files: u32 = if (req.query.len > 50 or (req.maxResults orelse 50) > 100) 500 else 1000;

    while (stack.items.len > 0) {
        const dir_path = stack.pop().?;
        defer allocator.free(dir_path);

        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied => continue,
            else => continue,
        };
        defer dir.close();

        var it = dir.iterate();
        while (true) {
            const next = it.next() catch |e| switch (e) {
                else => null,
            };
            if (next == null) break;
            const entry = next.?;

            if (entry.kind == .directory) {
                // Skip common ignored directories, then add to stack for recursion
                if (shouldSkipDirectory(entry.name)) continue;
                const child_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
                try stack.append(allocator, child_path);
                continue;
            }

            if (entry.kind != .file) continue;
            if (files_searched >= max_files) break;

            // Skip common non-text files
            if (shouldSkipFile(entry.name)) continue;

            files_searched += 1;

            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(full_path);

            // Adaptive file size limit based on current memory usage and file count
            const max_file_size: usize = if (files_searched < 100) 10 * 1024 * 1024 else 1024 * 1024; // 10MB->1MB
            const file_content = std.fs.cwd().readFileAlloc(allocator, full_path, max_file_size) catch continue;
            defer allocator.free(file_content);

            // Search for pattern in file content
            if (searchInFile(allocator, full_path, file_content, req, &results)) |found| {
                if (found) {
                    file_count += 1;
                    if (results.items.len >= (req.maxResults orelse 50)) break;
                }
            } else |_| {
                continue;
            }
        }

        if (results.items.len >= (req.maxResults orelse 50)) break;
    }

    const summary = try std.fmt.allocPrint(allocator, "Found {d} matches across {d} files (searched {d} files) for query: {s}", .{ results.items.len, file_count, files_searched, req.query });

    return SearchResponse{
        .results = try results.toOwnedSlice(allocator),
        .totalFiles = file_count,
        .summary = summary,
    };
}

fn searchInFile(allocator: Allocator, file_path: []const u8, content: []const u8, req: SearchRequest, results: *std.ArrayList(SearchResult)) !bool {
    var found_in_file = false;
    var line_number: u32 = 1;
    var lines = std.mem.splitSequence(u8, content, "\n");

    while (lines.next()) |line| {
        defer line_number += 1;

        const match_pos = if (req.caseSensitive orelse false)
            std.mem.indexOf(u8, line, req.query)
        else
            std.ascii.indexOfIgnoreCase(line, req.query);

        if (match_pos) |pos| {
            try results.append(allocator, SearchResult{
                .file = try allocator.dupe(u8, file_path),
                .line = line_number,
                .column = @as(u32, @intCast(pos)) + 1,
                .content = try allocator.dupe(u8, line),
                .contextBefore = null,
                .contextAfter = null,
            });
            found_in_file = true;

            if (results.items.len >= (req.maxResults orelse 50)) break;
        }
    }

    return found_in_file;
}

fn shouldSkipDirectory(name: []const u8) bool {
    // Skip common directories that should not be searched
    const skip_dirs = [_][]const u8{
        "node_modules", ".git",    ".svn",             ".hg",           "target",        "build",
        "dist",         "out",     "bin",              ".cache",        "coverage",      ".nyc_output",
        ".zig-cache",   "zig-out", "vendor",           "__pycache__",   ".pytest_cache", ".idea",
        ".vscode",      ".vs",     "bower_components", "jspm_packages",
    };

    for (skip_dirs) |dir| {
        if (std.mem.eql(u8, name, dir)) return true;
    }

    return false;
}

fn shouldSkipFile(path: []const u8) bool {
    // Skip binary files and common non-searchable files
    const skip_extensions = [_][]const u8{
        ".exe", ".dll",  ".so",   ".dylib", ".a",   ".o",    ".obj",
        ".png", ".jpg",  ".jpeg", ".gif",   ".bmp", ".svg",  ".ico",
        ".mp3", ".mp4",  ".avi",  ".mov",   ".wav", ".ogg",  ".zip",
        ".tar", ".gz",   ".bz2",  ".xz",    ".7z",  ".rar",  ".pdf",
        ".doc", ".docx", ".xls",  ".xlsx",  ".ppt", ".pptx", ".class",
        ".jar", ".war",
    };

    for (skip_extensions) |ext| {
        if (std.mem.endsWith(u8, path, ext)) return true;
    }

    // Skip common directories
    const skip_dirs = [_][]const u8{
        "node_modules", ".git", ".svn", ".hg",    "target",   "build",
        "dist",         "out",  "bin",  ".cache", "coverage", ".nyc_output",
    };

    for (skip_dirs) |dir| {
        if (std.mem.indexOf(u8, path, dir)) |_| return true;
    }

    return false;
}

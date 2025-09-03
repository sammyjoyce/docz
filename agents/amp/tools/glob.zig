//! Glob file-matching tool for AMP agent.
//!
//! Implements specs/amp/prompts/amp-glob-tool.md:
//! - Inputs: filePattern (string), limit (?number), offset (?number)
//! - Output: JSON array of file paths sorted by modification time (most recent first)
//! - Behavior: Fast recursive search with basic glob syntax, including **, *, ?, {a,b}, and [a-z]

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;
const performance = @import("performance.zig");

const Allocator = std.mem.Allocator;

const Request = struct {
    filePattern: []const u8,
    limit: ?usize = null,
    offset: ?usize = null,
};

const Match = struct {
    path: []const u8,
    mtime: i128,
};

/// Public JSON tool entrypoint
pub fn run(allocator: Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    // Initialize performance tracking
    var perf = performance.ToolPerformance.init(allocator, "glob") catch {
        return runWithoutPerformanceTracking(allocator, params);
    };

    // Record input size
    // Record approximate input size (simplified for now)
    perf.recordInputSize(256);

    perf.startExecution();
    defer {
        perf.endExecution();

        if (performance.getGlobalRegistry()) |registry| {
            registry.recordToolExecution(&perf) catch {};
        }

        if (perf.generateReport()) |report| {
            allocator.free(report);
        } else |_| {}
    }

    const result = runWithoutPerformanceTracking(allocator, params);

    if (result) |_| {
        // Record approximate output size (simplified for now)
        perf.recordOutputSize(1024);
    } else |_| {}

    return result;
}

fn runWithoutPerformanceTracking(allocator: Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    // Manual parse for Zig 0.15.1 stability
    if (params != .object) return toolsMod.ToolError.InvalidInput;
    const obj = params.object;
    const pattern_val = obj.get("filePattern") orelse return toolsMod.ToolError.MissingParameter;
    if (pattern_val != .string) return toolsMod.ToolError.InvalidInput;
    const file_pattern = pattern_val.string;

    var limit_opt: ?usize = null;
    if (obj.get("limit")) |lv| switch (lv) {
        .integer => |iv| {
            if (iv < 0) return toolsMod.ToolError.InvalidInput;
            limit_opt = @as(usize, @intCast(iv));
        },
        .float => |fv| {
            if (fv < 0) return toolsMod.ToolError.InvalidInput;
            limit_opt = @as(usize, @intFromFloat(fv));
        },
        .null => {},
        else => return toolsMod.ToolError.InvalidInput,
    };

    var offset_opt: ?usize = null;
    if (obj.get("offset")) |ov| switch (ov) {
        .integer => |iv| {
            if (iv < 0) return toolsMod.ToolError.InvalidInput;
            offset_opt = @as(usize, @intCast(iv));
        },
        .float => |fv| {
            if (fv < 0) return toolsMod.ToolError.InvalidInput;
            offset_opt = @as(usize, @intFromFloat(fv));
        },
        .null => {},
        else => return toolsMod.ToolError.InvalidInput,
    };

    const req = Request{ .filePattern = file_pattern, .limit = limit_opt, .offset = offset_opt };

    // Expand braces in the pattern (e.g., "*.{js,ts}")
    var patterns = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer {
        for (patterns.items) |p| allocator.free(p);
        patterns.deinit(allocator);
    }
    try expandBraces(allocator, req.filePattern, &patterns);
    if (patterns.items.len == 0) {
        // Fallback to raw pattern if expansion produced nothing
        const dup = try allocator.dupe(u8, req.filePattern);
        try patterns.append(allocator, dup);
    }

    // Determine minimal base directory to search to reduce IO
    const base_dir = try computeBaseDir(allocator, req.filePattern);
    defer allocator.free(base_dir);

    // Collect candidate files under base_dir
    var matches = try std.ArrayList(Match).initCapacity(allocator, 0);
    defer {
        for (matches.items) |m| allocator.free(m.path);
        matches.deinit(allocator);
    }

    try walkAndMatch(allocator, base_dir, patterns.items, &matches);

    // Sort by modification time (desc), then path (asc) for stability
    std.mem.sort(Match, matches.items, {}, struct {
        fn lessThan(_: void, a: Match, b: Match) bool {
            if (a.mtime != b.mtime) return a.mtime > b.mtime; // newer first
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);

    // Apply offset/limit
    const off: usize = req.offset orelse 0;
    const start: usize = if (off > matches.items.len) matches.items.len else off;
    var end: usize = matches.items.len;
    if (req.limit) |lim| {
        const max_end = start + lim;
        if (max_end < end) end = max_end;
    }

    // Build JSON array of strings (paths)
    var arr = std.json.Array.init(allocator);
    errdefer arr.deinit();
    var i: usize = start;
    while (i < end) : (i += 1) {
        try arr.append(std.json.Value{ .string = matches.items[i].path });
    }

    return std.json.Value{ .array = arr };
}

// ---------------- Implementation Helpers ----------------

fn computeBaseDir(allocator: Allocator, pattern: []const u8) ![]const u8 {
    var last_slash: ?usize = null;
    var i: usize = 0;
    while (i < pattern.len) : (i += 1) {
        const c = pattern[i];
        if (c == '/') last_slash = i;
        if (c == '*' or c == '?' or c == '[' or c == '{') break;
    }
    if (i == pattern.len) {
        // No wildcards; if pattern names a file in a directory, base is dirname
        if (std.mem.lastIndexOfScalar(u8, pattern, '/')) |idx| {
            if (idx == 0) return allocator.dupe(u8, "/");
            return allocator.dupe(u8, pattern[0..idx]);
        }
        return allocator.dupe(u8, ".");
    }
    if (last_slash) |idx2| {
        if (idx2 == 0) return allocator.dupe(u8, "/");
        return allocator.dupe(u8, pattern[0..idx2]);
    }
    return allocator.dupe(u8, ".");
}

fn walkAndMatch(allocator: Allocator, base_dir: []const u8, patterns: [][]const u8, out: *std.ArrayList(Match)) !void {
    var stack = try std.ArrayList([]u8).initCapacity(allocator, 0);
    defer {
        for (stack.items) |p| allocator.free(p);
        stack.deinit(allocator);
    }

    try stack.append(allocator, try allocator.dupe(u8, base_dir));

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

            // Skip special or heavy directories commonly ignored
            if (entry.kind == .directory) {
                // Skip common heavy directories for performance
                if (shouldSkipDirectory(entry.name)) continue;

                // Build child directory path
                const child = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
                // Avoid cycles; continue recursion
                try stack.append(allocator, child);
                continue;
            }

            if (entry.kind != .file) continue;

            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
            // Compute relative path from CWD for matching
            const rel = full_path; // Already relative to cwd

            // Check against any of the expanded patterns
            var matched = false;
            for (patterns) |pat| {
                if (pathGlobMatch(allocator, rel, pat)) {
                    matched = true;
                    break;
                }
            }
            if (!matched) {
                allocator.free(full_path);
                continue;
            }

            // Stat for mtime
            const st = std.fs.cwd().statFile(rel) catch |err| switch (err) {
                else => blk: {
                    allocator.free(full_path);
                    break :blk null;
                },
            };
            if (st == null) continue;

            try out.append(allocator, .{ .path = full_path, .mtime = st.?.mtime });
        }
    }
}

fn pathGlobMatch(allocator: Allocator, path: []const u8, pattern: []const u8) bool {
    // Normalize: collapse any duplicate slashes in path for robustness
    // Split into segments
    var path_it = std.mem.splitScalar(u8, path, '/');
    var pat_it = std.mem.splitScalar(u8, pattern, '/');

    var pathSegs = std.ArrayList([]const u8).initCapacity(allocator, 0) catch return false;
    defer pathSegs.deinit(allocator);
    var patSegs = std.ArrayList([]const u8).initCapacity(allocator, 0) catch return false;
    defer patSegs.deinit(allocator);

    while (path_it.next()) |seg| {
        if (seg.len > 0) pathSegs.append(allocator, seg) catch return false;
    }
    while (pat_it.next()) |seg| {
        if (seg.len > 0) patSegs.append(allocator, seg) catch return false;
    }

    return matchSegments(pathSegs.items, patSegs.items, 0, 0);
}

fn matchSegments(pathSegs: [][]const u8, patSegs: [][]const u8, pi: usize, si: usize) bool {
    if (si == patSegs.len) return pi == pathSegs.len;
    if (si < patSegs.len and std.mem.eql(u8, patSegs[si], "**")) {
        // '**' matches zero or more segments
        var k: usize = pi;
        while (true) {
            if (matchSegments(pathSegs, patSegs, k, si + 1)) return true;
            if (k == pathSegs.len) break;
            k += 1;
        }
        return false;
    }
    if (pi == pathSegs.len) return false;
    if (!segmentMatch(pathSegs[pi], patSegs[si])) return false;
    return matchSegments(pathSegs, patSegs, pi + 1, si + 1);
}

fn segmentMatch(text: []const u8, pattern: []const u8) bool {
    var ti: usize = 0;
    var pi: usize = 0;
    var star_idx: ?usize = null;
    var match_idx: usize = 0;

    while (ti < text.len) {
        if (pi < pattern.len and pattern[pi] == '*') {
            star_idx = pi;
            pi += 1;
            match_idx = ti;
        } else if (pi < pattern.len and (pattern[pi] == '?' or charClassMatch(text[ti], pattern, &pi))) {
            if (pattern[pi] == '?') pi += 1; // '?' matches single char
            ti += 1;
        } else if (pi < pattern.len and pattern[pi] == text[ti]) {
            pi += 1;
            ti += 1;
        } else if (star_idx) |s| {
            // Backtrack to last '*'
            pi = s + 1;
            match_idx += 1;
            ti = match_idx;
        } else {
            return false;
        }
    }

    // Consume trailing '*'
    while (pi < pattern.len and pattern[pi] == '*') pi += 1;
    return pi == pattern.len;
}

fn charClassMatch(c: u8, pattern: []const u8, pi: *usize) bool {
    const idx = pi.*;
    if (idx >= pattern.len or pattern[idx] != '[') return false;
    var i: usize = idx + 1;
    var negate = false;
    if (i < pattern.len and pattern[i] == '!') {
        negate = true;
        i += 1;
    }
    var matched = false;
    while (i < pattern.len and pattern[i] != ']') {
        if (i + 2 < pattern.len and pattern[i + 1] == '-') {
            const start = pattern[i];
            const end = pattern[i + 2];
            if (start <= c and c <= end) matched = true;
            i += 3;
        } else {
            if (pattern[i] == c) matched = true;
            i += 1;
        }
    }
    if (i >= pattern.len or pattern[i] != ']') return false; // malformed -> no match
    pi.* = i + 1;
    return if (negate) !matched else matched;
}

fn expandBraces(allocator: Allocator, pattern: []const u8, out: *std.ArrayList([]const u8)) !void {
    // Find first {...}
    if (std.mem.indexOfScalar(u8, pattern, '{')) |start| {
        if (std.mem.indexOfScalarPos(u8, pattern, start + 1, '}')) |end| {
            const prefix = pattern[0..start];
            const body = pattern[start + 1 .. end];
            const suffix = pattern[end + 1 ..];

            var it = std.mem.splitScalar(u8, body, ',');
            while (it.next()) |alt| {
                const combined = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ prefix, alt, suffix });
                defer allocator.free(combined);
                try expandBraces(allocator, combined, out); // recurse for nested braces
            }
            return;
        }
    }
    // No braces -> append as-is
    try out.append(allocator, try allocator.dupe(u8, pattern));
}

fn shouldSkipDirectory(name: []const u8) bool {
    // Skip common heavy directories for performance
    const skip_dirs = [_][]const u8{ "node_modules", ".git", ".svn", ".hg", "target", "build", "dist", "out", "bin", ".cache", "coverage", ".nyc_output", ".zig-cache", "zig-out", "vendor", "__pycache__", ".pytest_cache", ".idea", ".vscode", ".vs", "bower_components", "jspm_packages", ".next", ".nuxt", ".docker" };

    for (skip_dirs) |dir| {
        if (std.mem.eql(u8, name, dir)) return true;
    }
    return false;
}

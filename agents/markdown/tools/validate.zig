const std = @import("std");
const json = std.json;
const tools = @import("foundation").tools;

/// Document validation tool for markdown
pub fn execute(allocator: std.mem.Allocator, params: json.Value) tools.ToolError!json.Value {
    var result = json.ObjectMap.init(allocator);

    // Extract parameters
    const obj = params.object;
    const content = obj.get("content") orelse {
        try result.put("success", json.Value{ .bool = false });
        try result.put("error", json.Value{ .string = "Missing 'content' parameter" });
        return json.Value{ .object = result };
    };

    const content_str = switch (content) {
        .string => |s| s,
        else => {
            try result.put("success", json.Value{ .bool = false });
            try result.put("error", json.Value{ .string = "Invalid 'content' type" });
            return json.Value{ .object = result };
        },
    };

    // Get validation rules (optional)
    const rules = obj.get("rules") orelse json.Value{ .null = {} };

    // Perform validation
    var issues = json.Array.init(allocator);
    var warnings = json.Array.init(allocator);
    var stats = json.ObjectMap.init(allocator);

    // Check for common markdown issues
    try validateStructure(allocator, content_str, &issues, &warnings);
    try validateLinks(allocator, content_str, &issues, &warnings);
    try validateCodeBlocks(allocator, content_str, &issues, &warnings);
    try validateHeadings(allocator, content_str, &issues, &warnings);

    // Apply custom rules if provided
    if (rules != .null) {
        try applyCustomRules(allocator, content_str, rules, &issues, &warnings);
    }

    // Calculate statistics
    try calculateStats(allocator, content_str, &stats);

    // Build result
    try result.put("success", json.Value{ .bool = true });
    try result.put("valid", json.Value{ .bool = issues.items.len == 0 });
    try result.put("issues", json.Value{ .array = issues });
    try result.put("warnings", json.Value{ .array = warnings });
    try result.put("stats", json.Value{ .object = stats });

    return json.Value{ .object = result };
}

/// Validate document structure
fn validateStructure(allocator: std.mem.Allocator, content: []const u8, issues: *json.Array, warnings: *json.Array) !void {
    // Check for empty document
    if (content.len == 0) {
        var issue = json.ObjectMap.init(allocator);
        try issue.put("type", json.Value{ .string = "empty_document" });
        try issue.put("message", json.Value{ .string = "Document is empty" });
        try issue.put("severity", json.Value{ .string = "error" });
        try issues.append(json.Value{ .object = issue });
    }

    // Check for missing title (first heading)
    if (!std.mem.startsWith(u8, content, "#")) {
        var warning_obj = json.ObjectMap.init(allocator);
        try warning_obj.put("type", json.Value{ .string = "missing_title" });
        try warning_obj.put("message", json.Value{ .string = "Document should start with a heading" });
        try warning_obj.put("severity", json.Value{ .string = "warning" });
        try warnings.append(json.Value{ .object = warning_obj });
    }
}

/// Validate links in the document
fn validateLinks(allocator: std.mem.Allocator, content: []const u8, issues: *json.Array, warnings: *json.Array) !void {
    _ = warnings;

    // Simple link detection pattern
    var iter = std.mem.tokenizeScalar(u8, content, '\n');
    var line_num: usize = 0;

    while (iter.next()) |line| {
        line_num += 1;

        // Check for broken reference links [text][ref]
        if (std.mem.indexOf(u8, line, "][") != null) {
            // Check if reference is defined
            const ref_start = std.mem.indexOf(u8, line, "][") orelse continue;
            const ref_end = std.mem.indexOf(u8, line[ref_start + 2 ..], "]") orelse continue;
            const ref = line[ref_start + 2 .. ref_start + 2 + ref_end];

            // Look for reference definition
            const ref_def_pattern = try std.fmt.allocPrint(allocator, "[{s}]:", .{ref});
            defer allocator.free(ref_def_pattern);

            if (std.mem.indexOf(u8, content, ref_def_pattern) == null) {
                var issue = json.ObjectMap.init(allocator);
                try issue.put("type", json.Value{ .string = "broken_reference" });
                try issue.put("message", json.Value{ .string = try std.fmt.allocPrint(allocator, "Undefined reference: {s}", .{ref}) });
                try issue.put("line", json.Value{ .integer = @intCast(line_num) });
                try issue.put("severity", json.Value{ .string = "error" });
                try issues.append(json.Value{ .object = issue });
            }
        }
    }
}

/// Validate code blocks
fn validateCodeBlocks(allocator: std.mem.Allocator, content: []const u8, issues: *json.Array, warnings: *json.Array) !void {
    _ = issues;

    var in_code_block = false;
    var code_block_start: usize = 0;
    var has_language = false;

    var iter = std.mem.tokenizeAny(u8, content, "\n");
    var line_num: usize = 0;

    while (iter.next()) |line| {
        line_num += 1;

        if (std.mem.startsWith(u8, line, "```")) {
            if (!in_code_block) {
                in_code_block = true;
                code_block_start = line_num;
                has_language = line.len > 3 and !std.mem.allEqual(u8, line[3..], ' ');

                if (!has_language) {
                    var warning_obj = json.ObjectMap.init(allocator);
                    try warning_obj.put("type", json.Value{ .string = "missing_language" });
                    try warning_obj.put("message", json.Value{ .string = "Code block without language specifier" });
                    try warning_obj.put("line", json.Value{ .integer = @intCast(line_num) });
                    try warning_obj.put("severity", json.Value{ .string = "warning" });
                    try warnings.append(json.Value{ .object = warning_obj });
                }
            } else {
                in_code_block = false;
            }
        }
    }

    // Check for unclosed code blocks
    if (in_code_block) {
        var issue = json.ObjectMap.init(allocator);
        try issue.put("type", json.Value{ .string = "unclosed_code_block" });
        try issue.put("message", json.Value{ .string = "Code block not closed" });
        try issue.put("line", json.Value{ .integer = @intCast(code_block_start) });
        try issue.put("severity", json.Value{ .string = "error" });
        try warnings.append(json.Value{ .object = issue });
    }
}

/// Validate heading hierarchy
fn validateHeadings(allocator: std.mem.Allocator, content: []const u8, issues: *json.Array, warnings: *json.Array) !void {
    _ = issues;

    var prev_level: usize = 0;
    var iter = std.mem.tokenizeAny(u8, content, "\n");
    var line_num: usize = 0;

    while (iter.next()) |line| {
        line_num += 1;

        if (std.mem.startsWith(u8, line, "#")) {
            // Count heading level
            var level: usize = 0;
            for (line) |c| {
                if (c == '#') {
                    level += 1;
                } else {
                    break;
                }
            }

            // Check for skipped levels
            if (prev_level > 0 and level > prev_level + 1) {
                var warning_obj = json.ObjectMap.init(allocator);
                try warning_obj.put("type", json.Value{ .string = "skipped_heading_level" });
                try warning_obj.put("message", json.Value{ .string = try std.fmt.allocPrint(allocator, "Skipped heading level from H{} to H{}", .{ prev_level, level }) });
                try warning_obj.put("line", json.Value{ .integer = @intCast(line_num) });
                try warning_obj.put("severity", json.Value{ .string = "warning" });
                try warnings.append(json.Value{ .object = warning_obj });
            }

            prev_level = level;
        }
    }
}

/// Apply custom validation rules
fn applyCustomRules(allocator: std.mem.Allocator, content: []const u8, rules: json.Value, issues: *json.Array, warnings: *json.Array) !void {
    _ = allocator;
    _ = content;
    _ = rules;
    _ = issues;
    _ = warnings;
    // Custom rules would be applied here based on the rules parameter
}

/// Calculate document statistics
fn calculateStats(_: std.mem.Allocator, content: []const u8, stats: *json.ObjectMap) !void {
    // Line count
    const line_count = std.mem.count(u8, content, "\n") + 1;
    try stats.put("lines", json.Value{ .integer = @intCast(line_count) });

    // Word count
    var word_count: usize = 0;
    var iter = std.mem.tokenizeAny(u8, content, " \n\t\r");
    while (iter.next()) |_| {
        word_count += 1;
    }
    try stats.put("words", json.Value{ .integer = @intCast(word_count) });

    // Character count
    try stats.put("characters", json.Value{ .integer = @intCast(content.len) });

    // Heading count
    var heading_count: usize = 0;
    var line_iter = std.mem.tokenizeAny(u8, content, "\n");
    while (line_iter.next()) |line| {
        if (std.mem.startsWith(u8, line, "#")) {
            heading_count += 1;
        }
    }
    try stats.put("headings", json.Value{ .integer = @intCast(heading_count) });

    // Code block count
    const code_block_count = std.mem.count(u8, content, "```") / 2;
    try stats.put("code_blocks", json.Value{ .integer = @intCast(code_block_count) });

    // Link count (simple detection)
    const link_count = std.mem.count(u8, content, "](");
    try stats.put("links", json.Value{ .integer = @intCast(link_count) });
}

const std = @import("std");

pub const Error = error{
    InvalidPattern,
    OutOfMemory,
    InvalidRange,
};

pub const SearchOptions = struct {
    case_sensitive: bool = false,
    whole_words: bool = false,
    regex_mode: bool = false,
    max_results: ?u32 = null,
};

pub const SearchResult = struct {
    line: u32,
    column: u32,
    match: []const u8,
    context_before: ?[]const u8 = null,
    context_after: ?[]const u8 = null,
};

/// Find all occurrences of a pattern in text
pub fn findAll(allocator: std.mem.Allocator, text: []const u8, pattern: []const u8, options: SearchOptions) Error![]SearchResult {
    var results = std.array_list.Managed(SearchResult).init(allocator);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var lineNum: usize = 0;
    var foundCount: usize = 0;

    const max_results: usize = if (options.max_results) |mr| @as(usize, mr) else std.math.maxInt(usize);

    while (lines.next()) |line| : (lineNum += 1) {
        if (foundCount >= max_results) break;

        const searchText = if (options.case_sensitive) line else blk: {
            var lowerLine = try allocator.alloc(u8, line.len);
            for (line, 0..) |c, i| {
                lowerLine[i] = std.ascii.toLower(c);
            }
            break :blk lowerLine;
        };
        defer if (!options.case_sensitive) allocator.free(searchText);

        const searchPattern = if (options.case_sensitive) pattern else blk: {
            var lowerPattern = try allocator.alloc(u8, pattern.len);
            for (pattern, 0..) |c, i| {
                lowerPattern[i] = std.ascii.toLower(c);
            }
            break :blk lowerPattern;
        };
        defer if (!options.case_sensitive) allocator.free(searchPattern);

        var col: usize = 0;
        while (std.mem.indexOf(u8, searchText[col..], searchPattern)) |pos| {
            const absPos = col + pos;

            // Check whole words if requested
            if (options.whole_words) {
                const beforeOk = absPos == 0 or !isWordChar(searchText[absPos - 1]);
                const afterPos = absPos + searchPattern.len;
                const afterOk = afterPos >= searchText.len or !isWordChar(searchText[afterPos]);

                if (!beforeOk or !afterOk) {
                    col = absPos + 1;
                    continue;
                }
            }

            const result = SearchResult{
                .line = @as(u32, @intCast(@min(lineNum, std.math.maxInt(u32)))),
                .column = @as(u32, @intCast(@min(absPos, std.math.maxInt(u32)))),
                .match = line[absPos .. absPos + pattern.len],
            };

            try results.append(result);
            foundCount += 1;

            if (foundCount >= max_results) break;
            col = absPos + 1;
        }
    }

    return results.toOwnedSlice();
}

/// Replace all occurrences of a pattern
pub fn replaceAll(allocator: std.mem.Allocator, text: []const u8, pattern: []const u8, replacement: []const u8, options: SearchOptions) Error![]u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var remaining = text;
    var replaced_count: usize = 0;
    const max_replacements: usize = if (options.max_results) |mr| @as(usize, mr) else std.math.maxInt(usize);

    while (replaced_count < max_replacements) {
        const pos = if (options.case_sensitive)
            std.mem.indexOf(u8, remaining, pattern)
        else
            indexOfIgnoreCase(remaining, pattern);

        if (pos == null) break;

        const actual_pos = pos.?;

        // Check whole words if requested
        if (options.whole_words) {
            const before_ok = actual_pos == 0 or !isWordChar(remaining[actual_pos - 1]);
            const after_pos = actual_pos + pattern.len;
            const after_ok = after_pos >= remaining.len or !isWordChar(remaining[after_pos]);

            if (!before_ok or !after_ok) {
                try result.appendSlice(allocator, remaining[0 .. actual_pos + 1]);
                remaining = remaining[actual_pos + 1 ..];
                continue;
            }
        }

        // Add text before match
        try result.appendSlice(allocator, remaining[0..actual_pos]);
        // Add replacement
        try result.appendSlice(allocator, replacement);

        remaining = remaining[actual_pos + pattern.len ..];
        replaced_count += 1;
    }

    // Add remaining text
    try result.appendSlice(allocator, remaining);

    return result.toOwnedSlice();
}

/// Wrap text to specified width
pub fn wrapText(allocator: std.mem.Allocator, text: []const u8, width: usize) Error![]u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var lines = std.mem.splitScalar(u8, text, '\n');

    while (lines.next()) |line| {
        if (line.len <= width) {
            try result.appendSlice(allocator, line);
            try result.append(allocator, '\n');
            continue;
        }

        var remaining = line;
        while (remaining.len > width) {
            // Find last space before width
            var break_pos = width;
            while (break_pos > 0 and remaining[break_pos] != ' ') {
                break_pos -= 1;
            }

            // If no space found, break at width
            if (break_pos == 0) break_pos = width;

            try result.appendSlice(allocator, remaining[0..break_pos]);
            try result.append(allocator, '\n');

            // Skip space if that's where we broke
            if (break_pos < remaining.len and remaining[break_pos] == ' ') {
                break_pos += 1;
            }

            remaining = remaining[break_pos..];
        }

        if (remaining.len > 0) {
            try result.appendSlice(allocator, remaining);
            try result.append(allocator, '\n');
        }
    }

    return result.toOwnedSlice();
}

/// Normalize whitespace in text
pub fn normalizeWhitespace(allocator: std.mem.Allocator, text: []const u8) Error![]u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    var in_whitespace = false;

    for (text) |char| {
        if (std.ascii.isWhitespace(char)) {
            if (!in_whitespace) {
                try result.append(allocator, ' ');
                in_whitespace = true;
            }
        } else {
            try result.append(allocator, char);
            in_whitespace = false;
        }
    }

    return result.toOwnedSlice();
}

/// Get lines in a range
pub fn getLines(text: []const u8, start_line: usize, end_line: usize) Error![]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var current_line: usize = 0;
    var start_pos: usize = 0;
    var end_pos: usize = text.len;

    // Find start position
    while (lines.next()) |line| {
        if (current_line == start_line) {
            break;
        }
        start_pos += line.len + 1; // +1 for newline
        current_line += 1;
    }

    if (current_line != start_line) {
        return Error.InvalidRange;
    }

    // Find end position
    while (lines.next()) |_| {
        current_line += 1;
        if (current_line > end_line) {
            end_pos = start_pos + (lines.index orelse text.len) - start_pos;
            break;
        }
    }

    if (end_pos > text.len) end_pos = text.len;
    if (start_pos >= end_pos) return Error.InvalidRange;

    return text[start_pos..end_pos];
}

// Helper functions
fn isWordChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn indexOfIgnoreCase(text: []const u8, pattern: []const u8) ?usize {
    if (pattern.len > text.len) return null;

    var i: usize = 0;
    while (i <= text.len - pattern.len) {
        var match = true;
        for (pattern, 0..) |p_char, j| {
            if (std.ascii.toLower(text[i + j]) != std.ascii.toLower(p_char)) {
                match = false;
                break;
            }
        }
        if (match) return i;
        i += 1;
    }

    return null;
}

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
    max_results: ?usize = null,
};

pub const SearchResult = struct {
    line: usize,
    column: usize,
    match: []const u8,
    context_before: ?[]const u8 = null,
    context_after: ?[]const u8 = null,
};

/// Find all occurrences of a pattern in text
pub fn findAll(allocator: std.mem.Allocator, text: []const u8, pattern: []const u8, options: SearchOptions) Error![]SearchResult {
    var results = std.ArrayList(SearchResult).init(allocator);
    var lines = std.mem.split(u8, text, "\n");
    var line_num: usize = 0;
    var found_count: usize = 0;

    const max_results = options.max_results orelse std.math.maxInt(usize);

    while (lines.next()) |line| : (line_num += 1) {
        if (found_count >= max_results) break;

        const search_text = if (options.case_sensitive) line else blk: {
            var lower_line = try allocator.alloc(u8, line.len);
            for (line, 0..) |c, i| {
                lower_line[i] = std.ascii.toLower(c);
            }
            break :blk lower_line;
        };
        defer if (!options.case_sensitive) allocator.free(search_text);

        const search_pattern = if (options.case_sensitive) pattern else blk: {
            var lower_pattern = try allocator.alloc(u8, pattern.len);
            for (pattern, 0..) |c, i| {
                lower_pattern[i] = std.ascii.toLower(c);
            }
            break :blk lower_pattern;
        };
        defer if (!options.case_sensitive) allocator.free(search_pattern);

        var col: usize = 0;
        while (std.mem.indexOf(u8, search_text[col..], search_pattern)) |pos| {
            const abs_pos = col + pos;

            // Check whole words if requested
            if (options.whole_words) {
                const before_ok = abs_pos == 0 or !isWordChar(search_text[abs_pos - 1]);
                const after_pos = abs_pos + search_pattern.len;
                const after_ok = after_pos >= search_text.len or !isWordChar(search_text[after_pos]);

                if (!before_ok or !after_ok) {
                    col = abs_pos + 1;
                    continue;
                }
            }

            const result = SearchResult{
                .line = line_num,
                .column = abs_pos,
                .match = line[abs_pos .. abs_pos + pattern.len],
            };

            try results.append(result);
            found_count += 1;

            if (found_count >= max_results) break;
            col = abs_pos + 1;
        }
    }

    return results.toOwnedSlice();
}

/// Replace all occurrences of a pattern
pub fn replaceAll(allocator: std.mem.Allocator, text: []const u8, pattern: []const u8, replacement: []const u8, options: SearchOptions) Error![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var remaining = text;
    var replaced_count: usize = 0;
    const max_replacements = options.max_results orelse std.math.maxInt(usize);

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
                try result.appendSlice(remaining[0 .. actual_pos + 1]);
                remaining = remaining[actual_pos + 1 ..];
                continue;
            }
        }

        // Add text before match
        try result.appendSlice(remaining[0..actual_pos]);
        // Add replacement
        try result.appendSlice(replacement);

        remaining = remaining[actual_pos + pattern.len ..];
        replaced_count += 1;
    }

    // Add remaining text
    try result.appendSlice(remaining);

    return result.toOwnedSlice();
}

/// Wrap text to specified width
pub fn wrapText(allocator: std.mem.Allocator, text: []const u8, width: usize) Error![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var lines = std.mem.split(u8, text, "\n");

    while (lines.next()) |line| {
        if (line.len <= width) {
            try result.appendSlice(line);
            try result.append('\n');
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

            try result.appendSlice(remaining[0..break_pos]);
            try result.append('\n');

            // Skip space if that's where we broke
            if (break_pos < remaining.len and remaining[break_pos] == ' ') {
                break_pos += 1;
            }

            remaining = remaining[break_pos..];
        }

        if (remaining.len > 0) {
            try result.appendSlice(remaining);
            try result.append('\n');
        }
    }

    return result.toOwnedSlice();
}

/// Normalize whitespace in text
pub fn normalizeWhitespace(allocator: std.mem.Allocator, text: []const u8) Error![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var in_whitespace = false;

    for (text) |char| {
        if (std.ascii.isWhitespace(char)) {
            if (!in_whitespace) {
                try result.append(' ');
                in_whitespace = true;
            }
        } else {
            try result.append(char);
            in_whitespace = false;
        }
    }

    return result.toOwnedSlice();
}

/// Get lines in a range
pub fn getLines(text: []const u8, start_line: usize, end_line: usize) Error![]const u8 {
    var lines = std.mem.split(u8, text, "\n");
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

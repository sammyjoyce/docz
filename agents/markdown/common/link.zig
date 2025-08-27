const std = @import("std");

pub const Error = error{
    InvalidUrl,
    OutOfMemory,
    NetworkError,
    Timeout,
};

pub const LinkType = enum {
    internal,
    external,
    anchor,
    image,
    reference,
};

pub const Link = struct {
    text: []const u8,
    url: []const u8,
    title: ?[]const u8,
    type: LinkType,
    line: usize,
    column: usize,
};

/// Parse a markdown link
pub fn parseLink(text: []const u8, start_pos: usize) ?Link {
    if (start_pos >= text.len or text[start_pos] != '[') return null;

    // Find closing bracket
    var pos = start_pos + 1;
    var bracket_count: usize = 1;
    var link_text_end: ?usize = null;

    while (pos < text.len and bracket_count > 0) {
        switch (text[pos]) {
            '[' => bracket_count += 1,
            ']' => {
                bracket_count -= 1;
                if (bracket_count == 0) link_text_end = pos;
            },
            else => {},
        }
        pos += 1;
    }

    if (link_text_end == null) return null;
    const text_end = link_text_end.?;

    // Check for link URL
    if (pos >= text.len or text[pos] != '(') return null;
    pos += 1; // Skip '('

    const url_start = pos;
    var url_end: ?usize = null;
    var paren_count: usize = 1;

    while (pos < text.len and paren_count > 0) {
        switch (text[pos]) {
            '(' => paren_count += 1,
            ')' => {
                paren_count -= 1;
                if (paren_count == 0) url_end = pos;
            },
            else => {},
        }
        pos += 1;
    }

    if (url_end == null) return null;

    const link_text = text[start_pos + 1 .. text_end];
    const link_url = text[url_start..url_end.?];

    return Link{
        .text = link_text,
        .url = link_url,
        .title = null,
        .type = classifyLink(link_url),
        .line = 0, // Will be set by caller
        .column = start_pos,
    };
}

/// Find all links in markdown text
pub fn findLinks(allocator: std.mem.Allocator, text: []const u8) Error![]Link {
    var links = std.ArrayListUnmanaged(Link){};
    defer links.deinit(allocator);
    var lines = std.mem.splitSequence(u8, text, "\n");
    var line_num: usize = 0;

    while (lines.next()) |line| : (line_num += 1) {
        var pos: usize = 0;

        while (pos < line.len) {
            if (line[pos] == '[') {
                if (parseLink(line, pos)) |link| {
                    var found_link = link;
                    found_link.line = line_num;
                    try links.append(allocator, found_link);
                    pos = link.column + link.text.len + link.url.len + 4; // Skip past this link
                } else {
                    pos += 1;
                }
            } else {
                pos += 1;
            }
        }
    }

    return links.toOwnedSlice(allocator);
}

/// Classify a link by type
pub fn classifyLink(url: []const u8) LinkType {
    if (url.len == 0) return .internal;

    // Check for anchor links
    if (url[0] == '#') return .anchor;

    // Check for external URLs
    if (std.mem.startsWith(u8, url, "http://") or
        std.mem.startsWith(u8, url, "https://") or
        std.mem.startsWith(u8, url, "ftp://"))
    {
        return .external;
    }

    // Check for image extensions
    var lower_url_buf: [1024]u8 = undefined;
    const lower_url = std.ascii.lowerString(&lower_url_buf, url);
    if (std.mem.endsWith(u8, lower_url, ".png") or
        std.mem.endsWith(u8, lower_url, ".jpg") or
        std.mem.endsWith(u8, lower_url, ".jpeg") or
        std.mem.endsWith(u8, lower_url, ".gif") or
        std.mem.endsWith(u8, lower_url, ".svg"))
    {
        return .image;
    }

    return .internal;
}

/// Resolve a relative path against a base path
pub fn resolveRelativePath(allocator: std.mem.Allocator, base_path: []const u8, relative_path: []const u8) Error![]u8 {
    if (std.fs.path.isAbsolute(relative_path)) {
        return allocator.dupe(u8, relative_path);
    }

    const base_dir = std.fs.path.dirname(base_path) orelse "";
    return std.fs.path.resolve(allocator, &[_][]const u8{ base_dir, relative_path });
}

/// Normalize a URL (remove fragments, resolve .., etc.)
pub fn normalizeUrl(allocator: std.mem.Allocator, url: []const u8) Error![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    // Remove fragment
    const fragment_pos = std.mem.indexOf(u8, url, "#");
    const clean_url = if (fragment_pos) |pos| url[0..pos] else url;

    // Basic path resolution for relative paths
    var parts = std.mem.split(u8, clean_url, "/");
    var resolved_parts = std.ArrayList([]const u8).init(allocator);
    defer resolved_parts.deinit();

    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, ".")) {
            continue; // Current directory, skip
        } else if (std.mem.eql(u8, part, "..")) {
            // Parent directory, pop if possible
            if (resolved_parts.items.len > 0) {
                _ = resolved_parts.pop();
            }
        } else if (part.len > 0) {
            try resolved_parts.append(part);
        }
    }

    // Rebuild URL
    for (resolved_parts.items, 0..) |part, i| {
        if (i > 0) try result.append('/');
        try result.appendSlice(part);
    }

    return result.toOwnedSlice();
}

/// Check if URL is accessible (basic validation)
pub fn validateUrl(url: []const u8) bool {
    if (url.len == 0) return false;

    // Check for valid URL characters
    for (url) |c| {
        if (!std.ascii.isPrint(c) or c == ' ') return false;
    }

    // Basic format checks
    if (std.mem.startsWith(u8, url, "http://") or
        std.mem.startsWith(u8, url, "https://"))
    {
        return url.len > 7; // Has content after protocol
    }

    // Local paths should not have invalid characters
    const invalid_chars = "<>:\"|?*";
    for (invalid_chars) |invalid| {
        if (std.mem.indexOf(u8, url, &[_]u8{invalid}) != null) {
            return false;
        }
    }

    return true;
}

/// Create a markdown link
pub fn createLink(allocator: std.mem.Allocator, text: []const u8, url: []const u8, title: ?[]const u8) Error![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    try result.append('[');
    try result.appendSlice(text);
    try result.append(']');
    try result.append('(');
    try result.appendSlice(url);

    if (title) |t| {
        try result.appendSlice(" \"");
        try result.appendSlice(t);
        try result.append('"');
    }

    try result.append(')');

    return result.toOwnedSlice();
}

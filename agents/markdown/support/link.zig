const std = @import("std");

pub const Error = error{
    InvalidURL,
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
    line: u32,
    column: u32,
};

/// Parse a markdown link
pub fn parseLink(text: []const u8, start_pos: usize) ?Link {
    if (start_pos >= text.len or text[start_pos] != '[') return null;

    // Find closing bracket
    var pos = start_pos + 1;
    var bracketCount: usize = 1;
    var linkTextEnd: ?usize = null;

    while (pos < text.len and bracketCount > 0) {
        switch (text[pos]) {
            '[' => bracketCount += 1,
            ']' => {
                bracketCount -= 1;
                if (bracketCount == 0) linkTextEnd = pos;
            },
            else => {},
        }
        pos += 1;
    }

    if (linkTextEnd == null) return null;
    const textEnd = linkTextEnd.?;

    // Check for link URL
    if (pos >= text.len or text[pos] != '(') return null;
    pos += 1; // Skip '('

    const urlStart = pos;
    var urlEnd: ?usize = null;
    var parenCount: usize = 1;

    while (pos < text.len and parenCount > 0) {
        switch (text[pos]) {
            '(' => parenCount += 1,
            ')' => {
                parenCount -= 1;
                if (parenCount == 0) urlEnd = pos;
            },
            else => {},
        }
        pos += 1;
    }

    if (urlEnd == null) return null;

    const linkText = text[start_pos + 1 .. textEnd];
    const linkURL = text[urlStart..urlEnd.?];

    return Link{
        .text = linkText,
        .url = linkURL,
        .title = null,
        .type = classifyLink(linkURL),
        .line = 0, // Will be set by caller
        .column = @as(u32, @intCast(@min(start_pos, std.math.maxInt(u32)))),
    };
}

/// Find all links in markdown text
pub fn findLinks(allocator: std.mem.Allocator, text: []const u8) Error![]Link {
    var links = std.ArrayListUnmanaged(Link){};
    defer links.deinit(allocator);
    var lines = std.mem.splitSequence(u8, text, "\n");
    var lineNum: usize = 0;

    while (lines.next()) |line| : (lineNum += 1) {
        var pos: usize = 0;

        while (pos < line.len) {
            if (line[pos] == '[') {
                if (parseLink(line, pos)) |link| {
                    var foundLink = link;
                    foundLink.line = @as(u32, @intCast(@min(lineNum, std.math.maxInt(u32))));
                    try links.append(allocator, foundLink);
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
pub fn resolveRelativePath(allocator: std.mem.Allocator, basePath: []const u8, relativePath: []const u8) Error![]u8 {
    if (std.fs.path.isAbsolute(relativePath)) {
        return allocator.dupe(u8, relativePath);
    }

    const baseDir = std.fs.path.dirname(basePath) orelse "";
    return std.fs.path.resolve(allocator, &[_][]const u8{ baseDir, relativePath });
}

/// Normalize a URL (remove fragments, resolve .., etc.)
pub fn normalizeURL(allocator: std.mem.Allocator, url: []const u8) Error![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    // Remove fragment
    const fragmentPos = std.mem.indexOf(u8, url, "#");
    const cleanUrl = if (fragmentPos) |pos| url[0..pos] else url;

    // Basic path resolution for relative paths
    var parts = std.mem.split(u8, cleanUrl, "/");
    var resolvedParts = std.ArrayList([]const u8).init(allocator);
    defer resolvedParts.deinit();

    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, ".")) {
            continue; // Current directory, skip
        } else if (std.mem.eql(u8, part, "..")) {
            // Parent directory, pop if possible
            if (resolvedParts.items.len > 0) {
                _ = resolvedParts.pop();
            }
        } else if (part.len > 0) {
            try resolvedParts.append(part);
        }
    }

    // Rebuild URL
    for (resolvedParts.items, 0..) |part, i| {
        if (i > 0) try result.append('/');
        try result.appendSlice(part);
    }

    return result.toOwnedSlice();
}

/// Check if URL is accessible (validation)
pub fn validateURL(url: []const u8) bool {
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

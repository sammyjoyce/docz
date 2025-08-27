const std = @import("std");
const json = std.json;
const fs = @import("../common/fs.zig");
const text = @import("../common/text.zig");
const link = @import("../common/link.zig");

pub const Error = fs.Error || text.Error || link.Error || error{
    InvalidSection,
    UnknownCommand,
    InvalidParameters,
};

pub const Command = enum {
    read_file,
    read_multiple,
    read_section,
    search_content,
    search_pattern,
    find_references,
    list_directory,
    find_files,
    get_workspace_tree,

    pub fn fromString(str: []const u8) ?Command {
        return std.meta.stringToEnum(Command, str);
    }
};

/// Main entry point for document I/O operations
pub fn execute(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    return executeInternal(allocator, params) catch |err| {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("error", json.Value{ .string = @errorName(err) });
        try result.put("tool", json.Value{ .string = "document_io" });
        return json.Value{ .object = result };
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    const params_obj = params.object;

    const command_str = params_obj.get("command").?.string;
    const command = Command.fromString(command_str) orelse return Error.UnknownCommand;

    return switch (command) {
        .read_file => readFile(allocator, params_obj),
        .read_multiple => readMultiple(allocator, params_obj),
        .read_section => readSection(allocator, params_obj),
        .search_content => searchContent(allocator, params_obj),
        .search_pattern => searchPattern(allocator, params_obj),
        .find_references => findReferences(allocator, params_obj),
        .list_directory => listDirectory(allocator, params_obj),
        .find_files => findFiles(allocator, params_obj),
        .get_workspace_tree => getWorkspaceTree(allocator, params_obj),
    };
}

/// Read a single file
fn readFile(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const file_path = params.get("file_path").?.string;
    const include_metadata = params.get("include_metadata").?.bool;

    const content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(content);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "document_io" });
    try result.put("command", json.Value{ .string = "read_file" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("content", json.Value{ .string = try allocator.dupe(u8, content) });

    if (include_metadata) {
        const file_metadata = try fs.getFileInfo(file_path);
        var metadata = json.ObjectMap.init(allocator);
        try metadata.put("size", json.Value{ .integer = @intCast(file_metadata.size) });
        try metadata.put("modified", json.Value{ .integer = file_metadata.modified });
        try metadata.put("is_file", json.Value{ .bool = file_metadata.is_file });
        try metadata.put("is_dir", json.Value{ .bool = file_metadata.is_dir });
        try result.put("metadata", json.Value{ .object = metadata });
    }

    return json.Value{ .object = result };
}

/// Read multiple files
fn readMultiple(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const file_paths_array = params.get("file_paths").?.array;
    const include_metadata = params.get("include_metadata") orelse json.Value{ .bool = true };

    var files = json.ObjectMap.init(allocator);

    for (file_paths_array.items) |file_path_json| {
        const file_path = file_path_json.string;

        const content = fs.readFileAlloc(allocator, file_path, null) catch |err| switch (err) {
            fs.Error.FileNotFound => continue, // Skip missing files
            else => return err,
        };
        defer allocator.free(content);

        var file_data = json.ObjectMap.init(allocator);
        try file_data.put("content", json.Value{ .string = try allocator.dupe(u8, content) });

        if (include_metadata.bool) {
            const file_metadata = fs.getFileInfo(file_path) catch continue;
            var metadata = json.ObjectMap.init(allocator);
            try metadata.put("size", json.Value{ .integer = @intCast(file_metadata.size) });
            try metadata.put("modified", json.Value{ .integer = file_metadata.modified });
            try file_data.put("metadata", json.Value{ .object = metadata });
        }

        try files.put(file_path, json.Value{ .object = file_data });
    }

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "document_io" });
    try result.put("command", json.Value{ .string = "read_multiple" });
    try result.put("files", json.Value{ .object = files });

    return json.Value{ .object = result };
}

/// Read a specific section of a file
fn readSection(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const file_path = params.get("file_path").?.string;
    const section_id = params.get("section_identifier").?.string;

    const full_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(full_content);

    const section_content = if (std.mem.startsWith(u8, section_id, "heading:")) blk: {
        const heading_text = section_id[8..]; // Skip "heading:"
        break :blk try extractHeadingSection(allocator, full_content, heading_text);
    } else if (std.mem.startsWith(u8, section_id, "lines:")) blk: {
        const range_text = section_id[6..]; // Skip "lines:"
        const dash_pos = std.mem.indexOf(u8, range_text, "-") orelse return Error.InvalidSection;
        const start_line = std.fmt.parseInt(usize, range_text[0..dash_pos], 10) catch return Error.InvalidSection;
        const end_line = std.fmt.parseInt(usize, range_text[dash_pos + 1 ..], 10) catch return Error.InvalidSection;
        break :blk try text.getLines(full_content, start_line, end_line);
    } else if (std.mem.eql(u8, section_id, "front_matter")) blk: {
        break :blk extractFrontMatter(full_content);
    } else {
        return Error.InvalidSection;
    };

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "document_io" });
    try result.put("command", json.Value{ .string = "read_section" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("section", json.Value{ .string = section_id });
    try result.put("content", json.Value{ .string = try allocator.dupe(u8, section_content) });

    return json.Value{ .object = result };
}

/// Search for content across files
fn searchContent(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const query = params.get("query").?.string;
    const search_opts_json = params.get("search_options") orelse json.Value{ .object = json.ObjectMap.init(allocator) };
    const file_patterns_json = params.get("file_patterns") orelse json.Value{ .array = json.Array.init(allocator) };

    var search_options = text.SearchOptions{};
    if (search_opts_json == .object) {
        const opts = search_opts_json.object;
        search_options.case_sensitive = opts.get("case_sensitive").?.bool;
        search_options.whole_words = opts.get("whole_words").?.bool;
        search_options.regex_mode = opts.get("regex_mode").?.bool;
        search_options.max_results = if (opts.get("max_results")) |mr| @intCast(mr.integer) else null;
    }

    // Get files to search
    var file_list = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (file_list.items) |path| allocator.free(path);
        file_list.deinit(allocator);
    }

    if (file_patterns_json == .array) {
        for (file_patterns_json.array.items) |pattern_json| {
            const pattern = pattern_json.string;
            const files = try findFilesByPattern(allocator, pattern);
            defer {
                for (files) |path| allocator.free(path);
                allocator.free(files);
            }

            for (files) |path| {
                try file_list.append(allocator, try allocator.dupe(u8, path));
            }
        }
    } else {
        // Default to current directory markdown files
        const files = try findFilesByPattern(allocator, "*.md");
        defer {
            for (files) |path| allocator.free(path);
            allocator.free(files);
        }

        for (files) |path| {
            try file_list.append(allocator, try allocator.dupe(u8, path));
        }
    }

    // Search in all files
    var all_results = json.Array.init(allocator);

    for (file_list.items) |file_path| {
        const content = fs.readFileAlloc(allocator, file_path, null) catch continue;
        defer allocator.free(content);

        const results = try text.findAll(allocator, content, query, search_options);
        defer allocator.free(results);

        for (results) |match| {
            var match_obj = json.ObjectMap.init(allocator);
            try match_obj.put("file", json.Value{ .string = try allocator.dupe(u8, file_path) });
            try match_obj.put("line", json.Value{ .integer = @intCast(match.line) });
            try match_obj.put("column", json.Value{ .integer = @intCast(match.column) });
            try match_obj.put("match", json.Value{ .string = try allocator.dupe(u8, match.match) });

            try all_results.append(json.Value{ .object = match_obj });
        }
    }

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "document_io" });
    try result.put("command", json.Value{ .string = "search_content" });
    try result.put("query", json.Value{ .string = query });
    try result.put("results", json.Value{ .array = all_results });

    return json.Value{ .object = result };
}

/// Search using patterns (regex support)
fn searchPattern(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    // For now, delegate to searchContent with regex enabled
    var modified_params = params;
    var search_options = json.ObjectMap.init(allocator);
    try search_options.put("regex_mode", json.Value{ .bool = true });
    try modified_params.put("search_options", json.Value{ .object = search_options });

    return searchContent(allocator, modified_params);
}

/// Find references to specific content
fn findReferences(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const query = params.get("query").?.string;

    // Look for markdown links, images, and other references
    var all_results = json.Array.init(allocator);

    const files = try findFilesByPattern(allocator, "*.md");
    defer {
        for (files) |path| allocator.free(path);
        allocator.free(files);
    }

    for (files) |file_path| {
        const content = fs.readFileAlloc(allocator, file_path, null) catch continue;
        defer allocator.free(content);

        const links = try link.findLinks(allocator, content);
        defer allocator.free(links);

        for (links) |found_link| {
            if (std.mem.indexOf(u8, found_link.text, query) != null or
                std.mem.indexOf(u8, found_link.url, query) != null)
            {
                var ref_obj = json.ObjectMap.init(allocator);
                try ref_obj.put("file", json.Value{ .string = try allocator.dupe(u8, file_path) });
                try ref_obj.put("line", json.Value{ .integer = @intCast(found_link.line) });
                try ref_obj.put("column", json.Value{ .integer = @intCast(found_link.column) });
                try ref_obj.put("text", json.Value{ .string = try allocator.dupe(u8, found_link.text) });
                try ref_obj.put("url", json.Value{ .string = try allocator.dupe(u8, found_link.url) });
                try ref_obj.put("type", json.Value{ .string = @tagName(found_link.type) });

                try all_results.append(json.Value{ .object = ref_obj });
            }
        }
    }

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "document_io" });
    try result.put("command", json.Value{ .string = "find_references" });
    try result.put("query", json.Value{ .string = query });
    try result.put("results", json.Value{ .array = all_results });

    return json.Value{ .object = result };
}

/// List directory contents
fn listDirectory(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const directory_path = params.get("directory_path") orelse json.Value{ .string = "." };
    const max_results_json = params.get("max_results") orelse json.Value{ .integer = 100 };
    const show_details = params.get("show_details") orelse json.Value{ .bool = false };

    const max_results: usize = @intCast(max_results_json.integer);
    const entries = try fs.listDir(allocator, directory_path.string, max_results);
    defer {
        for (entries) |entry| allocator.free(entry);
        allocator.free(entries);
    }

    var result_entries = json.Array.init(allocator);

    for (entries) |entry| {
        if (show_details.bool) {
            var entry_obj = json.ObjectMap.init(allocator);
            try entry_obj.put("name", json.Value{ .string = try allocator.dupe(u8, entry) });

            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ directory_path.string, entry });
            defer allocator.free(full_path);

            const file_metadata = fs.getFileInfo(full_path) catch continue;
            try entry_obj.put("size", json.Value{ .integer = @intCast(file_metadata.size) });
            try entry_obj.put("modified", json.Value{ .integer = file_metadata.modified });
            try entry_obj.put("is_file", json.Value{ .bool = file_metadata.is_file });
            try entry_obj.put("is_dir", json.Value{ .bool = file_metadata.is_dir });

            try result_entries.append(json.Value{ .object = entry_obj });
        } else {
            try result_entries.append(json.Value{ .string = try allocator.dupe(u8, entry) });
        }
    }

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "document_io" });
    try result.put("command", json.Value{ .string = "list_directory" });
    try result.put("directory", json.Value{ .string = directory_path.string });
    try result.put("entries", json.Value{ .array = result_entries });

    return json.Value{ .object = result };
}

/// Find files by pattern
fn findFiles(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const file_patterns_json = params.get("file_patterns") orelse json.Value{ .array = json.Array.init(allocator) };
    const max_results_json = params.get("max_results") orelse json.Value{ .integer = 100 };
    const max_results: usize = @intCast(max_results_json.integer);

    var all_files = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (all_files.items) |path| allocator.free(path);
        all_files.deinit(allocator);
    }

    if (file_patterns_json == .array) {
        for (file_patterns_json.array.items) |pattern_json| {
            const pattern = pattern_json.string;
            const files = try findFilesByPattern(allocator, pattern);
            defer {
                for (files) |path| allocator.free(path);
                allocator.free(files);
            }

            for (files) |path| {
                if (all_files.items.len >= max_results) break;
                try all_files.append(allocator, try allocator.dupe(u8, path));
            }
        }
    }

    var result_files = json.Array.init(allocator);
    for (all_files.items) |file_path| {
        try result_files.append(json.Value{ .string = try allocator.dupe(u8, file_path) });
    }

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "document_io" });
    try result.put("command", json.Value{ .string = "find_files" });
    try result.put("files", json.Value{ .array = result_files });

    return json.Value{ .object = result };
}

/// Get workspace tree structure
fn getWorkspaceTree(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const directory_path = params.get("directory_path") orelse json.Value{ .string = "." };
    const max_depth_json = params.get("max_depth") orelse json.Value{ .integer = 3 };
    const max_depth: usize = @intCast(max_depth_json.integer);

    const tree = try buildDirectoryTree(allocator, directory_path.string, 0, max_depth);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "document_io" });
    try result.put("command", json.Value{ .string = "get_workspace_tree" });
    try result.put("directory", json.Value{ .string = directory_path.string });
    try result.put("tree", tree);

    return json.Value{ .object = result };
}

/// Extract front matter section from content
fn extractFrontMatter(content: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, content, " \t\n\r");
    if (std.mem.startsWith(u8, trimmed, "---\n")) {
        const end_marker = std.mem.indexOf(u8, trimmed[4..], "\n---\n");
        if (end_marker) |end_pos| {
            return trimmed[0 .. 4 + end_pos + 5]; // Include both markers
        }
    }

    if (std.mem.startsWith(u8, trimmed, "+ + +\n")) {
        const end_marker = std.mem.indexOf(u8, trimmed[4..], "\n+ + +\n");
        if (end_marker) |end_pos| {
            return trimmed[0 .. 4 + end_pos + 5];
        }
    }
    return "";
}

/// Extract section by heading text (simplified)
fn extractHeadingSection(allocator: std.mem.Allocator, content: []const u8, heading_text: []const u8) ![]const u8 {
    var lines = std.mem.splitSequence(u8, content, "\n");
    var result = std.ArrayListUnmanaged(u8){};
    defer result.deinit(allocator);

    var in_section = false;
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (std.mem.startsWith(u8, trimmed, "#")) {
            // Start of a heading
            const after_hash = std.mem.trimLeft(u8, trimmed, "# ");
            if (std.mem.eql(u8, after_hash, heading_text)) {
                in_section = true;
            } else if (in_section) {
                break; // End of section
            }
        }

        if (in_section) {
            try result.appendSlice(allocator, line);
            try result.append(allocator, '\n');
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Find files matching a pattern (simplified)
fn findFilesByPattern(allocator: std.mem.Allocator, pattern: []const u8) ![][]const u8 {
    var result = std.ArrayListUnmanaged([]const u8){};
    defer result.deinit(allocator);

    if (std.mem.endsWith(u8, pattern, "*.md")) {
        const extension = ".md";
        const entries = try fs.listDir(allocator, ".", 10000);
        defer {
            for (entries) |entry| allocator.free(entry);
            allocator.free(entries);
        }

        for (entries) |entry| {
            if (std.mem.endsWith(u8, entry, extension)) {
                try result.append(allocator, try allocator.dupe(u8, entry));
            }
        }
    } else {
        // For other patterns, just check if file exists
        if (fs.fileExists(pattern)) {
            try result.append(allocator, try allocator.dupe(u8, pattern));
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Build directory tree recursively
fn buildDirectoryTree(allocator: std.mem.Allocator, path: []const u8, current_depth: usize, max_depth: usize) Error!json.Value {
    if (current_depth >= max_depth) {
        return json.Value{ .null = {} };
    }

    const entries = fs.listDir(allocator, path, 100) catch |err| switch (err) {
        fs.Error.FileNotFound, fs.Error.AccessDenied => {
            return json.Value{ .null = {} };
        },
        else => return err,
    };
    defer {
        for (entries) |entry| allocator.free(entry);
        allocator.free(entries);
    }

    var tree = json.ObjectMap.init(allocator);

    for (entries) |entry| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, entry });
        defer allocator.free(full_path);

        const file_metadata = fs.getFileInfo(full_path) catch continue;

        if (file_metadata.is_dir) {
            const subtree = try buildDirectoryTree(allocator, full_path, current_depth + 1, max_depth);
            try tree.put(entry, subtree);
        } else {
            var file_obj = json.ObjectMap.init(allocator);
            try file_obj.put("type", json.Value{ .string = "file" });
            try file_obj.put("size", json.Value{ .integer = @intCast(file_metadata.size) });
            try tree.put(entry, json.Value{ .object = file_obj });
        }
    }

    return json.Value{ .object = tree };
}

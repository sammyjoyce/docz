const std = @import("std");
const json = std.json;
const fs = @import("../common/fs.zig");
const text = @import("../common/text.zig");
const table = @import("../common/table.zig");
const meta = @import("../common/meta.zig");

pub const Error = fs.Error || text.Error || table.Error || meta.Error || error{
    UnknownCommand,
    InvalidParameters,
    InvalidLocation,
    InvalidScope,
    OperationFailed,
};

pub const Command = enum {
    // Content operations
    insert_content,
    replace_content,
    move_content,
    delete_content,
    batch_replace,

    // Structure operations
    add_section,
    move_section,
    delete_section,
    generate_toc,
    restructure,

    // Table operations
    create_table,
    update_table_cell,
    add_table_row,
    add_table_column,
    format_table,

    // Metadata operations
    set_metadata,
    update_metadata,
    remove_metadata,
    validate_metadata,

    // Formatting operations
    apply_formatting,
    normalize_markdown,
    wrap_text,
    fix_lists,

    pub fn fromString(str: []const u8) ?Command {
        return std.meta.stringToEnum(Command, str);
    }
};

/// Main entry point for content editing operations
pub fn execute(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    return executeInternal(allocator, params) catch |err| {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("error", json.Value{ .string = @errorName(err) });
        try result.put("tool", json.Value{ .string = "content_editor" });
        return json.Value{ .object = result };
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    const params_obj = params.object;

    const command_str = params_obj.get("command").?.string;
    const command = Command.fromString(command_str) orelse return Error.UnknownCommand;
    const file_path = params_obj.get("file_path").?.string;

    // Backup file if requested
    const backup_before_change = params_obj.get("backup_before_change") orelse json.Value{ .bool = true };
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    return switch (command) {
        // Content operations
        .insert_content => insertContent(allocator, params_obj, file_path),
        .replace_content => replaceContent(allocator, params_obj, file_path),
        .move_content => moveContent(allocator, params_obj, file_path),
        .delete_content => deleteContent(allocator, params_obj, file_path),
        .batch_replace => batchReplace(allocator, params_obj, file_path),

        // Structure operations
        .add_section => addSection(allocator, params_obj, file_path),
        .move_section => moveSection(allocator, params_obj, file_path),
        .delete_section => deleteSection(allocator, params_obj, file_path),
        .generate_toc => generateToc(allocator, params_obj, file_path),
        .restructure => restructure(allocator, params_obj, file_path),

        // Table operations
        .create_table => createTable(allocator, params_obj, file_path),
        .update_table_cell => updateTableCell(allocator, params_obj, file_path),
        .add_table_row => addTableRow(allocator, params_obj, file_path),
        .add_table_column => addTableColumn(allocator, params_obj, file_path),
        .format_table => formatTable(allocator, params_obj, file_path),

        // Metadata operations
        .set_metadata => setMetadata(allocator, params_obj, file_path),
        .update_metadata => updateMetadata(allocator, params_obj, file_path),
        .remove_metadata => removeMetadata(allocator, params_obj, file_path),
        .validate_metadata => validateMetadata(allocator, params_obj, file_path),

        // Formatting operations
        .apply_formatting => applyFormatting(allocator, params_obj, file_path),
        .normalize_markdown => normalizeMarkdown(allocator, params_obj, file_path),
        .wrap_text => wrapText(allocator, params_obj, file_path),
        .fix_lists => fixLists(allocator, params_obj, file_path),
    };
}

// Content Operations

fn insertContent(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const content = params.get("content").?.string;
    const location = params.get("location").?.string;

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    const new_content = try insertAtLocation(allocator, original_content, content, location);
    defer allocator.free(new_content);

    try fs.writeFile(file_path, new_content);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "insert_content" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("location", json.Value{ .string = location });
    try result.put("inserted_length", json.Value{ .integer = @intCast(content.len) });

    return json.Value{ .object = result };
}

fn replaceContent(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const search_pattern = params.get("search_pattern").?.string;
    const replacement = params.get("replacement").?.string;
    const is_regex = params.get("is_regex") orelse json.Value{ .bool = false };
    const scope_json = params.get("scope") orelse json.Value{ .string = "file" };

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    const search_options = text.SearchOptions{
        .regex_mode = is_regex.bool,
    };

    const scoped_content = try applyScopeFilter(allocator, original_content, scope_json.string);
    defer allocator.free(scoped_content);

    const new_content = try text.replaceAll(allocator, scoped_content, search_pattern, replacement, search_options);
    defer allocator.free(new_content);

    try fs.writeFile(file_path, new_content);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "replace_content" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("pattern", json.Value{ .string = search_pattern });
    try result.put("replacement", json.Value{ .string = replacement });

    return json.Value{ .object = result };
}

fn batchReplace(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const batch_ops = params.get("batch_operations").?.array;

    var content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(content);

    var replacements_made: usize = 0;

    for (batch_ops.items) |op_json| {
        const op = op_json.object;
        const search = op.get("search").?.string;
        const replace = op.get("replace").?.string;
        const is_regex = op.get("is_regex") orelse json.Value{ .bool = false };

        const search_options = text.SearchOptions{
            .regex_mode = is_regex.bool,
        };

        const new_content = try text.replaceAll(allocator, content, search, replace, search_options);
        allocator.free(content);
        content = new_content;
        replacements_made += 1;
    }

    try fs.writeFile(file_path, content);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "batch_replace" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("operations_completed", json.Value{ .integer = @intCast(replacements_made) });

    return json.Value{ .object = result };
}

// Structure Operations

fn addSection(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const heading_text = params.get("heading_text").?.string;
    const heading_level = params.get("heading_level").?.integer;
    const location = params.get("location") orelse json.Value{ .string = "end" };

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Create the section
    var section_content = std.ArrayList(u8).init(allocator);
    defer section_content.deinit();

    try section_content.appendNTimes('#', @intCast(heading_level));
    try section_content.append(' ');
    try section_content.appendSlice(heading_text);
    try section_content.appendSlice("\n\n");

    const new_content = try insertAtLocation(allocator, original_content, section_content.items, location.string);
    defer allocator.free(new_content);

    try fs.writeFile(file_path, new_content);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "add_section" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("heading", json.Value{ .string = heading_text });
    try result.put("level", json.Value{ .integer = heading_level });

    return json.Value{ .object = result };
}

fn generateToc(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const max_depth_json = params.get("max_depth") orelse json.Value{ .integer = 3 };
    const max_depth: usize = @intCast(max_depth_json.integer);

    const content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(content);

    var toc = std.ArrayList(u8).init(allocator);
    defer toc.deinit();

    try toc.appendSlice("## Table of Contents\n\n");

    var lines = std.mem.split(u8, content, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len > 0 and trimmed[0] == '#') {
            var level: usize = 0;
            while (level < trimmed.len and trimmed[level] == '#') {
                level += 1;
            }

            if (level <= max_depth) {
                const heading_text = std.mem.trim(u8, trimmed[level..], " \t");
                const slug = try createSlug(allocator, heading_text);
                defer allocator.free(slug);

                // Add indentation
                try toc.appendNTimes(' ', (level - 1) * 2);
                try toc.appendSlice("- [");
                try toc.appendSlice(heading_text);
                try toc.appendSlice("](#");
                try toc.appendSlice(slug);
                try toc.appendSlice(")\n");
            }
        }
    }

    // Insert TOC after front matter or at beginning
    const toc_location = if (std.mem.indexOf(u8, content, "---\n") != null and
        std.mem.indexOf(u8, content[4..], "\n---\n") != null)
        "after_front_matter"
    else
        "start";

    const new_content = try insertAtLocation(allocator, content, toc.items, toc_location);
    defer allocator.free(new_content);

    try fs.writeFile(file_path, new_content);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "generate_toc" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("max_depth", json.Value{ .integer = @intCast(max_depth) });

    return json.Value{ .object = result };
}

// Metadata Operations

fn setMetadata(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const metadata_key = params.get("metadata_key").?.string;
    const metadata_value_json = params.get("metadata_value").?;

    const content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(content);

    const metadata_opt = try meta.parseFrontMatter(allocator, content);
    var metadata = metadata_opt orelse blk: {
        const new_meta = meta.DocumentMetadata{
            .content = std.StringHashMap(meta.MetadataValue).init(allocator),
            .format = .yaml,
            .raw_content = try allocator.dupe(u8, ""),
        };
        break :blk new_meta;
    };
    defer metadata.deinit(allocator);

    // Convert JSON value to MetadataValue
    const meta_value = try jsonToMetadataValue(allocator, metadata_value_json);
    try metadata.set(allocator, metadata_key, meta_value);

    // Serialize metadata
    const serialized_metadata = try meta.serializeMetadata(allocator, &metadata);
    defer allocator.free(serialized_metadata);

    // Combine with content
    const document_content = meta.extractContent(content);
    var new_content = std.ArrayList(u8).init(allocator);
    defer new_content.deinit();

    try new_content.appendSlice(serialized_metadata);
    if (document_content.len > 0) {
        try new_content.append('\n');
        try new_content.appendSlice(document_content);
    }

    try fs.writeFile(file_path, new_content.items);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "set_metadata" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("key", json.Value{ .string = metadata_key });

    return json.Value{ .object = result };
}

// Formatting Operations

fn normalizeMarkdown(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = params; // Parameters for specific normalization rules can be added later

    const content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(content);

    // Apply basic normalization
    const normalized = try text.normalizeWhitespace(allocator, content);
    defer allocator.free(normalized);

    // Additional markdown-specific normalizations can be added here

    try fs.writeFile(file_path, normalized);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "normalize_markdown" });
    try result.put("file", json.Value{ .string = file_path });

    return json.Value{ .object = result };
}

// Placeholder implementations for remaining functions
// These would be fully implemented in the actual codebase

fn moveContent(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const source_pattern = params.get("source_pattern").?.string;
    const destination_location = params.get("destination_location").?.string;
    const is_regex = params.get("is_regex") orelse json.Value{ .bool = false };
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Configure search options
    const search_options = text.SearchOptions{
        .regex_mode = is_regex.bool,
    };

    // First, find and extract the content that matches the pattern
    // We'll use replaceAll to identify what content would be replaced
    const content_after_removal = try text.replaceAll(allocator, original_content, source_pattern, "", search_options);
    defer allocator.free(content_after_removal);

    // Calculate what content was extracted by comparing lengths and finding the difference
    const bytes_extracted = original_content.len - content_after_removal.len;
    if (bytes_extracted == 0) {
        // Pattern not found, return error
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("error", json.Value{ .string = "Pattern not found in content" });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "move_content" });
        try result.put("file", json.Value{ .string = file_path });
        return json.Value{ .object = result };
    }

    // To extract the actual content, we need to find what was removed
    // A simpler approach: find the pattern in the original content and extract it
    var extracted_content: []u8 = undefined;
    if (is_regex.bool) {
        // For regex, we need to handle this differently - for now, use a simple approach
        // This is a limitation - full regex content extraction is complex
        extracted_content = try allocator.dupe(u8, source_pattern); // Fallback
    } else {
        // For literal patterns, we can extract the first occurrence
        if (std.mem.indexOf(u8, original_content, source_pattern)) |start_idx| {
            const end_idx = start_idx + source_pattern.len;
            extracted_content = try allocator.dupe(u8, original_content[start_idx..end_idx]);
        } else {
            // This shouldn't happen since we already confirmed content was found
            var result = json.ObjectMap.init(allocator);
            try result.put("success", json.Value{ .bool = false });
            try result.put("error", json.Value{ .string = "Unexpected error extracting content" });
            try result.put("tool", json.Value{ .string = "content_editor" });
            try result.put("command", json.Value{ .string = "move_content" });
            try result.put("file", json.Value{ .string = file_path });
            return json.Value{ .object = result };
        }
    }
    defer allocator.free(extracted_content);

    // Insert the extracted content at the destination location
    const content_with_moved = try insertAtLocation(allocator, content_after_removal, extracted_content, destination_location);
    defer allocator.free(content_with_moved);

    // Write the final content back to file
    try fs.writeFile(file_path, content_with_moved);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "move_content" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("source_pattern", json.Value{ .string = source_pattern });
    try result.put("destination_location", json.Value{ .string = destination_location });
    try result.put("bytes_moved", json.Value{ .integer = @intCast(bytes_extracted) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

fn deleteContent(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const search_pattern = params.get("search_pattern").?.string;
    const is_regex = params.get("is_regex") orelse json.Value{ .bool = false };
    const scope_json = params.get("scope") orelse json.Value{ .string = "file" };
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Apply scope filter
    const scoped_content = try applyScopeFilter(allocator, original_content, scope_json.string);
    defer allocator.free(scoped_content);

    // Configure search options
    const search_options = text.SearchOptions{
        .regex_mode = is_regex.bool,
    };

    // Delete content by replacing with empty string
    const new_content = try text.replaceAll(allocator, scoped_content, search_pattern, "", search_options);
    defer allocator.free(new_content);

    // Calculate how much content was deleted
    const bytes_deleted = scoped_content.len - new_content.len;

    try fs.writeFile(file_path, new_content);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "delete_content" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("pattern", json.Value{ .string = search_pattern });
    try result.put("bytes_deleted", json.Value{ .integer = @intCast(bytes_deleted) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

fn moveSection(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const heading_text = params.get("heading_text").?.string;
    const location = params.get("location").?.string;
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Step 1: Extract the section content
    var section_content = std.ArrayList(u8).init(allocator);
    defer section_content.deinit();

    var remaining_content = std.ArrayList(u8).init(allocator);
    defer remaining_content.deinit();

    var lines = std.mem.splitSequence(u8, original_content, "\n");
    var in_target_section = false;
    var section_level: ?usize = null;
    var section_lines: usize = 0;

    while (lines.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, " \t");

        // Check if this is a heading line
        if (std.mem.startsWith(u8, trimmed_line, "#")) {
            var current_level: usize = 0;
            for (trimmed_line) |char| {
                if (char == '#') {
                    current_level += 1;
                } else {
                    break;
                }
            }

            // Extract the heading text (skip # and spaces)
            const heading_start = std.mem.indexOfNone(u8, trimmed_line[current_level..], " \t") orelse 0;
            const current_heading = std.mem.trim(u8, trimmed_line[current_level + heading_start ..], " \t");

            // Check if this is our target section
            if (std.mem.eql(u8, current_heading, heading_text) and !in_target_section) {
                in_target_section = true;
                section_level = current_level;
                try section_content.appendSlice(line);
                try section_content.append('\n');
                section_lines += 1;
                continue;
            }

            // If we're in the target section and hit a heading of equal or higher level, end extraction
            if (in_target_section and section_level != null and current_level <= section_level.?) {
                in_target_section = false;
                section_level = null;
            }
        }

        // Collect section content or remaining content
        if (in_target_section) {
            try section_content.appendSlice(line);
            try section_content.append('\n');
            section_lines += 1;
        } else {
            try remaining_content.appendSlice(line);
            try remaining_content.append('\n');
        }
    }

    // Check if section was found
    if (section_lines == 0) {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "move_section" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("error", json.Value{ .string = "Section not found" });
        return json.Value{ .object = result };
    }

    // Remove trailing newline from remaining content if original didn't have one
    if (remaining_content.items.len > 0 and !std.mem.endsWith(u8, original_content, "\n")) {
        remaining_content.items.len -= 1;
    }

    // Remove trailing newline from section content for proper insertion
    if (section_content.items.len > 0 and section_content.items[section_content.items.len - 1] == '\n') {
        section_content.items.len -= 1;
    }

    // Step 2: Insert the section at the new location
    const final_content = try insertAtLocation(allocator, remaining_content.items, section_content.items, location);
    defer allocator.free(final_content);

    // Step 3: Write the updated content back to file
    const bytes_moved = section_content.items.len;
    try fs.writeFile(file_path, final_content);

    // Return success response
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "move_section" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("heading", json.Value{ .string = heading_text });
    try result.put("location", json.Value{ .string = location });
    try result.put("lines_moved", json.Value{ .integer = @intCast(section_lines) });
    try result.put("bytes_moved", json.Value{ .integer = @intCast(bytes_moved) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

fn deleteSection(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const heading_text = params.get("heading_text").?.string;
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    var new_content = std.ArrayList(u8).init(allocator);
    defer new_content.deinit();

    var lines = std.mem.splitSequence(u8, original_content, "\n");
    var in_target_section = false;
    var section_level: ?usize = null;
    var lines_deleted: usize = 0;

    while (lines.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, " \t");

        // Check if this is a heading line
        if (std.mem.startsWith(u8, trimmed_line, "#")) {
            var current_level: usize = 0;
            for (trimmed_line) |char| {
                if (char == '#') {
                    current_level += 1;
                } else {
                    break;
                }
            }

            // Extract the heading text (skip # and spaces)
            const heading_start = std.mem.indexOfNone(u8, trimmed_line[current_level..], " \t") orelse 0;
            const current_heading = std.mem.trim(u8, trimmed_line[current_level + heading_start ..], " \t");

            // Check if this is our target section
            if (std.mem.eql(u8, current_heading, heading_text) and !in_target_section) {
                in_target_section = true;
                section_level = current_level;
                lines_deleted += 1;
                continue; // Skip this heading line
            }

            // If we're in the target section and hit a heading of equal or higher level, end deletion
            if (in_target_section and section_level != null and current_level <= section_level.?) {
                in_target_section = false;
                section_level = null;
            }
        }

        // If we're not in the target section, keep the line
        if (!in_target_section) {
            try new_content.appendSlice(line);
            try new_content.append('\n');
        } else {
            lines_deleted += 1;
        }
    }

    // Remove the trailing newline if the original didn't have one
    if (new_content.items.len > 0 and !std.mem.endsWith(u8, original_content, "\n")) {
        new_content.items.len -= 1;
    }

    const bytes_deleted = original_content.len - new_content.items.len;
    try fs.writeFile(file_path, new_content.items);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "delete_section" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("heading", json.Value{ .string = heading_text });
    try result.put("lines_deleted", json.Value{ .integer = @intCast(lines_deleted) });
    try result.put("bytes_deleted", json.Value{ .integer = @intCast(bytes_deleted) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

fn restructure(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
}

fn createTable(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    // Parse required parameters
    const headers_json = params.get("headers") orelse return Error.InvalidParameters;
    const location = params.get("location") orelse json.Value{ .string = "end" };
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Extract headers array from JSON
    var headers_list = std.ArrayList([]const u8).init(allocator);
    defer {
        for (headers_list.items) |header| {
            allocator.free(header);
        }
        headers_list.deinit();
    }

    switch (headers_json) {
        .array => |headers_array| {
            for (headers_array.items) |header_value| {
                switch (header_value) {
                    .string => |header_str| {
                        const header_copy = try allocator.dupe(u8, header_str);
                        try headers_list.append(header_copy);
                    },
                    else => return Error.InvalidParameters,
                }
            }
        },
        else => return Error.InvalidParameters,
    }

    if (headers_list.items.len == 0) return Error.InvalidParameters;

    // Parse optional rows data
    var rows_list = std.ArrayList([]const []const u8).init(allocator);
    defer {
        for (rows_list.items) |row| {
            for (row) |cell| {
                allocator.free(cell);
            }
            allocator.free(row);
        }
        rows_list.deinit();
    }

    if (params.get("rows")) |rows_json| {
        switch (rows_json) {
            .array => |rows_array| {
                for (rows_array.items) |row_value| {
                    switch (row_value) {
                        .array => |row_array| {
                            var row_cells = std.ArrayList([]const u8).init(allocator);
                            defer row_cells.deinit();

                            for (row_array.items) |cell_value| {
                                switch (cell_value) {
                                    .string => |cell_str| {
                                        const cell_copy = try allocator.dupe(u8, cell_str);
                                        try row_cells.append(cell_copy);
                                    },
                                    else => return Error.InvalidParameters,
                                }
                            }

                            const row_slice = try row_cells.toOwnedSlice();
                            try rows_list.append(row_slice);
                        },
                        else => return Error.InvalidParameters,
                    }
                }
            },
            else => return Error.InvalidParameters,
        }
    }

    // Parse optional alignments
    var alignments_list = std.ArrayList(table.Alignment).init(allocator);
    defer alignments_list.deinit();

    if (params.get("alignments")) |alignments_json| {
        switch (alignments_json) {
            .array => |alignments_array| {
                for (alignments_array.items) |alignment_value| {
                    switch (alignment_value) {
                        .string => |alignment_str| {
                            const alignment = if (std.mem.eql(u8, alignment_str, "center"))
                                table.Alignment.center
                            else if (std.mem.eql(u8, alignment_str, "right"))
                                table.Alignment.right
                            else
                                table.Alignment.left;
                            try alignments_list.append(alignment);
                        },
                        else => return Error.InvalidParameters,
                    }
                }
            },
            else => return Error.InvalidParameters,
        }
    }

    // Fill remaining alignments with default (left)
    while (alignments_list.items.len < headers_list.items.len) {
        try alignments_list.append(table.Alignment.left);
    }

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    // Read original content
    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Create the table using table.zig utilities
    var new_table = try table.createTable(allocator, headers_list.items, rows_list.items, if (alignments_list.items.len > 0) alignments_list.items else null);
    defer new_table.deinit(allocator);

    // Format the table as markdown
    const table_markdown = try table.formatTable(allocator, &new_table);
    defer allocator.free(table_markdown);

    // Insert table at specified location
    const new_content = try insertAtLocation(allocator, original_content, table_markdown, location.string);
    defer allocator.free(new_content);

    // Write the modified content back to file
    try fs.writeFile(file_path, new_content);

    // Build JSON response
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "create_table" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("headers_count", json.Value{ .integer = @intCast(headers_list.items.len) });
    try result.put("rows_count", json.Value{ .integer = @intCast(rows_list.items.len) });
    try result.put("location", json.Value{ .string = location.string });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

fn updateTableCell(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const row_index = params.get("row_index").?.integer;
    const column_index = params.get("column_index").?.integer;
    const new_content = params.get("new_content").?.string;
    const table_index = params.get("table_index") orelse json.Value{ .integer = 0 };
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Find all tables in the content
    var tables_found: usize = 0;
    var lines = std.mem.splitSequence(u8, original_content, "\n");
    var content_before_table = std.ArrayList(u8).init(allocator);
    defer content_before_table.deinit();
    var table_lines = std.ArrayList([]const u8).init(allocator);
    defer table_lines.deinit();
    var content_after_table = std.ArrayList(u8).init(allocator);
    defer content_after_table.deinit();

    var in_table = false;
    var current_table_index: usize = 0;
    var target_table_found = false;

    while (lines.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, " \t");

        if (trimmed_line.len > 0 and trimmed_line[0] == '|') {
            // This looks like a table line
            if (!in_table) {
                // Starting a new table
                in_table = true;
                if (current_table_index == table_index.integer) {
                    target_table_found = true;
                }
            }

            if (current_table_index == table_index.integer) {
                try table_lines.append(line);
            } else {
                if (target_table_found) {
                    // We've passed our target table, add to after content
                    try content_after_table.appendSlice(line);
                    try content_after_table.append('\n');
                } else {
                    // We haven't reached our target table yet, add to before content
                    try content_before_table.appendSlice(line);
                    try content_before_table.append('\n');
                }
            }
        } else {
            // Not a table line
            if (in_table) {
                // We just finished a table
                in_table = false;
                if (current_table_index == table_index.integer) {
                    // We just finished processing our target table
                    tables_found = current_table_index + 1;
                }
                current_table_index += 1;
            }

            if (target_table_found and current_table_index > table_index.integer) {
                // Add to after content
                try content_after_table.appendSlice(line);
                try content_after_table.append('\n');
            } else {
                // Add to before content
                try content_before_table.appendSlice(line);
                try content_before_table.append('\n');
            }
        }
    }

    if (!target_table_found) {
        return Error.InvalidParameters; // Table index not found
    }

    // Reconstruct table text from collected lines
    var table_text = std.ArrayList(u8).init(allocator);
    defer table_text.deinit();

    for (table_lines.items) |line| {
        try table_text.appendSlice(line);
        try table_text.append('\n');
    }

    // Parse the table
    var parsed_table = try table.parseTable(allocator, table_text.items) orelse return Error.InvalidParameters;
    defer parsed_table.deinit(allocator);

    // Update the specific cell
    try table.updateCell(&parsed_table, @intCast(row_index), @intCast(column_index), new_content, allocator);

    // Format the updated table
    const formatted_table = try table.formatTable(allocator, &parsed_table);
    defer allocator.free(formatted_table);

    // Combine all content parts
    var new_content_list = std.ArrayList(u8).init(allocator);
    defer new_content_list.deinit();

    try new_content_list.appendSlice(content_before_table.items);
    try new_content_list.appendSlice(formatted_table);
    try new_content_list.append('\n');
    try new_content_list.appendSlice(content_after_table.items);

    // Remove trailing newline if original didn't have one
    if (new_content_list.items.len > 0 and !std.mem.endsWith(u8, original_content, "\n")) {
        new_content_list.items.len -= 1;
    }

    try fs.writeFile(file_path, new_content_list.items);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "update_table_cell" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("table_index", json.Value{ .integer = table_index.integer });
    try result.put("row_index", json.Value{ .integer = row_index });
    try result.put("column_index", json.Value{ .integer = column_index });
    try result.put("new_content", json.Value{ .string = new_content });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

fn addTableRow(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    // Parse required parameters
    const row_data_json = params.get("row_data") orelse return Error.InvalidParameters;
    const table_index = params.get("table_index") orelse json.Value{ .integer = 0 };
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Extract row data array from JSON
    var row_data_list = std.ArrayList([]const u8).init(allocator);
    defer {
        for (row_data_list.items) |cell| {
            allocator.free(cell);
        }
        row_data_list.deinit();
    }

    switch (row_data_json) {
        .array => |row_array| {
            for (row_array.items) |cell_value| {
                switch (cell_value) {
                    .string => |cell_str| {
                        const cell_copy = try allocator.dupe(u8, cell_str);
                        try row_data_list.append(cell_copy);
                    },
                    else => return Error.InvalidParameters,
                }
            }
        },
        else => return Error.InvalidParameters,
    }

    if (row_data_list.items.len == 0) return Error.InvalidParameters;

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Find the target table in the content (using same pattern as updateTableCell)
    var lines = std.mem.splitSequence(u8, original_content, "\n");
    var content_before_table = std.ArrayList(u8).init(allocator);
    defer content_before_table.deinit();
    var table_lines = std.ArrayList([]const u8).init(allocator);
    defer table_lines.deinit();
    var content_after_table = std.ArrayList(u8).init(allocator);
    defer content_after_table.deinit();

    var in_table = false;
    var current_table_index: usize = 0;
    var target_table_found = false;

    while (lines.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, " \t");

        if (trimmed_line.len > 0 and trimmed_line[0] == '|') {
            // This looks like a table line
            if (!in_table) {
                // Starting a new table
                in_table = true;
                if (current_table_index == table_index.integer) {
                    target_table_found = true;
                }
            }

            if (current_table_index == table_index.integer) {
                try table_lines.append(line);
            } else {
                if (target_table_found) {
                    // We've passed our target table, add to after content
                    try content_after_table.appendSlice(line);
                    try content_after_table.append('\n');
                } else {
                    // We haven't reached our target table yet, add to before content
                    try content_before_table.appendSlice(line);
                    try content_before_table.append('\n');
                }
            }
        } else {
            // Not a table line
            if (in_table) {
                // We just finished a table
                in_table = false;
                if (current_table_index == table_index.integer) {
                    // We just finished processing our target table
                }
                current_table_index += 1;
            }

            if (target_table_found and current_table_index > table_index.integer) {
                // Add to after content
                try content_after_table.appendSlice(line);
                try content_after_table.append('\n');
            } else {
                // Add to before content
                try content_before_table.appendSlice(line);
                try content_before_table.append('\n');
            }
        }
    }

    if (!target_table_found) {
        return Error.InvalidParameters; // Table index not found
    }

    // Reconstruct table text from collected lines
    var table_text = std.ArrayList(u8).init(allocator);
    defer table_text.deinit();

    for (table_lines.items) |line| {
        try table_text.appendSlice(line);
        try table_text.append('\n');
    }

    // Parse the table
    var parsed_table = try table.parseTable(allocator, table_text.items) orelse return Error.InvalidParameters;
    defer parsed_table.deinit(allocator);

    // Add the new row to the table
    try table.addRow(allocator, &parsed_table, row_data_list.items);

    // Format the updated table
    const formatted_table = try table.formatTable(allocator, &parsed_table);
    defer allocator.free(formatted_table);

    // Combine all content parts
    var new_content_list = std.ArrayList(u8).init(allocator);
    defer new_content_list.deinit();

    try new_content_list.appendSlice(content_before_table.items);
    try new_content_list.appendSlice(formatted_table);
    try new_content_list.append('\n');
    try new_content_list.appendSlice(content_after_table.items);

    // Remove trailing newline if original didn't have one
    if (new_content_list.items.len > 0 and !std.mem.endsWith(u8, original_content, "\n")) {
        new_content_list.items.len -= 1;
    }

    try fs.writeFile(file_path, new_content_list.items);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "add_table_row" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("table_index", json.Value{ .integer = table_index.integer });
    try result.put("row_data_count", json.Value{ .integer = @intCast(row_data_list.items.len) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

fn addTableColumn(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
}

fn formatTable(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
}

fn updateMetadata(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const metadata_updates = params.get("metadata").?.object;
    const format_str = params.get("format") orelse json.Value{ .string = "yaml" };
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Parse existing metadata
    var metadata = try meta.parseFrontMatter(allocator, original_content) orelse blk: {
        // No existing metadata, create new one
        const format = std.meta.stringToEnum(meta.MetadataFormat, format_str.string) orelse meta.MetadataFormat.yaml;
        const new_metadata = meta.DocumentMetadata{
            .content = std.StringHashMap(meta.MetadataValue).init(allocator),
            .format = format,
            .raw_content = try allocator.dupe(u8, ""),
        };
        break :blk new_metadata;
    };
    defer metadata.deinit(allocator);

    // Update metadata with provided values
    var updates_made: usize = 0;
    var metadata_iterator = metadata_updates.iterator();
    while (metadata_iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const json_value = entry.value_ptr.*;

        // Convert JSON value to MetadataValue
        const metadata_value = try jsonToMetadataValue(allocator, json_value);
        try metadata.set(allocator, key, metadata_value);
        updates_made += 1;
    }

    // Serialize updated metadata
    const serialized_metadata = try meta.serializeMetadata(allocator, &metadata);
    defer allocator.free(serialized_metadata);

    // Extract content without front matter
    const content_without_metadata = meta.extractContent(original_content);

    // Combine updated metadata with content
    var new_content = std.ArrayList(u8).init(allocator);
    defer new_content.deinit();

    try new_content.appendSlice(serialized_metadata);
    if (content_without_metadata.len > 0) {
        // Add separator if content exists
        if (!std.mem.endsWith(u8, serialized_metadata, "\n")) {
            try new_content.append('\n');
        }
        try new_content.appendSlice(content_without_metadata);
    }

    const final_content = try new_content.toOwnedSlice();
    defer allocator.free(final_content);

    try fs.writeFile(file_path, final_content);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "update_metadata" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("metadata_updates", json.Value{ .integer = @intCast(updates_made) });
    try result.put("format", json.Value{ .string = @tagName(metadata.format) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

fn removeMetadata(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
}

fn validateMetadata(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
}

fn applyFormatting(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const format_type = params.get("format_type").?.string;
    const text_to_format = params.get("text_to_format").?.string;
    const selection_mode = params.get("selection_mode") orelse json.Value{ .string = "pattern" };
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Determine the formatting to apply based on format_type
    const formatted_text = blk: {
        if (std.mem.eql(u8, format_type, "bold")) {
            break :blk try std.fmt.allocPrint(allocator, "**{s}**", .{text_to_format});
        } else if (std.mem.eql(u8, format_type, "italic")) {
            break :blk try std.fmt.allocPrint(allocator, "*{s}*", .{text_to_format});
        } else if (std.mem.eql(u8, format_type, "code")) {
            break :blk try std.fmt.allocPrint(allocator, "`{s}`", .{text_to_format});
        } else if (std.mem.eql(u8, format_type, "strikethrough")) {
            break :blk try std.fmt.allocPrint(allocator, "~~{s}~~", .{text_to_format});
        } else if (std.mem.eql(u8, format_type, "header")) {
            const level_json = params.get("header_level") orelse json.Value{ .integer = 1 };
            const level: usize = @intCast(std.math.clamp(level_json.integer, 1, 6));
            var header_prefix = std.ArrayList(u8).init(allocator);
            defer header_prefix.deinit();
            try header_prefix.appendNTimes('#', level);
            try header_prefix.append(' ');
            break :blk try std.fmt.allocPrint(allocator, "{s}{s}", .{ header_prefix.items, text_to_format });
        } else if (std.mem.eql(u8, format_type, "link")) {
            const url = params.get("link_url").?.string;
            break :blk try std.fmt.allocPrint(allocator, "[{s}]({s})", .{ text_to_format, url });
        } else if (std.mem.eql(u8, format_type, "blockquote")) {
            break :blk try std.fmt.allocPrint(allocator, "> {s}", .{text_to_format});
        } else if (std.mem.eql(u8, format_type, "code_block")) {
            const language = params.get("language") orelse json.Value{ .string = "" };
            break :blk try std.fmt.allocPrint(allocator, "```{s}\n{s}\n```", .{ language.string, text_to_format });
        } else {
            return Error.InvalidParameters;
        }
    };
    defer allocator.free(formatted_text);

    // Apply the formatting based on selection mode
    const new_content = blk: {
        if (std.mem.eql(u8, selection_mode.string, "pattern")) {
            // Replace all occurrences of the pattern with formatted version
            const search_options = text.SearchOptions{
                .regex_mode = false,
            };
            break :blk try text.replaceAll(allocator, original_content, text_to_format, formatted_text, search_options);
        } else if (std.mem.eql(u8, selection_mode.string, "lines")) {
            // Apply formatting to specific line range
            const start_line = params.get("start_line").?.integer;
            const end_line = params.get("end_line") orelse params.get("start_line").?;

            var result = std.ArrayList(u8).init(allocator);
            defer result.deinit();

            var lines = std.mem.splitSequence(u8, original_content, "\n");
            var current_line: usize = 0;
            var formatted_lines: usize = 0;

            while (lines.next()) |line| {
                if (current_line >= start_line and current_line <= end_line.integer) {
                    // Apply formatting to this line
                    if (std.mem.eql(u8, format_type, "header") or std.mem.eql(u8, format_type, "blockquote")) {
                        try result.appendSlice(formatted_text);
                        try result.appendSlice(line);
                    } else {
                        try result.appendSlice(line);
                    }
                    formatted_lines += 1;
                } else {
                    try result.appendSlice(line);
                }

                if (lines.index) |_| {
                    try result.append('\n');
                }
                current_line += 1;
            }

            break :blk try result.toOwnedSlice();
        } else if (std.mem.eql(u8, selection_mode.string, "insert")) {
            // Insert formatted text at a specific location
            const location = params.get("location") orelse json.Value{ .string = "end" };
            break :blk try insertAtLocation(allocator, original_content, formatted_text, location.string);
        } else {
            return Error.InvalidParameters;
        }
    };
    defer allocator.free(new_content);

    try fs.writeFile(file_path, new_content);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "apply_formatting" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("format_type", json.Value{ .string = format_type });
    try result.put("text_formatted", json.Value{ .string = text_to_format });
    try result.put("selection_mode", json.Value{ .string = selection_mode.string });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

fn wrapText(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
}

fn fixLists(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
}

// Helper Functions

fn createBackup(allocator: std.mem.Allocator, file_path: []const u8) !void {
    const content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(content);

    const backup_path = try std.fmt.allocPrint(allocator, "{s}.backup", .{file_path});
    defer allocator.free(backup_path);

    try fs.writeFile(backup_path, content);
}

fn insertAtLocation(allocator: std.mem.Allocator, original: []const u8, insert_content: []const u8, location: []const u8) ![]u8 {
    if (std.mem.eql(u8, location, "start")) {
        var result = std.ArrayList(u8).init(allocator);
        try result.appendSlice(insert_content);
        try result.append('\n');
        try result.appendSlice(original);
        return result.toOwnedSlice();
    } else if (std.mem.eql(u8, location, "end")) {
        var result = std.ArrayList(u8).init(allocator);
        try result.appendSlice(original);
        try result.append('\n');
        try result.appendSlice(insert_content);
        return result.toOwnedSlice();
    } else if (std.mem.startsWith(u8, location, "line:")) {
        const line_num = std.fmt.parseInt(usize, location[5..], 10) catch return Error.InvalidLocation;
        return insertAtLine(allocator, original, insert_content, line_num);
    } else {
        return Error.InvalidLocation;
    }
}

fn insertAtLine(allocator: std.mem.Allocator, content: []const u8, insert_text: []const u8, line_num: usize) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var lines = std.mem.split(u8, content, "\n");
    var current_line: usize = 0;

    while (lines.next()) |line| {
        if (current_line == line_num) {
            try result.appendSlice(insert_text);
            try result.append('\n');
        }
        try result.appendSlice(line);
        try result.append('\n');
        current_line += 1;
    }

    // If line_num is beyond content, append at end
    if (line_num >= current_line) {
        try result.appendSlice(insert_text);
        try result.append('\n');
    }

    return result.toOwnedSlice();
}

fn applyScopeFilter(allocator: std.mem.Allocator, content: []const u8, scope: []const u8) ![]u8 {
    if (std.mem.eql(u8, scope, "file")) {
        return allocator.dupe(u8, content);
    }
    // For now, just return the full content
    // More sophisticated scoping can be implemented later
    return allocator.dupe(u8, content);
}

fn createSlug(allocator: std.mem.Allocator, input_text: []const u8) ![]u8 {
    var slug = std.ArrayList(u8).init(allocator);

    for (input_text) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            try slug.append(std.ascii.toLower(c));
        } else if (c == ' ' or c == '-' or c == '_') {
            try slug.append('-');
        }
    }

    return slug.toOwnedSlice();
}

fn jsonToMetadataValue(allocator: std.mem.Allocator, json_value: json.Value) !meta.MetadataValue {
    return switch (json_value) {
        .string => |s| meta.MetadataValue{ .string = try allocator.dupe(u8, s) },
        .integer => |i| meta.MetadataValue{ .integer = i },
        .float => |f| meta.MetadataValue{ .float = f },
        .bool => |b| meta.MetadataValue{ .boolean = b },
        else => meta.MetadataValue{ .string = try allocator.dupe(u8, "null") },
    };
}

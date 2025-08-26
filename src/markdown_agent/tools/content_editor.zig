const std = @import("std");
const json = std.json;
const fs = @import("../common/fs.zig");
const text = @import("../common/text.zig");
const table = @import("../common/table.zig");
const meta = @import("../common/meta.zig");
const template = @import("../common/template.zig");

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
    extract_section,
    split_document,
    merge_documents,
    generate_toc,
    restructure,

    // Table operations
    create_table,
    update_table_cell,
    add_table_row,
    add_table_column,
    delete_table_column,
    reorder_table_column,
    sort_table_column,
    format_table,
    import_csv_tsv,
    export_csv_tsv,
    validate_table,
    repair_table,

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

    // Template operations
    process_template,

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
        .extract_section => extractSection(allocator, params_obj, file_path),
        .split_document => splitDocument(allocator, params_obj, file_path),
        .merge_documents => mergeDocuments(allocator, params_obj, file_path),
        .generate_toc => generateToc(allocator, params_obj, file_path),
        .restructure => restructure(allocator, params_obj, file_path),

        // Table operations
        .create_table => createTable(allocator, params_obj, file_path),
        .update_table_cell => updateTableCell(allocator, params_obj, file_path),
        .add_table_row => addTableRow(allocator, params_obj, file_path),
        .add_table_column => addTableColumn(allocator, params_obj, file_path),
        .delete_table_column => deleteTableColumn(allocator, params_obj, file_path),
        .reorder_table_column => reorderTableColumn(allocator, params_obj, file_path),
        .sort_table_column => sortTableColumn(allocator, params_obj, file_path),
        .format_table => formatTable(allocator, params_obj, file_path),
        .import_csv_tsv => importCSVTSV(allocator, params_obj, file_path),
        .export_csv_tsv => exportCSVTSV(allocator, params_obj, file_path),
        .validate_table => validateTableCommand(allocator, params_obj, file_path),
        .repair_table => repairTableCommand(allocator, params_obj, file_path),

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

        // Template operations
        .process_template => processTemplate(allocator, params_obj, file_path),
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
    var section_content = std.array_list.ArrayListUnmanaged(u8){};
    defer section_content.deinit(allocator);

    try section_content.appendNTimes(allocator, '#', @intCast(heading_level));
    try section_content.append(allocator, ' ');
    try section_content.appendSlice(allocator, heading_text);
    try section_content.appendSlice(allocator, "\n\n");

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

    var toc = std.array_list.ArrayListUnmanaged(u8){};
    defer toc.deinit(allocator);

    try toc.appendSlice(allocator, "## Table of Contents\n\n");

    var lines = std.mem.splitScalar(u8, content, '\n');
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
                try toc.appendNTimes(allocator, ' ', (level - 1) * 2);
                try toc.appendSlice(allocator, "- [");
                try toc.appendSlice(allocator, heading_text);
                try toc.appendSlice(allocator, "](#");
                try toc.appendSlice(allocator, slug);
                try toc.appendSlice(allocator, ")\n");
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
    var new_content = std.array_list.ArrayListUnmanaged(u8){};
    defer new_content.deinit(allocator);

    try new_content.appendSlice(allocator, serialized_metadata);
    if (document_content.len > 0) {
        try new_content.append(allocator, '\n');
        try new_content.appendSlice(allocator, document_content);
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
    var section_content = std.array_list.ArrayListUnmanaged(u8){};
    defer section_content.deinit(allocator);

    var remaining_content = std.array_list.ArrayListUnmanaged(u8){};
    defer remaining_content.deinit(allocator);

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
                try section_content.appendSlice(allocator, line);
                try section_content.append(allocator, '\n');
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
            try section_content.appendSlice(allocator, line);
            try section_content.append(allocator, '\n');
        } else {
            try remaining_content.appendSlice(allocator, line);
            try remaining_content.append(allocator, '\n');
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

    var new_content = std.array_list.ArrayListUnmanaged(u8){};
    defer new_content.deinit(allocator);

    var lines = std.mem.splitScalar(u8, original_content, '\n');
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
            try new_content.appendSlice(allocator, line);
            try new_content.append(allocator, '\n');
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

fn extractSection(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const heading_text = params.get("heading_text").?.string;
    const output_file = params.get("output_file").?.string;
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };
    const remove_from_source = params.get("remove_from_source") orelse json.Value{ .bool = false };

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Extract the section content
    var section_content = std.array_list.ArrayListUnmanaged(u8){};
    defer section_content.deinit(allocator);

    var remaining_content = std.array_list.ArrayListUnmanaged(u8){};
    defer remaining_content.deinit(allocator);

    var lines = std.mem.splitScalar(u8, original_content, '\n');
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
                try section_content.appendSlice(allocator, line);
                try section_content.append(allocator, '\n');
                section_lines += 1;

                // If not removing from source, also add to remaining content
                if (!remove_from_source.bool) {
                    try remaining_content.appendSlice(allocator, line);
                    try remaining_content.append(allocator, '\n');
                }
                continue;
            }

            // If we're in the target section and hit a heading of equal or higher level, end extraction
            if (in_target_section and section_level != null and current_level <= section_level.?) {
                in_target_section = false;
                section_level = null;
            }
        }

        // Collect section content and/or remaining content
        if (in_target_section) {
            try section_content.appendSlice(allocator, line);
            try section_content.append(allocator, '\n');
            section_lines += 1;

            // If not removing from source, also add to remaining content
            if (!remove_from_source.bool) {
                try remaining_content.appendSlice(allocator, line);
                try remaining_content.append(allocator, '\n');
            }
        } else {
            try remaining_content.appendSlice(allocator, line);
            try remaining_content.append(allocator, '\n');
        }
    }

    // Check if section was found
    if (section_lines == 0) {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "extract_section" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("error", json.Value{ .string = "Section not found" });
        return json.Value{ .object = result };
    }

    // Remove trailing newline from section content if original didn't have one
    if (section_content.items.len > 0 and !std.mem.endsWith(u8, original_content, "\n")) {
        section_content.items.len -= 1;
    }

    // Write extracted section to output file
    try fs.writeFile(output_file, section_content.items);

    // If removing from source, update the original file
    if (remove_from_source.bool) {
        // Remove trailing newline from remaining content if original didn't have one
        if (remaining_content.items.len > 0 and !std.mem.endsWith(u8, original_content, "\n")) {
            remaining_content.items.len -= 1;
        }

        try fs.writeFile(file_path, remaining_content.items);
    }

    // Return success response
    const bytes_extracted = section_content.items.len;
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "extract_section" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("output_file", json.Value{ .string = output_file });
    try result.put("heading", json.Value{ .string = heading_text });
    try result.put("lines_extracted", json.Value{ .integer = @intCast(section_lines) });
    try result.put("bytes_extracted", json.Value{ .integer = @intCast(bytes_extracted) });
    try result.put("removed_from_source", json.Value{ .bool = remove_from_source.bool });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

fn splitDocument(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const split_level = params.get("split_level") orelse json.Value{ .integer = 1 };
    const output_directory = params.get("output_directory") orelse json.Value{ .string = "split_output" };
    const preserve_structure = params.get("preserve_structure") orelse json.Value{ .bool = true };
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Create output directory
    std.fs.cwd().makeDir(output_directory.string) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Parse document into sections
    var sections = std.ArrayList(DocumentSection).init(allocator);
    defer {
        for (sections.items) |section| {
            allocator.free(section.heading);
            section.content.deinit(allocator);
        }
        sections.deinit();
    }

    var preamble_content = std.array_list.ArrayListUnmanaged(u8){};
    defer preamble_content.deinit(allocator);

    const target_level: u32 = @intCast(split_level.integer);

    var lines = std.mem.splitScalar(u8, original_content, '\n');
    var current_section: ?*DocumentSection = null;
    var found_first_split_header = false;

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

            // If this is a split-level heading, start a new section
            if (current_level == target_level) {
                found_first_split_header = true;

                // Create new section
                var new_section = DocumentSection{
                    .heading = try allocator.dupe(u8, current_heading),
                    .content = std.array_list.ArrayListUnmanaged(u8){},
                    .level = current_level,
                };

                // Add preamble content if preserve_structure and this is first section
                if (preserve_structure.bool and sections.items.len == 0 and preamble_content.items.len > 0) {
                    try new_section.content.appendSlice(allocator, preamble_content.items);
                }

                // Add the heading line itself
                try new_section.content.appendSlice(allocator, line);
                try new_section.content.append(allocator, '\n');

                try sections.append(new_section);
                current_section = &sections.items[sections.items.len - 1];
                continue;
            }
        }

        // Add line to current section or preamble
        if (current_section != null) {
            try current_section.?.content.appendSlice(allocator, line);
            try current_section.?.content.append(allocator, '\n');
        } else if (!found_first_split_header) {
            // Content before first split header goes to preamble
            try preamble_content.appendSlice(allocator, line);
            try preamble_content.append(allocator, '\n');
        }
    }

    if (sections.items.len == 0) {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "split_document" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("error", json.Value{ .string = "No sections found at specified level" });
        return json.Value{ .object = result };
    }

    // Write sections to files
    var created_files = std.ArrayList([]const u8).init(allocator);
    defer {
        for (created_files.items) |filename| {
            allocator.free(filename);
        }
        created_files.deinit();
    }

    var total_bytes: usize = 0;

    for (sections.items, 0..) |section, index| {
        // Create filename from heading (sanitize for filesystem)
        const filename = try sanitizeFilename(allocator, section.heading);
        defer allocator.free(filename);

        const full_filename = try std.fmt.allocPrint(allocator, "{s}/{02d}_{s}.md", .{ output_directory.string, index + 1, filename });

        // Remove trailing newline if original didn't have one
        var content_to_write = section.content.items;
        if (content_to_write.len > 0 and !std.mem.endsWith(u8, original_content, "\n")) {
            content_to_write = content_to_write[0 .. content_to_write.len - 1];
        }

        try fs.writeFile(full_filename, content_to_write);
        try created_files.append(try allocator.dupe(u8, full_filename));
        total_bytes += content_to_write.len;
    }

    // Return success response
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "split_document" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("output_directory", json.Value{ .string = output_directory.string });
    try result.put("split_level", json.Value{ .integer = split_level.integer });
    try result.put("sections_created", json.Value{ .integer = @intCast(sections.items.len) });
    try result.put("total_bytes_written", json.Value{ .integer = @intCast(total_bytes) });
    try result.put("preserve_structure", json.Value{ .bool = preserve_structure.bool });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    // Add list of created files
    var files_array = json.Array.init(allocator);
    for (created_files.items) |filename| {
        try files_array.append(json.Value{ .string = filename });
    }
    try result.put("created_files", json.Value{ .array = files_array });

    return json.Value{ .object = result };
}

fn mergeDocuments(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const input_files_json = params.get("input_files") orelse return Error.InvalidParameters;
    const merge_strategy = params.get("merge_strategy") orelse json.Value{ .string = "append" };
    const location = params.get("location") orelse json.Value{ .string = "end" };
    const separator = params.get("separator") orelse json.Value{ .string = "\n\n---\n\n" };
    const merge_metadata = params.get("merge_metadata") orelse json.Value{ .bool = true };
    const metadata_merge_strategy = params.get("metadata_merge_strategy") orelse json.Value{ .string = "override" };
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Parse input files array
    var input_files = std.ArrayList([]const u8).init(allocator);
    defer {
        for (input_files.items) |file_path_copy| {
            allocator.free(file_path_copy);
        }
        input_files.deinit();
    }

    switch (input_files_json) {
        .array => |files_array| {
            if (files_array.items.len == 0) return Error.InvalidParameters;

            for (files_array.items) |file_value| {
                switch (file_value) {
                    .string => |file_str| {
                        const file_copy = try allocator.dupe(u8, file_str);
                        try input_files.append(file_copy);
                    },
                    else => return Error.InvalidParameters,
                }
            }
        },
        else => return Error.InvalidParameters,
    }

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    // Read target document content
    const target_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(target_content);

    // Parse target document metadata if merge_metadata is enabled
    var target_metadata: ?meta.DocumentMetadata = null;
    var target_document_content: []const u8 = target_content;

    if (merge_metadata.bool) {
        target_metadata = meta.parseFrontMatter(allocator, target_content) catch null;
        target_document_content = meta.extractContent(target_content);
    }
    defer if (target_metadata) |*metadata| {
        metadata.deinit(allocator);
    };

    // Collect content from all input files
    var merged_content_parts = std.ArrayList([]const u8).init(allocator);
    defer {
        for (merged_content_parts.items) |content_part| {
            allocator.free(content_part);
        }
        merged_content_parts.deinit();
    }

    var merged_metadata_keys = std.StringHashMap(meta.MetadataValue).init(allocator);
    defer {
        var iterator = merged_metadata_keys.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        merged_metadata_keys.deinit();
    }

    // Process each input file
    var files_processed: usize = 0;
    var total_bytes_merged: usize = 0;

    for (input_files.items) |input_file| {
        // Check if file exists
        if (!fs.fileExists(input_file)) {
            var result = json.ObjectMap.init(allocator);
            try result.put("success", json.Value{ .bool = false });
            try result.put("error", json.Value{ .string = try std.fmt.allocPrint(allocator, "Input file not found: {s}", .{input_file}) });
            try result.put("tool", json.Value{ .string = "content_editor" });
            try result.put("command", json.Value{ .string = "merge_documents" });
            try result.put("file", json.Value{ .string = file_path });
            return json.Value{ .object = result };
        }

        const file_content = try fs.readFileAlloc(allocator, input_file, null);
        defer allocator.free(file_content);

        // Handle metadata merging if enabled
        if (merge_metadata.bool) {
            if (meta.parseFrontMatter(allocator, file_content)) |*file_metadata| {
                defer file_metadata.deinit(allocator);

                // Merge metadata based on strategy
                if (std.mem.eql(u8, metadata_merge_strategy.string, "override")) {
                    // Override target metadata with source metadata
                    var iterator = file_metadata.content.iterator();
                    while (iterator.next()) |entry| {
                        const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                        const value_copy = try entry.value_ptr.clone(allocator);
                        try merged_metadata_keys.put(key_copy, value_copy);
                    }
                } else if (std.mem.eql(u8, metadata_merge_strategy.string, "preserve")) {
                    // Only add if key doesn't exist in target
                    var iterator = file_metadata.content.iterator();
                    while (iterator.next()) |entry| {
                        if (!merged_metadata_keys.contains(entry.key_ptr.*)) {
                            const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                            const value_copy = try entry.value_ptr.clone(allocator);
                            try merged_metadata_keys.put(key_copy, value_copy);
                        }
                    }
                }

                const document_content = meta.extractContent(file_content);
                const content_copy = try allocator.dupe(u8, document_content);
                try merged_content_parts.append(content_copy);
                total_bytes_merged += document_content.len;
            } else |_| {
                // No metadata in this file, use entire content
                const content_copy = try allocator.dupe(u8, file_content);
                try merged_content_parts.append(content_copy);
                total_bytes_merged += file_content.len;
            }
        } else {
            // No metadata merging, use entire content
            const content_copy = try allocator.dupe(u8, file_content);
            try merged_content_parts.append(content_copy);
            total_bytes_merged += file_content.len;
        }

        files_processed += 1;
    }

    // Combine all merged content
    var combined_content = std.array_list.ArrayListUnmanaged(u8){};
    defer combined_content.deinit(allocator);

    for (merged_content_parts.items, 0..) |content_part, index| {
        const trimmed_content = std.mem.trim(u8, content_part, " \t\n\r");
        if (trimmed_content.len > 0) {
            if (index > 0) {
                try combined_content.appendSlice(allocator, separator.string);
            }
            try combined_content.appendSlice(allocator, trimmed_content);
        }
    }

    // Apply merge strategy to target document
    var final_content = std.array_list.ArrayListUnmanaged(u8){};
    defer final_content.deinit(allocator);

    // Handle final metadata creation
    if (merge_metadata.bool and (target_metadata != null or merged_metadata_keys.count() > 0)) {
        var final_metadata = if (target_metadata) |*tm|
            meta.DocumentMetadata{
                .content = std.StringHashMap(meta.MetadataValue).init(allocator),
                .format = tm.format,
                .raw_content = try allocator.dupe(u8, ""),
            }
        else
            meta.DocumentMetadata{
                .content = std.StringHashMap(meta.MetadataValue).init(allocator),
                .format = .yaml,
                .raw_content = try allocator.dupe(u8, ""),
            };
        defer final_metadata.deinit(allocator);

        // Copy target metadata first
        if (target_metadata) |*tm| {
            var iterator = tm.content.iterator();
            while (iterator.next()) |entry| {
                const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                const value_copy = try entry.value_ptr.clone(allocator);
                try final_metadata.set(allocator, key_copy, value_copy);
            }
        }

        // Apply merged metadata
        var merged_iterator = merged_metadata_keys.iterator();
        while (merged_iterator.next()) |entry| {
            const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
            const value_copy = try entry.value_ptr.clone(allocator);
            try final_metadata.set(allocator, key_copy, value_copy);
        }

        // Serialize final metadata
        const serialized_metadata = try meta.serializeMetadata(allocator, &final_metadata);
        defer allocator.free(serialized_metadata);

        try final_content.appendSlice(allocator, serialized_metadata);

        // Add target document content based on merge strategy
        if (std.mem.eql(u8, merge_strategy.string, "append")) {
            // Add target content first, then merged content
            const target_doc_content = std.mem.trim(u8, target_document_content, " \t\n\r");
            if (target_doc_content.len > 0) {
                if (!std.mem.endsWith(u8, serialized_metadata, "\n")) {
                    try final_content.append(allocator, '\n');
                }
                try final_content.appendSlice(allocator, target_doc_content);
                if (combined_content.items.len > 0) {
                    try final_content.appendSlice(allocator, separator.string);
                }
            } else if (!std.mem.endsWith(u8, serialized_metadata, "\n")) {
                try final_content.append(allocator, '\n');
            }

            if (combined_content.items.len > 0) {
                try final_content.appendSlice(allocator, combined_content.items);
            }
        } else if (std.mem.eql(u8, merge_strategy.string, "prepend")) {
            // Add merged content first, then target content
            if (!std.mem.endsWith(u8, serialized_metadata, "\n")) {
                try final_content.append(allocator, '\n');
            }

            if (combined_content.items.len > 0) {
                try final_content.appendSlice(allocator, combined_content.items);
            }

            const target_doc_content = std.mem.trim(u8, target_document_content, " \t\n\r");
            if (target_doc_content.len > 0) {
                if (combined_content.items.len > 0) {
                    try final_content.appendSlice(allocator, separator.string);
                }
                try final_content.appendSlice(allocator, target_doc_content);
            }
        } else if (std.mem.eql(u8, merge_strategy.string, "replace")) {
            // Replace target content entirely with merged content
            if (!std.mem.endsWith(u8, serialized_metadata, "\n")) {
                try final_content.append(allocator, '\n');
            }
            if (combined_content.items.len > 0) {
                try final_content.appendSlice(allocator, combined_content.items);
            }
        } else if (std.mem.eql(u8, merge_strategy.string, "insert")) {
            // Insert merged content at specified location within target content
            if (!std.mem.endsWith(u8, serialized_metadata, "\n")) {
                try final_content.append(allocator, '\n');
            }

            const content_with_inserted = try insertAtLocation(allocator, target_document_content, combined_content.items, location.string);
            defer allocator.free(content_with_inserted);
            try final_content.appendSlice(allocator, content_with_inserted);
        }
    } else {
        // No metadata handling, work with raw content
        if (std.mem.eql(u8, merge_strategy.string, "append")) {
            try final_content.appendSlice(allocator, target_content);
            if (combined_content.items.len > 0) {
                try final_content.appendSlice(allocator, separator.string);
                try final_content.appendSlice(allocator, combined_content.items);
            }
        } else if (std.mem.eql(u8, merge_strategy.string, "prepend")) {
            if (combined_content.items.len > 0) {
                try final_content.appendSlice(allocator, combined_content.items);
                try final_content.appendSlice(allocator, separator.string);
            }
            try final_content.appendSlice(allocator, target_content);
        } else if (std.mem.eql(u8, merge_strategy.string, "replace")) {
            if (combined_content.items.len > 0) {
                try final_content.appendSlice(allocator, combined_content.items);
            }
        } else if (std.mem.eql(u8, merge_strategy.string, "insert")) {
            const content_with_inserted = try insertAtLocation(allocator, target_content, combined_content.items, location.string);
            defer allocator.free(content_with_inserted);
            try final_content.appendSlice(allocator, content_with_inserted);
        }
    }

    // Write final content to target file
    try fs.writeFile(file_path, final_content.items);

    // Build JSON response
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "merge_documents" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("files_merged", json.Value{ .integer = @intCast(files_processed) });
    try result.put("total_bytes_merged", json.Value{ .integer = @intCast(total_bytes_merged) });
    try result.put("merge_strategy", json.Value{ .string = merge_strategy.string });
    try result.put("metadata_merged", json.Value{ .bool = merge_metadata.bool });
    try result.put("metadata_keys_merged", json.Value{ .integer = @intCast(merged_metadata_keys.count()) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    // Add list of merged files
    var files_array = json.Array.init(allocator);
    for (input_files.items) |file_name| {
        try files_array.append(json.Value{ .string = file_name });
    }
    try result.put("input_files", json.Value{ .array = files_array });

    return json.Value{ .object = result };
}

const DocumentSection = struct {
    heading: []const u8,
    content: std.array_list.ArrayListUnmanaged(u8),
    level: usize,
};

fn sanitizeFilename(allocator: std.mem.Allocator, filename: []const u8) ![]const u8 {
    var sanitized = try allocator.alloc(u8, filename.len);
    var write_index: usize = 0;

    for (filename) |char| {
        switch (char) {
            'a'...'z', 'A'...'Z', '0'...'9', '-', '_', ' ' => {
                sanitized[write_index] = if (char == ' ') '_' else char;
                write_index += 1;
            },
            else => {}, // Skip invalid characters
        }
    }

    // Trim to actual length and limit to reasonable size
    const final_length = @min(write_index, 50);
    if (final_length == 0) {
        allocator.free(sanitized);
        return try allocator.dupe(u8, "section");
    }

    const result = try allocator.alloc(u8, final_length);
    @memcpy(result, sanitized[0..final_length]);
    allocator.free(sanitized);

    return result;
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
    var headers_list = std.ArrayList([]const u8){};
    defer {
        for (headers_list.items) |header| {
            allocator.free(header);
        }
        headers_list.deinit(allocator);
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
    var rows_list = std.ArrayList([]const []const u8){};
    defer {
        for (rows_list.items) |row| {
            for (row) |cell| {
                allocator.free(cell);
            }
            allocator.free(row);
        }
        rows_list.deinit(allocator);
    }

    if (params.get("rows")) |rows_json| {
        switch (rows_json) {
            .array => |rows_array| {
                for (rows_array.items) |row_value| {
                    switch (row_value) {
                        .array => |row_array| {
                            var row_cells = std.ArrayList([]const u8){};
                            defer row_cells.deinit(allocator);

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
    var alignments_list = std.ArrayList(table.Alignment){};
    defer alignments_list.deinit(allocator);

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
    var content_before_table = std.ArrayList(u8){};
    defer content_before_table.deinit(allocator);
    var table_lines = std.ArrayList([]const u8){};
    defer table_lines.deinit(allocator);
    var content_after_table = std.ArrayList(u8){};
    defer content_after_table.deinit(allocator);

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
    var new_content_list = std.ArrayList(u8){};
    defer new_content_list.deinit(allocator);

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
    var row_data_list = std.ArrayList([]const u8){};
    defer {
        for (row_data_list.items) |cell| {
            allocator.free(cell);
        }
        row_data_list.deinit(allocator);
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
    var content_before_table = std.ArrayList(u8){};
    defer content_before_table.deinit(allocator);
    var table_lines = std.ArrayList([]const u8){};
    defer table_lines.deinit(allocator);
    var content_after_table = std.ArrayList(u8){};
    defer content_after_table.deinit(allocator);

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
    var new_content_list = std.ArrayList(u8){};
    defer new_content_list.deinit(allocator);

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
    // Parse required parameters
    const header = params.get("header") orelse return Error.InvalidParameters;
    const table_index = params.get("table_index") orelse json.Value{ .integer = 0 };
    const column_index = params.get("column_index"); // Optional - defaults to end
    const alignment_str = params.get("alignment") orelse json.Value{ .string = "left" };
    const column_data_json = params.get("column_data"); // Optional array of cell data
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Validate header parameter
    const header_text = switch (header) {
        .string => |h| h,
        else => return Error.InvalidParameters,
    };

    // Parse alignment
    const alignment = std.meta.stringToEnum(table.Alignment, alignment_str.string) orelse table.Alignment.left;

    // Parse column data if provided
    var column_data_list = std.ArrayList([]const u8){};
    defer {
        for (column_data_list.items) |cell| {
            allocator.free(cell);
        }
        column_data_list.deinit(allocator);
    }

    if (column_data_json) |data| {
        switch (data) {
            .array => |data_array| {
                for (data_array.items) |cell_value| {
                    switch (cell_value) {
                        .string => |cell_str| {
                            const cell_copy = try allocator.dupe(u8, cell_str);
                            try column_data_list.append(cell_copy);
                        },
                        else => return Error.InvalidParameters,
                    }
                }
            },
            else => return Error.InvalidParameters,
        }
    }

    // Parse column index if provided
    const insert_index: ?usize = if (column_index) |idx| switch (idx) {
        .integer => |i| if (i >= 0) @intCast(i) else null,
        else => null,
    } else null;

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Find the target table in the content (using same pattern as addTableRow)
    var lines = std.mem.splitSequence(u8, original_content, "\n");
    var content_before_table = std.ArrayList(u8){};
    defer content_before_table.deinit(allocator);
    var table_lines = std.ArrayList([]const u8){};
    defer table_lines.deinit(allocator);
    var content_after_table = std.ArrayList(u8){};
    defer content_after_table.deinit(allocator);

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

    // Add the new column to the table
    try table.addColumn(allocator, &parsed_table, header_text, column_data_list.items, alignment, insert_index);

    // Format the updated table
    const formatted_table = try table.formatTable(allocator, &parsed_table);
    defer allocator.free(formatted_table);

    // Combine all content parts
    var new_content_list = std.ArrayList(u8){};
    defer new_content_list.deinit(allocator);

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
    try result.put("command", json.Value{ .string = "add_table_column" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("table_index", json.Value{ .integer = table_index.integer });
    try result.put("header", json.Value{ .string = header_text });
    try result.put("alignment", json.Value{ .string = @tagName(alignment) });
    try result.put("column_data_count", json.Value{ .integer = @intCast(column_data_list.items.len) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    // Include column_index in response if it was specified
    if (insert_index) |idx| {
        try result.put("column_index", json.Value{ .integer = @intCast(idx) });
    }

    return json.Value{ .object = result };
}

fn deleteTableColumn(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    // Parse required parameters
    const column_index = params.get("column_index") orelse return Error.InvalidParameters;
    const table_index = params.get("table_index") orelse json.Value{ .integer = 0 };
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Validate column_index parameter
    const col_index: usize = switch (column_index) {
        .integer => |idx| if (idx >= 0) @intCast(idx) else return Error.InvalidParameters,
        else => return Error.InvalidParameters,
    };

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Find the target table in the content (using same pattern as addTableColumn)
    var lines = std.mem.splitSequence(u8, original_content, "\n");
    var content_before_table = std.ArrayList(u8){};
    defer content_before_table.deinit(allocator);
    var table_lines = std.ArrayList([]const u8){};
    defer table_lines.deinit(allocator);
    var content_after_table = std.ArrayList(u8){};
    defer content_after_table.deinit(allocator);

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

    // Store the header name being deleted for response
    const deleted_header = if (col_index < parsed_table.headers.len)
        try allocator.dupe(u8, parsed_table.headers[col_index])
    else
        return Error.InvalidParameters;
    defer allocator.free(deleted_header);

    // Delete the column from the table
    try table.deleteColumn(allocator, &parsed_table, col_index);

    // Format the updated table
    const formatted_table = try table.formatTable(allocator, &parsed_table);
    defer allocator.free(formatted_table);

    // Combine all content parts
    var new_content_list = std.ArrayList(u8){};
    defer new_content_list.deinit(allocator);

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
    try result.put("command", json.Value{ .string = "delete_table_column" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("table_index", json.Value{ .integer = table_index.integer });
    try result.put("column_index", json.Value{ .integer = @intCast(col_index) });
    try result.put("deleted_header", json.Value{ .string = deleted_header });
    try result.put("remaining_columns", json.Value{ .integer = @intCast(parsed_table.headers.len) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

fn formatTable(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const table_index = params.get("table_index") orelse json.Value{ .integer = 0 };
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Find all tables in the content
    var lines = std.mem.splitSequence(u8, original_content, "\n");
    var content_before_table = std.ArrayList(u8).init(allocator);
    defer content_before_table.deinit();
    var table_lines = std.ArrayList([]const u8).init(allocator);
    defer table_lines.deinit();
    var content_after_table = std.ArrayList(u8).init(allocator);
    defer content_after_table.deinit();

    var in_table = false;
    var current_table_index: usize = 0;
    var found_target_table = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (!in_table) {
            // Check if this line starts a table
            if (trimmed.len > 0 and trimmed[0] == '|') {
                if (current_table_index == table_index.integer) {
                    // This is our target table
                    found_target_table = true;
                    in_table = true;
                    try table_lines.append(line);
                } else {
                    // Not our target table, include in content_before_table
                    try content_before_table.appendSlice(line);
                    try content_before_table.append('\n');

                    // Skip through this table
                    var skip_lines = std.mem.splitSequence(u8, line, "\n");
                    _ = skip_lines.next(); // Skip current line since we already have it
                    while (skip_lines.next()) |skip_line| {
                        const skip_trimmed = std.mem.trim(u8, skip_line, " \t");
                        if (skip_trimmed.len > 0 and skip_trimmed[0] == '|') {
                            try content_before_table.appendSlice(skip_line);
                            try content_before_table.append('\n');
                        } else {
                            // End of table, put this line back
                            try content_before_table.appendSlice(skip_line);
                            try content_before_table.append('\n');
                            break;
                        }
                    }
                    current_table_index += 1;
                }
            } else {
                if (!found_target_table) {
                    try content_before_table.appendSlice(line);
                    try content_before_table.append('\n');
                } else {
                    try content_after_table.appendSlice(line);
                    try content_after_table.append('\n');
                }
            }
        } else {
            // We're in our target table
            if (trimmed.len > 0 and trimmed[0] == '|') {
                try table_lines.append(line);
            } else {
                // End of table
                in_table = false;
                // This line goes to content_after_table
                try content_after_table.appendSlice(line);
                try content_after_table.append('\n');
            }
        }
    }

    if (!found_target_table) {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("error", json.Value{ .string = "Table not found at specified index" });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "format_table" });
        try result.put("file", json.Value{ .string = file_path });
        return json.Value{ .object = result };
    }

    // Reconstruct the table text from collected lines
    var table_text = std.ArrayList(u8).init(allocator);
    defer table_text.deinit();
    for (table_lines.items) |line| {
        try table_text.appendSlice(line);
        try table_text.append('\n');
    }

    // Parse the table
    var parsed_table = try table.parseTable(allocator, table_text.items) orelse {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("error", json.Value{ .string = "Failed to parse table" });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "format_table" });
        try result.put("file", json.Value{ .string = file_path });
        return json.Value{ .object = result };
    };
    defer parsed_table.deinit(allocator);

    // Format the table
    const formatted_table = try table.formatTable(allocator, &parsed_table);
    defer allocator.free(formatted_table);

    // Reconstruct the file content
    var new_content = std.ArrayList(u8).init(allocator);
    defer new_content.deinit();

    // Add content before table
    try new_content.appendSlice(content_before_table.items);

    // Add formatted table
    try new_content.appendSlice(formatted_table);
    try new_content.append('\n');

    // Add content after table
    try new_content.appendSlice(content_after_table.items);

    // Remove trailing newline if the original didn't have one
    if (new_content.items.len > 0 and new_content.items[new_content.items.len - 1] == '\n' and
        (original_content.len == 0 or original_content[original_content.len - 1] != '\n'))
    {
        _ = new_content.pop();
    }

    // Write the formatted content back to file
    try fs.writeFile(file_path, new_content.items);

    // Build JSON response
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "format_table" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("table_index", json.Value{ .integer = table_index.integer });
    try result.put("headers_count", json.Value{ .integer = @intCast(parsed_table.headers.len) });
    try result.put("rows_count", json.Value{ .integer = @intCast(parsed_table.rows.len) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

fn reorderTableColumn(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const table_index = params.get("table_index") orelse json.Value{ .integer = 0 };
    const from_index_param = params.get("from_index") orelse {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "reorder_table_column" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("error", json.Value{ .string = "Missing required parameter: from_index" });
        return json.Value{ .object = result };
    };
    const to_index_param = params.get("to_index") orelse {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "reorder_table_column" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("error", json.Value{ .string = "Missing required parameter: to_index" });
        return json.Value{ .object = result };
    };
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    const from_index: usize = @intCast(from_index_param.integer);
    const to_index: usize = @intCast(to_index_param.integer);

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Find all tables in the content
    var lines = std.mem.splitSequence(u8, original_content, "\n");
    var content_before_table = std.ArrayList(u8).init(allocator);
    defer content_before_table.deinit();
    var table_lines = std.ArrayList([]const u8).init(allocator);
    defer table_lines.deinit();
    var content_after_table = std.ArrayList(u8).init(allocator);
    defer content_after_table.deinit();

    var in_table = false;
    var current_table_index: usize = 0;
    var found_target_table = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (!in_table) {
            // Check if this line starts a table
            if (trimmed.len > 0 and trimmed[0] == '|') {
                if (current_table_index == table_index.integer) {
                    // This is our target table
                    found_target_table = true;
                    in_table = true;
                    try table_lines.append(line);
                } else {
                    // This is a different table, add to before content
                    try content_before_table.appendSlice(line);
                    try content_before_table.append('\n');
                }
            } else {
                // Not a table line, add to before content (if we haven't found target table yet) or after content
                if (!found_target_table) {
                    try content_before_table.appendSlice(line);
                    try content_before_table.append('\n');
                } else {
                    try content_after_table.appendSlice(line);
                    try content_after_table.append('\n');
                }
            }
        } else {
            // We're in the target table
            if (trimmed.len > 0 and trimmed[0] == '|') {
                // Still in table
                try table_lines.append(line);
            } else {
                // Table ended
                in_table = false;
                current_table_index += 1;
                try content_after_table.appendSlice(line);
                try content_after_table.append('\n');
            }
        }
    }

    if (!found_target_table) {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "reorder_table_column" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("error", json.Value{ .string = "Table not found at specified index" });
        return json.Value{ .object = result };
    }

    // Join table lines for parsing
    var table_content = std.ArrayList(u8).init(allocator);
    defer table_content.deinit();
    for (table_lines.items, 0..) |line, i| {
        try table_content.appendSlice(line);
        if (i < table_lines.items.len - 1) {
            try table_content.append('\n');
        }
    }

    // Parse the table
    var parsed_table = try table.parseTable(allocator, table_content.items) orelse {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "reorder_table_column" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("error", json.Value{ .string = "Could not parse table" });
        return json.Value{ .object = result };
    };
    defer parsed_table.deinit(allocator);

    // Validate column indices
    if (from_index >= parsed_table.headers.len) {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "reorder_table_column" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("error", json.Value{ .string = "Invalid from_index: column does not exist" });
        return json.Value{ .object = result };
    }

    if (to_index >= parsed_table.headers.len) {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "reorder_table_column" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("error", json.Value{ .string = "Invalid to_index: column does not exist" });
        return json.Value{ .object = result };
    }

    // Store the header names for response
    const moved_header = try allocator.dupe(u8, parsed_table.headers[from_index]);
    defer allocator.free(moved_header);

    // Reorder the column
    try table.moveColumn(allocator, &parsed_table, from_index, to_index);

    // Format the reordered table
    const formatted_table = try table.formatTable(allocator, &parsed_table);
    defer allocator.free(formatted_table);

    // Reconstruct the file content
    var new_content = std.ArrayList(u8).init(allocator);
    defer new_content.deinit();

    // Add content before table
    try new_content.appendSlice(content_before_table.items);

    // Add formatted table
    try new_content.appendSlice(formatted_table);

    // Add content after table
    try new_content.appendSlice(content_after_table.items);

    // Remove trailing newline if original content didn't have one
    if (new_content.items.len > 0 and !std.mem.endsWith(u8, original_content, "\n")) {
        new_content.items.len -= 1;
    }

    // Write the new content back to file
    try fs.writeFile(file_path, new_content.items);

    // Build JSON response
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "reorder_table_column" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("table_index", json.Value{ .integer = table_index.integer });
    try result.put("from_index", json.Value{ .integer = @intCast(from_index) });
    try result.put("to_index", json.Value{ .integer = @intCast(to_index) });
    try result.put("moved_header", json.Value{ .string = moved_header });
    try result.put("total_columns", json.Value{ .integer = @intCast(parsed_table.headers.len) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

fn sortTableColumn(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const table_index = params.get("table_index") orelse json.Value{ .integer = 0 };
    const column_index_param = params.get("column_index") orelse {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "sort_table_column" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("error", json.Value{ .string = "Missing required parameter: column_index" });
        return json.Value{ .object = result };
    };
    const sort_order_str = params.get("sort_order") orelse json.Value{ .string = "asc" };
    const sort_type_str = params.get("sort_type") orelse json.Value{ .string = "auto" };
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    const column_index: usize = @intCast(column_index_param.integer);

    // Parse sort order
    const sort_order = if (std.mem.eql(u8, sort_order_str.string, "desc"))
        table.SortOrder.desc
    else
        table.SortOrder.asc;

    // Parse sort type
    const sort_type = if (std.mem.eql(u8, sort_type_str.string, "string"))
        table.SortType.string
    else if (std.mem.eql(u8, sort_type_str.string, "numeric"))
        table.SortType.numeric
    else
        table.SortType.auto;

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Find all tables in the content (using same pattern as reorderTableColumn)
    var lines = std.mem.splitSequence(u8, original_content, "\n");
    var content_before_table = std.ArrayList(u8).init(allocator);
    defer content_before_table.deinit();
    var table_lines = std.ArrayList([]const u8).init(allocator);
    defer table_lines.deinit();
    var content_after_table = std.ArrayList(u8).init(allocator);
    defer content_after_table.deinit();

    var in_table = false;
    var current_table_index: usize = 0;
    var found_target_table = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (!in_table) {
            // Check if this line starts a table
            if (trimmed.len > 0 and trimmed[0] == '|') {
                if (current_table_index == table_index.integer) {
                    // This is our target table
                    found_target_table = true;
                    in_table = true;
                    try table_lines.append(line);
                } else {
                    // This is a different table, add to before content
                    try content_before_table.appendSlice(line);
                    try content_before_table.append('\n');
                }
            } else {
                // Not a table line, add to before content (if we haven't found target table yet) or after content
                if (!found_target_table) {
                    try content_before_table.appendSlice(line);
                    try content_before_table.append('\n');
                } else {
                    try content_after_table.appendSlice(line);
                    try content_after_table.append('\n');
                }
            }
        } else {
            // We're in the target table
            if (trimmed.len > 0 and trimmed[0] == '|') {
                // Still in table
                try table_lines.append(line);
            } else {
                // Table ended
                in_table = false;
                current_table_index += 1;
                try content_after_table.appendSlice(line);
                try content_after_table.append('\n');
            }
        }
    }

    if (!found_target_table) {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "sort_table_column" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("error", json.Value{ .string = "Table not found at specified index" });
        return json.Value{ .object = result };
    }

    // Join table lines for parsing
    var table_content = std.ArrayList(u8).init(allocator);
    defer table_content.deinit();
    for (table_lines.items, 0..) |line, i| {
        try table_content.appendSlice(line);
        if (i < table_lines.items.len - 1) {
            try table_content.append('\n');
        }
    }

    // Parse the table
    var parsed_table = try table.parseTable(allocator, table_content.items) orelse {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "sort_table_column" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("error", json.Value{ .string = "Could not parse table" });
        return json.Value{ .object = result };
    };
    defer parsed_table.deinit(allocator);

    // Validate column index
    if (column_index >= parsed_table.headers.len) {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "sort_table_column" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("error", json.Value{ .string = "Invalid column_index: column does not exist" });
        return json.Value{ .object = result };
    }

    // Store the header name and row count for response
    const sorted_header = try allocator.dupe(u8, parsed_table.headers[column_index]);
    defer allocator.free(sorted_header);
    const original_row_count = parsed_table.rows.len;

    // Sort the table
    try table.sortTable(allocator, &parsed_table, column_index, sort_order, sort_type);

    // Format the sorted table
    const formatted_table = try table.formatTable(allocator, &parsed_table);
    defer allocator.free(formatted_table);

    // Reconstruct the file content
    var new_content = std.ArrayList(u8).init(allocator);
    defer new_content.deinit();

    // Add content before table
    try new_content.appendSlice(content_before_table.items);

    // Add formatted table
    try new_content.appendSlice(formatted_table);

    // Add content after table
    try new_content.appendSlice(content_after_table.items);

    // Remove trailing newline if original content didn't have one
    if (new_content.items.len > 0 and !std.mem.endsWith(u8, original_content, "\n")) {
        new_content.items.len -= 1;
    }

    // Write the new content back to file
    try fs.writeFile(file_path, new_content.items);

    // Build JSON response
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "sort_table_column" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("table_index", json.Value{ .integer = table_index.integer });
    try result.put("column_index", json.Value{ .integer = @intCast(column_index) });
    try result.put("sorted_column", json.Value{ .string = sorted_header });
    try result.put("sort_order", json.Value{ .string = sort_order_str.string });
    try result.put("sort_type", json.Value{ .string = sort_type_str.string });
    try result.put("rows_sorted", json.Value{ .integer = @intCast(original_row_count) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
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
    var new_content = std.ArrayList(u8){};
    defer new_content.deinit(allocator);

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

// Metadata validation types - must be defined before use

const ValidationConfig = struct {
    require_metadata: bool = false,
    require_content_after_metadata: bool = true,
    required_fields: []const []const u8 = &[_][]const u8{},
    allowed_formats: []const meta.MetadataFormat = &[_]meta.MetadataFormat{ .yaml, .toml },
    max_field_count: ?usize = null,
    validate_field_types: bool = true,
    string_field_max_length: ?usize = null,
    integer_field_range: ?struct { min: i64, max: i64 } = null,
};

const ValidationIssue = struct {
    category: IssueCategory,
    message: []const u8,
    line: ?usize,
    severity: Severity,
    field_name: ?[]const u8 = null,
};

const IssueCategory = enum {
    format_error,
    missing_metadata,
    structure_error,
    required_field_missing,
    invalid_field_type,
    invalid_field_value,
    format_not_supported,
};

const Severity = enum {
    err,
    warning,
    info,
};

fn validateMetadata(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    const content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(content);

    // Parse validation configuration from parameters
    const config = parseValidationConfig(params);

    // Initialize validation results
    var issues = std.ArrayList(ValidationIssue).init(allocator);
    defer issues.deinit();
    var metadata_found = false;
    var format_detected: ?meta.MetadataFormat = null;

    // Attempt to parse front matter
    const metadata_result = meta.parseFrontMatter(allocator, content) catch |err| {
        const issue = ValidationIssue{
            .category = .format_error,
            .message = try std.fmt.allocPrint(allocator, "Failed to parse front matter: {s}", .{@errorName(err)}),
            .line = 1,
            .severity = .err,
        };
        try issues.append(issue);
        return buildValidationResponse(allocator, file_path, false, &issues, null);
    };

    if (metadata_result) |*metadata| {
        defer metadata.deinit(allocator);
        metadata_found = true;
        format_detected = metadata.format;

        // Validate metadata structure and content
        try validateMetadataStructure(allocator, metadata, &config, &issues);
        try validateRequiredFields(allocator, metadata, &config, &issues);
        try validateFieldTypes(allocator, metadata, &config, &issues);
        try validateFieldValues(allocator, metadata, &config, &issues);
    } else if (config.require_metadata) {
        const issue = ValidationIssue{
            .category = .missing_metadata,
            .message = try allocator.dupe(u8, "Document requires front matter metadata"),
            .line = 1,
            .severity = .err,
        };
        try issues.append(issue);
    }

    // Check for metadata-only content if required
    if (metadata_found and config.require_content_after_metadata) {
        const document_content = meta.extractContent(content);
        const meaningful_content = std.mem.trim(u8, document_content, " \t\n\r");
        if (meaningful_content.len == 0) {
            const issue = ValidationIssue{
                .category = .structure_error,
                .message = try allocator.dupe(u8, "Document contains only metadata without meaningful content"),
                .line = null,
                .severity = .warning,
            };
            try issues.append(issue);
        }
    }

    const is_valid = issues.items.len == 0 or !hasErrorSeverityIssues(&issues);
    return buildValidationResponse(allocator, file_path, is_valid, &issues, format_detected);
}

fn parseValidationConfig(params: json.ObjectMap) ValidationConfig {
    var config = ValidationConfig{};

    if (params.get("require_metadata")) |val| {
        if (val == .bool) config.require_metadata = val.bool;
    }

    if (params.get("require_content_after_metadata")) |val| {
        if (val == .bool) config.require_content_after_metadata = val.bool;
    }

    if (params.get("max_field_count")) |val| {
        if (val == .integer) config.max_field_count = @as(usize, @intCast(val.integer));
    }

    if (params.get("validate_field_types")) |val| {
        if (val == .bool) config.validate_field_types = val.bool;
    }

    if (params.get("string_field_max_length")) |val| {
        if (val == .integer) config.string_field_max_length = @as(usize, @intCast(val.integer));
    }

    // Note: required_fields parsing would need more complex implementation
    // For now, using default empty array

    return config;
}

fn validateMetadataStructure(allocator: std.mem.Allocator, metadata: *const meta.DocumentMetadata, config: *const ValidationConfig, issues: *std.ArrayList(ValidationIssue)) !void {
    // Check if format is supported
    var format_supported = false;
    for (config.allowed_formats) |allowed_format| {
        if (metadata.format == allowed_format) {
            format_supported = true;
            break;
        }
    }

    if (!format_supported) {
        const issue = ValidationIssue{
            .category = .format_not_supported,
            .message = try std.fmt.allocPrint(allocator, "Metadata format '{s}' is not supported", .{@tagName(metadata.format)}),
            .line = 1,
            .severity = .err,
        };
        try issues.append(issue);
    }

    // Check field count limits
    if (config.max_field_count) |max_count| {
        if (metadata.content.count() > max_count) {
            const issue = ValidationIssue{
                .category = .structure_error,
                .message = try std.fmt.allocPrint(allocator, "Metadata contains {} fields, maximum allowed is {}", .{ metadata.content.count(), max_count }),
                .line = 1,
                .severity = .warning,
            };
            try issues.append(issue);
        }
    }

    // Check for empty metadata
    if (metadata.content.count() == 0) {
        const issue = ValidationIssue{
            .category = .structure_error,
            .message = try allocator.dupe(u8, "Metadata section is empty"),
            .line = 1,
            .severity = .warning,
        };
        try issues.append(issue);
    }
}

fn validateRequiredFields(allocator: std.mem.Allocator, metadata: *const meta.DocumentMetadata, config: *const ValidationConfig, issues: *std.ArrayList(ValidationIssue)) !void {
    for (config.required_fields) |required_field| {
        if (metadata.get(required_field) == null) {
            const issue = ValidationIssue{
                .category = .required_field_missing,
                .message = try std.fmt.allocPrint(allocator, "Required field '{s}' is missing", .{required_field}),
                .line = null,
                .severity = .err,
                .field_name = try allocator.dupe(u8, required_field),
            };
            try issues.append(issue);
        }
    }
}

fn validateFieldTypes(allocator: std.mem.Allocator, metadata: *const meta.DocumentMetadata, config: *const ValidationConfig, issues: *std.ArrayList(ValidationIssue)) !void {
    if (!config.validate_field_types) return;

    var iterator = metadata.content.iterator();
    while (iterator.next()) |entry| {
        const field_name = entry.key_ptr.*;
        const field_value = entry.value_ptr.*;

        // Basic type validation - check for supported types
        switch (field_value.*) {
            .array => |arr| {
                if (arr.len == 0) {
                    const issue = ValidationIssue{
                        .category = .invalid_field_value,
                        .message = try std.fmt.allocPrint(allocator, "Field '{}' contains empty array", .{field_name}),
                        .line = null,
                        .severity = .warning,
                        .field_name = try allocator.dupe(u8, field_name),
                    };
                    try issues.append(issue);
                }
            },
            .object => {
                // Object validation could be expanded
                const issue = ValidationIssue{
                    .category = .invalid_field_type,
                    .message = try std.fmt.allocPrint(allocator, "Field '{}' contains complex object type (limited support)", .{field_name}),
                    .line = null,
                    .severity = .info,
                    .field_name = try allocator.dupe(u8, field_name),
                };
                try issues.append(issue);
            },
            else => {}, // Other types are fine
        }
    }
}

fn validateFieldValues(allocator: std.mem.Allocator, metadata: *const meta.DocumentMetadata, config: *const ValidationConfig, issues: *std.ArrayList(ValidationIssue)) !void {
    var iterator = metadata.content.iterator();
    while (iterator.next()) |entry| {
        const field_name = entry.key_ptr.*;
        const field_value = entry.value_ptr.*;

        switch (field_value.*) {
            .string => |str| {
                // Check string length limits
                if (config.string_field_max_length) |max_len| {
                    if (str.len > max_len) {
                        const issue = ValidationIssue{
                            .category = .invalid_field_value,
                            .message = try std.fmt.allocPrint(allocator, "Field '{}' exceeds maximum length of {} characters", .{ field_name, max_len }),
                            .line = null,
                            .severity = .warning,
                            .field_name = try allocator.dupe(u8, field_name),
                        };
                        try issues.append(issue);
                    }
                }

                // Check for empty string values
                if (str.len == 0) {
                    const issue = ValidationIssue{
                        .category = .invalid_field_value,
                        .message = try std.fmt.allocPrint(allocator, "Field '{}' contains empty string", .{field_name}),
                        .line = null,
                        .severity = .info,
                        .field_name = try allocator.dupe(u8, field_name),
                    };
                    try issues.append(issue);
                }
            },
            .integer => |int_val| {
                // Check integer range limits
                if (config.integer_field_range) |range| {
                    if (int_val < range.min or int_val > range.max) {
                        const issue = ValidationIssue{
                            .category = .invalid_field_value,
                            .message = try std.fmt.allocPrint(allocator, "Field '{}' value {} is outside valid range [{}, {}]", .{ field_name, int_val, range.min, range.max }),
                            .line = null,
                            .severity = .warning,
                            .field_name = try allocator.dupe(u8, field_name),
                        };
                        try issues.append(issue);
                    }
                }
            },
            .float => |float_val| {
                // Basic float validation - check for NaN and infinity
                if (std.math.isNan(float_val) or std.math.isInf(float_val)) {
                    const issue = ValidationIssue{
                        .category = .invalid_field_value,
                        .message = try std.fmt.allocPrint(allocator, "Field '{}' contains invalid float value", .{field_name}),
                        .line = null,
                        .severity = .err,
                        .field_name = try allocator.dupe(u8, field_name),
                    };
                    try issues.append(issue);
                }
            },
            else => {}, // Other types don't need value validation for now
        }
    }
}

fn hasErrorSeverityIssues(issues: *const std.ArrayList(ValidationIssue)) bool {
    for (issues.items) |issue| {
        if (issue.severity == .err) return true;
    }
    return false;
}

fn buildValidationResponse(allocator: std.mem.Allocator, file_path: []const u8, is_valid: bool, issues: *const std.ArrayList(ValidationIssue), format_detected: ?meta.MetadataFormat) !json.Value {
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "validate_metadata" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("valid", json.Value{ .bool = is_valid });

    // Add detected format information
    if (format_detected) |format| {
        try result.put("format", json.Value{ .string = @tagName(format) });
    } else {
        try result.put("format", json.Value{ .string = "none" });
    }

    // Build issues array
    var issues_array = json.Array.init(allocator);
    for (issues.items) |issue| {
        var issue_obj = json.ObjectMap.init(allocator);
        try issue_obj.put("category", json.Value{ .string = @tagName(issue.category) });
        try issue_obj.put("message", json.Value{ .string = issue.message });
        try issue_obj.put("severity", json.Value{ .string = @tagName(issue.severity) });

        if (issue.line) |line_num| {
            try issue_obj.put("line", json.Value{ .integer = @intCast(line_num) });
        }

        if (issue.field_name) |field_name| {
            try issue_obj.put("field", json.Value{ .string = field_name });
        }

        try issues_array.append(json.Value{ .object = issue_obj });
    }
    try result.put("issues", json.Value{ .array = issues_array });

    // Add summary statistics
    var summary = json.ObjectMap.init(allocator);
    try summary.put("total_issues", json.Value{ .integer = @intCast(issues.items.len) });

    var error_count: usize = 0;
    var warning_count: usize = 0;
    var info_count: usize = 0;

    for (issues.items) |issue| {
        switch (issue.severity) {
            .err => error_count += 1,
            .warning => warning_count += 1,
            .info => info_count += 1,
        }
    }

    try summary.put("errors", json.Value{ .integer = @intCast(error_count) });
    try summary.put("warnings", json.Value{ .integer = @intCast(warning_count) });
    try summary.put("info", json.Value{ .integer = @intCast(info_count) });

    try result.put("summary", json.Value{ .object = summary });

    return json.Value{ .object = result };
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
            var header_prefix = std.ArrayList(u8){};
            defer header_prefix.deinit(allocator);
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

            var result = std.ArrayList(u8){};
            defer result.deinit(allocator);

            var lines = std.mem.splitScalar(u8, original_content, '\n');
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
    // Parse required parameters
    const width = params.get("width") orelse return Error.InvalidParameters;
    const width_val = switch (width) {
        .integer => @as(usize, @intCast(width.integer)),
        else => return Error.InvalidParameters,
    };

    // Parse optional parameters
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };
    const selection_mode = params.get("selection_mode") orelse json.Value{ .string = "all" };

    // Validate width parameter
    if (width_val == 0 or width_val > 1000) {
        return Error.InvalidParameters;
    }

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    // Read original content
    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Apply text wrapping based on selection mode
    const new_content = blk: {
        if (std.mem.eql(u8, selection_mode.string, "all")) {
            // Wrap entire document
            break :blk try text.wrapText(allocator, original_content, width_val);
        } else if (std.mem.eql(u8, selection_mode.string, "lines")) {
            // Wrap specific line range
            const start_line = params.get("start_line") orelse return Error.InvalidParameters;
            const end_line = params.get("end_line") orelse start_line;

            var result = std.ArrayList(u8){};
            defer result.deinit(allocator);

            var lines = std.mem.splitScalar(u8, original_content, '\n');
            var current_line: usize = 0;
            var wrapped_lines: usize = 0;

            while (lines.next()) |line| {
                if (current_line >= start_line.integer and current_line <= end_line.integer) {
                    // Wrap this line
                    const wrapped_line = try text.wrapText(allocator, line, width_val);
                    defer allocator.free(wrapped_line);

                    // Remove the trailing newline that wrapText adds for single lines
                    const clean_wrapped = if (wrapped_line.len > 0 and wrapped_line[wrapped_line.len - 1] == '\n')
                        wrapped_line[0 .. wrapped_line.len - 1]
                    else
                        wrapped_line;

                    try result.appendSlice(clean_wrapped);
                    wrapped_lines += 1;
                } else {
                    try result.appendSlice(line);
                }

                if (lines.index) |_| {
                    try result.append('\n');
                }
                current_line += 1;
            }

            break :blk try result.toOwnedSlice();
        } else if (std.mem.eql(u8, selection_mode.string, "pattern")) {
            // Wrap text matching a specific pattern
            const pattern = params.get("pattern") orelse return Error.InvalidParameters;
            const search_options = text.SearchOptions{ .regex_mode = false };

            // Find all occurrences of the pattern
            const matches = try text.findAll(allocator, original_content, pattern.string, search_options);
            defer {
                for (matches) |match| {
                    allocator.free(match.content);
                }
                allocator.free(matches);
            }

            var result = try allocator.dupe(u8, original_content);

            // Replace each match with wrapped version (in reverse order to maintain positions)
            var i: usize = matches.len;
            while (i > 0) {
                i -= 1;
                const match = matches[i];
                const wrapped = try text.wrapText(allocator, match.content, width_val);
                defer allocator.free(wrapped);

                // Remove trailing newline for cleaner replacement
                const clean_wrapped = if (wrapped.len > 0 and wrapped[wrapped.len - 1] == '\n')
                    wrapped[0 .. wrapped.len - 1]
                else
                    wrapped;

                const replacement_opts = text.SearchOptions{ .regex_mode = false };
                const new_result = try text.replaceAll(allocator, result, match.content, clean_wrapped, replacement_opts);
                allocator.free(result);
                result = new_result;
            }

            break :blk result;
        } else {
            return Error.InvalidParameters;
        }
    };
    defer allocator.free(new_content);

    // Write wrapped content back to file
    try fs.writeFile(file_path, new_content);

    // Count lines for metadata
    var line_count: usize = 0;
    for (new_content) |char| {
        if (char == '\n') line_count += 1;
    }

    // Create response
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "wrap_text" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("width", json.Value{ .integer = @intCast(width_val) });
    try result.put("selection_mode", json.Value{ .string = selection_mode.string });
    try result.put("line_count", json.Value{ .integer = @intCast(line_count) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

// List processing structures
const ListProcessOptions = struct {
    list_style: []const u8,
    fix_indentation: bool,
    normalize_markers: bool,
    fix_numbering: bool,
};

const ListProcessResult = struct {
    content: []u8,
    lists_fixed: usize,
    indentation_fixed: usize,
    markers_normalized: usize,
    numbering_fixed: usize,
};

const ListType = enum {
    unordered,
    ordered,
    none,
};

const ListItem = struct {
    line_index: usize,
    indent_level: usize,
    marker: []const u8,
    content: []const u8,
    list_type: ListType,
};

// Process all lists in the content
fn processLists(allocator: std.mem.Allocator, content: []const u8, options: ListProcessOptions) !ListProcessResult {
    var lines = std.mem.splitScalar(u8, content, '\n');
    var processed_lines = std.array_list.Managed([]u8).init(allocator);
    defer {
        for (processed_lines.items) |line| {
            allocator.free(line);
        }
        processed_lines.deinit();
    }

    var lists_fixed: usize = 0;
    var indentation_fixed: usize = 0;
    var markers_normalized: usize = 0;
    var numbering_fixed: usize = 0;

    var in_list = false;
    var current_list_items = std.array_list.Managed(ListItem).init(allocator);
    defer current_list_items.deinit();

    var line_index: usize = 0;
    var ordered_counter: usize = 1;

    // Process each line
    while (lines.next()) |line| : (line_index += 1) {
        const list_item = parseListItem(line, line_index);

        if (list_item.list_type != .none) {
            // We're in a list item
            if (!in_list) {
                in_list = true;
                ordered_counter = 1;
            }

            try current_list_items.append(allocator, list_item);

            // Process this list item based on options
            const processed_line = try processListItem(allocator, list_item, &ordered_counter, options);

            // Track metrics
            if (!std.mem.eql(u8, processed_line, line)) {
                lists_fixed += 1;
                if (hasIndentationFix(line, processed_line)) indentation_fixed += 1;
                if (hasMarkerNormalization(line, processed_line)) markers_normalized += 1;
                if (hasNumberingFix(line, processed_line)) numbering_fixed += 1;
            }

            try processed_lines.append(allocator, processed_line);
        } else {
            // Not a list item
            if (in_list and std.mem.trim(u8, line, " \t\n\r").len == 0) {
                // Empty line in list - preserve it
                const line_copy = try allocator.dupe(u8, line);
                try processed_lines.append(allocator, line_copy);
            } else if (in_list) {
                // End of list
                in_list = false;
                current_list_items.clearRetainingCapacity();
                ordered_counter = 1;

                const line_copy = try allocator.dupe(u8, line);
                try processed_lines.append(allocator, line_copy);
            } else {
                // Normal content line
                const line_copy = try allocator.dupe(u8, line);
                try processed_lines.append(allocator, line_copy);
            }
        }
    }

    // Reconstruct content
    var result = std.array_list.Managed(u8).init(allocator);
    for (processed_lines.items, 0..) |line, i| {
        try result.appendSlice(allocator, line);
        if (i < processed_lines.items.len - 1) {
            try result.append(allocator, '\n');
        }
    }

    return ListProcessResult{
        .content = try result.toOwnedSlice(),
        .lists_fixed = lists_fixed,
        .indentation_fixed = indentation_fixed,
        .markers_normalized = markers_normalized,
        .numbering_fixed = numbering_fixed,
    };
}

// Parse a line to determine if it's a list item
fn parseListItem(line: []const u8, line_index: usize) ListItem {
    const trimmed_start = std.mem.trimLeft(u8, line, " \t");
    const indent_level = line.len - trimmed_start.len;

    // Check for unordered list markers
    if (trimmed_start.len >= 2) {
        const first_char = trimmed_start[0];
        const second_char = trimmed_start[1];

        if ((first_char == '-' or first_char == '*' or first_char == '+') and
            (second_char == ' ' or second_char == '\t'))
        {
            return ListItem{
                .line_index = line_index,
                .indent_level = indent_level,
                .marker = trimmed_start[0..1],
                .content = std.mem.trim(u8, trimmed_start[2..], " \t"),
                .list_type = .unordered,
            };
        }
    }

    // Check for ordered list markers (number followed by .)
    if (trimmed_start.len >= 3) {
        var num_end: usize = 0;
        while (num_end < trimmed_start.len and std.ascii.isDigit(trimmed_start[num_end])) {
            num_end += 1;
        }

        if (num_end > 0 and num_end < trimmed_start.len and
            trimmed_start[num_end] == '.' and
            num_end + 1 < trimmed_start.len and
            (trimmed_start[num_end + 1] == ' ' or trimmed_start[num_end + 1] == '\t'))
        {
            return ListItem{
                .line_index = line_index,
                .indent_level = indent_level,
                .marker = trimmed_start[0 .. num_end + 1],
                .content = std.mem.trim(u8, trimmed_start[num_end + 2 ..], " \t"),
                .list_type = .ordered,
            };
        }
    }

    return ListItem{
        .line_index = line_index,
        .indent_level = 0,
        .marker = "",
        .content = "",
        .list_type = .none,
    };
}

// Process a single list item according to options
fn processListItem(allocator: std.mem.Allocator, item: ListItem, counter: *usize, options: ListProcessOptions) ![]u8 {
    var result = std.array_list.Managed(u8).init(allocator);

    // Apply indentation fix
    const fixed_indent_level = if (options.fix_indentation)
        (item.indent_level / 4) * 4 // Normalize to multiples of 4
    else
        item.indent_level;

    // Add indentation (always use spaces)
    for (0..fixed_indent_level) |_| {
        try result.append(allocator, ' ');
    }

    // Apply marker normalization
    if (item.list_type == .unordered and options.normalize_markers) {
        const marker_char = switch (options.list_style[0]) {
            'd' => '-', // dash
            'a' => '*', // asterisk
            'p' => '+', // plus
            else => '-',
        };
        try result.append(allocator, marker_char);
    } else if (item.list_type == .ordered and options.fix_numbering) {
        const num_str = try std.fmt.allocPrint(allocator, "{d}.", .{counter.*});
        defer allocator.free(num_str);
        try result.appendSlice(allocator, num_str);
        counter.* += 1;
    } else {
        try result.appendSlice(allocator, item.marker);
        if (item.list_type == .ordered) {
            counter.* += 1;
        }
    }

    // Add space and content
    try result.append(allocator, ' ');
    try result.appendSlice(allocator, item.content);

    return result.toOwnedSlice();
}

// Helper functions to detect what was fixed
fn hasIndentationFix(original: []const u8, processed: []const u8) bool {
    const orig_indent = original.len - std.mem.trimLeft(u8, original, " \t").len;
    const proc_indent = processed.len - std.mem.trimLeft(u8, processed, " \t").len;
    return orig_indent != proc_indent;
}

fn hasMarkerNormalization(original: []const u8, processed: []const u8) bool {
    const orig_trimmed = std.mem.trimLeft(u8, original, " \t");
    const proc_trimmed = std.mem.trimLeft(u8, processed, " \t");
    if (orig_trimmed.len == 0 or proc_trimmed.len == 0) return false;
    return orig_trimmed[0] != proc_trimmed[0];
}

fn hasNumberingFix(original: []const u8, processed: []const u8) bool {
    const orig_trimmed = std.mem.trimLeft(u8, original, " \t");
    const proc_trimmed = std.mem.trimLeft(u8, processed, " \t");

    // Extract number from original
    var orig_num_end: usize = 0;
    while (orig_num_end < orig_trimmed.len and std.ascii.isDigit(orig_trimmed[orig_num_end])) {
        orig_num_end += 1;
    }

    // Extract number from processed
    var proc_num_end: usize = 0;
    while (proc_num_end < proc_trimmed.len and std.ascii.isDigit(proc_trimmed[proc_num_end])) {
        proc_num_end += 1;
    }

    if (orig_num_end == 0 or proc_num_end == 0) return false;

    return !std.mem.eql(u8, orig_trimmed[0..orig_num_end], proc_trimmed[0..proc_num_end]);
}

fn fixLists(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    // Parse parameters with defaults
    const list_style_param = params.get("list_style") orelse json.Value{ .string = "dash" };
    const fix_indentation = params.get("fix_indentation") orelse json.Value{ .bool = true };
    const normalize_markers = params.get("normalize_markers") orelse json.Value{ .bool = true };
    const fix_numbering = params.get("fix_numbering") orelse json.Value{ .bool = true };
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Validate list_style parameter
    const list_style = list_style_param.string;
    if (!std.mem.eql(u8, list_style, "dash") and
        !std.mem.eql(u8, list_style, "asterisk") and
        !std.mem.eql(u8, list_style, "plus"))
    {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("error", json.Value{ .string = "Invalid list_style. Must be 'dash', 'asterisk', or 'plus'" });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "fix_lists" });
        try result.put("file", json.Value{ .string = file_path });
        return json.Value{ .object = result };
    }

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    // Read original content
    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Process lists in the content
    const processed_result = try processLists(allocator, original_content, .{
        .list_style = list_style,
        .fix_indentation = fix_indentation.bool,
        .normalize_markers = normalize_markers.bool,
        .fix_numbering = fix_numbering.bool,
    });
    defer allocator.free(processed_result.content);

    // Write modified content back to file
    try fs.writeFile(file_path, processed_result.content);

    // Build JSON response with metrics
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "fix_lists" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("lists_fixed", json.Value{ .integer = @intCast(processed_result.lists_fixed) });
    try result.put("indentation_fixed", json.Value{ .integer = @intCast(processed_result.indentation_fixed) });
    try result.put("markers_normalized", json.Value{ .integer = @intCast(processed_result.markers_normalized) });
    try result.put("numbering_fixed", json.Value{ .integer = @intCast(processed_result.numbering_fixed) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
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
        var result = std.ArrayList(u8){};
        try result.appendSlice(allocator, insert_content);
        try result.append(allocator, '\n');
        try result.appendSlice(allocator, original);
        return result.toOwnedSlice(allocator);
    } else if (std.mem.eql(u8, location, "end")) {
        var result = std.ArrayList(u8){};
        try result.appendSlice(allocator, original);
        try result.append(allocator, '\n');
        try result.appendSlice(allocator, insert_content);
        return result.toOwnedSlice(allocator);
    } else if (std.mem.startsWith(u8, location, "line:")) {
        const line_num = std.fmt.parseInt(usize, location[5..], 10) catch return Error.InvalidLocation;
        return insertAtLine(allocator, original, insert_content, line_num);
    } else {
        return Error.InvalidLocation;
    }
}

fn insertAtLine(allocator: std.mem.Allocator, content: []const u8, insert_text: []const u8, line_num: usize) ![]u8 {
    var result = std.ArrayList(u8){};
    var lines = std.mem.split(u8, content, "\n");
    var current_line: usize = 0;

    while (lines.next()) |line| {
        if (current_line == line_num) {
            try result.appendSlice(allocator, insert_text);
            try result.append(allocator, '\n');
        }
        try result.appendSlice(allocator, line);
        try result.append(allocator, '\n');
        current_line += 1;
    }

    // If line_num is beyond content, append at end
    if (line_num >= current_line) {
        try result.appendSlice(allocator, insert_text);
        try result.append(allocator, '\n');
    }

    return result.toOwnedSlice(allocator);
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
    var slug = std.ArrayList(u8){};

    for (input_text) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            try slug.append(allocator, std.ascii.toLower(c));
        } else if (c == ' ' or c == '-' or c == '_') {
            try slug.append(allocator, '-');
        }
    }

    return slug.toOwnedSlice(allocator);
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

/// Process template with variable substitution
fn processTemplate(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    // Get parameters
    const template_name = params.get("template_name");
    const template_file = params.get("template_file");
    const variables_json = params.get("variables");
    const output_file = params.get("output_file");

    // Validate parameters - must have either template_name or template_file
    if (template_name == null and template_file == null) {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("error", json.Value{ .string = "Either template_name or template_file must be provided" });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "process_template" });
        try result.put("file", json.Value{ .string = file_path });
        return json.Value{ .object = result };
    }

    // Load template
    var loaded_template: template.Template = undefined;
    var template_loaded = false;
    defer if (template_loaded) loaded_template.deinit(allocator);

    if (template_name) |name| {
        // Load built-in template
        loaded_template = template.getBuiltinTemplate(allocator, name.string) catch |err| switch (err) {
            template.Error.TemplateNotFound => {
                var result = json.ObjectMap.init(allocator);
                try result.put("success", json.Value{ .bool = false });
                try result.put("error", json.Value{ .string = try std.fmt.allocPrint(allocator, "Built-in template not found: {s}", .{name.string}) });
                try result.put("tool", json.Value{ .string = "content_editor" });
                try result.put("command", json.Value{ .string = "process_template" });
                try result.put("file", json.Value{ .string = file_path });
                return json.Value{ .object = result };
            },
            else => |e| return e,
        };
        template_loaded = true;
    } else if (template_file) |file| {
        // Load template from file
        loaded_template = template.loadTemplate(allocator, file.string) catch |err| switch (err) {
            template.Error.TemplateNotFound => {
                var result = json.ObjectMap.init(allocator);
                try result.put("success", json.Value{ .bool = false });
                try result.put("error", json.Value{ .string = try std.fmt.allocPrint(allocator, "Template file not found: {s}", .{file.string}) });
                try result.put("tool", json.Value{ .string = "content_editor" });
                try result.put("command", json.Value{ .string = "process_template" });
                try result.put("file", json.Value{ .string = file_path });
                return json.Value{ .object = result };
            },
            else => |e| return e,
        };
        template_loaded = true;
    }

    // Parse variables from JSON
    var variables = std.StringHashMap(template.TemplateVariable).init(allocator);
    defer {
        var iterator = variables.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            switch (entry.value_ptr.*) {
                .string => |s| allocator.free(s),
                else => {},
            }
        }
        variables.deinit();
    }

    if (variables_json) |vars| {
        if (vars != .object) {
            var result = json.ObjectMap.init(allocator);
            try result.put("success", json.Value{ .bool = false });
            try result.put("error", json.Value{ .string = "Variables must be a JSON object" });
            try result.put("tool", json.Value{ .string = "content_editor" });
            try result.put("command", json.Value{ .string = "process_template" });
            try result.put("file", json.Value{ .string = file_path });
            return json.Value{ .object = result };
        }

        // Convert JSON variables to template variables
        var vars_iter = vars.object.iterator();
        while (vars_iter.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const value = switch (entry.value_ptr.*) {
                .string => |s| template.TemplateVariable{ .string = try allocator.dupe(u8, s) },
                .integer => |i| template.TemplateVariable{ .integer = i },
                .float => |f| template.TemplateVariable{ .float = f },
                .bool => |b| template.TemplateVariable{ .boolean = b },
                else => template.TemplateVariable{ .string = try allocator.dupe(u8, "unknown") },
            };
            try variables.put(key, value);
        }
    }

    // Render template
    const rendered_content = template.renderTemplate(allocator, &loaded_template, variables) catch |err| switch (err) {
        template.Error.OutOfMemory => return error.OutOfMemory,
        else => {
            var result = json.ObjectMap.init(allocator);
            try result.put("success", json.Value{ .bool = false });
            try result.put("error", json.Value{ .string = "Failed to render template" });
            try result.put("tool", json.Value{ .string = "content_editor" });
            try result.put("command", json.Value{ .string = "process_template" });
            try result.put("file", json.Value{ .string = file_path });
            return json.Value{ .object = result };
        },
    };
    defer allocator.free(rendered_content);

    // Determine output file
    const target_file = if (output_file) |out_file| out_file.string else file_path;

    // Write rendered content to file
    try fs.writeFile(target_file, rendered_content);

    // Build success response
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("template_name", json.Value{ .string = loaded_template.name });
    try result.put("variables_count", json.Value{ .integer = @intCast(variables.count()) });
    try result.put("content_length", json.Value{ .integer = @intCast(rendered_content.len) });
    try result.put("output_file", json.Value{ .string = target_file });
    try result.put("command", json.Value{ .string = "process_template" });
    try result.put("tool", json.Value{ .string = "content_editor" });

    return json.Value{ .object = result };
}

// Tests
test "addTableColumn - add column at end with data" {
    const allocator = std.testing.allocator;

    // Create a test markdown file content with a table
    const test_content =
        \\# Test Document
        \\
        \\Here's a test table:
        \\
        \\| Name | Age |
        \\|------|-----|
        \\| Alice | 30 |
        \\| Bob | 25 |
        \\
        \\Some content after.
    ;

    // Write test file
    const test_file_path = "test_add_column.md";
    try fs.writeFile(test_file_path, test_content);
    defer fs.deleteFile(test_file_path) catch {};

    // Create parameters JSON for adding a column
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("header", json.Value{ .string = "City" });
    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("alignment", json.Value{ .string = "left" });

    // Create column data array
    var column_data = json.Array.init(allocator);
    defer column_data.deinit();
    try column_data.append(json.Value{ .string = "NYC" });
    try column_data.append(json.Value{ .string = "LA" });
    try params.put("column_data", json.Value{ .array = column_data });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute addTableColumn
    const result = try addTableColumn(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the result indicates success
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expectEqualStrings("add_table_column", result.object.get("command").?.string);
    try std.testing.expectEqualStrings("City", result.object.get("header").?.string);
    try std.testing.expect(result.object.get("column_data_count").?.integer == 2);

    // Read the modified file and verify the table was updated
    const modified_content = try fs.readFileAlloc(allocator, test_file_path, null);
    defer allocator.free(modified_content);

    // The modified content should contain the new column
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Name | Age | City |") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Alice | 30 | NYC |") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Bob | 25 | LA |") != null);
}

test "addTableColumn - add column at specific index" {
    const allocator = std.testing.allocator;

    // Create a test markdown file content with a table
    const test_content =
        \\| Name | Age | Status |
        \\|------|-----|--------|
        \\| Alice | 30 | Active |
        \\| Bob | 25 | Inactive |
    ;

    // Write test file
    const test_file_path = "test_add_column_index.md";
    try fs.writeFile(test_file_path, test_content);
    defer fs.deleteFile(test_file_path) catch {};

    // Create parameters JSON for adding a column at index 1 (between Name and Age)
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("header", json.Value{ .string = "ID" });
    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("column_index", json.Value{ .integer = 1 });
    try params.put("alignment", json.Value{ .string = "center" });

    // Create column data array
    var column_data = json.Array.init(allocator);
    defer column_data.deinit();
    try column_data.append(json.Value{ .string = "001" });
    try column_data.append(json.Value{ .string = "002" });
    try params.put("column_data", json.Value{ .array = column_data });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute addTableColumn
    const result = try addTableColumn(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the result indicates success
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expect(result.object.get("column_index").?.integer == 1);
    try std.testing.expectEqualStrings("center", result.object.get("alignment").?.string);

    // Read the modified file and verify the table was updated with column at index 1
    const modified_content = try fs.readFileAlloc(allocator, test_file_path, null);
    defer allocator.free(modified_content);

    // The modified content should have ID column between Name and Age
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Name | ID | Age | Status |") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Alice | 001 | 30 | Active |") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Bob | 002 | 25 | Inactive |") != null);
}

test "addTableColumn - add column without data (empty cells)" {
    const allocator = std.testing.allocator;

    // Create a test markdown file content with a table
    const test_content =
        \\| Product | Price |
        \\|---------|-------|
        \\| Widget | $10 |
        \\| Gadget | $20 |
        \\| Tool | $15 |
    ;

    // Write test file
    const test_file_path = "test_add_column_empty.md";
    try fs.writeFile(test_file_path, test_content);
    defer fs.deleteFile(test_file_path) catch {};

    // Create parameters JSON for adding a column without data
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("header", json.Value{ .string = "Category" });
    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("alignment", json.Value{ .string = "right" });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute addTableColumn (without column_data)
    const result = try addTableColumn(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the result indicates success
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expectEqualStrings("Category", result.object.get("header").?.string);
    try std.testing.expect(result.object.get("column_data_count").?.integer == 0);

    // Read the modified file and verify the table was updated with empty cells
    const modified_content = try fs.readFileAlloc(allocator, test_file_path, null);
    defer allocator.free(modified_content);

    // The modified content should have Category column with empty cells
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Product | Price | Category |") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Widget | $10 |  |") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Gadget | $20 |  |") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Tool | $15 |  |") != null);
}

test "addTableColumn - multiple tables, target second table" {
    const allocator = std.testing.allocator;

    // Create a test markdown file content with multiple tables
    const test_content =
        \\# First Table
        \\| A | B |
        \\|---|---|
        \\| 1 | 2 |
        \\
        \\# Second Table  
        \\| X | Y |
        \\|---|---|
        \\| 3 | 4 |
        \\| 5 | 6 |
        \\
        \\End of document.
    ;

    // Write test file
    const test_file_path = "test_add_column_multiple.md";
    try fs.writeFile(test_file_path, test_content);
    defer fs.deleteFile(test_file_path) catch {};

    // Create parameters JSON for adding a column to the second table (index 1)
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("header", json.Value{ .string = "Z" });
    try params.put("table_index", json.Value{ .integer = 1 }); // Target second table
    try params.put("alignment", json.Value{ .string = "left" });

    // Create column data array
    var column_data = json.Array.init(allocator);
    defer column_data.deinit();
    try column_data.append(json.Value{ .string = "7" });
    try column_data.append(json.Value{ .string = "8" });
    try params.put("column_data", json.Value{ .array = column_data });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute addTableColumn
    const result = try addTableColumn(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the result indicates success
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expect(result.object.get("table_index").?.integer == 1);

    // Read the modified file and verify only the second table was modified
    const modified_content = try fs.readFileAlloc(allocator, test_file_path, null);
    defer allocator.free(modified_content);

    // First table should remain unchanged
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| A | B |") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| 1 | 2 |") != null);

    // Second table should have the new column
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| X | Y | Z |") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| 3 | 4 | 7 |") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| 5 | 6 | 8 |") != null);
}

test "addTableColumn - error cases" {
    const allocator = std.testing.allocator;

    // Test case 1: Invalid table index (table doesn't exist)
    const test_content =
        \\| Name | Age |
        \\|------|-----|
        \\| Alice | 30 |
    ;

    const test_file_path = "test_add_column_error.md";
    try fs.writeFile(test_file_path, test_content);
    defer fs.deleteFile(test_file_path) catch {};

    // Create parameters with invalid table index
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("header", json.Value{ .string = "City" });
    try params.put("table_index", json.Value{ .integer = 5 }); // Invalid - table doesn't exist
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute addTableColumn - should return error
    const result = try addTableColumn(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // This should fail with InvalidParameters because table index 5 doesn't exist
    try std.testing.expect(result.object.get("success").?.bool == false);

    // Test case 2: Missing required header parameter
    var invalid_params = json.ObjectMap.init(allocator);
    defer invalid_params.deinit();
    try invalid_params.put("table_index", json.Value{ .integer = 0 });
    // Missing header parameter

    const error_result = addTableColumn(allocator, invalid_params, test_file_path);
    try std.testing.expectError(Error.InvalidParameters, error_result);
}

test "deleteTableColumn - delete middle column" {
    const allocator = std.testing.allocator;

    // Create a test markdown file content with a table
    const test_content =
        \\# Test Document
        \\
        \\Here's a test table:
        \\
        \\| Name | Age | City |
        \\|------|-----|------|
        \\| Alice | 30 | NYC |
        \\| Bob | 25 | LA |
        \\
        \\Some content after.
    ;

    // Write test file
    const test_file_path = "test_delete_column.md";
    try fs.writeFile(test_file_path, test_content);
    defer fs.deleteFile(test_file_path) catch {};

    // Create parameters JSON for deleting the Age column (index 1)
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("column_index", json.Value{ .integer = 1 });
    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute deleteTableColumn
    const result = try deleteTableColumn(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the result indicates success
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expect(result.object.get("deleted_header") != null);
    try std.testing.expect(std.mem.eql(u8, result.object.get("deleted_header").?.string, "Age"));
    try std.testing.expect(result.object.get("remaining_columns").?.integer == 2);
    try std.testing.expect(result.object.get("column_index").?.integer == 1);

    // Verify the file content was updated correctly
    const updated_content = try fs.readFileAlloc(allocator, test_file_path, null);
    defer allocator.free(updated_content);

    // The Age column should be removed
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "| Name | City |") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "| Alice | NYC |") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "| Bob | LA |") != null);
    // Age column should be gone
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "Age") == null);
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "30") == null);
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "25") == null);
}

test "deleteTableColumn - delete first column" {
    const allocator = std.testing.allocator;

    // Create a test markdown file content with a table
    const test_content =
        \\| Name | Age | City |
        \\|------|-----|------|
        \\| Alice | 30 | NYC |
        \\| Bob | 25 | LA |
    ;

    // Write test file
    const test_file_path = "test_delete_first_column.md";
    try fs.writeFile(test_file_path, test_content);
    defer fs.deleteFile(test_file_path) catch {};

    // Create parameters JSON for deleting the Name column (index 0)
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("column_index", json.Value{ .integer = 0 });
    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute deleteTableColumn
    const result = try deleteTableColumn(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the result indicates success
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expect(std.mem.eql(u8, result.object.get("deleted_header").?.string, "Name"));
    try std.testing.expect(result.object.get("remaining_columns").?.integer == 2);

    // Verify the file content was updated correctly
    const updated_content = try fs.readFileAlloc(allocator, test_file_path, null);
    defer allocator.free(updated_content);

    // The Name column should be removed, Age and City should remain
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "| Age | City |") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "| 30 | NYC |") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "| 25 | LA |") != null);
    // Name column should be gone
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "Name") == null);
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "Alice") == null);
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "Bob") == null);
}

test "deleteTableColumn - error cases" {
    const allocator = std.testing.allocator;

    // Create a test markdown file content with a single column table
    const test_content =
        \\| Name |
        \\|------|
        \\| Alice |
    ;

    // Write test file
    const test_file_path = "test_delete_column_error.md";
    try fs.writeFile(test_file_path, test_content);
    defer fs.deleteFile(test_file_path) catch {};

    // Test case 1: Try to delete from single-column table (should fail)
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("column_index", json.Value{ .integer = 0 });
    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("backup_before_change", json.Value{ .bool = false });

    const error_result = deleteTableColumn(allocator, params, test_file_path);
    try std.testing.expectError(table.Error.InvalidColumnIndex, error_result);

    // Test case 2: Invalid column index (out of bounds)
    var params2 = json.ObjectMap.init(allocator);
    defer params2.deinit();

    try params2.put("column_index", json.Value{ .integer = 10 }); // Invalid index
    try params2.put("table_index", json.Value{ .integer = 0 });
    try params2.put("backup_before_change", json.Value{ .bool = false });

    const error_result2 = deleteTableColumn(allocator, params2, test_file_path);
    try std.testing.expectError(table.Error.InvalidColumnIndex, error_result2);

    // Test case 3: Missing column_index parameter
    var invalid_params = json.ObjectMap.init(allocator);
    defer invalid_params.deinit();
    try invalid_params.put("table_index", json.Value{ .integer = 0 });
    // Missing column_index parameter

    const error_result3 = deleteTableColumn(allocator, invalid_params, test_file_path);
    try std.testing.expectError(Error.InvalidParameters, error_result3);
}

test "formatTable - basic table formatting" {
    const allocator = std.testing.allocator;

    // Create a test file with an unformatted table
    const test_content =
        \\# Test Document
        \\
        \\This is a test document with an unformatted table:
        \\
        \\|Name|Age|City|
        \\|---|---|---|
        \\|John|25|New York|
        \\|Jane Smith|30|Los Angeles|
        \\|Bob|35|Chicago|
        \\
        \\End of document.
    ;

    const test_file_path = "/tmp/test_format_table.md";
    try std.fs.cwd().writeFile(test_file_path, test_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Set up parameters for formatTable
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute formatTable
    const result = try formatTable(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the operation succeeded
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expect(result.object.get("table_index").?.integer == 0);
    try std.testing.expect(result.object.get("headers_count").?.integer == 3);
    try std.testing.expect(result.object.get("rows_count").?.integer == 3);

    // Read the formatted file content
    const formatted_content = try std.fs.cwd().readFileAlloc(allocator, test_file_path, 1024 * 1024);
    defer allocator.free(formatted_content);

    // Verify the table has been formatted with proper alignment
    // The formatted table should have consistent column widths
    try std.testing.expect(std.mem.indexOf(u8, formatted_content, "| Name      | Age | City        |") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted_content, "|-----------|-----|-------------|") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted_content, "| Jane Smith") != null);

    // Verify that non-table content is preserved
    try std.testing.expect(std.mem.indexOf(u8, formatted_content, "# Test Document") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted_content, "End of document.") != null);
}

test "formatTable - table not found error" {
    const allocator = std.testing.allocator;

    // Create a test file without any tables
    const test_content =
        \\# Test Document
        \\
        \\This document has no tables.
        \\
        \\Just some regular content.
    ;

    const test_file_path = "/tmp/test_format_table_no_table.md";
    try std.fs.cwd().writeFile(test_file_path, test_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Set up parameters for formatTable
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute formatTable - should fail
    const result = try formatTable(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the operation failed with appropriate error
    try std.testing.expect(result.object.get("success").?.bool == false);
    const error_msg = result.object.get("error").?.string;
    try std.testing.expect(std.mem.indexOf(u8, error_msg, "Table not found") != null);
}

test "wrapText - basic text wrapping" {
    const allocator = std.testing.allocator;

    // Create test content with long lines
    const test_content =
        \\# Test Document
        \\
        \\This is a very long line that should be wrapped when we apply text wrapping with a reasonable width setting.
        \\
        \\Another paragraph with some text that goes on for quite a while and should be wrapped appropriately.
        \\
        \\Short line.
        \\
    ;

    const test_file_path = "/tmp/test_wrap_text.md";
    try std.fs.cwd().writeFile(test_file_path, test_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Create parameters for wrapping at 40 characters
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("width", json.Value{ .integer = 40 });
    try params.put("selection_mode", json.Value{ .string = "all" });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute wrapText
    const result = try wrapText(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify success response
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expectEqualStrings("content_editor", result.object.get("tool").?.string);
    try std.testing.expectEqualStrings("wrap_text", result.object.get("command").?.string);
    try std.testing.expect(result.object.get("width").?.integer == 40);
    try std.testing.expectEqualStrings("all", result.object.get("selection_mode").?.string);
    try std.testing.expect(result.object.get("backup_created").?.bool == false);

    // Read and verify wrapped content
    const wrapped_content = try std.fs.cwd().readFileAlloc(allocator, test_file_path, 1024 * 1024);
    defer allocator.free(wrapped_content);

    // Verify that long lines are wrapped
    var lines = std.mem.splitScalar(u8, wrapped_content, '\n');
    while (lines.next()) |line| {
        if (line.len > 40) {
            // Allow some tolerance for word boundaries
            try std.testing.expect(line.len <= 45); // Some flexibility for word wrapping
        }
    }

    // Verify content structure is preserved
    try std.testing.expect(std.mem.indexOf(u8, wrapped_content, "# Test Document") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrapped_content, "This is a very long line") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrapped_content, "Short line.") != null);
}

test "wrapText - error cases" {
    const allocator = std.testing.allocator;

    const test_content = "Some test content here.";
    const test_file_path = "/tmp/test_wrap_text_errors.md";
    try std.fs.cwd().writeFile(test_file_path, test_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Test invalid width (zero)
    {
        var params = json.ObjectMap.init(allocator);
        defer params.deinit();

        try params.put("width", json.Value{ .integer = 0 });
        try params.put("selection_mode", json.Value{ .string = "all" });

        const result = wrapText(allocator, params, test_file_path);
        try std.testing.expectError(Error.InvalidParameters, result);
    }

    // Test invalid width (too large)
    {
        var params = json.ObjectMap.init(allocator);
        defer params.deinit();

        try params.put("width", json.Value{ .integer = 2000 });
        try params.put("selection_mode", json.Value{ .string = "all" });

        const result = wrapText(allocator, params, test_file_path);
        try std.testing.expectError(Error.InvalidParameters, result);
    }

    // Test missing width parameter
    {
        var params = json.ObjectMap.init(allocator);
        defer params.deinit();

        try params.put("selection_mode", json.Value{ .string = "all" });

        const result = wrapText(allocator, params, test_file_path);
        try std.testing.expectError(Error.InvalidParameters, result);
    }

    // Test invalid selection mode
    {
        var params = json.ObjectMap.init(allocator);
        defer params.deinit();

        try params.put("width", json.Value{ .integer = 50 });
        try params.put("selection_mode", json.Value{ .string = "invalid_mode" });

        const result = wrapText(allocator, params, test_file_path);
        try std.testing.expectError(Error.InvalidParameters, result);
    }
}

test "extractSection - successful section extraction without removal" {
    const allocator = std.testing.allocator;

    // Create test content with multiple sections
    const test_content =
        \\# Introduction
        \\This is the introduction section.
        \\Some content here.
        \\
        \\## Getting Started
        \\This section explains how to get started.
        \\Step 1: Do this.
        \\Step 2: Do that.
        \\
        \\### Prerequisites
        \\You need these things first.
        \\
        \\## Advanced Usage
        \\Advanced features go here.
        \\Complex examples.
        \\
        \\# Conclusion
        \\Final thoughts.
        \\
    ;

    // Write test file
    const test_file_path = "test_extract_section.md";
    const output_file_path = "extracted_section.md";
    try fs.writeFile(test_file_path, test_content);
    defer fs.deleteFile(test_file_path) catch {};
    defer fs.deleteFile(output_file_path) catch {};

    // Create parameters JSON for extracting a section
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("heading_text", json.Value{ .string = "Getting Started" });
    try params.put("output_file", json.Value{ .string = output_file_path });
    try params.put("remove_from_source", json.Value{ .bool = false });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute extractSection
    const result = try extractSection(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the result indicates success
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expectEqualStrings("extract_section", result.object.get("command").?.string);
    try std.testing.expectEqualStrings("Getting Started", result.object.get("heading").?.string);
    try std.testing.expectEqualStrings(output_file_path, result.object.get("output_file").?.string);
    try std.testing.expect(result.object.get("removed_from_source").?.bool == false);
    try std.testing.expect(result.object.get("lines_extracted").?.integer > 0);

    // Read the extracted file and verify the content
    const extracted_content = try fs.readFileAlloc(allocator, output_file_path, null);
    defer allocator.free(extracted_content);

    // Should contain the section heading and content
    try std.testing.expect(std.mem.indexOf(u8, extracted_content, "## Getting Started") != null);
    try std.testing.expect(std.mem.indexOf(u8, extracted_content, "This section explains how to get started.") != null);
    try std.testing.expect(std.mem.indexOf(u8, extracted_content, "### Prerequisites") != null);
    // Should NOT contain content from other sections
    try std.testing.expect(std.mem.indexOf(u8, extracted_content, "# Introduction") == null);
    try std.testing.expect(std.mem.indexOf(u8, extracted_content, "## Advanced Usage") == null);

    // Verify original file still contains all content (since remove_from_source is false)
    const original_content = try fs.readFileAlloc(allocator, test_file_path, null);
    defer allocator.free(original_content);
    try std.testing.expect(std.mem.indexOf(u8, original_content, "## Getting Started") != null);
    try std.testing.expect(std.mem.indexOf(u8, original_content, "# Introduction") != null);
}

test "extractSection - successful section extraction with removal" {
    const allocator = std.testing.allocator;

    // Create test content with multiple sections
    const test_content =
        \\# Introduction
        \\This is the introduction section.
        \\
        \\## Section to Remove
        \\This section will be removed.
        \\Some content here.
        \\
        \\## Remaining Section
        \\This section should remain.
        \\
    ;

    // Write test file
    const test_file_path = "test_extract_remove.md";
    const output_file_path = "extracted_remove.md";
    try fs.writeFile(test_file_path, test_content);
    defer fs.deleteFile(test_file_path) catch {};
    defer fs.deleteFile(output_file_path) catch {};

    // Create parameters JSON for extracting and removing a section
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("heading_text", json.Value{ .string = "Section to Remove" });
    try params.put("output_file", json.Value{ .string = output_file_path });
    try params.put("remove_from_source", json.Value{ .bool = true });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute extractSection
    const result = try extractSection(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the result indicates success
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expect(result.object.get("removed_from_source").?.bool == true);

    // Read the extracted file and verify the content
    const extracted_content = try fs.readFileAlloc(allocator, output_file_path, null);
    defer allocator.free(extracted_content);

    // Should contain the extracted section
    try std.testing.expect(std.mem.indexOf(u8, extracted_content, "## Section to Remove") != null);
    try std.testing.expect(std.mem.indexOf(u8, extracted_content, "This section will be removed.") != null);

    // Verify original file no longer contains the removed section
    const remaining_content = try fs.readFileAlloc(allocator, test_file_path, null);
    defer allocator.free(remaining_content);
    try std.testing.expect(std.mem.indexOf(u8, remaining_content, "## Section to Remove") == null);
    try std.testing.expect(std.mem.indexOf(u8, remaining_content, "This section will be removed.") == null);
    // But should still contain other sections
    try std.testing.expect(std.mem.indexOf(u8, remaining_content, "# Introduction") != null);
    try std.testing.expect(std.mem.indexOf(u8, remaining_content, "## Remaining Section") != null);
}

test "extractSection - section not found error" {
    const allocator = std.testing.allocator;

    // Create test content
    const test_content =
        \\# Introduction
        \\This is the introduction section.
        \\
        \\## Existing Section
        \\This section exists.
        \\
    ;

    // Write test file
    const test_file_path = "test_extract_not_found.md";
    const output_file_path = "not_extracted.md";
    try fs.writeFile(test_file_path, test_content);
    defer fs.deleteFile(test_file_path) catch {};
    defer fs.deleteFile(output_file_path) catch {};

    // Create parameters JSON for extracting a non-existent section
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("heading_text", json.Value{ .string = "Non-existent Section" });
    try params.put("output_file", json.Value{ .string = output_file_path });
    try params.put("remove_from_source", json.Value{ .bool = false });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute extractSection
    const result = try extractSection(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the result indicates failure
    try std.testing.expect(result.object.get("success").?.bool == false);
    try std.testing.expectEqualStrings("Section not found", result.object.get("error").?.string);

    // Verify no output file was created
    const output_exists = fs.fileExists(output_file_path);
    try std.testing.expect(!output_exists);
}

test "splitDocument - successful document splitting" {
    const allocator = std.testing.allocator;

    // Create test content with multiple sections at different levels
    const test_content =
        \\# Introduction
        \\This is the introduction to our document.
        \\Some introductory content here.
        \\
        \\## Background
        \\Important background information.
        \\
        \\# Getting Started
        \\This section covers getting started.
        \\Basic setup instructions.
        \\
        \\## Installation
        \\How to install the software.
        \\
        \\## Configuration
        \\Configuration details here.
        \\
        \\# Advanced Topics
        \\Advanced usage patterns.
        \\Complex scenarios and solutions.
        \\
        \\# Conclusion
        \\Final thoughts and summary.
        \\
    ;

    // Write test file
    const test_file_path = "test_split_document.md";
    try fs.writeFile(test_file_path, test_content);
    defer fs.deleteFile(test_file_path) catch {};

    // Clean up output directory at start and end
    const output_dir = "test_split_output";
    std.fs.cwd().deleteTree(output_dir) catch {};
    defer std.fs.cwd().deleteTree(output_dir) catch {};

    // Create parameters JSON for splitting at level 1
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("split_level", json.Value{ .integer = 1 });
    try params.put("output_directory", json.Value{ .string = output_dir });
    try params.put("preserve_structure", json.Value{ .bool = true });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute splitDocument
    const result = try splitDocument(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the result indicates success
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expectEqualStrings("split_document", result.object.get("command").?.string);
    try std.testing.expectEqualStrings(test_file_path, result.object.get("file").?.string);
    try std.testing.expectEqualStrings(output_dir, result.object.get("output_directory").?.string);
    try std.testing.expect(result.object.get("split_level").?.integer == 1);
    try std.testing.expect(result.object.get("sections_created").?.integer == 4); // Introduction, Getting Started, Advanced Topics, Conclusion
    try std.testing.expect(result.object.get("preserve_structure").?.bool == true);

    // Verify created files array
    const created_files = result.object.get("created_files").?.array;
    try std.testing.expect(created_files.items.len == 4);

    // Check that all expected files were created
    const expected_files = [_][]const u8{
        "test_split_output/01_Introduction.md",
        "test_split_output/02_Getting_Started.md",
        "test_split_output/03_Advanced_Topics.md",
        "test_split_output/04_Conclusion.md",
    };

    for (expected_files) |expected_file| {
        try std.testing.expect(fs.fileExists(expected_file));

        // Read and verify content
        const file_content = try fs.readFileAlloc(allocator, expected_file, null);
        defer allocator.free(file_content);

        // Each file should start with the appropriate heading
        if (std.mem.indexOf(u8, expected_file, "Introduction")) |_| {
            try std.testing.expect(std.mem.indexOf(u8, file_content, "# Introduction") != null);
            try std.testing.expect(std.mem.indexOf(u8, file_content, "This is the introduction") != null);
            try std.testing.expect(std.mem.indexOf(u8, file_content, "## Background") != null);
        } else if (std.mem.indexOf(u8, expected_file, "Getting_Started")) |_| {
            try std.testing.expect(std.mem.indexOf(u8, file_content, "# Getting Started") != null);
            try std.testing.expect(std.mem.indexOf(u8, file_content, "## Installation") != null);
            try std.testing.expect(std.mem.indexOf(u8, file_content, "## Configuration") != null);
        }
    }
}

test "splitDocument - no sections at specified level" {
    const allocator = std.testing.allocator;

    // Create test content with only level 2 headers
    const test_content =
        \\## Section One
        \\Content for section one.
        \\
        \\## Section Two
        \\Content for section two.
        \\
    ;

    // Write test file
    const test_file_path = "test_split_no_sections.md";
    try fs.writeFile(test_file_path, test_content);
    defer fs.deleteFile(test_file_path) catch {};

    // Clean up output directory
    const output_dir = "test_no_sections_output";
    std.fs.cwd().deleteTree(output_dir) catch {};
    defer std.fs.cwd().deleteTree(output_dir) catch {};

    // Create parameters JSON for splitting at level 1 (no level 1 headers exist)
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("split_level", json.Value{ .integer = 1 });
    try params.put("output_directory", json.Value{ .string = output_dir });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute splitDocument
    const result = try splitDocument(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the result indicates failure due to no sections found
    try std.testing.expect(result.object.get("success").?.bool == false);
    try std.testing.expectEqualStrings("split_document", result.object.get("command").?.string);
    try std.testing.expectEqualStrings("No sections found at specified level", result.object.get("error").?.string);
}

test "reorderTableColumn - move column from start to end" {
    const allocator = std.testing.allocator;

    // Create a test file with a table
    const test_content =
        \\# Test Document
        \\
        \\This is a test document with a table:
        \\
        \\| Name | Age | City | Status |
        \\|------|-----|------|--------|
        \\| John | 25 | NYC | Active |
        \\| Jane | 30 | LA | Inactive |
        \\| Bob | 35 | Chicago | Active |
        \\
        \\End of document.
    ;

    const test_file_path = "/tmp/test_reorder_table_column.md";
    try std.fs.cwd().writeFile(test_file_path, test_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Set up parameters for reordering: move column 0 (Name) to position 3 (end)
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("from_index", json.Value{ .integer = 0 });
    try params.put("to_index", json.Value{ .integer = 3 });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute reorderTableColumn
    const result = try reorderTableColumn(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the operation succeeded
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expectEqualStrings("reorder_table_column", result.object.get("command").?.string);
    try std.testing.expectEqual(@as(i64, 0), result.object.get("from_index").?.integer);
    try std.testing.expectEqual(@as(i64, 3), result.object.get("to_index").?.integer);
    try std.testing.expectEqualStrings("Name", result.object.get("moved_header").?.string);

    // Verify the file was modified correctly
    const updated_content = try std.fs.cwd().readFileAlloc(allocator, test_file_path, 1024 * 1024);
    defer allocator.free(updated_content);

    // The Name column should now be at the end
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "| Age | City | Status | Name |") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "| 25 | NYC | Active | John |") != null);
}

test "reorderTableColumn - move column from end to start" {
    const allocator = std.testing.allocator;

    // Create a test file with a table
    const test_content =
        \\# Test Document
        \\
        \\| Age | City | Status | Name |
        \\|-----|------|--------|----- |
        \\| 25 | NYC | Active | John |
        \\| 30 | LA | Inactive | Jane |
        \\| 35 | Chicago | Active | Bob |
        \\
        \\End of document.
    ;

    const test_file_path = "/tmp/test_reorder_table_column2.md";
    try std.fs.cwd().writeFile(test_file_path, test_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Set up parameters for reordering: move column 3 (Name) to position 0 (start)
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("from_index", json.Value{ .integer = 3 });
    try params.put("to_index", json.Value{ .integer = 0 });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute reorderTableColumn
    const result = try reorderTableColumn(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the operation succeeded
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expectEqualStrings("reorder_table_column", result.object.get("command").?.string);
    try std.testing.expectEqual(@as(i64, 3), result.object.get("from_index").?.integer);
    try std.testing.expectEqual(@as(i64, 0), result.object.get("to_index").?.integer);
    try std.testing.expectEqualStrings("Name", result.object.get("moved_header").?.string);

    // Verify the file was modified correctly
    const updated_content = try std.fs.cwd().readFileAlloc(allocator, test_file_path, 1024 * 1024);
    defer allocator.free(updated_content);

    // The Name column should now be at the start
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "| Name | Age | City | Status |") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "| John | 25 | NYC | Active |") != null);
}

test "reorderTableColumn - move middle column" {
    const allocator = std.testing.allocator;

    // Create a test file with a table
    const test_content =
        \\# Test Document
        \\
        \\| Name | Age | City | Status |
        \\|------|-----|------|--------|
        \\| John | 25 | NYC | Active |
        \\| Jane | 30 | LA | Inactive |
        \\
        \\End of document.
    ;

    const test_file_path = "/tmp/test_reorder_table_column3.md";
    try std.fs.cwd().writeFile(test_file_path, test_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Set up parameters for reordering: move column 2 (City) to position 1
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("from_index", json.Value{ .integer = 2 });
    try params.put("to_index", json.Value{ .integer = 1 });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute reorderTableColumn
    const result = try reorderTableColumn(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the operation succeeded
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expectEqual(@as(i64, 2), result.object.get("from_index").?.integer);
    try std.testing.expectEqual(@as(i64, 1), result.object.get("to_index").?.integer);
    try std.testing.expectEqualStrings("City", result.object.get("moved_header").?.string);

    // Verify the file was modified correctly
    const updated_content = try std.fs.cwd().readFileAlloc(allocator, test_file_path, 1024 * 1024);
    defer allocator.free(updated_content);

    // The order should now be: Name, City, Age, Status
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "| Name | City | Age | Status |") != null);
    try std.testing.expect(std.mem.indexOf(u8, updated_content, "| John | NYC | 25 | Active |") != null);
}

test "reorderTableColumn - error cases" {
    const allocator = std.testing.allocator;

    // Create a test file with a table
    const test_content =
        \\# Test Document
        \\
        \\| Name | Age |
        \\|------|-----|
        \\| John | 25 |
        \\
        \\End of document.
    ;

    const test_file_path = "/tmp/test_reorder_error.md";
    try std.fs.cwd().writeFile(test_file_path, test_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Test case 1: Missing from_index parameter
    var params1 = json.ObjectMap.init(allocator);
    defer params1.deinit();
    try params1.put("table_index", json.Value{ .integer = 0 });
    try params1.put("to_index", json.Value{ .integer = 1 });

    const error_result1 = try reorderTableColumn(allocator, params1, test_file_path);
    defer {
        switch (error_result1) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    try std.testing.expect(error_result1.object.get("success").?.bool == false);
    try std.testing.expect(std.mem.indexOf(u8, error_result1.object.get("error").?.string, "Missing required parameter: from_index") != null);

    // Test case 2: Invalid from_index (out of range)
    var params2 = json.ObjectMap.init(allocator);
    defer params2.deinit();
    try params2.put("table_index", json.Value{ .integer = 0 });
    try params2.put("from_index", json.Value{ .integer = 5 }); // Only 2 columns exist
    try params2.put("to_index", json.Value{ .integer = 1 });

    const error_result2 = try reorderTableColumn(allocator, params2, test_file_path);
    defer {
        switch (error_result2) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    try std.testing.expect(error_result2.object.get("success").?.bool == false);
    try std.testing.expect(std.mem.indexOf(u8, error_result2.object.get("error").?.string, "Invalid from_index") != null);

    // Test case 3: Table not found
    var params3 = json.ObjectMap.init(allocator);
    defer params3.deinit();
    try params3.put("table_index", json.Value{ .integer = 5 }); // Only 1 table exists
    try params3.put("from_index", json.Value{ .integer = 0 });
    try params3.put("to_index", json.Value{ .integer = 1 });

    const error_result3 = try reorderTableColumn(allocator, params3, test_file_path);
    defer {
        switch (error_result3) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    try std.testing.expect(error_result3.object.get("success").?.bool == false);
    try std.testing.expect(std.mem.indexOf(u8, error_result3.object.get("error").?.string, "Table not found") != null);
}

test "sortTableColumn - sort string column ascending" {
    const allocator = std.testing.allocator;

    // Create a test file with a table containing string data
    const test_content =
        \\# Test Document
        \\
        \\| Name | Age | City |
        \\|------|-----|------|
        \\| John | 25 | NYC |
        \\| Alice | 30 | LA |
        \\| Bob | 35 | Chicago |
        \\| Charlie | 20 | Boston |
        \\
        \\End of document.
    ;

    const test_file_path = "/tmp/test_sort_table_column1.md";
    try std.fs.cwd().writeFile(test_file_path, test_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Set up parameters for sorting Name column (column 0) in ascending order
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("column_index", json.Value{ .integer = 0 });
    try params.put("sort_order", json.Value{ .string = "asc" });
    try params.put("sort_type", json.Value{ .string = "string" });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute sortTableColumn
    const result = try sortTableColumn(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify response
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expect(std.mem.eql(u8, result.object.get("sorted_column").?.string, "Name"));
    try std.testing.expect(std.mem.eql(u8, result.object.get("sort_order").?.string, "asc"));
    try std.testing.expect(result.object.get("rows_sorted").?.integer == 4);

    // Verify the file was sorted correctly (Alice, Bob, Charlie, John)
    const updated_content = try std.fs.cwd().readFileAlloc(allocator, test_file_path, 1024 * 1024);
    defer allocator.free(updated_content);

    // Check order: Alice should be first, John should be last
    const alice_pos = std.mem.indexOf(u8, updated_content, "| Alice | 30 | LA |");
    const bob_pos = std.mem.indexOf(u8, updated_content, "| Bob | 35 | Chicago |");
    const charlie_pos = std.mem.indexOf(u8, updated_content, "| Charlie | 20 | Boston |");
    const john_pos = std.mem.indexOf(u8, updated_content, "| John | 25 | NYC |");

    try std.testing.expect(alice_pos != null);
    try std.testing.expect(bob_pos != null);
    try std.testing.expect(charlie_pos != null);
    try std.testing.expect(john_pos != null);
    try std.testing.expect(alice_pos.? < bob_pos.?);
    try std.testing.expect(bob_pos.? < charlie_pos.?);
    try std.testing.expect(charlie_pos.? < john_pos.?);
}

test "sortTableColumn - sort numeric column descending" {
    const allocator = std.testing.allocator;

    // Create a test file with a table containing numeric data
    const test_content =
        \\# Test Document
        \\
        \\| Name | Age | Score |
        \\|------|-----|-------|
        \\| John | 25 | 85.5 |
        \\| Alice | 30 | 92.0 |
        \\| Bob | 35 | 78.2 |
        \\| Charlie | 20 | 95.8 |
        \\
        \\End of document.
    ;

    const test_file_path = "/tmp/test_sort_table_column2.md";
    try std.fs.cwd().writeFile(test_file_path, test_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Set up parameters for sorting Score column (column 2) in descending order
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("column_index", json.Value{ .integer = 2 });
    try params.put("sort_order", json.Value{ .string = "desc" });
    try params.put("sort_type", json.Value{ .string = "numeric" });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute sortTableColumn
    const result = try sortTableColumn(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify response
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expect(std.mem.eql(u8, result.object.get("sorted_column").?.string, "Score"));
    try std.testing.expect(std.mem.eql(u8, result.object.get("sort_order").?.string, "desc"));
    try std.testing.expect(result.object.get("rows_sorted").?.integer == 4);

    // Verify the file was sorted correctly by score descending (95.8, 92.0, 85.5, 78.2)
    const updated_content = try std.fs.cwd().readFileAlloc(allocator, test_file_path, 1024 * 1024);
    defer allocator.free(updated_content);

    // Check order: Charlie (95.8) should be first, Bob (78.2) should be last
    const charlie_pos = std.mem.indexOf(u8, updated_content, "| Charlie | 20 | 95.8 |");
    const alice_pos = std.mem.indexOf(u8, updated_content, "| Alice | 30 | 92.0 |");
    const john_pos = std.mem.indexOf(u8, updated_content, "| John | 25 | 85.5 |");
    const bob_pos = std.mem.indexOf(u8, updated_content, "| Bob | 35 | 78.2 |");

    try std.testing.expect(charlie_pos != null);
    try std.testing.expect(alice_pos != null);
    try std.testing.expect(john_pos != null);
    try std.testing.expect(bob_pos != null);
    try std.testing.expect(charlie_pos.? < alice_pos.?);
    try std.testing.expect(alice_pos.? < john_pos.?);
    try std.testing.expect(john_pos.? < bob_pos.?);
}

test "sortTableColumn - auto-detect sorting with mixed data" {
    const allocator = std.testing.allocator;

    // Create a test file with a table containing mostly numeric data (should auto-detect as numeric)
    const test_content =
        \\# Test Document
        \\
        \\| Item | Quantity | Price |
        \\|------|----------|-------|
        \\| A | 10 | 15.99 |
        \\| B | 25 | 8.50 |
        \\| C | 5 | 22.00 |
        \\| D | 100 | 1.99 |
        \\
        \\End of document.
    ;

    const test_file_path = "/tmp/test_sort_table_column3.md";
    try std.fs.cwd().writeFile(test_file_path, test_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Set up parameters for sorting Quantity column (column 1) with auto-detection
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("column_index", json.Value{ .integer = 1 });
    try params.put("sort_order", json.Value{ .string = "asc" });
    try params.put("sort_type", json.Value{ .string = "auto" });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute sortTableColumn
    const result = try sortTableColumn(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify response
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expect(std.mem.eql(u8, result.object.get("sorted_column").?.string, "Quantity"));
    try std.testing.expect(std.mem.eql(u8, result.object.get("sort_order").?.string, "asc"));
    try std.testing.expect(result.object.get("rows_sorted").?.integer == 4);

    // Verify the file was sorted correctly by quantity ascending (5, 10, 25, 100)
    const updated_content = try std.fs.cwd().readFileAlloc(allocator, test_file_path, 1024 * 1024);
    defer allocator.free(updated_content);

    // Check order: C(5), A(10), B(25), D(100)
    const c_pos = std.mem.indexOf(u8, updated_content, "| C | 5 | 22.00 |");
    const a_pos = std.mem.indexOf(u8, updated_content, "| A | 10 | 15.99 |");
    const b_pos = std.mem.indexOf(u8, updated_content, "| B | 25 | 8.50 |");
    const d_pos = std.mem.indexOf(u8, updated_content, "| D | 100 | 1.99 |");

    try std.testing.expect(c_pos != null);
    try std.testing.expect(a_pos != null);
    try std.testing.expect(b_pos != null);
    try std.testing.expect(d_pos != null);
    try std.testing.expect(c_pos.? < a_pos.?);
    try std.testing.expect(a_pos.? < b_pos.?);
    try std.testing.expect(b_pos.? < d_pos.?);
}

test "sortTableColumn - error cases" {
    const allocator = std.testing.allocator;

    // Create a test file with a simple table
    const test_content =
        \\# Test Document
        \\
        \\| Name | Age |
        \\|------|-----|
        \\| John | 25 |
        \\| Alice | 30 |
        \\
        \\End of document.
    ;

    const test_file_path = "/tmp/test_sort_table_column_errors.md";
    try std.fs.cwd().writeFile(test_file_path, test_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Test case 1: Missing column_index parameter
    var params1 = json.ObjectMap.init(allocator);
    defer params1.deinit();
    try params1.put("table_index", json.Value{ .integer = 0 });
    try params1.put("sort_order", json.Value{ .string = "asc" });

    const error_result1 = try sortTableColumn(allocator, params1, test_file_path);
    defer {
        switch (error_result1) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    try std.testing.expect(error_result1.object.get("success").?.bool == false);
    try std.testing.expect(std.mem.indexOf(u8, error_result1.object.get("error").?.string, "Missing required parameter: column_index") != null);

    // Test case 2: Invalid column_index (out of range)
    var params2 = json.ObjectMap.init(allocator);
    defer params2.deinit();
    try params2.put("table_index", json.Value{ .integer = 0 });
    try params2.put("column_index", json.Value{ .integer = 5 }); // Only 2 columns exist
    try params2.put("sort_order", json.Value{ .string = "asc" });

    const error_result2 = try sortTableColumn(allocator, params2, test_file_path);
    defer {
        switch (error_result2) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    try std.testing.expect(error_result2.object.get("success").?.bool == false);
    try std.testing.expect(std.mem.indexOf(u8, error_result2.object.get("error").?.string, "Invalid column_index") != null);

    // Test case 3: Table not found
    var params3 = json.ObjectMap.init(allocator);
    defer params3.deinit();
    try params3.put("table_index", json.Value{ .integer = 5 }); // Only 1 table exists
    try params3.put("column_index", json.Value{ .integer = 0 });
    try params3.put("sort_order", json.Value{ .string = "asc" });

    const error_result3 = try sortTableColumn(allocator, params3, test_file_path);
    defer {
        switch (error_result3) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    try std.testing.expect(error_result3.object.get("success").?.bool == false);
    try std.testing.expect(std.mem.indexOf(u8, error_result3.object.get("error").?.string, "Table not found") != null);
}

// CSV/TSV Import/Export Operations

fn importCSVTSV(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    // Parse required parameters
    const input_file = params.get("input_file") orelse return Error.InvalidParameters;
    const delimiter_type_param = params.get("delimiter_type") orelse json.Value{ .string = "csv" };
    const table_index = params.get("table_index") orelse json.Value{ .integer = 0 };
    const mode = params.get("mode") orelse json.Value{ .string = "replace" }; // "replace" or "append"
    const backup_before_change = params.get("backup_before_change") orelse json.Value{ .bool = true };

    // Validate input_file parameter
    const input_file_path = switch (input_file) {
        .string => |path| path,
        else => return Error.InvalidParameters,
    };

    // Parse delimiter type
    const delimiter_type_str = delimiter_type_param.string;
    const delimiter_type = std.meta.stringToEnum(table.DelimiterType, delimiter_type_str) orelse table.DelimiterType.csv;

    // Parse mode
    const import_mode = mode.string;
    if (!std.mem.eql(u8, import_mode, "replace") and !std.mem.eql(u8, import_mode, "append")) {
        return Error.InvalidParameters;
    }

    // Create backup if requested
    if (backup_before_change.bool) {
        try createBackup(allocator, file_path);
    }

    // Read CSV/TSV input file
    const csv_content = try fs.readFileAlloc(allocator, input_file_path, null);
    defer allocator.free(csv_content);

    // Parse CSV/TSV content into table structure
    var imported_table = try table.parseCSVTSV(allocator, csv_content, delimiter_type);
    defer imported_table.deinit(allocator);

    if (imported_table.headers.len == 0) {
        return Error.InvalidParameters; // Empty CSV/TSV file
    }

    // Read original markdown content
    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    var new_content: []u8 = undefined;
    defer allocator.free(new_content);

    if (std.mem.eql(u8, import_mode, "replace")) {
        // Replace mode: find target table and replace it, or add at end if not found
        const result = try replaceTableAtIndex(allocator, original_content, &imported_table, table_index.integer);
        new_content = result;
    } else {
        // Append mode: add table at the end of the document
        var content_list = std.ArrayList(u8).init(allocator);
        defer content_list.deinit();

        try content_list.appendSlice(original_content);

        // Add separator if content doesn't end with newline
        if (original_content.len > 0 and original_content[original_content.len - 1] != '\n') {
            try content_list.append('\n');
        }
        try content_list.append('\n');

        // Format and append the imported table
        const formatted_table = try table.formatTable(allocator, &imported_table);
        defer allocator.free(formatted_table);

        try content_list.appendSlice(formatted_table);
        new_content = try content_list.toOwnedSlice();
    }

    // Write the updated content
    try fs.writeFile(file_path, new_content);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "import_csv_tsv" });
    try result.put("file", json.Value{ .string = file_path });
    try result.put("input_file", json.Value{ .string = input_file_path });
    try result.put("delimiter_type", json.Value{ .string = @tagName(delimiter_type) });
    try result.put("mode", json.Value{ .string = import_mode });
    try result.put("table_index", json.Value{ .integer = table_index.integer });
    try result.put("headers_imported", json.Value{ .integer = @intCast(imported_table.headers.len) });
    try result.put("rows_imported", json.Value{ .integer = @intCast(imported_table.rows.len) });
    try result.put("backup_created", json.Value{ .bool = backup_before_change.bool });

    return json.Value{ .object = result };
}

fn exportCSVTSV(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    // Parse required parameters
    const output_file = params.get("output_file") orelse return Error.InvalidParameters;
    const delimiter_type_param = params.get("delimiter_type") orelse json.Value{ .string = "csv" };
    const table_index = params.get("table_index") orelse json.Value{ .integer = 0 };

    // Validate output_file parameter
    const output_file_path = switch (output_file) {
        .string => |path| path,
        else => return Error.InvalidParameters,
    };

    // Parse delimiter type
    const delimiter_type_str = delimiter_type_param.string;
    const delimiter_type = std.meta.stringToEnum(table.DelimiterType, delimiter_type_str) orelse table.DelimiterType.csv;

    // Read markdown content
    const original_content = try fs.readFileAlloc(allocator, file_path, null);
    defer allocator.free(original_content);

    // Find and parse the target table
    const target_table_opt = try findTableAtIndex(allocator, original_content, table_index.integer);
    if (target_table_opt == null) {
        return Error.InvalidParameters; // Table not found
    }

    var target_table = target_table_opt.?;
    defer target_table.deinit(allocator);

    // Format table as CSV/TSV
    const csv_content = try table.formatCSVTSV(allocator, &target_table, delimiter_type);
    defer allocator.free(csv_content);

    // Write CSV/TSV content to output file
    try fs.writeFile(output_file_path, csv_content);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "content_editor" });
    try result.put("command", json.Value{ .string = "export_csv_tsv" });
    try result.put("file_path", json.Value{ .string = file_path });
    try result.put("output_file", json.Value{ .string = output_file });

    return result;
}

/// Validate table structure and identify issues
fn validateTableCommand(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    // Parse parameters
    const table_index = if (params.get("table_index")) |val| blk: {
        if (val == .integer) break :blk @as(usize, @intCast(val.integer));
        return Error.InvalidInput;
    } else 0;

    // Parse validation configuration
    var validation_config = table.ValidationConfig{};

    if (params.get("check_column_consistency")) |val| {
        if (val == .bool) validation_config.check_column_consistency = val.bool;
    }
    if (params.get("check_empty_cells")) |val| {
        if (val == .bool) validation_config.check_empty_cells = val.bool;
    }
    if (params.get("check_alignment_format")) |val| {
        if (val == .bool) validation_config.check_alignment_format = val.bool;
    }
    if (params.get("check_separator_format")) |val| {
        if (val == .bool) validation_config.check_separator_format = val.bool;
    }
    if (params.get("allow_empty_table")) |val| {
        if (val == .bool) validation_config.allow_empty_table = val.bool;
    }
    if (params.get("max_cell_length")) |val| {
        if (val == .integer) validation_config.max_cell_length = @as(usize, @intCast(val.integer));
    }
    if (params.get("trim_whitespace")) |val| {
        if (val == .bool) validation_config.trim_whitespace = val.bool;
    }

    // Read the file
    const file_content = try fs.readFile(allocator, file_path);
    defer allocator.free(file_content);

    // Find and parse the target table
    const tables = try findTablesInContent(allocator, file_content);
    defer {
        for (tables) |*tbl| {
            tbl.deinit(allocator);
        }
        allocator.free(tables);
    }

    if (table_index >= tables.len) {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("error", json.Value{ .string = "Table index out of range" });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "validate_table" });
        try result.put("file", json.Value{ .string = file_path });
        return json.Value{ .object = result };
    }

    // Validate the table
    var validation_result = try table.validateTable(allocator, &tables[table_index], validation_config);
    defer validation_result.deinit(allocator);

    // Build response
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("is_valid", json.Value{ .bool = validation_result.is_valid });
    try result.put("table_index", json.Value{ .integer = @intCast(table_index) });
    try result.put("headers_count", json.Value{ .integer = @intCast(tables[table_index].headers.len) });
    try result.put("rows_count", json.Value{ .integer = @intCast(tables[table_index].rows.len) });

    // Add issues array
    var issues_array = json.Array.init(allocator);
    for (validation_result.issues) |issue| {
        var issue_obj = json.ObjectMap.init(allocator);
        try issue_obj.put("type", json.Value{ .string = @tagName(issue.issue_type) });
        try issue_obj.put("severity", json.Value{ .string = @tagName(issue.severity) });
        try issue_obj.put("message", json.Value{ .string = issue.message });

        if (issue.row_index) |row_idx| {
            try issue_obj.put("row_index", json.Value{ .integer = @intCast(row_idx) });
        }
        if (issue.column_index) |col_idx| {
            try issue_obj.put("column_index", json.Value{ .integer = @intCast(col_idx) });
        }
        if (issue.line_number) |line_num| {
            try issue_obj.put("line_number", json.Value{ .integer = @intCast(line_num) });
        }

        try issues_array.append(json.Value{ .object = issue_obj });
    }
    try result.put("issues", json.Value{ .array = issues_array });

    // Add suggestions array
    var suggestions_array = json.Array.init(allocator);
    for (validation_result.suggestions) |suggestion| {
        try suggestions_array.append(json.Value{ .string = suggestion });
    }
    try result.put("suggestions", json.Value{ .array = suggestions_array });

    try result.put("command", json.Value{ .string = "validate_table" });
    try result.put("file_path", json.Value{ .string = file_path });

    return json.Value{ .object = result };
}

/// Repair common table issues
fn repairTableCommand(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    // Parse parameters
    const table_index = if (params.get("table_index")) |val| blk: {
        if (val == .integer) break :blk @as(usize, @intCast(val.integer));
        return Error.InvalidInput;
    } else 0;

    const backup_before_change = if (params.get("backup_before_change")) |val| blk: {
        if (val == .bool) break :blk val.bool;
        break :blk true; // Default to true
    } else true;

    // Parse repair configuration
    var repair_config = table.RepairConfig{};

    if (params.get("fix_column_consistency")) |val| {
        if (val == .bool) repair_config.fix_column_consistency = val.bool;
    }
    if (params.get("trim_whitespace")) |val| {
        if (val == .bool) repair_config.trim_whitespace = val.bool;
    }
    if (params.get("fill_empty_cells")) |val| {
        if (val == .bool) repair_config.fill_empty_cells = val.bool;
    }
    if (params.get("empty_cell_placeholder")) |val| {
        if (val == .string) repair_config.empty_cell_placeholder = val.string;
    }
    if (params.get("normalize_alignments")) |val| {
        if (val == .bool) repair_config.normalize_alignments = val.bool;
    }
    if (params.get("remove_empty_rows")) |val| {
        if (val == .bool) repair_config.remove_empty_rows = val.bool;
    }

    // Backup file if requested
    var backup_path: ?[]const u8 = null;
    if (backup_before_change) {
        try createBackup(allocator, file_path);
        backup_path = "backup_created";
    }

    // Read the file
    const file_content = try fs.readFile(allocator, file_path);
    defer allocator.free(file_content);

    // Find and parse the target table
    const tables = try findTablesInContent(allocator, file_content);
    defer {
        for (tables) |*tbl| {
            tbl.deinit(allocator);
        }
        allocator.free(tables);
    }

    if (table_index >= tables.len) {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("error", json.Value{ .string = "Table index out of range" });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "repair_table" });
        try result.put("file", json.Value{ .string = file_path });
        return json.Value{ .object = result };
    }

    // Make a copy of the table for repair
    var table_to_repair = tables[table_index];

    // Repair the table
    const repairs_made = table.repairTable(allocator, &table_to_repair, repair_config) catch {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("error", json.Value{ .string = "Failed to repair table" });
        try result.put("tool", json.Value{ .string = "content_editor" });
        try result.put("command", json.Value{ .string = "repair_table" });
        try result.put("file", json.Value{ .string = file_path });
        return json.Value{ .object = result };
    };

    // Replace the table in content and write back to file
    const new_content = try replaceTableAtIndex(allocator, file_content, &table_to_repair, @intCast(table_index));
    defer allocator.free(new_content);

    try fs.writeFile(file_path, new_content);

    // Build response
    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("table_index", json.Value{ .integer = @intCast(table_index) });
    try result.put("repairs_made", json.Value{ .integer = @intCast(repairs_made) });
    try result.put("headers_count", json.Value{ .integer = @intCast(table_to_repair.headers.len) });
    try result.put("rows_count", json.Value{ .integer = @intCast(table_to_repair.rows.len) });

    if (backup_path) |bp| {
        try result.put("backup_created", json.Value{ .bool = true });
        try result.put("backup_path", json.Value{ .string = bp });
    } else {
        try result.put("backup_created", json.Value{ .bool = false });
    }

    try result.put("command", json.Value{ .string = "repair_table" });
    try result.put("file_path", json.Value{ .string = file_path });

    return json.Value{ .object = result };
}

// Helper function to replace a table at a specific index
fn replaceTableAtIndex(allocator: std.mem.Allocator, original_content: []const u8, new_table: *const table.Table, target_table_index: i64) ![]u8 {
    var lines = std.mem.splitSequence(u8, original_content, "\n");
    var content_before_table = std.ArrayList(u8).init(allocator);
    defer content_before_table.deinit();
    var content_after_table = std.ArrayList(u8).init(allocator);
    defer content_after_table.deinit();

    var in_table = false;
    var current_table_index: i64 = 0;
    var target_table_found = false;

    while (lines.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, " \t");

        if (trimmed_line.len > 0 and trimmed_line[0] == '|') {
            // This looks like a table line
            if (!in_table) {
                // Starting a new table
                in_table = true;
                if (current_table_index == target_table_index) {
                    target_table_found = true;
                }
            }

            if (current_table_index != target_table_index) {
                // Not our target table, preserve it
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
            // Skip lines for target table (they will be replaced)
        } else {
            // Not a table line
            if (in_table) {
                // We just finished a table
                in_table = false;
                current_table_index += 1;
            }

            if (target_table_found and current_table_index > target_table_index) {
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

    // Format the new table
    const formatted_table = try table.formatTable(allocator, new_table);
    defer allocator.free(formatted_table);

    // Combine all parts
    var result_content = std.ArrayList(u8).init(allocator);
    defer result_content.deinit();

    try result_content.appendSlice(content_before_table.items);

    if (!target_table_found) {
        // Table index not found, append the new table at the end
        if (content_before_table.items.len > 0 and
            content_before_table.items[content_before_table.items.len - 1] != '\n')
        {
            try result_content.append('\n');
        }
        try result_content.append('\n');
    }

    try result_content.appendSlice(formatted_table);

    if (content_after_table.items.len > 0) {
        try result_content.append('\n');
        try result_content.appendSlice(content_after_table.items);
    }

    // Remove trailing newline if original didn't have one
    if (result_content.items.len > 0 and
        !std.mem.endsWith(u8, original_content, "\n") and
        result_content.items[result_content.items.len - 1] == '\n')
    {
        result_content.items.len -= 1;
    }

    return result_content.toOwnedSlice();
}

// Helper function to find and parse all tables in content
fn findTablesInContent(allocator: std.mem.Allocator, content: []const u8) ![]table.Table {
    var lines = std.mem.splitSequence(u8, content, "\n");
    var table_lines = std.ArrayList([]const u8).init(allocator);
    defer table_lines.deinit();
    var tables = std.ArrayList(table.Table).init(allocator);

    var in_table = false;

    while (lines.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, " \t");

        if (trimmed_line.len > 0 and trimmed_line[0] == '|') {
            // This looks like a table line
            if (!in_table) {
                in_table = true;
                table_lines.clearRetainingCapacity();
            }
            try table_lines.append(line);
        } else if (in_table and trimmed_line.len == 0) {
            // Empty line - might be end of table or just spacing within table
            // Look ahead to see if next non-empty line is also a table line
            continue;
        } else if (in_table) {
            // Non-table line - end of current table
            if (table_lines.items.len > 1) {
                const table_content = try std.mem.join(allocator, "\n", table_lines.items);
                defer allocator.free(table_content);

                if (try table.parseTable(allocator, table_content)) |parsed_table| {
                    try tables.append(parsed_table);
                }
            }
            in_table = false;
            table_lines.clearRetainingCapacity();
        }
    }

    // Handle case where content ends with a table
    if (in_table and table_lines.items.len > 1) {
        const table_content = try std.mem.join(allocator, "\n", table_lines.items);
        defer allocator.free(table_content);

        if (try table.parseTable(allocator, table_content)) |parsed_table| {
            try tables.append(parsed_table);
        }
    }

    return tables.toOwnedSlice();
}

// Helper function to find and parse a table at a specific index
fn findTableAtIndex(allocator: std.mem.Allocator, content: []const u8, target_index: i64) !?table.Table {
    var lines = std.mem.splitSequence(u8, content, "\n");
    var table_lines = std.ArrayList([]const u8).init(allocator);
    defer table_lines.deinit();

    var in_table = false;
    var current_table_index: i64 = 0;
    var target_table_found = false;

    while (lines.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, " \t");

        if (trimmed_line.len > 0 and trimmed_line[0] == '|') {
            // This looks like a table line
            if (!in_table) {
                // Starting a new table
                in_table = true;
                if (current_table_index == target_index) {
                    target_table_found = true;
                }
            }

            if (current_table_index == target_index) {
                try table_lines.append(line);
            }
        } else {
            // Not a table line
            if (in_table) {
                // We just finished a table
                in_table = false;
                if (current_table_index == target_index) {
                    // We just finished processing our target table, stop here
                    break;
                }
                current_table_index += 1;
            }
        }
    }

    if (!target_table_found) {
        return null;
    }

    // Reconstruct table text from collected lines
    var table_text = std.ArrayList(u8).init(allocator);
    defer table_text.deinit();

    for (table_lines.items) |line| {
        try table_text.appendSlice(line);
        try table_text.append('\n');
    }

    return table.parseTable(allocator, table_text.items);
}

// CSV/TSV Import/Export Tests

test "importCSVTSV - CSV import in replace mode" {
    const allocator = std.testing.allocator;

    // Create test CSV file
    const csv_content = "Name,Age,City\nAlice,30,NYC\nBob,25,LA\n";
    const csv_file_path = "test_import.csv";
    try fs.writeFile(csv_file_path, csv_content);
    defer std.fs.cwd().deleteFile(csv_file_path) catch {};

    // Create test markdown file with an existing table
    const markdown_content =
        \\# Test Document
        \\
        \\| Product | Price |
        \\|---------|-------|
        \\| Apple   | $1.50 |
        \\| Orange  | $2.00 |
        \\
        \\Some content after.
    ;
    const test_file_path = "test_import.md";
    try fs.writeFile(test_file_path, markdown_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Create parameters for import
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("input_file", json.Value{ .string = csv_file_path });
    try params.put("delimiter_type", json.Value{ .string = "csv" });
    try params.put("table_index", json.Value{ .integer = 0 });
    try params.put("mode", json.Value{ .string = "replace" });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute import
    const result = try importCSVTSV(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the result
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expect(result.object.get("headers_imported").?.integer == 3);
    try std.testing.expect(result.object.get("rows_imported").?.integer == 2);

    // Read the modified file and verify the table was replaced
    const modified_content = try fs.readFileAlloc(allocator, test_file_path, null);
    defer allocator.free(modified_content);

    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Name | Age | City |") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Alice | 30 | NYC |") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Bob | 25 | LA |") != null);

    // Verify old table content was replaced
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "Apple") == null);
}

test "exportCSVTSV - CSV export" {
    const allocator = std.testing.allocator;

    // Create test markdown file with a table
    const test_content =
        \\# Test Document
        \\
        \\| Product | Price | Category |
        \\|---------|-------|----------|
        \\| Laptop  | $999  | Tech     |
        \\| Mouse   | $25   | Tech     |
        \\
        \\End of document.
    ;
    const test_file_path = "test_export.md";
    try fs.writeFile(test_file_path, test_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    const output_file_path = "exported_test.csv";
    defer std.fs.cwd().deleteFile(output_file_path) catch {};

    // Create parameters for export
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("output_file", json.Value{ .string = output_file_path });
    try params.put("delimiter_type", json.Value{ .string = "csv" });
    try params.put("table_index", json.Value{ .integer = 0 });

    // Execute export
    const result = try exportCSVTSV(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the result
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expect(result.object.get("headers_exported").?.integer == 3);
    try std.testing.expect(result.object.get("rows_exported").?.integer == 2);

    // Read the exported CSV file and verify content
    const csv_content = try fs.readFileAlloc(allocator, output_file_path, null);
    defer allocator.free(csv_content);

    try std.testing.expect(std.mem.indexOf(u8, csv_content, "Product,Price,Category") != null);
    try std.testing.expect(std.mem.indexOf(u8, csv_content, "Laptop,$999,Tech") != null);
    try std.testing.expect(std.mem.indexOf(u8, csv_content, "Mouse,$25,Tech") != null);
}

test "importCSVTSV - TSV import in append mode" {
    const allocator = std.testing.allocator;

    // Create test TSV file
    const tsv_content = "Item\tQuantity\tPrice\nKeyboard\t5\t75.50\nMouse\t10\t25.99\n";
    const tsv_file_path = "test_import.tsv";
    try fs.writeFile(tsv_file_path, tsv_content);
    defer std.fs.cwd().deleteFile(tsv_file_path) catch {};

    // Create test markdown file with existing content
    const markdown_content =
        \\# Inventory Report
        \\
        \\Current stock status:
        \\
    ;
    const test_file_path = "test_append.md";
    try fs.writeFile(test_file_path, markdown_content);
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Create parameters for import
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("input_file", json.Value{ .string = tsv_file_path });
    try params.put("delimiter_type", json.Value{ .string = "tsv" });
    try params.put("mode", json.Value{ .string = "append" });
    try params.put("backup_before_change", json.Value{ .bool = false });

    // Execute import
    const result = try importCSVTSV(allocator, params, test_file_path);
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify the result
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expect(result.object.get("headers_imported").?.integer == 3);
    try std.testing.expect(result.object.get("rows_imported").?.integer == 2);

    // Read the modified file and verify the table was appended
    const modified_content = try fs.readFileAlloc(allocator, test_file_path, null);
    defer allocator.free(modified_content);

    try std.testing.expect(std.mem.indexOf(u8, modified_content, "Current stock status:") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Item | Quantity | Price |") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Keyboard | 5 | 75.50 |") != null);
    try std.testing.expect(std.mem.indexOf(u8, modified_content, "| Mouse | 10 | 25.99 |") != null);
}

test "processTemplate - built-in template with variables" {
    const allocator = std.testing.allocator;

    // Create temporary output file
    const test_file_path = "test_template_output.md";
    defer fs.deleteFile(test_file_path) catch {};

    // Create test parameters with built-in blog_post template
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("command", json.Value{ .string = "process_template" });
    try params.put("file_path", json.Value{ .string = test_file_path });
    try params.put("template_name", json.Value{ .string = "blog_post" });

    // Create variables JSON
    var variables = json.ObjectMap.init(allocator);
    defer variables.deinit();

    try variables.put("title", json.Value{ .string = "My Amazing Blog Post" });
    try variables.put("author", json.Value{ .string = "John Doe" });
    try variables.put("date", json.Value{ .string = "2024-01-15" });
    try variables.put("excerpt", json.Value{ .string = "This is an amazing blog post about templates" });
    try variables.put("tags", json.Value{ .string = "\"template\", \"markdown\", \"automation\"" });
    try variables.put("content", json.Value{ .string = "This is the main content of the blog post. It demonstrates how template substitution works with multiple variables and complex markdown formatting." });

    try params.put("variables", json.Value{ .object = variables });

    // Execute the command
    const result = try execute(allocator, json.Value{ .object = params });
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify successful execution
    try std.testing.expect(result.object.get("success").?.bool == true);
    try std.testing.expect(std.mem.eql(u8, result.object.get("template_name").?.string, "blog_post"));
    try std.testing.expect(result.object.get("variables_count").?.integer == 6);
    try std.testing.expect(result.object.get("content_length").?.integer > 0);
    try std.testing.expectEqualStrings(test_file_path, result.object.get("output_file").?.string);

    // Verify the generated file exists and contains expected content
    try std.testing.expect(fs.fileExists(test_file_path));

    const generated_content = try fs.readFileAlloc(allocator, test_file_path, null);
    defer allocator.free(generated_content);

    // Check that variables were properly substituted
    try std.testing.expect(std.mem.indexOf(u8, generated_content, "title: \"My Amazing Blog Post\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_content, "author: \"John Doe\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_content, "date: 2024-01-15") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_content, "# My Amazing Blog Post") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_content, "*Published on 2024-01-15 by John Doe*") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_content, "This is the main content of the blog post") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_content, "*Tags: \"template\", \"markdown\", \"automation\"*") != null);
}

test "processTemplate - missing template error" {
    const allocator = std.testing.allocator;

    // Create test parameters with non-existent template
    var params = json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("command", json.Value{ .string = "process_template" });
    try params.put("file_path", json.Value{ .string = "test_output.md" });
    try params.put("template_name", json.Value{ .string = "nonexistent_template" });

    // Execute the command
    const result = try execute(allocator, json.Value{ .object = params });
    defer {
        switch (result) {
            .object => |obj| {
                var obj_copy = obj;
                obj_copy.deinit();
            },
            else => {},
        }
    }

    // Verify error response
    try std.testing.expect(result.object.get("success").?.bool == false);
    try std.testing.expect(std.mem.indexOf(u8, result.object.get("error").?.string, "Built-in template not found") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.object.get("error").?.string, "nonexistent_template") != null);
}

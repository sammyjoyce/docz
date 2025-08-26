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
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
}

fn deleteContent(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
}

fn moveSection(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
}

fn deleteSection(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
}

fn restructure(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
}

fn createTable(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
}

fn updateTableCell(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
}

fn addTableRow(allocator: std.mem.Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
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
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
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
    _ = allocator;
    _ = params;
    _ = file_path;
    return Error.OperationFailed; // Placeholder
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

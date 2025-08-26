const std = @import("std");
const json = std.json;
const fs = @import("../common/fs.zig");
const template = @import("../common/template.zig");
const meta = @import("../common/meta.zig");

pub const Error = fs.Error || template.Error || meta.Error || error{
    UnknownCommand,
    InvalidParameters,
    ConversionFailed,
    TemplateError,
};

pub const Command = enum {
    // Template operations
    create_from_template,
    list_templates,
    save_as_template,
    update_template,

    // Conversion operations
    to_html,
    to_pdf,
    to_docx,
    from_html,
    from_docx,
    to_latex,

    pub fn fromString(str: []const u8) ?Command {
        return std.meta.stringToEnum(Command, str);
    }
};

/// Main entry point for document transformation operations
pub fn execute(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    return executeInternal(allocator, params) catch |err| {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("error", json.Value{ .string = @errorName(err) });
        try result.put("tool", json.Value{ .string = "document_transformer" });
        return json.Value{ .object = result };
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    const params_obj = params.object;

    const command_str = params_obj.get("command").?.string;
    const command = Command.fromString(command_str) orelse return Error.UnknownCommand;

    return switch (command) {
        // Template operations
        .create_from_template => createFromTemplate(allocator, params_obj),
        .list_templates => listTemplates(allocator, params_obj),
        .save_as_template => saveAsTemplate(allocator, params_obj),
        .update_template => updateTemplate(allocator, params_obj),

        // Conversion operations
        .to_html => convertToHtml(allocator, params_obj),
        .to_pdf => convertToPdf(allocator, params_obj),
        .to_docx => convertToDocx(allocator, params_obj),
        .from_html => convertFromHtml(allocator, params_obj),
        .from_docx => convertFromDocx(allocator, params_obj),
        .to_latex => convertToLatex(allocator, params_obj),
    };
}

// Template Operations

fn createFromTemplate(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const template_options = params.get("template_options").?.object;
    const template_name = template_options.get("template_name").?.string;
    const output_path = template_options.get("output_path").?.string;

    // Get the template
    var template_obj = try template.getBuiltinTemplate(allocator, template_name);
    defer template_obj.deinit(allocator);

    // Parse template variables if provided
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

    if (template_options.get("template_variables")) |vars_json| {
        if (vars_json == .object) {
            var var_iterator = vars_json.object.iterator();
            while (var_iterator.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const value = try jsonToTemplateVariable(allocator, entry.value_ptr.*);
                try variables.put(key, value);
            }
        }
    }

    // Add default variables if not provided
    if (!variables.contains("date")) {
        const now = std.time.timestamp();
        const date_str = try std.fmt.allocPrint(allocator, "{}", .{now});
        try variables.put(try allocator.dupe(u8, "date"), template.TemplateVariable{ .string = date_str });
    }

    // Render the template
    const rendered = try template.renderTemplate(allocator, &template_obj, variables);
    defer allocator.free(rendered);

    // Write to output file
    try fs.writeFile(output_path, rendered);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "document_transformer" });
    try result.put("command", json.Value{ .string = "create_from_template" });
    try result.put("template", json.Value{ .string = template_name });
    try result.put("output_file", json.Value{ .string = output_path });
    try result.put("rendered_size", json.Value{ .integer = @intCast(rendered.len) });

    return json.Value{ .object = result };
}

fn listTemplates(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    _ = params;

    const template_names = try template.listBuiltinTemplates(allocator);
    defer {
        for (template_names) |name| allocator.free(name);
        allocator.free(template_names);
    }

    var templates_array = json.Array.init(allocator);
    for (template_names) |name| {
        try templates_array.append(json.Value{ .string = try allocator.dupe(u8, name) });
    }

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "document_transformer" });
    try result.put("command", json.Value{ .string = "list_templates" });
    try result.put("templates", json.Value{ .array = templates_array });

    return json.Value{ .object = result };
}

fn saveAsTemplate(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const template_options = params.get("template_options").?.object;
    const source_file = template_options.get("source_file").?.string;
    const template_path = template_options.get("template_path").?.string;

    // Read source file
    const content = try fs.readFileAlloc(allocator, source_file, null);
    defer allocator.free(content);

    // Create template object
    var template_obj = template.Template{
        .name = try allocator.dupe(u8, std.fs.path.stem(template_path)),
        .content = try allocator.dupe(u8, content),
        .variables = std.StringHashMap(template.TemplateVariable).init(allocator),
    };
    defer template_obj.deinit(allocator);

    // Save template to file
    try template.saveTemplate(&template_obj, template_path);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "document_transformer" });
    try result.put("command", json.Value{ .string = "save_as_template" });
    try result.put("source_file", json.Value{ .string = source_file });
    try result.put("template_path", json.Value{ .string = template_path });

    return json.Value{ .object = result };
}

fn updateTemplate(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    _ = allocator;
    _ = params;
    // Placeholder implementation
    return Error.ConversionFailed;
}

// Conversion Operations

fn convertToHtml(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const conversion_options = params.get("conversion_options").?.object;
    const input_path = conversion_options.get("input_path").?.string;
    const output_path = conversion_options.get("output_path").?.string;

    // Read markdown file
    const markdown_content = try fs.readFileAlloc(allocator, input_path, null);
    defer allocator.free(markdown_content);

    // Extract front matter and content
    const document_content = meta.extractContent(markdown_content);
    var metadata_opt = try meta.parseFrontMatter(allocator, markdown_content);
    defer if (metadata_opt) |*metadata| metadata.deinit(allocator);

    // Basic HTML conversion (this would be more sophisticated in a real implementation)
    var html_content = std.ArrayList(u8).init(allocator);
    defer html_content.deinit();

    // HTML header
    try html_content.appendSlice("<!DOCTYPE html>\n<html>\n<head>\n");
    try html_content.appendSlice("<meta charset=\"UTF-8\">\n");

    // Add title from metadata if available
    if (metadata_opt) |metadata| {
        if (metadata.get("title")) |title_value| {
            if (title_value.* == .string) {
                try html_content.appendSlice("<title>");
                try html_content.appendSlice(title_value.string);
                try html_content.appendSlice("</title>\n");
            }
        }
    }

    // Check for style options
    if (params.get("style_options")) |style_opts| {
        if (style_opts == .object) {
            if (style_opts.object.get("css_file")) |css_file| {
                try html_content.appendSlice("<link rel=\"stylesheet\" href=\"");
                try html_content.appendSlice(css_file.string);
                try html_content.appendSlice("\">\n");
            }
        }
    }

    try html_content.appendSlice("</head>\n<body>\n");

    // Convert markdown to HTML (simplified)
    const html_body = try convertMarkdownToHtml(allocator, document_content);
    defer allocator.free(html_body);

    try html_content.appendSlice(html_body);
    try html_content.appendSlice("\n</body>\n</html>\n");

    // Write to output file
    try fs.writeFile(output_path, html_content.items);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "document_transformer" });
    try result.put("command", json.Value{ .string = "to_html" });
    try result.put("input_file", json.Value{ .string = input_path });
    try result.put("output_file", json.Value{ .string = output_path });
    try result.put("output_size", json.Value{ .integer = @intCast(html_content.items.len) });

    return json.Value{ .object = result };
}

fn convertToPdf(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    // For now, return an indication that PDF conversion requires external tools
    const conversion_options = params.get("conversion_options").?.object;
    const input_path = conversion_options.get("input_path").?.string;
    const output_path = conversion_options.get("output_path").?.string;

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = false });
    try result.put("tool", json.Value{ .string = "document_transformer" });
    try result.put("command", json.Value{ .string = "to_pdf" });
    try result.put("input_file", json.Value{ .string = input_path });
    try result.put("output_file", json.Value{ .string = output_path });
    try result.put("message", json.Value{ .string = "PDF conversion requires external tools (pandoc, wkhtmltopdf, etc.)" });

    return json.Value{ .object = result };
}

// Placeholder implementations for remaining conversion functions
fn convertToDocx(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    _ = allocator;
    _ = params;
    return Error.ConversionFailed;
}

fn convertFromHtml(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    _ = allocator;
    _ = params;
    return Error.ConversionFailed;
}

fn convertFromDocx(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    _ = allocator;
    _ = params;
    return Error.ConversionFailed;
}

fn convertToLatex(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    _ = allocator;
    _ = params;
    return Error.ConversionFailed;
}

// Helper Functions

fn jsonToTemplateVariable(allocator: std.mem.Allocator, json_value: json.Value) !template.TemplateVariable {
    return switch (json_value) {
        .string => |s| template.TemplateVariable{ .string = try allocator.dupe(u8, s) },
        .integer => |i| template.TemplateVariable{ .integer = i },
        .float => |f| template.TemplateVariable{ .float = f },
        .bool => |b| template.TemplateVariable{ .boolean = b },
        else => template.TemplateVariable{ .string = try allocator.dupe(u8, "null") },
    };
}

fn convertMarkdownToHtml(allocator: std.mem.Allocator, markdown: []const u8) ![]u8 {
    var html = std.ArrayList(u8).init(allocator);
    var lines = std.mem.split(u8, markdown, "\n");

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (trimmed.len == 0) {
            try html.appendSlice("<p></p>\n");
            continue;
        }

        // Convert headings
        if (trimmed[0] == '#') {
            var level: usize = 0;
            for (trimmed) |char| {
                if (char == '#') {
                    level += 1;
                } else {
                    break;
                }
            }

            if (level <= 6) {
                const heading_text = std.mem.trim(u8, trimmed[level..], " \t");
                try html.appendSlice(try std.fmt.allocPrint(allocator, "<h{}>{s}</h{}>\n", .{ level, heading_text, level }));
                continue;
            }
        }

        // Convert paragraphs (default)
        try html.appendSlice("<p>");
        try html.appendSlice(trimmed);
        try html.appendSlice("</p>\n");
    }

    return html.toOwnedSlice();
}


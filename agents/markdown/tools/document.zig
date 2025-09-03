const std = @import("std");
const json = std.json;
const tools = @import("foundation").tools;
const fs = @import("../lib/fs.zig");
const template = @import("../lib/template.zig");
const meta = @import("../lib/meta.zig");

pub const Error = fs.Error || template.Error || meta.Error || error{
    UnknownCommand,
    InvalidParameters,
    ConversionFailed,
    TemplateError,
};

pub const Command = enum {
    // Template operations
    createFromTemplate,
    listTemplates,
    saveAsTemplate,
    updateTemplate,

    // Conversion operations
    toHtml,
    toPdf,
    toDocx,
    fromHtml,
    fromDocx,
    toLatex,

    pub fn parse(str: []const u8) ?Command {
        return std.meta.stringToEnum(Command, str);
    }
};

/// Main entry point for document operations
pub fn execute(allocator: std.mem.Allocator, params: json.Value) tools.ToolError!json.Value {
    return executeInternal(allocator, params) catch |err| {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("error", json.Value{ .string = @errorName(err) });
        try result.put("tool", json.Value{ .string = "document" });
        return json.Value{ .object = result };
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    const params_obj = params.object;

    const command_str = params_obj.get("command").?.string;
    const command = Command.parse(command_str) orelse return Error.UnknownCommand;

    return switch (command) {
        // Template operations
        .createFromTemplate => createFromTemplate(allocator, params_obj),
        .listTemplates => listTemplates(allocator, params_obj),
        .saveAsTemplate => saveAsTemplate(allocator, params_obj),
        .updateTemplate => updateTemplate(allocator, params_obj),

        // Conversion operations
        .toHtml => convertToHtml(allocator, params_obj),
        .toPdf => convertToPdf(allocator, params_obj),
        .toDocx => convertToDocx(allocator, params_obj),
        .fromHtml => convertFromHtml(allocator, params_obj),
        .fromDocx => convertFromDocx(allocator, params_obj),
        .toLatex => convertToLatex(allocator, params_obj),
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
    try result.put("tool", json.Value{ .string = "document" });
    try result.put("command", json.Value{ .string = "createFromTemplate" });
    try result.put("template", json.Value{ .string = template_name });
    try result.put("output_file", json.Value{ .string = output_path });
    try result.put("rendered_size", json.Value{ .integer = @as(i64, @intCast(@min(rendered.len, std.math.maxInt(i64)))) });

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
    try result.put("tool", json.Value{ .string = "document" });
    try result.put("command", json.Value{ .string = "listTemplates" });
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
    try result.put("tool", json.Value{ .string = "document" });
    try result.put("command", json.Value{ .string = "saveAsTemplate" });
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
    var html_content = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer html_content.deinit(allocator);

    // HTML header
    try html_content.appendSlice(allocator, "<!DOCTYPE html>\n<html>\n<head>\n");
    try html_content.appendSlice(allocator, "<meta charset=\"UTF-8\">\n");

    // Add title from metadata if available
    if (metadata_opt) |metadata| {
        if (metadata.get("title")) |title_value| {
            if (title_value.* == .string) {
                try html_content.appendSlice(allocator, "<title>");
                try html_content.appendSlice(allocator, title_value.string);
                try html_content.appendSlice(allocator, "</title>\n");
            }
        }
    }

    // Check for style options
    if (params.get("style_options")) |style_opts| {
        if (style_opts == .object) {
            if (style_opts.object.get("css_file")) |css_file| {
                try html_content.appendSlice(allocator, "<link rel=\"stylesheet\" href=\"");
                try html_content.appendSlice(allocator, css_file.string);
                try html_content.appendSlice(allocator, "\">\n");
            }
        }
    }

    try html_content.appendSlice(allocator, "</head>\n<body>\n");

    // Convert markdown to HTML (simplified)
    const html_body = try convertMarkdownToHtml(allocator, document_content);
    defer allocator.free(html_body);

    try html_content.appendSlice(allocator, html_body);
    try html_content.appendSlice(allocator, "\n</body>\n</html>\n");

    // Write to output file
    try fs.writeFile(output_path, html_content.items);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "document" });
    try result.put("command", json.Value{ .string = "toHtml" });
    try result.put("input_file", json.Value{ .string = input_path });
    try result.put("output_file", json.Value{ .string = output_path });
    try result.put("output_size", json.Value{ .integer = @as(i64, @intCast(@min(html_content.items.len, std.math.maxInt(i64)))) });

    return json.Value{ .object = result };
}

fn convertToPdf(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    // For now, return an indication that PDF conversion requires external tools
    const conversion_options = params.get("conversion_options").?.object;
    const input_path = conversion_options.get("input_path").?.string;
    const output_path = conversion_options.get("output_path").?.string;

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = false });
    try result.put("tool", json.Value{ .string = "document" });
    try result.put("command", json.Value{ .string = "toPdf" });
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
    var html = try std.ArrayList(u8).initCapacity(allocator, 1024);
    var lines = std.mem.splitScalar(u8, markdown, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (trimmed.len == 0) {
            try html.appendSlice(allocator, "<p></p>\n");
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
                try html.appendSlice(allocator, try std.fmt.allocPrint(allocator, "<h{}>{s}</h{}>\n", .{ level, heading_text, level }));
                continue;
            }
        }

        // Convert paragraphs (default)
        try html.appendSlice(allocator, "<p>");
        try html.appendSlice(allocator, trimmed);
        try html.appendSlice(allocator, "</p>\n");
    }

    return html.toOwnedSlice(allocator);
}

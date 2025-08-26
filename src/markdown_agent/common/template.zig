const std = @import("std");

pub const Error = error{
    TemplateNotFound,
    InvalidTemplate,
    OutOfMemory,
    MissingVariable,
};

pub const TemplateVariable = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
};

pub const Template = struct {
    name: []const u8,
    content: []const u8,
    variables: std.StringHashMap(TemplateVariable),

    pub fn deinit(self: *Template, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.content);

        var iterator = self.variables.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            switch (entry.value_ptr.*) {
                .string => |s| allocator.free(s),
                else => {},
            }
        }
        self.variables.deinit();
    }
};

/// Built-in template definitions
const BUILTIN_TEMPLATES = .{
    .article =
    \\---
    \\title: "{{title}}"
    \\author: "{{author}}"
    \\date: {{date}}
    \\tags: [{{tags}}]
    \\---
    \\
    \\# {{title}}
    \\
    \\## Introduction
    \\
    \\{{content}}
    \\
    \\## Conclusion
    \\
    \\{{conclusion}}
    ,

    .blog_post =
    \\---
    \\title: "{{title}}"
    \\date: {{date}}
    \\author: "{{author}}"
    \\excerpt: "{{excerpt}}"
    \\tags: [{{tags}}]
    \\---
    \\
    \\# {{title}}
    \\
    \\*Published on {{date}} by {{author}}*
    \\
    \\{{content}}
    \\
    \\---
    \\
    \\*Tags: {{tags}}*
    ,

    .tutorial =
    \\---
    \\title: "{{title}}"
    \\difficulty: "{{difficulty}}"
    \\duration: "{{duration}}"
    \\prerequisites: [{{prerequisites}}]
    \\---
    \\
    \\# {{title}}
    \\
    \\**Difficulty:** {{difficulty}}  
    \\**Duration:** {{duration}}  
    \\**Prerequisites:** {{prerequisites}}
    \\
    \\## Overview
    \\
    \\{{overview}}
    \\
    \\## Steps
    \\
    \\### Step 1: {{step1_title}}
    \\
    \\{{step1_content}}
    \\
    \\### Step 2: {{step2_title}}
    \\
    \\{{step2_content}}
    \\
    \\## Summary
    \\
    \\{{summary}}
    ,

    .documentation =
    \\---
    \\title: "{{title}}"
    \\version: "{{version}}"
    \\api_version: "{{api_version}}"
    \\---
    \\
    \\# {{title}}
    \\
    \\Version: {{version}}  
    \\API Version: {{api_version}}
    \\
    \\## Description
    \\
    \\{{description}}
    \\
    \\## Usage
    \\
    \\```{{language}}
    \\{{usage_example}}
    \\```
    \\
    \\## Parameters
    \\
    \\{{parameters}}
    \\
    \\## Examples
    \\
    \\{{examples}}
    \\
    \\## Notes
    \\
    \\{{notes}}
    ,

    .readme =
    \\# {{project_name}}
    \\
    \\{{description}}
    \\
    \\## Installation
    \\
    \\{{installation}}
    \\
    \\## Usage
    \\
    \\```{{language}}
    \\{{usage_example}}
    \\```
    \\
    \\## Features
    \\
    \\{{features}}
    \\
    \\## Contributing
    \\
    \\{{contributing}}
    \\
    \\## License
    \\
    \\{{license}}
    ,

    .specification =
    \\---
    \\title: "{{title}}"
    \\version: "{{version}}"
    \\status: "{{status}}"
    \\authors: [{{authors}}]
    \\---
    \\
    \\# {{title}}
    \\
    \\**Version:** {{version}}  
    \\**Status:** {{status}}  
    \\**Authors:** {{authors}}
    \\
    \\## Abstract
    \\
    \\{{abstract}}
    \\
    \\## Specification
    \\
    \\### Requirements
    \\
    \\{{requirements}}
    \\
    \\### Implementation
    \\
    \\{{implementation}}
    \\
    \\### Testing
    \\
    \\{{testing}}
    \\
    \\## References
    \\
    \\{{references}}
    ,
};

/// Get a built-in template by name
pub fn getBuiltinTemplate(allocator: std.mem.Allocator, name: []const u8) Error!Template {
    const template_content = inline for (std.meta.fields(@TypeOf(BUILTIN_TEMPLATES))) |field| {
        if (std.mem.eql(u8, name, field.name)) {
            break @field(BUILTIN_TEMPLATES, field.name);
        }
    } else return Error.TemplateNotFound;

    return Template{
        .name = try allocator.dupe(u8, name),
        .content = try allocator.dupe(u8, template_content),
        .variables = std.StringHashMap(TemplateVariable).init(allocator),
    };
}

/// Load template from file
pub fn loadTemplate(allocator: std.mem.Allocator, path: []const u8) Error!Template {
    const file_content = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return Error.TemplateNotFound,
        else => return Error.OutOfMemory,
    };

    const name = std.fs.path.stem(path);

    return Template{
        .name = try allocator.dupe(u8, name),
        .content = file_content,
        .variables = std.StringHashMap(TemplateVariable).init(allocator),
    };
}

/// Render template with variables
pub fn renderTemplate(allocator: std.mem.Allocator, template: *const Template, variables: std.StringHashMap(TemplateVariable)) Error![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var content = template.content;
    var pos: usize = 0;

    while (pos < content.len) {
        // Look for variable substitution {{variable_name}}
        const start_marker = std.mem.indexOf(u8, content[pos..], "{{");

        if (start_marker == null) {
            // No more variables, append rest of content
            try result.appendSlice(content[pos..]);
            break;
        }

        const marker_start = pos + start_marker.?;

        // Append content before marker
        try result.appendSlice(content[pos..marker_start]);

        // Find end marker
        const end_marker = std.mem.indexOf(u8, content[marker_start + 2 ..], "}}");
        if (end_marker == null) {
            // Malformed template, append rest as-is
            try result.appendSlice(content[marker_start..]);
            break;
        }

        const marker_end = marker_start + 2 + end_marker.? + 2;
        const var_name = std.mem.trim(u8, content[marker_start + 2 .. marker_end - 2], " \t");

        // Look up variable value
        if (variables.get(var_name)) |var_value| {
            const var_str = try variableToString(allocator, var_value);
            defer allocator.free(var_str);
            try result.appendSlice(var_str);
        } else if (template.variables.get(var_name)) |var_value| {
            const var_str = try variableToString(allocator, var_value);
            defer allocator.free(var_str);
            try result.appendSlice(var_str);
        } else {
            // Variable not found, keep placeholder or use default
            const placeholder = std.fmt.allocPrint(allocator, "[{s}]", .{var_name}) catch return Error.OutOfMemory;
            defer allocator.free(placeholder);
            try result.appendSlice(placeholder);
        }

        pos = marker_end;
    }

    return result.toOwnedSlice();
}

/// Convert template variable to string
fn variableToString(allocator: std.mem.Allocator, variable: TemplateVariable) Error![]u8 {
    return switch (variable) {
        .string => |s| allocator.dupe(u8, s),
        .integer => |i| std.fmt.allocPrint(allocator, "{}", .{i}) catch return Error.OutOfMemory,
        .float => |f| std.fmt.allocPrint(allocator, "{d}", .{f}) catch return Error.OutOfMemory,
        .boolean => |b| allocator.dupe(u8, if (b) "true" else "false"),
    };
}

/// Create variables map from key-value pairs
pub fn createVariables(allocator: std.mem.Allocator, vars: []const struct { key: []const u8, value: TemplateVariable }) Error!std.StringHashMap(TemplateVariable) {
    var variables = std.StringHashMap(TemplateVariable).init(allocator);

    for (vars) |var_pair| {
        const key = try allocator.dupe(u8, var_pair.key);
        const value = switch (var_pair.value) {
            .string => |s| TemplateVariable{ .string = try allocator.dupe(u8, s) },
            else => var_pair.value,
        };
        try variables.put(key, value);
    }

    return variables;
}

/// Get list of built-in template names
pub fn listBuiltinTemplates(allocator: std.mem.Allocator) Error![][]const u8 {
    var templates = std.ArrayList([]const u8).init(allocator);

    inline for (std.meta.fields(@TypeOf(BUILTIN_TEMPLATES))) |field| {
        const name = try allocator.dupe(u8, field.name);
        try templates.append(name);
    }

    return templates.toOwnedSlice();
}

/// Save template to file
pub fn saveTemplate(template: *const Template, path: []const u8) Error!void {
    std.fs.cwd().writeFile(path, template.content) catch return Error.OutOfMemory;
}

/// Extract variables from template content
pub fn extractVariables(allocator: std.mem.Allocator, content: []const u8) Error![][]const u8 {
    var variables = std.ArrayList([]const u8).init(allocator);
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var pos: usize = 0;
    while (pos < content.len) {
        const start_marker = std.mem.indexOf(u8, content[pos..], "{{");
        if (start_marker == null) break;

        const marker_start = pos + start_marker.?;
        const end_marker = std.mem.indexOf(u8, content[marker_start + 2 ..], "}}");
        if (end_marker == null) break;

        const marker_end = marker_start + 2 + end_marker.?;
        const var_name = std.mem.trim(u8, content[marker_start + 2 .. marker_end], " \t");

        if (!seen.contains(var_name) and var_name.len > 0) {
            const owned_name = try allocator.dupe(u8, var_name);
            try variables.append(owned_name);
            try seen.put(owned_name, {});
        }

        pos = marker_end + 2;
    }

    return variables.toOwnedSlice();
}

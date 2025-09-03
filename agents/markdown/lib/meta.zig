const std = @import("std");

pub const Error = error{
    InvalidMetadata,
    OutOfMemory,
    UnsupportedFormat,
};

pub const MetadataFormat = enum {
    yaml,
    toml,
    json,
};

pub const Metadata = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    array: []const Metadata,
    object: std.StringHashMap(Metadata),
};

pub const DocumentMetadata = struct {
    content: std.StringHashMap(Metadata),
    format: MetadataFormat,
    raw_content: []const u8,

    pub fn deinitMetadata(self: *DocumentMetadata, allocator: std.mem.Allocator) void {
        // Deep free all values
        var iterator = self.content.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            freeMetadata(entry.value_ptr.*, allocator);
        }
        self.content.deinit();
        allocator.free(self.raw_content);
    }

    pub fn getMetadata(self: *const DocumentMetadata, key: []const u8) ?*const Metadata {
        return self.content.getPtr(key);
    }

    pub fn setMetadata(self: *DocumentMetadata, allocator: std.mem.Allocator, key: []const u8, value: Metadata) Error!void {
        const owned_key = try allocator.dupe(u8, key);
        try self.content.put(owned_key, value);
    }
};

/// Parse front matter from markdown content
pub fn parseFrontMatter(allocator: std.mem.Allocator, content: []const u8) Error!?DocumentMetadata {
    const trimmed = std.mem.trim(u8, content, " \t\n\r");
    if (trimmed.len < 6) return null; // Minimum: "---\n\n---"

    // Check for YAML front matter
    if (std.mem.startsWith(u8, trimmed, "---\n")) {
        const end_marker = std.mem.indexOf(u8, trimmed[4..], "\n---\n");
        if (end_marker) |end_pos| {
            const yaml_content = trimmed[4 .. 4 + end_pos];
            return try parseYamlMetadata(allocator, yaml_content);
        }
    }

    // Check for TOML front matter
    if (std.mem.startsWith(u8, trimmed, "+ + +\n")) {
        const end_marker = std.mem.indexOf(u8, trimmed[4..], "\n+ + +\n");
        if (end_marker) |end_pos| {
            const toml_content = trimmed[4 .. 4 + end_pos];
            return try parseTomlMetadata(allocator, toml_content);
        }
    }

    return null;
}

/// Extract content without front matter
pub fn extractContent(content: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, content, " \t\n\r");

    // Check for YAML front matter
    if (std.mem.startsWith(u8, trimmed, "---\n")) {
        const end_marker = std.mem.indexOf(u8, trimmed[4..], "\n---\n");
        if (end_marker) |end_pos| {
            const after_yaml = 4 + end_pos + 5; // Skip past "\n---\n"
            return if (after_yaml < content.len) content[after_yaml..] else "";
        }
    }

    // Check for TOML front matter
    if (std.mem.startsWith(u8, trimmed, "+ + +\n")) {
        const end_marker = std.mem.indexOf(u8, trimmed[4..], "\n+ + +\n");
        if (end_marker) |end_pos| {
            const after_toml = 4 + end_pos + 5; // Skip past "\n+++\n"
            return if (after_toml < content.len) content[after_toml..] else "";
        }
    }

    return content;
}

/// Parse basic YAML-like metadata (simplified parser)
fn parseYamlMetadata(allocator: std.mem.Allocator, yamlContent: []const u8) Error!DocumentMetadata {
    var metadata = DocumentMetadata{
        .content = std.StringHashMap(Metadata).init(allocator),
        .format = .yaml,
        .raw_content = try allocator.dupe(u8, yamlContent),
    };

    var lines = std.mem.splitScalar(u8, yamlContent, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) continue;

        const colonPos = std.mem.indexOf(u8, trimmed, ":");
        if (colonPos) |pos| {
            const key = std.mem.trim(u8, trimmed[0..pos], " \t");
            const valueStr = std.mem.trim(u8, trimmed[pos + 1 ..], " \t");

            if (key.len > 0) {
                const value = try parseYamlValue(allocator, valueStr);
                try metadata.setMetadata(allocator, key, value);
            }
        }
    }

    return metadata;
}

/// Parse basic TOML-like metadata (simplified parser)
fn parseTomlMetadata(allocator: std.mem.Allocator, tomlContent: []const u8) Error!?DocumentMetadata {
    var metadata = DocumentMetadata{
        .content = std.StringHashMap(Metadata).init(allocator),
        .format = .toml,
        .raw_content = try allocator.dupe(u8, tomlContent),
    };

    var lines = std.mem.splitScalar(u8, tomlContent, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue; // Skip comments

        const equalsPos = std.mem.indexOf(u8, trimmed, "=");
        if (equalsPos) |pos| {
            const key = std.mem.trim(u8, trimmed[0..pos], " \t");
            const valueStr = std.mem.trim(u8, trimmed[pos + 1 ..], " \t");

            if (key.len > 0) {
                const value = try parseTomlValue(allocator, valueStr);
                try metadata.setMetadata(allocator, key, value);
            }
        }
    }

    return metadata;
}

/// Parse a YAML value (simplified)
fn parseYamlValue(allocator: std.mem.Allocator, valueStr: []const u8) Error!Metadata {
    if (valueStr.len == 0) {
        return Metadata{ .string = try allocator.dupe(u8, "") };
    }

    // Boolean values
    if (std.mem.eql(u8, valueStr, "true")) {
        return Metadata{ .boolean = true };
    }
    if (std.mem.eql(u8, valueStr, "false")) {
        return Metadata{ .boolean = false };
    }

    // Quoted string
    if (valueStr.len >= 2 and
        ((valueStr[0] == '"' and valueStr[valueStr.len - 1] == '"') or
            (valueStr[0] == '\'' and valueStr[valueStr.len - 1] == '\'')))
    {
        const unquoted = valueStr[1 .. valueStr.len - 1];
        return Metadata{ .string = try allocator.dupe(u8, unquoted) };
    }

    // Try to parse as integer
    if (std.fmt.parseInt(i64, valueStr, 10)) |intVal| {
        return Metadata{ .integer = intVal };
    } else |_| {}

    // Try to parse as float
    if (std.fmt.parseFloat(f64, valueStr)) |floatVal| {
        return Metadata{ .float = floatVal };
    } else |_| {}

    // Default to string
    return Metadata{ .string = try allocator.dupe(u8, valueStr) };
}

/// Parse a TOML value (simplified)
fn parseTomlValue(allocator: std.mem.Allocator, valueStr: []const u8) Error!Metadata {
    if (valueStr.len == 0) {
        return Metadata{ .string = try allocator.dupe(u8, "") };
    }

    // Boolean values
    if (std.mem.eql(u8, valueStr, "true")) {
        return Metadata{ .boolean = true };
    }
    if (std.mem.eql(u8, valueStr, "false")) {
        return Metadata{ .boolean = false };
    }

    // Quoted string
    if (valueStr.len >= 2 and valueStr[0] == '"' and valueStr[valueStr.len - 1] == '"') {
        const unquoted = valueStr[1 .. valueStr.len - 1];
        return Metadata{ .string = try allocator.dupe(u8, unquoted) };
    }

    // Try to parse as integer
    if (std.fmt.parseInt(i64, valueStr, 10)) |intVal| {
        return Metadata{ .integer = intVal };
    } else |_| {}

    // Try to parse as float
    if (std.fmt.parseFloat(f64, valueStr)) |floatVal| {
        return Metadata{ .float = floatVal };
    } else |_| {}

    // Default to string
    return Metadata{ .string = try allocator.dupe(u8, valueStr) };
}

/// Serialize metadata back to string format
pub fn serializeMetadata(allocator: std.mem.Allocator, metadata: *const DocumentMetadata) Error![]u8 {
    var result = std.array_list.Managed(u8).init(allocator);

    switch (metadata.format) {
        .yaml => {
            try result.appendSlice(allocator, "---\n");
            var iterator = metadata.content.iterator();
            while (iterator.next()) |entry| {
                try result.appendSlice(allocator, entry.key_ptr.*);
                try result.appendSlice(allocator, ": ");
                try serializeYamlValue(&result, entry.value_ptr.*, allocator);
                try result.append(allocator, '\n');
            }
            try result.appendSlice(allocator, "---\n");
        },
        .toml => {
            try result.appendSlice(allocator, "+ + +\n");
            var iterator = metadata.content.iterator();
            while (iterator.next()) |entry| {
                try result.appendSlice(allocator, entry.key_ptr.*);
                try result.appendSlice(allocator, " = ");
                try serializeTomlValue(&result, entry.value_ptr.*, allocator);
                try result.append(allocator, '\n');
            }
            try result.appendSlice(allocator, "+ + +\n");
        },
        .json => return Error.UnsupportedFormat, // JSON front matter not common
    }

    return result.toOwnedSlice();
}

/// Helper to serialize YAML values
fn serializeYamlValue(result: *std.array_list.Managed(u8), value: Metadata, allocator: std.mem.Allocator) Error!void {
    switch (value) {
        .string => |s| {
            // Quote strings that need quoting
            const needs_quotes = std.mem.indexOfAny(u8, s, " \t\n:#[]{}") != null;
            if (needs_quotes) {
                try result.append(allocator, '"');
                try result.appendSlice(allocator, s);
                try result.append(allocator, '"');
            } else {
                try result.appendSlice(allocator, s);
            }
        },
        .integer => |i| {
            const str = std.fmt.allocPrint(allocator, "{}", .{i}) catch return Error.OutOfMemory;
            defer allocator.free(str);
            try result.appendSlice(allocator, str);
        },
        .float => |f| {
            const str = std.fmt.allocPrint(allocator, "{d}", .{f}) catch return Error.OutOfMemory;
            defer allocator.free(str);
            try result.appendSlice(allocator, str);
        },
        .boolean => |b| {
            try result.appendSlice(allocator, if (b) "true" else "false");
        },
        .array, .object => {
            // Complex types not supported in this simplified implementation
            try result.appendSlice(allocator, "null");
        },
    }
}

/// Helper to serialize TOML values
fn serializeTomlValue(result: *std.array_list.Managed(u8), value: Metadata, allocator: std.mem.Allocator) Error!void {
    switch (value) {
        .string => |s| {
            try result.append(allocator, '"');
            try result.appendSlice(allocator, s);
            try result.append(allocator, '"');
        },
        .integer => |i| {
            const str = std.fmt.allocPrint(allocator, "{}", .{i}) catch return Error.OutOfMemory;
            defer allocator.free(str);
            try result.appendSlice(allocator, str);
        },
        .float => |f| {
            const str = std.fmt.allocPrint(allocator, "{d}", .{f}) catch return Error.OutOfMemory;
            defer allocator.free(str);
            try result.appendSlice(allocator, str);
        },
        .boolean => |b| {
            try result.appendSlice(allocator, if (b) "true" else "false");
        },
        .array, .object => {
            // Complex types not supported in this simplified implementation
            try result.appendSlice(allocator, "\"\"");
        },
    }
}

/// Free a metadata value recursively
fn freeMetadata(value: Metadata, allocator: std.mem.Allocator) void {
    switch (value) {
        .string => |s| allocator.free(s),
        .array => |arr| {
            for (arr) |item| {
                freeMetadata(item, allocator);
            }
            allocator.free(arr);
        },
        .object => |obj| {
            var iterator = obj.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                freeMetadata(entry.value_ptr.*, allocator);
            }
            // Note: obj.deinit() should be called by the parent
        },
        .integer, .float, .boolean => {}, // No cleanup needed
    }
}

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

pub const MetadataValue = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    array: []const MetadataValue,
    object: std.StringHashMap(MetadataValue),
};

pub const DocumentMetadata = struct {
    content: std.StringHashMap(MetadataValue),
    format: MetadataFormat,
    raw_content: []const u8,

    pub fn deinit(self: *DocumentMetadata, allocator: std.mem.Allocator) void {
        // Deep free all values
        var iterator = self.content.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            freeMetadataValue(entry.value_ptr.*, allocator);
        }
        self.content.deinit();
        allocator.free(self.raw_content);
    }

    pub fn get(self: *const DocumentMetadata, key: []const u8) ?*const MetadataValue {
        return self.content.getPtr(key);
    }

    pub fn set(self: *DocumentMetadata, allocator: std.mem.Allocator, key: []const u8, value: MetadataValue) Error!void {
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
            return parseYamlMetadata(allocator, yaml_content);
        }
    }

    // Check for TOML front matter
    if (std.mem.startsWith(u8, trimmed, "+ + +\n")) {
        const end_marker = std.mem.indexOf(u8, trimmed[4..], "\n+ + +\n");
        if (end_marker) |end_pos| {
            const toml_content = trimmed[4 .. 4 + end_pos];
            return parseTomlMetadata(allocator, toml_content);
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
fn parseYamlMetadata(allocator: std.mem.Allocator, yaml_content: []const u8) Error!DocumentMetadata {
    var metadata = DocumentMetadata{
        .content = std.StringHashMap(MetadataValue).init(allocator),
        .format = .yaml,
        .raw_content = try allocator.dupe(u8, yaml_content),
    };

    var lines = std.mem.splitScalar(u8, yaml_content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) continue;

        const colon_pos = std.mem.indexOf(u8, trimmed, ":");
        if (colon_pos) |pos| {
            const key = std.mem.trim(u8, trimmed[0..pos], " \t");
            const value_str = std.mem.trim(u8, trimmed[pos + 1 ..], " \t");

            if (key.len > 0) {
                const value = try parseYamlValue(allocator, value_str);
                try metadata.set(allocator, key, value);
            }
        }
    }

    return metadata;
}

/// Parse basic TOML-like metadata (simplified parser)
fn parseTomlMetadata(allocator: std.mem.Allocator, toml_content: []const u8) Error!DocumentMetadata {
    var metadata = DocumentMetadata{
        .content = std.StringHashMap(MetadataValue).init(allocator),
        .format = .toml,
        .raw_content = try allocator.dupe(u8, toml_content),
    };

    var lines = std.mem.splitScalar(u8, toml_content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue; // Skip comments

        const equals_pos = std.mem.indexOf(u8, trimmed, "=");
        if (equals_pos) |pos| {
            const key = std.mem.trim(u8, trimmed[0..pos], " \t");
            const value_str = std.mem.trim(u8, trimmed[pos + 1 ..], " \t");

            if (key.len > 0) {
                const value = try parseTomlValue(allocator, value_str);
                try metadata.set(allocator, key, value);
            }
        }
    }

    return metadata;
}

/// Parse a YAML value (simplified)
fn parseYamlValue(allocator: std.mem.Allocator, value_str: []const u8) Error!MetadataValue {
    if (value_str.len == 0) {
        return MetadataValue{ .string = try allocator.dupe(u8, "") };
    }

    // Boolean values
    if (std.mem.eql(u8, value_str, "true")) {
        return MetadataValue{ .boolean = true };
    }
    if (std.mem.eql(u8, value_str, "false")) {
        return MetadataValue{ .boolean = false };
    }

    // Quoted string
    if (value_str.len >= 2 and
        ((value_str[0] == '"' and value_str[value_str.len - 1] == '"') or
            (value_str[0] == '\'' and value_str[value_str.len - 1] == '\'')))
    {
        const unquoted = value_str[1 .. value_str.len - 1];
        return MetadataValue{ .string = try allocator.dupe(u8, unquoted) };
    }

    // Try to parse as integer
    if (std.fmt.parseInt(i64, value_str, 10)) |int_val| {
        return MetadataValue{ .integer = int_val };
    } else |_| {}

    // Try to parse as float
    if (std.fmt.parseFloat(f64, value_str)) |float_val| {
        return MetadataValue{ .float = float_val };
    } else |_| {}

    // Default to string
    return MetadataValue{ .string = try allocator.dupe(u8, value_str) };
}

/// Parse a TOML value (simplified)
fn parseTomlValue(allocator: std.mem.Allocator, value_str: []const u8) Error!MetadataValue {
    if (value_str.len == 0) {
        return MetadataValue{ .string = try allocator.dupe(u8, "") };
    }

    // Boolean values
    if (std.mem.eql(u8, value_str, "true")) {
        return MetadataValue{ .boolean = true };
    }
    if (std.mem.eql(u8, value_str, "false")) {
        return MetadataValue{ .boolean = false };
    }

    // Quoted string
    if (value_str.len >= 2 and value_str[0] == '"' and value_str[value_str.len - 1] == '"') {
        const unquoted = value_str[1 .. value_str.len - 1];
        return MetadataValue{ .string = try allocator.dupe(u8, unquoted) };
    }

    // Try to parse as integer
    if (std.fmt.parseInt(i64, value_str, 10)) |int_val| {
        return MetadataValue{ .integer = int_val };
    } else |_| {}

    // Try to parse as float
    if (std.fmt.parseFloat(f64, value_str)) |float_val| {
        return MetadataValue{ .float = float_val };
    } else |_| {}

    // Default to string
    return MetadataValue{ .string = try allocator.dupe(u8, value_str) };
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
fn serializeYamlValue(result: *std.array_list.Managed(u8), value: MetadataValue, allocator: std.mem.Allocator) Error!void {
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
fn serializeTomlValue(result: *std.array_list.Managed(u8), value: MetadataValue, allocator: std.mem.Allocator) Error!void {
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
fn freeMetadataValue(value: MetadataValue, allocator: std.mem.Allocator) void {
    switch (value) {
        .string => |s| allocator.free(s),
        .array => |arr| {
            for (arr) |item| {
                freeMetadataValue(item, allocator);
            }
            allocator.free(arr);
        },
        .object => |obj| {
            var iterator = obj.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                freeMetadataValue(entry.value_ptr.*, allocator);
            }
            // Note: obj.deinit() should be called by the parent
        },
        .integer, .float, .boolean => {}, // No cleanup needed
    }
}

const std = @import("std");
const toolsMod = @import("foundation").tools;
const core_engine = @import("core_engine");

const DataSchemaRequest = struct {
    input: []const u8,
    format: ?[]const u8 = null,

    pub fn jsonFieldName(comptime field_name: []const u8) []const u8 {
        return field_name;
    }
};

const SchemaField = struct {
    name: []const u8,
    data_type: []const u8,
    required: bool,
    description: []const u8,
    constraints: []const u8,

    pub fn jsonFieldName(comptime field_name: []const u8) []const u8 {
        return field_name;
    }
};

const SchemaEntity = struct {
    name: []const u8,
    description: []const u8,
    fields: []SchemaField,
    relationships: [][]const u8,
    indexes: [][]const u8,
    examples: [][]const u8,

    pub fn jsonFieldName(comptime field_name: []const u8) []const u8 {
        return field_name;
    }
};

const DataSchemaResponse = struct {
    success: bool,
    tool: []const u8 = "data_schema",
    entities: []SchemaEntity = &.{},
    summary: []const u8 = "",
    format_detected: []const u8 = "",
    error_message: ?[]const u8 = null,

    pub fn jsonFieldName(comptime field_name: []const u8) []const u8 {
        return field_name;
    }
};

pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    return executeInternal(allocator, params) catch |err| {
        const ResponseMapper = toolsMod.JsonReflector.mapper(DataSchemaResponse);
        const response = DataSchemaResponse{
            .success = false,
            .error_message = @errorName(err),
        };
        return ResponseMapper.toJsonValue(allocator, response);
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: std.json.Value) !std.json.Value {
    const RequestMapper = toolsMod.JsonReflector.mapper(DataSchemaRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    // Analyze the input to detect format
    const input = request.value.input;
    const format_detected = detectSchemaFormat(input);

    // Parse schema based on detected format
    var entities = try std.ArrayList(SchemaEntity).initCapacity(allocator, 0);
    defer entities.deinit(allocator);

    if (std.mem.containsAtLeast(u8, input, 1, "CREATE TABLE")) {
        try parseSQL(allocator, &entities, input);
    } else if (std.mem.containsAtLeast(u8, input, 1, "type") and std.mem.containsAtLeast(u8, input, 1, "Query")) {
        try parseGraphQL(allocator, &entities, input);
    } else if (std.mem.containsAtLeast(u8, input, 1, "\"properties\"")) {
        try parseJSONSchema(allocator, &entities, input);
    } else if (std.mem.containsAtLeast(u8, input, 1, "class") and std.mem.containsAtLeast(u8, input, 1, "Model")) {
        try parseModel(allocator, &entities, input);
    } else {
        try parseGeneric(allocator, &entities, input);
    }

    const owned_entities = try entities.toOwnedSlice(allocator);
    const response = DataSchemaResponse{
        .success = true,
        .entities = owned_entities,
        .summary = try generateSummary(allocator, owned_entities),
        .format_detected = format_detected,
    };

    const ResponseMapper = toolsMod.JsonReflector.mapper(DataSchemaResponse);
    return ResponseMapper.toJsonValue(allocator, response);
}

fn detectSchemaFormat(input: []const u8) []const u8 {
    if (std.mem.containsAtLeast(u8, input, 1, "CREATE TABLE")) return "SQL";
    if (std.mem.containsAtLeast(u8, input, 1, "type") and std.mem.containsAtLeast(u8, input, 1, "Query")) return "GraphQL";
    if (std.mem.containsAtLeast(u8, input, 1, "\"properties\"")) return "JSON Schema";
    if (std.mem.containsAtLeast(u8, input, 1, "class") and std.mem.containsAtLeast(u8, input, 1, "Model")) return "ORM Model";
    if (std.mem.containsAtLeast(u8, input, 1, "interface") or std.mem.containsAtLeast(u8, input, 1, "type")) return "TypeScript";
    return "Generic";
}

fn parseSQL(allocator: std.mem.Allocator, entities: *std.ArrayList(SchemaEntity), input: []const u8) !void {
    var lines = std.mem.splitSequence(u8, input, "\n");
    var current_table: ?[]const u8 = null;
    var fields = try std.ArrayList(SchemaField).initCapacity(allocator, 0);
    defer fields.deinit(allocator);

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");

        if (std.mem.startsWith(u8, trimmed, "CREATE TABLE")) {
            if (current_table) |table_name| {
                try entities.append(allocator, .{
                    .name = table_name,
                    .description = try std.fmt.allocPrint(allocator, "Database table: {s}", .{table_name}),
                    .fields = try fields.toOwnedSlice(allocator),
                    .relationships = &.{},
                    .indexes = &.{},
                    .examples = &.{},
                });
                fields = try std.ArrayList(SchemaField).initCapacity(allocator, 0);
            }

            // Extract table name
            var parts = std.mem.splitSequence(u8, trimmed, " ");
            _ = parts.next(); // CREATE
            _ = parts.next(); // TABLE
            if (parts.next()) |table_part| {
                current_table = try allocator.dupe(u8, std.mem.trim(u8, table_part, " \t\r\n(`"));
            }
        } else if (current_table != null and trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, ")") and !std.mem.startsWith(u8, trimmed, "CREATE")) {
            if (std.mem.indexOf(u8, trimmed, " ")) |space_idx| {
                const field_name = try allocator.dupe(u8, std.mem.trim(u8, trimmed[0..space_idx], " \t\r\n,"));
                const rest = std.mem.trim(u8, trimmed[space_idx..], " \t\r\n,");

                var type_end: usize = rest.len;
                if (std.mem.indexOf(u8, rest, " ")) |next_space| {
                    type_end = next_space;
                }

                const data_type = try allocator.dupe(u8, rest[0..type_end]);
                const required = !std.mem.containsAtLeast(u8, rest, 1, "NULL");

                try fields.append(allocator, .{
                    .name = field_name,
                    .data_type = data_type,
                    .required = required,
                    .description = try std.fmt.allocPrint(allocator, "Column in {s} table", .{current_table.?}),
                    .constraints = if (std.mem.containsAtLeast(u8, rest, 1, "PRIMARY KEY")) "Primary Key" else "",
                });
            }
        }
    }

    // Add final table
    if (current_table) |table_name| {
        try entities.append(allocator, .{
            .name = table_name,
            .description = try std.fmt.allocPrint(allocator, "Database table: {s}", .{table_name}),
            .fields = try fields.toOwnedSlice(allocator),
            .relationships = &.{},
            .indexes = &.{},
            .examples = &.{},
        });
    }
}

fn parseGraphQL(allocator: std.mem.Allocator, entities: *std.ArrayList(SchemaEntity), input: []const u8) !void {
    var lines = std.mem.splitSequence(u8, input, "\n");
    var current_type: ?[]const u8 = null;
    var fields = try std.ArrayList(SchemaField).initCapacity(allocator, 0);
    defer fields.deinit(allocator);

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");

        if (std.mem.startsWith(u8, trimmed, "type ")) {
            if (current_type) |type_name| {
                try entities.append(allocator, .{
                    .name = type_name,
                    .description = try std.fmt.allocPrint(allocator, "GraphQL type: {s}", .{type_name}),
                    .fields = try fields.toOwnedSlice(allocator),
                    .relationships = &.{},
                    .indexes = &.{},
                    .examples = &.{},
                });
                fields = try std.ArrayList(SchemaField).initCapacity(allocator, 0);
            }

            // Extract type name
            var parts = std.mem.splitSequence(u8, trimmed, " ");
            _ = parts.next(); // type
            if (parts.next()) |type_part| {
                current_type = try allocator.dupe(u8, std.mem.trim(u8, type_part, " \t\r\n{"));
            }
        } else if (current_type != null) {
            if (std.mem.indexOf(u8, trimmed, ":")) |colon_idx| {
                const field_name = try allocator.dupe(u8, std.mem.trim(u8, trimmed[0..colon_idx], " \t\r\n"));
                const rest = std.mem.trim(u8, trimmed[colon_idx + 1 ..], " \t\r\n");

                const required = !std.mem.endsWith(u8, rest, "!");
                const data_type = try allocator.dupe(u8, std.mem.trim(u8, rest, " \t\r\n!"));

                try fields.append(allocator, .{
                    .name = field_name,
                    .data_type = data_type,
                    .required = required,
                    .description = try std.fmt.allocPrint(allocator, "Field in {s} type", .{current_type.?}),
                    .constraints = "",
                });
            }
        }
    }

    // Add final type
    if (current_type) |type_name| {
        try entities.append(allocator, .{
            .name = type_name,
            .description = try std.fmt.allocPrint(allocator, "GraphQL type: {s}", .{type_name}),
            .fields = try fields.toOwnedSlice(allocator),
            .relationships = &.{},
            .indexes = &.{},
            .examples = &.{},
        });
    }
}

fn parseJSONSchema(allocator: std.mem.Allocator, entities: *std.ArrayList(SchemaEntity), input: []const u8) !void {
    _ = input;
    // Simple JSON Schema parsing - in a real implementation would use full JSON parser
    try entities.append(allocator, .{
        .name = "JSONSchema",
        .description = "JSON Schema definition",
        .fields = &.{},
        .relationships = &.{},
        .indexes = &.{},
        .examples = &.{},
    });
}

fn parseModel(allocator: std.mem.Allocator, entities: *std.ArrayList(SchemaEntity), input: []const u8) !void {
    _ = input;
    // Simple ORM model parsing
    try entities.append(allocator, .{
        .name = "Model",
        .description = "ORM Model definition",
        .fields = &.{},
        .relationships = &.{},
        .indexes = &.{},
        .examples = &.{},
    });
}

fn parseGeneric(alloc: std.mem.Allocator, entities: *std.ArrayList(SchemaEntity), input: []const u8) !void {
    _ = input;
    // Generic parsing for unknown formats
    try entities.append(alloc, .{
        .name = "GenericSchema",
        .description = "Generic schema definition",
        .fields = &.{},
        .relationships = &.{},
        .indexes = &.{},
        .examples = &.{},
    });
}

fn generateSummary(allocator: std.mem.Allocator, entities: []const SchemaEntity) ![]const u8 {
    if (entities.len == 0) {
        return try allocator.dupe(u8, "No entities found in the schema.");
    }

    return try std.fmt.allocPrint(allocator, "Schema contains {d} entities: {s}", .{
        entities.len,
        if (entities.len > 0) entities[0].name else "none",
    });
}

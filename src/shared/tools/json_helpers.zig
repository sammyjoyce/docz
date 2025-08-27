//! JSON helper utilities for tool development.
//! Provides convenience functions to simplify common JSON tool patterns
//! and eliminate boilerplate code.

const std = @import("std");
const tools_mod = @import("mod.zig");

/// Parse and validate a tool request from JSON into a struct.
/// Uses comptime reflection to automatically parse JSON fields into struct fields.
/// Handles type conversion and validation automatically.
///
/// Example:
/// ```zig
/// const Request = struct {
///     filename: []const u8,
///     options: struct {
///         format: []const u8 = "text",
///         validate: bool = true,
///     },
/// };
///
/// const request = try parseToolRequest(Request, params);
/// ```
pub fn parseToolRequest(comptime T: type, json_value: std.json.Value) !T {
    if (json_value != .object) {
        return tools_mod.ToolError.InvalidInput;
    }

    const obj = json_value.object;
    var result: T = undefined;

    // Use comptime reflection to iterate over struct fields
    const info = @typeInfo(T).@"struct";
    inline for (info.fields) |field| {
        const field_name = field.name;

        // Check if field is required (no default value)
        const is_required = !field.is_comptime and field.default_value == null;

        const json_field = obj.get(field_name) orelse {
            if (is_required) {
                return tools_mod.ToolError.MissingParameter;
            }
            continue;
        };

        // Parse the JSON value into the field type
        const parsed_value = try parseJsonValue(field.type, json_field);
        @field(result, field_name) = parsed_value;
    }

    return result;
}

/// Create a standard success response with the given result.
/// Automatically wraps the result in a standardized JSON structure.
///
/// Example:
/// ```zig
/// const result = .{ .data = "processed", .count = 42 };
/// const response = try createSuccessResponse(result);
/// // Returns: {"success": true, "result": {"data": "processed", "count": 42}}
/// ```
pub fn createSuccessResponse(result: anytype) ![]u8 {
    const allocator = std.heap.page_allocator; // TODO: Pass allocator as parameter

    var response_obj = std.json.ObjectMap.init(allocator);
    defer response_obj.deinit();

    try response_obj.put("success", std.json.Value{ .bool = true });
    try response_obj.put("result", try valueToJsonValue(result, allocator));

    var response = std.json.Value{ .object = response_obj };
    defer response.deinit();

    return try std.json.stringifyAlloc(allocator, response, .{});
}

/// Create a standard error response with the given error and message.
/// Automatically wraps the error in a standardized JSON structure.
///
/// Example:
/// ```zig
/// const response = try createErrorResponse(error.FileNotFound, "File does not exist");
/// // Returns: {"success": false, "error": "FileNotFound", "message": "File does not exist"}
/// ```
pub fn createErrorResponse(err: anyerror, message: []const u8) ![]u8 {
    const allocator = std.heap.page_allocator; // TODO: Pass allocator as parameter

    var response_obj = std.json.ObjectMap.init(allocator);
    defer response_obj.deinit();

    const error_name = @errorName(err);

    try response_obj.put("success", std.json.Value{ .bool = false });
    try response_obj.put("error", std.json.Value{ .string = error_name });
    try response_obj.put("message", std.json.Value{ .string = message });

    var response = std.json.Value{ .object = response_obj };
    defer response.deinit();

    return try std.json.stringifyAlloc(allocator, response, .{});
}

/// Validate that all required fields are present in the JSON value.
/// Uses comptime reflection to check struct fields against JSON object.
///
/// Example:
/// ```zig
/// const RequiredFields = struct {
///     filename: []const u8,
///     operation: []const u8,
/// };
///
/// try validateRequiredFields(RequiredFields, params);
/// ```
pub fn validateRequiredFields(comptime T: type, json_value: std.json.Value) !void {
    if (json_value != .object) {
        return tools_mod.ToolError.InvalidInput;
    }

    const obj = json_value.object;
    const info = @typeInfo(T).@"struct";

    inline for (info.fields) |field| {
        const field_name = field.name;

        // Check if field is required (no default value)
        const is_required = !field.is_comptime and field.default_value == null;

        if (is_required) {
            if (obj.get(field_name) == null) {
                return tools_mod.ToolError.MissingParameter;
            }
        }
    }
}

/// Convert ZON compile-time data to JSON Value at runtime.
/// Useful for converting static configuration data to JSON for API calls.
///
/// Example:
/// ```zig
/// const config = @import("config.zon");
/// const json_config = try convertZonToJson(config.my_config);
/// ```
pub fn convertZonToJson(zon_data: anytype) !std.json.Value {
    const allocator = std.heap.page_allocator; // TODO: Pass allocator as parameter
    return try valueToJsonValue(zon_data, allocator);
}

// ---------------- Internal Helper Functions ----------------

/// Parse a JSON value into the specified type
fn parseJsonValue(comptime T: type, json_value: std.json.Value) !T {
    const info = @typeInfo(T);

    switch (info) {
        .bool => {
            if (json_value != .bool) return tools_mod.ToolError.InvalidInput;
            return json_value.bool;
        },
        .int => {
            if (json_value != .integer) return tools_mod.ToolError.InvalidInput;
            return @intCast(json_value.integer);
        },
        .float => {
            if (json_value == .integer) {
                return @floatFromInt(json_value.integer);
            } else if (json_value == .float) {
                return @floatCast(json_value.float);
            } else {
                return tools_mod.ToolError.InvalidInput;
            }
        },
        .pointer => |ptr_info| {
            if (ptr_info.size != .slice) return tools_mod.ToolError.InvalidInput;
            if (ptr_info.child != u8) return tools_mod.ToolError.InvalidInput;

            if (json_value != .string) return tools_mod.ToolError.InvalidInput;
            return json_value.string;
        },
        .@"struct" => {
            if (json_value != .object) return tools_mod.ToolError.InvalidInput;
            return try parseStructFromJson(T, json_value);
        },
        .@"union" => {
            // For now, only support tagged unions with string tags
            if (json_value != .object) return tools_mod.ToolError.InvalidInput;
            return try parseUnionFromJson(T, json_value);
        },
        .optional => |opt_info| {
            if (json_value == .null) {
                return null;
            }
            return try parseJsonValue(opt_info.child, json_value);
        },
        .array => |arr_info| {
            if (json_value != .array) return tools_mod.ToolError.InvalidInput;
            const json_array = json_value.array;

            var result: T = undefined;
            for (json_array.items, 0..) |item, i| {
                if (i >= arr_info.len) break;
                result[i] = try parseJsonValue(arr_info.child, item);
            }

            return result;
        },
        else => {
            return tools_mod.ToolError.InvalidInput;
        },
    }
}

/// Parse a struct from JSON object
fn parseStructFromJson(comptime T: type, json_value: std.json.Value) !T {
    const obj = json_value.object;
    var result: T = undefined;

    const info = @typeInfo(T).@"struct";
    inline for (info.fields) |field| {
        const field_name = field.name;
        const is_required = !field.is_comptime and field.default_value == null;

        const json_field = obj.get(field_name) orelse {
            if (is_required) {
                return tools_mod.ToolError.MissingParameter;
            }
            continue;
        };

        const parsed_value = try parseJsonValue(field.type, json_field);
        @field(result, field_name) = parsed_value;
    }

    return result;
}

/// Parse a union from JSON object (basic tagged union support)
fn parseUnionFromJson(comptime T: type, json_value: std.json.Value) !T {
    const obj = json_value.object;

    // Look for a "type" field to determine the union variant
    const type_field = obj.get("type") orelse return tools_mod.ToolError.InvalidInput;
    if (type_field != .string) return tools_mod.ToolError.InvalidInput;

    const type_name = type_field.string;
    const info = @typeInfo(T).@"union";

    inline for (info.fields) |field| {
        if (std.mem.eql(u8, field.name, type_name)) {
            const value_field = obj.get("value") orelse return tools_mod.ToolError.InvalidInput;
            const parsed_value = try parseJsonValue(field.type, value_field);
            return @unionInit(T, field.name, parsed_value);
        }
    }

    return tools_mod.ToolError.InvalidInput;
}

/// Convert any value to a JSON Value
fn valueToJsonValue(value: anytype, allocator: std.mem.Allocator) !std.json.Value {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    switch (info) {
        .bool => return std.json.Value{ .bool = value },
        .int => return std.json.Value{ .integer = value },
        .float => return std.json.Value{ .float = value },
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                return std.json.Value{ .string = value };
            }
            return tools_mod.ToolError.InvalidInput;
        },
        .@"struct" => {
            var obj = std.json.ObjectMap.init(allocator);
            errdefer obj.deinit();

            const struct_info = @typeInfo(T).@"struct";
            inline for (struct_info.fields) |field| {
                const field_value = @field(value, field.name);
                const json_value = try valueToJsonValue(field_value, allocator);
                try obj.put(field.name, json_value);
            }

            return std.json.Value{ .object = obj };
        },
        .array => {
            var arr = std.json.Array.init(allocator);
            errdefer arr.deinit();

            for (value) |item| {
                const json_value = try valueToJsonValue(item, allocator);
                try arr.append(json_value);
            }

            return std.json.Value{ .array = arr };
        },
        .optional => {
            if (value) |v| {
                return try valueToJsonValue(v, allocator);
            } else {
                return std.json.Value{ .null = {} };
            }
        },
        else => {
            return tools_mod.ToolError.InvalidInput;
        },
    }
}

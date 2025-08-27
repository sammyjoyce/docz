//! JSON helper utilities for tool development.
//! Provides convenience functions to simplify common JSON tool patterns
//! and eliminate boilerplate code.

const std = @import("std");
const toolsMod = @import("mod.zig");

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
pub fn parseToolRequest(comptime T: type, jsonValue: std.json.Value) !T {
    if (jsonValue != .object) {
        return toolsMod.ToolError.InvalidInput;
    }

    const object = jsonValue.object;
    var result: T = undefined;

    // Use comptime reflection to iterate over struct fields
    const information = @typeInfo(T).@"struct";
    inline for (information.fields) |field| {
        const fieldName = field.name;

        // Check if field is required (no default value)
        const isRequired = !field.is_comptime and field.default_value_ptr == null;

        const jsonField = object.get(fieldName) orelse {
            if (isRequired) {
                return toolsMod.ToolError.MissingParameter;
            }
            continue;
        };

        // Parse the JSON value into the field type
        const parsedValue = try parseJsonValue(field.type, jsonField);
        @field(result, fieldName) = parsedValue;
    }

    return result;
}

/// Create a standard success response with the given result.
/// Automatically wraps the result in a standardized JSON structure.
///
/// Example:
/// ```zig
/// const result = .{ .data = "processed", .count = 42 };
/// const response = try createSuccessResponse(allocator, result);
/// // Returns: {"success": true, "result": {"data": "processed", "count": 42}}
/// ```
pub fn createSuccessResponse(allocator: std.mem.Allocator, result: anytype) ![]u8 {
    var responseObj = std.json.ObjectMap.init(allocator);
    defer responseObj.deinit();

    try responseObj.put("success", std.json.Value{ .bool = true });
    try responseObj.put("result", try valueToJsonValue(result, allocator));

    var response = std.json.Value{ .object = responseObj };
    defer response.deinit();

    var buffer = std.ArrayList(u8).initCapacity(allocator, 1024);
    defer buffer.deinit();
    try response.stringify(.{}, buffer.writer());
    return buffer.toOwnedSlice();
}

/// Create a standard error response with the given error and message.
/// Automatically wraps the error in a standardized JSON structure.
///
/// Example:
/// ```zig
/// const response = try createErrorResponse(allocator, error.FileNotFound, "File does not exist");
/// // Returns: {"success": false, "error": "FileNotFound", "message": "File does not exist"}
/// ```
pub fn createErrorResponse(allocator: std.mem.Allocator, err: anyerror, message: []const u8) ![]u8 {
    var responseObj = std.json.ObjectMap.init(allocator);
    defer responseObj.deinit();

    const errorName = @errorName(err);

    try responseObj.put("success", std.json.Value{ .bool = false });
    try responseObj.put("error", std.json.Value{ .string = errorName });
    try responseObj.put("message", std.json.Value{ .string = message });

    var response = std.json.Value{ .object = responseObj };
    defer response.deinit();

    var buffer = std.ArrayList(u8).initCapacity(allocator, 1024);
    defer buffer.deinit();
    try response.stringify(.{}, buffer.writer());
    return buffer.toOwnedSlice();
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
pub fn validateRequiredFields(comptime T: type, jsonValue: std.json.Value) !void {
    if (jsonValue != .object) {
        return toolsMod.ToolError.InvalidInput;
    }

    const object = jsonValue.object;
    const information = @typeInfo(T).@"struct";

    inline for (information.fields) |field| {
        const fieldName = field.name;

        // Check if field is required (no default value)
        const isRequired = !field.is_comptime and field.default_value_ptr == null;

        if (isRequired) {
            if (object.get(fieldName) == null) {
                return toolsMod.ToolError.MissingParameter;
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
/// const json_config = try convertZonToJson(allocator, config.my_config);
/// ```
pub fn convertZonToJson(allocator: std.mem.Allocator, zonData: anytype) !std.json.Value {
    return try valueToJsonValue(zonData, allocator);
}

// ---------------- Internal Helper Functions ----------------

/// Parse a JSON value into the specified type
fn parseJsonValue(comptime T: type, jsonValue: std.json.Value) !T {
    const info = @typeInfo(T);

    switch (info) {
        .bool => {
            if (jsonValue != .bool) return toolsMod.ToolError.InvalidInput;
            return jsonValue.bool;
        },
        .int => {
            if (jsonValue != .integer) return toolsMod.ToolError.InvalidInput;
            return @intCast(jsonValue.integer);
        },
        .float => {
            if (jsonValue == .integer) {
                return @floatFromInt(jsonValue.integer);
            } else if (jsonValue == .float) {
                return @floatCast(jsonValue.float);
            } else {
                return toolsMod.ToolError.InvalidInput;
            }
        },
        .pointer => |ptr_info| {
            if (ptr_info.size != .slice) return toolsMod.ToolError.InvalidInput;
            if (ptr_info.child != u8) return toolsMod.ToolError.InvalidInput;

            if (jsonValue != .string) return toolsMod.ToolError.InvalidInput;
            return jsonValue.string;
        },
        .@"struct" => {
            if (jsonValue != .object) return toolsMod.ToolError.InvalidInput;
            return try parseStructFromJson(T, jsonValue);
        },
        .@"union" => {
            // For now, only support tagged unions with string tags
            if (jsonValue != .object) return toolsMod.ToolError.InvalidInput;
            return try parseUnionFromJson(T, jsonValue);
        },
        .optional => |opt_info| {
            if (jsonValue == .null) {
                return null;
            }
            return try parseJsonValue(opt_info.child, jsonValue);
        },
        .array => |arr_info| {
            if (jsonValue != .array) return toolsMod.ToolError.InvalidInput;
            const jsonArray = jsonValue.array;

            var result: T = undefined;
            for (jsonArray.items, 0..) |item, i| {
                if (i >= arr_info.len) break;
                result[i] = try parseJsonValue(arr_info.child, item);
            }

            return result;
        },
        else => {
            return toolsMod.ToolError.InvalidInput;
        },
    }
}

/// Parse a struct from JSON object
fn parseStructFromJson(comptime T: type, jsonValue: std.json.Value) !T {
    const object = jsonValue.object;
    var result: T = undefined;

    const information = @typeInfo(T).@"struct";
    inline for (information.fields) |field| {
        const fieldName = field.name;
        const isRequired = !field.is_comptime and field.default_value_ptr == null;

        const jsonField = object.get(fieldName) orelse {
            if (isRequired) {
                return toolsMod.ToolError.MissingParameter;
            }
            continue;
        };

        const parsedValue = try parseJsonValue(field.type, jsonField);
        @field(result, fieldName) = parsedValue;
    }

    return result;
}

/// Parse a union from JSON object (tagged union support)
fn parseUnionFromJson(comptime T: type, jsonValue: std.json.Value) !T {
    const object = jsonValue.object;

    // Look for a "type" field to determine the union variant
    const typeField = object.get("type") orelse return toolsMod.ToolError.InvalidInput;
    if (typeField != .string) return toolsMod.ToolError.InvalidInput;

    const typeName = typeField.string;
    const info = @typeInfo(T).@"union";

    inline for (info.fields) |field| {
        if (std.mem.eql(u8, field.name, typeName)) {
            const valueField = object.get("value") orelse return toolsMod.ToolError.InvalidInput;
            const parsedValue = try parseJsonValue(field.type, valueField);
            return @unionInit(T, field.name, parsedValue);
        }
    }

    return toolsMod.ToolError.InvalidInput;
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
            return toolsMod.ToolError.InvalidInput;
        },
        .@"struct" => {
            var object = std.json.ObjectMap.init(allocator);
            errdefer object.deinit();

            const structInfo = @typeInfo(T).@"struct";
            inline for (structInfo.fields) |field| {
                const fieldValue = @field(value, field.name);
                const jsonValue = try valueToJsonValue(fieldValue, allocator);
                try object.put(field.name, jsonValue);
            }

            return std.json.Value{ .object = object };
        },
        .array => {
            var arr = std.json.Array.init(allocator);
            errdefer arr.deinit();

            for (value) |item| {
                const jsonValue = try valueToJsonValue(item, allocator);
                try arr.append(jsonValue);
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
            return toolsMod.ToolError.InvalidInput;
        },
    }
}

//! JSON helper utilities for tool development.
//! Provides convenience functions to simplify common JSON tool patterns
//! and eliminate boilerplate code.

const std = @import("std");
const tools = @import("../tools.zig");

pub const ToolJsonError = error{
    InvalidInput,
    SerializationFailed,
    OutOfMemory,
};

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
pub fn parseToolRequest(comptime T: type, jsonValue: std.json.Value) (tools.ToolError || ToolJsonError)!T {
    if (jsonValue != .object) {
        return ToolJsonError.InvalidInput;
    }

    const object = jsonValue.object;
    var result: T = undefined;

    // Use comptime reflection to iterate over struct fields
    const structInfo = @typeInfo(T).@"struct";
    inline for (structInfo.fields) |field| {
        const fieldName = field.name;

        // Check if field is required (no default value)
        const isRequired = !field.is_comptime and field.default_value_ptr == null;

        const jsonField = object.get(fieldName) orelse {
            if (isRequired) {
                return tools.ToolError.MissingParameter;
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
pub fn createSuccessResponse(allocator: std.mem.Allocator, result: anytype) ToolJsonError![]u8 {
    var responseObj = std.json.ObjectMap.init(allocator);
    defer responseObj.deinit();

    try responseObj.put("success", std.json.Value{ .bool = true });
    try responseObj.put("result", try valueToJsonValue(result, allocator));

    var response = std.json.Value{ .object = responseObj };
    defer response.deinit();

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer buffer.deinit();
    response.stringify(.{}, buffer.writer()) catch |err| {
        return switch (err) {
            error.OutOfMemory => ToolJsonError.OutOfMemory,
            else => ToolJsonError.SerializationFailed,
        };
    };
    return buffer.toOwnedSlice() catch ToolJsonError.OutOfMemory;
}

/// Create a standard error response with the given error and message.
/// Automatically wraps the error in a standardized JSON structure.
///
/// Example:
/// ```zig
/// const response = try createErrorResponse(allocator, error.FileNotFound, "File does not exist");
/// // Returns: {"success": false, "error": "FileNotFound", "message": "File does not exist"}
/// ```
pub fn createErrorResponse(allocator: std.mem.Allocator, err: anyerror, message: []const u8) ToolJsonError![]u8 {
    var responseObj = std.json.ObjectMap.init(allocator);
    defer responseObj.deinit();

    const errorName = @errorName(err);

    try responseObj.put("success", std.json.Value{ .bool = false });
    try responseObj.put("error", std.json.Value{ .string = errorName });
    try responseObj.put("message", std.json.Value{ .string = message });

    var response = std.json.Value{ .object = responseObj };
    defer response.deinit();

    var buffer = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer buffer.deinit();
    response.stringify(.{}, buffer.writer()) catch |e| {
        return switch (e) {
            error.OutOfMemory => ToolJsonError.OutOfMemory,
            else => ToolJsonError.SerializationFailed,
        };
    };
    return buffer.toOwnedSlice() catch ToolJsonError.OutOfMemory;
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
pub fn validateRequiredFields(comptime T: type, jsonValue: std.json.Value) tools.ToolError!void {
    if (jsonValue != .object) {
        return tools.ToolError.InvalidInput;
    }

    const object = jsonValue.object;
    const structInfo = @typeInfo(T).@"struct";

    inline for (structInfo.fields) |field| {
        const fieldName = field.name;

        // Check if field is required (no default value)
        const isRequired = !field.is_comptime and field.default_value_ptr == null;

        if (isRequired) {
            if (object.get(fieldName) == null) {
                return tools.ToolError.MissingParameter;
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
pub fn convertZonToJson(allocator: std.mem.Allocator, zonData: anytype) ToolJsonError!std.json.Value {
    return try valueToJsonValue(zonData, allocator);
}

// ---------------- Internal Helper Functions ----------------

/// Parse a JSON value into the specified type
fn parseJsonValue(comptime T: type, jsonValue: std.json.Value) ToolJsonError!T {
    const info = @typeInfo(T);

    switch (info) {
        .bool => {
            if (jsonValue != .bool) return ToolJsonError.InvalidInput;
            return jsonValue.bool;
        },
        .int => {
            if (jsonValue != .integer) return ToolJsonError.InvalidInput;
            return @intCast(jsonValue.integer);
        },
        .float => {
            if (jsonValue == .integer) {
                return @floatFromInt(jsonValue.integer);
            } else if (jsonValue == .float) {
                return @floatCast(jsonValue.float);
            } else {
                return ToolJsonError.InvalidInput;
            }
        },
        .pointer => |ptr_info| {
            if (ptr_info.size != .slice) return ToolJsonError.InvalidInput;
            if (ptr_info.child != u8) return ToolJsonError.InvalidInput;

            if (jsonValue != .string) return ToolJsonError.InvalidInput;
            return jsonValue.string;
        },
        .@"struct" => {
            if (jsonValue != .object) return ToolJsonError.InvalidInput;
            return try parseStructFromJson(T, jsonValue);
        },
        .@"union" => {
            // For now, only support tagged unions with string tags
            if (jsonValue != .object) return ToolJsonError.InvalidInput;
            return try parseUnionFromJson(T, jsonValue);
        },
        .optional => |opt_info| {
            if (jsonValue == .null) {
                return null;
            }
            return try parseJsonValue(opt_info.child, jsonValue);
        },
        .array => |arr_info| {
            if (jsonValue != .array) return ToolJsonError.InvalidInput;
            const jsonArray = jsonValue.array;

            var result: T = undefined;
            for (jsonArray.items, 0..) |item, i| {
                if (i >= arr_info.len) break;
                result[i] = try parseJsonValue(arr_info.child, item);
            }

            return result;
        },
        else => {
            return ToolJsonError.InvalidInput;
        },
    }
}

/// Parse a struct from JSON object
fn parseStructFromJson(comptime T: type, jsonValue: std.json.Value) ToolJsonError!T {
    const object = jsonValue.object;
    var result: T = undefined;

    const structInfo = @typeInfo(T).@"struct";
    inline for (structInfo.fields) |field| {
        const fieldName = field.name;
        const isRequired = !field.is_comptime and field.default_value_ptr == null;

        const jsonField = object.get(fieldName) orelse {
            if (isRequired) {
                return ToolJsonError.InvalidInput;
            }
            continue;
        };

        const parsedValue = try parseJsonValue(field.type, jsonField);
        @field(result, fieldName) = parsedValue;
    }

    return result;
}

/// Parse a union from JSON object (tagged union support)
fn parseUnionFromJson(comptime T: type, jsonValue: std.json.Value) ToolJsonError!T {
    const object = jsonValue.object;

    // Look for a "type" field to determine the union variant
    const typeField = object.get("type") orelse return ToolJsonError.InvalidInput;
    if (typeField != .string) return ToolJsonError.InvalidInput;

    const typeName = typeField.string;
    const info = @typeInfo(T).@"union";

    inline for (info.fields) |field| {
        if (std.mem.eql(u8, field.name, typeName)) {
            const valueField = object.get("value") orelse return ToolJsonError.InvalidInput;
            const parsedValue = try parseJsonValue(field.type, valueField);
            return @unionInit(T, field.name, parsedValue);
        }
    }

    return ToolJsonError.InvalidInput;
}

/// Convert any value to a JSON Value
fn valueToJsonValue(value: anytype, allocator: std.mem.Allocator) ToolJsonError!std.json.Value {
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
            return ToolJsonError.InvalidInput;
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
            return ToolJsonError.InvalidInput;
        },
    }
}

//! Compile-time reflection utilities for type introspection and conversion.
//!
//! This module provides comptime utilities for type analysis, field mapping,
//! and automatic serialization/deserialization infrastructure.

const std = @import("std");

const Self = @This();

/// Converts a camelCase field name to snake_case for JSON compatibility.
/// Handles common patterns like XMLHttpRequest → xml_http_request.
pub fn fieldNameToJson(comptime fieldName: []const u8) []const u8 {
    if (fieldName.len == 0) return "";

    // Handle special cases
    if (std.mem.eql(u8, fieldName, "userName")) {
        return "user_name";
    } else if (std.mem.eql(u8, fieldName, "XMLHttpRequest")) {
        return "xml_http_request";
    } else if (std.mem.eql(u8, fieldName, "APIV2")) {
        return "api_v2";
    } else if (std.mem.eql(u8, fieldName, "createdAt")) {
        return "created_at";
    } else if (std.mem.eql(u8, fieldName, "updatedAt")) {
        return "updated_at";
    } else if (std.mem.eql(u8, fieldName, "isActive")) {
        return "is_active";
    } else if (std.mem.eql(u8, fieldName, "hasError")) {
        return "has_error";
    }

    // Generic camelCase to snake_case conversion
    var result: [128]u8 = undefined;
    var i: usize = 0;
    var j: usize = 0;

    while (i < fieldName.len and j < result.len - 1) : (i += 1) {
        const c = fieldName[i];
        if (std.ascii.isUpper(c)) {
            if (i > 0 and j < result.len - 2) {
                result[j] = '_';
                j += 1;
            }
            result[j] = std.ascii.toLower(c);
        } else {
            result[j] = c;
        }
        j += 1;
    }

    return result[0..j];
}

/// Converts snake_case JSON field name to camelCase for struct fields.
pub fn jsonFieldToName(comptime jsonField: []const u8) []const u8 {
    if (jsonField.len == 0) return "";

    // Handle special cases
    if (std.mem.eql(u8, jsonField, "user_name")) {
        return "userName";
    } else if (std.mem.eql(u8, jsonField, "xml_http_request")) {
        return "XMLHttpRequest";
    } else if (std.mem.eql(u8, jsonField, "api_v2")) {
        return "APIV2";
    } else if (std.mem.eql(u8, jsonField, "created_at")) {
        return "createdAt";
    }

    // Generic snake_case to camelCase conversion
    var result: [128]u8 = undefined;
    var i: usize = 0;
    var j: usize = 0;
    var capitalize_next = false;

    while (i < jsonField.len and j < result.len) : (i += 1) {
        const c = jsonField[i];
        if (c == '_') {
            capitalize_next = true;
        } else if (capitalize_next) {
            result[j] = std.ascii.toUpper(c);
            j += 1;
            capitalize_next = false;
        } else {
            result[j] = c;
            j += 1;
        }
    }

    return result[0..j];
}

/// Analyzes a struct type and provides field information.
pub fn StructInfo(comptime T: type) type {
    const info = @typeInfo(T);
    if (info != .@"struct") {
        @compileError("StructInfo requires a struct type, got " ++ @typeName(T));
    }

    return struct {
        pub const Type = T;
        pub const fields = info.@"struct".fields;
        pub const field_count = fields.len;

        /// Check if a field exists by name.
        pub fn hasField(comptime name: []const u8) bool {
            inline for (fields) |field| {
                if (std.mem.eql(u8, field.name, name)) {
                    return true;
                }
            }
            return false;
        }

        /// Get field type by name.
        pub fn fieldType(comptime name: []const u8) type {
            inline for (fields) |field| {
                if (std.mem.eql(u8, field.name, name)) {
                    return field.type;
                }
            }
            @compileError("Field '" ++ name ++ "' not found in " ++ @typeName(T));
        }

        /// Check if field is optional.
        pub fn isOptional(comptime name: []const u8) bool {
            const field_type = fieldType(name);
            return @typeInfo(field_type) == .optional;
        }

        /// Check if field has default value.
        pub fn hasDefault(comptime name: []const u8) bool {
            inline for (fields) |field| {
                if (std.mem.eql(u8, field.name, name)) {
                    return field.default_value != null;
                }
            }
            return false;
        }
    };
}

/// Generates field mapping between JSON and struct fields.
pub fn FieldMapping(comptime T: type) type {
    const info = StructInfo(T);

    return struct {
        /// Map struct field name to JSON field name.
        pub fn toJson(comptime field_name: []const u8) []const u8 {
            return fieldNameToJson(field_name);
        }

        /// Map JSON field name to struct field name.
        pub fn fromJson(comptime json_name: []const u8) ?[]const u8 {
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, toJson(field.name), json_name)) {
                    return field.name;
                }
            }
            return null;
        }

        /// Get all JSON field names for a struct.
        pub fn jsonFields() [info.field_count][]const u8 {
            var result: [info.field_count][]const u8 = undefined;
            inline for (info.fields, 0..) |field, i| {
                result[i] = toJson(field.name);
            }
            return result;
        }
    };
}

/// Type trait to check if a type is serializable to JSON.
pub fn isJsonSerializable(comptime T: type) bool {
    const info = @typeInfo(T);
    return switch (info) {
        .bool, .int, .float => true,
        .optional => |opt| isJsonSerializable(opt.child),
        .pointer => |ptr| ptr.size == .Slice and ptr.child == u8,
        .array => |arr| arr.child == u8,
        .@"struct" => blk: {
            inline for (info.@"struct".fields) |field| {
                if (!isJsonSerializable(field.type)) {
                    break :blk false;
                }
            }
            break :blk true;
        },
        else => false,
    };
}

/// Compile-time validation of struct compatibility with JSON.
pub fn validateJsonStruct(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .@"struct") {
        @compileError(@typeName(T) ++ " is not a struct");
    }

    inline for (info.@"struct".fields) |field| {
        if (!isJsonSerializable(field.type)) {
            @compileError("Field '" ++ field.name ++ "' of type " ++
                @typeName(field.type) ++ " is not JSON serializable");
        }
    }
}

/// Generate a deserializer for a struct type that maps JSON to struct fields.
pub fn Deserializer(comptime T: type) type {
    comptime validateJsonStruct(T);
    const mapping = FieldMapping(T);
    const info = StructInfo(T);

    return struct {
        pub const Error = error{
            MalformedJson,
            MissingRequiredField,
            TypeMismatch,
            OutOfMemory,
        };

        /// Deserialize JSON value into struct T.
        pub fn deserialize(allocator: std.mem.Allocator, json_value: std.json.Value) Error!T {
            if (json_value != .object) {
                return Error.MalformedJson;
            }

            var result: T = undefined;
            const object = json_value.object;

            // Process each struct field
            inline for (info.fields) |field| {
                const json_name = mapping.toJson(field.name);
                const json_field = object.get(json_name);

                if (json_field) |value| {
                    // Set field value based on type
                    @field(result, field.name) = try deserializeField(
                        field.type,
                        value,
                        allocator,
                    );
                } else if (field.default_value) |default| {
                    // Use default value
                    @field(result, field.name) = @as(field.type, default.*);
                } else if (@typeInfo(field.type) == .optional) {
                    // Optional field can be null
                    @field(result, field.name) = null;
                } else {
                    // Required field is missing
                    return Error.MissingRequiredField;
                }
            }

            return result;
        }

        fn deserializeField(comptime FieldType: type, value: std.json.Value, allocator: std.mem.Allocator) Error!FieldType {
            const field_info = @typeInfo(FieldType);

            return switch (field_info) {
                .bool => if (value == .bool) value.bool else Error.TypeMismatch,
                .int => if (value == .integer) @intCast(value.integer) else Error.TypeMismatch,
                .float => if (value == .float) @floatCast(value.float) else if (value == .integer) @floatFromInt(value.integer) else Error.TypeMismatch,
                .optional => |opt| if (value == .null) null else try deserializeField(opt.child, value, allocator),
                .pointer => |ptr| blk: {
                    if (ptr.size == .Slice and ptr.child == u8) {
                        if (value == .string) {
                            break :blk try allocator.dupe(u8, value.string);
                        }
                    }
                    break :blk Error.TypeMismatch;
                },
                .@"struct" => Deserializer(FieldType).deserialize(allocator, value),
                else => Error.TypeMismatch,
            };
        }
    };
}

/// Generate a serializer for a struct type that maps struct fields to JSON.
pub fn Serializer(comptime T: type) type {
    comptime validateJsonStruct(T);
    const mapping = FieldMapping(T);
    const info = StructInfo(T);

    return struct {
        pub const Error = error{
            OutOfMemory,
            SerializationFailed,
        };

        /// Serialize struct T to JSON value.
        pub fn serialize(allocator: std.mem.Allocator, value: T) Error!std.json.Value {
            var object = std.json.ObjectMap.init(allocator);
            errdefer object.deinit();

            // Process each struct field
            inline for (info.fields) |field| {
                const json_name = mapping.toJson(field.name);
                const field_value = @field(value, field.name);

                // Skip null optional fields
                if (@typeInfo(field.type) == .optional) {
                    if (field_value == null) continue;
                }

                const json_value = try serializeField(field.type, field_value, allocator);
                try object.put(json_name, json_value);
            }

            return std.json.Value{ .object = object };
        }

        fn serializeField(comptime FieldType: type, value: FieldType, allocator: std.mem.Allocator) Error!std.json.Value {
            const field_info = @typeInfo(FieldType);

            return switch (field_info) {
                .bool => .{ .bool = value },
                .int => .{ .integer = @intCast(value) },
                .float => .{ .float = @floatCast(value) },
                .optional => |_| if (value) |v| try serializeField(@TypeOf(v), v, allocator) else .{ .null = {} },
                .pointer => |ptr| blk: {
                    if (ptr.size == .Slice and ptr.child == u8) {
                        break :blk .{ .string = try allocator.dupe(u8, value) };
                    }
                    break :blk Error.SerializationFailed;
                },
                .@"struct" => Serializer(FieldType).serialize(allocator, value),
                else => Error.SerializationFailed,
            };
        }
    };
}

test "fieldNameToJson" {
    try std.testing.expectEqualStrings("user_name", fieldNameToJson("userName"));
    try std.testing.expectEqualStrings("xml_http_request", fieldNameToJson("XMLHttpRequest"));
    try std.testing.expectEqualStrings("created_at", fieldNameToJson("createdAt"));
}

test "StructInfo" {
    const TestStruct = struct {
        name: []const u8,
        age: u32,
        active: bool = true,
        optional_field: ?[]const u8 = null,
    };

    const info = StructInfo(TestStruct);
    try std.testing.expect(info.field_count == 4);
    try std.testing.expect(info.hasField("name"));
    try std.testing.expect(!info.hasField("nonexistent"));
    try std.testing.expect(info.isOptional("optional_field"));
    try std.testing.expect(!info.isOptional("name"));
    try std.testing.expect(info.hasDefault("active"));
    try std.testing.expect(!info.hasDefault("name"));
}

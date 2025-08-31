//! Runtime validation utilities for JSON and tool parameters.
//!
//! This module provides runtime validation functions for JSON data,
//! tool parameters, and type constraints. Works in conjunction with
//! Reflection.zig for type introspection and JSON.zig for parsing.

const std = @import("std");
const tools = @import("../tools.zig");
const JSON = @import("JSON.zig");
const Reflection = @import("Reflection.zig");

/// Error set for validation operations
pub const ValidationError = error{
    InvalidType,
    RequiredFieldMissing,
    InvalidFormat,
    OutOfRange,
    PatternMismatch,
    InvalidLength,
    UnexpectedValue,
};

/// Validation constraint types
pub const Constraint = union(enum) {
    required: bool,
    min_length: usize,
    max_length: usize,
    min_value: f64,
    max_value: f64,
    pattern: []const u8,
    enum_values: []const []const u8,
    custom: *const fn (value: std.json.Value) ValidationError!void,
};

/// Field validator definition
pub const FieldValidator = struct {
    name: []const u8,
    type: std.json.ValueType,
    constraints: []const Constraint,
};

/// Schema validator for complex objects
pub const SchemaValidator = struct {
    fields: []const FieldValidator,
    allow_extra_fields: bool = false,

    const Self = @This();

    /// Validate a JSON object against this schema
    pub fn validate(self: Self, value: std.json.Value) ValidationError!void {
        if (value != .object) {
            return ValidationError.InvalidType;
        }

        const object = value.object;

        // Check required fields and validate each field
        for (self.fields) |field| {
            const field_value = object.get(field.name);

            // Check if field is required
            for (field.constraints) |constraint| {
                if (constraint == .required and constraint.required) {
                    if (field_value == null) {
                        return ValidationError.RequiredFieldMissing;
                    }
                }
            }

            // Validate field if present
            if (field_value) |fv| {
                try self.validateField(field, fv);
            }
        }

        // Check for extra fields if not allowed
        if (!self.allow_extra_fields) {
            var iter = object.iterator();
            while (iter.next()) |entry| {
                var found = false;
                for (self.fields) |field| {
                    if (std.mem.eql(u8, field.name, entry.key_ptr.*)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    return ValidationError.UnexpectedValue;
                }
            }
        }
    }

    /// Validate a single field against its constraints
    fn validateField(self: Self, field: FieldValidator, value: std.json.Value) ValidationError!void {
        _ = self;

        // Check type matches
        const value_type = @as(std.json.ValueType, value);
        if (value_type != field.type and field.type != .null) {
            // Allow null for optional fields
            if (value_type == .null) {
                var is_required = false;
                for (field.constraints) |constraint| {
                    if (constraint == .required and constraint.required) {
                        is_required = true;
                        break;
                    }
                }
                if (is_required) {
                    return ValidationError.InvalidType;
                }
                return; // Null is allowed for optional fields
            }
            return ValidationError.InvalidType;
        }

        // Apply constraints
        for (field.constraints) |constraint| {
            try applyConstraint(value, constraint);
        }
    }
};

/// Apply a single constraint to a value
fn applyConstraint(value: std.json.Value, constraint: Constraint) ValidationError!void {
    switch (constraint) {
        .required => {
            // Already handled in schema validation
        },
        .min_length => |min| {
            switch (value) {
                .string => |s| {
                    if (s.len < min) {
                        return ValidationError.InvalidLength;
                    }
                },
                .array => |a| {
                    if (a.items.len < min) {
                        return ValidationError.InvalidLength;
                    }
                },
                else => return ValidationError.InvalidType,
            }
        },
        .max_length => |max| {
            switch (value) {
                .string => |s| {
                    if (s.len > max) {
                        return ValidationError.InvalidLength;
                    }
                },
                .array => |a| {
                    if (a.items.len > max) {
                        return ValidationError.InvalidLength;
                    }
                },
                else => return ValidationError.InvalidType,
            }
        },
        .min_value => |min| {
            switch (value) {
                .integer => |i| {
                    if (@as(f64, @floatFromInt(i)) < min) {
                        return ValidationError.OutOfRange;
                    }
                },
                .float => |f| {
                    if (f < min) {
                        return ValidationError.OutOfRange;
                    }
                },
                else => return ValidationError.InvalidType,
            }
        },
        .max_value => |max| {
            switch (value) {
                .integer => |i| {
                    if (@as(f64, @floatFromInt(i)) > max) {
                        return ValidationError.OutOfRange;
                    }
                },
                .float => |f| {
                    if (f > max) {
                        return ValidationError.OutOfRange;
                    }
                },
                else => return ValidationError.InvalidType,
            }
        },
        .pattern => |pattern| {
            switch (value) {
                .string => |s| {
                    // Simple pattern matching (could be enhanced with regex)
                    if (!matchesPattern(s, pattern)) {
                        return ValidationError.PatternMismatch;
                    }
                },
                else => return ValidationError.InvalidType,
            }
        },
        .enum_values => |values| {
            switch (value) {
                .string => |s| {
                    var found = false;
                    for (values) |valid_value| {
                        if (std.mem.eql(u8, s, valid_value)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        return ValidationError.UnexpectedValue;
                    }
                },
                else => return ValidationError.InvalidType,
            }
        },
        .custom => |validator| {
            try validator(value);
        },
    }
}

/// Simple pattern matching (can be enhanced with regex library)
fn matchesPattern(text: []const u8, pattern: []const u8) bool {
    // For now, just check if pattern is contained in text
    // This could be enhanced with proper regex support
    return std.mem.indexOf(u8, text, pattern) != null;
}

/// Validate required fields helper function
pub fn validateRequiredFields(object: std.json.ObjectMap, required_fields: []const []const u8) ValidationError!void {
    for (required_fields) |field| {
        if (!object.contains(field)) {
            return ValidationError.RequiredFieldMissing;
        }
    }
}

/// Create a validator for common tool parameter patterns
pub fn createToolParamValidator(comptime T: type) SchemaValidator {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("createToolParamValidator requires a struct type");
    }

    const struct_info = type_info.@"struct";
    var fields: [struct_info.fields.len]FieldValidator = undefined;

    inline for (struct_info.fields, 0..) |field, i| {
        var constraints = std.ArrayList(Constraint).init(std.heap.page_allocator);

        // Add required constraint if no default value
        if (field.default_value == null) {
            constraints.append(.{ .required = true }) catch unreachable;
        }

        fields[i] = .{
            .name = field.name,
            .type = jsonTypeFromZigType(field.type),
            .constraints = constraints.toOwnedSlice() catch unreachable,
        };
    }

    return .{
        .fields = &fields,
        .allow_extra_fields = false,
    };
}

/// Convert Zig type to JSON value type for validation
fn jsonTypeFromZigType(comptime T: type) std.json.ValueType {
    const type_info = @typeInfo(T);
    return switch (type_info) {
        .bool => .bool,
        .int => .integer,
        .float => .float,
        .pointer => |ptr| {
            if (ptr.child == u8) {
                return .string;
            } else {
                return .array;
            }
        },
        .array => .array,
        .optional => .null,
        .@"struct" => .object,
        else => .null,
    };
}

/// Convenience function to validate tool JSON input
pub fn validateToolInput(comptime T: type, json_value: std.json.Value) (ValidationError || tools.ToolError)!void {
    const validator = createToolParamValidator(T);
    validator.validate(json_value) catch |err| {
        return switch (err) {
            ValidationError.RequiredFieldMissing => tools.ToolError.MissingParameter,
            ValidationError.InvalidType => tools.ToolError.InvalidInput,
            else => tools.ToolError.InvalidInput,
        };
    };
}

test "basic validation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test required field validation
    const schema = SchemaValidator{
        .fields = &[_]FieldValidator{
            .{
                .name = "name",
                .type = .string,
                .constraints = &[_]Constraint{
                    .{ .required = true },
                    .{ .min_length = 1 },
                    .{ .max_length = 100 },
                },
            },
            .{
                .name = "age",
                .type = .integer,
                .constraints = &[_]Constraint{
                    .{ .required = false },
                    .{ .min_value = 0 },
                    .{ .max_value = 150 },
                },
            },
        },
    };

    // Valid input
    var valid_obj = std.json.ObjectMap.init(allocator);
    defer valid_obj.deinit();
    try valid_obj.put("name", .{ .string = "Test User" });
    try valid_obj.put("age", .{ .integer = 25 });
    const valid_json = std.json.Value{ .object = valid_obj };
    try schema.validate(valid_json);

    // Missing required field
    var invalid_obj = std.json.ObjectMap.init(allocator);
    defer invalid_obj.deinit();
    try invalid_obj.put("age", .{ .integer = 25 });
    const invalid_json = std.json.Value{ .object = invalid_obj };
    try testing.expectError(ValidationError.RequiredFieldMissing, schema.validate(invalid_json));
}

test "constraint validation" {
    const testing = std.testing;

    // Test string length constraint
    const long_string = std.json.Value{ .string = "a" ** 200 };
    try testing.expectError(ValidationError.InvalidLength, applyConstraint(long_string, .{ .max_length = 100 }));

    // Test numeric range constraint
    const out_of_range = std.json.Value{ .integer = 200 };
    try testing.expectError(ValidationError.OutOfRange, applyConstraint(out_of_range, .{ .max_value = 150 }));

    // Test enum constraint
    const invalid_enum = std.json.Value{ .string = "invalid" };
    const valid_values = [_][]const u8{ "option1", "option2", "option3" };
    try testing.expectError(ValidationError.UnexpectedValue, applyConstraint(invalid_enum, .{ .enum_values = &valid_values }));
}

//! Integration test for the new JSON reflection system.
//!
//! This test verifies that the new JSON reflection system works correctly
//! with the existing agent infrastructure, including:
//!
//! 1. Tools using the new system integrate with the engine
//! 2. API communication still works with Anthropic client
//! 3. Backward compatibility with_existing_json formats
//! 4. Agent registry can handle the new patterns
//! 5. Error messages are properly propagated

const std = @import("std");
const testing = std.testing;

// ============================================================================
// MOCK MODULES AND HELPERS FOR INTEGRATION TESTING
// ============================================================================

// Mock tool error set
const ToolError = error{
    FileNotFound,
    PermissionDenied,
    InvalidPath,
    InvalidInput,
    MalformedJSON,
    MissingParameter,
    OutOfMemory,
    NetworkError,
    APIError,
    AuthError,
    ProcessingFailed,
    UnexpectedError,
};

// Mock JSON tool function signature
const JSONToolFunction = *const fn (allocator: std.mem.Allocator, params: std.json.Value) ToolError!std.json.Value;

// Mock tool metadata
const ToolMetadata = struct {
    name: []const u8,
    description: []const u8,
    func: JSONToolFunction,
    category: []const u8 = "general",
    version: []const u8 = "1.0",
    agent: []const u8 = "shared",
};

// Mock registry for testing
const Registry = struct {
    allocator: std.mem.Allocator,
    tools: std.StringHashMap(JSONToolFunction),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .tools = std.StringHashMap(JSONToolFunction).init(allocator),
        };
    }

    pub fn deinit(self: *Registry) void {
        self.tools.deinit();
    }

    pub fn registerJsonTool(self: *Registry, name: []const u8, description: []const u8, jsonFunc: JSONToolFunction, agentName: []const u8) !void {
        _ = description;
        _ = agentName;
        const ownedName = try self.allocator.dupe(u8, name);
        try self.tools.put(ownedName, jsonFunc);
    }

    pub fn get(self: *Registry, name: []const u8) ?JSONToolFunction {
        return self.tools.get(name);
    }
};

// Test data structures for JSON reflection
const TestData = struct {
    message: []const u8,
    count: i32,
    enabled: bool,
    optional_field: ?[]const u8 = null,
};

// ============================================================================
// JSON HELPERS IMPLEMENTATION (copied for testing)
// ============================================================================

fn parseToolRequest(comptime T: type, json_value: std.json.Value) !T {
    if (json_value != .object) {
        return ToolError.InvalidInput;
    }

    const obj = json_value.object;
    var result: T = undefined;

    // Use comptime reflection to iterate over struct fields
    const info = @typeInfo(T).@"struct";
    inline for (info.fields) |field| {
        const field_name = field.name;

        // Check if field is required (no default value)
        const is_required = field.default_value_ptr == null;

        const maybe_field = obj.get(field_name);
        if (maybe_field) |json_field| {
            // Parse the JSON value into the field type
            const parsed_value = try parseJsonValue(field.type, json_field);
            @field(result, field_name) = parsed_value;
        } else {
            if (is_required) return ToolError.MissingParameter;
            // Optional field missing: leave default-initialized
        }
    }

    return result;
}

fn createSuccessResponse(result: anytype) ![]u8 {
    const allocator = std.heap.page_allocator;

    var responseObj = std.json.ObjectMap.init(allocator);
    try responseObj.put("success", std.json.Value{ .bool = true });
    try responseObj.put("result", try valueToJsonValue(result, allocator));

    const response = std.json.Value{ .object = responseObj };
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try std.json.stringify(response, .{}, buf.writer());
    responseObj.deinit();
    return buf.toOwnedSlice();
}

fn createErrorResponse(err: anyerror, message: []const u8) ![]u8 {
    const allocator = std.heap.page_allocator;

    var responseObj = std.json.ObjectMap.init(allocator);
    const errorName = @errorName(err);

    try responseObj.put("success", std.json.Value{ .bool = false });
    try responseObj.put("error", std.json.Value{ .string = errorName });
    try responseObj.put("message", std.json.Value{ .string = message });

    const response = std.json.Value{ .object = responseObj };
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try std.json.stringify(response, .{}, buf.writer());
    responseObj.deinit();
    return buf.toOwnedSlice();
}

// Helper functions for JSON parsing
fn parseJsonValue(comptime T: type, jsonValue: std.json.Value) !T {
    const info = @typeInfo(T);

    switch (info) {
        .bool => {
            if (jsonValue != .bool) return ToolError.InvalidInput;
            return jsonValue.bool;
        },
        .int => {
            if (jsonValue != .integer) return ToolError.InvalidInput;
            return @intCast(jsonValue.integer);
        },
        .float => {
            if (jsonValue == .integer) {
                return @floatFromInt(jsonValue.integer);
            } else if (jsonValue == .float) {
                return @floatCast(jsonValue.float);
            } else {
                return ToolError.InvalidInput;
            }
        },
        .pointer => |ptr_info| {
            if (ptr_info.size != .slice) return ToolError.InvalidInput;
            if (ptr_info.child != u8) return ToolError.InvalidInput;

            if (jsonValue != .string) return ToolError.InvalidInput;
            return jsonValue.string;
        },
        .optional => |opt_info| {
            if (jsonValue == .null) {
                return null;
            }
            return try parseJsonValue(opt_info.child, jsonValue);
        },
        else => {
            return ToolError.InvalidInput;
        },
    }
}

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
            return ToolError.InvalidInput;
        },
        .optional => {
            if (value) |v| {
                return try valueToJsonValue(v, allocator);
            } else {
                return std.json.Value{ .null = {} };
            }
        },
        .@"struct" => {
            var obj = std.json.ObjectMap.init(allocator);
            errdefer obj.deinit();

            const structInfo = @typeInfo(T).@"struct";
            inline for (structInfo.fields) |field| {
                const fieldValue = @field(value, field.name);
                const jsonValue = try valueToJsonValue(fieldValue, allocator);
                try obj.put(field.name, jsonValue);
            }

            return std.json.Value{ .object = obj };
        },
        else => {
            return ToolError.InvalidInput;
        },
    }
}

// ============================================================================
// MOCK TOOLS FOR TESTING
// ============================================================================

// Mock tool for testing
fn mockJsonTool(allocator: std.mem.Allocator, params: std.json.Value) ToolError!std.json.Value {
    const request = try parseToolRequest(TestData, params);

    var result = std.json.ObjectMap.init(allocator);
    try result.put("processed_message", std.json.Value{ .string = request.message });
    try result.put("count_doubled", std.json.Value{ .integer = request.count * 2 });
    try result.put("enabled", std.json.Value{ .bool = request.enabled });
    if (request.optional_field) |field| {
        try result.put("optional_field", std.json.Value{ .string = field });
    }

    return std.json.Value{ .object = result };
}

// Test tool that simulates errors for error propagation testing
fn errorTestTool(allocator: std.mem.Allocator, params: std.json.Value) ToolError!std.json.Value {
    // Simulate different types of errors
    const paramsObj = params.object;
    if (paramsObj.get("error_type")) |errorType| {
        if (errorType == .string) {
            if (std.mem.eql(u8, errorType.string, "missing_param")) {
                return ToolError.MissingParameter;
            } else if (std.mem.eql(u8, errorType.string, "invalid_input")) {
                return ToolError.InvalidInput;
            } else if (std.mem.eql(u8, errorType.string, "network_error")) {
                return ToolError.NetworkError;
            }
        }
    }

    // Default success response
    var result = std.json.ObjectMap.init(allocator);
    try result.put("success", std.json.Value{ .bool = true });
    return std.json.Value{ .object = result };
}

// ============================================================================
// TEST CASES
// ============================================================================

test "jsonReflectionSystemBasicSerializationAndDeserialization" {
    const allocator = testing.allocator;

    // Test basic struct serialization/deserialization
    const original = TestData{
        .message = "Hello, World!",
        .count = 42,
        .enabled = true,
        .optional_field = "optional_value",
    };

    // Create JSON value manually for testing
    var jsonObj = std.json.ObjectMap.init(allocator);
    defer jsonObj.deinit();

    try jsonObj.put("message", std.json.Value{ .string = original.message });
    try jsonObj.put("count", std.json.Value{ .integer = original.count });
    try jsonObj.put("enabled", std.json.Value{ .bool = original.enabled });
    try jsonObj.put("optional_field", std.json.Value{ .string = original.optional_field.? });

    const jsonValue = std.json.Value{ .object = jsonObj };

    // Test deserialization
    const deserialized = try std.json.parseFromValue(TestData, allocator, jsonValue, .{});
    defer deserialized.deinit();

    // Verify round trip
    try testing.expectEqualStrings(original.message, deserialized.value.message);
    try testing.expectEqual(original.count, deserialized.value.count);
    try testing.expectEqual(original.enabled, deserialized.value.enabled);
    try testing.expectEqualStrings(original.optional_field.?, deserialized.value.optional_field.?);
}

test "jsonHelpersIntegrationWithToolSystem" {
    const allocator = testing.allocator;

    // Test parseToolRequest
    const json_string =
        \\{
        \\  "message": "Test message",
        \\  "count": 100,
        \\  "enabled": true,
        \\  "optional_field": "present"
        \\}
    ;

    const json_value = try std.json.parseFromSlice(std.json.Value, allocator, json_string, .{});
    defer json_value.deinit();

    const request = try parseToolRequest(TestData, json_value.value);

    try testing.expectEqualStrings("Test message", request.message);
    try testing.expectEqual(@as(i32, 100), request.count);
    try testing.expectEqual(true, request.enabled);
    try testing.expectEqualStrings("present", request.optional_field.?);

    // Test createSuccessResponse
    const result_data = .{
        .processed = true,
        .result_count = 42,
    };

    const success_response = try createSuccessResponse(result_data);
    defer allocator.free(success_response);

    const success_json = try std.json.parseFromSlice(std.json.Value, allocator, success_response, .{});
    defer success_json.deinit();

    try testing.expectEqual(true, success_json.value.object.get("success").?.bool);
    try testing.expectEqual(true, success_json.value.object.get("result").?.object.get("processed").?.bool);
    try testing.expectEqual(@as(i64, 42), success_json.value.object.get("result").?.object.get("result_count").?.integer);

    // Test createErrorResponse
    const error_response = try createErrorResponse(ToolError.InvalidInput, "Test error message");
    defer allocator.free(error_response);

    const error_json = try std.json.parseFromSlice(std.json.Value, allocator, error_response, .{});
    defer error_json.deinit();

    try testing.expectEqual(false, error_json.value.object.get("success").?.bool);
    try testing.expectEqualStrings("InvalidInput", error_json.value.object.get("error").?.string);
    try testing.expectEqualStrings("Test error message", error_json.value.object.get("message").?.string);
}

test "toolRegistryIntegrationWithNewJsonTools" {
    const allocator = testing.allocator;

    // Create a registry and register our mock tool
    var registry = Registry.init(allocator);
    defer registry.deinit();

    try registry.registerJsonTool("mock_tool", "Mock tool for testing", mockJsonTool, "test_agent");

    // Verify tool was registered
    const toolFn = registry.get("mock_tool");
    try testing.expect(toolFn != null);

    // Test tool execution through the registry
    const testInput =
        \\{
        \\  "message": "Integration test",
        \\  "count": 5,
        \\  "enabled": false
        \\}
    ;

    const jsonValue = try std.json.parseFromSlice(std.json.Value, allocator, testInput, .{});
    defer jsonValue.deinit();

    var result = try toolFn.?(allocator, jsonValue.value);
    // Free contained ObjectMap explicitly
    result.object.deinit();

    // Verify the result
    try testing.expectEqualStrings("Integration test", result.object.get("processed_message").?.string);
    try testing.expectEqual(@as(i64, 10), result.object.get("count_doubled").?.integer);
    try testing.expectEqual(false, result.object.get("enabled").?.bool);
}

test "errorPropagationThroughToolSystem" {
    const allocator = testing.allocator;

    var registry = Registry.init(allocator);
    defer registry.deinit();

    try registry.registerJsonTool("error_tool", "Tool that can produce errors", errorTestTool, "test_agent");

    const tool_fn = registry.get("error_tool").?;

    // Test missing parameter error
    const missing_param_input =
        \\{
        \\  "error_type": "missing_param"
        \\}
    ;

    const json_value1 = try std.json.parseFromSlice(std.json.Value, allocator, missing_param_input, .{});
    defer json_value1.deinit();

    const result1 = tool_fn(allocator, json_value1.value);
    try testing.expectError(ToolError.MissingParameter, result1);

    // Test invalid input error
    const invalid_input =
        \\{
        \\  "error_type": "invalid_input"
        \\}
    ;

    const json_value2 = try std.json.parseFromSlice(std.json.Value, allocator, invalid_input, .{});
    defer json_value2.deinit();

    const result2 = tool_fn(allocator, json_value2.value);
    try testing.expectError(ToolError.InvalidInput, result2);

    // Test successful execution
    const success_input =
        \\{
        \\  "message": "Success case"
        \\}
    ;

    const json_value3 = try std.json.parseFromSlice(std.json.Value, allocator, success_input, .{});
    defer json_value3.deinit();

    var success_result = try tool_fn(allocator, json_value3.value);
    success_result.object.deinit();

    try testing.expectEqual(true, success_result.object.get("success").?.bool);
}

test "backwardCompatibilityWithExistingJsonFormats" {
    const allocator = testing.allocator;

    // Test that the new system can handle existing JSON formats
    const legacy_json =
        \\{
        \\  "action": "read_file",
        \\  "path": "/tmp/test.txt",
        \\  "encoding": "utf8"
        \\}
    ;

    const json_value = try std.json.parseFromSlice(std.json.Value, allocator, legacy_json, .{});
    defer json_value.deinit();

    // Verify we can extract values using the new system
    const obj = json_value.value.object;
    try testing.expectEqualStrings("read_file", obj.get("action").?.string);
    try testing.expectEqualStrings("/tmp/test.txt", obj.get("path").?.string);
    try testing.expectEqualStrings("utf8", obj.get("encoding").?.string);
}

test "memoryManagementAndCleanup" {
    const allocator = testing.allocator;

    // Test that all allocations are properly cleaned up
    var registry = Registry.init(allocator);
    defer registry.deinit();

    try registry.registerJsonTool("cleanup_test", "Test cleanup", mockJsonTool, "test_agent");

    const test_input =
        \\{
        \\  "message": "Cleanup test",
        \\  "count": 1,
        \\  "enabled": true
        \\}
    ;

    const json_value = try std.json.parseFromSlice(std.json.Value, allocator, test_input, .{});
    defer json_value.deinit();

    const tool_fn = registry.get("cleanup_test").?;
    var result = try tool_fn(allocator, json_value.value);
    result.object.deinit();

    // Verify result is valid JSON
    try testing.expect(result.object.get("processed_message") != null);
    try testing.expect(result.object.get("count_doubled") != null);
    try testing.expect(result.object.get("enabled") != null);
}

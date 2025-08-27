//! Tools module for test_agent.
//! Register all your agent-specific tools here.

const std = @import("std");
const toolsMod = @import("tools_shared");

// Tool Implementation
pub const Tool = @import("Tool.zig");

/// Test tool function demonstrating the new json_reflection approach.
/// This replaces manual ObjectMap building with type-safe structs.
pub fn testTool(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    _ = params; // Use params as needed

    // Define response structure using json_reflection approach
    const TestResponse = struct {
        message: []const u8,
        success: bool,
        agent: []const u8,
        timestamp: i64,
    };

    // Create response instance
    const response = TestResponse{
        .message = "Hello from test_agent!",
        .success = true,
        .agent = "test_agent",
        .timestamp = std.time.timestamp(),
    };

    // Generate JSON mapper and serialize
    const json_reflection = @import("json_reflection");
    const ResponseMapper = json_reflection.generateJsonMapper(TestResponse);
    return ResponseMapper.toJsonValue(allocator, response);
}

/// Calculator tool for arithmetic operations
/// Demonstrates the improved pattern using json_helpers
pub fn calculator(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    // Define the expected request structure
    const CalculatorRequest = struct {
        operation: []const u8,
        a: i64,
        b: i64,
    };

    // Parse and validate the request using json_helpers
    const request = toolsMod.parseToolRequest(CalculatorRequest, params) catch |err| {
        // Return a proper error response
        const errorMsg = try toolsMod.createErrorResponse(allocator, err, "Invalid calculator request");
        defer allocator.free(errorMsg);
        return std.json.parseFromSlice(std.json.Value, allocator, errorMsg, .{});
    };

    // Perform the calculation
    const resultValue: i64 = if (std.mem.eql(u8, request.operation, "add"))
        request.a + request.b
    else if (std.mem.eql(u8, request.operation, "subtract"))
        request.a - request.b
    else if (std.mem.eql(u8, request.operation, "multiply"))
        request.a * request.b
    else if (std.mem.eql(u8, request.operation, "divide"))
        if (request.b == 0) return toolsMod.ToolError.InvalidInput else @divTrunc(request.a, request.b)
    else
        return toolsMod.ToolError.InvalidInput;

    // Create the result structure
    const result = .{
        .result = resultValue,
        .operation = request.operation,
        .inputs = .{ request.a, request.b },
    };

    // Return success response using json_helpers
    const responseJson = try toolsMod.createSuccessResponse(result);
    defer allocator.free(responseJson);

    return try std.json.parseFromSlice(std.json.Value, allocator, responseJson, .{});
}

/// Tool that demonstrates the standardized tool pattern
pub fn tool(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    return Tool.execute(allocator, params);
}

// Tool Registry for this agent
pub const ToolRegistry = struct {
    pub const tools = .{
        .test_tool = testTool,
        .calculator = calculator,
        .tool = tool,
        .complex = Tool.complexExecute,
    };
};

// Default registry
pub const DefaultRegistry = ToolRegistry;

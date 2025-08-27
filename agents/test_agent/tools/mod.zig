//! Tools module for test_agent.
//! Register all your agent-specific tools here.

const std = @import("std");
const tools_mod = @import("tools_shared");

// Example Tool Implementation
pub const Example = @import("example_tool.zig");

// Test tool function that demonstrates basic functionality
pub fn testTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    _ = params; // Use params as needed

    var result = std.json.ObjectMap.init(allocator);
    try result.put("message", std.json.Value{ .string = "Hello from test_agent!" });
    try result.put("success", std.json.Value{ .bool = true });
    try result.put("agent", std.json.Value{ .string = "test_agent" });

    return std.json.Value{ .object = result };
}

/// Calculator tool for basic arithmetic operations
pub fn calculator(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    const params_obj = params.object;

    const operation = params_obj.get("operation") orelse return tools_mod.ToolError.MissingParameter;
    const firstNumber = params_obj.get("a") orelse return tools_mod.ToolError.MissingParameter;
    const secondNumber = params_obj.get("b") orelse return tools_mod.ToolError.MissingParameter;

    if (operation != .string or firstNumber != .integer or secondNumber != .integer) {
        return tools_mod.ToolError.InvalidInput;
    }

    const operationString = operation.string;
    const x = firstNumber.integer;
    const y = secondNumber.integer;

    const resultValue: i64 = if (std.mem.eql(u8, operationString, "add"))
        x + y
    else if (std.mem.eql(u8, operationString, "subtract"))
        x - y
    else if (std.mem.eql(u8, operationString, "multiply"))
        x * y
    else if (std.mem.eql(u8, operationString, "divide"))
        if (y == 0) return tools_mod.ToolError.InvalidInput else @divTrunc(x, y)
    else
        return tools_mod.ToolError.InvalidInput;

    var result = std.json.ObjectMap.init(allocator);
    try result.put("result", std.json.Value{ .integer = resultValue });
    try result.put("operation", std.json.Value{ .string = operationString });
    try result.put("inputs", std.json.Value{ .array = std.json.Array.init(allocator) });
    try result.put("success", std.json.Value{ .bool = true });

    return std.json.Value{ .object = result };
}

/// Example tool that demonstrates the standardized tool pattern
pub fn exampleTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    return Example.execute(allocator, params);
}

// Tool Registry for this agent
pub const ToolRegistry = struct {
    pub const TOOLS = .{
        .test_tool = testTool,
        .calculator = calculator,
        .example_tool = exampleTool,
    };
};

// Default registry
pub const DefaultRegistry = ToolRegistry;

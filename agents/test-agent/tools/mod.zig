//! Tools module for test-agent.
//! Register all your agent-specific tools here.

const std = @import("std");
const tools_mod = @import("tools_shared");

// Example Tool Implementation
pub const ExampleTool = @import("ExampleTool.zig");

// Test tool function that demonstrates basic functionality
pub fn testTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    _ = params; // Use params as needed

    var result = std.json.ObjectMap.init(allocator);
    try result.put("message", std.json.Value{ .string = "Hello from test-agent!" });
    try result.put("success", std.json.Value{ .bool = true });
    try result.put("agent", std.json.Value{ .string = "test-agent" });

    return std.json.Value{ .object = result };
}

/// Calculator tool for basic arithmetic operations
pub fn calculator(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    const params_obj = params.object;

    const operation = params_obj.get("operation") orelse return tools_mod.ToolError.MissingParameter;
    const a = params_obj.get("a") orelse return tools_mod.ToolError.MissingParameter;
    const b = params_obj.get("b") orelse return tools_mod.ToolError.MissingParameter;

    if (operation != .string or a != .integer or b != .integer) {
        return tools_mod.ToolError.InvalidInput;
    }

    const op = operation.string;
    const x = a.integer;
    const y = b.integer;

    const result_value: i64 = if (std.mem.eql(u8, op, "add"))
        x + y
    else if (std.mem.eql(u8, op, "subtract"))
        x - y
    else if (std.mem.eql(u8, op, "multiply"))
        x * y
    else if (std.mem.eql(u8, op, "divide"))
        if (y == 0) return tools_mod.ToolError.InvalidInput else @divTrunc(x, y)
    else
        return tools_mod.ToolError.InvalidInput;

    var result = std.json.ObjectMap.init(allocator);
    try result.put("result", std.json.Value{ .integer = result_value });
    try result.put("operation", std.json.Value{ .string = op });
    try result.put("inputs", std.json.Value{ .array = std.json.Array.init(allocator) });
    try result.put("success", std.json.Value{ .bool = true });

    return std.json.Value{ .object = result };
}

/// Example tool that demonstrates the standardized tool pattern
pub fn exampleTool(allocator: std.mem.Allocator, params: std.json.Value) tools_mod.ToolError!std.json.Value {
    return ExampleTool.execute(allocator, params);
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

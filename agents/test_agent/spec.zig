//! Agent spec for test_agent. Provides system prompt and tools registration.

const std = @import("std");
const engine = @import("core_engine");
const AgentSpec = engine.AgentSpec;
const impl = @import("agent.zig");
const toolsMod = @import("tools_shared");

fn buildSystemPromptImpl(allocator: std.mem.Allocator, options: engine.CliOptions) ![]const u8 {
    _ = options; // reserved for future use (e.g., config path)

    var agent = try impl.Test.initFromConfig(allocator);
    defer agent.deinit();

    return agent.loadSystemPrompt();
}

fn registerToolsImpl(registry: *toolsMod.Registry) !void {
    // Register test_agent-specific tools using the new system
    const tools = @import("tools/mod.zig");

    // Register tools individually with metadata
    try toolsMod.registerJsonTool(registry, "test_tool", "Test tool that demonstrates agent functionality", tools.testTool, "test_agent");
    try toolsMod.registerJsonTool(registry, "calculator", "Calculator for arithmetic operations (add, subtract, multiply, divide)", tools.calculator, "test_agent");
    try toolsMod.registerJsonTool(registry, "tool", "Tool that demonstrates standardized tool patterns with JSON parameters", tools.tool, "test_agent");
    try toolsMod.registerJsonTool(registry, "complex", "Complex tool demonstrating JSON reflection patterns with nested structures", tools.tool, "test_agent");
}

pub const SPEC: AgentSpec = .{
    .buildSystemPrompt = buildSystemPromptImpl,
    .registerTools = registerToolsImpl,
};

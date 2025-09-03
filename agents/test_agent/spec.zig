//! Agent spec for test_agent. Provides system prompt and tools registration.

const std = @import("std");
const engine = @import("core_engine");
const AgentSpec = engine.AgentSpec;
const impl = @import("agent.zig");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

fn buildSystemPrompt(allocator: std.mem.Allocator, options: engine.CliOptions) ![]const u8 {
    _ = options; // reserved for future use (e.g., config path)

    var agent = try impl.Test.initFromConfig(allocator);
    defer agent.deinit();

    return agent.loadSystemPrompt();
}

fn registerTools(registry: *toolsMod.Registry) !void {
    // Register test_agent-specific tools using the new system
    const tools = @import("tools.zig");

    // Register tools individually with metadata
    try toolsMod.registerJsonTool(registry, "test_tool", "Test tool that demonstrates agent functionality", tools.testTool, "test_agent");
    try toolsMod.registerJsonTool(registry, "calculator", "Calculator for arithmetic operations (add, subtract, multiply, divide)", tools.calculator, "test_agent");
    try toolsMod.registerJsonTool(registry, "execute", "Tool that demonstrates standardized tool patterns with JSON parameters", tools.execute, "test_agent");
}

pub const SPEC: AgentSpec = .{
    .buildSystemPrompt = buildSystemPrompt,
    .registerTools = registerTools,
};

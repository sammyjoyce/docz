//! Agent spec for test-agent. Provides system prompt and tools registration.

const std = @import("std");
const engine = @import("core_engine");
const impl = @import("Agent.zig");
const tools_mod = @import("tools_shared");

fn buildSystemPromptImpl(allocator: std.mem.Allocator, options: engine.CliOptions) ![]const u8 {
    _ = options; // reserved for future use (e.g., config path)

    var agent = try impl.TestAgent.initFromConfig(allocator);
    defer agent.deinit();

    return agent.loadSystemPrompt();
}

fn registerToolsImpl(registry: *tools_mod.Registry) !void {
    // Register test-agent-specific tools using the new system
    const tools = @import("tools/mod.zig");

    // Register tools individually with metadata
    try tools_mod.registerJSONTool(registry, "test_tool", "Basic test tool that demonstrates agent functionality", tools.testTool, "test-agent");
    try tools_mod.registerJSONTool(registry, "calculator", "Basic calculator for arithmetic operations (add, subtract, multiply, divide)", tools.calculator, "test-agent");
    try tools_mod.registerJSONTool(registry, "example_tool", "Example tool that demonstrates standardized tool patterns with JSON parameters", tools.exampleTool, "test-agent");
}

pub const SPEC: engine.AgentSpec = .{
    .buildSystemPrompt = buildSystemPromptImpl,
    .registerTools = registerToolsImpl,
};

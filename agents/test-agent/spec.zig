//! Agent spec for template agent. Provides system prompt and tools registration.

const std = @import("std");
const engine = @import("core_engine");
const impl = @import("agent.zig");
const tools_mod = @import("tools_shared");

fn buildSystemPromptImpl(allocator: std.mem.Allocator, options: engine.CliOptions) ![]const u8 {
    _ = options; // reserved for future use (e.g., config path)

    var agent = impl.Agent.init(allocator, .{});
    defer agent.deinit();

    return agent.loadSystemPrompt();
}

fn registerToolsImpl(registry: *tools_mod.Registry) !void {
    // Register agent-specific tools here
    const tools = @import("tools/mod.zig");
    try tools.registerAll(registry);
}

pub const SPEC: engine.AgentSpec = .{
    .buildSystemPrompt = buildSystemPromptImpl,
    .registerTools = registerToolsImpl,
};

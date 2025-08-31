// AgentSpec for the Markdown agent. Supplies system prompt and tools registration.

const std = @import("std");
const engine = @import("core_engine");
const impl = @import("agent.zig");
const foundation = @import("foundation");
const tools_mod = foundation.tools;

fn buildSystemPromptImpl(allocator: std.mem.Allocator, options: engine.CliOptions) ![]const u8 {
    _ = options; // reserved for future use (e.g., config path)

    var agent = try impl.Markdown.initFromConfig(allocator);
    defer agent.deinit();

    return agent.loadSystemPrompt();
}

fn registerToolsImpl(registry: *tools_mod.Registry) !void {
    _ = registry; // Tools disabled for minimal auth setup build
}

pub const SPEC: engine.AgentSpec = .{
    .buildSystemPrompt = buildSystemPromptImpl,
    .registerTools = registerToolsImpl,
};

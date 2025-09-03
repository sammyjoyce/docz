//! Simple agent specification

const std = @import("std");
const engine = @import("core_engine");
const foundation = @import("foundation");
const tools = foundation.tools;

fn buildSystemPromptSimple(allocator: std.mem.Allocator, opts: engine.CliOptions) ![]const u8 {
    _ = opts;
    return allocator.dupe(u8,
        \\You are a helpful AI assistant powered by Claude.
        \\Respond concisely and accurately to user queries.
    );
}

fn registerToolsSimple(registry: *tools.Registry) !void {
    // No custom tools for simple agent
    _ = registry;
}

pub const SPEC: engine.AgentSpec = .{
    .buildSystemPrompt = buildSystemPromptSimple,
    .registerTools = registerToolsSimple,
};

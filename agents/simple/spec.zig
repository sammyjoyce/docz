//! Simple agent specification

const std = @import("std");
const engine = @import("../../src/engine.zig");
const tools = @import("../../src/foundation/tools.zig");

fn buildSystemPromptImpl(allocator: std.mem.Allocator, opts: engine.CliOptions) ![]const u8 {
    _ = opts;
    return allocator.dupe(u8,
        \\You are a helpful AI assistant powered by Claude.
        \\Respond concisely and accurately to user queries.
    );
}

fn registerToolsImpl(registry: *tools.Registry) !void {
    // No custom tools for simple agent
    _ = registry;
}

pub const SPEC: engine.AgentSpec = .{
    .buildSystemPrompt = buildSystemPromptImpl,
    .registerTools = registerToolsImpl,
};

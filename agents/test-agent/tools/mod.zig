//! Tools module for template agent.
//! Register all your agent-specific tools here.

const std = @import("std");
const tools_mod = @import("tools_shared");
const ExampleTool = @import("example_tool.zig");

/// Register all tools provided by this agent
pub fn registerAll(registry: *tools_mod.Registry) !void {
    try registry.register("example_tool", ExampleTool.execute);

    // Register additional tools here:
    // try registry.register("my_tool", MyTool.execute);
}

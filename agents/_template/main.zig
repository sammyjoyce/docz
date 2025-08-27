//! Template agent entry point using the simplified agent_main.runAgent() pattern.
//!
//! This demonstrates the recommended approach for new agents:
//! - Uses agent_main.runAgent() for standardized CLI handling
//! - Eliminates boilerplate CLI parsing code
//! - Provides consistent behavior across all agents
//! - Automatically handles built-in commands (help, version, auth, etc.)

const std = @import("std");
const agent_main = @import("core_agent_main");
const spec = @import("spec.zig");

pub fn main() !void {
    // Create a general-purpose allocator for the agent
    // In production, you might want to use a more sophisticated allocator
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    // Use the simplified agent_main.runAgent() function
    // This handles all CLI parsing, built-in commands, and engine delegation
    // The agent specification (spec.SPEC) defines how this agent works
    return agent_main.runAgent(allocator, spec.SPEC);
}

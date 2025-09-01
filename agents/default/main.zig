//! Default agent entry point using the simplified agent_main.runAgent() pattern.
//!
//! This provides a basic REPL agent with OAuth support.

const std = @import("std");
const agentMain = @import("../../src/foundation/agent_main.zig");
const spec = @import("spec.zig");

pub fn main() !void {
    // Create a general-purpose allocator for the agent
    var gpaState = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpaState.deinit();
    const allocator = gpaState.allocator();

    // Use the simplified agentMain.runAgent() function
    // This handles all CLI parsing, built-in commands, and engine delegation
    return agentMain.runAgent(allocator, spec.SPEC);
}
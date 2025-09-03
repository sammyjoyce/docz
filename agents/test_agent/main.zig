const std = @import("std");
const agentMain = @import("foundation").agent_main;
const spec = @import("spec.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Use the standardized agentMain.runAgent() which handles CLI parsing and orchestration
    try agentMain.runAgent(allocator, spec.SPEC);
}

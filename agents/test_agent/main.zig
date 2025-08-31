const std = @import("std");
const agentMain = @import("foundation").agent_main;
const spec = @import("spec.zig");

pub fn main() !void {
    var gpaState: std.heap.DebugAllocator(.{}) = .init;
    const gpa = gpaState.allocator();
    defer if (gpaState.deinit() == .leak) {
        std.log.err("Memory leak detected", .{});
    };

    // Use the standardized agentMain.runAgent() which handles CLI parsing and orchestration
    try agentMain.runAgent(gpa, spec.SPEC);
}

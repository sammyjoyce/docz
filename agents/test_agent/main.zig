const std = @import("std");
const agent_main = @import("agent_main");
const spec = @import("spec.zig");

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    const gpa = gpa_state.allocator();
    defer if (gpa_state.deinit() == .leak) {
        std.log.err("Memory leak detected", .{});
    };

    // Use the standardized agent_main.runAgent() which handles CLI parsing and orchestration
    try agent_main.runAgent(gpa, spec.SPEC);
}

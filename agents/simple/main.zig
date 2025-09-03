//! Simple test agent entry point

const std = @import("std");
const foundation = @import("foundation");
const spec = @import("spec.zig");

pub fn main() !void {
    var gpaState: std.heap.DebugAllocator(.{}) = .init;
    const gpa = gpaState.allocator();
    defer if (gpaState.deinit() == .leak) {
        std.log.err("Memory leak detected", .{});
    };

    try foundation.agent_main.runAgent(gpa, spec.SPEC);
}

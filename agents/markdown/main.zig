const std = @import("std");
const foundation = @import("foundation");
const engine = @import("core_engine");
const spec = @import("spec.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    try foundation.agent_main.runAgent(engine, gpa.allocator(), spec.SPEC);
}

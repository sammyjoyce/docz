const std = @import("std");
const agent_main = @import("agent_main");
const spec = @import("spec.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    try agent_main.runAgent(gpa.allocator(), spec.SPEC);
}

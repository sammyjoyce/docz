//! Simple test agent entry point

const std = @import("std");
const foundation = @import("../../src/foundation.zig");
const spec = @import("spec.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    try foundation.agent_main.runAgent(gpa.allocator(), spec.SPEC);
}

//! AMP agent entry point using the shared foundation runner.
//! Aligns with repository standard: delegate to `foundation.agent_main.runAgent(core_engine, …)`.

const std = @import("std");
const engine = @import("core_engine");
const spec = @import("spec.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Delegate CLI handling and engine orchestration to the shared entry.
    return @import("foundation").agent_main.runAgent(engine, alloc, spec.SPEC);
}

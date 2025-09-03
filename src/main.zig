//! Main entry point for the Docz CLI application
//! Handles OAuth authentication and agent REPL functionality

const std = @import("std");
const foundation = @import("foundation.zig");
const cli = foundation.cli;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    _ = try cli.main(allocator, args[1..]);
}



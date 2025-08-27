//! Main entry point for the CLI with Graphics Dashboard
//! Demonstrates the CLI architecture and progressive enhancement capabilities

const std = @import("std");
const cli_mod = @import("components/cli.zig");

const Allocator = std.mem.Allocator;
const Cli = cli_mod.Cli;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Initialize CLI
    var cli = try Cli.init(allocator);
    defer cli.deinit();

    // Run CLI and get exit code
    const exit_code = try cli.run(args);
    std.process.exit(exit_code);
}

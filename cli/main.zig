//! Main entry point for the Enhanced CLI with Graphics Dashboard
//! Demonstrates the unified CLI architecture and progressive enhancement capabilities

const std = @import("std");
const enhanced_cli = @import("components/enhanced_cli.zig");

const Allocator = std.mem.Allocator;
const EnhancedCLI = enhanced_cli.EnhancedCLI;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Initialize enhanced CLI
    var cli = try EnhancedCLI.init(allocator);
    defer cli.deinit();

    // Run CLI and get exit code
    const exit_code = try cli.run(args);
    std.process.exit(exit_code);
}

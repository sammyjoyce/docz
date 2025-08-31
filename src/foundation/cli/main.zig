//! CLI Entry Point
//! Single entry point that replaces the multiple CLI implementations

const std = @import("std");
const cli = @import("mod.zig");

/// Main entry point for the CLI
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Skip program name
    const cli_args = if (args.len > 1) args[1..] else &[_][]const u8{};

    // Initialize and run the CLI app
    var app = cli.CliApp.init(allocator) catch |err| {
        std.log.err("Failed to initialize CLI: {}", .{err});
        std.process.exit(1);
    };
    defer app.deinit();

    // Execute the command
    const exit_code = app.run(cli_args) catch |err| {
        std.log.err("CLI execution failed: {}", .{err});
        return err;
    };

    std.process.exit(exit_code);
}

/// Entry point that can be called from other modules
pub fn runCli(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    var app = try cli.CliApp.init(allocator);
    defer app.deinit();
    return try app.run(args);
}

/// Compatibility function for existing code
pub fn legacyMain(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const exit_code = try runCli(allocator, args);
    if (exit_code != 0) {
        std.process.exit(exit_code);
    }
}

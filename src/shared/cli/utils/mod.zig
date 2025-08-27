//! CLI utilities module
//! Shared utilities for CLI operations

const std = @import("std");

// For now, provide basic utilities
pub fn printVersion() void {
    const stdout = std.fs.File.stdout().writer();
    stdout.print("DocZ v0.1.0\n", .{}) catch {};
}

pub fn printHelp() void {
    const stdout = std.fs.File.stdout().writer();
    stdout.print("DocZ - Elegant terminal AI assistant\n", .{}) catch {};
    stdout.print("Run 'docz --help' for detailed usage information.\n", .{}) catch {};
}

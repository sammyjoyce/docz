//! CLI utilities module
//! Shared utilities for CLI operations

const std = @import("std");

// Export hyperlink utilities
pub const hyperlinks = @import("hyperlinks.zig");

// For now, provide basic utilities
pub fn printVersion() void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    stdout_writer.print("DocZ v0.1.0\n", .{}) catch {};
    stdout_writer.flush() catch {};
}

pub fn printHelp() void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    stdout_writer.print("DocZ - Elegant terminal AI assistant\n", .{}) catch {};
    stdout_writer.print("Run 'docz --help' for detailed usage information.\n", .{}) catch {};
    stdout_writer.flush() catch {};
}

//! Terminal writer utilities for printing to stdout with ANSI support

const std = @import("std");

/// Global writer instance for stdout
pub var writer: Writer = undefined;

/// Writer struct for terminal output
pub const Writer = struct {
    stdout: std.fs.File.Writer,

    /// Initialize the global writer
    pub fn init() void {
        writer = Writer{
            .stdout = std.io.getStdOut().writer(),
        };
    }

    /// Deinitialize the global writer
    pub fn deinit() void {
        writer.stdout = undefined;
    }

    /// Print formatted text to stdout
    pub fn print(comptime fmt: []const u8, args: anytype) void {
        writer.stdout.print(fmt, args) catch {};
    }

    /// Print text to stdout
    pub fn writeAll(text: []const u8) void {
        writer.stdout.writeAll(text) catch {};
    }

    /// Flush the writer
    pub fn flush() void {
        writer.stdout.flush() catch {};
    }
};

/// Print formatted text to stdout (convenience function)
pub fn print(comptime fmt: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(fmt, args) catch {};
}

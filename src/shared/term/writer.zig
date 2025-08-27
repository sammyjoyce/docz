//! Terminal writer utilities for printing to stdout with ANSI support

const std = @import("std");

/// Global writer instance for stdout
pub var writer: Writer = undefined;

/// Writer struct for terminal output with caller-owned buffer
pub const Writer = struct {
    stdout: std.fs.File,
    buffer: [4096]u8 = undefined,
    end: usize = 0,

    /// Initialize the global writer
    pub fn init() void {
        writer = Writer{
            .stdout = std.io.getStdOut(),
        };
    }

    /// Deinitialize the global writer
    pub fn deinit() void {
        writer.flush();
    }

    /// Print formatted text to stdout
    pub fn print(comptime fmt: []const u8, args: anytype) void {
        const formatted = std.fmt.bufPrint(&writer.buffer, fmt, args) catch {
            // If formatting fails, try direct write with a temporary buffer
            var temp_buffer: [4096]u8 = undefined;
            const temp_formatted = std.fmt.bufPrint(&temp_buffer, fmt, args) catch return;
            writer.stdout.writeAll(temp_formatted) catch {};
            return;
        };
        writer.writeAll(formatted);
    }

    /// Print text to stdout
    pub fn writeAll(text: []const u8) void {
        // If we have space in buffer, add to it
        if (writer.end + text.len <= writer.buffer.len) {
            @memcpy(writer.buffer[writer.end .. writer.end + text.len], text);
            writer.end += text.len;
        } else {
            // Flush buffer first, then write directly
            writer.flush();
            writer.stdout.writeAll(text) catch {};
        }
    }

    /// Flush the writer
    pub fn flush() void {
        if (writer.end > 0) {
            writer.stdout.writeAll(writer.buffer[0..writer.end]) catch {};
            writer.end = 0;
        }
    }
};

/// Print formatted text to stdout (convenience function)
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buffer: [4096]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buffer, fmt, args) catch {
        // If formatting fails, write directly with a temporary buffer
        var temp_buffer: [4096]u8 = undefined;
        const temp_formatted = std.fmt.bufPrint(&temp_buffer, fmt, args) catch return;
        const stdout = std.io.getStdOut();
        stdout.writeAll(temp_formatted) catch {};
        return;
    };
    const stdout = std.io.getStdOut();
    stdout.writeAll(formatted) catch {};
}

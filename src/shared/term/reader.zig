//! Terminal reader utilities for reading input from stdin

const std = @import("std");

/// Global reader instance for stdin
pub var reader: Reader = undefined;

/// Reader struct for terminal input
pub const Reader = struct {
    stdin: std.fs.File.Reader,

    /// Initialize the global reader
    pub fn init() void {
        reader = Reader{
            .stdin = std.io.getStdIn().reader(),
        };
    }

    /// Deinitialize the global reader
    pub fn deinit() void {
        reader.stdin = undefined;
    }

    /// Read a single key from stdin
    pub fn readKey() !u8 {
        var buffer: [1]u8 = undefined;
        const bytes_read = try reader.stdin.read(&buffer);
        if (bytes_read == 0) return error.EndOfStream;
        return buffer[0];
    }

    /// Read a line from stdin
    pub fn readLine(allocator: std.mem.Allocator) ![]u8 {
        return reader.stdin.readUntilDelimiterAlloc(allocator, '\n', 1024);
    }
};

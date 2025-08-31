const std = @import("std");

/// Logger interface: function pointer accepting format string and arguments
pub const Logger = *const fn ([]const u8, anytype) void;

/// Default logger that wraps std.debug.print
pub fn defaultLogger(fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

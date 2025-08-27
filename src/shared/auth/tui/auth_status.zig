const std = @import("std");

/// Print function for TUI output
fn print(comptime fmt: []const u8, args: anytype) void {
    const formatted = std.fmt.allocPrint(std.heap.page_allocator, fmt, args) catch return;
    defer std.heap.page_allocator.free(formatted);
    const stdout = std.fs.File.stdout();
    stdout.writeAll(formatted) catch {};
}

/// Run the auth status display
pub fn run(allocator: std.mem.Allocator) !void {
    try display(allocator);
}

/// Display current authentication status with TUI formatting
pub fn display(allocator: std.mem.Allocator) !void {
    _ = allocator;
    print("❌ Anthropic module not available (network access disabled)\n", .{});
    print("   This agent does not support network operations.\n\n", .{});
    return;
}

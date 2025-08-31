//! CLI Demo
//! Demonstrates the unified CliApp entry surface

const std = @import("std");
const cli = @import("../cli.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.fs.File.stdout().writer();
    try stdout.print("=== Unified CLI Demo ===\n\n", .{});

    var app = try cli.CliApp.init(allocator);
    defer app.deinit();

    try stdout.print("✓ CLI application initialized\n", .{});
    try stdout.print("Terminal: {s}\n\n", .{app.state.capabilitySummary()});

    // Demo 1: Help
    _ = try app.run(&[_][]const u8{"help"});

    // Demo 2: Auth status
    _ = try app.run(&[_][]const u8{ "auth", "status" });

    try stdout.print("\n=== Demo Complete ===\n", .{});
}

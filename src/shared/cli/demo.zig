//! Unified CLI Demo
//! Demonstrates the new enhanced CLI system with terminal integration

const std = @import("std");
const cli = @import("mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.fs.File.stdout().writer();
    try stdout.print("=== Unified CLI Demo ===\n\n", .{});

    // Initialize the CLI application
    var app = try cli.CliApp.init(allocator);
    defer app.deinit();

    try stdout.print("✓ CLI application initialized\n", .{});
    try stdout.print("Terminal capabilities: {s}\n\n", .{app.context.capabilitySummary()});

    // Demo 1: Show help
    try stdout.print("Demo 1: Help command\n", .{});
    try stdout.print("Command: help\n", .{});
    const help_result = try app.run(&[_][]const u8{"help"});
    if (help_result == 0) {
        try stdout.print("✓ Help command executed successfully\n\n", .{});
    }

    // Demo 2: Auth status
    try stdout.print("Demo 2: Auth status\n", .{});
    try stdout.print("Command: auth status\n", .{});
    const auth_result = try app.run(&[_][]const u8{ "auth", "status" });
    if (auth_result == 0) {
        try stdout.print("✓ Auth status command executed successfully\n\n", .{});
    }

    // Demo 3: Workflow execution
    try stdout.print("Demo 3: Workflow execution\n", .{});
    try stdout.print("Command: workflow auth-setup\n", .{});
    const workflow_result = try app.run(&[_][]const u8{ "workflow", "auth-setup" });
    if (workflow_result == 0) {
        try stdout.print("✓ Workflow executed successfully\n\n", .{});
    }

    // Demo 4: Smart components
    try stdout.print("Demo 4: Smart components\n", .{});
    demoSmartComponents(&app.context);

    try stdout.print("\n=== Demo Complete ===\n", .{});
}

fn demoSmartComponents(ctx: *cli.Cli) void {
    const stdout = std.fs.File.stdout().writer();
    const stderr = std.fs.File.stderr().writer();

    // Demo hyperlink menu
    stdout.print("Smart Component: Hyperlink Menu\n", .{}) catch {};

    const menu_items = [_]cli.components.smart.MenuItem{
        .{ .label = "Documentation", .url = "https://docs.example.com", .hotkey = 'd' },
        .{ .label = "API Reference", .url = "https://api.example.com", .hotkey = 'a' },
    };

    var menu = cli.components.smart.HyperlinkMenu.init(ctx, &menu_items);
    menu.setTitle("Quick Links");

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    menu.render(&stdout_writer.interface) catch |err| {
        stderr.print("Error rendering menu: {}\n", .{err}) catch {};
    };

    // Demo notification
    stdout.print("\nSmart Component: Notification Display\n", .{}) catch {};

    var notifier = cli.components.smart.NotificationDisplay.init(ctx);
    notifier.show(.success, "Demo Complete", "All components tested successfully", .system) catch |err| {
        stderr.print("Error showing notification: {}\n", .{err}) catch {};
    };
}

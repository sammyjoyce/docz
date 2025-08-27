//! Unified CLI Demo
//! Demonstrates the new enhanced CLI system with terminal integration

const std = @import("std");
const cli = @import("mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Unified CLI Demo ===\n\n");

    // Initialize the CLI application
    var app = try cli.CliApp.init(allocator);
    defer app.deinit();

    std.debug.print("✓ CLI application initialized\n");
    std.debug.print("Terminal capabilities: {s}\n\n", .{app.context.capabilitySummary()});

    // Demo 1: Show help
    std.debug.print("Demo 1: Help command\n");
    std.debug.print("Command: help\n");
    const help_result = try app.run(&[_][]const u8{"help"});
    if (help_result == 0) {
        std.debug.print("✓ Help command executed successfully\n\n");
    }

    // Demo 2: Auth status
    std.debug.print("Demo 2: Auth status\n");
    std.debug.print("Command: auth status\n");
    const auth_result = try app.run(&[_][]const u8{ "auth", "status" });
    if (auth_result == 0) {
        std.debug.print("✓ Auth status command executed successfully\n\n");
    }

    // Demo 3: Workflow execution
    std.debug.print("Demo 3: Workflow execution\n");
    std.debug.print("Command: workflow auth-setup\n");
    const workflow_result = try app.run(&[_][]const u8{ "workflow", "auth-setup" });
    if (workflow_result == 0) {
        std.debug.print("✓ Workflow executed successfully\n\n");
    }

    // Demo 4: Smart components
    std.debug.print("Demo 4: Smart components\n");
    demoSmartComponents(&app.context);

    std.debug.print("\n=== Demo Complete ===\n");
}

fn demoSmartComponents(ctx: *cli.CliContext) void {
    // Demo hyperlink menu
    std.debug.print("Smart Component: Hyperlink Menu\n");

    const menu_items = [_]cli.components.smart.MenuItem{
        .{ .label = "Documentation", .url = "https://docs.example.com", .hotkey = 'd' },
        .{ .label = "API Reference", .url = "https://api.example.com", .hotkey = 'a' },
    };

    var menu = cli.components.smart.HyperlinkMenu.init(ctx, &menu_items);
    menu.setTitle("Quick Links");

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    menu.render(&stdout_writer.interface) catch |err| {
        std.debug.print("Error rendering menu: {}\n", .{err});
    };

    // Demo notification
    std.debug.print("\nSmart Component: Notification Display\n");

    var notifier = cli.components.smart.NotificationDisplay.init(ctx);
    notifier.show(.success, "Demo Complete", "All components tested successfully", .system) catch |err| {
        std.debug.print("Error showing notification: {}\n", .{err});
    };
}

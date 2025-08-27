//! Demo script showcasing the enhanced CLI and TUI improvements
//! Run with: zig run src/cli_enhancement_demo.zig

const std = @import("std");
const cli = @import("cli/mod.zig");
const tui = @import("tui/mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🚀 DocZ CLI & TUI Enhancement Demo\n", .{});
    std.debug.print("=" ** 50 ++ "\n\n", .{});

    // CLI demonstration
    std.debug.print("=== Enhanced CLI Parser ===\n", .{});
    const test_args = [_][]const u8{"--help"};

    var app = cli.CliApp.init(allocator) catch |err| {
        std.debug.print("❌ Failed to initialize CLI app: {}\n", .{err});
        return;
    };
    defer app.deinit();

    const exit_code = app.run(&test_args) catch |err| {
        std.debug.print("❌ CLI execution failed: {}\n", .{err});
        return;
    };

    if (exit_code == 0) {
        std.debug.print("✅ Built-in command was handled\n", .{});
    }

    std.debug.print("\n=== Advanced CLI Features ===\n");
    const advanced_args = [_][]const u8{ "--model", "claude-3-haiku", "Hello world!" };

    var parser = cli.EnhancedParser.init(allocator);
    defer parser.deinit();

    // Need to add program name for proper parsing
    const argv = [_][]const u8{"docz"} ++ advanced_args;

    if (parser.parse(&argv)) |parsed_adv| {
        defer parsed_adv.deinit();

        std.debug.print("✅ Parsed arguments successfully:\n", .{});
        std.debug.print("   Model: {s}\n", .{parsed_adv.model});
        std.debug.print("   Stream: {}\n", .{parsed_adv.stream});
        if (parsed_adv.prompt) |prompt| {
            std.debug.print("   Prompt: {s}\n", .{prompt});
        }
    } else |err| {
        std.debug.print("❌ Parsing failed: {}\n", .{err});
    }

    std.debug.print("\n=== Terminal Capabilities ===\n", .{});
    const caps = tui.TermCaps.getTermCaps();
    std.debug.print("Truecolor support: {}\n", .{caps.supportsTruecolor});
    std.debug.print("Hyperlink support: {}\n", .{caps.supportsHyperlinkOsc8});
    std.debug.print("Graphics support: {} (Kitty: {}, Sixel: {})\n", .{ caps.supportsKittyGraphics or caps.supportsSixel, caps.supportsKittyGraphics, caps.supportsSixel });
    std.debug.print("Notification support: {}\n", .{caps.supportsNotifyOsc9});

    std.debug.print("\n=== Widget Demonstration ===\n", .{});

    // Quick widget demo
    var section = tui.Section.init(allocator, "Demo Section");
    defer section.deinit();
    section.setIcon("🎨");
    try section.addLine("This is a demonstration of the enhanced TUI widgets");
    try section.addLine("✅ Rich theming and colors");
    try section.addLine("✅ Terminal capability detection");
    try section.addLine("✅ Modular architecture");
    section.draw();

    std.debug.print("\n", .{});

    // Menu demo
    const menu_items = [_]tui.MenuItem{
        tui.MenuItem.init("1", "CLI Features").withIcon("⌨️").withDescription("Advanced CLI parsing"),
        tui.MenuItem.init("2", "TUI Widgets").withIcon("🧩").withDescription("Rich terminal UI"),
        tui.MenuItem.init("3", "Graphics").withIcon("🎨").withDescription("Image display support"),
        tui.MenuItem.init("4", "Notifications").withIcon("🔔").withDescription("User feedback system"),
    };

    var demo_menu = try tui.Menu.initFromItems(allocator, "🎯 Available Features", &menu_items);
    defer demo_menu.deinit();
    demo_menu.draw();

    std.debug.print("\n=== Notification System ===\n", .{});
    var notificationHandler = tui.NotificationHandler.init(allocator);
    defer notificationHandler.deinit();

    try notificationHandler.info("This is an info notification");
    try notificationHandler.success("Enhancement demo completed!");

    if (caps.supportsNotifyOsc9) {
        try tui.notification.systemNotify(allocator, "CLI Enhancement Demo finished! 🎉");
    }

    std.debug.print("\n" ++ "=" ** 50 ++ "\n", .{});
    std.debug.print("✨ Demo completed! Run 'zig run src/tui/demo.zig' for full TUI demo\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});
}

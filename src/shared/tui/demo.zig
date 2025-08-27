//! TUI Demo - Showcases all enhanced TUI capabilities
//! Demonstrates the new graphics, notification, and enhanced widget features

const std = @import("std");
const tui = @import("mod.zig");
const cli = @import("../cli.zig");
const term_caps = @import("../term/caps.zig");
const print = std.debug.print;

pub const DemoError = error{
    UserExit,
    DemoFailed,
    OutOfMemory,
};

pub const Demo = struct {
    allocator: std.mem.Allocator,
    notification_manager: tui.NotificationManager,
    graphics_widget: ?tui.GraphicsWidget,
    caps: term_caps.TermCaps,

    pub fn init(allocator: std.mem.Allocator) Demo {
        return Demo{
            .allocator = allocator,
            .notification_manager = tui.NotificationManager.init(allocator),
            .graphics_widget = null,
            .caps = term_caps.getTermCaps(),
        };
    }

    pub fn deinit(self: *Demo) void {
        self.notification_manager.deinit();
        if (self.graphics_widget) |*widget| {
            widget.deinit();
        }
    }

    pub fn run(self: *Demo) !void {
        try self.showWelcome();
        try self.demonstrateCapabilities();
        try self.showInteractiveMenu();
        try self.showFarewell();
    }

    fn showWelcome(self: *Demo) !void {
        print("\n");

        // Welcome notification
        try self.notification_manager.info("Welcome to the Enhanced TUI Demo!");

        std.time.sleep(1_500_000_000); // 1.5 seconds

        // Create welcome section
        var section = tui.Section.init(self.allocator, "🚀 Enhanced TUI Demo");
        defer section.deinit();

        section.setIcon("🎨");
        try section.addLine("This demo showcases the new TUI capabilities:");
        try section.addLine("• Enhanced graphics support (Kitty & Sixel)");
        try section.addLine("• Rich notification system");
        try section.addLine("• Improved menu and section widgets");
        try section.addLine("• Advanced terminal capability detection");
        try section.addLine("");

        const caps_info = if (self.caps.supportsKittyGraphics)
            "✅ Kitty graphics supported"
        else if (self.caps.supportsSixel)
            "✅ Sixel graphics supported"
        else
            "❌ Graphics not supported in this terminal";

        try section.addFormattedLine("Graphics: {s}", .{caps_info});

        const notification_info = if (self.caps.supportsNotifyOsc9)
            "✅ Desktop notifications supported"
        else
            "❌ Desktop notifications not supported";

        try section.addFormattedLine("Notifications: {s}", .{notification_info});

        section.draw();

        std.time.sleep(2_000_000_000); // 2 seconds
    }

    fn demonstrateCapabilities(self: *Demo) !void {
        // Graphics demo
        try self.demoGraphics();

        // Notification demo
        try self.demoNotifications();

        // Widget demo
        try self.demoWidgets();
    }

    fn demoGraphics(self: *Demo) !void {
        var graphics_section = tui.Section.init(self.allocator, "🖼️ Graphics Capabilities");
        defer graphics_section.deinit();

        graphics_section.setIcon("🎨");

        if (tui.graphics.isGraphicsSupported()) {
            const protocol = tui.graphics.getBestGraphicsProtocol() orelse "unknown";
            try graphics_section.addFormattedLine("Using {s} graphics protocol", .{protocol});
            try graphics_section.addLine("");
            try graphics_section.addLine("Creating sample image display...");

            graphics_section.draw();

            // Try to display a simple graphic
            self.graphics_widget = tui.GraphicsWidget.init(self.allocator);

            // Create a simple test image (just some test data)
            const test_image_data = "Simple test image data - in real usage this would be PNG/JPEG bytes";
            self.graphics_widget.?.loadFromBytes(test_image_data, tui.graphics.ImageFormat.PNG) catch |err| {
                try self.notification_manager.warning("Failed to load test image");
                print("Graphics error: {}\n", .{err});
                return;
            };

            const display_options = tui.graphics.DisplayOptions{
                .width = 20,
                .height = 10,
                .x = 5,
                .y = 15,
            };
            self.graphics_widget.?.setDisplayOptions(display_options);

            self.graphics_widget.?.display() catch |err| {
                try self.notification_manager.warning("Graphics display failed - this is expected for demo data");
                print("Display error (expected): {}\n", .{err});
            };

            std.time.sleep(2_000_000_000); // 2 seconds

        } else {
            try graphics_section.addLine("Graphics not supported in this terminal");
            try graphics_section.addLine("For graphics support, try:");
            try graphics_section.addLine("  • Kitty terminal");
            try graphics_section.addLine("  • iTerm2 with sixel support");
            try graphics_section.addLine("  • WezTerm");

            graphics_section.draw();
        }

        std.time.sleep(1_500_000_000); // 1.5 seconds

        try self.notification_manager.success("Graphics demo completed!");
    }

    fn demoNotifications(self: *Demo) !void {
        var notification_section = tui.Section.init(self.allocator, "🔔 Notification System");
        defer notification_section.deinit();

        notification_section.setIcon("📢");
        try notification_section.addLine("Demonstrating different notification levels:");
        try notification_section.addLine("");

        notification_section.draw();

        // Demo different notification types
        try self.notification_manager.info("This is an info notification");
        std.time.sleep(800_000_000);

        try self.notification_manager.success("This is a success notification");
        std.time.sleep(800_000_000);

        try self.notification_manager.warning("This is a warning notification");
        std.time.sleep(800_000_000);

        try self.notification_manager.error_("This is an error notification");
        std.time.sleep(800_000_000);

        try self.notification_manager.debug("This is a debug notification");
        std.time.sleep(1_500_000_000);

        // Try system notification if supported
        if (self.caps.supportsNotifyOsc9) {
            try tui.notification.systemNotify(self.allocator, "System notification test - check your desktop!");
        }

        std.time.sleep(1_000_000_000);

        // Clear notifications
        try self.notification_manager.clearAll();
    }

    fn demoWidgets(self: *Demo) !void {
        var widgets_section = tui.Section.init(self.allocator, "🧩 Enhanced Widgets");
        defer widgets_section.deinit();

        widgets_section.setIcon("⚙️");
        try widgets_section.addLine("Enhanced widget capabilities:");
        try widgets_section.addLine("");

        widgets_section.draw();

        // Collapsible sections demo
        try self.demoSections();

        // Enhanced menu demo
        try self.demoMenus();

        std.time.sleep(1_000_000_000);
    }

    fn demoSections(self: *Demo) !void {
        print("\n📁 Collapsible Sections:\n\n");

        // Create multiple sections with different states
        var section1 = tui.Section.init(self.allocator, "Expanded Section");
        defer section1.deinit();
        section1.setIcon("📂");
        try section1.addLine("This section is expanded by default");
        try section1.addLine("You can see all the content");
        section1.draw();

        print("\n");

        var section2 = tui.Section.init(self.allocator, "Collapsed Section");
        defer section2.deinit();
        section2.setIcon("📁");
        section2.collapse();
        try section2.addLine("This content is hidden");
        try section2.addLine("Click to expand in interactive mode");
        section2.draw();

        print("\n");

        var section3 = tui.Section.init(self.allocator, "Nested Content");
        defer section3.deinit();
        section3.setIcon("🔗");
        section3.setIndent(1);
        try section3.addLine("This section is indented");
        try section3.addLine("Perfect for hierarchical content");
        section3.draw();

        std.time.sleep(2_000_000_000);
    }

    fn demoMenus(self: *Demo) !void {
        print("\n📋 Enhanced Menus:\n\n");

        // Create sample menu items
        const menu_items = [_]tui.MenuItem{
            tui.MenuItem.init("1", "Graphics Demo")
                .withDescription("Showcase graphics capabilities")
                .withShortcut("g")
                .withIcon("🎨"),
            tui.MenuItem.init("2", "Notifications Demo")
                .withDescription("Test notification system")
                .withShortcut("n")
                .withIcon("🔔"),
            tui.MenuItem.init("3", "Terminal Info")
                .withDescription("Show terminal capabilities")
                .withShortcut("i")
                .withIcon("💻"),
            tui.MenuItem.init("4", "Help & Documentation")
                .withDescription("Access help resources")
                .withShortcut("h")
                .withIcon("📚")
                .withHelpUrl("https://github.com/example/docz"),
        };

        var demo_menu = try tui.Menu.initFromItems(self.allocator, "🎯 Demo Menu Options", &menu_items);
        defer demo_menu.deinit();

        demo_menu.draw();

        std.time.sleep(3_000_000_000);
    }

    fn showInteractiveMenu(self: *Demo) !void {
        print("\n");

        var main_section = tui.Section.init(self.allocator, "🎮 Interactive Demo");
        defer main_section.deinit();

        main_section.setIcon("🎯");
        try main_section.addLine("In a full application, you could:");
        try main_section.addLine("• Navigate menus with arrow keys");
        try main_section.addLine("• Click on sections to expand/collapse");
        try main_section.addLine("• Use keyboard shortcuts for quick actions");
        try main_section.addLine("• Copy content to clipboard");
        try main_section.addLine("• Follow hyperlinks in supported terminals");
        try main_section.addLine("");
        try main_section.addLine("Press any key to continue...");

        main_section.draw();

        // Wait for user input (simplified)
        var stdin_buffer: [1]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
        const stdin = &stdin_reader.interface;
        _ = stdin.readByte() catch {};
    }

    fn showFarewell(self: *Demo) !void {
        print("\n");

        try self.notification_manager.success("Demo completed successfully!");

        var farewell_section = tui.Section.init(self.allocator, "👋 Demo Complete");
        defer farewell_section.deinit();

        farewell_section.setIcon("✨");
        try farewell_section.addLine("Thank you for exploring the enhanced TUI capabilities!");
        try farewell_section.addLine("");
        try farewell_section.addLine("New features demonstrated:");
        try farewell_section.addLine("✅ Modular TUI widget system");
        try farewell_section.addLine("✅ Graphics support (Kitty & Sixel protocols)");
        try farewell_section.addLine("✅ Rich notification system (OSC 9 + in-terminal)");
        try farewell_section.addLine("✅ Enhanced menus with icons and hyperlinks");
        try farewell_section.addLine("✅ Collapsible sections with theming");
        try farewell_section.addLine("✅ Terminal capability detection");
        try farewell_section.addLine("✅ Restructured CLI architecture");
        try farewell_section.addLine("");
        try farewell_section.addLine("The TUI system is now ready for advanced applications!");

        farewell_section.draw();

        std.time.sleep(2_000_000_000);

        // Final system notification
        if (self.caps.supportsNotifyOsc9) {
            try tui.notification.systemNotify(self.allocator, "TUI Demo completed! 🎉");
        }
    }
};

/// Run the TUI demo
pub fn runDemo(allocator: std.mem.Allocator) !void {
    var demo = Demo.init(allocator);
    defer demo.deinit();

    try demo.run();
}

/// CLI demo entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Show CLI capabilities first
    const args = [_][]const u8{ "tui-demo", "--version" };
    var cli_parser = cli.EnhancedParser.init(allocator);
    var parsed = try cli_parser.parse(&args);
    defer parsed.deinit();
    try cli_parser.handleParsedArgs(&parsed);

    print("\n" ++ "=".repeat(60) ++ "\n");
    print("🎨 Starting Enhanced TUI Demo\n");
    print("=".repeat(60) ++ "\n");

    // Run the TUI demo
    try runDemo(allocator);

    print("\n" ++ "=".repeat(60) ++ "\n");
    print("✨ Demo completed successfully!\n");
    print("=".repeat(60) ++ "\n\n");
}

// Helper for string repetition (since Zig doesn't have it built-in)
fn repeat(comptime str: []const u8, comptime n: usize) []const u8 {
    return str ** n;
}

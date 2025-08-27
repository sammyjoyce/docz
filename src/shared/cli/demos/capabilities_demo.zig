//! Enhanced CLI Capabilities Demo
//!
//! This demo showcases the advanced terminal capabilities provided by the
//! unified terminal interface and enhanced CLI components including:
//! - Progressive enhancement based on terminal capabilities
//! - Rich progress bars with multiple rendering modes
//! - Smart notifications with system integration
//! - Enhanced input components with validation
//! - Clipboard integration and hyperlink support

const std = @import("std");
const term_shared = @import("term_shared");
const unified = term_shared.unified;
const terminal_bridge = @import("../core/terminal_bridge.zig");
const components = @import("../../components/mod.zig");
const notification = @import("../components/base/notification.zig");
const input = @import("../components/base/input.zig");

/// Demo configuration
const DemoConfig = struct {
    show_capabilities: bool = true,
    run_progress_demo: bool = true,
    run_notification_demo: bool = true,
    run_input_demo: bool = true,
    run_integration_demo: bool = true,
    pause_between_demos: bool = true,
};

/// Main demo entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal bridge
    const bridge_config = terminal_bridge.Config{
        .enable_buffering = true,
        .enable_graphics = true,
        .enable_notifications = true,
        .enable_clipboard = true,
    };

    var bridge = try terminal_bridge.TerminalBridge.init(allocator, bridge_config);
    defer bridge.deinit();

    const demo_config = DemoConfig{};

    // Welcome message
    try showWelcome(&bridge);

    // Demo sections
    if (demo_config.show_capabilities) {
        try showCapabilities(&bridge);
        if (demo_config.pause_between_demos) try waitForEnter(&bridge);
    }

    if (demo_config.run_progress_demo) {
        try runProgressDemo(&bridge);
        if (demo_config.pause_between_demos) try waitForEnter(&bridge);
    }

    if (demo_config.run_notification_demo) {
        try runNotificationDemo(&bridge);
        if (demo_config.pause_between_demos) try waitForEnter(&bridge);
    }

    if (demo_config.run_input_demo) {
        try runInputDemo(&bridge);
        if (demo_config.pause_between_demos) try waitForEnter(&bridge);
    }

    if (demo_config.run_integration_demo) {
        try runIntegrationDemo(&bridge);
    }

    // Farewell
    try showFarewell(&bridge);
}

/// Show welcome message with terminal capabilities
fn showWelcome(bridge: *terminal_bridge.TerminalBridge) !void {
    try bridge.clearScreen();

    const title_style = unified.Style{
        .fg_color = unified.Color{ .rgb = .{ .r = 100, .g = 200, .b = 255 } },
        .bold = true,
    };

    try bridge.print("╔══════════════════════════════════════════════════════════════╗\n", title_style);
    try bridge.print("║               Enhanced CLI Capabilities Demo                 ║\n", title_style);
    try bridge.print("║          Progressive Terminal Enhancement Showcase          ║\n", title_style);
    try bridge.print("╚══════════════════════════════════════════════════════════════╝\n", title_style);
    try bridge.print("\n", null);

    // Show brief introduction
    try bridge.print("Welcome to the Enhanced CLI Capabilities Demo!\n\n", null);
    try bridge.print("This demonstration showcases advanced terminal features with\n", null);
    try bridge.print("progressive enhancement - automatically adapting to your\n", null);
    try bridge.print("terminal's capabilities for the best possible experience.\n\n", null);

    // Show current strategy
    const strategy = bridge.getRenderStrategy();
    try bridge.print("Current Rendering Strategy: ", terminal_bridge.Styles.INFO);

    const strategy_name = switch (strategy) {
        .full_graphics => "Full Graphics (Kitty Protocol)",
        .sixel_graphics => "Sixel Graphics",
        .rich_text => "Rich Text (Truecolor)",
        .enhanced_ansi => "Enhanced ANSI (256 colors)",
        .basic_ascii => "Basic ASCII (16 colors)",
        .fallback => "Fallback (Minimal support)",
    };

    const strategy_color = switch (strategy) {
        .full_graphics, .sixel_graphics => unified.Colors.GREEN,
        .rich_text => unified.Colors.CYAN,
        .enhanced_ansi => unified.Colors.YELLOW,
        .basic_ascii => unified.Colors.MAGENTA,
        .fallback => unified.Colors.RED,
    };

    try bridge.print(strategy_name, unified.Style{ .fg_color = strategy_color, .bold = true });
    try bridge.print("\n\n", null);
}

/// Show detailed terminal capabilities
fn showCapabilities(bridge: *terminal_bridge.TerminalBridge) !void {
    try bridge.print("═══ Terminal Capabilities Detection ═══\n\n", terminal_bridge.Styles.HIGHLIGHT);

    const caps = bridge.getCapabilities();

    const capabilities_list = [_]struct { name: []const u8, supported: bool }{
        .{ .name = "Truecolor (24-bit RGB)", .supported = caps.supportsTruecolor },
        .{ .name = "Kitty Graphics Protocol", .supported = caps.supportsKittyGraphics },
        .{ .name = "Sixel Graphics", .supported = caps.supportsSixel },
        .{ .name = "Hyperlinks (OSC 8)", .supported = caps.supportsHyperlinkOsc8 },
        .{ .name = "Clipboard Integration (OSC 52)", .supported = caps.supportsClipboardOsc52 },
        .{ .name = "System Notifications (OSC 9)", .supported = caps.supportsNotifyOsc9 },
        .{ .name = "Bracketed Paste", .supported = caps.supportsBracketedPaste },
        .{ .name = "Focus Events", .supported = caps.supportsFocusEvents },
        .{ .name = "Mouse Support (SGR)", .supported = caps.supportsSgrMouse },
        .{ .name = "Pixel Mouse Support", .supported = caps.supportsSgrPixelMouse },
        .{ .name = "Kitty Keyboard Protocol", .supported = caps.supportsKittyKeyboard },
    };

    for (capabilities_list) |cap| {
        const status_icon = if (cap.supported) "✅" else "❌";
        const status_color = if (cap.supported) unified.Colors.GREEN else unified.Colors.RED;

        try bridge.printf("{s} ", .{status_icon}, unified.Style{ .fg_color = status_color });
        try bridge.printf("{s}\n", .{cap.name}, null);
    }

    try bridge.print("\n", null);

    // Show color count
    const strategy = bridge.getRenderStrategy();
    const color_count = strategy.colorCount();
    try bridge.printf("Available Colors: ", .{}, terminal_bridge.Styles.INFO);

    if (color_count > 1000000) {
        try bridge.printf("16.7M (Truecolor)\n", .{}, unified.Style{ .fg_color = unified.Colors.GREEN });
    } else {
        try bridge.printf("{d}\n", .{color_count}, unified.Style{ .fg_color = unified.Colors.YELLOW });
    }

    try bridge.print("\n", null);
}

/// Demonstrate progressive progress bar rendering
fn runProgressDemo(bridge: *terminal_bridge.TerminalBridge) !void {
    try bridge.print("═══ Progressive Progress Bar Demo ═══\n\n", terminal_bridge.Styles.HIGHLIGHT);

    // Create different progress bar configurations
    const progress_configs = [_]struct { name: []const u8, config: components.ProgressConfig }{
        .{
            .name = "Default Progress Bar",
            .config = components.ProgressConfig{},
        },
        .{
            .name = "Rainbow Gradient",
            .config = components.ProgressConfig{
                .color_scheme = .rainbow,
                .width = 50,
                .show_percentage = true,
            },
        },
        .{
            .name = "Fire Theme with ETA",
            .config = components.ProgressConfig{
                .color_scheme = .fire,
                .width = 60,
                .show_percentage = true,
                .show_eta = true,
                .show_rate = true,
            },
        },
        .{
            .name = "Minimal Progress",
            .config = components.ProgressConfig{
                .width = 20,
                .show_percentage = false,
                .enable_graphics = false,
                .left_cap = "",
                .right_cap = "",
            },
        },
    };

    for (progress_configs) |demo_config| {
        try bridge.printf("🔄 {s}\n", .{demo_config.name}, terminal_bridge.Styles.INFO);

        var progress_bar = components.UnifiedProgressBar.init(bridge, demo_config.config);
        defer progress_bar.deinit();

        // Animate progress
        var progress: f64 = 0.0;
        while (progress <= 1.0) : (progress += 0.02) {
            try bridge.moveTo(0, 0); // Move to start of line
            try progress_bar.setProgress(progress, true);

            std.time.sleep(50_000_000); // 50ms delay
        }

        try bridge.print("\n✅ Complete!\n\n", terminal_bridge.Styles.SUCCESS);
        std.time.sleep(500_000_000); // 500ms pause
    }

    // Demonstrate scoped progress
    try bridge.print("🔄 Scoped Progress Operation\n", terminal_bridge.Styles.INFO);
    var progress_bar = components.ProgressBarPresets.download(bridge);
    defer progress_bar.deinit();

    var scoped_progress = progress_bar.scopedOperation(100.0);
    defer scoped_progress.deinit();

    // Simulate file download
    for (0..100) |i| {
        try scoped_progress.update(@as(f64, @floatFromInt(i + 1)));
        std.time.sleep(30_000_000); // 30ms delay
    }

    try scoped_progress.finish();
    try bridge.print("\n✅ Download Complete!\n\n", terminal_bridge.Styles.SUCCESS);
}

/// Demonstrate enhanced notification system
fn runNotificationDemo(bridge: *terminal_bridge.TerminalBridge) !void {
    try bridge.print("═══ Enhanced Notification Demo ═══\n\n", terminal_bridge.Styles.HIGHLIGHT);

    const notification_config = notification.NotificationConfig{
        .enable_system_notifications = true,
        .show_timestamp = true,
        .show_icons = true,
        .enable_clipboard_actions = true,
        .enable_hyperlinks = true,
    };

    var notifications = notification.Notification.init(bridge, notification_config);

    // Demonstrate different notification types
    const notification_demos = [_]struct {
        type: notification.NotificationType,
        title: []const u8,
        message: []const u8,
    }{
        .{ .type = .info, .title = "Information", .message = "This is an informational message" },
        .{ .type = .success, .title = "Success", .message = "Operation completed successfully!" },
        .{ .type = .warning, .title = "Warning", .message = "This action might have consequences" },
        .{ .type = .@"error", .title = "Error", .message = "Something went wrong, but it's recoverable" },
        .{ .type = .critical, .title = "Critical", .message = "This requires immediate attention!" },
    };

    for (notification_demos) |demo| {
        try bridge.printf("Showing {s} notification...\n", .{@tagName(demo.type)}, null);
        try notifications.show(demo.type, demo.title, demo.message);
        try bridge.print("\n", null);
        std.time.sleep(1_000_000_000); // 1 second delay
    }

    // Demonstrate notification with actions
    try bridge.print("Showing notification with actions...\n", null);
    const actions = [_]notification.NotificationAction{
        .{
            .label = "Copy Error Code",
            .action = .{ .copy_text = "ERR_DEMO_001" },
        },
        .{
            .label = "View Documentation",
            .action = .{ .open_url = "https://github.com/example/docs" },
        },
        .{
            .label = "Retry Operation",
            .action = .{ .execute_command = "retry --force" },
        },
    };

    try notifications.showWithActions(.@"error", "Network Timeout", "Failed to connect to remote server", &actions);

    try bridge.print("\n", null);

    // Show notification statistics
    const stats = notifications.getStats();
    try bridge.printf("📊 Notifications sent: {d}\n\n", .{stats.total_count}, terminal_bridge.Styles.INFO);
}

/// Demonstrate smart input components
fn runInputDemo(bridge: *terminal_bridge.TerminalBridge) !void {
    try bridge.print("═══ Smart Input Demo ═══\n\n", terminal_bridge.Styles.HIGHLIGHT);

    // Note: This demo shows the input components but doesn't actually collect input
    // In a real implementation, you would handle keyboard events properly

    const input_demos = [_]struct {
        name: []const u8,
        config: input.InputConfig,
        sample_input: []const u8,
    }{
        .{
            .name = "Email Input with Validation",
            .config = input.InputConfig{
                .input_type = .email,
                .placeholder = "user@example.com",
                .show_validation = true,
            },
            .sample_input = "demo@example.com",
        },
        .{
            .name = "URL Input with Protocol Detection",
            .config = input.InputConfig{
                .input_type = .url,
                .show_validation = true,
            },
            .sample_input = "https://github.com/example/repo",
        },
        .{
            .name = "Number Input with Validation",
            .config = input.InputConfig{
                .input_type = .number,
                .max_length = 10,
            },
            .sample_input = "42.5",
        },
        .{
            .name = "Password Input (Hidden)",
            .config = input.InputConfig{
                .input_type = .password,
                .enable_history = false,
            },
            .sample_input = "secret123",
        },
    };

    for (input_demos) |demo| {
        try bridge.printf("🔤 {s}\n", .{demo.name}, terminal_bridge.Styles.INFO);

        var input_component = input.Input.init(bridge.allocator, bridge, demo.config);
        defer input_component.deinit();

        // Simulate the input (in a real app, this would be interactive)
        try input_component.current_input.appendSlice(demo.sample_input);

        // Show what the input would look like
        const prompt_text = demo.config.input_type.getPrompt();
        try bridge.printf("{s}: ", .{prompt_text}, demo.config.prompt_style);

        // Show syntax highlighting based on input type
        switch (demo.config.input_type) {
            .email => {
                if (std.mem.indexOf(u8, demo.sample_input, "@")) |at_pos| {
                    const username = demo.sample_input[0..at_pos];
                    const domain = demo.sample_input[at_pos..];

                    try bridge.print(username, unified.Style{ .fg_color = unified.Colors.CYAN });
                    try bridge.print(domain, unified.Style{ .fg_color = unified.Colors.GREEN });
                }
            },
            .url => {
                if (std.mem.startsWith(u8, demo.sample_input, "https://")) {
                    try bridge.print("https://", unified.Style{ .fg_color = unified.Colors.GREEN });
                    try bridge.print(demo.sample_input[8..], unified.Style{ .fg_color = unified.Colors.CYAN });
                }
            },
            .number => {
                try bridge.print(demo.sample_input, unified.Style{ .fg_color = unified.Colors.GREEN });
            },
            .password => {
                for (0..demo.sample_input.len) |_| {
                    try bridge.print("*", unified.Style{ .fg_color = unified.Colors.MAGENTA });
                }
            },
            else => {
                try bridge.print(demo.sample_input, null);
            },
        }

        // Show validation status
        const validation = input_component.validateInput();
        switch (validation) {
            .valid => try bridge.print(" ✓", terminal_bridge.Styles.SUCCESS),
            .invalid => |msg| try bridge.printf(" ✗ {s}", .{msg}, terminal_bridge.Styles.ERROR),
            .warning => |msg| try bridge.printf(" ⚠ {s}", .{msg}, unified.Style{ .fg_color = unified.Colors.YELLOW }),
        }

        try bridge.print("\n\n", null);
        std.time.sleep(1_000_000_000); // 1 second delay
    }
}

/// Demonstrate integration between components
fn runIntegrationDemo(bridge: *terminal_bridge.TerminalBridge) !void {
    try bridge.print("═══ Component Integration Demo ═══\n\n", terminal_bridge.Styles.HIGHLIGHT);

    // Create notification system
    const notification_config = notification.NotificationConfig{};
    var notifications = notification.Notification.init(bridge, notification_config);

    // Simulate a complex operation with progress, notifications, and potential user input
    try bridge.print("🚀 Starting Complex Operation...\n\n", terminal_bridge.Styles.INFO);

    // Step 1: Initialization with notification
    try notifications.show(.info, "Initialization", "Setting up operation parameters");
    std.time.sleep(500_000_000);

    // Step 2: Progress bar for main work
    try bridge.print("📊 Processing data...\n", null);
    var progress_bar = components.ProgressBarPresets.rich(bridge);
    defer progress_bar.deinit();

    const total_items = 50;
    for (0..total_items) |i| {
        try progress_bar.update(@as(f64, @floatFromInt(i + 1)), total_items, true);

        // Simulate some warnings during processing
        if (i == 15) {
            try notifications.show(.warning, "Performance", "Processing is slower than expected");
        }
        if (i == 35) {
            try notifications.show(.success, "Checkpoint", "Halfway point reached successfully");
        }

        std.time.sleep(100_000_000); // 100ms delay
    }

    try bridge.print("\n", null);

    // Step 3: Final notification with actions
    const completion_actions = [_]notification.NotificationAction{
        .{
            .label = "View Results",
            .action = .{ .open_url = "file://./results.log" },
        },
        .{
            .label = "Copy Summary",
            .action = .{ .copy_text = "Operation completed: 50/50 items processed successfully" },
        },
    };

    try notifications.showWithActions(.success, "Operation Complete", "All 50 items processed successfully!", &completion_actions);

    // Show final statistics
    const stats = notifications.getStats();
    const metrics = bridge.getMetrics();

    try bridge.print("\n📈 Performance Metrics:\n", terminal_bridge.Styles.INFO);
    try bridge.printf("  • Total notifications: {d}\n", .{stats.total_count}, null);
    try bridge.printf("  • Render operations: {d}\n", .{metrics.render_calls}, null);
    try bridge.printf("  • Average render time: {d:.2}ms\n", .{metrics.averageRenderTime()}, null);
    try bridge.print("\n", null);
}

/// Show farewell message
fn showFarewell(bridge: *terminal_bridge.TerminalBridge) !void {
    try bridge.print("═══════════════════════════════════════════════════════════════\n", terminal_bridge.Styles.HIGHLIGHT);
    try bridge.print("                    Demo Complete! 🎉                          \n", terminal_bridge.Styles.SUCCESS);
    try bridge.print("═══════════════════════════════════════════════════════════════\n", terminal_bridge.Styles.HIGHLIGHT);
    try bridge.print("\n", null);

    try bridge.print("Thank you for exploring the Enhanced CLI Capabilities!\n\n", null);

    try bridge.print("Key features demonstrated:\n", terminal_bridge.Styles.INFO);
    try bridge.print("  ✅ Progressive enhancement based on terminal capabilities\n", null);
    try bridge.print("  ✅ Rich progress bars with multiple rendering modes\n", null);
    try bridge.print("  ✅ Smart notifications with system integration\n", null);
    try bridge.print("  ✅ Enhanced input components with validation\n", null);
    try bridge.print("  ✅ Clipboard integration and hyperlink support\n", null);
    try bridge.print("  ✅ Performance monitoring and optimization\n", null);

    try bridge.print("\n", null);

    const strategy = bridge.getRenderStrategy();
    try bridge.print("Your terminal supports: ", null);
    try bridge.print(switch (strategy) {
        .full_graphics => "Full Graphics Mode! 🎨",
        .sixel_graphics => "Sixel Graphics! 🖼️",
        .rich_text => "Rich Text Mode! 🌈",
        .enhanced_ansi => "Enhanced Colors! 🎭",
        .basic_ascii => "Basic Colors! 🎪",
        .fallback => "Text Mode! 📝",
    }, unified.Style{ .bold = true });

    try bridge.print("\n\n", null);

    // Try to copy demo summary to clipboard
    const summary = "Enhanced CLI Demo completed - progressive terminal capabilities showcased!";
    bridge.copyToClipboard(summary) catch {};

    try bridge.print("💾 Demo summary copied to clipboard (if supported)\n", terminal_bridge.Styles.MUTED);
    try bridge.print("\nPress any key to exit...\n", terminal_bridge.Styles.MUTED);
}

/// Wait for user to press Enter (simplified)
fn waitForEnter(bridge: *terminal_bridge.TerminalBridge) !void {
    try bridge.print("\n⏸️  Press Enter to continue...", terminal_bridge.Styles.MUTED);

    // In a real implementation, this would wait for actual keyboard input
    std.time.sleep(2_000_000_000); // 2 second delay for demo
    try bridge.print("\n\n", null);
}

/// Alternative main function that can be called with arguments
pub fn runDemo(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = allocator;
    _ = args;

    try main();
}

test "demo initialization" {
    // Basic test to ensure the demo can be compiled and basic structures work
    const demo_config = DemoConfig{};
    _ = demo_config;
}

//! UI Capabilities Demo
//!
//! This demo showcases the new unified terminal interface, graphics manager,
//! component-based architecture, and shared UI components with progressive enhancement.

const std = @import("std");
const shared = @import("shared.zig");
const progress_bar = @import("components/progress_bar.zig");
const smart_input = @import("components/smart_input.zig");

const UI = shared.UI;
const UIMode = shared.UIMode;
const Component = shared.Component;
const NotificationLevel = shared.NotificationLevel;
const ProgressBar = progress_bar.ProgressBar;
const SmartInput = smart_input.SmartInput;

/// Demo showcasing UI capabilities
pub const UIDemo = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    uiContext: UI,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var uiContext = try UI.init(allocator, .tui);

        return Self{
            .allocator = allocator,
            .uiContext = uiContext,
        };
    }

    pub fn deinit(self: *Self) void {
        self.uiContext.deinit();
    }

    /// Run the comprehensive demo
    pub fn run(self: *Self) !void {
        try self.showWelcomeScreen();
        try self.demonstrateCapabilities();
        try self.showProgressDemo();
        try self.showInputDemo();
        try self.showNotificationDemo();
        try self.showGraphicsDemo();
        try self.showFarewell();
    }

    fn showWelcomeScreen(self: *Self) !void {
        try self.ui_context.clear();

        const caps = self.ui_context.getCapabilities();

        // Display terminal info with progressive styling
        const TITLE_STYLE = shared.createTextStyle(shared.Colors.BRIGHT_BLUE, true);

        try self.ui_context.terminal.printf("╔═══════════════════════════════════════════╗\n", .{}, TITLE_STYLE);
        try self.ui_context.terminal.printf("║            UI Demo v2.0                  ║\n", .{}, TITLE_STYLE);
        try self.ui_context.terminal.printf("╚═══════════════════════════════════════════╝\n\n", .{}, TITLE_STYLE);

        try self.ui_context.terminal.printf("Terminal Capabilities Detected:\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_WHITE, true));

        // Capability checklist with icons
        const CHECKMARK = if (caps.supportsTruecolor) "✓" else "✗";
        const COLOR = if (caps.supportsTruecolor) shared.Colors.BRIGHT_GREEN else shared.Colors.BRIGHT_RED;
        try self.ui_context.terminal.printf("  {s} Truecolor Support (24-bit RGB)\n", .{CHECKMARK}, shared.createTextStyle(COLOR, false));

        const GRAPHICS_CHECK = if (caps.supportsKittyGraphics or caps.supportsSixel) "✓" else "✗";
        const GRAPHICS_COLOR = if (caps.supportsKittyGraphics or caps.supportsSixel) shared.Colors.BRIGHT_GREEN else shared.Colors.BRIGHT_RED;
        try self.ui_context.terminal.printf("  {s} Graphics Support (Kitty/Sixel)\n", .{GRAPHICS_CHECK}, shared.createTextStyle(GRAPHICS_COLOR, false));

        const HYPERLINK_CHECK = if (caps.supportsHyperlinkOsc8) "✓" else "✗";
        const HYPERLINK_COLOR = if (caps.supportsHyperlinkOsc8) shared.Colors.BRIGHT_GREEN else shared.Colors.BRIGHT_RED;
        try self.ui_context.terminal.printf("  {s} Hyperlink Support (OSC 8)\n", .{HYPERLINK_CHECK}, shared.createTextStyle(HYPERLINK_COLOR, false));

        const CLIPBOARD_CHECK = if (caps.supportsClipboardOsc52) "✓" else "✗";
        const CLIPBOARD_COLOR = if (caps.supportsClipboardOsc52) shared.Colors.BRIGHT_GREEN else shared.Colors.BRIGHT_RED;
        try self.ui_context.terminal.printf("  {s} Clipboard Support (OSC 52)\n", .{CLIPBOARD_CHECK}, shared.createTextStyle(CLIPBOARD_COLOR, false));

        const NOTIFICATION_CHECK = if (caps.supportsNotifyOsc9) "✓" else "✗";
        const NOTIFICATION_COLOR = if (caps.supportsNotifyOsc9) shared.Colors.BRIGHT_GREEN else shared.Colors.BRIGHT_RED;
        try self.ui_context.terminal.printf("  {s} Native Notifications (OSC 9)\n\n", .{NOTIFICATION_CHECK}, shared.createTextStyle(NOTIFICATION_COLOR, false));

        // Show what will be demonstrated
        try self.ui_context.terminal.printf("This demo will showcase:\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_CYAN, true));
        try self.ui_context.terminal.printf("  • Unified terminal interface with capability detection\n", .{}, null);
        try self.ui_context.terminal.printf("  • Progressive enhancement based on your terminal\n", .{}, null);
        try self.ui_context.terminal.printf("  • Smart components that adapt automatically\n", .{}, null);
        try self.ui_context.terminal.printf("  • Graphics rendering\n", .{}, null);
        try self.ui_context.terminal.printf("  • Unified CLI/TUI component architecture\n\n", .{}, null);

        try self.ui_context.terminal.printf("Press Enter to continue...", .{}, shared.createTextStyle(shared.Colors.YELLOW, false));
        try self.waitForEnter();
    }

    fn demonstrateCapabilities(self: *Self) !void {
        try self.ui_context.clear();

        try self.ui_context.terminal.printf("═══ Capability Demonstration ═══\n\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_MAGENTA, true));

        // Demonstrate hyperlinks
        try self.ui_context.terminal.printf("1. Hyperlink Support:\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_WHITE, true));
        try self.ui_context.terminal.hyperlink("https://github.com/your-project", "🔗 Visit our GitHub repository", shared.createTextStyle(shared.Colors.BRIGHT_BLUE, false));
        try self.ui_context.terminal.printf("\n\n", .{}, null);

        // Demonstrate colors with progressive fallback
        try self.ui_context.terminal.printf("2. Color Demonstration:\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_WHITE, true));
        const colors = [_]shared.Color{
            shared.Color{ .rgb = .{ .r = 255, .g = 100, .b = 100 } }, // Red
            shared.Color{ .rgb = .{ .r = 100, .g = 255, .b = 100 } }, // Green
            shared.Color{ .rgb = .{ .r = 100, .g = 100, .b = 255 } }, // Blue
            shared.Color{ .rgb = .{ .r = 255, .g = 255, .b = 100 } }, // Yellow
            shared.Color{ .rgb = .{ .r = 255, .g = 100, .b = 255 } }, // Magenta
            shared.Color{ .rgb = .{ .r = 100, .g = 255, .b = 255 } }, // Cyan
        };

        for (colors) |color| {
            try self.ui_context.terminal.printf("████ ", .{}, shared.createTextStyle(color, false));
        }
        try self.ui_context.terminal.printf("\n", .{}, null);

        const caps = self.ui_context.getCapabilities();
        if (caps.supportsTruecolor) {
            try self.ui_context.terminal.printf("  ↑ 24-bit RGB colors (your terminal supports this!)\n\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_GREEN, false));
        } else {
            try self.ui_context.terminal.printf("  ↑ Colors automatically adapted to your terminal's capabilities\n\n", .{}, shared.createTextStyle(shared.Colors.YELLOW, false));
        }

        try self.ui_context.terminal.printf("Press Enter to continue...", .{}, shared.createTextStyle(shared.Colors.YELLOW, false));
        try self.waitForEnter();
    }

    fn showProgressDemo(self: *Self) !void {
        try self.ui_context.clear();

        try self.ui_context.terminal.printf("═══ Smart Progress Bar Demo ═══\n\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_MAGENTA, true));

        // Demonstrate different progress bar styles
        const styles = [_]progress_bar.ProgressBarStyle{ .ascii, .unicode_blocks, .gradient, .animated };
        const style_names = [_][]const u8{ "ASCII", "Unicode Blocks", "Gradient", "Animated" };

        for (styles, style_names) |style, name| {
            try self.ui_context.terminal.printf("{s} Style:\n", .{name}, shared.createTextStyle(shared.Colors.BRIGHT_CYAN, true));

            const progress_component = try ProgressBar.create(self.allocator, .{
                .progress = 0.0,
                .label = "Processing",
                .style = style,
                .showPercentage = true,
                .animated = true,
            });

            // Animate progress
            var progress: f32 = 0.0;
            while (progress <= 1.0) {
                const progress_bar_impl: *ProgressBar = @ptrCast(@alignCast(progress_component.impl));
                progress_bar_impl.setProgress(progress);

                // Position and render the progress bar
                progress_component.setBounds(shared.Rect{
                    .x = 2,
                    .y = @as(i32, @intCast(@intFromFloat(progress * 10))) + 10, // Dynamic positioning for demo
                    .width = 50,
                    .height = 2,
                });

                const ctx = self.ui_context.createRenderContext(shared.Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });
                try progress_component.render(ctx);

                // Brief pause to show animation
                std.time.sleep(50_000_000); // 50ms
                progress += 0.1;

                // Clear line for next frame
                try self.ui_context.terminal.moveTo(0, @as(i32, @intCast(@intFromFloat(progress * 10))) + 10);
                try self.ui_context.terminal.clearLine();
            }

            // Show completed state
            const progress_bar_impl: *ProgressBar = @ptrCast(@alignCast(progress_component.impl));
            progress_bar_impl.setProgress(1.0);
            const final_ctx = self.ui_context.createRenderContext(shared.Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });
            try progress_component.render(final_ctx);

            try self.ui_context.terminal.printf("\n\n", .{}, null);

            progress_component.deinit();
            self.allocator.destroy(progress_component);

            std.time.sleep(500_000_000); // 500ms between styles
        }

        try self.ui_context.terminal.printf("Press Enter to continue...", .{}, shared.createTextStyle(shared.Colors.YELLOW, false));
        try self.waitForEnter();
    }

    fn showInputDemo(self: *Self) !void {
        try self.ui_context.clear();

        try self.ui_context.terminal.printf("═══ Smart Input Component Demo ═══\n\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_MAGENTA, true));

        try self.ui_context.terminal.printf("Features demonstrated:\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_WHITE, true));
        try self.ui_context.terminal.printf("  • Progressive enhancement based on terminal capabilities\n", .{}, null);
        try self.ui_context.terminal.printf("  • Automatic suggestion system\n", .{}, null);
        try self.ui_context.terminal.printf("  • Live validation feedback\n", .{}, null);
        try self.ui_context.terminal.printf("  • Syntax highlighting (if supported)\n", .{}, null);
        try self.ui_context.terminal.printf("  • Unified component architecture\n\n", .{}, null);

        const input_component = try SmartInput.create(self.allocator, .{
            .placeholder = "Type 'hello' or 'git' for suggestions...",
            .features = .{
                .autocomplete = true,
                .syntax_highlighting = true,
                .live_validation = true,
            },
            .suggestionProvider = smart_input.defaultSuggestionProvider,
            .validator = smart_input.defaultValidator,
        });

        // Position the input component
        input_component.setBounds(shared.Rect{ .x = 2, .y = 8, .width = 60, .height = 5 });

        // Render the input component
        const ctx = self.ui_context.createRenderContext(shared.Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });
        try input_component.render(ctx);

        try self.ui_context.terminal.printf("\n\n(This is a visual demo - actual input handling requires event loop integration)\n", .{}, shared.createTextStyle(shared.Colors.YELLOW, false));

        input_component.deinit();
        self.allocator.destroy(input_component);

        try self.ui_context.terminal.printf("\nPress Enter to continue...", .{}, shared.createTextStyle(shared.Colors.YELLOW, false));
        try self.waitForEnter();
    }

    fn showNotificationDemo(self: *Self) !void {
        try self.ui_context.clear();

        try self.ui_context.terminal.printf("═══ Notification System Demo ═══\n\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_MAGENTA, true));

        const notification_types = [_]NotificationLevel{ .info, .success, .warning, .@"error", .debug };
        const messages = [_][]const u8{
            "This is an informational message",
            "Operation completed successfully!",
            "Warning: This might need attention",
            "Error: Something went wrong",
            "Debug: Internal system information",
        };
        const titles = [_][]const u8{ "Info", "Success", "Warning", "Error", "Debug" };

        try self.ui_context.terminal.printf("Demonstrating adaptive notifications:\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_WHITE, true));

        const caps = self.ui_context.getCapabilities();
        if (caps.supportsNotifyOsc9) {
            try self.ui_context.terminal.printf("  • Will use native system notifications (OSC 9)\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_GREEN, false));
        } else {
            try self.ui_context.terminal.printf("  • Will use terminal-based notifications (fallback)\n", .{}, shared.createTextStyle(shared.Colors.YELLOW, false));
        }

        try self.ui_context.terminal.printf("\nShowing different notification levels:\n\n", .{}, null);

        for (notification_types, messages, titles) |level, message, title| {
            try self.ui_context.notify(level, title, message);
            std.time.sleep(800_000_000); // 800ms between notifications
        }

        try self.ui_context.terminal.printf("\nPress Enter to continue...", .{}, shared.createTextStyle(shared.Colors.YELLOW, false));
        try self.waitForEnter();
    }

    fn showGraphicsDemo(self: *Self) !void {
        try self.ui_context.clear();

        try self.ui_context.terminal.printf("═══ Enhanced Graphics Demo ═══\n\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_MAGENTA, true));

        const caps = self.ui_context.getCapabilities();

        try self.ui_context.terminal.printf("Graphics capabilities:\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_WHITE, true));

        if (caps.supportsKittyGraphics) {
            try self.ui_context.terminal.printf("  ✓ Kitty Graphics Protocol - Best quality images\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_GREEN, false));
        } else if (caps.supportsSixel) {
            try self.ui_context.terminal.printf("  ✓ Sixel Graphics - Good quality images\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_GREEN, false));
        } else {
            try self.ui_context.terminal.printf("  ○ Using Unicode/ASCII art fallback\n", .{}, shared.createTextStyle(shared.Colors.YELLOW, false));
        }

        try self.ui_context.terminal.printf("\nDemonstrating adaptive graphics rendering:\n\n", .{}, null);

        // Create a simple pattern demo
        if (self.ui_context.graphics) |*graphics_manager| {
            // Try to create a simple progress visualization
            const vis_style = shared.graphics.ProgressVisualizationStyle{
                .width = 40,
                .height = 8,
                .style = .gradient,
            };

            const image_id = graphics_manager.createProgressVisualization(0.75, vis_style) catch {
                try self.ui_context.terminal.printf("Graphics creation failed, showing fallback...\n", .{}, shared.createTextStyle(shared.Colors.YELLOW, false));
                try self.showGraphicsFallback();
                return;
            };

            graphics_manager.renderImage(image_id, shared.Point{ .x = 2, .y = 12 }, shared.graphics.RenderOptions{}) catch {
                try self.ui_context.terminal.printf("Graphics rendering failed, showing fallback...\n", .{}, shared.createTextStyle(shared.Colors.YELLOW, false));
                try self.showGraphicsFallback();
                graphics_manager.removeImage(image_id);
                return;
            };

            graphics_manager.removeImage(image_id);

            try self.ui_context.terminal.printf("\n\n  ↑ Rendered using advanced graphics protocol\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_GREEN, false));
        } else {
            try self.showGraphicsFallback();
        }

        try self.ui_context.terminal.printf("\nPress Enter to continue...", .{}, shared.createTextStyle(shared.Colors.YELLOW, false));
        try self.waitForEnter();
    }

    fn showGraphicsFallback(self: *Self) !void {
        try self.ui_context.terminal.printf("Fallback graphics rendering:\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_WHITE, true));

        // Create a simple ASCII/Unicode art pattern
        const pattern = [_][]const u8{
            "╭─────────────────────────────────────────╮",
            "│ ████████████████████░░░░░░░░░░░░░░░░░░░░ │",
            "│ ████████████████████░░░░░░░░░░░░░░░░░░░░ │",
            "│ ████████████████████░░░░░░░░░░░░░░░░░░░░ │",
            "│                 75% Complete            │",
            "╰─────────────────────────────────────────╯",
        };

        for (pattern) |line| {
            try self.ui_context.terminal.printf("  {s}\n", .{line}, shared.createTextStyle(shared.Colors.BRIGHT_CYAN, false));
        }

        try self.ui_context.terminal.printf("  ↑ Unicode art fallback (universal compatibility)\n", .{}, shared.createTextStyle(shared.Colors.CYAN, false));
    }

    fn showFarewell(self: *Self) !void {
        try self.ui_context.clear();

        try self.ui_context.terminal.printf("╔═══════════════════════════════════════════╗\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_GREEN, true));
        try self.ui_context.terminal.printf("║              Demo Complete!               ║\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_GREEN, true));
        try self.ui_context.terminal.printf("╚═══════════════════════════════════════════╝\n\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_GREEN, true));

        try self.ui_context.terminal.printf("Key improvements demonstrated:\n\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_WHITE, true));

        try self.ui_context.terminal.printf("🔧 Unified Terminal Interface:\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_BLUE, true));
        try self.ui_context.terminal.printf("   • Single API for all terminal capabilities\n", .{}, null);
        try self.ui_context.terminal.printf("   • Automatic capability detection and adaptation\n", .{}, null);
        try self.ui_context.terminal.printf("   • Progressive enhancement based on your terminal\n\n", .{}, null);

        try self.ui_context.terminal.printf("🎨 Graphics Manager:\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_MAGENTA, true));
        try self.ui_context.terminal.printf("   • Support for Kitty Graphics Protocol and Sixel\n", .{}, null);
        try self.ui_context.terminal.printf("   • Automatic fallback to Unicode/ASCII art\n", .{}, null);
        try self.ui_context.terminal.printf("   • Built-in chart and visualization generation\n\n", .{}, null);

        try self.ui_context.terminal.printf("🧱 Component-Based Architecture:\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_CYAN, true));
        try self.ui_context.terminal.printf("   • Reusable components for CLI and TUI\n", .{}, null);
        try self.ui_context.terminal.printf("   • Consistent theming and styling system\n", .{}, null);
        try self.ui_context.terminal.printf("   • Event-driven architecture with animations\n\n", .{}, null);

        try self.ui_context.terminal.printf("🔗 Shared Integration:\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_YELLOW, true));
        try self.ui_context.terminal.printf("   • Eliminated code duplication between CLI/TUI\n", .{}, null);
        try self.ui_context.terminal.printf("   • Unified notification and progress systems\n", .{}, null);
        try self.ui_context.terminal.printf("   • Better file organization and maintainability\n\n", .{}, null);

        try self.ui_context.terminal.printf("The codebase now provides a modern, capability-aware\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_WHITE, false));
        try self.ui_context.terminal.printf("terminal interface that automatically adapts to any\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_WHITE, false));
        try self.ui_context.terminal.printf("terminal's capabilities while maintaining universal\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_WHITE, false));
        try self.ui_context.terminal.printf("compatibility. 🚀\n\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_WHITE, false));

        try self.ui_context.terminal.printf("Thank you for exploring the UI system!\n", .{}, shared.createTextStyle(shared.Colors.BRIGHT_GREEN, true));
    }

    fn waitForEnter(self: *Self) !void {
        _ = self;
        // Simplified input waiting - in real implementation would use proper input handling
        var stdin_buffer: [4096]u8 = undefined;
        const stdin_file = std.fs.File.stdin();
        var stdin_reader = stdin_file.reader(&stdin_buffer);
        var line_buffer: [10]u8 = undefined;
        _ = try stdin_reader.readUntilDelimiterOrEof(&line_buffer, '\n');
    }
};

/// Entry point for the demo
pub fn runDemo(allocator: std.mem.Allocator) !void {
    var demo = try UIDemo.init(allocator);
    defer demo.deinit();

    try demo.run();
}

test "demo initialization" {
    var demo = try UIDemo.init(std.testing.allocator);
    defer demo.deinit();
}

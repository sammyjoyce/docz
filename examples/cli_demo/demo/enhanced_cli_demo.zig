//! Enhanced CLI Capabilities Demo
//!
//! This demo showcases all the advanced terminal capabilities and components:
//! - Terminal abstraction with progressive enhancement
//! - Advanced progress component with graphics and notifications
//! - Smart input with mouse support and auto-completion
//! - Graphics integration with Kitty/Sixel/Unicode fallbacks
//! - Comprehensive terminal feature detection and utilization
//!
//! The demo automatically detects terminal capabilities and demonstrates
//! the appropriate features for maximum compatibility.

const std = @import("std");
const unified = @import("../../src/shared/term/unified.zig");

// Our enhanced components
const terminal_abstraction = @import("../core/terminal_abstraction.zig");
const advanced_progress = @import("../components/enhanced/advanced_progress.zig");
const smart_input = @import("../components/input/smart_input.zig");
const terminal_graphics = @import("../components/graphics/terminal_graphics.zig");

const Allocator = std.mem.Allocator;
const TerminalAbstraction = terminal_abstraction.TerminalAbstraction;
const AdvancedProgress = advanced_progress.AdvancedProgress;
const SmartInput = smart_input.SmartInput;
const TerminalGraphics = terminal_graphics.TerminalGraphics;

/// Demo configuration
const DemoConfig = struct {
    show_capabilities: bool = true,
    run_progress_demo: bool = true,
    run_input_demo: bool = true,
    run_graphics_demo: bool = true,
    interactive_mode: bool = true,
    duration_ms: u64 = 5000,
};

/// Enhanced CLI Demo
pub const EnhancedCliDemo = struct {
    allocator: Allocator,
    terminal: *unified.Terminal,
    abstraction: TerminalAbstraction,
    config: DemoConfig,

    pub fn init(allocator: Allocator, config: DemoConfig) !EnhancedCliDemo {
        const terminal = try allocator.create(unified.Terminal);
        terminal.* = try unified.Terminal.init(allocator);

        return EnhancedCliDemo{
            .allocator = allocator,
            .terminal = terminal,
            .abstraction = TerminalAbstraction.init(terminal),
            .config = config,
        };
    }

    pub fn deinit(self: *EnhancedCliDemo) void {
        self.terminal.deinit();
        self.allocator.destroy(self.terminal);
    }

    /// Run the complete demo
    pub fn run(self: *EnhancedCliDemo) !void {
        try self.showWelcome();

        if (self.config.show_capabilities) {
            try self.demoCapabilities();
        }

        if (self.config.run_progress_demo) {
            try self.demoAdvancedProgress();
        }

        if (self.config.run_input_demo) {
            try self.demoSmartInput();
        }

        if (self.config.run_graphics_demo) {
            try self.demoGraphics();
        }

        if (self.config.interactive_mode) {
            try self.interactiveDemo();
        }

        try self.showConclusion();
    }

    /// Show welcome message with terminal feature detection
    fn showWelcome(self: *EnhancedCliDemo) !void {
        try self.abstraction.clear();

        // Welcome header with styling
        const header_style = terminal_abstraction.CliStyles.HEADER;
        try self.abstraction.print("🚀 Enhanced CLI Capabilities Demo\n", header_style);
        try self.abstraction.print("=====================================\n\n", terminal_abstraction.CliStyles.ACCENT);

        // Terminal info
        const features = self.abstraction.getFeatures();

        try self.abstraction.print("Terminal Features Detected:\n", terminal_abstraction.CliStyles.INFO);
        try self.printFeature("True Color Support", features.truecolor);
        try self.printFeature("Graphics Protocol", features.graphics);
        try self.printFeature("Hyperlink Support", features.hyperlinks);
        try self.printFeature("Clipboard Integration", features.clipboard);
        try self.printFeature("System Notifications", features.notifications);
        try self.printFeature("Mouse Support", features.mouse_support);
        try self.printFeature("Synchronized Output", features.synchronized_output);
        try self.printFeature("Shell Integration", features.shell_integration);

        try self.abstraction.print("\n", null);
        try self.waitForUser();
    }

    /// Demonstrate advanced progress component
    fn demoAdvancedProgress(self: *EnhancedCliDemo) !void {
        try self.showSectionHeader("🎯 Advanced Progress Component");

        // Configure advanced progress
        const progress_config = advanced_progress.AdvancedProgressConfig{
            .width = 50,
            .label = "Processing Data",
            .show_rate = true,
            .show_eta = true,
            .show_chart = true,
            .enable_notifications = true,
            .enable_clipboard = true,
            .enable_shell_integration = true,
        };

        var progress_comp = try AdvancedProgress.init(self.allocator, self.terminal, progress_config);
        defer progress_comp.deinit();

        // Simulate work with progress updates
        const total_items = 100;
        try progress_comp.start(total_items);

        for (0..total_items) |i| {
            const progress = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(total_items - 1));
            const completed = i + 1;

            // Add some custom data for demonstration
            const custom_data = if (i % 10 == 0)
                try std.fmt.allocPrint(self.allocator, "milestone_{d}", .{i / 10})
            else
                null;
            defer if (custom_data) |data| self.allocator.free(data);

            try progress_comp.update(progress, completed, custom_data);
            try progress_comp.render(false);

            // Variable delay to show different rates
            const delay_ms: u64 = if (i < 20) 100 else if (i < 80) 50 else 150;
            std.time.sleep(delay_ms * std.time.ns_per_ms);
        }

        try progress_comp.finish(true, "Data processing completed successfully!");

        try self.abstraction.print("\n✅ Progress demo complete!\n", terminal_abstraction.CliStyles.SUCCESS);
        try self.waitForUser();
    }

    /// Demonstrate smart input component
    fn demoSmartInput(self: *EnhancedCliDemo) !void {
        try self.showSectionHeader("💬 Smart Input Component");

        try self.abstraction.print("This demo shows smart input features:\n", null);
        try self.abstraction.print("• Mouse support for cursor positioning\n", null);
        try self.abstraction.print("• Real-time validation\n", null);
        try self.abstraction.print("• Auto-completion\n", null);
        try self.abstraction.print("• History navigation (↑/↓)\n", null);
        try self.abstraction.print("• Clipboard integration (Ctrl+V)\n", null);
        try self.abstraction.print("• Syntax highlighting\n\n", null);

        // Configure smart input
        const input_config = smart_input.SmartInputConfig{
            .prompt = "🔍 Enter command: ",
            .enable_completion = true,
            .enable_validation = true,
            .enable_mouse = true,
            .enable_history = true,
            .syntax_type = .shell_command,
            .completion_provider = demoCompletionProvider,
            .validator = demoValidator,
        };

        var input_comp = try SmartInput.init(self.allocator, self.abstraction, input_config);
        defer input_comp.deinit();

        // In a real implementation, this would read actual input
        try self.abstraction.print("Demo Input: 'ls --help'\n", terminal_abstraction.CliStyles.INFO);
        try self.abstraction.print("(In actual implementation, you would type interactively)\n\n", terminal_abstraction.CliStyles.MUTED);

        // Simulate validation feedback
        try self.abstraction.print("  ✓ Command validated successfully\n", terminal_abstraction.CliStyles.SUCCESS);
        try self.abstraction.print("  📋 Auto-completion suggestions: ls, list, ln, locate\n", terminal_abstraction.CliStyles.INFO);
        try self.abstraction.print("  🖱️  Mouse support: Click to position cursor\n", terminal_abstraction.CliStyles.INFO);

        try self.abstraction.print("\n✅ Smart input demo complete!\n", terminal_abstraction.CliStyles.SUCCESS);
        try self.waitForUser();
    }

    /// Demonstrate graphics integration
    fn demoGraphics(self: *EnhancedCliDemo) !void {
        try self.showSectionHeader("🎨 Graphics Integration");

        // Configure graphics
        const graphics_config = terminal_graphics.GraphicsConfig{
            .width = 60,
            .height = 20,
            .color_scheme = .rainbow,
            .enable_animation = true,
        };

        var graphics = try TerminalGraphics.init(self.allocator, self.abstraction, graphics_config);
        defer graphics.deinit();

        // Generate sample data
        const data_points = try self.allocator.alloc(terminal_graphics.DataPoint, 20);
        defer self.allocator.free(data_points);

        // Create sine wave data
        for (data_points, 0..) |*point, i| {
            const x = @as(f64, @floatFromInt(i));
            const y = @sin(x * 0.5) * 10 + 15; // Scale and offset
            point.* = terminal_graphics.DataPoint{
                .x = x,
                .y = y,
                .label = null,
            };
        }

        // Create dataset
        const dataset = terminal_graphics.Dataset{
            .name = "Sample Data",
            .data = data_points,
            .color = terminal_abstraction.CliColors.PRIMARY,
        };

        const datasets = [_]terminal_graphics.Dataset{dataset};

        // Render different chart types
        try self.abstraction.print("Line Chart:\n", terminal_abstraction.CliStyles.HEADER);
        _ = try graphics.renderChart(.line, &datasets, "Sample Sine Wave", "Time", "Value");
        try self.abstraction.print("\n", null);

        try self.abstraction.print("Bar Chart:\n", terminal_abstraction.CliStyles.HEADER);
        _ = try graphics.renderChart(.bar, &datasets, "Sample Bar Data", "Index", "Value");
        try self.abstraction.print("\n", null);

        try self.abstraction.print("Sparkline:\n", terminal_abstraction.CliStyles.HEADER);
        _ = try graphics.renderChart(.sparkline, &datasets, "Trend", null, null);
        try self.abstraction.print("\n", null);

        // Progress with graphics
        try self.abstraction.print("Progress with Chart:\n", terminal_abstraction.CliStyles.HEADER);
        const progress_history = [_]f32{ 0.1, 0.3, 0.45, 0.7, 0.85, 0.9 };
        try graphics.renderProgressWithChart(0.9, &progress_history, "Data Processing");
        try self.abstraction.print("\n", null);

        try self.abstraction.print("✅ Graphics demo complete!\n", terminal_abstraction.CliStyles.SUCCESS);
        try self.waitForUser();
    }

    /// Interactive demonstration mode
    fn interactiveDemo(self: *EnhancedCliDemo) !void {
        try self.showSectionHeader("🎮 Interactive Demonstration");

        try self.abstraction.print("Interactive features demonstrated:\n\n", null);

        // Hyperlink demo
        if (self.abstraction.getFeatures().hyperlinks) {
            try self.abstraction.print("🔗 Hyperlinks: ", null);
            try self.abstraction.hyperlink("https://github.com/sam/docz", "Project Repository", terminal_abstraction.CliStyles.ACCENT);
            try self.abstraction.print("\n", null);
        }

        // Clipboard demo
        if (self.abstraction.getFeatures().clipboard) {
            try self.abstraction.print("📋 Clipboard: ", null);
            const demo_data = "Enhanced CLI Demo - Terminal capabilities detected and demonstrated!";
            try self.abstraction.copyToClipboard(demo_data);
            try self.abstraction.print("Demo data copied to clipboard!\n", terminal_abstraction.CliStyles.SUCCESS);
        }

        // Notifications demo
        if (self.abstraction.getFeatures().notifications) {
            try self.abstraction.print("🔔 Notifications: ", null);
            try self.abstraction.notify(.info, "Demo Notification", "All terminal features working correctly!");
            try self.abstraction.print("System notification sent!\n", terminal_abstraction.CliStyles.SUCCESS);
        }

        // Real-time data simulation
        try self.abstraction.print("\n📊 Real-time Data Simulation:\n", terminal_abstraction.CliStyles.HEADER);
        try self.simulateRealTimeData();

        try self.abstraction.print("\n✅ Interactive demo complete!\n", terminal_abstraction.CliStyles.SUCCESS);
    }

    /// Show conclusion and feature summary
    fn showConclusion(self: *EnhancedCliDemo) !void {
        try self.showSectionHeader("🎉 Demo Conclusion");

        try self.abstraction.print("Enhanced CLI capabilities demonstrated:\n\n", null);

        const features_demonstrated = [_]struct { name: []const u8, icon: []const u8 }{
            .{ .name = "Progressive terminal enhancement", .icon = "🔄" },
            .{ .name = "Advanced progress with graphics", .icon = "📊" },
            .{ .name = "Smart input with mouse support", .icon = "🖱️" },
            .{ .name = "Multi-protocol graphics rendering", .icon = "🎨" },
            .{ .name = "Automatic capability detection", .icon = "🔍" },
            .{ .name = "Graceful fallback systems", .icon = "📉" },
            .{ .name = "System integration features", .icon = "🔗" },
            .{ .name = "Enhanced user experience", .icon = "✨" },
        };

        for (features_demonstrated) |feature| {
            try self.abstraction.printf("  {s} {s}\n", .{ feature.icon, feature.name }, terminal_abstraction.CliStyles.SUCCESS);
        }

        try self.abstraction.print("\n", null);

        // Summary of component improvements
        try self.abstraction.print("Component Improvements Made:\n\n", terminal_abstraction.CliStyles.HEADER);

        const improvements = [_][]const u8{
            "• Unified terminal abstraction layer",
            "• Enhanced progress with Kitty/Sixel graphics",
            "• Smart input with real-time validation",
            "• Graphics integration with fallback chain",
            "• Better organized component structure",
            "• Comprehensive terminal feature utilization",
        };

        for (improvements) |improvement| {
            try self.abstraction.print(improvement, terminal_abstraction.CliStyles.INFO);
            try self.abstraction.print("\n", null);
        }

        try self.abstraction.print("\n🚀 Enhanced CLI demo complete!", terminal_abstraction.CliStyles.HEADER);
        try self.abstraction.print("\nThank you for exploring the advanced terminal capabilities!\n", null);
    }

    // ========== HELPER FUNCTIONS ==========

    fn showSectionHeader(self: *EnhancedCliDemo, title: []const u8) !void {
        try self.abstraction.print("\n", null);
        try self.abstraction.print("=".repeat(50), terminal_abstraction.CliStyles.ACCENT);
        try self.abstraction.print("\n", null);
        try self.abstraction.print(title, terminal_abstraction.CliStyles.HEADER);
        try self.abstraction.print("\n", null);
        try self.abstraction.print("=".repeat(50), terminal_abstraction.CliStyles.ACCENT);
        try self.abstraction.print("\n\n", null);
    }

    fn printFeature(self: *EnhancedCliDemo, name: []const u8, supported: bool) !void {
        const icon = if (supported) "✅" else "❌";
        const style = if (supported) terminal_abstraction.CliStyles.SUCCESS else terminal_abstraction.CliStyles.MUTED;

        try self.abstraction.printf("  {s} {s}\n", .{ icon, name }, style);
    }

    fn waitForUser(self: *EnhancedCliDemo) !void {
        try self.abstraction.print("\n💡 Press Enter to continue...", terminal_abstraction.CliStyles.MUTED);

        // In a real implementation, this would wait for actual user input
        // For demo purposes, just add a short delay
        std.time.sleep(2 * std.time.ns_per_s);
        try self.abstraction.print(" ⏭️\n", null);
    }

    fn simulateRealTimeData(self: *EnhancedCliDemo) !void {
        var data_history = try self.allocator.alloc(f32, 10);
        defer self.allocator.free(data_history);

        // Initialize with random-like data
        var prng = std.rand.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
        const random = prng.random();

        for (data_history) |*value| {
            value.* = random.float(f32);
        }

        // Simulate 10 updates
        for (0..10) |i| {
            // Update data
            const new_value = random.float(f32);

            // Shift array left and add new value
            std.mem.copyForwards(f32, data_history[0..9], data_history[1..10]);
            data_history[9] = new_value;

            // Clear line and show updated data
            try self.abstraction.print("\r\x1b[K", null);
            try self.abstraction.printf("Update #{d}: ", .{i + 1}, terminal_abstraction.CliStyles.INFO);

            // Show sparkline
            const sparkline_chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
            try self.abstraction.print("[", null);
            for (data_history) |value| {
                const char_idx = @as(usize, @intFromFloat(value * 7.0));
                try self.abstraction.print(sparkline_chars[@min(char_idx, sparkline_chars.len - 1)], terminal_abstraction.CliStyles.ACCENT);
            }
            try self.abstraction.print("]", null);
            try self.abstraction.printf(" {d:.3}", .{new_value}, terminal_abstraction.CliStyles.SUCCESS);

            std.time.sleep(500 * std.time.ns_per_ms);
        }
    }
};

// ========== DEMO COMPLETION PROVIDERS ==========

fn demoCompletionProvider(
    input: []const u8,
    cursor_pos: usize,
    context: ?*anyopaque,
    allocator: Allocator,
) anyerror![]smart_input.Suggestion {
    _ = cursor_pos;
    _ = context;

    const commands = [_][]const u8{ "ls", "list", "ln", "locate", "less", "cat", "cd", "pwd", "help" };

    var suggestions = std.ArrayList(smart_input.Suggestion).init(allocator);

    for (commands) |command| {
        if (std.mem.startsWith(u8, command, input)) {
            try suggestions.append(smart_input.Suggestion{
                .text = try allocator.dupe(u8, command),
                .description = try std.fmt.allocPrint(allocator, "Command: {s}", .{command}),
                .score = 1.0,
            });
        }
    }

    return suggestions.toOwnedSlice();
}

fn demoValidator(input: []const u8, context: ?*anyopaque) smart_input.ValidationResult {
    _ = context;

    if (input.len == 0) {
        return smart_input.ValidationResult{ .info = "Enter a command..." };
    } else if (std.mem.startsWith(u8, input, "rm")) {
        return smart_input.ValidationResult{ .warning = "Dangerous command - use with caution!" };
    } else if (std.mem.indexOf(u8, input, "--help") != null) {
        return smart_input.ValidationResult{ .valid = {} };
    } else {
        return smart_input.ValidationResult{ .valid = {} };
    }
}

// ========== MAIN DEMO ENTRY POINT ==========

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = DemoConfig{
        .show_capabilities = true,
        .run_progress_demo = true,
        .run_input_demo = true,
        .run_graphics_demo = true,
        .interactive_mode = true,
    };

    var demo = try EnhancedCliDemo.init(allocator, config);
    defer demo.deinit();

    try demo.run();
}

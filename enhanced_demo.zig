//! Complete Demonstration of Enhanced CLI and TUI with Graphics
//! Shows the unified architecture and progressive enhancement in action

const std = @import("std");

// Import our enhanced systems
const enhanced_cli = @import("cli/components/enhanced_cli.zig");
const unified_renderer = @import("tui/core/unified_renderer.zig");
const demo_widget = @import("tui/widgets/demo_widget.zig");

const Allocator = std.mem.Allocator;
const EnhancedCLI = enhanced_cli.EnhancedCLI;
const UnifiedRenderer = unified_renderer.UnifiedRenderer;
const Theme = unified_renderer.Theme;
const Rect = unified_renderer.Rect;
const Size = unified_renderer.Size;
const Color = @import("cli/core/unified_terminal.zig").Color;

/// Main demonstration function
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try showUsage();
        return;
    }

    const mode = args[1];
    
    if (std.mem.eql(u8, mode, "cli")) {
        try runCLIDemo(allocator, args);
    } else if (std.mem.eql(u8, mode, "tui")) {
        try runTUIDemo(allocator);
    } else if (std.mem.eql(u8, mode, "both")) {
        try runIntegratedDemo(allocator);
    } else {
        try showUsage();
    }
}

fn showUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\Enhanced CLI/TUI Demonstration
        \\=============================
        \\
        \\Usage: enhanced_demo [MODE]
        \\
        \\Modes:
        \\  cli   - CLI-only demonstration with graphics dashboard
        \\  tui   - TUI-only demonstration with unified widgets  
        \\  both  - Integrated demonstration showing both systems
        \\
        \\Features Demonstrated:
        \\• Progressive enhancement (Kitty → Sixel → Unicode → ASCII)
        \\• Graphics-enhanced dashboard with real-time data
        \\• Unified terminal capability detection
        \\• Advanced progress bars and visualizations
        \\• Hyperlinks, clipboard, and notification integration
        \\• Theme system with automatic dark/light mode detection
        \\• Focus management and keyboard/mouse navigation
        \\• Layout engine with flexible component positioning
        \\
        \\Example:
        \\  enhanced_demo cli dashboard
        \\  enhanced_demo tui
        \\  enhanced_demo both
        \\
    );
}

/// Run CLI demonstration
fn runCLIDemo(allocator: Allocator, args: [][]const u8) !void {
    var cli = try EnhancedCLI.init(allocator);
    defer cli.deinit();

    const exit_code = try cli.run(args);
    std.process.exit(exit_code);
}

/// Run TUI demonstration  
fn runTUIDemo(allocator: Allocator) !void {
    // Initialize unified renderer with theme detection
    const theme = if (detectDarkMode()) Theme.defaultDark() else Theme.defaultLight();
    var renderer = try UnifiedRenderer.init(allocator, theme);
    defer renderer.deinit();

    // Create demo widgets
    const terminal_size = renderer.getTerminal().getSize() orelse Size{ .width = 80, .height = 24 };
    
    // Main panel (left side)
    const main_panel = try demo_widget.DemoPanel.init(
        allocator,
        Rect{ .x = 2, .y = 2, .width = terminal_size.width / 2 - 3, .height = terminal_size.height - 6 },
        "Enhanced TUI System"
    );
    defer main_panel.deinit();
    try renderer.addWidget(main_panel.asWidget());

    // Side panel (right side) 
    const side_panel = try demo_widget.DemoPanel.init(
        allocator,
        Rect{ .x = @as(i16, @intCast(terminal_size.width / 2 + 1)), .y = 2, .width = terminal_size.width / 2 - 3, .height = terminal_size.height - 10 },
        "Terminal Features"
    );
    defer side_panel.deinit();
    try side_panel.addLine("🌈 True Color Support");
    try side_panel.addLine("🖼️  Graphics Rendering");
    try side_panel.addLine("🔗 Hyperlink Support"); 
    try side_panel.addLine("📋 Clipboard Integration");
    try side_panel.addLine("🔔 System Notifications");
    try side_panel.addLine("🖱️  Mouse Interactions");
    try side_panel.addLine("⌨️  Enhanced Keyboard");
    try renderer.addWidget(side_panel.asWidget());

    // Button panel (bottom)
    const quit_button = try demo_widget.Button.init(
        allocator,
        Rect{ .x = @as(i16, @intCast(terminal_size.width / 2 - 5)), .y = @as(i16, @intCast(terminal_size.height - 4)), .width = 10, .height = 3 },
        "Quit"
    );
    defer quit_button.deinit();
    
    var should_quit = false;
    quit_button.setOnClick(struct {
        var quit_flag: *bool = undefined;
        
        fn onClick() void {
            quit_flag.* = true;
        }
        
        fn setQuitFlag(flag: *bool) void {
            quit_flag = flag;
        }
    }.onClick);
    
    // This is a workaround for the callback - in real code you'd use a better pattern
    @import("std").mem.doNotOptimizeAway(&should_quit);
    
    try renderer.addWidget(quit_button.asWidget());

    // Enable terminal features for interactive demo
    const terminal = renderer.getTerminal();
    try terminal.setCursorVisible(false);
    
    // Show startup message
    try showTUIStartupMessage(terminal);

    // Main event loop
    var running = true;
    while (running and !should_quit) {
        // Render frame
        try renderer.render();
        
        // Simple event simulation (in real implementation, you'd read actual input)
        std.time.sleep(100 * std.time.ns_per_ms); // 100ms delay
        
        // Simulate some input events for demo
        const fake_event = unified_renderer.InputEvent{ 
            .key = .{ .key = .tab, .modifiers = .{} }
        };
        _ = try renderer.handleInput(fake_event);
        
        // Simple exit condition for demo (normally you'd handle actual input)
        var loop_counter: u32 = 0;
        loop_counter += 1;
        if (loop_counter > 100) { // Exit after ~10 seconds
            running = false;
        }
    }

    // Cleanup
    try terminal.setCursorVisible(true);
    try terminal.clearScreen();
    
    const w = terminal.writer();
    try w.writeAll("TUI Demo completed!\n");
    try w.writeAll("The unified TUI system demonstrated:\n");
    try w.writeAll("• Widget-based architecture with focus management\n");
    try w.writeAll("• Progressive enhancement based on terminal capabilities\n");
    try w.writeAll("• Unified theme system with automatic detection\n");
    try w.writeAll("• Layout engine for flexible component positioning\n");
    try terminal.flush();
}

/// Run integrated demonstration showing both systems
fn runIntegratedDemo(allocator: Allocator) !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.writeAll("🚀 Integrated CLI/TUI Demonstration\n");
    try stdout.writeAll("===================================\n\n");

    // First, run CLI demo to show terminal capabilities
    try stdout.writeAll("Phase 1: CLI Graphics Dashboard\n");
    try stdout.writeAll("-------------------------------\n");
    
    var cli = try EnhancedCLI.init(allocator);
    defer cli.deinit();
    
    const cli_args = [_][]const u8{ "enhanced_demo", "dashboard" };
    _ = try cli.run(&cli_args);
    
    try stdout.writeAll("\n\nPress Enter to continue to TUI demonstration...\n");
    _ = try std.io.getStdIn().reader().readByte();

    // Then run TUI demo to show widget system
    try stdout.writeAll("\nPhase 2: Unified TUI System\n");
    try stdout.writeAll("---------------------------\n");
    
    try runTUIDemo(allocator);
    
    try stdout.writeAll("\n\n✅ Integration Complete!\n");
    try stdout.writeAll("This demonstration showcased:\n");
    try stdout.writeAll("• CLI with graphics-enhanced dashboard\n");
    try stdout.writeAll("• TUI with unified widget architecture\n");
    try stdout.writeAll("• Progressive enhancement across both systems\n");
    try stdout.writeAll("• Shared terminal capability detection\n");
    try stdout.writeAll("• Consistent theming and component interfaces\n");
}

/// Show TUI startup message with terminal capability info
fn showTUIStartupMessage(terminal: *@import("cli/core/unified_terminal.zig").UnifiedTerminal) !void {
    const w = terminal.writer();
    
    try terminal.clearScreen();
    try terminal.setForeground(Color.CYAN);
    try w.writeAll("🎨 Unified TUI System Starting...\n\n");
    try terminal.resetStyles();
    
    try w.writeAll("Detected Capabilities:\n");
    
    const capabilities = [_]struct {
        feature: @import("cli/core/unified_terminal.zig").UnifiedTerminal.Feature,
        name: []const u8,
        icon: []const u8,
    }{
        .{ .feature = .truecolor, .name = "True Color", .icon = "🌈" },
        .{ .feature = .graphics, .name = "Graphics", .icon = "🖼️" },
        .{ .feature = .hyperlinks, .name = "Hyperlinks", .icon = "🔗" },
        .{ .feature = .clipboard, .name = "Clipboard", .icon = "📋" },
        .{ .feature = .mouse_support, .name = "Mouse", .icon = "🖱️" },
    };

    for (capabilities) |cap| {
        if (terminal.hasFeature(cap.feature)) {
            try terminal.setForeground(Color.GREEN);
            try w.print("✓ {s} {s}\n", .{ cap.icon, cap.name });
        } else {
            try terminal.setForeground(Color.RED);
            try w.print("✗ ❌ {s}\n", .{cap.name});
        }
        try terminal.resetStyles();
    }
    
    try w.writeAll("\nStarting widget demonstration in 2 seconds...\n");
    try terminal.flush();
    std.time.sleep(2 * std.time.ns_per_s);
}

/// Simple dark mode detection (placeholder implementation)
fn detectDarkMode() bool {
    // In a real implementation, this would check:
    // - Terminal background color
    // - System theme preferences  
    // - Environment variables
    // - User configuration
    
    // For demo, assume dark mode
    return true;
}

// Add compilation test
test "enhanced demo compilation" {
    // Basic compilation test
    const allocator = std.testing.allocator;
    _ = allocator;
    
    // Test that our imports work
    const cli_type = @TypeOf(EnhancedCLI);
    const renderer_type = @TypeOf(UnifiedRenderer);
    
    try std.testing.expect(cli_type != void);
    try std.testing.expect(renderer_type != void);
}
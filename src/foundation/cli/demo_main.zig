//! CLI Main Entry Point
//!
//! This demonstrates how to integrate the CLI components with the
//! existing CLI framework to provide progressive terminal capabilities.

const std = @import("std");
const shared_components = @import("../components/mod.zig");
const term_shared = @import("term_shared");
const terminal = term_shared.common;
const terminal_bridge = @import("core/terminal_bridge.zig");
const components = @import("../components/mod.zig");
const notification = @import("notifications.zig");
const input_mod = shared.components.input;
const demo = @import("demos/capabilities_presenters_demo.zig");

/// CLI Application that uses the terminal interface
pub const App = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    bridge: terminal_bridge.Bridge,
    notifications: notification.Notification,

    pub fn init(allocator: std.mem.Allocator) !Self {
        // Initialize terminal bridge with full capabilities
        const bridge_config = terminal_bridge.Config{
            .enable_buffering = true,
            .enable_graphics = true,
            .enable_notifications = true,
            .enable_clipboard = true,
            .cache_capabilities = true,
        };

        var bridge = try terminal_bridge.Bridge.init(allocator, bridge_config);

        // Initialize notification system
        const notification_config = notification.NotificationConfig{
            .enable_system_notifications = true,
            .show_timestamp = true,
            .show_icons = true,
            .enable_clipboard_actions = true,
            .enable_hyperlinks = true,
        };

        const notifications = notification.Notification.init(&bridge, notification_config);

        return Self{
            .allocator = allocator,
            .bridge = bridge,
            .notifications = notifications,
        };
    }

    pub fn deinit(self: *Self) void {
        self.bridge.deinit();
    }

    /// Main CLI run method with capabilities
    pub fn run(self: *Self, args: []const []const u8) !u8 {
        // Show welcome message with terminal capabilities
        try self.showWelcome();

        // Parse command line arguments
        if (args.len == 0) {
            try self.showHelp();
            return 0;
        }

        const command = args[0];
        const command_args = if (args.len > 1) args[1..] else &[_][]const u8{};

        // Execute command with error handling
        const result = self.executeCommand(command, command_args) catch |err| {
            try self.handleError(command, err);
            return 1;
        };

        return result;
    }

    /// Show welcome message with detected capabilities
    fn showWelcome(self: *Self) !void {
        const strategy = self.bridge.getRenderStrategy();

        // Only show capabilities in interactive mode or with verbose flag
        if (strategy.supportsColor()) {
            try self.bridge.printf("🚀 CLI v1.0 ", .{}, terminal_bridge.Styles.INFO);
            try self.bridge.printf("({s})\n", .{@tagName(strategy)}, terminal_bridge.Styles.MUTED);
        }
    }

    /// Execute a command with features
    fn executeCommand(self: *Self, command: []const u8, args: []const []const u8) !u8 {
        if (std.mem.eql(u8, command, "demo")) {
            try demo.runDemo(self.allocator, args);
            return 0;
        }

        if (std.mem.eql(u8, command, "progress")) {
            try self.runProgressCommand(args);
            return 0;
        }

        if (std.mem.eql(u8, command, "notify")) {
            try self.runNotifyCommand(args);
            return 0;
        }

        if (std.mem.eql(u8, command, "input")) {
            try self.runInputCommand(args);
            return 0;
        }

        if (std.mem.eql(u8, command, "capabilities")) {
            try self.showCapabilities();
            return 0;
        }

        if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
            try self.showHelp();
            return 0;
        }

        // Unknown command
        try self.notifications.show(.@"error", "Unknown Command", command);
        try self.showHelp();
        return 1;
    }

    /// Run progress command with various options
    fn runProgressCommand(self: *Self, args: []const []const u8) !void {
        const count = if (args.len > 0)
            std.fmt.parseInt(u32, args[0], 10) catch 50
        else
            50;

        const theme = if (args.len > 1) args[1] else "default";

        // Create progress bar based on theme
        const config = if (std.mem.eql(u8, theme, "rainbow"))
            components.ProgressConfig{ .color_scheme = .rainbow, .width = 50, .show_percentage = true, .show_eta = true }
        else if (std.mem.eql(u8, theme, "fire"))
            components.ProgressConfig{ .color_scheme = .fire, .width = 60, .show_rate = true }
        else
            components.ProgressConfig{};

        var progress_bar = components.UnifiedProgressBar.init(&self.bridge, config);
        defer progress_bar.deinit();

        try self.notifications.show(.info, "Progress Demo", "Starting progress simulation");

        for (0..count) |i| {
            try progress_bar.update(@as(f64, @floatFromInt(i + 1)), @as(f64, @floatFromInt(count)), true);
            std.time.sleep(50_000_000); // 50ms delay
        }

        try self.bridge.print("\n", null);
        try self.notifications.show(.success, "Complete", "Progress simulation finished!");
    }

    /// Run notification command
    fn runNotifyCommand(self: *Self, args: []const []const u8) !void {
        if (args.len < 2) {
            try self.bridge.print("Usage: notify <type> <title> [message]\n", terminal_bridge.Styles.errorStyle);
            return;
        }

        const type_str = args[0];
        const title = args[1];
        const message = if (args.len > 2) args[2] else "Default message";

        const notification_type = if (std.mem.eql(u8, type_str, "info"))
            notification.NotificationType.info
        else if (std.mem.eql(u8, type_str, "success"))
            notification.NotificationType.success
        else if (std.mem.eql(u8, type_str, "warning"))
            notification.NotificationType.warning
        else if (std.mem.eql(u8, type_str, "error"))
            notification.NotificationType.@"error"
        else if (std.mem.eql(u8, type_str, "critical"))
            notification.NotificationType.critical
        else
            notification.NotificationType.info;

        try self.notifications.show(notification_type, title, message);
    }

    /// Run input command to demonstrate smart input
    fn runInputCommand(self: *Self, args: []const []const u8) !void {
        const input_type = if (args.len > 0) args[0] else "text";

        try self.bridge.printf("Smart Input Demo: {s}\n", .{input_type}, terminal_bridge.Styles.INFO);
        try self.bridge.print("(This is a demonstration - real input handling would be interactive)\n\n", terminal_bridge.Styles.MUTED);

        // Show what different input types would look like
        if (std.mem.eql(u8, input_type, "email")) {
            var input = input_mod.InputPresets.email(&self.bridge);
            defer input.deinit();

            // Simulate email input with validation
            try input.current_input.appendSlice("user@example.com");
            const validation = input.validateInput();

            try self.bridge.print("Email input: ", null);
            try self.bridge.print("user", terminal.Style{ .fg_color = terminal.Colors.CYAN });
            try self.bridge.print("@example.com", terminal.Style{ .fg_color = terminal.Colors.GREEN });

            switch (validation) {
                .valid => try self.bridge.print(" ✓", terminal_bridge.Styles.success),
                .invalid => |msg| try self.bridge.printf(" ✗ {s}", .{msg}, terminal_bridge.Styles.errorStyle),
                .warning => |msg| try self.bridge.printf(" ⚠ {s}", .{msg}, terminal.Style{ .fg_color = terminal.Colors.YELLOW }),
            }
            try self.bridge.print("\n", null);
        }

        try self.notifications.show(.info, "Input Demo", "Smart input validation showcased");
    }

    /// Show detailed terminal capabilities
    fn showCapabilities(self: *Self) !void {
        try self.bridge.print("Terminal Capabilities Report\n", terminal_bridge.Styles.HIGHLIGHT);
        try self.bridge.print("═══════════════════════════\n\n", terminal_bridge.Styles.HIGHLIGHT);

        const caps = self.bridge.getCapabilities();
        const strategy = self.bridge.getRenderStrategy();

        try self.bridge.printf("Rendering Strategy: {s}\n", .{@tagName(strategy)}, terminal_bridge.Styles.INFO);
        try self.bridge.printf("Color Support: {d} colors\n", .{strategy.colorCount()}, null);
        try self.bridge.printf("Graphics Support: {s}\n", .{if (strategy.supportsGraphics()) "Yes" else "No"}, null);
        try self.bridge.print("\n", null);

        const features = [_]struct { name: []const u8, supported: bool }{
            .{ .name = "Truecolor", .supported = caps.supportsTruecolor },
            .{ .name = "Kitty Graphics", .supported = caps.supportsKittyGraphics },
            .{ .name = "Sixel Graphics", .supported = caps.supportsSixel },
            .{ .name = "Hyperlinks", .supported = caps.supportsHyperlinkOsc8 },
            .{ .name = "Clipboard", .supported = caps.supportsClipboardOsc52 },
            .{ .name = "Notifications", .supported = caps.supportsNotifyOsc9 },
            .{ .name = "Mouse Support", .supported = caps.supportsSgrMouse },
        };

        for (features) |feature| {
            const status = if (feature.supported) "✅ Supported" else "❌ Not supported";
            const color = if (feature.supported) terminal.Colors.GREEN else terminal.Colors.RED;

            try self.bridge.printf("{s:<15} {s}\n", .{ feature.name, status }, terminal.Style{ .fg_color = color });
        }

        try self.bridge.print("\n", null);

        // Performance metrics
        const metrics = self.bridge.getMetrics();
        if (metrics.render_calls > 0) {
            try self.bridge.print("Performance Metrics:\n", terminal_bridge.Styles.INFO);
            try self.bridge.printf("  Render calls: {d}\n", .{metrics.render_calls}, null);
            try self.bridge.printf("  Avg render time: {d:.2}ms\n", .{metrics.averageRenderTime()}, null);
        }
    }

    /// Show help information
    fn showHelp(self: *Self) !void {
        try self.bridge.print("Enhanced CLI - Terminal Capabilities Showcase\n\n", terminal_bridge.Styles.HIGHLIGHT);

        try self.bridge.print("Commands:\n", terminal_bridge.Styles.INFO);
        try self.bridge.print("  demo                    Run the full capabilities demo\n", null);
        try self.bridge.print("  progress [count] [theme] Show progress bar demo\n", null);
        try self.bridge.print("  notify <type> <title> [msg] Send notification\n", null);
        try self.bridge.print("  input [type]            Show smart input demo\n", null);
        try self.bridge.print("  capabilities            Show terminal capabilities\n", null);
        try self.bridge.print("  help                    Show this help\n", null);

        try self.bridge.print("\nExamples:\n", terminal_bridge.Styles.INFO);
        try self.bridge.print("  cli demo\n", terminal_bridge.Styles.MUTED);
        try self.bridge.print("  cli progress 100 rainbow\n", terminal_bridge.Styles.MUTED);
        try self.bridge.print("  cli notify success 'Build Complete' 'All tests passed'\n", terminal_bridge.Styles.MUTED);
        try self.bridge.print("  cli input email\n", terminal_bridge.Styles.MUTED);
    }

    /// Handle command execution errors with error reporting
    fn handleError(self: *Self, command: []const u8, err: anyerror) !void {
        const error_msg = try std.fmt.allocPrint(self.allocator, "Failed to execute '{s}': {s}", .{ command, @errorName(err) });
        defer self.allocator.free(error_msg);

        // Try to provide helpful suggestions based on error type
        const suggestion = switch (err) {
            error.OutOfMemory => "Try reducing the operation size or increase available memory",
            error.InvalidArgument => "Check command arguments and try again",
            error.FileNotFound => "Make sure all required files exist",
            else => "Use 'help' command for usage information",
        };

        const actions = [_]notification.NotificationAction{
            .{
                .label = "View Help",
                .action = .{ .execute_command = "help" },
            },
        };

        try self.notifications.showWithActions(.@"error", "Command Error", error_msg, &actions);

        try self.bridge.printf("💡 Suggestion: {s}\n", .{suggestion}, terminal_bridge.Styles.INFO);
    }
};

/// Main entry point for CLI
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cli_args = if (args.len > 1) args[1..] else &[_][]const u8{};

    var app = try App.init(allocator);
    defer app.deinit();

    const exit_code = try app.run(cli_args);
    std.process.exit(exit_code);
}

test "cli initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator);
    defer app.deinit();

    // Basic functionality test
    const exit_code = try app.run(&[_][]const u8{"help"});
    try std.testing.expect(exit_code == 0);
}

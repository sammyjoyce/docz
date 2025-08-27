//! Enhanced CLI Components Demo
//! Demonstrates the new advanced CLI components with terminal capabilities

const std = @import("std");
const components = @import("components/mod.zig");

const InputManager = components.InputManager;
const EnhancedSelectMenu = components.EnhancedSelectMenu;
const RichProgressBar = components.RichProgressBar;
const InfoPanel = components.InfoPanel;
const StatusIndicator = components.StatusIndicator;
const BreadcrumbTrail = components.BreadcrumbTrail;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll("🎉 Enhanced CLI Components Demo\n");
    try stdout.writeAll("=====================================\n\n");

    // Test InfoPanel
    try demonstrateInfoPanel(allocator, stdout);

    // Test StatusIndicator
    try demonstrateStatusIndicator(stdout);

    // Test BreadcrumbTrail
    try demonstrateBreadcrumbTrail(allocator, stdout);

    // Test RichProgressBar (non-interactive)
    try demonstrateRichProgressBar(allocator, stdout);

    // Note about interactive components
    try stdout.writeAll("\n📋 Interactive Components Available:\n");
    try stdout.writeAll("• InputManager - Unified input handling with mouse/keyboard support\n");
    try stdout.writeAll("• EnhancedSelectMenu - Mouse-enabled selection menus\n");
    try stdout.writeAll("• Full terminal capabilities integration\n\n");

    try stdout.writeAll("✨ Demo completed successfully! All components compiled and work.\n");
}

fn demonstrateInfoPanel(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("📋 InfoPanel Demo:\n");

    var panel = InfoPanel.init(allocator, "System Status");
    defer panel.deinit();

    try panel.addInfo("Version", "1.0.0");
    try panel.addSuccess("Connection", "Connected to API");
    try panel.addWarning("Storage", "Disk space low (15% remaining)");
    try panel.addError("Network", "Failed to reach backup server");

    // Add item with hyperlink
    try panel.addWithLink(.info, "Documentation", "Click to view docs", "https://docs.anthropic.com/claude/docs");

    try panel.render(writer);
    try writer.writeAll("\n");
}

fn demonstrateStatusIndicator(writer: anytype) !void {
    try writer.writeAll("🔄 StatusIndicator Demo:\n");

    var status = StatusIndicator.init(.loading, "Processing request...");
    try status.render(writer);
    try writer.writeAll("\n");

    status.setStatus(.success, "Request completed successfully!");
    try status.render(writer);
    try writer.writeAll("\n");

    status.setStatus(.@"error", "Connection failed");
    try status.render(writer);
    try writer.writeAll("\n\n");
}

fn demonstrateBreadcrumbTrail(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("🗺️ BreadcrumbTrail Demo:\n");

    var trail = BreadcrumbTrail.init(allocator);
    defer trail.deinit();

    try trail.addPath("Projects", "/projects");
    try trail.addPath("DocZ", "/projects/docz");
    try trail.addPath("src", "/projects/docz/src");
    try trail.addLabel("cli");

    try trail.render(writer);
    try writer.writeAll("\n");
}

fn demonstrateRichProgressBar(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.writeAll("📊 RichProgressBar Demo:\n");

    // Demonstrate different progress bar styles
    const styles = [_]components.RichProgressBar.ProgressStyle{ .simple, .unicode, .gradient, .animated, .sparkline, .circular };

    const style_names = [_][]const u8{ "Simple", "Unicode", "Gradient", "Animated", "Sparkline", "Circular" };

    for (styles, style_names) |style, name| {
        var progress = RichProgressBar.init(allocator, style, 30, name);
        defer progress.deinit();

        progress.configure(.{
            .show_percentage = true,
            .show_eta = false,
            .show_speed = false,
            .show_sparkline = false,
        });

        // Simulate some progress with history
        var i: u32 = 0;
        while (i <= 10) : (i += 1) {
            const prog = @as(f32, @floatFromInt(i)) / 10.0;
            try progress.setProgress(prog);
        }

        try progress.render(writer);
        try writer.writeAll("\n");

        // Clear the progress bar
        try progress.clear(writer);
    }

    try writer.writeAll("\n");
}

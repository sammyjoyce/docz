//! CLI Component with Graphics Dashboard Integration
//! Demonstrates progressive enhancement and terminal capabilities

const std = @import("std");
const unified_terminal = @import("../core/unified_terminal.zig");
const graphics_mod = @import("../dashboard/graphics.zig");

const Allocator = std.mem.Allocator;
const Terminal = unified_terminal.Terminal;
const Color = unified_terminal.Color;
const GraphicsDashboard = graphics_mod.GraphicsDashboard;
const DashboardConfig = graphics_mod.DashboardConfig;

/// Cli with graphics capabilities and progressive enhancement
pub const Cli = struct {
    const Self = @This();

    allocator: Allocator,
    terminal: Terminal,
    dashboard: ?GraphicsDashboard,
    running: bool,

    pub fn init(allocator: Allocator) !Self {
        const terminal = try Terminal.init(allocator);

        return Self{
            .allocator = allocator,
            .terminal = terminal,
            .dashboard = null,
            .running = false,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.dashboard) |*dash| {
            dash.deinit();
        }
        self.terminal.deinit();
    }

    /// Initialize dashboard with configuration
    pub fn initDashboard(self: *Self, config: DashboardConfig) !void {
        self.dashboard = try GraphicsDashboard.init(self.allocator, config);
        if (self.dashboard) |*dash| {
            try dash.generateDemoData();
        }
    }

    /// Main CLI entry point with feature detection and progressive enhancement
    pub fn run(self: *Self, args: []const []const u8) !u8 {
        try self.displayCapabilities();

        if (args.len > 1 and std.mem.eql(u8, args[1], "dashboard")) {
            return self.runDashboard();
        } else if (args.len > 1 and std.mem.eql(u8, args[1], "demo")) {
            return self.runFeatureDemo();
        } else {
            return self.showHelp();
        }
    }

    /// Display terminal capabilities with progressive enhancement showcase
    fn displayCapabilities(self: *Self) !void {
        const w = self.terminal.writer();

        try self.terminal.clearScreen();
        try self.terminal.setForeground(Color.CYAN);
        try w.writeAll("🚀 CLI with Progressive Terminal Capabilities\n");
        try self.terminal.resetStyles();

        try w.writeAll("\n📊 Detected Terminal Features:\n");

        // Check each feature and display with appropriate styling
        const features = [_]struct {
            feature: Terminal.Feature,
            name: []const u8,
            icon: []const u8,
        }{
            .{ .feature = .truecolor, .name = "True Color (24-bit RGB)", .icon = "🌈" },
            .{ .feature = .graphics, .name = "Graphics Support (Kitty/Sixel)", .icon = "🖼️" },
            .{ .feature = .hyperlinks, .name = "Hyperlinks (OSC 8)", .icon = "🔗" },
            .{ .feature = .clipboard, .name = "Clipboard Integration (OSC 52)", .icon = "📋" },
            .{ .feature = .notifications, .name = "System Notifications (OSC 9)", .icon = "🔔" },
            .{ .feature = .mouse_support, .name = "Advanced Mouse Support", .icon = "🖱️" },
            .{ .feature = .synchronized_output, .name = "Synchronized Output", .icon = "⚡" },
        };

        for (features) |feature_info| {
            try w.writeAll("  ");

            if (self.terminal.hasFeature(feature_info.feature)) {
                try self.terminal.setForeground(Color.GREEN);
                try w.print("✓ {s} {s}", .{ feature_info.icon, feature_info.name });

                // Demonstrate the feature if possible
                switch (feature_info.feature) {
                    .truecolor => {
                        try w.writeAll(" ");
                        for (0..5) |i| {
                            const hue = @as(f32, @floatFromInt(i)) * 72.0; // 360/5
                            const color = hsvToRgb(hue, 1.0, 1.0);
                            try self.terminal.setForeground(Color.rgb(color[0], color[1], color[2]));
                            try w.writeAll("█");
                        }
                    },
                    .hyperlinks => {
                        try w.writeAll(" ");
                        try self.terminal.writeHyperlink("https://github.com", "Demo Link");
                    },
                    else => {},
                }
            } else {
                try self.terminal.setForeground(Color.RED);
                try w.print("✗ {s} {s} (not supported)", .{ "❌", feature_info.name });
            }

            try self.terminal.resetStyles();
            try w.writeByte('\n');
        }

        try w.writeAll("\n");
        try self.terminal.flush();
    }

    /// Run the graphics dashboard demo
    fn runDashboard(self: *Self) !u8 {
        // Initialize dashboard if not already done
        if (self.dashboard == null) {
            const config = DashboardConfig{
                .width = 80,
                .height = 24,
                .title = "Graphics Dashboard",
                .show_legend = true,
                .show_grid = true,
                .update_interval_ms = 1000,
            };
            try self.initDashboard(config);
        }

        if (self.dashboard) |*dash| {
            self.running = true;

            try dash.render();
            try self.terminal.flush();

            const w = self.terminal.writer();
            try w.writeAll("\n\n🎯 Dashboard Demo Complete!\n");
            try w.writeAll("   This showcases:\n");
            try w.writeAll("   • Progressive enhancement (Kitty → Sixel → Unicode → ASCII)\n");
            try w.writeAll("   • Real-time data visualization\n");
            try w.writeAll("   • Rich progress indicators with multiple styles\n");
            try w.writeAll("   • Automatic terminal capability detection\n");
            try w.writeAll("   • Graphics fallback chain for maximum compatibility\n");

            if (self.terminal.hasFeature(.clipboard)) {
                try w.writeAll("\n📋 Dashboard data copied to clipboard!\n");
                try self.terminal.copyToClipboard("Enhanced CLI Dashboard Demo - Terminal capabilities detected and utilized!");
            }

            if (self.terminal.hasFeature(.notifications)) {
                try self.terminal.sendNotification("Enhanced CLI", "Dashboard demo completed successfully!");
            }

            try self.terminal.flush();
        }

        return 0;
    }

    /// Run feature demonstration
    fn runFeatureDemo(self: *Self) !u8 {
        const w = self.terminal.writer();

        try w.writeAll("\n🧪 Terminal Feature Demonstration\n");
        try w.writeAll("==================================\n\n");

        // Color demonstration
        try self.demoColors();

        // Progress bar demonstration
        try self.demoProgressBars();

        // Graphics demonstration
        try self.demoGraphics();

        // Interactive features demonstration
        try self.demoInteractiveFeatures();

        try w.writeAll("\n✨ Feature demonstration complete!\n");
        try self.terminal.flush();
        return 0;
    }

    fn demoColors(self: *Self) !void {
        const w = self.terminal.writer();

        try w.writeAll("🌈 Color Capabilities:\n");

        if (self.terminal.hasFeature(.truecolor)) {
            try w.writeAll("  24-bit RGB Colors: ");
            for (0..20) |i| {
                const hue = @as(f32, @floatFromInt(i)) * 18.0; // 360/20
                const color = hsvToRgb(hue, 0.8, 1.0);
                try self.terminal.setForeground(Color.rgb(color[0], color[1], color[2]));
                try w.writeAll("█");
            }
            try self.terminal.resetStyles();
            try w.writeAll("\n");
        } else {
            try w.writeAll("  256-color palette: ");
            for (16..32) |i| {
                try self.terminal.setForeground(Color.rgb(@intCast(i * 8), @intCast(i * 4), @intCast(i * 16)));
                try w.writeAll("█");
            }
            try self.terminal.resetStyles();
            try w.writeAll("\n");
        }

        try w.writeAll("\n");
    }

    fn demoProgressBars(self: *Self) !void {
        const w = self.terminal.writer();

        try w.writeAll("⚡ Progress Bar Styles:\n");

        const rich_progress = @import("../../src/shared/components/progress.zig");

        const styles = [_]struct {
            style: rich_progress.ProgressStyle,
            name: []const u8,
            progress: f32,
        }{
            .{ .style = .unicode, .name = "Unicode Blocks", .progress = 0.75 },
            .{ .style = .gradient, .name = "Color Gradient", .progress = 0.60 },
            .{ .style = .animated, .name = "Animated Wave", .progress = 0.45 },
            .{ .style = .sparkline, .name = "Data Sparkline", .progress = 0.80 },
            .{ .style = .circular, .name = "Circular Gauge", .progress = 0.35 },
        };

        for (styles) |style_info| {
            var progress_bar = rich_progress.RichProgressBar.init(self.allocator, style_info.style, 35, style_info.name);
            defer progress_bar.deinit();

            if (self.terminal.graphics) |graphics| {
                progress_bar.setGraphicsManager(graphics);
            }

            try progress_bar.setProgress(style_info.progress);
            try w.writeAll("  ");
            try progress_bar.render(w);
            try w.writeAll("\n");
        }

        try w.writeAll("\n");
    }

    fn demoGraphics(self: *Self) !void {
        const w = self.terminal.writer();

        try w.writeAll("🖼️  Graphics Capabilities:\n");

        if (self.terminal.hasFeature(.graphics)) {
            try w.writeAll("  Graphics Mode: ");
            try self.terminal.setForeground(Color.GREEN);
            try w.writeAll("Enhanced (Kitty/Sixel supported)\n");
            try self.terminal.resetStyles();

            // Simple ASCII art as placeholder for graphics
            try w.writeAll("  Sample Chart:\n");
            try w.writeAll("    ▄▄▄▄▄▄▄▄▄▄\n");
            try w.writeAll("    ██▄▄██▄▄██  📈 Graphics rendering available\n");
            try w.writeAll("    ▄▄██▄▄██▄▄\n");
        } else {
            try w.writeAll("  Graphics Mode: ");
            try self.terminal.setForeground(Color.YELLOW);
            try w.writeAll("Text-based (Unicode/ASCII fallback)\n");
            try self.terminal.resetStyles();

            // ASCII art chart
            try w.writeAll("  Sample Chart:\n");
            try w.writeAll("    ▁▂▃▅▆▇█▇▆▅▃▂▁  📊 Text-based visualization\n");
        }

        try w.writeAll("\n");
    }

    fn demoInteractiveFeatures(self: *Self) !void {
        const w = self.terminal.writer();

        try w.writeAll("🔧 Interactive Features:\n");

        if (self.terminal.hasFeature(.hyperlinks)) {
            try w.writeAll("  Hyperlinks: ");
            try self.terminal.writeHyperlink("https://github.com/sam/docz", "Project Repository");
            try w.writeAll(" | ");
            try self.terminal.writeHyperlink("https://docs.example.com", "Documentation");
            try w.writeAll("\n");
        }

        if (self.terminal.hasFeature(.clipboard)) {
            try w.writeAll("  Clipboard: ");
            try self.terminal.setForeground(Color.GREEN);
            try w.writeAll("✓ OSC 52 clipboard integration available\n");
            try self.terminal.resetStyles();
        }

        if (self.terminal.hasFeature(.notifications)) {
            try w.writeAll("  Notifications: ");
            try self.terminal.setForeground(Color.GREEN);
            try w.writeAll("✓ System notification support available\n");
            try self.terminal.resetStyles();
        }

        try w.writeAll("\n");
    }

    fn showHelp(self: *Self) !u8 {
        const w = self.terminal.writer();

        try w.writeAll("CLI with Graphics Dashboard\n");
        try w.writeAll("===========================\n\n");
        try w.writeAll("Usage: cli [COMMAND]\n\n");
        try w.writeAll("Commands:\n");
        try w.writeAll("  dashboard    Display graphics dashboard\n");
        try w.writeAll("  demo         Run terminal feature demonstrations\n");
        try w.writeAll("  help         Show this help message\n\n");

        try w.writeAll("Features:\n");
        try w.writeAll("• Progressive enhancement (Kitty → Sixel → Unicode → ASCII)\n");
        try w.writeAll("• Real-time data visualization with rich graphics\n");
        try w.writeAll("• Multiple progress bar styles with animations\n");
        try w.writeAll("• Automatic terminal capability detection\n");
        try w.writeAll("• Hyperlinks, clipboard integration, and notifications\n");
        try w.writeAll("• True color support with graceful fallbacks\n\n");

        try self.terminal.flush();
        return 0;
    }
};

/// HSV to RGB color conversion for demonstrations
fn hsvToRgb(h: f32, s: f32, v: f32) [3]u8 {
    const c = v * s;
    const x = c * (1.0 - @abs(@mod(h / 60.0, 2.0) - 1.0));
    const m = v - c;

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    if (h >= 0.0 and h < 60.0) {
        r = c;
        g = x;
    } else if (h >= 60.0 and h < 120.0) {
        r = x;
        g = c;
    } else if (h >= 120.0 and h < 180.0) {
        g = c;
        b = x;
    } else if (h >= 180.0 and h < 240.0) {
        g = x;
        b = c;
    } else if (h >= 240.0 and h < 300.0) {
        r = x;
        b = c;
    } else {
        r = c;
        b = x;
    }

    return [3]u8{
        @intFromFloat((r + m) * 255.0),
        @intFromFloat((g + m) * 255.0),
        @intFromFloat((b + m) * 255.0),
    };
}

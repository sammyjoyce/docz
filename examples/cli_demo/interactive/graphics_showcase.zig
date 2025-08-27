//! Interactive Terminal Graphics Showcase
//!
//! This demo showcases the full power of the terminal graphics system,
//! demonstrating progressive enhancement from ASCII to Kitty graphics.

const std = @import("std");
const unified = @import("../../src/shared/term/unified.zig");
const graphics_manager = @import("../../src/shared/term/graphics_manager.zig");
const canvas_engine = @import("../../tui/core/canvas_engine.zig");
const adaptive_renderer = @import("../../tui/components/graphics/adaptive_renderer.zig");
const enhanced_input = @import("../../src/shared/term/enhanced_input_handler.zig");

/// Interactive graphics showcase with multiple demo modes
pub const GraphicsShowcase = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    terminal: *unified.Terminal,
    canvas: canvas_engine.CanvasEngine,
    renderer: adaptive_renderer.AdaptiveRenderer,
    current_demo: DemoMode = .menu,
    should_exit: bool = false,

    pub const DemoMode = enum {
        menu,
        realtime_charts,
        interactive_canvas,
        data_visualization,
        drawing_pad,
        terminal_capabilities,
    };

    pub fn init(allocator: std.mem.Allocator) !Self {
        var terminal = try allocator.create(unified.Terminal);
        terminal.* = try unified.Terminal.init(allocator);

        var canvas = try canvas_engine.CanvasEngine.init(allocator, terminal);

        // Set canvas viewport to terminal size
        canvas.setViewport(2, 3, 76, 20); // Leave space for menu and borders

        var graphics = graphics_manager.GraphicsManager.init(allocator, terminal);
        var renderer = adaptive_renderer.AdaptiveRenderer.init(allocator, &graphics, terminal);

        return Self{
            .allocator = allocator,
            .terminal = terminal,
            .canvas = canvas,
            .renderer = renderer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.canvas.deinit();
        self.terminal.deinit();
        self.allocator.destroy(self.terminal);
    }

    pub fn run(self: *Self) !void {
        try self.terminal.clear();
        try self.showWelcomeMessage();

        while (!self.should_exit) {
            try self.renderCurrentDemo();
            try self.handleInput();
            std.time.sleep(16_000_000); // ~60 FPS
        }

        try self.showExitMessage();
    }

    fn showWelcomeMessage(self: *Self) !void {
        const caps = self.terminal.getCapabilities();
        const graphics_mode = graphics_manager.GraphicsMode.detect(caps);

        try self.terminal.moveTo(0, 0);
        try self.terminal.print("🎨 Terminal Graphics Showcase", .{ .fg_color = unified.Colors.CYAN, .bold = true });

        try self.terminal.moveTo(0, 1);
        const mode_text = switch (graphics_mode) {
            .kitty => "✨ Ultra Mode: Kitty Graphics Protocol",
            .sixel => "🌟 Enhanced Mode: Sixel Graphics",
            .unicode => "📊 Standard Mode: Unicode Blocks",
            .ascii => "📈 Minimal Mode: ASCII Art",
            .none => "📝 Text Mode Only",
        };
        try self.terminal.print(mode_text, .{ .fg_color = unified.Colors.GREEN });

        // Draw a separator line
        try self.terminal.moveTo(0, 2);
        for (0..80) |_| {
            try self.terminal.print("─", .{ .fg_color = unified.Colors.BRIGHT_BLACK });
        }
    }

    fn renderCurrentDemo(self: *Self) !void {
        switch (self.current_demo) {
            .menu => try self.renderMenu(),
            .realtime_charts => try self.renderRealtimeChartsDemo(),
            .interactive_canvas => try self.renderInteractiveCanvasDemo(),
            .data_visualization => try self.renderDataVisualizationDemo(),
            .drawing_pad => try self.renderDrawingPadDemo(),
            .terminal_capabilities => try self.renderTerminalCapabilitiesDemo(),
        }
    }

    fn renderMenu(self: *Self) !void {
        const menu_items = [_][]const u8{
            "1. Realtime Charts - Live data visualization",
            "2. Interactive Canvas - Drawing and manipulation",
            "3. Data Visualization - Heatmaps, scatter plots",
            "4. Drawing Pad - Free-form drawing tool",
            "5. Terminal Capabilities - Feature detection",
            "Q. Quit",
        };

        try self.terminal.moveTo(2, 5);
        try self.terminal.print("Select a demo:", .{ .bold = true });

        for (menu_items, 0..) |item, i| {
            try self.terminal.moveTo(4, 7 + @as(i32, @intCast(i)));
            try self.terminal.print(item, .{ .fg_color = unified.Colors.WHITE });
        }

        // Show current graphics capabilities
        try self.renderCapabilitiesPanel();
    }

    fn renderCapabilitiesPanel(self: *Self) !void {
        const caps = self.terminal.getCapabilities();

        try self.terminal.moveTo(2, 15);
        try self.terminal.print("Current Terminal Capabilities:", .{ .bold = true, .fg_color = unified.Colors.YELLOW });

        const capabilities = [_]struct { name: []const u8, supported: bool }{
            .{ .name = "Truecolor (24-bit RGB)", .supported = caps.supportsTruecolor },
            .{ .name = "Kitty Graphics Protocol", .supported = caps.supportsKittyGraphics },
            .{ .name = "Sixel Graphics", .supported = caps.supportsSixel },
            .{ .name = "Hyperlinks (OSC 8)", .supported = caps.supportsHyperlinkOsc8 },
            .{ .name = "Clipboard (OSC 52)", .supported = caps.supportsClipboardOsc52 },
            .{ .name = "System Notifications", .supported = caps.supportsNotifyOsc9 },
            .{ .name = "Mouse Support", .supported = caps.supportsSgrMouse },
        };

        for (capabilities, 0..) |cap, i| {
            try self.terminal.moveTo(4, 17 + @as(i32, @intCast(i)));
            const status_color = if (cap.supported) unified.Colors.GREEN else unified.Colors.RED;
            const status_icon = if (cap.supported) "✓" else "✗";

            try self.terminal.print(status_icon, .{ .fg_color = status_color });
            try self.terminal.print(" ", null);
            try self.terminal.print(cap.name, null);
        }
    }

    fn renderRealtimeChartsDemo(self: *Self) !void {
        try self.clearDemoArea();

        try self.terminal.moveTo(2, 3);
        try self.terminal.print("Realtime Charts Demo", .{ .bold = true, .fg_color = unified.Colors.CYAN });

        // Generate sample data
        var data: [50]f64 = undefined;
        const time = @as(f64, @floatFromInt(std.time.milliTimestamp())) / 1000.0;

        for (data, 0..) |*val, i| {
            const x = @as(f64, @floatFromInt(i)) / 10.0;
            val.* = @sin(time + x) * 50.0 + 50.0; // Sine wave animation
        }

        // Render chart using adaptive renderer
        const chart_content = adaptive_renderer.AdaptiveRenderer.RenderableContent{
            .realtime_chart = .{
                .data_stream = &data,
                .chart_type = .line,
                .update_rate_ms = 100,
            },
        };

        const bounds = unified.Rect{ .x = 2, .y = 5, .width = 70, .height = 15 };
        try self.renderer.render(chart_content, bounds);

        // Show controls
        try self.terminal.moveTo(2, 21);
        try self.terminal.print("Press SPACE to change chart type, ESC to return to menu", .{ .fg_color = unified.Colors.BRIGHT_BLACK });
    }

    fn renderInteractiveCanvasDemo(self: *Self) !void {
        try self.clearDemoArea();

        try self.terminal.moveTo(2, 3);
        try self.terminal.print("Interactive Canvas Demo", .{ .bold = true, .fg_color = unified.Colors.CYAN });

        // Create sample drawing layers
        const drawing_content = adaptive_renderer.AdaptiveRenderer.RenderableContent{
            .drawing_canvas = .{
                .layers = &[_]adaptive_renderer.AdaptiveRenderer.RenderableContent.DrawingCanvas.DrawingLayer{
                    .{
                        .strokes = &[_]adaptive_renderer.AdaptiveRenderer.RenderableContent.DrawingCanvas.Stroke{
                            .{
                                .points = &[_]adaptive_renderer.AdaptiveRenderer.RenderableContent.DrawingCanvas.DrawingLayer.Point2D{
                                    .{ .x = 10.0, .y = 10.0 },
                                    .{ .x = 30.0, .y = 15.0 },
                                    .{ .x = 50.0, .y = 5.0 },
                                    .{ .x = 70.0, .y = 20.0 },
                                },
                                .color = unified.Colors.BLUE,
                                .width = 3.0,
                            },
                        },
                    },
                },
                .tools = .{
                    .active_tool = .brush,
                    .brush_size = 2.0,
                    .active_color = unified.Colors.WHITE,
                },
            },
        };

        const bounds = unified.Rect{ .x = 2, .y = 5, .width = 70, .height = 15 };
        try self.renderer.render(drawing_content, bounds);

        // Show drawing tools
        try self.terminal.moveTo(2, 21);
        try self.terminal.print("Tools: [B]rush [L]ine [R]ectangle [C]ircle [E]raser - Mouse to draw, ESC for menu", .{ .fg_color = unified.Colors.BRIGHT_BLACK });
    }

    fn renderDataVisualizationDemo(self: *Self) !void {
        try self.clearDemoArea();

        try self.terminal.moveTo(2, 3);
        try self.terminal.print("Data Visualization Demo", .{ .bold = true, .fg_color = unified.Colors.CYAN });

        // Generate sample heatmap data
        var matrix_data: [10][20]f64 = undefined;
        for (matrix_data, 0..) |*row, i| {
            for (row, 0..) |*val, j| {
                const x = @as(f64, @floatFromInt(j)) / 20.0;
                const y = @as(f64, @floatFromInt(i)) / 10.0;
                val.* = @sin(x * 6.0) * @cos(y * 4.0);
            }
        }

        // Convert to flat array for rendering
        var flat_data: [200]f64 = undefined;
        var idx: usize = 0;
        for (matrix_data) |row| {
            for (row) |val| {
                flat_data[idx] = val;
                idx += 1;
            }
        }

        // Create slice pointers for the matrix
        var matrix_slices: [10][]const f64 = undefined;
        for (matrix_slices, 0..) |*slice, i| {
            slice.* = flat_data[i * 20 .. (i + 1) * 20];
        }

        const viz_content = adaptive_renderer.AdaptiveRenderer.RenderableContent{
            .data_visualization = .{
                .viz_type = .heatmap,
                .data = .{ .matrix = &matrix_slices },
                .styling = .{
                    .color_scheme = .viridis,
                    .show_labels = true,
                    .show_grid = false,
                },
            },
        };

        const bounds = unified.Rect{ .x = 2, .y = 5, .width = 70, .height = 15 };
        try self.renderer.render(viz_content, bounds);

        // Show controls
        try self.terminal.moveTo(2, 21);
        try self.terminal.print("Press 1-5 to change visualization type, ESC to return to menu", .{ .fg_color = unified.Colors.BRIGHT_BLACK });
    }

    fn renderDrawingPadDemo(self: *Self) !void {
        try self.clearDemoArea();

        try self.terminal.moveTo(2, 3);
        try self.terminal.print("Drawing Pad", .{ .bold = true, .fg_color = unified.Colors.CYAN });

        // Render the canvas
        try self.canvas.render();

        // Show instructions
        try self.terminal.moveTo(2, 21);
        try self.terminal.print("Click and drag to draw, ESC to return to menu", .{ .fg_color = unified.Colors.BRIGHT_BLACK });
    }

    fn renderTerminalCapabilitiesDemo(self: *Self) !void {
        try self.clearDemoArea();

        try self.terminal.moveTo(2, 3);
        try self.terminal.print("Terminal Capabilities Test", .{ .bold = true, .fg_color = unified.Colors.CYAN });

        // Test color capabilities
        try self.testColorCapabilities();

        // Test graphics capabilities
        try self.testGraphicsCapabilities();

        // Test interaction capabilities
        try self.testInteractionCapabilities();

        try self.terminal.moveTo(2, 21);
        try self.terminal.print("ESC to return to menu", .{ .fg_color = unified.Colors.BRIGHT_BLACK });
    }

    fn testColorCapabilities(self: *Self) !void {
        try self.terminal.moveTo(4, 5);
        try self.terminal.print("Color Support Test:", .{ .bold = true });

        // Test ANSI colors
        try self.terminal.moveTo(6, 6);
        try self.terminal.print("ANSI 16: ", null);
        for (0..8) |i| {
            const color = unified.Color{ .ansi = @as(u8, @intCast(i)) };
            try self.terminal.print("██", .{ .fg_color = color });
        }

        // Test 256 colors
        try self.terminal.moveTo(6, 7);
        try self.terminal.print("256 Color: ", null);
        for (0..16) |i| {
            const color = unified.Color{ .palette = @as(u8, @intCast(i * 15)) };
            try self.terminal.print("█", .{ .fg_color = color });
        }

        // Test RGB colors
        try self.terminal.moveTo(6, 8);
        try self.terminal.print("Truecolor: ", null);
        for (0..16) |i| {
            const intensity = @as(u8, @intCast(i * 15));
            const color = unified.Color{ .rgb = .{ .r = intensity, .g = 255 - intensity, .b = intensity } };
            try self.terminal.print("█", .{ .fg_color = color });
        }
    }

    fn testGraphicsCapabilities(self: *Self) !void {
        try self.terminal.moveTo(4, 10);
        try self.terminal.print("Graphics Support Test:", .{ .bold = true });

        const caps = self.terminal.getCapabilities();
        const graphics_mode = graphics_manager.GraphicsMode.detect(caps);

        try self.terminal.moveTo(6, 11);
        switch (graphics_mode) {
            .kitty => {
                try self.terminal.print("✓ Kitty Graphics Protocol - Ultra quality", .{ .fg_color = unified.Colors.GREEN });
                // Could render a small test image here
            },
            .sixel => {
                try self.terminal.print("✓ Sixel Graphics - High quality", .{ .fg_color = unified.Colors.GREEN });
            },
            .unicode => {
                try self.terminal.print("✓ Unicode Blocks - Standard quality", .{ .fg_color = unified.Colors.YELLOW });
                try self.terminal.moveTo(8, 12);
                try self.terminal.print("▄▀█▀▄ ▄▀█▀▄ ▄▀█▀▄", .{ .fg_color = unified.Colors.CYAN });
            },
            .ascii => {
                try self.terminal.print("✓ ASCII Art - Basic quality", .{ .fg_color = unified.Colors.YELLOW });
                try self.terminal.moveTo(8, 12);
                try self.terminal.print("###  ###  ### ", null);
            },
            .none => {
                try self.terminal.print("✗ No graphics support", .{ .fg_color = unified.Colors.RED });
            },
        }
    }

    fn testInteractionCapabilities(self: *Self) !void {
        try self.terminal.moveTo(4, 14);
        try self.terminal.print("Interaction Support Test:", .{ .bold = true });

        const caps = self.terminal.getCapabilities();

        const interactions = [_]struct { name: []const u8, supported: bool }{
            .{ .name = "Mouse Support", .supported = caps.supportsSgrMouse },
            .{ .name = "Pixel-Precise Mouse", .supported = caps.supportsSgrPixelMouse },
            .{ .name = "Focus Events", .supported = caps.supportsFocusEvents },
            .{ .name = "Bracketed Paste", .supported = caps.supportsBracketedPaste },
        };

        for (interactions, 0..) |interaction, i| {
            try self.terminal.moveTo(6, 15 + @as(i32, @intCast(i)));
            const status_color = if (interaction.supported) unified.Colors.GREEN else unified.Colors.RED;
            const status_icon = if (interaction.supported) "✓" else "✗";

            try self.terminal.print(status_icon, .{ .fg_color = status_color });
            try self.terminal.print(" ", null);
            try self.terminal.print(interaction.name, null);
        }
    }

    fn handleInput(self: *Self) !void {
        // Simplified input handling - in a real implementation this would use
        // the enhanced input system for better cross-platform support

        var stdin_buffer: [4096]u8 = undefined;
        const stdin_file = std.fs.File.stdin();
        var stdin_reader = stdin_file.reader(&stdin_buffer);
        var buf: [1]u8 = undefined;
        if (stdin_reader.read(&buf)) |bytes_read| {
            if (bytes_read == 0) return;

            const key = buf[0];

            switch (self.current_demo) {
                .menu => {
                    switch (key) {
                        '1' => self.current_demo = .realtime_charts,
                        '2' => self.current_demo = .interactive_canvas,
                        '3' => self.current_demo = .data_visualization,
                        '4' => self.current_demo = .drawing_pad,
                        '5' => self.current_demo = .terminal_capabilities,
                        'q', 'Q' => self.should_exit = true,
                        else => {},
                    }
                },
                else => {
                    switch (key) {
                        27 => self.current_demo = .menu, // ESC key
                        else => try self.handleDemoSpecificInput(key),
                    }
                },
            }
        } else |_| {
            // No input available
        }
    }

    fn handleDemoSpecificInput(self: *Self, key: u8) !void {
        switch (self.current_demo) {
            .drawing_pad => {
                // Handle drawing pad controls
                switch (key) {
                    'b', 'B' => {
                        // Switch to brush tool
                    },
                    'c', 'C' => {
                        // Clear canvas
                        self.canvas = try canvas_engine.CanvasEngine.init(self.allocator, self.terminal);
                        self.canvas.setViewport(2, 5, 70, 15);
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    fn clearDemoArea(self: *Self) !void {
        // Clear the demo area (lines 3-22)
        for (3..23) |y| {
            try self.terminal.moveTo(0, @as(i32, @intCast(y)));
            for (0..80) |_| {
                try self.terminal.print(" ", null);
            }
        }
    }

    fn showExitMessage(self: *Self) !void {
        try self.terminal.clear();
        try self.terminal.moveTo(30, 10);
        try self.terminal.print("Thanks for using the Terminal Graphics Showcase!", .{ .fg_color = unified.Colors.CYAN, .bold = true });

        try self.terminal.moveTo(25, 12);
        try self.terminal.print("Your terminal supports amazing graphics capabilities!", .{ .fg_color = unified.Colors.GREEN });

        try self.terminal.moveTo(0, 15);
    }
};

/// Simple CLI entry point for the graphics showcase
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var showcase = try GraphicsShowcase.init(allocator);
    defer showcase.deinit();

    try showcase.run();
}

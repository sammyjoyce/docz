//! Clear Widget Demo
//! 
//! This example demonstrates the Clear widget's various capabilities including:
//! - Different clear modes (spaces, solid color, transparent overlay, patterns)
//! - Modal dialog creation
//! - Tooltip functionality
//! - Keyboard interaction (ESC to close)
//!
//! Run with: zig build run-example -- clear_widget_demo

const std = @import("std");
const clear_widget = @import("../src/shared/tui/widgets/core/clear.zig");
const bounds_mod = @import("../src/shared/tui/core/bounds.zig");
const themes = @import("../src/shared/tui/themes/default.zig");
const term_writer = @import("../src/shared/term/writer.zig");

const Clear = clear_widget.Clear;
const ClearMode = clear_widget.ClearMode;
const ClearConfig = clear_widget.ClearConfig;
const Pattern = clear_widget.Pattern;
const BorderOptions = clear_widget.BorderOptions;
const Bounds = bounds_mod.Bounds;
const Point = bounds_mod.Point;
const Color = themes.Color;
const print = term_writer.print;

const DemoState = struct {
    current_demo: usize = 0,
    is_running: bool = true,
    should_redraw: bool = true,
    allocator: std.mem.Allocator,
    overlays: std.ArrayList(*Clear),
    
    pub fn init(allocator: std.mem.Allocator) !DemoState {
        return .{
            .allocator = allocator,
            .overlays = std.ArrayList(*Clear).init(allocator),
        };
    }
    
    pub fn deinit(self: *DemoState) void {
        for (self.overlays.items) |overlay| {
            self.allocator.destroy(overlay);
        }
        self.overlays.deinit();
    }
    
    pub fn addOverlay(self: *DemoState, overlay: *Clear) !void {
        try self.overlays.append(overlay);
    }
    
    pub fn clearOverlays(self: *DemoState) void {
        for (self.overlays.items) |overlay| {
            self.allocator.destroy(overlay);
        }
        self.overlays.clearRetainingCapacity();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize demo state
    var demo_state = try DemoState.init(allocator);
    defer demo_state.deinit();
    
    // Clear screen and hide cursor
    print("\x1b[2J\x1b[H\x1b[?25l", .{});
    defer print("\x1b[?25h\x1b[0m", .{}); // Show cursor and reset on exit
    
    // Print header
    printHeader();
    
    // Run demo loop
    try runDemoLoop(&demo_state);
    
    // Clean up
    print("\x1b[2J\x1b[H", .{}); // Clear screen
    print("✨ Clear Widget Demo completed!\n", .{});
}

fn printHeader() void {
    print("\x1b[H", .{}); // Move to top
    print("\x1b[1;36m╔══════════════════════════════════════════════════════════════════╗\x1b[0m\n", .{});
    print("\x1b[1;36m║           🎨 Clear Widget Demo - TUI Overlay System 🎨          ║\x1b[0m\n", .{});
    print("\x1b[1;36m╚══════════════════════════════════════════════════════════════════╝\x1b[0m\n", .{});
    print("\n", .{});
    printInstructions();
}

fn printInstructions() void {
    print("\x1b[4;1H", .{}); // Move to line 4
    print("Instructions:\n", .{});
    print("  \x1b[33m[1-8]\x1b[0m Select demo  \x1b[33m[SPACE]\x1b[0m Toggle overlay  \x1b[33m[ESC]\x1b[0m Hide overlay  \x1b[33m[Q]\x1b[0m Quit\n", .{});
    print("  \x1b[33m[C]\x1b[0m Clear all     \x1b[33m[H]\x1b[0m Help           \x1b[33m[R]\x1b[0m Refresh\n", .{});
    print("\n", .{});
    print("\x1b[90m────────────────────────────────────────────────────────────────────────\x1b[0m\n", .{});
}

fn runDemoLoop(state: *DemoState) !void {
    var current_demo: usize = 0;
    
    while (state.is_running) {
        if (state.should_redraw) {
            try drawCurrentDemo(state, current_demo);
            state.should_redraw = false;
        }
        
        // Read input (simplified - in real app you'd use proper terminal input)
        var buffer: [1]u8 = undefined;
        const stdin = std.io.getStdIn();
        const bytes_read = try stdin.read(&buffer);
        
        if (bytes_read > 0) {
            const key = buffer[0];
            switch (key) {
                '1'...'8' => {
                    current_demo = key - '1';
                    state.clearOverlays();
                    state.should_redraw = true;
                },
                ' ' => { // Space - toggle current overlay
                    if (state.overlays.items.len > 0) {
                        const overlay = state.overlays.items[state.overlays.items.len - 1];
                        try overlay.toggle();
                    }
                },
                27 => { // ESC - hide all overlays
                    for (state.overlays.items) |overlay| {
                        try overlay.hide();
                    }
                },
                'c', 'C' => { // Clear all overlays
                    state.clearOverlays();
                    clearDemoArea();
                },
                'r', 'R' => { // Refresh
                    clearScreen();
                    printHeader();
                    state.should_redraw = true;
                },
                'h', 'H' => { // Help
                    try showHelp(state);
                },
                'q', 'Q' => { // Quit
                    state.is_running = false;
                },
                else => {},
            }
        }
        
        // Small delay to prevent busy waiting
        std.time.sleep(50 * std.time.ns_per_ms);
    }
}

fn drawCurrentDemo(state: *DemoState, demo_index: usize) !void {
    // Clear demo area
    clearDemoArea();
    
    // Show demo title
    print("\x1b[10;1H", .{});
    print("\x1b[1;32mDemo {d}: ", .{demo_index + 1});
    
    switch (demo_index) {
        0 => try demoSpacesClear(state),
        1 => try demoSolidColorClear(state),
        2 => try demoTransparentOverlay(state),
        3 => try demoPatternClear(state),
        4 => try demoModalDialog(state),
        5 => try demoTooltip(state),
        6 => try demoBorderedOverlay(state),
        7 => try demoAdvancedEffects(state),
        else => {
            print("Select a demo using keys 1-8\x1b[0m\n", .{});
        },
    }
}

fn demoSpacesClear(state: *DemoState) !void {
    print("Basic Spaces Clear\x1b[0m\n\n", .{});
    print("This demo shows the simplest clear mode - filling with spaces.\n", .{});
    
    // Create background content
    drawBackgroundContent(12, 5, 40, 10);
    
    // Create clear overlay
    const overlay = try state.allocator.create(Clear);
    overlay.* = Clear.init(state.allocator, Bounds.init(15, 14, 30, 8))
        .withMode(.spaces);
    
    try state.addOverlay(overlay);
    try overlay.show();
}

fn demoSolidColorClear(state: *DemoState) !void {
    print("Solid Color Clear\x1b[0m\n\n", .{});
    print("Clear with solid background colors.\n", .{});
    
    // Create background content
    drawBackgroundContent(12, 5, 50, 12);
    
    // Create multiple colored overlays
    const colors = [_]Color{ .BLUE, .GREEN, .MAGENTA, .CYAN };
    const positions = [_][2]u32{
        .{ 14, 13 },
        .{ 24, 14 },
        .{ 34, 15 },
        .{ 44, 16 },
    };
    
    for (colors, positions) |color, pos| {
        const overlay = try state.allocator.create(Clear);
        overlay.* = Clear.init(state.allocator, Bounds.init(pos[0], pos[1], 15, 6))
            .withMode(.solid_color)
            .withBackgroundColor(color);
        
        try state.addOverlay(overlay);
        try overlay.show();
    }
}

fn demoTransparentOverlay(state: *DemoState) !void {
    print("Transparent Overlay\x1b[0m\n\n", .{});
    print("Semi-transparent overlay effect using shading characters.\n", .{});
    
    // Create rich background content
    drawColorfulBackground(12, 5, 60, 14);
    
    // Create transparent overlays with different transparency levels
    const transparencies = [_]u8{ 50, 100, 150, 200 };
    var x: u32 = 14;
    
    for (transparencies) |transparency| {
        const overlay = try state.allocator.create(Clear);
        overlay.* = Clear.init(state.allocator, Bounds.init(x, 14, 12, 8))
            .withMode(.transparent_overlay)
            .withTransparency(transparency);
        
        try state.addOverlay(overlay);
        try overlay.show();
        x += 13;
    }
}

fn demoPatternClear(state: *DemoState) !void {
    print("Pattern Clear\x1b[0m\n\n", .{});
    print("Various pattern fills for decorative overlays.\n", .{});
    
    // Create background
    drawBackgroundContent(12, 5, 70, 15);
    
    // Demo different patterns
    const patterns = [_]Pattern{
        .checkered,
        .horizontal_stripes,
        .vertical_stripes,
        .diagonal_stripes,
        .dots,
        .cross_hatch,
    };
    
    const pattern_names = [_][]const u8{
        "Checkered",
        "H-Stripes",
        "V-Stripes",
        "Diagonal",
        "Dots",
        "CrossHatch",
    };
    
    var x: u32 = 13;
    const y: u32 = 14;
    
    for (patterns, pattern_names) |pattern, name| {
        const overlay = try state.allocator.create(Clear);
        overlay.* = Clear.init(state.allocator, Bounds.init(x, y, 10, 5))
            .withMode(.pattern)
            .withPattern(pattern, null)
            .withBackgroundColor(.BLACK)
            .withBorder(BorderOptions{
                .style = .single,
                .color = .WHITE,
                .padding = 0,
            });
        
        try state.addOverlay(overlay);
        try overlay.show();
        
        // Draw pattern name
        print("\x1b[{d};{d}H\x1b[33m{s}\x1b[0m", .{ y + 6, x, name });
        
        x += 11;
    }
}

fn demoModalDialog(state: *DemoState) !void {
    print("Modal Dialog\x1b[0m\n\n", .{});
    print("Center-aligned modal with shadow and border.\n", .{});
    
    // Create background content
    drawColorfulBackground(12, 5, 70, 18);
    
    // Create modal overlay
    const parent_bounds = Bounds.init(10, 12, 70, 18);
    const modal = try state.allocator.create(Clear);
    modal.* = Clear.initModal(state.allocator, parent_bounds, 60, 60);
    
    try state.addOverlay(modal);
    try modal.show();
    
    // Draw modal content
    const modal_bounds = modal.getActualBounds();
    const center_x = modal_bounds.x + modal_bounds.width / 2;
    const center_y = modal_bounds.y + modal_bounds.height / 2;
    
    print("\x1b[{d};{d}H\x1b[1;37m╔═══════════════════════════╗\x1b[0m", .{ center_y - 3, center_x - 15 });
    print("\x1b[{d};{d}H\x1b[1;37m║     \x1b[33mModal Dialog Demo\x1b[37m     ║\x1b[0m", .{ center_y - 2, center_x - 15 });
    print("\x1b[{d};{d}H\x1b[1;37m╠═══════════════════════════╣\x1b[0m", .{ center_y - 1, center_x - 15 });
    print("\x1b[{d};{d}H\x1b[1;37m║  Press \x1b[32mESC\x1b[37m to close      ║\x1b[0m", .{ center_y, center_x - 15 });
    print("\x1b[{d};{d}H\x1b[1;37m║  Press \x1b[32mSPACE\x1b[37m to toggle   ║\x1b[0m", .{ center_y + 1, center_x - 15 });
    print("\x1b[{d};{d}H\x1b[1;37m╚═══════════════════════════╝\x1b[0m", .{ center_y + 2, center_x - 15 });
}

fn demoTooltip(state: *DemoState) !void {
    print("Tooltip Overlay\x1b[0m\n\n", .{});
    print("Small informational overlays with rounded corners.\n", .{});
    
    // Create interactive elements
    drawInteractiveElements();
    
    // Create tooltips at different positions
    const tooltip_data = [_]struct {
        point: Point,
        text: []const u8,
        width: u32,
        height: u32,
    }{
        .{ .point = .{ .x = 18, .y = 15 }, .text = "Hover Info", .width = 12, .height = 3 },
        .{ .point = .{ .x = 35, .y = 14 }, .text = "Help Text", .width = 11, .height = 3 },
        .{ .point = .{ .x = 52, .y = 16 }, .text = "Quick Tip", .width = 11, .height = 3 },
        .{ .point = .{ .x = 25, .y = 20 }, .text = "Details", .width = 10, .height = 3 },
    };
    
    for (tooltip_data) |data| {
        const tooltip = try state.allocator.create(Clear);
        tooltip.* = Clear.initTooltip(state.allocator, data.point, data.width, data.height);
        
        try state.addOverlay(tooltip);
        try tooltip.show();
        
        // Draw tooltip text
        print("\x1b[{d};{d}H\x1b[30;43m {s} \x1b[0m", .{
            data.point.y + 1,
            data.point.x + 1,
            data.text,
        });
    }
}

fn demoBorderedOverlay(state: *DemoState) !void {
    print("Bordered Overlays\x1b[0m\n\n", .{});
    print("Different border styles for overlays.\n", .{});
    
    // Create background
    drawBackgroundContent(12, 5, 70, 15);
    
    // Border styles
    const border_styles = [_]clear_widget.BorderOptions{
        .{ .style = .single, .color = .WHITE, .padding = 1 },
        .{ .style = .double, .color = .CYAN, .padding = 1 },
        .{ .style = .rounded, .color = .GREEN, .padding = 0 },
        .{ .style = .thick, .color = .YELLOW, .padding = 0 },
        .{ .style = .dashed, .color = .MAGENTA, .padding = 0 },
    };
    
    const style_names = [_][]const u8{
        "Single", "Double", "Rounded", "Thick", "Dashed",
    };
    
    var x: u32 = 13;
    const y: u32 = 14;
    
    for (border_styles, style_names) |border, name| {
        const overlay = try state.allocator.create(Clear);
        overlay.* = Clear.init(state.allocator, Bounds.init(x, y, 12, 6))
            .withMode(.solid_color)
            .withBackgroundColor(.BLACK)
            .withBorder(border);
        
        try state.addOverlay(overlay);
        try overlay.show();
        
        // Draw border style name
        print("\x1b[{d};{d}H\x1b[36m{s}\x1b[0m", .{ y + 2, x + 2, name });
        
        x += 13;
    }
}

fn demoAdvancedEffects(state: *DemoState) !void {
    print("Advanced Effects\x1b[0m\n\n", .{});
    print("Combined effects: shadow, blur, and color filters.\n", .{});
    
    // Create rich background
    drawColorfulBackground(12, 5, 70, 18);
    
    // Blur effect overlay
    const blur_overlay = try state.allocator.create(Clear);
    blur_overlay.* = Clear.init(state.allocator, Bounds.init(13, 14, 20, 8))
        .withMode(.blur)
        .withShadow(true, .GRAY);
    try state.addOverlay(blur_overlay);
    try blur_overlay.show();
    
    // Color filter overlay
    const filter_overlay = try state.allocator.create(Clear);
    filter_overlay.* = Clear.init(state.allocator, Bounds.init(35, 15, 20, 8))
        .withMode(.color_filter)
        .withShadow(true, .BLACK);
    try state.addOverlay(filter_overlay);
    try filter_overlay.show();
    
    // Combined effects overlay
    const combined_overlay = try state.allocator.create(Clear);
    combined_overlay.* = Clear.init(state.allocator, Bounds.init(57, 14, 20, 10))
        .withMode(.pattern)
        .withPattern(.diagonal_stripes, null)
        .withBackgroundColor(.BLUE)
        .withBorder(BorderOptions{
            .style = .double,
            .color = .CYAN,
            .padding = 1,
        })
        .withShadow(true, .BLACK);
    try state.addOverlay(combined_overlay);
    try combined_overlay.show();
    
    // Labels
    print("\x1b[{d};{d}H\x1b[1;35mBlur Effect\x1b[0m", .{ 23, 17 });
    print("\x1b[{d};{d}H\x1b[1;35mColor Filter\x1b[0m", .{ 24, 38 });
    print("\x1b[{d};{d}H\x1b[1;35mCombined\x1b[0m", .{ 25, 62 });
}

fn showHelp(state: *DemoState) !void {
    // Create help modal
    const help_bounds = Bounds.init(20, 10, 40, 15);
    const help_overlay = try state.allocator.create(Clear);
    help_overlay.* = Clear.init(state.allocator, help_bounds)
        .withMode(.solid_color)
        .withBackgroundColor(.BLACK)
        .withBorder(BorderOptions{
            .style = .double,
            .color = .YELLOW,
            .padding = 1,
        })
        .withShadow(true, .GRAY);
    
    try state.addOverlay(help_overlay);
    try help_overlay.show();
    
    // Draw help content
    print("\x1b[{d};{d}H\x1b[1;33m═══════ HELP ═══════\x1b[0m", .{ 11, 28 });
    print("\x1b[{d};{d}H\x1b[32mDemo Selection:\x1b[0m", .{ 13, 22 });
    print("\x1b[{d};{d}H  1 - Spaces Clear", .{ 14, 22 });
    print("\x1b[{d};{d}H  2 - Solid Color", .{ 15, 22 });
    print("\x1b[{d};{d}H  3 - Transparent", .{ 16, 22 });
    print("\x1b[{d};{d}H  4 - Patterns", .{ 17, 22 });
    print("\x1b[{d};{d}H  5 - Modal Dialog", .{ 18, 22 });
    print("\x1b[{d};{d}H  6 - Tooltips", .{ 19, 22 });
    print("\x1b[{d};{d}H  7 - Borders", .{ 20, 22 });
    print("\x1b[{d};{d}H  8 - Effects", .{ 21, 22 });
    print("\x1b[{d};{d}H\x1b[33mPress any key...\x1b[0m", .{ 23, 25 });
}

// Helper functions for drawing background content

fn drawBackgroundContent(x: u32, y: u32, width: u32, height: u32) void {
    print("\x1b[32m", .{}); // Green text
    var row: u32 = 0;
    while (row < height) : (row += 1) {
        print("\x1b[{d};{d}H", .{ y + row, x });
        var col: u32 = 0;
        while (col < width) : (col += 1) {
            const char = if ((row + col) % 3 == 0) "█" else if ((row + col) % 3 == 1) "▓" else "▒";
            print("{s}", .{char});
        }
    }
    print("\x1b[0m", .{});
}

fn drawColorfulBackground(x: u32, y: u32, width: u32, height: u32) void {
    const colors = [_]u8{ 31, 32, 33, 34, 35, 36 }; // Red through Cyan
    var row: u32 = 0;
    while (row < height) : (row += 1) {
        print("\x1b[{d};{d}H", .{ y + row, x });
        var col: u32 = 0;
        while (col < width) : (col += 1) {
            const color_idx = (row + col) % colors.len;
            print("\x1b[{d}m█\x1b[0m", .{colors[color_idx]});
        }
    }
}

fn drawInteractiveElements() void {
    // Draw some "buttons" as background
    print("\x1b[14;15H\x1b[44;37m[ Button 1 ]\x1b[0m", .{});
    print("\x1b[14;32H\x1b[42;37m[ Button 2 ]\x1b[0m", .{});
    print("\x1b[14;49H\x1b[45;37m[ Button 3 ]\x1b[0m", .{});
    print("\x1b[19;22H\x1b[46;30m[ Action Item ]\x1b[0m", .{});
    print("\x1b[19;42H\x1b[43;30m[   Submit   ]\x1b[0m", .{});
}

fn clearScreen() void {
    print("\x1b[2J\x1b[H", .{});
}

fn clearDemoArea() void {
    // Clear the demo area (lines 10-30)
    var line: u32 = 10;
    while (line <= 30) : (line += 1) {
        print("\x1b[{d};1H\x1b[2K", .{line});
    }
}
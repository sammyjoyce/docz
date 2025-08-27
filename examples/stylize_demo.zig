//! Demonstration of the new Stylize trait system and styled widgets
//! This example showcases ergonomic styling patterns for TUI applications

const std = @import("std");
const stylize = @import("../src/shared/tui/core/stylize.zig");
const styled_widgets = @import("../src/shared/tui/widgets/styled_widgets.zig");
const term = @import("../src/shared/term/mod.zig");
const terminal_mod = @import("../src/shared/term/unified.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal
    var terminal = try terminal_mod.Terminal.init(allocator, .{});
    defer terminal.deinit();

    const stdout = std.io.getStdOut().writer();

    try terminal.enterRawMode();
    defer terminal.exitRawMode() catch {};

    try terminal.clearScreen();
    try terminal.hideCursor();
    defer terminal.showCursor() catch {};

    // Demo 1: Basic Stylize trait usage
    try demonstrateBasicStylize(&terminal, stdout);

    // Demo 2: StyleBuilder pattern
    try demonstrateStyleBuilder(&terminal, stdout);

    // Demo 3: Style composition (merge and patch)
    try demonstrateStyleComposition(&terminal, stdout);

    // Demo 4: Styled widgets showcase
    try demonstrateStyledWidgets(allocator, &terminal, stdout);

    // Demo 5: Advanced styling patterns
    try demonstrateAdvancedPatterns(allocator, &terminal, stdout);

    // Wait for key press
    try stdout.print("\n\nPress any key to exit...", .{});
    _ = try terminal.readKey();
}

fn demonstrateBasicStylize(terminal: anytype, stdout: anytype) !void {
    try terminal.moveCursor(2, 2);
    try stdout.print("=== Basic Stylize Trait Usage ===\n\n", .{});

    // Create styled text using fluent API
    var text1 = stylize.StyledText.init("This is red and bold text");
    _ = text1.red().bold();

    var text2 = stylize.StyledText.init("This is blue on yellow background");
    _ = text2.blue().on_yellow();

    var text3 = stylize.StyledText.init("This is italic green with underline");
    _ = text3.green().italic().underline();

    var text4 = stylize.StyledText.init("RGB colors: custom purple");
    _ = text4.rgb(128, 0, 128);

    var text5 = stylize.StyledText.init("Hex colors: orange");
    _ = text5.hex("#FF8C00");

    // Apply styles and render
    try applyAndPrint(terminal, stdout, &text1, 4);
    try applyAndPrint(terminal, stdout, &text2, 5);
    try applyAndPrint(terminal, stdout, &text3, 6);
    try applyAndPrint(terminal, stdout, &text4, 7);
    try applyAndPrint(terminal, stdout, &text5, 8);
}

fn demonstrateStyleBuilder(terminal: anytype, stdout: anytype) !void {
    try terminal.moveCursor(2, 11);
    try stdout.print("=== StyleBuilder Pattern ===\n\n", .{});

    // Build complex styles step by step
    const style1 = stylize.StyleBuilder.init()
        .red()
        .bold()
        .italic()
        .build();

    const style2 = stylize.StyleBuilder.init()
        .fg(stylize.Style.Color{ .rgb = .{ .r = 255, .g = 165, .b = 0 } }) // Orange
        .bg(stylize.Style.Color{ .ansi = 4 }) // Blue background
        .underline()
        .build();

    const style3 = stylize.StyleBuilder.init()
        .cyan()
        .bold()
        .build();

    // Apply and display
    try renderWithStyle(terminal, stdout, "Built with StyleBuilder: Red Bold Italic", style1, 13);
    try renderWithStyle(terminal, stdout, "Orange on Blue with Underline", style2, 14);
    try renderWithStyle(terminal, stdout, "Cyan and Bold", style3, 15);
}

fn demonstrateStyleComposition(terminal: anytype, stdout: anytype) !void {
    try terminal.moveCursor(2, 18);
    try stdout.print("=== Style Composition ===\n\n", .{});

    // Base styles
    const base_style = stylize.Style{
        .fg_color = stylize.Style.Color{ .ansi = 7 }, // White
        .bold = true,
    };

    const accent_style = stylize.Style{
        .bg_color = stylize.Style.Color{ .ansi = 4 }, // Blue background
        .italic = true,
    };

    // Merge styles
    const merged = base_style.merge(accent_style);
    try renderWithStyle(terminal, stdout, "Merged: White Bold + Blue BG Italic", merged, 20);

    // Patch styles
    const patched = base_style.patch(stylize.StylePatch{
        .fg_color = stylize.Style.Color{ .ansi = 3 }, // Yellow
        .underline = true,
    });
    try renderWithStyle(terminal, stdout, "Patched: Base style with yellow and underline", patched, 21);
}

fn demonstrateStyledWidgets(allocator: std.mem.Allocator, terminal: anytype, stdout: anytype) !void {
    try terminal.moveCursor(2, 24);
    try stdout.print("=== Styled Widgets Showcase ===\n\n", .{});

    // Styled Button Examples
    var button1 = try styled_widgets.StyledButton.init(
        allocator,
        "Primary Button",
        .{ .x = 4, .y = 26, .width = 16, .height = 3 }
    );
    _ = button1.white().on_blue().bold()
        .onHover(stylize.StyleBuilder.init().black().on_cyan().build())
        .onPress(stylize.StyleBuilder.init().white().on_green().build());

    var button2 = try styled_widgets.StyledButton.init(
        allocator,
        "Danger Button",
        .{ .x = 22, .y = 26, .width = 15, .height = 3 }
    );
    _ = button2.white().on_red()
        .onHover(stylize.StyleBuilder.init().yellow().on_red().bold().build());

    // Styled Progress Bar
    var progress = try styled_widgets.StyledProgressBar.init(
        allocator,
        0.75,
        .{ .x = 4, .y = 30, .width = 40, .height = 1 }
    );
    _ = progress
        .completeStyle(stylize.StyleBuilder.init().green().bold().build())
        .barStyle(stylize.StyleBuilder.init().gray().build())
        .withBarChars(.blocks);

    // Styled List
    const items = [_][]const u8{
        "▸ Option 1 - Selected",
        "  Option 2 - Normal",
        "  Option 3 - Normal",
        "  Option 4 - Hover",
    };
    var list = try styled_widgets.StyledList.init(
        allocator,
        &items,
        .{ .x = 4, .y = 32, .width = 25, .height = 5 }
    );
    _ = list.white()
        .selectedStyle(stylize.StyleBuilder.init().black().on_white().bold().build())
        .hoverStyle(stylize.StyleBuilder.init().cyan().italic().build())
        .select(0)
        .hover(3);

    // Styled Block with title
    var block = try styled_widgets.StyledBlock.init(
        allocator,
        .{ .x = 32, .y = 32, .width = 30, .height = 8 }
    );
    _ = block.withTitle("╣ Settings Panel ╠")
        .borderStyle(stylize.StyleBuilder.init().cyan().build())
        .titleStyle(stylize.StyleBuilder.init().yellow().bold().build())
        .borderType(.double);

    // Note: In a real application, these would be rendered through the widget system
    // For demo purposes, we'll just show the styled text representations
    try terminal.moveCursor(4, 26);
    try stdout.print("[Button Examples Above]", .{});
    try terminal.moveCursor(4, 30);
    try stdout.print("Progress: ", .{});
    try renderProgressBar(terminal, stdout, 0.75);
    try terminal.moveCursor(4, 32);
    try stdout.print("List Widget:", .{});
    try terminal.moveCursor(32, 32);
    try stdout.print("Settings Panel", .{});
}

fn demonstrateAdvancedPatterns(allocator: std.mem.Allocator, terminal: anytype, stdout: anytype) !void {
    _ = allocator;

    try terminal.moveCursor(2, 41);
    try stdout.print("=== Advanced Styling Patterns ===\n\n", .{});

    // Pattern 1: Theme-based styling
    const dark_theme = stylize.Style{
        .fg_color = stylize.Style.Color{ .ansi = 7 }, // White
        .bg_color = stylize.Style.Color{ .rgb = .{ .r = 40, .g = 40, .b = 40 } },
    };

    const light_theme = stylize.Style{
        .fg_color = stylize.Style.Color{ .ansi = 0 }, // Black
        .bg_color = stylize.Style.Color{ .rgb = .{ .r = 240, .g = 240, .b = 240 } },
    };

    try renderWithStyle(terminal, stdout, "Dark Theme Text", dark_theme, 43);
    try renderWithStyle(terminal, stdout, "Light Theme Text", light_theme, 44);

    // Pattern 2: Semantic styling
    const error_style = stylize.StyleBuilder.init().red().bold().build();
    const warning_style = stylize.StyleBuilder.init().yellow().build();
    const success_style = stylize.StyleBuilder.init().green().build();
    const info_style = stylize.StyleBuilder.init().cyan().italic().build();

    try terminal.moveCursor(4, 46);
    try renderWithStyle(terminal, stdout, "ERROR: This is an error message", error_style, 46);
    try renderWithStyle(terminal, stdout, "WARNING: This is a warning", warning_style, 47);
    try renderWithStyle(terminal, stdout, "SUCCESS: Operation completed", success_style, 48);
    try renderWithStyle(terminal, stdout, "INFO: Additional information", info_style, 49);

    // Pattern 3: Gradient effect (simulated)
    try terminal.moveCursor(4, 51);
    try stdout.print("Gradient: ", .{});
    const gradient_text = "Smooth Color Transition";
    for (gradient_text, 0..) |char, i| {
        const intensity = @as(u8, @intFromFloat(@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(gradient_text.len)) * 255));
        const gradient_style = stylize.Style{
            .fg_color = stylize.Style.Color{ .rgb = .{ .r = intensity, .g = 100, .b = 255 - intensity } },
        };
        try applyStyleDirect(terminal, gradient_style);
        try stdout.print("{c}", .{char});
    }
    try terminal.resetStyle();
}

// Helper functions
fn applyAndPrint(terminal: anytype, stdout: anytype, text: *stylize.StyledText, row: u16) !void {
    try terminal.moveCursor(4, row);
    try applyStyleDirect(terminal, text.style);
    try stdout.print("{s}", .{text.content});
    try terminal.resetStyle();
}

fn renderWithStyle(terminal: anytype, stdout: anytype, text: []const u8, style: stylize.Style, row: u16) !void {
    try terminal.moveCursor(4, row);
    try applyStyleDirect(terminal, style);
    try stdout.print("{s}", .{text});
    try terminal.resetStyle();
}

fn applyStyleDirect(terminal: anytype, style: stylize.Style) !void {
    // Convert our style to terminal codes
    if (style.fg_color) |fg| {
        switch (fg) {
            .default => {},
            .ansi => |code| try terminal.setFgColor(@enumFromInt(30 + code)),
            .palette => |code| try terminal.setFg256(code),
            .rgb => |rgb| try terminal.setFgRGB(rgb.r, rgb.g, rgb.b),
        }
    }

    if (style.bg_color) |bg| {
        switch (bg) {
            .default => {},
            .ansi => |code| try terminal.setBgColor(@enumFromInt(40 + code)),
            .palette => |code| try terminal.setBg256(code),
            .rgb => |rgb| try terminal.setBgRGB(rgb.r, rgb.g, rgb.b),
        }
    }

    if (style.bold) try terminal.setBold();
    if (style.italic) try terminal.setItalic();
    if (style.underline) try terminal.setUnderline();
    if (style.strikethrough) try terminal.setStrikethrough();
    if (style.blink) try terminal.setBlink();
    if (style.reverse) try terminal.setReverse();
}

fn renderProgressBar(terminal: anytype, stdout: anytype, value: f32) !void {
    const width = 30;
    const filled = @as(usize, @intFromFloat(@floor(@as(f32, @floatFromInt(width)) * value)));

    // Green for filled
    try terminal.setFgColor(.green);
    for (0..filled) |_| {
        try stdout.print("█", .{});
    }

    // Gray for empty
    try terminal.setFgColor(.gray);
    for (filled..width) |_| {
        try stdout.print("▒", .{});
    }

    try terminal.resetStyle();
    try stdout.print(" {d}%", .{@as(u8, @intFromFloat(value * 100))});
}
const std = @import("std");
const components = @import("../src/shared/components/mod.zig");
const tab_processor = @import("../src/shared/term/tab_processor.zig");

/// Demonstration of the cellbuf functionality
/// Terminal cell buffer features with Zig implementation
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a cell buffer
    var buffer = try components.CellBuffer.init(allocator, 40, 10);
    defer buffer.deinit();

    std.debug.print("=== Unified CellBuffer Demo ===\n\n");

    // Demo 1: Basic text with styles
    std.debug.print("1. Basic styled text:\n");
    try demoBasicStyles(&buffer, allocator);

    // Demo 2: Wide characters and combining characters
    std.debug.print("\n2. Wide and combining characters:\n");
    try demoWideAndCombining(&buffer, allocator);

    // Demo 3: Hyperlinks
    std.debug.print("\n3. Hyperlinks:\n");
    try demoHyperlinks(&buffer, allocator);

    // Demo 4: Line operations
    std.debug.print("\n4. Line insertion/deletion:\n");
    try demoLineOperations(&buffer, allocator);

    // Demo 5: Advanced styling
    std.debug.print("\n5. Advanced styling features:\n");
    try demoStyling(&buffer, allocator);

    // Demo 6: Tab processing
    std.debug.print("\n6. Tab character processing:\n");
    try demoTabProcessing(&buffer, allocator);

    std.debug.print("\nDemo completed!\n");
}

fn demoBasicStyles(buffer: *components.CellBuffer, allocator: std.mem.Allocator) !void {
    buffer.clear();

    // Create some styled text
    const bold_style = components.Style{
        .attrs = .{ .bold = true },
        .fg = .{ .ansi = 1 }, // Red
    };

    const italic_style = components.Style{
        .attrs = .{ .italic = true },
        .fg = .{ .ansi = 2 }, // Green
    };

    // Write "Hello World" with different styles
    const hello = "Hello";
    const world = "World";

    var x: usize = 0;
    for (hello) |char| {
        const cell = components.Cell{
            .rune = char,
            .width = 1,
            .style = bold_style,
        };
        _ = buffer.setCellFull(x, 0, cell);
        x += 1;
    }

    _ = buffer.setCellFull(x, 0, components.newCell(' ', 1));
    x += 1;

    for (world) |char| {
        const cell = components.Cell{
            .rune = char,
            .width = 1,
            .style = italic_style,
        };
        _ = buffer.setCellFull(x, 0, cell);
        x += 1;
    }

    const output = try buffer.toString(allocator);
    defer allocator.free(output);
    std.debug.print("Basic styled output: {s}\n", .{output});
}

fn demoWideAndCombining(buffer: *components.CellBuffer, allocator: std.mem.Allocator) !void {
    buffer.clear();

    // Wide character example (emoji)
    const emoji_cell = components.Cell{
        .rune = 0x1F600, // 😀
        .width = 2,
        .style = components.Style{},
    };
    _ = buffer.setCellFull(0, 0, emoji_cell);

    // Regular text after wide character
    const text = "Wide!";
    var x: usize = 2; // Start after wide character
    for (text) |char| {
        const cell = components.newCell(char, 1);
        _ = buffer.setCellFull(x, 0, cell);
        x += 1;
    }

    // Create a cell with combining characters (e with accent)
    var combining_cell = components.newCell('e', 1);
    try combining_cell.addCombining(allocator, 0x0301); // Combining acute accent
    _ = buffer.setCellFull(0, 1, combining_cell);

    const output = try buffer.toString(allocator);
    defer allocator.free(output);
    std.debug.print("Wide and combining chars output:\n{s}\n", .{output});
}

fn demoHyperlinks(buffer: *components.CellBuffer, allocator: std.mem.Allocator) !void {
    _ = allocator; // TODO: Implement hyperlink rendering
    buffer.clear();

    // Create hyperlinked text
    const link_style = components.Style{
        .attrs = .{ .underline = true },
        .fg = .{ .ansi = 4 }, // Blue
    };

    const link_text = "github.com";
    var x: usize = 0;
    for (link_text) |char| {
        const cell = components.Cell{
            .rune = char,
            .width = 1,
            .style = link_style,
            .link = .{ .url = "https://github.com" },
        };
        _ = buffer.setCellFull(x, 0, cell);
        x += 1;
    }

    std.debug.print("Hyperlinked text created (URL: https://github.com)\n");
}

fn demoLineOperations(buffer: *components.CellBuffer, allocator: std.mem.Allocator) !void {
    buffer.clear();

    // Fill buffer with numbered lines
    for (0..5) |y| {
        const line_text = try std.fmt.allocPrint(allocator, "Line {d}", .{y + 1});
        defer allocator.free(line_text);

        for (line_text, 0..) |char, x| {
            const cell = components.newCell(char, 1);
            _ = buffer.setCellFull(x, y, cell);
        }
    }

    std.debug.print("Original buffer:\n");
    const original = try buffer.toString(allocator);
    defer allocator.free(original);
    std.debug.print("{s}\n", .{original});

    // Insert 2 lines at position 2
    const fill_cell = components.newStyledCell('*', 1, components.Style{
        .fg = .{ .ansi = 3 }, // Yellow
    });
    buffer.insertLines(2, 2, fill_cell);

    std.debug.print("\nAfter inserting 2 lines at position 2:\n");
    const after_insert = try buffer.toString(allocator);
    defer allocator.free(after_insert);
    std.debug.print("{s}\n", .{after_insert});

    // Delete 1 line at position 1
    const blank_cell = components.newCell(' ', 1);
    buffer.deleteLines(1, 1, blank_cell);

    std.debug.print("\nAfter deleting 1 line at position 1:\n");
    const after_delete = try buffer.toString(allocator);
    defer allocator.free(after_delete);
    std.debug.print("{s}\n", .{after_delete});
}

fn demoStyling(buffer: *components.CellBuffer, allocator: std.mem.Allocator) !void {
    buffer.clear();

    // Demonstrate various underline styles
    const underline_styles = [_]components.UnderlineStyle{ .single, .double, .curly, .dotted, .dashed };
    const style_names = [_][]const u8{ "Single", "Double", "Curly", "Dotted", "Dashed" };

    for (underline_styles, style_names, 0..) |ul_style, name, y| {
        const style = components.Style{
            .ul_style = ul_style,
            .ul_color = .{ .ansi = 5 }, // Magenta
            .fg = .{ .rgb = .{ .r = 0, .g = 255, .b = 255 } }, // Cyan
        };

        var x: usize = 0;
        for (name) |char| {
            const cell = components.Cell{
                .rune = char,
                .width = 1,
                .style = style,
            };
            _ = buffer.setCellFull(x, y, cell);
            x += 1;
        }
    }

    std.debug.print("Advanced styling demo:\n");
    const output = try buffer.toString(allocator);
    defer allocator.free(output);
    std.debug.print("{s}\n", .{output});

    // Show ANSI sequence generation
    const test_style = components.Style{
        .attrs = .{ .bold = true, .italic = true },
        .fg = .{ .rgb = .{ .r = 255, .g = 0, .b = 0 } },
        .bg = .{ .ansi256 = 17 },
        .ul_style = .single,
        .ul_color = .{ .ansi = 4 },
    };

    const ansi_seq = try test_style.toAnsiSeq(allocator);
    defer allocator.free(ansi_seq);
    std.debug.print("\nGenerated ANSI sequence: {s}\n", .{ansi_seq});
}

fn demoTabProcessing(buffer: *components.CellBuffer, allocator: std.mem.Allocator) !void {
    buffer.clear();

    // Demo tab expansion with different tab widths
    const tab_configs = [_]tab_processor.TabConfig{
        .{ .tab_width = 4, .expand_tabs = true },
        .{ .tab_width = 8, .expand_tabs = true },
    };

    const test_texts = [_][]const u8{
        "Hello\tWorld\t!",
        "\tIndented\ttext",
        "Col1\tCol2\tCol3",
    };

    for (tab_configs, 0..) |config, config_idx| {
        std.debug.print("\nTab width {d}:\n", .{config.tab_width});

        for (test_texts, 0..) |text, text_idx| {
            // Expand tabs using the tab processor
            const expanded = try tab_processor.expandTabs(allocator, text, config);
            defer allocator.free(expanded);

            // Calculate display width
            const width = tab_processor.displayWidth(text, config);

            std.debug.print("  Original: '{s}' (display width: {d})\n", .{text, width});
            std.debug.print("  Expanded: '{s}'\n", .{expanded});

            // Render to cell buffer for demonstration
            buffer.clear();
            var x: usize = 0;
            for (expanded) |char| {
                const cell = components.newCell(char, 1);
                _ = buffer.setCellFull(x, config_idx * 3 + text_idx, cell);
                x += 1;
            }
        }
    }

    // Demonstrate tab stop
    std.debug.print("\nTab Stop Demo:\n");
    var tab_manager = try tab_processor.TabStop.init(allocator, 80);
    defer tab_manager.deinit();

    // Show default tab stops
    std.debug.print("  Default tab stops (every 8 columns):\n");
    var col: usize = 0;
    while (col < 40) {
        const next_stop = tab_manager.nextTabStop(col);
        const spaces = tab_manager.spacesToNextTabStop(col);
        std.debug.print("    Column {d} -> next stop at {d} (spaces: {d})\n", .{col, next_stop, spaces});
        col = next_stop + 1;
    }

    // Set custom tab stop
    tab_manager.setTabStop(12);
    std.debug.print("  After setting custom tab stop at column 12:\n");
    const custom_next = tab_manager.nextTabStop(10);
    const custom_spaces = tab_manager.spacesToNextTabStop(10);
    std.debug.print("    Column 10 -> next stop at {d} (spaces: {d})\n", .{custom_next, custom_spaces});

    // Render final buffer state
    std.debug.print("\nFinal cell buffer content:\n");
    const output = try buffer.toString(allocator);
    defer allocator.free(output);
    std.debug.print("{s}\n", .{output});
}

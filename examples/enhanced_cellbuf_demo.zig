const std = @import("std");
const term = @import("../src/shared/term/enhanced_cellbuf.zig");

/// Demonstration of the enhanced cellbuf functionality
/// Advanced terminal cell buffer features with Zig implementation
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create an enhanced cell buffer
    var buffer = try term.EnhancedCellBuffer.init(allocator, 40, 10);
    defer buffer.deinit();

    std.debug.print("=== Enhanced CellBuffer Demo ===\n\n");

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
    try demoAdvancedStyling(&buffer, allocator);

    std.debug.print("\nDemo completed!\n");
}

fn demoBasicStyles(buffer: *term.EnhancedCellBuffer, allocator: std.mem.Allocator) !void {
    buffer.clear();

    // Create some styled text
    const bold_style = term.Style{
        .attrs = .{ .bold = true },
        .fg = .{ .ansi = 1 }, // Red
    };

    const italic_style = term.Style{
        .attrs = .{ .italic = true },
        .fg = .{ .ansi = 2 }, // Green
    };

    // Write "Hello World" with different styles
    const hello = "Hello";
    const world = "World";

    var x: u32 = 0;
    for (hello) |char| {
        const cell = term.Cell{
            .rune = char,
            .width = 1,
            .style = bold_style,
        };
        _ = buffer.setCell(x, 0, cell);
        x += 1;
    }

    _ = buffer.setCell(x, 0, term.newCell(' ', 1));
    x += 1;

    for (world) |char| {
        const cell = term.Cell{
            .rune = char,
            .width = 1,
            .style = italic_style,
        };
        _ = buffer.setCell(x, 0, cell);
        x += 1;
    }

    const output = try buffer.toString(allocator);
    defer allocator.free(output);
    std.debug.print("Basic styled output: {s}\n", .{output});
}

fn demoWideAndCombining(buffer: *term.EnhancedCellBuffer, allocator: std.mem.Allocator) !void {
    buffer.clear();

    // Wide character example (emoji)
    const emoji_cell = term.Cell{
        .rune = 0x1F600, // 😀
        .width = 2,
        .style = term.Style{},
    };
    _ = buffer.setCell(0, 0, emoji_cell);

    // Regular text after wide character
    const text = "Wide!";
    var x: u32 = 2; // Start after wide character
    for (text) |char| {
        const cell = term.newCell(char, 1);
        _ = buffer.setCell(x, 0, cell);
        x += 1;
    }

    // Create a cell with combining characters (e with accent)
    var combining_cell = term.newCell('e', 1);
    try combining_cell.addCombining(allocator, 0x0301); // Combining acute accent
    _ = buffer.setCell(0, 1, combining_cell);

    const output = try buffer.toString(allocator);
    defer allocator.free(output);
    std.debug.print("Wide and combining chars output:\n{s}\n", .{output});
}

fn demoHyperlinks(buffer: *term.EnhancedCellBuffer, allocator: std.mem.Allocator) !void {
    _ = allocator; // TODO: Implement hyperlink rendering
    buffer.clear();

    // Create hyperlinked text
    const link_style = term.Style{
        .attrs = .{ .underline = true },
        .fg = .{ .ansi = 4 }, // Blue
    };

    const link_text = "github.com";
    var x: u32 = 0;
    for (link_text) |char| {
        const cell = term.Cell{
            .rune = char,
            .width = 1,
            .style = link_style,
            .link = .{ .url = "https://github.com" },
        };
        _ = buffer.setCell(x, 0, cell);
        x += 1;
    }

    std.debug.print("Hyperlinked text created (URL: https://github.com)\n");
}

fn demoLineOperations(buffer: *term.EnhancedCellBuffer, allocator: std.mem.Allocator) !void {
    buffer.clear();

    // Fill buffer with numbered lines
    for (0..5) |y| {
        const line_text = try std.fmt.allocPrint(allocator, "Line {d}", .{y + 1});
        defer allocator.free(line_text);

        for (line_text, 0..) |char, x| {
            const cell = term.newCell(char, 1);
            _ = buffer.setCell(@intCast(x), @intCast(y), cell);
        }
    }

    std.debug.print("Original buffer:\n");
    const original = try buffer.toString(allocator);
    defer allocator.free(original);
    std.debug.print("{s}\n", .{original});

    // Insert 2 lines at position 2
    const fill_cell = term.newStyledCell('*', 1, term.Style{
        .fg = .{ .ansi = 3 }, // Yellow
    });
    buffer.insertLines(2, 2, fill_cell);

    std.debug.print("\nAfter inserting 2 lines at position 2:\n");
    const after_insert = try buffer.toString(allocator);
    defer allocator.free(after_insert);
    std.debug.print("{s}\n", .{after_insert});

    // Delete 1 line at position 1
    const blank_cell = term.newCell(' ', 1);
    buffer.deleteLines(1, 1, blank_cell);

    std.debug.print("\nAfter deleting 1 line at position 1:\n");
    const after_delete = try buffer.toString(allocator);
    defer allocator.free(after_delete);
    std.debug.print("{s}\n", .{after_delete});
}

fn demoAdvancedStyling(buffer: *term.EnhancedCellBuffer, allocator: std.mem.Allocator) !void {
    buffer.clear();

    // Demonstrate various underline styles
    const underline_styles = [_]term.UnderlineStyle{ .single, .double, .curly, .dotted, .dashed };
    const style_names = [_][]const u8{ "Single", "Double", "Curly", "Dotted", "Dashed" };

    for (underline_styles, style_names, 0..) |ul_style, name, y| {
        const style = term.Style{
            .ul_style = ul_style,
            .ul_color = .{ .ansi = 5 }, // Magenta
            .fg = .{ .rgb = .{ .r = 0, .g = 255, .b = 255 } }, // Cyan
        };

        var x: u32 = 0;
        for (name) |char| {
            const cell = term.Cell{
                .rune = char,
                .width = 1,
                .style = style,
            };
            _ = buffer.setCell(x, @intCast(y), cell);
            x += 1;
        }
    }

    std.debug.print("Advanced styling demo:\n");
    const output = try buffer.toString(allocator);
    defer allocator.free(output);
    std.debug.print("{s}\n", .{output});

    // Show ANSI sequence generation
    const test_style = term.Style{
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

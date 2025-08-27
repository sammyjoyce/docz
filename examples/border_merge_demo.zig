const std = @import("std");
const tui = @import("../src/shared/tui/tui.zig");
const term = @import("../src/shared/term/term.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal
    const stdout_file = std.io.getStdOut();
    const writer = stdout_file.writer();

    // Clear screen and hide cursor
    try writer.print("\x1b[2J\x1b[H\x1b[?25l", .{});
    defer writer.print("\x1b[?25h", .{}) catch {};

    // Create cell buffer for rendering
    var buffer = try term.CellBuffer.init(allocator, 80, 24);
    defer buffer.deinit();

    // Create border merger
    var merger = tui.BorderMerger.init(allocator);
    defer merger.deinit();

    // Define widget boundaries - create a grid layout
    const widgets = [_]tui.BorderMerger.WidgetBoundary{
        // Top row
        .{ .rect = .{ .x = 0, .y = 0, .width = 20, .height = 8 }, .style = .single },
        .{ .rect = .{ .x = 20, .y = 0, .width = 20, .height = 8 }, .style = .single },
        .{ .rect = .{ .x = 40, .y = 0, .width = 20, .height = 8 }, .style = .single },
        // Middle row
        .{ .rect = .{ .x = 0, .y = 8, .width = 30, .height = 8 }, .style = .double },
        .{ .rect = .{ .x = 30, .y = 8, .width = 30, .height = 8 }, .style = .double },
        // Bottom row
        .{ .rect = .{ .x = 0, .y = 16, .width = 60, .height = 8 }, .style = .rounded },
    };

    // Draw individual widgets first
    for (widgets) |widget| {
        try drawBorder(&buffer, widget);
    }

    // Register widgets with merger
    for (widgets) |widget| {
        try merger.addWidget(widget);
    }

    // Calculate merge points
    try merger.calculateMergePoints();

    // Apply border merging
    try merger.applyMerging(&buffer);

    // Add labels to widgets
    try buffer.writeString(5, 3, "Widget 1", .{});
    try buffer.writeString(25, 3, "Widget 2", .{});
    try buffer.writeString(45, 3, "Widget 3", .{});
    try buffer.writeString(10, 11, "Wide Widget 4", .{});
    try buffer.writeString(40, 11, "Wide Widget 5", .{});
    try buffer.writeString(20, 19, "Full Width Widget 6", .{});

    // Render the buffer to terminal
    try renderBuffer(&buffer, writer);

    // Show title and instructions
    try writer.print("\x1b[1;1H\x1b[7m Border Merge Demo - Seamless Widget Connections \x1b[27m", .{});
    try writer.print("\x1b[25;1HPress any key to exit...", .{});

    // Wait for keypress
    const stdin_file = std.io.getStdIn();
    try term.enableRawMode(stdin_file.handle);
    defer term.disableRawMode(stdin_file.handle) catch {};

    var buf: [1]u8 = undefined;
    _ = try stdin_file.read(&buf);
}

fn drawBorder(buffer: *term.CellBuffer, widget: tui.BorderMerger.WidgetBoundary) !void {
    const chars = getBorderChars(widget.style);

    const x = widget.rect.x;
    const y = widget.rect.y;
    const w = widget.rect.width;
    const h = widget.rect.height;

    // Draw corners
    try buffer.setCell(x, y, .{ .rune = chars.top_left, .style = .{} });
    try buffer.setCell(x + w - 1, y, .{ .rune = chars.top_right, .style = .{} });
    try buffer.setCell(x, y + h - 1, .{ .rune = chars.bottom_left, .style = .{} });
    try buffer.setCell(x + w - 1, y + h - 1, .{ .rune = chars.bottom_right, .style = .{} });

    // Draw horizontal lines
    var i: usize = 1;
    while (i < w - 1) : (i += 1) {
        try buffer.setCell(x + i, y, .{ .rune = chars.horizontal, .style = .{} });
        try buffer.setCell(x + i, y + h - 1, .{ .rune = chars.horizontal, .style = .{} });
    }

    // Draw vertical lines
    i = 1;
    while (i < h - 1) : (i += 1) {
        try buffer.setCell(x, y + i, .{ .rune = chars.vertical, .style = .{} });
        try buffer.setCell(x + w - 1, y + i, .{ .rune = chars.vertical, .style = .{} });
    }
}

const BorderChars = struct {
    horizontal: u21,
    vertical: u21,
    top_left: u21,
    top_right: u21,
    bottom_left: u21,
    bottom_right: u21,
};

fn getBorderChars(style: tui.BorderStyle) BorderChars {
    return switch (style) {
        .single => .{
            .horizontal = '─',
            .vertical = '│',
            .top_left = '┌',
            .top_right = '┐',
            .bottom_left = '└',
            .bottom_right = '┘',
        },
        .double => .{
            .horizontal = '═',
            .vertical = '║',
            .top_left = '╔',
            .top_right = '╗',
            .bottom_left = '╚',
            .bottom_right = '╝',
        },
        .rounded => .{
            .horizontal = '─',
            .vertical = '│',
            .top_left = '╭',
            .top_right = '╮',
            .bottom_left = '╰',
            .bottom_right = '╯',
        },
        .thick => .{
            .horizontal = '━',
            .vertical = '┃',
            .top_left = '┏',
            .top_right = '┓',
            .bottom_left = '┗',
            .bottom_right = '┛',
        },
        else => .{
            .horizontal = '-',
            .vertical = '|',
            .top_left = '+',
            .top_right = '+',
            .bottom_left = '+',
            .bottom_right = '+',
        },
    };
}

fn renderBuffer(buffer: *term.CellBuffer, writer: anytype) !void {
    for (0..buffer.height) |y| {
        for (0..buffer.width) |x| {
            const cell = buffer.getCell(@intCast(x), @intCast(y));
            if (cell.rune != ' ') {
                try writer.print("\x1b[{d};{d}H{u}", .{ y + 1, x + 1, cell.rune });
            }
        }
    }
}
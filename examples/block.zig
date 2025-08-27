//! Demo for the Block widget showing various border styles, titles, and content wrapping

const std = @import("std");
const tui = @import("../src/shared/tui/mod.zig");
const term = @import("../src/shared/term/mod.zig");
const block_mod = @import("../src/shared/tui/widgets/core/block.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    _ = allocator;
    
    // Initialize terminal
    try term.writer.init();
    defer term.writer.deinit();
    
    // Clear screen
    try term.cursor.clearScreen();
    try term.cursor.moveTo(0, 0);
    
    try term.writer.print("=== Block Widget Demo ===\n\n", .{});
    
    // Demo different aspects
    try demoBorderStyles();
    try demoTitlePositions();
    try demoPaddingAndBackground();
    try demoNestedBlocks();
    
    // Wait for user input
    try term.writer.print("\n\nPress any key to exit...\n", .{});
    _ = try term.reader.readKey();
}

fn demoBorderStyles() !void {
    const Bounds = tui.core.bounds.Bounds;
    const Block = tui.widgets.core.Block;
    const BorderStyle = tui.widgets.core.BorderStyle;
    const Color = tui.themes.default.Color;
    
    try term.writer.print("## Border Styles\n\n", .{});
    
    const styles = [_]struct {
        style: BorderStyle,
        name: []const u8,
    }{
        .{ .style = .single, .name = "Single" },
        .{ .style = .double, .name = "Double" },
        .{ .style = .rounded, .name = "Rounded" },
        .{ .style = .thick, .name = "Thick" },
    };
    
    // Draw blocks with different border styles
    for (styles, 0..) |style_info, i| {
        const x = 5 + (@as(u32, i) * 20);
        const bounds = Bounds{ .x = x, .y = 5, .width = 18, .height = 5 };
        
        const block = Block.init(bounds)
            .withBorderStyle(style_info.style)
            .withTitle(style_info.name, .center, .top)
            .withBorderColor(Color.BRIGHT_CYAN);
        
        block.draw();
    }
    
    // Second row of border styles
    const styles2 = [_]struct {
        style: BorderStyle,
        name: []const u8,
    }{
        .{ .style = .dashed, .name = "Dashed" },
        .{ .style = .dotted, .name = "Dotted" },
        .{ .style = .ascii, .name = "ASCII" },
        .{ .style = .none, .name = "None" },
    };
    
    for (styles2, 0..) |style_info, i| {
        const x = 5 + (@as(u32, i) * 20);
        const bounds = Bounds{ .x = x, .y = 11, .width = 18, .height = 5 };
        
        var block = Block.init(bounds)
            .withBorderStyle(style_info.style)
            .withTitle(style_info.name, .center, .top)
            .withBorderColor(Color.BRIGHT_GREEN);
        
        // For "None" style, show background to make it visible
        if (style_info.style == .none) {
            block = block.withBackground(Color.DARK_GRAY);
        }
        
        block.draw();
    }
    
    try term.cursor.moveTo(17, 0);
}

fn demoTitlePositions() !void {
    const Bounds = tui.core.bounds.Bounds;
    const Block = block_mod.Block;
    const TitleAlignment = block_mod.TitleAlignment;
    const Color = tui.themes.default.Color;
    
    try term.writer.print("## Title Positions & Alignment\n\n", .{});
    
    // Title at top with different alignments
    const alignment_data = [_]struct {
        alignment: TitleAlignment,
        name: []const u8,
    }{
        .{ .alignment = .left, .name = "Left Title" },
        .{ .alignment = .center, .name = "Center Title" },
        .{ .alignment = .right, .name = "Right Title" },
    };

    for (alignment_data, 0..) |align_info, i| {
        const x = 5 + (@as(u32, i) * 25);
        const bounds = Bounds{ .x = x, .y = 20, .width = 23, .height = 5 };

        const block = Block.init(bounds)
            .withBorderStyle(.single)
            .withTitle(align_info.name, align_info.alignment, .top)
            .withTitleColor(Color.BRIGHT_YELLOW)
            .withBorderColor(Color.WHITE);

        block.draw();
    }
    
    // Title at bottom with subtitle
    {
        const bounds = Bounds{ .x = 5, .y = 26, .width = 35, .height = 5 };
        
        const block = Block.init(bounds)
            .withBorderStyle(.double)
            .withTitle("Bottom Title", .center, .bottom)
            .withTitleColor(Color.BRIGHT_MAGENTA)
            .withBorderColor(Color.WHITE);
        
        block.draw();
    }
    
    // Title inside the block
    {
        const bounds = Bounds{ .x = 42, .y = 26, .width = 35, .height = 5 };
        
        const block = Block.init(bounds)
            .withBorderStyle(.rounded)
            .withTitle("Inside Title", .center, .inside)
            .withTitleColor(Color.BRIGHT_RED)
            .withBorderColor(Color.WHITE);
        
        block.draw();
    }
    
    // Block with title and subtitle
    {
        const bounds = Bounds{ .x = 5, .y = 32, .width = 72, .height = 5 };
        
        const block = Block.init(bounds)
            .withBorderStyle(.thick)
            .withTitle("Main Title", .center, .top)
            .withSubtitle("Subtitle Information", .center)
            .withTitleColor(Color.BRIGHT_WHITE)
            .withBorderColor(Color.BRIGHT_BLUE);
        
        block.draw();
    }
    
    try term.cursor.moveTo(38, 0);
}

fn demoPaddingAndBackground() !void {
    const Bounds = tui.core.bounds.Bounds;
    const Block = tui.widgets.core.Block;
    const Padding = tui.widgets.core.Padding;
    const Color = tui.themes.default.Color;
    const print = term.writer.print;
    
    try print("## Padding & Background Colors\n\n", .{});
    
    // No padding
    {
        const bounds = Bounds{ .x = 5, .y = 41, .width = 22, .height = 6 };
        
        const block = Block.init(bounds)
            .withBorderStyle(.single)
            .withTitle("No Padding", .center, .top)
            .withBackground(Color.DARK_BLUE)
            .withContent(struct {
                fn render(inner: Bounds) void {
                    // Draw some content to show padding effect
                    term.cursor.moveTo(inner.y, inner.x) catch {};
                    print("Content", .{}) catch {};
                }
            }.render);
        
        block.draw();
    }
    
    // Uniform padding
    {
        const bounds = Bounds{ .x = 29, .y = 41, .width = 22, .height = 6 };
        
        const block = Block.init(bounds)
            .withBorderStyle(.single)
            .withTitle("Uniform Pad", .center, .top)
            .withPadding(Padding.uniform(1))
            .withBackground(Color.DARK_GREEN)
            .withContent(struct {
                fn render(inner: Bounds) void {
                    term.cursor.moveTo(inner.y, inner.x) catch {};
                    print("Content", .{}) catch {};
                }
            }.render);
        
        block.draw();
    }
    
    // Symmetric padding
    {
        const bounds = Bounds{ .x = 53, .y = 41, .width = 24, .height = 6 };
        
        const block = Block.init(bounds)
            .withBorderStyle(.single)
            .withTitle("Symmetric", .center, .top)
            .withPadding(Padding.symmetric(0, 2))
            .withBackground(Color.DARK_RED)
            .withContent(struct {
                fn render(inner: Bounds) void {
                    term.cursor.moveTo(inner.y, inner.x) catch {};
                    print("Content", .{}) catch {};
                }
            }.render);
        
        block.draw();
    }
    
    try term.cursor.moveTo(48, 0);
}

fn demoNestedBlocks() !void {
    const Bounds = tui.core.bounds.Bounds;
    const Block = tui.widgets.core.Block;
    const Padding = tui.widgets.core.Padding;
    const Color = tui.themes.default.Color;
    const print = term.writer.print;
    
    try print("## Nested Blocks & Composition\n\n", .{});
    
    // Outer block
    const outer_bounds = Bounds{ .x = 5, .y = 51, .width = 72, .height = 12 };
    
    const outer_block = Block.init(outer_bounds)
        .withBorderStyle(.double)
        .withTitle("Outer Container", .center, .top)
        .withSubtitle("Status: Active", .left)
        .withTitleColor(Color.BRIGHT_CYAN)
        .withBorderColor(Color.BRIGHT_WHITE)
        .withPadding(Padding.uniform(1))
        .withContent(struct {
            fn render(inner: Bounds) void {
                // Draw nested blocks inside
                
                // Left nested block
                const left_bounds = Bounds{ 
                    .x = inner.x, 
                    .y = inner.y, 
                    .width = inner.width / 2 - 1, 
                    .height = inner.height 
                };
                
                const left_block = Block.init(left_bounds)
                    .withBorderStyle(.single)
                    .withTitle("Left Panel", .center, .top)
                    .withBorderColor(Color.YELLOW)
                    .withContent(struct {
                        fn renderLeft(b: Bounds) void {
                            term.cursor.moveTo(b.y + 1, b.x + 1) catch {};
                            print("• Item 1", .{}) catch {};
                            term.cursor.moveTo(b.y + 2, b.x + 1) catch {};
                            print("• Item 2", .{}) catch {};
                            term.cursor.moveTo(b.y + 3, b.x + 1) catch {};
                            print("• Item 3", .{}) catch {};
                        }
                    }.renderLeft);
                
                left_block.draw();
                
                // Right nested block
                const right_bounds = Bounds{ 
                    .x = inner.x + inner.width / 2 + 1, 
                    .y = inner.y, 
                    .width = inner.width / 2 - 1, 
                    .height = inner.height 
                };
                
                const right_block = Block.init(right_bounds)
                    .withBorderStyle(.rounded)
                    .withTitle("Right Panel", .center, .top)
                    .withBorderColor(Color.GREEN)
                    .withBackground(Color.DARK_GRAY)
                    .withContent(struct {
                        fn renderRight(b: Bounds) void {
                            term.cursor.moveTo(b.y + 1, b.x + 1) catch {};
                            print("Status: OK", .{}) catch {};
                            term.cursor.moveTo(b.y + 2, b.x + 1) catch {};
                            print("CPU: 45%", .{}) catch {};
                            term.cursor.moveTo(b.y + 3, b.x + 1) catch {};
                            print("RAM: 2.3GB", .{}) catch {};
                        }
                    }.renderRight);
                
                right_block.draw();
            }
        }.render);
    
    outer_block.draw();
    
    try term.cursor.moveTo(65, 0);
}
const std = @import("std");
const render = @import("../src/shared/render/mod.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Sample markdown content
    const markdown =
        \\# Welcome to Markdown Renderer
        \\
        \\This is a comprehensive terminal markdown renderer that supports:
        \\
        \\## Features
        \\
        \\### Text Formatting
        \\- **Bold text** for emphasis
        \\- *Italic text* for style
        \\- `inline code` for code snippets
        \\- ***Bold and italic*** combined
        \\
        \\### Code Blocks
        \\
        \\```zig
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    std.debug.print("Hello, world!\n", .{});
        \\}
        \\```
        \\
        \\### Lists
        \\
        \\#### Unordered Lists
        \\- First item
        \\- Second item
        \\  - Nested item
        \\  - Another nested item
        \\- Third item
        \\
        \\#### Ordered Lists
        \\1. First step
        \\2. Second step
        \\3. Third step
        \\
        \\### Links
        \\
        \\Check out [Zig Programming Language](https://ziglang.org) for more information.
        \\
        \\### Blockquotes
        \\
        \\> This is a blockquote.
        \\> It can span multiple lines.
        \\
        \\### Tables
        \\
        \\| Header 1 | Header 2 | Header 3 |
        \\|----------|----------|----------|
        \\| Cell 1   | Cell 2   | Cell 3   |
        \\| Cell 4   | Cell 5   | Cell 6   |
        \\
        \\### Horizontal Rules
        \\
        \\---
        \\
        \\## Different Quality Tiers
        \\
        \\The renderer supports multiple quality tiers:
        \\- **Enhanced**: Full graphics and true color support
        \\- **Standard**: 256 colors and Unicode characters
        \\- **Compatible**: 16 colors and ASCII art
        \\- **Minimal**: Plain text only
        \\
        \\---
        \\
        \\*Thank you for using the markdown renderer!*
    ;

    // Test different quality tiers
    const tiers = [_]render.RenderMode{
        .enhanced,
        .standard,
        .compatible,
        .minimal,
    };

    const stdout = std.io.getStdOut().writer();

    for (tiers) |tier| {
        try stdout.print("\n{'='<^80}\n", .{""});
        try stdout.print(" Quality Tier: {s} \n", .{@tagName(tier)});
        try stdout.print("{'='<^80}\n\n", .{""});

        const options = render.MarkdownOptions{
            .max_width = 80,
            .color_enabled = true,
            .quality_tier = tier,
            .enable_hyperlinks = tier == .enhanced or tier == .standard,
            .enable_syntax_highlight = tier == .enhanced or tier == .standard,
            .show_line_numbers = tier == .enhanced,
        };

        const rendered = try render.renderMarkdown(allocator, markdown, options);
        defer allocator.free(rendered);

        try stdout.writeAll(rendered);
        try stdout.print("\n", .{});
    }

    // Interactive mode - show specific features
    try stdout.print("\n{'='<^80}\n", .{""});
    try stdout.print(" Interactive Examples \n", .{""});
    try stdout.print("{'='<^80}\n\n", .{""});

    // Example 1: Just headings
    const headings =
        \\# Level 1 Heading
        \\## Level 2 Heading
        \\### Level 3 Heading
        \\#### Level 4 Heading
        \\##### Level 5 Heading
        \\###### Level 6 Heading
    ;

    try stdout.print("Headings Example (Enhanced Mode):\n", .{});
    const heading_result = try render.renderMarkdown(allocator, headings, .{
        .quality_tier = .enhanced,
        .color_enabled = true,
    });
    defer allocator.free(heading_result);
    try stdout.writeAll(heading_result);

    // Example 2: Complex inline formatting
    const inline_complex =
        \\This text demonstrates **bold**, *italic*, and `code` formatting.
        \\You can also combine ***bold and italic*** together.
        \\Links like [this one](https://example.com) are also supported.
        \\
        \\Here's some `inline code` mixed with **bold text** and *italics*.
    ;

    try stdout.print("\nComplex Inline Formatting (Standard Mode):\n", .{});
    const inline_result = try render.renderMarkdown(allocator, inline_complex, .{
        .quality_tier = .standard,
        .color_enabled = true,
    });
    defer allocator.free(inline_result);
    try stdout.writeAll(inline_result);

    // Example 3: Code block with line numbers
    const code_example =
        \\Here's a code example:
        \\
        \\```zig
        \\const std = @import("std");
        \\const ArrayList = std.ArrayList;
        \\
        \\pub fn processData(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        \\    var result = ArrayList(u8).init(allocator);
        \\    defer result.deinit();
        \\    
        \\    for (data) |byte| {
        \\        try result.append(byte ^ 0xFF);
        \\    }
        \\    
        \\    return try result.toOwnedSlice();
        \\}
        \\```
    ;

    try stdout.print("\nCode Block with Line Numbers (Enhanced Mode):\n", .{});
    const code_result = try render.renderMarkdown(allocator, code_example, .{
        .quality_tier = .enhanced,
        .color_enabled = true,
        .show_line_numbers = true,
    });
    defer allocator.free(code_result);
    try stdout.writeAll(code_result);
}
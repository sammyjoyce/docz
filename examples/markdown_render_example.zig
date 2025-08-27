// Simple example demonstrating the markdown renderer
// This example shows how the markdown renderer would be used in practice

const std = @import("std");

pub fn main() !void {
    const print = std.debug.print;

    // Example markdown content
    const markdown_sample =
        \\# Markdown Renderer Example
        \\
        \\This demonstrates the **comprehensive markdown renderer** with support for:
        \\
        \\## Core Features
        \\
        \\### Text Formatting
        \\- **Bold text** for emphasis
        \\- *Italic text* for style  
        \\- `inline code` snippets
        \\- ***Combined bold and italic***
        \\
        \\### Code Blocks
        \\
        \\```zig
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    std.debug.print("Hello!\n", .{});
        \\}
        \\```
        \\
        \\### Lists
        \\
        \\#### Unordered
        \\- First item
        \\- Second item
        \\- Third item
        \\
        \\#### Ordered
        \\1. Step one
        \\2. Step two
        \\3. Step three
        \\
        \\### Links and References
        \\
        \\Visit [Zig Language](https://ziglang.org) for more info.
        \\
        \\### Blockquotes
        \\
        \\> "The best way to predict the future is to invent it."
        \\> - Alan Kay
        \\
        \\### Tables
        \\
        \\| Feature | Status | Notes |
        \\|---------|--------|-------|
        \\| Headings | ✓ | All levels |
        \\| Bold/Italic | ✓ | Combined too |
        \\| Code | ✓ | Inline & blocks |
        \\| Lists | ✓ | Ordered & unordered |
        \\| Links | ✓ | With hyperlinks |
        \\| Tables | ✓ | With alignment |
        \\
        \\---
        \\
        \\*End of demonstration*
    ;

    print("\n", .{});
    print("========================================\n", .{});
    print("     Markdown Renderer Demonstration    \n", .{});
    print("========================================\n", .{});
    print("\n", .{});
    
    // The actual markdown rendering would happen here when integrated
    // For now, we'll just show what the API would look like:
    
    print("The markdown renderer would be called like this:\n\n", .{});
    print("```zig\n", .{});
    print("const render = @import(\"render\");\n", .{});
    print("\n", .{});
    print("const options = render.MarkdownOptions{{\n", .{});
    print("    .max_width = 80,\n", .{});
    print("    .color_enabled = true,\n", .{});
    print("    .quality_tier = .enhanced,\n", .{});
    print("    .enable_hyperlinks = true,\n", .{});
    print("}};\n", .{});
    print("\n", .{});
    print("const rendered = try render.renderMarkdown(\n", .{});
    print("    allocator,\n", .{});
    print("    markdown_text,\n", .{});
    print("    options\n", .{});
    print(");\n", .{});
    print("defer allocator.free(rendered);\n", .{});
    print("```\n", .{});
    print("\n", .{});
    
    print("Quality tiers available:\n", .{});
    print("  • Enhanced - Full graphics, true color, animations\n", .{});
    print("  • Standard - 256 colors, Unicode blocks\n", .{});
    print("  • Compatible - 16 colors, ASCII art\n", .{});
    print("  • Minimal - Plain text only\n", .{});
    print("\n", .{});
    
    print("The renderer intelligently adapts to terminal capabilities!\n", .{});
    print("\n", .{});
    
    // Show sample markdown
    print("Sample markdown input:\n", .{});
    print("----------------------------------------\n", .{});
    print("{s}", .{markdown_sample});
    print("\n", .{});
    print("----------------------------------------\n", .{});
    print("\n", .{});
    
    print("The renderer would transform this into beautifully\n", .{});
    print("formatted terminal output with colors, styles, and\n", .{});
    print("proper layout based on the selected quality tier.\n", .{});
    print("\n", .{});
}
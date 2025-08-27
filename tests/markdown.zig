const std = @import("std");
const render = @import("../src/shared/render/markdown.zig");

 test "markdownRendering" {
    const allocator = std.testing.allocator;
    
    const markdown = "# Hello World\nThis is a **test**";
    const options = render.MarkdownOptions{
        .color_enabled = false,
        .quality_tier = .minimal,
    };
    
    const result = try render.renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);
    
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result, "Hello World") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "test") != null);
}

test "headingLevels" {
    const allocator = std.testing.allocator;
    
    const markdown = 
        \\# H1
        \\## H2
        \\### H3
        \\#### H4
        \\##### H5
        \\###### H6
    ;
    
    const options = render.MarkdownOptions{
        .color_enabled = false,
        .quality_tier = .minimal,
    };
    
    const result = try render.renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);
    
    try std.testing.expect(std.mem.indexOf(u8, result, "H1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "H6") != null);
}

test "inlineFormatting" {
    const allocator = std.testing.allocator;
    
    const markdown = 
        \\**bold** *italic* `code`
        \\***bold italic*** text
    ;
    
    const options = render.MarkdownOptions{
        .color_enabled = false,
        .quality_tier = .standard,
    };
    
    const result = try render.renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);
    
    try std.testing.expect(std.mem.indexOf(u8, result, "bold") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "italic") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "code") != null);
}

test "code_blocks" {
    const allocator = std.testing.allocator;
    
    const markdown = 
        \\```zig
        \\const x = 10;
        \\const y = 20;
        \\```
    ;
    
    const options = render.MarkdownOptions{
        .color_enabled = false,
        .quality_tier = .standard,
        .show_line_numbers = false,
    };
    
    const result = try render.renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);
    
    try std.testing.expect(std.mem.indexOf(u8, result, "const x = 10;") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "const y = 20;") != null);
}

test "lists" {
    const allocator = std.testing.allocator;
    
    const markdown = 
        \\- Item 1
        \\- Item 2
        \\
        \\1. First
        \\2. Second
    ;
    
    const options = render.MarkdownOptions{
        .color_enabled = false,
        .quality_tier = .compatible,
    };
    
    const result = try render.renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);
    
    try std.testing.expect(std.mem.indexOf(u8, result, "Item 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "1. First") != null);
}

test "links" {
    const allocator = std.testing.allocator;
    
    const markdown = "[Zig](https://ziglang.org)";
    
    const options = render.MarkdownOptions{
        .color_enabled = false,
        .quality_tier = .standard,
        .enable_hyperlinks = false, // Disable OSC 8 for testing
    };
    
    const result = try render.renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);
    
    try std.testing.expect(std.mem.indexOf(u8, result, "Zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "https://ziglang.org") != null);
}

test "blockquotes" {
    const allocator = std.testing.allocator;
    
    const markdown = "> This is a quote";
    
    const options = render.MarkdownOptions{
        .color_enabled = false,
        .quality_tier = .standard,
    };
    
    const result = try render.renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);
    
    try std.testing.expect(std.mem.indexOf(u8, result, "This is a quote") != null);
}

test "horizontal_rules" {
    const allocator = std.testing.allocator;
    
    const markdown = 
        \\Text above
        \\---
        \\Text below
    ;
    
    const options = render.MarkdownOptions{
        .color_enabled = false,
        .quality_tier = .minimal,
    };
    
    const result = try render.renderMarkdown(allocator, markdown, options);
    defer allocator.free(result);
    
    try std.testing.expect(std.mem.indexOf(u8, result, "Text above") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "---") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Text below") != null);
}

test "quality_tiers" {
    const allocator = std.testing.allocator;
    
    const markdown = "# Test";
    
    const tiers = [_]render.RenderMode{
        .rich,
        .standard,
        .compatible,
        .minimal,
    };
    
    for (tiers) |tier| {
        const options = render.MarkdownOptions{
            .color_enabled = false,
            .quality_tier = tier,
        };
        
        const result = try render.renderMarkdown(allocator, markdown, options);
        defer allocator.free(result);
        
        try std.testing.expect(result.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, result, "Test") != null);
    }
}
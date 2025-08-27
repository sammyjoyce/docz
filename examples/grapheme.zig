//! Demo for grapheme cluster support showing proper Unicode text handling

const std = @import("std");
const term = @import("../src/shared/term/mod.zig");
const grapheme = term.grapheme;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize terminal
    try term.writer.init();
    defer term.writer.deinit();
    
    // Clear screen
    try term.cursor.clearScreen();
    try term.cursor.moveTo(0, 0);
    
    try term.writer.print("=== Grapheme Cluster Support Demo ===\n\n", .{});
    
    // Demo different aspects
    try demoGraphemeCounting(allocator);
    try demoDisplayWidth(allocator);
    try demoTextTruncation(allocator);
    try demoWordWrapping(allocator);
    
    try term.writer.print("\nPress any key to exit...\n", .{});
    _ = try term.reader.readKey();
}

fn demoGraphemeCounting(allocator: std.mem.Allocator) !void {
    try term.writer.print("## Grapheme Counting (User-Perceived Characters)\n\n", .{});
    
    const test_cases = [_]struct {
        text: []const u8,
        description: []const u8,
    }{
        .{ .text = "hello", .description = "Basic ASCII" },
        .{ .text = "café", .description = "Accented character (é)" },
        .{ .text = "👍", .description = "Single emoji" },
        .{ .text = "👨‍👩‍👧‍👦", .description = "Family emoji (ZWJ sequence)" },
        .{ .text = "🇺🇸", .description = "Flag emoji (regional indicators)" },
        .{ .text = "e\u{0301}", .description = "e + combining acute accent" },
        .{ .text = "한글", .description = "Korean Hangul" },
        .{ .text = "你好", .description = "Chinese characters" },
        .{ .text = "🌈✨", .description = "Multiple emoji" },
        .{ .text = "a̐éö̲", .description = "Multiple combining marks" },
    };
    
    for (test_cases) |case| {
        const count = try grapheme.countGraphemes(allocator, case.text);
        const bytes = case.text.len;
        
        // Count UTF-8 codepoints for comparison
        var cp_count: usize = 0;
        var iter = std.unicode.Utf8View.init(case.text) catch unreachable;
        var cp_iter = iter.iterator();
        while (cp_iter.nextCodepoint()) |_| {
            cp_count += 1;
        }
        
        try term.writer.print("  Text: \"{s}\"\n", .{case.text});
        try term.writer.print("    Description: {s}\n", .{case.description});
        try term.writer.print("    Bytes: {d}, Codepoints: {d}, Graphemes: {d}\n\n", .{
            bytes, cp_count, count
        });
    }
}

fn demoDisplayWidth(allocator: std.mem.Allocator) !void {
    try term.writer.print("## Display Width Calculation\n\n", .{});
    
    const test_cases = [_]struct {
        text: []const u8,
        expected_width: usize,
    }{
        .{ .text = "hello", .expected_width = 5 },
        .{ .text = "你好", .expected_width = 4 },  // CJK = 2 columns each
        .{ .text = "😀", .expected_width = 2 },    // Emoji = 2 columns
        .{ .text = "café", .expected_width = 4 },   // Combining mark doesn't add width
        .{ .text = "👨‍👩‍👧‍👦", .expected_width = 2 },  // Complex emoji = 2 columns
        .{ .text = "A🌈B", .expected_width = 4 },  // 1 + 2 + 1
        .{ .text = "한글", .expected_width = 4 },   // Korean = 2 columns each
    };
    
    try term.writer.print("  Terminal Column Width:\n");
    try term.writer.print("  ┌─────────────────────┬─────────┬──────────┐\n", .{});
    try term.writer.print("  │ Text                │ Expected│ Actual   │\n", .{});
    try term.writer.print("  ├─────────────────────┼─────────┼──────────┤\n", .{});
    
    for (test_cases) |case| {
        const width = try grapheme.displayWidth(allocator, case.text);
        const status = if (width == case.expected_width) "✓" else "✗";
        
        try term.writer.print("  │ {s: <19} │ {d: >7} │ {d: >6} {s} │\n", .{
            case.text,
            case.expected_width,
            width,
            status
        });
    }
    
    try term.writer.print("  └─────────────────────┴─────────┴──────────┘\n\n", .{});
}

fn demoTextTruncation(allocator: std.mem.Allocator) !void {
    try term.writer.print("## Smart Text Truncation\n\n", .{});
    
    const test_texts = [_][]const u8{
        "Hello, World! This is a long text.",
        "Hello, 世界! This has wide characters.",
        "Emoji: 🌈✨🎉🎊 Fun stuff!",
        "Family: 👨‍👩‍👧‍👦 is one grapheme!",
        "Flags: 🇺🇸🇬🇧🇯🇵 are complex",
    };
    
    const widths = [_]usize{ 10, 15, 20 };
    
    for (test_texts) |text| {
        try term.writer.print("  Original: \"{s}\"\n", .{text});
        
        for (widths) |max_width| {
            const truncated = try grapheme.truncateToWidth(allocator, text, max_width, "...");
            defer allocator.free(truncated);
            
            const actual_width = try grapheme.displayWidth(allocator, truncated);
            
            try term.writer.print("    Width {d: >2}: \"{s}\" (actual: {d})\n", .{
                max_width,
                truncated,
                actual_width
            });
        }
        try term.writer.print("\n", .{});
    }
}

fn demoWordWrapping(allocator: std.mem.Allocator) !void {
    try term.writer.print("## Word Wrapping with Grapheme Awareness\n\n", .{});
    
    const text = "This is a test with emoji 🌈 and Chinese 你好 and very long words supercalifragilisticexpialidocious that need proper wrapping. Family emoji 👨‍👩‍👧‍👦 should stay together!";
    
    const wrap_widths = [_]usize{ 20, 30, 40 };
    
    for (wrap_widths) |width| {
        try term.writer.print("  Wrapped to width {d}:\n", .{width});
        try term.writer.print("  ┌", .{});
        for (0..width) |_| {
            try term.writer.print("─", .{});
        }
        try term.writer.print("┐\n", .{});
        
        const lines = try grapheme.wordWrap(allocator, text, width);
        defer {
            for (lines) |line| {
                allocator.free(line);
            }
            allocator.free(lines);
        }
        
        for (lines) |line| {
            const line_width = try grapheme.displayWidth(allocator, line);
            try term.writer.print("  │{s}", .{line});
            
            // Pad to width
            if (line_width < width) {
                for (line_width..width) |_| {
                    try term.writer.print(" ", .{});
                }
            }
            try term.writer.print("│\n", .{});
        }
        
        try term.writer.print("  └", .{});
        for (0..width) |_| {
            try term.writer.print("─", .{});
        }
        try term.writer.print("┘\n\n", .{});
    }
    
    // Demo edge cases
    try term.writer.print("  Edge Cases:\n", .{});
    
    const edge_cases = [_][]const u8{
        "NoSpacesHereAtAllJustOneLongWord",
        "Mixed中文English텍스트",
        "🌈🌈🌈🌈🌈🌈🌈🌈",
    };
    
    for (edge_cases) |edge_text| {
        try term.writer.print("    Input: \"{s}\"\n", .{edge_text});
        const wrapped = try grapheme.wordWrap(allocator, edge_text, 15);
        defer {
            for (wrapped) |line| {
                allocator.free(line);
            }
            allocator.free(wrapped);
        }
        
        for (wrapped, 0..) |line, i| {
            try term.writer.print("      Line {d}: \"{s}\"\n", .{ i + 1, line });
        }
        try term.writer.print("\n", .{});
    }
}
//! Demo showcasing the TagInput widget functionality
const std = @import("std");
const widgets = @import("../src/shared/tui/widgets/mod.zig");
const Bounds = @import("../src/shared/tui/core/bounds.zig").Bounds;
const TermCaps = @import("../src/shared/term/capabilities.zig").TermCaps;
const events = @import("../src/shared/tui/core/events.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Clear screen and hide cursor
    std.debug.print("\x1b[2J\x1b[?25l", .{});
    defer std.debug.print("\x1b[?25h\n", .{}); // Show cursor on exit

    // Create terminal capabilities detector
    const caps = TermCaps{};

    // Create tag input widget
    const bounds = Bounds{ 
        .x = 2, 
        .y = 2, 
        .width = 60, 
        .height = 5,
    };

    var tag_input = try widgets.TagInput.init(allocator, bounds, caps, .{
        .max_tags = 10,
        .placeholder = "Type a tag and press Enter...",
        .validation = .{
            .max_length = 20,
            .min_length = 2,
            .allow_duplicates = false,
        },
        .enable_autocomplete = true,
        .show_count = true,
    });
    defer tag_input.deinit();

    // Set up some autocomplete suggestions
    const suggestions = [_][]const u8{
        "javascript",
        "typescript", 
        "python",
        "rust",
        "zig",
        "golang",
        "docker",
        "kubernetes",
        "react",
        "vue",
        "angular",
        "nodejs",
    };
    tag_input.setSuggestions(&suggestions);

    // Add some initial tags as examples
    try tag_input.addTag("programming", .primary);
    try tag_input.addTag("tutorial", .success);
    try tag_input.addTag("example", .info);

    // Focus the widget
    tag_input.focus();

    // Main render loop
    std.debug.print("\x1b[H", .{}); // Move to home
    std.debug.print("=== Tag Input Widget Demo ===\n\n", .{});
    std.debug.print("Instructions:\n", .{});
    std.debug.print("- Type and press Enter to add tags\n", .{});
    std.debug.print("- Use Backspace on empty input to remove last tag\n", .{});
    std.debug.print("- Use Ctrl+Left/Right to navigate between tags\n", .{});
    std.debug.print("- Use Up/Down arrows to select autocomplete suggestions\n", .{});
    std.debug.print("- Press Ctrl+V to paste multiple tags (comma-separated)\n", .{});
    std.debug.print("- Press Ctrl+C to copy all tags\n", .{});
    std.debug.print("- Press Ctrl+Q to quit\n\n", .{});

    // Draw initial widget
    tag_input.draw();

    // Simulated interaction examples
    std.debug.print("\n\nCurrent tags:\n", .{});
    for (tag_input.getTags()) |tag| {
        const color = tag.category.getColor();
        std.debug.print("{s}[{s}]{s} ", .{ color, tag.text, "\x1b[0m" });
    }
    std.debug.print("\n\n", .{});

    // Demonstrate adding a tag programmatically
    try tag_input.addTag("demo", .warning);
    
    // Show validation in action
    std.debug.print("Validation examples:\n", .{});
    
    // Try to add a tag that's too short
    tag_input.addTag("a", .default) catch {
        std.debug.print("✗ Tag 'a' rejected (too short)\n", .{});
    };
    
    // Try to add a duplicate
    tag_input.addTag("demo", .default) catch {
        std.debug.print("✗ Tag 'demo' rejected (duplicate)\n", .{});
    };
    
    // Demonstrate paste functionality
    std.debug.print("\nPasting multiple tags: 'rust, webassembly, performance'\n", .{});
    try tag_input.pasteMultipleTags("rust, webassembly, performance");
    
    // Final render
    tag_input.draw();
    
    // Show final tag list
    std.debug.print("\n\nFinal tags ({d}):\n", .{tag_input.tags.items.len});
    for (tag_input.getTags()) |tag| {
        const color = tag.category.getColor();
        std.debug.print("{s}[{s}]{s} ", .{ color, tag.text, "\x1b[0m" });
    }
    std.debug.print("\n", .{});
}
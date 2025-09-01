//! Unit tests for Markdown agent spec

const std = @import("std");
const testing = std.testing;
const spec = @import("../agents/markdown/spec.zig");
const engine = @import("../src/engine.zig");
const tools = @import("../src/foundation/tools.zig");

test "buildSystemPrompt loads template" {
    const allocator = testing.allocator;

    const options = engine.CliOptions{
        .model = "test-model",
        .max_tokens = 4096,
        .temperature = 0.7,
        .stream = false,
        .verbose = false,
    };

    const prompt = try spec.SPEC.buildSystemPrompt(allocator, options);
    defer allocator.free(prompt);

    // System prompt should be loaded
    try testing.expect(prompt.len > 0);

    // Should contain key markdown-related terms
    try testing.expect(std.mem.indexOf(u8, prompt, "markdown") != null or
        std.mem.indexOf(u8, prompt, "Markdown") != null);
}

test "registerTools adds markdown tools" {
    const allocator = testing.allocator;

    var registry = tools.Registry.init(allocator);
    defer registry.deinit();

    try spec.SPEC.registerTools(&registry);

    // Should have registered built-ins plus 6 markdown tools
    const tool_count = registry.tools.count();
    try testing.expect(tool_count >= 6);

    // Check for specific markdown tools
    const io_tool = registry.get("io");
    try testing.expect(io_tool != null);

    const validate_tool = registry.get("validate");
    try testing.expect(validate_tool != null);
}

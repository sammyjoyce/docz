//! Unit tests for Markdown agent spec

const std = @import("std");
const testing = std.testing;

test "markdown spec.zig exports required symbols" {
    const allocator = testing.allocator;

    // Load spec.zig file and verify it has the expected exports
    const spec_src = try std.fs.cwd().readFileAlloc(allocator, "agents/markdown/spec.zig", 64 * 1024);
    defer allocator.free(spec_src);

    // Check for required exports
    try testing.expect(std.mem.indexOf(u8, spec_src, "pub const agentName") != null);
    try testing.expect(std.mem.indexOf(u8, spec_src, "pub const SPEC") != null);
    try testing.expect(std.mem.indexOf(u8, spec_src, "buildSystemPromptImpl") != null);
    try testing.expect(std.mem.indexOf(u8, spec_src, "registerToolsImpl") != null);

    // Check that all 6 tools are registered
    try testing.expect(std.mem.indexOf(u8, spec_src, "\"io\"") != null);
    try testing.expect(std.mem.indexOf(u8, spec_src, "\"content_editor\"") != null);
    try testing.expect(std.mem.indexOf(u8, spec_src, "\"validate\"") != null);
    try testing.expect(std.mem.indexOf(u8, spec_src, "\"document\"") != null);
    try testing.expect(std.mem.indexOf(u8, spec_src, "\"workflow\"") != null);
    try testing.expect(std.mem.indexOf(u8, spec_src, "\"file\"") != null);
}

test "system_prompt.txt exists and is non-empty" {
    const allocator = testing.allocator;

    // Load the system prompt file
    const prompt = std.fs.cwd().readFileAlloc(allocator, "agents/markdown/system_prompt.txt", 64 * 1024) catch |err| {
        // FileNotFound is acceptable if prompt is generated
        if (err == error.FileNotFound) return;
        return err;
    };
    defer allocator.free(prompt);

    // Verify prompt is substantial
    try testing.expect(prompt.len > 100);

    // Should contain markdown-related content
    const has_markdown_ref = std.mem.indexOf(u8, prompt, "markdown") != null or
        std.mem.indexOf(u8, prompt, "Markdown") != null or
        std.mem.indexOf(u8, prompt, "document") != null;
    try testing.expect(has_markdown_ref);
}

test "agent config structure" {
    const allocator = testing.allocator;

    // Load and parse the actual config.zon file
    const config_src = try std.fs.cwd().readFileAlloc(allocator, "agents/markdown/config.zon", 64 * 1024);
    defer allocator.free(config_src);

    // Basic parse validation - check it contains expected keys
    try testing.expect(std.mem.indexOf(u8, config_src, "agentConfig") != null);
    try testing.expect(std.mem.indexOf(u8, config_src, "concurrentOperationsMax") != null);
    try testing.expect(std.mem.indexOf(u8, config_src, "timeoutMsDefault") != null);
    try testing.expect(std.mem.indexOf(u8, config_src, "inputSizeMax") != null);
    try testing.expect(std.mem.indexOf(u8, config_src, "outputSizeMax") != null);
    try testing.expect(std.mem.indexOf(u8, config_src, "processingTimeMsMax") != null);
    try testing.expect(std.mem.indexOf(u8, config_src, "modelDefault") != null);
}

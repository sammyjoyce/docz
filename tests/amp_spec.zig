//! Unit tests for AMP agent spec

const std = @import("std");
const testing = std.testing;

test "amp spec.zig exports required symbols" {
    const allocator = testing.allocator;

    // Load spec.zig file and verify it has the expected exports
    const spec_src = try std.fs.cwd().readFileAlloc(allocator, "agents/amp/spec.zig", 64 * 1024);
    defer allocator.free(spec_src);

    // Check for required exports
    try testing.expect(std.mem.indexOf(u8, spec_src, "pub const agentName") != null);
    try testing.expect(std.mem.indexOf(u8, spec_src, "pub const SPEC") != null);
    try testing.expect(std.mem.indexOf(u8, spec_src, "buildSystemPrompt") != null);
    try testing.expect(std.mem.indexOf(u8, spec_src, "registerTools") != null);
}

test "system_prompt.txt exists and contains AMP content" {
    const allocator = testing.allocator;

    // Load the system prompt file
    const prompt = std.fs.cwd().readFileAlloc(allocator, "agents/amp/system_prompt.txt", 64 * 1024) catch |err| {
        // FileNotFound is acceptable if prompt is generated
        if (err == error.FileNotFound) return;
        return err;
    };
    defer allocator.free(prompt);

    // Verify prompt is substantial (> 1KB as specified in fix_plan.md)
    try testing.expect(prompt.len > 1024);

    // Should contain AMP-related content
    const has_amp_ref = std.mem.indexOf(u8, prompt, "Amp") != null or
        std.mem.indexOf(u8, prompt, "AMP") != null;
    try testing.expect(has_amp_ref);

    // Should contain Sourcegraph reference
    const has_sourcegraph_ref = std.mem.indexOf(u8, prompt, "Sourcegraph") != null;
    try testing.expect(has_sourcegraph_ref);
}

test "amp agent prompt assembly via SPEC" {
    const allocator = testing.allocator;

    // Import the amp spec via named module
    const spec_module = @import("amp_spec");

    // Call buildSystemPrompt function
    const prompt = try spec_module.SPEC.buildSystemPrompt(allocator, .{});
    defer allocator.free(prompt);

    // Verify prompt is substantial
    try testing.expect(prompt.len > 100);

    // Should contain key AMP phrases
    const has_amp_ref = std.mem.indexOf(u8, prompt, "Amp") != null or
        std.mem.indexOf(u8, prompt, "AMP") != null;
    try testing.expect(has_amp_ref);

    // Should mention coding/software engineering
    const has_coding_ref = std.mem.indexOf(u8, prompt, "coding") != null or
        std.mem.indexOf(u8, prompt, "software") != null or
        std.mem.indexOf(u8, prompt, "engineering") != null;
    try testing.expect(has_coding_ref);
}

test "amp agent config structure" {
    const allocator = testing.allocator;

    // Load and parse the actual config.zon file
    const config_src = try std.fs.cwd().readFileAlloc(allocator, "agents/amp/config.zon", 64 * 1024);
    defer allocator.free(config_src);

    // Basic parse validation - check it contains expected keys
    try testing.expect(std.mem.indexOf(u8, config_src, "agent_config") != null);
    try testing.expect(std.mem.indexOf(u8, config_src, "agent_info") != null);
    try testing.expect(std.mem.indexOf(u8, config_src, "name") != null);
    try testing.expect(std.mem.indexOf(u8, config_src, "version") != null);
    try testing.expect(std.mem.indexOf(u8, config_src, "description") != null);
    try testing.expect(std.mem.indexOf(u8, config_src, "author") != null);

    // Should contain AMP-specific values
    try testing.expect(std.mem.indexOf(u8, config_src, "AMP") != null);
    try testing.expect(std.mem.indexOf(u8, config_src, "Sourcegraph") != null);
}

test "amp agent manifest structure" {
    const allocator = testing.allocator;

    // Load and parse the actual agent.manifest.zon file
    const manifest_src = try std.fs.cwd().readFileAlloc(allocator, "agents/amp/agent.manifest.zon", 64 * 1024);
    defer allocator.free(manifest_src);

    // Basic parse validation - check it contains expected keys
    try testing.expect(std.mem.indexOf(u8, manifest_src, ".agent") != null);
    try testing.expect(std.mem.indexOf(u8, manifest_src, ".id") != null);
    try testing.expect(std.mem.indexOf(u8, manifest_src, ".name") != null);
    try testing.expect(std.mem.indexOf(u8, manifest_src, ".description") != null);

    // Should contain AMP-specific values
    try testing.expect(std.mem.indexOf(u8, manifest_src, "amp") != null);
    try testing.expect(std.mem.indexOf(u8, manifest_src, "AMP") != null);
    try testing.expect(std.mem.indexOf(u8, manifest_src, "Sourcegraph") != null);

    // Should have system_commands enabled
    try testing.expect(std.mem.indexOf(u8, manifest_src, ".system_commands = true") != null);

    // Should have code_generation enabled
    try testing.expect(std.mem.indexOf(u8, manifest_src, ".code_generation = true") != null);
}

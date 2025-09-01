//! Unit tests for Markdown agent spec

const std = @import("std");
const testing = std.testing;
const foundation = @import("foundation");
const engine = @import("core_engine");

test "markdown spec builds system prompt" {
    const allocator = testing.allocator;
    const spec = @import("markdown_spec");

    const options = engine.CliOptions{
        .model = "test-model",
    };

    // buildSystemPrompt should load the template
    const prompt = spec.SPEC.buildSystemPrompt(allocator, options) catch |err| {
        // FileNotFound is acceptable in test environment
        if (err == error.FileNotFound) return;
        return err;
    };
    defer allocator.free(prompt);

    // Verify prompt is non-empty
    try testing.expect(prompt.len > 0);

    // Could contain markdown-specific instructions
    // Basic check that it's not just a fallback
    try testing.expect(prompt.len > 50);
}

test "markdown spec registers tools" {
    const allocator = testing.allocator;
    const spec = @import("markdown_spec");

    var registry = foundation.tools.Registry.init(allocator);
    defer registry.deinit();

    // Register tools via spec
    try spec.SPEC.registerTools(&registry);

    // Verify markdown-specific tools are registered
    const io_tool = registry.get("io");
    try testing.expect(io_tool != null);

    const content_editor_tool = registry.get("content_editor");
    try testing.expect(content_editor_tool != null);

    const validate_tool = registry.get("validate");
    try testing.expect(validate_tool != null);

    const document_tool = registry.get("document");
    try testing.expect(document_tool != null);

    const workflow_tool = registry.get("workflow");
    try testing.expect(workflow_tool != null);

    const file_tool = registry.get("file");
    try testing.expect(file_tool != null);
}

test "agent config structure" {
    // Verify foundation.config.AgentConfig structure is available
    const config = foundation.config.createValidatedAgentConfig(
        "markdown",
        "Test description",
        "Test author",
    );

    try testing.expectEqualStrings("markdown", config.agentInfo.name);
    try testing.expect(config.defaults.concurrentOperationsMax > 0);
    try testing.expect(config.limits.inputSizeMax > 0);
}

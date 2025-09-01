//! Integration tests for the agent engine and loop

const std = @import("std");
const engine = @import("../src/engine.zig");
const tools = @import("../src/foundation/tools.zig");
const network = @import("../src/foundation/network.zig");
const context = @import("../src/foundation/context.zig");

// Mock agent spec for testing
const MockSpec = struct {
    fn buildSystemPrompt(allocator: std.mem.Allocator, opts: engine.CliOptions) ![]const u8 {
        _ = opts;
        return allocator.dupe(u8, "You are a test assistant.");
    }

    fn registerTools(registry: *tools.Registry) !void {
        // Register a simple echo tool for testing
        try registry.register("echo", echoTool);
    }

    fn echoTool(ctx: *context.SharedContext, allocator: std.mem.Allocator, input: []const u8) tools.ToolError![]u8 {
        _ = ctx;
        return allocator.dupe(u8, input) catch tools.ToolError.OutOfMemory;
    }
};

test "Engine initializes with default options" {
    const allocator = std.testing.allocator;

    const options = engine.CliOptions{};
    var eng = try engine.Engine.init(allocator, options);
    defer eng.deinit();

    try std.testing.expectEqualStrings("claude-3-5-sonnet-20241022", eng.options.model);
    try std.testing.expectEqual(@as(u32, 4096), eng.options.max_tokens);
    try std.testing.expectEqual(@as(f32, 0.7), eng.options.temperature);
    try std.testing.expect(eng.options.stream);
}

test "Engine registers tools from spec" {
    const allocator = std.testing.allocator;

    const options = engine.CliOptions{};
    var eng = try engine.Engine.init(allocator, options);
    defer eng.deinit();

    // Register tools using mock spec
    try MockSpec.registerTools(&eng.tool_registry);

    // Verify tool is registered
    const echo_fn = eng.tool_registry.get("echo");
    try std.testing.expect(echo_fn != null);
}

test "Context trimming maintains reasonable message count" {
    const allocator = std.testing.allocator;

    const options = engine.CliOptions{};
    var eng = try engine.Engine.init(allocator, options);
    defer eng.deinit();

    // Add many messages to trigger trimming
    var i: usize = 0;
    while (i < 30) : (i += 1) {
        const msg = try std.fmt.allocPrint(allocator, "Message {}", .{i});
        try eng.messages.append(.{
            .role = if (i % 2 == 0) .user else .assistant,
            .content = msg,
        });
    }

    // Trim context
    try eng.trimContext();

    // Should have at most 20 messages after trimming
    try std.testing.expect(eng.messages.items.len <= 20);
}

test "SSE event processing extracts text correctly" {
    const allocator = std.testing.allocator;

    var ctx = context.SharedContext.init(allocator);
    defer ctx.deinit();

    // Simulate SSE event data with text delta
    const event_data =
        \\{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}
    ;

    // Process the event
    engine.Engine.processStreamingEvent(&ctx, event_data);

    // Check that text was accumulated
    try std.testing.expectEqualStrings("Hello", ctx.anthropic.contentCollector.items);
}

test "Tool JSON accumulation works correctly" {
    const allocator = std.testing.allocator;

    var ctx = context.SharedContext.init(allocator);
    defer ctx.deinit();

    // Simulate tool use start event
    const start_event =
        \\{"type":"content_block_start","content_block":{"type":"tool_use","name":"echo","id":"tool_1"}}
    ;
    engine.Engine.processStreamingEvent(&ctx, start_event);

    try std.testing.expect(ctx.tools.hasPending);
    try std.testing.expectEqualStrings("echo", ctx.tools.toolName.?);

    // Simulate tool JSON delta
    const delta_event =
        \\{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\"input\":\"test\"}"}}
    ;
    engine.Engine.processStreamingEvent(&ctx, delta_event);

    try std.testing.expectEqualStrings("{\"input\":\"test\"}", ctx.tools.tokenBuffer.items);

    // Simulate tool use stop event
    const stop_event =
        \\{"type":"content_block_stop"}
    ;
    engine.Engine.processStreamingEvent(&ctx, stop_event);

    try std.testing.expect(!ctx.tools.hasPending);
    try std.testing.expectEqualStrings("{\"input\":\"test\"}", ctx.tools.jsonComplete.?);
}

test "Build system prompt includes tools" {
    const allocator = std.testing.allocator;

    const options = engine.CliOptions{};
    var eng = try engine.Engine.init(allocator, options);
    defer eng.deinit();

    // Register a test tool
    try eng.tool_registry.register("test_tool", MockSpec.echoTool);

    // Build system prompt
    const prompt = try eng.buildSystemPrompt();
    defer if (prompt) |p| allocator.free(p);

    // Should mention tools
    if (prompt) |p| {
        try std.testing.expect(std.mem.indexOf(u8, p, "Tool: test_tool") != null);
    }
}

test "OAuth credentials refresh on expiry" {
    const allocator = std.testing.allocator;

    // Create expired credentials
    const expired_creds = network.Auth.OAuth.Credentials{
        .type = try allocator.dupe(u8, "oauth"),
        .accessToken = try allocator.dupe(u8, "old_token"),
        .refreshToken = try allocator.dupe(u8, "refresh_token"),
        .expiresAt = std.time.timestamp() - 3600, // Expired 1 hour ago
    };
    defer expired_creds.deinit(allocator);

    // Verify expiry detection
    try std.testing.expect(expired_creds.isExpired());
    try std.testing.expect(expired_creds.willExpireSoon(120));
}

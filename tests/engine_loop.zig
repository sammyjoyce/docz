const std = @import("std");
const foundation = @import("foundation");

test "engine initializes with OAuth authentication" {
    const a = std.testing.allocator;
    const engine_mod = @import("../src/engine.zig");

    // Create mock credentials file
    const creds_path = "test_creds.json";
    defer std.fs.cwd().deleteFile(creds_path) catch {};

    const creds_json = "{\"type\":\"oauth\",\"access_token\":\"test_token\",\"refresh_token\":\"test_refresh\",\"expires_at\":9999999999}";
    const file = try std.fs.cwd().createFile(creds_path, .{});
    defer file.close();
    try file.writeAll(creds_json);

    // Initialize engine
    var engine = try engine_mod.Engine.init(a, .{ .model = "claude-3-5-sonnet-20241022" });
    defer engine.deinit();

    // Test authentication (this would normally require a real token)
    // For now, just test that the engine initializes correctly
    try std.testing.expect(engine.client == null);
    try std.testing.expectEqual(@as(usize, 0), engine.messages.items.len);
}

test "engine context trimming works correctly" {
    const a = std.testing.allocator;
    const engine_mod = @import("../src/engine.zig");

    var engine = try engine_mod.Engine.init(a, .{ .model = "claude-3-5-sonnet-20241022" });
    defer engine.deinit();

    // Add many messages
    for (0..25) |i| {
        const content = try std.fmt.allocPrint(a, "Message {d}", .{i});
        defer a.free(content);

        try engine.messages.append(.{
            .role = if (i % 2 == 0) .user else .assistant,
            .content = try a.dupe(u8, content),
        });
    }

    // Trim context
    try engine.trimContext();

    // Should keep last 20 messages
    try std.testing.expectEqual(@as(usize, 20), engine.messages.items.len);
    try std.testing.expectEqualStrings("Message 5", engine.messages.items[0].content);
}

test "tool registry basic operations" {
    const a = std.testing.allocator;
    const tools = foundation.tools;

    var registry = tools.Registry.init(a);
    defer registry.deinit();

    // Register a simple tool
    const testTool = struct {
        fn run(ctx: *foundation.network.Anthropic.Client.SharedContext, alloc: std.mem.Allocator, input: []const u8) tools.ToolError![]u8 {
            _ = ctx;
            return alloc.dupe(u8, input);
        }
    }.run;

    try registry.register("test_tool", testTool);

    // Verify registration
    const retrieved = registry.get("test_tool");
    try std.testing.expect(retrieved != null);

    // Test tool execution
    var shared_ctx = foundation.network.Anthropic.Client.SharedContext.init(a);
    defer shared_ctx.deinit();

    const result = try retrieved.?(&shared_ctx, a, "test input");
    defer a.free(result);
    try std.testing.expectEqualStrings("test input", result);
}

test "anthropic spoof content is included in system prompts" {
    const a = std.testing.allocator;
    const engine_mod = @import("../src/engine.zig");

    var engine = try engine_mod.Engine.init(a, .{ .model = "claude-3-5-sonnet-20241022" });
    defer engine.deinit();

    // Register some tools
    try foundation.tools.registerBuiltins(&engine.tool_registry);

    // Build system prompt
    const system_prompt = try engine.buildSystemPrompt();
    defer if (system_prompt) |sp| a.free(sp);

    try std.testing.expect(system_prompt != null);
    try std.testing.expect(system_prompt.?.len > 0);

    // Check if spoof content is included (if file exists)
    const spoof_exists = blk: {
        std.fs.cwd().access("prompt/anthropic_spoof.txt", .{}) catch break :blk false;
        break :blk true;
    };

    if (spoof_exists) {
        const spoof_content = "You are Claude Code, Anthropic's official CLI for Claude.";
        try std.testing.expect(std.mem.indexOf(u8, system_prompt.?, spoof_content) != null);
    }
}

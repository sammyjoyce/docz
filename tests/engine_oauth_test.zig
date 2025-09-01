//! Integration tests for engine with OAuth authentication

const std = @import("std");
const engine = @import("../src/engine.zig");
const network = @import("../src/foundation/network.zig");
const Auth = network.Auth;
const testing = std.testing;

test "engine: authentication initialization" {
    const allocator = testing.allocator;

    var eng = try engine.Engine.init(allocator, .{
        .model = "claude-3-5-sonnet-20241022",
        .max_tokens = 100,
        .temperature = 0.7,
        .stream = false,
        .verbose = false,
    });
    defer eng.deinit();

    // Create test credentials
    const test_dir = "test_engine_oauth";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Set AGENT_NAME for test
    try std.posix.setenv("AGENT_NAME", "test_engine", 1);
    defer std.posix.unsetenv("AGENT_NAME") catch {};

    // Create auth directory
    const auth_dir = try std.fmt.allocPrint(allocator, "{s}/.local/share/test_engine", .{std.posix.getenv("HOME").?});
    defer allocator.free(auth_dir);
    try std.fs.cwd().makePath(auth_dir);
    defer std.fs.cwd().deleteTree(auth_dir) catch {};

    // Save test credentials
    const store = Auth.store.TokenStore.init(allocator, .{
        .agent_name = "test_engine",
    });

    const test_creds = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "test_access_token",
        .refresh_token = "test_refresh_token",
        .expires_at = std.time.timestamp() + 3600,
    };

    try store.save(test_creds);

    // Try to authenticate
    try eng.authenticate();

    // Verify client is initialized
    try testing.expect(eng.client != null);
}

test "engine: context trimming" {
    const allocator = testing.allocator;

    var eng = try engine.Engine.init(allocator, .{
        .model = "claude-3-5-sonnet-20241022",
        .max_tokens = 100,
        .temperature = 0.7,
        .stream = false,
        .verbose = false,
    });
    defer eng.deinit();

    // Add many messages to trigger trimming
    var i: usize = 0;
    while (i < 25) : (i += 1) {
        const msg = try std.fmt.allocPrint(allocator, "Test message {d}", .{i});
        defer allocator.free(msg);

        try eng.messages.append(.{
            .role = .user,
            .content = try allocator.dupe(u8, msg),
        });
    }

    // Trim context
    try eng.trimContext();

    // Should have kept only the last 20 messages (or fewer)
    try testing.expect(eng.messages.items.len <= 20);
}

test "engine: system prompt building" {
    const allocator = testing.allocator;

    var eng = try engine.Engine.init(allocator, .{
        .model = "claude-3-5-sonnet-20241022",
        .max_tokens = 100,
        .temperature = 0.7,
        .stream = false,
        .verbose = false,
    });
    defer eng.deinit();

    // Register a test tool
    const test_tool_fn = struct {
        fn testTool(ctx: *network.SharedContext, alloc: std.mem.Allocator, args_json: []const u8) ![]u8 {
            _ = ctx;
            _ = args_json;
            return alloc.dupe(u8, "Tool executed");
        }
    }.testTool;

    try eng.tool_registry.register("test_tool", "A test tool", test_tool_fn);

    // Build system prompt
    const prompt = try eng.buildSystemPrompt();
    defer if (prompt) |p| allocator.free(p);

    if (prompt) |p| {
        // Should contain tool description
        try testing.expect(std.mem.indexOf(u8, p, "test_tool") != null);
        try testing.expect(std.mem.indexOf(u8, p, "A test tool") != null);
    }
}

test "engine: tool execution" {
    const allocator = testing.allocator;

    var eng = try engine.Engine.init(allocator, .{
        .model = "claude-3-5-sonnet-20241022",
        .max_tokens = 100,
        .temperature = 0.7,
        .stream = false,
        .verbose = false,
    });
    defer eng.deinit();

    // Register a test tool
    const test_tool_fn = struct {
        fn testTool(ctx: *network.SharedContext, alloc: std.mem.Allocator, args_json: []const u8) ![]u8 {
            _ = ctx;
            
            // Parse arguments
            const parsed = try std.json.parseFromSlice(std.json.Value, alloc, args_json, .{});
            defer parsed.deinit();

            if (parsed.value == .object) {
                if (parsed.value.object.get("test_param")) |param| {
                    if (param == .string) {
                        return std.fmt.allocPrint(alloc, "Received: {s}", .{param.string});
                    }
                }
            }
            
            return alloc.dupe(u8, "No param");
        }
    }.testTool;

    try eng.tool_registry.register("test_tool", "A test tool", test_tool_fn);

    // Create test arguments
    const test_args = try std.json.stringifyAlloc(allocator, .{
        .test_param = "hello",
    }, .{});
    defer allocator.free(test_args);

    const args_value = try std.json.parseFromSlice(std.json.Value, allocator, test_args, .{});
    defer args_value.deinit();

    // Execute tool
    try eng.executeTool("test_tool", &args_value.value);

    // Should have added a result message
    const last_msg = eng.messages.items[eng.messages.items.len - 1];
    try testing.expect(std.mem.indexOf(u8, last_msg.content, "Received: hello") != null);
}

test "engine: SSE event processing" {
    const allocator = testing.allocator;

    var shared_ctx = network.SharedContext.init(allocator);
    defer shared_ctx.deinit();

    // Test message_start event
    const message_start = 
        \\{"type":"message_start","message":{"id":"msg_123","model":"claude-3","stop_reason":null}}
    ;
    engine.Engine.processStreamingEvent(&shared_ctx, message_start);
    try testing.expectEqualStrings("msg_123", shared_ctx.anthropic.messageId.?);
    try testing.expectEqualStrings("claude-3", shared_ctx.anthropic.model.?);

    // Test content_block_start for tool use
    const tool_start = 
        \\{"type":"content_block_start","content_block":{"type":"tool_use","id":"tool_1","name":"calculator"}}
    ;
    engine.Engine.processStreamingEvent(&shared_ctx, tool_start);
    try testing.expect(shared_ctx.tools.hasPending);
    try testing.expectEqualStrings("calculator", shared_ctx.tools.toolName.?);

    // Test content_block_delta with text
    const text_delta = 
        \\{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello "}}
    ;
    engine.Engine.processStreamingEvent(&shared_ctx, text_delta);
    try testing.expectEqualStrings("Hello ", shared_ctx.anthropic.contentCollector.items);

    // Test content_block_delta with more text
    const text_delta2 = 
        \\{"type":"content_block_delta","delta":{"type":"text_delta","text":"world!"}}
    ;
    engine.Engine.processStreamingEvent(&shared_ctx, text_delta2);
    try testing.expectEqualStrings("Hello world!", shared_ctx.anthropic.contentCollector.items);

    // Test tool JSON accumulation
    shared_ctx.anthropic.contentCollector.clearRetainingCapacity();
    const json_delta = 
        \\{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\"x\":42"}}
    ;
    engine.Engine.processStreamingEvent(&shared_ctx, json_delta);
    try testing.expectEqualStrings("{\"x\":42", shared_ctx.tools.tokenBuffer.items);

    // Test content_block_stop finalizes tool JSON
    const block_stop = 
        \\{"type":"content_block_stop"}
    ;
    engine.Engine.processStreamingEvent(&shared_ctx, block_stop);
    try testing.expect(!shared_ctx.tools.hasPending);
    try testing.expectEqualStrings("{\"x\":42", shared_ctx.tools.jsonComplete.?);

    // Test message_delta with stop reason
    const message_delta = 
        \\{"type":"message_delta","delta":{"stop_reason":"end_turn"}}
    ;
    engine.Engine.processStreamingEvent(&shared_ctx, message_delta);
    try testing.expectEqualStrings("end_turn", shared_ctx.anthropic.stopReason.?);
}

test "engine: AgentSpec interface" {
    const allocator = testing.allocator;

    // Create a test agent spec
    const TestSpec = struct {
        fn buildSystemPrompt(alloc: std.mem.Allocator, opts: engine.CliOptions) ![]const u8 {
            _ = opts;
            return alloc.dupe(u8, "Test system prompt");
        }

        fn registerTools(registry: *@import("../src/foundation/tools.zig").Registry) !void {
            const tool_fn = struct {
                fn tool(ctx: *network.SharedContext, alloc: std.mem.Allocator, args: []const u8) ![]u8 {
                    _ = ctx;
                    _ = args;
                    return alloc.dupe(u8, "Tool result");
                }
            }.tool;
            try registry.register("test_tool", "Test tool", tool_fn);
        }
    };

    const spec = engine.AgentSpec{
        .buildSystemPrompt = TestSpec.buildSystemPrompt,
        .registerTools = TestSpec.registerTools,
    };

    // Test system prompt building
    const opts = engine.CliOptions{};
    const prompt = try spec.buildSystemPrompt(allocator, opts);
    defer allocator.free(prompt);
    try testing.expectEqualStrings("Test system prompt", prompt);

    // Test tool registration
    var registry = @import("../src/foundation/tools.zig").Registry.init(allocator);
    defer registry.deinit();
    
    try spec.registerTools(&registry);
    const tool = registry.get("test_tool");
    try testing.expect(tool != null);
}
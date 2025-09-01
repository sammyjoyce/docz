const std = @import("std");
const engine_mod = @import("engine");

test "engine initialization" {
    const a = std.testing.allocator;
    const options = engine_mod.CliOptions{
        .model = "claude-3-5-sonnet-20241022",
        .max_tokens = 1024,
        .temperature = 0.7,
        .stream = true,
        .verbose = false,
    };

    var eng = try engine_mod.Engine.init(a, options);
    defer eng.deinit();

    try std.testing.expect(eng.options.model.len > 0);
    try std.testing.expectEqual(@as(u32, 1024), eng.options.max_tokens);
}

test "engine context trimming" {
    const a = std.testing.allocator;
    const options = engine_mod.CliOptions{};

    var eng = try engine_mod.Engine.init(a, options);
    defer eng.deinit();

    // Add more than 20 messages
    var i: usize = 0;
    while (i < 25) : (i += 1) {
        const msg = engine_mod.network.Anthropic.Message{
            .role = .user,
            .content = try std.fmt.allocPrint(a, "Message {d}", .{i}),
        };
        try eng.messages.append(msg);
    }

    try eng.trimContext();

    // Should keep only last 20 messages
    try std.testing.expectEqual(@as(usize, 20), eng.messages.items.len);
    try std.testing.expectEqualStrings("Message 5", eng.messages.items[0].content);
}

test "engine streaming event processing" {
    const a = std.testing.allocator;
    const options = engine_mod.CliOptions{};

    var eng = try engine_mod.Engine.init(a, options);
    defer eng.deinit();

    // Test message_start event
    const messageStartEvent = "{\"type\":\"message_start\",\"message\":{\"id\":\"msg_123\",\"model\":\"claude-3-5-sonnet\"}}";
    engine_mod.Engine.processStreamingEvent(&eng.shared_ctx, messageStartEvent);
    try std.testing.expect(eng.shared_ctx.anthropic.messageId != null);
    try std.testing.expectEqualStrings("msg_123", eng.shared_ctx.anthropic.messageId.?);

    // Test content_block_delta with text
    const textDeltaEvent = "{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}";
    engine_mod.Engine.processStreamingEvent(&eng.shared_ctx, textDeltaEvent);
    try std.testing.expect(std.mem.indexOf(u8, eng.shared_ctx.anthropic.contentCollector.items, "Hello") != null);

    // Test content_block_stop
    const stopEvent = "{\"type\":\"content_block_stop\"}";
    engine_mod.Engine.processStreamingEvent(&eng.shared_ctx, stopEvent);
    // Should not crash
}
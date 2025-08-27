//! Anthropic client (split from anthropic.zig)
//! Thin wrapper that delegates to legacy implementation during transition.

const std = @import("std");
const svc = @import("../Service.zig");
const legacy = @import("../anthropic.zig");
const models = @import("models.zig");

pub const Error = legacy.Error;
pub const Message = legacy.Message;
pub const MessageRole = legacy.MessageRole;

/// High-level request interface for messages API.
pub const MessagesRequest = struct {
    model: []const u8,
    messages: []const Message,
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
    stream: bool = false,
};

pub const MessagesResponse = struct {
    content: []const u8,
    stop_reason: []const u8,
    usage_input_tokens: u32,
    usage_output_tokens: u32,
};

/// Typed client using UI-free network service. For now, delegate to legacy client.
pub const AnthropicClient = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) !AnthropicClient {
        // Delegate basic validation to legacy module for now
        _ = allocator;
        if (api_key.len == 0) return Error.MissingAPIKey;
        return .{ .allocator = allocator, .api_key = api_key };
    }

    /// Non-streaming call that returns the full response.
    pub fn create(self: *AnthropicClient, req: MessagesRequest) !MessagesResponse {
        // Bridge to legacy API until full split is complete
        var legacy_client = try legacy.AnthropicClient.init(self.allocator, self.api_key);
        defer legacy_client.deinit();

        const legacy_resp = try legacy_client.create(.{
            .model = req.model,
            .messages = req.messages,
            .max_tokens = req.max_tokens orelse 1024,
            .temperature = req.temperature orelse 0.7,
        });
        return .{
            .content = legacy_resp.content,
            .stop_reason = legacy_resp.stop_reason,
            .usage_input_tokens = legacy_resp.usage_input_tokens,
            .usage_output_tokens = legacy_resp.usage_output_tokens,
        };
    }

    /// Streaming call using a token callback. Delegates to legacy for now.
    pub fn stream(self: *AnthropicClient, req: struct {
        model: []const u8,
        messages: []const Message,
        on_token: *const fn ([]const u8) void,
        temperature: ?f32 = null,
    }) !void {
        var legacy_client = try legacy.AnthropicClient.init(self.allocator, self.api_key);
        defer legacy_client.deinit();
        try legacy_client.stream(.{
            .model = req.model,
            .messages = req.messages,
            .on_token = req.on_token,
            .temperature = req.temperature orelse 0.7,
        });
    }
};

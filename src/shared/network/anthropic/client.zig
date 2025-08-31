//! Anthropic client implementation
//! Complete implementation extracted and adapted from the monolithic anthropic.zig file.
//! Provides clean API for interacting with Anthropic's Messages API with both API key and OAuth support.
//!
//! Features:
//! - API key and OAuth authentication
//! - Streaming and non-streaming message completions
//! - Automatic token refresh for OAuth sessions
//! - Cost calculation with Pro/Max subscription support
//! - Single-flight protection for token refresh
//! - Retry logic for expired OAuth tokens
//!
//! This implementation replaces the legacy wrapper and integrates with:
//! - models.zig for type definitions
//! - oauth.zig for OAuth operations
//! - stream.zig for SSE streaming
//! - curl.zig for HTTP operations

const std = @import("std");
const curl = @import("curl_shared");
const models = @import("models.zig");
const oauth = @import("oauth.zig");
const stream_module = @import("stream.zig");
const SharedContext = @import("context_shared").SharedContext;

// Re-export commonly used types
pub const Message = models.Message;
pub const MessageRole = models.MessageRole;
pub const AuthType = models.AuthType;
pub const Credentials = models.Credentials;
pub const Usage = models.Usage;
pub const Error = models.Error;
pub const CostCalc = models.CostCalc;

/// High-level request interface for messages API
pub const MessageParameters = struct {
    model: []const u8,
    messages: []const Message,
    maxTokens: u32 = 1024,
    temperature: f32 = 0.7,
    stream: bool = false,
    system: ?[]const u8 = null,
    topP: ?f32 = null,
    topK: ?u32 = null,
    stopSequences: ?[]const []const u8 = null,
};

/// Response from non-streaming messages API
pub const MessageResult = struct {
    id: []const u8,
    content: []const u8,
    stopReason: []const u8,
    model: []const u8,
    usage: Usage,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *MessageResult) void {
        self.allocator.free(self.id);
        self.allocator.free(self.content);
        self.allocator.free(self.stopReason);
        self.allocator.free(self.model);
    }
};

/// Streaming parameters for the messages API
pub const StreamParameters = struct {
    model: []const u8,
    messages: []const Message,
    maxTokens: u32 = 1024,
    temperature: f32 = 0.7,
    onToken: *const fn (*SharedContext, []const u8) void,
    system: ?[]const u8 = null,
    topP: ?f32 = null,
    topK: ?u32 = null,
    stopSequences: ?[]const []const u8 = null,
};

/// Anthropic HTTP client with OAuth and API key support
pub const Client = struct {
    allocator: std.mem.Allocator,
    auth: AuthType,
    credentialsPath: ?[]const u8 = null,
    baseUrl: []const u8 = "https://api.anthropic.com",
    apiVersion: []const u8 = "2023-06-01",
    timeoutMs: u32 = 120000, // 2 minute default timeout

    const Self = @This();

    /// Initialize client with API key
    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) !Self {
        if (api_key.len == 0) return Error.MissingAPIKey;
        return Self{
            .allocator = allocator,
            .auth = AuthType{ .api_key = api_key },
        };
    }

    /// Initialize client with OAuth credentials
    pub fn initWithOAuth(
        allocator: std.mem.Allocator,
        oauthCreds: Credentials,
        credentialsPath: ?[]const u8,
    ) !Self {
        var dupedPath: ?[]const u8 = null;
        if (credentialsPath) |path| {
            dupedPath = try allocator.dupe(u8, path);
        }

        // Duplicate OAuth credentials
        const dupedCreds = Credentials{
            .type = try allocator.dupe(u8, oauthCreds.type),
            .accessToken = try allocator.dupe(u8, oauthCreds.accessToken),
            .refreshToken = try allocator.dupe(u8, oauthCreds.refreshToken),
            .expiresAt = oauthCreds.expiresAt,
        };

        return Self{
            .allocator = allocator,
            .auth = AuthType{ .oauth = dupedCreds },
            .credentialsPath = dupedPath,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        if (self.credentialsPath) |path| {
            self.allocator.free(path);
        }

        // Free auth data
        switch (self.auth) {
            .oauth => |creds| {
                self.allocator.free(creds.type);
                self.allocator.free(creds.accessToken);
                self.allocator.free(creds.refreshToken);
            },
            .api_key => {}, // String is not owned by client
        }
    }

    /// Check if current session is OAuth Pro/Max (for cost override)
    pub fn isOAuthSession(self: Self) bool {
        return switch (self.auth) {
            .oauth => true,
            .api_key => false,
        };
    }

    /// Get a cost calculator for this client
    pub fn getCostCalculator(self: Self) CostCalc {
        return CostCalc.init(self.isOAuthSession());
    }

    /// Refresh OAuth tokens if needed with single-flight protection
    pub fn refreshOAuthIfNeeded(self: *Self, ctx: *SharedContext) !void {
        switch (self.auth) {
            .api_key => return, // No refresh needed for API key
            .oauth => |oauthCreds| {
                // Check if refresh is needed (5 minute leeway)
                if (!oauthCreds.willExpireSoon(300)) return;

                // Single-flight protection
                ctx.anthropic.refreshLock.mutex.lock();
                defer ctx.anthropic.refreshLock.mutex.unlock();

                // Check again in case another thread refreshed while we waited
                if (!oauthCreds.willExpireSoon(300)) return;

                if (ctx.anthropic.refreshLock.inProgress) {
                    return Error.RefreshInProgress;
                }

                ctx.anthropic.refreshLock.inProgress = true;
                defer ctx.anthropic.refreshLock.inProgress = false;

                // Perform the refresh
                const newCreds = oauth.refreshTokens(self.allocator, oauthCreds.refreshToken) catch |err| {
                    std.log.err("Token refresh failed: {}", .{err});
                    return err;
                };

                // Free old credentials
                self.allocator.free(oauthCreds.type);
                self.allocator.free(oauthCreds.accessToken);
                self.allocator.free(oauthCreds.refreshToken);

                // Update with new credentials
                self.auth = AuthType{ .oauth = newCreds };

                // Persist updated credentials
                if (self.credentialsPath) |path| {
                    oauth.saveOAuthCredentials(self.allocator, path, newCreds) catch |err| {
                        std.log.warn("Failed to save refreshed credentials: {}", .{err});
                    };
                }
            },
        }
    }

    /// Create a non-streaming message (complete response)
    pub fn create(self: *Self, ctx: *SharedContext, req: MessageParameters) !MessageResult {
        // Use the complete method which collects the streaming response
        return self.complete(ctx, .{
            .model = req.model,
            .messages = req.messages,
            .max_tokens = req.max_tokens,
            .temperature = req.temperature,
            .system = req.system,
            .top_p = req.top_p,
            .top_k = req.top_k,
            .stop_sequences = req.stop_sequences,
        });
    }

    /// Complete method for non-streaming requests (collects streaming response)
    pub fn complete(self: *Self, ctx: *SharedContext, params: MessageParameters) !MessageResult {
        // Set up collector in shared context (not thread-safe)
        ctx.anthropic.contentCollector.clearRetainingCapacity();
        ctx.anthropic.usageInfo = Usage{};
        ctx.anthropic.messageId = null;
        ctx.anthropic.stopReason = null;
        ctx.anthropic.model = null;

        // Create stream params with our collector callback
        const streamParams = StreamParameters{
            .model = params.model,
            .maxTokens = params.maxTokens,
            .temperature = params.temperature,
            .messages = params.messages,
            .system = params.system,
            .topP = params.topP,
            .topK = params.topK,
            .stopSequences = params.stopSequences,
            .onToken = struct {
                fn callback(innerCtx: *SharedContext, data: []const u8) void {
                    // Try to parse as JSON to extract usage and content
                    const DeltaMessage = struct {
                        id: ?[]const u8 = null,
                        type: ?[]const u8 = null,
                        model: ?[]const u8 = null,
                        stopReason: ?[]const u8 = null,
                        delta: ?struct {
                            text: ?[]const u8 = null,
                            type: ?[]const u8 = null,
                        } = null,
                        usage: ?struct {
                            inputTokens: u32,
                            outputTokens: u32,
                        } = null,
                    };

                    const parsed = std.json.parseFromSlice(DeltaMessage, innerCtx.anthropic.allocator, data, .{}) catch {
                        // If not valid JSON, treat as raw text content
                        innerCtx.anthropic.contentCollector.appendSlice(innerCtx.anthropic.allocator, data) catch return;
                        return;
                    };
                    defer parsed.deinit();

                    // Extract metadata
                    if (parsed.value.id) |id| {
                        if (innerCtx.anthropic.messageId == null) {
                            innerCtx.anthropic.messageId = innerCtx.anthropic.allocator.dupe(u8, id) catch null;
                        }
                    }

                    if (parsed.value.model) |model| {
                        if (innerCtx.anthropic.model == null) {
                            innerCtx.anthropic.model = innerCtx.anthropic.allocator.dupe(u8, model) catch null;
                        }
                    }

                    if (parsed.value.stopReason) |reason| {
                        if (innerCtx.anthropic.stopReason == null) {
                            innerCtx.anthropic.stopReason = innerCtx.anthropic.allocator.dupe(u8, reason) catch null;
                        }
                    }

                    // Extract content from delta if present
                    if (parsed.value.delta) |delta| {
                        if (delta.text) |text| {
                            innerCtx.anthropic.contentCollector.appendSlice(innerCtx.anthropic.allocator, text) catch return;
                        }
                    }

                    // Extract usage if present
                    if (parsed.value.usage) |usage| {
                        innerCtx.anthropic.usageInfo.inputTokens = usage.inputTokens;
                        innerCtx.anthropic.usageInfo.outputTokens = usage.outputTokens;
                    }
                }
            }.callback,
        };

        // Perform streaming request
        try self.stream(ctx, streamParams);

        // Create owned copies of the response data
        const owned_id = try self.allocator.dupe(u8, ctx.anthropic.messageId orelse "unknown");
        errdefer self.allocator.free(owned_id);

        const owned_content = try self.allocator.dupe(u8, ctx.anthropic.contentCollector.items);
        errdefer self.allocator.free(owned_content);

        const owned_stop_reason = try self.allocator.dupe(u8, ctx.anthropic.stopReason orelse "stop");
        errdefer self.allocator.free(owned_stop_reason);

        const owned_model = try self.allocator.dupe(u8, ctx.anthropic.model orelse params.model);
        errdefer self.allocator.free(owned_model);

        // Clean up context strings using the same allocator that allocated them
        if (ctx.anthropic.messageId) |id| {
            ctx.anthropic.allocator.free(id);
            ctx.anthropic.messageId = null;
        }
        if (ctx.anthropic.stopReason) |reason| {
            ctx.anthropic.allocator.free(reason);
            ctx.anthropic.stopReason = null;
        }
        if (ctx.anthropic.model) |model| {
            ctx.anthropic.allocator.free(model);
            ctx.anthropic.model = null;
        }

        return MessageResult{
            .id = owned_id,
            .content = owned_content,
            .stopReason = owned_stop_reason,
            .model = owned_model,
            .usage = ctx.anthropic.usageInfo,
            .allocator = self.allocator,
        };
    }

    /// Stream messages using Server-Sent Events
    pub fn stream(self: *Self, ctx: *SharedContext, params: StreamParameters) !void {
        return self.streamWithRetry(ctx, params, false);
    }

    /// Internal method to handle streaming with automatic retry on 401
    fn streamWithRetry(self: *Self, ctx: *SharedContext, params: StreamParameters, is_retry: bool) !void {
        // Refresh OAuth tokens if needed (unless this is already a retry)
        if (!is_retry) {
            try self.refreshOAuthIfNeeded(ctx);
        }

        // Build request body
        const bodyJson = try self.buildBodyJson(params);
        defer self.allocator.free(bodyJson);

        // Initialize libcurl client
        var client = curl.HTTPClient.init(self.allocator) catch |err| {
            std.log.err("Failed to initialize HTTP client for streaming: {}", .{err});
            return Error.NetworkError;
        };
        defer client.deinit();

        // Prepare headers with auth
        var authHeaderValue: ?[]const u8 = null;
        defer if (authHeaderValue) |value| self.allocator.free(value);

        const headers = switch (self.auth) {
            .api_key => |key| [_]curl.Header{
                .{ .name = "x-api-key", .value = key },
                .{ .name = "accept", .value = "text/event-stream" },
                .{ .name = "content-type", .value = "application/json" },
                .{ .name = "anthropic-version", .value = self.apiVersion },
                .{ .name = "user-agent", .value = "docz/1.0 (libcurl)" },
            },
            .oauth => |creds| blk: {
                authHeaderValue = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{creds.accessToken});
                break :blk [_]curl.Header{
                    .{ .name = "authorization", .value = authHeaderValue.? },
                    .{ .name = "accept", .value = "text/event-stream" },
                    .{ .name = "content-type", .value = "application/json" },
                    .{ .name = "anthropic-version", .value = self.apiVersion },
                    .{ .name = "user-agent", .value = "docz/1.0 (libcurl)" },
                };
            },
        };

        // Create streaming context
        var streamingContext = stream_module.createStreamingContext(self.allocator, ctx, params.onToken);
        defer stream_module.destroyStreamingContext(&streamingContext);

        // Build full URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}/v1/messages", .{self.baseUrl});
        defer self.allocator.free(url);

        const req = curl.HTTPRequest{
            .method = .POST,
            .url = url,
            .headers = &headers,
            .body = bodyJson,
            .timeout_ms = self.timeoutMs,
            .verify_ssl = true,
            .follow_redirects = false,
            .verbose = false,
        };

        // Perform streaming request
        const statusCode = client.streamRequest(
            req,
            stream_module.processStreamChunk,
            &streamingContext,
        ) catch |err| {
            std.log.err("Streaming request failed: {}", .{err});
            switch (err) {
                curl.HTTPError.NetworkError => return Error.NetworkError,
                curl.HTTPError.TlsError => return Error.NetworkError,
                curl.HTTPError.Timeout => return Error.NetworkError,
                else => return Error.APIError,
            }
        };

        // Check for 401 Unauthorized and retry once for OAuth; report auth error for API keys
        if (statusCode == 401 and !is_retry) {
            std.log.warn("Received 401 Unauthorized, attempting token refresh...", .{});
            return self.streamWithRetry(ctx, params, true); // Retry once after refresh
        }

        if (statusCode == 401) {
            // After retry (or with API keys), surface as authentication error
            return Error.AuthError;
        }

        if (statusCode != 200) {
            std.log.err("HTTP error: {}", .{statusCode});
            return Error.APIError;
        }

        // Process any remaining buffered data
        if (streamingContext.buffer.items.len > 0) {
            stream_module.processSseChunk(&streamingContext, &.{}) catch |err| {
                std.log.warn("Error processing final streaming data: {}", .{err});
            };
        }
    }

    /// Build JSON request body for the messages API
    fn buildBodyJson(self: *Self, params: StreamParameters) ![]u8 {
        var buffer = std.ArrayListUnmanaged(u8){};
        defer buffer.deinit(self.allocator);

        const writer = buffer.writer(self.allocator);

        // Start JSON object
        try writer.writeAll("{");

        // Model
        try std.fmt.format(writer, "\"model\":\"{s}\",", .{params.model});

        // Max tokens
        try std.fmt.format(writer, "\"max_tokens\":{},", .{params.maxTokens});

        // Temperature
        try std.fmt.format(writer, "\"temperature\":{d:.2},", .{params.temperature});

        // Stream flag (always true for streaming requests)
        try writer.writeAll("\"stream\":true,");

        // System prompt (optional)
        if (params.system) |system| {
            try writer.writeAll("\"system\":\"");
            try writeEscapedJson(writer, system);
            try writer.writeAll("\",");
        }

        // Top-p (optional)
        if (params.topP) |top_p| {
            try std.fmt.format(writer, "\"top_p\":{d:.2},", .{top_p});
        }

        // Top-k (optional)
        if (params.topK) |top_k| {
            try std.fmt.format(writer, "\"top_k\":{},", .{top_k});
        }

        // Stop sequences (optional)
        if (params.stopSequences) |sequences| {
            try writer.writeAll("\"stop_sequences\":[");
            for (sequences, 0..) |seq, i| {
                if (i > 0) try writer.writeAll(",");
                try writer.writeAll("\"");
                try writeEscapedJson(writer, seq);
                try writer.writeAll("\"");
            }
            try writer.writeAll("],");
        }

        // Messages array
        try writer.writeAll("\"messages\":[");
        for (params.messages, 0..) |message, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("{\"role\":\"");
            try writer.writeAll(@tagName(message.role));
            try writer.writeAll("\",\"content\":\"");
            try writeEscapedJson(writer, message.content);
            try writer.writeAll("\"}");
        }
        try writer.writeAll("]");

        // End JSON object
        try writer.writeAll("}");

        return buffer.toOwnedSlice(self.allocator);
    }

    /// Helper to escape JSON strings
    fn writeEscapedJson(writer: anytype, str: []const u8) !void {
        for (str) |c| {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                0x08 => try writer.writeAll("\\b"),
                0x0C => try writer.writeAll("\\f"),
                else => {
                    if (c < 0x20) {
                        try std.fmt.format(writer, "\\u{x:0>4}", .{c});
                    } else {
                        try writer.writeByte(c);
                    }
                },
            }
        }
    }

    /// Convenience method: completion with just a prompt
    pub fn completePrompt(self: *Self, ctx: *SharedContext, model: []const u8, prompt: []const u8) ![]const u8 {
        const messages = [_]Message{
            .{ .role = .user, .content = prompt },
        };

        const response = try self.complete(ctx, .{
            .model = model,
            .messages = &messages,
        });
        defer {
            var mut_response = response;
            mut_response.deinit();
        }

        // Return owned copy of content
        return try self.allocator.dupe(u8, response.content);
    }

    /// Load OAuth credentials from file and initialize client
    pub fn initFromOAuthFile(allocator: std.mem.Allocator, file_path: []const u8) !Self {
        const creds = try oauth.loadOAuthCredentials(allocator, file_path);
        if (creds) |oauth_creds| {
            defer {
                allocator.free(oauth_creds.type);
                allocator.free(oauth_creds.access_token);
                allocator.free(oauth_creds.refresh_token);
            }
            return Self.initWithOAuth(allocator, oauth_creds, file_path);
        }
        return Error.AuthError;
    }

    /// Get authentication header value (caller owns the returned string)
    pub fn getAuthHeader(self: *Self, allocator: std.mem.Allocator) !struct { name: []const u8, value: []u8 } {
        switch (self.auth) {
            .api_key => |key| {
                return .{
                    .name = "x-api-key",
                    .value = try allocator.dupe(u8, key),
                };
            },
            .oauth => |creds| {
                return .{
                    .name = "authorization",
                    .value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{creds.access_token}),
                };
            },
        }
    }
};

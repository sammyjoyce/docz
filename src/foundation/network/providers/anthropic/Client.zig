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
const models = @import("Models.zig");
const oauth = @import("../../auth/OAuth.zig"); // Use network auth OAuth module
const stream_module = @import("Stream.zig");
const sse = @import("../../SSE.zig");
const curl = @import("../../curl.zig");
const root = @import("root");
const has_build_options = @hasDecl(root, "build_options");
const build_options = if (has_build_options) @import("build_options") else struct {
    pub const http_verbose_default = false;
    pub const anthropic_beta_oauth = "oauth-2025-04-20";
    pub const oauth_beta_header = true;
};

// Import the foundation SharedContext to ensure compatibility
const foundation_context = @import("../../../context.zig");

// Use the foundation SharedContext for compatibility with tools
pub const SharedContext = foundation_context.SharedContext;

// Re-export commonly used types
pub const Message = models.Message;
pub const MessageRole = models.MessageRole;
pub const AuthType = models.AuthType;
pub const Credentials = oauth.Credentials; // Use OAuth credentials from network auth
pub const Usage = models.Usage;
pub const Error = models.Error;
pub const CostCalc = models.CostCalculator;

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
    httpVerbose: bool = false,

    const Self = @This();

    fn maskToken(allocator: std.mem.Allocator, token: []const u8) ![]u8 {
        if (token.len <= 10) return allocator.dupe(u8, "<redacted>");
        const prefix = token[0..6];
        const suffix = token[token.len - 4 .. token.len];
        return std.fmt.allocPrint(allocator, "{s}...{s}", .{ prefix, suffix });
    }

    /// Test helper: build headers for a request without performing I/O
    /// Returns an owned slice of headers; caller must free `value` fields and the slice itself.
    pub fn buildHeadersForTest(self: *Self, allocator: std.mem.Allocator, streaming: bool) ![]curl.Header {
        var headers = std.ArrayListUnmanaged(curl.Header){};
        errdefer headers.deinit(allocator);

        switch (self.auth) {
            .api_key => |key| {
                try headers.append(allocator, .{ .name = "x-api-key", .value = try allocator.dupe(u8, key) });
                try headers.append(allocator, .{ .name = "accept", .value = try allocator.dupe(u8, if (streaming) "text/event-stream" else "application/json") });
                try headers.append(allocator, .{ .name = "content-type", .value = try allocator.dupe(u8, "application/json") });
                try headers.append(allocator, .{ .name = "anthropic-version", .value = try allocator.dupe(u8, self.apiVersion) });
                try headers.append(allocator, .{ .name = "anthropic-beta", .value = try allocator.dupe(u8, "none") });
                try headers.append(allocator, .{ .name = "user-agent", .value = try allocator.dupe(u8, "docz/1.0 (libcurl)") });
            },
            .oauth => |creds| {
                const bearer = try std.fmt.allocPrint(allocator, "Bearer {s}", .{creds.accessToken});
                defer allocator.free(bearer);
                const beta_value = if (build_options.oauth_beta_header) build_options.anthropic_beta_oauth else "none";
                try headers.append(allocator, .{ .name = "Authorization", .value = try allocator.dupe(u8, bearer) });
                try headers.append(allocator, .{ .name = "accept", .value = try allocator.dupe(u8, if (streaming) "text/event-stream" else "application/json") });
                try headers.append(allocator, .{ .name = "content-type", .value = try allocator.dupe(u8, "application/json") });
                try headers.append(allocator, .{ .name = "anthropic-version", .value = try allocator.dupe(u8, self.apiVersion) });
                try headers.append(allocator, .{ .name = "anthropic-beta", .value = try allocator.dupe(u8, beta_value) });
                try headers.append(allocator, .{ .name = "user-agent", .value = try allocator.dupe(u8, "docz/1.0 (libcurl)") });
            },
        }

        return headers.toOwnedSlice(allocator);
    }
    fn redactHeaderValue(self: *Self, name: []const u8, value: []const u8) ![]u8 {
        // Redact secrets for Authorization and x-api-key
        if (std.ascii.eqlIgnoreCase(name, "authorization")) {
            // Expect "Bearer <token>"; redact the token part
            if (std.mem.indexOfScalar(u8, value, ' ')) |sp| {
                const scheme = value[0..sp];
                const tok = value[sp + 1 ..];
                const masked = try maskToken(self.allocator, tok);
                defer self.allocator.free(masked);
                return std.fmt.allocPrint(self.allocator, "{s} {s}", .{ scheme, masked });
            }
            return self.allocator.dupe(u8, "<redacted>");
        }
        if (std.ascii.eqlIgnoreCase(name, "x-api-key")) {
            const masked = try maskToken(self.allocator, value);
            return masked;
        }
        return self.allocator.dupe(u8, value);
    }

    fn logRequestHeaders(self: *Self, url: []const u8, headers: []const curl.Header) void {
        std.log.debug("Anthropic request headers for {s}:", .{url});
        var i: usize = 0;
        while (i < headers.len) : (i += 1) {
            const h = headers[i];
            const redacted = self.redactHeaderValue(h.name, h.value) catch {
                std.log.debug("  {s}: <redaction-error>", .{h.name});
                continue;
            };
            std.log.debug("  {s}: {s}", .{ h.name, redacted });
            self.allocator.free(redacted);
        }
    }

    /// Initialize client with API key
    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) !Self {
        if (api_key.len == 0) return Error.MissingAPIKey;
        return Self{
            .allocator = allocator,
            .auth = AuthType{ .api_key = api_key },
            .httpVerbose = build_options.http_verbose_default,
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
            .httpVerbose = build_options.http_verbose_default,
        };
    }

    /// Control libcurl verbose logging at runtime
    pub fn setHttpVerbose(self: *Self, verbose: bool) void {
        self.httpVerbose = verbose;
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
                    oauth.saveCredentials(self.allocator, path, newCreds) catch |err| {
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

    /// Build JSON request body for Messages API
    fn buildBodyJson(self: *Self, params: StreamParameters) ![]u8 {
        var json_body = std.ArrayList(u8).init(self.allocator);
        defer json_body.deinit();

        try json_body.appendSlice("{");
        
        // Model
        try json_body.appendSlice("\"model\":\"");
        try json_body.appendSlice(params.model);
        try json_body.appendSlice("\",");
        
        // Max tokens
        try json_body.writer().print("\"max_tokens\":{},", .{params.maxTokens});
        
        // Temperature
        try json_body.writer().print("\"temperature\":{d:.2},", .{params.temperature});
        
        // Stream flag
        try json_body.appendSlice("\"stream\":true,");
        
        // System prompt (optional)
        if (params.system) |system| {
            try json_body.appendSlice("\"system\":\"");
            // JSON-escape the system prompt
            for (system) |c| {
                switch (c) {
                    '\\' => try json_body.appendSlice("\\\\"),
                    '"' => try json_body.appendSlice("\\\""),
                    '\n' => try json_body.appendSlice("\\n"),
                    '\r' => try json_body.appendSlice("\\r"),
                    '\t' => try json_body.appendSlice("\\t"),
                    else => try json_body.append(c),
                }
            }
            try json_body.appendSlice("\",");
        }
        
        // Messages array
        try json_body.appendSlice("\"messages\":[");
        for (params.messages, 0..) |msg, i| {
            if (i > 0) try json_body.appendSlice(",");
            try json_body.appendSlice("{\"role\":\"");
            try json_body.appendSlice(@tagName(msg.role));
            try json_body.appendSlice("\",\"content\":\"");
            // JSON-escape the content
            for (msg.content) |c| {
                switch (c) {
                    '\\' => try json_body.appendSlice("\\\\"),
                    '"' => try json_body.appendSlice("\\\""),
                    '\n' => try json_body.appendSlice("\\n"),
                    '\r' => try json_body.appendSlice("\\r"),
                    '\t' => try json_body.appendSlice("\\t"),
                    else => try json_body.append(c),
                }
            }
            try json_body.appendSlice("\"}");
        }
        try json_body.appendSlice("]");
        
        try json_body.appendSlice("}");
        
        return json_body.toOwnedSlice();
    }

    /// Stream messages using Server-Sent Events
    pub fn stream(self: *Self, ctx: *SharedContext, params: StreamParameters) !void {
        return self.streamWithRetry(ctx, params, false);
    }

    /// Internal method to handle streaming with automatic retry on 401
    fn streamWithRetry(self: *Self, ctx: *SharedContext, params: StreamParameters, is_retry: bool) !void {
        // Proactive refresh even before first attempt; ignore RefreshInProgress in concurrent scenarios
        if (!is_retry) {
            self.refreshOAuthIfNeeded(ctx) catch |err| {
                if (err != Error.RefreshInProgress) {
                    std.log.warn("Proactive OAuth refresh skipped: {}", .{err});
                }
            };
        }

        // Build request body
        const bodyJson = try self.buildBodyJson(params);
        defer self.allocator.free(bodyJson);

        // Initialize HTTP client
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Parse URL
        const uri = try std.Uri.parse(try std.fmt.allocPrint(self.allocator, "{s}/v1/messages", .{self.baseUrl}));
        defer self.allocator.free(uri.path);

        // Prepare headers
        var headers_list = std.ArrayListUnmanaged(std.http.Header){};
        defer headers_list.deinit(self.allocator);

        const is_api_key_auth = switch (self.auth) {
            .api_key => true,
            .oauth => false,
        };

        if (is_api_key_auth) {
            // API key path (standard header)
            try headers_list.append(self.allocator, .{ .name = "x-api-key", .value = self.auth.api_key });
            try headers_list.append(self.allocator, .{ .name = "accept", .value = "text/event-stream" });
            try headers_list.append(self.allocator, .{ .name = "content-type", .value = "application/json" });
            try headers_list.append(self.allocator, .{ .name = "anthropic-version", .value = self.apiVersion });
            try headers_list.append(self.allocator, .{ .name = "anthropic-beta", .value = "none" });
            try headers_list.append(self.allocator, .{ .name = "user-agent", .value = "docz/1.0" });
        } else {
            // OAuth path: Bearer only (no x-api-key fallback)
            const creds = self.auth.oauth;
            const bearer = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{creds.accessToken});
            defer self.allocator.free(bearer);
            // OAuth beta header is feature-gated via build options; default matches spec
            const beta_value = if (build_options.oauth_beta_header) build_options.anthropic_beta_oauth else "none";
            try headers_list.append(self.allocator, .{ .name = "Authorization", .value = bearer });
            try headers_list.append(self.allocator, .{ .name = "accept", .value = "text/event-stream" });
            try headers_list.append(self.allocator, .{ .name = "content-type", .value = "application/json" });
            try headers_list.append(self.allocator, .{ .name = "anthropic-version", .value = self.apiVersion });
            try headers_list.append(self.allocator, .{ .name = "anthropic-beta", .value = beta_value });
            try headers_list.append(self.allocator, .{ .name = "user-agent", .value = "docz/1.0" });
        }

        const headers = headers_list.items;
        self.logRequestHeaders(uri.path, headers);

        // Make streaming request
        var req = try client.open(.POST, uri, .{
            .server_header_buffer = &[_]u8{},
            .extra_headers = headers,
        });
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = bodyJson.len };
        try req.send();
        try req.writeAll(bodyJson);
        try req.finish();
        try req.wait();

        // Check for 401 Unauthorized and retry once for OAuth; report auth error for API keys
        if (req.response.status == .unauthorized and !is_retry) {
            std.log.warn("Received 401 Unauthorized, attempting token refresh...", .{});
            // Force a refresh regardless of current expiry to handle server-side invalidation
            switch (self.auth) {
                .oauth => |creds| {
                    const newCreds = oauth.refreshTokens(self.allocator, creds.refreshToken) catch |err| {
                        std.log.err("Token refresh on 401 failed: {}", .{err});
                        return Error.AuthError;
                    };
                    // Replace credentials and persist
                    self.allocator.free(creds.type);
                    self.allocator.free(creds.accessToken);
                    self.allocator.free(creds.refreshToken);
                    self.auth = AuthType{ .oauth = newCreds };
                    if (self.credentialsPath) |path| {
                        oauth.saveCredentials(self.allocator, path, newCreds) catch |err| {
                            std.log.warn("Failed to save refreshed credentials: {}", .{err});
                        };
                    }
                },
                .api_key => {},
            }
            return self.streamWithRetry(ctx, params, true); // Retry once after refresh
        }

        if (req.response.status == .unauthorized) {
            // After retry (or with API keys), surface as authentication error
            return Error.AuthError;
        }

        if (req.response.status != .ok) {
            // Attempt a non-streaming POST to fetch error body for diagnostics
            std.log.err("HTTP error: {}", .{req.response.status});

            const error_body = try req.reader().readAllAlloc(self.allocator, 1024 * 1024);
            defer self.allocator.free(error_body);
            std.log.err("Error body: {s}", .{error_body});

            // Surface upstream request-id when present for troubleshooting
            const maybe_req_id = blk: {
                if (req.response.headers.get("request-id")) |v| break :blk v;
                if (req.response.headers.get("Request-Id")) |v| break :blk v;
                if (req.response.headers.get("x-request-id")) |v| break :blk v;
                if (req.response.headers.get("X-Request-Id")) |v| break :blk v;
                break :blk null;
            };
            if (maybe_req_id) |rid| {
                std.log.warn("Upstream request-id: {s}", .{rid});
            }

            if (std.mem.indexOf(u8, error_body, "Invalid bearer token")) |_| {
                return Error.AuthError;
            }
            return Error.APIError;
        }

        // Process streaming response using proper SSE parser
        const sse = @import("../../SSE.zig");
        var eventState = sse.ServerSentEventBuilder.init(self.allocator);
        defer eventState.deinit();

        var buffer: [4096]u8 = undefined;
        var accumulated_data = std.ArrayList(u8).init(self.allocator);
        defer accumulated_data.deinit();

        while (true) {
            const bytes_read = try req.reader().read(&buffer);
            if (bytes_read == 0) break;

            // Accumulate data
            try accumulated_data.appendSlice(buffer[0..bytes_read]);

            // Process accumulated SSE data
            var events = std.ArrayList(sse.ServerSentEvent).init(self.allocator);
            defer {
                for (events.items) |*event| {
                    event.deinit(self.allocator);
                }
                events.deinit();
            }

            sse.processServerSentEventLines(accumulated_data.items, &eventState, &sse.ServerSentEventConfig{}, &events, self.allocator) catch |err| {
                std.log.warn("SSE processing error: {}", .{err});
                continue;
            };

            // Process completed events
            for (events.items) |event| {
                if (event.has_data and !std.mem.eql(u8, event.data, "[DONE]")) {
                    // Call the token callback with the event data
                    params.onToken(ctx, event.data);
                }
            }

            // Clear processed data
            accumulated_data.clearRetainingCapacity();
        }

        // Process any remaining accumulated data
        if (accumulated_data.items.len > 0) {
            var events = std.ArrayList(sse.ServerSentEvent).init(self.allocator);
            defer {
                for (events.items) |*event| {
                    event.deinit(self.allocator);
                }
                events.deinit();
            }

            sse.processServerSentEventLines(accumulated_data.items, &eventState, &sse.ServerSentEventConfig{}, &events, self.allocator) catch |err| {
                std.log.warn("Final SSE processing error: {}", .{err});
            };

            // Process final events
            for (events.items) |event| {
                if (event.has_data and !std.mem.eql(u8, event.data, "[DONE]")) {
                    params.onToken(ctx, event.data);
                }
            }
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
                allocator.free(oauth_creds.accessToken);
                allocator.free(oauth_creds.refreshToken);
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
                    .name = "Authorization",
                    .value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{creds.accessToken}),
                };
            },
        }
    }
};

test "getAuthHeader returns Bearer for OAuth and x-api-key for API key" {
    const a = std.testing.allocator;
    // API key path
    var client1 = try Client.init(a, "k");
    defer client1.deinit();
    const h1 = try client1.getAuthHeader(a);
    defer a.free(h1.value);
    try std.testing.expectEqualStrings("x-api-key", h1.name);
    try std.testing.expectEqualStrings("k", h1.value);

    // OAuth path
    const creds = Credentials{
        .type = "oauth",
        .accessToken = "t",
        .refreshToken = "r",
        .expiresAt = 0,
    };
    var client2 = try Client.initWithOAuth(a, creds, null);
    defer client2.deinit();
    const h2 = try client2.getAuthHeader(a);
    defer a.free(h2.value);
    try std.testing.expectEqualStrings("Authorization", h2.name);
    try std.testing.expectEqualStrings("Bearer t", h2.value);
}

test "buildHeadersForTest includes beta for OAuth and no x-api-key" {
    const a = std.testing.allocator;
    // OAuth client
    const creds = Credentials{ .type = "oauth", .accessToken = "tok", .refreshToken = "ref", .expiresAt = 0 };
    var c = try Client.initWithOAuth(a, creds, null);
    defer c.deinit();
    const hdrs = try c.buildHeadersForTest(a, true);
    defer {
        // free duplicated header values
        for (hdrs) |h| a.free(h.value);
        a.free(hdrs);
    }
    var has_auth = false;
    var has_beta = false;
    var has_x_api = false;
    for (hdrs) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "authorization")) has_auth = true;
        if (std.ascii.eqlIgnoreCase(h.name, "anthropic-beta")) has_beta = true;
        if (std.ascii.eqlIgnoreCase(h.name, "x-api-key")) has_x_api = true;
    }
    try std.testing.expect(has_auth);
    try std.testing.expect(has_beta);
    try std.testing.expect(!has_x_api);
}

//! DEPRECATED: Monolithic Anthropic client (transitional)
//!
//! This file is kept temporarily for backwards compatibility during the
//! Phase 3 split. New code should import the split module via:
//!   `@import("shared/network/anthropic/mod.zig")`
//! and use `client.zig`, `models.zig`, `stream.zig`, and `oauth.zig` APIs.
//!
//! The implementation below remains functional but will be removed after the
//! deprecation window. Please migrate to the split modules.
//!
//! Minimal Anthropic HTTP streaming client for Zig 0.15.1.
//! Supports both API key and OAuth (Claude Pro/Max) authentication.

const std = @import("std");
const sse = @import("sse.zig");
const curl = @import("curl.zig");

pub const MessageRole = enum { system, user, assistant, tool };

pub const Message = struct {
    role: MessageRole,
    content: []const u8,
};

// OAuth configuration constants
pub const oauthClientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
pub const oauthAuthorizationUrl = "https://claude.ai/oauth/authorize";
pub const oauthTokenEndpoint = "https://console.anthropic.com/v1/oauth/token";
pub const oauthRedirectUri = "https://console.anthropic.com/oauth/code/callback";
pub const oauthScopes = "org:create_api_key user:profile user:inference";

// OAuth credentials stored to disk
pub const Credentials = struct {
    type: []const u8, // Always "oauth"
    accessToken: []const u8,
    refreshToken: []const u8,
    expiresAt: i64, // Unix timestamp

    /// Check if the token is expired
    pub fn isExpired(self: Credentials) bool {
        const now = std.time.timestamp();
        return now >= self.expiresAt;
    }

    /// Check if the token will expire within the specified leeway (in seconds)
    pub fn willExpireSoon(self: Credentials, leeway: i64) bool {
        const now = std.time.timestamp();
        return now + leeway >= self.expiresAt;
    }
};

// PKCE parameters for OAuth flow
pub const Pkce = struct {
    codeVerifier: []const u8,
    codeChallenge: []const u8,
    state: []const u8,

    /// Clean up allocated memory
    pub fn deinit(self: Pkce, allocator: std.mem.Allocator) void {
        allocator.free(self.codeVerifier);
        allocator.free(self.codeChallenge);
        allocator.free(self.state);
    }
};

/// Authentication methods supported
pub const AuthType = union(enum) {
    api_key: []const u8,
    oauth: Credentials,
};

/// OAuth provider configuration
pub const OAuthProvider = struct {
    client_id: []const u8,
    authorization_url: []const u8,
    token_url: []const u8,
    redirect_uri: []const u8,
    scopes: []const []const u8,

    pub fn buildAuthUrl(self: OAuthProvider, allocator: std.mem.Allocator, pkce_params: Pkce) ![]u8 {
        const scopes_joined = try std.mem.join(allocator, " ", self.scopes);
        defer allocator.free(scopes_joined);

        return try std.fmt.allocPrint(allocator, "{s}?client_id={s}&response_type=code&redirect_uri={s}&scope={s}&code_challenge={s}&code_challenge_method=S256&state={s}", .{ self.authorization_url, self.client_id, self.redirect_uri, scopes_joined, pkce_params.codeChallenge, pkce_params.state });
    }
};

/// Token refresh state to prevent concurrent refreshes
pub const RefreshLock = struct {
    mutex: std.Thread.Mutex,
    inProgress: bool,

    pub fn init() RefreshLock {
        return RefreshLock{
            .mutex = std.Thread.Mutex{},
            .inProgress = false,
        };
    }
};

/// Global refresh state for single-flight protection
var globalRefreshState = RefreshLock.init();

/// Global content collector for complete method (not thread-safe)
var globalContentCollector: std.ArrayList(u8) = undefined;
var globalAllocator: std.mem.Allocator = undefined;
var globalUsageInfo: Usage = undefined;

/// Model pricing information (rates per million tokens)
pub const ModelRates = struct {
    inputRate: f64, // Rate per million input tokens
    outputRate: f64, // Rate per million output tokens

    pub fn getInputCostPerToken(self: ModelRates) f64 {
        return self.inputRate / 1_000_000.0;
    }

    pub fn getOutputCostPerToken(self: ModelRates) f64 {
        return self.outputRate / 1_000_000.0;
    }
};

/// Anthropic API pricing table (updated as of August 2025)
const model_pricing = std.StaticStringMap(ModelRates).initComptime(.{
    // Current Models
    .{ "claude-opus-4-1-20250805", ModelRates{ .inputRate = 15.0, .outputRate = 75.0 } },
    .{ "claude-opus-4-1", ModelRates{ .inputRate = 15.0, .outputRate = 75.0 } }, // alias
    .{ "claude-opus-4-20250514", ModelRates{ .inputRate = 15.0, .outputRate = 75.0 } },
    .{ "claude-opus-4-0", ModelRates{ .inputRate = 15.0, .outputRate = 75.0 } }, // alias
    .{ "claude-sonnet-4-20250514", ModelRates{ .inputRate = 3.0, .outputRate = 15.0 } },
    .{ "claude-sonnet-4-0", ModelRates{ .inputRate = 3.0, .outputRate = 15.0 } }, // alias
    .{ "claude-3-7-sonnet-20250219", ModelRates{ .inputRate = 3.0, .outputRate = 15.0 } },
    .{ "claude-3-7-sonnet-latest", ModelRates{ .inputRate = 3.0, .outputRate = 15.0 } }, // alias
    .{ "claude-3-5-haiku-20241022", ModelRates{ .inputRate = 0.80, .outputRate = 4.0 } },
    .{ "claude-3-5-haiku-latest", ModelRates{ .inputRate = 0.80, .outputRate = 4.0 } }, // alias
    .{ "claude-3-haiku-20240307", ModelRates{ .inputRate = 0.25, .outputRate = 1.25 } },

    // Legacy/Deprecated Models
    .{ "claude-3-5-sonnet-20241022", ModelRates{ .inputRate = 3.0, .outputRate = 15.0 } }, // deprecated
    .{ "claude-3-5-sonnet-20240620", ModelRates{ .inputRate = 3.0, .outputRate = 15.0 } }, // deprecated
    .{ "claude-3-opus-20240229", ModelRates{ .inputRate = 15.0, .outputRate = 75.0 } }, // deprecated
});

/// Default pricing for unknown models (uses Sonnet 4 rates)
const default_pricing = ModelRates{ .inputRate = 3.0, .outputRate = 15.0 };

/// Cost calculation structure with Pro/Max override support
pub const CostCalculator = struct {
    isOauthSession: bool,

    pub fn init(isOauth: bool) CostCalculator {
        return CostCalculator{ .isOauthSession = isOauth };
    }

    /// Get model pricing information
    fn getModelPricing(model: []const u8) ModelRates {
        return model_pricing.get(model) orelse default_pricing;
    }

    /// Calculate cost for input tokens (returns 0 for OAuth Pro/Max sessions)
    pub fn calculateInputCost(self: CostCalculator, tokens: u32, model: []const u8) f64 {
        if (self.isOauthSession) return 0.0;

        const pricing = getModelPricing(model);
        return @as(f64, @floatFromInt(tokens)) * pricing.getInputCostPerToken();
    }

    /// Calculate cost for output tokens (returns 0 for OAuth Pro/Max sessions)
    pub fn calculateOutputCost(self: CostCalculator, tokens: u32, model: []const u8) f64 {
        if (self.isOauthSession) return 0.0;

        const pricing = getModelPricing(model);
        return @as(f64, @floatFromInt(tokens)) * pricing.getOutputCostPerToken();
    }

    /// Get pricing display mode
    pub fn getPricingMode(self: CostCalculator) []const u8 {
        return if (self.isOauthSession) "Subscription (Free)" else "Pay-per-use";
    }

    /// Get model pricing information for display
    pub fn getModelRates(self: CostCalculator, model: []const u8) ModelRates {
        _ = self; // Cost calculator itself doesn't affect pricing rates
        return getModelPricing(model);
    }
};

/// Error set for client operations.
pub const Error = error{ MissingAPIKey, APIError, AuthError, TokenExpired, OutOfMemory, InvalidFormat, InvalidPort, UnexpectedCharacter, InvalidGrant, NetworkError, RefreshInProgress, ChunkParseError, MalformedChunk, InvalidChunkSize, PayloadTooLarge, StreamingFailed, BufferOverflow, ChunkProcessingFailed,
    // OAuth and network related errors
    WriteFailed, ReadFailed, EndOfStream, ConnectionResetByPeer, ConnectionTimedOut, NetworkUnreachable, ConnectionRefused, TemporaryNameServerFailure, NameServerFailure, UnknownHostName, HostLacksNetworkAddresses, UnexpectedConnectFailure, TlsInitializationFailed, UnsupportedURIScheme, URIMissingHost, URIHostTooLong, CertificateBundleLoadFailure,
    // HTTP protocol errors
    HTTPChunkInvalid, HTTPChunkTruncated, HTTPHeadersOversize, HTTPRequestTruncated, HTTPConnectionClosing, HTTPHeadersInvalid, TooManyHttpRedirects, RedirectRequiresResend, HTTPRedirectLocationMissing, HTTPRedirectLocationOversize, HTTPRedirectLocationInvalid, HTTPContentEncodingUnsupported,
    // Buffer errors
    NoSpaceLeft, StreamTooLong };

pub const Stream = struct {
    model: []const u8,
    maxTokens: usize = 256,
    temperature: f32 = 0.7,
    messages: []const Message,
    /// Callback invoked for every token / delta chunk.
    /// The slice is only valid until the next invocation.
    onToken: *const fn ([]const u8) void,
};

/// Response structure for non-streaming completion
pub const CompletionResult = struct {
    content: []const u8,
    usage: Usage,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CompletionResult, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // Content is owned by the collector, which will be freed separately
    }
};

pub const Usage = struct {
    inputTokens: u32 = 0,
    outputTokens: u32 = 0,
};

/// Parameters for non-streaming completion
pub const Complete = struct {
    model: []const u8,
    maxTokens: usize = 256,
    temperature: f32 = 0.7,
    messages: []const Message,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    auth: AuthType,
    credentialsPath: ?[]const u8, // Path to store OAuth credentials

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) Error!Client {
        if (api_key.len == 0) return Error.MissingAPIKey;
        return Client{
            .allocator = allocator,
            .auth = AuthType{ .api_key = api_key },
            .credentialsPath = null,
        };
    }

    pub fn initWithOAuth(allocator: std.mem.Allocator, oauth_creds: Credentials, credentials_path: []const u8) Error!Client {
        return Client{
            .allocator = allocator,
            .auth = AuthType{ .oauth = oauth_creds },
            .credentialsPath = try allocator.dupe(u8, credentials_path),
        };
    }

    pub fn deinit(self: *Client) void {
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
    pub fn isOAuthSession(self: Client) bool {
        return switch (self.auth) {
            .oauth => true,
            .api_key => false,
        };
    }

    /// Refresh OAuth tokens if needed and update client auth with single-flight protection
    pub fn refreshOAuthIfNeeded(self: *Client) Error!void {
        switch (self.auth) {
            .api_key => return, // No refresh needed for API key
            .oauth => |oauth_creds| {
                // Check if refresh is needed (5 minute leeway)
                if (!oauth_creds.willExpireSoon(300)) return;

                // Single-flight protection
                globalRefreshState.mutex.lock();
                defer globalRefreshState.mutex.unlock();

                // Check again in case another thread refreshed while we waited
                if (!oauth_creds.willExpireSoon(300)) return;

                if (globalRefreshState.inProgress) {
                    return Error.RefreshInProgress;
                }

                globalRefreshState.inProgress = true;
                defer globalRefreshState.inProgress = false;

                // Perform the refresh
                const new_creds = refreshTokens(self.allocator, oauth_creds.refreshToken) catch |err| {
                    std.log.err("Token refresh failed: {}", .{err});
                    return err;
                };

                // Free old credentials
                self.allocator.free(oauth_creds.type);
                self.allocator.free(oauth_creds.accessToken);
                self.allocator.free(oauth_creds.refreshToken);

                // Update with new credentials
                self.auth = AuthType{ .oauth = new_creds };

                // Persist updated credentials
                if (self.credentialsPath) |path| {
                    saveOAuthCredentials(self.allocator, path, new_creds) catch |err| {
                        std.log.warn("Failed to save refreshed credentials: {}", .{err});
                    };
                }
            },
        }
    }

    /// Streams completion via Server-Sent Events, invoking callback per data chunk.
    pub fn stream(self: *Client, params: Stream) Error!void {
        return self.streamWithRetry(params, false);
    }

    /// Complete method for non-streaming requests (collects streaming response)
    pub fn complete(self: *Client, params: Complete) !CompletionResult {
        // Set up global collector (not thread-safe, but ok for single-threaded use)
        globalAllocator = self.allocator;
        globalContentCollector = std.ArrayList(u8){};
        defer globalContentCollector.deinit(self.allocator);
        globalUsageInfo = Usage{ .inputTokens = 0, .outputTokens = 0 };

        // Create stream params with our collector callback
        const streamParams = Stream{
            .model = params.model,
            .maxTokens = params.maxTokens,
            .temperature = params.temperature,
            .messages = params.messages,
            .onToken = struct {
                fn callback(data: []const u8) void {
                    // Try to parse as JSON to extract usage and content
                    const DeltaMessage = struct {
                        delta: ?struct {
                            text: ?[]const u8,
                        },
                        usage: ?struct {
                            input_tokens: u32,
                            output_tokens: u32,
                        },
                        type: ?[]const u8,
                    };

                    const parsed = std.json.parseFromSlice(DeltaMessage, globalAllocator, data, .{}) catch {
                        // If not valid JSON, treat as raw text content
                        globalContentCollector.appendSlice(globalAllocator, data) catch return;
                        return;
                    };
                    defer parsed.deinit();

                    // Extract content from delta if present
                    if (parsed.value.delta) |delta| {
                        if (delta.text) |text| {
                            globalContentCollector.appendSlice(globalAllocator, text) catch return;
                        }
                    }

                    // Extract usage if present
                    if (parsed.value.usage) |usage| {
                        globalUsageInfo.inputTokens = usage.input_tokens;
                        globalUsageInfo.outputTokens = usage.output_tokens;
                    }
                }
            }.callback,
        };

        try self.stream(streamParams);

        // Create owned content copy
        const ownedContent = try self.allocator.dupe(u8, globalContentCollector.items);

        return CompletionResult{
            .content = ownedContent,
            .usage = globalUsageInfo,
            .allocator = self.allocator,
        };
    }

    /// Internal method to handle streaming with automatic retry on 401
    fn streamWithRetry(self: *Client, params: Stream, isRetry: bool) Error!void {
        // Refresh OAuth tokens if needed (unless this is already a retry)
        if (!isRetry) {
            try self.refreshOAuthIfNeeded();
        }

        // Build request body
        const bodyJson = try buildBodyJson(self.allocator, params);
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
                .{ .name = "anthropic-version", .value = "2023-06-01" },
                .{ .name = "user-agent", .value = "docz/1.0 (libcurl)" },
            },
            .oauth => |creds| blk: {
                authHeaderValue = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{creds.accessToken});
                break :blk [_]curl.Header{
                    .{ .name = "authorization", .value = authHeaderValue.? },
                    .{ .name = "accept", .value = "text/event-stream" },
                    .{ .name = "content-type", .value = "application/json" },
                    .{ .name = "anthropic-version", .value = "2023-06-01" },
                    .{ .name = "user-agent", .value = "docz/1.0 (libcurl)" },
                };
            },
        };

        // Create streaming context
        const Streaming = struct {
            allocator: std.mem.Allocator,
            callback: *const fn ([]const u8) void,
            buffer: std.ArrayListUnmanaged(u8),

            pub fn init(alloc: std.mem.Allocator, cb: *const fn ([]const u8) void) @This() {
                return @This(){
                    .allocator = alloc,
                    .callback = cb,
                    .buffer = std.ArrayListUnmanaged(u8){},
                };
            }

            pub fn deinit(ctx: *@This()) void {
                ctx.buffer.deinit(ctx.allocator);
            }
        };

        var streamContext = Streaming.init(self.allocator, params.onToken);
        defer streamContext.deinit();

        const req = curl.HTTPRequest{
            .method = .POST,
            .url = "https://api.anthropic.com/v1/messages",
            .headers = &headers,
            .body = bodyJson,
            .timeout_ms = 120000, // 2 minute timeout for streaming
            .verify_ssl = true,
            .follow_redirects = false,
            .verbose = false,
        };

        // Perform streaming request
        const statusCode = client.streamRequest(
            req,
            processStreamChunk,
            &streamContext,
        ) catch |err| {
            std.log.err("Streaming request failed: {}", .{err});
            switch (err) {
                curl.HTTPError.NetworkError => return Error.NetworkError,
                curl.HTTPError.TlsError => return Error.NetworkError,
                curl.HTTPError.Timeout => return Error.NetworkError,
                else => return Error.APIError,
            }
        };

        // Check for 401 Unauthorized and retry if needed
        if (statusCode == 401 and !isRetry) {
            std.log.warn("Received 401 Unauthorized, attempting token refresh...", .{});
            return self.streamWithRetry(params, true); // Retry once after refresh
        }

        if (statusCode != 200) {
            std.log.err("HTTP error: {}", .{statusCode});
            return Error.APIError;
        }

        // Process any remaining buffered data
        if (streamContext.buffer.items.len > 0) {
            processSseChunk(&streamContext, &.{}) catch |err| {
                std.log.warn("Error processing final streaming data: {}", .{err});
            };
        }
    }
};

fn buildBodyJson(allocator: std.mem.Allocator, params: Stream) ![]u8 {
    var buffer = std.array_list.Managed(u8).init(allocator);
    defer buffer.deinit();

    const writer = buffer.writer();

    // Manual JSON construction for Zig 0.15.1 compatibility
    try std.fmt.format(writer, "{{", .{});
    try std.fmt.format(writer, "\"model\":\"{s}\",", .{params.model});
    try std.fmt.format(writer, "\"max_tokens\":{},", .{params.maxTokens});
    try std.fmt.format(writer, "\"temperature\":{d},", .{params.temperature});
    try std.fmt.format(writer, "\"stream\":true,", .{});
    try std.fmt.format(writer, "\"messages\":[", .{});

    for (params.messages, 0..) |message, i| {
        if (i > 0) try std.fmt.format(writer, ",", .{});
        try std.fmt.format(writer, "{{\"role\":\"{s}\",\"content\":\"{s}\"}}", .{ @tagName(message.role), message.content });
    }

    try std.fmt.format(writer, "]}}", .{});

    return buffer.toOwnedSlice();
}

/// Callback function for processing streaming chunks from libcurl
fn processStreamChunk(chunk: []const u8, context: *anyopaque) void {
    const Streaming = struct {
        allocator: std.mem.Allocator,
        callback: *const fn ([]const u8) void,
        buffer: std.ArrayListUnmanaged(u8),

        pub fn init(alloc: std.mem.Allocator, cb: *const fn ([]const u8) void) @This() {
            return @This(){
                .allocator = alloc,
                .callback = cb,
                .buffer = std.ArrayListUnmanaged(u8){},
            };
        }

        pub fn deinit(ctx: *@This()) void {
            ctx.buffer.deinit(ctx.allocator);
        }
    };

    const streamContext: *Streaming = @ptrCast(@alignCast(context));

    // Process chunk for SSE events
    processSseChunk(streamContext, chunk) catch |err| {
        std.log.warn("Error processing stream chunk: {}", .{err});
    };
}

/// Process individual SSE chunk and extract events
fn processSseChunk(streamContext: anytype, chunk: []const u8) !void {
    // Add chunk to buffer
    try streamContext.buffer.appendSlice(streamContext.allocator, chunk);

    // Process complete SSE events (separated by double newlines)
    while (std.mem.indexOf(u8, streamContext.buffer.items, "\n\n")) |endPos| {
        const eventData = streamContext.buffer.items[0..endPos];

        // Extract SSE data field content
        var lines = std.mem.splitSequence(u8, eventData, "\n");
        while (lines.next()) |line| {
            const trimmedLine = std.mem.trim(u8, line, " \t\r");
            if (std.mem.startsWith(u8, trimmedLine, "data: ")) {
                const dataContent = trimmedLine[6..]; // Skip "data: "
                if (dataContent.len > 0 and !std.mem.eql(u8, dataContent, "[DONE]")) {
                    // Call the user callback with the SSE data
                    streamContext.callback(dataContent);
                }
            }
        }

        // Remove processed event from buffer
        const remaining = streamContext.buffer.items[endPos + 2 ..];
        std.mem.copyForwards(u8, streamContext.buffer.items[0..remaining.len], remaining);
        streamContext.buffer.shrinkRetainingCapacity(remaining.len);
    }
}

/// Check if response uses chunked transfer encoding
/// Note: In Zig 0.15.1, std.http.Client handles chunked encoding transparently
/// This function serves as a placeholder for future header inspection
fn isChunkedEncoding(response_head: anytype) bool {
    _ = response_head;
    // For now, assume non-chunked as std.http.Client handles chunked encoding internally
    // This allows us to keep the processing logic for future use
    return false;
}

/// Chunk processing state for incremental parsing
const Chunk = struct {
    size: usize = 0,
    bytes_read: usize = 0,
    reading_size: bool = true,
    trailers_started: bool = false,
    extensions: ?[]const u8 = null,

    pub fn reset(self: *Chunk) void {
        self.size = 0;
        self.bytes_read = 0;
        self.reading_size = true;
        self.trailers_started = false;
        self.extensions = null;
    }
};

/// Configuration for large payload processing
const LargePayload = struct {
    largeChunkThreshold: usize = 1024 * 1024, // 1MB threshold for large chunk processing
    streamingBufferSize: usize = 64 * 1024, // 64KB buffer for streaming large chunks
    maxAccumulatedSize: usize = 16 * 1024 * 1024, // 16MB max accumulated data before streaming
    progressReportingInterval: usize = 1024 * 1024, // Report progress every 1MB
    adaptiveBufferMin: usize = 8 * 1024, // Minimum adaptive buffer size: 8KB
    adaptiveBufferMax: usize = 512 * 1024, // Maximum adaptive buffer size: 512KB
};

/// Process chunked Server-Sent Events with large payload optimization and streaming processing
fn processChunkedStreamingResponse(allocator: std.mem.Allocator, reader: *std.Io.Reader, callback: *const fn ([]const u8) void) !void {
    var event_data = std.array_list.Managed(u8).init(allocator);
    defer event_data.deinit();

    var chunk_state = Chunk{};
    var chunk_buffer = std.array_list.Managed(u8).init(allocator);
    defer chunk_buffer.deinit();

    const config = LargePayload{};

    // Use adaptive initial capacity based on expected large payload handling
    try event_data.ensureTotalCapacity(16384); // 16KB initial capacity
    try chunk_buffer.ensureTotalCapacity(config.adaptive_buffer_min);

    var recoveryAttempts: u8 = 0;
    const maxRecoveryAttempts = 3;
    var totalBytesProcessed: usize = 0;
    var largeChunksProcessed: u32 = 0;

    while (true) {
        if (chunk_state.reading_size) {
            // Read chunk size line (hex format with optional extensions)
            const size_line_result = reader.*.takeDelimiterExclusive('\n') catch |err| switch (err) {
                error.EndOfStream => {
                    // Send final event if any data remains
                    if (event_data.items.len > 0) {
                        callback(event_data.items);
                    }
                    std.log.debug("Chunked processing complete: {} bytes total, {} large chunks", .{ totalBytesProcessed, largeChunksProcessed });
                    return; // Normal end of stream
                },
                error.StreamTooLong => {
                    std.log.warn("Chunked response contains size line too long for buffer, attempting graceful recovery", .{});
                    recoveryAttempts += 1;
                    if (recoveryAttempts >= maxRecoveryAttempts) {
                        std.log.err("Too many recovery attempts, falling back to non-chunked processing", .{});
                        // Fallback: try to process remaining data as regular SSE stream
                        return processStreamingResponse(allocator, reader, callback) catch Error.MalformedChunk;
                    }
                    chunk_state.reset();
                    continue; // Try again
                },
                else => return err,
            };

            const size_line = if (size_line_result) |l| std.mem.trim(u8, l, " \t\r\n") else return; // Handle EOF

            // Skip empty lines that might occur in malformed streams
            if (size_line.len == 0) {
                continue;
            }

            // Parse chunk size (hex) with optional chunk extensions and error recovery
            const chunkInfo = parseChunkSize(size_line) catch |err| {
                std.log.warn("Failed to parse chunk size '{s}': {}, attempting recovery", .{ size_line, err });
                recoveryAttempts += 1;
                if (recoveryAttempts >= maxRecoveryAttempts) {
                    std.log.err("Too many chunk parse errors, falling back to non-chunked processing", .{});
                    return processStreamingResponse(allocator, reader, callback) catch Error.ChunkParseError;
                }
                chunk_state.reset();
                continue;
            };

            chunk_state.size = chunkInfo.size;
            chunk_state.extensions = chunkInfo.extensions;
            recoveryAttempts = 0; // Reset on successful parse

            // Logging for large chunk detection
            if (chunk_state.size >= config.largeChunkThreshold) {
                std.log.info("Processing large chunk: {} bytes (using streaming mode)", .{chunk_state.size});
                largeChunksProcessed += 1;
            } else if (chunk_state.size > 64 * 1024) {
                std.log.debug("Processing medium chunk: {} bytes", .{chunk_state.size});
            }

            if (chunk_state.size == 0) {
                // Zero-sized chunk indicates end of chunked data
                // Process any remaining trailers, then finish
                processChunkTrailers(reader) catch |err| {
                    std.log.warn("Error processing chunk trailers: {}, continuing anyway", .{err});
                };
                if (event_data.items.len > 0) {
                    callback(event_data.items);
                }
                std.log.debug("Chunked processing complete: {} bytes total, {} large chunks", .{ totalBytesProcessed, largeChunksProcessed });
                return;
            }

            chunk_state.reading_size = false;
            chunk_state.bytes_read = 0;
            chunk_buffer.clearRetainingCapacity();

            // Adaptive buffer sizing based on chunk size for memory efficiency
            const optimal_buffer_size = if (chunk_state.size >= config.large_chunk_threshold)
                @min(config.adaptive_buffer_max, @max(config.adaptive_buffer_min, chunk_state.size / 8))
            else
                config.adaptive_buffer_min;

            try chunk_buffer.ensureTotalCapacity(optimal_buffer_size);
        } else {
            // Enhanced chunk data reading with streaming processing for large payloads
            const remaining = chunk_state.size - chunk_state.bytes_read;
            if (remaining == 0) {
                // Chunk complete, process accumulated data as SSE lines
                processSSELines(chunk_buffer.items, &event_data, callback) catch |err| {
                    std.log.warn("Error processing SSE lines in chunk: {}, continuing", .{err});
                };

                // Skip trailing CRLF after chunk data with graceful handling
                if (reader.*.takeDelimiterExclusive('\n')) |_| {
                    // Successfully skipped CRLF
                } else |err| switch (err) {
                    error.EndOfStream => return,
                    error.StreamTooLong => {
                        std.log.warn("Malformed chunk trailing CRLF, continuing gracefully", .{});
                    },
                    else => {
                        std.log.warn("Error reading chunk trailer CRLF: {}, continuing", .{err});
                    },
                }

                _ = chunk_state.size; // Track processed bytes for debugging
                chunk_state.reset();
                continue;
            }

            // Enhanced adaptive read sizing for large payloads
            const is_large_chunk = chunk_state.size >= config.large_chunk_threshold;
            const adaptive_read_size = if (is_large_chunk)
                @min(remaining, config.streaming_buffer_size) // Use larger buffer for large chunks
            else
                @min(remaining, 4096); // Use smaller buffer for normal chunks

            // Adaptive temporary buffer allocation for large chunk processing
            var large_temp_buffer: [512 * 1024]u8 = undefined; // 512KB buffer for large chunks
            var normal_temp_buffer: [4096]u8 = undefined; // 4KB buffer for normal chunks

            const temp_buffer = if (is_large_chunk and adaptive_read_size > normal_temp_buffer.len)
                large_temp_buffer[0..adaptive_read_size]
            else
                normal_temp_buffer[0..adaptive_read_size];

            const bytes_read = reader.readUpTo(temp_buffer) catch |err| switch (err) {
                error.EndOfStream => {
                    std.log.warn("Unexpected end of stream in chunk data, processing partial data", .{});
                    // Graceful degradation: process what we have so far
                    if (chunk_buffer.items.len > 0) {
                        processSSELines(chunk_buffer.items, &event_data, callback) catch {};
                    }
                    if (event_data.items.len > 0) {
                        callback(event_data.items);
                    }
                    return;
                },
                else => {
                    std.log.warn("Error reading chunk data: {}, attempting recovery", .{err});
                    _ = err; // Track recovery attempts for debugging
                    // Process any accumulated data before retry
                    if (chunk_buffer.items.len > 0) {
                        processSSELines(chunk_buffer.items, &event_data, callback) catch {};
                    }
                    if (event_data.items.len > 0) {
                        callback(event_data.items);
                    }
                    chunk_state.reset();
                    continue;
                },
            };

            if (bytes_read == 0) {
                std.log.warn("No bytes read in chunk processing, attempting to continue", .{});
                // Process any accumulated data if we hit zero bytes
                if (chunk_buffer.items.len > 0) {
                    processSSELines(chunk_buffer.items, &event_data, callback) catch {};
                }
                if (event_data.items.len > 0) {
                    callback(event_data.items);
                }
                continue;
            }

            // Enhanced memory management: streaming processing for very large chunks
            if (is_large_chunk and chunk_buffer.items.len + bytes_read > config.max_accumulated_size) {
                // Process accumulated data before adding more to prevent excessive memory usage
                std.log.debug("Triggering streaming processing to prevent memory overflow (current: {}, adding: {})", .{ chunk_buffer.items.len, bytes_read });
                if (chunk_buffer.items.len > 0) {
                    processSSELines(chunk_buffer.items, &event_data, callback) catch |err| {
                        std.log.warn("Error in streaming SSE processing: {}, continuing", .{err});
                    };
                    chunk_buffer.clearRetainingCapacity();
                }
            }

            // Accumulate chunk data with capacity management
            try chunk_buffer.ensureUnusedCapacity(bytes_read);
            try chunk_buffer.appendSlice(temp_buffer[0..bytes_read]);
            chunk_state.bytes_read += bytes_read;
            // Reset on successful read - continue processing

            // Enhanced progress reporting for large chunks
            if (is_large_chunk and chunk_state.bytes_read > 0 and
                chunk_state.bytes_read % config.progress_reporting_interval == 0)
            {
                const progress_percent = (@as(f64, @floatFromInt(chunk_state.bytes_read)) /
                    @as(f64, @floatFromInt(chunk_state.size))) * 100.0;
                std.log.info("Large chunk progress: {d:.1}% ({} / {} bytes)", .{ progress_percent, chunk_state.bytes_read, chunk_state.size });
            }
        }
    }
}

/// Chunk size validation thresholds for large payload processing
const ChunkSizeValidation = struct {
    maxChunkSize: usize = 512 * 1024 * 1024, // 512MB absolute maximum per chunk
    largeChunkThreshold: usize = 1024 * 1024, // 1MB threshold for special handling
    warningThreshold: usize = 64 * 1024 * 1024, // 64MB threshold for warnings
    streamingThreshold: usize = 16 * 1024 * 1024, // 16MB threshold for mandatory streaming
};

/// Parse chunk size and extensions from chunk size line with large payload support
fn parseChunkSize(size_line: []const u8) !struct { size: usize, extensions: ?[]const u8 } {
    const validation = ChunkSizeValidation{};

    // Find semicolon separator for chunk extensions
    const semicolon_pos = std.mem.indexOf(u8, size_line, ";");
    const size_str = if (semicolon_pos) |pos| size_line[0..pos] else size_line;
    const extensions = if (semicolon_pos) |pos| size_line[pos + 1 ..] else null;

    // Size string validation before parsing
    if (size_str.len == 0) {
        std.log.warn("Empty chunk size string", .{});
        return Error.ChunkParseError;
    }

    // Validate hex string format and reasonable length (prevent DoS)
    if (size_str.len > 16) { // More than 16 hex digits would be > 64-bit integer
        std.log.warn("Chunk size string too long: {} characters", .{size_str.len});
        return Error.InvalidChunkSize;
    }

    // Parse hex chunk size with error handling
    const size = std.fmt.parseInt(usize, size_str, 16) catch |err| switch (err) {
        error.Overflow => {
            std.log.warn("Chunk size overflow when parsing: '{s}'", .{size_str});
            return Error.InvalidChunkSize;
        },
        error.InvalidCharacter => {
            std.log.warn("Invalid hex character in chunk size: '{s}'", .{size_str});
            return Error.ChunkParseError;
        },
    };

    // Chunk size validation with multiple thresholds
    if (size > validation.maxChunkSize) {
        std.log.err("Chunk size {} exceeds absolute maximum allowed size ({})", .{ size, validation.maxChunkSize });
        return Error.PayloadTooLarge;
    }

    // Warning thresholds for large payload awareness
    if (size >= validation.warningThreshold) {
        std.log.warn("Very large chunk detected: {} bytes ({}MB) - processing enabled", .{ size, size / (1024 * 1024) });
    } else if (size >= validation.streamingThreshold) {
        std.log.info("Large chunk detected: {} bytes ({}MB) - streaming processing enabled", .{ size, size / (1024 * 1024) });
    } else if (size >= validation.largeChunkThreshold) {
        std.log.debug("Medium chunk detected: {} bytes ({}KB)", .{ size, size / 1024 });
    }

    // Log chunk extensions if present for debugging large payload scenarios
    if (extensions) |ext| {
        std.log.debug("Chunk extensions present: '{s}'", .{ext});
    }

    return .{ .size = size, .extensions = extensions };
}

/// Process chunk trailers (headers after final chunk)
fn processChunkTrailers(reader: *std.Io.Reader) !void {
    while (true) {
        const trailer_line = reader.*.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => return,
            error.StreamTooLong => {
                std.log.warn("Chunk trailer line too long, skipping", .{});
                continue;
            },
            else => return err,
        };

        const line = if (trailer_line) |l| std.mem.trim(u8, l, " \t\r\n") else return; // Handle EOF
        if (line.len == 0) {
            // Empty line indicates end of trailers
            return;
        }

        // Log trailer headers for debugging (could be used for metadata)
        if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
            const header_name = std.mem.trim(u8, line[0..colon_pos], " \t");
            const header_value = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");
            std.log.debug("Chunk trailer: {s}: {s}", .{ header_name, header_value });
        }
    }
}

/// Process accumulated chunk data as Server-Sent Event lines with large payload handling
fn processSSELines(chunk_data: []const u8, event_data: *std.array_list.Managed(u8), callback: *const fn ([]const u8) void) !void {
    const sse_config = sse.ServerSentEventConfig{};
    var line_iter = std.mem.splitSequence(u8, chunk_data, "\n");
    var lines_processed: usize = 0;
    var total_data_processed: usize = 0;

    while (line_iter.next()) |line_data| {
        const line = std.mem.trim(u8, line_data, " \t\r\n");
        lines_processed += 1;

        if (line.len == 0) {
            // Empty line indicates end of SSE event
            if (event_data.items.len > 0) {
                // Event size validation for large payloads
                if (event_data.items.len >= sse_config.large_event_threshold) {
                    std.log.debug("Processing large SSE event: {} bytes", .{event_data.items.len});
                }

                if (event_data.items.len > sse_config.max_event_size) {
                    std.log.warn("SSE event exceeds maximum size ({} > {}), truncating", .{ event_data.items.len, sse_config.max_event_size });
                    // Truncate to maximum size to prevent memory issues
                    const truncated_event = event_data.items[0..sse_config.max_event_size];
                    callback(truncated_event);
                } else {
                    callback(event_data.items);
                }

                total_data_processed += event_data.items.len;
                event_data.clearRetainingCapacity();
            }
        } else if (std.mem.startsWith(u8, line, "data: ")) {
            // Parse SSE data field with capacity management for large payloads
            const data_content = line[6..]; // Skip "data: "

            // Validation for extremely large data lines
            if (data_content.len > sse_config.max_event_size / 2) { // More than half max event size per line
                std.log.warn("Very large SSE data line: {} bytes - consider streaming optimization", .{data_content.len});
            }

            if (event_data.items.len > 0) {
                try event_data.append('\n'); // Multi-line data separator
            }

            // Capacity management with overflow protection
            const required_capacity = event_data.items.len + data_content.len;
            if (required_capacity > sse_config.max_event_size) {
                std.log.warn("SSE event would exceed maximum size, triggering early callback", .{});
                // Trigger callback with current data before adding more
                if (event_data.items.len > 0) {
                    callback(event_data.items);
                    event_data.clearRetainingCapacity();
                }
            }

            // Ensure we have capacity for the new data to handle large payloads
            try event_data.ensureUnusedCapacity(data_content.len);
            try event_data.appendSlice(data_content);

            // Streaming: trigger callback for very large events before completion
            if (event_data.items.len >= sse_config.streaming_callback_threshold) {
                std.log.debug("Large SSE event streaming: triggering early callback for {} bytes", .{event_data.items.len});
                callback(event_data.items);
                event_data.clearRetainingCapacity();
            }
        } else if (std.mem.startsWith(u8, line, "event: ") or
            std.mem.startsWith(u8, line, "id: ") or
            std.mem.startsWith(u8, line, "retry: "))
        {
            // Logging for other SSE fields in large payload scenarios
            if (chunk_data.len >= sse_config.large_event_threshold) {
                std.log.debug("SSE field in large payload: {s}", .{line[0..@min(line.len, 50)]});
            }
        }

        // Periodic progress reporting for very large chunk processing
        if (lines_processed % sse_config.line_processing_batch_size == 0 and
            chunk_data.len >= sse_config.large_event_threshold)
        {
            std.log.debug("SSE line processing progress: {} lines, {} bytes total", .{ lines_processed, total_data_processed });
        }
    }

    // Final logging for large payload processing
    if (chunk_data.len >= sse_config.large_event_threshold) {
        std.log.debug("SSE processing complete: {} lines, {} bytes processed", .{ lines_processed, total_data_processed });
    }
}

/// Process Server-Sent Events using Io.Reader with comprehensive event field handling and error recovery
fn processStreamingResponse(allocator: std.mem.Allocator, reader: *std.Io.Reader, callback: *const fn ([]const u8) void) !void {
    const sse_config = sse.SSEProcessing{};
    var event_state = sse.SSEEventBuilder.init(allocator);
    defer event_state.deinit();

    var lines_processed: usize = 0;
    var events_processed: usize = 0;
    var bytes_processed: usize = 0;
    var malformed_lines: usize = 0;
    var partial_line_buffer = std.array_list.Managed(u8).init(allocator);
    defer partial_line_buffer.deinit();

    // Use larger initial capacity for potentially large events
    try event_state.data_buffer.ensureTotalCapacity(4096);

    std.log.debug("SSE processing started with comprehensive field support", .{});

    while (true) {
        // Line reading with partial line accumulation for large events
        const line_result = reader.*.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => {
                // Process any remaining partial line
                if (partial_line_buffer.items.len > 0) {
                    std.log.debug("Processing final partial line: {} bytes", .{partial_line_buffer.items.len});
                    processSSELine(partial_line_buffer.items, &event_state, &sse_config) catch |line_err| {
                        std.log.warn("Error processing final partial line: {}", .{line_err});
                        malformed_lines += 1;
                    };
                }

                // Send final event if any data remains
                if (event_state.has_data) {
                    callback(event_state.data_buffer.items);
                    events_processed += 1;
                }

                std.log.debug("SSE processing complete: {} lines, {} events, {} bytes, {} malformed", .{ lines_processed, events_processed, bytes_processed, malformed_lines });
                return; // Normal end of stream
            },
            error.StreamTooLong => {
                std.log.warn("SSE line exceeds buffer capacity, attempting partial line handling", .{});
                // For very large lines, we could implement partial line accumulation
                // However, given current API constraints, we'll log and continue gracefully
                if (partial_line_buffer.items.len > 0) {
                    std.log.debug("Processing accumulated partial line due to StreamTooLong: {} bytes", .{partial_line_buffer.items.len});
                    processSSELine(partial_line_buffer.items, &event_state, &sse_config) catch |line_err| {
                        std.log.warn("Error processing partial line after StreamTooLong: {}", .{line_err});
                        malformed_lines += 1;
                    };
                    partial_line_buffer.clearRetainingCapacity();
                }
                malformed_lines += 1;
                continue; // Skip this oversized line and continue
            },
            else => {
                std.log.warn("Error reading SSE line: {}, attempting to continue", .{err});
                return err;
            },
        };

        const line = std.mem.trim(u8, line_result, " \t\r\n");
        lines_processed += 1;
        bytes_processed += line.len;

        // Empty line handling with event dispatch
        if (line.len == 0) {
            // Empty line indicates end of SSE event - dispatch complete event
            if (event_state.has_data) {
                // Event size validation
                if (event_state.data_buffer.items.len >= sse_config.large_event_threshold) {
                    std.log.debug("Dispatching large SSE event: {} bytes, type: {s}, id: {s}", .{ event_state.data_buffer.items.len, event_state.event_type orelse "default", event_state.event_id orelse "none" });
                }

                if (event_state.data_buffer.items.len > sse_config.max_event_size) {
                    std.log.warn("SSE event exceeds maximum size ({} > {}), truncating for safety", .{ event_state.data_buffer.items.len, sse_config.max_event_size });
                    // Truncate to maximum size to prevent memory issues
                    const truncated_event = event_state.data_buffer.items[0..sse_config.max_event_size];
                    callback(truncated_event);
                } else {
                    callback(event_state.data_buffer.items);
                }

                events_processed += 1;
                event_state.reset(); // Prepare for next event
            }
        } else {
            // Process SSE field line with comprehensive field support
            processSSELine(line, &event_state, &sse_config) catch |line_err| {
                std.log.warn("Error processing SSE line '{s}': {}, continuing", .{ line[0..@min(line.len, 50)], line_err });
                malformed_lines += 1;
                // Continue processing despite malformed line
            };

            // Early callback for very large events to prevent memory buildup
            if (event_state.data_buffer.items.len >= sse_config.streaming_callback_threshold) {
                std.log.debug("Triggering early callback for large SSE event: {} bytes", .{event_state.data_buffer.items.len});
                callback(event_state.data_buffer.items);
                events_processed += 1;
                event_state.reset(); // Reset state after early dispatch
            }
        }

        // Periodic progress reporting for large event streams
        if (lines_processed % 1000 == 0 and bytes_processed >= sse_config.large_event_threshold) {
            std.log.debug("SSE processing progress: {} lines, {} events, {d:.1}MB processed", .{ lines_processed, events_processed, @as(f64, @floatFromInt(bytes_processed)) / (1024.0 * 1024.0) });
        }
    }
}

/// Process individual SSE line with comprehensive field support and validation
fn processSSELine(line: []const u8, event_state: *sse.SSEEventBuilder, sse_config: *const sse.ServerSentEventConfig) !void {
    _ = try sse.processServerSentEventLine(line, event_state, sse_config);
}

/// Exchange authorization code for tokens
pub fn exchangeCodeForTokens(allocator: std.mem.Allocator, authorization_code: []const u8, pkce_params: Pkce) !Credentials {
    std.log.info("🔄 Exchanging authorization code for OAuth tokens...", .{});

    var client = curl.HTTPClient.init(allocator) catch |err| {
        std.log.err("Failed to initialize HTTP client: {}", .{err});
        return Error.NetworkError;
    };
    defer client.deinit();

    // Split the authorization code if it contains a fragment (like OpenCode does)
    var code_parts = std.mem.splitSequence(u8, authorization_code, "#");
    const code = code_parts.next() orelse authorization_code;
    const state = code_parts.next() orelse "";

    // Build the JSON request body (matching OpenCode's format)
    const body = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "code": "{s}",
        \\  "state": "{s}",
        \\  "grant_type": "authorization_code",
        \\  "client_id": "{s}",
        \\  "redirect_uri": "{s}",
        \\  "code_verifier": "{s}"
        \\}}
    , .{ code, state, oauthClientId, oauthRedirectUri, pkce_params.codeVerifier });
    defer allocator.free(body);

    std.log.debug("Sending OAuth token request with JSON body: {s}", .{body});

    const headers = [_]curl.Header{
        .{ .name = "content-type", .value = "application/json" },
        .{ .name = "accept", .value = "application/json" },
        .{ .name = "user-agent", .value = "docz/1.0 (libcurl)" },
    };

    const req = curl.HTTPRequest{
        .method = .POST,
        .url = oauthTokenEndpoint,
        .headers = &headers,
        .body = body,
        .timeout_ms = 30000, // 30 second timeout
        .verify_ssl = true,
        .follow_redirects = false,
        .verbose = false,
    };

    var resp = client.request(req) catch |err| {
        std.log.err("❌ Token exchange request failed: {}", .{err});
        switch (err) {
            curl.HTTPError.NetworkError => {
                std.log.err("   Network connection failed", .{});
                std.log.err("   • Check your internet connection", .{});
                std.log.err("   • Check if corporate firewall blocks HTTPS", .{});
            },
            curl.HTTPError.TlsError => {
                std.log.err("   TLS/SSL connection failed", .{});
                std.log.err("   • Certificate validation or security settings issue", .{});
            },
            curl.HTTPError.Timeout => {
                std.log.err("   Request timed out", .{});
                std.log.err("   🔄 Try again - this is often temporary", .{});
            },
            else => {
                std.log.err("   Unexpected error: {}", .{err});
                std.log.err("   🔄 Please try again", .{});
            },
        }
        return Error.NetworkError;
    };
    defer resp.deinit();

    if (resp.status_code != 200) {
        std.log.err("OAuth token exchange failed with status: {}", .{resp.status_code});
        if (resp.status_code >= 400 and resp.status_code < 500) {
            std.log.err("Client error - check OAuth configuration", .{});
        } else if (resp.status_code >= 500) {
            std.log.err("Server error - Anthropic's OAuth service may be unavailable", .{});
        }
        return Error.AuthError;
    }

    // Parse JSON response to extract OAuth tokens
    const parsed = std.json.parseFromSlice(struct {
        access_token: []const u8,
        refresh_token: []const u8,
        expires_in: i64,
    }, allocator, resp.body, .{}) catch |err| {
        std.log.err("Failed to parse OAuth token response: {}", .{err});
        std.log.debug("Response body: {s}", .{resp.body});
        return Error.AuthError;
    };
    defer parsed.deinit();

    // Convert expires_in (seconds) to expires_at (Unix timestamp)
    const now = std.time.timestamp();
    const expires_at = now + parsed.value.expires_in;

    std.log.info("✅ OAuth tokens received successfully!", .{});

    // Return OAuth credentials with owned strings
    return Credentials{
        .type = try allocator.dupe(u8, "oauth"),
        .accessToken = try allocator.dupe(u8, parsed.value.access_token),
        .refreshToken = try allocator.dupe(u8, parsed.value.refresh_token),
        .expiresAt = expires_at,
    };
}

/// Refresh OAuth tokens
pub fn refreshTokens(allocator: std.mem.Allocator, refreshToken: []const u8) !Credentials {
    std.log.info("🔄 Refreshing OAuth tokens...", .{});

    var client = curl.HTTPClient.init(allocator) catch |err| {
        std.log.err("Failed to initialize HTTP client: {}", .{err});
        return Error.NetworkError;
    };
    defer client.deinit();

    // Build the JSON request body (matching OpenCode's format)
    const body = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "grant_type": "refresh_token",
        \\  "refresh_token": "{s}",
        \\  "client_id": "{s}"
        \\}}
    , .{ refreshToken, oauthClientId });
    defer allocator.free(body);

    const headers = [_]curl.Header{
        .{ .name = "content-type", .value = "application/json" },
        .{ .name = "accept", .value = "application/json" },
        .{ .name = "user-agent", .value = "docz/1.0 (libcurl)" },
    };

    const req = curl.HTTPRequest{
        .method = .POST,
        .url = oauthTokenEndpoint,
        .headers = &headers,
        .body = body,
        .timeout_ms = 30000, // 30 second timeout
        .verify_ssl = true,
        .follow_redirects = false,
        .verbose = false,
    };

    var resp = client.request(req) catch |err| {
        std.log.err("❌ Token refresh request failed: {}", .{err});
        switch (err) {
            curl.HTTPError.NetworkError => {
                std.log.err("Connection was reset by Anthropic's OAuth server during token refresh. This can happen due to network issues or server load.", .{});
                std.log.err("Please try again in a few moments.", .{});
            },
            curl.HTTPError.TlsError => {
                std.log.err("TLS connection failed during token refresh.", .{});
                std.log.err("Please check your network settings.", .{});
            },
            curl.HTTPError.Timeout => {
                std.log.err("Token refresh request timed out.", .{});
                std.log.err("🔄 Try again - this is often temporary", .{});
            },
            else => {
                std.log.err("Failed to refresh OAuth tokens: {}", .{err});
            },
        }
        return Error.NetworkError;
    };
    defer resp.deinit();

    if (resp.status_code != 200) {
        std.log.err("OAuth token refresh failed with status: {}", .{resp.status_code});
        return Error.AuthError;
    }

    // Parse JSON response to extract OAuth tokens
    const parsed = std.json.parseFromSlice(struct {
        access_token: []const u8,
        refresh_token: []const u8,
        expires_in: i64,
    }, allocator, resp.body, .{}) catch |err| {
        std.log.err("Failed to parse OAuth token refresh response: {}", .{err});
        return Error.AuthError;
    };
    defer parsed.deinit();

    // Convert expires_in (seconds) to expires_at (Unix timestamp)
    const now = std.time.timestamp();
    const expires_at = now + parsed.value.expires_in;

    std.log.info("✅ OAuth tokens refreshed successfully!", .{});

    // Return OAuth credentials with owned strings
    return Credentials{
        .type = try allocator.dupe(u8, "oauth"),
        .accessToken = try allocator.dupe(u8, parsed.value.access_token),
        .refreshToken = try allocator.dupe(u8, parsed.value.refresh_token),
        .expiresAt = expires_at,
    };
}

/// Load OAuth credentials from file
pub fn loadOAuthCredentials(allocator: std.mem.Allocator, file_path: []const u8) !?Credentials {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 16 * 1024);
    defer allocator.free(contents);

    const parsed = try std.json.parseFromSlice(Credentials, allocator, contents, .{});
    defer parsed.deinit();

    return Credentials{
        .type = try allocator.dupe(u8, parsed.value.type),
        .accessToken = try allocator.dupe(u8, parsed.value.accessToken),
        .refreshToken = try allocator.dupe(u8, parsed.value.refreshToken),
        .expiresAt = parsed.value.expiresAt,
    };
}

/// Save OAuth credentials to file with atomic update
pub fn saveOAuthCredentials(allocator: std.mem.Allocator, file_path: []const u8, creds: Credentials) !void {
    // Use manual JSON construction (working approach in Zig 0.15.1)
    const json_content = try std.fmt.allocPrint(allocator, "{{\"type\":\"{s}\",\"access_token\":\"{s}\",\"refresh_token\":\"{s}\",\"expires_at\":{}}}", .{ creds.type, creds.accessToken, creds.refreshToken, creds.expiresAt });
    defer allocator.free(json_content);

    const file = try std.fs.cwd().createFile(file_path, .{ .mode = 0o600 });
    defer file.close();

    try file.writeAll(json_content);
}

/// Extract authorization code from OAuth callback URL
pub fn extractCodeFromCallbackUrl(allocator: std.mem.Allocator, callback_url: []const u8) ![]u8 {
    // Parse URL and extract code parameter
    const url = try std.URI.parse(callback_url);

    // Handle both query parameters and fragments
    if (url.query) |query_component| {
        const query_str = switch (query_component) {
            .percent_encoded => |str| str,
            .raw => |str| str,
        };
        if (std.mem.indexOf(u8, query_str, "code=")) |start| {
            const code_start = start + 5; // Length of "code="
            const code_end = std.mem.indexOf(u8, query_str[code_start..], "&") orelse query_str.len - code_start;
            return try allocator.dupe(u8, query_str[code_start .. code_start + code_end]);
        }
    }

    if (url.fragment) |fragment_component| {
        const fragment_str = switch (fragment_component) {
            .percent_encoded => |str| str,
            .raw => |str| str,
        };
        if (std.mem.indexOf(u8, fragment_str, "code=")) |start| {
            const code_start = start + 5; // Length of "code="
            const code_end = std.mem.indexOf(u8, fragment_str[code_start..], "&") orelse fragment_str.len - code_start;
            return try allocator.dupe(u8, fragment_str[code_start .. code_start + code_end]);
        }
    }

    return Error.AuthError;
}

/// Launch browser to open authorization URL
pub fn launchBrowser(url: []const u8) !void {
    const allocator = std.heap.page_allocator;

    switch (@import("builtin").os.tag) {
        .macos => {
            const argv = [_][]const u8{ "open", url };
            _ = try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &argv,
            });
        },
        .linux => {
            const argv = [_][]const u8{ "xdg-open", url };
            _ = try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &argv,
            });
        },
        .windows => {
            const argv = [_][]const u8{ "cmd", "/c", "start", url };
            _ = try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &argv,
            });
        },
        else => {
            std.log.warn("Unsupported platform for browser launching. Please manually open: {s}", .{url});
        },
    }
}

/// Start HTTP callback server to handle OAuth authorization code automatically
pub fn waitForOAuthCallback(allocator: std.mem.Allocator, port: u16) ![]const u8 {
    std.log.info("Starting OAuth callback server on port {}...", .{port});

    // Create TCP server address
    const address = std.net.Address.parseIp4("127.0.0.1", port) catch |err| {
        std.log.err("Failed to parse callback server address: {}", .{err});
        return Error.InvalidPort;
    };

    // Start listening for connections
    var server = address.listen(.{}) catch |err| {
        std.log.err("Failed to start callback server on port {}: {}", .{ port, err });
        return Error.NetworkError;
    };
    defer server.deinit();

    std.log.info("✅ Callback server ready at http://127.0.0.1:{}", .{port});
    std.log.info("🔗 Complete the authorization in your browser...", .{});

    while (true) {
        // Accept connection
        var connection = server.accept() catch |err| {
            std.log.warn("Failed to accept connection: {}, continuing...", .{err});
            continue;
        };
        defer connection.stream.close();

        // Read HTTP request with timeout handling
        var request_buffer: [4096]u8 = undefined;
        const bytes_read = connection.stream.read(&request_buffer) catch |err| switch (err) {
            error.WouldBlock => 0,
            else => {
                std.log.warn("Error reading request: {}", .{err});
                continue;
            },
        };

        if (bytes_read == 0) {
            std.log.warn("Client closed connection before sending request", .{});
            continue;
        }

        const request_data = request_buffer[0..bytes_read];
        const request_line_end = std.mem.indexOf(u8, request_data, "\n") orelse {
            sendHTTPError(&connection.stream, 400, "Invalid request format - no line ending") catch {};
            continue;
        };

        const request_line = std.mem.trim(u8, request_data[0..request_line_end], " \t\r\n");

        // Continue with parsing the request line

        const request_line_trimmed = std.mem.trim(u8, request_line, " \t\r\n");

        // Parse HTTP request: "GET /path?query HTTP/1.1"
        var request_parts = std.mem.splitSequence(u8, request_line_trimmed, " ");
        const method = request_parts.next() orelse {
            sendHTTPError(&connection.stream, 400, "Invalid request format") catch {};
            continue;
        };
        const path_and_query = request_parts.next() orelse {
            sendHTTPError(&connection.stream, 400, "Invalid request format") catch {};
            continue;
        };

        // Only handle GET requests for OAuth callback
        if (!std.mem.eql(u8, method, "GET")) {
            sendHTTPError(&connection.stream, 405, "Method not allowed") catch {};
            continue;
        }

        std.log.debug("Received OAuth callback request: GET {s}", .{path_and_query});

        // Extract query parameters from the path
        const query_start = std.mem.indexOf(u8, path_and_query, "?");
        if (query_start == null) {
            sendHTTPError(&connection.stream, 400, "No query parameters in OAuth callback") catch {};
            continue;
        }

        const query_string = path_and_query[query_start.? + 1 ..];

        // Check for OAuth error parameters first
        if (std.mem.indexOf(u8, query_string, "error=")) |_| {
            const error_code = extractQueryParam(query_string, "error") orelse "unknown_error";
            const error_desc = extractQueryParam(query_string, "error_description");

            // Send user-friendly error page to browser
            sendOAuthErrorResponse(&connection.stream, error_code, error_desc) catch {};

            // Handle the error and return appropriate error
            return handleOAuthError(allocator, error_code, error_desc);
        }

        // Extract authorization code from query parameters
        if (extractQueryParam(query_string, "code")) |auth_code| {
            // Send success response to browser
            sendOAuthSuccessResponse(&connection.stream) catch |err| {
                std.log.warn("Failed to send success response to browser: {}", .{err});
            };

            std.log.info("✅ Authorization code received successfully!", .{});

            // Return the authorization code (caller owns the memory)
            return allocator.dupe(u8, auth_code);
        } else {
            // No code parameter found
            sendHTTPError(&connection.stream, 400, "Authorization code not found in OAuth callback") catch {};
            continue;
        }
    }
}

/// Send HTTP error response to client
fn sendHTTPError(stream: *std.net.Stream, status_code: u16, message: []const u8) !void {
    const status_text = switch (status_code) {
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        500 => "Internal Server Error",
        else => "Error",
    };

    var response_buffer: [1024]u8 = undefined;
    var writer_buffer: [1024]u8 = undefined;

    const response = try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 {} {s}\r\n" ++
        "Content-Type: text/plain\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "{s}\r\n", .{ status_code, status_text, message });

    var stream_writer = stream.writer(&writer_buffer);
    const writer_interface = &stream_writer.interface;
    try writer_interface.writeAll(response);
}

/// Send OAuth success response with user-friendly page
fn sendOAuthSuccessResponse(stream: *std.net.Stream) !void {
    const html_content =
        "<!DOCTYPE html>\n" ++
        "<html><head><title>Authorization Successful</title>" ++
        "<style>body{font-family:Arial,sans-serif;max-width:600px;margin:50px auto;text-align:center;background:#f5f5f5;padding:20px}" ++
        ".success{color:#28a745;font-size:24px;margin:20px 0}" ++
        ".message{color:#333;font-size:16px;margin:10px 0}</style></head>" ++
        "<body><div class='success'>✅ Authorization Successful!</div>" ++
        "<div class='message'>You can now close this browser tab and return to your terminal.</div>" ++
        "<div class='message'>The OAuth setup will continue automatically.</div></body></html>";

    var response_buffer: [2048]u8 = undefined;
    var writer_buffer: [2048]u8 = undefined;

    const response = try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/html\r\n" ++
        "Content-Length: {}\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "{s}", .{ html_content.len, html_content });

    var stream_writer = stream.writer(&writer_buffer);
    const writer_interface = &stream_writer.interface;
    try writer_interface.writeAll(response);
}

/// Send OAuth error response with user-friendly error page
fn sendOAuthErrorResponse(stream: *std.net.Stream, error_code: []const u8, error_description: ?[]const u8) !void {
    var html_buffer: [2048]u8 = undefined;

    const description = error_description orelse "No additional details provided.";
    const html_content = try std.fmt.bufPrint(&html_buffer, "<!DOCTYPE html>\n" ++
        "<html><head><title>Authorization Error</title>" ++
        "<style>body{{font-family:Arial,sans-serif;max-width:600Dpx;margin:50px auto;text-align:center;background:#f5f5f5;padding:20px}}" ++
        ".error{{color:#dc3545;font-size:24px;margin:20px 0}}" ++
        ".message{{color:#333;font-size:16px;margin:10px 0}}" ++
        ".code{{background:#e9ecef;padding:10px;border-radius:5px;font-family:monospace}}</style></head>" ++
        "<body><div class='error'>❌ Authorization Failed</div>" ++
        "<div class='message'><strong>Error:</strong> {s}</div>" ++
        "<div class='message'>{s}</div>" ++
        "<div class='message'>Please close this tab and try the authorization again.</div></body></html>", .{ error_code, description });

    var response_buffer: [3072]u8 = undefined;
    var writer_buffer: [3072]u8 = undefined;

    const response = try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 400 Bad Request\r\n" ++
        "Content-Type: text/html\r\n" ++
        "Content-Length: {}\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "{s}", .{ html_content.len, html_content });

    var stream_writer = stream.writer(&writer_buffer);
    const writer_interface = &stream_writer.interface;
    try writer_interface.writeAll(response);
}

/// Extract query parameter value from URL query string
fn extractQueryParam(query_string: []const u8, param_name: []const u8) ?[]const u8 {
    const search_key = std.fmt.allocPrint(std.heap.page_allocator, "{s}=", .{param_name}) catch return null;
    defer std.heap.page_allocator.free(search_key);

    const param_start = std.mem.indexOf(u8, query_string, search_key) orelse return null;
    const value_start = param_start + search_key.len;

    // Find end of parameter value (next & or end of string)
    const value_end = std.mem.indexOfScalarPos(u8, query_string, value_start, '&') orelse query_string.len;

    if (value_end <= value_start) return null;

    return query_string[value_start..value_end];
}

/// Validate state parameter for CSRF protection
pub fn validateState(received_state: []const u8, expected_state: []const u8) bool {
    return std.mem.eql(u8, received_state, expected_state);
}

/// Comprehensive error recovery for OAuth failures
pub fn handleOAuthError(allocator: std.mem.Allocator, error_code: []const u8, error_description: ?[]const u8) Error {
    std.log.err("OAuth error: {s}", .{error_code});
    if (error_description) |desc| {
        std.log.err("Description: {s}", .{desc});
    }

    // Provide user-friendly guidance
    if (std.mem.eql(u8, error_code, "invalid_grant")) {
        std.log.err("🔄 Your authorization has expired or been revoked.", .{});
        std.log.err("   Please run OAuth setup again: --oauth", .{});
        return Error.InvalidGrant;
    } else if (std.mem.eql(u8, error_code, "invalid_request")) {
        std.log.err("⚠️  Invalid OAuth request. This may be a client issue.", .{});
        std.log.err("   Try running OAuth setup again: --oauth", .{});
        return Error.AuthError;
    } else if (std.mem.eql(u8, error_code, "access_denied")) {
        std.log.err("🚫 Authorization was denied.", .{});
        std.log.err("   Please authorize the application to continue.", .{});
        return Error.AuthError;
    } else if (std.mem.eql(u8, error_code, "server_error")) {
        std.log.err("🔧 Server error occurred. Please try again later.", .{});
        return Error.NetworkError;
    }

    _ = allocator;
    return Error.AuthError;
}

/// Check if credentials file exists and is readable
pub fn validateCredentialsFile(file_path: []const u8) bool {
    const file = std.fs.cwd().openFile(file_path, .{}) catch return false;
    defer file.close();

    // Check if file has content
    const stat = file.stat() catch return false;
    return stat.size > 0;
}

/// Clean up expired or invalid credentials
pub fn cleanupCredentials(allocator: std.mem.Allocator, file_path: []const u8) !void {
    if (validateCredentialsFile(file_path)) {
        std.log.info("Removing invalid OAuth credentials file: {s}", .{file_path});
        std.fs.cwd().deleteFile(file_path) catch |err| {
            std.log.warn("Failed to cleanup credentials file: {}", .{err});
        };
    }
    _ = allocator;
}

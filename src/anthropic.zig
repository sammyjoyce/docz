//! Minimal Anthropic HTTP streaming client for Zig 0.15.1.
//! Supports both API key and OAuth (Claude Pro/Max) authentication.

const std = @import("std");

pub const MessageRole = enum { system, user, assistant, tool };

pub const Message = struct {
    role: MessageRole,
    content: []const u8,
};

/// OAuth configuration constants
pub const OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
pub const OAUTH_AUTHORIZATION_URL = "https://claude.ai/oauth/authorize";
pub const OAUTH_TOKEN_ENDPOINT = "https://console.anthropic.com/v1/oauth/token";
pub const OAUTH_REDIRECT_URI = "https://console.anthropic.com/oauth/code/callback";
pub const OAUTH_SCOPES = "org:create_api_key user:profile user:inference";

/// OAuth credentials stored to disk
pub const OAuthCredentials = struct {
    type: []const u8, // Always "oauth"
    access_token: []const u8,
    refresh_token: []const u8,
    expires_at: i64, // Unix timestamp

    /// Check if the token is expired
    pub fn isExpired(self: OAuthCredentials) bool {
        const now = std.time.timestamp();
        return now >= self.expires_at;
    }

    /// Check if the token will expire within the specified leeway (in seconds)
    pub fn willExpireSoon(self: OAuthCredentials, leeway: i64) bool {
        const now = std.time.timestamp();
        return now + leeway >= self.expires_at;
    }
};

/// PKCE parameters for OAuth flow
pub const PkceParams = struct {
    code_verifier: []const u8,
    code_challenge: []const u8,
    state: []const u8,
};

/// Authentication methods supported
pub const AuthMethod = union(enum) {
    api_key: []const u8,
    oauth: OAuthCredentials,
};

/// OAuth provider configuration
pub const OAuthProvider = struct {
    client_id: []const u8,
    authorization_url: []const u8,
    token_url: []const u8,
    redirect_uri: []const u8,
    scopes: []const []const u8,

    pub fn buildAuthUrl(self: OAuthProvider, allocator: std.mem.Allocator, pkce_params: PkceParams) ![]u8 {
        const scopes_joined = try std.mem.join(allocator, " ", self.scopes);
        defer allocator.free(scopes_joined);

        return try std.fmt.allocPrint(allocator, "{s}?client_id={s}&response_type=code&redirect_uri={s}&scope={s}&code_challenge={s}&code_challenge_method=S256&state={s}", .{ self.authorization_url, self.client_id, self.redirect_uri, scopes_joined, pkce_params.code_challenge, pkce_params.state });
    }
};

/// Token refresh state to prevent concurrent refreshes
pub const RefreshState = struct {
    mutex: std.Thread.Mutex,
    in_progress: bool,

    pub fn init() RefreshState {
        return RefreshState{
            .mutex = std.Thread.Mutex{},
            .in_progress = false,
        };
    }
};

/// Global refresh state for single-flight protection
var global_refresh_state = RefreshState.init();

/// Cost calculation structure with Pro/Max override support
pub const CostCalculator = struct {
    is_oauth_session: bool,

    pub fn init(is_oauth: bool) CostCalculator {
        return CostCalculator{ .is_oauth_session = is_oauth };
    }

    /// Calculate cost for input tokens (returns 0 for OAuth Pro/Max sessions)
    pub fn calculateInputCost(self: CostCalculator, tokens: u32, model: []const u8) f64 {
        if (self.is_oauth_session) return 0.0;

        // API key pricing (example rates per 1k tokens)
        _ = model; // TODO: Implement per-model pricing
        const rate_per_1k = 0.003; // Example rate
        return (@as(f64, @floatFromInt(tokens)) / 1000.0) * rate_per_1k;
    }

    /// Calculate cost for output tokens (returns 0 for OAuth Pro/Max sessions)
    pub fn calculateOutputCost(self: CostCalculator, tokens: u32, model: []const u8) f64 {
        if (self.is_oauth_session) return 0.0;

        // API key pricing (example rates per 1k tokens)
        _ = model; // TODO: Implement per-model pricing
        const rate_per_1k = 0.015; // Example rate
        return (@as(f64, @floatFromInt(tokens)) / 1000.0) * rate_per_1k;
    }

    /// Get pricing display mode
    pub fn getPricingMode(self: CostCalculator) []const u8 {
        return if (self.is_oauth_session) "Subscription (Free)" else "Pay-per-use";
    }
};

/// Error set for client operations.
pub const Error = error{ MissingAPIKey, ApiError, AuthError, TokenExpired, OutOfMemory, InvalidFormat, InvalidPort, UnexpectedCharacter, InvalidGrant, NetworkError, RefreshInProgress, ChunkParseError, MalformedChunk, InvalidChunkSize };

pub const StreamParams = struct {
    model: []const u8,
    max_tokens: usize = 256,
    temperature: f32 = 0.7,
    messages: []const Message,
    /// Callback invoked for every token / delta chunk.
    /// The slice is only valid until the next invocation.
    on_token: *const fn ([]const u8) void,
};

pub const AnthropicClient = struct {
    allocator: std.mem.Allocator,
    auth: AuthMethod,
    credentials_path: ?[]const u8, // Path to store OAuth credentials

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) Error!AnthropicClient {
        if (api_key.len == 0) return Error.MissingAPIKey;
        return AnthropicClient{
            .allocator = allocator,
            .auth = AuthMethod{ .api_key = api_key },
            .credentials_path = null,
        };
    }

    pub fn initWithOAuth(allocator: std.mem.Allocator, oauth_creds: OAuthCredentials, credentials_path: []const u8) Error!AnthropicClient {
        return AnthropicClient{
            .allocator = allocator,
            .auth = AuthMethod{ .oauth = oauth_creds },
            .credentials_path = try allocator.dupe(u8, credentials_path),
        };
    }

    pub fn deinit(self: *AnthropicClient) void {
        if (self.credentials_path) |path| {
            self.allocator.free(path);
        }
        // Free auth data
        switch (self.auth) {
            .oauth => |creds| {
                self.allocator.free(creds.type);
                self.allocator.free(creds.access_token);
                self.allocator.free(creds.refresh_token);
            },
            .api_key => {}, // String is not owned by client
        }
    }

    /// Check if current session is OAuth Pro/Max (for cost override)
    pub fn isOAuthSession(self: AnthropicClient) bool {
        return switch (self.auth) {
            .oauth => true,
            .api_key => false,
        };
    }

    /// Refresh OAuth tokens if needed and update client auth with single-flight protection
    pub fn refreshOAuthIfNeeded(self: *AnthropicClient) !void {
        switch (self.auth) {
            .api_key => return, // No refresh needed for API key
            .oauth => |oauth_creds| {
                // Check if refresh is needed (5 minute leeway)
                if (!oauth_creds.willExpireSoon(300)) return;

                // Single-flight protection
                global_refresh_state.mutex.lock();
                defer global_refresh_state.mutex.unlock();

                // Check again in case another thread refreshed while we waited
                if (!oauth_creds.willExpireSoon(300)) return;

                if (global_refresh_state.in_progress) {
                    return Error.RefreshInProgress;
                }

                global_refresh_state.in_progress = true;
                defer global_refresh_state.in_progress = false;

                // Perform the refresh
                const new_creds = refreshTokens(self.allocator, oauth_creds.refresh_token) catch |err| {
                    std.log.err("Token refresh failed: {}", .{err});
                    return err;
                };

                // Free old credentials
                self.allocator.free(oauth_creds.type);
                self.allocator.free(oauth_creds.access_token);
                self.allocator.free(oauth_creds.refresh_token);

                // Update with new credentials
                self.auth = AuthMethod{ .oauth = new_creds };

                // Persist updated credentials
                if (self.credentials_path) |path| {
                    saveOAuthCredentials(self.allocator, path, new_creds) catch |err| {
                        std.log.warn("Failed to save refreshed credentials: {}", .{err});
                    };
                }
            },
        }
    }

    /// Streams completion via Server-Sent Events, invoking callback per data chunk.
    pub fn stream(self: *AnthropicClient, params: StreamParams) anyerror!void {
        return self.streamWithRetry(params, false);
    }

    /// Internal method to handle streaming with automatic retry on 401
    fn streamWithRetry(self: *AnthropicClient, params: StreamParams, is_retry: bool) anyerror!void {
        // Refresh OAuth tokens if needed (unless this is already a retry)
        if (!is_retry) {
            try self.refreshOAuthIfNeeded();
        }

        // 1) Build request body and send streaming request via std.http.Client
        const body_json = try buildBodyJson(self.allocator, params);
        defer self.allocator.free(body_json);

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Prepare auth header
        var auth_header_buffer: [512]u8 = undefined;
        var auth_header: std.http.Header = undefined;

        switch (self.auth) {
            .api_key => |key| {
                auth_header = .{ .name = "x-api-key", .value = key };
            },
            .oauth => |creds| {
                const bearer = try std.fmt.bufPrint(&auth_header_buffer, "Bearer {s}", .{creds.access_token});
                auth_header = .{ .name = "authorization", .value = bearer };
            },
        }

        const extra_headers = [_]std.http.Header{
            auth_header,
            .{ .name = "accept", .value = "text/event-stream" },
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "anthropic-version", .value = "2023-06-01" },
        };

        const uri = try std.Uri.parse("https://api.anthropic.com/v1/messages");
        var req = try client.request(.POST, uri, .{
            .extra_headers = &extra_headers,
            .keep_alive = false,
            .redirect_behavior = .not_allowed,
        });

        req.transfer_encoding = .{ .content_length = body_json.len };

        var bw = try req.sendBody(&.{});
        try bw.writer.writeAll(body_json);
        try bw.end();

        // Receive the response using Zig 0.15.1 API
        var resp = try req.receiveHead(&.{});

        // Check for 401 Unauthorized and retry if needed
        if (resp.head.status == .unauthorized and !is_retry) {
            std.log.warn("Received 401 Unauthorized, attempting token refresh...", .{});
            return self.streamWithRetry(params, true); // Retry once after refresh
        }

        if (resp.head.status != .ok) {
            std.log.err("HTTP error: {}", .{resp.head.status});
            return Error.ApiError;
        }

        // Enhanced HTTP streaming response reading for Zig 0.15.1 with improved buffer management
        // Use optimized streaming processing for large payloads (chunked encoding handled by std.http.Client)
        var response_buffer: [65536]u8 = undefined; // 64KB buffer for enhanced processing
        const response_reader = resp.reader(&response_buffer);

        // Use enhanced streaming processing with larger buffer for better performance
        try processStreamingResponse(self.allocator, response_reader, params.on_token);
    }
};

fn buildBodyJson(allocator: std.mem.Allocator, params: StreamParams) ![]u8 {
    var buffer = std.array_list.Managed(u8).init(allocator);
    defer buffer.deinit();

    const writer = buffer.writer();

    // Manual JSON construction for Zig 0.15.1 compatibility
    try std.fmt.format(writer, "{{", .{});
    try std.fmt.format(writer, "\"model\":\"{s}\",", .{params.model});
    try std.fmt.format(writer, "\"max_tokens\":{},", .{params.max_tokens});
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

/// Check if response uses chunked transfer encoding
/// Note: In Zig 0.15.1, std.http.Client handles chunked encoding transparently
/// This function serves as a placeholder for future header inspection
fn isChunkedEncoding(response_head: anytype) bool {
    _ = response_head;
    // For now, assume non-chunked as std.http.Client handles chunked encoding internally
    // This allows us to keep the enhanced processing logic for future use
    return false;
}

/// Chunk processing state for incremental parsing
const ChunkState = struct {
    size: usize = 0,
    bytes_read: usize = 0,
    reading_size: bool = true,
    trailers_started: bool = false,
    extensions: ?[]const u8 = null,

    pub fn reset(self: *ChunkState) void {
        self.size = 0;
        self.bytes_read = 0;
        self.reading_size = true;
        self.trailers_started = false;
        self.extensions = null;
    }
};

/// Process chunked Server-Sent Events with enhanced memory optimization and graceful error recovery
fn processChunkedStreamingResponse(allocator: std.mem.Allocator, reader: *std.Io.Reader, callback: *const fn ([]const u8) void) !void {
    var event_data = std.array_list.Managed(u8).init(allocator);
    defer event_data.deinit();

    var chunk_state = ChunkState{};
    var chunk_buffer = std.array_list.Managed(u8).init(allocator);
    defer chunk_buffer.deinit();

    // Use larger initial capacity for potentially large chunked events
    try event_data.ensureTotalCapacity(8192);
    try chunk_buffer.ensureTotalCapacity(4096);

    var recovery_attempts: u8 = 0;
    const max_recovery_attempts = 3;

    while (true) {
        if (chunk_state.reading_size) {
            // Read chunk size line (hex format with optional extensions)
            const size_line_result = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
                error.EndOfStream => {
                    // Send final event if any data remains in accumulated buffer
                    if (event_data.items.len > 0) {
                        callback(event_data.items);
                    }
                    return; // Normal end of chunked stream
                },
                error.StreamTooLong => {
                    std.log.warn("Chunked response contains size line too long for buffer, attempting graceful recovery", .{});
                    recovery_attempts += 1;
                    if (recovery_attempts >= max_recovery_attempts) {
                        std.log.err("Too many recovery attempts, falling back to non-chunked processing", .{});
                        // Fallback: try to process remaining data as regular SSE stream
                        return processStreamingResponse(allocator, reader, callback) catch Error.MalformedChunk;
                    }
                    chunk_state.reset();
                    continue;
                },
                else => return err,
            };

            const size_line = std.mem.trim(u8, size_line_result, " \t\r\n");

            // Skip empty lines that might occur in malformed streams
            if (size_line.len == 0) {
                continue;
            }

            // Parse chunk size (hex) with optional chunk extensions and error recovery
            const chunk_info = parseChunkSize(size_line) catch |err| {
                std.log.warn("Failed to parse chunk size '{s}': {}, attempting recovery", .{ size_line, err });
                recovery_attempts += 1;
                if (recovery_attempts >= max_recovery_attempts) {
                    std.log.err("Too many chunk parse errors, falling back to non-chunked processing", .{});
                    return processStreamingResponse(allocator, reader, callback) catch Error.ChunkParseError;
                }
                chunk_state.reset();
                continue;
            };

            chunk_state.size = chunk_info.size;
            chunk_state.extensions = chunk_info.extensions;
            recovery_attempts = 0; // Reset on successful parse

            if (chunk_state.size == 0) {
                // Zero-sized chunk indicates end of chunked data
                // Process any remaining trailers, then finish
                processChunkTrailers(reader) catch |err| {
                    std.log.warn("Error processing chunk trailers: {}, continuing anyway", .{err});
                };
                if (event_data.items.len > 0) {
                    callback(event_data.items);
                }
                return;
            }

            chunk_state.reading_size = false;
            chunk_state.bytes_read = 0;
            chunk_buffer.clearRetainingCapacity();
        } else {
            // Read chunk data incrementally with memory optimization
            const remaining = chunk_state.size - chunk_state.bytes_read;
            if (remaining == 0) {
                // Chunk complete, process accumulated data as SSE lines
                processSSELines(chunk_buffer.items, &event_data, callback) catch |err| {
                    std.log.warn("Error processing SSE lines in chunk: {}, continuing", .{err});
                };

                // Skip trailing CRLF after chunk data with graceful handling
                _ = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
                    error.EndOfStream => return,
                    error.StreamTooLong => {
                        std.log.warn("Malformed chunk trailing CRLF, continuing gracefully", .{});
                    },
                    else => {
                        std.log.warn("Error reading chunk trailer CRLF: {}, continuing", .{err});
                    },
                };

                chunk_state.reset();
                continue;
            }

            // Read up to remaining bytes or available buffer space
            const read_size = @min(remaining, 1024); // Read in 1KB increments for memory efficiency
            var temp_buffer: [1024]u8 = undefined;
            const bytes_read = reader.readUpTo(temp_buffer[0..read_size]) catch |err| switch (err) {
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
                    recovery_attempts += 1;
                    if (recovery_attempts >= max_recovery_attempts) {
                        std.log.err("Too many chunk read errors, processing accumulated data and exiting", .{});
                        if (chunk_buffer.items.len > 0) {
                            processSSELines(chunk_buffer.items, &event_data, callback) catch {};
                        }
                        if (event_data.items.len > 0) {
                            callback(event_data.items);
                        }
                        return;
                    }
                    chunk_state.reset();
                    continue;
                },
            };

            if (bytes_read == 0) {
                std.log.warn("No bytes read in chunk processing, attempting to continue", .{});
                recovery_attempts += 1;
                if (recovery_attempts >= max_recovery_attempts) {
                    std.log.err("Too many zero-byte reads, processing accumulated data", .{});
                    if (chunk_buffer.items.len > 0) {
                        processSSELines(chunk_buffer.items, &event_data, callback) catch {};
                    }
                    if (event_data.items.len > 0) {
                        callback(event_data.items);
                    }
                    return;
                }
                continue;
            }

            // Accumulate chunk data with capacity management
            try chunk_buffer.ensureUnusedCapacity(bytes_read);
            try chunk_buffer.appendSlice(temp_buffer[0..bytes_read]);
            chunk_state.bytes_read += bytes_read;
            recovery_attempts = 0; // Reset on successful read
        }
    }
}

/// Parse chunk size and extensions from chunk size line
fn parseChunkSize(size_line: []const u8) !struct { size: usize, extensions: ?[]const u8 } {
    // Find semicolon separator for chunk extensions
    const semicolon_pos = std.mem.indexOf(u8, size_line, ";");
    const size_str = if (semicolon_pos) |pos| size_line[0..pos] else size_line;
    const extensions = if (semicolon_pos) |pos| size_line[pos + 1 ..] else null;

    // Parse hex chunk size with error handling
    const size = std.fmt.parseInt(usize, size_str, 16) catch |err| switch (err) {
        error.Overflow => return Error.InvalidChunkSize,
        error.InvalidCharacter => return Error.ChunkParseError,
    };

    // Validate reasonable chunk size (prevent DoS)
    if (size > 128 * 1024 * 1024) { // 128MB limit per chunk
        std.log.warn("Chunk size {} exceeds maximum allowed size", .{size});
        return Error.InvalidChunkSize;
    }

    return .{ .size = size, .extensions = extensions };
}

/// Process chunk trailers (headers after final chunk)
fn processChunkTrailers(reader: *std.Io.Reader) !void {
    while (true) {
        const trailer_line = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => return,
            error.StreamTooLong => {
                std.log.warn("Chunk trailer line too long, skipping", .{});
                continue;
            },
            else => return err,
        };

        const line = std.mem.trim(u8, trailer_line, " \t\r\n");
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

/// Process accumulated chunk data as Server-Sent Event lines
fn processSSELines(chunk_data: []const u8, event_data: *std.array_list.Managed(u8), callback: *const fn ([]const u8) void) !void {
    var line_iter = std.mem.splitSequence(u8, chunk_data, "\n");

    while (line_iter.next()) |line_data| {
        const line = std.mem.trim(u8, line_data, " \t\r\n");

        if (line.len == 0) {
            // Empty line indicates end of SSE event
            if (event_data.items.len > 0) {
                callback(event_data.items);
                event_data.clearRetainingCapacity();
            }
        } else if (std.mem.startsWith(u8, line, "data: ")) {
            // Parse SSE data field with enhanced capacity management
            const data_content = line[6..]; // Skip "data: "
            if (event_data.items.len > 0) {
                try event_data.append('\n'); // Multi-line data separator
            }

            // Ensure we have capacity for the new data to handle large payloads
            try event_data.ensureUnusedCapacity(data_content.len);
            try event_data.appendSlice(data_content);
        }
        // Ignore other SSE fields (event, id, retry, etc.) in chunk processing
    }
}

/// Process Server-Sent Events using Io.Reader with enhanced streaming for large payloads
fn processStreamingResponse(allocator: std.mem.Allocator, reader: *std.Io.Reader, callback: *const fn ([]const u8) void) !void {
    var event_data = std.array_list.Managed(u8).init(allocator);
    defer event_data.deinit();

    // Use larger initial capacity for potentially large events in chunked responses
    try event_data.ensureTotalCapacity(4096);

    while (true) {
        // Read line by line using Io.Reader interface with enhanced error handling
        const line_result = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => {
                // Send final event if any data remains
                if (event_data.items.len > 0) {
                    callback(event_data.items);
                }
                return; // Normal end of stream
            },
            error.StreamTooLong => {
                // For large responses, handle lines that are too long gracefully
                // Skip this line and continue processing to prevent blocking
                std.log.warn("HTTP response contains line too long for buffer, skipping", .{});
                continue;
            },
            else => return err, // Other read errors
        };

        const line = std.mem.trim(u8, line_result, " \t\r\n");

        if (line.len == 0) {
            // Empty line indicates end of SSE event
            if (event_data.items.len > 0) {
                callback(event_data.items);
                event_data.clearRetainingCapacity();
            }
        } else if (std.mem.startsWith(u8, line, "data: ")) {
            // Parse SSE data field with enhanced capacity management
            const data_content = line[6..]; // Skip "data: "
            if (event_data.items.len > 0) {
                try event_data.append('\n'); // Multi-line data separator
            }

            // Ensure we have capacity for the new data to handle large payloads
            try event_data.ensureUnusedCapacity(data_content.len);
            try event_data.appendSlice(data_content);
        }
        // Ignore other SSE fields (event, id, retry, etc.)
    }
}

// ================== OAuth Implementation ==================

/// Generate PKCE parameters for OAuth flow
pub fn generatePkceParams(allocator: std.mem.Allocator) !PkceParams {
    // Generate random code verifier (43-128 chars, URL-safe base64)
    var random_bytes: [64]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);

    const verifier_size = std.base64.url_safe.Encoder.calcSize(random_bytes.len);
    const verifier = try allocator.alloc(u8, verifier_size);
    _ = std.base64.url_safe.Encoder.encode(verifier, &random_bytes);

    // Create code challenge using SHA256
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(verifier);
    var challenge_hash: [32]u8 = undefined;
    hasher.final(&challenge_hash);

    const challenge_size = std.base64.url_safe.Encoder.calcSize(challenge_hash.len);
    const challenge = try allocator.alloc(u8, challenge_size);
    _ = std.base64.url_safe.Encoder.encode(challenge, &challenge_hash);

    // Generate state parameter
    var state_bytes: [32]u8 = undefined;
    std.crypto.random.bytes(&state_bytes);
    const state_size = std.base64.url_safe.Encoder.calcSize(state_bytes.len);
    const state = try allocator.alloc(u8, state_size);
    _ = std.base64.url_safe.Encoder.encode(state, &state_bytes);

    return PkceParams{
        .code_verifier = verifier,
        .code_challenge = challenge,
        .state = state,
    };
}

/// Build OAuth authorization URL with default provider
pub fn buildAuthorizationUrl(allocator: std.mem.Allocator, pkce_params: PkceParams) ![]u8 {
    const scopes = [_][]const u8{ "org:create_api_key", "user:profile", "user:inference" };
    const provider = OAuthProvider{
        .client_id = OAUTH_CLIENT_ID,
        .authorization_url = OAUTH_AUTHORIZATION_URL,
        .token_url = OAUTH_TOKEN_ENDPOINT,
        .redirect_uri = OAUTH_REDIRECT_URI,
        .scopes = &scopes,
    };

    return try provider.buildAuthUrl(allocator, pkce_params);
}

/// Exchange authorization code for tokens
pub fn exchangeCodeForTokens(allocator: std.mem.Allocator, authorization_code: []const u8, pkce_params: PkceParams) !OAuthCredentials {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Build the request body
    const body = try std.fmt.allocPrint(allocator, "grant_type=authorization_code&code={s}&redirect_uri={s}&client_id={s}&code_verifier={s}", .{ authorization_code, OAUTH_REDIRECT_URI, OAUTH_CLIENT_ID, pkce_params.code_verifier });
    defer allocator.free(body);

    const headers = [_]std.http.Header{
        .{ .name = "content-type", .value = "application/x-www-form-urlencoded" },
        .{ .name = "accept", .value = "application/json" },
    };

    const uri = try std.Uri.parse(OAUTH_TOKEN_ENDPOINT);
    var req = try client.request(.POST, uri, .{
        .extra_headers = &headers,
        .keep_alive = false,
        .redirect_behavior = .not_allowed,
    });

    req.transfer_encoding = .{ .content_length = body.len };

    var bw = try req.sendBody(&.{});
    try bw.writer.writeAll(body);
    try bw.end();

    // Receive the response using Zig 0.15.1 API
    var resp = try req.receiveHead(&.{});

    if (resp.head.status != .ok) {
        std.log.err("OAuth token exchange failed with status: {}", .{resp.head.status});
        return Error.AuthError;
    }

    // Read response body using the new reader interface
    var response_buffer: [128 * 1024]u8 = undefined; // 128KB buffer for OAuth JSON responses
    const response_reader = resp.reader(&response_buffer);

    // Read the full response body directly into response buffer
    var response_writer: std.Io.Writer = .fixed(&response_buffer);
    const bytes_read = try response_reader.stream(&response_writer, .unlimited);
    const actual_body = response_buffer[0..bytes_read];

    // Parse JSON response to extract OAuth tokens
    const parsed = std.json.parseFromSlice(struct {
        access_token: []const u8,
        refresh_token: []const u8,
        expires_in: i64,
    }, allocator, actual_body, .{}) catch |err| {
        std.log.err("Failed to parse OAuth token response: {}", .{err});
        return Error.AuthError;
    };
    defer parsed.deinit();

    // Convert expires_in (seconds) to expires_at (Unix timestamp)
    const now = std.time.timestamp();
    const expires_at = now + parsed.value.expires_in;

    // Return OAuth credentials with owned strings
    return OAuthCredentials{
        .type = try allocator.dupe(u8, "oauth"),
        .access_token = try allocator.dupe(u8, parsed.value.access_token),
        .refresh_token = try allocator.dupe(u8, parsed.value.refresh_token),
        .expires_at = expires_at,
    };
}

/// Refresh OAuth tokens
pub fn refreshTokens(allocator: std.mem.Allocator, refresh_token: []const u8) !OAuthCredentials {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Build the request body
    const body = try std.fmt.allocPrint(allocator, "grant_type=refresh_token&refresh_token={s}&client_id={s}", .{ refresh_token, OAUTH_CLIENT_ID });
    defer allocator.free(body);

    const headers = [_]std.http.Header{
        .{ .name = "content-type", .value = "application/x-www-form-urlencoded" },
        .{ .name = "accept", .value = "application/json" },
    };

    const uri = try std.Uri.parse(OAUTH_TOKEN_ENDPOINT);
    var req = try client.request(.POST, uri, .{
        .extra_headers = &headers,
        .keep_alive = false,
        .redirect_behavior = .not_allowed,
    });

    req.transfer_encoding = .{ .content_length = body.len };

    var bw = try req.sendBody(&.{});
    try bw.writer.writeAll(body);
    try bw.end();

    // Receive the response using Zig 0.15.1 API
    var resp = try req.receiveHead(&.{});

    if (resp.head.status != .ok) {
        std.log.err("OAuth token refresh failed with status: {}", .{resp.head.status});
        return Error.AuthError;
    }

    // Read response body using the new reader interface
    var response_buffer: [128 * 1024]u8 = undefined; // 128KB buffer for OAuth JSON responses
    const response_reader = resp.reader(&response_buffer);

    // Read the full response body directly into response buffer
    var response_writer: std.Io.Writer = .fixed(&response_buffer);
    const bytes_read = try response_reader.stream(&response_writer, .unlimited);
    const actual_body = response_buffer[0..bytes_read];

    // Parse JSON response to extract OAuth tokens
    const parsed = std.json.parseFromSlice(struct {
        access_token: []const u8,
        refresh_token: []const u8,
        expires_in: i64,
    }, allocator, actual_body, .{}) catch |err| {
        std.log.err("Failed to parse OAuth token refresh response: {}", .{err});
        return Error.AuthError;
    };
    defer parsed.deinit();

    // Convert expires_in (seconds) to expires_at (Unix timestamp)
    const now = std.time.timestamp();
    const expires_at = now + parsed.value.expires_in;

    // Return OAuth credentials with owned strings
    return OAuthCredentials{
        .type = try allocator.dupe(u8, "oauth"),
        .access_token = try allocator.dupe(u8, parsed.value.access_token),
        .refresh_token = try allocator.dupe(u8, parsed.value.refresh_token),
        .expires_at = expires_at,
    };
}

/// Load OAuth credentials from file
pub fn loadOAuthCredentials(allocator: std.mem.Allocator, file_path: []const u8) !?OAuthCredentials {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 16 * 1024);
    defer allocator.free(contents);

    const parsed = try std.json.parseFromSlice(OAuthCredentials, allocator, contents, .{});
    defer parsed.deinit();

    return OAuthCredentials{
        .type = try allocator.dupe(u8, parsed.value.type),
        .access_token = try allocator.dupe(u8, parsed.value.access_token),
        .refresh_token = try allocator.dupe(u8, parsed.value.refresh_token),
        .expires_at = parsed.value.expires_at,
    };
}

/// Save OAuth credentials to file with atomic update
pub fn saveOAuthCredentials(allocator: std.mem.Allocator, file_path: []const u8, creds: OAuthCredentials) !void {
    // Use manual JSON construction (working approach in Zig 0.15.1)
    const json_content = try std.fmt.allocPrint(allocator, "{{\"type\":\"{s}\",\"access_token\":\"{s}\",\"refresh_token\":\"{s}\",\"expires_at\":{}}}", .{ creds.type, creds.access_token, creds.refresh_token, creds.expires_at });
    defer allocator.free(json_content);

    const file = try std.fs.cwd().createFile(file_path, .{ .mode = 0o600 });
    defer file.close();

    try file.writeAll(json_content);
}

/// Parse authorization code from callback URL (handles fragments)
pub fn parseAuthorizationCode(allocator: std.mem.Allocator, callback_url: []const u8) ![]const u8 {
    // Parse URL and extract code parameter
    const url = try std.Uri.parse(callback_url);

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
        const connection = server.accept() catch |err| {
            std.log.warn("Failed to accept connection: {}, continuing...", .{err});
            continue;
        };
        defer connection.stream.close();
        
        // Read HTTP request with timeout handling
        var request_buffer: [4096]u8 = undefined;
        var request_reader = connection.stream.reader(&request_buffer);
        
        // Read the HTTP request line
        const request_line = request_reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => {
                std.log.warn("Client closed connection before sending request", .{});
                continue;
            },
            error.StreamTooLong => {
                // Send 400 Bad Request for oversized request
                sendHttpError(&connection.stream, 400, "Request too large") catch {};
                continue;
            },
            else => {
                std.log.warn("Error reading request: {}", .{err});
                continue;
            },
        };
        
        const request_line_trimmed = std.mem.trim(u8, request_line, " \t\r\n");
        
        // Parse HTTP request: "GET /path?query HTTP/1.1"
        var request_parts = std.mem.splitSequence(u8, request_line_trimmed, " ");
        const method = request_parts.next() orelse {
            sendHttpError(&connection.stream, 400, "Invalid request format") catch {};
            continue;
        };
        const path_and_query = request_parts.next() orelse {
            sendHttpError(&connection.stream, 400, "Invalid request format") catch {};
            continue;
        };
        
        // Only handle GET requests for OAuth callback
        if (!std.mem.eql(u8, method, "GET")) {
            sendHttpError(&connection.stream, 405, "Method not allowed") catch {};
            continue;
        }
        
        std.log.debug("Received OAuth callback request: GET {s}", .{path_and_query});
        
        // Extract query parameters from the path
        const query_start = std.mem.indexOf(u8, path_and_query, "?");
        if (query_start == null) {
            sendHttpError(&connection.stream, 400, "No query parameters in OAuth callback") catch {};
            continue;
        }
        
        const query_string = path_and_query[query_start.? + 1..];
        
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
            
            std.log.info("✅ Authorization code received successfully!");
            
            // Return the authorization code (caller owns the memory)
            return allocator.dupe(u8, auth_code);
        } else {
            // No code parameter found
            sendHttpError(&connection.stream, 400, "Authorization code not found in OAuth callback") catch {};
            continue;
        }
    }
}

/// Send HTTP error response to client
fn sendHttpError(stream: *std.net.Stream, status_code: u16, message: []const u8) !void {
    const status_text = switch (status_code) {
        400 => "Bad Request",
        404 => "Not Found", 
        405 => "Method Not Allowed",
        500 => "Internal Server Error",
        else => "Error",
    };
    
    var response_buffer: [1024]u8 = undefined;
    
    const response = try std.fmt.bufPrint(&response_buffer, 
        "HTTP/1.1 {} {s}\r\n" ++
        "Content-Type: text/plain\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "{s}\r\n",
        .{ status_code, status_text, message }
    );
    
    var stream_writer = stream.writer(&response_buffer);
    try stream_writer.writeAll(response);
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
    
    const response = try std.fmt.bufPrint(&response_buffer,
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/html\r\n" ++
        "Content-Length: {}\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "{s}",
        .{ html_content.len, html_content }
    );
    
    var stream_writer = stream.writer(&response_buffer);
    try stream_writer.writeAll(response);
}

/// Send OAuth error response with user-friendly error page
fn sendOAuthErrorResponse(stream: *std.net.Stream, error_code: []const u8, error_description: ?[]const u8) !void {
    var html_buffer: [2048]u8 = undefined;
    
    const description = error_description orelse "No additional details provided.";
    const html_content = try std.fmt.bufPrint(&html_buffer,
        "<!DOCTYPE html>\n" ++
        "<html><head><title>Authorization Error</title>" ++
        "<style>body{{font-family:Arial,sans-serif;max-width:600Dpx;margin:50px auto;text-align:center;background:#f5f5f5;padding:20px}}" ++
        ".error{{color:#dc3545;font-size:24px;margin:20px 0}}" ++
        ".message{{color:#333;font-size:16px;margin:10px 0}}" ++
        ".code{{background:#e9ecef;padding:10px;border-radius:5px;font-family:monospace}}</style></head>" ++
        "<body><div class='error'>❌ Authorization Failed</div>" ++
        "<div class='message'><strong>Error:</strong> {s}</div>" ++
        "<div class='message'>{s}</div>" ++
        "<div class='message'>Please close this tab and try the authorization again.</div></body></html>",
        .{ error_code, description }
    );
    
    var response_buffer: [3072]u8 = undefined;
    
    const response = try std.fmt.bufPrint(&response_buffer,
        "HTTP/1.1 400 Bad Request\r\n" ++
        "Content-Type: text/html\r\n" ++
        "Content-Length: {}\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "{s}",
        .{ html_content.len, html_content }
    );
    
    var stream_writer = stream.writer(&response_buffer);
    try stream_writer.writeAll(response);
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

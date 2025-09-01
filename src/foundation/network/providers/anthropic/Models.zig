//! Anthropic models and core types

const std = @import("std");

pub const MessageRole = enum { system, user, assistant, tool };

/// Content blocks (Anthropic-style)
pub const ContentBlock = union(enum) {
    /// {"type":"text","text": "..."}
    text: struct { text: []const u8 },
    /// {"type":"tool_use","id":"...","name":"...","input":{...}}
    /// `input_json` must be a valid JSON object string; we write it raw (no extra quoting).
    tool_use: struct { id: []const u8, name: []const u8, input_json: []const u8 },
    /// {"type":"tool_result","tool_use_id":"...","content":"...","is_error":true?}
    tool_result: struct { tool_use_id: ?[]const u8 = null, content: []const u8, is_error: bool = false },
};

/// A message can be a single text string, or a list of blocks.
pub const MessageContent = union(enum) {
    text: []const u8,
    blocks: []const ContentBlock,
};

pub const Message = struct {
    role: MessageRole,
    content: MessageContent,
};

/// Helpers (role → string)
pub fn roleString(role: MessageRole) []const u8 {
    return switch (role) {
        .system => "system",
        .user => "user",
        .assistant => "assistant",
        .tool => "tool",
    };
}

/// JSON writers (no heap, write directly to a writer)
fn writeJSONString(w: anytype, s: []const u8) !void {
    try w.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    var buf: [6]u8 = .{ '\\', 'u', '0', '0', 0, 0 };
                    const HEX = "0123456789abcdef";
                    buf[4] = HEX[(c >> 4) & 0xF];
                    buf[5] = HEX[c & 0xF];
                    try w.writeAll(&buf);
                } else {
                    try w.writeByte(c);
                }
            },
        }
    }
    try w.writeByte('"');
}

fn writeContentBlock(w: anytype, b: ContentBlock) !void {
    switch (b) {
        .text => |tb| {
            try w.writeAll("{\"type\":\"text\",\"text\":");
            try writeJSONString(w, tb.text);
            try w.writeByte('}');
        },
        .tool_use => |tu| {
            try w.writeAll("{\"type\":\"tool_use\",\"id\":");
            try writeJSONString(w, tu.id);
            try w.writeAll(",\"name\":");
            try writeJSONString(w, tu.name);
            try w.writeAll(",\"input\":");
            // Raw JSON (assumed valid)
            try w.writeAll(tu.input_json);
            try w.writeByte('}');
        },
        .tool_result => |tr| {
            try w.writeAll("{\"type\":\"tool_result\"");
            if (tr.tool_use_id) |tid| {
                try w.writeAll(",\"tool_use_id\":");
                try writeJSONString(w, tid);
            }
            if (tr.is_error) try w.writeAll(",\"is_error\":true");
            try w.writeAll(",\"content\":");
            try writeJSONString(w, tr.content);
            try w.writeByte('}');
        },
    }
}

/// Write a single message as an API wire object ("{\"role\":\"...\",\"content\": ...}").
pub fn writeWireMessage(w: anytype, msg: Message) !void {
    try w.writeAll("{\"role\":\"");
    try w.writeAll(roleString(msg.role));
    try w.writeAll("\",\"content\":");
    switch (msg.content) {
        .text => |t| {
            // Anthropic v1 requires content blocks; wrap plain text in a single text block
            try w.writeByte('[');
            try writeContentBlock(w, .{ .text = .{ .text = t } });
            try w.writeByte(']');
        },
        .blocks => |bs| {
            try w.writeByte('[');
            var first = true;
            for (bs) |b| {
                if (!first) try w.writeByte(',');
                first = false;
                try writeContentBlock(w, b);
            }
            try w.writeByte(']');
        },
    }
    try w.writeByte('}');
}

/// Write an array of messages for the request body: `[ {role,content}, ... ]`
pub fn writeWireMessages(w: anytype, msgs: []const Message) !void {
    try w.writeByte('[');
    var first = true;
    for (msgs) |m| {
        if (!first) try w.writeByte(',');
        first = false;
        try writeWireMessage(w, m);
    }
    try w.writeByte(']');
}

/// Free a Message's owned memory (strings/slices inside). Assumes all slices were duped by the allocator.
pub fn freeMessage(allocator: std.mem.Allocator, msg: *Message) void {
    switch (msg.content) {
        .text => |t| allocator.free(t),
        .blocks => |bs| {
            for (bs) |b| switch (b) {
                .text => |tb| allocator.free(tb.text),
                .tool_use => |tu| {
                    allocator.free(tu.id);
                    allocator.free(tu.name);
                    allocator.free(tu.input_json);
                },
                .tool_result => |tr| {
                    if (tr.tool_use_id) |tid| allocator.free(tid);
                    allocator.free(tr.content);
                },
            };
            allocator.free(bs);
        },
    }
    // Reset to safe state
    msg.* = .{ .role = msg.role, .content = .{ .text = "" } };
}

/// Convenience: create a role=tool message with a single tool_result block
pub fn makeToolResultMessage(
    allocator: std.mem.Allocator,
    tool_use_id: ?[]const u8,
    content: []const u8,
    is_error: bool,
) !Message {
    var blocks = try allocator.alloc(ContentBlock, 1);
    blocks[0] = .{ .tool_result = .{
        .tool_use_id = if (tool_use_id) |tid| try allocator.dupe(u8, tid) else null,
        .content = try allocator.dupe(u8, content),
        .is_error = is_error,
    } };
    return .{ .role = .tool, .content = .{ .blocks = blocks } };
}

/// OAuth credentials stored to disk
pub const Credentials = struct {
    type: []const u8, // Always "oauth"
    accessToken: []const u8,
    refreshToken: []const u8,
    expiresAt: i64, // Unix timestamp

    pub fn isExpired(self: Credentials) bool {
        const now = std.time.timestamp();
        return now >= self.expiresAt;
    }

    pub fn willExpireSoon(self: Credentials, leeway: i64) bool {
        const now = std.time.timestamp();
        return now + leeway >= self.expiresAt;
    }
};

/// PKCE parameters for OAuth flow
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
    clientId: []const u8,
    authorizationUrl: []const u8,
    tokenUrl: []const u8,
    redirectUri: []const u8,
    scopes: []const []const u8,

    pub fn buildAuthUrl(self: OAuthProvider, allocator: std.mem.Allocator, pkceParams: Pkce) ![]u8 {
        // Percent-encode each query value (RFC 3986 unreserved set)
        var buf = std.ArrayList(u8){};
        errdefer buf.deinit(allocator);
        const w = buf.writer(allocator);
        try w.print("{s}?client_id=", .{self.authorizationUrl});
        try writePctEncoded(w, self.clientId);
        try w.writeAll("&response_type=code&redirect_uri=");
        try writePctEncoded(w, self.redirectUri);
        try w.writeAll("&scope=");
        const scopesJoined = try std.mem.join(allocator, " ", self.scopes);
        defer allocator.free(scopesJoined);
        try writePctEncoded(w, scopesJoined);
        try w.writeAll("&code_challenge=");
        try writePctEncoded(w, pkceParams.codeChallenge);
        try w.writeAll("&code_challenge_method=S256&state=");
        try writePctEncoded(w, pkceParams.state);
        return try buf.toOwnedSlice(allocator);
    }
};

inline fn isUnreserved(b: u8) bool {
    return (b >= 'A' and b <= 'Z') or
        (b >= 'a' and b <= 'z') or
        (b >= '0' and b <= '9') or
        b == '-' or b == '.' or b == '_' or b == '~';
}

fn writePctEncoded(w: anytype, s: []const u8) !void {
    const HEX = "0123456789ABCDEF";
    for (s) |b| {
        if (isUnreserved(b)) {
            try w.writeByte(b);
        } else {
            var out: [3]u8 = .{ '%', 0, 0 };
            out[1] = HEX[(b >> 4) & 0xF];
            out[2] = HEX[b & 0xF];
            try w.writeAll(&out);
        }
    }
}

/// Token refresh state to prevent concurrent refreshes
pub const RefreshLock = struct {
    mutex: std.Thread.Mutex,
    inProgress: bool,

    pub fn init() RefreshLock {
        return .{ .mutex = .{}, .inProgress = false };
    }
    pub fn acquire(self: *RefreshLock) void {
        self.mutex.lock();
        self.inProgress = true;
    }
    pub fn release(self: *RefreshLock) void {
        self.inProgress = false;
        self.mutex.unlock();
    }
};

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
    .{ "claude-opus-4-1", ModelRates{ .inputRate = 15.0, .outputRate = 75.0 } },
    .{ "claude-opus-4-20250514", ModelRates{ .inputRate = 15.0, .outputRate = 75.0 } },
    .{ "claude-opus-4-0", ModelRates{ .inputRate = 15.0, .outputRate = 75.0 } },
    .{ "claude-sonnet-4-20250514", ModelRates{ .inputRate = 3.0, .outputRate = 15.0 } },
    .{ "claude-sonnet-4-0", ModelRates{ .inputRate = 3.0, .outputRate = 15.0 } },
    .{ "claude-3-7-sonnet-20250219", ModelRates{ .inputRate = 3.0, .outputRate = 15.0 } },
    .{ "claude-3-7-sonnet-latest", ModelRates{ .inputRate = 3.0, .outputRate = 15.0 } },
    .{ "claude-3-5-haiku-20241022", ModelRates{ .inputRate = 0.80, .outputRate = 4.0 } },
    .{ "claude-3-5-haiku-latest", ModelRates{ .inputRate = 0.80, .outputRate = 4.0 } },
    .{ "claude-3-haiku-20240307", ModelRates{ .inputRate = 0.25, .outputRate = 1.25 } },

    // Legacy/Deprecated Models
    .{ "claude-3-5-sonnet-20241022", ModelRates{ .inputRate = 3.0, .outputRate = 15.0 } },
    .{ "claude-3-5-sonnet-20240620", ModelRates{ .inputRate = 3.0, .outputRate = 15.0 } },
    .{ "claude-3-opus-20240229", ModelRates{ .inputRate = 15.0, .outputRate = 75.0 } },
});

/// Default pricing for unknown models (uses Sonnet 4 rates)
const default_pricing = ModelRates{ .inputRate = 3.0, .outputRate = 15.0 };

/// Cost calculation structure with Pro/Max override support
pub const CostCalculator = struct {
    isOauthSession: bool,

    pub fn init(isOauth: bool) CostCalculator {
        return CostCalculator{ .isOauthSession = isOauth };
    }

    fn getModelPricing(model: []const u8) ModelRates {
        return model_pricing.get(model) orelse default_pricing;
    }

    pub fn calculateInputCost(self: CostCalculator, tokens: u32, model: []const u8) f64 {
        if (self.isOauthSession) return 0.0;
        const pricing = getModelPricing(model);
        return @as(f64, @floatFromInt(tokens)) * pricing.getInputCostPerToken();
    }

    pub fn calculateOutputCost(self: CostCalculator, tokens: u32, model: []const u8) f64 {
        if (self.isOauthSession) return 0.0;
        const pricing = getModelPricing(model);
        return @as(f64, @floatFromInt(tokens)) * pricing.getOutputCostPerToken();
    }

    pub fn getPricingMode(self: CostCalculator) []const u8 {
        return if (self.isOauthSession) "Subscription (Free)" else "Pay-per-use";
    }

    pub fn getModelRates(self: CostCalculator, model: []const u8) ModelRates {
        _ = self;
        return getModelPricing(model);
    }
};

/// Error set for client operations.
pub const Error = error{
    MissingAPIKey,
    APIError,
    AuthError,
    TokenExpired,
    OutOfMemory,
    InvalidFormat,
    InvalidPort,
    UnexpectedCharacter,
    InvalidGrant,
    NetworkError,
    RefreshInProgress,
    ChunkParseError,
    MalformedChunk,
    InvalidChunkSize,
    PayloadTooLarge,
    StreamingFailed,
    BufferOverflow,
    ChunkProcessingFailed,
    // OAuth and network related errors
    WriteFailed,
    ReadFailed,
    EndOfStream,
    ConnectionResetByPeer,
    ConnectionTimedOut,
    NetworkUnreachable,
    ConnectionRefused,
    TemporaryNameServerFailure,
    NameServerFailure,
    UnknownHostName,
    HostLacksNetworkAddresses,
    UnexpectedConnectFailure,
    TlsInitializationFailed,
    UnsupportedURIScheme,
    URIMissingHost,
    URIHostTooLong,
    CertificateBundleLoadFailure,
    // HTTP protocol errors
    HTTPChunkInvalid,
    HTTPChunkTruncated,
    HTTPHeadersOversize,
    HTTPRequestTruncated,
    HTTPConnectionClosing,
    HTTPHeadersInvalid,
    TooManyHttpRedirects,
    RedirectRequiresResend,
    HTTPRedirectLocationMissing,
    HTTPRedirectLocationOversize,
    HTTPRedirectLocationInvalid,
    HTTPContentEncodingUnsupported,
    // Buffer errors
    NoSpaceLeft,
    StreamTooLong,
};

pub const Stream = struct {
    model: []const u8,
    maxTokens: usize = 256,
    temperature: f32 = 0.7,
    messages: []const Message,
    system: ?[]const u8 = null,
    /// Optional per-token callback with user context pointer.
    onToken: ?*const fn (?*anyopaque, []const u8) void = null,
    user_ctx: ?*anyopaque = null,
};

pub const CompletionResult = struct {
    content: []const u8,
    usage: Usage,
    allocator: std.mem.Allocator,

    /// Content is owned by the caller/collector; nothing to free here.
    pub fn deinit(self: *CompletionResult) void {
        _ = self;
    }
};

pub const Usage = struct {
    inputTokens: u32 = 0,
    outputTokens: u32 = 0,
};

pub const Complete = struct {
    model: []const u8,
    maxTokens: usize = 256,
    temperature: f32 = 0.7,
    messages: []const Message,
    system: ?[]const u8 = null,
};

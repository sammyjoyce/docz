//! Anthropic models and core types

const std = @import("std");

pub const MessageRole = enum { system, user, assistant, tool };

pub const Message = struct {
    role: MessageRole,
    content: []const u8,
};

/// OAuth credentials stored to disk
pub const OAuthCredentials = struct {
    type: []const u8, // Always "oauth"
    access_token: []const u8,
    refresh_token: []const u8,
    expires_at: i64, // Unix timestamp

    pub fn isExpired(self: OAuthCredentials) bool {
        const now = std.time.timestamp();
        return now >= self.expires_at;
    }

    pub fn willExpireSoon(self: OAuthCredentials, leeway: i64) bool {
        const now = std.time.timestamp();
        return now + leeway >= self.expires_at;
    }
};

/// PKCE parameters for OAuth flow
pub const Pkce = struct {
    code_verifier: []const u8,
    code_challenge: []const u8,
    state: []const u8,

    /// Clean up allocated memory
    pub fn deinit(self: Pkce, allocator: std.mem.Allocator) void {
        allocator.free(self.code_verifier);
        allocator.free(self.code_challenge);
        allocator.free(self.state);
    }
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

    pub fn buildAuthURL(self: OAuthProvider, allocator: std.mem.Allocator, pkce_params: Pkce) ![]u8 {
        const scopes_joined = try std.mem.join(allocator, " ", self.scopes);
        defer allocator.free(scopes_joined);
        return try std.fmt.allocPrint(
            allocator,
            "{s}?client_id={s}&response_type=code&redirect_uri={s}&scope={s}&code_challenge={s}&code_challenge_method=S256&state={s}",
            .{ self.authorization_url, self.client_id, self.redirect_uri, scopes_joined, pkce_params.code_challenge, pkce_params.state },
        );
    }
};

/// Token refresh state to prevent concurrent refreshes
pub const RefreshState = struct {
    mutex: std.Thread.Mutex,
    in_progress: bool,

    pub fn init() RefreshState {
        return .{ .mutex = .{}, .in_progress = false };
    }
};

/// Model pricing information (rates per million tokens)
pub const ModelPricing = struct {
    input_rate: f64, // Rate per million input tokens
    output_rate: f64, // Rate per million output tokens

    pub fn getInputCostPerToken(self: ModelPricing) f64 {
        return self.input_rate / 1_000_000.0;
    }

    pub fn getOutputCostPerToken(self: ModelPricing) f64 {
        return self.output_rate / 1_000_000.0;
    }
};

/// Anthropic API pricing table (updated as of August 2025)
const MODEL_PRICING = std.StaticStringMap(ModelPricing).initComptime(.{
    // Current Models
    .{ "claude-opus-4-1-20250805", ModelPricing{ .input_rate = 15.0, .output_rate = 75.0 } },
    .{ "claude-opus-4-1", ModelPricing{ .input_rate = 15.0, .output_rate = 75.0 } },
    .{ "claude-opus-4-20250514", ModelPricing{ .input_rate = 15.0, .output_rate = 75.0 } },
    .{ "claude-opus-4-0", ModelPricing{ .input_rate = 15.0, .output_rate = 75.0 } },
    .{ "claude-sonnet-4-20250514", ModelPricing{ .input_rate = 3.0, .output_rate = 15.0 } },
    .{ "claude-sonnet-4-0", ModelPricing{ .input_rate = 3.0, .output_rate = 15.0 } },
    .{ "claude-3-7-sonnet-20250219", ModelPricing{ .input_rate = 3.0, .output_rate = 15.0 } },
    .{ "claude-3-7-sonnet-latest", ModelPricing{ .input_rate = 3.0, .output_rate = 15.0 } },
    .{ "claude-3-5-haiku-20241022", ModelPricing{ .input_rate = 0.80, .output_rate = 4.0 } },
    .{ "claude-3-5-haiku-latest", ModelPricing{ .input_rate = 0.80, .output_rate = 4.0 } },
    .{ "claude-3-haiku-20240307", ModelPricing{ .input_rate = 0.25, .output_rate = 1.25 } },

    // Legacy/Deprecated Models
    .{ "claude-3-5-sonnet-20241022", ModelPricing{ .input_rate = 3.0, .output_rate = 15.0 } },
    .{ "claude-3-5-sonnet-20240620", ModelPricing{ .input_rate = 3.0, .output_rate = 15.0 } },
    .{ "claude-3-opus-20240229", ModelPricing{ .input_rate = 15.0, .output_rate = 75.0 } },
});

/// Default pricing for unknown models (uses Sonnet 4 rates)
const DEFAULT_PRICING = ModelPricing{ .input_rate = 3.0, .output_rate = 15.0 };

/// Cost calculation structure with Pro/Max override support
pub const CostCalculator = struct {
    is_oauth_session: bool,

    pub fn init(is_oauth: bool) CostCalculator {
        return .{ .is_oauth_session = is_oauth };
    }

    fn getModelPricing(model: []const u8) ModelPricing {
        return MODEL_PRICING.get(model) orelse DEFAULT_PRICING;
    }

    pub fn calculateInputCost(self: CostCalculator, tokens: u32, model: []const u8) f64 {
        if (self.is_oauth_session) return 0.0;
        const pricing = getModelPricing(model);
        return @as(f64, @floatFromInt(tokens)) * pricing.getInputCostPerToken();
    }

    pub fn calculateOutputCost(self: CostCalculator, tokens: u32, model: []const u8) f64 {
        if (self.is_oauth_session) return 0.0;
        const pricing = getModelPricing(model);
        return @as(f64, @floatFromInt(tokens)) * pricing.getOutputCostPerToken();
    }

    pub fn getPricingMode(self: CostCalculator) []const u8 {
        return if (self.is_oauth_session) "Subscription (Free)" else "Pay-per-use";
    }

    pub fn getModelPricingInfo(self: CostCalculator, model: []const u8) ModelPricing {
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
    max_tokens: usize = 256,
    temperature: f32 = 0.7,
    messages: []const Message,
    on_token: *const fn ([]const u8) void,
};

pub const CompletionResponse = struct {
    content: []const u8,
    usage: Usage,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CompletionResponse, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // Content is owned by the collector, which will be freed separately
    }
};

pub const Usage = struct {
    input_tokens: u32 = 0,
    output_tokens: u32 = 0,
};

pub const Complete = struct {
    model: []const u8,
    max_tokens: usize = 256,
    temperature: f32 = 0.7,
    messages: []const Message,
};

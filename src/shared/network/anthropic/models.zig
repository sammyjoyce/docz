//! Anthropic models and core types

const std = @import("std");

pub const MessageRole = enum { system, user, assistant, tool };

pub const Message = struct {
    role: MessageRole,
    content: []const u8,
};

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

    pub fn buildAuthURL(self: OAuthProvider, allocator: std.mem.Allocator, pkceParams: Pkce) ![]u8 {
        const scopesJoined = try std.mem.join(allocator, " ", self.scopes);
        defer allocator.free(scopesJoined);
        return try std.fmt.allocPrint(
            allocator,
            "{s}?client_id={s}&response_type=code&redirect_uri={s}&scope={s}&code_challenge={s}&code_challenge_method=S256&state={s}",
            .{ self.authorizationUrl, self.clientId, self.redirectUri, scopesJoined, pkceParams.codeChallenge, pkceParams.state },
        );
    }
};

/// Token refresh state to prevent concurrent refreshes
pub const RefreshLock = struct {
    mutex: std.Thread.Mutex,
    inProgress: bool,

    pub fn init() RefreshLock {
        return .{ .mutex = .{}, .inProgress = false };
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
pub const CostCalc = struct {
    isOauthSession: bool,

    pub fn init(isOauth: bool) CostCalc {
        return CostCalc{ .isOauthSession = isOauth };
    }

    fn getModelPricing(model: []const u8) ModelRates {
        return model_pricing.get(model) orelse default_pricing;
    }

    pub fn calculateInputCost(self: CostCalc, tokens: u32, model: []const u8) f64 {
        if (self.isOauthSession) return 0.0;
        const pricing = getModelPricing(model);
        return @as(f64, @floatFromInt(tokens)) * pricing.getInputCostPerToken();
    }

    pub fn calculateOutputCost(self: CostCalc, tokens: u32, model: []const u8) f64 {
        if (self.isOauthSession) return 0.0;
        const pricing = getModelPricing(model);
        return @as(f64, @floatFromInt(tokens)) * pricing.getOutputCostPerToken();
    }

    pub fn getPricingMode(self: CostCalc) []const u8 {
        return if (self.isOauthSession) "Subscription (Free)" else "Pay-per-use";
    }

    pub fn getModelPricingInfo(self: CostCalc, model: []const u8) ModelRates {
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
    onToken: *const fn ([]const u8) void,
};

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

pub const Complete = struct {
    model: []const u8,
    maxTokens: usize = 256,
    temperature: f32 = 0.7,
    messages: []const Message,
};

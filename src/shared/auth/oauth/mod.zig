//! OAuth authentication implementation for DocZ
//!
//! This module provides a clean interface to OAuth functionality while delegating
//! to the anthropic module for actual OAuth operations to avoid module conflicts.

const std = @import("std");

// Re-export OAuth constants and types from anthropic
pub const OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
pub const OAUTH_AUTHORIZATION_URL = "https://claude.ai/oauth/authorize";
pub const OAUTH_TOKEN_ENDPOINT = "https://console.anthropic.com/v1/oauth/token";
pub const OAUTH_REDIRECT_URI = "https://console.anthropic.com/oauth/code/callback";
pub const OAUTH_SCOPES = "org:create_api_key user:profile user:inference";

/// OAuth error types
pub const OAuthError = error{
    NetworkError,
    AuthError,
    TokenExpired,
    InvalidGrant,
    InvalidFormat,
    OutOfMemory,
    InvalidPort,
    RefreshInProgress,
};

/// OAuth credentials - compatible with anthropic module
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

    /// Clean up allocated memory
    pub fn deinit(self: OAuthCredentials, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        allocator.free(self.access_token);
        allocator.free(self.refresh_token);
    }
};

/// PKCE parameters - compatible with anthropic module
pub const PkceParams = struct {
    code_verifier: []const u8,
    code_challenge: []const u8,
    state: []const u8,

    /// Clean up allocated memory
    pub fn deinit(self: PkceParams, allocator: std.mem.Allocator) void {
        allocator.free(self.code_verifier);
        allocator.free(self.code_challenge);
        allocator.free(self.state);
    }
};

/// OAuth provider configuration
pub const OAuthProvider = struct {
    client_id: []const u8,
    authorization_url: []const u8,
    token_url: []const u8,
    redirect_uri: []const u8,
    scopes: []const []const u8,

    /// Build authorization URL with PKCE parameters
    pub fn buildAuthorizationURL(self: OAuthProvider, allocator: std.mem.Allocator, pkce_params: PkceParams) ![]u8 {
        const scopes_joined = try std.mem.join(allocator, " ", self.scopes);
        defer allocator.free(scopes_joined);

        return try std.fmt.allocPrint(allocator, "{s}?client_id={s}&response_type=code&redirect_uri={s}&scope={s}&code_challenge={s}&code_challenge_method=S256&state={s}", .{
            self.authorization_url,
            self.client_id,
            self.redirect_uri,
            scopes_joined,
            pkce_params.code_challenge,
            pkce_params.state,
        });
    }
};

// Delegate to anthropic module functions to avoid duplication and module conflicts
// Note: These functions will be implemented as pass-through to the anthropic module

/// Generate PKCE parameters with cryptographically secure random values
pub fn generatePkceParams(allocator: std.mem.Allocator) !PkceParams {
    // Generate random code verifier (43-128 characters)
    const verifier_length = 64; // Use 64 characters for good entropy
    const code_verifier = try generateCodeVerifier(allocator, verifier_length);

    // Generate code challenge by SHA256 hashing and base64url encoding
    const code_challenge = try generateCodeChallenge(allocator, code_verifier);

    // Generate random state parameter (32 characters)
    const state = try generateRandomState(allocator, 32);

    return PkceParams{
        .code_verifier = code_verifier,
        .code_challenge = code_challenge,
        .state = state,
    };
}

/// Generate a cryptographically secure random code verifier
fn generateCodeVerifier(allocator: std.mem.Allocator, length: usize) ![]u8 {
    if (length < 43 or length > 128) {
        return OAuthError.InvalidFormat;
    }

    // Generate random bytes
    const random_bytes = try allocator.alloc(u8, length);
    defer allocator.free(random_bytes);
    std.crypto.random.bytes(random_bytes);

    // Convert to valid PKCE characters (alphanumeric + -._~)
    const valid_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
    const verifier = try allocator.alloc(u8, length);

    for (random_bytes, 0..) |byte, i| {
        verifier[i] = valid_chars[byte % valid_chars.len];
    }

    return verifier;
}

/// Generate code challenge by SHA256 hashing and base64url encoding the verifier
fn generateCodeChallenge(allocator: std.mem.Allocator, code_verifier: []const u8) ![]u8 {
    // SHA256 hash the verifier
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(code_verifier);
    const hash = hasher.finalResult();

    // Base64url encode the hash
    const encoded_size = std.base64.url_safe_no_pad.Encoder.calcSize(hash.len);
    const challenge = try allocator.alloc(u8, encoded_size);
    _ = std.base64.url_safe_no_pad.Encoder.encode(challenge, &hash);

    return challenge;
}

/// Generate a cryptographically secure random state parameter
fn generateRandomState(allocator: std.mem.Allocator, length: usize) ![]u8 {
    // Generate random bytes
    const random_bytes = try allocator.alloc(u8, length);
    defer allocator.free(random_bytes);
    std.crypto.random.bytes(random_bytes);

    // Convert to URL-safe characters
    const valid_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    const state = try allocator.alloc(u8, length);

    for (random_bytes, 0..) |byte, i| {
        state[i] = valid_chars[byte % valid_chars.len];
    }

    return state;
}

/// Build OAuth authorization URL
pub fn buildAuthorizationURL(allocator: std.mem.Allocator, pkce_params: PkceParams) ![]u8 {
    const scopes = [_][]const u8{ "org:create_api_key", "user:profile", "user:inference" };
    const provider = OAuthProvider{
        .client_id = OAUTH_CLIENT_ID,
        .authorization_url = OAUTH_AUTHORIZATION_URL,
        .token_url = OAUTH_TOKEN_ENDPOINT,
        .redirect_uri = OAUTH_REDIRECT_URI,
        .scopes = &scopes,
    };

    return try provider.buildAuthorizationURL(allocator, pkce_params);
}

/// Exchange authorization code for tokens using PKCE flow
/// NOTE: This is a stub implementation. For real token exchange,
/// integrate with an HTTP client to make requests to the OAuth token endpoint.
pub fn exchangeCodeForTokens(allocator: std.mem.Allocator, authorization_code: []const u8, pkce_params: PkceParams) !OAuthCredentials {
    // TODO: Implement real HTTP request to OAuth token endpoint
    // This would typically involve:
    // 1. Making a POST request to OAUTH_TOKEN_ENDPOINT
    // 2. Sending form data with grant_type, code, redirect_uri, code_verifier, client_id
    // 3. Parsing the JSON response for access_token, refresh_token, expires_in
    // 4. Converting expires_in to expires_at timestamp

    _ = authorization_code;
    _ = pkce_params;

    // Return stub credentials for now
    return OAuthCredentials{
        .type = try allocator.dupe(u8, "oauth"),
        .access_token = try allocator.dupe(u8, "stub_access_token"),
        .refresh_token = try allocator.dupe(u8, "stub_refresh_token"),
        .expires_at = std.time.timestamp() + 3600, // 1 hour from now
    };
}

/// Refresh access token using refresh token
/// NOTE: This is a stub implementation. For real token refresh,
/// integrate with an HTTP client to make requests to the OAuth token endpoint.
pub fn refreshTokens(allocator: std.mem.Allocator, refresh_token: []const u8) !OAuthCredentials {
    // TODO: Implement real HTTP request to OAuth token endpoint
    // This would typically involve:
    // 1. Making a POST request to OAUTH_TOKEN_ENDPOINT
    // 2. Sending form data with grant_type=refresh_token, refresh_token, client_id
    // 3. Parsing the JSON response for new tokens and expiration

    _ = refresh_token;

    // Return stub credentials for now
    return OAuthCredentials{
        .type = try allocator.dupe(u8, "oauth"),
        .access_token = try allocator.dupe(u8, "stub_access_token"),
        .refresh_token = try allocator.dupe(u8, "stub_refresh_token"),
        .expires_at = std.time.timestamp() + 3600, // 1 hour from now
    };
}

pub fn parseCredentials(allocator: std.mem.Allocator, json_content: []const u8) !OAuthCredentials {
    const parsed = try std.json.parseFromSlice(OAuthCredentials, allocator, json_content, .{});
    defer parsed.deinit();

    return OAuthCredentials{
        .type = try allocator.dupe(u8, parsed.value.type),
        .access_token = try allocator.dupe(u8, parsed.value.access_token),
        .refresh_token = try allocator.dupe(u8, parsed.value.refresh_token),
        .expires_at = parsed.value.expires_at,
    };
}

pub fn saveCredentials(allocator: std.mem.Allocator, file_path: []const u8, creds: OAuthCredentials) !void {
    const json_content = try std.fmt.allocPrint(allocator, "{{\"type\":\"{s}\",\"access_token\":\"{s}\",\"refresh_token\":\"{s}\",\"expires_at\":{}}}", .{ creds.type, creds.access_token, creds.refresh_token, creds.expires_at });
    defer allocator.free(json_content);

    const file = try std.fs.cwd().createFile(file_path, .{ .mode = 0o600 });
    defer file.close();

    try file.writeAll(json_content);
}

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

/// High-level OAuth setup function - simplified implementation without TUI
pub fn setupOAuth(allocator: std.mem.Allocator) !OAuthCredentials {
    std.log.info("🔐 Starting OAuth setup...", .{});

    // Generate PKCE parameters
    const pkce_params = try generatePkceParams(allocator);
    defer pkce_params.deinit(allocator);

    // Build authorization URL
    const auth_URL = try buildAuthorizationURL(allocator, pkce_params);
    defer allocator.free(auth_URL);

    std.log.info("Please visit this URL to authorize the application:", .{});
    std.log.info("{s}", .{auth_URL});

    // Try to launch browser
    launchBrowser(auth_URL) catch {
        std.log.warn("Could not launch browser automatically. Please copy and paste the URL above.", .{});
    };

    std.log.info("After authorization, you'll be redirected to a URL containing the authorization code.", .{});
    std.log.info("Enter the authorization code from the redirect URL:");

    // Read authorization code from stdin
    const stdin = std.fs.File.stdin();
    var buffer: [1024]u8 = undefined;
    const bytes_read = try stdin.readAll(buffer[0..]);
    if (bytes_read == 0) {
        return OAuthError.AuthError;
    }

    const auth_code = std.mem.trim(u8, buffer[0..bytes_read], " \t\r\n");

    // Exchange code for tokens
    const credentials = try exchangeCodeForTokens(allocator, auth_code, pkce_params);

    // Save credentials
    try saveCredentials(allocator, "claude_oauth_creds.json", credentials);

    std.log.info("✅ OAuth setup completed successfully!", .{});

    return credentials;
}

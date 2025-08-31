//! OAuth authentication implementation for DocZ
//!
//! This module provides a complete OAuth 2.0 implementation with PKCE support,
//! including proper HTTP requests to the OAuth token endpoint for exchanging
//! authorization codes and refreshing access tokens.
//!
//! Features:
//! - PKCE (Proof Key for Code Exchange) for security
//! - Real HTTP POST requests to OAuth token endpoint
//! - Proper JSON response parsing and error handling
//! - Token expiration management
//! - Integration with callback server for seamless authorization flow

const std = @import("std");
pub const callbackServer = @import("Callback.zig");
// Get curl from the network module
const curl = @import("../curl.zig");

// Re-export OAuth constants and types from anthropic
pub const OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
pub const OAUTH_AUTHORIZATION_URL = "https://claude.ai/oauth/authorize";
pub const OAUTH_TOKEN_ENDPOINT = "https://console.anthropic.com/v1/oauth/token";
pub const OAUTH_REDIRECT_URI = "https://console.anthropic.com/oauth/code/callback";
pub const OAUTH_SCOPES = "org:create_api_key user:profile user:inference";

/// OAuth error types
pub const Error = error{
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

    /// Clean up allocated memory
    pub fn deinit(self: Credentials, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        allocator.free(self.accessToken);
        allocator.free(self.refreshToken);
    }
};

/// PKCE parameters - compatible with anthropic module
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

/// OAuth provider configuration
pub const Provider = struct {
    clientId: []const u8,
    authorizationUrl: []const u8,
    tokenUrl: []const u8,
    redirectUri: []const u8,
    scopes: []const []const u8,

    /// Build authorization URL with PKCE parameters
    pub fn buildAuthorizationUrl(self: Provider, allocator: std.mem.Allocator, pkceParams: Pkce) ![]u8 {
        const scopesJoined = try std.mem.join(allocator, " ", self.scopes);
        defer allocator.free(scopesJoined);

        return try std.fmt.allocPrint(allocator, "{s}?client_id={s}&response_type=code&redirect_uri={s}&scope={s}&code_challenge={s}&code_challenge_method=S256&state={s}", .{
            self.authorizationUrl,
            self.clientId,
            self.redirectUri,
            scopesJoined,
            pkceParams.codeChallenge,
            pkceParams.state,
        });
    }
};

// Delegate to anthropic module functions to avoid duplication and module conflicts
// Note: These functions will be implemented as pass-through to the anthropic module

/// Generate PKCE parameters with cryptographically secure random values
pub fn generatePkceParams(allocator: std.mem.Allocator) !Pkce {
    // Generate random code verifier (43-128 characters)
    const verifierLength = 64; // Use 64 characters for good entropy
    const codeVerifier = try generateCodeVerifier(allocator, verifierLength);

    // Generate code challenge by SHA256 hashing and base64url encoding
    const codeChallenge = try generateCodeChallenge(allocator, codeVerifier);

    // Generate random state parameter (32 characters)
    const state = try generateRandomState(allocator, 32);

    return Pkce{
        .codeVerifier = codeVerifier,
        .codeChallenge = codeChallenge,
        .state = state,
    };
}

/// Generate a cryptographically secure random code verifier
fn generateCodeVerifier(allocator: std.mem.Allocator, length: usize) ![]u8 {
    if (length < 43 or length > 128) {
        return Error.InvalidFormat;
    }

    // Generate random bytes
    const randomBytes = try allocator.alloc(u8, length);
    defer allocator.free(randomBytes);
    std.crypto.random.bytes(randomBytes);

    // Convert to valid PKCE characters (alphanumeric + -._~)
    const validChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
    const verifier = try allocator.alloc(u8, length);

    for (randomBytes, 0..) |byte, i| {
        verifier[i] = validChars[byte % validChars.len];
    }

    return verifier;
}

/// Generate code challenge by SHA256 hashing and base64url encoding the verifier
fn generateCodeChallenge(allocator: std.mem.Allocator, codeVerifier: []const u8) ![]u8 {
    // SHA256 hash the verifier
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(codeVerifier);
    const hash = hasher.finalResult();

    // Base64url encode the hash
    const encodedSize = std.base64.url_safe_no_pad.Encoder.calcSize(hash.len);
    const challenge = try allocator.alloc(u8, encodedSize);
    _ = std.base64.url_safe_no_pad.Encoder.encode(challenge, &hash);

    return challenge;
}

/// Generate a cryptographically secure random state parameter
fn generateRandomState(allocator: std.mem.Allocator, length: usize) ![]u8 {
    // Generate random bytes
    const randomBytes = try allocator.alloc(u8, length);
    defer allocator.free(randomBytes);
    std.crypto.random.bytes(randomBytes);

    // Convert to URL-safe characters
    const validChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    const state = try allocator.alloc(u8, length);

    for (randomBytes, 0..) |byte, i| {
        state[i] = validChars[byte % validChars.len];
    }

    return state;
}

/// Build OAuth authorization URL
pub fn buildAuthorizationUrl(allocator: std.mem.Allocator, pkceParams: Pkce) ![]u8 {
    const scopes = [_][]const u8{ "org:create_api_key", "user:profile", "user:inference" };
    const provider = Provider{
        .clientId = OAUTH_CLIENT_ID,
        .authorizationUrl = OAUTH_AUTHORIZATION_URL,
        .tokenUrl = OAUTH_TOKEN_ENDPOINT,
        .redirectUri = OAUTH_REDIRECT_URI,
        .scopes = &scopes,
    };

    return try provider.buildAuthorizationUrl(allocator, pkceParams);
}

/// Helper function to encode form data for OAuth requests
fn isUnreserved(c: u8) bool {
    // RFC 3986 unreserved: ALPHA / DIGIT / '-' / '.' / '_' / '~'
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-' or c == '.' or c == '_' or c == '~';
}

fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (isUnreserved(c)) {
            try out.append(allocator, c);
        } else if (c == ' ') {
            // application/x-www-form-urlencoded encodes space as '+'
            try out.append(allocator, '+');
        } else {
            const hex = "0123456789ABCDEF";
            try out.append(allocator, '%');
            try out.append(allocator, hex[(c >> 4) & 0xF]);
            try out.append(allocator, hex[c & 0xF]);
        }
    }
    return out.toOwnedSlice(allocator);
}

fn encodeFormData(allocator: std.mem.Allocator, fields: anytype) ![]u8 {
    var formData = std.ArrayListUnmanaged(u8){};
    defer formData.deinit(allocator);

    for (fields, 0..) |field, i| {
        if (i > 0) try formData.appendSlice(allocator, "&");

        const keyEnc = try urlEncode(allocator, field.key);
        defer allocator.free(keyEnc);
        try formData.appendSlice(allocator, keyEnc);
        try formData.appendSlice(allocator, "=");

        const valEnc = try urlEncode(allocator, field.value);
        defer allocator.free(valEnc);
        try formData.appendSlice(allocator, valEnc);
    }
    return formData.toOwnedSlice(allocator);
}

/// Parse OAuth token response JSON
fn parseTokenResponse(allocator: std.mem.Allocator, jsonResponse: []const u8) !Credentials {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, jsonResponse, .{});
    defer parsed.deinit();

    // Check if response contains an error
    if (parsed.value == .object) {
        if (parsed.value.object.get("error")) |errorField| {
            var code: []const u8 = "unknown_error";
            if (errorField == .string) {
                code = errorField.string;
            } else if (errorField == .object) {
                if (errorField.object.get("type")) |t| {
                    if (t == .string) code = t.string;
                }
            }
            std.log.err("OAuth error response type: {s}", .{code});
            if (std.mem.eql(u8, code, "invalid_grant")) return Error.InvalidGrant;
            if (std.mem.eql(u8, code, "invalid_request")) return Error.InvalidFormat;
            return Error.AuthError;
        }
    }

    if (parsed.value != .object) return Error.InvalidFormat;
    const obj = parsed.value.object;

    // Extract required fields with proper error handling
    const accessToken = obj.get("access_token") orelse {
        std.log.err("Missing access_token in OAuth response", .{});
        return Error.InvalidFormat;
    };

    const refreshToken = obj.get("refresh_token") orelse {
        std.log.err("Missing refresh_token in OAuth response", .{});
        return Error.InvalidFormat;
    };

    const expiresIn = obj.get("expires_in") orelse {
        std.log.err("Missing expires_in in OAuth response", .{});
        return Error.InvalidFormat;
    };

    if (accessToken != .string or refreshToken != .string or expiresIn != .integer) {
        std.log.err("Invalid field types in OAuth response", .{});
        return Error.InvalidFormat;
    }

    // Calculate expiration timestamp
    const expiresAt = std.time.timestamp() + expiresIn.integer;

    return Credentials{
        .type = try allocator.dupe(u8, "oauth"),
        .accessToken = try allocator.dupe(u8, accessToken.string),
        .refreshToken = try allocator.dupe(u8, refreshToken.string),
        .expiresAt = expiresAt,
    };
}

/// Exchange authorization code for tokens using PKCE flow
pub fn exchangeCodeForTokens(
    allocator: std.mem.Allocator,
    authorizationCode: []const u8,
    pkceParams: Pkce,
    redirectUri: []const u8,
) !Credentials {
    // Prepare JSON body for token exchange (Anthropic expects JSON)
    const body = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "grant_type": "authorization_code",
        \\  "code": "{s}",
        \\  "redirect_uri": "{s}",
        \\  "code_verifier": "{s}",
        \\  "client_id": "{s}",
        \\  "state": "{s}"
        \\}}
    , .{ authorizationCode, redirectUri, pkceParams.codeVerifier, OAUTH_CLIENT_ID, pkceParams.state });
    defer allocator.free(body);

    // Initialize HTTP client
    var httpClient = try curl.HTTPClient.init(allocator);
    defer httpClient.deinit();

    // Prepare headers
    const headers = [_]curl.Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "User-Agent", .value = "docz/1.0 (libcurl)" },
    };

    // Make POST request to token endpoint
    const request = curl.HTTPRequest{
        .method = .POST,
        .url = OAUTH_TOKEN_ENDPOINT,
        .headers = &headers,
        .body = body,
        .timeout_ms = 30000,
        .verify_ssl = true,
    };

    var response = httpClient.request(request) catch |err| {
        std.log.err("Network error during OAuth token exchange: {any}", .{err});
        return Error.NetworkError;
    };
    defer response.deinit();

    // Check for successful response
    if (response.status_code != 200) {
        std.log.err("OAuth token exchange failed with status: {d}", .{response.status_code});
        std.log.err("Response body: {s}", .{response.body});

        // Try to log error details (without panicking on structure)
        if (std.mem.indexOf(u8, response.body, "message")) |idx| {
            _ = idx; // suppress unused
            std.log.err("OAuth error response: {s}", .{response.body});
        }

        return Error.AuthError;
    }

    // Parse JSON response
    return try parseTokenResponse(allocator, response.body);
}

/// Refresh access token using refresh token
pub fn refreshTokens(allocator: std.mem.Allocator, refreshToken: []const u8) !Credentials {
    // Prepare form data for token refresh
    const fields = [_]struct { key: []const u8, value: []const u8 }{
        .{ .key = "grant_type", .value = "refresh_token" },
        .{ .key = "refresh_token", .value = refreshToken },
        .{ .key = "client_id", .value = OAUTH_CLIENT_ID },
    };

    const formData = try encodeFormData(allocator, fields[0..]);
    defer allocator.free(formData);

    // Initialize HTTP client
    var httpClient = try curl.HTTPClient.init(allocator);
    defer httpClient.deinit();

    // Prepare headers
    const headers = [_]curl.Header{
        .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
        .{ .name = "Accept", .value = "application/json" },
    };

    // Make POST request to token endpoint
    const request = curl.HTTPRequest{
        .method = .POST,
        .url = OAUTH_TOKEN_ENDPOINT,
        .headers = &headers,
        .body = formData,
        .timeout_ms = 30000,
        .verify_ssl = true,
    };

    var response = httpClient.request(request) catch |err| {
        std.log.err("Network error during OAuth token refresh: {any}", .{err});
        return Error.NetworkError;
    };
    defer response.deinit();

    // Check for successful response
    if (response.status_code != 200) {
        std.log.err("OAuth token refresh failed with status: {d}", .{response.status_code});
        std.log.err("Response body: {s}", .{response.body});

        // Try to parse error response
        if (std.mem.indexOf(u8, response.body, "error")) |_| {
            _ = parseTokenResponse(allocator, response.body) catch {};
        }

        return Error.AuthError;
    }

    // Parse JSON response
    return try parseTokenResponse(allocator, response.body);
}

pub fn parseCredentials(allocator: std.mem.Allocator, jsonContent: []const u8) !Credentials {
    const parsed = try std.json.parseFromSlice(Credentials, allocator, jsonContent, .{});
    defer parsed.deinit();

    return Credentials{
        .type = try allocator.dupe(u8, parsed.value.type),
        .accessToken = try allocator.dupe(u8, parsed.value.accessToken),
        .refreshToken = try allocator.dupe(u8, parsed.value.refreshToken),
        .expiresAt = parsed.value.expiresAt,
    };
}

pub fn saveCredentials(allocator: std.mem.Allocator, filePath: []const u8, creds: Credentials) !void {
    const jsonContent = try std.fmt.allocPrint(allocator, "{{\"type\":\"{s}\",\"accessToken\":\"{s}\",\"refreshToken\":\"{s}\",\"expiresAt\":{d}}}", .{ creds.type, creds.accessToken, creds.refreshToken, creds.expiresAt });
    defer allocator.free(jsonContent);

    const file = try std.fs.cwd().createFile(filePath, .{ .mode = 0o600 });
    defer file.close();

    try file.writeAll(jsonContent);
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
pub fn setupOAuth(allocator: std.mem.Allocator) !Credentials {
    std.log.info("🔐 Starting OAuth setup...", .{});

    // Generate PKCE parameters
    const pkceParams = try generatePkceParams(allocator);
    defer pkceParams.deinit(allocator);

    // Build authorization URL
    const authUrl = try buildAuthorizationUrl(allocator, pkceParams);
    defer allocator.free(authUrl);

    std.log.info("Please visit this URL to authorize the application:", .{});
    std.log.info("{s}", .{authUrl});

    // Try to launch browser
    launchBrowser(authUrl) catch {
        std.log.warn("Could not launch browser automatically. Please copy and paste the URL above.", .{});
    };

    std.log.info("After authorization, you'll be redirected to a URL containing the authorization code.", .{});
    std.log.info("Enter the authorization code from the redirect URL:", .{});

    // Read authorization code from stdin
    const stdin = std.fs.File.stdin();
    var buffer: [1024]u8 = undefined;
    const bytesRead = try stdin.readAll(buffer[0..]);
    if (bytesRead == 0) {
        return Error.AuthError;
    }

    const authCode = std.mem.trim(u8, buffer[0..bytesRead], " \t\r\n");

    // Exchange code for tokens
    const credentials = try exchangeCodeForTokens(allocator, authCode, pkceParams, OAUTH_REDIRECT_URI);

    // Save credentials
    try saveCredentials(allocator, "claude_oauth_creds.json", credentials);

    std.log.info("✅ OAuth setup completed successfully!", .{});

    return credentials;
}

// Re-export callback server types and functions for convenience
pub const Server = callbackServer.Server;
pub const Config = callbackServer.Config;
pub const Result = callbackServer.Result;
pub const runCallbackServer = callbackServer.runCallbackServer;
pub const integrateWithWizard = callbackServer.integrateWithWizard;
pub const completeOAuthFlow = callbackServer.completeOAuthFlow;

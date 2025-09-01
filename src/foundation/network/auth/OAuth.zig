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

// Re-export OAuth constants and types from anthropic
pub const OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
// Use claude.ai for the authorization step; it supports localhost redirects.
pub const OAUTH_AUTHORIZATION_URL = "https://claude.ai/oauth/authorize";
pub const OAUTH_TOKEN_ENDPOINT = "https://console.anthropic.com/v1/oauth/token";
pub const OAUTH_REDIRECT_URI = "http://localhost:8080/callback";
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

/// PKCE parameters - alias for compatibility
pub const Pkce = @import("pkce.zig").PkceParams;

/// OAuth provider configuration
pub const Provider = struct {
    clientId: []const u8,
    authorizationUrl: []const u8,
    tokenUrl: []const u8,
    redirectUri: []const u8,
    scopes: []const []const u8,

    /// Build authorization URL with PKCE parameters
    /// All query parameter values are URL-encoded per RFC 3986.
    pub fn buildAuthorizationUrl(self: Provider, allocator: std.mem.Allocator, pkceParams: Pkce) ![]u8 {
        const scopesJoined = try std.mem.join(allocator, " ", self.scopes);
        defer allocator.free(scopesJoined);

        const client_id_enc = try urlEncode(allocator, self.clientId);
        defer allocator.free(client_id_enc);

        const redirect_enc = try urlEncode(allocator, self.redirectUri);
        defer allocator.free(redirect_enc);

        const scopes_enc = try urlEncode(allocator, scopesJoined);
        defer allocator.free(scopes_enc);

        const challenge_enc = try urlEncode(allocator, pkceParams.challenge);
        defer allocator.free(challenge_enc);

        const state_enc = try urlEncode(allocator, pkceParams.state);
        defer allocator.free(state_enc);

        return try std.fmt.allocPrint(
            allocator,
            "{s}?client_id={s}&response_type=code&redirect_uri={s}&scope={s}&code_challenge={s}&code_challenge_method=S256&state={s}",
            .{ self.authorizationUrl, client_id_enc, redirect_enc, scopes_enc, challenge_enc, state_enc },
        );
    }
};

// Delegate to anthropic module functions to avoid duplication and module conflicts
// Note: These functions will be implemented as pass-through to the anthropic module

/// Generate PKCE parameters with cryptographically secure random values
pub fn generatePkceParams(allocator: std.mem.Allocator) !Pkce {
    return @import("pkce.zig").generate(allocator, 64);
}



/// Build OAuth authorization URL
pub fn buildAuthorizationUrl(allocator: std.mem.Allocator, pkceParams: Pkce) ![]u8 {
    return buildAuthorizationUrlWithRedirect(allocator, pkceParams, OAUTH_REDIRECT_URI);
}

/// Build OAuth authorization URL with custom redirect URI
pub fn buildAuthorizationUrlWithRedirect(allocator: std.mem.Allocator, pkceParams: Pkce, redirectUri: []const u8) ![]u8 {
    const scopes = [_][]const u8{ "org:create_api_key", "user:profile", "user:inference" };
    const provider = Provider{
        .clientId = OAUTH_CLIENT_ID,
        .authorizationUrl = OAUTH_AUTHORIZATION_URL,
        .tokenUrl = OAUTH_TOKEN_ENDPOINT,
        .redirectUri = redirectUri,
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
    , .{ authorizationCode, redirectUri, pkceParams.verifier, OAUTH_CLIENT_ID, pkceParams.state });
    defer allocator.free(body);

    // Initialize HTTP client
    var httpClient = std.http.Client{ .allocator = allocator };
    defer httpClient.deinit();

    // Parse URL
    const uri = try std.Uri.parse(OAUTH_TOKEN_ENDPOINT);

    // Make POST request to token endpoint
    var req = try httpClient.request(.POST, uri, .{
        .headers = .{
            .user_agent = .{ .override = "docz/1.0" },
            .content_type = .{ .override = "application/json" },
        },
        .extra_headers = &.{ .{ .name = "Accept", .value = "application/json" } },
    });
    defer req.deinit();

    try req.sendBodyComplete(body);
    var redirect_buf: [256]u8 = undefined;
    var resp = try req.receiveHead(&redirect_buf);

    // Check for successful response
    if (resp.head.status != .ok) {
        std.log.err("OAuth token exchange failed with status: {}", .{resp.head.status});
        const reader = resp.reader(&[_]u8{});
        const error_body = try reader.*.allocRemaining(allocator, std.Io.Limit.limited(1024 * 1024));
        defer allocator.free(error_body);
        std.log.err("Response body: {s}", .{error_body});
        return Error.AuthError;
    }
    const reader = resp.reader(&[_]u8{});
    const response_body = try reader.*.allocRemaining(allocator, std.Io.Limit.limited(1024 * 1024));
    defer allocator.free(response_body);
    return try parseTokenResponse(allocator, response_body);
}

/// Refresh access token using refresh token (JSON body per spec)
pub fn refreshTokens(allocator: std.mem.Allocator, refreshToken: []const u8) !Credentials {
    // Prepare JSON body
    const body = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "grant_type": "refresh_token",
        \\  "refresh_token": "{s}",
        \\  "client_id": "{s}"
        \\}}
    , .{ refreshToken, OAUTH_CLIENT_ID });
    defer allocator.free(body);

    // Initialize HTTP client
    var httpClient = std.http.Client{ .allocator = allocator };
    defer httpClient.deinit();

    // Parse URL
    const uri = try std.Uri.parse(OAUTH_TOKEN_ENDPOINT);

    // Make POST request to token endpoint
    var req = try httpClient.request(.POST, uri, .{
        .headers = .{
            .user_agent = .{ .override = "docz/1.0" },
            .content_type = .{ .override = "application/json" },
        },
        .extra_headers = &.{ .{ .name = "Accept", .value = "application/json" } },
    });
    defer req.deinit();

    try req.sendBodyComplete(body);
    // handled above

    // Check for successful response
    var redirect_buf2: [256]u8 = undefined;
    var resp2 = try req.receiveHead(&redirect_buf2);
    if (resp2.head.status != .ok) {
        std.log.err("OAuth token refresh failed with status: {}", .{resp2.head.status});
        const reader2 = resp2.reader(&[_]u8{});
        const error_body = try reader2.*.allocRemaining(allocator, std.Io.Limit.limited(1024 * 1024));
        defer allocator.free(error_body);
        std.log.err("Response body: {s}", .{error_body});
        return Error.AuthError;
    }
    const reader2 = resp2.reader(&[_]u8{});
    const response_body = try reader2.*.allocRemaining(allocator, std.Io.Limit.limited(1024 * 1024));
    defer allocator.free(response_body);
    return try parseTokenResponse(allocator, response_body);
}

/// Save credentials to file - delegates to store module when path not provided
pub fn saveCredentialsToStore(allocator: std.mem.Allocator, creds: Credentials) !void {
    const agent_name = std.process.getEnvVarOwned(allocator, "AGENT_NAME") catch |err| blk: {
        if (err == error.EnvironmentVariableNotFound) {
            break :blk try allocator.dupe(u8, "docz");
        }
        return err;
    };
    defer allocator.free(agent_name);

    const store = @import("store.zig").TokenStore.init(allocator, .{ 
        .agent_name = agent_name,
    });
    
    const stored_creds = @import("store.zig").StoredCredentials{
        .type = creds.type,
        .access_token = creds.accessToken,
        .refresh_token = creds.refreshToken,
        .expires_at = creds.expiresAt,
    };
    try store.save(stored_creds);
}

/// Save credentials to specific file path with atomic write
pub fn saveCredentials(allocator: std.mem.Allocator, filePath: []const u8, creds: Credentials) !void {
    // Persist in snake_case per spec; chmod 0600. Write atomically via a temp file then rename.
    const jsonContent = try std.fmt.allocPrint(
        allocator,
        \\{{"type":"{s}","access_token":"{s}","refresh_token":"{s}","expires_at":{}}}
    ,
        .{ creds.type, creds.accessToken, creds.refreshToken, creds.expiresAt },
    );
    defer allocator.free(jsonContent);

    var cwd = std.fs.cwd();
    // Create temp path in same directory to ensure rename is atomic on most filesystems
    const tmpPath = try std.fmt.allocPrint(allocator, "{s}.tmp", .{filePath});
    defer allocator.free(tmpPath);

    {
        const tmp = try cwd.createFile(tmpPath, .{ .mode = 0o600 });
        defer tmp.close();
        try tmp.writeAll(jsonContent);
        // Ensure contents are on disk before rename
        tmp.sync() catch {};
    }

    // Rename temp → final path
    cwd.rename(tmpPath, filePath) catch |err| {
        // Best-effort fallback: write directly (kept for portability)
        switch (err) {
            error.FileNotFound, error.AccessDenied, error.RenameAcrossMountPoints => {
                const file = try cwd.createFile(filePath, .{ .mode = 0o600 });
                defer file.close();
                try file.writeAll(jsonContent);
                return;
            },
            else => return err,
        }
    };
}

/// Convenience: Full login using loopback server and PKCE; persists tokens and returns creds.
pub fn loginWithLoopback(allocator: std.mem.Allocator) !Credentials {
    const pkceParams = try generatePkceParams(allocator);
    errdefer pkceParams.deinit(allocator);

    var server = try @import("loopback_server.zig").LoopbackServer.init(allocator, .{
        .host = "localhost",
        .port = 8080,
        .path = "/callback",
        .timeout_ms = 300000,
    });
    defer server.deinit();

    const redirect_uri = try server.getRedirectUri(allocator);
    defer allocator.free(redirect_uri);

    const auth_url = try buildAuthorizationUrlWithRedirect(allocator, pkceParams, redirect_uri);
    defer allocator.free(auth_url);

    // Try to open browser
    launchBrowser(auth_url) catch |err| {
        std.log.warn("Failed to open browser: {}", .{err});
    };

    // Wait for callback
    const callback_result = try server.waitForCallback(pkceParams.state);
    defer callback_result.deinit(allocator);

    // Exchange code for tokens
    const creds = try exchangeCodeForTokens(allocator, callback_result.code, pkceParams, redirect_uri);
    errdefer creds.deinit(allocator);

    // Save credentials
    const agent_name = std.process.getEnvVarOwned(allocator, "AGENT_NAME") catch |err| blk: {
        if (err == error.EnvironmentVariableNotFound) {
            break :blk try allocator.dupe(u8, "docz");
        }
        return err;
    };
    defer allocator.free(agent_name);

    const store = @import("store.zig").TokenStore.init(allocator, .{ 
        .agent_name = agent_name,
    });
    
    const stored_creds = @import("store.zig").StoredCredentials{
        .type = "oauth",
        .access_token = creds.accessToken,
        .refresh_token = creds.refreshToken,
        .expires_at = creds.expiresAt,
    };
    try store.save(stored_creds);

    return creds;
}

/// Convenience: Load current access token from default credentials file.
pub fn getAccessToken(allocator: std.mem.Allocator) ![]u8 {
    const agent_name = std.process.getEnvVarOwned(allocator, "AGENT_NAME") catch |err| blk: {
        if (err == error.EnvironmentVariableNotFound) {
            break :blk try allocator.dupe(u8, "docz");
        }
        return err;
    };
    defer allocator.free(agent_name);

    const store = @import("store.zig").TokenStore.init(allocator, .{ 
        .agent_name = agent_name,
    });
    
    const stored_creds = try store.load();
    defer allocator.free(stored_creds.type);
    defer allocator.free(stored_creds.refresh_token);
    
    // Return owned copy of access token
    return stored_creds.access_token;
}

/// Launch the system browser to open the authorization URL  
pub fn launchBrowser(url: []const u8) !void {
    const allocator = std.heap.page_allocator;
    return @import("authorize_url.zig").openInBrowser(allocator, url);
}

/// Convenience: Minimal Messages API POST using OAuth Bearer headers.
pub fn fetchWithAnthropicOAuth(
    allocator: std.mem.Allocator,
    access_token: []const u8,
    body_json: []const u8,
) ![]u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const bearer = try std.fmt.allocPrint(allocator, "Bearer {s}", .{access_token});
    defer allocator.free(bearer);

    const version = "2023-06-01";
    const has_build_options = @hasDecl(@import("root"), "build_options");
    const build_options = if (has_build_options) @import("root").build_options else struct {
        pub const anthropic_beta_oauth = "oauth-2025-04-20";
        pub const oauth_beta_header = true;
    };
    const beta = if (build_options.oauth_beta_header) build_options.anthropic_beta_oauth else "none";

    const uri = try std.Uri.parse("https://api.anthropic.com/v1/messages");

    var req = try client.request(.POST, uri, .{
        .headers = .{ .user_agent = .override("docz/1.0"), .content_type = .override("application/json") },
        .extra_headers = &.{
            .{ .name = "Authorization", .value = bearer },
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "Accept", .value = "application/json" },
            .{ .name = "anthropic-version", .value = version },
            .{ .name = "anthropic-beta", .value = beta },
            .{ .name = "User-Agent", .value = "docz/1.0" },
        },
    });
    defer req.deinit();

    try req.sendBodyComplete(body_json);
    var redirect_buf3: [256]u8 = undefined;
    const resp3 = try req.receiveHead(&redirect_buf3);
    if (resp3.head.status != .ok) return Error.AuthError;
    var reader3 = resp3.reader(&[_]u8{});
    const response_body = try reader3.readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(response_body);
    return try allocator.dupe(u8, response_body);
}

pub fn parseCredentialsFromJson(allocator: std.mem.Allocator, jsonContent: []const u8) !Credentials {
    // Preferred: snake_case fields per repo spec
    const Snake = struct {
        type: []const u8,
        access_token: []const u8,
        refresh_token: []const u8,
        expires_at: i64,
    };

    if (std.json.parseFromSlice(Snake, allocator, jsonContent, .{})) |parsed| {
        defer parsed.deinit();
        return Credentials{
            .type = try allocator.dupe(u8, parsed.value.type),
            .accessToken = try allocator.dupe(u8, parsed.value.access_token),
            .refreshToken = try allocator.dupe(u8, parsed.value.refresh_token),
            .expiresAt = parsed.value.expires_at,
        };
    } else |_| {}

    // Back-compat: camelCase fields
    const Camel = struct {
        type: []const u8,
        accessToken: []const u8,
        refreshToken: []const u8,
        expiresAt: i64,
    };
    const parsed2 = try std.json.parseFromSlice(Camel, allocator, jsonContent, .{});
    defer parsed2.deinit();
    return Credentials{
        .type = try allocator.dupe(u8, parsed2.value.type),
        .accessToken = try allocator.dupe(u8, parsed2.value.accessToken),
        .refreshToken = try allocator.dupe(u8, parsed2.value.refreshToken),
        .expiresAt = parsed2.value.expiresAt,
    };
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

test "parseCredentialsFromJson supports snake_case and camelCase" {
    const a = std.testing.allocator;

    const snake = "{\"type\":\"oauth\",\"access_token\":\"a\",\"refresh_token\":\"b\",\"expires_at\":123}";
    const c1 = try parseCredentialsFromJson(a, snake);
    defer c1.deinit(a);
    try std.testing.expectEqualStrings("oauth", c1.type);
    try std.testing.expectEqualStrings("a", c1.accessToken);
    try std.testing.expectEqualStrings("b", c1.refreshToken);
    try std.testing.expectEqual(@as(i64, 123), c1.expiresAt);

    const camel = "{\"type\":\"oauth\",\"accessToken\":\"x\",\"refreshToken\":\"y\",\"expiresAt\":42}";
    const c2 = try parseCredentialsFromJson(a, camel);
    defer c2.deinit(a);
    try std.testing.expectEqualStrings("oauth", c2.type);
    try std.testing.expectEqualStrings("x", c2.accessToken);
    try std.testing.expectEqualStrings("y", c2.refreshToken);
    try std.testing.expectEqual(@as(i64, 42), c2.expiresAt);
}

test "pkce generator produces valid lengths and URL-safe challenge" {
    const a = std.testing.allocator;
    const pk = try generatePkceParams(a);
    defer pk.deinit(a);
    // Verifier length within RFC bounds [43,128]
    try std.testing.expect(pk.verifier.len >= 43 and pk.verifier.len <= 128);
    // Challenge should be URL-safe base64 (no '=' padding)
    for (pk.challenge) |c| {
        const ok = (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-' or c == '_';
        try std.testing.expect(ok);
    }
    // State should be 32 characters
    try std.testing.expectEqual(@as(usize, 32), pk.state.len);
}

test "authorization URL uses localhost callback" {
    const a = std.testing.allocator;
    const scopes = [_][]const u8{ "org:create_api_key", "user:profile", "user:inference" };
    const p = Provider{
        .clientId = OAUTH_CLIENT_ID,
        .authorizationUrl = OAUTH_AUTHORIZATION_URL,
        .tokenUrl = OAUTH_TOKEN_ENDPOINT,
        .redirectUri = "http://localhost:54321/callback",
        .scopes = &scopes,
    };
    const pk = try generatePkceParams(a);
    defer pk.deinit(a);
    const url = try p.buildAuthorizationUrl(a, pk);
    defer a.free(url);
    try std.testing.expect(std.mem.indexOf(u8, url, "redirect_uri=http%3A%2F%2Flocalhost%3A54321%2Fcallback") != null);
}

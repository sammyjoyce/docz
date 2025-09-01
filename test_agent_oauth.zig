//! Test suite for agent OAuth functionality
//!
//! Tests PKCE generation, OAuth flow, token refresh, and agent loop

const std = @import("std");
const testing = std.testing;
const foundation = @import("foundation");
const network = foundation.network;
const oauth = network.Auth.OAuth;

test "PKCE parameter generation" {
    const allocator = testing.allocator;

    const pkce = try oauth.generatePkceParams(allocator);
    defer pkce.deinit(allocator);

    // Verify verifier length is within RFC bounds [43,128]
    try testing.expect(pkce.codeVerifier.len >= 43);
    try testing.expect(pkce.codeVerifier.len <= 128);

    // Verify challenge is base64url encoded (no padding)
    for (pkce.codeChallenge) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '_';
        try testing.expect(valid);
    }

    // Verify state is generated
    try testing.expect(pkce.state.len > 0);
}

test "OAuth credentials parsing" {
    const allocator = testing.allocator;

    // Test snake_case format (per spec)
    const snake_json =
        \\{"type":"oauth","access_token":"test_access","refresh_token":"test_refresh","expires_at":1234567890}
    ;
    const creds1 = try oauth.parseCredentials(allocator, snake_json);
    defer creds1.deinit(allocator);

    try testing.expectEqualStrings("oauth", creds1.type);
    try testing.expectEqualStrings("test_access", creds1.accessToken);
    try testing.expectEqualStrings("test_refresh", creds1.refreshToken);
    try testing.expectEqual(@as(i64, 1234567890), creds1.expiresAt);

    // Test camelCase format (backwards compat)
    const camel_json =
        \\{"type":"oauth","accessToken":"test_access2","refreshToken":"test_refresh2","expiresAt":987654321}
    ;
    const creds2 = try oauth.parseCredentials(allocator, camel_json);
    defer creds2.deinit(allocator);

    try testing.expectEqualStrings("oauth", creds2.type);
    try testing.expectEqualStrings("test_access2", creds2.accessToken);
    try testing.expectEqualStrings("test_refresh2", creds2.refreshToken);
    try testing.expectEqual(@as(i64, 987654321), creds2.expiresAt);
}

test "OAuth authorization URL building" {
    const allocator = testing.allocator;

    const pkce = try oauth.generatePkceParams(allocator);
    defer pkce.deinit(allocator);

    const url = try oauth.buildAuthorizationUrl(allocator, pkce);
    defer allocator.free(url);

    // Verify URL contains required parameters
    try testing.expect(std.mem.indexOf(u8, url, "response_type=code") != null);
    try testing.expect(std.mem.indexOf(u8, url, "client_id=") != null);
    try testing.expect(std.mem.indexOf(u8, url, "redirect_uri=") != null);
    try testing.expect(std.mem.indexOf(u8, url, "scope=") != null);
    try testing.expect(std.mem.indexOf(u8, url, "code_challenge=") != null);
    try testing.expect(std.mem.indexOf(u8, url, "code_challenge_method=S256") != null);
    try testing.expect(std.mem.indexOf(u8, url, "state=") != null);
}

test "Callback server request parsing" {
    const allocator = testing.allocator;
    const callback = network.Auth.Callback;

    var server = try callback.Server.init(allocator, .{});
    defer server.deinit();

    // Test valid callback request
    const valid_request =
        "GET /callback?code=test_code&state=test_state HTTP/1.1\r\n" ++
        "Host: localhost:8080\r\n" ++
        "\r\n";

    const result = try server.parseCallbackRequest(valid_request);
    defer result.deinit(allocator);

    try testing.expectEqualStrings("test_code", result.code);
    try testing.expectEqualStrings("test_state", result.state);

    // Test error callback
    const error_request =
        "GET /callback?error=access_denied&state=test_state HTTP/1.1\r\n" ++
        "Host: localhost:8080\r\n" ++
        "\r\n";

    const error_result = try server.parseCallbackRequest(error_request);
    defer error_result.deinit(allocator);

    try testing.expectEqualStrings("", error_result.code);
    try testing.expectEqualStrings("test_state", error_result.state);
    try testing.expectEqualStrings("access_denied", error_result.errorCode.?);
}

test "Token expiration checking" {
    const allocator = testing.allocator;
    const now = std.time.timestamp();

    // Create expired credentials
    const expired = oauth.Credentials{
        .type = "oauth",
        .accessToken = "expired_token",
        .refreshToken = "refresh",
        .expiresAt = now - 3600, // Expired 1 hour ago
    };
    try testing.expect(expired.isExpired());

    // Create valid credentials
    const valid = oauth.Credentials{
        .type = "oauth",
        .accessToken = "valid_token",
        .refreshToken = "refresh",
        .expiresAt = now + 3600, // Expires in 1 hour
    };
    try testing.expect(!valid.isExpired());

    // Check will expire soon (with 2 hour buffer)
    try testing.expect(!valid.willExpireSoon(300)); // 5 minute buffer - still valid
    try testing.expect(valid.willExpireSoon(7200)); // 2 hour buffer - will expire
}

test "Auth client creation fallback" {
    const allocator = testing.allocator;
    const core = network.Auth.Core;

    // Test with no credentials (should fail gracefully)
    const result = core.createClient(allocator);
    if (result) |client| {
        defer client.deinit();
        // If successful, verify we have some auth method
        try testing.expect(client.credentials.getMethod() != .none);
    } else |err| {
        // Expected error when no credentials available
        try testing.expectEqual(core.AuthError.MissingAPIKey, err);
    }
}

test "Localhost redirect URI validation" {
    const allocator = testing.allocator;
    const scopes = [_][]const u8{"user:inference"};

    const provider = oauth.Provider{
        .clientId = "test_client",
        .authorizationUrl = "https://example.com/authorize",
        .tokenUrl = "https://example.com/token",
        .redirectUri = "http://localhost:8080/callback",
        .scopes = &scopes,
    };

    const pkce = try oauth.generatePkceParams(allocator);
    defer pkce.deinit(allocator);

    const url = try provider.buildAuthorizationUrl(allocator, pkce);
    defer allocator.free(url);

    // Verify localhost redirect is properly encoded
    try testing.expect(std.mem.indexOf(u8, url, "redirect_uri=http%3A%2F%2Flocalhost%3A8080%2Fcallback") != null);
}

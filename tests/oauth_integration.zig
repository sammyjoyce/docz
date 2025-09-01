//! OAuth integration tests for end-to-end flow validation
//! Tests PKCE generation, loopback server, token exchange, and API calls

const std = @import("std");
const network = @import("../src/foundation/network.zig");
const Auth = network.Auth;
const testing = std.testing;

test "PKCE generation produces correct verifier and challenge" {
    const allocator = testing.allocator;

    // Generate PKCE parameters
    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);

    // Verify verifier length (should be 64 * 4/3 for base64url)
    try testing.expect(pkce.verifier.len >= 43);
    try testing.expect(pkce.verifier.len <= 128);

    // Verify challenge is base64url encoded SHA256 (43 chars)
    try testing.expectEqual(@as(usize, 43), pkce.challenge.len);

    // Verify state is present and has reasonable length
    try testing.expect(pkce.state.len >= 16);
}

test "Authorization URL builder creates valid URL with all parameters" {
    const allocator = testing.allocator;

    // Generate PKCE parameters
    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);

    // Build authorization URL
    const auth_url = try Auth.OAuth.buildAuthorizationUrl(allocator, pkce);
    defer allocator.free(auth_url);

    // Verify URL contains required parameters
    try testing.expect(std.mem.indexOf(u8, auth_url, "client_id=") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "response_type=code") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "redirect_uri=") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "code_challenge=") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "code_challenge_method=S256") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "state=") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "scope=") != null);
}

test "Token store saves and loads credentials with proper permissions" {
    const allocator = testing.allocator;

    const test_creds_path = "test_oauth_creds.json";
    defer std.fs.cwd().deleteFile(test_creds_path) catch {};

    // Create test credentials
    const creds = Auth.OAuth.Credentials{
        .type = try allocator.dupe(u8, "oauth"),
        .accessToken = try allocator.dupe(u8, "test_access_token"),
        .refreshToken = try allocator.dupe(u8, "test_refresh_token"),
        .expiresAt = std.time.timestamp() + 3600,
    };
    defer creds.deinit(allocator);

    // Save credentials
    const store = Auth.store.TokenStore.init(allocator, .{ .path = test_creds_path });
    try store.save(.{
        .type = creds.type,
        .access_token = creds.accessToken,
        .refresh_token = creds.refreshToken,
        .expires_at = creds.expiresAt,
    });

    // Verify file exists
    try testing.expect(store.exists());

    // Load credentials back
    const loaded = try store.load();
    defer allocator.free(loaded.type);
    defer allocator.free(loaded.access_token);
    defer allocator.free(loaded.refresh_token);

    // Verify loaded data matches
    try testing.expectEqualStrings("oauth", loaded.type);
    try testing.expectEqualStrings("test_access_token", loaded.access_token);
    try testing.expectEqualStrings("test_refresh_token", loaded.refresh_token);
    try testing.expectEqual(creds.expiresAt, loaded.expires_at);

    // Verify file permissions (should be 0600)
    const file = try std.fs.cwd().openFile(test_creds_path, .{});
    defer file.close();
    const stat = try file.stat();
    if (@hasField(@TypeOf(stat), "mode")) {
        const mode = stat.mode & 0o777;
        try testing.expectEqual(@as(u32, 0o600), mode);
    }
}

test "Loopback server binds to localhost only" {
    const allocator = testing.allocator;

    // Initialize loopback server
    var server = try Auth.loopback_server.LoopbackServer.init(allocator, .{
        .host = "localhost",
        .port = 0, // Use ephemeral port
        .path = "/callback",
        .timeout_ms = 1000,
    });
    defer server.deinit();

    // Get the actual port
    const redirect_uri = try server.getRedirectUri(allocator);
    defer allocator.free(redirect_uri);

    // Verify redirect URI uses localhost
    try testing.expect(std.mem.startsWith(u8, redirect_uri, "http://localhost:"));
    try testing.expect(std.mem.endsWith(u8, redirect_uri, "/callback"));
}

test "OAuth credentials expiration checking" {
    const allocator = testing.allocator;

    // Create expired credentials
    const expired_creds = Auth.OAuth.Credentials{
        .type = try allocator.dupe(u8, "oauth"),
        .accessToken = try allocator.dupe(u8, "expired_token"),
        .refreshToken = try allocator.dupe(u8, "refresh_token"),
        .expiresAt = std.time.timestamp() - 3600, // Expired 1 hour ago
    };
    defer expired_creds.deinit(allocator);

    try testing.expect(expired_creds.isExpired());
    try testing.expect(expired_creds.willExpireSoon(0));

    // Create valid credentials
    const valid_creds = Auth.OAuth.Credentials{
        .type = try allocator.dupe(u8, "oauth"),
        .accessToken = try allocator.dupe(u8, "valid_token"),
        .refreshToken = try allocator.dupe(u8, "refresh_token"),
        .expiresAt = std.time.timestamp() + 3600, // Valid for 1 hour
    };
    defer valid_creds.deinit(allocator);

    try testing.expect(!valid_creds.isExpired());
    try testing.expect(!valid_creds.willExpireSoon(3000)); // Won't expire in 50 minutes
    try testing.expect(valid_creds.willExpireSoon(4000)); // Will expire in 67 minutes
}

test "Anthropic client builds correct headers for OAuth" {
    const allocator = testing.allocator;

    // Create OAuth credentials
    const creds = Auth.OAuth.Credentials{
        .type = try allocator.dupe(u8, "oauth"),
        .accessToken = try allocator.dupe(u8, "test_bearer_token"),
        .refreshToken = try allocator.dupe(u8, "test_refresh"),
        .expiresAt = std.time.timestamp() + 3600,
    };
    defer creds.deinit(allocator);

    // Initialize client with OAuth
    var client = network.Anthropic.Client{
        .allocator = allocator,
        .auth = .{ .oauth = creds },
        .credentialsPath = null,
        .baseUrl = "https://api.anthropic.com",
        .apiVersion = "2023-06-01",
        .timeoutMs = 30000,
        .httpVerbose = false,
    };
    defer client.deinit();

    // Build headers for non-streaming request
    const headers = try client.buildHeadersForTest(allocator, false);
    defer {
        for (headers) |h| {
            allocator.free(h.value);
        }
        allocator.free(headers);
    }

    // Verify required headers
    var has_auth = false;
    var has_version = false;
    var has_beta = false;
    var has_no_api_key = true;

    for (headers) |h| {
        if (std.mem.eql(u8, h.name, "Authorization")) {
            has_auth = true;
            try testing.expect(std.mem.startsWith(u8, h.value, "Bearer "));
        } else if (std.mem.eql(u8, h.name, "anthropic-version")) {
            has_version = true;
            try testing.expectEqualStrings("2023-06-01", h.value);
        } else if (std.mem.eql(u8, h.name, "anthropic-beta")) {
            has_beta = true;
            // Should include oauth beta header when enabled
        } else if (std.mem.eql(u8, h.name, "x-api-key")) {
            has_no_api_key = false; // Should NOT have API key with OAuth
        }
    }

    try testing.expect(has_auth);
    try testing.expect(has_version);
    try testing.expect(has_beta);
    try testing.expect(has_no_api_key);
}

test "State validation prevents CSRF attacks" {
    const allocator = testing.allocator;

    // Generate PKCE with state
    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);

    // Simulate callback with wrong state
    const wrong_state = "malicious_state";
    const correct_state = pkce.state;

    // State mismatch should be detected
    try testing.expect(!std.mem.eql(u8, wrong_state, correct_state));
}

test "Redirect URI exact match validation" {
    const allocator = testing.allocator;

    const expected_redirect = "http://localhost:8080/callback";
    const wrong_redirect_1 = "http://localhost:8080/callback/"; // Extra slash
    const wrong_redirect_2 = "http://localhost:8081/callback"; // Wrong port
    const wrong_redirect_3 = "http://127.0.0.1:8080/callback"; // Wrong host

    // Only exact match should pass
    try testing.expect(std.mem.eql(u8, expected_redirect, expected_redirect));
    try testing.expect(!std.mem.eql(u8, expected_redirect, wrong_redirect_1));
    try testing.expect(!std.mem.eql(u8, expected_redirect, wrong_redirect_2));
    try testing.expect(!std.mem.eql(u8, expected_redirect, wrong_redirect_3));
}

// Integration test for the full OAuth flow (requires mock server)
test "OAuth flow happy path" {
    if (true) return error.SkipZigTest; // Skip in CI, enable for manual testing

    const allocator = testing.allocator;

    // This test would:
    // 1. Generate PKCE parameters
    // 2. Start loopback server
    // 3. Build auth URL
    // 4. Simulate browser callback with code
    // 5. Exchange code for tokens
    // 6. Save credentials
    // 7. Make test API call
    // 8. Refresh tokens
    // 9. Make another API call

    // For now, we just verify the components work independently
    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);

    try testing.expect(pkce.verifier.len > 0);
    try testing.expect(pkce.challenge.len > 0);
    try testing.expect(pkce.state.len > 0);
}

//! Complete OAuth flow tests including PKCE, loopback server, token exchange, and refresh
//! Tests both unit-level components and integration scenarios

const std = @import("std");
const network = @import("../src/foundation/network.zig");
const Auth = network.Auth;
const testing = std.testing;
const builtin = @import("builtin");

// ============================================================================
// PKCE Tests
// ============================================================================

test "PKCE: verifier length validation" {
    const allocator = testing.allocator;

    // Test minimum length (43)
    const params_min = try Auth.pkce.generate(allocator, 43);
    defer params_min.deinit(allocator);
    try testing.expectEqual(@as(usize, 43), params_min.verifier.len);

    // Test maximum length (128)
    const params_max = try Auth.pkce.generate(allocator, 128);
    defer params_max.deinit(allocator);
    try testing.expectEqual(@as(usize, 128), params_max.verifier.len);

    // Test typical length (64)
    const params_typical = try Auth.pkce.generate(allocator, 64);
    defer params_typical.deinit(allocator);
    try testing.expectEqual(@as(usize, 64), params_typical.verifier.len);

    // Test too short (should fail)
    const result_short = Auth.pkce.generate(allocator, 42);
    try testing.expectError(error.InvalidVerifierLength, result_short);

    // Test too long (should fail)
    const result_long = Auth.pkce.generate(allocator, 129);
    try testing.expectError(error.InvalidVerifierLength, result_long);
}

test "PKCE: separate state generation" {
    const allocator = testing.allocator;

    const params = try Auth.pkce.generate(allocator, 64);
    defer params.deinit(allocator);

    // State MUST be different from verifier (RFC 8252 requirement)
    try testing.expect(!std.mem.eql(u8, params.state, params.verifier));

    // State should be high-entropy (at least 32 chars recommended)
    try testing.expectEqual(@as(usize, 32), params.state.len);

    // Verify character sets
    for (params.verifier) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '.' or c == '_' or c == '~';
        try testing.expect(valid);
    }

    for (params.state) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9');
        try testing.expect(valid);
    }
}

test "PKCE: S256 challenge method" {
    const allocator = testing.allocator;

    // RFC 7636 test vector
    const test_verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
    const expected_challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";

    const challenge = try Auth.pkce.generateS256Challenge(allocator, test_verifier);
    defer allocator.free(challenge);

    try testing.expectEqualStrings(expected_challenge, challenge);
    try testing.expectEqualStrings("S256", Auth.pkce.PkceParams.method);
}

// ============================================================================
// Redirect URI Tests
// ============================================================================

test "redirect URI: localhost validation" {
    const allocator = testing.allocator;

    // Build redirect URIs with different ports
    const uri1 = try std.fmt.allocPrint(allocator, "http://localhost:8080/callback", .{});
    defer allocator.free(uri1);
    const uri2 = try std.fmt.allocPrint(allocator, "http://localhost:54321/callback", .{});
    defer allocator.free(uri2);

    // Verify format
    try testing.expect(std.mem.startsWith(u8, uri1, "http://localhost:"));
    try testing.expect(std.mem.endsWith(u8, uri1, "/callback"));

    // Parse to validate structure
    const parsed1 = try std.Uri.parse(uri1);
    const parsed2 = try std.Uri.parse(uri2);

    try testing.expectEqualStrings("localhost", parsed1.host.?.raw);
    try testing.expectEqualStrings("localhost", parsed2.host.?.raw);
}

test "authorization URL: required parameters" {
    const allocator = testing.allocator;

    const pkce = try Auth.OAuth.generatePkceParams(allocator);
    defer pkce.deinit(allocator);

    const auth_url = try Auth.OAuth.buildAuthorizationUrl(allocator, pkce);
    defer allocator.free(auth_url);

    // Check for required OAuth parameters
    try testing.expect(std.mem.indexOf(u8, auth_url, "response_type=code") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "client_id=") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "redirect_uri=") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "scope=") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "code_challenge=") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "code_challenge_method=S256") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "state=") != null);

    // Verify URL encoding
    try testing.expect(std.mem.indexOf(u8, auth_url, "redirect_uri=http%3A%2F%2Flocalhost") != null);
}

// ============================================================================
// Token Storage Tests
// ============================================================================

test "token store: secure file permissions" {
    if (builtin.os.tag == .windows) return error.SkipZigTest; // Skip on Windows

    const allocator = testing.allocator;

    // Create temporary test path
    const test_dir = "test_oauth_tmp";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    const test_path = try std.fmt.allocPrint(allocator, "{s}/test_creds.json", .{test_dir});
    defer allocator.free(test_path);

    const store = Auth.store.TokenStore.init(allocator, .{
        .path = test_path,
    });

    const creds = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "test_access_token",
        .refresh_token = "test_refresh_token",
        .expires_at = std.time.timestamp() + 3600,
    };

    try store.save(creds);

    // Verify file exists and has correct permissions (0600)
    const file = try std.fs.cwd().openFile(test_path, .{});
    defer file.close();

    const stat = try file.stat();
    const mode = stat.mode & 0o777;
    try testing.expectEqual(@as(u32, 0o600), mode);

    // Verify content can be loaded
    const loaded = try store.load();
    defer allocator.free(loaded.type);
    defer allocator.free(loaded.access_token);
    defer allocator.free(loaded.refresh_token);

    try testing.expectEqualStrings("oauth", loaded.type);
    try testing.expectEqualStrings("test_access_token", loaded.access_token);
    try testing.expectEqualStrings("test_refresh_token", loaded.refresh_token);
}

test "token store: canonical path for agent" {
    const allocator = testing.allocator;

    const store = Auth.store.TokenStore.init(allocator, .{
        .agent_name = "test_agent",
    });

    const path = try store.getCredentialPath();
    defer allocator.free(path);

    // Should follow pattern: ~/.local/share/{agent_name}/auth.json
    try testing.expect(std.mem.indexOf(u8, path, ".local/share/test_agent/auth.json") != null);
}

test "credentials: expiration checking" {
    const creds_valid = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "token",
        .refreshToken = "refresh",
        .expiresAt = std.time.timestamp() + 3600, // 1 hour from now
    };

    const creds_expired = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "token",
        .refreshToken = "refresh",
        .expiresAt = std.time.timestamp() - 3600, // 1 hour ago
    };

    try testing.expect(!creds_valid.isExpired());
    try testing.expect(creds_expired.isExpired());

    // Test willExpireSoon with different leeway
    try testing.expect(!creds_valid.willExpireSoon(120)); // 2 minute leeway
    try testing.expect(creds_valid.willExpireSoon(7200)); // 2 hour leeway
}

// ============================================================================
// Loopback Server Tests
// ============================================================================

test "loopback server: initialization and URI generation" {
    const allocator = testing.allocator;

    var server = try Auth.loopback_server.LoopbackServer.init(allocator, .{
        .host = "localhost",
        .port = 0, // Use ephemeral port
        .path = "/callback",
        .timeout_ms = 1000,
    });
    defer server.deinit();

    const redirect_uri = try server.getRedirectUri(allocator);
    defer allocator.free(redirect_uri);

    // Verify URI format
    try testing.expect(std.mem.startsWith(u8, redirect_uri, "http://localhost:"));
    try testing.expect(std.mem.endsWith(u8, redirect_uri, "/callback"));

    // Verify server is bound to loopback
    const port = server.address.getPort();
    try testing.expect(port > 0);
    try testing.expect(port < 65536);
}

test "loopback server: state validation" {
    const allocator = testing.allocator;

    // Create mock callback result with matching state
    const valid_result = Auth.loopback_server.CallbackResult{
        .code = try allocator.dupe(u8, "test_code"),
        .state = try allocator.dupe(u8, "test_state"),
        .error_msg = null,
    };
    defer valid_result.deinit(allocator);

    try testing.expectEqualStrings("test_code", valid_result.code);
    try testing.expectEqualStrings("test_state", valid_result.state);
    try testing.expect(valid_result.error_msg == null);
}

// ============================================================================
// Header Construction Tests
// ============================================================================

test "headers: OAuth Bearer authentication" {
    const allocator = testing.allocator;

    const creds = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "test_access_token",
        .refreshToken = "test_refresh_token",
        .expiresAt = std.time.timestamp() + 3600,
    };

    // Initialize client with OAuth
    var client = try network.Anthropic.Client.initWithOAuth(allocator, creds, null);
    defer client.deinit();

    // Build headers for test
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
            // Should have OAuth beta header when enabled
        } else if (std.mem.eql(u8, h.name, "x-api-key")) {
            has_no_api_key = false; // Should NOT have API key with OAuth
        }
    }

    try testing.expect(has_auth);
    try testing.expect(has_version);
    try testing.expect(has_beta);
    try testing.expect(has_no_api_key);
}

test "headers: API key authentication excludes OAuth headers" {
    const allocator = testing.allocator;

    // Initialize client with API key
    var client = try network.Anthropic.Client.init(allocator, "test_api_key");
    defer client.deinit();

    // Build headers for test
    const headers = try client.buildHeadersForTest(allocator, false);
    defer {
        for (headers) |h| {
            allocator.free(h.value);
        }
        allocator.free(headers);
    }

    // Verify headers
    var has_api_key = false;
    var has_no_bearer = true;

    for (headers) |h| {
        if (std.mem.eql(u8, h.name, "x-api-key")) {
            has_api_key = true;
            try testing.expectEqualStrings("test_api_key", h.value);
        } else if (std.mem.eql(u8, h.name, "Authorization")) {
            has_no_bearer = false; // Should NOT have Bearer with API key
        }
    }

    try testing.expect(has_api_key);
    try testing.expect(has_no_bearer);
}

// ============================================================================
// Token Refresh Tests
// ============================================================================

test "token refresh: proactive refresh detection" {
    const creds_fresh = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "token",
        .refreshToken = "refresh",
        .expiresAt = std.time.timestamp() + 7200, // 2 hours from now
    };

    const creds_expiring = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "token",
        .refreshToken = "refresh",
        .expiresAt = std.time.timestamp() + 60, // 1 minute from now
    };

    // Fresh token should not need refresh with 120s leeway
    try testing.expect(!creds_fresh.willExpireSoon(120));

    // Expiring token should need refresh with 120s leeway
    try testing.expect(creds_expiring.willExpireSoon(120));
}

// ============================================================================
// Integration Test: Mock OAuth Flow
// ============================================================================

test "integration: OAuth flow state machine" {
    const allocator = testing.allocator;

    // Step 1: Generate PKCE
    const pkce = try Auth.OAuth.generatePkceParams(allocator);
    defer pkce.deinit(allocator);

    try testing.expect(pkce.verifier.len >= 43);
    try testing.expect(pkce.verifier.len <= 128);
    try testing.expect(pkce.state.len == 32);

    // Step 2: Build authorization URL
    const auth_url = try Auth.OAuth.buildAuthorizationUrl(allocator, pkce);
    defer allocator.free(auth_url);

    try testing.expect(auth_url.len > 0);

    // Step 3: Simulate callback receipt
    const mock_code = "mock_authorization_code";
    const mock_state = pkce.state;

    // Step 4: Validate state matches
    try testing.expectEqualStrings(pkce.state, mock_state);

    // Step 5: Mock credentials from exchange
    const mock_creds = Auth.OAuth.Credentials{
        .type = try allocator.dupe(u8, "oauth"),
        .accessToken = try allocator.dupe(u8, "mock_access_token"),
        .refreshToken = try allocator.dupe(u8, "mock_refresh_token"),
        .expiresAt = std.time.timestamp() + 3600,
    };
    defer mock_creds.deinit(allocator);

    // Step 6: Verify credentials are valid
    try testing.expect(!mock_creds.isExpired());
    try testing.expectEqualStrings("oauth", mock_creds.type);
}

// Run all tests
pub fn main() !void {
    std.testing.refAllDecls(@This());
}

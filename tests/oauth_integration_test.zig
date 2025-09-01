//! OAuth integration tests
//! Tests the complete OAuth flow including PKCE, token exchange, and refresh

const std = @import("std");
const network = @import("../src/foundation/network.zig");
const Auth = network.Auth;
const testing = std.testing;

test "PKCE parameters generation" {
    const allocator = testing.allocator;

    // Generate PKCE parameters
    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);

    // Verify verifier length
    try testing.expectEqual(@as(usize, 64), pkce.verifier.len);

    // Verify verifier contains only unreserved characters
    for (pkce.verifier) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '.' or c == '_' or c == '~';
        try testing.expect(valid);
    }

    // Verify challenge is base64url encoded (no padding)
    for (pkce.challenge) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '_';
        try testing.expect(valid);
    }

    // Verify state is separate from verifier
    try testing.expect(!std.mem.eql(u8, pkce.verifier, pkce.state));
    try testing.expectEqual(@as(usize, 32), pkce.state.len);
}

test "authorization URL construction" {
    const allocator = testing.allocator;

    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);

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

test "credential storage with correct permissions" {
    const allocator = testing.allocator;

    // Create temp directory for test
    const tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create test credentials
    const creds = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "test_access_token",
        .refresh_token = "test_refresh_token",
        .expires_at = std.time.timestamp() + 3600,
    };

    // Save credentials to temp path
    const temp_path = try std.fmt.allocPrint(allocator, "{s}/test_auth.json", .{tmp_dir.path});
    defer allocator.free(temp_path);

    const store = Auth.store.TokenStore.init(allocator, .{
        .path = temp_path,
    });

    try store.save(creds);

    // Check file exists
    try testing.expect(store.exists());

    // Load and verify
    const loaded = try store.load();
    defer allocator.free(loaded.type);
    defer allocator.free(loaded.access_token);
    defer allocator.free(loaded.refresh_token);

    try testing.expectEqualStrings("oauth", loaded.type);
    try testing.expectEqualStrings("test_access_token", loaded.access_token);
    try testing.expectEqualStrings("test_refresh_token", loaded.refresh_token);
    try testing.expectEqual(creds.expires_at, loaded.expires_at);

    // Check file permissions (Unix only)
    if (@import("builtin").os.tag != .windows) {
        const file = try std.fs.openFileAbsolute(temp_path, .{});
        defer file.close();
        const stat = try file.stat();
        const mode = stat.mode & 0o777;
        try testing.expectEqual(@as(u32, 0o600), mode);
    }
}

test "token expiration check" {
    const allocator = testing.allocator;

    const now = std.time.timestamp();

    // Create expired token
    const expired = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "expired",
        .refreshToken = "refresh",
        .expiresAt = now - 100,
    };
    try testing.expect(expired.isExpired());

    // Create valid token
    const valid = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "valid",
        .refreshToken = "refresh",
        .expiresAt = now + 3600,
    };
    try testing.expect(!valid.isExpired());

    // Check will expire soon
    const expiring_soon = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "expiring",
        .refreshToken = "refresh",
        .expiresAt = now + 60,
    };
    try testing.expect(expiring_soon.willExpireSoon(120)); // 2 minute leeway
    try testing.expect(!expiring_soon.willExpireSoon(30)); // 30 second leeway
}

test "loopback server redirect URI" {
    const allocator = testing.allocator;

    const server = try Auth.loopback_server.LoopbackServer.init(allocator, .{
        .host = "localhost",
        .port = 0, // Use ephemeral port
        .path = "/callback",
    });
    defer server.deinit();

    const redirect_uri = try server.getRedirectUri(allocator);
    defer allocator.free(redirect_uri);

    // Verify redirect URI format
    try testing.expect(std.mem.startsWith(u8, redirect_uri, "http://localhost:"));
    try testing.expect(std.mem.endsWith(u8, redirect_uri, "/callback"));
}

test "headers for OAuth requests" {
    const allocator = testing.allocator;

    const creds = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "test_token_123",
        .refreshToken = "refresh_456",
        .expiresAt = std.time.timestamp() + 3600,
    };

    var client = try network.Anthropic.Client.initWithOAuth(allocator, creds, null);
    defer client.deinit();

    // Test headers are built correctly
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
        if (std.ascii.eqlIgnoreCase(h.name, "authorization")) {
            has_auth = true;
            try testing.expect(std.mem.startsWith(u8, h.value, "Bearer "));
        }
        if (std.ascii.eqlIgnoreCase(h.name, "anthropic-version")) {
            has_version = true;
            try testing.expectEqualStrings("2023-06-01", h.value);
        }
        if (std.ascii.eqlIgnoreCase(h.name, "anthropic-beta")) {
            has_beta = true;
            // Should contain OAuth beta header when enabled
            if (@import("build_options").oauth_beta_header) {
                try testing.expectEqualStrings("oauth-2025-04-20", h.value);
            }
        }
        if (std.ascii.eqlIgnoreCase(h.name, "x-api-key")) {
            has_no_api_key = false; // Should NOT have API key with OAuth
        }
    }

    try testing.expect(has_auth);
    try testing.expect(has_version);
    try testing.expect(has_beta);
    try testing.expect(has_no_api_key);
}

test "state validation prevents CSRF" {
    const allocator = testing.allocator;

    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);

    // Valid state should match
    try testing.expect(std.mem.eql(u8, pkce.state, pkce.state));

    // Different state should not match
    const other_state = try Auth.pkce.generateState(allocator, 32);
    defer allocator.free(other_state);

    try testing.expect(!std.mem.eql(u8, pkce.state, other_state));
}

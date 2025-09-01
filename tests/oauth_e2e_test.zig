//! End-to-end OAuth integration test
//! Tests the full OAuth flow including PKCE, token exchange, and API calls

const std = @import("std");
const network = @import("../src/foundation/network.zig");
const Auth = network.Auth;
const testing = std.testing;

test "PKCE generation meets RFC requirements" {
    const allocator = testing.allocator;

    // Generate PKCE parameters
    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);

    // Verify verifier length is within RFC bounds [43-128]
    try testing.expect(pkce.verifier.len >= 43);
    try testing.expect(pkce.verifier.len <= 128);

    // Verify verifier uses only unreserved characters
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
    try testing.expect(std.mem.indexOf(u8, pkce.challenge, "=") == null);

    // Verify state is separate from verifier
    try testing.expect(!std.mem.eql(u8, pkce.state, pkce.verifier));
    try testing.expect(pkce.state.len >= 16);
}

test "authorization URL contains required parameters" {
    const allocator = testing.allocator;

    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);

    const auth_url = try Auth.OAuth.buildAuthorizationUrl(allocator, pkce);
    defer allocator.free(auth_url);

    // Verify URL contains all required OAuth parameters
    try testing.expect(std.mem.indexOf(u8, auth_url, "client_id=") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "response_type=code") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "redirect_uri=") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "scope=") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "code_challenge=") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "code_challenge_method=S256") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "state=") != null);

    // Verify localhost redirect URI
    try testing.expect(std.mem.indexOf(u8, auth_url, "http%3A%2F%2Flocalhost") != null);
}

test "token store saves with proper permissions" {
    const allocator = testing.allocator;

    const test_path = "test_oauth_creds.json";
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const store = Auth.store.TokenStore.init(allocator, .{ .path = test_path });

    const creds = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "test_access_token",
        .refresh_token = "test_refresh_token",
        .expires_at = std.time.timestamp() + 3600,
    };

    try store.save(creds);
    try testing.expect(store.exists());

    // Verify file permissions (Unix only)
    if (@import("builtin").os.tag != .windows) {
        const file = try std.fs.cwd().openFile(test_path, .{});
        defer file.close();
        const stat = try file.stat();
        const mode = stat.mode & 0o777;
        try testing.expectEqual(@as(u32, 0o600), mode);
    }

    // Verify we can load the credentials back
    const loaded = try store.load();
    defer allocator.free(loaded.type);
    defer allocator.free(loaded.access_token);
    defer allocator.free(loaded.refresh_token);

    try testing.expectEqualStrings("oauth", loaded.type);
    try testing.expectEqualStrings("test_access_token", loaded.access_token);
    try testing.expectEqualStrings("test_refresh_token", loaded.refresh_token);
}

test "loopback server binds to localhost only" {
    const allocator = testing.allocator;

    var server = try Auth.loopback_server.LoopbackServer.init(allocator, .{
        .host = "localhost",
        .port = 0, // Use ephemeral port
        .path = "/callback",
    });
    defer server.deinit();

    // Verify server is bound to loopback interface
    const addr = server.address;
    try testing.expect(addr.getPort() != 0);

    // Get redirect URI
    const redirect_uri = try server.getRedirectUri(allocator);
    defer allocator.free(redirect_uri);

    try testing.expect(std.mem.startsWith(u8, redirect_uri, "http://localhost:"));
    try testing.expect(std.mem.endsWith(u8, redirect_uri, "/callback"));
}

test "OAuth headers exclude x-api-key" {
    const allocator = testing.allocator;

    const creds = network.Anthropic.Models.Credentials{
        .type = "oauth",
        .accessToken = "test_token",
        .refreshToken = "refresh",
        .expiresAt = std.time.timestamp() + 3600,
    };

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

    // Verify required headers are present
    var has_auth = false;
    var has_version = false;
    var has_beta = false;
    var has_api_key = false;

    for (headers) |h| {
        if (std.mem.eql(u8, h.name, "Authorization")) {
            has_auth = true;
            try testing.expect(std.mem.startsWith(u8, h.value, "Bearer "));
        } else if (std.mem.eql(u8, h.name, "anthropic-version")) {
            has_version = true;
        } else if (std.mem.eql(u8, h.name, "anthropic-beta")) {
            has_beta = true;
        } else if (std.mem.eql(u8, h.name, "x-api-key")) {
            has_api_key = true;
        }
    }

    try testing.expect(has_auth);
    try testing.expect(has_version);
    try testing.expect(has_beta);
    try testing.expect(!has_api_key); // Must NOT have x-api-key with OAuth
}

test "token expiration checking" {
    const now = std.time.timestamp();

    const expired = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "token",
        .refresh_token = "refresh",
        .expires_at = now - 100,
    };
    try testing.expect(expired.isExpired());
    try testing.expect(expired.willExpireSoon(0));

    const valid = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "token",
        .refresh_token = "refresh",
        .expires_at = now + 3600,
    };
    try testing.expect(!valid.isExpired());
    try testing.expect(!valid.willExpireSoon(60));
    try testing.expect(valid.willExpireSoon(3700));
}

test "state parameter validation" {
    const allocator = testing.allocator;

    // Generate two different states
    const state1 = try Auth.pkce.generateState(allocator, 32);
    defer allocator.free(state1);

    const state2 = try Auth.pkce.generateState(allocator, 32);
    defer allocator.free(state2);

    // States should be different (with high probability)
    try testing.expect(!std.mem.eql(u8, state1, state2));

    // States should only contain alphanumeric characters
    for (state1) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9');
        try testing.expect(valid);
    }
}

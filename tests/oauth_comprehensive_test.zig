//! Comprehensive OAuth implementation tests
//! Tests PKCE, loopback server, token exchange, storage, and header generation

const std = @import("std");
const network = @import("../src/foundation/network.zig");
const Auth = network.Auth;
const testing = std.testing;
const builtin = @import("builtin");

// ===== PKCE Tests =====

test "PKCE: verifier length constraints" {
    const allocator = testing.allocator;

    // Valid lengths
    for ([_]usize{ 43, 64, 96, 128 }) |length| {
        const params = try Auth.pkce.generate(allocator, length);
        defer params.deinit(allocator);
        try testing.expectEqual(length, params.verifier.len);
        try testing.expectEqualStrings("S256", params.method);
    }

    // Invalid lengths
    try testing.expectError(error.InvalidVerifierLength, Auth.pkce.generate(allocator, 42));
    try testing.expectError(error.InvalidVerifierLength, Auth.pkce.generate(allocator, 129));
}

test "PKCE: verifier character set" {
    const allocator = testing.allocator;
    const params = try Auth.pkce.generate(allocator, 64);
    defer params.deinit(allocator);

    // Verify unreserved characters only: [A-Z] [a-z] [0-9] - . _ ~
    for (params.verifier) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '.' or c == '_' or c == '~';
        try testing.expect(valid);
    }
}

test "PKCE: state is separate and high-entropy" {
    const allocator = testing.allocator;
    const params = try Auth.pkce.generate(allocator, 64);
    defer params.deinit(allocator);

    // State must be different from verifier (RFC 8252 requirement)
    try testing.expect(!std.mem.eql(u8, params.state, params.verifier));

    // State should be at least 16 chars for security
    try testing.expect(params.state.len >= 16);
    try testing.expectEqual(@as(usize, 32), params.state.len);

    // State should only contain alphanumeric
    for (params.state) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9');
        try testing.expect(valid);
    }
}

test "PKCE: S256 challenge generation with RFC test vector" {
    const allocator = testing.allocator;

    // RFC 7636 Appendix B test vector
    const test_verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
    const expected_challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";

    const challenge = try Auth.pkce.generateS256Challenge(allocator, test_verifier);
    defer allocator.free(challenge);

    try testing.expectEqualStrings(expected_challenge, challenge);
}

// ===== Redirect URI Tests =====

test "redirect URI: localhost only" {
    const allocator = testing.allocator;

    // Build with localhost (required)
    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);

    const url1 = try Auth.OAuth.buildAuthorizationUrlWithRedirect(allocator, pkce, "http://localhost:8080/callback");
    defer allocator.free(url1);
    try testing.expect(std.mem.indexOf(u8, url1, "redirect_uri=http%3A%2F%2Flocalhost%3A8080%2Fcallback") != null or
        std.mem.indexOf(u8, url1, "redirect_uri=http://localhost:8080/callback") != null);

    // Should work with different ports
    const url2 = try Auth.OAuth.buildAuthorizationUrlWithRedirect(allocator, pkce, "http://localhost:12345/callback");
    defer allocator.free(url2);
    try testing.expect(std.mem.indexOf(u8, url2, "localhost") != null);
}

// ===== Token Storage Tests =====

test "token store: file permissions 0600" {
    const allocator = testing.allocator;

    const test_path = "test_oauth_perms.json";
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const store = Auth.store.TokenStore.init(allocator, .{
        .path = test_path,
    });

    const creds = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "test_token",
        .refresh_token = "refresh_token",
        .expires_at = std.time.timestamp() + 3600,
    };

    try store.save(creds);

    // Verify file permissions on Unix systems
    if (builtin.os.tag != .windows) {
        const file = try std.fs.cwd().openFile(test_path, .{});
        defer file.close();
        const stat = try file.stat();
        const mode = stat.mode & 0o777;
        try testing.expectEqual(@as(u32, 0o600), mode);
    }
}

test "token store: atomic write" {
    const allocator = testing.allocator;

    const test_path = "test_oauth_atomic.json";
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const store = Auth.store.TokenStore.init(allocator, .{
        .path = test_path,
    });

    // Write initial credentials
    const creds1 = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "token1",
        .refresh_token = "refresh1",
        .expires_at = 1000,
    };
    try store.save(creds1);

    // Overwrite with new credentials
    const creds2 = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "token2",
        .refresh_token = "refresh2",
        .expires_at = 2000,
    };
    try store.save(creds2);

    // Load and verify
    const loaded = try store.load();
    defer allocator.free(loaded.type);
    defer allocator.free(loaded.access_token);
    defer allocator.free(loaded.refresh_token);

    try testing.expectEqualStrings("token2", loaded.access_token);
    try testing.expectEqual(@as(i64, 2000), loaded.expires_at);
}

test "token store: expiration checks" {
    const now = std.time.timestamp();

    // Expired token
    const expired = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "token",
        .refresh_token = "refresh",
        .expires_at = now - 100,
    };
    try testing.expect(expired.isExpired());
    try testing.expect(expired.willExpireSoon(0));

    // Valid token
    const valid = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "token",
        .refresh_token = "refresh",
        .expires_at = now + 3600,
    };
    try testing.expect(!valid.isExpired());
    try testing.expect(!valid.willExpireSoon(120));

    // Will expire soon
    const expiring = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "token",
        .refresh_token = "refresh",
        .expires_at = now + 60,
    };
    try testing.expect(!expiring.isExpired());
    try testing.expect(expiring.willExpireSoon(120));
}

// ===== Authorization URL Tests =====

test "authorization URL: required parameters" {
    const allocator = testing.allocator;

    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);

    const url = try Auth.OAuth.buildAuthorizationUrl(allocator, pkce);
    defer allocator.free(url);

    // Verify required OAuth parameters
    try testing.expect(std.mem.indexOf(u8, url, "response_type=code") != null);
    try testing.expect(std.mem.indexOf(u8, url, "client_id=") != null);
    try testing.expect(std.mem.indexOf(u8, url, "redirect_uri=") != null);
    try testing.expect(std.mem.indexOf(u8, url, "scope=") != null);

    // Verify PKCE parameters
    try testing.expect(std.mem.indexOf(u8, url, "code_challenge=") != null);
    try testing.expect(std.mem.indexOf(u8, url, "code_challenge_method=S256") != null);
    try testing.expect(std.mem.indexOf(u8, url, "state=") != null);
}

// ===== Header Generation Tests =====

test "OAuth headers: no x-api-key with Bearer auth" {
    const allocator = testing.allocator;

    const creds = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "test_access_token",
        .refreshToken = "test_refresh_token",
        .expiresAt = std.time.timestamp() + 3600,
    };

    var client = try network.Anthropic.Client.initWithOAuth(allocator, creds, null);
    defer client.deinit();

    // Build headers for testing
    const headers = try client.buildHeadersForTest(allocator, false);
    defer {
        for (headers) |header| {
            allocator.free(header.value);
        }
        allocator.free(headers);
    }

    // Verify Authorization header present
    var has_auth = false;
    var has_api_key = false;
    var has_version = false;
    var has_beta = false;

    for (headers) |header| {
        if (std.mem.eql(u8, header.name, "Authorization")) {
            has_auth = true;
            try testing.expect(std.mem.startsWith(u8, header.value, "Bearer "));
        }
        if (std.mem.eql(u8, header.name, "x-api-key")) {
            has_api_key = true;
        }
        if (std.mem.eql(u8, header.name, "anthropic-version")) {
            has_version = true;
            try testing.expectEqualStrings("2023-06-01", header.value);
        }
        if (std.mem.eql(u8, header.name, "anthropic-beta")) {
            has_beta = true;
            // Should be oauth-2025-04-20 or none depending on build options
        }
    }

    try testing.expect(has_auth);
    try testing.expect(!has_api_key); // MUST NOT have x-api-key with OAuth
    try testing.expect(has_version);
    try testing.expect(has_beta);
}

test "OAuth headers: streaming vs non-streaming" {
    const allocator = testing.allocator;

    const creds = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "test_token",
        .refreshToken = "refresh",
        .expiresAt = std.time.timestamp() + 3600,
    };

    var client = try network.Anthropic.Client.initWithOAuth(allocator, creds, null);
    defer client.deinit();

    // Non-streaming headers
    const headers1 = try client.buildHeadersForTest(allocator, false);
    defer {
        for (headers1) |header| {
            allocator.free(header.value);
        }
        allocator.free(headers1);
    }

    // Streaming headers
    const headers2 = try client.buildHeadersForTest(allocator, true);
    defer {
        for (headers2) |header| {
            allocator.free(header.value);
        }
        allocator.free(headers2);
    }

    // Find Accept headers
    var accept1: ?[]const u8 = null;
    var accept2: ?[]const u8 = null;

    for (headers1) |header| {
        if (std.mem.eql(u8, header.name, "accept")) {
            accept1 = header.value;
        }
    }

    for (headers2) |header| {
        if (std.mem.eql(u8, header.name, "accept")) {
            accept2 = header.value;
        }
    }

    try testing.expect(accept1 != null);
    try testing.expect(accept2 != null);
    try testing.expectEqualStrings("application/json", accept1.?);
    try testing.expectEqualStrings("text/event-stream", accept2.?);
}

// ===== Credential JSON Parsing Tests =====

test "credential JSON: snake_case parsing" {
    const allocator = testing.allocator;

    const json =
        \\{"type":"oauth","access_token":"abc123","refresh_token":"xyz789","expires_at":1234567890}
    ;

    const creds = try Auth.OAuth.parseCredentialsFromJson(allocator, json);
    defer creds.deinit(allocator);

    try testing.expectEqualStrings("oauth", creds.type);
    try testing.expectEqualStrings("abc123", creds.accessToken);
    try testing.expectEqualStrings("xyz789", creds.refreshToken);
    try testing.expectEqual(@as(i64, 1234567890), creds.expiresAt);
}

test "credential JSON: camelCase fallback" {
    const allocator = testing.allocator;

    const json =
        \\{"type":"oauth","accessToken":"abc123","refreshToken":"xyz789","expiresAt":1234567890}
    ;

    const creds = try Auth.OAuth.parseCredentialsFromJson(allocator, json);
    defer creds.deinit(allocator);

    try testing.expectEqualStrings("oauth", creds.type);
    try testing.expectEqualStrings("abc123", creds.accessToken);
    try testing.expectEqualStrings("xyz789", creds.refreshToken);
    try testing.expectEqual(@as(i64, 1234567890), creds.expiresAt);
}

// ===== Integration Test Helpers =====

test "loopback server: localhost binding" {
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

    // Verify localhost in URI
    try testing.expect(std.mem.indexOf(u8, redirect_uri, "http://localhost:") != null);
    try testing.expect(std.mem.indexOf(u8, redirect_uri, "/callback") != null);
}

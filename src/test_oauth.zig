//! OAuth flow integration tests

const std = @import("std");
const testing = std.testing;
const foundation = @import("foundation/foundation.zig");
const network = foundation.network;
const Auth = network.Auth;

test "PKCE generation" {
    const allocator = testing.allocator;

    // Generate PKCE parameters
    const params = try Auth.pkce.generate(allocator, 64);
    defer params.deinit(allocator);

    // Verify lengths
    try testing.expectEqual(@as(usize, 64), params.verifier.len);
    try testing.expect(params.challenge.len > 0);
    try testing.expectEqualStrings("S256", params.method);

    // Verify verifier contains only valid characters
    for (params.verifier) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '.' or c == '_' or c == '~';
        try testing.expect(valid);
    }
}

test "state generation" {
    const allocator = testing.allocator;

    const state = try Auth.pkce.generateState(allocator, 32);
    defer allocator.free(state);

    try testing.expectEqual(@as(usize, 32), state.len);

    // Verify state is different from another generation
    const state2 = try Auth.pkce.generateState(allocator, 32);
    defer allocator.free(state2);

    try testing.expect(!std.mem.eql(u8, state, state2));
}

test "authorization URL building" {
    const allocator = testing.allocator;

    const url = try Auth.token_client.buildAuthorizationUrl(
        allocator,
        "https://claude.ai/oauth/authorize",
        "test-client-id",
        "http://localhost:8080/callback",
        "user:inference",
        "test-challenge",
        "test-state",
    );
    defer allocator.free(url);

    // Verify URL contains required parameters
    try testing.expect(std.mem.indexOf(u8, url, "client_id=test-client-id") != null);
    try testing.expect(std.mem.indexOf(u8, url, "response_type=code") != null);
    try testing.expect(std.mem.indexOf(u8, url, "redirect_uri=http%3A%2F%2Flocalhost%3A8080%2Fcallback") != null);
    try testing.expect(std.mem.indexOf(u8, url, "code_challenge=test-challenge") != null);
    try testing.expect(std.mem.indexOf(u8, url, "code_challenge_method=S256") != null);
    try testing.expect(std.mem.indexOf(u8, url, "state=test-state") != null);
}

test "token storage with permissions" {
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

    // Load and verify
    const loaded = try store.load();
    defer allocator.free(loaded.type);
    defer allocator.free(loaded.access_token);
    defer allocator.free(loaded.refresh_token);

    try testing.expectEqualStrings("oauth", loaded.type);
    try testing.expectEqualStrings("test_access_token", loaded.access_token);
    try testing.expectEqualStrings("test_refresh_token", loaded.refresh_token);

    // Check file permissions (Unix only)
    if (@import("builtin").os.tag != .windows) {
        const file = try std.fs.cwd().openFile(test_path, .{});
        defer file.close();
        const stat = try file.stat();
        const mode = stat.mode & 0o777;
        try testing.expectEqual(@as(u32, 0o600), mode);
    }
}

test "token expiration checks" {
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
    try testing.expect(valid.willExpireSoon(4000));
}

test "loopback server initialization" {
    const allocator = testing.allocator;

    var server = try Auth.loopback_server.LoopbackServer.init(allocator, .{
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

test "URL encoding" {
    const allocator = testing.allocator;

    const testCases = .{
        .{ "hello world", "hello%20world" },
        .{ "test@example.com", "test%40example.com" },
        .{ "a+b=c", "a%2Bb%3Dc" },
        .{ "safe-._~", "safe-._~" },
    };

    inline for (testCases) |tc| {
        const encoded = try urlEncode(allocator, tc[0]);
        defer allocator.free(encoded);
        try testing.expectEqualStrings(tc[1], encoded);
    }
}

fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (input) |c| {
        if ((c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '_' or c == '.' or c == '~')
        {
            try result.append(c);
        } else {
            try result.writer().print("%{X:0>2}", .{c});
        }
    }

    return result.toOwnedSlice();
}

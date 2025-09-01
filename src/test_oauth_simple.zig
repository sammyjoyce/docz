//! Simple test to verify OAuth implementation compiles

const std = @import("std");
const foundation = @import("foundation.zig");
const network = foundation.network;
const Auth = network.Auth;

test "OAuth modules compile" {
    const allocator = std.testing.allocator;

    // Test PKCE generation
    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 64), pkce.verifier.len);
    try std.testing.expect(pkce.challenge.len > 0);

    // Test state generation
    const state = try Auth.pkce.generateState(allocator, 32);
    defer allocator.free(state);

    try std.testing.expectEqual(@as(usize, 32), state.len);
}

test "Token store operations" {
    const allocator = std.testing.allocator;

    const test_path = "test_oauth_creds.json";
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const store = Auth.store.TokenStore.init(allocator, .{ .path = test_path });

    const creds = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "test_token",
        .refresh_token = "test_refresh",
        .expires_at = std.time.timestamp() + 3600,
    };

    try store.save(creds);
    try std.testing.expect(store.exists());

    const loaded = try store.load();
    defer allocator.free(loaded.type);
    defer allocator.free(loaded.access_token);
    defer allocator.free(loaded.refresh_token);

    try std.testing.expectEqualStrings("oauth", loaded.type);
    try std.testing.expectEqualStrings("test_token", loaded.access_token);
}

test "Authorization URL building" {
    const allocator = std.testing.allocator;

    const url = try Auth.token_client.buildAuthorizationUrl(
        allocator,
        "https://example.com/authorize",
        "client123",
        "http://localhost:8080/callback",
        "read write",
        "challenge123",
        "state456",
    );
    defer allocator.free(url);

    try std.testing.expect(std.mem.indexOf(u8, url, "client_id=client123") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "response_type=code") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge=challenge123") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "state=state456") != null);
}

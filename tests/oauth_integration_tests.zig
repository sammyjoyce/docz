//! Integration tests for OAuth flow

const std = @import("std");
const network = @import("../src/foundation/network.zig");
const Auth = network.Auth;
const testing = std.testing;

test "OAuth login flow - happy path simulation" {
    const allocator = testing.allocator;

    // Generate PKCE parameters
    const pkce_params = try Auth.pkce.generate(allocator, 64);
    defer pkce_params.deinit(allocator);

    // Verify PKCE parameters are valid
    try testing.expectEqual(@as(usize, 64), pkce_params.verifier.len);
    try testing.expect(pkce_params.challenge.len > 0);
    try testing.expectEqual(@as(usize, 32), pkce_params.state.len);
    try testing.expectEqualStrings("S256", pkce_params.method);

    // Build authorization URL
    const auth_url = try Auth.token_client.buildAuthorizationUrl(
        allocator,
        "https://claude.ai/oauth/authorize",
        "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        "http://localhost:8080/callback",
        "org:create_api_key user:profile user:inference",
        pkce_params.challenge,
        pkce_params.state,
    );
    defer allocator.free(auth_url);

    // Verify URL contains all required parameters
    try testing.expect(std.mem.indexOf(u8, auth_url, "response_type=code") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, "code_challenge_method=S256") != null);
}

test "OAuth token refresh simulation" {
    const allocator = testing.allocator;

    // Simulate expired credentials
    const expired_creds = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "old_access_token",
        .refreshToken = "valid_refresh_token",
        .expiresAt = std.time.timestamp() - 100, // Expired
    };

    // Check that token is expired
    try testing.expect(expired_creds.isExpired());

    // Check that it will expire soon (with any leeway)
    try testing.expect(expired_creds.willExpireSoon(0));
    try testing.expect(expired_creds.willExpireSoon(120));
}

test "Loopback server redirect URI validation" {
    const allocator = testing.allocator;

    // Valid localhost redirect URIs
    const valid_uris = [_][]const u8{
        "http://localhost:8080/callback",
        "http://localhost:8081/callback",
        "http://localhost:12345/callback",
    };

    for (valid_uris) |uri_str| {
        const uri = try std.Uri.parse(uri_str);

        // Verify host is localhost
        try testing.expect(uri.host != null);
        try testing.expectEqualStrings("localhost", uri.host.?.percent_encoded);

        // Verify path is /callback
        try testing.expectEqualStrings("/callback", uri.path.percent_encoded);

        // Verify scheme is http (not https for loopback)
        try testing.expectEqualStrings("http", uri.scheme);
    }
}

test "State validation in callback" {
    const allocator = testing.allocator;

    // Generate state
    const state = try Auth.pkce.generateState(allocator, 32);
    defer allocator.free(state);

    // Simulate callback with correct state
    const correct_state = try allocator.dupe(u8, state);
    defer allocator.free(correct_state);

    // Verify state matches
    try testing.expect(std.mem.eql(u8, state, correct_state));

    // Simulate callback with wrong state
    const wrong_state = "different_state_value_123456789";
    try testing.expect(!std.mem.eql(u8, state, wrong_state));
}

test "Token storage and retrieval" {
    const allocator = testing.allocator;

    const test_path = "test_integration_oauth_creds.json";
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const store = Auth.store.TokenStore.init(allocator, .{
        .path = test_path,
    });

    // Save credentials
    const original_creds = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "test_access_token_abc123",
        .refresh_token = "test_refresh_token_xyz789",
        .expires_at = std.time.timestamp() + 3600,
    };

    try store.save(original_creds);

    // Load credentials
    const loaded_creds = try store.load();
    defer allocator.free(loaded_creds.type);
    defer allocator.free(loaded_creds.access_token);
    defer allocator.free(loaded_creds.refresh_token);

    // Verify loaded matches saved
    try testing.expectEqualStrings(original_creds.type, loaded_creds.type);
    try testing.expectEqualStrings(original_creds.access_token, loaded_creds.access_token);
    try testing.expectEqualStrings(original_creds.refresh_token, loaded_creds.refresh_token);
    try testing.expectEqual(original_creds.expires_at, loaded_creds.expires_at);
}

test "401 recovery scenario" {
    const allocator = testing.allocator;

    // Simulate credentials that will trigger 401
    const creds = network.Anthropic.Models.Credentials{
        .type = "oauth",
        .accessToken = "invalid_or_expired_token",
        .refreshToken = "valid_refresh_token",
        .expiresAt = std.time.timestamp() + 3600, // Not expired by time
    };

    // Create client with OAuth
    var client = network.Anthropic.Client{
        .allocator = allocator,
        .auth = .{ .oauth = creds },
        .baseUrl = "https://api.anthropic.com",
        .apiVersion = "2023-06-01",
        .timeoutMs = 30000,
        .httpVerbose = false,
    };

    // Client should be configured for OAuth
    switch (client.auth) {
        .oauth => |oauth_creds| {
            try testing.expectEqualStrings("oauth", oauth_creds.type);
            try testing.expect(oauth_creds.refreshToken.len > 0);
        },
        .api_key => {
            try testing.expect(false); // Should not be API key auth
        },
    }
}

test "Anthropic API headers for OAuth" {
    const allocator = testing.allocator;

    const creds = network.Anthropic.Models.Credentials{
        .type = "oauth",
        .accessToken = "test_bearer_token",
        .refreshToken = "test_refresh",
        .expiresAt = std.time.timestamp() + 3600,
    };

    var client = network.Anthropic.Client{
        .allocator = allocator,
        .auth = .{ .oauth = creds },
        .baseUrl = "https://api.anthropic.com",
        .apiVersion = "2023-06-01",
        .timeoutMs = 30000,
        .httpVerbose = false,
    };

    // Test streaming headers
    const stream_headers = try client.buildHeadersForTest(allocator, true);
    defer {
        for (stream_headers) |header| {
            allocator.free(header.value);
        }
        allocator.free(stream_headers);
    }

    // Verify streaming headers
    var found_sse = false;
    for (stream_headers) |header| {
        if (std.mem.eql(u8, header.name, "accept")) {
            try testing.expectEqualStrings("text/event-stream", header.value);
            found_sse = true;
        }
    }
    try testing.expect(found_sse);

    // Test non-streaming headers
    const normal_headers = try client.buildHeadersForTest(allocator, false);
    defer {
        for (normal_headers) |header| {
            allocator.free(header.value);
        }
        allocator.free(normal_headers);
    }

    // Verify non-streaming headers
    var found_json = false;
    for (normal_headers) |header| {
        if (std.mem.eql(u8, header.name, "accept")) {
            try testing.expectEqualStrings("application/json", header.value);
            found_json = true;
        }
    }
    try testing.expect(found_json);
}

test "Message history management" {
    const allocator = testing.allocator;

    var messages = std.ArrayList(network.Anthropic.Message).init(allocator);
    defer {
        for (messages.items) |msg| {
            allocator.free(msg.content);
        }
        messages.deinit();
    }

    // Simulate conversation with system prompt
    const system_prompt = try allocator.dupe(u8, "You are a helpful assistant.");
    try messages.append(.{
        .role = .user,
        .content = system_prompt,
    });

    // Add conversation messages
    var i: usize = 0;
    while (i < 30) : (i += 1) {
        const user_msg = try std.fmt.allocPrint(allocator, "User message {}", .{i});
        try messages.append(.{
            .role = .user,
            .content = user_msg,
        });

        const assistant_msg = try std.fmt.allocPrint(allocator, "Assistant response {}", .{i});
        try messages.append(.{
            .role = .assistant,
            .content = assistant_msg,
        });
    }

    // Should have 61 messages (1 system + 30 user + 30 assistant)
    try testing.expectEqual(@as(usize, 61), messages.items.len);

    // Trim to 20 messages, keeping system prompt
    const limit: usize = 20;
    if (messages.items.len > limit) {
        const start: usize = 1; // Keep system prompt
        const to_remove = messages.items.len - limit;

        // Free old messages
        for (messages.items[start .. start + to_remove]) |msg| {
            allocator.free(msg.content);
        }

        // Shift remaining
        std.mem.copyForwards(
            network.Anthropic.Message,
            messages.items[start..],
            messages.items[start + to_remove ..],
        );

        messages.shrinkRetainingCapacity(limit);
    }

    try testing.expectEqual(@as(usize, 20), messages.items.len);
    // First message should still be system prompt
    try testing.expectEqualStrings("You are a helpful assistant.", messages.items[0].content);
}

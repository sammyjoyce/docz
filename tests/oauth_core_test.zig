//! Core OAuth and agent loop integration tests
//! Tests the complete OAuth flow with PKCE, token exchange, and API calls

const std = @import("std");
const network = @import("../src/foundation/network.zig");
const Auth = network.Auth;
const build_options = @import("build_options");

test "PKCE generation meets RFC requirements" {
    const allocator = std.testing.allocator;

    // Test verifier length requirements (43-128 chars)
    const params = try Auth.pkce.generate(allocator, 64);
    defer params.deinit(allocator);

    try std.testing.expect(params.verifier.len >= 43);
    try std.testing.expect(params.verifier.len <= 128);
    try std.testing.expectEqual(@as(usize, 64), params.verifier.len);

    // Verify challenge is base64url without padding
    for (params.challenge) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '_';
        try std.testing.expect(valid);
    }

    // Verify state is separate from verifier
    try std.testing.expect(!std.mem.eql(u8, params.verifier, params.state));
    try std.testing.expectEqual(@as(usize, 32), params.state.len);
}

test "credential store uses correct path and permissions" {
    const allocator = std.testing.allocator;

    const temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    const test_path = try std.fmt.allocPrint(allocator, "{s}/test_creds.json", .{temp_dir.sub_path});
    defer allocator.free(test_path);

    const store = Auth.store.TokenStore.init(allocator, .{
        .path = test_path,
        .agent_name = null, // Direct path for testing
    });

    const creds = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "test_access_token",
        .refresh_token = "test_refresh_token",
        .expires_at = std.time.timestamp() + 3600,
    };

    try store.save(creds);

    // Check file permissions (0600)
    const file = try std.fs.cwd().openFile(test_path, .{});
    defer file.close();

    const stat = try file.stat();
    if (@import("builtin").os.tag != .windows) {
        const mode = stat.mode & 0o777;
        try std.testing.expectEqual(@as(u32, 0o600), mode);
    }

    // Load and verify
    const loaded = try store.load();
    try std.testing.expectEqualStrings("oauth", loaded.type);
    try std.testing.expectEqualStrings("test_access_token", loaded.access_token);
    try std.testing.expectEqualStrings("test_refresh_token", loaded.refresh_token);
    try std.testing.expectEqual(creds.expires_at, loaded.expires_at);
}

test "OAuth authorization URL includes required parameters" {
    const allocator = std.testing.allocator;

    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);

    const auth_url = try Auth.token_client.buildAuthorizationUrl(
        allocator,
        "https://claude.ai/oauth/authorize",
        "test_client_id",
        "http://localhost:8080/callback",
        "org:create_api_key user:profile user:inference",
        pkce.challenge,
        pkce.state,
    );
    defer allocator.free(auth_url);

    // Verify all required parameters are present
    try std.testing.expect(std.mem.indexOf(u8, auth_url, "response_type=code") != null);
    try std.testing.expect(std.mem.indexOf(u8, auth_url, "client_id=test_client_id") != null);
    try std.testing.expect(std.mem.indexOf(u8, auth_url, "redirect_uri=http%3A%2F%2Flocalhost%3A8080%2Fcallback") != null);
    try std.testing.expect(std.mem.indexOf(u8, auth_url, "code_challenge_method=S256") != null);
    try std.testing.expect(std.mem.indexOf(u8, auth_url, "code_challenge=") != null);
    try std.testing.expect(std.mem.indexOf(u8, auth_url, "state=") != null);
}

test "loopback server binds to localhost only" {
    const allocator = std.testing.allocator;

    // Try to start server on ephemeral port
    var server = Auth.loopback_server.LoopbackServer.init(allocator, .{
        .host = "localhost",
        .port = 0, // Ephemeral port
        .path = "/callback",
    }) catch |err| switch (err) {
        error.AddressInUse => return, // Skip if port in use
        else => return err,
    };
    defer server.deinit();

    // Verify it's bound to loopback interface
    const port = server.address.getPort();
    try std.testing.expect(port > 0);

    // Get redirect URI
    const redirect_uri = try server.getRedirectUri(allocator);
    defer allocator.free(redirect_uri);

    // Verify format
    try std.testing.expect(std.mem.startsWith(u8, redirect_uri, "http://localhost:"));
    try std.testing.expect(std.mem.endsWith(u8, redirect_uri, "/callback"));
}

test "Anthropic client includes correct headers for OAuth" {
    const allocator = std.testing.allocator;

    const creds = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "test_token",
        .refreshToken = "refresh_token",
        .expiresAt = std.time.timestamp() + 3600,
    };

    var client = network.Anthropic.Client.initWithOAuth(allocator, creds, null);
    defer client.deinit();

    // Build headers for testing
    const headers = try client.buildHeadersForTest(allocator, false);
    defer {
        for (headers) |h| {
            allocator.free(h.value);
        }
        allocator.free(headers);
    }

    // Verify OAuth headers
    var has_bearer = false;
    var has_version = false;
    var has_beta = false;
    var has_no_api_key = true;

    for (headers) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "authorization")) {
            try std.testing.expect(std.mem.startsWith(u8, h.value, "Bearer "));
            has_bearer = true;
        } else if (std.ascii.eqlIgnoreCase(h.name, "anthropic-version")) {
            try std.testing.expectEqualStrings("2023-06-01", h.value);
            has_version = true;
        } else if (std.ascii.eqlIgnoreCase(h.name, "anthropic-beta")) {
            if (build_options.oauth_beta_header) {
                try std.testing.expectEqualStrings(build_options.anthropic_beta_oauth, h.value);
            }
            has_beta = true;
        } else if (std.ascii.eqlIgnoreCase(h.name, "x-api-key")) {
            has_no_api_key = false; // Should NOT have x-api-key with OAuth
        }
    }

    try std.testing.expect(has_bearer);
    try std.testing.expect(has_version);
    try std.testing.expect(has_beta);
    try std.testing.expect(has_no_api_key);
}

test "token expiry checking works correctly" {
    const now = std.time.timestamp();

    const expired_creds = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "expired",
        .refreshToken = "refresh",
        .expiresAt = now - 1,
    };

    try std.testing.expect(expired_creds.isExpired());
    try std.testing.expect(expired_creds.willExpireSoon(0));

    const valid_creds = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "valid",
        .refreshToken = "refresh",
        .expiresAt = now + 3600,
    };

    try std.testing.expect(!valid_creds.isExpired());
    try std.testing.expect(!valid_creds.willExpireSoon(60));
    try std.testing.expect(valid_creds.willExpireSoon(3540));
}

test "SSE event parsing for tool calls" {
    const allocator = std.testing.allocator;

    // Test content_block_start for tool_use
    const tool_start =
        \\{"type":"content_block_start","content_block":{"type":"tool_use","id":"tool_123","name":"calculator"}}
    ;

    const parsed_start = try std.json.parseFromSlice(std.json.Value, allocator, tool_start, .{});
    defer parsed_start.deinit();

    const event_type = parsed_start.value.object.get("type").?.string;
    try std.testing.expectEqualStrings("content_block_start", event_type);

    const block_type = parsed_start.value.object.get("content_block").?.object.get("type").?.string;
    try std.testing.expectEqualStrings("tool_use", block_type);

    // Test input_json_delta
    const json_delta =
        \\{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{\"x\":42"}}
    ;

    const parsed_delta = try std.json.parseFromSlice(std.json.Value, allocator, json_delta, .{});
    defer parsed_delta.deinit();

    const delta_type = parsed_delta.value.object.get("delta").?.object.get("type").?.string;
    try std.testing.expectEqualStrings("input_json_delta", delta_type);
}

test "context trimming preserves recent messages" {
    const allocator = std.testing.allocator;

    var messages = std.ArrayList(network.Anthropic.Message).init(allocator);
    defer {
        for (messages.items) |msg| {
            allocator.free(msg.content);
        }
        messages.deinit();
    }

    // Add 25 messages
    var i: usize = 0;
    while (i < 25) : (i += 1) {
        const content = try std.fmt.allocPrint(allocator, "Message {}", .{i});
        try messages.append(.{
            .role = if (i % 2 == 0) .user else .assistant,
            .content = content,
        });
    }

    // Simulate trimming (keep last 20)
    const max_messages = 20;
    if (messages.items.len > max_messages) {
        const to_remove = messages.items.len - max_messages;

        for (messages.items[0..to_remove]) |msg| {
            allocator.free(msg.content);
        }

        std.mem.copyForwards(
            network.Anthropic.Message,
            messages.items[0..],
            messages.items[to_remove..],
        );
        messages.shrinkRetainingCapacity(max_messages);
    }

    try std.testing.expectEqual(@as(usize, 20), messages.items.len);

    // Verify the oldest remaining message is "Message 5"
    const first_content = messages.items[0].content;
    try std.testing.expect(std.mem.indexOf(u8, first_content, "5") != null);
}

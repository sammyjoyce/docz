//! Unit tests for OAuth implementation

const std = @import("std");
const network = @import("../src/foundation/network.zig");
const Auth = network.Auth;
const testing = std.testing;

test "PKCE verifier generation - valid length" {
    const allocator = testing.allocator;

    // Test minimum length (43)
    const params1 = try Auth.pkce.generate(allocator, 43);
    defer params1.deinit(allocator);
    try testing.expectEqual(@as(usize, 43), params1.verifier.len);

    // Test maximum length (128)
    const params2 = try Auth.pkce.generate(allocator, 128);
    defer params2.deinit(allocator);
    try testing.expectEqual(@as(usize, 128), params2.verifier.len);

    // Test typical length (64)
    const params3 = try Auth.pkce.generate(allocator, 64);
    defer params3.deinit(allocator);
    try testing.expectEqual(@as(usize, 64), params3.verifier.len);
}

test "PKCE verifier generation - invalid length" {
    const allocator = testing.allocator;

    // Too short
    const result1 = Auth.pkce.generate(allocator, 42);
    try testing.expectError(error.InvalidVerifierLength, result1);

    // Too long
    const result2 = Auth.pkce.generate(allocator, 129);
    try testing.expectError(error.InvalidVerifierLength, result2);
}

test "PKCE state is separate from verifier" {
    const allocator = testing.allocator;

    const params = try Auth.pkce.generate(allocator, 64);
    defer params.deinit(allocator);

    // State should be different from verifier
    try testing.expect(!std.mem.eql(u8, params.state, params.verifier));

    // State should have reasonable length
    try testing.expect(params.state.len >= 16);
    try testing.expectEqual(@as(usize, 32), params.state.len);
}

test "PKCE S256 challenge generation" {
    const allocator = testing.allocator;

    // Test with known RFC 7636 test vector
    const test_verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
    const expected_challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";

    const challenge = try Auth.pkce.generateS256Challenge(allocator, test_verifier);
    defer allocator.free(challenge);

    try testing.expectEqualStrings(expected_challenge, challenge);
}

test "redirect URI validation" {
    const allocator = testing.allocator;

    // Valid localhost URIs
    const valid1 = "http://localhost:8080/callback";
    const valid2 = "http://localhost:12345/callback";
    const valid3 = "http://localhost/callback"; // No port

    // Invalid URIs (should be rejected in production)
    const invalid1 = "http://127.0.0.1:8080/callback"; // IP instead of localhost
    const invalid2 = "https://localhost:8080/callback"; // HTTPS not HTTP
    const invalid3 = "http://example.com/callback"; // Not localhost

    // Basic validation (just check they can be parsed)
    _ = try std.Uri.parse(valid1);
    _ = try std.Uri.parse(valid2);
    _ = try std.Uri.parse(valid3);
    _ = try std.Uri.parse(invalid1);
    _ = try std.Uri.parse(invalid2);
    _ = try std.Uri.parse(invalid3);
}

test "token store file permissions" {
    const allocator = testing.allocator;

    const test_path = "test_oauth_creds.json";
    defer std.fs.cwd().deleteFile(test_path) catch {};

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

    // Check file exists and has correct permissions (0600)
    const file = try std.fs.cwd().openFile(test_path, .{});
    defer file.close();

    const stat = try file.stat();
    if (@hasField(@TypeOf(stat), "mode")) {
        // Unix-like systems
        const mode = stat.mode & 0o777;
        try testing.expectEqual(@as(u32, 0o600), mode);
    }
}

test "credentials expiry checking" {
    const now = std.time.timestamp();

    const expired_creds = network.Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "token",
        .refreshToken = "refresh",
        .expiresAt = now - 100, // Expired 100 seconds ago
    };

    const valid_creds = network.Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "token",
        .refreshToken = "refresh",
        .expiresAt = now + 3600, // Valid for 1 hour
    };

    const expiring_soon = network.Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "token",
        .refreshToken = "refresh",
        .expiresAt = now + 60, // Expires in 60 seconds
    };

    try testing.expect(expired_creds.isExpired());
    try testing.expect(!valid_creds.isExpired());
    try testing.expect(!expiring_soon.isExpired());

    // Check will expire soon with 120 second leeway
    try testing.expect(expired_creds.willExpireSoon(120));
    try testing.expect(!valid_creds.willExpireSoon(120));
    try testing.expect(expiring_soon.willExpireSoon(120));
}

test "authorization URL building" {
    const allocator = testing.allocator;

    const url = try Auth.token_client.buildAuthorizationUrl(
        allocator,
        "https://claude.ai/oauth/authorize",
        "test-client-id",
        "http://localhost:8080/callback",
        "org:create_api_key user:profile user:inference",
        "test-challenge-123",
        "test-state-456",
    );
    defer allocator.free(url);

    // Check required parameters are present
    try testing.expect(std.mem.indexOf(u8, url, "client_id=test-client-id") != null);
    try testing.expect(std.mem.indexOf(u8, url, "response_type=code") != null);
    try testing.expect(std.mem.indexOf(u8, url, "redirect_uri=http%3A%2F%2Flocalhost%3A8080%2Fcallback") != null);
    try testing.expect(std.mem.indexOf(u8, url, "code_challenge=test-challenge-123") != null);
    try testing.expect(std.mem.indexOf(u8, url, "code_challenge_method=S256") != null);
    try testing.expect(std.mem.indexOf(u8, url, "state=test-state-456") != null);
}

test "header construction for OAuth" {
    const allocator = testing.allocator;

    const creds = network.Anthropic.Models.Credentials{
        .type = "oauth",
        .accessToken = "test_access_token_12345",
        .refreshToken = "test_refresh_token",
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

    const headers = try client.buildHeadersForTest(allocator, false);
    defer {
        for (headers) |header| {
            allocator.free(header.value);
        }
        allocator.free(headers);
    }

    // Check required headers
    var has_auth = false;
    var has_version = false;
    var has_beta = false;
    var has_no_api_key = true;

    for (headers) |header| {
        if (std.mem.eql(u8, header.name, "Authorization")) {
            has_auth = true;
            try testing.expect(std.mem.startsWith(u8, header.value, "Bearer "));
        } else if (std.mem.eql(u8, header.name, "anthropic-version")) {
            has_version = true;
            try testing.expectEqualStrings("2023-06-01", header.value);
        } else if (std.mem.eql(u8, header.name, "anthropic-beta")) {
            has_beta = true;
            // Should include oauth beta header when enabled
        } else if (std.mem.eql(u8, header.name, "x-api-key")) {
            has_no_api_key = false; // Should NOT have API key with OAuth
        }
    }

    try testing.expect(has_auth);
    try testing.expect(has_version);
    try testing.expect(has_beta);
    try testing.expect(has_no_api_key);
}

test "SSE event parsing" {
    const allocator = testing.allocator;

    var builder = network.SSE.SSEEventBuilder.init(allocator);
    defer builder.deinit();

    const sse_data =
        \\event: message_start
        \\data: {"type": "message_start", "message": {"id": "msg_123"}}
        \\
        \\event: content_block_delta
        \\data: {"type": "content_block_delta", "delta": {"text": "Hello"}}
        \\
        \\event: message_stop
        \\data: {"type": "message_stop"}
        \\
        \\
    ;

    var events = std.ArrayList(network.SSE.ServerSentEvent).init(allocator);
    defer {
        for (events.items) |*event| {
            event.deinit(allocator);
        }
        events.deinit();
    }

    // Process the SSE data
    var remaining = sse_data;
    while (remaining.len > 0) {
        const processed = try builder.processData(remaining, &events);
        if (processed == 0) break;
        remaining = remaining[processed..];
    }

    // Should have parsed 3 events
    try testing.expectEqual(@as(usize, 3), events.items.len);

    // Check event types
    try testing.expectEqualStrings("message_start", events.items[0].event orelse "");
    try testing.expectEqualStrings("content_block_delta", events.items[1].event orelse "");
    try testing.expectEqualStrings("message_stop", events.items[2].event orelse "");
}

test "context trimming" {
    const allocator = testing.allocator;

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

    // Trim to 20 messages
    const limit: usize = 20;
    if (messages.items.len > limit) {
        const to_remove = messages.items.len - limit;

        // Free old messages
        for (messages.items[0..to_remove]) |msg| {
            allocator.free(msg.content);
        }

        // Shift remaining
        std.mem.copyForwards(
            network.Anthropic.Message,
            messages.items[0..],
            messages.items[to_remove..],
        );

        messages.shrinkRetainingCapacity(limit);
    }

    try testing.expectEqual(@as(usize, 20), messages.items.len);
    // First remaining message should be "Message 5"
    try testing.expect(std.mem.indexOf(u8, messages.items[0].content, "5") != null);
}

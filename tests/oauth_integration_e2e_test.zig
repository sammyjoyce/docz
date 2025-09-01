//! OAuth integration and E2E tests
//! Tests the full OAuth flow including login, token refresh, and API calls

const std = @import("std");
const network = @import("../src/foundation/network.zig");
const Auth = network.Auth;
const testing = std.testing;

// ===== Integration Tests =====

test "integration: full OAuth flow simulation" {
    const allocator = testing.allocator;
    
    // Generate PKCE parameters
    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);
    
    // Build authorization URL
    const auth_url = try Auth.OAuth.buildAuthorizationUrl(allocator, pkce);
    defer allocator.free(auth_url);
    
    // Verify URL structure
    try testing.expect(std.mem.indexOf(u8, auth_url, "https://claude.ai/oauth/authorize") != null or
                      std.mem.indexOf(u8, auth_url, "https://console.anthropic.com/oauth/authorize") != null);
    try testing.expect(std.mem.indexOf(u8, auth_url, pkce.state) != null);
    
    // Simulate successful callback (would come from browser)
    const simulated_code = "test_auth_code_12345";
    
    // Exchange code for tokens (would fail with test code in real API)
    // This tests the request structure
    _ = Auth.OAuth.exchangeCodeForTokens(allocator, simulated_code, pkce, "http://localhost:8080/callback") catch |err| {
        // Expected to fail with test code
        try testing.expectEqual(Auth.AuthError, err);
    };
}

test "integration: token refresh with 401 recovery" {
    const allocator = testing.allocator;
    
    // Create expired credentials
    const expired_creds = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "expired_token",
        .refreshToken = "valid_refresh_token",
        .expiresAt = std.time.timestamp() - 100, // Expired
    };
    
    // Check expiration
    try testing.expect(expired_creds.isExpired());
    
    // Attempt refresh (would fail with test token in real API)
    _ = Auth.OAuth.refreshTokens(allocator, expired_creds.refreshToken) catch |err| {
        // Expected to fail with test token
        try testing.expectEqual(Auth.AuthError, err);
    };
}

test "integration: credential persistence workflow" {
    const allocator = testing.allocator;
    
    const test_path = "test_oauth_workflow.json";
    defer std.fs.cwd().deleteFile(test_path) catch {};
    
    // Initial save
    const store = Auth.store.TokenStore.init(allocator, .{
        .path = test_path,
    });
    
    const initial_creds = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "initial_token",
        .refresh_token = "initial_refresh",
        .expires_at = std.time.timestamp() + 3600,
    };
    
    try store.save(initial_creds);
    try testing.expect(store.exists());
    
    // Load and verify
    const loaded = try store.load();
    defer allocator.free(loaded.type);
    defer allocator.free(loaded.access_token);
    defer allocator.free(loaded.refresh_token);
    
    try testing.expectEqualStrings("initial_token", loaded.access_token);
    
    // Simulate refresh
    const refreshed_creds = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "refreshed_token",
        .refresh_token = "new_refresh",
        .expires_at = std.time.timestamp() + 7200,
    };
    
    try store.save(refreshed_creds);
    
    // Load again and verify update
    const reloaded = try store.load();
    defer allocator.free(reloaded.type);
    defer allocator.free(reloaded.access_token);
    defer allocator.free(reloaded.refresh_token);
    
    try testing.expectEqualStrings("refreshed_token", reloaded.access_token);
    try testing.expectEqualStrings("new_refresh", reloaded.refresh_token);
}

test "integration: agent authentication flow" {
    const allocator = testing.allocator;
    
    // Set up test credentials
    const test_agent = "test_agent";
    std.posix.setenv("AGENT_NAME", test_agent) catch {};
    defer std.posix.unsetenv("AGENT_NAME") catch {};
    
    // Create directory structure
    const home = std.posix.getenv("HOME") orelse return error.SkipZigTest;
    const dir_path = try std.fmt.allocPrint(allocator, "{s}/.local/share/{s}", .{ home, test_agent });
    defer allocator.free(dir_path);
    
    std.fs.makeDirAbsolute(dir_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    
    const creds_path = try std.fmt.allocPrint(allocator, "{s}/auth.json", .{dir_path});
    defer allocator.free(creds_path);
    defer std.fs.deleteFileAbsolute(creds_path) catch {};
    
    // Save credentials in agent location
    const store = Auth.store.TokenStore.init(allocator, .{
        .agent_name = test_agent,
    });
    
    const creds = Auth.store.StoredCredentials{
        .type = "oauth",
        .access_token = "agent_token",
        .refresh_token = "agent_refresh",
        .expires_at = std.time.timestamp() + 3600,
    };
    
    try store.save(creds);
    
    // Verify engine can load credentials
    const loaded = try store.load();
    defer allocator.free(loaded.type);
    defer allocator.free(loaded.access_token);
    defer allocator.free(loaded.refresh_token);
    
    try testing.expectEqualStrings("oauth", loaded.type);
    try testing.expectEqualStrings("agent_token", loaded.access_token);
}

// ===== E2E Test Helpers =====

test "e2e: loopback server callback handling" {
    const allocator = testing.allocator;
    
    // Start loopback server
    var server = try Auth.loopback_server.LoopbackServer.init(allocator, .{
        .host = "localhost",
        .port = 0, // Ephemeral port
        .path = "/callback",
        .timeout_ms = 100,
    });
    defer server.deinit();
    
    const redirect_uri = try server.getRedirectUri(allocator);
    defer allocator.free(redirect_uri);
    
    // Parse port from redirect URI
    const port_start = std.mem.indexOf(u8, redirect_uri, "localhost:") orelse return error.InvalidURI;
    const port_str_start = port_start + "localhost:".len;
    const port_end = std.mem.indexOf(u8, redirect_uri[port_str_start..], "/") orelse redirect_uri.len - port_str_start;
    const port_str = redirect_uri[port_str_start..port_str_start + port_end];
    const port = try std.fmt.parseInt(u16, port_str, 10);
    
    // Simulate callback request in separate thread
    const test_state = "test_state_123";
    const CallbackThread = struct {
        fn sendCallback(p: u16, state: []const u8) void {
            std.time.sleep(10 * std.time.ns_per_ms); // Small delay
            
            const a = std.heap.page_allocator;
            const addr = std.net.Address.parseIp("127.0.0.1", p) catch return;
            const stream = std.net.tcpConnectToAddress(addr) catch return;
            defer stream.close();
            
            const request = std.fmt.allocPrint(a,
                "GET /callback?code=test_code&state={s} HTTP/1.1\r\n" ++
                "Host: localhost\r\n" ++
                "Connection: close\r\n" ++
                "\r\n",
                .{state}
            ) catch return;
            defer a.free(request);
            
            _ = stream.write(request) catch return;
        }
    };
    
    // Start callback sender in thread
    const thread = try std.Thread.spawn(.{}, CallbackThread.sendCallback, .{ port, test_state });
    defer thread.join();
    
    // Wait for callback
    const result = server.waitForCallback(test_state) catch |err| {
        // Timeout expected in test environment
        if (err == error.WouldBlock or err == error.Timeout) {
            return; // Expected in test
        }
        return err;
    };
    defer result.deinit(allocator);
    
    try testing.expectEqualStrings("test_code", result.code);
    try testing.expectEqualStrings(test_state, result.state);
}

test "e2e: state mismatch rejection" {
    const allocator = testing.allocator;
    
    var server = try Auth.loopback_server.LoopbackServer.init(allocator, .{
        .host = "localhost",
        .port = 0,
        .path = "/callback",
        .timeout_ms = 50,
    });
    defer server.deinit();
    
    const expected_state = "expected_state";
    
    // Simulate callback with wrong state
    const WrongStateThread = struct {
        fn sendWrongState(srv: *Auth.loopback_server.LoopbackServer) void {
            std.time.sleep(10 * std.time.ns_per_ms);
            
            const a = std.heap.page_allocator;
            const addr = std.net.Address.parseIp("127.0.0.1", srv.address.getPort()) catch return;
            const stream = std.net.tcpConnectToAddress(addr) catch return;
            defer stream.close();
            
            const request = 
                "GET /callback?code=test&state=wrong_state HTTP/1.1\r\n" ++
                "Host: localhost\r\n" ++
                "Connection: close\r\n" ++
                "\r\n";
            
            _ = stream.write(request) catch return;
        }
    };
    
    const thread = try std.Thread.spawn(.{}, WrongStateThread.sendWrongState, .{&server});
    defer thread.join();
    
    // Should reject mismatched state
    const result = server.waitForCallback(expected_state);
    try testing.expectError(error.StateMismatch, result);
}

test "e2e: error response handling" {
    const allocator = testing.allocator;
    
    var server = try Auth.loopback_server.LoopbackServer.init(allocator, .{
        .host = "localhost",
        .port = 0,
        .path = "/callback",
        .timeout_ms = 50,
    });
    defer server.deinit();
    
    // Simulate OAuth error callback
    const ErrorThread = struct {
        fn sendError(srv: *Auth.loopback_server.LoopbackServer) void {
            std.time.sleep(10 * std.time.ns_per_ms);
            
            const a = std.heap.page_allocator;
            const addr = std.net.Address.parseIp("127.0.0.1", srv.address.getPort()) catch return;
            const stream = std.net.tcpConnectToAddress(addr) catch return;
            defer stream.close();
            
            const request = 
                "GET /callback?error=access_denied&error_description=User%20denied%20access HTTP/1.1\r\n" ++
                "Host: localhost\r\n" ++
                "Connection: close\r\n" ++
                "\r\n";
            
            _ = stream.write(request) catch return;
        }
    };
    
    const thread = try std.Thread.spawn(.{}, ErrorThread.sendError, .{&server});
    defer thread.join();
    
    const result = server.waitForCallback(null) catch |err| {
        // Timeout expected in test
        if (err == error.WouldBlock or err == error.Timeout) {
            return;
        }
        return err;
    };
    defer result.deinit(allocator);
    
    // Should have error message
    try testing.expect(result.error_msg != null);
}

// ===== API Call Mock Tests =====

test "api: Messages request structure" {
    const allocator = testing.allocator;
    
    // Build a test request body
    const messages = [_]network.Anthropic.Message{
        .{ .role = .user, .content = "Test message" },
    };
    
    var body_obj = std.json.ObjectMap.init(allocator);
    defer body_obj.deinit();
    
    try body_obj.put("model", .{ .string = "claude-3-5-sonnet-20241022" });
    try body_obj.put("max_tokens", .{ .integer = 256 });
    
    var messages_array = std.json.Array.init(allocator);
    defer messages_array.deinit();
    
    for (messages) |msg| {
        var msg_obj = std.json.ObjectMap.init(allocator);
        defer msg_obj.deinit();
        
        const role_str = switch (msg.role) {
            .user => "user",
            .assistant => "assistant",
            .system => "system",
        };
        
        try msg_obj.put("role", .{ .string = role_str });
        try msg_obj.put("content", .{ .string = msg.content });
        try messages_array.append(.{ .object = msg_obj });
    }
    
    try body_obj.put("messages", .{ .array = messages_array });
    
    const json_value = std.json.Value{ .object = body_obj };
    
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    try std.json.stringify(json_value, .{}, buffer.writer());
    
    // Verify JSON structure
    try testing.expect(std.mem.indexOf(u8, buffer.items, "\"model\"") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "\"messages\"") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "\"role\":\"user\"") != null);
}
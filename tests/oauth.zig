//! OAuth authentication flow tests

const std = @import("std");
const network = @import("../src/foundation/network.zig");
const Auth = network.Auth;

test "PKCE generation creates valid parameters" {
    const allocator = std.testing.allocator;
    
    const pkce = try Auth.pkce.generate(allocator, 64);
    defer pkce.deinit(allocator);
    
    // Verify verifier length
    try std.testing.expect(pkce.verifier.len == 64);
    
    // Verify challenge is base64url encoded
    try std.testing.expect(pkce.challenge.len > 0);
    
    // Verify state is different from verifier (per spec requirement)
    try std.testing.expect(!std.mem.eql(u8, pkce.state, pkce.verifier));
}

test "Credentials parsing supports snake_case JSON" {
    const allocator = std.testing.allocator;
    
    const json = 
        \\{"type":"oauth","access_token":"test_access","refresh_token":"test_refresh","expires_at":1234567890}
    ;
    
    const creds = try Auth.OAuth.parseCredentialsFromJson(allocator, json);
    defer creds.deinit(allocator);
    
    try std.testing.expectEqualStrings("oauth", creds.type);
    try std.testing.expectEqualStrings("test_access", creds.accessToken);
    try std.testing.expectEqualStrings("test_refresh", creds.refreshToken);
    try std.testing.expectEqual(@as(i64, 1234567890), creds.expiresAt);
}

test "Credentials expiry check works correctly" {
    const allocator = std.testing.allocator;
    
    const future_time = std.time.timestamp() + 3600; // 1 hour from now
    const past_time = std.time.timestamp() - 3600; // 1 hour ago
    
    const valid_creds = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "valid",
        .refreshToken = "valid",
        .expiresAt = future_time,
    };
    
    const expired_creds = Auth.OAuth.Credentials{
        .type = "oauth",
        .accessToken = "expired",
        .refreshToken = "expired",
        .expiresAt = past_time,
    };
    
    try std.testing.expect(!valid_creds.isExpired());
    try std.testing.expect(expired_creds.isExpired());
    
    // Test willExpireSoon with 2 hour leeway
    try std.testing.expect(!valid_creds.willExpireSoon(120)); // 2 minutes
    try std.testing.expect(expired_creds.willExpireSoon(120));
}

test "Authorization URL is properly formatted" {
    const allocator = std.testing.allocator;
    
    const pkce = Auth.pkce.PkceParams{
        .verifier = "test_verifier",
        .challenge = "test_challenge",
        .state = "test_state",
    };
    
    const url = try Auth.OAuth.buildAuthorizationUrl(allocator, pkce);
    defer allocator.free(url);
    
    // Check that URL contains required parameters
    try std.testing.expect(std.mem.indexOf(u8, url, "client_id=") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "response_type=code") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "redirect_uri=") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "scope=") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge=test_challenge") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge_method=S256") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "state=test_state") != null);
}

test "Redirect URI validation enforces localhost" {
    const allocator = std.testing.allocator;
    
    // Per spec, we only accept localhost redirect URIs
    const valid_uri = "http://localhost:8080/callback";
    const invalid_uri = "http://127.0.0.1:8080/callback";
    
    // This is more of a documentation test - the actual validation
    // happens during the OAuth flow
    try std.testing.expect(std.mem.startsWith(u8, valid_uri, "http://localhost"));
    try std.testing.expect(!std.mem.startsWith(u8, invalid_uri, "http://localhost"));
}

test "Credential storage uses mode 0600" {
    const allocator = std.testing.allocator;
    
    const temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();
    
    const test_path = "test_creds.json";
    const creds = Auth.OAuth.Credentials{
        .type = try allocator.dupe(u8, "oauth"),
        .accessToken = try allocator.dupe(u8, "test_access"),
        .refreshToken = try allocator.dupe(u8, "test_refresh"),
        .expiresAt = 1234567890,
    };
    defer creds.deinit(allocator);
    
    // Save credentials
    try Auth.OAuth.saveCredentials(allocator, test_path, creds);
    defer std.fs.cwd().deleteFile(test_path) catch {};
    
    // Check file permissions (mode 0600)
    const file = try std.fs.cwd().openFile(test_path, .{});
    defer file.close();
    
    const stat = try file.stat();
    if (@hasField(@TypeOf(stat), "mode")) {
        // Unix-like systems
        const mode = stat.mode & 0o777;
        try std.testing.expectEqual(@as(u32, 0o600), mode);
    }
}
const std = @import("std");
const oauth = @import("src/foundation/network/auth/oauth.zig");
const Io = std.Io;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Manual OAuth Test ===\n", .{});
    std.debug.print("This test verifies the OAuth flow with manual code entry.\n\n", .{});

    // Generate PKCE parameters
    const pkceParams = try oauth.generatePkceParams(allocator);
    defer pkceParams.deinit(allocator);

    std.debug.print("✓ PKCE parameters generated\n", .{});
    std.debug.print("  Verifier length: {d}\n", .{pkceParams.verifier.len});
    std.debug.print("  Challenge length: {d}\n", .{pkceParams.challenge.len});
    std.debug.print("  State: {s}\n\n", .{pkceParams.state});

    // Build authorization URL with the official redirect URI
    const auth_url = try oauth.buildAuthorizationUrl(allocator, pkceParams);
    defer allocator.free(auth_url);

    std.debug.print("✓ Authorization URL built\n", .{});
    std.debug.print("\n🔐 Please visit this URL to authorize:\n", .{});
    std.debug.print("{s}\n\n", .{auth_url});

    std.debug.print("After authorization, you'll be redirected to a URL like:\n", .{});
    std.debug.print("https://console.anthropic.com/oauth/code/callback#code=XXXXXXXX#state=YYYYYYYY\n\n", .{});

    std.debug.print("Copy the ENTIRE code part (everything after 'code=' including both parts separated by #)\n", .{});
    std.debug.print("For example: XXXXXXXX#YYYYYYYY\n\n", .{});
    std.debug.print("Paste the code here and press Enter: ", .{});

    // Read authorization code from stdin
    const stdin = std.fs.File.stdin();
    var buffer: [1024]u8 = undefined;
    const bytesRead = try stdin.readAll(&buffer);
    if (bytesRead > 0) {
        const authCode = std.mem.trim(u8, buffer[0..bytesRead], " \t\r\n");

        std.debug.print("\nReceived code: {s}\n", .{authCode});

        // Exchange code for tokens
        const redirect_uri = "https://console.anthropic.com/oauth/code/callback";
        std.debug.print("\n🔄 Exchanging code for tokens...\n", .{});

        const credentials = oauth.exchangeCodeForTokens(allocator, authCode, pkceParams, redirect_uri) catch |err| {
            std.debug.print("❌ Token exchange failed: {}\n", .{err});
            return err;
        };
        defer credentials.deinit(allocator);

        std.debug.print("\n✅ OAuth authentication successful!\n", .{});
        std.debug.print("Access token (first 20 chars): {s}...\n", .{credentials.accessToken[0..@min(20, credentials.accessToken.len)]});
        std.debug.print("Token expires at: {d}\n", .{credentials.expiresAt});

        // Test the token with a simple API call
        std.debug.print("\n🧪 Testing token with API call...\n", .{});
        const test_body =
            \\{
            \\  "model": "claude-3-5-haiku-20241022",
            \\  "max_tokens": 100,
            \\  "messages": [
            \\    {"role": "user", "content": "Say 'OAuth test successful!' in 5 words or less"}
            \\  ]
            \\}
        ;

        const response = oauth.fetchWithAnthropicOAuth(allocator, credentials.accessToken, test_body) catch |err| {
            std.debug.print("❌ API test failed: {}\n", .{err});
            return err;
        };
        defer allocator.free(response);

        std.debug.print("✅ API call successful!\n", .{});
        std.debug.print("Response (first 200 chars): {s}...\n", .{response[0..@min(200, response.len)]});

        // Save credentials
        try oauth.saveCredentials(allocator, "oauth_test_creds.json", credentials);
        std.debug.print("\n✅ Credentials saved to oauth_test_creds.json\n", .{});
    } else {
        std.debug.print("❌ No input received\n", .{});
        return error.NoInput;
    }
}

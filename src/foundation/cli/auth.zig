//! CLI commands for OAuth authentication

const std = @import("std");
const network = @import("../network.zig");
const Auth = network.Auth;

const log = std.log.scoped(.cli_auth);

// Re-export Commands for the CLI barrel
pub const Commands = struct {

    /// OAuth configuration constants
    const OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
    const OAUTH_AUTHORIZATION_URL = "https://claude.ai/oauth/authorize";
    const OAUTH_TOKEN_ENDPOINT = "https://console.anthropic.com/v1/oauth/token";
    const OAUTH_SCOPES = "org:create_api_key user:profile user:inference";
    /// Handle 'auth login' command
    pub fn login(allocator: std.mem.Allocator, args: struct {
        port: u16 = 8080,
        host: []const u8 = "localhost",
        manual: bool = false,
    }) !void {
        const stdout = std.debug;

        if (args.manual) {
            try loginManual(allocator);
            return;
        }

        try stdout.print("Starting OAuth login flow...\n", .{});

        // Generate PKCE parameters
        const pkce_params = try Auth.OAuth.generatePkceParams(allocator);
        defer pkce_params.deinit(allocator);

        // Start loopback server
        var server = try Auth.loopback_server.LoopbackServer.init(allocator, .{
            .host = args.host,
            .port = args.port,
            .path = "/callback",
            .timeout_ms = 300000, // 5 minutes
        });
        defer server.deinit();

        // Build authorization URL
        const redirect_uri = try server.getRedirectUri(allocator);
        defer allocator.free(redirect_uri);

        const auth_url = try Auth.OAuth.buildAuthorizationUrlWithRedirect(allocator, pkce_params, redirect_uri);
        defer allocator.free(auth_url);

        // Open browser
        Auth.OAuth.launchBrowser(auth_url) catch |err| {
            log.warn("Failed to open browser: {}", .{err});
            try stdout.print("Please manually open this URL in your browser:\n{s}\n", .{auth_url});
        };

        try stdout.print("Waiting for authorization callback...\n", .{});

        // Wait for callback with state validation
        const callback_result = try server.waitForCallback(pkce_params.state);
        defer callback_result.deinit(allocator);

        try stdout.print("Authorization code received, exchanging for tokens...\n", .{});

        // Exchange code for tokens
        const token_response = try Auth.OAuth.exchangeCodeForTokens(
            allocator,
            callback_result.code,
            pkce_params,
            redirect_uri,
        );
        defer token_response.deinit(allocator);

        // Save credentials
        try Auth.OAuth.saveCredentials(allocator, "claude_oauth_creds.json", token_response);

        try stdout.print("\n✓ Authentication successful!\n", .{});
        try stdout.print("Access token expires in {} seconds\n", .{token_response.expiresAt - std.time.timestamp()});
    }

    /// Handle 'auth status' command
    pub fn status(allocator: std.mem.Allocator) !void {
        const stdout = std.debug;

        const creds_path = "claude_oauth_creds.json";
        const creds = Auth.OAuth.parseCredentials(allocator, creds_path) catch |err| {
            if (err == error.FileNotFound) {
                try stdout.print("Not authenticated. Run 'docz auth login' to authenticate.\n", .{});
                return;
            }
            return err;
        };
        defer creds.deinit(allocator);

        try stdout.print("Authentication Status:\n", .{});
        try stdout.print("  Type: {s}\n", .{creds.type});

        const now = std.time.timestamp();
        if (creds.isExpired()) {
            try stdout.print("  Status: EXPIRED\n", .{});
        } else {
            const remaining = creds.expiresAt - now;
            try stdout.print("  Status: VALID\n", .{});
            try stdout.print("  Expires in: {} seconds\n", .{remaining});
        }
    }

    /// Handle 'auth whoami' command
    pub fn whoami(allocator: std.mem.Allocator) !void {
        const stdout = std.debug;

        const creds_path = "claude_oauth_creds.json";
        const creds = Auth.OAuth.parseCredentials(allocator, creds_path) catch |err| {
            if (err == error.FileNotFound) {
                try stdout.print("Not authenticated. Run 'docz auth login' to authenticate.\n", .{});
                return;
            }
            return err;
        };
        defer creds.deinit(allocator);

        // TODO: Make API call to get user info
        try stdout.print("Authenticated via OAuth\n", .{});
        try stdout.print("Token type: {s}\n", .{creds.type});
    }

    /// Handle 'auth logout' command
    pub fn logout(allocator: std.mem.Allocator) !void {
        const stdout = std.debug;

        const creds_path = "claude_oauth_creds.json";
        _ = std.fs.cwd().deleteFile(creds_path) catch |err| {
            if (err == error.FileNotFound) {
                try stdout.print("Not authenticated.\n", .{});
                return;
            }
            return err;
        };

        try stdout.print("Successfully logged out.\n", .{});
    }

    /// Manual login flow (copy-paste)
    fn loginManual(allocator: std.mem.Allocator) !void {
        const stdout = std.debug;
        const stdin = std.io.getStdIn().reader();

        try stdout.print("Starting manual OAuth login flow...\n", .{});

        // Generate PKCE parameters
        const pkce_params = try Auth.OAuth.generatePkceParams(allocator);
        defer pkce_params.deinit(allocator);

        // Build authorization URL with default redirect
        const auth_url = try Auth.OAuth.buildAuthorizationUrl(allocator, pkce_params);
        defer allocator.free(auth_url);

        try stdout.print("\nPlease open this URL in your browser:\n{s}\n\n", .{auth_url});
        try stdout.print("After authorization, you'll be redirected to a URL like:\n", .{});
        try stdout.print("http://localhost:8080/callback?code=CODE&state=STATE\n\n", .{});
        try stdout.print("Please paste the authorization code: ", .{});

        // Read authorization code
        var buf: [1024]u8 = undefined;
        if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |input| {
            const code = std.mem.trim(u8, input, " \t\r\n");

            try stdout.print("Please paste the state parameter: ", .{});
            if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |state_input| {
                const state = std.mem.trim(u8, state_input, " \t\r\n");

                // Verify state matches
                if (!std.mem.eql(u8, state, pkce_params.state)) {
                    try stdout.print("Error: State mismatch - authorization may have been intercepted\n", .{});
                    return error.StateMismatch;
                }

                try stdout.print("Exchanging code for tokens...\n", .{});

                // Exchange code for tokens using default redirect URI
                const token_response = try Auth.OAuth.exchangeCodeForTokens(
                    allocator,
                    code,
                    pkce_params,
                    "http://localhost:8080/callback",
                );
                defer token_response.deinit(allocator);

                // Save credentials
                try Auth.OAuth.saveCredentials(allocator, "claude_oauth_creds.json", token_response);

                try stdout.print("\n✓ Authentication successful!\n", .{});
                try stdout.print("Access token expires in {} seconds\n", .{token_response.expiresAt - std.time.timestamp()});
            }
        }
    }

    /// Handle 'auth test-call' command
    pub fn testCall(allocator: std.mem.Allocator, args: struct {
        stream: bool = false,
    }) !void {
        const stdout = std.debug;

        const creds_path = "claude_oauth_creds.json";
        var creds = Auth.OAuth.parseCredentials(allocator, creds_path) catch |err| {
            if (err == error.FileNotFound) {
                try stdout.print("Not authenticated. Run 'docz auth login' to authenticate.\n", .{});
                return;
            }
            return err;
        };
        defer creds.deinit(allocator);

        // Check if token needs refresh
        if (creds.willExpireSoon(120)) {
            try stdout.print("Token expiring soon, refreshing...\n", .{});

            const new_creds = try Auth.OAuth.refreshTokens(allocator, creds.refreshToken);
            defer new_creds.deinit(allocator);

            // Update stored credentials
            try Auth.OAuth.saveCredentials(allocator, creds_path, new_creds);

            // Use new access token
            allocator.free(creds.accessToken);
            creds.accessToken = try allocator.dupe(u8, new_creds.accessToken);
            allocator.free(creds.refreshToken);
            creds.refreshToken = try allocator.dupe(u8, new_creds.refreshToken);
            creds.expiresAt = new_creds.expiresAt;
        }

        try stdout.print("Making test API call to Anthropic Messages API...\n", .{});

        // Initialize Anthropic client
        var client = try network.Anthropic.Client.initWithOAuth(allocator, creds, creds_path);
        defer client.deinit();

        // Make a simple test call
        const messages = [_]network.Anthropic.Message{
            .{ .role = .user, .content = "Say 'Test successful!' in exactly 3 words." },
        };

        if (args.stream) {
            try stdout.print("Using streaming mode...\n", .{});

            // Streaming test call
            var shared_ctx = @import("../context.zig").SharedContext.init(allocator);
            defer shared_ctx.deinit();

            const streamParams = network.Anthropic.Client.StreamParameters{
                .model = "claude-3-5-sonnet-20241022",
                .messages = &messages,
                .maxTokens = 100,
                .temperature = 0.0,
                .onToken = struct {
                    fn callback(ctx: *@import("../context.zig").SharedContext, data: []const u8) void {
                        _ = ctx;
                        // Parse and print streaming data
                        const parsed = std.json.parseFromSlice(
                            struct { delta: ?struct { text: ?[]const u8 } = null },
                            std.heap.page_allocator,
                            data,
                            .{ .ignore_unknown_fields = true }
                        ) catch return;
                        defer parsed.deinit();

                        if (parsed.value.delta) |delta| {
                            if (delta.text) |text| {
                                std.debug.print("{s}", .{text});
                            }
                        }
                    }
                }.callback,
            };

            try client.stream(&shared_ctx, streamParams);
            try stdout.print("\n", .{});
        } else {
            // Non-streaming test call
            var shared_ctx = @import("../context.zig").SharedContext.init(allocator);
            defer shared_ctx.deinit();

            const result = try client.complete(&shared_ctx, .{
                .model = "claude-3-5-sonnet-20241022",
                .messages = &messages,
                .maxTokens = 100,
                .temperature = 0.0,
            });
            defer result.deinit();

            // Print response
            try stdout.print("Response: {s}\n", .{result.content});
        }

        try stdout.print("✓ Test call successful!\n", .{});
    }

    fn loginManual(allocator: std.mem.Allocator) !void {
        const stdout = std.debug;
        const stdin = std.fs.File.stdin().reader();

        // Generate PKCE parameters
        const pkce_params = try Auth.OAuth.generatePkceParams(allocator);
        defer pkce_params.deinit(allocator);

        // Build authorization URL for manual flow
        const auth_url = try Auth.OAuth.buildAuthorizationUrl(allocator, pkce_params);
        defer allocator.free(auth_url);

        try stdout.print("\nManual OAuth Flow\n", .{});
        try stdout.print("==================\n\n", .{});
        try stdout.print("1. Open this URL in your browser:\n\n", .{});
        try stdout.print("{s}\n\n", .{auth_url});
        try stdout.print("2. After authorizing, copy the code from the redirect URL\n", .{});
        try stdout.print("3. Enter the authorization code: ", .{});

        var buf: [256]u8 = undefined;
        if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |code| {
            const trimmed_code = std.mem.trim(u8, code, " \t\r\n");

            // Exchange code for tokens
            const token_response = try Auth.OAuth.exchangeCodeForTokens(
                allocator,
                trimmed_code,
                pkce_params,
                "urn:ietf:wg:oauth:2.0:oob",
            );
            defer token_response.deinit(allocator);

            // Save credentials
            try Auth.OAuth.saveCredentials(allocator, "claude_oauth_creds.json", token_response);

            try stdout.print("\n✓ Authentication successful!\n", .{});
        } else {
            return error.NoCodeEntered;
        }
    }
};
};

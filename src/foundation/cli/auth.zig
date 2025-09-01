//! CLI commands for OAuth authentication

const std = @import("std");
const network = @import("network_shared");
const Auth = network.Auth;

const log = std.log.scoped(.cli_auth);

/// OAuth configuration constants
const OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
const OAUTH_AUTHORIZATION_URL = "https://claude.ai/oauth/authorize";
const OAUTH_TOKEN_ENDPOINT = "https://console.anthropic.com/v1/oauth/token";
const OAUTH_SCOPES = "org:create_api_key user:profile user:inference";

/// CLI auth command handlers
pub const Commands = struct {
    /// Handle 'auth login' command
    pub fn login(allocator: std.mem.Allocator, args: struct {
        port: u16 = 8080,
        host: []const u8 = "localhost",
        manual: bool = false,
    }) !void {
        const stdout = std.io.getStdOut().writer();

        if (args.manual) {
            try loginManual(allocator);
            return;
        }

        try stdout.print("Starting OAuth login flow...\n", .{});

        // Generate PKCE parameters
        const pkce_params = try Auth.pkce.generate(allocator, 64);
        defer pkce_params.deinit(allocator);

        const state = try Auth.pkce.generateState(allocator, 32);
        defer allocator.free(state);

        // Start loopback server
        var server = try Auth.loopback_server.LoopbackServer.init(allocator, .{
            .host = args.host,
            .port = args.port,
            .path = "/callback",
        });
        defer server.deinit();

        const redirect_uri = try server.getRedirectUri(allocator);
        defer allocator.free(redirect_uri);

        // Build authorization URL
        const auth_url = try Auth.token_client.buildAuthorizationUrl(
            allocator,
            OAUTH_AUTHORIZATION_URL,
            OAUTH_CLIENT_ID,
            redirect_uri,
            OAUTH_SCOPES,
            pkce_params.challenge,
            state,
        );
        defer allocator.free(auth_url);

        // Open browser
        Auth.authorize_url.openInBrowser(allocator, auth_url) catch |err| {
            log.warn("Failed to open browser: {}", .{err});
            Auth.authorize_url.showManualInstructions(auth_url);
        };

        try stdout.print("Waiting for authorization callback...\n", .{});

        // Wait for callback with state validation
        const callback_result = try server.waitForCallback(state);
        defer callback_result.deinit(allocator);

        try stdout.print("Authorization code received, exchanging for tokens...\n", .{});

        // Exchange code for tokens
        var token_client = Auth.token_client.TokenClient.init(allocator, .{
            .client_id = OAUTH_CLIENT_ID,
            .token_endpoint = OAUTH_TOKEN_ENDPOINT,
        });
        defer token_client.deinit();

        const token_response = try token_client.exchangeCode(
            callback_result.code,
            pkce_params.verifier,
            redirect_uri,
            state,
        );
        defer token_response.deinit(allocator);

        // Save credentials
        const store = Auth.store.TokenStore.init(allocator, .{});
        const creds = Auth.store.StoredCredentials{
            .type = "oauth",
            .access_token = token_response.access_token,
            .refresh_token = token_response.refresh_token,
            .expires_at = std.time.timestamp() + token_response.expires_in,
        };
        try store.save(creds);

        try stdout.print("\n✓ Authentication successful!\n", .{});
        try stdout.print("Access token expires in {} seconds\n", .{token_response.expires_in});
    }

    /// Handle 'auth status' command
    pub fn status(allocator: std.mem.Allocator) !void {
        const stdout = std.io.getStdOut().writer();
        const store = Auth.store.TokenStore.init(allocator, .{});

        if (!store.exists()) {
            try stdout.print("Not authenticated. Run 'docz auth login' to authenticate.\n", .{});
            return;
        }

        const creds = try store.load();
        defer allocator.free(creds.type);
        defer allocator.free(creds.access_token);
        defer allocator.free(creds.refresh_token);

        try stdout.print("Authentication Status:\n", .{});
        try stdout.print("  Type: {s}\n", .{creds.type});

        const now = std.time.timestamp();
        if (creds.isExpired()) {
            try stdout.print("  Status: EXPIRED\n", .{});
        } else {
            const remaining = creds.expires_at - now;
            try stdout.print("  Status: VALID\n", .{});
            try stdout.print("  Expires in: {} seconds\n", .{remaining});
        }
    }

    /// Handle 'auth whoami' command
    pub fn whoami(allocator: std.mem.Allocator) !void {
        const stdout = std.io.getStdOut().writer();
        const store = Auth.store.TokenStore.init(allocator, .{});

        if (!store.exists()) {
            try stdout.print("Not authenticated. Run 'docz auth login' to authenticate.\n", .{});
            return;
        }

        const creds = try store.load();
        defer allocator.free(creds.type);
        defer allocator.free(creds.access_token);
        defer allocator.free(creds.refresh_token);

        // TODO: Make API call to get user info
        try stdout.print("Authenticated via OAuth\n", .{});
        try stdout.print("Token type: {s}\n", .{creds.type});
    }

    /// Handle 'auth logout' command
    pub fn logout(allocator: std.mem.Allocator) !void {
        const stdout = std.io.getStdOut().writer();
        const store = Auth.store.TokenStore.init(allocator, .{});

        if (!store.exists()) {
            try stdout.print("Not authenticated.\n", .{});
            return;
        }

        try store.remove();
        try stdout.print("Successfully logged out.\n", .{});
    }

    /// Handle 'auth test-call' command
    pub fn testCall(allocator: std.mem.Allocator, args: struct {
        stream: bool = false,
    }) !void {
        const stdout = std.io.getStdOut().writer();
        const store = Auth.store.TokenStore.init(allocator, .{});

        if (!store.exists()) {
            try stdout.print("Not authenticated. Run 'docz auth login' to authenticate.\n", .{});
            return;
        }

        var creds = try store.load();
        defer allocator.free(creds.type);
        defer allocator.free(creds.access_token);
        defer allocator.free(creds.refresh_token);

        // Check if token needs refresh
        if (creds.willExpireSoon(120)) {
            try stdout.print("Token expiring soon, refreshing...\n", .{});

            var token_client = Auth.token_client.TokenClient.init(allocator, .{
                .client_id = OAUTH_CLIENT_ID,
                .token_endpoint = OAUTH_TOKEN_ENDPOINT,
            });
            defer token_client.deinit();

            const new_tokens = try token_client.refreshToken(creds.refresh_token);
            defer new_tokens.deinit(allocator);

            // Update stored credentials
            const new_creds = Auth.store.StoredCredentials{
                .type = "oauth",
                .access_token = new_tokens.access_token,
                .refresh_token = new_tokens.refresh_token,
                .expires_at = std.time.timestamp() + new_tokens.expires_in,
            };
            try store.save(new_creds);

            // Use new access token
            allocator.free(creds.access_token);
            creds.access_token = try allocator.dupe(u8, new_tokens.access_token);
        }

        try stdout.print("Making test API call to Anthropic Messages API...\n", .{});

        // Initialize Anthropic client
        var client = network.Anthropic.Client.init(allocator, .{}, creds);
        defer client.deinit();

        // Make a simple test call
        const messages = [_]network.Anthropic.Message{
            .{ .role = .user, .content = "Say 'Test successful!' in exactly 3 words." },
        };

        if (args.stream) {
            try stdout.print("Using streaming mode...\n", .{});

            // Streaming test call
            const streamCallback = struct {
                fn callback(event: network.Anthropic.StreamEvent, data: []const u8) void {
                    const out = std.io.getStdOut().writer();
                    switch (event) {
                        .content_block_delta => {
                            // Parse delta and print text
                            const parsed = std.json.parseFromSlice(struct { delta: struct { text: []const u8 } }, std.heap.page_allocator, data, .{ .ignore_unknown_fields = true }) catch return;
                            defer parsed.deinit();
                            out.print("{s}", .{parsed.value.delta.text}) catch {};
                        },
                        .message_stop => {
                            out.print("\n", .{}) catch {};
                        },
                        else => {},
                    }
                }
            }.callback;

            try client.sendMessageStream(.{
                .model = "claude-3-5-sonnet-20241022",
                .messages = &messages,
                .max_tokens = 100,
                .temperature = 0.0,
            }, streamCallback);
        } else {
            // Non-streaming test call
            const response = try client.sendMessage(.{
                .model = "claude-3-5-sonnet-20241022",
                .messages = &messages,
                .max_tokens = 100,
                .temperature = 0.0,
            });
            defer response.deinit(allocator);

            // Print response
            for (response.content) |block| {
                if (block.text) |text| {
                    try stdout.print("Response: {s}\n", .{text});
                }
            }
        }

        try stdout.print("✓ Test call successful!\n", .{});
    }

    fn loginManual(allocator: std.mem.Allocator) !void {
        const stdout = std.io.getStdOut().writer();
        const stdin = std.io.getStdIn().reader();

        // Generate PKCE parameters
        const pkce_params = try Auth.pkce.generate(allocator, 64);
        defer pkce_params.deinit(allocator);

        const state = try Auth.pkce.generateState(allocator, 32);
        defer allocator.free(state);

        // Build authorization URL for manual flow
        const auth_url = try Auth.token_client.buildAuthorizationUrl(
            allocator,
            OAUTH_AUTHORIZATION_URL,
            OAUTH_CLIENT_ID,
            "urn:ietf:wg:oauth:2.0:oob", // Out-of-band redirect for manual flow
            OAUTH_SCOPES,
            pkce_params.challenge,
            state,
        );
        defer allocator.free(auth_url);

        try stdout.print("\nManual OAuth Flow\n", .{});
        try stdout.print("==================\n\n", .{});
        try stdout.print("1. Open this URL in your browser:\n\n", .{});
        try stdout.print("{s}\n\n", .{auth_url});
        try stdout.print("2. After authorizing, copy the code from the redirect URL\n", .{});
        try stdout.print("3. Enter the authorization code: ", .{});

        var buf: [256]u8 = undefined;
        if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |code| {
            // Exchange code for tokens
            var token_client = Auth.token_client.TokenClient.init(allocator, .{
                .client_id = OAUTH_CLIENT_ID,
                .token_endpoint = OAUTH_TOKEN_ENDPOINT,
            });
            defer token_client.deinit();

            const token_response = try token_client.exchangeCode(
                code,
                pkce_params.verifier,
                "urn:ietf:wg:oauth:2.0:oob",
                state,
            );
            defer token_response.deinit(allocator);

            // Save credentials
            const store = Auth.store.TokenStore.init(allocator, .{});
            const creds = Auth.store.StoredCredentials{
                .type = "oauth",
                .access_token = token_response.access_token,
                .refresh_token = token_response.refresh_token,
                .expires_at = std.time.timestamp() + token_response.expires_in,
            };
            try store.save(creds);

            try stdout.print("\n✓ Authentication successful!\n", .{});
        } else {
            return error.NoCodeEntered;
        }
    }
};

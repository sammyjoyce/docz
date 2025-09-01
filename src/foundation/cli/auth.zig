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

        stdout.print("Starting OAuth login flow...\n", .{});

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

        stdout.print("Using redirect_uri: {s}\n", .{redirect_uri});

        // Open browser
        Auth.OAuth.launchBrowser(auth_url) catch |err| {
            log.warn("Failed to open browser: {}", .{err});
            stdout.print("Please manually open this URL in your browser:\n{s}\n", .{auth_url});
        };

        stdout.print("Waiting for authorization callback...\n", .{});

        // Wait for callback with state validation
        const callback_result = try server.waitForCallback(pkce_params.state);
        defer callback_result.deinit(allocator);

        stdout.print("Authorization code received, exchanging for tokens...\n", .{});
        stdout.print("POST {s}/access_token with redirect_uri={s}\n", .{ Auth.OAuth.OAUTH_TOKEN_ENDPOINT, redirect_uri });

        // Exchange code for tokens
        const creds = try Auth.OAuth.exchangeCodeForTokens(
            allocator,
            callback_result.code,
            pkce_params,
            redirect_uri,
        );
        defer creds.deinit(allocator);

        // Save credentials to standard location
        const agent_name = std.process.getEnvVarOwned(allocator, "AGENT_NAME") catch |err| blk: {
            if (err == error.EnvironmentVariableNotFound) {
                break :blk try allocator.dupe(u8, "docz");
            }
            return err;
        };
        defer allocator.free(agent_name);

        const store = Auth.store.TokenStore.init(allocator, .{
            .agent_name = agent_name,
        });

        const stored_creds = Auth.store.StoredCredentials{
            .type = creds.type,
            .access_token = creds.accessToken,
            .refresh_token = creds.refreshToken,
            .expires_at = creds.expiresAt,
        };
        try store.save(stored_creds);

        stdout.print("\n✓ Authentication successful!\n", .{});
        stdout.print("Access token expires in {} seconds\n", .{creds.expiresAt - std.time.timestamp()});
    }

    /// Handle 'auth status' command
    pub fn status(allocator: std.mem.Allocator) !void {
        const stdout = std.debug;

        // Get agent name from environment or use default
        const agent_name = std.process.getEnvVarOwned(allocator, "AGENT_NAME") catch |err| blk: {
            if (err == error.EnvironmentVariableNotFound) {
                break :blk try allocator.dupe(u8, "docz");
            }
            return err;
        };
        defer allocator.free(agent_name);

        const store = Auth.store.TokenStore.init(allocator, .{
            .agent_name = agent_name,
        });

        if (!store.exists()) {
            stdout.print("Not authenticated. Run 'docz auth login' to authenticate.\n", .{});
            return;
        }

        const stored_creds = try store.load();
        defer allocator.free(stored_creds.type);
        defer allocator.free(stored_creds.access_token);
        defer allocator.free(stored_creds.refresh_token);

        // Convert to OAuth credentials for compatibility
        const creds = Auth.OAuth.Credentials{
            .type = stored_creds.type,
            .accessToken = stored_creds.access_token,
            .refreshToken = stored_creds.refresh_token,
            .expiresAt = stored_creds.expires_at,
        };

        stdout.print("Authentication Status:\n", .{});
        stdout.print("  Type: {s}\n", .{creds.type});

        const now = std.time.timestamp();
        if (creds.isExpired()) {
            stdout.print("  Status: EXPIRED\n", .{});
        } else {
            const remaining = creds.expiresAt - now;
            stdout.print("  Status: VALID\n", .{});
            stdout.print("  Expires in: {} seconds\n", .{remaining});
        }
    }

    /// Handle 'auth whoami' command
    pub fn whoami(allocator: std.mem.Allocator) !void {
        const stdout = std.debug;

        // Get agent name from environment or use default
        const agent_name = std.process.getEnvVarOwned(allocator, "AGENT_NAME") catch |err| blk: {
            if (err == error.EnvironmentVariableNotFound) {
                break :blk try allocator.dupe(u8, "docz");
            }
            return err;
        };
        defer allocator.free(agent_name);

        const store = Auth.store.TokenStore.init(allocator, .{
            .agent_name = agent_name,
        });

        if (!store.exists()) {
            stdout.print("Not authenticated. Run 'docz auth login' to authenticate.\n", .{});
            return;
        }

        const stored_creds = try store.load();
        defer allocator.free(stored_creds.type);
        defer allocator.free(stored_creds.access_token);
        defer allocator.free(stored_creds.refresh_token);

        const creds = Auth.OAuth.Credentials{
            .type = stored_creds.type,
            .accessToken = stored_creds.access_token,
            .refreshToken = stored_creds.refresh_token,
            .expiresAt = stored_creds.expires_at,
        };

        stdout.print("Authenticated via OAuth\n", .{});
        stdout.print("Token type: {s}\n", .{creds.type});
    }

    /// Handle 'auth logout' command
    pub fn logout(allocator: std.mem.Allocator) !void {
        const stdout = std.debug;

        // Get agent name from environment or use default
        const agent_name = std.process.getEnvVarOwned(allocator, "AGENT_NAME") catch |err| blk: {
            if (err == error.EnvironmentVariableNotFound) {
                break :blk try allocator.dupe(u8, "docz");
            }
            return err;
        };
        defer allocator.free(agent_name);

        const store = Auth.store.TokenStore.init(allocator, .{
            .agent_name = agent_name,
        });

        if (!store.exists()) {
            stdout.print("Not authenticated.\n", .{});
            return;
        }

        try store.remove();
        stdout.print("Successfully logged out.\n", .{});
    }

    /// Handle 'auth test-call' command
    pub fn testCall(allocator: std.mem.Allocator, args: struct {
        stream: bool = false,
    }) !void {
        const stdout = std.debug;

        // Get agent name from environment or use default
        const agent_name = std.process.getEnvVarOwned(allocator, "AGENT_NAME") catch |err| blk: {
            if (err == error.EnvironmentVariableNotFound) {
                break :blk try allocator.dupe(u8, "docz");
            }
            return err;
        };
        defer allocator.free(agent_name);

        const store = Auth.store.TokenStore.init(allocator, .{
            .agent_name = agent_name,
        });

        if (!store.exists()) {
            stdout.print("Not authenticated. Run 'docz auth login' to authenticate.\n", .{});
            return;
        }

        const stored_creds = try store.load();
        defer allocator.free(stored_creds.type);
        defer allocator.free(stored_creds.access_token);
        defer allocator.free(stored_creds.refresh_token);

        // Convert to OAuth credentials
        var creds = Auth.OAuth.Credentials{
            .type = try allocator.dupe(u8, stored_creds.type),
            .accessToken = try allocator.dupe(u8, stored_creds.access_token),
            .refreshToken = try allocator.dupe(u8, stored_creds.refresh_token),
            .expiresAt = stored_creds.expires_at,
        };
        defer creds.deinit(allocator);

        // Check if token needs refresh
        if (creds.willExpireSoon(120)) {
            stdout.print("Token expiring soon, refreshing...\n", .{});

            const new_creds = try Auth.OAuth.refreshTokens(allocator, creds.refreshToken);
            defer new_creds.deinit(allocator);

            // Update stored credentials
            const updated_store_creds = Auth.store.StoredCredentials{
                .type = new_creds.type,
                .access_token = new_creds.accessToken,
                .refresh_token = new_creds.refreshToken,
                .expires_at = new_creds.expiresAt,
            };
            try store.save(updated_store_creds);

            // Use new credentials
            creds.deinit(allocator);
            creds = new_creds;
        }

        stdout.print("Making test API call to Anthropic Messages API...\n", .{});

        // Initialize Anthropic client
        var client = try network.Anthropic.Client.Client.initWithOAuth(allocator, creds, null);
        defer client.deinit();

        // Make a simple test call
        const messages = [_]network.Anthropic.Message{
            .{ .role = .user, .content = .{ .text = "Say 'Test successful!' in exactly 3 words." } },
        };

        if (args.stream) {
            // Streaming test
            var shared_ctx = @import("../context.zig").SharedContext.init(allocator);
            defer shared_ctx.deinit();

            const stream_params = network.Anthropic.Client.StreamParameters{
                .model = "claude-3-5-sonnet-20241022",
                .messages = &messages,
                .maxTokens = 64,
                .temperature = 0.7,
                .onToken = struct {
                    fn onToken(ctx: *@import("../context.zig").SharedContext, token: []const u8) void {
                        _ = ctx;
                        std.debug.print("{s}", .{token});
                    }
                }.onToken,
            };

            try client.createMessageStream(&shared_ctx, stream_params);
            stdout.print("\n✓ Streaming API call successful!\n", .{});
        } else {
            // Non-streaming test
            const params = network.Anthropic.Client.MessageParameters{
                .model = "claude-3-5-sonnet-20241022",
                .messages = &messages,
                .maxTokens = 64,
                .temperature = 0.7,
                .stream = false,
            };

            var result = try client.createMessage(params);
            defer result.deinit();

            stdout.print("Claude says: {s}\n", .{result.content});
            stdout.print("✓ API call successful!\n", .{});
        }
    }

    /// Manual login flow (copy-paste)
    fn loginManual(_: std.mem.Allocator) !void {
        const stdout = std.debug;
        stdout.print("Manual OAuth login is not available in this build.\n", .{});
        stdout.print("Please run: docz auth login\n", .{});
        return error.ManualLoginNotSupported;
    }
};

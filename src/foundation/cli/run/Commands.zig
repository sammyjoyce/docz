//! CLI commands for running the agent loop
//!
//! This module provides command-line interface handlers for the run command
//! that starts the interactive agent REPL with OAuth authentication.

const std = @import("std");
const network = @import("network_shared");
const Auth = network.Auth;
const tools = @import("tools_shared");

const log = std.log.scoped(.cli_run);

/// Run command configuration
pub const RunConfig = struct {
    model: []const u8 = "claude-3-5-sonnet-20241022",
    max_tokens: u32 = 4096,
    temperature: f32 = 0.7,
    stream: bool = true,
    system_prompt: ?[]const u8 = null,
};

/// Handle the run command
pub fn handleRunCommand(allocator: std.mem.Allocator, config: RunConfig) !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    // Check authentication
    const store = Auth.store.TokenStore.init(allocator, .{});

    if (!store.exists()) {
        try stdout.print("Not authenticated. Run 'docz auth login' to authenticate.\n", .{});
        return;
    }

    var creds = try store.load();
    defer allocator.free(creds.type);
    defer allocator.free(creds.access_token);
    defer allocator.free(creds.refresh_token);

    // Check and refresh token if needed
    if (creds.willExpireSoon(120)) {
        try stdout.print("Token expiring soon, refreshing...\n", .{});

        var token_client = Auth.token_client.TokenClient.init(allocator, .{
            .client_id = "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            .token_endpoint = "https://console.anthropic.com/v1/oauth/token",
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

    // Initialize Anthropic client (provider-based)
    const provider_creds = network.Anthropic.Models.Credentials{
        .type = creds.type,
        .accessToken = creds.access_token,
        .refreshToken = creds.refresh_token,
        .expiresAt = creds.expires_at,
    };
    var client = try network.Anthropic.Client.initWithOAuth(allocator, provider_creds, store.config.path);
    defer client.deinit();

    // Shared context for streaming and token refresh
    var shared_ctx = network.Anthropic.Client.SharedContext.init(allocator);
    defer shared_ctx.deinit();

    // Initialize conversation history
    var messages = std.ArrayList(network.Anthropic.Message).init(allocator);
    defer messages.deinit();

    // Add system prompt if provided
    if (config.system_prompt) |prompt| {
        try messages.append(.{
            .role = .user,
            .content = try allocator.dupe(u8, prompt),
        });
    }

    // Print banner
    try stdout.print("\n┌────────────────────────────────────────┐\n", .{});
    try stdout.print("│  Docz Agent - Claude AI Assistant     │\n", .{});
    try stdout.print("│  Model: {s: <30} │\n", .{config.model});
    try stdout.print("│  Auth: OAuth (Claude Pro/Max)         │\n", .{});
    try stdout.print("│  Type 'exit' or Ctrl-C to quit        │\n", .{});
    try stdout.print("└────────────────────────────────────────┘\n\n", .{});

    // REPL loop
    while (true) {
        try stdout.print("You: ", .{});

        var buf: [4096]u8 = undefined;
        if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |user_input| {
            const trimmed = std.mem.trim(u8, user_input, " \t\r\n");

            if (std.mem.eql(u8, trimmed, "exit")) {
                break;
            }

            if (trimmed.len == 0) {
                continue;
            }

            // Add user message
            try messages.append(.{ .role = .user, .content = try allocator.dupe(u8, trimmed) });

            try stdout.print("\nClaude: ", .{});

            // Send message and get non-streaming response via provider
            const result = try client.create(&shared_ctx, .{
                .model = config.model,
                .messages = messages.items,
                .maxTokens = config.max_tokens,
                .temperature = config.temperature,
                .system = config.system_prompt,
            });
            // result.content/id are owned by client allocator (freed when client deinit)

            // Print and append assistant content
            try stdout.print("{s}", .{result.content});
            try messages.append(.{ .role = .assistant, .content = try allocator.dupe(u8, result.content) });

            try stdout.print("\n\n", .{});

            // Keep conversation history manageable (max 20 messages)
            if (messages.items.len > 20) {
                // Keep system prompt and last 19 messages
                const start = if (config.system_prompt != null) 1 else 0;
                const to_remove = messages.items.len - 20;
                for (messages.items[start .. start + to_remove]) |msg| {
                    allocator.free(msg.content);
                }
                std.mem.copyForwards(network.Anthropic.Message, messages.items[start..], messages.items[start + to_remove ..]);
                messages.shrinkRetainingCapacity(20);
            }
        } else {
            // EOF
            break;
        }
    }

    try stdout.print("\nGoodbye!\n", .{});
}

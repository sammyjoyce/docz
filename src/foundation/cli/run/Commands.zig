//! CLI commands for running the agent loop
//!
//! This module provides command-line interface handlers for the run command
//! that starts the interactive agent REPL with OAuth authentication.

const std = @import("std");
const network = @import("../../network.zig");
const Auth = network.Auth;
const tools = @import("../../tools.zig");
const context = @import("../../context.zig");

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
    const stdout = std.debug;
    var stdin_file = std.fs.File.stdin();
    var stdin_buf: [4096]u8 = undefined;
    var stdin = stdin_file.reader(stdin_buf[0..]);

    // Check authentication
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

    var creds = try store.load();
    defer allocator.free(creds.type);
    defer allocator.free(creds.access_token);
    defer allocator.free(creds.refresh_token);

    // Check and refresh token if needed
    if (creds.willExpireSoon(120)) {
        stdout.print("Token expiring soon, refreshing...\n", .{});

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

    // Initialize Anthropic client with OAuth credentials
    const oauth_creds = network.Auth.OAuth.Credentials{
        .type = creds.type,
        .accessToken = creds.access_token,
        .refreshToken = creds.refresh_token,
        .expiresAt = creds.expires_at,
    };
    var client = try network.Anthropic.Client.Client.initWithOAuth(allocator, oauth_creds, null);
    defer client.deinit();

    // Shared context for streaming and token refresh
    var shared_ctx = context.SharedContext.init(allocator);
    defer shared_ctx.deinit();

    // Initialize conversation history
    var messages = std.ArrayList(network.Anthropic.Message).init(allocator);
    defer messages.deinit();
    defer {
        for (messages.items) |msg| {
            allocator.free(msg.content);
        }
    }

    // Print banner
    stdout.print("\n┌────────────────────────────────────────────┐\n", .{});
    stdout.print("│  Docz Agent - Claude AI Assistant         │\n", .{});
    stdout.print("│  Model: {s: <35} │\n", .{config.model});
    stdout.print("│  Auth: OAuth (Claude Pro/Max)              │\n", .{});
    stdout.print("│  Streaming: {s: <31} │\n", .{if (config.stream) "Enabled" else "Disabled"});
    stdout.print("│  Type 'exit' or Ctrl-C to quit            │\n", .{});
    stdout.print("└────────────────────────────────────────────┘\n\n", .{});

    // REPL loop
    while (true) {
        stdout.print("You: ", .{});

        var buf: [4096]u8 = undefined;
        if (try stdin.interface.readUntilDelimiterOrEof(&buf, '\n')) |user_input| {
            const trimmed = std.mem.trim(u8, user_input, " \t\r\n");

            if (std.mem.eql(u8, trimmed, "exit")) {
                break;
            }

            if (trimmed.len == 0) {
                continue;
            }

            // Add user message
            try messages.append(.{ .role = .user, .content = try allocator.dupe(u8, trimmed) });

            stdout.print("\nClaude: ", .{});

            if (config.stream) {
                // Streaming mode with SSE
                shared_ctx.anthropic.contentCollector.clearRetainingCapacity();
                shared_ctx.anthropic.messageId = null;
                shared_ctx.anthropic.stopReason = null;
                shared_ctx.anthropic.model = null;

                const streamParams = network.Anthropic.Client.StreamParameters{
                    .model = config.model,
                    .messages = messages.items,
                    .maxTokens = config.max_tokens,
                    .temperature = config.temperature,
                    .system = config.system_prompt,
                    .onToken = struct {
                        fn callback(ctx: *context.SharedContext, data: []const u8) void {
                            // Parse SSE event data and extract text content
                            _ = ctx;
                            const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, data, .{
                                .ignore_unknown_fields = true,
                            }) catch return;
                            defer parsed.deinit();
                            
                            if (parsed.value == .object) {
                                if (parsed.value.object.get("delta")) |delta| {
                                    if (delta == .object) {
                                        if (delta.object.get("text")) |text| {
                                            if (text == .string) {
                                                std.debug.print("{s}", .{text.string});
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }.callback,
                };

                try client.createMessageStream(&shared_ctx, streamParams);

                // Add assistant message to history
                const assistant_content = try allocator.dupe(u8, shared_ctx.anthropic.contentCollector.items);
                try messages.append(.{ .role = .assistant, .content = assistant_content });
            } else {
                // Non-streaming mode
                var result = try client.createMessage(.{
                    .model = config.model,
                    .messages = messages.items,
                    .maxTokens = config.max_tokens,
                    .temperature = config.temperature,
                    .system = config.system_prompt,
                });
                defer result.deinit();

                // Print and append assistant content
                stdout.print("{s}", .{result.content});
                try messages.append(.{ .role = .assistant, .content = try allocator.dupe(u8, result.content) });
            }

            stdout.print("\n\n", .{});

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

    stdout.print("\nGoodbye!\n", .{});
}

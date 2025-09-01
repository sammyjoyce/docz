//! Engine-centric agent loop (Zig 0.15.1)
//! The single, shared run loop used by all agents.
//! ~300 LoC core implementation with OAuth + SSE streaming support

const std = @import("std");
// Import shared modules directly to avoid circular dependencies
const network = @import("network_shared");
const Auth = network.Auth;
const tools = @import("tools_shared");

const log = std.log.scoped(.engine);

/// Agent specification interface
pub const AgentSpec = struct {
    /// Build the system prompt for this agent
    buildSystemPrompt: *const fn (allocator: std.mem.Allocator, opts: CliOptions) anyerror![]const u8,
    /// Register tools for this agent
    registerTools: *const fn (registry: *tools.Registry) anyerror!void,
};

/// CLI options for engine
pub const CliOptions = struct {
    model: []const u8 = "claude-3-5-sonnet-20241022",
    max_tokens: u32 = 4096,
    temperature: f32 = 0.7,
    stream: bool = true,
    verbose: bool = false,
    history: ?[]const u8 = null,
    input: ?[]const u8 = null,
    output: ?[]const u8 = null,
};

/// Engine runtime state
pub const Engine = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    client: ?network.Anthropic.Client,
    shared_ctx: network.Anthropic.Client.SharedContext,
    messages: std.ArrayList(network.Anthropic.Message),
    tool_registry: tools.Registry,
    options: CliOptions,

    pub fn init(allocator: std.mem.Allocator, options: CliOptions) !Self {
        return Self{
            .allocator = allocator,
            .client = null,
            .shared_ctx = network.Anthropic.Client.SharedContext.init(allocator),
            .messages = std.ArrayList(network.Anthropic.Message).init(allocator),
            .tool_registry = tools.Registry.init(allocator),
            .options = options,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.messages.items) |msg| {
            self.allocator.free(msg.content);
        }
        self.messages.deinit();
        self.shared_ctx.deinit();
        if (self.client) |*c| c.deinit();
        self.tool_registry.deinit();
    }

    /// Authenticate and initialize client
    pub fn authenticate(self: *Self) !void {
        const store = Auth.store.TokenStore.init(self.allocator, .{});

        if (!store.exists()) {
            return error.NotAuthenticated;
        }

        var creds = try store.load();
        defer self.allocator.free(creds.type);
        defer self.allocator.free(creds.access_token);
        defer self.allocator.free(creds.refresh_token);

        // Check and refresh token if needed
        if (creds.willExpireSoon(120)) {
            log.info("Token expiring soon, refreshing...", .{});

            var token_client = Auth.token_client.TokenClient.init(self.allocator, .{
                .client_id = "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
                .token_endpoint = "https://console.anthropic.com/v1/oauth/token",
            });
            defer token_client.deinit();

            const new_tokens = try token_client.refreshToken(creds.refresh_token);
            defer new_tokens.deinit(self.allocator);

            // Update stored credentials
            const new_creds = Auth.store.StoredCredentials{
                .type = "oauth",
                .access_token = new_tokens.access_token,
                .refresh_token = new_tokens.refresh_token,
                .expires_at = std.time.timestamp() + new_tokens.expires_in,
            };
            try store.save(new_creds);

            // Use new access token
            self.allocator.free(creds.access_token);
            creds.access_token = try self.allocator.dupe(u8, new_tokens.access_token);
        }

        // Initialize Anthropic client with OAuth
        const provider_creds = network.Anthropic.Models.Credentials{
            .type = creds.type,
            .accessToken = creds.access_token,
            .refreshToken = creds.refresh_token,
            .expiresAt = creds.expires_at,
        };
        self.client = try network.Anthropic.Client.initWithOAuth(self.allocator, provider_creds, store.config.path);
    }

    /// Run inference with streaming support
    pub fn runInference(self: *Self, user_input: []const u8) !void {
        const stdout = std.io.getStdOut().writer();

        // Add user message
        try self.messages.append(.{
            .role = .user,
            .content = try self.allocator.dupe(u8, user_input),
        });

        // Trim context if too large (keep last 20 messages)
        try self.trimContext();

        if (false and self.options.stream) { // TODO: Fix streaming callback
            // Streaming mode with SSE
            try stdout.print("\nClaude: ", .{});

            var assistant_content = std.ArrayList(u8).init(self.allocator);
            defer assistant_content.deinit();

            // Callback for streaming events
            const StreamCallback = struct {
                content: *std.ArrayList(u8),
                writer: std.fs.File.Writer,

                fn callback(event: network.ServerSentEvent, ctx: ?*anyopaque) !void {
                    _ = ctx; // Context passed from createStream but not needed here

                    if (std.mem.eql(u8, event.event orelse "", "content_block_delta")) {
                        // Parse delta and accumulate text
                        const parsed = try std.json.parseFromSlice(
                            struct { delta: struct { text: []const u8 } },
                            std.heap.page_allocator,
                            event.data orelse "",
                            .{ .ignore_unknown_fields = true },
                        );
                        defer parsed.deinit();

                        // Need to use stdout directly since we can't access struct fields from static callback
                        const out = std.io.getStdOut().writer();
                        try out.print("{s}", .{parsed.value.delta.text});
                        // TODO: Accumulate content for history
                    }
                }
            };

            var callback_data = StreamCallback{
                .content = &assistant_content,
                .writer = stdout,
            };

            // Stream the response
            const client = self.client orelse return error.NotAuthenticated;
            try client.createStream(&self.shared_ctx, .{
                .model = self.options.model,
                .messages = self.messages.items,
                .maxTokens = self.options.max_tokens,
                .temperature = self.options.temperature,
                .system = null,
            }, StreamCallback.callback, &callback_data);

            // Add assistant message to history (TODO: accumulate from stream)
            try self.messages.append(.{
                .role = .assistant,
                .content = try self.allocator.dupe(u8, "[streaming not yet implemented]"),
            });

            try stdout.print("\n\n", .{});
        } else {
            // Non-streaming mode
            const client = self.client orelse return error.NotAuthenticated;
            const result = try client.create(&self.shared_ctx, .{
                .model = self.options.model,
                .messages = self.messages.items,
                .maxTokens = self.options.max_tokens,
                .temperature = self.options.temperature,
                .system = null,
            });

            try stdout.print("\nClaude: {s}\n\n", .{result.content});

            // Add assistant message
            try self.messages.append(.{
                .role = .assistant,
                .content = try self.allocator.dupe(u8, result.content),
            });
        }
    }

    /// Context hygiene - keep conversation manageable
    fn trimContext(self: *Self) !void {
        if (self.messages.items.len > 20) {
            // Keep last 20 messages
            const to_remove = self.messages.items.len - 20;
            for (self.messages.items[0..to_remove]) |msg| {
                self.allocator.free(msg.content);
            }
            std.mem.copyForwards(
                network.Anthropic.Message,
                self.messages.items[0..],
                self.messages.items[to_remove..],
            );
            self.messages.shrinkRetainingCapacity(20);
        }
    }
};

/// Main engine entry point
pub fn runWithOptions(
    allocator: std.mem.Allocator,
    options: CliOptions,
    spec: AgentSpec,
    _: []const u8, // working directory (unused for now)
) !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    // Initialize engine
    var engine = try Engine.init(allocator, options);
    defer engine.deinit();

    // Authenticate
    engine.authenticate() catch |err| {
        if (err == error.NotAuthenticated) {
            try stdout.print("Not authenticated. Run 'docz auth login' to authenticate.\n", .{});
            return;
        }
        return err;
    };

    // Build system prompt
    const system_prompt = try spec.buildSystemPrompt(allocator, options);
    defer allocator.free(system_prompt);

    // Register tools
    try spec.registerTools(&engine.tool_registry);

    // Add system prompt as first message if provided
    if (system_prompt.len > 0) {
        try engine.messages.append(.{
            .role = .user,
            .content = try allocator.dupe(u8, system_prompt),
        });
    }

    // Print banner
    try stdout.print("\n┌────────────────────────────────────────┐\n", .{});
    try stdout.print("│  Docz Agent - Claude AI Assistant     │\n", .{});
    try stdout.print("│  Model: {s: <30} │\n", .{options.model});
    try stdout.print("│  Auth: OAuth (Claude Pro/Max)         │\n", .{});
    try stdout.print("│  Type 'exit' or Ctrl-C to quit        │\n", .{});
    try stdout.print("└────────────────────────────────────────┘\n\n", .{});

    // Check for input flag
    if (options.input) |input| {
        // Single-shot mode
        try engine.runInference(input);
        if (options.output) |output_path| {
            const file = try std.fs.cwd().createFile(output_path, .{});
            defer file.close();
            if (engine.messages.items.len > 0) {
                const last_msg = engine.messages.items[engine.messages.items.len - 1];
                try file.writeAll(last_msg.content);
            }
        }
        return;
    }

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

            try engine.runInference(trimmed);
        } else {
            // EOF
            break;
        }
    }

    try stdout.print("\nGoodbye!\n", .{});
}

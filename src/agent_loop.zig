//! Minimal core agent loop (~300 LoC)
//! Handles user input, Anthropic Messages API calls, tool execution, and streaming output

const std = @import("std");
const foundation = @import("foundation");
const network = foundation.network;
const tools = foundation.tools;
const context = foundation.context;

const log = std.log.scoped(.agent);

/// Agent configuration
pub const Config = struct {
    model: []const u8 = "claude-3-5-sonnet-20241022",
    max_tokens: u32 = 4096,
    temperature: f32 = 0.7,
    stream: bool = true,
    system_prompt: ?[]const u8 = null,
    history_limit: usize = 20,
    token_refresh_leeway: i64 = 120, // seconds before expiry to refresh
};

/// Core agent loop state
pub const Agent = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: Config,
    client: network.Anthropic.Client,
    shared_ctx: context.SharedContext,
    messages: std.ArrayList(network.Anthropic.Message),
    tool_registry: tools.Registry,

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        // Load OAuth credentials
        const store = network.Auth.store.TokenStore.init(allocator, .{});
        if (!store.exists()) {
            return error.NotAuthenticated;
        }

        const creds = try store.load();
        defer allocator.free(creds.type);
        defer allocator.free(creds.access_token);
        defer allocator.free(creds.refresh_token);

        // Convert to OAuth credentials
        const oauth_creds = network.Auth.OAuth.Credentials{
            .type = try allocator.dupe(u8, creds.type),
            .accessToken = try allocator.dupe(u8, creds.access_token),
            .refreshToken = try allocator.dupe(u8, creds.refresh_token),
            .expiresAt = creds.expires_at,
        };

        var client = try network.Anthropic.Client.Client.initWithOAuth(allocator, oauth_creds, store.config.path);
        errdefer client.deinit();

        var shared_ctx = context.SharedContext.init(allocator);
        errdefer shared_ctx.deinit();

        var messages = std.ArrayList(network.Anthropic.Message).init(allocator);
        errdefer messages.deinit();

        var tool_registry = tools.Registry.init(allocator);
        errdefer tool_registry.deinit();

        return Self{
            .allocator = allocator,
            .config = config,
            .client = client,
            .shared_ctx = shared_ctx,
            .messages = messages,
            .tool_registry = tool_registry,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.messages.items) |msg| {
            self.allocator.free(msg.content);
        }
        self.messages.deinit();
        self.shared_ctx.deinit();
        self.client.deinit();
        self.tool_registry.deinit();
    }

    /// Run a single inference cycle with the given input
    pub fn runInference(self: *Self, user_input: []const u8) !void {
        const stdout = std.debug;

        // Add user message
        try self.messages.append(.{
            .role = .user,
            .content = try self.allocator.dupe(u8, user_input),
        });

        // Trim context if needed
        try self.trimContext();

        stdout.print("\nClaude: ", .{});

        if (self.config.stream) {
            // Streaming mode with SSE
            self.shared_ctx.anthropic.contentCollector.clearRetainingCapacity();
            self.shared_ctx.anthropic.messageId = null;
            self.shared_ctx.anthropic.stopReason = null;
            self.shared_ctx.anthropic.model = null;
            self.shared_ctx.tools.tokenBuffer.clearRetainingCapacity();
            self.shared_ctx.tools.hasPending = false;
            self.shared_ctx.tools.toolName = null;
            self.shared_ctx.tools.toolId = null;
            self.shared_ctx.tools.jsonComplete = null;

            const streamParams = network.Anthropic.Client.StreamParameters{
                .model = self.config.model,
                .messages = self.messages.items,
                .maxTokens = self.config.max_tokens,
                .temperature = self.config.temperature,
                .system = self.config.system_prompt,
                .onToken = processStreamToken,
            };

            try self.client.stream(&self.shared_ctx, streamParams);

            // Add assistant response to history
            const content = try self.allocator.dupe(u8, self.shared_ctx.anthropic.contentCollector.items);
            try self.messages.append(.{
                .role = .assistant,
                .content = content,
            });

            // Process any tool calls
            try self.processToolCalls();
        } else {
            // Non-streaming mode
            const result = try self.client.complete(&self.shared_ctx, .{
                .model = self.config.model,
                .messages = self.messages.items,
                .maxTokens = self.config.max_tokens,
                .temperature = self.config.temperature,
                .system = self.config.system_prompt,
            });
            defer result.deinit();

            stdout.print("{s}", .{result.content});
            try self.messages.append(.{
                .role = .assistant,
                .content = try self.allocator.dupe(u8, result.content),
            });
        }

        stdout.print("\n\n", .{});
    }

    /// Process streaming tokens (SSE events)
    fn processStreamToken(ctx: *context.SharedContext, data: []const u8) void {
        // Parse the SSE event data
        const EventData = struct {
            type: ?[]const u8 = null,
            message: ?struct {
                id: ?[]const u8 = null,
                model: ?[]const u8 = null,
                stop_reason: ?[]const u8 = null,
            } = null,
            content_block: ?struct {
                type: ?[]const u8 = null,
                id: ?[]const u8 = null,
                name: ?[]const u8 = null,
            } = null,
            delta: ?struct {
                type: ?[]const u8 = null,
                text: ?[]const u8 = null,
                partial_json: ?[]const u8 = null,
            } = null,
        };

        const parsed = std.json.parseFromSlice(EventData, ctx.anthropic.allocator, data, .{
            .ignore_unknown_fields = true
        }) catch return;
        defer parsed.deinit();

        const event_type = parsed.value.type orelse return;

        // Handle different event types
        if (std.mem.eql(u8, event_type, "message_start")) {
            if (parsed.value.message) |msg| {
                if (msg.id) |id| {
                    ctx.anthropic.messageId = ctx.anthropic.allocator.dupe(u8, id) catch null;
                }
                if (msg.model) |model| {
                    ctx.anthropic.model = ctx.anthropic.allocator.dupe(u8, model) catch null;
                }
            }
        } else if (std.mem.eql(u8, event_type, "content_block_start")) {
            // Initialize tool JSON accumulation if this is a tool_use block
            if (parsed.value.content_block) |block| {
                if (block.type) |block_type| {
                    if (std.mem.eql(u8, block_type, "tool_use")) {
                        // Start accumulating tool JSON
                        ctx.tools.hasPending = true;
                        ctx.tools.toolName = if (block.name) |name|
                            ctx.anthropic.allocator.dupe(u8, name) catch null
                        else
                            null;
                        ctx.tools.toolId = if (block.id) |id|
                            ctx.anthropic.allocator.dupe(u8, id) catch null
                        else
                            null;
                        ctx.tools.jsonComplete = null;
                        ctx.tools.tokenBuffer.clearRetainingCapacity();
                    }
                }
            }
        } else if (std.mem.eql(u8, event_type, "content_block_delta")) {
            if (parsed.value.delta) |delta| {
                if (delta.type) |delta_type| {
                    if (std.mem.eql(u8, delta_type, "text_delta")) {
                        if (delta.text) |text| {
                            // Print text content
                            std.debug.print("{s}", .{text});
                            // Accumulate for history
                            ctx.anthropic.contentCollector.appendSlice(ctx.anthropic.allocator, text) catch {};
                        }
                    } else if (std.mem.eql(u8, delta_type, "input_json_delta")) {
                        if (delta.partial_json) |json_part| {
                            // Accumulate tool JSON
                            ctx.tools.tokenBuffer.appendSlice(json_part) catch {};
                        }
                    }
                }
            }
        } else if (std.mem.eql(u8, event_type, "content_block_stop")) {
            // Finalize tool JSON accumulation
            if (ctx.tools.hasPending and ctx.tools.tokenBuffer.items.len > 0) {
                ctx.tools.jsonComplete = ctx.anthropic.allocator.dupe(u8, ctx.tools.tokenBuffer.items) catch null;
                ctx.tools.hasPending = false;
            }
        } else if (std.mem.eql(u8, event_type, "message_delta")) {
            if (parsed.value.delta) |delta| {
                if (delta.stop_reason) |stop_reason| {
                    ctx.anthropic.stopReason = ctx.anthropic.allocator.dupe(u8, stop_reason) catch null;
                }
            }
        } else if (std.mem.eql(u8, event_type, "message_stop")) {
            // Message complete
        }
    }

    /// Process accumulated tool calls
    fn processToolCalls(self: *Self) !void {
        // Check if we have accumulated tool JSON from streaming
        if (self.shared_ctx.tools.jsonComplete) |tool_json| {
            defer {
                self.allocator.free(tool_json);
                self.shared_ctx.tools.jsonComplete = null;
            }

            // Parse the tool call
            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, tool_json, .{}) catch |err| {
                log.warn("Failed to parse tool call JSON: {}", .{err});
                return;
            };
            defer parsed.deinit();

            // Extract tool name and execute
            if (self.shared_ctx.tools.toolName) |tool_name| {
                defer {
                    self.allocator.free(tool_name);
                    self.shared_ctx.tools.toolName = null;
                }

                log.info("Executing tool: {s}", .{tool_name});

                // Execute through registry if available
                if (self.tool_registry.get(tool_name)) |tool_func| {
                    // Convert parameters to JSON string for the tool function
                    const args_json = try std.json.stringifyAlloc(self.allocator, parsed.value, .{});
                    defer self.allocator.free(args_json);

                    const result = tool_func(&self.shared_ctx, self.allocator, args_json) catch |err| {
                        log.err("Tool execution failed: {s} - {}", .{ tool_name, err });
                        const error_msg = try std.fmt.allocPrint(
                            self.allocator,
                            "Tool '{s}' failed: {s}",
                            .{ tool_name, @errorName(err) }
                        );
                        defer self.allocator.free(error_msg);

                        try self.messages.append(.{
                            .role = .user,
                            .content = error_msg,
                        });
                        return;
                    };
                    defer self.allocator.free(result);

                    // Add tool result as user message
                    const tool_result_content = try std.fmt.allocPrint(
                        self.allocator,
                        "Tool '{s}' result: {s}",
                        .{ tool_name, result }
                    );

                    try self.messages.append(.{
                        .role = .user,
                        .content = tool_result_content,
                    });

                    // Continue conversation with tool result
                    try self.runInference("");
                }
            }
        }

        // Clean up tool context
        if (self.shared_ctx.tools.toolId) |id| {
            self.allocator.free(id);
            self.shared_ctx.tools.toolId = null;
        }
    }

    /// Trim conversation history to stay within limits
    fn trimContext(self: *Self) !void {
        if (self.messages.items.len <= self.config.history_limit) return;

        const to_remove = self.messages.items.len - self.config.history_limit;
        
        // Keep system prompt if present (first message)
        const start: usize = if (self.config.system_prompt != null) 1 else 0;
        
        // Free old messages
        for (self.messages.items[start .. start + to_remove]) |msg| {
            self.allocator.free(msg.content);
        }

        // Shift remaining messages
        std.mem.copyForwards(
            network.Anthropic.Message,
            self.messages.items[start..],
            self.messages.items[start + to_remove ..],
        );
        
        self.messages.shrinkRetainingCapacity(self.config.history_limit);

        log.info("Trimmed context to {} messages", .{self.messages.items.len});
    }

    /// Register a tool with the agent
    pub fn registerTool(self: *Self, tool: tools.Tool) !void {
        try self.tool_registry.register(tool);
    }

    /// Build system prompt with tool descriptions
    pub fn buildSystemPrompt(self: *Self) !?[]const u8 {
        if (self.tool_registry.items.len == 0 and self.config.system_prompt == null) {
            return null;
        }

        var prompt = std.ArrayList(u8).init(self.allocator);
        defer prompt.deinit();

        if (self.config.system_prompt) |sp| {
            try prompt.appendSlice(sp);
            try prompt.appendSlice("\n\n");
        }

        if (self.tool_registry.items.len > 0) {
            try prompt.appendSlice("Available tools:\n");
            for (self.tool_registry.items) |tool| {
                try prompt.writer().print("- {s}: {s}\n", .{ tool.name, tool.description });
            }
        }

        return try prompt.toOwnedSlice();
    }
};

/// Run the agent REPL loop
pub fn runREPL(allocator: std.mem.Allocator, config: Config) !void {
    const stdout = std.debug;
    var stdin_file = std.fs.File.stdin();
    var stdin_buf: [4096]u8 = undefined;
    var stdin = stdin_file.reader(stdin_buf[0..]);

    var agent = try Agent.init(allocator, config);
    defer agent.deinit();

    // Print banner
    stdout.print("\n┌────────────────────────────────────────────┐\n", .{});
    stdout.print("│  Agent Loop - Claude AI Assistant         │\n", .{});
    stdout.print("│  Model: {s: <35} │\n", .{config.model});
    stdout.print("│  Streaming: {s: <31} │\n", .{if (config.stream) "Enabled" else "Disabled"});
    stdout.print("│  Type 'exit' or Ctrl-C to quit            │\n", .{});
    stdout.print("└────────────────────────────────────────────┘\n\n", .{});

    // Main loop
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

            try agent.runInference(trimmed);
        } else {
            // EOF
            break;
        }
    }

    stdout.print("\nGoodbye!\n", .{});
}

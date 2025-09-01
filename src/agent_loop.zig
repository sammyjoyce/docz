//! Minimal core agent loop (~300 LoC)
//! Handles user input, Anthropic Messages API calls, tool execution, and streaming output

const std = @import("std");
const network = @import("foundation/network.zig");
const tools = @import("foundation/tools.zig");
const context = @import("foundation/context.zig");

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

        var creds = try store.load();
        defer allocator.free(creds.type);
        defer allocator.free(creds.access_token);
        defer allocator.free(creds.refresh_token);

        // Convert to provider credentials
        const provider_creds = network.Anthropic.Models.Credentials{
            .type = try allocator.dupe(u8, creds.type),
            .accessToken = try allocator.dupe(u8, creds.access_token),
            .refreshToken = try allocator.dupe(u8, creds.refresh_token),
            .expiresAt = creds.expires_at,
        };

        var client = try network.Anthropic.Client.initWithOAuth(allocator, provider_creds, store.config.path);
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

        try stdout.print("\nClaude: ", .{});

        if (self.config.stream) {
            // Streaming mode with SSE
            self.shared_ctx.anthropic.contentCollector.clearRetainingCapacity();
            self.shared_ctx.anthropic.messageId = null;
            self.shared_ctx.anthropic.stopReason = null;
            self.shared_ctx.anthropic.model = null;
            self.shared_ctx.anthropic.toolCallsAccumulator.clearRetainingCapacity();

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

            try stdout.print("{s}", .{result.content});
            try self.messages.append(.{
                .role = .assistant,
                .content = try self.allocator.dupe(u8, result.content),
            });
        }

        try stdout.print("\n\n", .{});
    }

    /// Process streaming tokens (SSE events)
    fn processStreamToken(ctx: *context.SharedContext, data: []const u8) void {
        const event_type = ctx.anthropic.lastEventType orelse "";
        
        if (std.mem.eql(u8, event_type, "content_block_delta")) {
            // Parse delta for text content
            const Delta = struct {
                delta: ?struct {
                    text: ?[]const u8 = null,
                    type: ?[]const u8 = null,
                } = null,
            };

            const parsed = std.json.parseFromSlice(Delta, ctx.anthropic.allocator, data, .{
                .ignore_unknown_fields = true,
            }) catch {
                // If not valid JSON, accumulate raw
                ctx.anthropic.contentCollector.appendSlice(data) catch {};
                std.debug.print("{s}", .{data});
                return;
            };
            defer parsed.deinit();

            if (parsed.value.delta) |delta| {
                if (delta.text) |text| {
                    ctx.anthropic.contentCollector.appendSlice(text) catch {};
                    std.debug.print("{s}", .{text});
                }
            }
        } else if (std.mem.eql(u8, event_type, "content_block_stop")) {
            // Tool JSON should be complete now, process if needed
            const content = ctx.anthropic.contentCollector.items;
            if (std.mem.startsWith(u8, content, "{") and std.mem.endsWith(u8, content, "}")) {
                // Might be tool call JSON
                ctx.anthropic.toolCallsAccumulator.appendSlice(content) catch {};
            }
        }
    }

    /// Process accumulated tool calls
    fn processToolCalls(self: *Self) !void {
        const tool_json = self.shared_ctx.anthropic.toolCallsAccumulator.items;
        if (tool_json.len == 0) return;

        // Parse and execute tools
        const ToolCall = struct {
            name: []const u8,
            parameters: std.json.Value,
        };

        const parsed = std.json.parseFromSlice(ToolCall, self.allocator, tool_json, .{
            .ignore_unknown_fields = true,
        }) catch {
            // Not a valid tool call
            return;
        };
        defer parsed.deinit();

        log.info("Executing tool: {s}", .{parsed.value.name});

        // Execute through registry if available
        if (self.tool_registry.get(parsed.value.name)) |tool| {
            const result = try tool.execute(self.allocator, parsed.value.parameters);
            defer self.allocator.free(result);

            // Add tool result as user message
            try self.messages.append(.{
                .role = .user,
                .content = try std.fmt.allocPrint(self.allocator, "Tool result: {s}", .{result}),
            });

            // Continue conversation with tool result
            try self.runInference("");
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
    const stdin = std.io.getStdIn().reader();

    var agent = try Agent.init(allocator, config);
    defer agent.deinit();

    // Print banner
    try stdout.print("\n┌────────────────────────────────────────────┐\n", .{});
    try stdout.print("│  Agent Loop - Claude AI Assistant         │\n", .{});
    try stdout.print("│  Model: {s: <35} │\n", .{config.model});
    try stdout.print("│  Streaming: {s: <31} │\n", .{if (config.stream) "Enabled" else "Disabled"});
    try stdout.print("│  Type 'exit' or Ctrl-C to quit            │\n", .{});
    try stdout.print("└────────────────────────────────────────────┘\n\n", .{});

    // Main loop
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

            try agent.runInference(trimmed);
        } else {
            // EOF
            break;
        }
    }

    try stdout.print("\nGoodbye!\n", .{});
}
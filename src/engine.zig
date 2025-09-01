//! Engine-centric agent loop (Zig 0.15.1)
//! The single, shared run loop used by all agents.
//! ~300 LoC core implementation with OAuth + SSE streaming support

const std = @import("std");
const foundation = @import("foundation");
const network = foundation.network;
const Auth = network.Auth;
const tools = foundation.tools;
const SharedContext = foundation.context.SharedContext;

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
    client: ?network.Anthropic.Client.Client,
    shared_ctx: SharedContext,
    messages: std.ArrayList(network.Anthropic.Message),
    tool_registry: tools.Registry,
    options: CliOptions,
    /// Optional base system prompt provided by the AgentSpec (owned by Engine)
    system_base: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, options: CliOptions) !Self {
        return Self{
            .allocator = allocator,
            .client = null,
            .shared_ctx = SharedContext.init(allocator),
            .messages = std.ArrayList(network.Anthropic.Message).init(allocator),
            .tool_registry = tools.Registry.init(allocator),
            .options = options,
            .system_base = null,
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
        if (self.system_base) |sb| self.allocator.free(sb);
    }

    /// Authenticate and initialize client
    pub fn authenticate(self: *Self) !void {
        // Get agent name from environment or use default
        const agent_name = std.process.getEnvVarOwned(self.allocator, "AGENT_NAME") catch |err| blk: {
            if (err == error.EnvironmentVariableNotFound) {
                break :blk try self.allocator.dupe(u8, "docz");
            }
            return err;
        };
        defer self.allocator.free(agent_name);

        // Use standard credential path: ~/.local/share/{agent_name}/auth.json
        const store = Auth.store.TokenStore.init(self.allocator, .{
            .agent_name = agent_name,
        });

        // Check if credentials exist
        if (!store.exists()) {
            return error.NotAuthenticated;
        }

        // Load credentials
        const stored_creds = try store.load();
        defer self.allocator.free(stored_creds.type);
        defer self.allocator.free(stored_creds.access_token);
        defer self.allocator.free(stored_creds.refresh_token);

        // Convert to OAuth credentials format for Anthropic client
        var creds = Auth.OAuth.Credentials{
            .type = try self.allocator.dupe(u8, stored_creds.type),
            .accessToken = try self.allocator.dupe(u8, stored_creds.access_token),
            .refreshToken = try self.allocator.dupe(u8, stored_creds.refresh_token),
            .expiresAt = stored_creds.expires_at,
        };
        errdefer creds.deinit(self.allocator);

        // Check and refresh token if needed
        if (creds.willExpireSoon(120)) {
            log.info("Token expiring soon, refreshing...", .{});

            // Get fresh tokens; take ownership of returned allocations.
            var new_creds = try Auth.OAuth.refreshTokens(self.allocator, creds.refreshToken);

            // Update stored credentials
            const updated_store_creds = Auth.store.StoredCredentials{
                .type = new_creds.type,
                .access_token = new_creds.accessToken,
                .refresh_token = new_creds.refreshToken,
                .expires_at = new_creds.expiresAt,
            };
            try store.save(updated_store_creds);

            // Free old credentials and replace them (new_creds memory now owned by creds)
            creds.deinit(self.allocator);
            creds = new_creds;
        }

        // Get credentials path for auto-refresh support
        const creds_path = try store.getCredentialPath();
        defer self.allocator.free(creds_path);

        // Initialize Anthropic client with OAuth
        self.client = try network.Anthropic.Client.Client.initWithOAuth(self.allocator, creds, creds_path);
        // On success, the client is assumed to manage token refresh; we intentionally
        // do not deinit `creds` here.
    }

    /// Run inference with streaming support and tool execution
    pub fn runInference(self: *Self, user_input: []const u8) !void {
        const stdout = std.debug;

        // Add user message
        try self.messages.append(self.allocator, .{
            .role = .user,
            .content = try self.allocator.dupe(u8, user_input),
        });

        // Trim context if too large (keep last 20 messages)
        try self.trimContext();

        // Build system prompt from registered tools
        const system_prompt = try self.buildSystemPrompt();
        defer if (system_prompt) |sp| self.allocator.free(sp);

        if (self.options.stream) {
            // Streaming mode with SSE
            stdout.print("\nClaude: ", .{});

            // Initialize streaming state
            self.shared_ctx.anthropic.contentCollector.clearRetainingCapacity();
            self.shared_ctx.anthropic.messageId = null;
            self.shared_ctx.anthropic.stopReason = null;
            self.shared_ctx.anthropic.model = null;

            // Stream the response
            var client = self.client orelse return error.NotAuthenticated;
            const streamParams = network.Anthropic.Client.StreamParameters{
                .model = self.options.model,
                .messages = self.messages.items,
                .maxTokens = self.options.max_tokens,
                .temperature = self.options.temperature,
                .system = system_prompt,
                .onToken = struct {
                    fn callback(ctx: *SharedContext, data: []const u8) void {
                        Engine.processStreamingEvent(ctx, data);
                    }
                }.callback,
            };

            try client.createMessageStream(&self.shared_ctx, streamParams);

            // Add assistant message to history
            const assistant_content = try self.allocator.dupe(u8, self.shared_ctx.anthropic.contentCollector.items);
            try self.messages.append(self.allocator, .{
                .role = .assistant,
                .content = assistant_content,
            });

            // Check for tool calls and execute them
            try self.handleToolCalls();

            stdout.print("\n\n", .{});
        } else {
            // Non-streaming mode
            var client = self.client orelse return error.NotAuthenticated;
            var result = try client.createMessage(.{
                .model = self.options.model,
                .messages = self.messages.items,
                .maxTokens = self.options.max_tokens,
                .temperature = self.options.temperature,
                .system = system_prompt,
            });
            defer result.deinit();

            stdout.print("\nClaude: {s}\n\n", .{result.content});

            // Add assistant message
            try self.messages.append(self.allocator, .{
                .role = .assistant,
                .content = try self.allocator.dupe(u8, result.content),
            });

            // Check for tool calls and execute them
            try self.handleToolCalls();
        }
    }

    /// Process streaming SSE events with proper tool JSON accumulation
    fn processStreamingEvent(ctx: *SharedContext, data: []const u8) void {
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
            .ignore_unknown_fields = true,
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

    /// Build system prompt from registered tools
    fn buildSystemPrompt(self: *Self) !?[]const u8 {
        // Read anthropic_spoof.txt content per spec requirements
        const spoofContent = blk: {
            const spoofFile = std.fs.cwd().openFile("prompt/anthropic_spoof.txt", .{}) catch {
                break :blk null;
            };
            defer spoofFile.close();
            const content = spoofFile.readToEndAlloc(self.allocator, 1024 * 1024) catch null;
            break :blk content;
        };
        defer if (spoofContent) |content| self.allocator.free(content);

        var prompt_builder = std.ArrayList(u8).initCapacity(self.allocator, 0) catch unreachable;
        defer prompt_builder.deinit(self.allocator);

        // Prepend spoof content if available
        if (spoofContent) |content| {
            try prompt_builder.appendSlice(self.allocator, content);
            try prompt_builder.appendSlice(self.allocator, "\n\n");
        }

        // Add tool descriptions if available
        const tools_list = try self.tool_registry.listTools(self.allocator);
        defer self.allocator.free(tools_list);

        if (tools_list.len > 0) {
            try prompt_builder.appendSlice(self.allocator, "You have access to the following tools:\n\n");

            for (tools_list) |tool| {
                try prompt_builder.appendSlice(self.allocator, "Tool: ");
                try prompt_builder.appendSlice(self.allocator, tool.name);
                try prompt_builder.appendSlice(self.allocator, "\nDescription: ");
                try prompt_builder.appendSlice(self.allocator, tool.description);
                try prompt_builder.appendSlice(self.allocator, "\n\n");
            }

            try prompt_builder.appendSlice(self.allocator, "When you need to use a tool, respond with a tool_use block containing the tool name and parameters.\n");
        }

        if (prompt_builder.items.len == 0) {
            return null;
        }

        return try prompt_builder.toOwnedSlice(self.allocator);
    }

    /// Handle tool calls from the assistant response
    fn handleToolCalls(self: *Self) !void {
        // Check if we have accumulated tool JSON from streaming
        if (self.shared_ctx.tools.jsonComplete) |tool_json| {
            defer self.allocator.free(self.shared_ctx.tools.jsonComplete.?);
            self.shared_ctx.tools.jsonComplete = null;

            // Parse the tool call - Anthropic sends tool parameters as JSON
            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, tool_json, .{}) catch |err| {
                log.warn("Failed to parse tool call JSON: {}", .{err});
                return;
            };
            defer parsed.deinit();

            // Extract tool name and arguments from the accumulated JSON
            if (parsed.value == .object) {
                if (self.shared_ctx.tools.toolName) |tool_name| {
                    defer self.allocator.free(self.shared_ctx.tools.toolName.?);
                    self.shared_ctx.tools.toolName = null;

                    try self.executeTool(tool_name, &parsed.value);
                } else {
                    log.warn("Tool name not available for execution", .{});
                }
            }
        }

        // Clean up tool context
        if (self.shared_ctx.tools.toolName) |name| {
            self.allocator.free(name);
            self.shared_ctx.tools.toolName = null;
        }
        if (self.shared_ctx.tools.toolId) |id| {
            self.allocator.free(id);
            self.shared_ctx.tools.toolId = null;
        }
    }

    /// Execute a tool by name with given arguments
    fn executeTool(self: *Self, tool_name: []const u8, arguments: *const std.json.Value) !void {
        // Get the tool function from registry
        const tool_func = self.tool_registry.get(tool_name) orelse {
            log.warn("Tool not found in registry: {s}", .{tool_name});
            return;
        };

        // Convert arguments to JSON string for the tool function
        const args_json = try std.json.stringifyAlloc(self.allocator, arguments.*, .{});
        defer self.allocator.free(args_json);

        log.info("Executing tool: {s}", .{tool_name});

        // Execute the tool
        const result = tool_func(&self.shared_ctx, self.allocator, args_json) catch |err| {
            log.err("Tool execution failed: {s} - {}", .{ tool_name, err });
            const error_msg = try std.fmt.allocPrint(self.allocator, "Tool '{s}' failed: {s}", .{ tool_name, @errorName(err) });
            defer self.allocator.free(error_msg);

            try self.messages.append(self.allocator, .{
                .role = .user,
                .content = error_msg,
            });
            return;
        };
        defer self.allocator.free(result);

        log.info("Tool '{s}' completed successfully", .{tool_name});

        // Add tool result to conversation as a user message
        const tool_result_content = try std.fmt.allocPrint(self.allocator, "Tool '{s}' result: {s}", .{ tool_name, result });
        defer self.allocator.free(tool_result_content);

        try self.messages.append(self.allocator, .{
            .role = .user,
            .content = tool_result_content,
        });
    }

    /// Execute multiple tools in parallel when supported
    fn executeToolsParallel(self: *Self, tool_calls: []const ToolCall) !void {
        if (tool_calls.len == 0) return;

        // For now, execute tools sequentially (parallel execution can be added later)
        // This maintains compatibility while allowing for future parallel implementation
        for (tool_calls) |tool_call| {
            try self.executeTool(tool_call.name, &tool_call.arguments);
        }
    }

    /// Tool call structure for parallel execution
    const ToolCall = struct {
        name: []const u8,
        arguments: std.json.Value,
    };

    /// Context hygiene - keep conversation manageable with summarization
    fn trimContext(self: *Self) !void {
        const max_messages = 20;
        const estimated_tokens_per_message = 100; // Rough estimate
        const max_estimated_tokens = 160_000;
        const summarization_threshold = 120_000; // Summarize when approaching limit

        // Check message count first
        if (self.messages.items.len > max_messages) {
            const to_remove = self.messages.items.len - max_messages;
            log.debug("Trimming context: removing {} old messages", .{to_remove});

            for (self.messages.items[0..to_remove]) |msg| {
                self.allocator.free(msg.content);
            }
            std.mem.copyForwards(
                network.Anthropic.Message,
                self.messages.items[0..],
                self.messages.items[to_remove..],
            );
            self.messages.shrinkRetainingCapacity(max_messages);
        }

        // Check estimated token count (rough heuristic)
        const estimated_tokens = self.messages.items.len * estimated_tokens_per_message;
        if (estimated_tokens > max_estimated_tokens) {
            log.debug("Context estimated at {} tokens, trimming older messages", .{estimated_tokens});

            // Keep system message + last 10 exchanges
            const keep_count = 10;
            if (self.messages.items.len > keep_count) {
                const to_remove = self.messages.items.len - keep_count;
                for (self.messages.items[0..to_remove]) |msg| {
                    self.allocator.free(msg.content);
                }
                std.mem.copyForwards(
                    network.Anthropic.Message,
                    self.messages.items[0..],
                    self.messages.items[to_remove..],
                );
                self.messages.shrinkRetainingCapacity(keep_count);
            }
        } else if (estimated_tokens > summarization_threshold) {
            // Try to summarize older messages to preserve context
            try self.summarizeOldMessages();
        }
    }

    /// Summarize older messages to preserve context while reducing token count
    fn summarizeOldMessages(self: *Self) !void {
        if (self.messages.items.len < 8) return; // Need at least some messages to summarize

        // Find the oracle tool for summarization
        const oracle_tool = self.tool_registry.get("oracle");
        if (oracle_tool == null) {
            log.debug("Oracle tool not available for summarization, skipping", .{});
            return;
        }

        // Collect older messages for summarization (keep last 5, summarize the rest)
        const keep_recent = 5;
        if (self.messages.items.len <= keep_recent) return;

        const messages_to_summarize = self.messages.items[0..(self.messages.items.len - keep_recent)];

        // Build summarization prompt
        var summary_prompt = std.ArrayList(u8).initCapacity(self.allocator, 0) catch unreachable;
        defer summary_prompt.deinit(self.allocator);

        try summary_prompt.appendSlice(self.allocator, "Please provide a concise summary of the following conversation history. Focus on key decisions, important information, and context that would be relevant for continuing this conversation:\n\n");

        for (messages_to_summarize, 0..) |msg, i| {
            const role_name = switch (msg.role) {
                .user => "User",
                .assistant => "Assistant",
                .system => "System",
                .tool => "Tool",
            };
            try summary_prompt.writer(self.allocator).print("{s}: {s}\n", .{ role_name, msg.content });
            if (i < messages_to_summarize.len - 1) {
                try summary_prompt.appendSlice(self.allocator, "\n");
            }
        }

        // Use oracle tool to generate summary
        const summary_json = try std.fmt.allocPrint(self.allocator,
            \\{{"prompt":"{s}"}}
        , .{summary_prompt.items});
        defer self.allocator.free(summary_json);

        log.debug("Generating conversation summary using oracle tool", .{});

        const summary_result = oracle_tool.?(&self.shared_ctx, self.allocator, summary_json) catch |err| {
            log.warn("Failed to generate conversation summary: {}", .{err});
            return;
        };
        defer self.allocator.free(summary_result);

        // Replace old messages with summary
        const summary_content = try std.fmt.allocPrint(self.allocator, "Previous conversation summary: {s}", .{summary_result});

        // Free old messages
        for (messages_to_summarize) |msg| {
            self.allocator.free(msg.content);
        }

        // Replace with summary message
        self.messages.items[0] = .{
            .role = .user,
            .content = summary_content,
        };

        // Shift remaining messages
        std.mem.copyForwards(
            network.Anthropic.Message,
            self.messages.items[1..],
            self.messages.items[(messages_to_summarize.len)..],
        );

        // Resize array
        self.messages.shrinkRetainingCapacity(self.messages.items.len - messages_to_summarize.len + 1);

        log.debug("Successfully summarized {} messages into 1 summary", .{messages_to_summarize.len});
    }
};

/// Main engine entry point
pub fn runWithOptions(
    allocator: std.mem.Allocator,
    options: CliOptions,
    spec: AgentSpec,
    _: []const u8, // working directory (unused for now)
) !void {
    const stdout = std.debug;
    var stdin_file = std.fs.File.stdin();
    var stdin_buf: [4096]u8 = undefined;
    var stdin = stdin_file.reader(stdin_buf[0..]);

    // Initialize engine
    var engine = try Engine.init(allocator, options);
    defer engine.deinit();

    // Authenticate
    engine.authenticate() catch |err| {
        if (err == error.NotAuthenticated) {
            stdout.print("Not authenticated. Run 'docz auth login' to authenticate.\n", .{});
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
        try engine.messages.append(allocator, .{
            .role = .user,
            .content = try allocator.dupe(u8, system_prompt),
        });
    }

    // Print banner
    stdout.print("\n┌────────────────────────────────────────┐\n", .{});
    stdout.print("│  Docz Agent - Claude AI Assistant     │\n", .{});
    stdout.print("│  Model: {s: <30} │\n", .{options.model});
    stdout.print("│  Auth: OAuth (Claude Pro/Max)         │\n", .{});
    stdout.print("│  Type 'exit' or Ctrl-C to quit        │\n", .{});
    stdout.print("└────────────────────────────────────────┘\n\n", .{});

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

            try engine.runInference(trimmed);
        } else {
            // EOF
            break;
        }
    }

    stdout.print("\nGoodbye!\n", .{});
}

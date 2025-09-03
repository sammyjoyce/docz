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
    /// System blocks for OAuth multi-part system prompts
    system_blocks: ?[]const network.Anthropic.Client.SystemBlock = null,

    pub fn init(allocator: std.mem.Allocator, options: CliOptions) !Self {
        return Self{
            .allocator = allocator,
            .client = null,
            .shared_ctx = SharedContext.init(allocator),
            .messages = std.ArrayList(network.Anthropic.Message){},
            .tool_registry = tools.Registry.init(allocator),
            .options = options,
            .system_base = null,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.messages.items) |*msg| {
            network.Anthropic.Models.freeMessage(self.allocator, msg);
        }
        self.messages.deinit(self.allocator);
        self.shared_ctx.deinit();
        if (self.client) |*c| c.deinit();
        self.tool_registry.deinit();
        if (self.system_base) |sb| self.allocator.free(sb);
    }

    /// Authenticate and initialize client
    pub fn authenticate(self: *Self) !void {
        // Prefer API key from environment for general Messages API access
        if (std.process.getEnvVarOwned(self.allocator, "ANTHROPIC_API_KEY")) |api_key| {
            defer self.allocator.free(api_key);
            if (api_key.len > 0) {
                self.client = try network.Anthropic.Client.Client.init(self.allocator, api_key);
                self.shared_ctx.anthropic.client = &self.client.?;
                return;
            }
        } else |_| {}

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
            const new_creds = try Auth.OAuth.refreshTokens(self.allocator, creds.refreshToken);

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
        self.shared_ctx.anthropic.client = &self.client.?;
        // Client duplicates the credentials internally; free our local copies to avoid leaks.
        creds.deinit(self.allocator);
    }

    /// Run inference with streaming support and tool execution
    pub fn runInference(self: *Self, user_input: []const u8) !void {
        var out = std.fs.File.stdout().deprecatedWriter();

        // Add user message (text content)
        try self.messages.append(self.allocator, .{ .role = .user, .content = .{ .text = try self.allocator.dupe(u8, user_input) } });

        // Trim context if too large (keep last 20 messages)
        try self.trimContext();

        // Build system prompt from registered tools
        const system_prompt = try self.buildSystemPrompt();
        defer if (system_prompt) |sp| self.allocator.free(sp);
        defer if (self.system_blocks) |blocks| {
            for (blocks) |block| {
                self.allocator.free(block.text);
            }
            self.allocator.free(blocks);
            self.system_blocks = null;
        };

        // Prepare tools JSON (if any tools registered)
        const tools_json = try self.buildToolsJson();
        defer if (tools_json) |tj| self.allocator.free(tj);

        if (self.options.stream) {
            // Streaming mode with SSE. Loop to allow tool → continue cycles.
            var client = self.client orelse return error.NotAuthenticated;
            while (true) {
                // In TUI mode with streaming hooks, suppress direct stdout banner
                if (self.shared_ctx.ui_stream.onToken == null) {
                    out.writeAll("\nClaude: ") catch {};
                }

                // Initialize streaming state
                self.shared_ctx.anthropic.contentCollector.clearRetainingCapacity();
                self.shared_ctx.anthropic.messageId = null;
                self.shared_ctx.anthropic.stopReason = null;
                self.shared_ctx.anthropic.model = null;
                // Reset per-message tool queue/buffers
                self.shared_ctx.tools.resetForNewAssistantMessage();

                // Stream the response
                const streamParams = network.Anthropic.Client.StreamParameters{
                    .model = self.options.model,
                    .messages = self.messages.items,
                    .maxTokens = self.options.max_tokens,
                    .temperature = self.options.temperature,
                    .system = system_prompt,
                    .systemBlocks = self.system_blocks,
                    .toolsJson = tools_json,
                    .toolChoice = null, // default to auto when tools present
                    .onToken = struct {
                        fn callback(ctx: *SharedContext, data: []const u8) void {
                            Engine.processStreamingEvent(ctx, data);
                        }
                    }.callback,
                };

                try client.createMessageStream(&self.shared_ctx, streamParams);

                // Add assistant message as blocks: text + tool_use blocks captured during SSE
                var blocks = std.ArrayListUnmanaged(network.Anthropic.Models.ContentBlock){};
                defer blocks.deinit(self.allocator);
                if (self.shared_ctx.anthropic.contentCollector.items.len > 0) {
                    try blocks.append(self.allocator, .{ .text = .{ .text = try self.allocator.dupe(u8, self.shared_ctx.anthropic.contentCollector.items) } });
                }
                // Include each finalized pending tool_use
                for (self.shared_ctx.tools.queue.items) |p| {
                    if (p.jsonComplete) |input_json| {
                        const id_bytes = if (p.id) |id| try self.allocator.dupe(u8, id) else try self.allocator.dupe(u8, "tool-use");
                        const name_bytes = if (p.name) |nm| try self.allocator.dupe(u8, nm) else try self.allocator.dupe(u8, "unknown");
                        try blocks.append(self.allocator, .{ .tool_use = .{
                            .id = id_bytes,
                            .name = name_bytes,
                            .input_json = try self.allocator.dupe(u8, input_json),
                        } });
                    }
                }
                const owned_blocks = try blocks.toOwnedSlice(self.allocator);
                try self.messages.append(self.allocator, .{ .role = .assistant, .content = .{ .blocks = owned_blocks } });

                // Check for tool calls and execute them
                const executed = try self.handleToolCalls();

                out.writeAll("\n\n") catch {};
                if (!executed) break; // no tool calls → done; else loop again
            }
        } else {
            // Non-streaming mode with tool → continue cycle
            var client = self.client orelse return error.NotAuthenticated;
            while (true) {
                var result = try client.createMessage(.{
                    .model = self.options.model,
                    .messages = self.messages.items,
                    .maxTokens = self.options.max_tokens,
                    .temperature = self.options.temperature,
                    .system = system_prompt,
                    .toolsJson = tools_json,
                    .toolChoice = null,
                });
                defer result.deinit();

                std.fmt.format(out, "\nClaude: {s}\n\n", .{result.content}) catch {};

                // Add assistant message (text content)
                try self.messages.append(self.allocator, .{ .role = .assistant, .content = .{ .text = try self.allocator.dupe(u8, result.content) } });

                // Check for tool calls and execute them
                if (!try self.handleToolCalls()) break;
            }
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
                stop_reason: ?[]const u8 = null,
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
                if (ctx.ui_stream.onEvent) |cb| {
                    if (ctx.ui_stream.ctx) |c| cb(c, "message_start", msg.model orelse "");
                }
            }
        } else if (std.mem.eql(u8, event_type, "content_block_start")) {
            // Initialize tool JSON accumulation if this is a tool_use block
            if (parsed.value.content_block) |block| {
                if (block.type) |block_type| {
                    if (std.mem.eql(u8, block_type, "tool_use")) {
                        // Start a new pending tool_use
                        ctx.tools.pushToolStart(block.name, block.id);
                    }
                }
            }
        } else if (std.mem.eql(u8, event_type, "content_block_delta")) {
            if (parsed.value.delta) |delta| {
                if (delta.type) |delta_type| {
                    if (std.mem.eql(u8, delta_type, "text_delta")) {
                        if (delta.text) |text| {
                            // Prefer UI callback when available
                            if (ctx.ui_stream.onToken) |cb| {
                                if (ctx.ui_stream.ctx) |c| cb(c, text);
                            } else {
                                _ = std.fs.File.stdout().deprecatedWriter().writeAll(text) catch {};
                            }
                            // Accumulate for history
                            ctx.anthropic.contentCollector.appendSlice(ctx.anthropic.allocator, text) catch {};
                        }
                    } else if (std.mem.eql(u8, delta_type, "input_json_delta")) {
                        if (delta.partial_json) |json_part| {
                            // Accumulate tool JSON into current tool_use
                            ctx.tools.appendToCurrentJson(json_part);
                        }
                    }
                }
            }
        } else if (std.mem.eql(u8, event_type, "content_block_stop")) {
            // Finalize current tool_use JSON accumulation
            ctx.tools.finalizeCurrent();
        } else if (std.mem.eql(u8, event_type, "message_delta")) {
            if (parsed.value.delta) |delta| {
                if (delta.stop_reason) |stop_reason| {
                    ctx.anthropic.stopReason = ctx.anthropic.allocator.dupe(u8, stop_reason) catch null;
                }
            }
        } else if (std.mem.eql(u8, event_type, "message_stop")) {
            // Message complete
            if (ctx.ui_stream.onEvent) |cb| {
                if (ctx.ui_stream.ctx) |c| cb(c, "message_stop", "");
            }
        }
    }

    /// Build system prompt from registered tools
    fn buildSystemPrompt(self: *Self) !?[]const u8 {
        // Check if we're using OAuth authentication
        const is_oauth = if (self.client) |*client| blk: {
            break :blk switch (client.auth) {
                .oauth => true,
                .api_key => false,
            };
        } else false;

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

        // For OAuth, build system blocks array
        if (is_oauth and spoofContent != null) {
            var blocks = std.ArrayListUnmanaged(network.Anthropic.Client.SystemBlock){};
            defer blocks.deinit(self.allocator);

            // First block: Claude Code identifier with cache control
            try blocks.append(self.allocator, .{
                .text = try self.allocator.dupe(u8, spoofContent.?),
                .cache_control = .{ .type = "ephemeral" },
            });

            // Second block: Agent system prompt and tools
            var agent_prompt = std.ArrayListUnmanaged(u8){};
            defer agent_prompt.deinit(self.allocator);

            // Add agent-provided base system prompt if set
            if (self.system_base) |base| {
                try agent_prompt.appendSlice(self.allocator, base);
                try agent_prompt.appendSlice(self.allocator, "\n\n");
            }

            // Add tool descriptions if available
            const tools_list = try self.tool_registry.listTools(self.allocator);
            defer self.allocator.free(tools_list);

            if (tools_list.len > 0) {
                try agent_prompt.appendSlice(self.allocator, "You have access to the following tools:\n\n");

                for (tools_list) |tool| {
                    try agent_prompt.appendSlice(self.allocator, "Tool: ");
                    try agent_prompt.appendSlice(self.allocator, tool.name);
                    try agent_prompt.appendSlice(self.allocator, "\nDescription: ");
                    try agent_prompt.appendSlice(self.allocator, tool.description);
                    try agent_prompt.appendSlice(self.allocator, "\n\n");
                }

                try agent_prompt.appendSlice(self.allocator, "When you need to use a tool, respond with a tool_use block containing the tool name and parameters.\n");
            }

            if (agent_prompt.items.len > 0) {
                try blocks.append(self.allocator, .{
                    .text = try agent_prompt.toOwnedSlice(self.allocator),
                    .cache_control = null,
                });
            }

            // Store blocks for use in streaming
            self.system_blocks = try blocks.toOwnedSlice(self.allocator);

            // Return null for the single system prompt since we're using blocks
            return null;
        }

        var prompt_builder = std.ArrayListUnmanaged(u8){};
        defer prompt_builder.deinit(self.allocator);

        // Prepend spoof content FIRST (required for OAuth)
        if (spoofContent) |content| {
            try prompt_builder.appendSlice(self.allocator, content);
            try prompt_builder.appendSlice(self.allocator, "\n\n");
        }

        // Then add agent-provided base system prompt if set
        if (self.system_base) |base| {
            try prompt_builder.appendSlice(self.allocator, base);
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

    /// Build Anthropic tools array JSON from the registered tools.
    /// Produces a JSON array string with objects: {"name","description","input_schema"}.
    fn buildToolsJson(self: *Self) !?[]const u8 {
        const list = try self.tool_registry.listTools(self.allocator);
        defer self.allocator.free(list);
        if (list.len == 0) return null;

        const Writer = struct {
            fn writeJSONString(w: anytype, s: []const u8) !void {
                try w.writeByte('"');
                for (s) |c| switch (c) {
                    '"' => try w.writeAll("\\\""),
                    '\\' => try w.writeAll("\\\\"),
                    '\n' => try w.writeAll("\\n"),
                    '\r' => try w.writeAll("\\r"),
                    '\t' => try w.writeAll("\\t"),
                    else => {
                        if (c < 0x20) {
                            try std.fmt.format(w, "\\u{x:0>4}", .{c});
                        } else try w.writeByte(c);
                    },
                };
                try w.writeByte('"');
            }
        };

        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(self.allocator);
        var w = buf.writer(self.allocator);
        try w.writeByte('[');
        var first = true;
        for (list) |t| {
            if (!first) try w.writeByte(',');
            first = false;
            try w.writeByte('{');
            // name
            try w.writeAll("\"name\":");
            try Writer.writeJSONString(w, t.name);
            try w.writeByte(',');
            // description (fallback to name if empty)
            const desc = if (t.description.len == 0) t.name else t.description;
            try w.writeAll("\"description\":");
            try Writer.writeJSONString(w, desc);
            try w.writeByte(',');
            // input_schema: prefer registry-provided raw JSON (if any)
            try w.writeAll("\"input_schema\":");
            if (self.tool_registry.getInputSchema(t.name)) |schema_json| {
                try w.writeAll(schema_json);
            } else {
                try w.writeAll("{\"type\":\"object\"}");
            }
            try w.writeByte('}');
        }
        try w.writeByte(']');
        const owned = try buf.toOwnedSlice(self.allocator);
        const owned_const: []const u8 = owned;
        return owned_const;
    }

    /// Returns true if at least one tool call was executed.
    fn handleToolCalls(self: *Self) !bool {
        var executed = false;
        var tctx = &self.shared_ctx.tools;

        // Preferred path: drain queued multi-tool calls
        if (tctx.queue.items.len > 0) {
            var i: usize = 0;
            while (i < tctx.queue.items.len) : (i += 1) {
                const p = &tctx.queue.items[i];
                if (p.jsonComplete) |tool_json| {
                    const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, tool_json, .{}) catch |err| {
                        log.warn("Failed to parse tool call JSON: {}", .{err});
                        continue;
                    };
                    defer parsed.deinit();
                    if (p.name) |tool_name| {
                        try self.executeTool(tool_name, p.id, &parsed.value);
                        executed = true;
                    } else {
                        log.warn("Tool call had no name; skipping", .{});
                    }
                }
            }
            // Free and clear queue
            for (tctx.queue.items) |*p| {
                if (p.name) |n| self.allocator.free(n);
                if (p.id) |qid| self.allocator.free(qid);
                if (p.jsonComplete) |j| self.allocator.free(j);
                p.tokenBuffer.deinit();
            }
            tctx.queue.clearRetainingCapacity();
            tctx.current = null;
        }

        // Legacy fallback if nothing executed
        if (!executed) {
            if (tctx.jsonComplete) |tool_json| {
                defer self.allocator.free(tctx.jsonComplete.?);
                tctx.jsonComplete = null;
                const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, tool_json, .{}) catch |err| {
                    log.warn("Failed to parse tool call JSON: {}", .{err});
                    return false;
                };
                defer parsed.deinit();
                if (tctx.toolName) |tool_name| {
                    const id = tctx.toolId;
                    self.allocator.free(tctx.toolName.?);
                    tctx.toolName = null;
                    if (tctx.toolId) |tid| {
                        self.allocator.free(tid);
                        tctx.toolId = null;
                    }
                    try self.executeTool(tool_name, id, &parsed.value);
                    executed = true;
                } else {
                    log.warn("Tool name not available for execution (legacy path)", .{});
                }
            }
        }

        return executed;
    }

    /// Execute a tool by name with given arguments (and optional tool_use_id)
    fn executeTool(self: *Self, tool_name: []const u8, tool_id: ?[]const u8, arguments: *const std.json.Value) !void {
        // Get the tool function from registry
        const tool_func = self.tool_registry.get(tool_name) orelse {
            log.warn("Tool not found in registry: {s}", .{tool_name});
            return;
        };

        // Convert arguments to JSON string for the tool function
        var aj = std.ArrayList(u8){};
        defer aj.deinit(self.allocator);
        var ajw: std.Io.Writer.Allocating = .fromArrayList(self.allocator, &aj);
        std.json.Stringify.value(arguments.*, .{}, &ajw.writer) catch {
            return error.Unexpected;
        };
        aj = ajw.toArrayList();
        const args_json = try aj.toOwnedSlice(self.allocator);
        defer self.allocator.free(args_json);

        log.info("Executing tool: {s}", .{tool_name});

        // Execute the tool
        const result = tool_func(&self.shared_ctx, self.allocator, args_json) catch |err| {
            log.err("Tool execution failed: {s} - {}", .{ tool_name, err });
            const msg = try std.fmt.allocPrint(self.allocator, "Tool '{s}' failed: {s}", .{ tool_name, @errorName(err) });
            defer self.allocator.free(msg);
            const tool_err_msg = try network.Anthropic.Models.makeToolResultMessage(self.allocator, tool_id, msg, true);
            try self.messages.append(self.allocator, tool_err_msg);
            return;
        };
        defer self.allocator.free(result);

        log.info("Tool '{s}' completed successfully", .{tool_name});

        // Add structured tool_result with optional tool_use_id
        const tool_ok_msg = try network.Anthropic.Models.makeToolResultMessage(self.allocator, tool_id, result, false);
        try self.messages.append(self.allocator, tool_ok_msg);
    }

    /// Execute multiple tools in parallel when supported
    fn executeToolsParallel(self: *Self, tool_calls: []const ToolCall) !void {
        if (tool_calls.len == 0) return;

        // For now, execute tools sequentially (parallel execution can be added later)
        // This maintains compatibility while allowing for future parallel implementation
        for (tool_calls) |tool_call| {
            try self.executeTool(tool_call.name, null, &tool_call.arguments);
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

            for (self.messages.items[0..to_remove]) |*msg| {
                network.Anthropic.Models.freeMessage(self.allocator, msg);
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
                for (self.messages.items[0..to_remove]) |*msg| {
                    network.Anthropic.Models.freeMessage(self.allocator, msg);
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
        var summary_prompt = std.ArrayList(u8){};
        defer summary_prompt.deinit(self.allocator);
        var aw: std.Io.Writer.Allocating = .fromArrayList(self.allocator, &summary_prompt);

        try aw.writer.writeAll("Please provide a concise summary of the following conversation history. Focus on key decisions, important information, and context that would be relevant for continuing this conversation:\n\n");

        for (messages_to_summarize, 0..) |msg, i| {
            const role_name = switch (msg.role) {
                .user => "User",
                .assistant => "Assistant",
                .system => "System",
                .tool => "Tool",
            };
            // Write textual view of message content
            try aw.writer.writeAll(role_name);
            try aw.writer.writeAll(": ");
            switch (msg.content) {
                .text => |t| try aw.writer.writeAll(t),
                .blocks => |bs| {
                    var first = true;
                    for (bs) |b| switch (b) {
                        .text => |tb| {
                            if (!first) try aw.writer.writeAll(" ");
                            first = false;
                            try aw.writer.writeAll(tb.text);
                        },
                        .tool_use => |tu| {
                            if (!first) try aw.writer.writeAll(" ");
                            first = false;
                            try aw.writer.writeAll("[tool_use:");
                            try aw.writer.writeAll(tu.name);
                            try aw.writer.writeAll("]");
                        },
                        .tool_result => |tr| {
                            if (!first) try aw.writer.writeAll(" ");
                            first = false;
                            try aw.writer.writeAll(if (tr.is_error) "[tool_error]" else "[tool_result]");
                        },
                    };
                },
            }
            try aw.writer.writeAll("\n");
            if (i < messages_to_summarize.len - 1) {
                try aw.writer.writeAll("\n");
            }
        }

        // Use oracle tool to generate summary
        // JSON-safe stringify of the prompt: {"prompt":"..."}
        var json_buf = std.ArrayList(u8){};
        defer json_buf.deinit(self.allocator);
        var jw: std.Io.Writer.Allocating = .fromArrayList(self.allocator, &json_buf);
        try jw.writer.writeAll("{\"prompt\":\"");
        // minimal JSON string escape
        for (summary_prompt.items) |c| switch (c) {
            '"' => try jw.writer.writeAll("\\\""),
            '\\' => try jw.writer.writeAll("\\\\"),
            '\n' => try jw.writer.writeAll("\\n"),
            '\r' => try jw.writer.writeAll("\\r"),
            '\t' => try jw.writer.writeAll("\\t"),
            else => if (c < 0x20) {
                var buf4: [6]u8 = .{ '\\', 'u', '0', '0', 0, 0 };
                const HEX = "0123456789abcdef";
                buf4[4] = HEX[(c >> 4) & 0xF];
                buf4[5] = HEX[c & 0xF];
                try jw.writer.writeAll(&buf4);
            } else try jw.writer.writeByte(c),
        };
        try jw.writer.writeAll("\"}");
        json_buf = jw.toArrayList();
        const summary_json = try json_buf.toOwnedSlice(self.allocator);
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
        for (messages_to_summarize) |*msg| {
            network.Anthropic.Models.freeMessage(self.allocator, msg);
        }

        // Replace with summary message
        self.messages.items[0] = .{ .role = .system, .content = .{ .text = summary_content } };

        // Shift remaining messages
        std.mem.copyForwards(
            network.Anthropic.Message,
            self.messages.items[1 .. self.messages.items.len - (messages_to_summarize.len - 1)],
            self.messages.items[(messages_to_summarize.len)..],
        );

        // Resize array
        const final_len = self.messages.items.len - messages_to_summarize.len + 1;
        self.messages.items.len = final_len;
        self.messages.shrinkRetainingCapacity(final_len);

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
    var out = std.fs.File.stdout().deprecatedWriter();
    var stdin_depr = std.fs.File.stdin().deprecatedReader();

    // Initialize engine
    var engine = try Engine.init(allocator, options);
    defer engine.deinit();

    // Authenticate
    engine.authenticate() catch |err| {
        if (err == error.NotAuthenticated) {
            out.writeAll("Not authenticated. Run 'docz auth login' to authenticate.\n") catch {};
            return;
        }
        return err;
    };

    // Build agent-provided base system prompt once and store it
    const agent_system = try spec.buildSystemPrompt(allocator, options);
    defer allocator.free(agent_system);
    if (agent_system.len > 0) {
        engine.system_base = try allocator.dupe(u8, agent_system);
    }

    // Register tools
    try spec.registerTools(&engine.tool_registry);

    // Print banner
    out.writeAll("\n┌────────────────────────────────────────┐\n") catch {};
    out.writeAll("│  Docz Agent - Claude AI Assistant     │\n") catch {};
    std.fmt.format(out, "│  Model: {s: <30} │\n", .{options.model}) catch {};
    out.writeAll("│  Auth: OAuth (Claude Pro/Max)         │\n") catch {};
    out.writeAll("│  Type 'exit' or Ctrl-C to quit        │\n") catch {};
    out.writeAll("└────────────────────────────────────────┘\n\n") catch {};

    // Check for input flag
    if (options.input) |input| {
        // Single-shot mode
        try engine.runInference(input);
        if (options.output) |output_path| {
            const file = try std.fs.cwd().createFile(output_path, .{});
            defer file.close();
            if (engine.messages.items.len > 0) {
                const last_msg = engine.messages.items[engine.messages.items.len - 1];
                switch (last_msg.content) {
                    .text => |t| try file.writeAll(t),
                    .blocks => |bs| {
                        // Write only concatenated text blocks
                        var wrote_any = false;
                        for (bs) |b| if (b == .text) {
                            const txt = b.text.text;
                            if (wrote_any) try file.writeAll(" ");
                            wrote_any = true;
                            try file.writeAll(txt);
                        };
                    },
                }
            }
        }
        return;
    }

    // REPL loop
    while (true) {
        out.writeAll("You: ") catch {};

        var buf: [4096]u8 = undefined;
        if (try stdin_depr.readUntilDelimiterOrEof(&buf, '\n')) |user_input| {
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

    out.writeAll("\nGoodbye!\n") catch {};
}
/// Provide a default AuthPort backed by the network layer.
pub fn defaultAuthPort() foundation.ports.auth.AuthPort {
    return foundation.adapters.auth_network.make();
}

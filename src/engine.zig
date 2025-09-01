//! Core engine for terminal AI agents.
//! Provides run loop and client integration. Auth is headless under
//! `foundation.network/auth/*`; interactive auth flows live in CLI/TUI
//! (`foundation.tui.auth/*`, `foundation.cli.auth/*`). Agent prompts and
//! tools are supplied via AgentSpec.

const std = @import("std");
// Import from foundation barrel to avoid module conflicts
const foundation = @import("foundation");
// Use the provider-specific Anthropic namespace from the network barrel
const anthropic = foundation.network.Anthropic;
const AnthError = anthropic.Models.Error;
const tools_mod = foundation.tools;
// Headless auth core (no UI dependencies)
const auth_core = foundation.network.Auth.Core;
const auth = foundation.network.Auth;
const SharedContext = anthropic.Client.SharedContext;

pub const Message = anthropic.Message;

/// Native CLI options structure matching cli.zon specification.
/// This is shared across all agents.
pub const CliOptions = struct {
    options: struct {
        model: []const u8,
        output: ?[]const u8,
        input: ?[]const u8,
        system: ?[]const u8,
        config: ?[]const u8,
        tokensMax: u32,
        temperature: f32,
    },
    flags: struct {
        verbose: bool,
        help: bool,
        version: bool,
        stream: bool,
        pretty: bool,
        debug: bool,
        interactive: bool,
    },
    positionals: ?[]const u8,
};

/// AgentSpec allows each agent to provide its own system prompt and tools.
pub const AgentSpec = struct {
    /// Builds the agent's default system prompt. If CLI provides a system prompt,
    /// the engine will use that instead and skip this call.
    buildSystemPrompt: *const fn (allocator: std.mem.Allocator, options: CliOptions) anyerror![]const u8,

    /// Register agent-specific tools on top of shared built-ins.
    registerTools: *const fn (registry: *tools_mod.Registry) anyerror!void,
};

/// Map auth errors to anthropic errors
fn mapAuthError(err: auth_core.AuthError) AnthError {
    return switch (err) {
        auth_core.AuthError.MissingAPIKey => AnthError.MissingAPIKey,
        auth_core.AuthError.InvalidAPIKey => AnthError.AuthError,
        auth_core.AuthError.InvalidCredentials => AnthError.AuthError,
        auth_core.AuthError.TokenExpired => AnthError.TokenExpired,
        auth_core.AuthError.AuthenticationFailed => AnthError.AuthError,
        auth_core.AuthError.NetworkError => AnthError.NetworkError,
        auth_core.AuthError.FileNotFound => AnthError.AuthError,
        auth_core.AuthError.InvalidFormat => AnthError.AuthError,
        auth_core.AuthError.OutOfMemory => AnthError.OutOfMemory,
    };
}

/// Initialize Anthropic client using the auth system
fn initAnthropicClient(allocator: std.mem.Allocator) !anthropic.Client.Client {
    // Try to create auth client using available methods
    var authClient = auth_core.createClient(allocator) catch |err| {
        std.log.err("Failed to initialize authentication: {any}", .{err});
        return mapAuthError(err);
    };
    defer authClient.deinit();

    // Create Anthropic client based on auth method
    switch (authClient.credentials) {
        .api_key => |apiKey| {
            return try anthropic.Client.Client.init(allocator, apiKey);
        },
        .oauth => |creds| {
            const credentialsPath = "claude_oauth_creds.json";
            // Convert oauth Credentials to anthropic Credentials
            const anthropicCreds = anthropic.Models.Credentials{
                .type = creds.type,
                .accessToken = creds.accessToken,
                .refreshToken = creds.refreshToken,
                .expiresAt = creds.expiresAt,
            };
            return try anthropic.Client.Client.initWithOAuth(allocator, anthropicCreds, credentialsPath);
        },
        .none => {
            std.log.err("No authentication method available - network access disabled for this agent.", .{});
            return AnthError.MissingAPIKey;
        },
    }
}

/// Start OAuth flow using the auth system
pub fn setupOauth(allocator: std.mem.Allocator) !void {
    const oauth = foundation.network.Auth.OAuth;
    // Prefer automated local callback flow (no paste code)
    try oauth.completeOAuthFlow(allocator);

    std.log.info("✅ OAuth setup completed successfully!", .{});
    std.log.info("🔐 You can now use Claude Pro/Max features with your subscription.", .{});
}

/// Display current authentication status using the auth system
pub fn showAuthStatus(allocator: std.mem.Allocator) !void {
    // Minimal status without TUI dependencies
    var client = auth_core.createClient(allocator) catch |err| {
        std.log.err("Auth status: not configured ({any})", .{err});
        return err;
    };
    defer client.deinit();
    const method = client.credentials.getMethod();
    std.log.info("Auth status: {s}", .{switch (method) {
        .oauth => "OAuth",
        .api_key => "API key",
        .none => "None",
    }});
}

/// Refresh authentication tokens using the auth system
pub fn refreshAuth(allocator: std.mem.Allocator) !void {
    var client = try auth_core.createClient(allocator);
    defer client.deinit();

    try client.refresh();
    std.log.info("✅ Authentication tokens refreshed successfully!", .{});
}

/// Global stdout writer with buffer for streaming output
var stdoutBuffer: [4096]u8 = undefined;
var stdoutWriterInitialized = false;
var stdoutWriter: std.fs.File.Writer = undefined;

/// Global output file writer for saving responses to files
var globalOutputFile: ?std.fs.File = null;
var outputBuffer: [4096]u8 = undefined;
var outputWriterInitialized = false;
var outputWriter: ?std.fs.File.Writer = null;

fn initStdoutWriter() void {
    if (!stdoutWriterInitialized) {
        stdoutWriter = std.fs.File.stdout().writer(&stdoutBuffer);
        stdoutWriterInitialized = true;
    }
}

fn initOutputFile(dir: std.fs.Dir, filePath: []const u8) !void {
    if (!outputWriterInitialized) {
        globalOutputFile = try dir.createFile(filePath, .{});
        outputWriter = globalOutputFile.?.writer(&outputBuffer);
        outputWriterInitialized = true;
    }
}

fn flushAllOutputs() !void {
    if (stdoutWriterInitialized) {
        const stdout = &stdoutWriter.interface;
        stdout.flush() catch |err| {
            std.log.warn("Failed to flush stdout after streaming: {any}", .{err});
        };
    }

    if (outputWriterInitialized) {
        if (outputWriter) |*writer| {
            const fileWriter = &writer.interface;
            fileWriter.flush() catch |err| {
                std.log.warn("Failed to flush output file: {any}", .{err});
            };
        }
        if (globalOutputFile) |file| {
            file.close();
            globalOutputFile = null;
            outputWriter = null;
            outputWriterInitialized = false;
        }
    }
}

fn onToken(ctx: *anthropic.Client.SharedContext, chunk: []const u8) void {
    // Anthropic SSE sends JSON events per specs/anthropic-messages.md.
    // We only print assistant text deltas; for tool JSON deltas we accumulate
    // and defer emission until content_block_stop.
    const A = ctx.anthropic.allocator;
    const Parsed = std.json.Value;
    var parsed = std.json.parseFromSlice(Parsed, A, chunk, .{ .ignore_unknown_fields = true }) catch {
        // Fallback: not JSON; stream raw chunk
        initStdoutWriter();
        const stdout = &stdoutWriter.interface;
        stdout.writeAll(chunk) catch {};
        if (outputWriterInitialized) {
            if (outputWriter) |*writer| _ = writer.interface.writeAll(chunk) catch {};
        }
        return;
    };
    defer parsed.deinit();

    if (parsed.value != .object) return;
    const obj = parsed.value.object;
    const tval = obj.get("type") orelse return;
    if (tval != .string) return;
    const etype = tval.string;

    // Helper to write visible text
    const emitText = struct {
        fn out(s: []const u8) void {
            initStdoutWriter();
            const stdout = &stdoutWriter.interface;
            stdout.writeAll(s) catch {};
            if (outputWriterInitialized) {
                if (outputWriter) |*writer| _ = writer.interface.writeAll(s) catch {};
            }
        }
    }.out;

    // message_start can carry model/id — recorded by client.complete path.
    // Detect start of tool_use content blocks to capture tool name/id.
    if (std.mem.eql(u8, etype, "content_block_start")) {
        if (obj.get("content_block")) |cv| {
            if (cv == .object) {
                const cobj = cv.object;
                if (cobj.get("type")) |tv| {
                    if (tv == .string and std.mem.eql(u8, tv.string, "tool_use")) {
                        if (cobj.get("name")) |nv| {
                            if (nv == .string) {
                                if (ctx.tools.toolName) |old| A.free(old);
                                ctx.tools.toolName = A.dupe(u8, nv.string) catch null;
                            }
                        }
                        if (cobj.get("id")) |iv| {
                            if (iv == .string) {
                                if (ctx.tools.toolId) |old| A.free(old);
                                ctx.tools.toolId = A.dupe(u8, iv.string) catch null;
                            }
                        }
                        // reset any previous buffer
                        ctx.tools.tokenBuffer.clearRetainingCapacity();
                    }
                }
            }
        }
        return;
    }
    if (std.mem.eql(u8, etype, "content_block_delta")) {
        const maybe_delta = obj.get("delta") orelse return;
        if (maybe_delta != .object) return;
        const d_obj = maybe_delta.object;

        const maybe_dt = d_obj.get("type") orelse return;
        if (maybe_dt != .string) return;
        const dtt = maybe_dt.string;

        if (std.mem.eql(u8, dtt, "text_delta")) {
            if (d_obj.get("text")) |tv| {
                if (tv == .string) {
                    // Print assistant text
                    emitText(tv.string);
                    // Also keep a copy in contentCollector for completeness
                    ctx.anthropic.contentCollector.appendSlice(A, tv.string) catch {};
                }
            }
        } else if (std.mem.eql(u8, dtt, "input_json_delta") or std.mem.eql(u8, dtt, "tool_use_delta") or std.mem.eql(u8, dtt, "output_tool_use_delta")) {
            // Parameters streamed as partial JSON; do not print until stop.
            if (d_obj.get("partial_json")) |pj| {
                if (pj == .string) {
                    ctx.tools.tokenBuffer.appendSlice(pj.string) catch {};
                }
            }
        }
        return;
    }

    if (std.mem.eql(u8, etype, "content_block_stop")) {
        // If we accumulated tool JSON for an active tool_use block, mark pending
        if (ctx.tools.tokenBuffer.items.len > 0 and (ctx.tools.toolName != null or ctx.tools.toolId != null)) {
            if (ctx.tools.jsonComplete) |old| A.free(old);
            ctx.tools.jsonComplete = A.dupe(u8, ctx.tools.tokenBuffer.items) catch null;
            ctx.tools.hasPending = ctx.tools.jsonComplete != null;
            ctx.tools.tokenBuffer.clearRetainingCapacity();
        }
        return;
    }

    if (std.mem.eql(u8, etype, "message_delta")) {
        // Optional metadata: stop_reason, usage
        if (obj.get("delta")) |dv| {
            if (dv == .object) {
                const d_obj = dv.object;
                if (d_obj.get("stop_reason")) |sv| {
                    if (sv == .string) {
                        // Can be "tool_use", "end_turn", etc. Keep it in context.
                        if (ctx.anthropic.stopReason) |old| A.free(old);
                        ctx.anthropic.stopReason = A.dupe(u8, sv.string) catch null;
                    }
                }
            }
        }
        if (obj.get("usage")) |uv| {
            if (uv == .object) {
                const uo = uv.object;
                if (uo.get("output_tokens")) |ot| {
                    if (ot == .integer) ctx.anthropic.usageInfo.outputTokens = @intCast(ot.integer);
                }
                if (uo.get("input_tokens")) |it| {
                    if (it == .integer) ctx.anthropic.usageInfo.inputTokens = @intCast(it.integer);
                }
            }
        }
        return;
    }

    if (std.mem.eql(u8, etype, "message_stop")) {
        // Nothing to do; finalization handled by caller.
        return;
    }

    // Unknown event: ignore silently
}

fn writeCompleteResponse(content: []const u8) void {
    initStdoutWriter();
    const stdout = &stdoutWriter.interface;
    stdout.writeAll(content) catch |err| {
        std.log.err("Failed to write complete response to stdout: {any}", .{err});
    };

    if (outputWriterInitialized) {
        if (outputWriter) |*writer| {
            const fileWriter = &writer.interface;
            fileWriter.writeAll(content) catch |err| {
                std.log.err("Failed to write complete response to file: {any}", .{err});
            };
        }
    }
}

/// Main engine entry point used by all agents.
pub fn runWithOptions(
    allocator: std.mem.Allocator,
    options: CliOptions,
    spec: AgentSpec,
    dir: std.fs.Dir,
) !void {
    // Initialize client; if missing credentials, launch TUI/CLI auth flow
    var client: anthropic.Client.Client = blk_client: {
        const c0 = initAnthropicClient(allocator) catch |err| blk_retry: {
            if (err != AnthError.MissingAPIKey) return err;
            std.log.info("🔐 No credentials found. Starting CLI OAuth login...", .{});
            const cli_mod = foundation.cli;
            cli_mod.Auth.handleLoginCommand(allocator) catch |e2| {
                std.log.err("Auth setup failed: {any}", .{e2});
                return err;
            };
            break :blk_retry try initAnthropicClient(allocator);
        };
        break :blk_client c0;
    };
    defer client.deinit();
    // Enable wire logs via CLI verbose; build default handled in client
    client.setHttpVerbose(options.flags.verbose);

    if (client.isOAuthSession()) {
        std.log.info("🔐 Using Claude Pro/Max OAuth authentication", .{});
        std.log.info("💰 Usage costs are covered by your subscription", .{});
    } else {
        std.log.info("🔑 Using API key authentication", .{});
        std.log.info("💳 Usage will be billed according to your API plan", .{});
    }

    var registry = tools_mod.Registry.init(allocator);
    defer registry.deinit();
    try tools_mod.registerBuiltins(&registry);

    // Register agent-specific tools
    try spec.registerTools(&registry);

    var sharedContext = anthropic.Client.SharedContext.init(allocator);
    defer sharedContext.deinit();

    var messages = std.array_list.Managed(Message).init(allocator);
    defer messages.deinit();

    var systemPrompt = blk: {
        if (options.options.system) |explicit| break :blk try allocator.dupe(u8, explicit);
        break :blk try spec.buildSystemPrompt(allocator, options);
    };
    // Prepend anthropic spoof content, if present
    const spoof = blk: {
        const path = "prompt/anthropic_spoof.txt";
        const file = dir.openFile(path, .{}) catch break :blk null;
        defer file.close();
        const data = file.readToEndAlloc(allocator, 4096) catch break :blk null;
        break :blk data;
    };
    defer if (spoof) |s| allocator.free(s);

    if (spoof) |s| {
        if (std.fmt.allocPrint(allocator, "{s}\n\n{s}", .{ s, systemPrompt })) |combined| {
            // Replace original system prompt with combined content
            allocator.free(systemPrompt);
            systemPrompt = combined;
        } else |_| {
            // Allocation failed: proceed without spoof content
        }
    }
    defer allocator.free(systemPrompt);
    try messages.append(.{ .role = .system, .content = systemPrompt });

    const userPrompt = blk: {
        if (options.positionals) |prompt| break :blk try allocator.dupe(u8, prompt);

        if (options.options.input) |inputFile| {
            if (!std.mem.eql(u8, inputFile, "-")) {
                const file = dir.openFile(inputFile, .{}) catch |err| {
                    std.log.err("Failed to open input file '{s}': {any}", .{ inputFile, err });
                    return err;
                };
                defer file.close();
                const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
                    std.log.err("Failed to read input file '{s}': {any}", .{ inputFile, err });
                    return err;
                };
                break :blk content;
            }
        }

        const stdin = std.fs.File.stdin();
        const stdinBuffer = try allocator.alloc(u8, 64 * 1024);
        defer allocator.free(stdinBuffer);
        const bytesRead = try stdin.readAll(stdinBuffer);
        const stdinContent = std.mem.trim(u8, stdinBuffer[0..bytesRead], " \t\r\n");
        if (stdinContent.len == 0) {
            std.log.err("No input provided. Provide input via:\n  - Command argument: docz \"your prompt\"\n  - Input file: docz --input file.txt\n  - Stdin: echo \"your prompt\" | docz", .{});
            return error.NoInputProvided;
        }
        break :blk try allocator.dupe(u8, stdinContent);
    };
    defer allocator.free(userPrompt);

    try messages.append(.{ .role = .user, .content = userPrompt });

    if (options.options.output) |outputFile| {
        if (!std.mem.eql(u8, outputFile, "-")) {
            try initOutputFile(dir, outputFile);
            std.log.info("Output will be saved to: {s}", .{outputFile});
        }
    }

    if (!options.flags.stream) {
        std.log.info("Using non-streaming mode (complete response).", .{});
        const response = try client.complete(&sharedContext, .{
            .model = options.options.model,
            .maxTokens = options.options.tokensMax,
            .temperature = options.options.temperature,
            .messages = messages.items,
        });
        defer {
            var mutableResponse = response;
            mutableResponse.deinit();
        }
        writeCompleteResponse(response.content);
        std.log.info("Completion: {d} input tokens, {d} output tokens", .{ response.usage.inputTokens, response.usage.outputTokens });

        const costCalculator = client.getCostCalculator();
        if (!client.isOAuthSession()) {
            const inputCost = costCalculator.calculateInputCost(response.usage.inputTokens, options.options.model);
            const outputCost = costCalculator.calculateOutputCost(response.usage.outputTokens, options.options.model);
            const totalCost = inputCost + outputCost;
            std.log.info("Estimated cost: ${d:.4} (Input: ${d:.4}, Output: ${d:.4})", .{ totalCost, inputCost, outputCost });
        }
    } else {
        // Streaming loop with minimal tool execution support
        const max_history: usize = 10;
        while (true) {
            // Reset pending tool flags for this turn
            sharedContext.tools.hasPending = false;
            if (sharedContext.tools.jsonComplete) |s| {
                allocator.free(s);
                sharedContext.tools.jsonComplete = null;
            }

            try client.stream(&sharedContext, .{
                .model = options.options.model,
                .maxTokens = options.options.tokensMax,
                .temperature = options.options.temperature,
                .messages = messages.items,
                .onToken = onToken,
            });

            // If assistant requested tool_use, execute it and continue the loop
            if (sharedContext.tools.hasPending) {
                const toolJson = sharedContext.tools.jsonComplete orelse {
                    // No accumulated tool JSON; finish turn
                    break;
                };
                const toolName = sharedContext.tools.toolName orelse "";
                if (toolName.len == 0) {
                    std.log.warn("Tool use without name; skipping.", .{});
                    break;
                }

                const toolFn = registry.get(toolName);
                if (toolFn == null) {
                    std.log.warn("Unknown tool requested by model: {s}", .{toolName});
                    const errMsg = try std.fmt.allocPrint(allocator, "{{\"error\":\"unknown_tool\",\"tool\":\"{s}\"}}", .{toolName});
                    try messages.append(.{ .role = .tool, .content = errMsg });
                } else {
                    // Execute tool; keep context hygiene
                    var tool_ctx = foundation.context.SharedContext.init(allocator);
                    defer tool_ctx.deinit();
                    const out = toolFn.?(&tool_ctx, allocator, toolJson) catch |e| blk_err: {
                        const msg = try std.fmt.allocPrint(allocator, "{{\"error\":\"{s}\"}}", .{@errorName(e)});
                        break :blk_err msg;
                    };
                    try messages.append(.{ .role = .tool, .content = out });
                }

                // Clear tool tracking now that we've appended the result
                if (sharedContext.tools.toolName) |s| {
                    allocator.free(s);
                    sharedContext.tools.toolName = null;
                }
                if (sharedContext.tools.toolId) |s| {
                    allocator.free(s);
                    sharedContext.tools.toolId = null;
                }
                if (sharedContext.tools.jsonComplete) |s| {
                    allocator.free(s);
                    sharedContext.tools.jsonComplete = null;
                }
                sharedContext.tools.hasPending = false;

                // Trim history aggressively (keep last 10 messages)
                if (messages.items.len > max_history) {
                    const excess = messages.items.len - max_history;
                    // Shift remaining messages down (drop oldest without freeing to avoid double-free)
                    std.mem.copyForwards(Message, messages.items[0..], messages.items[excess..]);
                    messages.resize(max_history) catch {};
                }

                // Continue loop with new tool result appended
                continue;
            }

            // No tool requested; finish
            break;
        }
    }

    try flushAllOutputs();
}

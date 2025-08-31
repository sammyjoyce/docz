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
    const credentials = try oauth.setupOAuth(allocator);
    defer credentials.deinit(allocator);

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
    _ = ctx;
    initStdoutWriter();
    const stdout = &stdoutWriter.interface;
    stdout.writeAll(chunk) catch |err| {
        std.log.err("Failed to write streaming output to stdout: {any}", .{err});
    };

    if (outputWriterInitialized) {
        if (outputWriter) |*writer| {
            const fileWriter = &writer.interface;
            fileWriter.writeAll(chunk) catch |err| {
                std.log.err("Failed to write streaming output to file: {any}", .{err});
            };
        }
    }
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
        try client.stream(&sharedContext, .{
            .model = options.options.model,
            .maxTokens = options.options.tokensMax,
            .temperature = options.options.temperature,
            .messages = messages.items,
            .onToken = onToken,
        });
    }

    try flushAllOutputs();
}

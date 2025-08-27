//! Core engine for terminal AI agents.
//! Provides shared CLI, auth, client, and run loop logic.
//! Agent-specifics (prompts, tools) are supplied via AgentSpec.

const std = @import("std");
// These are wired by build.zig via named imports
const anthropic = @import("anthropic_shared");
const tools_mod = @import("tools_shared");
const auth = @import("auth_shared");

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
        max_tokens: u32,
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
fn mapAuthError(err: auth.core.AuthError) anthropic.Error {
    return switch (err) {
        auth.core.AuthError.MissingAPIKey => anthropic.Error.MissingAPIKey,
        auth.core.AuthError.InvalidApiKey => anthropic.Error.InvalidFormat,
        auth.core.AuthError.TokenExpired => anthropic.Error.TokenExpired,
        auth.core.AuthError.NetworkError => anthropic.Error.NetworkError,
        else => anthropic.Error.AuthError,
    };
}

/// Initialize Anthropic client using the new auth system
fn initAnthropicClient(allocator: std.mem.Allocator) !anthropic.AnthropicClient {
    var auth_client = auth.createClient(allocator) catch {
        std.log.err("No authentication method available - network access disabled for this agent.", .{});
        return anthropic.Error.MissingAPIKey;
    };
    defer auth_client.deinit();

    // Convert auth client to anthropic client
    const api_key = switch (auth_client.credentials) {
        .api_key => |key| key,
        .oauth => |oauth_creds| oauth_creds.access_token,
        .none => return anthropic.Error.MissingAPIKey,
    };

    return anthropic.AnthropicClient.init(allocator, api_key);
}

/// Start OAuth flow using the new auth TUI system
pub fn setupOAuth(allocator: std.mem.Allocator) !void {
    std.log.info("Starting Claude Pro/Max OAuth setup...", .{});
    if (@hasDecl(auth, "runAuthCommand")) {
        try auth.runAuthCommand(allocator, .login);
    } else {
        std.log.err("Authentication not available - this agent does not support network access", .{});
        return error.AuthNotAvailable;
    }
}

/// Display current authentication status using the new auth system
pub fn showAuthStatus(allocator: std.mem.Allocator) !void {
    try auth.runAuthCommand(allocator, .status);
}

/// Refresh authentication tokens using the new auth system
pub fn refreshAuth(allocator: std.mem.Allocator) !void {
    // For agents without network access, auth refresh is not available
    _ = allocator;
    std.log.info("Auth refresh not available for this agent (network access disabled)", .{});
}

/// Global stdout writer with buffer for streaming output
var stdout_buffer: [4096]u8 = undefined;
var stdout_writer_initialized = false;
var stdout_writer: std.fs.File.Writer = undefined;

/// Global output file writer for saving responses to files
var global_output_file: ?std.fs.File = null;
var output_buffer: [4096]u8 = undefined;
var output_writer_initialized = false;
var output_writer: ?std.fs.File.Writer = null;

fn initStdoutWriter() void {
    if (!stdout_writer_initialized) {
        stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        stdout_writer_initialized = true;
    }
}

fn initOutputFile(file_path: []const u8) !void {
    if (!output_writer_initialized) {
        global_output_file = try std.fs.cwd().createFile(file_path, .{});
        output_writer = global_output_file.?.writer(&output_buffer);
        output_writer_initialized = true;
    }
}

fn flushAllOutputs() !void {
    if (stdout_writer_initialized) {
        const stdout = &stdout_writer.interface;
        stdout.flush() catch |err| {
            std.log.warn("Failed to flush stdout after streaming: {}", .{err});
        };
    }

    if (output_writer_initialized) {
        if (output_writer) |*writer| {
            const file_writer = &writer.interface;
            file_writer.flush() catch |err| {
                std.log.warn("Failed to flush output file: {}", .{err});
            };
        }
        if (global_output_file) |file| {
            file.close();
            global_output_file = null;
            output_writer = null;
            output_writer_initialized = false;
        }
    }
}

fn onToken(chunk: []const u8) void {
    initStdoutWriter();
    const stdout = &stdout_writer.interface;
    stdout.writeAll(chunk) catch |err| {
        std.log.err("Failed to write streaming output to stdout: {}", .{err});
    };

    if (output_writer_initialized) {
        if (output_writer) |*writer| {
            const file_writer = &writer.interface;
            file_writer.writeAll(chunk) catch |err| {
                std.log.err("Failed to write streaming output to file: {}", .{err});
            };
        }
    }
}

fn writeCompleteResponse(content: []const u8) void {
    initStdoutWriter();
    const stdout = &stdout_writer.interface;
    stdout.writeAll(content) catch |err| {
        std.log.err("Failed to write complete response to stdout: {}", .{err});
    };

    if (output_writer_initialized) {
        if (output_writer) |*writer| {
            const file_writer = &writer.interface;
            file_writer.writeAll(content) catch |err| {
                std.log.err("Failed to write complete response to file: {}", .{err});
            };
        }
    }
}

/// Main engine entry point used by all agents.
pub fn runWithOptions(allocator: std.mem.Allocator, options: CliOptions, spec: AgentSpec) !void {
    var client = try initAnthropicClient(allocator);
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
    try tools_mod.registerBuiltIns(&registry);

    // Register agent-specific tools
    try spec.registerTools(&registry);

    var messages = std.array_list.Managed(Message).init(allocator);
    defer messages.deinit();

    const system_prompt = blk: {
        if (options.options.system) |explicit| break :blk try allocator.dupe(u8, explicit);
        break :blk try spec.buildSystemPrompt(allocator, options);
    };
    defer allocator.free(system_prompt);
    try messages.append(.{ .role = .system, .content = system_prompt });

    const user_prompt = blk: {
        if (options.positionals) |prompt| break :blk try allocator.dupe(u8, prompt);

        if (options.options.input) |input_file| {
            if (!std.mem.eql(u8, input_file, "-")) {
                const file = std.fs.cwd().openFile(input_file, .{}) catch |err| {
                    std.log.err("Failed to open input file '{s}': {}", .{ input_file, err });
                    return err;
                };
                defer file.close();
                const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
                    std.log.err("Failed to read input file '{s}': {}", .{ input_file, err });
                    return err;
                };
                break :blk content;
            }
        }

        const stdin = std.fs.File.stdin();
        const stdin_buffer = try allocator.alloc(u8, 64 * 1024);
        defer allocator.free(stdin_buffer);
        const bytes_read = try stdin.readAll(stdin_buffer);
        const stdin_content = std.mem.trim(u8, stdin_buffer[0..bytes_read], " \t\r\n");
        if (stdin_content.len == 0) {
            std.log.err("No input provided. Provide input via:\n  - Command argument: docz \"your prompt\"\n  - Input file: docz --input file.txt\n  - Stdin: echo \"your prompt\" | docz", .{});
            return error.NoInputProvided;
        }
        break :blk try allocator.dupe(u8, stdin_content);
    };
    defer allocator.free(user_prompt);

    try messages.append(.{ .role = .user, .content = user_prompt });

    if (options.options.output) |output_file| {
        if (!std.mem.eql(u8, output_file, "-")) {
            try initOutputFile(output_file);
            std.log.info("Output will be saved to: {s}", .{output_file});
        }
    }

    if (!options.flags.stream) {
        std.log.info("Using non-streaming mode (complete response).", .{});
        const response = try client.complete(.{
            .model = options.options.model,
            .max_tokens = options.options.max_tokens,
            .temperature = options.options.temperature,
            .messages = messages.items,
        });
        defer {
            var mutable_response = response;
            mutable_response.deinit(allocator);
        }
        writeCompleteResponse(response.content);
        std.log.info("Completion: {} input tokens, {} output tokens", .{ response.usage.input_tokens, response.usage.output_tokens });

        const cost_calculator = anthropic.CostCalculator.init(client.isOAuthSession());
        if (!client.isOAuthSession()) {
            const input_cost = cost_calculator.calculateInputCost(response.usage.input_tokens, options.options.model);
            const output_cost = cost_calculator.calculateOutputCost(response.usage.output_tokens, options.options.model);
            const total_cost = input_cost + output_cost;
            std.log.info("Estimated cost: ${d:.4} (Input: ${d:.4}, Output: ${d:.4})", .{ total_cost, input_cost, output_cost });
        }
    } else {
        try client.stream(.{
            .model = options.options.model,
            .max_tokens = options.options.max_tokens,
            .temperature = options.options.temperature,
            .messages = messages.items,
            .on_token = &onToken,
        });
    }

    try flushAllOutputs();
}



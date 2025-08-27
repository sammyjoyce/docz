//! Core engine for terminal AI agents.
//! Provides shared CLI, auth, client, and run loop logic.
//! Agent-specifics (prompts, tools) are supplied via AgentSpec.

const std = @import("std");
// These are wired by build.zig via named imports
const anthropic = @import("anthropic_shared");
const tools_mod = @import("tools_shared");
// const auth = @import("auth_shared"); // Temporarily disabled for testing

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
        maxTokens: u32,
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
fn mapAuthError(err: anyerror) anthropic.Error {
    // Stub implementation - auth module not available
    _ = err;
    return anthropic.Error.AuthError;
}

/// Initialize Anthropic client using the new auth system
fn initAnthropicClient(allocator: std.mem.Allocator) !anthropic.AnthropicClient {
    // Stub implementation - auth module not available
    _ = allocator;
    std.log.err("No authentication method available - network access disabled for this agent.", .{});
    return anthropic.Error.MissingAPIKey;
}

/// Start OAuth flow using the new auth TUI system
pub fn setupOAuth(allocator: std.mem.Allocator) !void {
    // Stub implementation - auth module not available
    _ = allocator;
    std.log.err("OAuth not available - network access disabled for this agent.", .{});
    return error.AuthNotAvailable;
}

/// Display current authentication status using the new auth system
pub fn showAuthStatus(allocator: std.mem.Allocator) !void {
    // Stub implementation - auth module not available
    _ = allocator;
    std.log.err("Auth status not available - network access disabled for this agent.", .{});
    return error.AuthNotAvailable;
}

/// Refresh authentication tokens using the new auth system
pub fn refreshAuth(allocator: std.mem.Allocator) !void {
    // Stub implementation - auth module not available
    _ = allocator;
    std.log.err("Auth refresh not available - network access disabled for this agent.", .{});
    return error.AuthNotAvailable;
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

fn initOutputFile(filePath: []const u8) !void {
    if (!outputWriterInitialized) {
        globalOutputFile = try std.fs.cwd().createFile(filePath, .{});
        outputWriter = globalOutputFile.?.writer(&outputBuffer);
        outputWriterInitialized = true;
    }
}

fn flushAllOutputs() !void {
    if (stdoutWriterInitialized) {
        const stdout = &stdoutWriter.interface;
        stdout.flush() catch |err| {
            std.log.warn("Failed to flush stdout after streaming: {}", .{err});
        };
    }

    if (outputWriterInitialized) {
        if (outputWriter) |*writer| {
            const fileWriter = &writer.interface;
            fileWriter.flush() catch |err| {
                std.log.warn("Failed to flush output file: {}", .{err});
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

fn onToken(chunk: []const u8) void {
    initStdoutWriter();
    const stdout = &stdoutWriter.interface;
    stdout.writeAll(chunk) catch |err| {
        std.log.err("Failed to write streaming output to stdout: {}", .{err});
    };

    if (outputWriterInitialized) {
        if (outputWriter) |*writer| {
            const fileWriter = &writer.interface;
            fileWriter.writeAll(chunk) catch |err| {
                std.log.err("Failed to write streaming output to file: {}", .{err});
            };
        }
    }
}

fn writeCompleteResponse(content: []const u8) void {
    initStdoutWriter();
    const stdout = &stdoutWriter.interface;
    stdout.writeAll(content) catch |err| {
        std.log.err("Failed to write complete response to stdout: {}", .{err});
    };

    if (outputWriterInitialized) {
        if (outputWriter) |*writer| {
            const fileWriter = &writer.interface;
            fileWriter.writeAll(content) catch |err| {
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
    try tools_mod.registerBuiltins(&registry);

    // Register agent-specific tools
    try spec.registerTools(&registry);

    var messages = std.array_list.Managed(Message).init(allocator);
    defer messages.deinit();

    const systemPrompt = blk: {
        if (options.options.system) |explicit| break :blk try allocator.dupe(u8, explicit);
        break :blk try spec.buildSystemPrompt(allocator, options);
    };
    defer allocator.free(systemPrompt);
    try messages.append(.{ .role = .system, .content = systemPrompt });

    const userPrompt = blk: {
        if (options.positionals) |prompt| break :blk try allocator.dupe(u8, prompt);

        if (options.options.input) |inputFile| {
            if (!std.mem.eql(u8, inputFile, "-")) {
                const file = std.fs.cwd().openFile(inputFile, .{}) catch |err| {
                    std.log.err("Failed to open input file '{s}': {}", .{ inputFile, err });
                    return err;
                };
                defer file.close();
                const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
                    std.log.err("Failed to read input file '{s}': {}", .{ inputFile, err });
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
            try initOutputFile(outputFile);
            std.log.info("Output will be saved to: {s}", .{outputFile});
        }
    }

    if (!options.flags.stream) {
        std.log.info("Using non-streaming mode (complete response).", .{});
        const response = try client.complete(.{
            .model = options.options.model,
            .max_tokens = options.options.maxTokens,
            .temperature = options.options.temperature,
            .messages = messages.items,
        });
        defer {
            var mutableResponse = response;
            mutableResponse.deinit(allocator);
        }
        writeCompleteResponse(response.content);
        std.log.info("Completion: {} input tokens, {} output tokens", .{ response.usage.input_tokens, response.usage.output_tokens });

        const costCalculator = anthropic.CostCalculator.init(client.isOAuthSession());
        if (!client.isOAuthSession()) {
            const inputCost = costCalculator.calculateInputCost(response.usage.input_tokens, options.options.model);
            const outputCost = costCalculator.calculateOutputCost(response.usage.output_tokens, options.options.model);
            const totalCost = inputCost + outputCost;
            std.log.info("Estimated cost: ${d:.4} (Input: ${d:.4}, Output: ${d:.4})", .{ totalCost, inputCost, outputCost });
        }
    } else {
        try client.stream(.{
            .model = options.options.model,
            .max_tokens = options.options.maxTokens,
            .temperature = options.options.temperature,
            .messages = messages.items,
            .on_token = &onToken,
        });
    }

    try flushAllOutputs();
}

//! Core engine for terminal AI agents.
//! Provides shared CLI, auth, client, and run loop logic.
//! Agent-specifics (prompts, tools) are supplied via AgentSpec.

const std = @import("std");
// These are wired by build.zig via named imports
const anthropic = @import("anthropic_shared");
const tools_mod = @import("tools_shared");

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

/// Initialize Anthropic client, preferring OAuth over API key
fn initAnthropicClient(allocator: std.mem.Allocator) !anthropic.AnthropicClient {
    const oauth_path = "claude_oauth_creds.json";
    if (anthropic.loadOAuthCredentials(allocator, oauth_path)) |maybe_creds| {
        if (maybe_creds) |creds| {
            std.log.info("Using OAuth authentication", .{});
            return try anthropic.AnthropicClient.initWithOAuth(allocator, creds, oauth_path);
        }
    } else |_| {}

    const api_key = std.posix.getenv("ANTHROPIC_API_KEY") orelse "";
    if (api_key.len > 0) {
        std.log.info("Using API key authentication", .{});
        return try anthropic.AnthropicClient.init(allocator, api_key);
    }

    std.log.err("No authentication method available. Either provide ANTHROPIC_API_KEY environment variable or run OAuth setup.", .{});
    return anthropic.Error.MissingAPIKey;
}

/// Start OAuth flow and save credentials
pub fn setupOAuth(allocator: std.mem.Allocator) !void {
    std.log.info("Starting Claude Pro/Max OAuth setup...", .{});

    const pkce_params = try anthropic.generatePkceParams(allocator);
    defer {
        allocator.free(pkce_params.code_verifier);
        allocator.free(pkce_params.code_challenge);
        allocator.free(pkce_params.state);
    }

    const auth_url = try anthropic.buildAuthorizationUrl(allocator, pkce_params);
    defer allocator.free(auth_url);

    std.log.info("Opening authorization URL in your browser...", .{});
    std.log.info("Authorization URL: {s}", .{auth_url});
    try anthropic.launchBrowser(auth_url);

    const auth_code = anthropic.waitForOAuthCallback(allocator, 8080) catch |err| {
        std.log.err("Failed to get authorization code: {}", .{err});
        return err;
    };
    defer allocator.free(auth_code);

    std.log.info("Received authorization code, exchanging for tokens...", .{});
    const credentials = anthropic.exchangeCodeForTokens(allocator, auth_code, pkce_params) catch |err| {
        std.log.err("Failed to exchange authorization code for tokens: {}", .{err});
        return err;
    };

    const creds_path = "claude_oauth_creds.json";
    std.log.info("Saving OAuth credentials to {s}...", .{creds_path});
    try anthropic.saveOAuthCredentials(allocator, creds_path, credentials);

    if (std.fs.cwd().openFile(creds_path, .{})) |file| {
        defer file.close();
        file.chmod(0o600) catch |err| {
            std.log.warn("Failed to set secure file permissions on {s}: {}", .{ creds_path, err });
        };
    } else |_| {}

    std.log.info("✅ OAuth setup completed successfully!", .{});

    allocator.free(credentials.type);
    allocator.free(credentials.access_token);
    allocator.free(credentials.refresh_token);
}

/// Display current authentication status
pub fn showAuthStatus(allocator: std.mem.Allocator) !void {
    const print = std.debug.print;
    print("🔑 Authentication Status\n", .{});
    print("========================\n\n", .{});

    const oauth_path = "claude_oauth_creds.json";
    if (anthropic.loadOAuthCredentials(allocator, oauth_path)) |maybe_creds| {
        if (maybe_creds) |creds| {
            defer {
                allocator.free(creds.type);
                allocator.free(creds.access_token);
                allocator.free(creds.refresh_token);
            }

            if (creds.isExpired()) {
                print("🔐 OAuth Authentication: EXPIRED\n", .{});
                print("   Status: Credentials found but expired\n", .{});
                print("   Action: Run 'docz auth refresh' to renew tokens\n", .{});
            } else {
                print("✅ OAuth Authentication: ACTIVE\n", .{});
                print("   Status: Using Claude Pro/Max OAuth authentication\n", .{});
                print("   Type: Subscription-based (no pay-per-use costs)\n", .{});
            }
        } else {
            print("❌ OAuth Authentication: NOT FOUND\n", .{});
        }
    } else |_| {
        print("❌ OAuth Authentication: ERROR\n", .{});
        print("   Status: Cannot read OAuth credentials file\n", .{});
    }

    print("\n", .{});

    const api_key = std.posix.getenv("ANTHROPIC_API_KEY") orelse "";
    if (api_key.len > 0) {
        print("🔑 API Key Authentication: AVAILABLE\n", .{});
        print("   Status: ANTHROPIC_API_KEY environment variable set\n", .{});
        print("   Type: Pay-per-use billing\n", .{});
    } else {
        print("❌ API Key Authentication: NOT SET\n", .{});
        print("   Status: ANTHROPIC_API_KEY environment variable not found\n", .{});
    }
}

/// Refresh OAuth tokens if available
pub fn refreshAuth(allocator: std.mem.Allocator) !void {
    const print = std.debug.print;
    print("🔄 Refreshing authentication...\n", .{});

    const oauth_path = "claude_oauth_creds.json";
    if (anthropic.loadOAuthCredentials(allocator, oauth_path)) |maybe_creds| {
        if (maybe_creds) |creds| {
            defer {
                allocator.free(creds.type);
                allocator.free(creds.access_token);
                allocator.free(creds.refresh_token);
            }

            print("Found OAuth credentials, attempting to refresh...\n", .{});
            var client = anthropic.AnthropicClient.initWithOAuth(allocator, creds, oauth_path) catch |err| {
                print("❌ Failed to initialize OAuth client: {}\n", .{err});
                return err;
            };
            defer client.deinit();

            client.refreshOAuthIfNeeded() catch |err| {
                print("❌ Failed to refresh OAuth tokens: {}\n", .{err});
                print("   You may need to run 'docz auth login' to re-authenticate\n", .{});
                return err;
            };

            print("✅ OAuth tokens refreshed successfully!\n", .{});
        } else {
            print("❌ No OAuth credentials found\n", .{});
            print("   Run 'docz auth login' to setup OAuth authentication\n", .{});
        }
    } else |err| {
        print("❌ Failed to load OAuth credentials: {}\n", .{err});
        print("   Run 'docz auth login' to setup OAuth authentication\n", .{});
        return err;
    }
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

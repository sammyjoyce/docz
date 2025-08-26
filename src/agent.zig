//! Minimal agent loop connecting STDIN → Anthropic → STDOUT.
//!
//! This is *not* production-ready. It demonstrates how the streaming client
//! and tools registry integrate. The loop:
//! 1. Reads a full prompt from stdin.
//! 2. Feeds it to Anthropic with system instructions and streams output.
//! 3. Prints tokens to stdout as they arrive.
//!
//! Tool calls are stubbed: if the assistant's message begins with "TOOL: name json",
//! the named tool is executed and its result streamed back, then the conversation
//! continues.

const std = @import("std");
const anthropic = @import("anthropic.zig");
const AnthropicClient = anthropic.AnthropicClient;
const Message = anthropic.Message;
const MessageRole = anthropic.MessageRole;
const tools_mod = @import("tools.zig");

/// Native CLI options structure matching cli.zon specification.
/// Uses pure Zig types for CLI parsing integration.
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
        oauth: bool,
        verbose: bool,
        help: bool,
        version: bool,
        stream: bool,
        pretty: bool,
        debug: bool,
        interactive: bool,
    },
    positionals: ?[]const u8, // Single PROMPT string matching cli.zon
};

/// Initialize Anthropic client, preferring OAuth over API key
fn initAnthropicClient(allocator: std.mem.Allocator) !AnthropicClient {
    // Try OAuth credentials first
    const oauth_path = "claude_oauth_creds.json";
    if (anthropic.loadOAuthCredentials(allocator, oauth_path)) |maybe_creds| {
        if (maybe_creds) |creds| {
            std.log.info("Using OAuth authentication", .{});
            return try AnthropicClient.initWithOAuth(allocator, creds, oauth_path);
        }
    } else |_| {
        // OAuth credentials not found or invalid
    }

    // Fallback to API key
    const api_key = std.posix.getenv("ANTHROPIC_API_KEY") orelse "";
    if (api_key.len > 0) {
        std.log.info("Using API key authentication", .{});
        return try AnthropicClient.init(allocator, api_key);
    }

    // No authentication method available
    std.log.err("No authentication method available. Either provide ANTHROPIC_API_KEY environment variable or run OAuth setup.", .{});
    return anthropic.Error.MissingAPIKey;
}

/// Start OAuth flow and save credentials
pub fn setupOAuth(allocator: std.mem.Allocator) !void {
    std.log.info("Starting Claude Pro/Max OAuth setup...", .{});

    // Step 1: Generate PKCE parameters
    std.log.info("Generating PKCE parameters...", .{});
    const pkce_params = try anthropic.generatePkceParams(allocator);
    defer {
        allocator.free(pkce_params.code_verifier);
        allocator.free(pkce_params.code_challenge);
        allocator.free(pkce_params.state);
    }

    // Step 2: Build authorization URL
    std.log.info("Building authorization URL...", .{});
    const auth_url = try anthropic.buildAuthorizationUrl(allocator, pkce_params);
    defer allocator.free(auth_url);

    // Step 3: Launch browser
    std.log.info("Opening authorization URL in your browser...", .{});
    std.log.info("Authorization URL: {s}", .{auth_url});

    try anthropic.launchBrowser(auth_url);

    // Step 4: Wait for callback and get authorization code
    std.log.info("Waiting for OAuth callback...", .{});
    const auth_code = anthropic.waitForOAuthCallback(allocator, 8080) catch |err| {
        std.log.err("Failed to get authorization code: {}", .{err});
        return err;
    };
    defer allocator.free(auth_code);

    std.log.info("Received authorization code, exchanging for tokens...", .{});

    // Step 5: Exchange code for tokens
    const credentials = anthropic.exchangeCodeForTokens(allocator, auth_code, pkce_params) catch |err| {
        std.log.err("Failed to exchange authorization code for tokens: {}", .{err});

        switch (err) {
            anthropic.Error.AuthError => {
                std.log.err("Authentication failed. Please try the OAuth setup again.", .{});
                std.log.err("Common issues:", .{});
                std.log.err("  - Authorization code may have expired", .{});
                std.log.err("  - Invalid or incomplete callback URL", .{});
                std.log.err("  - Network connectivity issues", .{});
            },
            else => {},
        }

        return err;
    };

    // Step 6: Save credentials securely
    const creds_path = "claude_oauth_creds.json";
    std.log.info("Saving OAuth credentials to {s}...", .{creds_path});

    try anthropic.saveOAuthCredentials(allocator, creds_path, credentials);

    // Set file permissions to owner-only (600) for security
    if (std.fs.cwd().openFile(creds_path, .{})) |file| {
        defer file.close();
        file.chmod(0o600) catch |err| {
            std.log.warn("Failed to set secure file permissions on {s}: {}", .{ creds_path, err });
        };
    } else |_| {}

    std.log.info("✅ OAuth setup completed successfully!", .{});
    std.log.info("Your Claude Pro/Max authentication is now configured.", .{});
    std.log.info("You can now use the CLI without setting ANTHROPIC_API_KEY.", .{});
    std.log.info("", .{});
    std.log.info("Next steps:", .{});
    std.log.info("  - Run regular CLI commands to test the setup", .{});
    std.log.info("  - Your tokens will be automatically refreshed as needed", .{});
    std.log.info("  - Usage costs are covered by your Claude Pro/Max subscription", .{});

    // Clean up credentials memory
    allocator.free(credentials.type);
    allocator.free(credentials.access_token);
    allocator.free(credentials.refresh_token);
}

/// Backward compatibility entry point that uses default CLI options.
/// This function maintains compatibility with code that calls agent.run()
/// directly without providing CLI options.
pub fn run(allocator: std.mem.Allocator) !void {
    // Create default options matching cli.zon defaults
    const default_options = CliOptions{
        .options = .{
            .model = "claude-3-sonnet-20240229",
            .output = null,
            .input = null,
            .system = null,
            .config = null,
            .max_tokens = 4096,
            .temperature = 0.7,
        },
        .flags = .{
            .oauth = false,
            .verbose = false,
            .help = false,
            .version = false,
            .stream = true,
            .pretty = false,
            .debug = false,
            .interactive = false,
        },
        .positionals = null,
    };

    try runWithOptions(allocator, default_options);
}

/// Main agent entry point that accepts native CLI options.
/// This function handles the full agent loop with the provided configuration.
pub fn runWithOptions(allocator: std.mem.Allocator, options: CliOptions) !void {
    // Prepare Anthropic client - try OAuth first, fallback to API key
    var client = try initAnthropicClient(allocator);
    defer client.deinit();

    // Log authentication mode and cost information
    if (client.isOAuthSession()) {
        std.log.info("🔐 Using Claude Pro/Max OAuth authentication", .{});
        std.log.info("💰 Usage costs are covered by your subscription", .{});
    } else {
        std.log.info("🔑 Using API key authentication", .{});
        std.log.info("💳 Usage will be billed according to your API plan", .{});
    }

    // Prepare tools
    var registry = tools_mod.Registry.init(allocator);
    defer registry.deinit();
    try tools_mod.registerBuiltIns(&registry);

    // Build conversation
    var messages = std.array_list.Managed(Message).init(allocator);
    defer messages.deinit();

    // Get current date for system prompt
    const current_date = blk: {
        const timestamp = std.time.timestamp();
        const epoch_seconds: i64 = @intCast(timestamp);
        const days_since_epoch: u47 = @intCast(@divFloor(epoch_seconds, std.time.s_per_day));
        const epoch_day = std.time.epoch.EpochDay{ .day = days_since_epoch };
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        break :blk try std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2}", .{
            year_day.year, @intFromEnum(month_day.month), month_day.day_index,
        });
    };
    defer allocator.free(current_date);

    // Add system prompt - prepend anthropic_spoof.txt to custom or default prompt
    const base_system_prompt = options.options.system orelse try std.fmt.allocPrint(allocator,
        \\# Role
        \\You are DocZ, a Zig coding agent specialized in writing and refining markdown documents.
        \\
        \\# Identity
        \\DocZ is a specialized AI assistant for markdown document management, built with Zig and focused on high-quality document creation and editing.
        \\
        \\# Today's Date
        \\The current date is {s}.
        \\
        \\# IMPORTANT
        \\- NEVER modify files without explicit user permission
        \\- ALWAYS validate changes before finalizing
        \\- NEVER break existing document structure or links
        \\
        \\# Output Formatting
        \\- Be concise and direct in responses
        \\- Report specific changes made to documents
        \\- Use bullet points for clarity
        \\- Provide file paths when referencing documents
    , .{current_date});
    defer if (options.options.system == null) allocator.free(base_system_prompt);

    // Read and prepend anthropic_spoof.txt
    const spoof_content = blk: {
        const spoof_file = std.fs.cwd().openFile("prompt/anthropic_spoof.txt", .{}) catch |err| {
            std.log.warn("Could not read prompt/anthropic_spoof.txt: {}, using base prompt only", .{err});
            break :blk "";
        };
        defer spoof_file.close();
        break :blk spoof_file.readToEndAlloc(allocator, 1024) catch |err| {
            std.log.warn("Could not read prompt/anthropic_spoof.txt content: {}, using base prompt only", .{err});
            break :blk "";
        };
    };
    defer if (spoof_content.len > 0) allocator.free(spoof_content);

    const system_prompt = if (spoof_content.len > 0)
        try std.fmt.allocPrint(allocator, "{s}\n\n{s}", .{ spoof_content, base_system_prompt })
    else
        try allocator.dupe(u8, base_system_prompt);
    defer allocator.free(system_prompt);

    try messages.append(.{ .role = .system, .content = system_prompt });

    // Get user input - from positional arg, file, or stdin ('-' means stdin)
    const user_prompt = blk: {
        // First check for positional argument
        if (options.positionals) |prompt| {
            break :blk try allocator.dupe(u8, prompt); // Make owned copy
        }

        // Then check for input file
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
                // Don't defer free here - return the allocated content directly
                break :blk content;
            }
        }

        // Read from stdin for interactive usage (or when --input "-" is passed)
        const stdin = std.fs.File.stdin();
        const stdin_buffer = try allocator.alloc(u8, 64 * 1024); // 64KB buffer for user input
        defer allocator.free(stdin_buffer);

        // Read full input from stdin until EOF
        const bytes_read = try stdin.readAll(stdin_buffer);
        const stdin_content = std.mem.trim(u8, stdin_buffer[0..bytes_read], " \t\r\n");

        if (stdin_content.len == 0) {
            std.log.err("No input provided. Provide input via:\n  - Command argument: docz \"your prompt\"\n  - Input file: docz --input file.txt\n  - Stdin: echo \"your prompt\" | docz", .{});
            return error.NoInputProvided;
        }

        // Return owned copy of stdin content
        break :blk try allocator.dupe(u8, stdin_content);
    };
    defer allocator.free(user_prompt); // Free the owned copy after use

    try messages.append(.{ .role = .user, .content = user_prompt });

    // Initialize output file if specified ('-' means stdout)
    if (options.options.output) |output_file| {
        if (!std.mem.eql(u8, output_file, "-")) {
            try initOutputFile(output_file);
            std.log.info("Output will be saved to: {s}", .{output_file});
        }
    }

    if (!options.flags.stream) {
        std.log.info("Using non-streaming mode (complete response).", .{});

        // Use non-streaming API call
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

        // Write complete response to stdout and output file
        writeCompleteResponse(response.content);

        // Log usage information
        std.log.info("Completion: {} input tokens, {} output tokens", .{ response.usage.input_tokens, response.usage.output_tokens });

        // Calculate cost information
        const cost_calculator = anthropic.CostCalculator.init(client.isOAuthSession());
        if (!client.isOAuthSession()) {
            const input_cost = cost_calculator.calculateInputCost(response.usage.input_tokens, options.options.model);
            const output_cost = cost_calculator.calculateOutputCost(response.usage.output_tokens, options.options.model);
            const total_cost = input_cost + output_cost;
            std.log.info("Estimated cost: ${d:.4} (Input: ${d:.4}, Output: ${d:.4})", .{ total_cost, input_cost, output_cost });
        }
    } else {
        // Stream response with configured model and parameters
        try client.stream(.{
            .model = options.options.model,
            .max_tokens = options.options.max_tokens,
            .temperature = options.options.temperature,
            .messages = messages.items,
            .on_token = &onToken,
        });
    }

    // Ensure all output is flushed after completion
    try flushAllOutputs();
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

/// Initialize stdout writer with proper buffering (call once)
fn initStdoutWriter() void {
    if (!stdout_writer_initialized) {
        stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        stdout_writer_initialized = true;
    }
}

/// Initialize output file writer with proper buffering
fn initOutputFile(file_path: []const u8) !void {
    if (!output_writer_initialized) {
        global_output_file = try std.fs.cwd().createFile(file_path, .{});
        output_writer = global_output_file.?.writer(&output_buffer);
        output_writer_initialized = true;
    }
}

/// Flush all output streams (stdout and output file if open)
fn flushAllOutputs() !void {
    // Flush stdout
    if (stdout_writer_initialized) {
        const stdout = &stdout_writer.interface;
        stdout.flush() catch |err| {
            std.log.warn("Failed to flush stdout after streaming: {}", .{err});
        };
    }

    // Flush and close output file
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

/// Enhanced streaming token callback that writes to both stdout and output file
fn onToken(chunk: []const u8) void {
    // Always write to stdout for real-time feedback
    initStdoutWriter();
    const stdout = &stdout_writer.interface;
    stdout.writeAll(chunk) catch |err| {
        std.log.err("Failed to write streaming output to stdout: {}", .{err});
    };

    // Also write to output file if configured
    if (output_writer_initialized) {
        if (output_writer) |*writer| {
            const file_writer = &writer.interface;
            file_writer.writeAll(chunk) catch |err| {
                std.log.err("Failed to write streaming output to file: {}", .{err});
            };
        }
    }
}

/// Write complete response to both stdout and output file (for non-streaming mode)
fn writeCompleteResponse(content: []const u8) void {
    // Always write to stdout
    initStdoutWriter();
    const stdout = &stdout_writer.interface;
    stdout.writeAll(content) catch |err| {
        std.log.err("Failed to write complete response to stdout: {}", .{err});
    };

    // Also write to output file if configured
    if (output_writer_initialized) {
        if (output_writer) |*writer| {
            const file_writer = &writer.interface;
            file_writer.writeAll(content) catch |err| {
                std.log.err("Failed to write complete response to file: {}", .{err});
            };
        }
    }
}

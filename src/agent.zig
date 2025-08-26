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
        help_me: bool,
        version: bool,
        stream: bool,
        disable_stream: bool,
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
            .help_me = false,
            .version = false,
            .stream = true,
            .disable_stream = false,
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

    // Get user input - from positional arg, file, or stdin
    const user_prompt = blk: {
        // First check for positional argument
        if (options.positionals) |prompt| {
            break :blk prompt;
        }

        // Then check for input file
        if (options.options.input) |input_file| {
            const file = std.fs.cwd().openFile(input_file, .{}) catch |err| {
                std.log.err("Failed to open input file '{s}': {}", .{ input_file, err });
                return err;
            };
            defer file.close();

            const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
                std.log.err("Failed to read input file '{s}': {}", .{ input_file, err });
                return err;
            };
            defer allocator.free(content);
            break :blk content;
        }

        // Fallback to default message for now
        // TODO: Implement proper stdin reading
        break :blk "Hello from DocZ!";
    };

    try messages.append(.{ .role = .user, .content = user_prompt });

    // Stream response with configured model and parameters
    // TODO: Implement output file support and non-streaming mode
    if (options.options.output) |output_file| {
        std.log.warn("Output file support not yet implemented. Output will go to stdout. File: '{s}'", .{output_file});
    }

    if (options.flags.disable_stream) {
        std.log.warn("Non-streaming mode not yet implemented. Using streaming mode.", .{});
    }

    try client.stream(.{
        .model = options.options.model,
        .messages = messages.items,
        .on_token = &onToken,
    });
}

fn onToken(chunk: []const u8) void {
    // TODO: Fix stdout API - for now just print to debug
    std.debug.print("{s}", .{chunk});
}

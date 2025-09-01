//! Agent main entry point with CLI parsing and agent orchestration.
//! Provides common CLI parsing, argument handling, and engine delegation.
//!
//! This module focuses on core agent functionality without forcing UI dependencies.
//! Theme and UX framework integration is available through optional imports.

const std = @import("std");

/// Main function for agents with CLI parsing and engine execution.
/// Agents should call this from their main.zig with their specific spec.
pub fn runAgent(allocator: std.mem.Allocator, spec: anytype) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cliArgs = if (args.len > 1) args[1..] else args[0..0];

    const cliArgsConst = try allocator.alloc([]const u8, cliArgs.len);
    defer allocator.free(cliArgsConst);
    for (cliArgs, 0..) |arg, i| {
        cliArgsConst[i] = std.mem.sliceTo(arg, 0);
    }

    // Handle auth subcommands
    if (cliArgsConst.len > 0 and std.mem.eql(u8, cliArgsConst[0], "auth")) {
        try handleAuthCommand(allocator, cliArgsConst[1..]);
        return;
    }

    // Handle run command (default)
    if (cliArgsConst.len == 0 or (cliArgsConst.len > 0 and std.mem.eql(u8, cliArgsConst[0], "run"))) {
        try runAgentLoop(allocator, spec, cliArgsConst[1..]);
        return;
    }

    // Unknown command
    std.log.err("Unknown command: {s}", .{cliArgsConst[0]});
    std.log.info("Available commands: auth, run", .{});
    return error.InvalidCommand;
}

/// Handle auth subcommands
fn handleAuthCommand(allocator: std.mem.Allocator, subArgs: [][]const u8) !void {
    if (subArgs.len == 0) {
        std.log.err("Auth subcommand required. Available: login, status, whoami, logout, test-call", .{});
        return error.MissingSubcommand;
    }

    const subcommand = subArgs[0];

    if (std.mem.eql(u8, subcommand, "login")) {
        const manual = hasFlag(subArgs, "--manual");
        const port = getPortArg(subArgs) orelse 8080;
        const host = getStringArg(subArgs, "--host") orelse "localhost";

        try @import("cli/auth.zig").Commands.login(allocator, .{
            .port = port,
            .host = host,
            .manual = manual,
        });
    } else if (std.mem.eql(u8, subcommand, "status")) {
        try @import("cli/auth.zig").Commands.status(allocator);
    } else if (std.mem.eql(u8, subcommand, "whoami")) {
        try @import("cli/auth.zig").Commands.whoami(allocator);
    } else if (std.mem.eql(u8, subcommand, "logout")) {
        try @import("cli/auth.zig").Commands.logout(allocator);
    } else if (std.mem.eql(u8, subcommand, "test-call")) {
        const stream = hasFlag(subArgs, "--stream");
        try @import("cli/auth.zig").Commands.testCall(allocator, .{ .stream = stream });
    } else {
        std.log.err("Unknown auth subcommand: {s}", .{subcommand});
        std.log.info("Available: login, status, whoami, logout, test-call", .{});
        return error.InvalidSubcommand;
    }
}

/// Run the main agent loop
fn runAgentLoop(allocator: std.mem.Allocator, spec: anytype, runArgs: [][]const u8) !void {
    // Parse CLI options for the run command
    const options = try parseRunOptions(allocator, runArgs);
    defer cleanupRunOptions(allocator, &options);

    // Import engine at runtime to avoid circular dependencies
    const engine = @import("../engine.zig");

    // Run the engine with the parsed options
    try engine.runWithOptions(allocator, options, spec, ".");
}

/// Parse CLI options for the run command
fn parseRunOptions(allocator: std.mem.Allocator, args: [][]const u8) !@import("../engine.zig").CliOptions {
    var options = @import("../engine.zig").CliOptions{
        .model = "claude-sonnet-4-20250514",
        .max_tokens = 4096,
        .temperature = 0.7,
        .stream = true,
        .verbose = false,
    };

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--model") or std.mem.eql(u8, arg, "-m")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            options.model = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--max-tokens")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            options.max_tokens = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--temperature") or std.mem.eql(u8, arg, "-t")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            options.temperature = try std.fmt.parseFloat(f32, args[i]);
        } else if (std.mem.eql(u8, arg, "--no-stream")) {
            options.stream = false;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "--input") or std.mem.eql(u8, arg, "-i")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            options.input = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            options.output = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--history")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            options.history = try allocator.dupe(u8, args[i]);
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            // Positional argument (input text)
            options.input = try allocator.dupe(u8, arg);
        }
    }

    return options;
}

/// Clean up allocated strings in run options
fn cleanupRunOptions(allocator: std.mem.Allocator, options: *@import("../engine.zig").CliOptions) void {
    if (options.model.len > 0 and options.model.ptr != @import("foundation/engine.zig").CliOptions{}.model.ptr) {
        allocator.free(options.model);
    }
    if (options.input) |input| allocator.free(input);
    if (options.output) |output| allocator.free(output);
    if (options.history) |history| allocator.free(history);
}

/// Helper functions for parsing arguments
fn hasFlag(args: [][]const u8, flag: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, flag)) return true;
    }
    return false;
}

fn getPortArg(args: [][]const u8) ?u16 {
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--port")) {
            if (i + 1 < args.len) {
                const port_str = args[i + 1];
                if (std.fmt.parseInt(u16, port_str, 10)) |port| {
                    return port;
                } else |_| {
                    return null; // Invalid port number
                }
            }
            return null; // No port value provided
        }
    }
    return null;
}

fn getStringArg(args: [][]const u8, flag: []const u8) ?[]const u8 {
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, flag)) {
            if (i + 1 < args.len) {
                return args[i + 1];
            }
            return null; // No value provided
        }
    }
    return null;
}
}

// Clean up interactive options memory
fn cleanupInteractiveOptions(allocator: std.mem.Allocator, options: *InteractiveCliOptions) void {
    // Cleanup removed - base field no longer exists
    if (options.session.title) |title| {
        allocator.free(title);
    }
    if (options.session.savePath) |path| {
        allocator.free(path);
    }
}

// Handle special modes that don't require full engine execution
fn handleSpecialModes(allocator: std.mem.Allocator, options: InteractiveCliOptions) !bool {
    // Handle authentication setup
    if (options.auth.setup or options.auth.forceOauth) {
        try setupAuthenticationFlow(allocator, options.auth.forceOauth);
        return true;
    }

    // Handle interactive help
    if (options.interactive.showHelp) {
        try showInteractiveHelp();
        return true;
    }

    return false;
}

// Setup authentication flow with user guidance
fn setupAuthenticationFlow(allocator: std.mem.Allocator, forceOauth: bool) !void {
    std.log.info("🔐 Starting Authentication Setup", .{});

    if (forceOauth) {
        std.log.info("🔄 Forcing OAuth setup...", .{});
        // TODO: Call setupOauth through auth module
        // try auth.setupOauth(allocator);
        return;
    }

    // Check current auth status
    const authStatus = try agent_base.AuthHelpers.getStatusText(allocator);
    defer allocator.free(authStatus);

    std.log.info("📊 Current authentication status: {s}", .{authStatus});

    // Offer setup options
    const hasOauth = agent_base.AuthHelpers.hasValidOauth(allocator);
    const hasApiKey = agent_base.AuthHelpers.hasValidApiKey(allocator);

    if (!hasOauth and !hasApiKey) {
        std.log.info("❌ No authentication method configured.", .{});
        std.log.info("🔧 Available options:", .{});
        std.log.info("  1. Setup OAuth (Claude Pro/Max) - Recommended", .{});
        std.log.info("  2. Configure API Key", .{});

        const stdin = std.fs.File.stdin();
        var buffer: [10]u8 = undefined;

        std.log.info("Choose an option (1 or 2): ", .{});
        const bytesRead = try stdin.read(&buffer);
        const choice = std.mem.trim(u8, buffer[0..bytesRead], " \t\r\n");

        if (std.mem.eql(u8, choice, "1")) {
            _ = try auth.setupOAuth(allocator);
        } else if (std.mem.eql(u8, choice, "2")) {
            std.log.info("📝 To configure an API key:", .{});
            std.log.info("  1. Get your API key from: https://console.anthropic.com/", .{});
            std.log.info("  2. Set the ANTHROPIC_API_KEY environment variable", .{});
            std.log.info("  3. Or use: export ANTHROPIC_API_KEY='your-api-key-here'", .{});
        } else {
            std.log.err("❌ Invalid choice. Please run setup again.", .{});
            return error.InvalidChoice;
        }
    } else {
        std.log.info("✅ Authentication is already configured!", .{});
        if (hasOauth) {
            std.log.info("🔐 Using OAuth authentication (Claude Pro/Max)", .{});
        } else {
            std.log.info("🔑 Using API key authentication", .{});
        }
    }
}

/// Show interactive help system
fn showInteractiveHelp() !void {
    const helpText =
        \\🤖 Interactive Mode Help
        \\
        \\Interactive mode provides a rich terminal experience with:
        \\  • Multi-turn conversations with context preservation
        \\  • Rich TUI interface with graphics and mouse support
        \\  • Real-time statistics and progress indicators
        \\  • Session management and history
        \\  • Authentication flows
        \\
        \\🎮 Available Commands:
        \\  help        - Show this help message
        \\  status       - Show session statistics
        \\  clear       - Clear the screen
        \\  exit/quit   - End the session
        \\  save        - Save current session
        \\  load        - Load a previous session
        \\
        \\🔧 Interactive Mode Options:
        \\  --tui=rich      - Force rich TUI mode with full graphics
        \\  --tui=minimal   - Use minimal TUI mode with limited graphics
        \\  --tui=auto      - Auto-detect terminal capabilities (default)
        \\  --dashboard     - Enable interactive dashboard
        \\  --no-progress   - Disable progress indicators
        \\  --session-title - Set custom session title
        \\  --save-session  - Save session to file
        \\
        \\🔐 Auth Commands:
        \\  auth login   - Start OAuth setup in browser
        \\  auth status  - Show authentication status
        \\  auth refresh - Refresh OAuth tokens
        \\
        \\🎯 Getting Started:
        \\  1. Run with --interactive flag: agent --interactive
        \\  2. Choose your preferred TUI mode: --tui=rich
        \\  3. Or use dashboard mode: --dashboard --interactive
        \\  4. Start chatting with the AI
        \\  5. Use Ctrl+C to exit gracefully
        \\
        \\💡 Tips:
        \\  • Use mouse to interact with UI elements in rich mode
        \\  • Press Tab for auto-completion
        \\  • Use Ctrl+Enter for multi-line input
        \\  • Sessions are automatically saved on exit
        \\
    ;

    std.log.info("{s}", .{helpText});
}

/// Run interactive mode with session support
fn runInteractiveMode(allocator: std.mem.Allocator, options: InteractiveCliOptions) !void {
    // Create session configuration
    const sessionConfig = session.InteractiveConfig{
        .interactive = true,
        .enableTui = switch (options.tui.mode) {
            .rich, .minimal => true,
            .none, .auto => false,
        },
        .enableDashboard = options.tui.dashboard,
        .enableAuth = true,
        .title = options.session.title orelse "AI Agent Interactive Session",
        .inputLengthMax = 4096,
        .multiLine = true,
        .showStats = true,
    };

    // Initialize base agent for authentication and session management
    var baseAgent = agent_base.Agent.init(allocator);
    defer baseAgent.deinit();

    // Setup authentication
    try ensureAuthentication(&baseAgent);

    // Enable interactive mode on base agent
    try baseAgent.enableInteractiveMode(sessionConfig);

    // Start the main interaction loop
    try baseAgent.startInteractiveSession();
}

/// Ensure authentication is properly configured
fn ensureAuthentication(baseAgent: *agent_base.Agent) !void {
    const authStatus = try baseAgent.authStatus();

    switch (authStatus) {
        .none => {
            std.log.info("🔐 No authentication configured. Starting setup...", .{});
            try baseAgent.setupOauth();
        },
        .oauth => {
            std.log.info("🔐 Using OAuth authentication (Claude Pro/Max)", .{});
        },
        .api_key => {
            std.log.info("🔑 Using API key authentication", .{});
        },
    }
}

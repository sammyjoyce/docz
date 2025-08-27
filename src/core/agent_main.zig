//! Agent main entry point with CLI parsing and agent orchestration.
//! Provides common CLI parsing, argument handling, and engine delegation.
//!
//! This module focuses on core agent functionality without forcing UI dependencies.
//! Theme and UX framework integration is available through optional imports.

const std = @import("std");
const engine = @import("engine_shared");
const session = @import("interactive_session");
const auth = @import("auth_shared");
const agent_base = @import("agent_base");

const CliOptions = engine.CliOptions;

/// Interactive CLI options for interactive and TUI modes
pub const InteractiveCliOptions = struct {
    /// Base CLI options
    base: CliOptions,
    /// Interactive mode settings
    interactive: InteractiveOptions,
    /// TUI mode settings
    tui: TuiOptions,
    /// Authentication settings
    auth: AuthOptions,
    /// Session management
    session: SessionOptions,
};

/// Interactive mode configuration
pub const InteractiveOptions = struct {
    /// Enable interactive mode
    enabled: bool = false,
    /// Interactive help system
    showHelp: bool = false,
    /// Continue previous session
    continueSession: bool = false,
};

/// TUI mode configuration
pub const TuiOptions = struct {
    /// TUI mode selection
    mode: TuiMode = .auto,
    /// Enable dashboard
    dashboard: bool = false,
    /// Enable progress indicators
    progress: bool = true,
};

/// Authentication configuration
pub const AuthOptions = struct {
    /// Setup authentication
    setup: bool = false,
    /// Force OAuth setup
    forceOauth: bool = false,
};

/// Session management options
pub const SessionOptions = struct {
    /// Session title
    title: ?[]const u8 = null,
    /// Session save path
    savePath: ?[]const u8 = null,
};

/// TUI mode enumeration
pub const TuiMode = enum {
    /// Auto-detect based on terminal capabilities
    auto,
    /// Rich TUI with full graphics support
    rich,
    /// Minimal TUI with limited graphics
    minimal,
    /// Disable TUI (CLI only)
    none,
};

/// Check if a flag is present in the command line arguments
fn hasFlag(args: [][]const u8, flag: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, flag)) {
            return true;
        }
    }
    return false;
}

/// Launch the agent launcher interface
fn launchAgentLauncher(allocator: std.mem.Allocator, args: [][]const u8) !void {
    _ = allocator;
    _ = args;
    return;
}

/// Main function for agents with TUI and interactive support.
/// Agents should call this from their main.zig with their specific spec.
pub fn runAgent(allocator: std.mem.Allocator, spec: engine.AgentSpec) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cliArgs = if (args.len > 1) args[1..] else args[0..0];

    // Convert [][:0]u8 to [][]const u8
    const cliArgsConst = try allocator.alloc([]const u8, cliArgs.len);
    defer allocator.free(cliArgsConst);
    for (cliArgs, 0..) |arg, i| {
        cliArgsConst[i] = std.mem.sliceTo(arg, 0);
    }

    // Quick routing for explicit subcommands (e.g., `auth login`)
    if (cliArgsConst.len > 0 and std.mem.eql(u8, cliArgsConst[0], "auth")) {
        const sub = if (cliArgsConst.len > 1) cliArgsConst[1] else "login";
        if (std.mem.eql(u8, sub, "login") or std.mem.eql(u8, sub, "oauth")) {
            // Start OAuth login via CLI presenter
            try auth.handleLoginCommand(allocator);
            return;
        } else if (std.mem.eql(u8, sub, "status")) {
            try auth.handleStatusCommand(allocator);
            return;
        } else if (std.mem.eql(u8, sub, "refresh")) {
            try auth.handleRefreshCommand(allocator);
            return;
        } else {
            std.log.err("Unknown auth subcommand: {s}", .{sub});
            std.log.info("Available: login | status | refresh", .{});
            return error.InvalidChoice;
        }
    }

    // Check if launcher mode is requested (no arguments or --launcher flag)
    const shouldLaunchLauncher = cliArgsConst.len == 0 or
        hasFlag(cliArgsConst, "--launcher") or
        hasFlag(cliArgsConst, "--agents") or
        hasFlag(cliArgsConst, "--list-agents");

    // In minimal builds, skip interactive launcher to reduce dependencies
    _ = shouldLaunchLauncher;

    // Parse interactive CLI arguments
    var interactiveOptions = try parseInteractiveArgs(allocator, cliArgsConst);
    defer cleanupInteractiveOptions(allocator, &interactiveOptions);

    // Handle special modes that don't require the full engine
    if (try handleSpecialModes(allocator, interactiveOptions)) {
        return;
    }

    // Check if interactive mode is requested
    if (interactiveOptions.interactive.enabled) {
        try runInteractiveMode(allocator, interactiveOptions);
        return;
    }

    // Fall back to standard engine execution
    if (engine.runWithOptions(allocator, interactiveOptions.base, spec)) {
        // done
    } else |err| {
        // Clear, actionable error handling for common cases
        if (err == error.MissingAPIKey) {
            std.log.warn("No authentication configured.", .{});
            std.log.info("Run 'docz auth login' or set ANTHROPIC_API_KEY.", .{});
            return err;
        }
        if (err == error.AuthError) {
            std.log.err("Authentication failed (unauthorized). Check your API key or OAuth session.", .{});
            std.log.info("Try: 'docz auth status' or re-auth with 'docz auth login'", .{});
            return err;
        }
        if (err == error.APIError) {
            std.log.err("API request failed. Verify model, quotas, and credentials.", .{});
            std.log.info("Inspect logs above; try --verbose for more detail.", .{});
            return err;
        }
        return err;
    }
}

/// Parse interactive CLI arguments with TUI and interactive support
fn parseInteractiveArgs(allocator: std.mem.Allocator, args: [][]const u8) !InteractiveCliOptions {
    var interactive = InteractiveCliOptions{
        .base = CliOptions{
            .options = .{
                .model = undefined,
                .output = null,
                .input = null,
                .system = null,
                .config = null,
                .tokensMax = 4096,
                .temperature = 0.7,
            },
            .flags = .{
                .verbose = false,
                .help = false,
                .version = false,
                .stream = true,
                .pretty = false,
                .debug = false,
                .interactive = false,
            },
            .positionals = null,
        },
        .interactive = .{},
        .tui = .{},
        .auth = .{},
        .session = .{},
    };

    // Parse CLI options manually
    var parsedArgs = CliOptions{
        .options = .{
            .model = "claude-3-sonnet-20240229",
            .output = null,
            .input = null,
            .system = null,
            .config = null,
            .tokensMax = 4096,
            .temperature = 0.7,
        },
        .flags = .{
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

    // Argument parsing
    var argIdx: usize = 0;
    while (argIdx < args.len) {
        const arg = args[argIdx];
        if (std.mem.eql(u8, arg, "--model") or std.mem.eql(u8, arg, "-m")) {
            argIdx += 1;
            if (argIdx >= args.len) return error.MissingValue;
            parsedArgs.options.model = try allocator.dupe(u8, args[argIdx]);
        } else if (std.mem.eql(u8, arg, "--max-tokens")) {
            argIdx += 1;
            if (argIdx >= args.len) return error.MissingValue;
            parsedArgs.options.tokensMax = try std.fmt.parseInt(u32, args[argIdx], 10);
        } else if (std.mem.eql(u8, arg, "--temperature") or std.mem.eql(u8, arg, "-t")) {
            argIdx += 1;
            if (argIdx >= args.len) return error.MissingValue;
            parsedArgs.options.temperature = try std.fmt.parseFloat(f32, args[argIdx]);
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            parsedArgs.flags.verbose = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            parsedArgs.flags.help = true;
        } else if (std.mem.eql(u8, arg, "--version")) {
            parsedArgs.flags.version = true;
        } else if (std.mem.eql(u8, arg, "--no-stream")) {
            parsedArgs.flags.stream = false;
        } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            argIdx += 1;
            if (argIdx >= args.len) return error.MissingValue;
            parsedArgs.options.output = try allocator.dupe(u8, args[argIdx]);
        } else if (std.mem.eql(u8, arg, "--input") or std.mem.eql(u8, arg, "-i")) {
            argIdx += 1;
            if (argIdx >= args.len) return error.MissingValue;
            parsedArgs.options.input = try allocator.dupe(u8, args[argIdx]);
        } else if (std.mem.eql(u8, arg, "--system")) {
            argIdx += 1;
            if (argIdx >= args.len) return error.MissingValue;
            parsedArgs.options.system = try allocator.dupe(u8, args[argIdx]);
        } else if (arg.len > 0 and arg[0] != '-') {
            // Positional argument (prompt)
            parsedArgs.positionals = try allocator.dupe(u8, arg);
        }
        argIdx += 1;
    }

    // Copy parsed options to interactive structure
    interactive.base.options.model = parsedArgs.options.model;
    interactive.base.options.tokensMax = parsedArgs.options.tokensMax;
    interactive.base.options.temperature = parsedArgs.options.temperature;
    interactive.base.flags.verbose = parsedArgs.flags.verbose;
    interactive.base.flags.help = parsedArgs.flags.help;
    interactive.base.flags.version = parsedArgs.flags.version;
    interactive.base.flags.stream = parsedArgs.flags.stream;
    interactive.base.positionals = parsedArgs.positionals;

    // Parse additional interactive options
    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--interactive") or std.mem.eql(u8, arg, "-i")) {
            interactive.interactive.enabled = true;
        } else if (std.mem.eql(u8, arg, "--interactive-help")) {
            interactive.interactive.showHelp = true;
        } else if (std.mem.eql(u8, arg, "--continue-session")) {
            interactive.interactive.continueSession = true;
        } else if (std.mem.startsWith(u8, arg, "--tui=")) {
            const modeStr = arg[6..];
            interactive.tui.mode = std.meta.stringToEnum(TuiMode, modeStr) orelse .auto;
        } else if (std.mem.eql(u8, arg, "--tui")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            interactive.tui.mode = std.meta.stringToEnum(TuiMode, args[i]) orelse .auto;
        } else if (std.mem.eql(u8, arg, "--dashboard") or std.mem.eql(u8, arg, "-d")) {
            interactive.tui.dashboard = true;
        } else if (std.mem.eql(u8, arg, "--no-progress")) {
            interactive.tui.progress = false;
        } else if (std.mem.eql(u8, arg, "--auth") or std.mem.eql(u8, arg, "--setup-auth")) {
            interactive.auth.setup = true;
        } else if (std.mem.eql(u8, arg, "--force-oauth")) {
            interactive.auth.forceOauth = true;
        } else if (std.mem.startsWith(u8, arg, "--session-title=")) {
            interactive.session.title = try allocator.dupe(u8, arg[16..]);
        } else if (std.mem.eql(u8, arg, "--session-title")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            interactive.session.title = try allocator.dupe(u8, args[i]);
        } else if (std.mem.startsWith(u8, arg, "--save-session=")) {
            interactive.session.savePath = try allocator.dupe(u8, arg[15..]);
        } else if (std.mem.eql(u8, arg, "--save-session")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            interactive.session.savePath = try allocator.dupe(u8, args[i]);
        }

        i += 1;
    }

    return interactive;
}

/// Clean up interactive options memory
fn cleanupInteractiveOptions(allocator: std.mem.Allocator, options: *InteractiveCliOptions) void {
    if (options.base.positionals) |p| {
        allocator.free(p);
        options.base.positionals = null;
    }
    if (options.session.title) |title| {
        allocator.free(title);
    }
    if (options.session.savePath) |path| {
        allocator.free(path);
    }
}

/// Handle special modes that don't require full engine execution
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

/// Setup authentication flow with user guidance
fn setupAuthenticationFlow(allocator: std.mem.Allocator, forceOauth: bool) !void {
    std.log.info("🔐 Starting Authentication Setup", .{});

    if (forceOauth) {
        std.log.info("🔄 Forcing OAuth setup...", .{});
        try engine.setupOauth(allocator);
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
    const authStatus = try baseAgent.checkAuthStatus();

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

//! Agent main entry point with CLI parsing and basic agent orchestration.
//! Provides common CLI parsing, argument handling, and engine delegation.
//!
//! This module focuses on core agent functionality without forcing UI dependencies.
//! Theme and UX framework integration is available through optional imports.

const std = @import("std");
const engine = @import("engine_shared");
const session = @import("interactive_session");
const auth = @import("auth_shared");
const agent_base = @import("agent_base");
const interactive_session = @import("interactive_session");

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
    show_help: bool = false,
    /// Continue previous session
    continue_session: bool = false,
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
    force_oauth: bool = false,
};

/// Session management options
pub const SessionOptions = struct {
    /// Session title
    title: ?[]const u8 = null,
    /// Session save path
    save_path: ?[]const u8 = null,
};

/// TUI mode enumeration
pub const TuiMode = enum {
    /// Auto-detect based on terminal capabilities
    auto,
    /// Rich TUI with full graphics support
    rich,
    /// Basic TUI with limited graphics
    basic,
    /// Disable TUI (CLI only)
    none,
};

/// Check if a flag is present in the command line arguments
fn has_flag(args: [][]const u8, flag: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, flag)) {
            return true;
        }
    }
    return false;
}

/// Launch the agent launcher interface
fn launch_agent_launcher(allocator: std.mem.Allocator, args: [][]const u8) !void {
    _ = allocator;
    _ = args;
    return;
}

/// Main function for agents with TUI and interactive support.
/// Agents should call this from their main.zig with their specific spec.
pub fn run_agent(allocator: std.mem.Allocator, spec: engine.AgentSpec) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cliArgs = if (args.len > 1) args[1..] else args[0..0];

    // Convert [][:0]u8 to [][]const u8
    const cliArgsConst = try allocator.alloc([]const u8, cliArgs.len);
    defer allocator.free(cliArgsConst);
    for (cliArgs, 0..) |arg, i| {
        cliArgsConst[i] = std.mem.sliceTo(arg, 0);
    }

    // Check if launcher mode is requested (no arguments or --launcher flag)
    const should_launch_launcher = cliArgsConst.len == 0 or
        has_flag(cliArgsConst, "--launcher") or
        has_flag(cliArgsConst, "--agents") or
        has_flag(cliArgsConst, "--list-agents");

    // In minimal builds, skip interactive launcher to reduce dependencies
    _ = should_launch_launcher;

    // Parse interactive CLI arguments
    const interactive_options = try parse_interactive_args(allocator, cliArgsConst);
    defer cleanup_interactive_options(allocator, &interactive_options);

    // Handle special modes that don't require the full engine
    if (try handle_special_modes(allocator, interactive_options)) {
        return;
    }

    // Check if interactive mode is requested
    if (interactive_options.interactive.enabled) {
        try run_interactive_mode(allocator, interactive_options);
        return;
    }

    // Fall back to standard engine execution
    try engine.run_with_options(allocator, interactive_options.base, spec);
}

/// Parse interactive CLI arguments with TUI and interactive support
fn parse_interactive_args(allocator: std.mem.Allocator, args: [][]const u8) !InteractiveCliOptions {
    var interactive = InteractiveCliOptions{
        .base = CliOptions{
            .options = .{
                .model = undefined,
                .output = null,
                .input = null,
                .system = null,
                .config = null,
                .max_tokens = 4096,
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

    // Parse basic CLI options manually
    var parsed_args = CliOptions{
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

    // Simple argument parsing
    var arg_idx: usize = 0;
    while (arg_idx < args.len) {
        const arg = args[arg_idx];
        if (std.mem.eql(u8, arg, "--model") or std.mem.eql(u8, arg, "-m")) {
            arg_idx += 1;
            if (arg_idx >= args.len) return error.MissingValue;
            parsed_args.options.model = try allocator.dupe(u8, args[arg_idx]);
        } else if (std.mem.eql(u8, arg, "--max-tokens")) {
            arg_idx += 1;
            if (arg_idx >= args.len) return error.MissingValue;
            parsed_args.options.max_tokens = try std.fmt.parseInt(u32, args[arg_idx], 10);
        } else if (std.mem.eql(u8, arg, "--temperature") or std.mem.eql(u8, arg, "-t")) {
            arg_idx += 1;
            if (arg_idx >= args.len) return error.MissingValue;
            parsed_args.options.temperature = try std.fmt.parseFloat(f32, args[arg_idx]);
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            parsed_args.flags.verbose = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            parsed_args.flags.help = true;
        } else if (std.mem.eql(u8, arg, "--version")) {
            parsed_args.flags.version = true;
        } else if (std.mem.eql(u8, arg, "--no-stream")) {
            parsed_args.flags.stream = false;
        } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            arg_idx += 1;
            if (arg_idx >= args.len) return error.MissingValue;
            parsed_args.options.output = try allocator.dupe(u8, args[arg_idx]);
        } else if (std.mem.eql(u8, arg, "--input") or std.mem.eql(u8, arg, "-i")) {
            arg_idx += 1;
            if (arg_idx >= args.len) return error.MissingValue;
            parsed_args.options.input = try allocator.dupe(u8, args[arg_idx]);
        } else if (std.mem.eql(u8, arg, "--system")) {
            arg_idx += 1;
            if (arg_idx >= args.len) return error.MissingValue;
            parsed_args.options.system = try allocator.dupe(u8, args[arg_idx]);
        } else if (arg.len > 0 and arg[0] != '-') {
            // Positional argument (prompt)
            parsed_args.positionals = try allocator.dupe(u8, arg);
        }
        arg_idx += 1;
    }

    // Copy parsed options to interactive structure
    interactive.base.options.model = parsed_args.options.model;
    interactive.base.options.max_tokens = parsed_args.options.max_tokens;
    interactive.base.options.temperature = parsed_args.options.temperature;
    interactive.base.flags.verbose = parsed_args.flags.verbose;
    interactive.base.flags.help = parsed_args.flags.help;
    interactive.base.flags.version = parsed_args.flags.version;
    interactive.base.flags.stream = parsed_args.flags.stream;
    interactive.base.positionals = parsed_args.positionals;

    // Parse additional interactive options
    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--interactive") or std.mem.eql(u8, arg, "-i")) {
            interactive.interactive.enabled = true;
        } else if (std.mem.eql(u8, arg, "--interactive-help")) {
            interactive.interactive.show_help = true;
        } else if (std.mem.eql(u8, arg, "--continue-session")) {
            interactive.interactive.continue_session = true;
        } else if (std.mem.startsWith(u8, arg, "--tui=")) {
            const mode_str = arg[6..];
            interactive.tui.mode = std.meta.stringToEnum(TuiMode, mode_str) orelse .auto;
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
            interactive.auth.force_oauth = true;
        } else if (std.mem.startsWith(u8, arg, "--session-title=")) {
            interactive.session.title = try allocator.dupe(u8, arg[16..]);
        } else if (std.mem.eql(u8, arg, "--session-title")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            interactive.session.title = try allocator.dupe(u8, args[i]);
        } else if (std.mem.startsWith(u8, arg, "--save-session=")) {
            interactive.session.save_path = try allocator.dupe(u8, arg[15..]);
        } else if (std.mem.eql(u8, arg, "--save-session")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            interactive.session.save_path = try allocator.dupe(u8, args[i]);
        }

        i += 1;
    }

    return interactive;
}

/// Clean up interactive options memory
fn cleanup_interactive_options(allocator: std.mem.Allocator, options: *InteractiveCliOptions) void {
    if (options.session.title) |title| {
        allocator.free(title);
    }
    if (options.session.save_path) |path| {
        allocator.free(path);
    }
}

/// Handle special modes that don't require full engine execution
fn handle_special_modes(allocator: std.mem.Allocator, options: InteractiveCliOptions) !bool {
    // Handle authentication setup
    if (options.auth.setup or options.auth.force_oauth) {
        try setup_authentication_flow(allocator, options.auth.force_oauth);
        return true;
    }

    // Handle interactive help
    if (options.interactive.show_help) {
        try show_interactive_help();
        return true;
    }

    return false;
}

/// Setup authentication flow with user guidance
fn setup_authentication_flow(allocator: std.mem.Allocator, force_oauth: bool) !void {
    std.log.info("🔐 Starting Authentication Setup", .{});

    if (force_oauth) {
        std.log.info("🔄 Forcing OAuth setup...", .{});
        try engine.setup_oauth(allocator);
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
        const bytes_read = try stdin.read(&buffer);
        const choice = std.mem.trim(u8, buffer[0..bytes_read], " \t\r\n");

        if (std.mem.eql(u8, choice, "1")) {
            try engine.setupOauth(allocator);
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
fn show_interactive_help() !void {
    const help_text =
        \\🤖 Interactive Mode Help
        \\
        \\Interactive mode provides a rich terminal experience with:
        \\  • Multi-turn conversations with context preservation
        \\  • Rich TUI interface with graphics and mouse support
        \\  • Real-time statistics and progress indicators
        \\  • Session management and history
        \\  • Enhanced authentication flows
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
        \\  --tui=basic     - Use basic TUI mode with limited graphics
        \\  --tui=auto      - Auto-detect terminal capabilities (default)
        \\  --dashboard     - Enable interactive dashboard
        \\  --no-progress   - Disable progress indicators
        \\  --session-title - Set custom session title
        \\  --save-session  - Save session to file
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

    std.log.info("{s}", .{help_text});
}

/// Run interactive mode with basic session support
fn run_interactive_mode(allocator: std.mem.Allocator, options: InteractiveCliOptions) !void {
    // Create session configuration
    const session_config = session.SessionConfig{
        .interactive = true,
        .enable_tui = switch (options.tui.mode) {
            .rich, .basic => true,
            .none, .auto => false,
        },
        .enable_dashboard = options.tui.dashboard,
        .enable_auth = true,
        .title = options.session.title orelse "AI Agent Interactive Session",
        .max_input_length = 4096,
        .multi_line = true,
        .show_stats = true,
    };

    // Initialize base agent for authentication and session management
    var base_agent = agent_base.BaseAgent.init(allocator);
    defer base_agent.deinit();

    // Setup authentication
    try ensureAuthentication(&base_agent);

    // Enable interactive mode on base agent
    try base_agent.enableInteractiveMode(session_config);

    // Start the main interaction loop
    try base_agent.startInteractiveSession();
}

/// Ensure authentication is properly configured
fn ensureAuthentication(baseAgent: *agent_base.BaseAgent) !void {
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

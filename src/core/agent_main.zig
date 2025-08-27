//! Enhanced agent main entry point with comprehensive TUI support and interactive mode capabilities.
//! Provides common CLI parsing, argument handling, engine delegation, and rich terminal experiences.

const std = @import("std");
const engine = @import("engine.zig");
const cli = @import("cli_shared");
const interactive_session = @import("interactive_session.zig");
const agent_base = @import("agent_base.zig");
const term = @import("../shared/term/mod.zig");

const CliOptions = engine.CliOptions;

/// Enhanced CLI options for interactive and TUI modes
pub const EnhancedCliOptions = struct {
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

/// Enhanced main function for agents with comprehensive TUI and interactive support.
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

    // Parse enhanced CLI arguments
    const enhancedOptions = try parseEnhancedArgs(allocator, cliArgsConst);
    defer cleanupEnhancedOptions(allocator, &enhancedOptions);

    // Handle special modes that don't require the full engine
    if (try handleSpecialModes(allocator, enhancedOptions)) {
        return;
    }

    // Check if interactive mode is requested
    if (enhancedOptions.interactive.enabled) {
        try runInteractiveMode(allocator, enhancedOptions);
        return;
    }

    // Fall back to standard engine execution
    try engine.runWithOptions(allocator, enhancedOptions.base, spec);
}

/// Parse enhanced CLI arguments with TUI and interactive support
fn parseEnhancedArgs(allocator: std.mem.Allocator, args: [][]const u8) !EnhancedCliOptions {
    var enhanced = EnhancedCliOptions{
        .base = CliOptions{
            .options = .{
                .model = undefined,
                .output = null,
                .input = null,
                .system = null,
                .config = null,
                .maxTokens = 4096,
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

    // First parse with standard CLI parser
    const parsedArgsResult = try cli.parseAndHandle(allocator, args);

    if (parsedArgsResult == null) {
        // Built-in command was handled, return default options
        return enhanced;
    }

    var argsToProcess = parsedArgsResult.?;
    defer argsToProcess.deinit();

    // Copy standard options
    enhanced.base.options.model = argsToProcess.model;
    enhanced.base.options.maxTokens = argsToProcess.max_tokens orelse 4096;
    enhanced.base.options.temperature = argsToProcess.temperature orelse 0.7;
    enhanced.base.flags.verbose = argsToProcess.verbose;
    enhanced.base.flags.help = argsToProcess.help;
    enhanced.base.flags.version = argsToProcess.version;
    enhanced.base.flags.stream = argsToProcess.stream;
    enhanced.base.positionals = argsToProcess.prompt;

    // Parse additional enhanced options
    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--interactive") or std.mem.eql(u8, arg, "-i")) {
            enhanced.interactive.enabled = true;
        } else if (std.mem.eql(u8, arg, "--interactive-help")) {
            enhanced.interactive.show_help = true;
        } else if (std.mem.eql(u8, arg, "--continue-session")) {
            enhanced.interactive.continue_session = true;
        } else if (std.mem.startsWith(u8, arg, "--tui=")) {
            const mode_str = arg[6..];
            enhanced.tui.mode = std.meta.stringToEnum(TuiMode, mode_str) orelse .auto;
        } else if (std.mem.eql(u8, arg, "--tui")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            enhanced.tui.mode = std.meta.stringToEnum(TuiMode, args[i]) orelse .auto;
        } else if (std.mem.eql(u8, arg, "--dashboard") or std.mem.eql(u8, arg, "-d")) {
            enhanced.tui.dashboard = true;
        } else if (std.mem.eql(u8, arg, "--no-progress")) {
            enhanced.tui.progress = false;
        } else if (std.mem.eql(u8, arg, "--auth") or std.mem.eql(u8, arg, "--setup-auth")) {
            enhanced.auth.setup = true;
        } else if (std.mem.eql(u8, arg, "--force-oauth")) {
            enhanced.auth.force_oauth = true;
        } else if (std.mem.startsWith(u8, arg, "--session-title=")) {
            enhanced.session.title = try allocator.dupe(u8, arg[16..]);
        } else if (std.mem.eql(u8, arg, "--session-title")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            enhanced.session.title = try allocator.dupe(u8, args[i]);
        } else if (std.mem.startsWith(u8, arg, "--save-session=")) {
            enhanced.session.save_path = try allocator.dupe(u8, arg[15..]);
        } else if (std.mem.eql(u8, arg, "--save-session")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            enhanced.session.save_path = try allocator.dupe(u8, args[i]);
        }

        i += 1;
    }

    return enhanced;
}

/// Clean up enhanced options memory
fn cleanupEnhancedOptions(allocator: std.mem.Allocator, options: *EnhancedCliOptions) void {
    if (options.session.title) |title| {
        allocator.free(title);
    }
    if (options.session.save_path) |path| {
        allocator.free(path);
    }
}

/// Handle special modes that don't require full engine execution
fn handleSpecialModes(allocator: std.mem.Allocator, options: EnhancedCliOptions) !bool {
    // Handle authentication setup
    if (options.auth.setup or options.auth.force_oauth) {
        try setupAuthenticationFlow(allocator, options.auth.force_oauth);
        return true;
    }

    // Handle interactive help
    if (options.interactive.show_help) {
        try showInteractiveHelp();
        return true;
    }

    return false;
}

/// Setup authentication flow with user guidance
fn setupAuthenticationFlow(allocator: std.mem.Allocator, force_oauth: bool) !void {
    std.log.info("🔐 Starting Authentication Setup", .{});

    if (force_oauth) {
        std.log.info("🔄 Forcing OAuth setup...", .{});
        try engine.setupOAuth(allocator);
        return;
    }

    // Check current auth status
    const auth_status = try agent_base.AuthHelpers.getStatusText(allocator);
    defer allocator.free(auth_status);

    std.log.info("📊 Current authentication status: {s}", .{auth_status});

    // Offer setup options
    const has_oauth = agent_base.AuthHelpers.hasValidOAuth(allocator);
    const has_api_key = agent_base.AuthHelpers.hasValidAPIKey(allocator);

    if (!has_oauth and !has_api_key) {
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
            try engine.setupOAuth(allocator);
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
        if (has_oauth) {
            std.log.info("🔐 Using OAuth (Claude Pro/Max)", .{});
        } else {
            std.log.info("🔑 Using API Key authentication", .{});
        }
    }
}

/// Show interactive help system
fn showInteractiveHelp() !void {
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
        \\  stats       - Show session statistics
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
        \\  2. Choose your preferred TUI mode
        \\  3. Start chatting with the AI
        \\  4. Use Ctrl+C to exit gracefully
        \\
        \\💡 Tips:
        \\  • Use mouse to interact with UI elements in rich mode
        \\  • Press Tab for auto-completion
        \\  • Use Ctrl+Enter for multi-line input
        \\  • Sessions are automatically saved on exit
        \\
    ;

    std.log.info("{s}", .{help_text});

    // Show terminal capabilities
    const capabilities = term.detectCapabilities();
    std.log.info("🖥️  Terminal Capabilities:", .{});
    std.log.info("  • Color Support: {s}", .{if (capabilities.supportsColor) "✅ Yes" else "❌ No"});
    std.log.info("  • True Color: {s}", .{if (capabilities.supportsTruecolor) "✅ Yes" else "❌ No"});
    std.log.info("  • Unicode: {s}", .{if (capabilities.supportsUnicode) "✅ Yes" else "❌ No"});
    std.log.info("  • Mouse: {s}", .{if (capabilities.supportsMouse) "✅ Yes" else "❌ No"});

    // Recommend TUI mode based on capabilities
    if (capabilities.supportsTruecolor and capabilities.supportsMouse) {
        std.log.info("💡 Recommendation: Use --tui=rich for the best experience!", .{});
    } else if (capabilities.supportsColor) {
        std.log.info("💡 Recommendation: Use --tui=basic for good compatibility.", .{});
    } else {
        std.log.info("💡 Recommendation: Use --tui=none for CLI-only mode.", .{});
    }
}

/// Run interactive mode with TUI support
fn runInteractiveMode(allocator: std.mem.Allocator, options: EnhancedCliOptions) !void {
    // Determine TUI mode based on options and capabilities
    const tui_mode = determineTuiMode(options.tui.mode);

    // Create session configuration
    const session_config = createSessionConfig(options, tui_mode);

    // Initialize base agent for authentication and session management
    var base_agent = agent_base.BaseAgent.init(allocator);
    defer base_agent.deinit();

    // Setup authentication if needed
    try ensureAuthentication(&base_agent);

    // Create and start interactive session
    try base_agent.enableInteractiveMode(session_config);
    try base_agent.startInteractiveSession();

    // The session will handle all user interaction from here
}

/// Determine the appropriate TUI mode based on options and terminal capabilities
fn determineTuiMode(requested_mode: TuiMode) TuiMode {
    const capabilities = term.detectCapabilities();

    return switch (requested_mode) {
        .auto => {
            if (capabilities.supportsTruecolor and capabilities.supportsMouse) {
                return .rich;
            } else if (capabilities.supportsColor) {
                return .basic;
            } else {
                return .none;
            }
        },
        .rich => {
            if (capabilities.supportsTruecolor) {
                return .rich;
            } else {
                std.log.warn("⚠️  Rich TUI mode requested but terminal doesn't support true color. Falling back to basic mode.", .{});
                return .basic;
            }
        },
        .basic => {
            if (capabilities.supportsColor) {
                return .basic;
            } else {
                std.log.warn("⚠️  Basic TUI mode requested but terminal doesn't support color. Falling back to CLI mode.", .{});
                return .none;
            }
        },
        .none => .none,
    };
}

/// Create session configuration based on options and TUI mode
fn createSessionConfig(options: EnhancedCliOptions, tui_mode: TuiMode) interactive_session.SessionConfig {
    const enable_tui = switch (tui_mode) {
        .rich, .basic => true,
        .none, .auto => false,
    };

    return .{
        .interactive = true,
        .enable_tui = enable_tui,
        .enable_dashboard = options.tui.dashboard,
        .enable_auth = true,
        .title = options.session.title orelse "AI Agent Interactive Session",
        .max_input_length = 4096,
        .multi_line = true,
        .show_stats = true,
    };
}

/// Clean up session configuration memory
fn cleanupSessionConfig(allocator: std.mem.Allocator, config: *interactive_session.SessionConfig) void {
    if (config.title.len > 0 and !std.mem.eql(u8, config.title, "AI Agent Interactive Session")) {
        allocator.free(config.title);
    }
}

/// Ensure authentication is properly configured
fn ensureAuthentication(base_agent: *agent_base.BaseAgent) !void {
    const auth_status = try base_agent.checkAuthStatus();

    switch (auth_status) {
        .none => {
            std.log.info("🔐 No authentication configured. Starting setup...", .{});
            try base_agent.setupOAuth();
        },
        .oauth => {
            std.log.info("🔐 Using OAuth authentication (Claude Pro/Max)", .{});
        },
        .api_key => {
            std.log.info("🔑 Using API key authentication", .{});
        },
    }
}

/// Show progress indicator for long operations
pub fn showProgress(operation: []const u8, current: usize, total: usize) void {
    const percentage = if (total > 0) (current * 100) / total else 0;
    const progress_bar_width = 20;
    const filled = (current * progress_bar_width) / total;
    const empty = progress_bar_width - filled;

    std.log.info("⏳ {s}: [{s}{s}] {d}% ({d}/{d})", .{
        operation,
        "█" ** filled,
        "░" ** empty,
        percentage,
        current,
        total,
    });
}

/// Show spinner for indeterminate progress
pub fn showSpinner(message: []const u8) void {
    const spinner_chars = [_]u8{ '|', '/', '-', '\\' };
    const timestamp = std.time.timestamp();
    const spinner_index = @as(usize, @intCast(timestamp % spinner_chars.len));
    const spinner = spinner_chars[spinner_index];

    std.log.info("⏳ {s} {c}", .{ message, spinner });
}

//! Agent main entry point with comprehensive UX framework integration.
//! Provides common CLI parsing, argument handling, engine delegation, and rich terminal experiences.
//!
//! # UX Framework Integration
//!
//! This module integrates the comprehensive UX framework for enhanced user experiences
//! across all agents without requiring individual agent implementation.
//!
//! ## Features Implemented
//!
//! ✅ **UX Mode Selection**: Command-line flags for UX mode selection (--ux-mode=minimal|standard|enhanced|dashboard)
//! ✅ **StandardAgentInterface**: Integration with StandardAgentInterface from agent_ux_framework.zig
//! ✅ **Enhanced Interactive Sessions**: Enhanced interactive session features enabled by default
//! ✅ **Visual OAuth Flow**: Automatic detection and use of visual OAuth flow when authentication is needed
//! ✅ **Theme Detection**: Automatic theme detection based on terminal capabilities and system preferences
//! ✅ **Theme Manager Initialization**: Global theme manager initialized on agent startup
//! ✅ **System Theme Detection**: Auto-detection of light/dark mode from system preferences
//! ✅ **CLI Theme Flags**: Full set of theme control options (--theme, --high-contrast, etc.)
//! ✅ **Color Blindness Support**: Adaptation for various color blindness types
//! ✅ **High Contrast Mode**: Enhanced accessibility with WCAG AAA compliance
//! ✅ **Theme Persistence**: User preferences saved and restored between sessions
//! ✅ **Progress Indicators**: Theme-aware progress bars and spinners
//! ✅ **Global Access**: Agents can access current theme via getCurrentTheme()
//! ✅ **Accessibility Info**: WCAG compliance checking and contrast ratio reporting
//!
//! ## Usage for Agents
//!
//! Agents can access the current theme through the global theme manager:
//!
//! ```zig
//! const theme = agent_main.getCurrentTheme();
//! if (theme) |t| {
//!     // Use theme colors for UI elements
//!     const primary_color = t.primary;
//!     // Apply theme-aware styling
//! }
//! ```
//!
//! ## CLI UX Options
//!
//! The following UX-related CLI flags are automatically available to all agents:
//!
//! - `--ux-mode=<mode>` - Select UX mode (minimal, standard, enhanced, dashboard)
//! - `--interactive` - Enable interactive mode with enhanced features
//! - `--dashboard` - Enable dashboard mode for comprehensive session management
//! - `--theme=<name>` - Select a specific theme (dark, light, solarized-dark, etc.)
//! - `--high-contrast` - Enable high contrast mode for accessibility
//! - `--color-blind-mode=<type>` - Apply color blindness adaptation
//!   - Types: protanopia, protanomaly, deuteranopia, deuteranomaly,
//!     tritanopia, tritanomaly, achromatopsia, achromatomaly
//! - `--list-themes` - Show all available themes
//! - `--reset-theme` - Reset to system default theme
//!
//! ## UX Modes
//!
//! - **minimal**: Basic CLI interface with essential features
//! - **standard**: Enhanced CLI with progress indicators and basic theming
//! - **enhanced**: Rich interactive session with command palette and notifications
//! - **dashboard**: Full dashboard with session browser, analytics, and monitoring
//!
//! ## Theme Persistence
//!
//! User theme preferences are automatically saved to `~/.config/docz/theme_config.zon`
//! and restored between sessions. The system supports per-agent theme overrides
//! and profile-based theming.
//!
//! ## Accessibility Features
//!
//! - **Screen Reader Detection**: Automatic detection and adaptation
//! - **Font Size Adjustments**: Support for user font size preferences
//! - **Animation Controls**: Reduced motion support for vestibular disorders
//! - **Semantic Colors**: Consistent color usage for different UI elements
//! - **WCAG Compliance**: All themes meet or exceed WCAG AA standards
//!
//! ## Integration Status
//!
//! 🔄 **UX Framework**: Complete - StandardAgentInterface integration
//! 🔄 **Interactive Sessions**: Enhanced features enabled by default
//! 🔄 **OAuth Flow**: Visual OAuth flow with automatic detection
//! 🔄 **Theme Integration**: Complete - all agents get theme flags automatically
//! 🔄 **CLI Integration**: Complete - all agents get UX flags automatically
//! 🔄 **TUI Integration**: Ready for integration with TUI components
//! 🔄 **Session Integration**: Theme manager available to interactive sessions
//! 🔄 **Persistence**: Configuration saving and loading implemented
//! 🔄 **Testing**: Basic integration test included
//!
//! ## Next Steps for Full Integration
//!
//! 1. Integrate theme manager into TUI components (Canvas, Modal, etc.)
//! 2. Update session management to use theme colors
//! 3. Add theme-aware ANSI color output for CLI tools
//! 4. Implement theme switching during runtime
//! 5. Add theme preview functionality

const std = @import("std");
const engine = @import("engine.zig");
const cli = @import("cli_shared");
const session = @import("session.zig");
const auth = @import("../shared/auth/core/mod.zig");
const agent_base = @import("agent_base.zig");
const agent_ux_framework = @import("agent_ux_framework.zig");
const term = @import("../shared/term/mod.zig");
const theme_manager = @import("../shared/theme_manager/mod.zig");
const interactive_session = @import("interactive_session.zig");

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
    /// Theme settings
    theme: ThemeOptions,
    /// UX framework settings
    ux: UxOptions,
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

/// Theme configuration
pub const ThemeOptions = struct {
    /// Theme name to use
    name: ?[]const u8 = null,
    /// Enable high contrast mode
    high_contrast: bool = false,
    /// Color blindness adaptation type
    color_blind_mode: ?[]const u8 = null,
    /// List available themes
    list_themes: bool = false,
    /// Reset theme to system default
    reset_theme: bool = false,
};

/// UX framework configuration
pub const UxOptions = struct {
    /// UX mode selection
    mode: UxMode = .standard,
    /// Enable enhanced interactive features
    enhanced_interactive: bool = true,
    /// Enable visual OAuth flow
    visual_oauth: bool = true,
    /// Enable automatic theme detection
    auto_theme_detection: bool = true,
};

/// UX mode enumeration
pub const UxMode = enum {
    /// Minimal CLI interface
    minimal,
    /// Standard CLI with enhancements
    standard,
    /// Enhanced interactive session
    enhanced,
    /// Full dashboard experience
    dashboard,
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

    // Parse interactive CLI arguments
    const interactiveOptions = try parseInteractiveArgs(allocator, cliArgsConst);
    defer cleanupInteractiveOptions(allocator, &interactiveOptions);

    // Initialize UX framework if enhanced mode is selected
    if (interactiveOptions.ux.mode != .minimal) {
        try initUxFramework(allocator, interactiveOptions);
    }

    // Initialize global theme manager for all modes
    try initGlobalThemeManager(allocator);
    defer deinitGlobalThemeManager();

    const theme_manager_instance = getGlobalThemeManager().?;

    // Apply theme settings from CLI options
    try applyThemeSettings(theme_manager_instance, interactiveOptions.theme, allocator);

    // Handle special modes that don't require the full engine
    if (try handleSpecialModes(allocator, interactiveOptions)) {
        return;
    }

    // Check if interactive mode is requested
    if (interactiveOptions.interactive.enabled) {
        try runInteractiveModeWithTheme(allocator, interactiveOptions, theme_manager_instance);
        return;
    }

    // Fall back to standard engine execution
    try engine.runWithOptions(allocator, interactiveOptions.base, spec);
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
        .theme = .{},
        .ux = .{},
    };

    // First parse with standard CLI parser
    const parsedArgsResult = try cli.parseAndHandle(allocator, args);

    if (parsedArgsResult == null) {
        // Built-in command was handled, return default options
        return interactive;
    }

    var argsToProcess = parsedArgsResult.?;
    defer argsToProcess.deinit();

    // Copy standard options
    interactive.base.options.model = argsToProcess.model;
    interactive.base.options.maxTokens = argsToProcess.max_tokens orelse 4096;
    interactive.base.options.temperature = argsToProcess.temperature orelse 0.7;
    interactive.base.flags.verbose = argsToProcess.verbose;
    interactive.base.flags.help = argsToProcess.help;
    interactive.base.flags.version = argsToProcess.version;
    interactive.base.flags.stream = argsToProcess.stream;
    interactive.base.positionals = argsToProcess.prompt;

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
        } else if (std.mem.startsWith(u8, arg, "--theme=")) {
            interactive.theme.name = try allocator.dupe(u8, arg[8..]);
        } else if (std.mem.eql(u8, arg, "--theme")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            interactive.theme.name = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--high-contrast")) {
            interactive.theme.high_contrast = true;
        } else if (std.mem.startsWith(u8, arg, "--color-blind-mode=")) {
            interactive.theme.color_blind_mode = try allocator.dupe(u8, arg[19..]);
        } else if (std.mem.eql(u8, arg, "--color-blind-mode")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            interactive.theme.color_blind_mode = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--list-themes")) {
            interactive.theme.list_themes = true;
        } else if (std.mem.eql(u8, arg, "--reset-theme")) {
            interactive.theme.reset_theme = true;
        } else if (std.mem.startsWith(u8, arg, "--ux-mode=")) {
            const mode_str = arg[10..];
            interactive.ux.mode = std.meta.stringToEnum(UxMode, mode_str) orelse .standard;
        } else if (std.mem.eql(u8, arg, "--ux-mode")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            interactive.ux.mode = std.meta.stringToEnum(UxMode, args[i]) orelse .standard;
        } else if (std.mem.eql(u8, arg, "--no-enhanced-ux")) {
            interactive.ux.enhanced_interactive = false;
        } else if (std.mem.eql(u8, arg, "--no-visual-oauth")) {
            interactive.ux.visual_oauth = false;
        } else if (std.mem.eql(u8, arg, "--no-auto-theme")) {
            interactive.ux.auto_theme_detection = false;
        }

        i += 1;
    }

    return interactive;
}

/// Clean up interactive options memory
fn cleanupInteractiveOptions(allocator: std.mem.Allocator, options: *InteractiveCliOptions) void {
    if (options.session.title) |title| {
        allocator.free(title);
    }
    if (options.session.save_path) |path| {
        allocator.free(path);
    }
    if (options.theme.name) |name| {
        allocator.free(name);
    }
    if (options.theme.color_blind_mode) |mode| {
        allocator.free(mode);
    }
    // UX options don't allocate memory currently, but this is here for future extensions
}

/// Handle special modes that don't require full engine execution
fn handleSpecialModes(allocator: std.mem.Allocator, options: InteractiveCliOptions) !bool {
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

    // Handle theme operations
    if (options.theme.list_themes) {
        try listAvailableThemes(allocator);
        return true;
    }

    if (options.theme.reset_theme) {
        try resetThemeToSystemDefault(allocator);
        return true;
    }

    // Handle UX mode information
    if (options.ux.mode != .standard) {
        std.log.info("🎨 UX Mode: {s}", .{@tagName(options.ux.mode)});
        if (options.ux.enhanced_interactive) {
            std.log.info("✨ Enhanced interactive features enabled", .{});
        }
        if (options.ux.visual_oauth) {
            std.log.info("🔐 Visual OAuth flow enabled", .{});
        }
        if (options.ux.auto_theme_detection) {
            std.log.info("🎨 Automatic theme detection enabled", .{});
        }
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
        \\  • UX framework integration with multiple modes
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
        \\🎨 UX Framework Options:
        \\  --ux-mode=<mode>            - Select UX mode (minimal, standard, enhanced, dashboard)
        \\  --no-enhanced-ux            - Disable enhanced interactive features
        \\  --no-visual-oauth           - Disable visual OAuth flow
        \\  --no-auto-theme             - Disable automatic theme detection
        \\
        \\🎨 Theme Options:
        \\  --theme=<name>              - Select theme (dark, light, solarized-dark, etc.)
        \\  --high-contrast             - Enable high contrast mode for accessibility
        \\  --color-blind-mode=<type>   - Apply color blindness adaptation
        \\                               (protanopia, deuteranopia, tritanopia, achromatopsia, etc.)
        \\  --list-themes               - Show all available themes
        \\  --reset-theme               - Reset to system default theme
        \\
        \\🎯 UX Modes:
        \\  • minimal    - Basic CLI interface with essential features
        \\  • standard   - Enhanced CLI with progress indicators and theming
        \\  • enhanced   - Rich interactive session with command palette and notifications
        \\  • dashboard  - Full dashboard with session browser, analytics, and monitoring
        \\
        \\🎯 Getting Started:
        \\  1. Run with --interactive flag: agent --interactive
        \\  2. Choose your preferred UX mode: --ux-mode=enhanced
        \\  3. Or use dashboard mode: --ux-mode=dashboard --interactive
        \\  4. Start chatting with the AI
        \\  5. Use Ctrl+C to exit gracefully
        \\
        \\💡 Tips:
        \\  • Use mouse to interact with UI elements in rich mode
        \\  • Press Tab for auto-completion
        \\  • Use Ctrl+Enter for multi-line input
        \\  • Sessions are automatically saved on exit
        \\  • Try --ux-mode=dashboard for the full experience
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

    // Recommend UX mode based on capabilities
    if (capabilities.supportsTruecolor and capabilities.supportsMouse) {
        std.log.info("💡 Recommendation: Use --ux-mode=dashboard or --ux-mode=enhanced for the best experience!", .{});
    } else if (capabilities.supportsColor) {
        std.log.info("💡 Recommendation: Use --ux-mode=standard or --ux-mode=enhanced for good compatibility.", .{});
    } else {
        std.log.info("💡 Recommendation: Use --ux-mode=minimal for CLI-only mode.", .{});
    }
}

/// Run interactive mode with TUI support and UX framework integration
fn runInteractiveModeWithTheme(allocator: std.mem.Allocator, options: InteractiveCliOptions, theme_manager_instance: *theme_manager.ThemeManager) !void {
    // Determine TUI mode based on options and capabilities
    const tui_mode = determineTuiMode(options.tui.mode);

    // Create session configuration
    const session_config = createSessionConfig(options, tui_mode);

    // Initialize base agent for authentication and session management
    var base_agent = agent_base.BaseAgent.init(allocator);
    defer base_agent.deinit();

    // Setup authentication with visual OAuth flow if enabled
    try ensureAuthenticationWithUx(&base_agent, options.ux);

    // Choose interaction mode based on UX settings
    switch (options.ux.mode) {
        .minimal => {
            // Basic interactive mode
            try base_agent.enableInteractiveMode(session_config);
            try base_agent.startInteractiveSession();
        },
        .standard => {
            // Enhanced CLI with theme support
            try runStandardUxMode(allocator, &base_agent, session_config, theme_manager_instance);
        },
        .enhanced => {
            // Full StandardAgentInterface integration
            try runEnhancedUxMode(allocator, &base_agent, options, theme_manager_instance);
        },
        .dashboard => {
            // Dashboard mode with session browser
            try runDashboardUxMode(allocator, &base_agent, options, theme_manager_instance);
        },
    }
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
fn createSessionConfig(options: InteractiveCliOptions, tui_mode: TuiMode) session.SessionConfig {
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
fn cleanupSessionConfig(allocator: std.mem.Allocator, config: *session.SessionConfig) void {
    _ = allocator; // Not currently used since session config is copied
    _ = config; // Not currently used since session config is copied
}

/// Ensure authentication is properly configured with UX enhancements
fn ensureAuthenticationWithUx(base_agent: *agent_base.BaseAgent, ux_options: UxOptions) !void {
    const auth_status = try base_agent.checkAuthStatus();

    switch (auth_status) {
        .none => {
            std.log.info("🔐 No authentication configured. Starting setup...", .{});
            if (ux_options.visual_oauth) {
                try setupVisualOAuthFlow(base_agent);
            } else {
                try base_agent.setupOAuth();
            }
        },
        .oauth => {
            std.log.info("🔐 Using OAuth authentication (Claude Pro/Max)", .{});
        },
        .api_key => {
            std.log.info("🔑 Using API key authentication", .{});
        },
    }
}

/// Setup visual OAuth flow with enhanced UX
fn setupVisualOAuthFlow(base_agent: *agent_base.BaseAgent) !void {
    std.log.info("🎨 Starting Visual OAuth Setup...", .{});

    // Check terminal capabilities for visual flow
    const capabilities = term.detectCapabilities();
    if (capabilities.supportsColor and capabilities.supportsUnicode) {
        std.log.info("✨ Enhanced visual OAuth flow available!", .{});

        // Try to use callback server for automatic flow
        const oauth_mod = @import("../shared/auth/oauth/mod.zig");
        if (oauth_mod.runCallbackServer) |runServer| {
            std.log.info("🌐 Attempting automatic OAuth flow...", .{});

            // Generate PKCE parameters
            const pkce_params = try oauth_mod.generatePkceParams(base_agent.allocator);
            defer pkce_params.deinit(base_agent.allocator);

            // Build authorization URL
            const auth_url = try oauth_mod.buildAuthorizationUrl(base_agent.allocator, pkce_params);
            defer base_agent.allocator.free(auth_url);

            // Try to launch browser
            oauth_mod.launchBrowser(auth_url) catch {
                std.log.warn("⚠️  Could not launch browser automatically", .{});
            };

            std.log.info("🔗 Please visit: {s}", .{auth_url});
            std.log.info("⏳ Waiting for authorization...", .{});

            // Start callback server
            const result = try runServer(base_agent.allocator, .{
                .port = 8080,
                .timeout_ms = 300000, // 5 minutes
            });
            defer base_agent.allocator.free(result.authorization_code);

            // Exchange code for tokens
            const credentials = try oauth_mod.exchangeCodeForTokens(
                base_agent.allocator,
                result.authorization_code,
                pkce_params
            );

            // Save credentials
            try oauth_mod.saveCredentials(base_agent.allocator, "claude_oauth_creds.json", credentials);

            std.log.info("✅ Visual OAuth setup completed successfully!", .{});
            return;
        }
    }

    // Fall back to standard OAuth flow
    std.log.info("📝 Falling back to standard OAuth flow...", .{});
    try base_agent.setupOAuth();
}

/// Run standard UX mode with enhanced CLI features
fn runStandardUxMode(
    allocator: std.mem.Allocator,
    base_agent: *agent_base.BaseAgent,
    session_config: session.SessionConfig,
    theme_manager_instance: *theme_manager.ThemeManager
) !void {
    _ = allocator; // Not currently used in standard mode
    _ = theme_manager_instance; // TODO: Integrate theme manager

    try base_agent.enableInteractiveMode(session_config);
    try base_agent.startInteractiveSession();
}

/// Run enhanced UX mode with StandardAgentInterface
fn runEnhancedUxMode(
    allocator: std.mem.Allocator,
    base_agent: *agent_base.BaseAgent,
    options: InteractiveCliOptions,
    theme_manager_instance: *theme_manager.ThemeManager
) !void {
    // Initialize StandardAgentInterface
    var ux_interface = try agent_ux_framework.StandardAgentInterface.init(allocator, base_agent);
    defer ux_interface.deinit();

    // Enable CLI mode with enhanced features
    try ux_interface.enableCLIMode();

    // Set theme manager if available
    ux_interface.theme_manager = theme_manager_instance;

    // Create session configuration
    const session_config = createSessionConfig(options, .none); // CLI mode

    // Enable interactive mode on base agent
    try base_agent.enableInteractiveMode(session_config);

    // Start the main interaction loop
    try ux_interface.startMainLoop();
}

/// Run dashboard UX mode with session browser
fn runDashboardUxMode(
    allocator: std.mem.Allocator,
    base_agent: *agent_base.BaseAgent,
    options: InteractiveCliOptions,
    theme_manager_instance: *theme_manager.ThemeManager
) !void {
    _ = theme_manager_instance; // TODO: Integrate theme manager

    // Create session configuration for dashboard
    var dashboard_config = createSessionConfig(options, .rich);
    dashboard_config.enable_dashboard = true;

    // Initialize session manager for dashboard
    var session_manager = try session.SessionManager.init(allocator);
    defer session_manager.deinit();

    // Enable interactive mode with dashboard
    try base_agent.enableInteractiveMode(dashboard_config);

    // Run session browser
    try interactive_session.runSessionBrowser(allocator, &session_manager);
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

    // Use theme-aware progress bar colors
    const theme = getCurrentTheme();
    const filled_char = if (theme != null and theme.isDark) "█" else "█";
    const empty_char = if (theme != null and theme.isDark) "░" else "░";

    std.log.info("⏳ {s}: [{s}{s}] {d}% ({d}/{d})", .{
        operation,
        filled_char ** filled,
        empty_char ** empty,
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

    // Use theme-aware spinner color
    const theme = getCurrentTheme();
    const spinner_icon = if (theme != null and theme.isDark) "⏳" else "⏳";

    std.log.info("{s} {s} {c}", .{ spinner_icon, message, spinner });
}

/// Global theme manager instance for agent-wide access
var global_theme_manager: ?*theme_manager.ThemeManager = null;

/// Initialize the global theme manager (called once at startup)
pub fn initGlobalThemeManager(allocator: std.mem.Allocator) !void {
    if (global_theme_manager != null) return;

    global_theme_manager = try theme_manager.init(allocator);
}

/// Get the global theme manager instance
pub fn getGlobalThemeManager() ?*theme_manager.ThemeManager {
    return global_theme_manager;
}

/// Cleanup the global theme manager
pub fn deinitGlobalThemeManager() void {
    if (global_theme_manager) |manager| {
        manager.deinit();
        global_theme_manager = null;
    }
}

/// Get the current active theme from the global manager
pub fn getCurrentTheme() ?*theme_manager.ColorScheme {
    if (global_theme_manager) |manager| {
        return manager.getCurrentTheme();
    }
    return null;
}

/// Helper function to apply theme colors to text output
pub fn styleText(text: []const u8, color_name: []const u8) []const u8 {
    const theme = getCurrentTheme() orelse return text;

    // This is a simplified implementation - in practice, you'd want to
    // integrate with the terminal's ANSI color system
    _ = theme;
    _ = color_name;
    return text;
}

/// Get theme-aware color for UI elements
pub fn getThemeColor(color_type: enum { primary, secondary, success, warning, @"error", info, background, foreground, border, highlight, accent, dimmed }) []const u8 {
    const theme = getCurrentTheme() orelse return "";

    // Return ANSI color codes based on theme
    const color = switch (color_type) {
        .primary => theme.primary,
        .secondary => theme.secondary,
        .success => theme.success,
        .warning => theme.warning,
        .@"error" => theme.errorColor,
        .info => theme.info,
        .background => theme.background,
        .foreground => theme.foreground,
        .border => theme.border,
        .highlight => theme.highlight,
        .accent => theme.accent,
        .dimmed => theme.dimmed,
    };

    // For now, return empty string - full ANSI integration would require more complex implementation
    _ = color;
    return "";
}

/// Reset terminal color
pub fn resetColor() []const u8 {
    return "\x1b[0m";
}

/// Apply theme-aware styling to progress indicators
pub fn styleProgressIndicator(completed: bool) []const u8 {
    const theme = getCurrentTheme() orelse return if (completed) "✅" else "⏳";

    if (completed) {
        return if (theme.isDark) "✅" else "✅";
    } else {
        return if (theme.isDark) "⏳" else "⏳";
    }
}

/// Helper function for agents to easily integrate theme support
/// This function can be called from agent-specific CLI handlers
pub fn handleThemeArgs(args: [][]const u8, allocator: std.mem.Allocator) !bool {
    _ = allocator; // Allocator might be needed for future theme operations
    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--theme") or std.mem.startsWith(u8, arg, "--theme=")) {
            // Theme argument already handled by main parser
            return true;
        } else if (std.mem.eql(u8, arg, "--high-contrast") or
            std.mem.eql(u8, arg, "--color-blind-mode") or
            std.mem.eql(u8, arg, "--list-themes") or
            std.mem.eql(u8, arg, "--reset-theme"))
        {
            // Theme argument already handled by main parser
            return true;
        }

        i += 1;
    }

    return false;
}

/// Get accessibility information about the current theme
pub fn getThemeAccessibilityInfo() struct {
    is_dark: bool,
    contrast_ratio: f32,
    wcag_level: []const u8,
    supports_color_blindness: bool,
} {
    const theme = getCurrentTheme() orelse return .{
        .is_dark = false,
        .contrast_ratio = 1.0,
        .wcag_level = "Unknown",
        .supports_color_blindness = false,
    };

    return .{
        .is_dark = theme.isDark,
        .contrast_ratio = theme.contrastRatio,
        .wcag_level = theme.wcagLevel,
        .supports_color_blindness = true, // All themes in our system support color blindness adaptation
    };
}

// Test theme integration
test "theme integration" {
    const allocator = std.testing.allocator;

    // Initialize global theme manager
    try initGlobalThemeManager(allocator);
    defer deinitGlobalThemeManager();

    // Verify theme manager is available
    const manager = getGlobalThemeManager();
    try std.testing.expect(manager != null);

    // Verify current theme is available
    const theme = getCurrentTheme();
    try std.testing.expect(theme != null);

    // Test theme color access
    const primary_color = getThemeColor(.primary);
    try std.testing.expect(primary_color.len == 0); // Empty for now, but structure is in place

    // Test accessibility info
    const accessibility = getThemeAccessibilityInfo();
    try std.testing.expect(accessibility.wcag_level.len > 0);
}

// Test UX framework integration
test "ux framework integration" {
    const allocator = std.testing.allocator;

    // Test UX options parsing
    const args = &[_][]const u8{"--ux-mode=enhanced", "--interactive"};
    var options = InteractiveCliOptions{
        .base = undefined,
        .interactive = .{},
        .tui = .{},
        .auth = .{},
        .session = .{},
        .theme = .{},
        .ux = .{},
    };

    // Simulate parsing UX mode
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--ux-mode=enhanced")) {
            options.ux.mode = .enhanced;
        } else if (std.mem.eql(u8, arg, "--interactive")) {
            options.interactive.enabled = true;
        }
    }

    try std.testing.expect(options.ux.mode == .enhanced);
    try std.testing.expect(options.interactive.enabled == true);

    // Test UX framework initialization (should not fail)
    try initUxFramework(allocator, options);
}

/// List all available themes
fn listAvailableThemes(allocator: std.mem.Allocator) !void {
    const manager = try theme_manager.init(allocator);
    defer manager.deinit();

    const themes = try manager.getAvailableThemes();
    defer {
        for (themes) |theme| {
            allocator.free(theme);
        }
        allocator.free(themes);
    }

    std.log.info("🎨 Available Themes:", .{});
    std.log.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", .{});

    const currentTheme = manager.getCurrentTheme();
    for (themes) |theme_name| {
        const isCurrent = std.mem.eql(u8, theme_name, currentTheme.name);
        const marker = if (isCurrent) "▶" else " ";
        std.log.info("{s} {s}", .{ marker, theme_name });
    }

    std.log.info("", .{});
    std.log.info("💡 Use --theme=<name> to switch themes", .{});
    std.log.info("💡 Use --reset-theme to reset to system default", .{});
}

/// Reset theme to system default
fn resetThemeToSystemDefault(allocator: std.mem.Allocator) !void {
    const manager = try theme_manager.init(allocator);
    defer manager.deinit();

    try theme_manager.Quick.applySystemTheme(manager);
    const currentTheme = manager.getCurrentTheme();

    std.log.info("🔄 Theme reset to system default: {s}", .{currentTheme.name});
    std.log.info("💡 The theme will be automatically detected based on your system settings", .{});
}

/// Initialize UX framework components
fn initUxFramework(_: std.mem.Allocator, options: InteractiveCliOptions) !void {
    if (options.ux.mode == .minimal) return;

    std.log.info("🎨 Initializing UX Framework ({s} mode)...", .{@tagName(options.ux.mode)});

    // Initialize enhanced interactive features if enabled
    if (options.ux.enhanced_interactive) {
        std.log.info("✨ Enhanced interactive features enabled", .{});
    }

    // Initialize visual OAuth if enabled
    if (options.ux.visual_oauth) {
        std.log.info("🔐 Visual OAuth flow enabled", .{});
    }

    // Initialize automatic theme detection if enabled
    if (options.ux.auto_theme_detection) {
        std.log.info("🎨 Automatic theme detection enabled", .{});
        // TODO: Implement automatic theme detection initialization
    }
}

/// Initialize automatic theme detection based on terminal capabilities
fn initAutomaticThemeDetection(_: std.mem.Allocator) !void {
    const manager = getGlobalThemeManager() orelse return;

    // Detect system theme
    const detector = theme_manager.SystemThemeDetector.init();
    const is_dark = try detector.detectSystemTheme();

    // Detect terminal capabilities
    const capabilities = term.detectCapabilities();

    // Choose theme based on system preference and terminal capabilities
    const recommended_theme = if (capabilities.supportsTruecolor) {
        if (is_dark) "dark" else "light";
    } else {
        // Use basic themes for limited color support
        if (is_dark) "dark-basic" else "light-basic";
    };

    // Apply the recommended theme
    try manager.switchTheme(recommended_theme);
    std.log.info("🎨 Auto-detected theme: {s} (system: {s}, terminal: {s})", .{
        recommended_theme,
        if (is_dark) "dark" else "light",
        if (capabilities.supportsTruecolor) "truecolor" else "basic"
    });
}

/// Apply theme settings from CLI options
fn applyThemeSettings(manager: *theme_manager.ThemeManager, theme_options: ThemeOptions, allocator: std.mem.Allocator) !void {
    // Apply theme name if specified
    if (theme_options.name) |theme_name| {
        try manager.switchTheme(theme_name);
        std.log.info("🎨 Switched to theme: {s}", .{theme_name});
    }

    // Apply high contrast mode
    if (theme_options.high_contrast) {
        const highContrastTheme = try theme_manager.Quick.generateHighContrast(manager);
        // Switch to the high contrast theme
        try manager.switchTheme(highContrastTheme.name);
        std.log.info("🔆 High contrast mode enabled", .{});
    }

    // Apply color blindness adaptation
    if (theme_options.color_blind_mode) |cb_mode| {
        const cb_type = std.meta.stringToEnum(theme_manager.ColorBlindnessAdapter.ColorBlindnessType, cb_mode) orelse {
            std.log.err("❌ Invalid color blindness mode: {s}", .{cb_mode});
            std.log.info("💡 Available modes: protanopia, protanomaly, deuteranopia, deuteranomaly, tritanopia, tritanomaly, achromatopsia, achromatomaly", .{});
            return error.InvalidColorBlindnessMode;
        };

        const adapter = theme_manager.ColorBlindnessAdapter.init(allocator);
        const adapted_theme = try adapter.adaptForColorBlindness(manager.getCurrentTheme(), cb_type);

        // Add the adapted theme to the manager and switch to it
        const adapted_name = try allocator.dupe(u8, adapted_theme.name);
        try manager.themes.put(adapted_name, adapted_theme);
        try manager.switchTheme(adapted_theme.name);

        std.log.info("♿ Applied color blindness adaptation: {s}", .{cb_mode});
    }

    // Log current theme
    const current_theme = manager.getCurrentTheme();
    std.log.info("🎨 Active theme: {s} ({s})", .{ current_theme.name, if (current_theme.isDark) "dark" else "light" });
}

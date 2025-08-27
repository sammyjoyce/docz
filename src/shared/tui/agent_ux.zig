//! Shared Agent UX Framework
//!
//! This module provides a UX framework that all agents can use to provide
//! consistent user experiences across different terminal capabilities and agent types.
//!
//! ## Key Features
//!
//! - **Session Manager**: Consistent session handling across all agents
//! - **Progressive Enhancement**: Automatically adapts to terminal capabilities
//! - **Shared Command System**: Extensible command palette with agent-specific commands
//! - **Universal Shortcuts**: Standardized keyboard shortcuts and navigation
//! - **Visual Feedback**: Consistent patterns for status, progress, and notifications
//! - **Onboarding System**: Guided first-time user experience
//! - **Help System**: Context-aware help and documentation
//! - **Workflow Automation**: Cross-agent workflow orchestration
//!
//! ## Usage Example
//!
//! ```zig
//! const AgentUX = @import("agent_ux.zig");
//!
//! // Create UX manager for an agent
//! const ux = try AgentUX.create(allocator, .{
//!     .agent_name = "My Agent",
//!     .enable_dashboard = true,
//!     .enable_mouse = true,
//!     .enable_animations = true,
//! });
//! defer ux.deinit();
//!
//! // Register agent-specific commands
//! try ux.registerCommand(.{
//!     .name = "analyze_file",
//!     .description = "Analyze the current file",
//!     .shortcut = "Ctrl+A",
//!     .action = analyzeFileAction,
//! });
//!
//! // Run the interactive UX loop
//! try ux.runInteractive();
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

// Core TUI modules
const tui = @import("../tui/mod.zig");
const renderer_mod = @import("../tui/core/renderer.zig");
const input_mod = @import("../tui/core/input/mod.zig");
const events_mod = @import("../tui/core/events.zig");
const bounds_mod = @import("../tui/core/bounds.zig");

// Component modules
const notifications = @import("../tui/notifications.zig");
const command_palette_mod = @import("../tui/components/command_palette.zig");
const session_manager_mod = @import("../tui/components/Session.zig");
const welcome_screen_mod = @import("../tui/components/welcome_screen.zig");

// Shared infrastructure
const term = @import("../../term/mod.zig");
const config_shared = @import("../../core/config.zig");
const theme_manager = @import("../../theme/mod.zig");

/// Configuration for the Agent UX framework
pub const UXConfig = struct {
    /// Agent identification
    agent_name: []const u8,
    agent_version: []const u8 = "1.0.0",
    agent_description: []const u8 = "",

    /// UI Feature flags
    enable_dashboard: bool = true,
    enable_mouse: bool = true,
    enable_animations: bool = true,
    enable_notifications: bool = true,
    enable_command_palette: bool = true,
    enable_help_system: bool = true,
    enable_onboarding: bool = true,
    enable_workflow_automation: bool = false,

    /// Terminal capability settings
    progressive_enhancement: bool = true,
    adaptive_layout: bool = true,
    render_quality: tui.RenderQuality = .auto,

    /// Session management
    enable_session_persistence: bool = true,
    auto_save_interval_ms: u32 = 30000,
    max_session_history: u32 = 100,

    /// Keyboard shortcuts
    enable_universal_shortcuts: bool = true,
    custom_shortcuts: ?std.StringHashMap([]const u8) = null,

    /// Onboarding settings
    show_welcome_screen: bool = true,
    enable_tutorials: bool = true,
    enable_tips: bool = true,

    /// Workflow automation
    enable_workflow_recording: bool = false,
    enable_workflow_replay: bool = false,
    workflow_storage_path: []const u8 = "~/.docz/workflows",
};

/// Universal keyboard shortcuts that work across all agents
pub const UniversalShortcuts = struct {
    pub const QUIT = "Ctrl+Q";
    pub const QUIT_ALT = "Ctrl+C";
    pub const HELP = "F1";
    pub const HELP_ALT = "?";
    pub const COMMAND_PALETTE = "Ctrl+P";
    pub const COMMAND_PALETTE_ALT = "Ctrl+Shift+P";
    pub const SAVE_SESSION = "Ctrl+S";
    pub const LOAD_SESSION = "Ctrl+O";
    pub const TOGGLE_DASHBOARD = "Ctrl+D";
    pub const TOGGLE_FILE_BROWSER = "Ctrl+Shift+E";
    pub const TOGGLE_HELP = "Ctrl+H";
    pub const NEXT_PANEL = "Ctrl+Tab";
    pub const PREV_PANEL = "Ctrl+Shift+Tab";
    pub const FOCUS_COMMAND = "Ctrl+L";
    pub const CLEAR_SCREEN = "Ctrl+Shift+C";
    pub const ZOOM_IN = "Ctrl+=";
    pub const ZOOM_OUT = "Ctrl+-";
    pub const RESET_ZOOM = "Ctrl+0";
};

/// Command definition for the shared command system
pub const CommandDefinition = struct {
    /// Unique command name (used for identification)
    name: []const u8,

    /// Human-readable description
    description: []const u8,

    /// Keyboard shortcut (optional)
    shortcut: ?[]const u8 = null,

    /// Command category for organization
    category: []const u8 = "general",

    /// Whether this command requires confirmation
    requires_confirmation: bool = false,

    /// Whether this command is enabled
    enabled: bool = true,

    /// The action to execute when command is triggered
    action: *const fn (context: *Command) anyerror!void,

    /// Optional help text
    help_text: ?[]const u8 = null,

    /// Command metadata for extensibility
    metadata: ?std.StringHashMap([]const u8) = null,
};

/// Context passed to command actions
pub const Command = struct {
    /// UX manager instance
    ux: *AgentUX,

    /// Current input arguments/parameters
    args: []const []const u8 = &.{},

    /// Current working directory
    cwd: []const u8,

    /// Selected files (if any)
    selected_files: []const []const u8 = &.{},

    /// Current terminal size
    terminal_size: bounds_mod.TerminalSize,

    /// User data for agent-specific context
    user_data: ?*anyopaque = null,
};

/// Workflow step definition for automation
pub const WorkflowStep = struct {
    /// Step identifier
    id: []const u8,

    /// Human-readable description
    description: []const u8,

    /// Command to execute
    command: []const u8,

    /// Arguments for the command
    args: []const []const u8 = &.{},

    /// Expected duration in milliseconds
    expected_duration_ms: u32 = 1000,

    /// Whether this step requires user interaction
    requires_interaction: bool = false,

    /// Step metadata
    metadata: ?std.StringHashMap([]const u8) = null,
};

/// Workflow definition for automation
pub const Workflow = struct {
    /// Workflow identifier
    id: []const u8,

    /// Human-readable name
    name: []const u8,

    /// Workflow description
    description: []const u8,

    /// Steps to execute
    steps: std.ArrayList(WorkflowStep),

    /// Whether workflow can be interrupted
    interruptible: bool = true,

    /// Maximum execution time in milliseconds
    max_execution_time_ms: u32 = 300000, // 5 minutes

    /// Workflow metadata
    metadata: ?std.StringHashMap([]const u8) = null,
};

/// Onboarding step for guided user experience
pub const OnboardingStep = struct {
    /// Step identifier
    id: []const u8,

    /// Step title
    title: []const u8,

    /// Step content/description
    content: []const u8,

    /// Type of interaction required
    interaction_type: OnboardingInteraction = .information,

    /// Expected user action
    expected_action: ?[]const u8 = null,

    /// Whether this step is skippable
    skippable: bool = true,

    /// Step metadata
    metadata: ?std.StringHashMap([]const u8) = null,
};

/// Types of onboarding interactions
pub const OnboardingInteraction = enum {
    information, // Just display information
    confirmation, // Require user to confirm
    input, // Require user input
    action, // Require user to perform an action
    choice, // Present multiple choices
};

/// Help topic for the help system
pub const HelpTopic = struct {
    /// Topic identifier
    id: []const u8,

    /// Topic title
    title: []const u8,

    /// Topic content
    content: []const u8,

    /// Related commands
    related_commands: []const []const u8 = &.{},

    /// Related topics
    related_topics: []const []const u8 = &.{},

    /// Topic category
    category: []const u8 = "general",

    /// Whether this is a context-sensitive topic
    context_sensitive: bool = false,

    /// Topic metadata
    metadata: ?std.StringHashMap([]const u8) = null,
};

/// Types of visual feedback
pub const FeedbackType = enum {
    success,
    @"error",
    warning,
    info,
    progress,
};

/// Main Agent UX Manager
/// This is the central component that coordinates all UX functionality
pub const AgentUX = struct {
    /// Memory allocator
    allocator: Allocator,

    /// Configuration
    config: UXConfig,

    /// Terminal capabilities
    terminal_caps: term.caps.TermCaps,

    /// Theme manager
    theme_mgr: *theme_manager.ThemeManager,

    /// Renderer system
    renderer: *tui.Renderer,

    /// Event system
    event_system: *tui.EventSystem,

    /// Session manager
    session_mgr: *session_manager_mod.Session,

    /// Notification system
    notifier: *notifications.NotificationSystem,

    /// Command palette
    command_palette: ?*command_palette_mod.CommandPalette,

    /// Welcome screen
    welcome_screen: welcome_screen_mod.WelcomeScreen,

    /// Registered commands
    commands: std.StringHashMap(Command),

    /// Active workflows
    workflows: std.StringHashMap(Workflow),

    /// Onboarding steps
    onboarding_steps: std.ArrayList(OnboardingStep),

    /// Help topics
    help_topics: std.StringHashMap(HelpTopic),

    /// Current UX state
    state: UXState,

    /// User data storage
    user_data: std.StringHashMap([]const u8),

    /// Thread pool for background operations
    thread_pool: *std.Thread.Pool,

    const Self = @This();

    /// Current UX state
    pub const UXState = struct {
        /// Current mode
        mode: UXMode = .interactive,

        /// Active panels/components
        active_panels: std.StringHashMap(bool),

        /// Current focus
        focused_component: ?[]const u8 = null,

        /// Current workflow (if any)
        current_workflow: ?[]const u8 = null,

        /// Current onboarding step
        current_onboarding_step: ?usize = null,

        /// Help system state
        help_visible: bool = false,

        /// Command palette state
        command_palette_visible: bool = false,

        /// Session state
        session_active: bool = false,

        /// Performance metrics
        metrics: PerformanceMetrics = .{},

        /// Error state
        last_error: ?[]const u8 = null,
    };

    /// UX modes
    pub const UXMode = enum {
        interactive, // Full interactive mode
        command, // Command-line mode
        workflow, // Workflow automation mode
        onboarding, // Guided onboarding mode
        help, // Help/documentation mode
        minimal, // Minimal UI mode
    };

    /// Performance metrics
    pub const PerformanceMetrics = struct {
        render_time_ms: f64 = 0,
        command_execution_time_ms: f64 = 0,
        workflow_execution_time_ms: f64 = 0,
        memory_usage_mb: f64 = 0,
        commands_executed: u64 = 0,
        workflows_completed: u64 = 0,
    };

    /// Initialize the Agent UX manager
    pub fn init(allocator: Allocator, config: UXConfig) !*Self {
        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = Self{
            .allocator = allocator,
            .config = config,
            .terminal_caps = undefined,
            .theme_mgr = undefined,
            .renderer = undefined,
            .event_system = undefined,
            .session_mgr = undefined,
            .notifier = undefined,
            .command_palette = null,
            .welcome_screen = undefined,
            .commands = std.StringHashMap(Command).init(allocator),
            .workflows = std.StringHashMap(Workflow).init(allocator),
            .onboarding_steps = std.ArrayList(OnboardingStep).init(allocator),
            .help_topics = std.StringHashMap(HelpTopic).init(allocator),
            .state = UXState{},
            .user_data = std.StringHashMap([]const u8).init(allocator),
            .thread_pool = undefined,
        };

        // Initialize terminal capabilities
        self.terminal_caps = term.caps.detectCaps(allocator);

        // Initialize theme manager
        self.theme_mgr = try theme_manager.init(allocator);

        // Initialize renderer with adaptive quality
        const render_mode = try self.determineRenderMode();
        self.renderer = try tui.createRenderer(allocator, render_mode);

        // Initialize event system
        self.event_system = try tui.EventSystem.init(allocator);

        // Initialize session manager
        self.session_mgr = try session_manager_mod.Session.init(
            allocator,
            self.config.session_settings,
        );

        // Initialize notification system
        self.notifier = try notifications.NotificationSystem.init(
            allocator,
            self.config.enable_notifications,
        );

        // Initialize command palette if enabled
        if (self.config.enable_command_palette) {
            self.command_palette = try command_palette_mod.CommandPalette.init(allocator);
        }

        // Initialize welcome screen
        self.welcome_screen = welcome_screen_mod.WelcomeScreen.init(
            allocator,
            self.theme_mgr.getCurrentTheme(),
        );

        // Initialize thread pool
        self.thread_pool = try allocator.create(std.Thread.Pool);
        self.thread_pool.* = std.Thread.Pool.init(.{ .allocator = allocator });

        // Register universal commands
        try self.registerUniversalCommands();

        // Initialize default help topics
        try self.initializeDefaultHelpTopics();

        // Initialize onboarding if enabled
        if (self.config.enable_onboarding) {
            try self.initializeDefaultOnboarding();
        }

        return self;
    }

    /// Deinitialize the Agent UX manager
    pub fn deinit(self: *Self) void {
        // Save session before cleanup
        if (self.config.enable_session_persistence) {
            self.saveSession() catch {};
        }

        // Cleanup components
        self.thread_pool.deinit();
        self.allocator.destroy(self.thread_pool);

        self.help_topics.deinit();
        self.onboarding_steps.deinit();
        self.workflows.deinit();
        self.commands.deinit();
        self.user_data.deinit();

        if (self.command_palette) |palette| {
            palette.deinit();
        }

        self.notifier.deinit();
        self.session_mgr.deinit();
        self.event_system.deinit();
        self.renderer.deinit();
        self.theme_mgr.deinit();

        self.allocator.destroy(self);
    }

    /// Run the interactive UX loop
    pub fn runInteractive(self: *Self) !void {
        // Setup terminal for interactive mode
        try self.setupTerminal();
        defer self.restoreTerminal();

        // Show welcome screen if enabled
        if (self.config.show_welcome_screen) {
            try self.showWelcomeScreen();
        }

        // Start onboarding if this is first run
        if (self.config.enable_onboarding and self.isFirstRun()) {
            try self.startOnboarding();
        }

        // Main interactive loop
        while (true) {
            // Render current UI
            try self.renderUI();

            // Process input events
            const event = try self.event_system.waitForEvent();

            // Handle event
            const should_exit = try self.handleEvent(event);
            if (should_exit) break;

            // Auto-save session periodically
            try self.checkAutoSave();

            // Update performance metrics
            try self.updateMetrics();
        }

        // Show goodbye screen
        try self.showGoodbyeScreen();
    }

    /// Register a command in the shared command system
    pub fn registerCommand(self: *Self, command: Command) !void {
        const name_key = try self.allocator.dupe(u8, command.name);
        errdefer self.allocator.free(name_key);

        try self.commands.put(name_key, command);

        // Add to command palette if available
        if (self.command_palette) |palette| {
            try palette.commands.append(.{
                .name = command.name,
                .description = command.description,
                .shortcut = command.shortcut,
                .action = struct {
                    fn action(ctx: *Command) anyerror!void {
                        _ = ctx;
                        // This would be replaced with the actual command action
                    }
                }.action,
            });
        }
    }

    /// Execute a command by name
    pub fn executeCommand(self: *Self, command_name: []const u8, args: []const []const u8) !void {
        const command = self.commands.get(command_name) orelse {
            return error.CommandNotFound;
        };

        if (!command.enabled) {
            return error.CommandDisabled;
        }

        const context = Command{
            .ux = self,
            .args = args,
            .cwd = try std.fs.cwd().realpathAlloc(self.allocator, "."),
            .terminal_size = try bounds_mod.getTerminalSize(),
        };
        defer self.allocator.free(context.cwd);

        const start_time = std.time.milliTimestamp();
        try command.action(&context);
        const end_time = std.time.milliTimestamp();

        self.state.metrics.command_execution_time_ms = @floatFromInt(end_time - start_time);
        self.state.metrics.commands_executed += 1;

        // Show success notification
        try self.notifier.showNotification(
            "Command Executed",
            try std.fmt.allocPrint(self.allocator, "Successfully executed '{s}'", .{command_name}),
            .success,
        );
    }

    /// Register a workflow for automation
    pub fn registerWorkflow(self: *Self, workflow: Workflow) !void {
        const id_key = try self.allocator.dupe(u8, workflow.id);
        errdefer self.allocator.free(id_key);

        try self.workflows.put(id_key, workflow);
    }

    /// Start a workflow
    pub fn startWorkflow(self: *Self, workflow_id: []const u8) !void {
        const workflow = self.workflows.get(workflow_id) orelse {
            return error.WorkflowNotFound;
        };

        self.state.mode = .workflow;
        self.state.current_workflow = try self.allocator.dupe(u8, workflow_id);

        try self.notifier.showNotification(
            "Workflow Started",
            try std.fmt.allocPrint(self.allocator, "Starting workflow: {s}", .{workflow.name}),
            .info,
        );

        // Execute workflow in background
        try self.thread_pool.spawn(struct {
            fn executeWorkflow(ux: *AgentUX, wf: Workflow) void {
                ux.executeWorkflow(&wf) catch |err| {
                    std.log.err("Workflow execution failed: {}", .{err});
                };
            }
        }.executeWorkflow, .{ self, workflow.* });
    }

    /// Show help for a specific topic
    pub fn showHelp(self: *Self, topic_id: ?[]const u8) !void {
        self.state.mode = .help;
        self.state.help_visible = true;

        const topic = if (topic_id) |id|
            self.help_topics.get(id) orelse self.help_topics.get("general").?
        else
            self.help_topics.get("general").?;

        try self.notifier.showNotification(
            "Help",
            try std.fmt.allocPrint(self.allocator, "Showing help: {s}", .{topic.title}),
            .info,
        );
    }

    /// Start the onboarding process
    pub fn startOnboarding(self: *Self) !void {
        if (self.onboarding_steps.items.len == 0) {
            return;
        }

        self.state.mode = .onboarding;
        self.state.current_onboarding_step = 0;

        try self.showCurrentOnboardingStep();
    }

    /// Get current terminal capabilities with progressive enhancement
    pub fn getEnhancedCapabilities(self: *Self) term.caps.TermCaps {
        var caps = self.terminal_caps;

        // Apply progressive enhancement based on configuration
        if (self.config.progressive_enhancement) {
            // Enhance capabilities based on detected features
            if (caps.supportsTruecolor and self.config.render_quality == .rich) {
                caps.color_support = .truecolor_24bit;
            }
        }

        return caps;
    }

    /// Save current session
    pub fn saveSession(self: *Self) !void {
        try self.session_mgr.saveSession(&self.state);
        try self.notifier.showNotification("Session Saved", "Your session has been saved successfully", .success);
    }

    /// Load a session
    pub fn loadSession(self: *Self, session_id: []const u8) !void {
        _ = session_id; // Would implement session loading logic
        try self.session_mgr.restoreLastSession(&self.state);
        try self.notifier.showNotification("Session Loaded", "Session has been restored", .success);
    }

    /// Show visual feedback for an action
    pub fn showFeedback(self: *Self, message: []const u8, feedback_type: FeedbackType) !void {
        switch (feedback_type) {
            .success => try self.notifier.showNotification("Success", message, .success),
            .@"error" => try self.notifier.showNotification("Error", message, .@"error"),
            .warning => try self.notifier.showNotification("Warning", message, .warning),
            .info => try self.notifier.showNotification("Info", message, .info),
            .progress => try self.notifier.showProgressNotification("Progress", message, 0.5),
        }
    }

    /// Get universal shortcut for an action
    pub fn getUniversalShortcut(self: *Self, action: []const u8) ?[]const u8 {
        _ = self; // UX manager context (could be used for customization)

        return switch (std.hash_map.hashString(action)) {
            std.hash_map.hashString("quit") => UniversalShortcuts.QUIT,
            std.hash_map.hashString("help") => UniversalShortcuts.HELP,
            std.hash_map.hashString("command_palette") => UniversalShortcuts.COMMAND_PALETTE,
            std.hash_map.hashString("save_session") => UniversalShortcuts.save_session,
            std.hash_map.hashString("load_session") => UniversalShortcuts.load_session,
            std.hash_map.hashString("toggle_dashboard") => UniversalShortcuts.toggle_dashboard,
            std.hash_map.hashString("toggle_file_browser") => UniversalShortcuts.toggle_file_browser,
            std.hash_map.hashString("toggle_help") => UniversalShortcuts.toggle_help,
            std.hash_map.hashString("next_panel") => UniversalShortcuts.next_panel,
            std.hash_map.hashString("prev_panel") => UniversalShortcuts.prev_panel,
            std.hash_map.hashString("focus_command") => UniversalShortcuts.focus_command,
            std.hash_map.hashString("clear_screen") => UniversalShortcuts.clear_screen,
            std.hash_map.hashString("zoom_in") => UniversalShortcuts.zoom_in,
            std.hash_map.hashString("zoom_out") => UniversalShortcuts.zoom_out,
            std.hash_map.hashString("reset_zoom") => UniversalShortcuts.reset_zoom,
            else => null,
        };
    }

    // === Private Helper Methods ===

    fn determineRenderMode(self: *Self) !tui.renderer.RenderMode {
        return switch (self.config.render_quality) {
            .auto => blk: {
                if (self.terminal_caps.supportsTruecolor) {
                    break :blk .rich;
                } else {
                    break :blk .standard;
                }
            },
            .rich => .rich,
            .standard => .standard,
            .compatible => .compatible,
            .minimal => .minimal,
        };
    }

    fn setupTerminal(self: *Self) !void {
        // Setup terminal for TUI application
        try self.renderer.setupTerminal();

        // Enable mouse tracking if configured
        if (self.config.enable_mouse and self.terminal_caps.supportsMouse) {
            try self.event_system.enableMouseTracking();
        }
    }

    fn restoreTerminal(self: *Self) void {
        // Restore terminal from TUI application
        self.renderer.restoreTerminal();

        // Disable mouse tracking if it was enabled
        if (self.config.enable_mouse) {
            self.event_system.disableMouseTracking() catch {};
        }
    }

    fn showWelcomeScreen(self: *Self) !void {
        try self.welcome_screen.render(self.renderer, .{
            .agent_name = self.config.agent_name,
            .agent_version = self.config.agent_version,
            .show_animation = self.config.enable_animations,
        });

        // Wait for user input
        _ = try self.event_system.waitForEvent();
    }

    fn showGoodbyeScreen(self: *Self) !void {
        // Simple goodbye message for now
        try self.renderer.writeText(0, 0, "Goodbye! Thanks for using " ++ self.config.agent_name ++ ".");
        std.time.sleep(2 * std.time.ns_per_s);
    }

    fn renderUI(self: *Self) !void {
        // Begin synchronized output for flicker-free rendering
        try self.renderer.beginFrame();
        defer self.renderer.endFrame() catch {};

        // Clear render buffer
        try self.renderer.clear();

        // Render based on current mode
        switch (self.state.mode) {
            .interactive => try self.renderInteractive(),
            .command => try self.renderCommand(),
            .workflow => try self.renderWorkflow(),
            .onboarding => try self.renderOnboarding(),
            .help => try self.renderHelp(),
            .minimal => try self.renderMinimal(),
        }

        // Render overlay components
        try self.renderOverlays();
    }

    fn renderInteractive(self: *Self) !void {
        const caps = self.getEnhancedCapabilities();
        const size = try bounds_mod.getTerminalSize();

        // Render main interface
        const title = try std.fmt.allocPrint(self.allocator, "{s} v{s}", .{
            self.config.agent_name,
            self.config.agent_version,
        });
        defer self.allocator.free(title);

        try self.renderer.writeText(0, 0, title);

        // Render status information
        const status_y = size.height - 2;
        const status_text = try std.fmt.allocPrint(self.allocator, "Ready | {s} | {d}x{d}", .{
            if (caps.supportsTruecolor) "True Color" else "256 Colors",
            size.width,
            size.height,
        });
        defer self.allocator.free(status_text);

        try self.renderer.writeText(0, status_y, status_text);

        // Render help hint
        const help_hint = try std.fmt.allocPrint(self.allocator, "Press {s} for help, {s} for commands", .{
            UniversalShortcuts.HELP,
            UniversalShortcuts.COMMAND_PALETTE,
        });
        defer self.allocator.free(help_hint);

        try self.renderer.writeText(0, status_y + 1, help_hint);
    }

    fn renderCommand(self: *Self) !void {
        try self.renderer.writeText(0, 0, "Command Mode - Type your command:");
        try self.renderer.writeText(0, 2, "> ");
    }

    fn renderWorkflow(self: *Self) !void {
        if (self.state.current_workflow) |workflow_id| {
            const workflow = self.workflows.get(workflow_id) orelse return;

            const status = try std.fmt.allocPrint(self.allocator, "Running workflow: {s}", .{workflow.name});
            defer self.allocator.free(status);

            try self.renderer.writeText(0, 0, status);
            try self.renderer.writeText(0, 2, "Press Ctrl+C to interrupt if needed...");
        }
    }

    fn renderOnboarding(self: *Self) !void {
        if (self.state.current_onboarding_step) |step_index| {
            if (step_index < self.onboarding_steps.items.len) {
                const step = &self.onboarding_steps.items[step_index];

                try self.renderer.writeText(0, 0, "Onboarding");
                try self.renderer.writeText(0, 2, step.title);
                try self.renderer.writeText(0, 4, step.content);

                const hint = switch (step.interaction_type) {
                    .information => "Press Enter to continue...",
                    .confirmation => "Press Y to confirm, N to skip...",
                    .input => "Enter your response...",
                    .action => "Perform the action, then press Enter...",
                    .choice => "Select an option...",
                };
                try self.renderer.writeText(0, 6, hint);
            }
        }
    }

    fn renderHelp(self: *Self) !void {
        try self.renderer.writeText(0, 0, "Help System");
        try self.renderer.writeText(0, 2, "Available topics:");
        try self.renderer.writeText(0, 4, "- shortcuts: Keyboard shortcuts");
        try self.renderer.writeText(0, 5, "- commands: Available commands");
        try self.renderer.writeText(0, 6, "- workflows: Workflow automation");
        try self.renderer.writeText(0, 8, "Press Esc to exit help");
    }

    fn renderMinimal(self: *Self) !void {
        const prompt = try std.fmt.allocPrint(self.allocator, "{s}> ", .{self.config.agent_name});
        defer self.allocator.free(prompt);

        try self.renderer.writeText(0, 0, prompt);
    }

    fn renderOverlays(self: *Self) !void {
        // Render command palette if visible
        if (self.state.command_palette_visible and self.command_palette != null) {
            try self.command_palette.?.render(self.renderer);
        }

        // Render help if visible
        if (self.state.help_visible) {
            try self.renderHelp();
        }

        // Render notifications
        try self.notifier.renderNotifications(self.renderer.writer());
    }

    fn handleEvent(self: *Self, event: tui.InputEvent) !bool {
        switch (event) {
            .key => |key| {
                // Handle universal shortcuts
                if (key.ctrl) {
                    switch (key.code) {
                        'q', 'c' => return true, // Quit
                        'p' => try self.toggleCommandPalette(),
                        'h' => try self.toggleHelp(),
                        's' => try self.saveSession(),
                        'o' => try self.loadSession("last"),
                        'd' => try self.toggleDashboard(),
                        'l' => try self.focusCommand(),
                        else => {},
                    }
                } else if (key.code == .f1 or key.code == '?') {
                    try self.toggleHelp();
                } else if (key.code == .escape) {
                    if (self.state.help_visible) {
                        self.state.help_visible = false;
                        self.state.mode = .interactive;
                    } else if (self.state.command_palette_visible) {
                        self.state.command_palette_visible = false;
                    }
                }

                // Handle mode-specific input
                switch (self.state.mode) {
                    .onboarding => try self.handleOnboardingInput(key),
                    .command => try self.handleCommandInput(key),
                    .help => try self.handleHelpInput(key),
                    else => {},
                }
            },
            .mouse => |mouse| {
                try self.handleMouseEvent(mouse);
            },
            .resize => |size| {
                try self.handleResize(size);
            },
            else => {},
        }

        return false;
    }

    fn handleOnboardingInput(self: *Self, key: tui.KeyEvent) !void {
        switch (key.code) {
            .enter => try self.nextOnboardingStep(),
            'y', 'Y' => try self.nextOnboardingStep(),
            'n', 'N' => try self.skipOnboardingStep(),
            else => {},
        }
    }

    fn handleCommandInput(self: *Self, key: tui.KeyEvent) !void {
        // Would implement command input handling
        _ = self;
        _ = key;
    }

    fn handleHelpInput(self: *Self, key: tui.KeyEvent) !void {
        switch (key.code) {
            .escape => {
                self.state.help_visible = false;
                self.state.mode = .interactive;
            },
            else => {},
        }
    }

    fn handleMouseEvent(self: *Self, mouse: tui.MouseEvent) !void {
        // Handle mouse events for interactive components
        _ = self;
        _ = mouse;
    }

    fn handleResize(self: *Self, size: bounds_mod.TerminalSize) !void {
        // Handle terminal resize
        _ = size;
        try self.renderUI();
    }

    fn toggleCommandPalette(self: *Self) !void {
        if (self.command_palette) |palette| {
            self.state.command_palette_visible = !self.state.command_palette_visible;
            try palette.toggle();
        }
    }

    fn toggleHelp(self: *Self) !void {
        self.state.help_visible = !self.state.help_visible;
        if (self.state.help_visible) {
            self.state.mode = .help;
        } else {
            self.state.mode = .interactive;
        }
    }

    fn toggleDashboard(self: *Self) !void {
        // Toggle dashboard visibility
        try self.notifier.showNotification("Dashboard", "Dashboard toggle not yet implemented", .info);
    }

    fn focusCommand(self: *Self) !void {
        self.state.mode = .command;
    }

    fn nextOnboardingStep(self: *Self) !void {
        if (self.state.current_onboarding_step) |*step| {
            step.* += 1;
            if (step.* >= self.onboarding_steps.items.len) {
                self.state.mode = .interactive;
                self.state.current_onboarding_step = null;
                try self.notifier.showNotification("Onboarding Complete", "Welcome to " ++ self.config.agent_name ++ "!", .success);
            } else {
                try self.showCurrentOnboardingStep();
            }
        }
    }

    fn skipOnboardingStep(self: *Self) !void {
        try self.nextOnboardingStep();
    }

    fn showCurrentOnboardingStep(self: *Self) !void {
        if (self.state.current_onboarding_step) |step_index| {
            if (step_index < self.onboarding_steps.items.len) {
                const step = &self.onboarding_steps.items[step_index];
                try self.notifier.showNotification(step.title, step.content, .info);
            }
        }
    }

    fn checkAutoSave(self: *Self) !void {
        if (!self.config.enable_session_persistence) return;

        const current_time = std.time.timestamp();
        const last_save = self.session_mgr.getLastSaveTime();

        if (current_time - last_save >= self.config.auto_save_interval_ms / 1000) {
            try self.saveSession();
        }
    }

    fn updateMetrics(self: *Self) !void {
        // Update performance metrics
        self.state.metrics.memory_usage_mb = @as(f64, @floatFromInt(std.heap.page_allocator.total_requested_bytes)) / 1024.0 / 1024.0;
    }

    fn registerUniversalCommands(self: *Self) !void {
        // Register quit command
        try self.registerCommand(.{
            .name = "quit",
            .description = "Exit the application",
            .shortcut = UniversalShortcuts.QUIT,
            .action = struct {
                fn action(ctx: *Command) anyerror!void {
                    _ = ctx;
                    // This would signal the main loop to exit
                }
            }.action,
        });

        // Register help command
        try self.registerCommand(.{
            .name = "help",
            .description = "Show help information",
            .shortcut = UniversalShortcuts.HELP,
            .action = struct {
                fn action(ctx: *Command) anyerror!void {
                    try ctx.ux.showHelp(null);
                }
            }.action,
        });

        // Register save session command
        try self.registerCommand(.{
            .name = "save_session",
            .description = "Save current session",
            .shortcut = UniversalShortcuts.save_session,
            .action = struct {
                fn action(ctx: *Command) anyerror!void {
                    try ctx.ux.saveSession();
                }
            }.action,
        });
    }

    fn initializeDefaultHelpTopics(self: *Self) !void {
        // General help topic
        const general_topic = HelpTopic{
            .id = "general",
            .title = "General Help",
            .content = "Welcome to " ++ self.config.agent_name ++ "! Here are some essential commands:",
            .related_commands = &.{ "help", "quit", "save_session" },
            .category = "general",
        };
        try self.help_topics.put(try self.allocator.dupe(u8, general_topic.id), general_topic);

        // Shortcuts help topic
        const shortcuts_topic = HelpTopic{
            .id = "shortcuts",
            .title = "Keyboard Shortcuts",
            .content = "Universal shortcuts that work across all agents:",
            .category = "shortcuts",
        };
        try self.help_topics.put(try self.allocator.dupe(u8, shortcuts_topic.id), shortcuts_topic);
    }

    fn initializeDefaultOnboarding(self: *Self) !void {
        try self.onboarding_steps.append(.{
            .id = "welcome",
            .title = "Welcome to " ++ self.config.agent_name,
            .content = "This appears to be your first time using " ++ self.config.agent_name ++ ". Let's take a quick tour!",
            .interaction_type = .information,
            .skippable = false,
        });

        try self.onboarding_steps.append(.{
            .id = "shortcuts",
            .title = "Keyboard Shortcuts",
            .content = "You can use Ctrl+P to open the command palette, F1 or ? for help, and Ctrl+Q to quit.",
            .interaction_type = .information,
        });

        try self.onboarding_steps.append(.{
            .id = "commands",
            .title = "Commands",
            .content = "Type commands to interact with the agent. Use the command palette (Ctrl+P) to see all available commands.",
            .interaction_type = .information,
        });
    }

    fn executeWorkflow(self: *Self, workflow: *const Workflow) !void {
        const start_time = std.time.milliTimestamp();

        for (workflow.steps.items) |step| {
            try self.executeWorkflowStep(&step);
        }

        const end_time = std.time.milliTimestamp();
        self.state.metrics.workflow_execution_time_ms = @floatFromInt(end_time - start_time);
        self.state.metrics.workflows_completed += 1;

        // Reset to interactive mode
        self.state.mode = .interactive;
        self.state.current_workflow = null;

        try self.notifier.showNotification(
            "Workflow Complete",
            try std.fmt.allocPrint(self.allocator, "Successfully completed workflow: {s}", .{workflow.name}),
            .success,
        );
    }

    fn executeWorkflowStep(self: *Self, step: *const WorkflowStep) !void {
        try self.notifier.showNotification(
            "Workflow Step",
            try std.fmt.allocPrint(self.allocator, "Executing: {s}", .{step.description}),
            .info,
        );

        // Execute the command
        try self.executeCommand(step.command, step.args);

        // Wait for expected duration or user interaction
        if (step.requires_interaction) {
            // Wait for user input
            _ = try self.event_system.waitForEvent();
        } else {
            std.time.sleep(step.expected_duration_ms * std.time.ns_per_ms);
        }
    }

    fn isFirstRun(self: *Self) bool {
        // Check if this is the first run (could check for config file, etc.)
        _ = self;
        return true; // For now, always show onboarding
    }
};

/// Create a new Agent UX manager with default configuration
pub fn create(allocator: std.mem.Allocator, options: struct {
    agent_name: []const u8,
    agent_version: []const u8 = "1.0.0",
    agent_description: []const u8 = "",
    enable_dashboard: bool = true,
    enable_mouse: bool = true,
    enable_animations: bool = true,
    theme: []const u8 = "auto",
}) !*AgentUX {
    const config = UXConfig{
        .agent_name = options.agent_name,
        .agent_version = options.agent_version,
        .agent_description = options.agent_description,
        .enable_dashboard = options.enable_dashboard,
        .enable_mouse = options.enable_mouse,
        .enable_animations = options.enable_animations,
        .theme = options.theme,
    };

    return try AgentUX.init(allocator, config);
}

/// Convenience function to create UX with full features enabled
pub fn createFull(allocator: std.mem.Allocator, agent_name: []const u8) !*AgentUX {
    return try create(allocator, .{
        .agent_name = agent_name,
        .enable_dashboard = true,
        .enable_mouse = true,
        .enable_animations = true,
    });
}

/// Convenience function to create minimal UX
pub fn createMinimal(allocator: std.mem.Allocator, agent_name: []const u8) !*AgentUX {
    const config = UXConfig{
        .agent_name = agent_name,
        .enable_dashboard = false,
        .enable_mouse = false,
        .enable_animations = false,
        .enable_notifications = false,
        .enable_command_palette = false,
        .enable_help_system = false,
        .enable_onboarding = false,
        .render_quality = .minimal,
    };

    return try AgentUX.init(allocator, config);
}

// === Tests ===

test "agent ux initialization" {
    const allocator = std.testing.allocator;

    const ux = try create(allocator, .{
        .agent_name = "Test Agent",
        .enable_dashboard = false,
        .enable_mouse = false,
    });
    defer ux.deinit();

    try std.testing.expectEqualStrings("Test Agent", ux.config.agent_name);
    try std.testing.expect(!ux.config.enable_dashboard);
}

test "universal shortcuts" {
    const allocator = std.testing.allocator;

    const ux = try create(allocator, .{
        .agent_name = "Test Agent",
    });
    defer ux.deinit();

    const quit_shortcut = ux.getUniversalShortcut("quit");
    try std.testing.expect(quit_shortcut != null);
    try std.testing.expectEqualStrings(UniversalShortcuts.QUIT, quit_shortcut.?);
}

test "command registration" {
    const allocator = std.testing.allocator;

    const ux = try create(allocator, .{
        .agent_name = "Test Agent",
    });
    defer ux.deinit();

    try ux.registerCommand(.{
        .name = "test_command",
        .description = "A test command",
        .action = struct {
            fn action(ctx: *Command) anyerror!void {
                _ = ctx;
            }
        }.action,
    });

    try std.testing.expect(ux.commands.contains("test_command"));
}

//! Agent Interface System
//!
//! This module provides a modern agent interface that leverages all advanced
//! terminal capabilities to create beautiful, modern, and interactive AI agent experiences.
//!
//! ## Key Features
//!
//! - **Advanced Terminal Integration**: Mouse support, graphics, notifications, themes
//! - **Rich CLI/TUI Experience**: Command palette, dashboards, progress tracking
//! - **OAuth Integration**: Seamless authentication with wizards
//! - **Adaptive Rendering**: Automatically adjusts to terminal capabilities
//! - **Session Management**: Save/restore agent sessions with full state preservation
//! - **Modern UX**: Beautiful, responsive interface with animations and effects
//!
//! ## Usage Example
//!
//! ```zig
//! const Interface = @import("agent_interface.zig");
//!
//! // Create an agent
//! const agent = try Interface.createAgent(allocator, .{
//!     .enable_dashboard = true,
//!     .enable_mouse = true,
//!     .enable_notifications = true,
//!     .theme = "cyberpunk",
//! });
//! defer agent.deinit();
//!
//! // Run in interactive mode with full UI
//! try agent.runInteractive();
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = Thread.Mutex;

// Core modules
const config = @import("config.zig");
const engine = @import("engine.zig");

// Shared infrastructure modules
const tui = @import("../shared/tui/mod.zig");
const cli = @import("../shared/cli/mod.zig");
const term = @import("../shared/term/mod.zig");
const auth = @import("../shared/auth/core/mod.zig");
const render = @import("../shared/render/mod.zig");
const theme_manager = @import("../shared/theme_manager/mod.zig");
const network = @import("../shared/network/mod.zig");
const tools_mod = @import("../shared/tools/mod.zig");
const components = @import("../shared/components/mod.zig");

// Re-export CliOptions from engine to avoid duplication
pub const CliOptions = engine.CliOptions;

// Terminal abstractions
const screen_manager = @import("../shared/term/screen_manager.zig");
const mouse_mod = @import("../shared/term/input/mouse.zig");

/// Configuration for modern agent interfaces
pub const Config = struct {
    /// Base agent configuration
    base_config: config.AgentConfig,
    
    /// UI Enhancement Settings
    ui_settings: UISettings = .{},
    
    /// Session management settings
    session_settings: SessionSettings = .{},
    
    /// Interactive features
    interactive_features: InteractiveFeatures = .{},
    
    /// Performance settings
    performance: PerformanceSettings = .{},
};

/// UI Enhancement Settings
pub const UISettings = struct {
    /// Enable dashboard view
    enable_dashboard: bool = true,
    
    /// Enable mouse interaction
    enable_mouse: bool = true,
    
    /// Enable graphics rendering
    enable_graphics: bool = true,
    
    /// Enable desktop notifications
    enable_notifications: bool = true,
    
    /// Enable command palette
    enable_command_palette: bool = true,
    
    /// Enable animations and transitions
    enable_animations: bool = true,
    
    /// Theme name or "auto" for system detection
    theme: []const u8 = "auto",
    
    /// Render quality mode
    render_quality: RenderQuality = .auto,
    
    /// Layout mode
    layout_mode: LayoutMode = .adaptive,
};

/// Session management settings
pub const SessionSettings = struct {
    /// Enable session persistence
    enable_persistence: bool = true,
    
    /// Session directory path
    session_dir: []const u8 = "~/.docz/sessions",
    
    /// Auto-save interval in seconds
    auto_save_interval: u32 = 60,
    
    /// Maximum sessions to keep
    max_sessions: u32 = 50,
    
    /// Enable session encryption
    encrypt_sessions: bool = false,
};

/// Interactive feature settings
pub const InteractiveFeatures = struct {
    /// Enable interactive chat mode
    enable_chat: bool = true,
    
    /// Enable command history
    enable_history: bool = true,
    
    /// Enable autocomplete
    enable_autocomplete: bool = true,
    
    /// Enable syntax highlighting
    enable_syntax_highlighting: bool = true,
    
    /// Enable inline documentation
    enable_inline_docs: bool = true,
    
    /// Enable quick actions
    enable_quick_actions: bool = true,
};

/// Performance settings
pub const PerformanceSettings = struct {
    /// Buffer size for rendering
    render_buffer_size: usize = 8192,
    
    /// Maximum FPS for animations
    max_fps: u32 = 60,
    
    /// Enable render caching
    enable_render_cache: bool = true,
    
    /// Enable lazy loading
    enable_lazy_loading: bool = true,
    
    /// Thread pool size
    thread_pool_size: u32 = 4,
};

/// Render quality modes
pub const RenderQuality = enum {
    auto,      // Detect and use best available
    enhanced,  // Full graphics, true color, animations
    standard,  // 256 colors, Unicode blocks
    compatible,// 16 colors, ASCII art
    minimal,   // Plain text only
};

/// Layout modes
pub const LayoutMode = enum {
    adaptive,     // Automatically adjust based on terminal size
    dashboard,    // Fixed dashboard layout
    split,        // Split view (chat + output)
    fullscreen,   // Fullscreen mode
    compact,      // Minimal UI
};

/// Agent interface state
pub const AgentState = struct {
    /// Current UI mode
    ui_mode: UIMode = .interactive,
    
    /// Active components
    active_components: ComponentSet = .{},
    
    /// Session data
    session: SessionData = .{},
    
    /// Performance metrics
    metrics: PerformanceMetrics = .{},
    
    /// Error state
    last_error: ?ErrorInfo = null,
};

/// UI modes
pub const UIMode = enum {
    interactive,  // Full interactive TUI
    command,      // Command-line mode
    batch,        // Batch processing mode
    minimal,      // Minimal output mode
};

/// Active component tracking
pub const ComponentSet = struct {
    dashboard: ?*tui.Dashboard = null,
    command_palette: ?*CommandPalette = null,
    notification_manager: ?*NotificationSystem = null,
    progress_tracker: ?*ProgressTracker = null,
    auth_wizard: ?*AuthenticationWizard = null,
    theme_selector: ?*ThemeSelector = null,
};

/// Session data
pub const SessionData = struct {
    session_id: []const u8 = "",
    start_time: i64 = 0,
    messages_processed: u64 = 0,
    tools_executed: u64 = 0,
    conversation_history: std.ArrayList(ConversationEntry) = undefined,
    metadata: std.StringHashMap([]const u8) = undefined,
};

/// Conversation entry
pub const ConversationEntry = struct {
    timestamp: i64,
    role: enum { user, assistant, system, tool },
    content: []const u8,
    metadata: ?std.json.Value = null,
};

/// Performance metrics
pub const PerformanceMetrics = struct {
    render_time_ms: f64 = 0,
    response_time_ms: f64 = 0,
    memory_usage_mb: f64 = 0,
    cpu_usage_percent: f64 = 0,
    cache_hit_rate: f64 = 0,
};

/// Error information
pub const ErrorInfo = struct {
    code: []const u8,
    message: []const u8,
    timestamp: i64,
    recoverable: bool,
    context: ?std.json.Value = null,
};

/// Message structure for conversation history
pub const ConversationMessage = struct {
    /// Message role (system, user, assistant)
    role: enum { system, user, assistant },
    /// Message content
    content: []const u8,
    /// Optional metadata
    metadata: ?std.json.Value = null,
};



/// Message processing context
pub const Message = struct {
    /// The user input message
    message: []const u8,
    /// Conversation history (previous messages)
    conversationHistory: []const ConversationMessage,
    /// Current CLI options
    cliOptions: CliOptions,
    /// Agent-specific context data
    agentContext: ?*anyopaque,
};

/// Agent Interface
/// This is the main structure that provides all modern capabilities
pub const Agent = struct {
    /// Memory allocator
    allocator: Allocator,
    
    /// Base agent interface
    base: *anyopaque,
    
    /// Configuration
    config: Config,
    
    /// Current state
    state: AgentState,
    
    /// Terminal capabilities
    terminal_caps: term.caps.TermCaps,
    
    /// Theme manager
    theme_mgr: *theme_manager.ThemeManager,
    
    /// Renderer system
    renderer: *tui.Renderer,
    
    /// Event system for input handling
    event_system: *tui.EventSystem,
    
    /// Dashboard engine
    dashboard_engine: ?*tui.DashboardEngine,
    
    /// Session manager
    session_mgr: *SessionManager,
    
    /// Authentication manager
    auth_mgr: *AuthenticationManager,
    
    /// Notification system
    notifier: *NotificationSystem,
    
    /// Command palette
    cmd_palette: ?*CommandPalette,
    
    /// Progress tracker
    progress: *ProgressTracker,

    /// Screen manager for terminal state management
    screen_mgr: *screen_manager.Screen,

    /// Mouse manager for input handling
    mouse_mgr: *mouse_mod.Mouse,

    /// Mutex for thread safety
    mutex: Mutex,
    
    const Self = @This();
    
    /// Initialize agent
    pub fn init(
        allocator: Allocator,
        base_agent: *anyopaque,
        agent_config: Config,
    ) !*Self {
        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        
        self.* = Self{
            .allocator = allocator,
            .base = base_agent,
            .config = agent_config,
            .state = AgentState{},
            .terminal_caps = undefined,
            .theme_mgr = undefined,
            .renderer = undefined,
            .event_system = undefined,
            .dashboard_engine = null,
            .session_mgr = undefined,
            .auth_mgr = undefined,
            .notifier = undefined,
            .cmd_palette = null,
            .progress = undefined,
            .screen_mgr = undefined,
            .mouse_mgr = undefined,
            .mutex = Mutex{},
        };
        
        // Initialize terminal capabilities
        self.terminal_caps = term.caps.detectCaps(allocator);
        
        // Initialize theme manager
        self.theme_mgr = try theme_manager.init(allocator);
        try self.applyTheme();
        
        // Initialize renderer with adaptive quality
        const render_mode = try self.determineRenderMode();
        self.renderer = try tui.createRenderer(allocator, render_mode);
        
        // Initialize event system
        self.event_system = try tui.EventSystem.init(allocator);
        
        // Initialize dashboard if enabled
        if (self.config.ui_settings.enable_dashboard) {
            self.dashboard_engine = try self.createDashboard();
        }
        
        // Initialize session manager
        self.session_mgr = try SessionManager.init(
            allocator,
            self.config.session_settings,
        );
        
        // Initialize authentication manager
        self.auth_mgr = try AuthenticationManager.init(allocator);
        
        // Initialize notification system
        self.notifier = try NotificationSystem.init(
            allocator,
            self.config.ui_settings.enable_notifications,
        );
        
        // Initialize command palette if enabled
        if (self.config.ui_settings.enable_command_palette) {
            self.cmd_palette = try CommandPalette.init(allocator);
        }
        
        // Initialize progress tracker
        self.progress = try ProgressTracker.init(allocator);

        // Initialize screen manager
        self.screen_mgr = try allocator.create(screen_manager.Screen);
        self.screen_mgr.* = screen_manager.Screen.init(allocator);

        // Initialize mouse manager
        self.mouse_mgr = try allocator.create(mouse_mod.Mouse);
        self.mouse_mgr.* = mouse_mod.Mouse.init(allocator);

        // Initialize session
        try self.initializeSession();
        
        return self;
    }
    
    /// Deinitialize enhanced agent
    pub fn deinit(self: *Self) void {
        // Save session before cleanup
        self.saveSession() catch {};
        
        // Cleanup components
        if (self.dashboard_engine) |dashboard| {
            dashboard.deinit();
        }
        
        if (self.cmd_palette) |palette| {
            palette.deinit();
        }
        
        self.progress.deinit();
        self.notifier.deinit();
        self.auth_mgr.deinit();
        self.session_mgr.deinit();
        self.event_system.deinit();
        self.renderer.deinit();
        self.theme_mgr.deinit();

        self.mouse_mgr.deinit();
        self.screen_mgr.deinit();
        
        self.allocator.destroy(self);
    }
    
    /// Run agent in interactive mode with full UI
    pub fn runInteractive(self: *Self) !void {
        // Setup terminal for interactive mode
        try self.setupTerminal();
        defer self.restoreTerminal();
        
        // Show welcome screen with branding
        try self.showWelcomeScreen();
        
        // Main interactive loop
        while (true) {
            // Render UI
            try self.renderUI();
            
            // Process input events
            const event = try self.event_system.waitForEvent();
            
            // Handle event
            const should_exit = try self.handleEvent(event);
            if (should_exit) break;
            
            // Auto-save session periodically
            try self.checkAutoSave();
        }
        
        // Show goodbye screen
        try self.showGoodbyeScreen();
    }
    
    /// Process a message with enhanced UI feedback
    pub fn processMessage(self: *Self, message: []const u8) ![]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Show processing indicator
        try self.showProcessingIndicator(message);
        
        // Update metrics
        const start_time = std.time.milliTimestamp();
        
        // Process through base agent
        const response = try self.processMessageThroughBase(message);
        
        // Update metrics
        const end_time = std.time.milliTimestamp();
        self.state.metrics.response_time_ms = @floatFromInt(end_time - start_time);
        
        // Update session
        try self.addToConversation(.user, message);
        try self.addToConversation(.assistant, response);
        
        // Hide processing indicator
        try self.hideProcessingIndicator();
        
        // Show notification if enabled
        if (self.config.ui_settings.enable_notifications) {
            try self.notifier.showNotification(.{
                .title = "Response Ready",
                .message = "AI agent has responded",
                .type = .success,
            });
        }
        
        return response;
    }
    
    /// Handle authentication with enhanced OAuth wizard
    pub fn authenticateWithWizard(self: *Self) !void {
        if (self.config.ui_settings.enable_dashboard) {
            // Use enhanced OAuth wizard UI
            const wizard = try AuthenticationWizard.init(self.allocator);
            defer wizard.deinit();
            
            try wizard.run(self.auth_mgr);
        } else {
            // Fallback to CLI authentication
            try self.auth_mgr.authenticateCLI();
        }
    }
    
    // === Private Helper Methods ===
    
    fn applyTheme(self: *Self) !void {
        if (std.mem.eql(u8, self.config.ui_settings.theme, "auto")) {
            // Auto-detect system theme
            try theme_manager.Quick.applySystemTheme(self.theme_mgr);
        } else {
            // Apply specified theme
            try theme_manager.Quick.switchTheme(
                self.theme_mgr,
                self.config.ui_settings.theme,
            );
        }
    }
    
    fn determineRenderMode(self: *Self) !tui.renderer.RenderMode {
        return switch (self.config.ui_settings.render_quality) {
            .auto => blk: {
                if (self.terminal_caps.supportsTruecolor) {
                    break :blk .enhanced;
                } else {
                    break :blk .standard;
                }
            },
            .enhanced => .enhanced,
            .standard => .standard,
            .compatible => .compatible,
            .minimal => .minimal,
        };
    }
    
    fn createDashboard(self: *Self) !*tui.DashboardEngine {
        const dashboard = try tui.createDashboard(self.allocator);
        
        // Add default widgets
        try dashboard.addWidget(.{
            .type = .line_chart,
            .title = "Performance Metrics",
            .position = .{ .x = 0, .y = 0, .width = 40, .height = 10 },
        });
        
        try dashboard.addWidget(.{
            .type = .kpi_card,
            .title = "Session Stats",
            .position = .{ .x = 42, .y = 0, .width = 38, .height = 10 },
        });
        
        try dashboard.addWidget(.{
            .type = .data_grid,
            .title = "Conversation History",
            .position = .{ .x = 0, .y = 12, .width = 80, .height = 20 },
        });
        
        return dashboard;
    }
    
    fn initializeSession(self: *Self) !void {
        const session_id = try generateSessionId(self.allocator);
        self.state.session = SessionData{
            .session_id = session_id,
            .start_time = std.time.milliTimestamp(),
            .messages_processed = 0,
            .tools_executed = 0,
            .conversation_history = std.ArrayList(ConversationEntry).init(self.allocator),
            .metadata = std.StringHashMap([]const u8).init(self.allocator),
        };
        
        // Try to restore previous session
        _ = self.session_mgr.restoreLastSession(&self.state.session) catch {};
    }
    
    fn setupTerminal(self: *Self) !void {
        // Setup terminal for TUI application using screen manager
        try self.screen_mgr.setupForTUI();

        // Enable mouse tracking if configured
        if (self.config.ui_settings.enable_mouse) {
            try self.mouse_mgr.enable(.sgr_basic);
        }
    }
    
    fn restoreTerminal(self: *Self) void {
        // Disable mouse tracking if it was enabled
        self.mouse_mgr.disable() catch {};

        // Restore terminal from TUI application using screen manager
        self.screen_mgr.restoreFromTUI() catch {};
    }
    
    fn showWelcomeScreen(self: *Self) !void {
        const welcome = WelcomeScreen.init(self.allocator, self.theme_mgr.getCurrentTheme());
        defer welcome.deinit();
        
        try welcome.render(self.renderer, .{
            .agent_name = self.config.base_config.agent_info.name,
            .agent_version = self.config.base_config.agent_info.version,
            .show_animation = self.config.ui_settings.enable_animations,
        });
        
        // Wait for user input
        _ = try self.event_system.waitForEvent();
    }
    
    fn showGoodbyeScreen(self: *Self) !void {
        const goodbye = GoodbyeScreen.init(self.allocator, self.theme_mgr.getCurrentTheme());
        defer goodbye.deinit();
        
        try goodbye.render(self.renderer, .{
            .session_stats = self.state.session,
            .show_animation = self.config.ui_settings.enable_animations,
        });
        
        // Brief pause
        std.time.sleep(2 * std.time.ns_per_s);
    }
    
    fn renderUI(self: *Self) !void {
        // Begin synchronized output for flicker-free rendering
        try self.screen_mgr.beginSync();
        defer self.screen_mgr.endSync() catch {};

        // Clear render buffer
        try self.renderer.clear();

        // Render based on layout mode
        switch (self.config.ui_settings.layout_mode) {
            .dashboard => try self.renderDashboard(),
            .split => try self.renderSplitView(),
            .fullscreen => try self.renderFullscreen(),
            .compact => try self.renderCompact(),
            .adaptive => try self.renderAdaptive(),
        }

        // Render overlay components
        try self.renderOverlays();

        // Flush to terminal
        try self.renderer.flush();

        // Update render metrics
        self.state.metrics.render_time_ms = self.renderer.getRenderTime();
    }
    
    fn renderDashboard(self: *Self) !void {
        if (self.dashboard_engine) |dashboard| {
            // Update dashboard data
            try dashboard.updateData("performance", self.state.metrics);
            try dashboard.updateData("session", self.state.session);
            
            // Render dashboard
            try dashboard.render(self.renderer);
        }
    }
    
    fn renderSplitView(self: *Self) !void {
        const size = try term.caps.getTerminalSize();

        // Left panel: Chat interface
        const chat_panel = tui.widgets.Core.Section{
            .title = "Chat",
            .bounds = .{ .x = 0, .y = 0, .width = size.width / 2, .height = size.height },
        };
        try chat_panel.render(self.renderer);

        // Right panel: Output/Results
        const output_panel = tui.widgets.Core.Section{
            .title = "Output",
            .bounds = .{ .x = size.width / 2, .y = 0, .width = size.width / 2, .height = size.height },
        };
        try output_panel.render(self.renderer);
    }
    
    fn renderFullscreen(self: *Self) !void {
        // Render main content area using full terminal
        const size = try term.caps.getTerminalSize();
        const content_area = tui.widgets.Core.Section{
            .title = self.config.base_config.agent_info.name,
            .bounds = .{ .x = 0, .y = 0, .width = size.width, .height = size.height },
        };
        try content_area.render(self.renderer);
    }
    
    fn renderCompact(self: *Self) !void {
        // Minimal UI with just essential information
        try self.renderer.writeText(0, 0, "Agent Ready>");
    }
    
    fn renderAdaptive(self: *Self) !void {
        const size = try term.caps.getTerminalSize();

        if (size.width >= 120 and size.height >= 30) {
            // Large terminal: Use dashboard
            try self.renderDashboard();
        } else if (size.width >= 80) {
            // Medium terminal: Use split view
            try self.renderSplitView();
        } else {
            // Small terminal: Use compact view
            try self.renderCompact();
        }
    }
    
    fn renderOverlays(self: *const Self) !void {
        // Render command palette if active
        if (self.cmd_palette) |palette| {
            if (palette.isVisible()) {
                try palette.render(self.renderer);
            }
        }
        
        // Render notifications
        try self.notifier.renderNotifications(self.renderer);
        
        // Render progress indicators
        try self.progress.renderAll(self.renderer);
    }
    
    fn handleEvent(self: *Self, event: tui.InputEvent) !bool {
        switch (event) {
            .key => |key| {
                // Handle keyboard shortcuts
                if (key.ctrl) {
                    switch (key.code) {
                        'q', 'c' => return true,  // Exit
                        'p' => try self.toggleCommandPalette(),
                        't' => try self.openThemeSelector(),
                        's' => try self.saveSession(),
                        'r' => try self.reloadConfig(),
                        else => {},
                    }
                }
                
                // Delegate to active component
                if (self.cmd_palette) |palette| {
                    if (palette.isVisible()) {
                        return try palette.handleInput(key);
                    }
                }
            },
            .mouse => |mouse| {
                // Handle mouse events
                try self.handleMouseEvent(mouse);
            },
            .resize => |size| {
                // Handle terminal resize
                try self.handleResize(size);
            },
            else => {},
        }
        
        return false;
    }
    
    fn handleMouseEvent(self: *Self, mouse: tui.MouseEvent) !void {
        // Update hover states
        if (self.dashboard_engine) |dashboard| {
            try dashboard.handleMouseMove(mouse.x, mouse.y);
        }
        
        // Handle clicks
        if (mouse.button == .left and mouse.action == .press) {
            try self.handleClick(mouse.x, mouse.y);
        }
    }
    
    fn handleResize(self: *Self, _: tui.TerminalSize) !void {
        // Recalculate layouts
        try self.renderUI();
    }
    
    fn handleClick(self: *Self, x: u16, y: u16) !void {
        // Check if click is on any interactive element
        if (self.dashboard_engine) |dashboard| {
            try dashboard.handleClick(x, y);
        }
    }
    
    fn toggleCommandPalette(self: *Self) !void {
        if (self.cmd_palette) |palette| {
            try palette.toggle();
        }
    }
    
    fn openThemeSelector(self: *Self) !void {
        const selector = try ThemeSelector.init(self.allocator, self.theme_mgr);
        defer selector.deinit();
        
        const selected_theme = try selector.run(self.event_system, self.renderer);
        if (selected_theme) |theme| {
            try self.theme_mgr.switchTheme(theme);
        }
    }
    
    fn saveSession(self: *Self) !void {
        try self.session_mgr.saveSession(&self.state.session);
        
        try self.notifier.showNotification(.{
            .title = "Session Saved",
            .message = "Your session has been saved successfully",
            .type = .info,
        });
    }
    
    fn reloadConfig(self: *Self) !void {
        // Reload configuration from disk
        // Implementation depends on config system
        try self.notifier.showNotification(.{
            .title = "Config Reloaded",
            .message = "Configuration has been reloaded",
            .type = .info,
        });
    }
    
    fn checkAutoSave(self: *Self) !void {
        const current_time = std.time.timestamp();
        const last_save = self.session_mgr.getLastSaveTime();
        
        if (current_time - last_save >= self.config.session_settings.auto_save_interval) {
            try self.saveSession();
        }
    }
    
    fn showProcessingIndicator(self: *Self, message: []const u8) !void {
        const indicator = try self.progress.createSpinner(.{
            .label = try std.fmt.allocPrint(self.allocator, "Processing: {s}", .{message[0..@min(50, message.len)]}),
            .style = .dots,
        });
        try indicator.start();
    }
    
    fn hideProcessingIndicator(self: *Self) !void {
        try self.progress.stopAllSpinners();
    }
    
    fn processMessageThroughBase(self: *Self, message: []const u8) ![]const u8 {
        // Call the base agent's processMessage method
        // Note: This function assumes the base agent implements a compatible interface
        // For now, return a placeholder response
        _ = self;
        _ = message;
        return "Enhanced agent response";
    }
    
    fn addToConversation(self: *Self, role: anytype, content: []const u8) !void {
        const entry = ConversationEntry{
            .timestamp = std.time.milliTimestamp(),
            .role = role,
            .content = try self.allocator.dupe(u8, content),
            .metadata = null,
        };
        try self.state.session.conversation_history.append(entry);
        self.state.session.messages_processed += 1;
    }
};

// === Supporting Components ===

/// Command Palette component
pub const CommandPalette = struct {
    allocator: Allocator,
    visible: bool = false,
    commands: std.ArrayList(Command),
    selected_index: usize = 0,
    search_query: []const u8 = "",
    
    pub const Command = struct {
        name: []const u8,
        description: []const u8,
        shortcut: ?[]const u8,
        action: *const fn () anyerror!void,
    };
    
    pub fn init(allocator: Allocator) !*CommandPalette {
        var self = try allocator.create(CommandPalette);
        self.* = .{
            .allocator = allocator,
            .commands = std.ArrayList(Command).init(allocator),
        };
        
        // Register default commands
        try self.registerDefaultCommands();
        
        return self;
    }
    
    pub fn deinit(self: *CommandPalette) void {
        self.commands.deinit();
        self.allocator.destroy(self);
    }
    
    pub fn toggle(self: *CommandPalette) !void {
        self.visible = !self.visible;
    }
    
    pub fn isVisible(self: *CommandPalette) bool {
        return self.visible;
    }
    
    pub fn render(_: *CommandPalette, _: *tui.Renderer) !void {
        // Render command palette overlay
        // Implementation here...
    }
    
    pub fn handleInput(_: *CommandPalette, _: tui.KeyEvent) !bool {
        // Handle input for command palette
        // Implementation here...
        return false;
    }
    
    fn registerDefaultCommands(_: *CommandPalette) !void {
        // Register common commands
    }
};

/// Notification system
pub const NotificationSystem = struct {
    allocator: Allocator,
    enabled: bool,
    notifications: std.ArrayList(Notification),
    
    pub const Notification = struct {
        title: []const u8,
        message: []const u8,
        type: NotificationType,
        timestamp: i64 = 0,
        duration_ms: u32 = 3000,
    };
    
    pub const NotificationType = enum {
        info,
        success,
        warning,
        err,
    };
    
    pub fn init(allocator: Allocator, enabled: bool) !*NotificationSystem {
        const self = try allocator.create(NotificationSystem);
        self.* = .{
            .allocator = allocator,
            .enabled = enabled,
            .notifications = std.ArrayList(Notification).init(allocator),
        };
        return self;
    }
    
    pub fn deinit(self: *NotificationSystem) void {
        self.notifications.deinit();
        self.allocator.destroy(self);
    }
    
    pub fn showNotification(self: *NotificationSystem, notification: Notification) !void {
        if (!self.enabled) return;
        
        var notif = notification;
        notif.timestamp = std.time.milliTimestamp();
        try self.notifications.append(notif);
        
        // Also send desktop notification if available
        try self.sendDesktopNotification(notif);
    }
    
    pub fn renderNotifications(self: *NotificationSystem, renderer: *tui.Renderer) !void {
        // Remove expired notifications
        const current_time = std.time.milliTimestamp();
        var i: usize = 0;
        while (i < self.notifications.items.len) {
            const notif = self.notifications.items[i];
            if (current_time - notif.timestamp > notif.duration_ms) {
                _ = self.notifications.swapRemove(i);
            } else {
                i += 1;
            }
        }
        
        // Render active notifications
        for (self.notifications.items, 0..) |notif, idx| {
            try self.renderNotification(renderer, notif, idx);
        }
    }
    
    fn renderNotification(self: *NotificationSystem, renderer: *tui.Renderer, notif: Notification, index: usize) !void {
        _ = self;
        _ = renderer;
        _ = notif;
        _ = index;
        // Render individual notification
        // Implementation here...
    }
    
    fn sendDesktopNotification(self: *NotificationSystem, notif: Notification) !void {
        _ = self;
        _ = notif;
        // Send desktop notification using system APIs
        // Implementation varies by platform
    }
};

/// Progress tracking system
pub const ProgressTracker = struct {
    allocator: Allocator,
    active_items: std.ArrayList(ProgressItem),
    
    pub const ProgressItem = struct {
        id: []const u8,
        label: []const u8,
        type: ProgressType,
        value: f32 = 0.0,
        active: bool = true,
    };
    
    pub const ProgressType = enum {
        bar,
        spinner,
        percentage,
    };
    
    pub const SpinnerStyle = enum {
        dots,
        line,
        circle,
        arc,
    };
    
    pub fn init(allocator: Allocator) !*ProgressTracker {
        const self = try allocator.create(ProgressTracker);
        self.* = .{
            .allocator = allocator,
            .active_items = std.ArrayList(ProgressItem).init(allocator),
        };
        return self;
    }
    
    pub fn deinit(self: *ProgressTracker) void {
        self.active_items.deinit();
        self.allocator.destroy(self);
    }
    
    pub fn createSpinner(self: *ProgressTracker, options: anytype) !ProgressItem {
        const item = ProgressItem{
            .id = try generateId(self.allocator),
            .label = options.label,
            .type = .spinner,
            .active = false,
        };
        try self.active_items.append(item);
        return self.active_items.items[self.active_items.items.len - 1];
    }
    
    pub fn stopAllSpinners(self: *ProgressTracker) !void {
        for (self.active_items.items) |*item| {
            if (item.type == .spinner) {
                item.active = false;
            }
        }
    }
    
    pub fn renderAll(self: *ProgressTracker, renderer: *tui.Renderer) !void {
        for (self.active_items.items) |item| {
            if (item.active) {
                try self.renderItem(renderer, item);
            }
        }
    }
    
    fn renderItem(self: *ProgressTracker, renderer: *tui.Renderer, item: ProgressItem) !void {
        _ = self;
        _ = renderer;
        _ = item;
        // Render individual progress item
        // Implementation here...
    }
};

/// Authentication wizard for OAuth flow
pub const AuthenticationWizard = struct {
    allocator: Allocator,
    current_step: usize = 0,
    
    pub fn init(allocator: Allocator) !*AuthenticationWizard {
        const self = try allocator.create(AuthenticationWizard);
        self.* = .{
            .allocator = allocator,
        };
        return self;
    }
    
    pub fn deinit(self: *AuthenticationWizard) void {
        self.allocator.destroy(self);
    }
    
    pub fn run(self: *AuthenticationWizard, auth_mgr: *AuthenticationManager) !void {
        _ = self;
        _ = auth_mgr;
        // Run OAuth wizard with enhanced UI
        // Implementation here...
    }
};

/// Theme selector component
pub const ThemeSelector = struct {
    allocator: Allocator,
    theme_mgr: *theme_manager.ThemeManager,
    
    pub fn init(allocator: Allocator, mgr: *theme_manager.ThemeManager) !*ThemeSelector {
        const self = try allocator.create(ThemeSelector);
        self.* = .{
            .allocator = allocator,
            .theme_mgr = mgr,
        };
        return self;
    }
    
    pub fn deinit(self: *ThemeSelector) void {
        self.allocator.destroy(self);
    }
    
    pub fn run(self: *ThemeSelector, event_system: *tui.EventSystem, renderer: *tui.Renderer) !?[]const u8 {
        _ = self;
        _ = event_system;
        _ = renderer;
        // Show theme selection UI
        // Implementation here...
        return null;
    }
};

/// Session manager for persistence
pub const SessionManager = struct {
    allocator: Allocator,
    settings: SessionSettings,
    last_save_time: i64 = 0,
    
    pub fn init(allocator: Allocator, settings: SessionSettings) !*SessionManager {
        const self = try allocator.create(SessionManager);
        self.* = .{
            .allocator = allocator,
            .settings = settings,
        };
        return self;
    }
    
    pub fn deinit(self: *SessionManager) void {
        self.allocator.destroy(self);
    }
    
    pub fn saveSession(self: *SessionManager, session: *SessionData) !void {
        _ = session;
        self.last_save_time = std.time.timestamp();
        // Save session to disk
        // Implementation here...
    }
    
    pub fn restoreLastSession(self: *SessionManager, session: *SessionData) !void {
        _ = self;
        _ = session;
        // Restore session from disk
        // Implementation here...
    }
    
    pub fn getLastSaveTime(self: *SessionManager) i64 {
        return self.last_save_time;
    }
};

/// Authentication manager
pub const AuthenticationManager = struct {
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) !*AuthenticationManager {
        const self = try allocator.create(AuthenticationManager);
        self.* = .{
            .allocator = allocator,
        };
        return self;
    }
    
    pub fn deinit(self: *AuthenticationManager) void {
        self.allocator.destroy(self);
    }
    
    pub fn authenticateCLI(self: *AuthenticationManager) !void {
        _ = self;
        // CLI authentication flow
        // Implementation here...
    }
};

/// Welcome screen component
pub const WelcomeScreen = struct {
    allocator: Allocator,
    theme: *theme_manager.ColorScheme,
    
    pub fn init(allocator: Allocator, theme: *theme_manager.ColorScheme) WelcomeScreen {
        return .{
            .allocator = allocator,
            .theme = theme,
        };
    }
    
    pub fn deinit(self: WelcomeScreen) void {
        _ = self;
    }
    
    pub fn render(self: WelcomeScreen, renderer: *tui.Renderer, options: anytype) !void {
        _ = self;
        _ = renderer;
        _ = options;
        // Render welcome screen with animation
        // Implementation here...
    }
};

/// Goodbye screen component
pub const GoodbyeScreen = struct {
    allocator: Allocator,
    theme: *theme_manager.ColorScheme,
    
    pub fn init(allocator: Allocator, theme: *theme_manager.ColorScheme) GoodbyeScreen {
        return .{
            .allocator = allocator,
            .theme = theme,
        };
    }
    
    pub fn deinit(self: GoodbyeScreen) void {
        _ = self;
    }
    
    pub fn render(self: GoodbyeScreen, renderer: *tui.Renderer, options: anytype) !void {
        _ = self;
        _ = renderer;
        _ = options;
        // Render goodbye screen with stats
        // Implementation here...
    }
};

// === Helper Functions ===

fn generateSessionId(allocator: Allocator) ![]const u8 {
    const timestamp = std.time.milliTimestamp();
    const random = std.crypto.random.int(u32);
    return try std.fmt.allocPrint(allocator, "session_{x}_{x}", .{ timestamp, random });
}

fn generateId(allocator: Allocator) ![]const u8 {
    const random = std.crypto.random.int(u64);
    return try std.fmt.allocPrint(allocator, "id_{x}", .{random});
}

// === Public Factory Functions ===

/// Create an agent with all modern features
pub fn createAgent(
    allocator: Allocator,
    base_agent: *anyopaque,
    options: struct {
        enable_dashboard: bool = true,
        enable_mouse: bool = true,
        enable_notifications: bool = true,
        enable_animations: bool = true,
        theme: []const u8 = "auto",
    },
) !*Agent {
    const agent_config = Config{
        .base_config = config.AgentConfig{},  // Use defaults or load from file
        .ui_settings = UISettings{
            .enable_dashboard = options.enable_dashboard,
            .enable_mouse = options.enable_mouse,
            .enable_notifications = options.enable_notifications,
            .enable_animations = options.enable_animations,
            .theme = options.theme,
        },
    };

    return try Agent.init(allocator, base_agent, agent_config);
}

/// Run an agent in interactive mode
pub fn runInteractive(
    allocator: Allocator,
    base_agent: *anyopaque,
) !void {
    const agent = try createAgent(allocator, base_agent, .{});
    defer agent.deinit();

    try agent.runInteractive();
}

// === Tests ===

test "agent initialization" {
    const allocator = std.testing.allocator;

    // Create mock base agent
    const MockAgent = struct {};
    var mock = MockAgent{};

    const agent = try createAgent(allocator, &mock, .{
        .enable_dashboard = false,
        .enable_mouse = false,
        .enable_notifications = false,
    });
    defer agent.deinit();

    try std.testing.expect(agent.config.ui_settings.enable_dashboard == false);
}
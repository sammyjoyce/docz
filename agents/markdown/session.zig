//! Improved Interactive Session for Markdown Agent
//!
//! An interactive session that provides a significantly better user experience
//! with progressive disclosure, interactive tool discovery, contextual help, and workflow automation.
//!
//! ## Key UX Improvements
//!
//! ### 1. Simplified Onboarding Experience
//! - **Progressive disclosure**: Start with essential features, reveal more options gradually
//! - **Interactive tutorial**: Context-sensitive guidance for new users
//! - **Welcome wizard**: Personalized setup based on user preferences
//! - **Quick start templates**: Pre-configured workflows for common use cases
//!
//! ### 2. Interactive Tool Discovery System
//! - **Visual grid layout**: Tools organized in an intuitive grid with icons and descriptions
//! - **Smart categorization**: Tools grouped by functionality (editing, formatting, analysis, etc.)
//! - **Search and filter**: Find tools quickly with fuzzy search
//! - **Tool previews**: See what each tool does before using it
//! - **Usage statistics**: Most-used tools highlighted for easy access
//!
//! ### 3. Contextual Help System
//! - **Adaptive help**: Help content changes based on current user actions
//! - **Inline tooltips**: Hover over UI elements for instant guidance
//! - **Contextual shortcuts**: Keyboard shortcuts relevant to current context
//! - **Progressive hints**: Subtle suggestions that become more prominent as needed
//!
//! ### 4. Unified Command Palette
//! - **Fuzzy search**: Find commands quickly with intelligent matching
//! - **Command categories**: Organize commands by type and frequency of use
//! - **Recent commands**: Quick access to recently used commands
//! - **Command chaining**: Execute multiple commands in sequence
//! - **Keyboard navigation**: Full keyboard control with arrow keys and shortcuts
//!
//! ### 5. Workflow Automation
//! - **Template workflows**: Pre-built automation for common markdown tasks
//! - **Macro recording**: Record and replay sequences of actions
//! - **Smart suggestions**: AI-powered recommendations for next steps
//! - **Batch operations**: Apply operations to multiple files or sections
//! - **Workflow sharing**: Save and share custom workflows
//!
//! ### 6. Visual Feedback
//! - **Real-time previews**: See changes instantly as you type
//! - **Progress indicators**: Clear feedback for long-running operations
//! - **Status animations**: Smooth transitions and loading states
//! - **Error highlighting**: Clear indication of issues with helpful suggestions
//! - **Success confirmations**: Positive feedback for completed actions
//!
//! ## Architecture
//!
//! The session builds upon the existing InteractiveSession and integrates
//! with TUI components, notification systems, and workflow automation.
//!
//! Key components:
//! - **InteractiveSession** - Main session controller with UX enhancements
//! - **OnboardingWizard** - Progressive disclosure onboarding system
//! - **ToolDiscoveryGrid** - Visual tool discovery with grid layout
//! - **ContextualHelpSystem** - Adaptive help that responds to user context
//! - **CommandPalette** - Command palette with fuzzy search
//! - **WorkflowAutomation** - Template and custom workflow management
//! - **VisualFeedbackSystem** - Comprehensive visual feedback and animations

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = Thread.Mutex;

// Core modules
const agent_interface = @import("agent_interface");
const config = @import("foundation").config;

// Shared infrastructure
const tui = @import("foundation").tui;
const render = @import("foundation").render;
const ui = @import("foundation").ui;

// TUI components - use barrel exports from foundation.tui
const dashboard = tui.dashboard;
const notification_system = tui.notifications;
const modal = tui.Modal;
const split_pane = tui.split_pane;
const file_tree = tui.file_tree;
const canvas_mod = tui.canvas;

// UI components - use barrel exports from foundation.ui
const input_component = components.Widgets.Input;

// Command palette and progress tracker from TUI components
const command_palette = tui.components.CommandPalette;
const progress_tracker = tui.components.ProgressTracker;

// Markdown agent specific
const markdown_tools = @import("tools.zig");
const ContentEditor = @import("tools/content_editor.zig");
const Validate = @import("tools/validate.zig");
const document_tool = @import("tools/document.zig");
const markdown_editor = @import("markdown_editor.zig");

// Common utilities
const fs = @import("lib/fs.zig");
const link = @import("lib/link.zig");
const meta = @import("lib/meta.zig");
const foundation = @import("foundation");
const table = foundation.tools.table;
const template = @import("lib/template.zig");
const text_utils = @import("lib/text.zig");

/// Interactive Session Configuration
pub const SessionConfig = struct {
    /// Base agent configuration
    base_config: agent_interface.Config,

    /// Onboarding configuration
    onboarding_config: OnboardingConfig = .{},

    /// Tool discovery configuration
    tool_discovery_config: ToolDiscoveryConfig = .{},

    /// Help system configuration
    help_config: HelpConfig = .{},

    /// Command palette configuration
    command_palette_config: CommandPaletteConfig = .{},

    /// Workflow automation configuration
    workflow_config: WorkflowConfig = .{},

    /// Visual feedback configuration
    feedback_config: FeedbackConfig = .{},

    /// Dashboard settings
    dashboard_config: DashboardConfig = .{},

    /// Layout configuration
    layout_config: LayoutConfig = .{},

    /// Preview settings
    preview_config: PreviewConfig = .{},

    /// Metrics and monitoring
    metrics_config: MetricsConfig = .{},

    /// Session management
    session_config: SessionManagementConfig = .{},

    /// Input handling
    input_config: InputConfig = .{},

    /// Notification settings
    notification_config: NotificationConfig = .{},

    /// Theme and appearance
    theme_config: ThemeSettings = .{},

    /// Performance settings
    performance_config: PerformanceConfig = .{},

    /// Accessibility options
    accessibility_config: AccessibilityConfig = .{},

    /// UX enhancement settings
    ux_config: UXConfig = .{},
};

/// Onboarding configuration
pub const OnboardingConfig = struct {
    /// Enable onboarding wizard
    enabled: bool = true,

    /// Show welcome screen
    show_welcome: bool = true,

    /// Enable interactive tutorial
    interactive_tutorial: bool = true,

    /// Progressive disclosure level
    disclosure_level: DisclosureLevel = .beginner,

    /// Quick start templates
    quick_start_templates: bool = true,

    /// Personalized recommendations
    personalized_recommendations: bool = true,

    /// Onboarding completion tracking
    track_completion: bool = true,
};

/// Progressive disclosure levels
pub const DisclosureLevel = enum {
    beginner,
    intermediate,
    advanced,
    expert,
};

/// Tool discovery configuration
pub const ToolDiscoveryConfig = struct {
    /// Enable tool discovery grid
    enabled: bool = true,

    /// Grid layout mode
    layout_mode: GridLayoutMode = .adaptive,

    /// Tool categories to show
    categories: []const ToolCategory = &[_]ToolCategory{ .editing, .formatting, .analysis, .automation },

    /// Show tool usage statistics
    show_usage_stats: bool = true,

    /// Enable tool previews
    tool_previews: bool = true,

    /// Search and filter options
    search_enabled: bool = true,

    /// Maximum tools per category
    max_tools_per_category: usize = 8,
};

/// Grid layout modes
pub const GridLayoutMode = enum {
    compact,
    comfortable,
    adaptive,
};

/// Tool categories for discovery
pub const ToolCategory = enum {
    editing,
    formatting,
    analysis,
    automation,
    collaboration,
    file_export,
};

/// Help system configuration
pub const HelpConfig = struct {
    /// Enable contextual help
    enabled: bool = true,

    /// Adaptive help level
    adaptive_level: AdaptiveHelpLevel = .balanced,

    /// Show inline tooltips
    inline_tooltips: bool = true,

    /// Contextual shortcuts
    contextual_shortcuts: bool = true,

    /// Progressive hints
    progressive_hints: bool = true,

    /// Help animation style
    animation_style: HelpAnimationStyle = .subtle,
};

/// Adaptive help levels
pub const AdaptiveHelpLevel = enum {
    minimal,
    balanced,
    comprehensive,
};

/// Help animation styles
pub const HelpAnimationStyle = enum {
    none,
    subtle,
    prominent,
};

/// Command palette configuration
pub const CommandPaletteConfig = struct {
    /// Enable fuzzy search
    fuzzy_search: bool = true,

    /// Show command categories
    show_categories: bool = true,

    /// Recent commands history
    recent_commands: bool = true,

    /// Command chaining
    command_chaining: bool = true,

    /// Keyboard navigation
    keyboard_navigation: bool = true,

    /// Maximum suggestions
    max_suggestions: usize = 10,

    /// Search debounce time (ms)
    search_debounce_ms: u32 = 150,
};

/// Workflow automation configuration
pub const WorkflowConfig = struct {
    /// Enable workflow automation
    enabled: bool = true,

    /// Template workflows
    template_workflows: bool = true,

    /// Macro recording
    macro_recording: bool = true,

    /// Smart suggestions
    smart_suggestions: bool = true,

    /// Batch operations
    batch_operations: bool = true,

    /// Workflow sharing
    workflow_sharing: bool = true,

    /// Maximum stored workflows
    max_workflows: usize = 20,
};

/// Visual feedback configuration
pub const FeedbackConfig = struct {
    /// Enable real-time previews
    real_time_previews: bool = true,

    /// Progress indicators
    progress_indicators: bool = true,

    /// Status animations
    status_animations: bool = true,

    /// Error highlighting
    error_highlighting: bool = true,

    /// Success confirmations
    success_confirmations: bool = true,

    /// Animation duration (ms)
    animation_duration_ms: u32 = 300,

    /// Feedback intensity
    intensity: FeedbackIntensity = .balanced,
};

/// Feedback intensity levels
pub const FeedbackIntensity = enum {
    subtle,
    balanced,
    prominent,
};

/// UX enhancement configuration
pub const UXConfig = struct {
    /// Enable smooth transitions
    smooth_transitions: bool = true,

    /// Hover effects
    hover_effects: bool = true,

    /// Focus indicators
    focus_indicators: bool = true,

    /// Gesture support
    gesture_support: bool = false,

    /// Voice commands
    voice_commands: bool = false,

    /// Accessibility enhancements
    accessibility_enhancements: bool = true,
};

/// Dashboard configuration
pub const DashboardConfig = struct {
    /// Enable dashboard mode
    enabled: bool = true,

    /// Dashboard title
    title: []const u8 = "Markdown Interactive Session",

    /// Auto-refresh interval in ms
    refresh_interval_ms: u64 = 1000,

    /// Enable animations
    enable_animations: bool = true,

    /// Enable mouse interactions
    enable_mouse: bool = true,

    /// Show welcome screen on startup
    show_welcome: bool = true,

    /// Default layout mode
    default_layout: LayoutMode = .dashboard,
};

/// Layout modes
pub const LayoutMode = enum {
    /// Full dashboard with all panes
    dashboard,

    /// Editor-focused with minimal dashboard
    editor_focus,

    /// Preview-focused layout
    preview_focus,

    /// Split view with editor and preview
    split_view,

    /// Minimal interface
    minimal,

    /// Tool discovery focused
    tool_discovery,

    /// Workflow automation focused
    workflow_focus,
};

/// Layout configuration
pub const LayoutConfig = struct {
    /// Pane sizes and positions
    pane_sizes: PaneSizes = .{},

    /// Enable resizable panes
    resizable_panes: bool = true,

    /// Minimum pane sizes
    min_pane_sizes: MinPaneSizes = .{},

    /// Layout mode
    mode: LayoutMode = .dashboard,

    /// Show pane borders
    show_borders: bool = true,

    /// Border style
    border_style: BorderStyle = .single,
};

/// Pane sizes configuration
pub const PaneSizes = struct {
    /// Editor pane width ratio (0.0-1.0)
    editor_width_ratio: f32 = 0.6,

    /// Preview pane width ratio (0.0-1.0)
    preview_width_ratio: f32 = 0.4,

    /// Sidebar width in characters
    sidebar_width: u16 = 30,

    /// Metrics panel height
    metrics_height: u16 = 8,

    /// Status bar height
    status_height: u16 = 1,

    /// Command palette height
    command_palette_height: u16 = 12,

    /// Tool discovery grid height
    tool_grid_height: u16 = 15,

    /// Help panel width
    help_panel_width: u16 = 25,
};

/// Minimum pane sizes
pub const MinPaneSizes = struct {
    editor_min_width: u16 = 40,
    preview_min_width: u16 = 30,
    sidebar_min_width: u16 = 20,
    metrics_min_height: u16 = 6,
    tool_grid_min_height: u16 = 10,
    help_panel_min_width: u16 = 20,
};

/// Border styles
pub const BorderStyle = enum {
    none,
    single,
    double,
    rounded,
    thick,
};

/// Preview configuration
pub const PreviewConfig = struct {
    /// Enable live preview
    live_preview: bool = true,

    /// Preview update delay in ms
    update_delay_ms: u32 = 300,

    /// Enable adaptive rendering
    adaptive_rendering: bool = true,

    /// Preview render mode
    render_mode: PreviewRenderMode = .full,

    /// Enable syntax highlighting in preview
    syntax_highlighting: bool = true,

    /// Enable math rendering
    enable_math: bool = true,

    /// Enable mermaid diagrams
    enable_mermaid: bool = true,

    /// Enable image previews
    enable_images: bool = true,

    /// Custom CSS for preview
    custom_css: ?[]const u8 = null,

    /// Zoom level for preview
    zoom_level: f32 = 1.0,
};

/// Preview render modes
pub const PreviewRenderMode = enum {
    /// Plain text
    plain,

    /// Text-only markdown formatting
    text,

    /// Full rendering with graphics
    full,

    /// Print-optimized layout
    print,
};

/// Metrics configuration
pub const MetricsConfig = struct {
    /// Enable metrics collection
    enabled: bool = true,

    /// Show live sparklines
    show_sparklines: bool = true,

    /// Metrics update interval in ms
    update_interval_ms: u64 = 1000,

    /// Maximum metrics history
    max_history: usize = 100,

    /// Show token usage
    show_tokens: bool = true,

    /// Show costs
    show_costs: bool = true,

    /// Show response times
    show_response_times: bool = true,

    /// Show document complexity
    show_complexity: bool = true,
};

/// Session management configuration
pub const SessionManagementConfig = struct {
    /// Enable session saving
    enable_session_save: bool = true,

    /// Session save interval in seconds
    save_interval_s: u32 = 60,

    /// Maximum session history
    max_history: usize = 1000,

    /// Enable version history
    enable_version_history: bool = true,

    /// Maximum versions to keep
    max_versions: usize = 50,

    /// Enable auto-backup
    enable_auto_backup: bool = true,

    /// Backup interval in seconds
    backup_interval_s: u32 = 300,

    /// Maximum backups to keep
    max_backups: usize = 10,
};

/// Input configuration
pub const InputConfig = struct {
    /// Enable smart input
    input_component: bool = true,

    /// Enable auto-completion
    auto_completion: bool = true,

    /// Completion delay in ms
    completion_delay_ms: u32 = 500,

    /// Enable fuzzy search in command palette
    fuzzy_search: bool = true,

    /// Maximum completion suggestions
    max_suggestions: usize = 10,

    /// Enable context-aware completions
    context_aware: bool = true,

    /// Enable tag-based management
    tag_management: bool = true,

    /// Custom keyboard shortcuts
    custom_shortcuts: std.StringHashMap([]const u8) = undefined,
};

/// Notification configuration
pub const NotificationConfig = struct {
    /// Enable notifications
    enabled: bool = true,

    /// Notification duration in ms
    duration_ms: u32 = 3000,

    /// Maximum concurrent notifications
    max_concurrent: usize = 5,

    /// Enable desktop notifications
    desktop_notifications: bool = false,

    /// Notification position
    position: NotificationPosition = .top_right,

    /// Enable sound notifications
    sound_notifications: bool = false,
};

/// Notification positions
pub const NotificationPosition = enum {
    top_left,
    top_right,
    bottom_left,
    bottom_right,
    center,
};

/// Theme configuration
pub const ThemeSettings = struct {
    /// Theme name
    name: []const u8 = "dark",

    /// Enable theme switching
    enable_switching: bool = true,

    /// Custom theme overrides
    custom_overrides: std.StringHashMap([]const u8) = undefined,

    /// Enable accessibility themes
    accessibility_themes: bool = true,

    /// High contrast mode
    high_contrast: bool = false,
};

/// Performance configuration
pub const PerformanceConfig = struct {
    /// Enable background processing
    background_processing: bool = true,

    /// Maximum background threads
    max_background_threads: u32 = 4,

    /// Preview rendering quality
    preview_quality: RenderQuality = .high,

    /// Enable caching
    enable_caching: bool = true,

    /// Cache size in MB
    cache_size_mb: usize = 100,

    /// Enable lazy loading
    lazy_loading: bool = true,
};

/// Render quality levels
pub const RenderQuality = enum {
    low,
    medium,
    high,
    ultra,
};

/// Accessibility configuration
pub const AccessibilityConfig = struct {
    /// Enable screen reader support
    screen_reader: bool = false,

    /// High contrast mode
    high_contrast: bool = false,

    /// Large text mode
    large_text: bool = false,

    /// Reduced motion
    reduced_motion: bool = false,

    /// Keyboard navigation only
    keyboard_only: bool = false,

    /// Focus indicators
    focus_indicators: bool = true,

    /// Skip links
    skip_links: bool = true,
};

/// Interactive Session
pub const InteractiveSession = struct {
    /// Memory allocator
    allocator: Allocator,

    /// Agent interface
    agent: *agent_interface.Agent,

    /// Session configuration
    config: SessionConfig,

    /// Enhanced markdown editor
    editor: *markdown_editor.MarkdownEditor,

    /// Dashboard instance
    dashboard: *dashboard.Dashboard,

    /// Command palette
    command_palette: *CommandPalette,

    /// Notification system
    notification_system: *notification_system.NotificationController,

    /// Progress tracker
    progress_tracker: *progress_tracker.ProgressTracker,

    /// Layout manager
    layout: *Layout,

    /// Metrics collector
    metrics_collector: *MetricsCollector,

    /// Preview renderer
    preview_renderer: *PreviewRenderer,

    /// Outline navigator
    outline_navigator: *OutlineNavigator,

    /// Version history viewer
    version_viewer: *VersionHistoryViewer,

    /// Onboarding wizard
    onboarding_wizard: *OnboardingWizard,

    /// Tool discovery grid
    tool_discovery_grid: *ToolDiscoveryGrid,

    /// Contextual help system
    help_system: *ContextualHelpSystem,

    /// Workflow automation system
    workflow_system: *WorkflowAutomation,

    /// Visual feedback system
    feedback_system: *VisualFeedbackSystem,

    /// Session state
    state: SessionState,

    /// Thread for background tasks
    background_thread: ?Thread = null,

    /// Mutex for thread safety
    mutex: Mutex,

    const Self = @This();

    /// Initialize the interactive session
    pub fn init(
        allocator: Allocator,
        agent: *agent_interface.Agent,
        session_config: SessionConfig,
    ) !*Self {
        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Initialize components
        const editor = try markdown_editor.MarkdownEditor.init(allocator, agent, session_config.base_config);
        errdefer editor.deinit();

        const dashboard_instance = try dashboard.Dashboard.init(allocator, .{
            .title = session_config.dashboard_config.title,
            .refresh_rate_ms = session_config.dashboard_config.refresh_interval_ms,
            .enable_animations = session_config.dashboard_config.enable_animations,
            .enable_mouse = session_config.dashboard_config.enable_mouse,
            .enable_notifications = session_config.notification_config.enabled,
            .theme_name = session_config.theme_config.name,
        });
        errdefer dashboard_instance.deinit();

        const cmd_palette = try CommandPalette.init(allocator, session_config.command_palette_config);
        errdefer cmd_palette.deinit();

        const notifications = try notification_system.NotificationController.init(allocator, undefined); // TODO: Pass renderer
        errdefer notifications.deinit();

        const progress = try progress_tracker.ProgressTracker.init(allocator);
        errdefer progress.deinit();

        const layout_mgr = try Layout.init(allocator, session_config.layout_config);
        errdefer layout_mgr.deinit();

        const metrics = try MetricsCollector.init(allocator, session_config.metrics_config);
        errdefer metrics.deinit();

        const preview = try PreviewRenderer.init(allocator, session_config.preview_config);
        errdefer preview.deinit();

        const outline = try OutlineNavigator.init(allocator);
        errdefer outline.deinit();

        const version_viewer = try VersionHistoryViewer.init(allocator, session_config.session_config);
        errdefer version_viewer.deinit();

        // Initialize UX enhancement components
        const onboarding = try OnboardingWizard.init(allocator, session_config.onboarding_config);
        errdefer onboarding.deinit();

        const tool_grid = try ToolDiscoveryGrid.init(allocator, session_config.tool_discovery_config);
        errdefer tool_grid.deinit();

        const help_sys = try ContextualHelpSystem.init(allocator, session_config.help_config);
        errdefer help_sys.deinit();

        const workflow_sys = try WorkflowAutomation.init(allocator, session_config.workflow_config);
        errdefer workflow_sys.deinit();

        const feedback_sys = try VisualFeedbackSystem.init(allocator, session_config.feedback_config);
        errdefer feedback_sys.deinit();

        // Initialize session state
        const session_state = SessionState{
            .layout_mode = session_config.layout_config.mode,
            .active_pane = .editor,
            .last_activity = std.time.timestamp(),
            .session_start = std.time.timestamp(),
            .is_running = false,
            .onboarding_completed = false,
            .current_context = .general,
            .ux_state = .normal,
        };

        self.* = Self{
            .allocator = allocator,
            .agent = agent,
            .config = session_config,
            .editor = editor,
            .dashboard = dashboard_instance,
            .command_palette = cmd_palette,
            .notification_system = notifications,
            .progress_tracker = progress,
            .layout_manager = layout_mgr,
            .metrics_collector = metrics,
            .preview_renderer = preview,
            .outline_navigator = outline,
            .version_viewer = version_viewer,
            .onboarding_wizard = onboarding,
            .tool_discovery_grid = tool_grid,
            .help_system = help_sys,
            .workflow_system = workflow_sys,
            .feedback_system = feedback_sys,
            .state = session_state,
            .mutex = Mutex{},
        };

        // Setup dashboard widgets
        try self.setupDashboardWidgets();

        // Register commands
        try self.registerCommands();

        // Initialize tool discovery
        try self.initializeToolDiscovery();

        // Start background processing if enabled
        if (session_config.performance_config.background_processing) {
            self.background_thread = try Thread.spawn(.{}, backgroundWorker, .{self});
        }

        return self;
    }

    /// Deinitialize the session
    pub fn deinit(self: *Self) void {
        // Stop background thread
        if (self.background_thread) |thread| {
            thread.join();
        }

        // Save session state
        self.saveSessionState() catch {};

        // Cleanup components
        self.feedback_system.deinit();
        self.workflow_system.deinit();
        self.help_system.deinit();
        self.tool_discovery_grid.deinit();
        self.onboarding_wizard.deinit();
        self.version_viewer.deinit();
        self.outline_navigator.deinit();
        self.preview_renderer.deinit();
        self.metrics_collector.deinit();
        self.layout_manager.deinit();
        self.progress_tracker.deinit();
        self.notification_system.deinit();
        self.command_palette.deinit();
        self.dashboard.deinit();
        self.editor.deinit();

        self.allocator.destroy(self);
    }

    /// Run the improved interactive session
    pub fn run(self: *Self) !void {
        // Setup terminal
        try self.setupTerminal();
        defer self.restoreTerminal();

        // Run onboarding if needed
        if (self.config.onboarding_config.enabled and !self.state.onboarding_completed) {
            try self.runOnboarding();
        }

        // Show welcome screen if enabled
        if (self.config.dashboard_config.show_welcome) {
            try self.showWelcomeScreen();
        }

        // Initialize session
        self.state.is_running = true;
        defer self.state.is_running = false;

        // Main session loop
        while (self.state.is_running) {
            // Update metrics
            try self.updateMetrics();

            // Update contextual help
            try self.updateContextualHelp();

            // Update visual feedback
            try self.updateVisualFeedback();

            // Render dashboard
            try self.render();

            // Handle input
            const event = try self.waitForEvent();
            const should_exit = try self.handleEvent(event);

            if (should_exit) break;

            // Update activity timestamp
            self.state.last_activity = std.time.timestamp();
        }

        // Show exit screen
        try self.showExitScreen();
    }

    /// Run onboarding wizard
    fn runOnboarding(self: *Self) !void {
        try self.onboarding_wizard.startOnboarding(self);
        self.state.onboarding_completed = true;
    }

    /// Setup dashboard widgets
    fn setupDashboardWidgets(self: *Self) !void {
        // Add metrics panel
        try self.dashboard.addWidget(.{
            .widget_type = .metric_card,
            .config = .{
                .title = "Document Metrics",
                .position = .{ .x = 0, .y = 0 },
                .size = .{ .width = 30, .height = 8 },
            },
        }, "document_metrics");

        // Add session metrics
        try self.dashboard.addWidget(.{
            .widget_type = .metric_card,
            .config = .{
                .title = "Session Metrics",
                .position = .{ .x = 30, .y = 0 },
                .size = .{ .width = 30, .height = 8 },
            },
        }, "session_metrics");

        // Add tool discovery grid
        try self.dashboard.addWidget(.{
            .widget_type = .custom,
            .config = .{
                .title = "Tool Discovery",
                .position = .{ .x = 0, .y = 8 },
                .size = .{ .width = 60, .height = 15 },
            },
        }, "tool_discovery");

        // Add contextual help panel
        try self.dashboard.addWidget(.{
            .widget_type = .custom,
            .config = .{
                .title = "Help & Tips",
                .position = .{ .x = 60, .y = 0 },
                .size = .{ .width = 25, .height = 23 },
            },
        }, "contextual_help");

        // Add workflow automation panel
        try self.dashboard.addWidget(.{
            .widget_type = .custom,
            .config = .{
                .title = "Workflow Automation",
                .position = .{ .x = 0, .y = 23 },
                .size = .{ .width = 40, .height = 8 },
            },
        }, "workflow_automation");
    }

    /// Register session commands
    fn registerCommands(self: *Self) !void {
        // File operations
        try self.command_palette.registerCommand(.{
            .name = "Save Document",
            .description = "Save the current document",
            .shortcut = "Ctrl+S",
            .category = .file,
            .action = saveDocumentCommand,
            .context = &[_]Context{ .general, .editing },
        });

        try self.command_palette.registerCommand(.{
            .name = "Open File",
            .description = "Open a file for editing",
            .shortcut = "Ctrl+O",
            .category = .file,
            .action = openFileCommand,
            .context = &[_]Context{.general},
        });

        try self.command_palette.registerCommand(.{
            .name = "New Document",
            .description = "Create a new document",
            .shortcut = "Ctrl+N",
            .category = .file,
            .action = newDocumentCommand,
            .context = &[_]Context{.general},
        });

        // View operations
        try self.command_palette.registerCommand(.{
            .name = "Toggle Preview",
            .description = "Toggle live preview pane",
            .shortcut = "Alt+P",
            .category = .view,
            .action = togglePreviewCommand,
            .context = &[_]Context{ .general, .editing },
        });

        try self.command_palette.registerCommand(.{
            .name = "Toggle Dashboard",
            .description = "Toggle dashboard visibility",
            .shortcut = "Alt+D",
            .category = .view,
            .action = toggleDashboardCommand,
            .context = &[_]Context{.general},
        });

        try self.command_palette.registerCommand(.{
            .name = "Switch Layout",
            .description = "Switch between layout modes",
            .shortcut = "Alt+L",
            .category = .view,
            .action = switchLayoutCommand,
            .context = &[_]Context{.general},
        });

        try self.command_palette.registerCommand(.{
            .name = "Show Tool Discovery",
            .description = "Show interactive tool discovery grid",
            .shortcut = "Alt+T",
            .category = .view,
            .action = showToolDiscoveryCommand,
            .context = &[_]Context{.general},
        });

        // Markdown operations
        try self.command_palette.registerCommand(.{
            .name = "Insert Heading",
            .description = "Insert a markdown heading",
            .shortcut = "Alt+1-6",
            .category = .editing,
            .action = insertHeadingCommand,
            .context = &[_]Context{.editing},
        });

        try self.command_palette.registerCommand(.{
            .name = "Format Table",
            .description = "Format markdown table",
            .shortcut = "Ctrl+Shift+T",
            .category = .editing,
            .action = formatTableCommand,
            .context = &[_]Context{.editing},
        });

        try self.command_palette.registerCommand(.{
            .name = "Insert Link",
            .description = "Insert a markdown link",
            .shortcut = "Ctrl+K",
            .category = .editing,
            .action = insertLinkCommand,
            .context = &[_]Context{.editing},
        });

        // Workflow operations
        try self.command_palette.registerCommand(.{
            .name = "Start Workflow",
            .description = "Start a workflow automation",
            .shortcut = "Alt+W",
            .category = .automation,
            .action = startWorkflowCommand,
            .context = &[_]Context{ .general, .editing },
        });

        try self.command_palette.registerCommand(.{
            .name = "Record Macro",
            .description = "Start recording a macro",
            .shortcut = "Alt+R",
            .category = .automation,
            .action = recordMacroCommand,
            .context = &[_]Context{ .general, .editing },
        });

        // Help operations
        try self.command_palette.registerCommand(.{
            .name = "Show Help",
            .description = "Show contextual help",
            .shortcut = "F1",
            .category = .help,
            .action = showHelpCommand,
            .context = &[_]Context{.general},
        });

        try self.command_palette.registerCommand(.{
            .name = "Interactive Tutorial",
            .description = "Start interactive tutorial",
            .shortcut = "Alt+I",
            .category = .help,
            .action = startTutorialCommand,
            .context = &[_]Context{.general},
        });
    }

    /// Initialize tool discovery
    fn initializeToolDiscovery(self: *Self) !void {
        // Register available tools with the discovery grid
        const tools = [_]ToolInfo{
            .{
                .name = "Content Editor",
                .description = "Markdown editing with AI assistance",
                .category = .editing,
                .icon = "✏️",
                .usage_count = 0,
                .action = contentEditorAction,
            },
            .{
                .name = "Table Formatter",
                .description = "Format and beautify markdown tables",
                .category = .formatting,
                .icon = "📊",
                .usage_count = 0,
                .action = tableFormatterAction,
            },
            .{
                .name = "Link Validator",
                .description = "Check and validate all links in document",
                .category = .analysis,
                .icon = "🔗",
                .usage_count = 0,
                .action = linkValidatorAction,
            },
            .{
                .name = "Document Transformer",
                .description = "Transform document structure and format",
                .category = .automation,
                .icon = "🔄",
                .usage_count = 0,
                .action = documentTransformerAction,
            },
            .{
                .name = "Workflow Recorder",
                .description = "Record and replay editing workflows",
                .category = .automation,
                .icon = "🎬",
                .usage_count = 0,
                .action = workflowRecorderAction,
            },
        };

        for (tools) |tool| {
            try self.tool_discovery_grid.registerTool(tool);
        }
    }

    /// Update contextual help
    fn updateContextualHelp(self: *Self) !void {
        const context = self.determineCurrentContext();
        try self.help_system.updateContext(context);
        self.state.current_context = context;
    }

    /// Determine current user context
    fn determineCurrentContext(self: *Self) Context {
        // Determine context based on current state and user actions
        if (self.state.layout_mode == .tool_discovery) {
            return .tool_discovery;
        }

        if (self.editor.state.cursor_pos < 50) {
            return .document_start;
        }

        if (self.editor.state.document.lines.items.len == 0) {
            return .empty_document;
        }

        // Check for specific patterns in current line
        const current_line_idx = self.editor.state.cursor_pos / 80; // Approximate
        if (current_line_idx < self.editor.state.document.lines.items.len) {
            const current_line = self.editor.state.document.lines.items[current_line_idx];
            if (std.mem.startsWith(u8, current_line, "#")) {
                return .heading_editing;
            }
            if (std.mem.indexOf(u8, current_line, "|") != null) {
                return .table_editing;
            }
            if (std.mem.indexOf(u8, current_line, "[") != null and std.mem.indexOf(u8, current_line, "]") != null) {
                return .link_editing;
            }
        }

        return .general_editing;
    }

    /// Update visual feedback
    fn updateVisualFeedback(self: *Self) !void {
        // Update feedback based on current state
        try self.feedback_system.updateState(self.state);
    }

    /// Setup terminal for session
    fn setupTerminal(self: *Self) !void {
        // Terminal setup handled by dashboard
        try self.dashboard.run();
    }

    /// Restore terminal state
    fn restoreTerminal(self: *Self) void {
        // Terminal restoration handled by dashboard
        self.dashboard.deinit();
    }

    /// Show welcome screen
    fn showWelcomeScreen(self: *Self) !void {
        const welcome = ImprovedWelcomeScreen.init(
            self.allocator,
            self.config.theme_config.name,
        );
        defer welcome.deinit();

        try welcome.render(self.dashboard.renderer, .{
            .title = self.config.dashboard_config.title,
            .features = &[_][]const u8{
                "🚀 Simplified Onboarding",
                "🔍 Interactive Tool Discovery",
                "💡 Contextual Help System",
                "⚡ Workflow Automation",
                "✨ Visual Feedback",
                "🎯 Command Palette",
            },
            .shortcuts = &[_][]const u8{
                "Ctrl+P - Command Palette",
                "Alt+T - Tool Discovery",
                "Alt+W - Workflow Automation",
                "F1 - Contextual Help",
                "Alt+I - Interactive Tutorial",
            },
            .quick_actions = &[_][]const u8{
                "📝 Create New Document",
                "📂 Open Existing File",
                "🎬 Start Tutorial",
                "🔧 Customize Experience",
            },
        });

        // Wait for user input
        _ = try self.waitForEvent();
    }

    /// Show exit screen
    fn showExitScreen(self: *Self) !void {
        const exit_screen = ImprovedExitScreen.init(self.allocator);
        defer exit_screen.deinit();

        try exit_screen.render(self.dashboard.renderer, .{
            .session_duration = std.time.timestamp() - self.state.session_start,
            .documents_edited = 1, // TODO: track this
            .total_words = self.editor.state.metrics.word_count,
            .total_tokens = self.metrics_collector.getTotalTokens(),
            .tools_used = self.tool_discovery_grid.getUsedToolsCount(),
            .workflows_completed = self.workflow_system.getCompletedWorkflowsCount(),
        });
    }

    /// Update session metrics
    fn updateMetrics(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Update document metrics
        try self.metrics_collector.updateDocumentMetrics(&self.editor.state.metrics);

        // Update session metrics
        try self.metrics_collector.updateSessionMetrics(.{
            .session_duration = std.time.timestamp() - self.state.session_start,
            .last_activity = self.state.last_activity,
            .commands_executed = self.metrics_collector.getCommandsExecuted(),
            .notifications_shown = self.metrics_collector.getNotificationsShown(),
        });

        // Update preview if needed
        if (self.config.preview_config.live_preview) {
            try self.updatePreview();
        }

        // Update outline
        try self.updateOutline();

        // Update version history
        try self.updateVersionHistory();
    }

    /// Render the session
    fn render(self: *Self) !void {
        // Begin frame
        try self.dashboard.renderer.beginFrame();

        // Render dashboard
        try self.dashboard.render();

        // Render editor in appropriate pane
        try self.renderEditor();

        // Render preview if enabled
        if (self.state.layout_mode != .editor_focus) {
            try self.renderPreview();
        }

        // Render tool discovery grid if active
        if (self.state.layout_mode == .tool_discovery) {
            try self.renderToolDiscovery();
        }

        // Render workflow automation if active
        if (self.state.layout_mode == .workflow_focus) {
            try self.renderWorkflowAutomation();
        }

        // Render command palette if visible
        if (self.command_palette.isVisible()) {
            try self.command_palette.render(self.dashboard.renderer);
        }

        // Render contextual help
        try self.renderContextualHelp();

        // Render notifications
        try self.notification_system.renderNotifications(self.dashboard.renderer);

        // Render visual feedback
        try self.feedback_system.render(self.dashboard.renderer);

        // End frame
        try self.dashboard.renderer.endFrame();
    }

    /// Render editor pane
    fn renderEditor(self: *Self) !void {
        const editor_bounds = self.layout_manager.getEditorBounds();
        try self.editor.renderEditorContent(
            self.dashboard.renderer,
            editor_bounds.x,
            editor_bounds.y,
            editor_bounds.width,
            editor_bounds.height,
        );
    }

    /// Render preview pane
    fn renderPreview(self: *Self) !void {
        const preview_bounds = self.layout_manager.getPreviewBounds();

        if (self.config.preview_config.adaptive_rendering) {
            try self.preview_renderer.renderAdaptivePreview(
                self.dashboard.renderer,
                preview_bounds.x,
                preview_bounds.y,
                preview_bounds.width,
                preview_bounds.height,
                &self.editor.state.document,
            );
        } else {
            try self.editor.renderMarkdownPreview(
                preview_bounds.x,
                preview_bounds.y,
                preview_bounds.width,
                preview_bounds.height,
            );
        }
    }

    /// Render tool discovery grid
    fn renderToolDiscovery(self: *Self) !void {
        const grid_bounds = self.layout_manager.getToolDiscoveryBounds();
        try self.tool_discovery_grid.render(
            self.dashboard.renderer,
            grid_bounds.x,
            grid_bounds.y,
            grid_bounds.width,
            grid_bounds.height,
        );
    }

    /// Render workflow automation
    fn renderWorkflowAutomation(self: *Self) !void {
        const workflow_bounds = self.layout_manager.getWorkflowBounds();
        try self.workflow_system.render(
            self.dashboard.renderer,
            workflow_bounds.x,
            workflow_bounds.y,
            workflow_bounds.width,
            workflow_bounds.height,
        );
    }

    /// Render contextual help
    fn renderContextualHelp(self: *Self) !void {
        if (!self.config.help_config.enabled) return;

        const help_bounds = self.layout_manager.getHelpBounds();
        try self.help_system.render(
            self.dashboard.renderer,
            help_bounds.x,
            help_bounds.y,
            help_bounds.width,
            help_bounds.height,
        );
    }

    /// Update preview
    fn updatePreview(self: *Self) !void {
        // Debounced preview update
        const current_time = std.time.milliTimestamp();
        if (current_time - self.preview_renderer.last_update > self.config.preview_config.update_delay_ms) {
            try self.preview_renderer.updatePreview(&self.editor.state.document);
            self.preview_renderer.last_update = current_time;
        }
    }

    /// Update document outline
    fn updateOutline(self: *Self) !void {
        try self.outline_navigator.updateOutline(&self.editor.state.document);
    }

    /// Update version history
    fn updateVersionHistory(self: *Self) !void {
        // Check if document has changed
        if (self.editor.state.document.version > self.version_viewer.last_version) {
            try self.version_viewer.addVersion(&self.editor.state.document);
            self.version_viewer.last_version = self.editor.state.document.version;
        }
    }

    /// Wait for input event
    fn waitForEvent(self: *Self) !tui.InputEvent {
        return try self.dashboard.terminal.waitForEvent();
    }

    /// Handle input event
    fn handleEvent(self: *Self, event: tui.InputEvent) !bool {
        switch (event) {
            .key => |key| return try self.handleKeyEvent(key),
            .mouse => |mouse| return try self.handleMouseEvent(mouse),
            .resize => |size| return try self.handleResize(size),
            else => return false,
        }
    }

    /// Handle keyboard event
    fn handleKeyEvent(self: *Self, key: tui.Key) !bool {
        // Check command palette first
        if (self.command_palette.isVisible()) {
            return try self.command_palette.handleInput(key);
        }

        // Handle ctrl shortcuts
        if (key.ctrl) {
            return try self.handleCtrlShortcut(key);
        }

        // Handle alt shortcuts
        if (key.alt) {
            return try self.handleAltShortcut(key);
        }

        // Handle function keys
        if (key.code == .f1) {
            try self.showHelpCommand();
            return false;
        }

        // Delegate to editor
        return try self.editor.handleKeyEvent(key);
    }

    /// Handle Ctrl shortcuts
    fn handleCtrlShortcut(self: *Self, key: tui.Key) !bool {
        switch (key.code) {
            'q' => return true, // Quit
            's' => try self.saveDocument(), // Save
            'o' => try self.openFile(), // Open
            'n' => try self.newDocument(), // New
            'p' => try self.command_palette.toggle(), // Command palette
            'z' => try self.editor.undo(), // Undo
            'y' => try self.editor.redo(), // Redo
            'f' => try self.showSearchDialog(), // Find
            'h' => try self.showReplaceDialog(), // Replace
            else => {},
        }
        return false;
    }

    /// Handle Alt shortcuts
    fn handleAltShortcut(self: *Self, key: tui.Key) !bool {
        switch (key.code) {
            'p' => try self.togglePreview(), // Toggle preview
            'd' => try self.toggleDashboard(), // Toggle dashboard
            'm' => try self.showMetrics(), // Show metrics
            'l' => try self.switchLayout(), // Switch layout
            'h' => try self.showVersionHistory(), // Version history
            't' => try self.showToolDiscovery(), // Tool discovery
            'w' => try self.showWorkflowAutomation(), // Workflow automation
            'i' => try self.startInteractiveTutorial(), // Interactive tutorial
            '1'...'6' => try self.insertHeading(key.code - '0'), // Insert heading
            else => {},
        }
        return false;
    }

    /// Handle mouse event
    fn handleMouseEvent(self: *Self, mouse: tui.Mouse) !void {
        // Handle mouse interactions based on pane
        const editor_bounds = self.layout_manager.getEditorBounds();
        const preview_bounds = self.layout_manager.getPreviewBounds();
        const tool_bounds = self.layout_manager.getToolDiscoveryBounds();

        if (mouse.x >= editor_bounds.x and mouse.x < editor_bounds.x + editor_bounds.width and
            mouse.y >= editor_bounds.y and mouse.y < editor_bounds.y + editor_bounds.height)
        {
            // Mouse in editor pane
            try self.handleEditorMouse(mouse);
        } else if (mouse.x >= preview_bounds.x and mouse.x < preview_bounds.x + preview_bounds.width and
            mouse.y >= preview_bounds.y and mouse.y < preview_bounds.y + preview_bounds.height)
        {
            // Mouse in preview pane
            try self.handlePreviewMouse(mouse);
        } else if (mouse.x >= tool_bounds.x and mouse.x < tool_bounds.x + tool_bounds.width and
            mouse.y >= tool_bounds.y and mouse.y < tool_bounds.y + tool_bounds.height)
        {
            // Mouse in tool discovery
            try self.handleToolDiscoveryMouse(mouse);
        } else {
            // Mouse in dashboard area
            try self.handleDashboardMouse(mouse);
        }
    }

    /// Handle mouse in editor pane
    fn handleEditorMouse(self: *Self, mouse: tui.Mouse) !void {
        switch (mouse.action) {
            .press => {
                if (mouse.button == .left) {
                    // Set cursor position
                    try self.setCursorFromMouse(mouse.x, mouse.y);
                }
            },
            .scroll => {
                if (mouse.direction == .up) {
                    try self.scrollEditor(-3);
                } else {
                    try self.scrollEditor(3);
                }
            },
            else => {},
        }
    }

    /// Handle mouse in preview pane
    fn handlePreviewMouse(self: *Self, mouse: tui.Mouse) !void {
        switch (mouse.action) {
            .press => {
                if (mouse.button == .left) {
                    // Navigate to section in editor
                    try self.navigateToSectionFromPreview(mouse.x, mouse.y);
                }
            },
            .scroll => {
                if (mouse.direction == .up) {
                    try self.scrollPreview(-3);
                } else {
                    try self.scrollPreview(3);
                }
            },
            else => {},
        }
    }

    /// Handle mouse in tool discovery
    fn handleToolDiscoveryMouse(self: *Self, mouse: tui.Mouse) !void {
        switch (mouse.action) {
            .press => {
                if (mouse.button == .left) {
                    // Select tool
                    try self.tool_discovery_grid.selectToolAt(mouse.x, mouse.y);
                }
            },
            else => {},
        }
    }

    /// Handle mouse in dashboard area
    fn handleDashboardMouse(self: *Self, mouse: tui.Mouse) !void {
        // Handle dashboard widget interactions
        try self.dashboard.handleMouse(mouse);
    }

    /// Handle resize event
    fn handleResize(self: *Self, size: tui.TerminalSize) !void {
        // Update layout
        try self.layout_manager.updateSize(size);

        // Update dashboard
        try self.dashboard.handleResize(size);
    }

    /// Save session state
    fn saveSessionState(self: *Self) !void {
        if (!self.config.session_config.enable_session_save) return;

        // Save layout preferences
        // Save command history
        // Save recent files
        // Implementation here...
    }

    /// Background worker thread
    fn backgroundWorker(self: *Self) !void {
        while (self.state.is_running) {
            std.time.sleep(1 * std.time.ns_per_s);

            // Auto-save
            if (self.config.session_config.enable_auto_backup) {
                try self.checkAutoBackup();
            }

            // Update metrics
            try self.updateMetrics();

            // Process notifications
            try self.processNotifications();

            // Update tool usage statistics
            try self.updateToolUsageStats();
        }
    }

    /// Check for auto-backup
    fn checkAutoBackup(self: *Self) !void {
        const current_time = std.time.timestamp();
        const last_backup = self.version_viewer.last_backup_time;

        if (current_time - last_backup > self.config.session_config.backup_interval_s) {
            try self.createBackup();
            self.version_viewer.last_backup_time = current_time;
        }
    }

    /// Create backup
    fn createBackup(self: *Self) !void {
        // Create backup of current document
        // Implementation here...
        _ = self;
    }

    /// Process pending notifications
    fn processNotifications(self: *Self) !void {
        // Process notification queue
        // Implementation here...
        _ = self;
    }

    /// Update tool usage statistics
    fn updateToolUsageStats(self: *Self) !void {
        // Update usage statistics for tools
        // Implementation here...
        _ = self;
    }

    // === Command Implementations ===

    fn saveDocumentCommand() !void {
        // Implementation here...
    }

    fn openFileCommand() !void {
        // Implementation here...
    }

    fn newDocumentCommand() !void {
        // Implementation here...
    }

    fn togglePreviewCommand() !void {
        // Implementation here...
    }

    fn toggleDashboardCommand() !void {
        // Implementation here...
    }

    fn switchLayoutCommand() !void {
        // Implementation here...
    }

    fn showToolDiscoveryCommand() !void {
        // Implementation here...
    }

    fn insertHeadingCommand() !void {
        // Implementation here...
    }

    fn formatTableCommand() !void {
        // Implementation here...
    }

    fn insertLinkCommand() !void {
        // Implementation here...
    }

    fn startWorkflowCommand() !void {
        // Implementation here...
    }

    fn recordMacroCommand() !void {
        // Implementation here...
    }

    fn showHelpCommandStatic() !void {
        // Implementation here...
    }

    fn startTutorialCommand() !void {
        // Implementation here...
    }

    // === Helper Methods ===

    fn saveDocument(self: *Self) !void {
        try self.editor.saveDocument();
        try self.notification_system.success("Document Saved", "Document has been saved successfully");
        try self.feedback_system.showSuccess("Document saved!");
    }

    fn openFile(self: *Self) !void {
        // Show file browser
        // Implementation here...
        _ = self;
    }

    fn newDocument(self: *Self) !void {
        // Create new document
        // Implementation here...
        _ = self;
    }

    fn togglePreview(self: *Self) !void {
        self.state.layout_mode = switch (self.state.layout_mode) {
            .editor_focus => .split_view,
            .split_view => .editor_focus,
            else => .split_view,
        };
        try self.feedback_system.showInfo("Preview toggled");
    }

    fn toggleDashboard(self: *Self) !void {
        self.state.layout_mode = switch (self.state.layout_mode) {
            .dashboard => .editor_focus,
            .editor_focus => .dashboard,
            else => .dashboard,
        };
        try self.feedback_system.showInfo("Dashboard toggled");
    }

    fn switchLayout(self: *Self) !void {
        // Cycle through layout modes
        const layouts = [_]LayoutMode{ .dashboard, .editor_focus, .preview_focus, .split_view, .tool_discovery, .workflow_focus, .minimal };
        const current_idx = std.mem.indexOfScalar(LayoutMode, &layouts, self.state.layout_mode) orelse 0;
        const next_idx = (current_idx + 1) % layouts.len;
        self.state.layout_mode = layouts[next_idx];
        try self.feedback_system.showInfo("Layout switched");
    }

    fn showToolDiscovery(self: *Self) !void {
        self.state.layout_mode = .tool_discovery;
        try self.feedback_system.showInfo("Tool discovery activated");
    }

    fn showWorkflowAutomation(self: *Self) !void {
        self.state.layout_mode = .workflow_focus;
        try self.feedback_system.showInfo("Workflow automation activated");
    }

    fn startInteractiveTutorial(self: *Self) !void {
        try self.onboarding_wizard.startTutorial(self);
        try self.feedback_system.showInfo("Tutorial started");
    }

    fn insertHeading(self: *Self, level: u8) !void {
        // Insert heading at current cursor
        // Implementation here...
        _ = self;
        _ = level;
    }

    fn showMetrics(self: *Self) !void {
        // Show detailed metrics modal
        // Implementation here...
        _ = self;
    }

    fn showVersionHistory(self: *Self) !void {
        // Show version history modal
        // Implementation here...
        _ = self;
    }

    fn showSearchDialog(self: *Self) !void {
        // Show search dialog
        // Implementation here...
        _ = self;
    }

    fn showReplaceDialog(self: *Self) !void {
        // Show replace dialog
        // Implementation here...
        _ = self;
    }

    fn showHelpCommand(self: *Self) !void {
        try self.help_system.showDetailedHelp();
    }

    fn setCursorFromMouse(self: *Self, x: u16, y: u16) !void {
        // Set cursor position from mouse coordinates
        // Implementation here...
        _ = self;
        _ = x;
        _ = y;
    }

    fn navigateToSectionFromPreview(self: *Self, x: u16, y: u16) !void {
        // Navigate to corresponding section in editor
        // Implementation here...
        _ = self;
        _ = x;
        _ = y;
    }

    fn scrollEditor(self: *Self, lines: i32) !void {
        // Scroll editor by specified lines
        // Implementation here...
        _ = self;
        _ = lines;
    }

    fn scrollPreview(self: *Self, lines: i32) !void {
        // Scroll preview by specified lines
        // Implementation here...
        _ = self;
        _ = lines;
    }
};

/// Session state with UX enhancements
pub const SessionState = struct {
    /// Current layout mode
    layout_mode: LayoutMode,

    /// Active pane
    active_pane: ActivePane,

    /// Last activity timestamp
    last_activity: i64,

    /// Session start timestamp
    session_start: i64,

    /// Is session running
    is_running: bool,

    /// Onboarding completed
    onboarding_completed: bool,

    /// Current user context
    current_context: Context,

    /// UX state
    ux_state: UXState,
};

/// Active panes
pub const ActivePane = enum {
    editor,
    preview,
    dashboard,
    command_palette,
    tool_discovery,
    workflow_automation,
    help_panel,
};

/// User context for adaptive help
pub const Context = enum {
    general,
    general_editing,
    document_start,
    empty_document,
    heading_editing,
    table_editing,
    link_editing,
    tool_discovery,
    workflow_creation,
    tutorial_active,
};

/// UX state for visual feedback
pub const UXState = enum {
    normal,
    onboarding,
    tutorial,
    error_state,
    success_state,
    busy,
};

/// Tool information for discovery
pub const ToolInfo = struct {
    name: []const u8,
    description: []const u8,
    category: ToolCategory,
    icon: []const u8,
    usage_count: u64,
    action: *const fn (*InteractiveSession) anyerror!void,
};

/// Layout for multi-pane interface
pub const Layout = struct {
    allocator: Allocator,
    config: LayoutConfig,
    terminal_size: tui.TerminalSize,

    pub fn init(allocator: Allocator, layout_config: LayoutConfig) !*LayoutManager {
        const self = try allocator.create(LayoutManager);
        self.* = .{
            .allocator = allocator,
            .config = layout_config,
            .terminal_size = .{ .width = 80, .height = 24 }, // Default
        };
        return self;
    }

    pub fn deinit(self: *LayoutManager) void {
        self.allocator.destroy(self);
    }

    pub fn updateSize(self: *LayoutManager, size: tui.TerminalSize) !void {
        self.terminal_size = size;
    }

    pub fn getEditorBounds(self: *LayoutManager) term.Rect {
        return switch (self.config.mode) {
            .dashboard => .{
                .x = self.config.pane_sizes.sidebar_width,
                .y = self.config.pane_sizes.metrics_height,
                .width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.terminal_size.width - self.config.pane_sizes.sidebar_width)) * self.config.pane_sizes.editor_width_ratio)),
                .height = self.terminal_size.height - self.config.pane_sizes.metrics_height - self.config.pane_sizes.status_height,
            },
            .editor_focus => .{
                .x = 0,
                .y = 0,
                .width = self.terminal_size.width,
                .height = self.terminal_size.height - self.config.pane_sizes.status_height,
            },
            .preview_focus => .{
                .x = 0,
                .y = 0,
                .width = 0,
                .height = 0,
            },
            .split_view => .{
                .x = 0,
                .y = 0,
                .width = self.terminal_size.width / 2,
                .height = self.terminal_size.height - self.config.pane_sizes.status_height,
            },
            .tool_discovery => .{
                .x = 0,
                .y = self.config.pane_sizes.tool_grid_height,
                .width = self.terminal_size.width,
                .height = self.terminal_size.height - self.config.pane_sizes.tool_grid_height - self.config.pane_sizes.status_height,
            },
            .workflow_focus => .{
                .x = 0,
                .y = 0,
                .width = self.terminal_size.width,
                .height = self.terminal_size.height - self.config.pane_sizes.status_height,
            },
            .minimal => .{
                .x = 0,
                .y = 0,
                .width = self.terminal_size.width,
                .height = self.terminal_size.height,
            },
        };
    }

    pub fn getPreviewBounds(self: *LayoutManager) term.Rect {
        return switch (self.config.mode) {
            .dashboard => .{
                .x = self.config.pane_sizes.sidebar_width + @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.terminal_size.width - self.config.pane_sizes.sidebar_width)) * self.config.pane_sizes.editor_width_ratio)),
                .y = self.config.pane_sizes.metrics_height,
                .width = self.terminal_size.width - self.config.pane_sizes.sidebar_width - @as(u16, @intFromFloat(@as(f32, @floatFromInt(self.terminal_size.width - self.config.pane_sizes.sidebar_width)) * self.config.pane_sizes.editor_width_ratio)),
                .height = self.terminal_size.height - self.config.pane_sizes.metrics_height - self.config.pane_sizes.status_height,
            },
            .editor_focus => .{
                .x = 0,
                .y = 0,
                .width = 0,
                .height = 0,
            },
            .preview_focus => .{
                .x = 0,
                .y = 0,
                .width = self.terminal_size.width,
                .height = self.terminal_size.height - self.config.pane_sizes.status_height,
            },
            .split_view => .{
                .x = self.terminal_size.width / 2,
                .y = 0,
                .width = self.terminal_size.width - self.terminal_size.width / 2,
                .height = self.terminal_size.height - self.config.pane_sizes.status_height,
            },
            .tool_discovery => .{
                .x = 0,
                .y = 0,
                .width = 0,
                .height = 0,
            },
            .workflow_focus => .{
                .x = 0,
                .y = 0,
                .width = 0,
                .height = 0,
            },
            .minimal => .{
                .x = 0,
                .y = 0,
                .width = 0,
                .height = 0,
            },
        };
    }

    pub fn getDashboardBounds(self: *LayoutManager) term.Rect {
        return .{
            .x = 0,
            .y = 0,
            .width = self.terminal_size.width,
            .height = self.config.pane_sizes.metrics_height,
        };
    }

    pub fn getSidebarBounds(self: *LayoutManager) term.Rect {
        return .{
            .x = 0,
            .y = self.config.pane_sizes.metrics_height,
            .width = self.config.pane_sizes.sidebar_width,
            .height = self.terminal_size.height - self.config.pane_sizes.metrics_height - self.config.pane_sizes.status_height,
        };
    }

    pub fn getToolDiscoveryBounds(self: *LayoutManager) term.Rect {
        return .{
            .x = 0,
            .y = 0,
            .width = self.terminal_size.width,
            .height = self.config.pane_sizes.tool_grid_height,
        };
    }

    pub fn getWorkflowBounds(self: *LayoutManager) term.Rect {
        return .{
            .x = 0,
            .y = 0,
            .width = self.terminal_size.width,
            .height = self.terminal_size.height - self.config.pane_sizes.status_height,
        };
    }

    pub fn getHelpBounds(self: *LayoutManager) term.Rect {
        return .{
            .x = self.terminal_size.width - self.config.pane_sizes.help_panel_width,
            .y = 0,
            .width = self.config.pane_sizes.help_panel_width,
            .height = self.terminal_size.height - self.config.pane_sizes.status_height,
        };
    }
};

/// Metrics collector for session and document metrics
pub const MetricsCollector = struct {
    allocator: Allocator,
    config: MetricsConfig,
    document_metrics: std.ArrayList(DocumentMetricsSnapshot),
    session_metrics: std.ArrayList(SessionMetricsSnapshot),
    sparklines: std.StringHashMap([]f32),

    pub fn init(allocator: Allocator, metrics_config: MetricsConfig) !*MetricsCollector {
        const self = try allocator.create(MetricsCollector);
        self.* = .{
            .allocator = allocator,
            .config = metrics_config,
            .document_metrics = std.ArrayList(DocumentMetricsSnapshot).init(allocator),
            .session_metrics = std.ArrayList(SessionMetricsSnapshot).init(allocator),
            .sparklines = std.StringHashMap([]f32).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *MetricsCollector) void {
        self.document_metrics.deinit();
        self.session_metrics.deinit();
        var it = self.sparklines.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.sparklines.deinit();
        self.allocator.destroy(self);
    }

    pub fn updateDocumentMetrics(self: *MetricsCollector, metrics: *const markdown_editor.DocumentMetrics) !void {
        const snapshot = DocumentMetricsSnapshot{
            .timestamp = std.time.timestamp(),
            .word_count = metrics.word_count,
            .line_count = metrics.line_count,
            .char_count = metrics.char_count,
            .reading_time = metrics.reading_time,
            .heading_count = @as(u32, @intCast(std.mem.count(u32, &metrics.heading_counts))),
            .link_count = metrics.link_count,
            .code_block_count = metrics.code_block_count,
            .table_count = metrics.table_count,
        };

        try self.document_metrics.append(snapshot);

        // Maintain history limit
        if (self.document_metrics.items.len > self.config.max_history) {
            _ = self.document_metrics.orderedRemove(0);
        }

        // Update sparklines
        try self.updateSparkline("word_count", @floatFromInt(metrics.word_count));
        try self.updateSparkline("line_count", @floatFromInt(metrics.line_count));
        try self.updateSparkline("reading_time", metrics.reading_time);
    }

    pub fn updateSessionMetrics(self: *MetricsCollector, metrics: SessionMetricsSnapshot) !void {
        try self.session_metrics.append(metrics);

        // Maintain history limit
        if (self.session_metrics.items.len > self.config.max_history) {
            _ = self.session_metrics.orderedRemove(0);
        }
    }

    pub fn getTotalTokens(self: *MetricsCollector) u64 {
        // Implementation here...
        _ = self;
        return 0;
    }

    pub fn getCommandsExecuted(self: *MetricsCollector) u64 {
        // Implementation here...
        _ = self;
        return 0;
    }

    pub fn getNotificationsShown(self: *MetricsCollector) u64 {
        // Implementation here...
        _ = self;
        return 0;
    }

    fn updateSparkline(self: *MetricsCollector, key: []const u8, value: f32) !void {
        const owned_key = try self.allocator.dupe(u8, key);
        const sparkline = self.sparklines.getPtr(owned_key) orelse blk: {
            const new_sparkline = try self.allocator.alloc(f32, 20); // Fixed size sparkline
            @memset(new_sparkline, 0);
            try self.sparklines.put(owned_key, new_sparkline);
            break :blk new_sparkline;
        };

        // Shift values and add new value
        std.mem.copyForwards(f32, sparkline[0 .. sparkline.len - 1], sparkline[1..]);
        sparkline[sparkline.len - 1] = value;
    }
};

/// Document metrics snapshot
pub const DocumentMetricsSnapshot = struct {
    timestamp: i64,
    word_count: u32,
    line_count: u32,
    char_count: u32,
    reading_time: f32,
    heading_count: u32,
    link_count: u32,
    code_block_count: u32,
    table_count: u32,
};

/// Session metrics snapshot
pub const SessionMetricsSnapshot = struct {
    timestamp: i64 = 0,
    session_duration: i64,
    last_activity: i64,
    commands_executed: u64,
    notifications_shown: u64,
};

/// Preview renderer with adaptive capabilities
pub const PreviewRenderer = struct {
    allocator: Allocator,
    config: PreviewConfig,
    last_update: i64 = 0,
    cached_preview: ?[]u8 = null,

    pub fn init(allocator: Allocator, preview_config: PreviewConfig) !*PreviewRenderer {
        const self = try allocator.create(PreviewRenderer);
        self.* = .{
            .allocator = allocator,
            .config = preview_config,
        };
        return self;
    }

    pub fn deinit(self: *PreviewRenderer) void {
        if (self.cached_preview) |preview| {
            self.allocator.free(preview);
        }
        self.allocator.destroy(self);
    }

    pub fn updatePreview(self: *PreviewRenderer, document: *const markdown_editor.Document) !void {
        // Generate preview based on configuration
        // Implementation here...
        _ = self;
        _ = document;
    }

    pub fn renderAdaptivePreview(self: *PreviewRenderer, renderer: *anyopaque, x: u16, y: u16, width: u16, height: u16, document: *const markdown_editor.Document) !void {
        // Render preview with adaptive quality
        // Implementation here...
        _ = self;
        _ = renderer;
        _ = x;
        _ = y;
        _ = width;
        _ = height;
        _ = document;
    }
};

/// Outline navigator for document structure
pub const OutlineNavigator = struct {
    allocator: Allocator,
    outline_items: std.ArrayList(OutlineItem),

    pub fn init(allocator: Allocator) !*OutlineNavigator {
        const self = try allocator.create(OutlineNavigator);
        self.* = .{
            .allocator = allocator,
            .outline_items = std.ArrayList(OutlineItem).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *OutlineNavigator) void {
        self.outline_items.deinit();
        self.allocator.destroy(self);
    }

    pub fn updateOutline(self: *OutlineNavigator, document: *const markdown_editor.Document) !void {
        // Clear existing outline
        self.outline_items.clearRetainingCapacity();

        // Parse document and build outline
        for (document.lines.items, 0..) |line, idx| {
            if (std.mem.startsWith(u8, line, "#")) {
                const level = markdown_editor.countHeadingLevel(line);
                const title = if (level > 0 and level <= line.len) line[level + 1 ..] else line;

                try self.outline_items.append(.{
                    .line = @intCast(idx),
                    .level = level,
                    .title = try self.allocator.dupe(u8, title),
                });
            }
        }
    }
};

/// Outline item
pub const OutlineItem = struct {
    line: u32,
    level: u32,
    title: []const u8,
};

/// Version history viewer with diff capabilities
pub const VersionHistoryViewer = struct {
    allocator: Allocator,
    config: SessionManagementConfig,
    versions: std.ArrayList(DocumentVersion),
    last_version: u64 = 0,
    last_backup_time: i64 = 0,

    pub fn init(allocator: Allocator, session_config: SessionManagementConfig) !*VersionHistoryViewer {
        const self = try allocator.create(VersionHistoryViewer);
        self.* = .{
            .allocator = allocator,
            .config = session_config,
            .versions = std.ArrayList(DocumentVersion).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *VersionHistoryViewer) void {
        for (self.versions.items) |*version| {
            self.allocator.free(version.content);
            if (version.diff) |diff| {
                self.allocator.free(diff);
            }
        }
        self.versions.deinit();
        self.allocator.destroy(self);
    }

    pub fn addVersion(self: *VersionHistoryViewer, document: *const markdown_editor.Document) !void {
        // Create snapshot of current document
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();

        for (document.lines.items) |line| {
            try content.appendSlice(line);
            try content.append('\n');
        }

        const version = DocumentVersion{
            .version = document.version,
            .timestamp = std.time.timestamp(),
            .content = try self.allocator.dupe(u8, content.items),
            .diff = null, // Will be computed if needed
        };

        try self.versions.append(version);

        // Maintain version limit
        if (self.versions.items.len > self.config.max_versions) {
            const removed = self.versions.orderedRemove(0);
            self.allocator.free(removed.content);
            if (removed.diff) |diff| {
                self.allocator.free(diff);
            }
        }
    }
};

/// Document version
pub const DocumentVersion = struct {
    version: u64,
    timestamp: i64,
    content: []const u8,
    diff: ?[]const u8,
};

/// Onboarding wizard for progressive disclosure
pub const OnboardingWizard = struct {
    allocator: Allocator,
    config: OnboardingConfig,
    current_step: usize = 0,
    completed_steps: std.ArrayList(bool),

    pub fn init(allocator: Allocator, onboarding_config: OnboardingConfig) !*OnboardingWizard {
        const self = try allocator.create(OnboardingWizard);
        self.* = .{
            .allocator = allocator,
            .config = onboarding_config,
            .completed_steps = std.ArrayList(bool).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *OnboardingWizard) void {
        self.completed_steps.deinit();
        self.allocator.destroy(self);
    }

    pub fn startOnboarding(self: *OnboardingWizard, session: *InteractiveSession) !void {
        // Implementation here...
        _ = self;
        _ = session;
    }

    pub fn startTutorial(self: *OnboardingWizard, session: *InteractiveSession) !void {
        // Implementation here...
        _ = self;
        _ = session;
    }
};

/// Tool discovery grid for interactive tool exploration
pub const ToolDiscoveryGrid = struct {
    allocator: Allocator,
    config: ToolDiscoveryConfig,
    tools: std.ArrayList(ToolInfo),
    selected_tool: usize = 0,
    search_query: []const u8 = "",
    filtered_tools: std.ArrayList(*ToolInfo),

    pub fn init(allocator: Allocator, tool_config: ToolDiscoveryConfig) !*ToolDiscoveryGrid {
        const self = try allocator.create(ToolDiscoveryGrid);
        self.* = .{
            .allocator = allocator,
            .config = tool_config,
            .tools = std.ArrayList(ToolInfo).init(allocator),
            .filtered_tools = std.ArrayList(*ToolInfo).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *ToolDiscoveryGrid) void {
        self.tools.deinit();
        self.filtered_tools.deinit();
        self.allocator.destroy(self);
    }

    pub fn registerTool(self: *ToolDiscoveryGrid, tool: ToolInfo) !void {
        try self.tools.append(tool);
    }

    pub fn render(self: *ToolDiscoveryGrid, renderer: *anyopaque, x: u16, y: u16, width: u16, height: u16) !void {
        // Implementation here...
        _ = self;
        _ = renderer;
        _ = x;
        _ = y;
        _ = width;
        _ = height;
    }

    pub fn selectToolAt(self: *ToolDiscoveryGrid, x: u16, y: u16) !void {
        // Implementation here...
        _ = self;
        _ = x;
        _ = y;
    }

    pub fn getUsedToolsCount(self: *ToolDiscoveryGrid) u64 {
        // Implementation here...
        _ = self;
        return 0;
    }
};

/// Contextual help system
pub const ContextualHelpSystem = struct {
    allocator: Allocator,
    config: HelpConfig,
    current_context: Context = .general,
    help_content: std.StringHashMap([]const u8),

    pub fn init(allocator: Allocator, help_config: HelpConfig) !*ContextualHelpSystem {
        const self = try allocator.create(ContextualHelpSystem);
        self.* = .{
            .allocator = allocator,
            .config = help_config,
            .help_content = std.StringHashMap([]const u8).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *ContextualHelpSystem) void {
        self.help_content.deinit();
        self.allocator.destroy(self);
    }

    pub fn updateContext(self: *ContextualHelpSystem, context: Context) !void {
        self.current_context = context;
    }

    pub fn render(self: *ContextualHelpSystem, renderer: *anyopaque, x: u16, y: u16, width: u16, height: u16) !void {
        // Implementation here...
        _ = self;
        _ = renderer;
        _ = x;
        _ = y;
        _ = width;
        _ = height;
    }

    pub fn showDetailedHelp(self: *ContextualHelpSystem) !void {
        // Implementation here...
        _ = self;
    }
};

/// Workflow automation system
pub const WorkflowAutomation = struct {
    allocator: Allocator,
    config: WorkflowConfig,
    workflows: std.ArrayList(Workflow),
    active_workflow: ?*Workflow = null,

    pub fn init(allocator: Allocator, workflow_config: WorkflowConfig) !*WorkflowAutomation {
        const self = try allocator.create(WorkflowAutomation);
        self.* = .{
            .allocator = allocator,
            .config = workflow_config,
            .workflows = std.ArrayList(Workflow).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *WorkflowAutomation) void {
        self.workflows.deinit();
        self.allocator.destroy(self);
    }

    pub fn render(self: *WorkflowAutomation, renderer: *anyopaque, x: u16, y: u16, width: u16, height: u16) !void {
        // Implementation here...
        _ = self;
        _ = renderer;
        _ = x;
        _ = y;
        _ = width;
        _ = height;
    }

    pub fn getCompletedWorkflowsCount(self: *WorkflowAutomation) u64 {
        // Implementation here...
        _ = self;
        return 0;
    }
};

/// Workflow definition
pub const Workflow = struct {
    name: []const u8,
    description: []const u8,
    steps: std.ArrayList(WorkflowStep),
    is_template: bool,
};

/// Workflow step
pub const WorkflowStep = struct {
    action: []const u8,
    parameters: std.StringHashMap([]const u8),
};

/// Visual feedback system
pub const VisualFeedbackSystem = struct {
    allocator: Allocator,
    config: FeedbackConfig,
    active_animations: std.ArrayList(Animation),

    pub fn init(allocator: Allocator, feedback_config: FeedbackConfig) !*VisualFeedbackSystem {
        const self = try allocator.create(VisualFeedbackSystem);
        self.* = .{
            .allocator = allocator,
            .config = feedback_config,
            .active_animations = std.ArrayList(Animation).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *VisualFeedbackSystem) void {
        self.active_animations.deinit();
        self.allocator.destroy(self);
    }

    pub fn updateState(self: *VisualFeedbackSystem, state: SessionState) !void {
        // Implementation here...
        _ = self;
        _ = state;
    }

    pub fn render(self: *VisualFeedbackSystem, renderer: *anyopaque) !void {
        // Implementation here...
        _ = self;
        _ = renderer;
    }

    pub fn showSuccess(self: *VisualFeedbackSystem, message: []const u8) !void {
        // Implementation here...
        _ = self;
        _ = message;
    }

    pub fn showInfo(self: *VisualFeedbackSystem, message: []const u8) !void {
        // Implementation here...
        _ = self;
        _ = message;
    }

    pub fn showError(self: *VisualFeedbackSystem, message: []const u8) !void {
        // Implementation here...
        _ = self;
        _ = message;
    }
};

/// Animation for visual feedback
pub const Animation = struct {
    type: AnimationType,
    start_time: i64,
    duration_ms: u32,
    progress: f32 = 0.0,
};

/// Animation types
pub const AnimationType = enum {
    success_check,
    error_shake,
    info_pulse,
    loading_spinner,
    slide_in,
    fade_out,
};

/// Command palette with fuzzy search
pub const CommandPalette = struct {
    allocator: Allocator,
    config: CommandPaletteConfig,
    commands: std.ArrayList(Command),
    visible: bool = false,
    search_query: []const u8 = "",
    selected_index: usize = 0,
    filtered_commands: std.ArrayList(*Command),

    pub const Command = struct {
        name: []const u8,
        description: []const u8,
        shortcut: ?[]const u8,
        category: CommandCategory,
        action: *const fn () anyerror!void,
        context: []const Context,
    };

    pub const CommandCategory = enum {
        file,
        edit,
        view,
        navigation,
        tools,
        automation,
        help,
    };

    pub fn init(allocator: Allocator, palette_config: CommandPaletteConfig) !*CommandPalette {
        const self = try allocator.create(CommandPalette);
        self.* = .{
            .allocator = allocator,
            .config = palette_config,
            .commands = std.ArrayList(Command).init(allocator),
            .filtered_commands = std.ArrayList(*Command).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *CommandPalette) void {
        self.commands.deinit();
        self.filtered_commands.deinit();
        self.allocator.destroy(self);
    }

    pub fn registerCommand(self: *CommandPalette, command: Command) !void {
        try self.commands.append(command);
    }

    pub fn toggle(self: *CommandPalette) !void {
        self.visible = !self.visible;
        if (self.visible) {
            self.search_query = "";
            try self.updateFilteredCommands();
        }
    }

    pub fn isVisible(self: *CommandPalette) bool {
        return self.visible;
    }

    pub fn render(self: *CommandPalette, renderer: *anyopaque) !void {
        // Implementation here...
        _ = self;
        _ = renderer;
    }

    pub fn handleInput(self: *CommandPalette, key: tui.Key) !bool {
        // Implementation here...
        _ = self;
        _ = key;
        return false;
    }

    fn updateFilteredCommands(self: *CommandPalette) !void {
        // Implementation here...
        _ = self;
    }
};

/// Improved welcome screen
pub const ImprovedWelcomeScreen = struct {
    allocator: Allocator,
    theme: []const u8,

    pub fn init(allocator: Allocator, theme: []const u8) ImprovedWelcomeScreen {
        return .{
            .allocator = allocator,
            .theme = theme,
        };
    }

    pub fn deinit(self: *ImprovedWelcomeScreen) void {
        _ = self;
    }

    pub fn render(self: ImprovedWelcomeScreen, renderer: *anyopaque, options: anytype) !void {
        // Implementation here...
        _ = self;
        _ = renderer;
        _ = options;
    }
};

/// Improved exit screen
pub const ImprovedExitScreen = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) ImprovedExitScreen {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ImprovedExitScreen) void {
        _ = self;
    }

    pub fn render(self: ImprovedExitScreen, renderer: *anyopaque, options: anytype) !void {
        // Implementation here...
        _ = self;
        _ = renderer;
        _ = options;
    }
};

/// Tool action functions
fn contentEditorAction(session: *InteractiveSession) !void {
    // Implementation here...
    _ = session;
}

fn tableFormatterAction(session: *InteractiveSession) !void {
    // Implementation here...
    _ = session;
}

fn linkValidatorAction(session: *InteractiveSession) !void {
    // Implementation here...
    _ = session;
}

fn documentTransformerAction(session: *InteractiveSession) !void {
    // Implementation here...
    _ = session;
}

fn workflowRecorderAction(session: *InteractiveSession) !void {
    // Implementation here...
    _ = session;
}

/// Public API for creating and running the interactive session
pub fn runInteractiveSession(allocator: std.mem.Allocator, agent: *agent_interface.Agent) !void {
    const session_config = SessionConfig{
        .base_config = agent.config,
        .onboarding_config = .{},
        .tool_discovery_config = .{},
        .help_config = .{},
        .command_palette_config = .{},
        .workflow_config = .{},
        .feedback_config = .{},
        .dashboard_config = .{},
        .layout_config = .{},
        .preview_config = .{},
        .metrics_config = .{},
        .session_config = .{},
        .input_config = .{},
        .notification_config = .{},
        .theme_config = .{},
        .performance_config = .{},
        .accessibility_config = .{},
        .ux_config = .{},
    };

    const session = try InteractiveSession.init(allocator, agent, session_config);
    defer session.deinit();

    try session.run();
}

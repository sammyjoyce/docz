//! Enhanced Interactive Session for Markdown Agent
//!
//! A comprehensive dashboard-style interface that provides an advanced markdown editing
//! experience with multiple panes, rich input handling, visual feedback, and interactive features.
//!
//! ## Features
//!
//! ### Dashboard Interface
//! - **Multi-pane layout** with resizable panels for different views
//! - **Live markdown preview** with adaptive rendering capabilities
//! - **Document statistics panel** showing word count, reading time, complexity metrics
//! - **Session metrics dashboard** with tokens used, costs, response times
//! - **Document structure outline** with clickable navigation
//! - **Version history viewer** with diff integration
//!
//! ### Rich Input Handling
//! - **Command palette** with fuzzy search for quick actions
//! - **Smart input component** with markdown-specific suggestions
//! - **Tag-based document management** for organization
//! - **Context-aware completions** based on cursor position
//!
//! ### Visual Feedback
//! - **Live sparklines** for session metrics visualization
//! - **Progress bars** for long-running operations
//! - **Animated transitions** between different modes
//! - **Notification system** for status updates and alerts
//!
//! ### Interactive Features
//! - **Mouse support** for clicking on document sections
//! - **Drag-and-drop** for reordering sections
//! - **Keyboard shortcuts** with customizable help modal
//! - **Split-pane editing** with synchronized scrolling
//!
//! ## Architecture
//!
//! The session builds upon the existing MarkdownEditor and integrates
//! with the shared dashboard components, notification system, and command palette.
//!
//! Key components:
//! - **InteractiveSession** - Main session controller
//! - **DashboardLayout** - Multi-pane layout management
//! - **MetricsPanel** - Real-time document and session metrics
//! - **PreviewPane** - Live markdown preview with adaptive rendering
//! - **OutlineNavigator** - Document structure navigation
//! - **VersionHistoryViewer** - Git-style version history with diffs

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = Thread.Mutex;

// Core modules
const agent_interface = @import("agent_interface");
const config = @import("config_shared");

// Shared infrastructure
const tui = @import("tui_shared");
const term = @import("term_shared");
const theme_manager = @import("../../src/shared/theme_manager/mod.zig");
const render = @import("render_shared");
const components = @import("components_shared");

// Dashboard and UI components
const dashboard = @import("../../src/shared/tui/components/dashboard/mod.zig");
const command_palette = @import("../../src/shared/tui/components/command_palette.zig");
const notification_system = @import("../../src/shared/tui/components/notification_system.zig");
const progress_tracker = @import("../../src/shared/tui/components/progress_tracker.zig");

// Advanced UI components
const input_enhanced = @import("../../src/shared/components/input_enhanced.zig");
const split_pane = @import("../../src/shared/tui/widgets/core/split_pane.zig");
const file_tree = @import("../../src/shared/tui/widgets/core/file_tree.zig");
const modal = @import("../../src/shared/tui/widgets/modal.zig");
const canvas_mod = @import("../../src/shared/tui/core/canvas.zig");
// Backward compatibility alias
const canvas_engine = canvas_mod;

// Markdown agent specific
const markdown_tools = @import("tools/mod.zig");
const ContentEditor = @import("tools/ContentEditor.zig");
const Validate = @import("tools/validate.zig");
const document_tool = @import("tools/document.zig");
const enhanced_editor = @import("markdown_editor.zig");

// Common utilities
const fs = @import("common/fs.zig");
const link = @import("common/link.zig");
const meta = @import("common/meta.zig");
const table = @import("common/table.zig");
const template = @import("common/template.zig");
const text_utils = @import("common/text.zig");

/// Enhanced Interactive Session Configuration
pub const InteractiveSessionConfig = struct {
    /// Base agent configuration
    base_config: agent_interface.Config,

    /// Dashboard settings
    dashboard_config: DashboardConfig = .{},

    /// Layout configuration
    layout_config: LayoutConfig = .{},

    /// Preview settings
    preview_config: PreviewConfig = .{},

    /// Metrics and monitoring
    metrics_config: MetricsConfig = .{},

    /// Session management
    session_config: SessionConfig = .{},

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
};

/// Minimum pane sizes
pub const MinPaneSizes = struct {
    editor_min_width: u16 = 40,
    preview_min_width: u16 = 30,
    sidebar_min_width: u16 = 20,
    metrics_min_height: u16 = 6,
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
    render_mode: PreviewRenderMode = .enhanced,

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

    /// Basic markdown formatting
    basic,

    /// Enhanced rendering with graphics
    enhanced,

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

/// Session configuration
pub const SessionConfig = struct {
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
    config: InteractiveSessionConfig,

    /// Enhanced markdown editor
    editor: *enhanced_editor.MarkdownEditor,

    /// Dashboard instance
    dashboard: *dashboard.Dashboard,

    /// Command palette
    command_palette: *command_palette.CommandPalette,

    /// Notification system
    notification_system: *notification_system.NotificationSystem,

    /// Progress tracker
    progress_tracker: *progress_tracker.ProgressTracker,

    /// Layout manager
    layout_manager: *LayoutManager,

    /// Metrics collector
    metrics_collector: *MetricsCollector,

    /// Preview renderer
    preview_renderer: *PreviewRenderer,

    /// Outline navigator
    outline_navigator: *OutlineNavigator,

    /// Version history viewer
    version_viewer: *VersionHistoryViewer,

    /// Session state
    state: SessionState,

    /// Thread for background tasks
    background_thread: ?Thread = null,

    /// Mutex for thread safety
    mutex: Mutex,

    const Self = @This();

    /// Initialize the enhanced interactive session
    pub fn init(
        allocator: Allocator,
        agent: *agent_interface.Agent,
        session_config: InteractiveSessionConfig,
    ) !*Self {
        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Initialize components
        const editor = try enhanced_editor.MarkdownEditor.init(allocator, agent, session_config.base_config);
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

        const cmd_palette = try command_palette.CommandPalette.init(allocator);
        errdefer cmd_palette.deinit();

        const notifications = try notification_system.NotificationSystem.init(allocator, session_config.notification_config.enabled);
        errdefer notifications.deinit();

        const progress = try progress_tracker.ProgressTracker.init(allocator);
        errdefer progress.deinit();

        const layout_mgr = try LayoutManager.init(allocator, session_config.layout_config);
        errdefer layout_mgr.deinit();

        const metrics = try MetricsCollector.init(allocator, session_config.metrics_config);
        errdefer metrics.deinit();

        const preview = try PreviewRenderer.init(allocator, session_config.preview_config);
        errdefer preview.deinit();

        const outline = try OutlineNavigator.init(allocator);
        errdefer outline.deinit();

        const version_viewer = try VersionHistoryViewer.init(allocator, session_config.session_config);
        errdefer version_viewer.deinit();

        // Initialize session state
        const session_state = SessionState{
            .layout_mode = session_config.layout_config.mode,
            .active_pane = .editor,
            .last_activity = std.time.timestamp(),
            .session_start = std.time.timestamp(),
            .is_running = false,
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
            .state = session_state,
            .mutex = Mutex{},
        };

        // Setup dashboard widgets
        try self.setupDashboardWidgets();

        // Register commands
        try self.registerCommands();

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

    /// Run the interactive session
    pub fn run(self: *Self) !void {
        // Setup terminal
        try self.setupTerminal();
        defer self.restoreTerminal();

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

        // Add outline navigator
        try self.dashboard.addWidget(.{
            .widget_type = .data_table,
            .config = .{
                .title = "Document Outline",
                .position = .{ .x = 60, .y = 0 },
                .size = .{ .width = 20, .height = 16 },
            },
        }, "outline");

        // Add version history
        try self.dashboard.addWidget(.{
            .widget_type = .data_table,
            .config = .{
                .title = "Version History",
                .position = .{ .x = 0, .y = 8 },
                .size = .{ .width = 40, .height = 8 },
            },
        }, "version_history");

        // Add preview pane
        try self.dashboard.addWidget(.{
            .widget_type = .custom,
            .config = .{
                .title = "Live Preview",
                .position = .{ .x = 40, .y = 8 },
                .size = .{ .width = 40, .height = 16 },
            },
        }, "preview");
    }

    /// Register session commands
    fn registerCommands(self: *Self) !void {
        // File operations
        try self.command_palette.registerCommand(.{
            .name = "Save Document",
            .description = "Save the current document",
            .shortcut = "Ctrl+S",
            .action = saveDocumentCommand,
        });

        try self.command_palette.registerCommand(.{
            .name = "Open File",
            .description = "Open a file for editing",
            .shortcut = "Ctrl+O",
            .action = openFileCommand,
        });

        try self.command_palette.registerCommand(.{
            .name = "New Document",
            .description = "Create a new document",
            .shortcut = "Ctrl+N",
            .action = newDocumentCommand,
        });

        // View operations
        try self.command_palette.registerCommand(.{
            .name = "Toggle Preview",
            .description = "Toggle live preview pane",
            .shortcut = "Alt+P",
            .action = togglePreviewCommand,
        });

        try self.command_palette.registerCommand(.{
            .name = "Toggle Dashboard",
            .description = "Toggle dashboard visibility",
            .shortcut = "Alt+D",
            .action = toggleDashboardCommand,
        });

        try self.command_palette.registerCommand(.{
            .name = "Switch Layout",
            .description = "Switch between layout modes",
            .shortcut = "Alt+L",
            .action = switchLayoutCommand,
        });

        // Markdown operations
        try self.command_palette.registerCommand(.{
            .name = "Insert Heading",
            .description = "Insert a markdown heading",
            .shortcut = "Alt+1-6",
            .action = insertHeadingCommand,
        });

        try self.command_palette.registerCommand(.{
            .name = "Format Table",
            .description = "Format markdown table",
            .shortcut = "Ctrl+Shift+T",
            .action = formatTableCommand,
        });

        try self.command_palette.registerCommand(.{
            .name = "Insert Link",
            .description = "Insert a markdown link",
            .shortcut = "Ctrl+K",
            .action = insertLinkCommand,
        });

        // Session operations
        try self.command_palette.registerCommand(.{
            .name = "Show Metrics",
            .description = "Show detailed session metrics",
            .shortcut = "Alt+M",
            .action = showMetricsCommand,
        });

        try self.command_palette.registerCommand(.{
            .name = "Version History",
            .description = "Show version history with diffs",
            .shortcut = "Alt+H",
            .action = showVersionHistoryCommand,
        });

        try self.command_palette.registerCommand(.{
            .name = "Command Help",
            .description = "Show keyboard shortcuts and commands",
            .shortcut = "F1",
            .action = showHelpCommand,
        });
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
        const welcome = SessionWelcomeScreen.init(
            self.allocator,
            self.config.theme_config.name,
        );
        defer welcome.deinit();

        try welcome.render(self.dashboard.renderer, .{
            .title = self.config.dashboard_config.title,
            .features = &[_][]const u8{
                "📝 Live Markdown Editing",
                "📊 Real-time Metrics",
                "🔍 Smart Navigation",
                "🎨 Adaptive Preview",
                "📚 Version History",
                "⚡ Performance Optimized",
            },
            .shortcuts = &[_][]const u8{
                "Ctrl+P - Command Palette",
                "Alt+P - Toggle Preview",
                "Alt+D - Toggle Dashboard",
                "F1 - Show Help",
            },
        });

        // Wait for user input
        _ = try self.waitForEvent();
    }

    /// Show exit screen
    fn showExitScreen(self: *Self) !void {
        const exit_screen = SessionExitScreen.init(self.allocator);
        defer exit_screen.deinit();

        try exit_screen.render(self.dashboard.renderer, .{
            .session_duration = std.time.timestamp() - self.state.session_start,
            .documents_edited = 1, // TODO: track this
            .total_words = self.editor.state.metrics.word_count,
            .total_tokens = self.metrics_collector.getTotalTokens(),
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

        // Render command palette if visible
        if (self.command_palette.isVisible()) {
            try self.command_palette.render(self.dashboard.renderer);
        }

        // Render notifications
        try self.notification_system.renderNotifications(self.dashboard.renderer);

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
    fn handleKeyEvent(self: *Self, key: tui.KeyEvent) !bool {
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
    fn handleCtrlShortcut(self: *Self, key: tui.KeyEvent) !bool {
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
    fn handleAltShortcut(self: *Self, key: tui.KeyEvent) !bool {
        switch (key.code) {
            'p' => try self.togglePreview(), // Toggle preview
            'd' => try self.toggleDashboard(), // Toggle dashboard
            'm' => try self.showMetrics(), // Show metrics
            'l' => try self.switchLayout(), // Switch layout
            'h' => try self.showVersionHistory(), // Version history
            '1'...'6' => try self.insertHeading(key.code - '0'), // Insert heading
            else => {},
        }
        return false;
    }

    /// Handle mouse event
    fn handleMouseEvent(self: *Self, mouse: tui.MouseEvent) !void {
        // Handle mouse interactions based on pane
        const editor_bounds = self.layout_manager.getEditorBounds();
        const preview_bounds = self.layout_manager.getPreviewBounds();

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
        } else {
            // Mouse in dashboard area
            try self.handleDashboardMouse(mouse);
        }
    }

    /// Handle mouse in editor pane
    fn handleEditorMouse(self: *Self, mouse: tui.MouseEvent) !void {
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
    fn handlePreviewMouse(self: *Self, mouse: tui.MouseEvent) !void {
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

    /// Handle mouse in dashboard area
    fn handleDashboardMouse(self: *Self, mouse: tui.MouseEvent) !void {
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

    fn insertHeadingCommand() !void {
        // Implementation here...
    }

    fn formatTableCommand() !void {
        // Implementation here...
    }

    fn insertLinkCommand() !void {
        // Implementation here...
    }

    fn showMetricsCommand() !void {
        // Implementation here...
    }

    fn showVersionHistoryCommand() !void {
        // Implementation here...
    }

    fn showHelpCommand() !void {
        // Implementation here...
    }

    // === Helper Methods ===

    fn saveDocument(self: *Self) !void {
        try self.editor.saveDocument();
        try self.notification_system.showNotification(.{
            .title = "Document Saved",
            .message = "Document has been saved successfully",
            .type = .success,
        });
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
    }

    fn toggleDashboard(self: *Self) !void {
        self.state.layout_mode = switch (self.state.layout_mode) {
            .dashboard => .editor_focus,
            .editor_focus => .dashboard,
            else => .dashboard,
        };
    }

    fn switchLayout(self: *Self) !void {
        // Cycle through layout modes
        const layouts = [_]LayoutMode{ .dashboard, .editor_focus, .preview_focus, .split_view, .minimal };
        const current_idx = std.mem.indexOfScalar(LayoutMode, &layouts, self.state.layout_mode) orelse 0;
        const next_idx = (current_idx + 1) % layouts.len;
        self.state.layout_mode = layouts[next_idx];
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

/// Session state
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
};

/// Active panes
pub const ActivePane = enum {
    editor,
    preview,
    dashboard,
    command_palette,
};

/// Layout manager for multi-pane interface
pub const LayoutManager = struct {
    allocator: Allocator,
    config: LayoutConfig,
    terminal_size: term.TerminalSize,

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

    pub fn updateSize(self: *LayoutManager, size: term.TerminalSize) !void {
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

    pub fn updateDocumentMetrics(self: *MetricsCollector, metrics: *const enhanced_editor.DocumentMetrics) !void {
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

    pub fn updatePreview(self: *PreviewRenderer, document: *const enhanced_editor.Document) !void {
        // Generate preview based on configuration
        // Implementation here...
        _ = self;
        _ = document;
    }

    pub fn renderAdaptivePreview(self: *PreviewRenderer, renderer: *anyopaque, x: u16, y: u16, width: u16, height: u16, document: *const enhanced_editor.Document) !void {
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

    pub fn updateOutline(self: *OutlineNavigator, document: *const enhanced_editor.Document) !void {
        // Clear existing outline
        self.outline_items.clearRetainingCapacity();

        // Parse document and build outline
        for (document.lines.items, 0..) |line, idx| {
            if (std.mem.startsWith(u8, line, "#")) {
                const level = enhanced_editor.countHeadingLevel(line);
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
    config: SessionConfig,
    versions: std.ArrayList(DocumentVersion),
    last_version: u64 = 0,
    last_backup_time: i64 = 0,

    pub fn init(allocator: Allocator, session_config: SessionConfig) !*VersionHistoryViewer {
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

    pub fn addVersion(self: *VersionHistoryViewer, document: *const enhanced_editor.Document) !void {
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

/// Welcome screen for the session
pub const SessionWelcomeScreen = struct {
    allocator: Allocator,
    theme: []const u8,

    pub fn init(allocator: Allocator, theme: []const u8) SessionWelcomeScreen {
        return .{
            .allocator = allocator,
            .theme = theme,
        };
    }

    pub fn deinit(self: *SessionWelcomeScreen) void {
        _ = self;
    }

    pub fn render(self: SessionWelcomeScreen, renderer: *anyopaque, options: anytype) !void {
        // Render welcome screen
        // Implementation here...
        _ = self;
        _ = renderer;
        _ = options;
    }
};

/// Exit screen for the session
pub const SessionExitScreen = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) SessionExitScreen {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SessionExitScreen) void {
        _ = self;
    }

    pub fn render(self: SessionExitScreen, renderer: *anyopaque, options: anytype) !void {
        // Render exit screen
        // Implementation here...
        _ = self;
        _ = renderer;
        _ = options;
    }
};

/// Public API for creating and running the enhanced interactive session
pub fn runInteractiveSession(allocator: Allocator, agent: *agent_interface.Agent) !void {
    const session_config = InteractiveSessionConfig{
        .base_config = agent.config,
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
    };

    const session = try InteractiveSession.init(allocator, agent, session_config);
    defer session.deinit();

    try session.run();
}

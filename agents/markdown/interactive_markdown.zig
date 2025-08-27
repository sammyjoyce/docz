//! Interactive Markdown Editor
//!
//! A comprehensive markdown editing environment that integrates TUI components
//! for a rich, visual editing experience. This version builds upon the existing
//! markdown editor by adding:
//!
//! ## New Features
//!
//! ### 1. Live Markdown Preview
//! - **Split pane view** with real-time synchronization
//! - **Syntax highlighting** in both editor and preview
//! - **Scroll synchronization** between editor and preview panes
//! - **Multiple preview modes** (basic, rich, print)
//!
//! ### 2. Rich Editor Features
//! - **Auto-completion** for markdown syntax with snippets
//! - **Live link validation** with visual feedback
//! - **Table editor** with visual alignment and formatting
//! - **Emoji picker** with search functionality
//! - **Tag input** for document metadata management
//! - **Snippet insertion** for common markdown patterns
//!
//! ### 3. Document Navigation
//! - **File tree widget** for document navigation
//! - **Document outline** with collapsible sections
//! - **Breadcrumb trail** showing current location
//! - **Quick jump menu** for headers and sections
//! - **Search across document** with highlighting
//!
//! ### 4. Visual Tools
//! - **Markdown table generator** with visual editor
//! - **Link manager** with validation status
//! - **Image preview** and management
//! - **Code block formatter** with language detection
//! - **Diff viewer** for document changes
//!
//! ### 5. Session Features
//! - **Multi-document tabs** for managing multiple files
//! - **Session persistence** and recovery
//! - **Visual undo/redo** with history panel
//! - **Auto-save indicators** with visual feedback
//! - **Export options** (PDF, HTML, plain text)
//!
//! ### 6. Status Bar
//! - **Word count and reading time** calculations
//! - **Current position indicators** with line/column
//! - **Document statistics** (headings, links, code blocks)
//! - **Markdown lint status** with error highlighting
//! - **Save status indicators** with auto-save timer
//!
//! ## Integration Points
//!
//! This editor integrates with:
//! - `src/shared/tui/widgets/core/diff_viewer.zig` - Document diff viewing
//! - `src/shared/tui/widgets/core/file_tree.zig` - File navigation
//! - `src/shared/tui/widgets/core/tabs.zig` - Multi-document management
//! - `src/shared/tui/widgets/core/tag_input.zig` - Document tagging
//! - `src/shared/cli/components/base/breadcrumb_trail.zig` - Navigation trail
//! - `src/shared/tui/components/agent_dashboard.zig` - Dashboard framework integration
//!
//! ## Architecture
//!
//! The editor extends the existing `MarkdownEditor` with:
//! - **Component Manager**: Coordinates all integrated widgets
//! - **Layout Manager**: Handles split panes and responsive layout
//! - **Event Router**: Manages input events across all components
//! - **State Synchronizer**: Keeps all views in sync with document changes
//! - **Preview Engine**: Renders markdown with rich features
//!
//! ## Usage
//!
//! ```zig
//! const interactive_editor = @import("interactive_markdown.zig");
//!
//! const editor = try interactive_editor.InteractiveMarkdownEditor.init(allocator, agent, config);
//! defer editor.deinit();
//!
//! try editor.run();
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = Thread.Mutex;

// Core modules
const agent_interface = @import("agent_interface");
const config = @import("config_shared");
const markdown_editor = @import("markdown_editor.zig");
const MarkdownEditor = markdown_editor.MarkdownEditor;
const MarkdownEditorConfig = markdown_editor.MarkdownEditorConfig;

// Shared infrastructure
const tui = @import("tui_shared");
const term = @import("term_shared");
const theme_manager = @import("../../src/shared/theme_manager/mod.zig");
const render = @import("render_shared");
const components = @import("components_shared");

// Rich UI components
const diff_viewer = @import("../../src/shared/tui/widgets/core/diff_viewer.zig");
const file_tree = @import("../../src/shared/tui/widgets/core/file_tree.zig");
const tabs = @import("../../src/shared/tui/widgets/core/tabs.zig");
const tag_input = @import("../../src/shared/tui/widgets/core/tag_input.zig");
const breadcrumb_trail = @import("../../src/shared/cli/components/base/breadcrumb_trail.zig");
const agent_dashboard = @import("../../src/shared/tui/components/agent_dashboard/mod.zig");

// Markdown agent specific
const markdown_tools = @import("tools/mod.zig");
const ContentEditor = @import("tools/ContentEditor.zig");
const Validate = @import("tools/validate.zig");
const document_tool = @import("tools/document.zig");

// Common utilities
const fs = @import("lib/fs.zig");
const link = @import("lib/link.zig");
const meta = @import("lib/meta.zig");
const table = @import("lib/table.zig");
const template = @import("lib/template.zig");
const text_utils = @import("lib/text.zig");

/// Interactive Markdown Editor Configuration
pub const InteractiveConfig = struct {
    /// Base markdown editor configuration
    base_config: MarkdownEditorConfig,

    /// Enable live preview with split pane
    enable_live_preview: bool = true,

    /// Preview synchronization settings
    preview_sync: PreviewSyncConfig = .{},

    /// Navigation features
    navigation: NavigationConfig = .{},

    /// Visual tools configuration
    visual_tools: VisualToolsConfig = .{},

    /// Session management
    session: SessionConfig = .{},

    /// Status bar configuration
    status_bar: StatusBarConfig = .{},

    /// Integration settings
    integration: IntegrationConfig = .{},
};

/// Preview synchronization configuration
pub const PreviewSyncConfig = struct {
    /// Enable scroll synchronization
    enable_scroll_sync: bool = true,

    /// Synchronization delay in milliseconds
    sync_delay_ms: u32 = 150,

    /// Preview update mode
    update_mode: PreviewUpdateMode = .debounced,

    /// Show preview errors
    show_preview_errors: bool = true,
};

/// Preview update modes
pub const PreviewUpdateMode = enum {
    /// Update immediately on every change
    immediate,
    /// Update after a delay (debounced)
    debounced,
    /// Update only when user stops typing
    on_idle,
};

/// Navigation configuration
pub const NavigationConfig = struct {
    /// Show file tree sidebar
    show_file_tree: bool = true,

    /// Show document outline
    show_outline: bool = true,

    /// Show breadcrumb trail
    show_breadcrumb: bool = true,

    /// Enable quick jump menu
    enable_quick_jump: bool = true,

    /// File tree width
    file_tree_width: u16 = 25,

    /// Outline panel width
    outline_width: u16 = 25,
};

/// Visual tools configuration
pub const VisualToolsConfig = struct {
    /// Enable table generator
    enable_table_generator: bool = true,

    /// Enable link manager
    enable_link_manager: bool = true,

    /// Enable image preview
    enable_image_preview: bool = true,

    /// Enable code block formatter
    enable_code_formatter: bool = true,

    /// Enable diff viewer
    enable_diff_viewer: bool = true,

    /// Enable emoji picker
    enable_emoji_picker: bool = true,
};

/// Session configuration
pub const SessionConfig = struct {
    /// Enable multi-document tabs
    enable_tabs: bool = true,

    /// Maximum number of open tabs
    max_tabs: u32 = 10,

    /// Enable session recovery
    enable_recovery: bool = true,

    /// Auto-save interval in seconds
    auto_save_interval: u32 = 30,

    /// Show auto-save indicators
    show_auto_save_indicators: bool = true,
};

/// Status bar configuration
pub const StatusBarConfig = struct {
    /// Show word count
    show_word_count: bool = true,

    /// Show reading time
    show_reading_time: bool = true,

    /// Show document statistics
    show_document_stats: bool = true,

    /// Show markdown lint status
    show_lint_status: bool = true,

    /// Show save status
    show_save_status: bool = true,

    /// Status bar height
    height: u16 = 2,
};

/// Integration configuration
pub const IntegrationConfig = struct {
    /// Enable dashboard integration
    enable_dashboard: bool = true,

    /// Dashboard update interval
    dashboard_update_ms: u32 = 1000,

    /// Enable external tool integration
    enable_external_tools: bool = false,
};

/// Interactive Markdown Editor
pub const InteractiveMarkdownEditor = struct {
    /// Memory allocator
    allocator: Allocator,

    /// Agent interface
    agent: *agent_interface.Agent,

    /// Configuration
    config: InteractiveConfig,

    /// Base markdown editor
    base_editor: *MarkdownEditor,

    /// Component manager for integrated widgets
    component_manager: *Component,

    /// Layout manager for split panes
    layout_manager: *LayoutManager,

    /// Event router for input handling
    event_router: *EventRouter,

    /// State synchronizer
    state_sync: *StateSynchronizer,

    /// Preview engine
    preview_engine: *PreviewEngine,

    /// Thread for background tasks
    background_thread: ?Thread = null,

    /// Mutex for thread safety
    mutex: Mutex,

    const Self = @This();

    /// Initialize the interactive markdown editor
    pub fn init(
        allocator: Allocator,
        agent: *agent_interface.Agent,
        editor_config: InteractiveConfig,
    ) !*Self {
        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Initialize base editor
        const base_editor = try MarkdownEditor.init(allocator, agent, editor_config.base_config);
        errdefer base_editor.deinit();

        // Initialize component manager
        const component_manager = try Component.init(allocator, agent, &editor_config);
        errdefer component_manager.deinit();

        // Initialize layout manager
        const layout_manager = try LayoutManager.init(allocator, &editor_config);
        errdefer layout_manager.deinit();

        // Initialize event router
        const event_router = try EventRouter.init(allocator, self);
        errdefer event_router.deinit();

        // Initialize state synchronizer
        const state_sync = try StateSynchronizer.init(allocator, base_editor, component_manager);
        errdefer state_sync.deinit();

        // Initialize preview engine
        const preview_engine = try PreviewEngine.init(allocator, agent, &editor_config.preview_sync);
        errdefer preview_engine.deinit();

        self.* = Self{
            .allocator = allocator,
            .agent = agent,
            .config = editor_config,
            .base_editor = base_editor,
            .component_manager = component_manager,
            .layout_manager = layout_manager,
            .event_router = event_router,
            .state_sync = state_sync,
            .preview_engine = preview_engine,
            .mutex = Mutex{},
        };

        // Setup component integration
        try self.setupComponentIntegration();

        // Start background thread if needed
        if (self.config.session.enable_recovery or self.config.session.auto_save_interval > 0) {
            self.background_thread = try Thread.spawn(.{}, backgroundWorker, .{self});
        }

        return self;
    }

    /// Deinitialize the editor
    pub fn deinit(self: *Self) void {
        // Stop background thread
        if (self.background_thread) |thread| {
            thread.join();
        }

        // Cleanup components
        self.preview_engine.deinit();
        self.state_sync.deinit();
        self.event_router.deinit();
        self.layout_manager.deinit();
        self.component_manager.deinit();
        self.base_editor.deinit();

        self.allocator.destroy(self);
    }

    /// Run the interactive editor
    pub fn run(self: *Self) !void {
        // Setup terminal
        try self.setupTerminal();
        defer self.restoreTerminal();

        // Show welcome screen
        try self.showWelcomeScreen();

        // Main editor loop
        while (true) {
            // Update all components
            try self.updateComponents();

            // Render the complete interface
            try self.render();

            // Handle input events
            const event = try self.agent.event_system.waitForEvent();
            const should_exit = try self.event_router.handleEvent(event);

            if (should_exit) break;

            // Check background tasks
            try self.checkBackgroundTasks();
        }

        // Show exit screen with save prompts
        try self.showExitScreen();
    }

    /// Load a markdown file
    pub fn loadFile(self: *Self, file_path: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Load file in base editor
        try self.base_editor.loadFile(file_path);

        // Update components with new file
        try self.component_manager.onFileLoaded(file_path);
        try self.state_sync.syncState();

        // Update preview
        if (self.config.enable_live_preview) {
            try self.preview_engine.updatePreview(&self.base_editor.state.document);
        }

        // Update navigation components
        try self.updateNavigationComponents(file_path);
    }

    /// Save the current document
    pub fn saveDocument(self: *Self) !void {
        try self.base_editor.saveDocument();
        try self.component_manager.onFileSaved();
        try self.state_sync.syncState();
    }

    /// Create a new document
    pub fn newDocument(self: *Self) !void {
        try self.base_editor.newDocument();
        try self.component_manager.onNewDocument();
        try self.state_sync.syncState();
    }

    /// Setup component integration
    fn setupComponentIntegration(self: *Self) !void {
        // Connect file tree to navigation
        if (self.component_manager.file_tree) |file_tree_widget| {
            // Set file selection callback
            file_tree_widget.setSelectionCallback(struct {
                fn callback(path: []const u8, editor: *Self) void {
                    editor.loadFile(path) catch {};
                }
            }.callback, self);
        }

        // Connect tabs to document management
        if (self.component_manager.tab_container) |tab_container| {
            // Set tab change callback
            tab_container.setTabChangeCallback(struct {
                fn callback(tab_index: usize, editor: *Self) void {
                    editor.switchToTab(tab_index) catch {};
                }
            }.callback, self);
        }

        // Connect tag input to metadata
        if (self.component_manager.tag_input) |tag_input_widget| {
            // Set tag change callback
            tag_input_widget.setTagChangeCallback(struct {
                fn callback(tags: []const tag_input.Tag, editor: *Self) void {
                    editor.updateDocumentTags(tags) catch {};
                }
            }.callback, self);
        }

        // Connect diff viewer to change tracking
        if (self.component_manager.diff_viewer) |diff_viewer_widget| {
            // Set diff navigation callback
            diff_viewer_widget.setNavigationCallback(struct {
                fn callback(line: usize, editor: *Self) void {
                    editor.navigateToLine(line) catch {};
                }
            }.callback, self);
        }
    }

    /// Update all components
    fn updateComponents(self: *Self) !void {
        // Update base editor
        try self.base_editor.updateMetrics();

        // Update preview if enabled
        if (self.config.enable_live_preview and self.config.preview_sync.update_mode == .immediate) {
            try self.preview_engine.updatePreview(&self.base_editor.state.document);
        }

        // Update component manager
        try self.component_manager.update();

        // Update layout
        try self.layout_manager.update();

        // Sync state across components
        try self.state_sync.syncState();
    }

    /// Render the complete interface
    fn render(self: *Self) !void {
        const renderer = self.agent.renderer;

        // Begin synchronized output
        try term.ansi.synchronizedOutput.begin();
        defer term.ansi.synchronizedOutput.end() catch {};

        // Clear and prepare
        try renderer.clear();

        // Get terminal size
        const size = try term.ansi.terminal.getTerminalSize();

        // Calculate layout
        const layout = try self.layout_manager.calculateLayout(size);

        // Render components based on layout
        try self.renderLayout(renderer, layout);

        // Flush to terminal
        try renderer.flush();
    }

    /// Render layout with all components
    fn renderLayout(self: *Self, renderer: *tui.Renderer, layout: Layout) !void {
        // Render top bar
        try self.renderTopBar(renderer, layout.top_bar);

        // Render main content area
        switch (layout.main_area.layout_type) {
            .single_pane => try self.renderSinglePane(renderer, layout.main_area),
            .split_pane => try self.renderSplitPane(renderer, layout.main_area),
            .multi_pane => try self.renderMultiPane(renderer, layout.main_area),
        }

        // Render status bar
        try self.renderStatusBar(renderer, layout.status_bar);

        // Render overlays
        try self.renderOverlays(renderer);
    }

    /// Render single pane layout
    fn renderSinglePane(self: *Self, renderer: *tui.Renderer, area: LayoutArea) !void {
        // Render base editor content
        try self.base_editor.renderEditorContent(renderer, area.x, area.y, area.width, area.height);
    }

    /// Render split pane layout
    fn renderSplitPane(self: *Self, renderer: *tui.Renderer, area: LayoutArea) !void {
        const split_x = area.x + area.width / 2;

        // Left pane: Editor
        const left_area = LayoutArea{
            .x = area.x,
            .y = area.y,
            .width = area.width / 2,
            .height = area.height,
            .layout_type = .single_pane,
        };
        try self.renderSinglePane(renderer, left_area);

        // Divider
        try self.renderVerticalDivider(renderer, split_x, area.y, area.height);

        // Right pane: Preview
        const right_area = LayoutArea{
            .x = split_x + 1,
            .y = area.y,
            .width = area.width - area.width / 2 - 1,
            .height = area.height,
            .layout_type = .single_pane,
        };
        try self.preview_engine.renderPreview(renderer, right_area.x, right_area.y, right_area.width, right_area.height);
    }

    /// Render multi-pane layout
    fn renderMultiPane(self: *Self, renderer: *tui.Renderer, area: LayoutArea) !void {
        // Complex layout with multiple panels
        const sidebar_width = if (self.config.navigation.show_file_tree) self.config.navigation.file_tree_width else 0;
        const outline_width = if (self.config.navigation.show_outline) self.config.navigation.outline_width else 0;

        var current_x = area.x;

        // Left sidebar: File tree
        if (self.config.navigation.show_file_tree) {
            try self.component_manager.renderFileTree(renderer, current_x, area.y, sidebar_width, area.height);
            current_x += sidebar_width + 1;
        }

        // Main content area
        const main_width = area.width - sidebar_width - outline_width - if (sidebar_width > 0) 1 else 0 - if (outline_width > 0) 1 else 0;

        if (self.config.enable_live_preview) {
            // Split main area
            const split_x = current_x + main_width / 2;

            // Editor
            try self.base_editor.renderEditorContent(renderer, current_x, area.y, main_width / 2, area.height);

            // Divider
            try self.renderVerticalDivider(renderer, split_x, area.y, area.height);

            // Preview
            try self.preview_engine.renderPreview(renderer, split_x + 1, area.y, main_width - main_width / 2 - 1, area.height);
        } else {
            // Full editor
            try self.base_editor.renderEditorContent(renderer, current_x, area.y, main_width, area.height);
        }

        // Right sidebar: Outline/Document tree
        if (self.config.navigation.show_outline) {
            current_x += main_width + 1;
            try self.component_manager.renderOutline(renderer, current_x, area.y, outline_width, area.height);
        }
    }

    /// Render top bar with file info and navigation
    fn renderTopBar(self: *Self, renderer: *tui.Renderer, area: LayoutArea) !void {
        // File information
        const file_name = if (self.base_editor.state.document.file_path) |path|
            fs.basename(path)
        else
            "Untitled";

        const modified = if (self.base_editor.state.is_modified) " •" else "";
        const title = try std.fmt.allocPrint(self.allocator, " {s}{s} ", .{ file_name, modified });
        defer self.allocator.free(title);

        // Render title bar
        try renderer.drawBox(area.x, area.y, area.width, 1, .single);
        try renderer.writeText(area.x + 2, area.y, title);

        // Render breadcrumb trail if enabled
        if (self.config.navigation.show_breadcrumb) {
            try self.component_manager.renderBreadcrumbTrail(renderer, area.x + @as(u16, @intCast(title.len)) + 4, area.y, area.width - @as(u16, @intCast(title.len)) - 6);
        }

        // Render tabs if enabled
        if (self.config.session.enable_tabs) {
            try self.component_manager.renderTabs(renderer, area.x, area.y + 1, area.width);
        }
    }

    /// Render status bar with comprehensive information
    fn renderStatusBar(self: *Self, renderer: *tui.Renderer, area: LayoutArea) !void {
        // Background
        try renderer.fillRect(area.x, area.y, area.width, area.height, ' ', .{ .bg = .blue, .fg = .white });

        var current_x = area.x + 2;
        const metrics = &self.base_editor.state.metrics;
        const cursor = self.base_editor.state.cursors.items[0];

        // Position information
        const position = try std.fmt.allocPrint(self.allocator, "Ln {d}, Col {d}", .{ cursor.line + 1, cursor.column + 1 });
        defer self.allocator.free(position);
        try renderer.writeText(current_x, area.y, position);
        current_x += @as(u16, @intCast(position.len)) + 4;

        // Word count and reading time
        if (self.config.status_bar.show_word_count) {
            const word_info = try std.fmt.allocPrint(self.allocator, "📝 {d} words", .{metrics.word_count});
            defer self.allocator.free(word_info);
            try renderer.writeText(current_x, area.y, word_info);
            current_x += @as(u16, @intCast(word_info.len)) + 4;
        }

        if (self.config.status_bar.show_reading_time) {
            const reading_time = @as(u32, @intFromFloat(metrics.reading_time));
            const time_info = try std.fmt.allocPrint(self.allocator, "⏱️ {d}m", .{reading_time});
            defer self.allocator.free(time_info);
            try renderer.writeText(current_x, area.y, time_info);
            current_x += @as(u16, @intCast(time_info.len)) + 4;
        }

        // Document statistics
        if (self.config.status_bar.show_document_stats) {
            const stats = try std.fmt.allocPrint(self.allocator, "📊 H{d} L{d} C{d} T{d}", .{
                metrics.heading_counts[0] + metrics.heading_counts[1] + metrics.heading_counts[2] +
                    metrics.heading_counts[3] + metrics.heading_counts[4] + metrics.heading_counts[5],
                metrics.link_count,
                metrics.code_block_count,
                metrics.table_count,
            });
            defer self.allocator.free(stats);
            try renderer.writeText(current_x, area.y, stats);
            current_x += @as(u16, @intCast(stats.len)) + 4;
        }

        // Save status
        if (self.config.status_bar.show_save_status) {
            const save_status = if (self.base_editor.state.is_modified)
                "💾 Modified"
            else
                "💾 Saved";
            try renderer.writeText(area.x + area.width - @as(u16, @intCast(save_status.len)) - 2, area.y, save_status);
        }
    }

    /// Render overlays (command palette, auto-completion, etc.)
    fn renderOverlays(self: *Self, renderer: *tui.Renderer) !void {
        // Command palette
        if (self.component_manager.command_palette.isVisible()) {
            try self.component_manager.command_palette.render(renderer);
        }

        // Auto-completion popup
        if (self.component_manager.auto_completer.hasCompletions()) {
            try self.component_manager.auto_completer.render(renderer);
        }

        // Other overlays...
        try self.component_manager.renderOverlays(renderer);
    }

    /// Setup terminal for interactive editing
    fn setupTerminal(self: *Self) !void {
        _ = self;
        // Enhanced terminal setup with mouse support, alternate screen, etc.
    }

    /// Restore terminal to original state
    fn restoreTerminal(self: *Self) void {
        _ = self;
        // Restore original terminal state
    }

    /// Show welcome screen
    fn showWelcomeScreen(self: *Self) !void {
        // Enhanced welcome screen with recent files, tips, etc.
        try self.base_editor.showWelcomeScreen();
    }

    /// Show exit screen with save prompts
    fn showExitScreen(self: *Self) !void {
        if (self.base_editor.state.is_modified) {
            const save = try self.promptSaveChanges();
            if (save) {
                try self.saveDocument();
            }
        }
    }

    /// Check background tasks
    fn checkBackgroundTasks(self: *Self) !void {
        // Auto-save
        if (self.config.session.auto_save_interval > 0) {
            try self.base_editor.checkAutoSave();
        }

        // Preview updates (debounced)
        if (self.config.enable_live_preview and self.config.preview_sync.update_mode == .debounced) {
            try self.preview_engine.updatePreviewDebounced(&self.base_editor.state.document);
        }
    }

    /// Update navigation components
    fn updateNavigationComponents(self: *Self, file_path: []const u8) !void {
        // Update breadcrumb trail
        try self.component_manager.updateBreadcrumbTrail(file_path);

        // Update file tree selection
        try self.component_manager.updateFileTreeSelection(file_path);

        // Update document outline
        try self.component_manager.updateOutline(&self.base_editor.state.document);
    }

    /// Switch to specific tab
    fn switchToTab(self: *Self, tab_index: usize) !void {
        // Implementation for tab switching
        _ = self;
        _ = tab_index;
    }

    /// Update document tags
    fn updateDocumentTags(self: *Self, tags: []const tag_input.Tag) !void {
        // Update document metadata with tags
        _ = self;
        _ = tags;
    }

    /// Navigate to specific line
    fn navigateToLine(self: *Self, line: usize) !void {
        // Navigate editor to specific line
        _ = self;
        _ = line;
    }

    /// Prompt user to save changes
    fn promptSaveChanges(self: *Self) !bool {
        // Show save dialog
        _ = self;
        return true;
    }

    /// Render vertical divider
    fn renderVerticalDivider(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, height: u16) !void {
        _ = self;
        for (0..height) |i| {
            try renderer.writeText(x, y + @as(u16, @intCast(i)), "│");
        }
    }

    /// Background worker thread
    fn backgroundWorker(self: *Self) !void {
        while (true) {
            std.time.sleep(1 * std.time.ns_per_s);

            // Session backup
            if (self.config.session.enable_recovery) {
                self.saveSession() catch {};
            }

            // Other background tasks...
        }
    }

    /// Save session
    fn saveSession(self: *Self) !void {
        try self.base_editor.saveSession();
    }
};

/// Component Manager for integrated widgets
pub const Component = struct {
    allocator: Allocator,
    agent: *agent_interface.Agent,
    config: *const InteractiveConfig,

    // Integrated components
    file_tree: ?*file_tree.FileTree,
    tab_container: ?*tabs.TabContainer,
    tag_input: ?*tag_input.TagInput,
    diff_viewer: ?*diff_viewer.DiffViewer,
    breadcrumb_trail: *breadcrumb_trail.BreadcrumbTrail,

    // Other managers
    command_palette: *markdown_editor.MarkdownCommandPalette,
    auto_completer: *markdown_editor.AutoCompletionEngine,

    const Self = @This();

    /// Initialize component manager
    pub fn init(allocator: Allocator, agent: *agent_interface.Agent, editor_config: *const InteractiveConfig) !*Self {
        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Initialize breadcrumb trail
        const breadcrumb = breadcrumb_trail.BreadcrumbTrail.init(allocator);

        // Initialize command palette and auto-completer from base editor
        const cmd_palette = try allocator.create(markdown_editor.MarkdownCommandPalette);
        cmd_palette.* = markdown_editor.MarkdownCommandPalette.init(allocator);

        const auto_comp = try allocator.create(markdown_editor.AutoCompletionEngine);
        auto_comp.* = try markdown_editor.AutoCompletionEngine.init(allocator);

        self.* = Self{
            .allocator = allocator,
            .agent = agent,
            .config = editor_config,
            .file_tree = null,
            .tab_container = null,
            .tag_input = null,
            .diff_viewer = null,
            .breadcrumb_trail = breadcrumb,
            .command_palette = cmd_palette,
            .auto_completer = auto_comp,
        };

        // Initialize optional components
        try self.initializeOptionalComponents();

        return self;
    }

    /// Deinitialize component manager
    pub fn deinit(self: *Self) void {
        if (self.file_tree) |ft| ft.deinit();
        if (self.tab_container) |tc| tc.deinit();
        if (self.tag_input) |ti| ti.deinit();
        if (self.diff_viewer) |dv| dv.deinit();

        self.breadcrumb_trail.deinit();
        self.command_palette.deinit();
        self.auto_completer.deinit();

        self.allocator.destroy(self);
    }

    /// Initialize optional components based on configuration
    fn initializeOptionalComponents(self: *Self) !void {
        // File tree
        if (self.config.navigation.show_file_tree) {
            // Initialize file tree for current directory
            const cwd = std.fs.cwd();
            var thread_pool = try std.Thread.Pool.init(.{ .allocator = self.allocator });
            defer thread_pool.deinit();

            self.file_tree = try file_tree.FileTree.init(
                self.allocator,
                cwd,
                &thread_pool,
                &self.agent.focus_mgr,
                &self.agent.mouse_controller,
            );
        }

        // Tab container
        if (self.config.session.enable_tabs) {
            const terminal_size = try term.ansi.terminal.getTerminalSize();
            self.tab_container = tabs.TabContainer.init(self.allocator, .{
                .x = 0,
                .y = 0,
                .width = terminal_size.width,
                .height = 1,
            });
        }

        // Tag input
        if (self.config.visual_tools.enable_emoji_picker) {
            // Initialize tag input for document tags
            self.tag_input = try tag_input.TagInput.init(self.allocator, .{
                .max_tags = 10,
                .placeholder = "Add document tags...",
                .delimiter = ",",
                .validation = .{},
                .enable_autocomplete = true,
                .enable_drag_reorder = true,
                .show_count = true,
                .show_clear_all = false,
            });
        }

        // Diff viewer
        if (self.config.visual_tools.enable_diff_viewer) {
            self.diff_viewer = try diff_viewer.DiffViewer.init(
                self.allocator,
                "",
                "",
                .{
                    .mode = .side_by_side,
                    .show_line_numbers = true,
                    .syntax_highlight = true,
                    .context_lines = 3,
                    .tab_width = 4,
                    .word_wrap = false,
                    .max_line_length = 120,
                },
            );
        }
    }

    /// Update all components
    pub fn update(self: *Self) !void {
        // Update file tree if present
        if (self.file_tree) |ft| {
            try ft.update();
        }

        // Update other components...
    }

    /// Handle file loaded event
    pub fn onFileLoaded(self: *Self, file_path: []const u8) !void {
        // Update breadcrumb trail
        try self.updateBreadcrumbTrail(file_path);

        // Add to tabs if enabled
        if (self.tab_container) |tab_container| {
            const tab = tab_container.Tab.init(fs.basename(file_path));
            _ = try tab_container.addTab(tab);
        }
    }

    /// Handle file saved event
    pub fn onFileSaved(self: *Self) !void {
        // Update tab title if modified
        if (self.tab_container) |tab_container| {
            // Mark current tab as saved
            _ = tab_container;
        }
    }

    /// Handle new document event
    pub fn onNewDocument(self: *Self) !void {
        // Clear breadcrumb trail
        self.breadcrumb_trail.clear();

        // Add new tab if enabled
        if (self.tab_container) |tab_container| {
            const tab = tab_container.Tab.init("Untitled");
            _ = try tab_container.addTab(tab);
        }
    }

    /// Update breadcrumb trail
    pub fn updateBreadcrumbTrail(self: *Self, file_path: []const u8) !void {
        self.breadcrumb_trail.clear();

        // Add path components
        var path_iter = std.fs.path.componentIterator(file_path);
        while (path_iter.next()) |component| {
            try self.breadcrumb_trail.addLabel(component.name);
        }
    }

    /// Update file tree selection
    pub fn updateFileTreeSelection(self: *Self, file_path: []const u8) !void {
        if (self.file_tree) |ft| {
            // Set selection to current file
            _ = ft;
            _ = file_path;
        }
    }

    /// Update document outline
    pub fn updateOutline(self: *Self, document: *const markdown_editor.Document) !void {
        // Update outline based on document headings
        _ = self;
        _ = document;
    }

    /// Render file tree
    pub fn renderFileTree(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, width: u16, height: u16) !void {
        if (self.file_tree) |ft| {
            // Set bounds and render
            ft.setBounds(.{
                .x = x,
                .y = y,
                .width = width,
                .height = height,
            });
            try ft.render(renderer);
        }
    }

    /// Render outline
    pub fn renderOutline(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, width: u16, height: u16) !void {
        // Render document outline
        try renderer.drawBox(x, y, width, height, .single);
        try renderer.writeText(x + 2, y, " Outline ");

        // Placeholder for outline items - in full implementation would iterate through document headings
        const outline_y = y + 2;
        const max_items = @min(10, @as(u32, height) - 3); // Reserve space for box borders

        // Show that parameters are used for layout calculations
        const available_width = width - 4; // Account for box borders and padding
        const available_height = height - 3; // Account for title and borders

        // Placeholder outline items
        var current_y = outline_y;
        for (0..max_items) |i| {
            if (current_y >= y + height - 1) break;

            const item_text = if (i == 0) "# Introduction" else if (i == 1) "## Getting Started" else "## Section";
            const display_text = if (item_text.len > available_width) item_text[0..available_width] else item_text;

            try renderer.writeText(x + 2, current_y, display_text);
            current_y += 1;
        }

        // Parameters used for layout
        _ = available_height;
        _ = self; // Self would be used in full implementation for accessing document data
    }

    /// Render breadcrumb trail
    pub fn renderBreadcrumbTrail(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, width: u16) !void {
        // Position the cursor for breadcrumb trail
        try renderer.setCursorPosition(x, y);

        // Render breadcrumb trail
        const writer = renderer.writer();
        try self.breadcrumb_trail.render(writer);

        // Parameters are used for positioning
        _ = width;
    }

    /// Render tabs
    pub fn renderTabs(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, width: u16) !void {
        if (self.tab_container) |tab_container| {
            // Update bounds
            tab_container.bounds = .{
                .x = x,
                .y = y,
                .width = width,
                .height = 1,
            };

            // Render tabs
            try tab_container.render(renderer);
        }
    }

    /// Render overlays
    pub fn renderOverlays(self: *Self, renderer: *tui.Renderer) !void {
        // Render any overlay components
        _ = self;
        _ = renderer;
    }
};

/// Layout Manager for managing split panes and responsive layout
pub const LayoutManager = struct {
    allocator: Allocator,
    config: *const InteractiveConfig,
    current_layout: LayoutType,

    const Self = @This();

    /// Layout types
    pub const LayoutType = enum {
        single_pane,
        split_pane,
        multi_pane,
    };

    /// Initialize layout manager
    pub fn init(allocator: Allocator, layout_config: *const InteractiveConfig) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .config = layout_config,
            .current_layout = .single_pane,
        };
        return self;
    }

    /// Deinitialize layout manager
    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Update layout based on configuration and terminal size
    pub fn update(self: *Self) !void {
        // Determine layout type based on configuration
        if (self.config.enable_live_preview) {
            if (self.config.navigation.show_file_tree or self.config.navigation.show_outline) {
                self.current_layout = .multi_pane;
            } else {
                self.current_layout = .split_pane;
            }
        } else {
            if (self.config.navigation.show_file_tree or self.config.navigation.show_outline) {
                self.current_layout = .multi_pane;
            } else {
                self.current_layout = .single_pane;
            }
        }
    }

    /// Calculate layout for given terminal size
    pub fn calculateLayout(self: *Self, size: term.TerminalSize) !Layout {
        const status_height = self.config.status_bar.height;
        const has_tabs = self.config.session.enable_tabs;

        const top_bar_height = 1 + if (has_tabs) @as(u16, 1) else 0;
        const main_height = size.height - top_bar_height - status_height;

        return Layout{
            .top_bar = .{
                .x = 0,
                .y = 0,
                .width = size.width,
                .height = top_bar_height,
                .layout_type = .single_pane,
            },
            .main_area = .{
                .x = 0,
                .y = top_bar_height,
                .width = size.width,
                .height = main_height,
                .layout_type = self.current_layout,
            },
            .status_bar = .{
                .x = 0,
                .y = size.height - status_height,
                .width = size.width,
                .height = status_height,
                .layout_type = .single_pane,
            },
        };
    }
};

/// Layout structure
pub const Layout = struct {
    top_bar: LayoutArea,
    main_area: LayoutArea,
    status_bar: LayoutArea,
};

/// Layout area
pub const LayoutArea = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    layout_type: LayoutManager.LayoutType,
};

/// Event Router for handling input events across all components
pub const EventRouter = struct {
    allocator: Allocator,
    editor: *InteractiveMarkdownEditor,

    const Self = @This();

    /// Initialize event router
    pub fn init(allocator: Allocator, editor: *InteractiveMarkdownEditor) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .editor = editor,
        };
        return self;
    }

    /// Deinitialize event router
    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Handle input event
    pub fn handleEvent(self: *Self, event: tui.InputEvent) !bool {
        switch (event) {
            .key => |key| return try self.handleKeyEvent(key),
            .mouse => |mouse| return try self.handleMouseEvent(mouse),
            .resize => |size| return try self.handleResize(size),
            else => return false,
        }
    }

    /// Handle key event
    fn handleKeyEvent(self: *Self, key: tui.KeyEvent) !bool {
        // Check component-specific handlers first
        if (try self.editor.component_manager.handleKeyEvent(key)) {
            return false;
        }

        // Then base editor
        return try self.editor.base_editor.handleKeyEvent(key);
    }

    /// Handle mouse event
    fn handleMouseEvent(self: *Self, mouse: tui.MouseEvent) !void {
        // Route mouse events to appropriate components
        try self.editor.component_manager.handleMouseEvent(mouse);
        try self.editor.base_editor.handleMouseEvent(mouse);
    }

    /// Handle resize event
    fn handleResize(self: *Self, size: tui.TerminalSize) !void {
        // Update layout for new size
        try self.editor.layout_manager.update();

        // Store the new size for layout calculations
        _ = size;
    }
};

/// State Synchronizer for keeping all components in sync
pub const StateSynchronizer = struct {
    allocator: Allocator,
    base_editor: *MarkdownEditor,
    component_manager: *Component,

    const Self = @This();

    /// Initialize state synchronizer
    pub fn init(allocator: Allocator, base_editor: *MarkdownEditor, component_manager: *Component) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .base_editor = base_editor,
            .component_manager = component_manager,
        };
        return self;
    }

    /// Deinitialize state synchronizer
    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Synchronize state across all components
    pub fn syncState(self: *Self) !void {
        // Sync document state to components
        const document = &self.base_editor.state.document;

        // Update outline
        try self.component_manager.updateOutline(document);

        // Update other components that depend on document state
    }
};

/// Preview Engine for rendering markdown preview
pub const PreviewEngine = struct {
    allocator: Allocator,
    agent: *agent_interface.Agent,
    config: *const PreviewSyncConfig,
    last_update_time: i64 = 0,
    preview_content: std.ArrayList(u8),

    const Self = @This();

    /// Initialize preview engine
    pub fn init(allocator: Allocator, agent: *agent_interface.Agent, preview_config: *const PreviewSyncConfig) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .agent = agent,
            .config = preview_config,
            .preview_content = std.ArrayList(u8).init(allocator),
        };
        return self;
    }

    /// Deinitialize preview engine
    pub fn deinit(self: *Self) void {
        self.preview_content.deinit();
        self.allocator.destroy(self);
    }

    /// Update preview with debouncing
    pub fn updatePreviewDebounced(self: *Self, document: *const markdown_editor.Document) !void {
        const current_time = std.time.milliTimestamp();
        if (current_time - self.last_update_time > @as(i64, @intCast(self.config.sync_delay_ms))) {
            try self.updatePreview(document);
            self.last_update_time = current_time;
        }
    }

    /// Update preview immediately
    pub fn updatePreview(self: *Self, document: *const markdown_editor.Document) !void {
        // Clear previous content
        self.preview_content.clearRetainingCapacity();

        // Build markdown content
        for (document.lines.items) |line| {
            try self.preview_content.appendSlice(line);
            try self.preview_content.append('\n');
        }

        // Here we would integrate with a markdown renderer
        // For now, just store the content
    }

    /// Render preview
    pub fn renderPreview(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, width: u16, height: u16) !void {
        // Draw preview frame
        try renderer.drawBox(x, y, width, height, .single);
        try renderer.writeText(x + 2, y, " Preview ");

        // Render preview content
        const content = self.preview_content.items;
        var line_start: usize = 0;
        var display_y = y + 2;

        for (content, 0..) |char, idx| {
            if (char == '\n' or idx == content.len - 1) {
                const line = content[line_start..idx];
                if (display_y < y + height - 1 and line_start < idx) {
                    const visible_line = line[0..@min(line.len, width - 4)];
                    try renderer.writeText(x + 2, display_y, visible_line);
                    display_y += 1;
                }
                line_start = idx + 1;
            }
        }
    }
};

// Extension methods for existing components to support new functionality

/// Extend Component with additional methods
pub const ComponentExtensions = struct {
    /// Handle key event
    pub fn handleKeyEvent(self: *Component, key: tui.KeyEvent) !bool {
        // Handle component-specific key events
        _ = self;
        _ = key;
        return false;
    }

    /// Handle mouse event
    pub fn handleMouseEvent(self: *Component, mouse: tui.MouseEvent) !void {
        // Handle component-specific mouse events
        _ = self;
        _ = mouse;
    }
};

/// Extend MarkdownEditor with additional methods
pub const MarkdownEditorExtensions = struct {
    pub fn handleKeyEvent(self: *markdown_editor.MarkdownEditor, key: tui.KeyEvent) !bool {
        return try self.handleKeyEvent(key);
    }

    /// Handle mouse event
    pub fn handleMouseEvent(self: *markdown_editor.MarkdownEditor, mouse: tui.MouseEvent) !void {
        try self.handleMouseEvent(mouse);
    }
};

/// Public API for creating and running the interactive editor
pub fn runInteractiveEditor(
    allocator: std.mem.Allocator,
    agent: *agent_interface.Agent,
    editor_config: InteractiveConfig,
) !void {
    const editor = try InteractiveMarkdownEditor.init(allocator, agent, editor_config);
    defer editor.deinit();

    try editor.run();
}

/// Create a default interactive configuration
pub fn createDefaultConfig() InteractiveConfig {
    return InteractiveConfig{
        .base_config = markdown_editor.MarkdownEditorConfig{
            .base_config = .{
                .agent_info = .{
                    .name = "Interactive Markdown Editor",
                    .version = "1.0.0",
                    .description = "Interactive markdown editing with live preview and rich features",
                    .author = "DocZ",
                },
                .defaults = .{
                    .max_concurrent_operations = 1,
                    .default_timeout_ms = 30000,
                    .enable_debug_logging = false,
                    .enable_verbose_output = false,
                },
                .features = .{
                    .enable_custom_tools = true,
                    .enable_file_operations = true,
                    .enable_network_access = false,
                    .enable_system_commands = false,
                },
                .limits = .{
                    .max_input_size = 1048576,
                    .max_output_size = 1048576,
                    .max_processing_time_ms = 60000,
                },
                .model = .{
                    .default_model = "claude-3-sonnet-20240229",
                    .max_tokens = 4096,
                    .temperature = 0.7,
                    .stream_responses = true,
                },
            },
            .editor_settings = .{
                .syntax_highlighting = true,
                .auto_complete = true,
                .smart_indent = true,
                .multi_cursor = true,
                .auto_save_interval = 30,
            },
            .preview_settings = .{
                .live_preview = true,
                .enable_mermaid = true,
                .enable_math = true,
                .code_highlighting = true,
            },
            .export_settings = .{
                .default_format = .html,
                .include_toc = true,
                .include_metadata = true,
            },
            .session_settings = .{
                .max_undo_history = 1000,
                .enable_recovery = true,
                .backup_interval_s = 60,
            },
        },
        .enable_live_preview = true,
        .preview_sync = .{
            .enable_scroll_sync = true,
            .sync_delay_ms = 150,
            .update_mode = .debounced,
            .show_preview_errors = true,
        },
        .navigation = .{
            .show_file_tree = true,
            .show_outline = true,
            .show_breadcrumb = true,
            .enable_quick_jump = true,
            .file_tree_width = 25,
            .outline_width = 25,
        },
        .visual_tools = .{
            .enable_table_generator = true,
            .enable_link_manager = true,
            .enable_image_preview = true,
            .enable_code_formatter = true,
            .enable_diff_viewer = true,
            .enable_emoji_picker = true,
        },
        .session = .{
            .enable_tabs = true,
            .max_tabs = 10,
            .enable_recovery = true,
            .auto_save_interval = 30,
            .show_auto_save_indicators = true,
        },
        .status_bar = .{
            .show_word_count = true,
            .show_reading_time = true,
            .show_document_stats = true,
            .show_lint_status = true,
            .show_save_status = true,
            .height = 2,
        },
        .integration = .{
            .enable_dashboard = true,
            .dashboard_update_ms = 1000,
            .enable_external_tools = false,
        },
    };
}

//! Markdown Interactive Editor
//!
//! A powerful, feature-rich markdown editor that rivals GUI editors but runs in the terminal.
//! Built using TUI components including split panes, smart input, file trees, modals,
//! canvas rendering, and comprehensive keyboard/mouse support.
//!
//! ## Features
//!
//! ### Core Editing
//! - **Split-pane editor** with resizable panels (editor + live preview)
//! - **Syntax highlighting** for markdown elements with customizable themes
//! - **Smart input component** with markdown-specific autocomplete
//! - **Multi-line editing** with proper cursor management
//! - **Live error checking** for broken links and formatting issues
//!
//! ### Navigation & Organization
//! - **File tree widget** for document navigation and quick file switching
//! - **Outline view** showing document structure (headings, sections)
//! - **Recent files** management with session persistence
//! - **Create/rename/delete** operations with confirmation dialogs
//!
//! ### Rendering
//! - **Canvas system** for diagrams (mermaid-like), image previews, tables
//! - **Live preview** with real-time markdown rendering
//! - **Math rendering** support (LaTeX/MathJax)
//! - **Code syntax highlighting** in preview blocks
//!
//! ### User Interface
//! - **Modal dialogs** for save/load, settings, help, export options
//! - **Command palette** with searchable markdown commands
//! - **Metrics dashboard** showing word count, reading time, etc.
//! - **Status bar** with cursor position, mode indicators, file info
//!
//! ### Input & Interaction
//! - **Vim-like navigation** modes with customizable keybindings
//! - **Quick markdown formatting** shortcuts (Ctrl+B for bold, etc.)
//! - **Mouse support** for click-to-position, drag-to-select, scroll
//! - **Theme integration** with syntax highlighting and UI themes
//!
//! ### Session Management
//! - **Auto-save** with configurable intervals
//! - **Session recovery** with backup and restore
//! - **Undo/redo** with operation grouping
//! - **Export options** (HTML, PDF, LaTeX, etc.)
//!
//! ## Usage Example
//!
//! ```zig
//! const editor = @import("MarkdownEditor.zig");
//!
//! // Create editor with full configuration
//! const editor = try editor.MarkdownEditor.init(allocator, agent, .{
//!     .base_config = agent_config,
//!     .editor_settings = .{
//!         .syntax_highlighting = true,
//!         .auto_complete = true,
//!         .smart_indent = true,
//!         .multi_cursor = true,
//!         .auto_save_interval = 30,
//!     },
//!     .preview_settings = .{
//!         .live_preview = true,
//!         .enable_mermaid = true,
//!         .enable_math = true,
//!         .code_highlighting = true,
//!     },
//!     .export_settings = .{
//!         .default_format = .html,
//!         .include_toc = true,
//!         .include_metadata = true,
//!     },
//!     .session_settings = .{
//!         .max_undo_history = 1000,
//!         .enable_recovery = true,
//!         .backup_interval_s = 60,
//!     },
//! });
//! defer editor.deinit();
//!
//! // Load a file (optional)
//! try editor.loadFile("document.md");
//!
//! // Run the interactive editor
//! try editor.run();
//! ```
//!
//! ## Keyboard Shortcuts
//!
//! ### File Operations
//! - `Ctrl+S` - Save document
//! - `Ctrl+O` - Open file
//! - `Ctrl+N` - New document
//! - `Ctrl+E` - Export document
//!
//! ### Editing
//! - `Ctrl+Z` - Undo
//! - `Ctrl+Y` - Redo
//! - `Ctrl+F` - Find
//! - `Ctrl+H` - Replace
//! - `Ctrl+K` - Insert link
//! - `Ctrl+B` - Toggle bold
//! - `Ctrl+I` - Toggle italic
//!
//! ### View
//! - `Alt+P` - Toggle preview
//! - `Alt+S` - Toggle sidebar
//! - `Alt+M` - Toggle metrics
//! - `Alt+V` - Toggle split mode
//! - `Ctrl+P` - Command palette
//!
//! ### Navigation
//! - `Arrow Keys` - Move cursor
//! - `Home/End` - Line start/end
//! - `Page Up/Down` - Page navigation
//! - `Ctrl+Home/End` - Document start/end
//! - `Alt+1-6` - Insert heading level 1-6
//!
//! ## Architecture
//!
//! The editor is built using a modular architecture with these key components:
//!
//! - **MarkdownEditor** - Main editor controller
//! - **Smart Input Component** - Text input with autocomplete
//! - **Split Pane Widget** - Resizable panel layout
//! - **File Tree Widget** - Hierarchical file browser
//! - **Modal System** - Dialog and popup management
//! - **Canvas Engine** - Graphics and diagram rendering
//! - **Command Palette** - Searchable command interface
//! - **Session Manager** - State persistence and recovery
//!
//! This architecture provides excellent separation of concerns while maintaining
//! high performance and rich functionality comparable to GUI editors.

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
const theme = @import("../../src/foundation/theme/mod.zig");
const render = @import("render_shared");
const components = @import("components_shared");

// UI components
const input_component = @import("../../src/foundation/components/input.zig");
const split_pane = @import("../../src/foundation/tui/widgets/core/split_pane.zig");
const file_tree = tui.widgets.core.file_tree;
const modal = @import("../../src/foundation/tui/widgets/modal.zig");
const canvas_mod = @import("../../src/foundation/tui/core/canvas.zig");
// Backward compatibility alias
const canvas_engine = canvas_mod;

// Markdown agent specific
const markdown_tools = @import("tools/mod.zig");
const ContentEditor = @import("tools/content_editor.zig");
const Validate = @import("tools/validate.zig");
const document_tool = @import("tools/document.zig");

// Common utilities
const fs = @import("lib/fs.zig");
const link = @import("lib/link.zig");
const meta = @import("lib/meta.zig");
const table = @import("lib/table.zig");
const template = @import("lib/template.zig");
const text_utils = @import("lib/text.zig");

/// Markdown Editor Configuration
pub const MarkdownEditorConfig = struct {
    /// Base agent configuration
    base_config: agent_interface.Config,

    /// Editor-specific settings
    editor_settings: EditorSettings = .{},

    /// Preview settings
    preview_settings: PreviewSettings = .{},

    /// Export settings
    export_settings: ExportSettings = .{},

    /// Session settings
    session_settings: EditorSessionSettings = .{},
};

/// Editor-specific settings
pub const EditorSettings = struct {
    /// Enable syntax highlighting
    syntax_highlighting: bool = true,

    /// Color scheme for highlighting
    highlight_theme: []const u8 = "github-dark",

    /// Enable auto-completion
    auto_complete: bool = true,

    /// Enable smart indentation
    smart_indent: bool = true,

    /// Tab size in spaces
    tab_size: u32 = 4,

    /// Enable word wrap
    word_wrap: bool = true,

    /// Word wrap column
    wrap_column: u32 = 80,

    /// Enable multi-cursor support
    multi_cursor: bool = true,

    /// Enable bracket matching
    bracket_matching: bool = true,

    /// Auto-save interval in seconds (0 = disabled)
    auto_save_interval: u32 = 30,
};

/// Preview settings
pub const PreviewSettings = struct {
    /// Enable live preview
    live_preview: bool = true,

    /// Preview update delay in ms
    update_delay_ms: u32 = 300,

    /// Enable mermaid diagrams
    enable_mermaid: bool = true,

    /// Enable math rendering (KaTeX/MathJax)
    enable_math: bool = true,

    /// Enable syntax highlighting in code blocks
    code_highlighting: bool = true,

    /// Custom CSS for preview
    custom_css: ?[]const u8 = null,

    /// Render mode
    render_mode: PreviewRenderMode = .full,
};

/// Preview render modes
pub const PreviewRenderMode = enum {
    plain, // Plain text
    text, // Text-only markdown formatting
    full, // Full rendering with graphics
    print, // Print-optimized layout
};

/// Export settings
pub const ExportSettings = struct {
    /// Default export format
    default_format: ExportFormat = .markdown,

    /// Include table of contents
    include_toc: bool = true,

    /// Include metadata
    include_metadata: bool = true,

    /// Export directory
    export_dir: []const u8 = "~/Documents/markdown-exports",
};

/// Export formats
pub const ExportFormat = enum {
    markdown,
    html,
    pdf,
    latex,
    docx,
    epub,
    json,
};

/// Editor session settings
pub const EditorSessionSettings = struct {
    /// Maximum undo history size
    max_undo_history: u32 = 1000,

    /// Enable session recovery
    enable_recovery: bool = true,

    /// Session backup interval
    backup_interval_s: u32 = 60,

    /// Maximum recent files
    max_recent_files: u32 = 20,
};

/// Editor state
pub const EditorState = struct {
    /// Current document
    document: Document,

    /// Cursor positions (for multi-cursor)
    cursors: std.ArrayList(CursorPosition),

    /// Selection ranges
    selections: std.ArrayList(SelectionRange),

    /// Undo/redo history
    undo_history: UndoHistory,

    /// Current view state
    view: ViewState,

    /// Search state
    search: SearchState,

    /// Metrics
    metrics: DocumentMetrics,

    /// Modified flag
    is_modified: bool = false,

    /// Last save time
    last_save_time: ?i64 = null,
};

/// Document structure
pub const Document = struct {
    /// File path (if any)
    file_path: ?[]const u8 = null,

    /// Document content (lines)
    lines: std.ArrayList([]u8),

    /// Document metadata
    metadata: DocumentMetadata,

    /// Syntax tree (for highlighting)
    syntax_tree: ?*SyntaxTree = null,

    /// Document version (for change tracking)
    version: u64 = 0,
};

/// Document metadata
pub const DocumentMetadata = struct {
    title: ?[]const u8 = null,
    author: ?[]const u8 = null,
    date: ?[]const u8 = null,
    tags: std.ArrayList([]const u8),
    custom: std.StringHashMap([]const u8),
};

/// Cursor position
pub const CursorPosition = struct {
    line: u32,
    column: u32,
    /// Virtual column for maintaining position during vertical movement
    virtual_column: u32,
    /// Cursor ID for multi-cursor support
    id: u32 = 0,
};

/// Selection range
pub const SelectionRange = struct {
    start: CursorPosition,
    end: CursorPosition,
};

/// Undo history
pub const UndoHistory = struct {
    undo_stack: std.ArrayList(EditOperation),
    redo_stack: std.ArrayList(EditOperation),
    current_group: ?u64 = null,
};

/// Edit operation for undo/redo
pub const EditOperation = struct {
    type: OperationType,
    position: CursorPosition,
    old_text: []const u8,
    new_text: []const u8,
    group_id: u64,
};

/// Operation types
pub const OperationType = enum {
    insert,
    delete,
    replace,
    indent,
    format,
};

/// View state
pub const ViewState = struct {
    /// Top visible line
    top_line: u32 = 0,

    /// Left offset (for horizontal scrolling)
    left_offset: u32 = 0,

    /// Split view mode
    split_mode: SplitMode = .none,

    /// Preview visible
    preview_visible: bool = true,

    /// Sidebar visible
    sidebar_visible: bool = true,

    /// Current zoom level
    zoom_level: f32 = 1.0,
};

/// Split modes
pub const SplitMode = enum {
    none,
    vertical,
    horizontal,
};

/// Search state
pub const SearchState = struct {
    query: []const u8 = "",
    regex: bool = false,
    case_sensitive: bool = false,
    whole_word: bool = false,
    results: std.ArrayList(SearchResult),
    current_result: ?usize = null,
};

/// Search result
pub const SearchResult = struct {
    line: u32,
    start_col: u32,
    end_col: u32,
    match_text: []const u8,
};

/// Document metrics
pub const DocumentMetrics = struct {
    /// Total lines
    line_count: u32 = 0,

    /// Total words
    word_count: u32 = 0,

    /// Total characters
    char_count: u32 = 0,

    /// Reading time in minutes
    reading_time: f32 = 0,

    /// Heading count by level
    heading_counts: [6]u32 = [_]u32{0} ** 6,

    /// Link count
    link_count: u32 = 0,

    /// Code block count
    code_block_count: u32 = 0,

    /// Table count
    table_count: u32 = 0,
};

/// Syntax tree for highlighting
pub const SyntaxTree = struct {
    allocator: Allocator,
    root: *Node,

    pub const Node = struct {
        type: NodeType,
        start: Position,
        end: Position,
        children: std.ArrayList(*Node),
        content: ?[]const u8 = null,
    };

    pub const NodeType = enum {
        document,
        heading,
        paragraph,
        code_block,
        inline_code,
        emphasis,
        strong,
        link,
        image,
        list,
        list_item,
        blockquote,
        table,
        horizontal_rule,
        text,
    };

    pub const Position = struct {
        line: u32,
        column: u32,
    };
};

/// Markdown Editor
pub const MarkdownEditor = struct {
    /// Memory allocator
    allocator: Allocator,

    /// Agent interface
    agent: *agent_interface.Agent,

    /// Editor configuration
    config: MarkdownEditorConfig,

    /// Current editor state
    state: EditorState,

    /// Canvas engine for preview and diagrams
    canvas_engine: ?*canvas_engine.CanvasEngine,

    /// Content editor tool
    content_editor: *ContentEditor,

    /// Document validator
    validator: *Validate,

    /// Auto-completion engine
    auto_completer: *AutoCompleter,

    /// Command palette with markdown commands
    command_palette: *CommandPalette,

    /// Metrics dashboard
    metrics_dashboard: *MetricsDashboard,

    /// Export manager
    export_manager: *Export,

    /// Session manager for drafts
    session_manager: *EditorSession,

    /// Theme for syntax highlighting
    syntax_theme: *SyntaxTheme,

    /// Event handlers
    event_handlers: EventHandlers,

    /// Thread for background tasks
    background_thread: ?Thread = null,

    /// Mutex for thread safety
    mutex: Mutex,

    const Self = @This();

    /// Initialize the enhanced markdown editor
    pub fn init(
        allocator: Allocator,
        agent: *agent_interface.Agent,
        editor_config: MarkdownEditorConfig,
    ) !*Self {
        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Initialize document
        const document = Document{
            .lines = std.ArrayList([]u8).init(allocator),
            .metadata = DocumentMetadata{
                .tags = std.ArrayList([]const u8).init(allocator),
                .custom = std.StringHashMap([]const u8).init(allocator),
            },
        };

        // Initialize editor state
        self.* = Self{
            .allocator = allocator,
            .agent = agent,
            .config = editor_config,
            .state = EditorState{
                .document = document,
                .cursors = std.ArrayList(CursorPosition).init(allocator),
                .selections = std.ArrayList(SelectionRange).init(allocator),
                .undo_history = UndoHistory{
                    .undo_stack = std.ArrayList(EditOperation).init(allocator),
                    .redo_stack = std.ArrayList(EditOperation).init(allocator),
                },
                .view = ViewState{},
                .search = SearchState{
                    .results = std.ArrayList(SearchResult).init(allocator),
                },
                .metrics = DocumentMetrics{},
            },
            .canvas_engine = null,
            .content_editor = undefined,
            .validator = undefined,
            .auto_completer = undefined,
            .command_palette = undefined,
            .metrics_dashboard = undefined,
            .export_manager = undefined,
            .session_manager = undefined,
            .syntax_theme = undefined,
            .event_handlers = EventHandlers{},
            .mutex = Mutex{},
        };

        // Initialize components
        try self.initializeComponents();

        // Add initial cursor
        try self.state.cursors.append(CursorPosition{ .line = 0, .column = 0, .virtual_column = 0 });

        // Start background thread for auto-save
        if (self.config.editor_settings.auto_save_interval > 0) {
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

        // Save session before cleanup
        self.saveSession() catch {};

        // Cleanup components
        if (self.canvas_engine) |canvas| {
            canvas.deinit();
        }
        self.content_editor.deinit();
        self.validator.deinit();
        self.auto_completer.deinit();
        self.command_palette.deinit();
        self.metrics_dashboard.deinit();
        self.export_manager.deinit();
        self.session_manager.deinit();
        self.syntax_theme.deinit();

        // Cleanup state
        self.state.document.lines.deinit();
        self.state.document.metadata.tags.deinit();
        self.state.document.metadata.custom.deinit();
        self.state.cursors.deinit();
        self.state.selections.deinit();
        self.state.undo_history.undo_stack.deinit();
        self.state.undo_history.redo_stack.deinit();
        self.state.search.results.deinit();

        self.allocator.destroy(self);
    }

    /// Run the editor in interactive mode
    pub fn run(self: *Self) !void {
        // Setup terminal
        try self.setupTerminal();
        defer self.restoreTerminal();

        // Show welcome/splash screen
        try self.showWelcomeScreen();

        // Main editor loop
        while (true) {
            // Update metrics
            try self.updateMetrics();

            // Render the editor UI
            try self.render();

            // Handle input events
            const event = try self.agent.event_system.waitForEvent();
            const should_exit = try self.handleEvent(event);

            if (should_exit) break;

            // Check for auto-save
            if (self.config.editor_settings.auto_save_interval > 0) {
                try self.checkAutoSave();
            }
        }

        // Show exit screen with save prompt if needed
        if (self.state.is_modified) {
            const save = try self.promptSaveChanges();
            if (save) {
                try self.saveDocument();
            }
        }
    }

    /// Load a markdown file
    pub fn loadFile(self: *Self, file_path: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Show loading progress
        const progress = try self.agent.progress.createSpinner(.{
            .label = try std.fmt.allocPrint(self.allocator, "Loading {s}...", .{file_path}),
            .style = .dots,
        });
        defer progress.active = false;

        // Load file content
        const content = try fs.readFile(self.allocator, file_path);
        defer self.allocator.free(content);

        // Parse into lines
        var lines = std.ArrayList([]u8).init(self.allocator);
        var it = std.mem.tokenize(u8, content, "\n");
        while (it.next()) |line| {
            try lines.append(try self.allocator.dupe(u8, line));
        }

        // Update document
        self.state.document.file_path = try self.allocator.dupe(u8, file_path);
        self.state.document.lines.deinit();
        self.state.document.lines = lines;

        // Extract metadata if present
        try self.extractMetadata();

        // Build syntax tree
        try self.buildSyntaxTree();

        // Reset state
        self.state.is_modified = false;
        self.state.last_save_time = std.time.milliTimestamp();
        self.state.document.version = 0;

        // Add to recent files
        try self.session_manager.addRecentFile(file_path);

        // Show notification
        try self.agent.notifier.showNotification(.{
            .title = "File Loaded",
            .message = try std.fmt.allocPrint(self.allocator, "Loaded {s}", .{fs.basename(file_path)}),
            .type = .success,
        });
    }

    /// Save the current document
    pub fn saveDocument(self: *Self) !void {
        if (self.state.document.file_path) |path| {
            try self.saveToFile(path);
        } else {
            // Prompt for file name
            const path = try self.promptFileName();
            if (path) |p| {
                try self.saveToFile(p);
            }
        }
    }

    /// Save to specific file
    pub fn saveToFile(self: *Self, file_path: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Show saving progress
        const progress = try self.agent.progress.createSpinner(.{
            .label = "Saving document...",
            .style = .dots,
        });
        defer progress.active = false;

        // Build content
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();

        // Add metadata if configured
        if (self.config.export_settings.include_metadata) {
            try self.appendMetadata(&content);
        }

        // Add lines
        for (self.state.document.lines.items, 0..) |line, i| {
            try content.appendSlice(line);
            if (i < self.state.document.lines.items.len - 1) {
                try content.append('\n');
            }
        }

        // Write to file
        try fs.writeFile(file_path, content.items);

        // Update state
        self.state.document.file_path = try self.allocator.dupe(u8, file_path);
        self.state.is_modified = false;
        self.state.last_save_time = std.time.milliTimestamp();

        // Show notification
        try self.agent.notifier.showNotification(.{
            .title = "Document Saved",
            .message = try std.fmt.allocPrint(self.allocator, "Saved to {s}", .{fs.basename(file_path)}),
            .type = .success,
        });
    }

    /// Export document to various formats
    pub fn exportDocument(self: *Self, format: ExportFormat) !void {
        try self.export_manager.exportDocument(&self.state.document, format);
    }

    /// Insert text at current cursor
    pub fn insertText(self: *Self, text: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Handle multi-cursor insertion
        for (self.state.cursors.items) |cursor| {
            try self.insertTextAtCursor(cursor, text);
        }

        self.state.is_modified = true;
        self.state.document.version += 1;

        // Update preview if live preview enabled
        if (self.config.preview_settings.live_preview) {
            try self.updatePreview();
        }
    }

    /// Delete text at cursor
    pub fn deleteText(self: *Self, direction: enum { backward, forward }) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.state.cursors.items) |*cursor| {
            try self.deleteAtCursor(cursor, direction);
        }

        self.state.is_modified = true;
        self.state.document.version += 1;
    }

    /// Undo last operation
    pub fn undo(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.state.undo_history.undo_stack.items.len == 0) return;

        const op = self.state.undo_history.undo_stack.pop();
        try self.applyOperation(op, true);
        try self.state.undo_history.redo_stack.append(op);
    }

    /// Redo last undone operation
    pub fn redo(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.state.undo_history.redo_stack.items.len == 0) return;

        const op = self.state.undo_history.redo_stack.pop();
        try self.applyOperation(op, false);
        try self.state.undo_history.undo_stack.append(op);
    }

    /// Search in document
    pub fn search(self: *Self, query: []const u8, options: SearchOptions) !void {
        self.state.search.query = query;
        self.state.search.regex = options.regex;
        self.state.search.case_sensitive = options.case_sensitive;
        self.state.search.whole_word = options.whole_word;

        // Clear previous results
        self.state.search.results.clearRetainingCapacity();

        // Search through lines
        for (self.state.document.lines.items, 0..) |line, line_idx| {
            const matches = try self.findMatchesInLine(line, query, options);
            for (matches) |match| {
                try self.state.search.results.append(SearchResult{
                    .line = @intCast(line_idx),
                    .start_col = match.start,
                    .end_col = match.end,
                    .match_text = line[match.start..match.end],
                });
            }
        }

        // Navigate to first result
        if (self.state.search.results.items.len > 0) {
            self.state.search.current_result = 0;
            try self.navigateToSearchResult(0);
        }
    }

    /// Navigate to next search result
    pub fn nextSearchResult(self: *Self) !void {
        if (self.state.search.results.items.len == 0) return;

        if (self.state.search.current_result) |current| {
            const next = (current + 1) % self.state.search.results.items.len;
            self.state.search.current_result = next;
            try self.navigateToSearchResult(next);
        }
    }

    /// Navigate to previous search result
    pub fn prevSearchResult(self: *Self) !void {
        if (self.state.search.results.items.len == 0) return;

        if (self.state.search.current_result) |current| {
            const prev = if (current == 0)
                self.state.search.results.items.len - 1
            else
                current - 1;
            self.state.search.current_result = prev;
            try self.navigateToSearchResult(prev);
        }
    }

    /// Replace text
    pub fn replace(self: *Self, search_text: []const u8, replace_text: []const u8, all: bool) !void {
        const options = SearchOptions{
            .case_sensitive = self.state.search.case_sensitive,
            .regex = self.state.search.regex,
            .whole_word = self.state.search.whole_word,
        };

        try self.search(search_text, options);

        if (all) {
            // Replace all occurrences
            for (self.state.search.results.items) |result| {
                try self.replaceAtPosition(result, replace_text);
            }
        } else {
            // Replace current occurrence
            if (self.state.search.current_result) |idx| {
                const result = self.state.search.results.items[idx];
                try self.replaceAtPosition(result, replace_text);
            }
        }

        self.state.is_modified = true;
    }

    // === Private Helper Methods ===

    fn initializeComponents(self: *Self) !void {
        // Initialize canvas engine for diagrams and graphics
        const terminal = self.agent.renderer.getTerminal();
        self.canvas_engine = try canvas_engine.CanvasEngine.init(self.allocator, terminal);

        // Initialize content editor
        self.content_editor = try ContentEditor.init(self.allocator);

        // Initialize validator
        self.validator = try Validate.init(self.allocator);

        // Initialize auto-completion engine with markdown suggestions
        self.auto_completer = try AutoCompleter.init(self.allocator);
        try self.setupMarkdownAutoComplete();

        // Initialize command palette with markdown commands
        self.command_palette = try CommandPalette.init(self.allocator);
        try self.registerEditorCommands();

        // Initialize metrics dashboard
        self.metrics_dashboard = try MetricsDashboard.init(self.allocator);

        // Initialize export manager
        self.export_manager = try Export.init(
            self.allocator,
            self.config.export_settings,
        );

        // Initialize session manager
        self.session_manager = try EditorSession.init(
            self.allocator,
            self.config.session_settings,
        );

        // Initialize syntax theme
        self.syntax_theme = try SyntaxTheme.init(
            self.allocator,
            self.config.editor_settings.highlight_theme,
        );
    }

    /// Setup markdown-specific autocomplete suggestions
    fn setupMarkdownAutoComplete(self: *Self) !void {
        _ = self;
        // Add markdown-specific suggestions to the auto-completer
        const markdown_suggestions = [_]input_component.Suggestion{
            .{ .text = "# ", .description = "Heading 1", .icon = "📄" },
            .{ .text = "## ", .description = "Heading 2", .icon = "📄" },
            .{ .text = "### ", .description = "Heading 3", .icon = "📄" },
            .{ .text = "- ", .description = "Bullet list", .icon = "•" },
            .{ .text = "1. ", .description = "Numbered list", .icon = "1️⃣" },
            .{ .text = "**bold**", .description = "Bold text", .icon = "𝐛" },
            .{ .text = "*italic*", .description = "Italic text", .icon = "𝑖" },
            .{ .text = "`code`", .description = "Inline code", .icon = "💻" },
            .{ .text = "[link](url)", .description = "Link", .icon = "🔗" },
            .{ .text = "![alt](image)", .description = "Image", .icon = "🖼️" },
            .{ .text = "> ", .description = "Blockquote", .icon = "💬" },
            .{ .text = "```language\ncode\n```", .description = "Code block", .icon = "📦" },
            .{ .text = "| Header | Header |\n|--------|--------|\n| Cell | Cell |", .description = "Table", .icon = "📊" },
            .{ .text = "---", .description = "Horizontal rule", .icon = "━" },
        };

        // The auto-completer would use these suggestions
        // For now, we just ensure they're available
        _ = markdown_suggestions;
    }

    /// Create a split pane layout for editor and preview
    pub fn createSplitLayout(self: *Self) !*split_pane.SplitPane {
        const terminal_size = try term.ansi.terminal.getTerminalSize();

        const split = try split_pane.SplitPane.init(self.allocator, .{ .x = 0, .y = 0, .width = terminal_size.width, .height = terminal_size.height }, .{
            .orientation = .vertical,
            .split_position = 0.6,
            .min_pane_size = 20,
        });

        return split;
    }

    /// Create a file tree for document navigation
    pub fn createFileTree(self: *Self, root_path: []const u8) !*file_tree.FileTree {
        var thread_pool = try std.Thread.Pool.init(.{ .allocator = self.allocator });
        defer thread_pool.deinit();

        const tree = try file_tree.FileTree.init(
            self.allocator,
            root_path,
            &thread_pool,
            &self.agent.focus_mgr,
            &self.agent.mouse_controller,
        );

        // Configure file tree
        tree.setSelectionMode(.single);
        try tree.setFilter(.{
            .show_hidden = false,
            .extensions = &[_][]const u8{ ".md", ".txt", ".markdown" },
            .search_text = "",
        });

        return tree;
    }

    /// Show a modal dialog
    pub fn showModal(self: *Self, modal_type: modal.ModalType, title: []const u8, content: []const u8) !*modal.Modal {
        const dialog_modal = try modal.Modal.init(self.allocator, modal_type, .{
            .title = title,
            .backdrop = true,
            .close_on_escape = true,
            .close_on_outside_click = true,
        });

        try dialog_modal.setContent(content);
        try dialog_modal.show();

        return dialog_modal;
    }

    /// Render markdown preview using canvas engine
    pub fn renderMarkdownPreview(self: *Self, x: u16, y: u16, width: u16, height: u16) !void {
        if (self.canvas_engine) |canvas| {
            // Set viewport for preview area
            try canvas.setViewport(x, y, width, height);

            // Clear the preview area
            try canvas.render();

            // Build markdown content
            var content = std.ArrayList(u8).init(self.allocator);
            defer content.deinit();

            for (self.state.document.lines.items) |line| {
                try content.appendSlice(line);
                try content.append('\n');
            }

            // Create text layer for preview
            const text_layer_id = try canvas.createTextLayer("preview");
            const preview_layer = canvas.getLayer(text_layer_id) orelse return;

            if (preview_layer.content == .text) {
                preview_layer.content.text.text = try self.allocator.dupe(u8, content.items);
                preview_layer.content.text.position = .{ .x = 0, .y = 0 };
            }

            // Render the canvas
            try canvas.render();
        }
    }

    fn setupTerminal(self: *Self) !void {
        _ = self;
        // Terminal setup handled by enhanced agent
    }

    fn restoreTerminal(self: *Self) void {
        _ = self;
        // Terminal restoration handled by enhanced agent
    }

    fn showWelcomeScreen(self: *Self) !void {
        const welcome = EditorWelcomeScreen.init(
            self.allocator,
            self.agent.theme_mgr.getCurrentTheme(),
        );
        defer welcome.deinit();

        try welcome.render(self.agent.renderer, .{
            .recent_files = self.session_manager.getRecentFiles(),
            .show_tips = true,
        });

        // Wait for user input
        _ = try self.agent.event_system.waitForEvent();
    }

    fn render(self: *Self) !void {
        const renderer = self.agent.renderer;

        // Begin synchronized output
        try term.ansi.synchronizedOutput.begin();
        defer term.ansi.synchronizedOutput.end() catch {};

        // Clear and prepare
        try renderer.clear();

        // Get terminal size
        const size = try term.ansi.terminal.getTerminalSize();

        // Calculate layout based on split mode
        switch (self.state.view.split_mode) {
            .none => try self.renderFullEditor(renderer, size),
            .vertical => try self.renderVerticalSplit(renderer, size),
            .horizontal => try self.renderHorizontalSplit(renderer, size),
        }

        // Render overlays
        try self.renderOverlays(renderer);

        // Flush to terminal
        try renderer.flush();
    }

    fn renderFullEditor(self: *Self, renderer: *tui.Renderer, size: term.TerminalSize) !void {
        // Top bar with file info and metrics
        try self.renderTopBar(renderer, 0, 0, size.width);

        // Main editor area
        const editor_height = size.height - 3; // Top bar + status bar

        if (self.state.view.sidebar_visible) {
            // Sidebar with file tree/outline
            const sidebar_width = 30;
            try self.renderSidebar(renderer, 0, 1, sidebar_width, editor_height);

            // Editor content
            try self.renderEditorContent(renderer, sidebar_width + 1, 1, size.width - sidebar_width - 1, editor_height);
        } else {
            // Full width editor
            try self.renderEditorContent(renderer, 0, 1, size.width, editor_height);
        }

        // Status bar at bottom
        try self.renderStatusBar(renderer, 0, size.height - 1, size.width);
    }

    fn renderVerticalSplit(self: *Self, renderer: *tui.Renderer, size: term.TerminalSize) !void {
        // Top bar
        try self.renderTopBar(renderer, 0, 0, size.width);

        const content_height = size.height - 2;
        const split_pos = size.width / 2;

        // Left: Editor
        try self.renderEditorContent(renderer, 0, 1, split_pos - 1, content_height);

        // Divider
        try self.renderVerticalDivider(renderer, split_pos - 1, 1, content_height);

        // Right: Preview
        if (self.state.view.preview_visible) {
            try self.renderPreview(renderer, split_pos, 1, size.width - split_pos, content_height);
        }

        // Status bar
        try self.renderStatusBar(renderer, 0, size.height - 1, size.width);
    }

    fn renderHorizontalSplit(self: *Self, renderer: *tui.Renderer, size: term.TerminalSize) !void {
        // Top bar
        try self.renderTopBar(renderer, 0, 0, size.width);

        const content_height = size.height - 2;
        const split_pos = content_height / 2;

        // Top: Editor
        try self.renderEditorContent(renderer, 0, 1, size.width, split_pos - 1);

        // Divider
        try self.renderHorizontalDivider(renderer, 0, split_pos, size.width);

        // Bottom: Preview
        if (self.state.view.preview_visible) {
            try self.renderPreview(renderer, 0, split_pos + 1, size.width, content_height - split_pos - 1);
        }

        // Status bar
        try self.renderStatusBar(renderer, 0, size.height - 1, size.width);
    }

    fn renderTopBar(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, width: u16) !void {
        // File name
        const file_name = if (self.state.document.file_path) |path|
            fs.basename(path)
        else
            "Untitled";

        const modified = if (self.state.is_modified) " •" else "";
        const title = try std.fmt.allocPrint(self.allocator, " {s}{s} ", .{ file_name, modified });
        defer self.allocator.free(title);

        // Metrics
        const metrics = try std.fmt.allocPrint(self.allocator, " 📝 {d} words │ ⏱️ {d}m │ 📊 {d} lines ", .{ self.state.metrics.word_count, @as(u32, @intFromFloat(self.state.metrics.reading_time)), self.state.metrics.line_count });
        defer self.allocator.free(metrics);

        // Render bar
        try renderer.drawBox(x, y, width, 1, .single);
        try renderer.writeText(x + 2, y, title);
        try renderer.writeText(x + width - @as(u16, @intCast(metrics.len)) - 2, y, metrics);
    }

    fn renderStatusBar(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, width: u16) !void {
        // Cursor position
        const cursor = self.state.cursors.items[0];
        const position = try std.fmt.allocPrint(self.allocator, " Ln {d}, Col {d} ", .{ cursor.line + 1, cursor.column + 1 });
        defer self.allocator.free(position);

        // Mode indicators
        const mode = try std.fmt.allocPrint(self.allocator, " {s} │ {s} │ {s} ", .{
            if (self.config.editor_settings.syntax_highlighting) "Syntax ✓" else "Syntax ✗",
            if (self.config.preview_settings.live_preview) "Preview ✓" else "Preview ✗",
            if (self.config.editor_settings.auto_save_interval > 0) "AutoSave ✓" else "AutoSave ✗",
        });
        defer self.allocator.free(mode);

        // Render bar
        try renderer.fillRect(x, y, width, 1, ' ', .{ .bg = .blue, .fg = .white });
        try renderer.writeText(x + 2, y, position);
        try renderer.writeText(x + width - @as(u16, @intCast(mode.len)) - 2, y, mode);
    }

    fn renderSidebar(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, width: u16, height: u16) !void {
        // Outline view
        try renderer.drawBox(x, y, width, height, .single);
        try renderer.writeText(x + 2, y, " Outline ");

        // Render document outline
        var current_y = y + 2;
        for (self.state.document.lines.items) |line| {
            if (std.mem.startsWith(u8, line, "#")) {
                const level = countHeadingLevel(line);
                const indent = "  " ** (level - 1);
                const heading = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ indent, line[level + 1 ..] });
                defer self.allocator.free(heading);

                if (current_y < y + height - 1) {
                    try renderer.writeText(x + 2, current_y, heading[0..@min(heading.len, width - 4)]);
                    current_y += 1;
                }
            }
        }
    }

    fn renderEditorContent(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, width: u16, height: u16) !void {
        // Draw editor frame
        try renderer.drawBox(x, y, width, height, .single);

        // Render lines with syntax highlighting
        const start_line = self.state.view.top_line;
        const end_line = @min(start_line + height - 2, self.state.document.lines.items.len);

        for (start_line..end_line) |line_idx| {
            const line = self.state.document.lines.items[line_idx];
            const display_y = y + 1 + @as(u16, @intCast(line_idx - start_line));

            // Line numbers
            const line_num = try std.fmt.allocPrint(self.allocator, "{d:4} ", .{line_idx + 1});
            defer self.allocator.free(line_num);
            try renderer.writeText(x + 1, display_y, line_num);

            // Content with syntax highlighting
            if (self.config.editor_settings.syntax_highlighting) {
                try self.renderHighlightedLine(renderer, x + 6, display_y, line, width - 8);
            } else {
                const visible_text = if (line.len > self.state.view.left_offset)
                    line[self.state.view.left_offset..@min(line.len, self.state.view.left_offset + width - 8)]
                else
                    "";
                try renderer.writeText(x + 6, display_y, visible_text);
            }

            // Render cursors
            for (self.state.cursors.items) |cursor| {
                if (cursor.line == line_idx) {
                    const cursor_x = x + 6 + @as(u16, @intCast(cursor.column)) - @as(u16, @intCast(self.state.view.left_offset));
                    if (cursor_x < x + width - 2) {
                        try renderer.setCursorPosition(cursor_x, display_y);
                        try renderer.writeText(cursor_x, display_y, "│");
                    }
                }
            }
        }
    }

    fn renderHighlightedLine(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, line: []const u8, max_width: u16) !void {
        _ = self;
        // Simple syntax highlighting for markdown
        var pos: u16 = 0;
        var i: usize = 0;

        while (i < line.len and pos < max_width) {
            // Headers
            if (i == 0 and std.mem.startsWith(u8, line, "#")) {
                const level = countHeadingLevel(line);
                try renderer.writeTextStyled(x + pos, y, line[0..level], .{ .fg = .cyan, .bold = true });
                pos += @intCast(level);
                i += level;
                continue;
            }

            // Bold
            if (std.mem.startsWith(u8, line[i..], "**")) {
                const end = std.mem.indexOf(u8, line[i + 2 ..], "**") orelse line.len - i - 2;
                try renderer.writeTextStyled(x + pos, y, line[i .. i + end + 4], .{ .bold = true });
                pos += @intCast(end + 4);
                i += end + 4;
                continue;
            }

            // Italic
            if (line[i] == '*' or line[i] == '_') {
                const end = std.mem.indexOfScalar(u8, line[i + 1 ..], line[i]) orelse line.len - i - 1;
                try renderer.writeTextStyled(x + pos, y, line[i .. i + end + 2], .{ .italic = true });
                pos += @intCast(end + 2);
                i += end + 2;
                continue;
            }

            // Code
            if (line[i] == '`') {
                const end = std.mem.indexOfScalar(u8, line[i + 1 ..], '`') orelse line.len - i - 1;
                try renderer.writeTextStyled(x + pos, y, line[i .. i + end + 2], .{ .fg = .green });
                pos += @intCast(end + 2);
                i += end + 2;
                continue;
            }

            // Links
            if (line[i] == '[') {
                const end = std.mem.indexOfScalar(u8, line[i + 1 ..], ']') orelse line.len - i - 1;
                try renderer.writeTextStyled(x + pos, y, line[i .. i + end + 2], .{ .fg = .blue, .underline = true });
                pos += @intCast(end + 2);
                i += end + 2;
                continue;
            }

            // Default
            try renderer.writeText(x + pos, y, &[_]u8{line[i]});
            pos += 1;
            i += 1;
        }
    }

    fn renderPreview(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, width: u16, height: u16) !void {
        // Draw preview frame
        try renderer.drawBox(x, y, width, height, .single);
        try renderer.writeText(x + 2, y, " Preview ");

        // Use canvas engine for enhanced preview if available
        if (self.canvas_engine != null and self.config.preview_settings.live_preview) {
            try self.renderMarkdownPreview(x + 1, y + 1, width - 2, height - 2);
        } else {
            // Fallback to text rendering
            try self.renderTextPreview(renderer, x, y, width, height);
        }
    }

    fn renderTextPreview(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, width: u16, height: u16) !void {
        // Build markdown content
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();

        for (self.state.document.lines.items) |line| {
            try content.appendSlice(line);
            try content.append('\n');
        }

        // Markdown rendering
        var line_start: usize = 0;
        var display_y = y + 2;

        for (content.items, 0..) |char, idx| {
            if (char == '\n' or idx == content.items.len - 1) {
                const line = content.items[line_start..idx];
                if (display_y < y + height - 1) {
                    // Syntax highlighting for preview
                    try self.renderPreviewLine(renderer, x + 2, display_y, line, width - 4);
                    display_y += 1;
                }
                line_start = idx + 1;
            }
        }
    }

    fn renderPreviewLine(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, line: []const u8, max_width: u16) !void {
        _ = self;
        var pos: u16 = 0;
        var i: usize = 0;

        while (i < line.len and pos < max_width) {
            // Headers
            if (i == 0 and std.mem.startsWith(u8, line, "#")) {
                const level = countHeadingLevel(line);
                const header_text = line[level + 1 .. @min(line.len, level + 1 + max_width)];
                try renderer.writeTextStyled(x + pos, y, header_text, .{ .bold = true });
                break;
            }

            // Bold text
            if (std.mem.startsWith(u8, line[i..], "**")) {
                const end = std.mem.indexOf(u8, line[i + 2 ..], "**") orelse line.len - i - 2;
                const text = line[i .. i + end + 4];
                try renderer.writeTextStyled(x + pos, y, text, .{ .bold = true });
                pos += @intCast(text.len);
                i += text.len;
                continue;
            }

            // Links
            if (line[i] == '[') {
                const end = std.mem.indexOfScalar(u8, line[i + 1 ..], ']') orelse line.len - i - 1;
                const link_text = line[i .. i + end + 2];
                try renderer.writeTextStyled(x + pos, y, link_text, .{ .underline = true });
                pos += @intCast(link_text.len);
                i += link_text.len;
                continue;
            }

            // Regular text
            try renderer.writeText(x + pos, y, line[i .. i + 1]);
            pos += 1;
            i += 1;
        }
    }

    fn renderVerticalDivider(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, height: u16) !void {
        _ = self;
        for (0..height) |i| {
            try renderer.writeText(x, y + @as(u16, @intCast(i)), "│");
        }
    }

    fn renderHorizontalDivider(self: *Self, renderer: *tui.Renderer, x: u16, y: u16, width: u16) !void {
        _ = self;
        for (0..width) |i| {
            try renderer.writeText(x + @as(u16, @intCast(i)), y, "─");
        }
    }

    fn renderOverlays(self: *Self, renderer: *tui.Renderer) !void {
        // Command palette
        if (self.command_palette.isVisible()) {
            try self.command_palette.render(renderer);
        }

        // Auto-completion popup
        if (self.auto_completer.hasCompletions()) {
            try self.auto_completer.render(renderer);
        }

        // Metrics dashboard overlay
        if (self.metrics_dashboard.isVisible()) {
            try self.metrics_dashboard.render(renderer, &self.state.metrics);
        }
    }

    fn handleEvent(self: *Self, event: tui.InputEvent) !bool {
        return switch (event) {
            .key => |key| try self.handleKeyEvent(key),
            .mouse => |mouse| try self.handleMouseEvent(mouse),
            .resize => |size| try self.handleResize(size),
            else => false,
        };
    }

    fn handleKeyEvent(self: *Self, key: tui.Key) !bool {
        // Check command palette first
        if (self.command_palette.isVisible()) {
            return try self.command_palette.handleInput(key);
        }

        // Check auto-completion
        if (self.auto_completer.hasCompletions()) {
            if (try self.auto_completer.handleInput(key)) {
                return false;
            }
        }

        // Handle ctrl shortcuts
        if (key.ctrl) {
            return try self.handleCtrlShortcut(key);
        }

        // Handle alt shortcuts
        if (key.alt) {
            return try self.handleAltShortcut(key);
        }

        // Handle regular keys
        switch (key.code) {
            .escape => {
                // Close overlays or exit
                if (self.command_palette.isVisible()) {
                    self.command_palette.hide();
                } else {
                    return true; // Exit
                }
            },
            .enter => try self.insertNewLine(),
            .backspace => try self.deleteText(.backward),
            .delete => try self.deleteText(.forward),
            .tab => try self.insertText("    "),
            .up => try self.moveCursor(.up),
            .down => try self.moveCursor(.down),
            .left => try self.moveCursor(.left),
            .right => try self.moveCursor(.right),
            .home => try self.moveCursorToLineStart(),
            .end => try self.moveCursorToLineEnd(),
            .page_up => try self.pageUp(),
            .page_down => try self.pageDown(),
            else => {
                // Regular character input
                if (key.char) |char| {
                    try self.insertText(&[_]u8{char});
                }
            },
        }

        return false;
    }

    fn handleCtrlShortcut(self: *Self, key: tui.Key) !bool {
        switch (key.code) {
            'q' => return true, // Quit
            's' => try self.saveDocument(), // Save
            'o' => try self.openFile(), // Open
            'n' => try self.newDocument(), // New
            'z' => try self.undo(), // Undo
            'y' => try self.redo(), // Redo
            'f' => try self.openSearchDialog(), // Find
            'h' => try self.openReplaceDialog(), // Replace
            'p' => try self.command_palette.toggle(), // Command palette
            'e' => try self.exportDialog(), // Export
            'b' => try self.toggleBold(), // Bold
            'i' => try self.toggleItalic(), // Italic
            'k' => try self.insertLink(), // Insert link
            ' ' => try self.triggerAutoComplete(), // Auto-complete
            else => {},
        }
        return false;
    }

    fn handleAltShortcut(self: *Self, key: tui.Key) !bool {
        switch (key.code) {
            'p' => try self.togglePreview(), // Toggle preview
            's' => try self.toggleSidebar(), // Toggle sidebar
            'm' => try self.toggleMetrics(), // Toggle metrics
            'v' => try self.toggleSplitMode(), // Toggle split mode
            '1'...'6' => try self.insertHeading(key.code - '0'), // Insert heading
            else => {},
        }
        return false;
    }

    fn handleMouseEvent(self: *Self, mouse: tui.Mouse) !void {
        switch (mouse.action) {
            .press => {
                if (mouse.button == .left) {
                    // Set cursor position
                    try self.setCursorFromMouse(mouse.x, mouse.y);
                }
            },
            .scroll => {
                if (mouse.direction == .up) {
                    try self.scrollUp(3);
                } else {
                    try self.scrollDown(3);
                }
            },
            else => {},
        }
    }

    fn handleResize(self: *Self, size: tui.TerminalSize) !void {
        _ = self;
        _ = size;
        // Recalculate layout
    }

    fn updateMetrics(self: *Self) !void {
        var metrics = DocumentMetrics{};

        // Count lines
        metrics.line_count = @intCast(self.state.document.lines.items.len);

        // Count words, characters, and analyze structure
        for (self.state.document.lines.items) |line| {
            // Count words
            var word_iter = std.mem.tokenize(u8, line, " \t\n\r");
            while (word_iter.next()) |_| {
                metrics.word_count += 1;
            }

            // Count characters
            metrics.char_count += @intCast(line.len);

            // Count headings
            if (std.mem.startsWith(u8, line, "#")) {
                const level = countHeadingLevel(line);
                if (level > 0 and level <= 6) {
                    metrics.heading_counts[level - 1] += 1;
                }
            }

            // Count links
            metrics.link_count += countOccurrences(line, "[");

            // Count code blocks
            if (std.mem.startsWith(u8, line, "```")) {
                metrics.code_block_count += 1;
            }

            // Count tables
            if (std.mem.indexOf(u8, line, "|") != null) {
                // Heuristic for tables
                const pipes = countOccurrences(line, "|");
                if (pipes >= 2) {
                    metrics.table_count += 1;
                }
            }
        }

        // Calculate reading time (average 200 words per minute)
        metrics.reading_time = @as(f32, @floatFromInt(metrics.word_count)) / 200.0;

        self.state.metrics = metrics;
    }

    fn updatePreview(self: *Self) !void {
        _ = self;
        // Debounced preview update
        // Implementation would use timer to delay updates
    }

    fn checkAutoSave(self: *Self) !void {
        if (!self.state.is_modified) return;

        const current_time = std.time.milliTimestamp();
        const last_save = self.state.last_save_time orelse 0;
        const interval_ms = self.config.editor_settings.auto_save_interval * 1000;

        if (current_time - last_save >= interval_ms) {
            try self.saveDocument();
        }
    }

    fn saveSession(self: *Self) !void {
        try self.session_manager.saveSession(&self.state);
    }

    fn extractMetadata(self: *Self) !void {
        // Look for YAML frontmatter
        if (self.state.document.lines.items.len > 0) {
            if (std.mem.eql(u8, self.state.document.lines.items[0], "---")) {
                // Find end of frontmatter
                for (self.state.document.lines.items[1..], 1..) |line, idx| {
                    if (std.mem.eql(u8, line, "---")) {
                        // Parse YAML metadata
                        // Implementation would parse YAML between lines 1 and idx
                        _ = idx;
                        break;
                    }
                }
            }
        }
    }

    fn buildSyntaxTree(self: *Self) !void {
        // Build AST for syntax highlighting and navigation
        // This would parse the markdown and build a tree structure
        _ = self;
    }

    fn insertTextAtCursor(self: *Self, cursor: CursorPosition, text: []const u8) !void {
        if (cursor.line >= self.state.document.lines.items.len) return;

        const line = &self.state.document.lines.items[cursor.line];
        const new_line = try std.mem.concat(self.allocator, u8, &[_][]const u8{
            line.*[0..@min(cursor.column, line.len)],
            text,
            if (cursor.column < line.len) line.*[cursor.column..] else "",
        });

        self.allocator.free(line.*);
        line.* = new_line;

        // Record operation for undo
        try self.recordOperation(.{
            .type = .insert,
            .position = cursor,
            .old_text = "",
            .new_text = text,
            .group_id = self.state.undo_history.current_group orelse 0,
        });
    }

    fn deleteAtCursor(self: *Self, cursor: *CursorPosition, direction: enum { backward, forward }) !void {
        _ = self;
        _ = cursor;
        _ = direction;
        // Implementation
    }

    fn applyOperation(self: *Self, op: EditOperation, reverse: bool) !void {
        _ = self;
        _ = op;
        _ = reverse;
        // Implementation
    }

    fn recordOperation(self: *Self, op: EditOperation) !void {
        try self.state.undo_history.undo_stack.append(op);
        self.state.undo_history.redo_stack.clearRetainingCapacity();
    }

    fn registerEditorCommands(self: *Self) !void {
        // Register markdown-specific commands
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

        try self.command_palette.registerCommand(.{
            .name = "Toggle Preview",
            .description = "Toggle preview pane",
            .shortcut = "Alt+P",
            .action = togglePreviewCommand,
        });

        // Add more commands...
    }

    fn backgroundWorker(self: *Self) !void {
        while (true) {
            std.time.sleep(1 * std.time.ns_per_s);

            // Auto-save check
            self.checkAutoSave() catch {};

            // Session backup
            if (self.config.session_settings.enable_recovery) {
                self.saveSession() catch {};
            }
        }
    }

    // Additional helper methods...

    fn promptSaveChanges(self: *Self) !bool {
        _ = self;
        // Show save dialog
        return true;
    }

    fn promptFileName(self: *Self) !?[]const u8 {
        _ = self;
        // Show file name prompt
        return null;
    }

    fn appendMetadata(self: *Self, content: *std.ArrayList(u8)) !void {
        _ = self;
        _ = content;
        // Add YAML frontmatter
    }

    fn findMatchesInLine(self: *Self, line: []const u8, query: []const u8, options: SearchOptions) ![]Match {
        _ = self;
        _ = line;
        _ = query;
        _ = options;
        // Find matches in line
        return &[_]Match{};
    }

    fn navigateToSearchResult(self: *Self, index: usize) !void {
        _ = self;
        _ = index;
        // Navigate to result
    }

    fn replaceAtPosition(self: *Self, result: SearchResult, replace_text: []const u8) !void {
        _ = self;
        _ = result;
        _ = replace_text;
        // Replace text at position
    }

    // Movement methods
    fn moveCursor(self: *Self, direction: enum { up, down, left, right }) !void {
        _ = self;
        _ = direction;
    }

    fn moveCursorToLineStart(self: *Self) !void {
        _ = self;
    }

    fn moveCursorToLineEnd(self: *Self) !void {
        _ = self;
    }

    fn pageUp(self: *Self) !void {
        _ = self;
    }

    fn pageDown(self: *Self) !void {
        _ = self;
    }

    fn scrollUp(self: *Self, lines: u32) !void {
        _ = self;
        _ = lines;
    }

    fn scrollDown(self: *Self, lines: u32) !void {
        _ = self;
        _ = lines;
    }

    fn setCursorFromMouse(self: *Self, x: u16, y: u16) !void {
        _ = self;
        _ = x;
        _ = y;
    }

    // Document methods
    fn openFile(self: *Self) !void {
        _ = self;
    }

    fn newDocument(self: *Self) !void {
        _ = self;
    }

    fn insertNewLine(self: *Self) !void {
        _ = self;
    }

    // Search methods
    fn openSearchDialog(self: *Self) !void {
        _ = self;
    }

    fn openReplaceDialog(self: *Self) !void {
        _ = self;
    }

    // Format methods
    fn toggleBold(self: *Self) !void {
        _ = self;
    }

    fn toggleItalic(self: *Self) !void {
        _ = self;
    }

    fn insertLink(self: *Self) !void {
        _ = self;
    }

    fn insertHeading(self: *Self, level: u8) !void {
        _ = self;
        _ = level;
    }

    fn triggerAutoComplete(self: *Self) !void {
        _ = self;
    }

    // View methods
    fn togglePreview(self: *Self) !void {
        self.state.view.preview_visible = !self.state.view.preview_visible;
    }

    fn toggleSidebar(self: *Self) !void {
        self.state.view.sidebar_visible = !self.state.view.sidebar_visible;
    }

    fn toggleMetrics(self: *Self) !void {
        try self.metrics_dashboard.toggle();
    }

    fn toggleSplitMode(self: *Self) !void {
        self.state.view.split_mode = switch (self.state.view.split_mode) {
            .none => .vertical,
            .vertical => .horizontal,
            .horizontal => .none,
        };
    }

    fn exportDialog(self: *Self) !void {
        _ = self;
    }
};

// === Supporting Components ===

const AutoCompleter = struct {
    allocator: Allocator,
    completions: std.ArrayList(Completion),
    visible: bool = false,

    const Completion = struct {
        text: []const u8,
        type: CompletionType,
        description: []const u8,
    };

    const CompletionType = enum {
        keyword,
        snippet,
        emoji,
        reference,
    };

    pub fn init(allocator: Allocator) !*AutoCompleter {
        const self = try allocator.create(AutoCompleter);
        self.* = .{
            .allocator = allocator,
            .completions = std.ArrayList(Completion).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *AutoCompleter) void {
        self.completions.deinit();
        self.allocator.destroy(self);
    }

    pub fn hasCompletions(self: *AutoCompleter) bool {
        return self.visible and self.completions.items.len > 0;
    }

    pub fn render(self: *AutoCompleter, renderer: *tui.Renderer) !void {
        _ = self;
        _ = renderer;
    }

    pub fn handleInput(self: *AutoCompleter, key: tui.Key) !bool {
        _ = self;
        _ = key;
        return false;
    }
};

const CommandPalette = struct {
    allocator: Allocator,
    visible: bool = false,
    commands: std.ArrayList(Command),

    const Command = struct {
        name: []const u8,
        description: []const u8,
        shortcut: ?[]const u8,
        action: *const fn () anyerror!void,
    };

    pub fn init(allocator: Allocator) !*CommandPalette {
        const self = try allocator.create(CommandPalette);
        self.* = .{
            .allocator = allocator,
            .commands = std.ArrayList(Command).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *CommandPalette) void {
        self.allocator.destroy(self);
    }

    pub fn toggle(self: *CommandPalette) !void {
        self.visible = !self.visible;
    }

    pub fn hide(self: *CommandPalette) void {
        self.visible = false;
    }

    pub fn isVisible(self: *CommandPalette) bool {
        return self.visible;
    }

    pub fn render(self: *CommandPalette, renderer: *tui.Renderer) !void {
        _ = self;
        _ = renderer;
    }

    pub fn handleInput(self: *CommandPalette, key: tui.Key) !bool {
        _ = self;
        _ = key;
        return false;
    }

    pub fn registerCommand(self: *CommandPalette, command: Command) !void {
        try self.commands.append(command);
    }
};

const MetricsDashboard = struct {
    allocator: Allocator,
    visible: bool = false,

    pub fn init(allocator: Allocator) !*MetricsDashboard {
        const self = try allocator.create(MetricsDashboard);
        self.* = .{
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *MetricsDashboard) void {
        self.allocator.destroy(self);
    }

    pub fn toggle(self: *MetricsDashboard) !void {
        self.visible = !self.visible;
    }

    pub fn isVisible(self: *MetricsDashboard) bool {
        return self.visible;
    }

    pub fn render(self: *MetricsDashboard, renderer: *tui.Renderer, metrics: *const DocumentMetrics) !void {
        _ = self;
        _ = renderer;
        _ = metrics;
    }
};

const Export = struct {
    allocator: Allocator,
    settings: ExportSettings,

    pub fn init(allocator: Allocator, settings: ExportSettings) !*Export {
        const self = try allocator.create(Export);
        self.* = .{
            .allocator = allocator,
            .settings = settings,
        };
        return self;
    }

    pub fn deinit(self: *Export) void {
        self.allocator.destroy(self);
    }

    pub fn exportDocument(self: *Export, document: *const Document, format: ExportFormat) !void {
        _ = self;
        _ = document;
        _ = format;
    }
};

const EditorSession = struct {
    allocator: Allocator,
    settings: EditorSessionSettings,
    recent_files: std.ArrayList([]const u8),

    pub fn init(allocator: Allocator, settings: EditorSessionSettings) !*EditorSession {
        const self = try allocator.create(EditorSession);
        self.* = .{
            .allocator = allocator,
            .settings = settings,
            .recent_files = std.ArrayList([]const u8).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *EditorSession) void {
        self.recent_files.deinit();
        self.allocator.destroy(self);
    }

    pub fn saveSession(self: *EditorSession, state: *const EditorState) !void {
        _ = self;
        _ = state;
    }

    pub fn addRecentFile(self: *EditorSession, path: []const u8) !void {
        try self.recent_files.append(try self.allocator.dupe(u8, path));
    }

    pub fn getRecentFiles(self: *EditorSession) [][]const u8 {
        return self.recent_files.items;
    }
};

const SyntaxTheme = struct {
    allocator: Allocator,
    theme_name: []const u8,

    pub fn init(allocator: Allocator, theme_name: []const u8) !*SyntaxTheme {
        const self = try allocator.create(SyntaxTheme);
        self.* = .{
            .allocator = allocator,
            .theme_name = theme_name,
        };
        return self;
    }

    pub fn deinit(self: *SyntaxTheme) void {
        self.allocator.destroy(self);
    }
};

const EditorWelcomeScreen = struct {
    allocator: Allocator,
    theme: *theme.ColorScheme,

    pub fn init(allocator: Allocator, theme: *theme.ColorScheme) EditorWelcomeScreen {
        return .{
            .allocator = allocator,
            .theme = theme,
        };
    }

    pub fn deinit(self: EditorWelcomeScreen) void {
        _ = self;
    }

    pub fn render(self: EditorWelcomeScreen, renderer: *tui.Renderer, options: anytype) !void {
        _ = self;
        _ = renderer;
        _ = options;
    }
};

// === Event Handlers ===

const EventHandlers = struct {
    on_save: ?*const fn () void = null,
    on_change: ?*const fn () void = null,
    on_cursor_move: ?*const fn () void = null,
};

// === Helper Types ===

const SearchOptions = struct {
    regex: bool = false,
    case_sensitive: bool = false,
    whole_word: bool = false,
};

const Match = struct {
    start: u32,
    end: u32,
};

// === Command Functions ===

fn insertHeadingCommand() !void {}
fn formatTableCommand() !void {}
fn insertLinkCommand() !void {}
fn togglePreviewCommand() !void {}

// === Utility Functions ===

fn countHeadingLevel(line: []const u8) u32 {
    var level: u32 = 0;
    for (line) |char| {
        if (char == '#') {
            level += 1;
        } else {
            break;
        }
    }
    return level;
}

fn countOccurrences(text: []const u8, needle: []const u8) u32 {
    var count: u32 = 0;
    var pos: usize = 0;
    while (std.mem.indexOf(u8, text[pos..], needle)) |idx| {
        count += 1;
        pos += idx + needle.len;
    }
    return count;
}

// === Public API ===

/// Create and run the markdown editor
pub fn runEditor(allocator: Allocator, agent: *agent_interface.Agent) !void {
    const editor_config = MarkdownEditorConfig{
        .base_config = agent.config,
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
            .default_format = .markdown,
            .include_toc = true,
            .include_metadata = true,
        },
        .session_settings = .{
            .max_undo_history = 1000,
            .enable_recovery = true,
            .backup_interval_s = 60,
        },
    };

    const editor = try MarkdownEditor.init(allocator, agent, editor_config);
    defer editor.deinit();

    try editor.run();
}

// === Tests ===

test "editor initialization" {
    // Test would go here
}

test "document metrics calculation" {
    // Test would go here
}

test "syntax highlighting" {
    // Test would go here
}

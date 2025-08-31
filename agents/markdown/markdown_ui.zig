//! Interactive Markdown UI
//!
//! This module provides an interactive session for markdown editing
//! with live preview, synchronized scrolling, smart completions, snippet management,
//! document outline navigation, and integrated diff viewer.

const std = @import("std");
const agent_ui_framework = @import("../../src/foundation/tui/agent_ui.zig");
const renderer_mod = @import("../../src/foundation/tui/core/renderer.zig");
const bounds_mod = @import("../../src/foundation/tui/core/bounds.zig");
const theme = @import("../../src/foundation/theme/mod.zig");
const input_system = @import("../../src/foundation/components/input.zig");
const markdown_renderer = @import("../../src/foundation/render/markdown_renderer.zig");
const diff_viewer = @import("../../examples/diff_viewer.zig");

const StandardUIPatterns = agent_ui_framework.StandardUIPatterns;
const MarkdownEditor = agent_ui_framework.MarkdownEditor;
const OAuthIntegration = agent_ui_framework.OAuthIntegration;
const KeyboardShortcuts = agent_ui_framework.KeyboardShortcuts;
const NotificationType = agent_ui_framework.NotificationType;
const Renderer = renderer_mod.Renderer;
const Render = renderer_mod.Render;
const Style = renderer_mod.Style;
const Bounds = renderer_mod.Bounds;
const Theme = theme.Theme;
const InputManager = input_system.InputManager;

/// Interactive markdown session configuration
pub const InteractiveMarkdownConfig = struct {
    /// Base UI framework config
    ui_config: agent_ui_framework.StandardUIPatterns,

    /// Editor configuration
    editor_config: EditorConfig = .{},

    /// Preview configuration
    preview_config: PreviewConfig = .{},

    /// Layout configuration
    layout_config: LayoutConfig = .{},

    /// Feature flags
    features: FeatureFlags = .{},
};

/// Editor-specific configuration
pub const EditorConfig = struct {
    /// Enable syntax highlighting
    syntax_highlighting: bool = true,

    /// Enable line numbers
    line_numbers: bool = true,

    /// Enable auto-save
    auto_save: bool = true,

    /// Auto-save interval in seconds
    auto_save_interval: u32 = 30,

    /// Enable word wrap
    word_wrap: bool = true,

    /// Tab size in spaces
    tab_size: u32 = 4,

    /// Enable smart indentation
    smart_indent: bool = true,

    /// Show whitespace characters
    show_whitespace: bool = false,
};

/// Preview-specific configuration
pub const PreviewConfig = struct {
    /// Enable live preview
    live_preview: bool = true,

    /// Preview update delay in milliseconds
    update_delay_ms: u32 = 300,

    /// Enable synchronized scrolling
    sync_scroll: bool = true,

    /// Preview zoom level
    zoom_level: f32 = 1.0,

    /// Show table of contents
    show_toc: bool = true,

    /// Enable math rendering
    enable_math: bool = true,

    /// Enable mermaid diagrams
    enable_mermaid: bool = false,
};

/// Layout configuration
pub const LayoutConfig = struct {
    /// Split orientation (horizontal or vertical)
    split_orientation: enum { horizontal, vertical } = .horizontal,

    /// Editor pane size ratio (0.0 to 1.0)
    editor_ratio: f32 = 0.5,

    /// Show minimap
    show_minimap: bool = true,

    /// Show status bar
    show_status_bar: bool = true,

    /// Show command palette
    show_command_palette: bool = true,
};

/// Feature flags for enabling/disabling functionality
pub const FeatureFlags = struct {
    /// Enable smart completions
    smart_completions: bool = true,

    /// Enable snippet management
    snippets: bool = true,

    /// Enable document outline
    outline_navigation: bool = true,

    /// Enable diff viewer
    diff_viewer: bool = true,

    /// Enable collaboration features
    collaboration: bool = false,

    /// Enable version history
    version_history: bool = true,
};

/// Interactive markdown session
pub const InteractiveMarkdownSession = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: InteractiveMarkdownConfig,
    renderer: *Renderer,
    theme_manager: *Theme,
    input_manager: InputManager,

    /// Core components
    editor: MarkdownEditor,
    preview_renderer: PreviewRenderer,
    outline_navigator: OutlineNavigator,
    snippet_manager: Snippet,
    diff_viewer_instance: ?*diff_viewer.DiffViewer = null,

    /// State management
    current_file_path: ?[]const u8 = null,
    is_modified: bool = false,
    last_saved: i64 = 0,

    /// Layout state
    terminal_size: bounds_mod.TerminalSize,
    editor_bounds: Bounds,
    preview_bounds: Bounds,

    /// Feature state
    show_outline: bool = false,
    show_diff: bool = false,
    command_palette_active: bool = false,

    pub fn init(allocator: std.mem.Allocator, config: InteractiveMarkdownConfig) !*Self {
        const session = try allocator.create(Self);
        const renderer = config.ui_config.renderer;
        const theme_manager = config.ui_config.theme_manager;

        // Initialize input manager
        const input_manager = try InputManager.init(allocator);

        // Initialize editor
        const editor = try MarkdownEditor.init(allocator, renderer, theme_manager);

        // Initialize preview renderer
        const preview_renderer = try PreviewRenderer.init(allocator, renderer, theme_manager);

        // Initialize outline navigator
        const outline_navigator = try OutlineNavigator.init(allocator);

        // Initialize snippet manager
        const snippet_manager = try Snippet.init(allocator);

        session.* = .{
            .allocator = allocator,
            .config = config,
            .renderer = renderer,
            .theme_manager = theme_manager,
            .input_manager = input_manager,
            .editor = editor,
            .preview_renderer = preview_renderer,
            .outline_navigator = outline_navigator,
            .snippet_manager = snippet_manager,
            .terminal_size = bounds_mod.getTerminalSize(),
        };

        // Set up keyboard shortcuts
        try session.setupKeyboardShortcuts();

        // Load default snippets
        try session.loadDefaultSnippets();

        return session;
    }

    pub fn deinit(self: *Self) void {
        self.editor.deinit();
        self.preview_renderer.deinit();
        self.outline_navigator.deinit();
        self.snippet_manager.deinit();
        if (self.diff_viewer_instance) |viewer| {
            viewer.deinit();
            self.allocator.destroy(viewer);
        }
        if (self.current_file_path) |path| {
            self.allocator.free(path);
        }
        self.input_manager.deinit();
    }

    /// Load a markdown file
    pub fn loadFile(self: *Self, file_path: []const u8) !void {
        const content = try std.fs.cwd().readFileAlloc(self.allocator, file_path, std.math.maxInt(usize));
        defer self.allocator.free(content);

        try self.editor.loadContent(content);

        // Update file path
        if (self.current_file_path) |old_path| {
            self.allocator.free(old_path);
        }
        self.current_file_path = try self.allocator.dupe(u8, file_path);

        // Parse outline
        try self.outline_navigator.parseOutline(content);

        // Update preview
        try self.updatePreview();

        // Reset modification state
        self.is_modified = false;
        self.last_saved = std.time.timestamp();

        // Show notification
        const file_name = std.fs.path.basename(file_path);
        try self.config.ui_config.showNotification(.info, "File Loaded", try std.fmt.allocPrint(self.allocator, "Opened {s}", .{file_name}));
    }

    /// Save current content to file
    pub fn saveFile(self: *Self) !void {
        if (self.current_file_path == null) {
            return error.NoFilePath;
        }

        const content = self.editor.getContent();
        try std.fs.cwd().writeFile(.{
            .sub_path = self.current_file_path.?,
            .data = content,
            .flags = .{ .truncate = true },
        });

        self.is_modified = false;
        self.last_saved = std.time.timestamp();

        // Show notification
        const file_name = std.fs.path.basename(self.current_file_path.?);
        try self.config.ui_config.showNotification(.success, "File Saved", try std.fmt.allocPrint(self.allocator, "Saved {s}", .{file_name}));
    }

    /// Run the interactive session
    pub fn run(self: *Self) !void {
        // Initial layout calculation
        try self.updateLayout();

        // Main event loop
        while (true) {
            try self.render();
            try self.handleInput();

            // Auto-save if enabled
            if (self.config.editor_config.auto_save and self.is_modified) {
                const now = std.time.timestamp();
                if (now - self.last_saved > self.config.editor_config.auto_save_interval) {
                    try self.saveFile();
                }
            }

            std.time.sleep(10_000_000); // 10ms
        }
    }

    /// Render the entire session
    fn render(self: *Self) !void {
        try self.renderer.beginFrame();
        try self.renderer.clear(Bounds{
            .x = 0,
            .y = 0,
            .width = self.terminal_size.width,
            .height = self.terminal_size.height,
        });

        // Render editor
        try self.editor.render(self.editor_bounds);

        // Render preview
        try self.preview_renderer.render(self.preview_bounds, self.editor.getContent());

        // Render outline if enabled
        if (self.show_outline) {
            try self.renderOutline();
        }

        // Render diff viewer if enabled
        if (self.show_diff and self.diff_viewer_instance != null) {
            try self.diff_viewer_instance.?.render();
        }

        // Render status bar
        if (self.config.layout_config.show_status_bar) {
            try self.renderStatusBar();
        }

        // Render command palette if active
        if (self.command_palette_active) {
            try self.renderCommandPalette();
        }

        try self.renderer.endFrame();
    }

    /// Handle user input
    fn handleInput(self: *Self) !void {
        if (try self.input_manager.pollEvent()) |event| {
            switch (event) {
                .key_press => |key_event| {
                    try self.handleKeyPress(key_event);
                },
                .mouse => |mouse_event| {
                    try self.handleMouseEvent(mouse_event);
                },
                .paste => |paste_event| {
                    try self.editor.insertText(paste_event.text);
                    self.is_modified = true;
                    try self.updatePreview();
                },
                else => {},
            }
        }
    }

    /// Handle keyboard input
    fn handleKeyPress(self: *Self, key_event: input_system.KeyEvent) !void {
        // Handle special keys
        switch (key_event.code) {
            .char => |char| {
                if (char == '\t') {
                    // Handle tab completion or indentation
                    if (self.config.features.smart_completions) {
                        try self.handleSmartCompletion();
                    } else {
                        try self.insertTab();
                    }
                } else {
                    try self.editor.insertText(&[_]u8{char});
                    self.is_modified = true;
                    try self.updatePreview();
                }
            },
            .enter => {
                try self.editor.insertText("\n");
                self.is_modified = true;
                try self.updatePreview();
            },
            .backspace => {
                self.editor.deleteChar();
                self.is_modified = true;
                try self.updatePreview();
            },
            .left => self.editor.moveCursor(.left),
            .right => self.editor.moveCursor(.right),
            .up => self.editor.moveCursor(.up),
            .down => self.editor.moveCursor(.down),
            .home => self.editor.moveCursorToLineStart(),
            .end => self.editor.moveCursorToLineEnd(),
            .page_up => self.editor.scrollUp(10),
            .page_down => self.editor.scrollDown(10),
            else => {},
        }
    }

    /// Handle mouse events
    fn handleMouseEvent(self: *Self, mouse_event: input_system.MouseEvent) !void {
        // Handle mouse events for interactive elements
        _ = self; // Mark self as used
        _ = mouse_event; // Placeholder for mouse handling
    }

    /// Update preview with current content
    fn updatePreview(self: *Self) !void {
        if (self.config.preview_config.live_preview) {
            const content = self.editor.getContent();
            try self.preview_renderer.updateContent(content);
        }
    }

    /// Update layout based on terminal size
    fn updateLayout(self: *Self) !void {
        self.terminal_size = bounds_mod.getTerminalSize();

        const total_width = self.terminal_size.width;
        const total_height = self.terminal_size.height;

        if (self.config.layout_config.split_orientation == .horizontal) {
            const editor_width = @as(u16, @intFromFloat(@as(f32, @floatFromInt(total_width)) * self.config.layout_config.editor_ratio));
            const preview_width = total_width - editor_width;

            self.editor_bounds = Bounds{
                .x = 0,
                .y = 0,
                .width = editor_width,
                .height = total_height - 2, // Leave space for status bar
            };

            self.preview_bounds = Bounds{
                .x = editor_width,
                .y = 0,
                .width = preview_width,
                .height = total_height - 2,
            };
        } else {
            // Vertical split
            const editor_height = @as(u16, @intFromFloat(@as(f32, @floatFromInt(total_height)) * self.config.layout_config.editor_ratio));
            const preview_height = total_height - editor_height;

            self.editor_bounds = Bounds{
                .x = 0,
                .y = 0,
                .width = total_width,
                .height = editor_height,
            };

            self.preview_bounds = Bounds{
                .x = 0,
                .y = editor_height,
                .width = total_width,
                .height = preview_height,
            };
        }
    }

    /// Render status bar
    fn renderStatusBar(self: *Self) !void {
        const status_y = self.terminal_size.height - 1;
        const status_bounds = Bounds{
            .x = 0,
            .y = status_y,
            .width = self.terminal_size.width,
            .height = 1,
        };

        const theme = self.current_theme.getCurrentTheme();

        // Draw status bar background
        const bg_style = Style{
            .bg_color = status_theme.primary,
            .fg_color = status_theme.background,
            .bold = false,
        };

        try self.renderer.drawRect(status_bounds, bg_style);

        // Draw status information
        const file_name = if (self.current_file_path) |path|
            std.fs.path.basename(path)
        else
            "Untitled";

        const modified_indicator = if (self.is_modified) " [+]" else "";
        const status_text = try std.fmt.allocPrint(self.allocator, "{s}{s} | Line {} | Col {}", .{
            file_name,
            modified_indicator,
            self.editor.getCurrentLine(),
            self.editor.getCurrentColumn(),
        });
        defer self.allocator.free(status_text);

        const status_ctx = Render{
            .bounds = status_bounds,
            .style = .{ .fg_color = current_theme.background, .bg_color = current_theme.primary },
            .zIndex = 0,
            .clipRegion = null,
        };

        try self.renderer.drawText(status_ctx, status_text);
    }

    /// Render outline panel
    fn renderOutline(self: *Self) !void {
        const outline_width = 30;
        const outline_bounds = Bounds{
            .x = self.terminal_size.width - outline_width,
            .y = 0,
            .width = outline_width,
            .height = self.terminal_size.height - 2,
        };

        // Draw outline background
        const outline_theme = self.current_theme.currentTheme();
        const bg_style = Style{
            .bg_color = outline_theme.secondary,
            .fg_color = outline_theme.foreground,
            .bold = false,
        };

        try self.renderer.drawRect(outline_bounds, bg_style);

        // Draw outline title
        const title_bounds = Bounds{
            .x = outline_bounds.x,
            .y = outline_bounds.y,
            .width = outline_bounds.width,
            .height = 1,
        };

        const title_ctx = Render{
            .bounds = title_bounds,
            .style = .{ .fg_color = current_theme.primary, .bold = true },
            .zIndex = 0,
            .clipRegion = null,
        };

        try self.renderer.drawText(title_ctx, " Outline ");

        // Draw outline items
        try self.outline_navigator.render(outline_bounds.x, outline_bounds.y + 1, outline_bounds.width, outline_bounds.height - 1);
    }

    /// Render command palette
    fn renderCommandPalette(self: *Self) !void {
        // Placeholder for command palette rendering
        _ = self;
    }

    /// Handle smart completion
    fn handleSmartCompletion(self: *Self) !void {
        // Placeholder for smart completion logic
        _ = self;
    }

    /// Insert tab character or spaces
    fn insertTab(self: *Self) !void {
        const tab_size = self.config.editor_config.tab_size;
        const spaces = try self.allocator.alloc(u8, tab_size);
        defer self.allocator.free(spaces);

        @memset(spaces, ' ');
        try self.editor.insertText(spaces);
        self.is_modified = true;
        try self.updatePreview();
    }

    /// Set up keyboard shortcuts
    fn setupKeyboardShortcuts(self: *Self) !void {
        // Placeholder for keyboard shortcut setup
        _ = self;
    }

    /// Load default snippets
    fn loadDefaultSnippets(self: *Self) !void {
        // Placeholder for loading default snippets
        _ = self;
    }
};

/// Preview renderer for markdown content
pub const PreviewRenderer = struct {
    allocator: std.mem.Allocator,
    renderer: *Renderer,
    theme_manager: *Theme,
    cached_html: ?[]const u8 = null,
    scroll_offset: usize = 0,

    pub fn init(allocator: std.mem.Allocator, renderer: *Renderer, theme_manager: *Theme) !PreviewRenderer {
        return PreviewRenderer{
            .allocator = allocator,
            .renderer = renderer,
            .theme_manager = theme_manager,
        };
    }

    pub fn deinit(self: *PreviewRenderer) void {
        if (self.cached_html) |html| {
            self.allocator.free(html);
        }
    }

    /// Update content and regenerate preview
    pub fn updateContent(self: *PreviewRenderer, markdown_content: []const u8) !void {
        // Clear previous cache
        if (self.cached_html) |html| {
            self.allocator.free(html);
        }

        // Convert markdown to HTML (placeholder - would use actual markdown parser)
        self.cached_html = try self.allocator.dupe(u8, markdown_content);
    }

    /// Render preview in specified bounds
    pub fn render(self: *PreviewRenderer, bounds: Bounds, content: []const u8) !void {
        if (self.cached_html == null) {
            try self.updateContent(content);
        }

        const theme = self.current_theme.getCurrentTheme();

        // Draw preview border
        const border_style = Style{
            .bg_color = preview_theme.background,
            .fg_color = preview_theme.primary,
            .bold = true,
        };

        try self.renderer.drawBorder(bounds, border_style, .single);

        // Draw preview title
        const title_bounds = Bounds{
            .x = bounds.x,
            .y = bounds.y,
            .width = bounds.width,
            .height = 1,
        };

        const title_ctx = Render{
            .bounds = title_bounds,
            .style = .{ .fg_color = current_theme.primary, .bold = true },
            .zIndex = 0,
            .clipRegion = null,
        };

        try self.renderer.drawText(title_ctx, " Preview ");

        // Draw preview content area
        const content_bounds = Bounds{
            .x = bounds.x + 1,
            .y = bounds.y + 1,
            .width = bounds.width - 2,
            .height = bounds.height - 2,
        };

        // Render markdown content (simplified)
        const content_ctx = Render{
            .bounds = content_bounds,
            .style = .{ .fg_color = current_theme.foreground },
            .zIndex = 0,
            .clipRegion = null,
        };

        // For now, just show the raw markdown with basic formatting
        try self.renderer.drawText(content_ctx, self.cached_html.?);
    }
};

/// Outline navigator for document structure
pub const OutlineNavigator = struct {
    allocator: std.mem.Allocator,
    headings: std.ArrayList(Heading),

    pub const Heading = struct {
        level: u32,
        text: []const u8,
        line_number: usize,
        is_expanded: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator) !OutlineNavigator {
        return OutlineNavigator{
            .allocator = allocator,
            .headings = std.ArrayList(Heading).init(allocator),
        };
    }

    pub fn deinit(self: *OutlineNavigator) void {
        for (self.headings.items) |heading| {
            self.allocator.free(heading.text);
        }
        self.headings.deinit();
    }

    /// Parse markdown content and extract headings
    pub fn parseOutline(self: *OutlineNavigator, content: []const u8) !void {
        // Clear previous headings
        for (self.headings.items) |heading| {
            self.allocator.free(heading.text);
        }
        self.headings.clearRetainingCapacity();

        var lines = std.mem.split(u8, content, "\n");
        var line_number: usize = 1;

        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "#")) {
                // Count leading # characters
                var level: u32 = 0;
                var i: usize = 0;
                while (i < line.len and line[i] == '#') {
                    level += 1;
                    i += 1;
                }

                // Skip whitespace after #
                while (i < line.len and line[i] == ' ') {
                    i += 1;
                }

                // Extract heading text
                const heading_text = line[i..];
                const heading_dup = try self.allocator.dupe(u8, heading_text);

                try self.headings.append(Heading{
                    .level = level,
                    .text = heading_dup,
                    .line_number = line_number,
                });
            }
            line_number += 1;
        }
    }

    /// Render outline in specified area
    pub fn render(self: *OutlineNavigator, x: u16, y: u16, width: u16, height: u16) !void {
        _ = x;
        _ = y;
        _ = width;
        _ = height;
        // Placeholder for outline rendering
        _ = self;
    }
};

/// Snippet manager for code snippets and templates
pub const Snippet = struct {
    allocator: std.mem.Allocator,
    snippets: std.StringHashMap(SnippetItem),

    pub const SnippetItem = struct {
        name: []const u8,
        description: []const u8,
        content: []const u8,
        trigger: []const u8,
        language: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) !Snippet {
        return Snippet{
            .allocator = allocator,
            .snippets = std.StringHashMap(SnippetItem).init(allocator),
        };
    }

    pub fn deinit(self: *Snippet) void {
        var it = self.snippets.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.name);
            self.allocator.free(entry.value_ptr.description);
            self.allocator.free(entry.value_ptr.content);
            self.allocator.free(entry.value_ptr.trigger);
            self.allocator.free(entry.value_ptr.language);
        }
        self.snippets.deinit();
    }

    /// Add a snippet
    pub fn addSnippet(self: *Snippet, snippet: Snippet) !void {
        const key_dup = try self.allocator.dupe(u8, snippet.trigger);
        try self.snippets.put(key_dup, snippet);
    }

    /// Get snippet by trigger
    pub fn getSnippet(self: *Snippet, trigger: []const u8) ?Snippet {
        return self.snippets.get(trigger);
    }
};

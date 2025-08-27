//! Interactive Markdown Preview and Editing System
//! Provides a split-screen editor with live preview, syntax highlighting,
//! and advanced editing features for markdown documents

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// Import TUI components
const SplitPane = @import("tui_shared").widgets.core.SplitPane;
const TextInput = @import("tui_shared").widgets.core.TextInput;
const Bounds = @import("tui_shared").Bounds;
const term_caps = @import("term_shared").caps;
const term_input = @import("term_shared").input.unified_input;
const mouse_mod = @import("tui_shared").input.mouse;
const focus_mod = @import("tui_shared").input.focus;

// Import markdown renderer
const MarkdownRenderer = @import("render_shared").MarkdownRenderer;
const MarkdownOptions = @import("render_shared").MarkdownOptions;

// Import terminal utilities
const ansi = @import("term_shared").ansi.color;
const clipboard = @import("term_shared").ansi.clipboard;

/// Configuration for the interactive markdown editor
pub const EditorConfig = struct {
    /// Initial split position (0.0 to 1.0)
    split_position: f32 = 0.5,
    /// Show line numbers in editor
    show_line_numbers: bool = true,
    /// Enable syntax highlighting in editor
    syntax_highlight: bool = true,
    /// Auto-save interval in seconds (0 = disabled)
    auto_save_interval: u32 = 30,
    /// Word wrap in preview
    word_wrap: bool = true,
    /// Maximum preview width
    max_preview_width: usize = 80,
    /// Enable mouse support
    enable_mouse: bool = true,
    /// Enable hyperlinks in preview
    enable_hyperlinks: bool = true,
    /// Theme for syntax highlighting
    theme: []const u8 = "default",
};

/// State of the interactive markdown editor
pub const EditorState = struct {
    /// Current markdown content
    content: ArrayList(u8),
    /// Cursor position in editor
    cursor_pos: usize,
    /// Current file path (null for untitled)
    file_path: ?[]const u8,
    /// Whether content has unsaved changes
    dirty: bool,
    /// Last saved content hash for change detection
    last_saved_hash: u64,
    /// Current scroll position in preview
    preview_scroll: usize,
    /// Table of contents entries
    toc_entries: ArrayList(TableOfContentsEntry),
    /// Search results
    search_results: ArrayList(SearchResult),
    /// Current search query
    search_query: ?[]const u8,

    pub const TableOfContentsEntry = struct {
        level: u8,
        text: []const u8,
        line_number: usize,
        anchor: []const u8,
    };

    pub const SearchResult = struct {
        line_number: usize,
        column_start: usize,
        column_end: usize,
        match_text: []const u8,
    };

    pub fn init(allocator: Allocator) EditorState {
        return EditorState{
            .content = ArrayList(u8).init(allocator),
            .cursor_pos = 0,
            .file_path = null,
            .dirty = false,
            .last_saved_hash = 0,
            .preview_scroll = 0,
            .toc_entries = ArrayList(TableOfContentsEntry).init(allocator),
            .search_results = ArrayList(SearchResult).init(allocator),
            .search_query = null,
        };
    }

    pub fn deinit(self: *EditorState) void {
        self.content.deinit();
        if (self.file_path) |path| {
            self.content.allocator.free(path);
        }
        if (self.search_query) |query| {
            self.content.allocator.free(query);
        }
        for (self.toc_entries.items) |entry| {
            self.content.allocator.free(entry.text);
            self.content.allocator.free(entry.anchor);
        }
        self.toc_entries.deinit();
        for (self.search_results.items) |result| {
            self.content.allocator.free(result.match_text);
        }
        self.search_results.deinit();
    }
};

/// Interactive Markdown Editor with live preview
pub const InteractiveMarkdownEditor = struct {
    allocator: Allocator,
    config: EditorConfig,
    state: EditorState,

    // UI Components
    split_pane: *SplitPane,
    editor_pane: *MarkdownEditorPane,
    preview_pane: *MarkdownPreviewPane,

    // Terminal capabilities
    caps: term_caps.TermCaps,

    // Focus management
    focus_manager: ?*focus_mod.FocusManager,

    // Mouse controller
    mouse_controller: ?*mouse_mod.Mouse,

    // Update timer for live preview
    last_update_time: i64,
    update_interval_ms: u32,

    const Self = @This();

    /// Initialize the interactive markdown editor
    pub fn init(
        allocator: Allocator,
        bounds: Bounds,
        config: EditorConfig,
        caps: term_caps.TermCaps,
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Initialize state
        const state = EditorState.init(allocator);

        // Create split pane
        const split_pane = try SplitPane.init(allocator, bounds, .{
            .orientation = .horizontal,
            .split_position = config.split_position,
            .min_pane_size = 20,
        });
        errdefer split_pane.deinit();

        // Create editor pane
        const editor_pane = try MarkdownEditorPane.init(allocator, split_pane.first_bounds, caps, config);
        errdefer editor_pane.deinit();

        // Create preview pane
        const preview_pane = try MarkdownPreviewPane.init(allocator, split_pane.second_bounds, caps, config);
        errdefer preview_pane.deinit();

        // Set up pane content
        split_pane.setFirstPane(editor_pane.toPaneContent());
        split_pane.setSecondPane(preview_pane.toPaneContent());

        self.* = .{
            .allocator = allocator,
            .config = config,
            .state = state,
            .split_pane = split_pane,
            .editor_pane = editor_pane,
            .preview_pane = preview_pane,
            .caps = caps,
            .focus_manager = null,
            .mouse_controller = null,
            .last_update_time = std.time.milliTimestamp(),
            .update_interval_ms = 500, // Update preview every 500ms
        };

        return self;
    }

    /// Deinitialize the editor
    pub fn deinit(self: *Self) void {
        self.state.deinit();
        self.split_pane.deinit();
        self.editor_pane.deinit();
        self.preview_pane.deinit();
        self.allocator.destroy(self);
    }

    /// Load content from file
    pub fn loadFile(self: *Self, file_path: []const u8) !void {
        const content = try std.fs.cwd().readFileAlloc(self.allocator, file_path, std.math.maxInt(usize));
        defer self.allocator.free(content);

        try self.state.content.appendSlice(content);
        self.state.file_path = try self.allocator.dupe(u8, file_path);
        self.state.dirty = false;
        self.state.last_saved_hash = std.hash.Wyhash.hash(0, content);

        // Update editor content
        try self.editor_pane.setContent(content);

        // Update preview
        try self.updatePreview();

        // Generate table of contents
        try self.generateTableOfContents();
    }

    /// Save content to file
    pub fn saveFile(self: *Self, file_path: ?[]const u8) !void {
        const path = file_path orelse self.state.file_path orelse return error.NoFilePath;

        try std.fs.cwd().writeFile(.{
            .sub_path = path,
            .data = self.state.content.items,
        });

        self.state.file_path = try self.allocator.dupe(u8, path);
        self.state.dirty = false;
        self.state.last_saved_hash = std.hash.Wyhash.hash(0, self.state.content.items);
    }

    /// Set editor content
    pub fn setContent(self: *Self, content: []const u8) !void {
        self.state.content.clearAndFree();
        try self.state.content.appendSlice(content);
        self.state.dirty = true;

        try self.editor_pane.setContent(content);
        try self.updatePreview();
        try self.generateTableOfContents();
    }

    /// Get current content
    pub fn getContent(self: *Self) []const u8 {
        return self.state.content.items;
    }

    /// Update the preview pane with current content
    pub fn updatePreview(self: *Self) !void {
        const content = self.state.content.items;
        try self.preview_pane.setContent(content);
    }

    /// Generate table of contents from headings
    pub fn generateTableOfContents(self: *Self) !void {
        // Clear existing entries
        for (self.state.toc_entries.items) |entry| {
            self.allocator.free(entry.text);
            self.allocator.free(entry.anchor);
        }
        self.state.toc_entries.clearAndFree();

        const content = self.state.content.items;
        var lines = std.mem.tokenize(u8, content, "\n");
        var line_number: usize = 1;

        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "#")) {
                // Count leading # characters
                var level: u8 = 0;
                var i: usize = 0;
                while (i < line.len and line[i] == '#' and level < 6) : (i += 1) {
                    level += 1;
                }

                if (level > 0 and i < line.len and line[i] == ' ') {
                    const heading_text = std.mem.trim(u8, line[i..], " \t");
                    if (heading_text.len > 0) {
                        // Create anchor from heading text
                        const anchor = try self.createAnchor(heading_text);

                        try self.state.toc_entries.append(.{
                            .level = level,
                            .text = try self.allocator.dupe(u8, heading_text),
                            .line_number = line_number,
                            .anchor = anchor,
                        });
                    }
                }
            }
            line_number += 1;
        }
    }

    /// Create URL-safe anchor from heading text
    fn createAnchor(self: *Self, text: []const u8) ![]const u8 {
        var anchor = ArrayList(u8).init(self.allocator);
        defer anchor.deinit();

        for (text) |c| {
            const lower_c = std.ascii.toLower(c);
            if (std.ascii.isAlphanumeric(lower_c)) {
                try anchor.append(lower_c);
            } else if (lower_c == ' ') {
                try anchor.append('-');
            }
            // Skip other characters
        }

        return anchor.toOwnedSlice();
    }

    /// Search for text in content
    pub fn search(self: *Self, query: []const u8) !void {
        // Clear previous results
        for (self.state.search_results.items) |result| {
            self.allocator.free(result.match_text);
        }
        self.state.search_results.clearAndFree();

        if (self.state.search_query) |old_query| {
            self.allocator.free(old_query);
        }
        self.state.search_query = try self.allocator.dupe(u8, query);

        if (query.len == 0) return;

        const content = self.state.content.items;
        var lines = std.mem.tokenize(u8, content, "\n");
        var line_number: usize = 1;

        while (lines.next()) |line| {
            var start: usize = 0;
            while (std.mem.indexOf(u8, line[start..], query)) |index| {
                const match_start = start + index;
                const match_end = match_start + query.len;

                try self.state.search_results.append(.{
                    .line_number = line_number,
                    .column_start = match_start,
                    .column_end = match_end,
                    .match_text = try self.allocator.dupe(u8, line[match_start..match_end]),
                });

                start = match_end;
            }
            line_number += 1;
        }
    }

    /// Export content to various formats
    pub fn exportTo(self: *Self, format: ExportFormat, output_path: []const u8) !void {
        const content = self.state.content.items;

        switch (format) {
            .html => try self.exportToHtml(content, output_path),
            .pdf => try self.exportToPdf(content, output_path),
            .clipboard => try self.exportToClipboard(content),
        }
    }

    /// Export to HTML with embedded styles
    fn exportToHtml(self: *Self, content: []const u8, output_path: []const u8) !void {
        _ = self; // Self not used in this implementation
        var html_file = try std.fs.cwd().createFile(output_path, .{});
        defer html_file.close();

        const writer = html_file.writer();

        try writer.writeAll("<!DOCTYPE html>\n<html>\n<head>\n");
        try writer.writeAll("<meta charset=\"utf-8\">\n");
        try writer.writeAll("<title>Markdown Document</title>\n");
        try writer.writeAll("<style>\n");
        try writer.writeAll("body { font-family: Arial, sans-serif; margin: 40px; }\n");
        try writer.writeAll("h1, h2, h3, h4, h5, h6 { color: #333; margin-top: 24px; }\n");
        try writer.writeAll("code { background: #f4f4f4; padding: 2px 4px; border-radius: 3px; }\n");
        try writer.writeAll("pre { background: #f4f4f4; padding: 16px; border-radius: 3px; overflow-x: auto; }\n");
        try writer.writeAll("blockquote { border-left: 4px solid #ddd; margin: 0; padding-left: 16px; color: #666; }\n");
        try writer.writeAll("table { border-collapse: collapse; width: 100%; }\n");
        try writer.writeAll("th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }\n");
        try writer.writeAll("th { background-color: #f2f2f2; }\n");
        try writer.writeAll("</style>\n");
        try writer.writeAll("</head>\n<body>\n");

        // Convert markdown to HTML (simplified)
        var lines = std.mem.tokenize(u8, content, "\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "#")) {
                var level: u8 = 0;
                var i: usize = 0;
                while (i < line.len and line[i] == '#' and level < 6) : (i += 1) {
                    level += 1;
                }
                if (level > 0 and i < line.len and line[i] == ' ') {
                    const heading_text = std.mem.trim(u8, line[i..], " \t");
                    try writer.print("<h{d}>{s}</h{d}>\n", .{ level, std.html.escape.escapeText(heading_text, writer) });
                }
            } else if (std.mem.trim(u8, line, " \t").len == 0) {
                try writer.writeAll("<br>\n");
            } else {
                try writer.print("<p>{s}</p>\n", .{std.html.escape.escapeText(line, writer)});
            }
        }

        try writer.writeAll("</body>\n</html>\n");
    }

    /// Export to PDF (placeholder - would need external tool)
    fn exportToPdf(self: *Self, content: []const u8, output_path: []const u8) !void {
        // TODO: Implement PDF export using external tool like pandoc or wkhtmltopdf
        _ = self; // Self not used in this placeholder implementation
        _ = content;
        _ = output_path;
        return error.NotImplemented;
    }

    /// Copy formatted text to clipboard
    fn exportToClipboard(self: *Self, content: []const u8) !void {
        try clipboard.setClipboard(content, self.caps);
    }

    /// Get document statistics
    pub fn getDocumentStats(self: *Self) DocumentStats {
        const content = self.state.content.items;
        var lines: usize = 0;
        var words: usize = 0;
        const chars: usize = content.len;

        var line_iter = std.mem.tokenize(u8, content, "\n");
        while (line_iter.next()) |_| {
            lines += 1;
        }

        var word_iter = std.mem.tokenize(u8, content, " \t\n\r");
        while (word_iter.next()) |_| {
            words += 1;
        }

        // Estimate reading time (200 words per minute)
        const reading_time_minutes = @as(f32, @floatFromInt(words)) / 200.0;

        return DocumentStats{
            .lines = lines,
            .words = words,
            .characters = chars,
            .reading_time_minutes = reading_time_minutes,
            .headings = self.state.toc_entries.items.len,
        };
    }

    /// Handle keyboard input
    pub fn handleKeyEvent(self: *Self, event: term_input.KeyEvent) !bool {
        // Handle global shortcuts
        if (event.modifiers.ctrl) {
            switch (event.key) {
                .char => |c| switch (c) {
                    's' => {
                        // Save file
                        try self.saveFile(null);
                        return true;
                    },
                    'o' => {
                        // Open file (would need file picker)
                        return true;
                    },
                    'f' => {
                        // Find
                        return true;
                    },
                    'e' => {
                        // Export
                        return true;
                    },
                    'q' => {
                        // Quit
                        return true;
                    },
                    else => {},
                },
                else => {},
            }
        }

        // Handle Alt+arrows for split resizing
        if (event.modifiers.alt) {
            switch (event.key) {
                .arrow_left => {
                    if (self.split_pane.orientation.isHorizontal()) {
                        self.split_pane.split_position = std.math.max(0.1, self.split_pane.split_position - 0.05);
                        try self.split_pane.updateLayout();
                        return true;
                    }
                },
                .arrow_right => {
                    if (self.split_pane.orientation.isHorizontal()) {
                        self.split_pane.split_position = std.math.min(0.9, self.split_pane.split_position + 0.05);
                        try self.split_pane.updateLayout();
                        return true;
                    }
                },
                else => {},
            }
        }

        // Pass to split pane
        return try self.split_pane.handleKeyEvent(event);
    }

    /// Handle mouse events
    pub fn handleMouseEvent(self: *Self, event: mouse_mod.MouseEvent) !bool {
        return try self.split_pane.handleMouseEvent(event);
    }

    /// Render the editor
    pub fn render(self: *Self) !void {
        // Check if preview needs updating
        const current_time = std.time.milliTimestamp();
        if (current_time - self.last_update_time > self.update_interval_ms) {
            if (self.state.dirty) {
                try self.updatePreview();
                self.state.dirty = false;
            }
            self.last_update_time = current_time;
        }

        try self.split_pane.render(std.io.getStdOut().writer());
    }

    /// Run the interactive editor
    pub fn run(self: *Self) !void {
        // Main event loop would go here
        // For now, just render once
        try self.render();
    }
};

/// Export format options
pub const ExportFormat = enum {
    html,
    pdf,
    clipboard,
};

/// Document statistics
pub const DocumentStats = struct {
    lines: usize,
    words: usize,
    characters: usize,
    reading_time_minutes: f32,
    headings: usize,
};

/// Markdown Editor Pane - handles text editing with markdown features
pub const MarkdownEditorPane = struct {
    allocator: Allocator,
    bounds: Bounds,
    text_input: TextInput,
    caps: term_caps.TermCaps,
    config: EditorConfig,
    line_numbers: ArrayList(u8),
    syntax_highlight_buffer: ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: Allocator, bounds: Bounds, caps: term_caps.TermCaps, config: EditorConfig) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .bounds = bounds,
            .text_input = TextInput.init(allocator, bounds, caps),
            .caps = caps,
            .config = config,
            .line_numbers = ArrayList(u8).init(allocator),
            .syntax_highlight_buffer = ArrayList(u8).init(allocator),
        };

        self.text_input.setMultiline(true);
        self.text_input.setMaxLength(null); // No limit

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.text_input.deinit();
        self.line_numbers.deinit();
        self.syntax_highlight_buffer.deinit();
        self.allocator.destroy(self);
    }

    pub fn setContent(self: *Self, content: []const u8) !void {
        try self.text_input.setText(content);
        try self.updateLineNumbers();
        try self.updateSyntaxHighlighting();
    }

    pub fn getContent(self: *Self) []const u8 {
        return self.text_input.getText();
    }

    pub fn toPaneContent(self: *Self) SplitPane.PaneContent {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn updateLineNumbers(self: *Self) !void {
        if (!self.config.show_line_numbers) return;

        self.line_numbers.clearAndFree();
        const content = self.text_input.getText();
        var line_count: usize = 1;

        // Count lines
        for (content) |c| {
            if (c == '\n') line_count += 1;
        }

        // Generate line number strings
        var buf: [32]u8 = undefined;
        for (1..line_count + 1) |i| {
            const line_str = std.fmt.bufPrint(&buf, "{d:4} │ ", .{i}) catch continue;
            try self.line_numbers.appendSlice(line_str);
            if (i < line_count) {
                try self.line_numbers.append('\n');
            }
        }
    }

    fn updateSyntaxHighlighting(self: *Self) !void {
        if (!self.config.syntax_highlight) return;

        self.syntax_highlight_buffer.clearAndFree();
        const content = self.text_input.getText();

        // Simple syntax highlighting for markdown
        var i: usize = 0;
        while (i < content.len) {
            const c = content[i];
            switch (c) {
                '#' => {
                    // Headings
                    try self.syntax_highlight_buffer.appendSlice("\x1b[1;34m"); // Bold blue
                    while (i < content.len and content[i] != '\n' and content[i] != ' ') {
                        try self.syntax_highlight_buffer.append(content[i]);
                        i += 1;
                    }
                    try self.syntax_highlight_buffer.appendSlice("\x1b[0m"); // Reset
                },
                '*' => {
                    // Bold/italic
                    try self.syntax_highlight_buffer.appendSlice("\x1b[1m"); // Bold
                    try self.syntax_highlight_buffer.append(c);
                    i += 1;
                    try self.syntax_highlight_buffer.appendSlice("\x1b[0m");
                },
                '`' => {
                    // Code
                    try self.syntax_highlight_buffer.appendSlice("\x1b[32m"); // Green
                    try self.syntax_highlight_buffer.append(c);
                    i += 1;
                    try self.syntax_highlight_buffer.appendSlice("\x1b[0m");
                },
                '[' => {
                    // Links
                    try self.syntax_highlight_buffer.appendSlice("\x1b[34m"); // Blue
                    while (i < content.len and content[i] != ']') {
                        try self.syntax_highlight_buffer.append(content[i]);
                        i += 1;
                    }
                    if (i < content.len) {
                        try self.syntax_highlight_buffer.append(content[i]); // ]
                        i += 1;
                    }
                    try self.syntax_highlight_buffer.appendSlice("\x1b[0m");
                },
                else => {
                    try self.syntax_highlight_buffer.append(c);
                    i += 1;
                },
            }
        }
    }

    const vtable = SplitPane.PaneContent.VTable{
        .render = struct {
            fn render(ptr: *anyopaque, bounds: Bounds) anyerror!void {
                const self = @as(*MarkdownEditorPane, @ptrCast(@alignCast(ptr)));
                self.bounds = bounds;
                try self.renderEditor();
            }
        }.render,

        .handleKeyEvent = struct {
            fn handleKeyEvent(ptr: *anyopaque, event: term_input.KeyEvent) anyerror!bool {
                const self = @as(*MarkdownEditorPane, @ptrCast(@alignCast(ptr)));
                return self.handleKeyEvent(event);
            }
        }.handleKeyEvent,

        .handleMouseEvent = struct {
            fn handleMouseEvent(ptr: *anyopaque, event: mouse_mod.MouseEvent) anyerror!bool {
                const self = @as(*MarkdownEditorPane, @ptrCast(@alignCast(ptr)));
                return self.handleMouseEvent(event);
            }
        }.handleMouseEvent,

        .onFocus = struct {
            fn onFocus(ptr: *anyopaque) void {
                const self = @as(*MarkdownEditorPane, @ptrCast(@alignCast(ptr)));
                self.text_input.focus();
            }
        }.onFocus,

        .onBlur = struct {
            fn onBlur(ptr: *anyopaque) void {
                const self = @as(*MarkdownEditorPane, @ptrCast(@alignCast(ptr)));
                self.text_input.blur();
            }
        }.onBlur,

        .deinit = struct {
            fn deinit(ptr: *anyopaque) void {
                const self = @as(*MarkdownEditorPane, @ptrCast(@alignCast(ptr)));
                self.deinit();
            }
        }.deinit,
    };

    fn renderEditor(self: *Self) !void {
        const writer = std.io.getStdOut().writer();

        // Clear pane
        try writer.print("\x1b[{}H\x1b[{}J", .{ self.bounds.y + 1, self.bounds.x + 1 });

        // Render line numbers if enabled
        if (self.config.show_line_numbers) {
            try self.renderLineNumbers();
        }

        // Render text input
        self.text_input.draw();

        // Render syntax highlighting overlay if enabled
        if (self.config.syntax_highlight) {
            try self.renderSyntaxHighlighting();
        }
    }

    fn renderLineNumbers(self: *Self) !void {
        const writer = std.io.getStdOut().writer();
        // const line_num_width = 6; // " 123 │ " - reserved for future use

        var y = self.bounds.y;
        var line_iter = std.mem.tokenize(u8, self.line_numbers.items, "\n");

        while (line_iter.next()) |line_num| {
            try writer.print("\x1b[{};{}H\x1b[90m{s}\x1b[0m", .{
                y + 1,
                self.bounds.x + 1,
                line_num,
            });
            y += 1;
            if (y >= self.bounds.y + self.bounds.height) break;
        }
    }

    fn renderSyntaxHighlighting(self: *Self) !void {
        // This would overlay syntax highlighting on top of the text
        // Implementation would depend on terminal capabilities
        _ = self;
    }

    fn handleKeyEvent(self: *Self, event: term_input.KeyEvent) !bool {
        // Handle editor-specific shortcuts
        if (event.modifiers.ctrl) {
            switch (event.key) {
                .char => |c| switch (c) {
                    'b' => {
                        // Insert bold formatting
                        try self.insertMarkdownFormatting("**", "**");
                        return true;
                    },
                    'i' => {
                        // Insert italic formatting
                        try self.insertMarkdownFormatting("*", "*");
                        return true;
                    },
                    'k' => {
                        // Insert code formatting
                        try self.insertMarkdownFormatting("`", "`");
                        return true;
                    },
                    'l' => {
                        // Insert link
                        try self.insertMarkdownFormatting("[", "](url)");
                        return true;
                    },
                    else => {},
                },
                else => {},
            }
        }

        // Handle Tab for indentation
        if (event.key == .tab) {
            if (event.modifiers.shift) {
                try self.unindentLine();
            } else {
                try self.indentLine();
            }
            return true;
        }

        // Pass to text input
        return false; // Let text input handle the event
    }

    fn handleMouseEvent(self: *Self, event: mouse_mod.MouseEvent) !bool {
        // Handle mouse events in editor pane
        _ = self;
        _ = event;
        return false;
    }

    fn insertMarkdownFormatting(self: *Self, before: []const u8, after: []const u8) !void {
        const content = self.text_input.getText();
        const cursor_pos = self.text_input.cursorPos;

        // Insert formatting around cursor or selection
        var new_content = ArrayList(u8).init(self.allocator);
        defer new_content.deinit();

        try new_content.appendSlice(content[0..cursor_pos]);
        try new_content.appendSlice(before);
        try new_content.appendSlice(content[cursor_pos..]);
        try new_content.appendSlice(after);

        try self.text_input.setText(new_content.items);
        self.text_input.cursorPos = cursor_pos + before.len;
    }

    fn indentLine(self: *Self) !void {
        // Add 4 spaces at the beginning of current line
        _ = self;
    }

    fn unindentLine(self: *Self) !void {
        // Remove up to 4 spaces from beginning of current line
        _ = self;
    }
};

/// Markdown Preview Pane - renders live markdown preview
pub const MarkdownPreviewPane = struct {
    allocator: Allocator,
    bounds: Bounds,
    renderer: MarkdownRenderer,
    rendered_content: ArrayList(u8),
    scroll_offset: usize,
    caps: term_caps.TermCaps,
    config: EditorConfig,

    const Self = @This();

    pub fn init(allocator: Allocator, bounds: Bounds, caps: term_caps.TermCaps, config: EditorConfig) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const options = MarkdownOptions{
            .max_width = config.max_preview_width,
            .color_enabled = caps.supportsColor(),
            .enable_hyperlinks = config.enable_hyperlinks and caps.supportsOSC8(),
            .enable_syntax_highlight = true,
            .show_line_numbers = false,
        };

        self.* = .{
            .allocator = allocator,
            .bounds = bounds,
            .renderer = MarkdownRenderer.init(allocator, options),
            .rendered_content = ArrayList(u8).init(allocator),
            .scroll_offset = 0,
            .caps = caps,
            .config = config,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.renderer.deinit();
        self.rendered_content.deinit();
        self.allocator.destroy(self);
    }

    pub fn setContent(self: *Self, content: []const u8) !void {
        self.rendered_content.clearAndFree();
        try self.renderer.renderMarkdown(content);
        const rendered = try self.renderer.getRenderedContent();
        try self.rendered_content.appendSlice(rendered);
    }

    pub fn toPaneContent(self: *Self) SplitPane.PaneContent {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable = SplitPane.PaneContent.VTable{
        .render = struct {
            fn render(ptr: *anyopaque, bounds: Bounds) anyerror!void {
                const self = @as(*MarkdownPreviewPane, @ptrCast(@alignCast(ptr)));
                self.bounds = bounds;
                try self.renderPreview();
            }
        }.render,

        .handleKeyEvent = struct {
            fn handleKeyEvent(ptr: *anyopaque, event: term_input.KeyEvent) anyerror!bool {
                const self = @as(*MarkdownPreviewPane, @ptrCast(@alignCast(ptr)));
                return self.handleKeyEvent(event);
            }
        }.handleKeyEvent,

        .handleMouseEvent = struct {
            fn handleMouseEvent(ptr: *anyopaque, event: mouse_mod.MouseEvent) anyerror!bool {
                const self = @as(*MarkdownPreviewPane, @ptrCast(@alignCast(ptr)));
                return self.handleMouseEvent(event);
            }
        }.handleMouseEvent,

        .onFocus = struct {
            fn onFocus(ptr: *anyopaque) void {
                _ = ptr;
            }
        }.onFocus,

        .onBlur = struct {
            fn onBlur(ptr: *anyopaque) void {
                _ = ptr;
            }
        }.onBlur,

        .deinit = struct {
            fn deinit(ptr: *anyopaque) void {
                const self = @as(*MarkdownPreviewPane, @ptrCast(@alignCast(ptr)));
                self.deinit();
            }
        }.deinit,
    };

    fn renderPreview(self: *Self) !void {
        const writer = std.io.getStdOut().writer();

        // Clear pane
        try writer.print("\x1b[{}H\x1b[{}J", .{ self.bounds.y + 1, self.bounds.x + 1 });

        // Render title
        try writer.print("\x1b[{};{}H\x1b[1;34mMarkdown Preview\x1b[0m", .{
            self.bounds.y + 1,
            self.bounds.x + 2,
        });

        // Render content with scrolling
        const content_height = self.bounds.height - 2; // Account for title
        const lines = std.mem.tokenize(u8, self.rendered_content.items, "\n");

        var y = self.bounds.y + 2;
        const line_index: usize = self.scroll_offset;

        var current_line: usize = 0;
        while (lines.next()) |line| {
            if (current_line >= line_index) {
                if (y >= self.bounds.y + self.bounds.height) break;

                // Truncate line if too long
                const max_line_len = self.bounds.width - 2;
                const display_line = if (line.len > max_line_len)
                    line[0..max_line_len]
                else
                    line;

                try writer.print("\x1b[{};{}H{s}", .{
                    y + 1,
                    self.bounds.x + 2,
                    display_line,
                });
                y += 1;
            }
            current_line += 1;
        }

        // Render scroll indicators if needed
        if (self.scroll_offset > 0) {
            try writer.print("\x1b[{};{}H\x1b[90m↑\x1b[0m", .{
                self.bounds.y + 2,
                self.bounds.x + self.bounds.width - 1,
            });
        }

        const total_lines = std.mem.count(u8, self.rendered_content.items, "\n") + 1;
        if (self.scroll_offset + content_height < total_lines) {
            try writer.print("\x1b[{};{}H\x1b[90m↓\x1b[0m", .{
                self.bounds.y + self.bounds.height - 1,
                self.bounds.x + self.bounds.width - 1,
            });
        }
    }

    fn handleKeyEvent(self: *Self, event: term_input.KeyEvent) !bool {
        const content_height = self.bounds.height - 2;
        const total_lines = std.mem.count(u8, self.rendered_content.items, "\n") + 1;

        switch (event.key) {
            .arrow_up => {
                if (self.scroll_offset > 0) {
                    self.scroll_offset -= 1;
                    return true;
                }
            },
            .arrow_down => {
                if (self.scroll_offset + content_height < total_lines) {
                    self.scroll_offset += 1;
                    return true;
                }
            },
            .page_up => {
                self.scroll_offset = std.math.max(0, self.scroll_offset -| content_height);
                return true;
            },
            .page_down => {
                self.scroll_offset = std.math.min(
                    total_lines -| content_height,
                    self.scroll_offset + content_height,
                );
                return true;
            },
            .home => {
                self.scroll_offset = 0;
                return true;
            },
            .end => {
                self.scroll_offset = total_lines -| content_height;
                return true;
            },
            else => {},
        }

        return false;
    }

    fn handleMouseEvent(self: *Self, event: mouse_mod.MouseEvent) !bool {
        // Handle mouse wheel for scrolling
        if (event.mouse.action == .scroll) {
            const delta = if (event.mouse.button == .wheel_up) -3 else 3;
            const new_offset = @as(i32, @intCast(self.scroll_offset)) + delta;
            self.scroll_offset = std.math.max(0, @as(usize, @intCast(std.math.max(0, new_offset))));
            return true;
        }

        return false;
    }
};

/// Launch the interactive markdown editor
pub fn launchInteractiveEditor(
    allocator: Allocator,
    file_path: ?[]const u8,
    config: EditorConfig,
) !void {
    // Get terminal capabilities
    const caps = term_caps.detect();

    // Get terminal size
    const term_size = try term_caps.getTerminalSize();
    const bounds = Bounds.init(0, 0, term_size.width, term_size.height);

    // Create editor
    const editor = try InteractiveMarkdownEditor.init(allocator, bounds, config, caps);
    defer editor.deinit();

    // Load file if provided
    if (file_path) |path| {
        try editor.loadFile(path);
    }

    // Run the editor
    try editor.run();
}

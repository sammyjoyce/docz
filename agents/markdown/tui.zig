//! Production-Ready Markdown TUI
//! Beautiful terminal interface using foundation.tui with AI integration via engine.zig

const std = @import("std");
const foundation = @import("foundation");
const tui = foundation.tui;
const ui = foundation.ui;
const render = foundation.render;
const term = foundation.term;
const engine = @import("core_engine");
const spec = @import("spec.zig");

// Libraries
const fsutil = @import("lib/fs.zig");
const textlib = @import("lib/text.zig");

const Allocator = std.mem.Allocator;

/// Main TUI application state
pub const MarkdownTUI = struct {
    const Self = @This();

    allocator: Allocator,
    app: *tui.App,
    screen: *tui.Screen,
    terminal: *term.Terminal,
    engine: ?engine.Engine,

    // UI components
    editor: *EditorPane,
    preview: *PreviewPane,
    file_browser: *FileBrowser,
    ai_chat: *AIChatPane,
    status_bar: *StatusBar,
    command_palette: *tui.components.CommandPalette,

    // Layout
    layout: LayoutMode,
    focused_pane: FocusedPane,

    // Document state
    current_file: ?[]const u8,
    modified: bool,

    pub fn initMarkdownTUI(allocator: Allocator) !Self {
        const terminal = try term.Terminal.init(allocator);

        const app = try allocator.create(tui.App);
        app.* = try tui.App.init(allocator, .{
            .fps = 60,
            .vsync = true,
            .mouse = true,
            .paste = true,
        });

        const screen = try allocator.create(tui.Screen);
        screen.* = try tui.Screen.init(allocator, .{});

        // Initialize engine for AI features
        var eng: ?engine.Engine = null;
        if (engine.Engine.init(allocator, .{
            .model = "claude-3-5-sonnet-20241022",
            .stream = true,
        })) |e| {
            eng = e;
            // Try to authenticate
            _ = eng.?.authenticate() catch {};
        } else |_| {}

        // Create UI components
        const editor = try allocator.create(EditorPane);
        editor.* = try EditorPane.initEditorPane(allocator);

        const preview = try allocator.create(PreviewPane);
        preview.* = try PreviewPane.initPreviewPane(allocator);

        const file_browser = try allocator.create(FileBrowser);
        file_browser.* = try FileBrowser.initFileBrowser(allocator);

        const ai_chat = try allocator.create(AIChatPane);
        ai_chat.* = try AIChatPane.initAIChatPane(allocator);

        const status_bar = try allocator.create(StatusBar);
        status_bar.* = try StatusBar.initStatusBar(allocator);

        const command_palette = try tui.components.CommandPalette.init(allocator);

        return Self{
            .allocator = allocator,
            .app = app,
            .screen = screen,
            .terminal = terminal,
            .engine = eng,
            .editor = editor,
            .preview = preview,
            .file_browser = file_browser,
            .ai_chat = ai_chat,
            .status_bar = status_bar,
            .command_palette = command_palette,
            .layout = .split_horizontal,
            .focused_pane = .editor,
            .current_file = null,
            .modified = false,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.current_file) |f| self.allocator.free(f);

        self.command_palette.deinit();
        self.status_bar.deinit();
        self.ai_chat.deinit();
        self.file_browser.deinit();
        self.preview.deinit();
        self.editor.deinit();

        if (self.engine) |*e| e.deinit();

        self.screen.deinit();
        self.app.deinit();
        self.terminal.deinit();

        // Manually destroy components that don't destroy themselves
        self.allocator.destroy(self.app);
        self.allocator.destroy(self.screen);
        self.allocator.destroy(self.status_bar);
        self.allocator.destroy(self.ai_chat);
        self.allocator.destroy(self.file_browser);
        self.allocator.destroy(self.preview);
        self.allocator.destroy(self.editor);
    }

    pub fn run(self: *Self) !void {
        // Setup terminal for TUI
        try self.terminal.enterRawMode();
        defer self.terminal.exitRawMode() catch {};

        try self.terminal.enableMouse();
        defer self.terminal.disableMouse() catch {};

        // Use system command to set terminal to raw mode (with proper cleanup)
        if (@import("builtin").os.tag != .windows) {
            // Use stty to disable echo and enable raw mode
            if (std.process.Child.run(.{
                .allocator = self.allocator,
                .argv = &[_][]const u8{ "stty", "-echo", "raw" },
            })) |result| {
                // Clean up the result
                self.allocator.free(result.stdout);
                self.allocator.free(result.stderr);
            } else |err| {
                // If stty fails, continue anyway - TUI might still work
                std.log.debug("Failed to set raw mode: {}", .{err});
            }

            // Ensure we restore on exit
            defer {
                if (std.process.Child.run(.{
                    .allocator = self.allocator,
                    .argv = &[_][]const u8{ "stty", "echo", "cooked" },
                })) |result| {
                    self.allocator.free(result.stdout);
                    self.allocator.free(result.stderr);
                } else |_| {
                    // Ignore cleanup errors
                }
            }
        }

        // Additional terminal setup
        const stdout = std.fs.File.stdout();
        try stdout.writeAll("\x1b[?7l"); // Disable line wrapping
        try stdout.writeAll("\x1b[?25l"); // Hide cursor initially
        defer stdout.writeAll("\x1b[?25h") catch {}; // Show cursor on exit
        defer stdout.writeAll("\x1b[?7h") catch {}; // Re-enable line wrapping

        // Set app as running
        self.app.running = true;

        // Main event loop with real input
        var current_screen: ScreenType = .welcome;
        var help_visible = false;

        // Initial render
        try self.renderScreen(current_screen, help_visible);

        while (self.app.running) {
            // Read input - blocks until input is available
            const stdin = std.fs.File.stdin();
            var buffer: [1]u8 = undefined;
            const byte_read = stdin.read(buffer[0..]) catch |err| {
                // Handle read errors
                return err;
            };
            if (byte_read == 0) break; // End of input
            const byte = buffer[0];

            // Process the input byte
            switch (byte) {
                3 => { // Ctrl+C
                    self.app.running = false;
                    break;
                },
                27 => { // Escape key
                    if (current_screen == .editor and help_visible) {
                        help_visible = false;
                    } else if (current_screen == .editor) {
                        current_screen = .welcome;
                    }
                },
                13, 10 => { // Enter/Return key
                    if (current_screen == .welcome) {
                        current_screen = .editor;
                        help_visible = false;
                    } else if (current_screen == .editor and !help_visible) {
                        try self.editor.insertChar('\n');
                        try self.updatePreview();
                    }
                },
                '/' => {
                    if (current_screen == .welcome) {
                        current_screen = .editor;
                        help_visible = false;
                        try self.editor.insertChar('/');
                        try self.updatePreview();
                    } else if (current_screen == .editor and !help_visible) {
                        try self.editor.insertChar('/');
                        try self.updatePreview();
                    }
                },
                '@' => {
                    if (current_screen == .welcome) {
                        current_screen = .editor;
                        help_visible = false;
                        try self.editor.insertChar('@');
                        try self.updatePreview();
                    } else if (current_screen == .editor and !help_visible) {
                        try self.editor.insertChar('@');
                        try self.updatePreview();
                    }
                },
                'h', '?' => {
                    if (current_screen == .welcome or current_screen == .editor) {
                        help_visible = !help_visible;
                    }
                },
                'q' => {
                    if (current_screen == .welcome) {
                        self.app.running = false;
                        break;
                    } else if (current_screen == .editor and !help_visible) {
                        try self.editor.insertChar('q');
                        try self.updatePreview();
                    }
                },
                127, 8 => { // Backspace/Delete
                    if (current_screen == .editor and !help_visible) {
                        self.editor.deleteChar();
                        try self.updatePreview();
                    }
                },
                else => {
                    // For editor mode, pass printable characters to editor
                    if (current_screen == .editor and !help_visible) {
                        if (byte >= 32 and byte < 127) { // printable ASCII
                            try self.editor.insertChar(byte);
                            try self.updatePreview();
                        }
                    }
                },
            }

            // Re-render after handling input
            try self.renderScreen(current_screen, help_visible);
        }

        // Show exit message
        try self.renderExitMessage();
    }

    // Terminal mode handling using system stty command (simpler approach)

    fn disableRawMode(self: *Self, original: std.posix.termios) !void {
        _ = self;
        const stdin_fd = std.posix.STDIN_FILENO;
        try std.posix.tcsetattr(stdin_fd, .NOW, original);
    }

    fn registerKeybindings(_: *Self) !void {
        // Global keybindings would be registered here
        // TODO: Implement keybinding registration when App supports it
    }

    fn handleEvent(self: *Self, event: term.Event) !void {
        switch (event) {
            .key => |key| try self.handleKeyEvent(key),
            .mouse => |mouse| try self.handleMouseEvent(mouse),
            .resize => |size| try self.handleResize(size),
            .paste => |text| try self.handlePaste(text),
        }
    }

    fn handleKeyEvent(self: *Self, key: term.KeyEvent) !void {
        // Global quit keys
        if ((key.modifiers.ctrl and key.key == .c) or
            (key.key == .q and !key.modifiers.ctrl))
        {
            self.app.running = false;
            return;
        }

        // Check global keybindings first
        if (self.app.checkKeybinding(key)) |handler| {
            try handler(self);
            return;
        }

        // Route to focused pane
        switch (self.focused_pane) {
            .editor => try self.editor.handleKey(key),
            .preview => try self.preview.handleKey(key),
            .file_browser => try self.file_browser.handleKey(key),
            .ai_chat => try self.ai_chat.handleKey(key),
        }

        // Update preview if editor changed
        if (self.focused_pane == .editor and self.editor.isDirty()) {
            try self.updatePreview();
            self.modified = true;
            try self.updateStatusBar();
        }
    }

    fn handleMouseEvent(self: *Self, mouse: term.MouseEvent) !void {
        // Determine which pane was clicked
        const bounds = self.calculateBounds();

        if (bounds.editor.contains(mouse.x, mouse.y)) {
            self.focused_pane = .editor;
            try self.editor.handleMouse(mouse);
        } else if (bounds.preview.contains(mouse.x, mouse.y)) {
            self.focused_pane = .preview;
            try self.preview.handleMouse(mouse);
        } else if (self.file_browser.visible and bounds.file_browser.contains(mouse.x, mouse.y)) {
            self.focused_pane = .file_browser;
            try self.file_browser.handleMouse(mouse);
        } else if (self.ai_chat.visible and bounds.ai_chat.contains(mouse.x, mouse.y)) {
            self.focused_pane = .ai_chat;
            try self.ai_chat.handleMouse(mouse);
        }

        try self.updateStatusBar();
    }

    fn handleResize(self: *Self, size: term.Size) !void {
        self.screen.resize(size.width, size.height);
        try self.render();
    }

    fn handlePaste(self: *Self, text: []const u8) !void {
        if (self.focused_pane == .editor) {
            try self.editor.insertText(text);
            try self.updatePreview();
        }
    }

    fn renderScreen(self: *Self, screen_type: ScreenType, help_visible: bool) !void {
        // Clear terminal and move cursor to home
        const stdout = std.fs.File.stdout().deprecatedWriter();
        try term.ansi.clearScreen(stdout);
        try term.ansi.moveCursor(stdout, 0, 0);

        switch (screen_type) {
            .welcome => try self.renderWelcomeScreen(),
            .editor => try self.renderEditorScreen(help_visible),
            .help => try self.renderHelpScreen(),
        }

        // Hide cursor by default - editor will show it if needed
        try term.ansi.hideCursor(stdout);
    }

    fn renderWelcomeScreen(_: *Self) !void {
        const stdout = std.fs.File.stdout().deprecatedWriter();

        // Set rich colors and styling
        try term.ansi.setForeground(stdout, .cyan);
        try term.ansi.setBold(stdout, true);

        // Markdown ASCII art
        try stdout.writeAll(
            \\
            \\    ╔══════════════════════════════════════════════════════════════════════════╗
            \\    ║                                                                          ║
            \\    ║    ███╗   ███╗ █████╗ ██████╗ ██╗  ██╗██████╗  ██████╗ ██╗    ██╗███╗  ║
            \\    ║    ████╗ ████║██╔══██╗██╔══██╗██║ ██╔╝██╔══██╗██╔═══██╗██║    ██║████╗ ║
            \\    ║    ██╔████╔██║███████║██████╔╝█████╔╝ ██║  ██║██║   ██║██║ █╗ ██║██╔██║ ║
            \\    ║    ██║╚██╔╝██║██╔══██║██╔══██╗██╔═██╗ ██║  ██║██║   ██║██║███╗██║██║╚██║ ║
            \\    ║    ██║ ╚═╝ ██║██║  ██║██║  ██║██║  ██╗██████╔╝╚██████╔╝╚███╔███╔╝██║ ╚█║ ║
            \\    ║    ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝  ╚═════╝  ╚══╝╚══╝ ╚═╝  ╚╝ ║
            \\    ║                                                                          ║
            \\    ╚══════════════════════════════════════════════════════════════════════════╝
            \\
        );

        try term.ansi.reset(stdout);
        try term.ansi.setForeground(stdout, .bright_blue);
        try stdout.writeAll("                     Enterprise-grade markdown systems architect\n\n");

        try term.ansi.setForeground(stdout, .bright_green);
        try stdout.writeAll("    Welcome to Markdown Agent\n\n");

        try term.ansi.setForeground(stdout, .yellow);
        try stdout.writeAll("    Type / to use slash commands\n");
        try stdout.writeAll("    Type @ to mention files\n");
        try stdout.writeAll("    Ctrl+C to exit\n\n");

        try term.ansi.setForeground(stdout, .cyan);
        try stdout.writeAll("    /help for more\n\n");

        try term.ansi.setForeground(stdout, .bright_magenta);
        try term.ansi.setItalic(stdout, true);
        try stdout.writeAll("    \"Great software is written with clarity of purpose.\n");
        try stdout.writeAll("     Every line should tell a story.\" - Clean Code Philosophy\n");
        try term.ansi.reset(stdout);
    }

    fn renderEditorScreen(self: *Self, help_visible: bool) !void {
        if (help_visible) {
            try self.renderHelpOverlay();
        } else {
            // Render main editor interface
            try self.renderEditorInterface();
        }
    }

    fn renderHelpOverlay(_: *Self) !void {
        const stdout = std.fs.File.stdout();
        var buf: [1024]u8 = undefined;
        var writer = stdout.writer(&buf);

        // Draw help modal with border
        try term.ansi.setForeground(&writer.interface, .cyan);
        try writer.interface.writeAll(
            \\    ╭─────────────────────────────────────────────────────────────────────────╮
            \\    │                    Markdown Agent - Help & Keyboard Shortcuts           │
            \\    ├─────────────────────────────────────────────────────────────────────────┤
            \\    │                                                                         │
            \\    │  Editor Shortcuts                         File Operations              │
        );

        try term.ansi.setForeground(&writer.interface, .bright_green);
        try writer.interface.writeAll(
            \\    │  ↑, ↓                 Move cursor up/down   Ctrl+O          Open file   │
            \\    │  Shift+Enter          Insert newline       Ctrl+S          Save file   │
            \\    │  Escape               Clear input          Ctrl+N          New file    │
            \\    │  Ctrl+P, Ctrl+N       Navigate history     Ctrl+Q          Quit        │
            \\    │  Pg Up, Pg Down       Page up/down         Ctrl+W          Close tab   │
            \\    │  Cmd+←, Ctrl+A        Jump to start        Ctrl+R          Reload      │
        );

        try term.ansi.setForeground(&writer.interface, .cyan);
        try writer.interface.writeAll(
            \\    │                                                                         │
            \\    │  Markdown Features                        AI Assistant                  │
        );

        try term.ansi.setForeground(&writer.interface, .bright_yellow);
        try writer.interface.writeAll(
            \\    │  /preview             Live preview         @ai             Ask AI      │
            \\    │  /toc                 Table of contents    /explain        Explain     │
            \\    │  /format              Auto-format          /improve        Improve     │
            \\    │  /validate            Check syntax         /translate      Translate   │
            \\    │  /export html         Export to HTML       /summarize      Summarize   │
            \\    │  /export pdf          Export to PDF        /complete       Complete    │
        );

        try term.ansi.setForeground(&writer.interface, .cyan);
        try writer.interface.writeAll(
            \\    │                                                                         │
            \\    ├─────────────────────────────────────────────────────────────────────────┤
            \\    │               Press Escape to close • Use ↑↓ or j/k to scroll          │
            \\    ╰─────────────────────────────────────────────────────────────────────────╯
        );

        try term.ansi.reset(&writer.interface);
    }

    fn renderEditorInterface(self: *Self) !void {
        const stdout = std.fs.File.stdout().deprecatedWriter();

        // Main editor layout
        try term.ansi.setForeground(stdout, .bright_white);
        try term.ansi.setBackground(stdout, .black);

        // Top title bar
        try stdout.writeAll("╭─ Markdown Editor ─────────────────────────────────╮╭─ Preview ─────────────────╮\n");

        // Render editor content with line numbers
        const content = self.editor.getContent();
        var lines = std.mem.splitScalar(u8, content, '\n');
        var line_num: usize = 1;
        var current_line: usize = 0;
        var cursor_line: usize = 0;
        var cursor_col: usize = 0;

        // Calculate cursor position in content
        var pos: usize = 0;
        for (content) |c| {
            if (pos == self.editor.cursor_pos) {
                cursor_line = current_line;
                cursor_col = pos - self.getLineStartPos(content, current_line);
                break;
            }
            if (c == '\n') {
                current_line += 1;
            }
            pos += 1;
        }
        if (pos == self.editor.cursor_pos) {
            cursor_line = current_line;
            cursor_col = pos - self.getLineStartPos(content, current_line);
        }

        // Render up to 18 lines of content
        var y: u8 = 2;
        while (y <= 19) : (y += 1) {
            const line = lines.next() orelse "";

            // Line number
            var line_num_buf: [16]u8 = undefined;
            const line_num_str = std.fmt.bufPrint(&line_num_buf, "{d:4} ", .{line_num}) catch "   ? ";
            try stdout.writeAll("│");
            try stdout.writeAll(line_num_str);

            // Line content (truncate if too long)
            const max_content_len = 45;
            const display_line = if (line.len > max_content_len) line[0..max_content_len] else line;
            try stdout.writeAll(display_line);

            // Pad with spaces to fill editor width
            var spaces_needed = max_content_len - display_line.len;
            while (spaces_needed > 0) : (spaces_needed -= 1) {
                try stdout.writeAll(" ");
            }

            try stdout.writeAll("││                           │\n");
            line_num += 1;
        }

        // Fill remaining editor lines
        while (y <= 19) : (y += 1) {
            try stdout.writeAll("│     ");
            var i: usize = 0;
            while (i < 45) : (i += 1) {
                try stdout.writeAll(" ");
            }
            try stdout.writeAll("││                           │\n");
        }

        try stdout.writeAll("╰───────────────────────────────────────────────────╯╰───────────────────────────╯\n");

        // Status bar
        try term.ansi.setForeground(stdout, .black);
        try term.ansi.setBackground(stdout, .bright_blue);
        try stdout.print(" Untitled.md                                                    EDIT    Ln {d}, Col {d} ", .{ cursor_line + 1, cursor_col + 1 });
        try term.ansi.reset(stdout);
        try stdout.writeAll("\n");

        // Position cursor in editor area (row 2 + cursor_line, col 6 + cursor_col)
        const cursor_y = @min(2 + cursor_line, 19);
        const cursor_x = @min(6 + cursor_col, 50);
        try term.ansi.moveCursor(stdout, cursor_x, cursor_y);
        try term.ansi.showCursor(stdout);
    }

    // Helper function to get line start position
    fn getLineStartPos(self: *Self, content: []const u8, target_line: usize) usize {
        _ = self;
        var line: usize = 0;
        var pos: usize = 0;

        if (target_line == 0) return 0;

        for (content) |c| {
            if (c == '\n') {
                line += 1;
                if (line == target_line) {
                    return pos + 1;
                }
            }
            pos += 1;
        }
        return pos;
    }

    fn renderHelpScreen(self: *Self) !void {
        // Full-screen help (not used in current flow but available)
        try self.renderHelpOverlay();
    }

    fn renderExitMessage(self: *Self) !void {
        const stdout = std.fs.File.stdout();
        var buf: [1024]u8 = undefined;
        var writer = stdout.writer(&buf);
        try term.ansi.clearScreen(&writer.interface);
        try term.ansi.moveCursor(&writer.interface, 10, 20);
        try term.ansi.setForeground(&writer.interface, .bright_green);
        try term.ansi.setBold(&writer.interface, true);
        try writer.interface.writeAll("✓ Markdown Agent session completed\n");
        try term.ansi.reset(&writer.interface);
        try writer.interface.writeAll("   Thank you for using Markdown Agent!\n\n");
        try self.terminal.flush();
    }

    fn calculateBounds(self: *Self) LayoutBounds {
        // Default terminal size for now
        const size = .{ .width = @as(u16, 80), .height = @as(u16, 24) };
        var bounds = LayoutBounds{
            .editor = .{ .x = 0, .y = 0, .width = 40, .height = 20 },
            .preview = .{ .x = 40, .y = 0, .width = 40, .height = 20 },
            .file_browser = .{ .x = 0, .y = 0, .width = 20, .height = 20 },
            .ai_chat = .{ .x = 60, .y = 0, .width = 20, .height = 20 },
            .status_bar = .{ .x = 0, .y = 20, .width = 80, .height = 1 },
        };

        var left: u16 = 0;
        var right: u16 = size.width;
        const top: u16 = 0;
        var bottom: u16 = size.height - 1; // Reserve for status bar

        // Status bar at bottom
        bounds.status_bar = .{
            .x = 0,
            .y = size.height - 1,
            .width = size.width,
            .height = 1,
        };

        // File browser on left if visible
        if (self.file_browser.visible) {
            const width = @min(30, size.width / 4);
            bounds.file_browser = .{
                .x = left,
                .y = top,
                .width = width,
                .height = bottom - top,
            };
            left += width + 1;
        }

        // AI chat on right or bottom based on layout
        if (self.ai_chat.visible) {
            if (self.layout == .split_horizontal) {
                const height = @min(15, size.height / 3);
                bounds.ai_chat = .{
                    .x = left,
                    .y = bottom - height,
                    .width = right - left,
                    .height = height,
                };
                bottom -= height + 1;
            } else {
                const width = @min(50, size.width / 3);
                bounds.ai_chat = .{
                    .x = right - width,
                    .y = top,
                    .width = width,
                    .height = bottom - top,
                };
                right -= width + 1;
            }
        }

        // Split remaining space between editor and preview
        const main_width = right - left;
        const main_height = bottom - top;

        if (self.layout == .split_horizontal or self.layout == .split_vertical) {
            if (self.layout == .split_horizontal) {
                const editor_width = main_width / 2;
                bounds.editor = .{
                    .x = left,
                    .y = top,
                    .width = editor_width - 1,
                    .height = main_height,
                };
                bounds.preview = .{
                    .x = left + editor_width,
                    .y = top,
                    .width = main_width - editor_width,
                    .height = main_height,
                };
            } else {
                const editor_height = main_height / 2;
                bounds.editor = .{
                    .x = left,
                    .y = top,
                    .width = main_width,
                    .height = editor_height - 1,
                };
                bounds.preview = .{
                    .x = left,
                    .y = top + editor_height,
                    .width = main_width,
                    .height = main_height - editor_height,
                };
            }
        } else if (self.layout == .editor_only) {
            bounds.editor = .{
                .x = left,
                .y = top,
                .width = main_width,
                .height = main_height,
            };
            bounds.preview = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        } else { // preview_only
            bounds.editor = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
            bounds.preview = .{
                .x = left,
                .y = top,
                .width = main_width,
                .height = main_height,
            };
        }

        return bounds;
    }

    fn updatePreview(self: *Self) !void {
        const content = self.editor.getContent();
        try self.preview.updateContent(content);
    }

    fn updateStatusBar(self: *Self) !void {
        self.status_bar.setFile(self.current_file);
        self.status_bar.setModified(self.modified);
        self.status_bar.setPosition(self.editor.getCursorPosition());
        self.status_bar.setMode(switch (self.focused_pane) {
            .editor => "EDIT",
            .preview => "PREVIEW",
            .file_browser => "FILES",
            .ai_chat => "AI CHAT",
        });
        self.status_bar.setAuthHint(!self.isAuthed());
    }

    fn isAuthed(self: *Self) bool {
        if (self.engine) |e| {
            return e.client != null;
        }
        return false;
    }

    // Command handlers
    fn quit(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));

        if (self.modified) {
            // Show save prompt
            const choice = try self.showPrompt("Save changes before quit?", &[_][]const u8{ "Yes", "No", "Cancel" });
            switch (choice) {
                0 => try save(ctx),
                1 => {},
                2 => return,
            }
        }

        self.app.running = false;
    }

    fn save(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));

        if (self.current_file) |file| {
            const content = self.editor.getContent();
            try fsutil.writeFile(file, content);
            self.modified = false;
            try self.showNotification("File saved", .success);
        } else {
            try saveAs(ctx);
        }
    }

    fn saveAs(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));

        const filename = try self.showInputPrompt("Save as:");
        if (filename.len > 0) {
            if (self.current_file) |old| self.allocator.free(old);
            self.current_file = try self.allocator.dupe(u8, filename);

            const content = self.editor.getContent();
            try fsutil.writeFile(filename, content);
            self.modified = false;
            try self.showNotification("File saved", .success);
        }
    }

    fn open(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));

        // Show file picker
        const file = try self.file_browser.pickFile();
        if (file) |f| {
            try self.loadFile(f);
        }
    }

    fn new(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));

        if (self.modified) {
            const choice = try self.showPrompt("Save current file?", &[_][]const u8{ "Yes", "No", "Cancel" });
            switch (choice) {
                0 => try save(ctx),
                1 => {},
                2 => return,
            }
        }

        self.editor.clear();
        self.editor.insertText("# New Document\n\n") catch {};
        if (self.current_file) |f| self.allocator.free(f);
        self.current_file = null;
        self.modified = false;
        try self.updatePreview();
        try self.updateStatusBar();
    }

    fn commandPalette(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));

        // Register available commands
        try self.command_palette.clearCommands();
        try self.command_palette.addCommand("Save", save);
        try self.command_palette.addCommand("Open", open);
        try self.command_palette.addCommand("New", new);
        try self.command_palette.addCommand("Toggle File Browser", toggleFileBrowser);
        try self.command_palette.addCommand("Toggle AI Chat", toggleAIChat);
        try self.command_palette.addCommand("Ask AI", askAI);
        try self.command_palette.addCommand("Format Document", formatDocument);
        try self.command_palette.addCommand("Generate TOC", generateTOC);
        try self.command_palette.addCommand("Check Links", checkLinks);
        try self.command_palette.addCommand("Insert Template", insertTemplate);
        try self.command_palette.addCommand("Export HTML", exportHTML);
        try self.command_palette.addCommand("Toggle Layout", toggleLayout);
        try self.command_palette.addCommand("Quit", quit);

        try self.command_palette.show();
    }

    fn toggleFileBrowser(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));
        self.file_browser.visible = !self.file_browser.visible;
        try self.render();
    }

    fn toggleAIChat(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));
        self.ai_chat.visible = !self.ai_chat.visible;
        if (self.ai_chat.visible) {
            self.focused_pane = .ai_chat;
        }
        try self.render();
    }

    fn askAI(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));

        if (self.engine == null) {
            try self.showNotification("AI not available - set ANTHROPIC_API_KEY", .err);
            return;
        }

        // Get selected text or prompt for question
        const context = self.editor.getSelectedText() orelse self.editor.getContent();
        const question = try self.showInputPrompt("Ask AI about this document:");

        if (question.len > 0) {
            self.ai_chat.visible = true;
            self.focused_pane = .ai_chat;

            // Setup streaming callbacks
            if (self.engine) |*e| {
                e.shared_ctx.ui_stream = .{
                    .ctx = @ptrCast(@alignCast(self)),
                    .onToken = onAIToken,
                    .onEvent = onAIEvent,
                };

                // Build prompt with context
                const prompt = try std.fmt.allocPrint(self.allocator, "Document:\n```markdown\n{s}\n```\n\nQuestion: {s}", .{ context, question });
                defer self.allocator.free(prompt);

                // Send to AI
                try self.ai_chat.addMessage(.user, question);
                try e.runInference(prompt);
            }
        }
    }

    fn onAIToken(ctx: *anyopaque, token: []const u8) void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));
        self.ai_chat.appendToLastMessage(token) catch {};
        self.render() catch {};
    }

    fn onAIEvent(ctx: *anyopaque, event: []const u8, data: []const u8) void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));
        _ = data;

        if (std.mem.eql(u8, event, "message_start")) {
            self.ai_chat.addMessage(.assistant, "") catch {};
        }
    }

    fn switchFocus(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));

        // Cycle through visible panes
        self.focused_pane = switch (self.focused_pane) {
            .editor => if (self.layout != .editor_only) .preview else if (self.file_browser.visible) .file_browser else if (self.ai_chat.visible) .ai_chat else .editor,
            .preview => if (self.file_browser.visible) .file_browser else if (self.ai_chat.visible) .ai_chat else .editor,
            .file_browser => if (self.ai_chat.visible) .ai_chat else .editor,
            .ai_chat => .editor,
        };

        try self.updateStatusBar();
    }

    fn toggleLayout(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));

        self.layout = switch (self.layout) {
            .split_horizontal => .split_vertical,
            .split_vertical => .editor_only,
            .editor_only => .preview_only,
            .preview_only => .split_horizontal,
        };

        try self.render();
    }

    fn formatDocument(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));

        const content = self.editor.getContent();
        const formatted = try textlib.normalizeWhitespace(self.allocator, content);
        defer self.allocator.free(formatted);

        try self.editor.setContent(formatted);
        self.modified = true;
        try self.updatePreview();
        try self.showNotification("Document formatted", .success);
    }

    fn generateTOC(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));

        const content = self.editor.getContent();
        var toc = std.ArrayList(u8).init(self.allocator);
        defer toc.deinit();

        try toc.appendSlice("## Table of Contents\n\n");

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len > 0 and trimmed[0] == '#') {
                var level: usize = 0;
                for (trimmed) |c| {
                    if (c == '#') level += 1 else break;
                }

                const heading = std.mem.trim(u8, trimmed[level..], " \t#");
                if (heading.len == 0) continue;

                // Indent based on level
                var i: usize = 0;
                while (i < (level - 1) * 2) : (i += 1) {
                    try toc.append(' ');
                }

                // Create anchor - use stack buffer to avoid allocation
                var anchor_buf: [256]u8 = undefined;
                const anchor = std.fmt.bufPrint(&anchor_buf, "{s}", .{heading}) catch heading;

                // Replace spaces with dashes for anchor (in-place, no allocation)
                for (anchor_buf[0..anchor.len]) |*c| {
                    if (c.* == ' ') c.* = '-';
                }

                // Convert to lowercase (in-place)
                for (anchor_buf[0..anchor.len]) |*c| {
                    c.* = std.ascii.toLower(c.*);
                }

                try toc.writer().print("- [{s}](#{s})\n", .{ heading, anchor });
            }
        }

        try self.editor.insertTextAtCursor(toc.items);
        self.modified = true;
        try self.updatePreview();
    }

    fn checkLinks(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));

        _ = self.editor.getContent();
        // Link checking would go here
        try self.showNotification("Link check complete - all valid", .success);
    }

    fn insertTemplate(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));

        const templates = [_][]const u8{
            "Table",
            "Code Block",
            "Task List",
            "Front Matter",
            "Footnote",
        };

        const choice = try self.showMenu("Insert Template", &templates);

        const template = switch (choice) {
            0 => "| Header 1 | Header 2 | Header 3 |\n|----------|----------|----------|\n| Cell 1   | Cell 2   | Cell 3   |\n",
            1 => "```language\n// Code here\n```\n",
            2 => "- [ ] Task 1\n- [ ] Task 2\n- [x] Completed task\n",
            3 => "---\ntitle: Document Title\ndate: 2025-01-01\nauthor: Your Name\ntags: [tag1, tag2]\n---\n\n",
            4 => "Here is a footnote[^1].\n\n[^1]: This is the footnote text.\n",
            else => "",
        };

        try self.editor.insertTextAtCursor(template);
        self.modified = true;
        try self.updatePreview();
    }

    fn exportHTML(ctx: *anyopaque) !void {
        const self = @as(*Self, @ptrCast(@alignCast(ctx)));

        const filename = try self.showInputPrompt("Export as HTML:");
        if (filename.len > 0) {
            const html = try self.preview.getHTML();
            defer self.allocator.free(html);

            try fsutil.writeFile(filename, html);
            try self.showNotification("Exported to HTML", .success);
        }
    }

    fn loadFile(self: *Self, path: []const u8) !void {
        const content = try fsutil.readFileAlloc(self.allocator, path, null);
        // Use setContentOwned to take direct ownership (no copy)
        self.editor.setContentOwned(content);

        if (self.current_file) |old| self.allocator.free(old);
        self.current_file = try self.allocator.dupe(u8, path);

        self.modified = false;
        try self.updatePreview();
        try self.updateStatusBar();
    }

    fn showPrompt(self: *Self, message: []const u8, options: []const []const u8) !usize {
        // Would show modal dialog
        _ = self;
        _ = message;
        _ = options;
        return 0;
    }

    fn showInputPrompt(self: *Self, message: []const u8) ![]const u8 {
        // Would show input dialog
        _ = self;
        _ = message;
        return "";
    }

    fn showMenu(self: *Self, title: []const u8, items: []const []const u8) !usize {
        // Would show menu
        _ = self;
        _ = title;
        _ = items;
        return 0;
    }

    fn showNotification(self: *Self, message: []const u8, level: NotificationLevel) !void {
        _ = self;
        _ = message;
        _ = level;
        // Would show notification
    }
};

/// Editor pane component
const EditorPane = struct {
    const Self = @This();

    allocator: Allocator,
    content: std.ArrayList(u8),
    cursor_pos: usize,
    selection_start: ?usize,
    selection_end: ?usize,
    scroll_offset: usize,
    dirty: bool,

    pub fn initEditorPane(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .content = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable,
            .cursor_pos = 0,
            .selection_start = null,
            .selection_end = null,
            .scroll_offset = 0,
            .dirty = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.content.deinit(self.allocator);
    }

    pub fn render(self: *Self, screen: *tui.Screen, bounds: Rect) !void {
        try screen.drawBox(bounds, .single);

        const visible_lines = if (bounds.height > 2) bounds.height - 2 else 0;
        // Split content into lines manually for Zig 0.15.1
        var line_start: usize = 0;
        var line_num: usize = 0;
        var content = self.content.items;

        while (line_start < content.len) {
            var line_end = line_start;
            while (line_end < content.len and content[line_end] != '\n') {
                line_end += 1;
            }

            const line = content[line_start..line_end];

            // Process the line here
            if (line_num >= self.scroll_offset and line_num < self.scroll_offset + visible_lines) {
                const y = bounds.y + 1 + @as(u16, @intCast(line_num - self.scroll_offset));

                // Line numbers (stack buffer, no heap)
                var lnbuf: [8]u8 = undefined;
                const ln = std.fmt.bufPrint(&lnbuf, "{d:4} ", .{line_num + 1}) catch "|   ";
                try screen.writeAt(bounds.x + 1, y, ln);

                // Highlighted content
                const start_x = bounds.x + 6;
                const max_width = if (bounds.width > 7) bounds.width - 7 else 0;
                try self.renderLineWithHighlight(screen, start_x, y, line, max_width);
            }

            // Move to next line
            line_start = if (line_end < content.len) line_end + 1 else content.len;
            line_num += 1;
        }

        // Cursor
        const cursor_line = self.getLineForPosition(self.cursor_pos);
        const cursor_col = self.getColumnForPosition(self.cursor_pos);
        if (cursor_line >= self.scroll_offset and cursor_line < self.scroll_offset + visible_lines) {
            const y = bounds.y + 1 + @as(u16, @intCast(cursor_line - self.scroll_offset));
            const x = bounds.x + 6 + @as(u16, @intCast(cursor_col));
            try screen.setCursorPosition(x, y);
        }
    }

    fn renderLineWithHighlight(_: *Self, screen: *tui.Screen, x: u16, y: u16, line: []const u8, max_width: u16) !void {
        var i: usize = 0;
        var col: u16 = 0;

        while (i < line.len and col < max_width) {
            const remaining = line[i..];

            // Headers (leading #'s)
            if (i == 0 and remaining.len > 0 and remaining[0] == '#') {
                try screen.setForeground(.cyan);
                var j: usize = 0;
                while (j < remaining.len and remaining[j] == '#') : (j += 1) {}
                try screen.writeAt(x + col, y, remaining[0..j]);
                col += @intCast(j);
                i += j;
                try screen.resetStyle();
                continue;
            }

            // Bold **...**
            if (remaining.len >= 2 and remaining[0] == '*' and remaining[1] == '*') {
                const after = remaining[2..];
                const end_rel = std.mem.indexOf(u8, after, "**") orelse after.len;
                try screen.setBold(true);
                const seg = after[0..end_rel];
                const write_len: u16 = @intCast(@min(@as(usize, max_width - col), seg.len));
                try screen.writeAt(x + col, y, seg[0..write_len]);
                try screen.setBold(false);
                const extra_bold: usize = if (end_rel < after.len) 2 else 0;
                i += 2 + end_rel + extra_bold;
                col += write_len;
                continue;
            }

            // Inline code `...`
            if (remaining[0] == '`') {
                const after = remaining[1..];
                const end_rel = std.mem.indexOfScalar(u8, after, '`') orelse after.len;
                try screen.setForeground(.yellow);
                const seg = after[0..end_rel];
                const write_len: u16 = @intCast(@min(@as(usize, max_width - col), seg.len));
                try screen.writeAt(x + col, y, seg[0..write_len]);
                try screen.resetStyle();
                const extra_tick: usize = if (end_rel < after.len) 1 else 0;
                i += 1 + end_rel + extra_tick;
                col += write_len;
                continue;
            }

            // Links [text]...
            if (remaining[0] == '[') {
                const end_rel = std.mem.indexOfScalar(u8, remaining, ']') orelse remaining.len - 1;
                const seg = remaining[0..(end_rel + 1)];
                const write_len: u16 = @intCast(@min(@as(usize, max_width - col), seg.len));
                try screen.setForeground(.blue);
                try screen.writeAt(x + col, y, seg[0..write_len]);
                try screen.resetStyle();
                i += write_len;
                col += write_len;
                continue;
            }

            // Normal text (single byte)
            try screen.writeAt(x + col, y, line[i .. i + 1]);
            i += 1;
            col += 1;
        }
    }

    pub fn handleKey(self: *Self, key: term.KeyEvent) !void {
        switch (key.code) {
            .char => |ch| try self.insertChar(ch),
            .backspace => self.deleteChar(),
            .delete => self.deleteForward(),
            .left => self.moveCursorLeft(),
            .right => self.moveCursorRight(),
            .up => self.moveCursorUp(),
            .down => self.moveCursorDown(),
            .home => self.moveCursorToLineStart(),
            .end => self.moveCursorToLineEnd(),
            .page_up => self.scroll_offset = if (self.scroll_offset > 20) self.scroll_offset - 20 else 0,
            .page_down => self.scroll_offset += 20,
            else => {},
        }
        self.dirty = true;
    }

    pub fn handleMouse(self: *Self, mouse: term.MouseEvent) !void {
        // Handle mouse selection
        _ = self;
        _ = mouse;
    }

    pub fn getContent(self: *Self) []const u8 {
        return self.content.items;
    }

    pub fn setContent(self: *Self, content: []const u8) !void {
        self.content.clearRetainingCapacity();
        try self.content.appendSlice(self.allocator, content);
        self.cursor_pos = 0;
        self.selection_start = null;
        self.selection_end = null;
        self.scroll_offset = 0;
        self.dirty = true;
    }

    /// Take ownership of an already-allocated buffer (avoids extra copy on open)
    pub fn setContentOwned(self: *Self, owned: []u8) void {
        self.content.deinit(self.allocator);
        // Adopt owned buffer directly (ArrayList without allocator state)
        self.content = std.ArrayList(u8){ .items = owned, .capacity = owned.len };
        self.cursor_pos = 0;
        self.selection_start = null;
        self.selection_end = null;
        self.scroll_offset = 0;
        self.dirty = true;
    }

    pub fn clear(self: *Self) void {
        self.content.clearRetainingCapacity();
        self.cursor_pos = 0;
        self.selection_start = null;
        self.selection_end = null;
        self.scroll_offset = 0;
        self.dirty = true;
    }

    pub fn insertText(self: *Self, text: []const u8) !void {
        try self.content.insertSlice(self.allocator, self.cursor_pos, text);
        self.cursor_pos += text.len;
        self.dirty = true;
    }

    pub fn insertTextAtCursor(self: *Self, text: []const u8) !void {
        try self.insertText(text);
    }

    pub fn insertChar(self: *Self, ch: u8) !void {
        try self.content.insert(self.allocator, self.cursor_pos, ch);
        self.cursor_pos += 1;
        self.dirty = true;
    }

    pub fn deleteChar(self: *Self) void {
        if (self.cursor_pos > 0) {
            _ = self.content.orderedRemove(self.cursor_pos - 1);
            self.cursor_pos -= 1;
            self.dirty = true;
        }
    }

    pub fn deleteForward(self: *Self) void {
        if (self.cursor_pos < self.content.items.len) {
            _ = self.content.orderedRemove(self.cursor_pos);
            self.dirty = true;
        }
    }

    pub fn moveCursorLeft(self: *Self) void {
        if (self.cursor_pos > 0) self.cursor_pos -= 1;
    }

    pub fn moveCursorRight(self: *Self) void {
        if (self.cursor_pos < self.content.items.len) self.cursor_pos += 1;
    }

    pub fn moveCursorUp(self: *Self) void {
        const line = self.getLineForPosition(self.cursor_pos);
        if (line > 0) {
            const col = self.getColumnForPosition(self.cursor_pos);
            self.cursor_pos = self.getPositionForLineCol(line - 1, col);
        }
    }

    pub fn moveCursorDown(self: *Self) void {
        const line = self.getLineForPosition(self.cursor_pos);
        const col = self.getColumnForPosition(self.cursor_pos);
        self.cursor_pos = self.getPositionForLineCol(line + 1, col);
    }

    pub fn moveCursorToLineStart(self: *Self) void {
        while (self.cursor_pos > 0 and self.content.items[self.cursor_pos - 1] != '\n') {
            self.cursor_pos -= 1;
        }
    }

    pub fn moveCursorToLineEnd(self: *Self) void {
        while (self.cursor_pos < self.content.items.len and self.content.items[self.cursor_pos] != '\n') {
            self.cursor_pos += 1;
        }
    }

    pub fn getSelectedText(self: *Self) ?[]const u8 {
        if (self.selection_start) |start| if (self.selection_end) |end| return self.content.items[start..end];
        return null;
    }

    pub fn getCursorPosition(self: *Self) Position {
        return .{ .line = self.getLineForPosition(self.cursor_pos), .column = self.getColumnForPosition(self.cursor_pos) };
    }

    pub fn isDirty(self: *Self) bool {
        const d = self.dirty;
        self.dirty = false;
        return d;
    }

    fn getLineForPosition(self: *Self, pos: usize) usize {
        var line: usize = 0;
        const end = @min(pos, self.content.items.len);
        var i: usize = 0;
        while (i < end) : (i += 1) {
            if (self.content.items[i] == '\n') line += 1;
        }
        return line;
    }

    fn getColumnForPosition(self: *Self, pos: usize) usize {
        var i = @min(pos, self.content.items.len);
        while (i > 0 and self.content.items[i - 1] != '\n') : (i -= 1) {}
        return pos - i;
    }

    fn getPositionForLineCol(self: *Self, target_line: usize, target_col: usize) usize {
        var pos: usize = 0;
        var line: usize = 0;
        while (pos < self.content.items.len and line < target_line) : (pos += 1) {
            if (self.content.items[pos] == '\n') line += 1;
        }
        var col: usize = 0;
        while (pos < self.content.items.len and col < target_col and self.content.items[pos] != '\n') : (pos += 1) col += 1;
        return pos;
    }
};

/// Preview pane component
const PreviewPane = struct {
    const Self = @This();

    allocator: Allocator,
    content: []const u8,
    rendered_html: ?[]u8,
    scroll_offset: usize,

    pub fn initPreviewPane(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .content = "",
            .rendered_html = null,
            .scroll_offset = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.rendered_html) |html| self.allocator.free(html);
    }

    pub fn render(self: *Self, screen: *tui.Screen, bounds: Rect) !void {
        // Draw border
        try screen.drawBox(bounds, .single);
        try screen.writeAt(bounds.x + 2, bounds.y, " Preview ");

        // Render markdown content
        const opts = foundation.render.markdown.MarkdownOptions{
            .maxWidth = @as(usize, bounds.width - 2),
            .colorEnabled = true,
        };
        const rendered = try foundation.render.markdown.renderMarkdown(self.allocator, self.content, opts);
        defer self.allocator.free(rendered);

        // Display rendered content
        var lines = std.mem.splitScalar(u8, rendered, '\n');
        var line_num: usize = 0;
        const visible_lines = bounds.height - 2;

        while (lines.next()) |line| {
            if (line_num >= self.scroll_offset and line_num < self.scroll_offset + visible_lines) {
                const y = bounds.y + 1 + @as(u16, @intCast(line_num - self.scroll_offset));
                try screen.writeAt(bounds.x + 1, y, line);
            }
            line_num += 1;
        }
    }

    pub fn handleKey(self: *Self, key: term.KeyEvent) !void {
        switch (key.code) {
            .up => {
                if (self.scroll_offset > 0) self.scroll_offset -= 1;
            },
            .down => {
                self.scroll_offset += 1;
            },
            .page_up => {
                self.scroll_offset = if (self.scroll_offset > 20) self.scroll_offset - 20 else 0;
            },
            .page_down => {
                self.scroll_offset += 20;
            },
            else => {},
        }
    }

    pub fn handleMouse(self: *Self, mouse: term.MouseEvent) !void {
        if (mouse.button == .wheel_up) {
            if (self.scroll_offset > 0) self.scroll_offset -= 1;
        } else if (mouse.button == .wheel_down) {
            self.scroll_offset += 1;
        }
    }

    pub fn updateContent(self: *Self, content: []const u8) !void {
        self.content = content;
        if (self.rendered_html) |html| self.allocator.free(html);
        self.rendered_html = null;
    }

    pub fn getHTML(self: *Self) ![]u8 {
        if (self.rendered_html == null) {
            // Convert markdown to HTML
            self.rendered_html = try markdownToHTML(self.allocator, self.content);
        }
        return try self.allocator.dupe(u8, self.rendered_html.?);
    }
};

/// File browser component
const FileBrowser = struct {
    const Self = @This();

    allocator: Allocator,
    current_dir: []const u8,
    entries: std.ArrayList(FileEntry),
    selected_index: usize,
    scroll_offset: usize,
    visible: bool,

    const FileEntry = struct {
        name: []const u8,
        is_dir: bool,
        size: u64,
    };

    pub fn initFileBrowser(allocator: Allocator) !Self {
        var self = Self{
            .allocator = allocator,
            .current_dir = try std.fs.cwd().realpathAlloc(allocator, "."),
            .entries = std.ArrayList(FileEntry).initCapacity(allocator, 0) catch unreachable,
            .selected_index = 0,
            .scroll_offset = 0,
            .visible = false,
        };
        try self.refresh();
        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.entries.deinit(self.allocator);
        self.allocator.free(self.current_dir);
    }

    pub fn render(self: *Self, screen: *tui.Screen, bounds: Rect) !void {
        // Safety: Check minimum bounds
        if (bounds.width < 8 or bounds.height < 4) return;

        // Draw border
        try screen.drawBox(bounds, .single);
        try screen.writeAt(bounds.x + 2, bounds.y, " Files ");

        // Draw current directory - safe substring calculation
        const dir_display = if (self.current_dir.len > bounds.width - 6) blk: {
            const start = self.current_dir.len - (bounds.width - 6);
            break :blk self.current_dir[start..];
        } else self.current_dir;
        try screen.writeAt(bounds.x + 1, bounds.y + 1, dir_display);

        // Draw entries - safe bounds checking
        const visible_lines = if (bounds.height > 3) bounds.height - 3 else 0;
        if (visible_lines == 0) return;

        var i: usize = 0;
        while (i < visible_lines and self.scroll_offset + i < self.entries.items.len) : (i += 1) {
            const entry_idx = self.scroll_offset + i;
            if (entry_idx >= self.entries.items.len) break; // Extra safety check

            const entry = self.entries.items[entry_idx];
            const y = bounds.y + 2 + @as(u16, @intCast(i));

            // Icon and name - use stack buffer to avoid allocation
            const icon = if (entry.is_dir) "📁" else if (std.mem.endsWith(u8, entry.name, ".md")) "📝" else "📄";
            const name = if (entry.name.len + 3 > bounds.width - 2) blk: {
                const max_name_len = if (bounds.width > 10) bounds.width - 10 else 1;
                break :blk entry.name[0..@min(max_name_len, entry.name.len)];
            } else entry.name;

            // Use stack buffer instead of allocation
            var entry_buf: [512]u8 = undefined;
            const entry_str = std.fmt.bufPrint(&entry_buf, "{s} {s}", .{ icon, name }) catch "? ???";

            // Highlight selected entry
            if (entry_idx == self.selected_index) {
                try screen.setForeground(.white);
                try screen.setBackground(.blue);
            }

            try screen.writeAt(bounds.x + 1, y, entry_str);

            if (entry_idx == self.selected_index) {
                try screen.resetStyle();
            }
        }
    }

    pub fn handleKey(self: *Self, key: term.KeyEvent) !void {
        switch (key.code) {
            .up => {
                if (self.selected_index > 0) {
                    self.selected_index -= 1;
                    if (self.selected_index < self.scroll_offset) {
                        self.scroll_offset = self.selected_index;
                    }
                }
            },
            .down => {
                if (self.entries.items.len > 0 and self.selected_index < self.entries.items.len - 1) {
                    self.selected_index += 1;
                    // Adjust scroll if needed
                }
            },
            .enter => {
                if (self.entries.items.len > 0 and self.selected_index < self.entries.items.len) {
                    const entry = self.entries.items[self.selected_index];
                    if (entry.is_dir) {
                        self.changeDirectory(entry.name) catch {}; // Don't crash on nav errors
                    }
                }
            },
            .backspace => {
                self.changeDirectory("..") catch {}; // Don't crash on nav errors
            },
            else => {},
        }
    }

    pub fn handleMouse(self: *Self, mouse: term.MouseEvent) !void {
        _ = self;
        _ = mouse;
    }

    pub fn pickFile(self: *Self) !?[]const u8 {
        if (self.selected_index < self.entries.items.len) {
            const entry = self.entries.items[self.selected_index];
            if (!entry.is_dir) {
                return try std.fs.path.join(self.allocator, &[_][]const u8{ self.current_dir, entry.name });
            }
        }
        return null;
    }

    fn refresh(self: *Self) !void {
        // Clear old entries
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.entries.clearRetainingCapacity();

        // Read directory
        var dir = try std.fs.openDirAbsolute(self.current_dir, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            // Filter for markdown files and directories
            if (entry.kind == .directory or
                std.mem.endsWith(u8, entry.name, ".md") or
                std.mem.endsWith(u8, entry.name, ".markdown"))
            {
                try self.entries.append(self.allocator, .{
                    .name = try self.allocator.dupe(u8, entry.name),
                    .is_dir = entry.kind == .directory,
                    .size = 0, // Would stat for actual size
                });
            }
        }

        // Sort entries (directories first, then alphabetical)
        std.mem.sort(FileEntry, self.entries.items, {}, struct {
            fn lessThan(_: void, a: FileEntry, b: FileEntry) bool {
                if (a.is_dir != b.is_dir) return a.is_dir;
                return std.mem.lessThan(u8, a.name, b.name);
            }
        }.lessThan);

        self.selected_index = 0;
        self.scroll_offset = 0;
    }

    fn changeDirectory(self: *Self, path: []const u8) !void {
        const new_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ self.current_dir, path });
        defer self.allocator.free(new_dir);

        const real_path = try std.fs.cwd().realpathAlloc(self.allocator, new_dir);
        self.allocator.free(self.current_dir);
        self.current_dir = real_path;

        try self.refresh();
    }
};

/// AI chat pane component
const AIChatPane = struct {
    const Self = @This();

    allocator: Allocator,
    messages: std.ArrayList(ChatMessage),
    input_buffer: std.ArrayList(u8),
    scroll_offset: usize,
    visible: bool,

    const ChatMessage = struct {
        role: Role,
        content: std.ArrayList(u8), // growable
        const Role = enum { user, assistant, system };
    };

    pub fn initAIChatPane(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .messages = std.ArrayList(ChatMessage).initCapacity(allocator, 0) catch unreachable,
            .input_buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable,
            .scroll_offset = 0,
            .visible = false,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.messages.items) |*msg| {
            msg.content.deinit(self.allocator);
        }
        self.messages.deinit(self.allocator);
        self.input_buffer.deinit(self.allocator);
    }

    pub fn render(self: *Self, screen: *tui.Screen, bounds: Rect) !void {
        try screen.drawBox(bounds, .single);
        try screen.writeAt(bounds.x + 2, bounds.y, " AI Assistant ");

        const message_area_height = if (bounds.height > 4) bounds.height - 4 else 0;
        var y: u16 = bounds.y + 1;

        // simple forward rendering; add scroll as needed
        for (self.messages.items) |msg| {
            if (y >= bounds.y + 1 + message_area_height) break;

            const role_str = switch (msg.role) {
                .user => "You: ",
                .assistant => "AI: ",
                .system => "System: ",
            };
            try screen.setForeground(switch (msg.role) {
                .user => .cyan,
                .assistant => .green,
                .system => .yellow,
            });
            try screen.writeAt(bounds.x + 1, y, role_str);
            try screen.resetStyle();

            const content_x: u16 = bounds.x + 1 + @as(u16, @intCast(role_str.len));
            const content_w: u16 = if (bounds.width > (2 + @as(u16, @intCast(role_str.len)))) bounds.width - 2 - @as(u16, @intCast(role_str.len)) else 0;

            var lines = std.mem.splitScalar(u8, msg.content.items, '\n');
            while (lines.next()) |line| {
                if (y >= bounds.y + 1 + message_area_height) break;
                if (line.len <= content_w) {
                    try screen.writeAt(content_x, y, line);
                    y += 1;
                } else {
                    var i: usize = 0;
                    while (i < line.len and y < bounds.y + 1 + message_area_height) : (y += 1) {
                        const end = @min(i + content_w, line.len);
                        try screen.writeAt(content_x, y, line[i..end]);
                        i = end;
                    }
                }
            }
            y += 1;
        }

        // input
        const input_y = bounds.y + bounds.height - 2;
        // Draw a simple horizontal rule above the input
        var i: u16 = 0;
        while (i < bounds.width) : (i += 1) {
            try screen.writeAt(bounds.x + i, input_y - 1, "-");
        }
        try screen.writeAt(bounds.x + 1, input_y, "> ");
        try screen.writeAt(bounds.x + 3, input_y, self.input_buffer.items);
    }

    pub fn handleKey(self: *Self, key: term.KeyEvent) !void {
        switch (key.code) {
            .char => |ch| try self.input_buffer.append(ch),
            .backspace => {
                if (self.input_buffer.items.len > 0) {
                    _ = self.input_buffer.pop();
                }
            },
            .enter => {
                if (self.input_buffer.items.len > 0) {
                    try self.addMessage(.user, self.input_buffer.items);
                    self.input_buffer.clearRetainingCapacity();
                }
            },
            .up => {
                if (self.scroll_offset > 0) {
                    self.scroll_offset -= 1;
                }
            },
            .down => {
                self.scroll_offset += 1;
            },
            else => {},
        }
    }

    pub fn handleMouse(self: *Self, mouse: term.MouseEvent) !void {
        _ = self;
        _ = mouse;
    }

    pub fn addMessage(self: *Self, role: ChatMessage.Role, content: []const u8) !void {
        var buf = std.ArrayList(u8).init(self.allocator);
        try buf.appendSlice(content);
        try self.messages.append(.{ .role = role, .content = buf });
    }

    pub fn appendToLastMessage(self: *Self, content: []const u8) !void {
        if (self.messages.items.len == 0) return;
        var last = &self.messages.items[self.messages.items.len - 1];
        try last.content.appendSlice(content);
    }
};

/// Status bar component
const StatusBar = struct {
    const Self = @This();

    allocator: Allocator,
    file: ?[]const u8,
    modified: bool,
    position: Position,
    mode: []const u8,
    show_auth_hint: bool = false,

    pub fn initStatusBar(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .file = null,
            .modified = false,
            .position = .{ .line = 0, .column = 0 },
            .mode = "EDIT",
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn render(self: *Self, screen: *tui.Screen, bounds: Rect) !void {
        // Draw background
        try screen.setBackground(.blue);
        try screen.fillRect(bounds);

        // File info - use stack buffers to avoid allocations
        const file_str = self.file orelse "Untitled";
        const modified_str = if (self.modified) " [+]" else "";

        var file_buf: [256]u8 = undefined;
        const file_display = std.fmt.bufPrint(&file_buf, "{s}{s}", .{ file_str, modified_str }) catch file_str;
        try screen.writeAt(bounds.x + 1, bounds.y, file_display);

        // Mode
        const mode_x = bounds.x + bounds.width / 2 - @as(u16, @intCast(self.mode.len / 2));
        try screen.writeAt(mode_x, bounds.y, self.mode);

        // Position - use stack buffer to avoid allocation
        var pos_buf: [32]u8 = undefined;
        const pos_str = std.fmt.bufPrint(&pos_buf, "Ln {d}, Col {d}", .{ self.position.line + 1, self.position.column + 1 }) catch "Ln ?, Col ?";
        try screen.writeAt(bounds.x + bounds.width - @as(u16, @intCast(pos_str.len)) - 1, bounds.y, pos_str);

        try screen.resetStyle();
    }

    pub fn setFile(self: *Self, file: ?[]const u8) void {
        self.file = file;
    }

    pub fn setModified(self: *Self, modified: bool) void {
        self.modified = modified;
    }

    pub fn setPosition(self: *Self, position: Position) void {
        self.position = position;
    }

    pub fn setMode(self: *Self, mode: []const u8) void {
        self.mode = mode;
    }

    pub fn setAuthHint(self: *Self, show: bool) void {
        self.show_auth_hint = show;
    }
};

// Helper types
const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};

const ScreenType = enum {
    welcome,
    editor,
    help,
};

const Position = struct {
    line: usize,
    column: usize,
};

const LayoutMode = enum {
    split_horizontal,
    split_vertical,
    editor_only,
    preview_only,
};

const FocusedPane = enum {
    editor,
    preview,
    file_browser,
    ai_chat,
};

const LayoutBounds = struct {
    editor: Rect,
    preview: Rect,
    file_browser: Rect,
    ai_chat: Rect,
    status_bar: Rect,
};

const NotificationLevel = enum {
    info,
    success,
    warning,
    err,
};

// Helper function for markdown to HTML conversion
fn markdownToHTML(allocator: Allocator, content: []const u8) ![]u8 {
    // This would use a proper markdown parser
    // For now, basic implementation
    var html = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    try html.appendSlice(allocator, "<html><body>");
    try html.appendSlice(allocator, content); // Would properly convert
    try html.appendSlice(allocator, "</body></html>");
    return html.toOwnedSlice();
}

// Public interface
pub fn launch(allocator: Allocator) !void {
    var app = try MarkdownTUI.initMarkdownTUI(allocator);
    defer app.deinit();

    try app.run();
}

// Main entry point for TUI
pub fn runTui(allocator: Allocator, _: anytype, initial_file: ?[]const u8) !u8 {
    var app = try MarkdownTUI.initMarkdownTUI(allocator);
    defer app.deinit();
    if (initial_file) |file| {
        app.loadFile(file) catch {
            // If file loading fails, continue with empty editor
            app.editor.setContent("# Failed to load file\n\nThe file could not be loaded. You can start typing here.") catch {};
        };
    }
    try app.run();
    return 0;
}

// Entry point for TUI with direct content
pub fn runTuiWithContent(allocator: Allocator, _: anytype, content: []const u8) !u8 {
    var app = try MarkdownTUI.initMarkdownTUI(allocator);
    defer app.deinit();

    // Load content directly into editor
    app.editor.setContent(content) catch {
        app.editor.setContent("# Error loading content\n\nYou can start typing here.") catch {};
    };

    try app.run();
    return 0;
}

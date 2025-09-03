//! Modern, beautiful TUI for the Markdown Agent
//! Inspired by modern editors like VS Code, with dark theme and smooth interactions

const std = @import("std");
const foundation = @import("foundation");
const tui = foundation.tui;
const ui = foundation.ui;
const render = foundation.render;
const term = foundation.term;
const engine = @import("core_engine");

const Allocator = std.mem.Allocator;

// Modern color palette inspired by VS Code Dark+ theme
pub const Theme = struct {
    // Background colors
    bg_primary: []const u8 = "\x1b[48;2;30;30;30m", // #1e1e1e - main background
    bg_secondary: []const u8 = "\x1b[48;2;37;37;38m", // #252526 - sidebar/panel
    bg_accent: []const u8 = "\x1b[48;2;51;51;51m", // #333333 - hover/active
    bg_selection: []const u8 = "\x1b[48;2;38;79;120m", // #264f78 - selection

    // Text colors
    text_primary: []const u8 = "\x1b[38;2;212;212;212m", // #d4d4d4 - main text
    text_secondary: []const u8 = "\x1b[38;2;153;153;153m", // #999999 - secondary text
    text_muted: []const u8 = "\x1b[38;2;106;153;85m", // #6a9955 - comments/muted
    text_accent: []const u8 = "\x1b[38;2;78;201;176m", // #4ec9b0 - accents
    text_error: []const u8 = "\x1b[38;2;244;71;71m", // #f44747 - errors
    text_success: []const u8 = "\x1b[38;2;115;218;202m", // #73daca - success

    // Border colors
    border_primary: []const u8 = "\x1b[38;2;68;68;68m", // #444444 - main borders
    border_accent: []const u8 = "\x1b[38;2;0;122;204m", // #007acc - accent borders

    // Special colors
    syntax_keyword: []const u8 = "\x1b[38;2;86;156;214m", // #569cd6 - keywords
    syntax_string: []const u8 = "\x1b[38;2;206;145;120m", // #ce9178 - strings
    syntax_comment: []const u8 = "\x1b[38;2;106;153;85m", // #6a9955 - comments

    // Reset
    reset: []const u8 = "\x1b[0m",
};

pub const ModernMarkdownTUI = struct {
    const Self = @This();

    allocator: Allocator,
    terminal: *term.Terminal,
    theme: Theme,

    // Layout state
    terminal_size: struct { width: u32, height: u32 },
    show_help: bool = false,
    show_command_palette: bool = false,

    // Content state
    current_file: ?[]const u8 = null,
    editor_content: std.ArrayList([]const u8),
    editor_cursor: struct { line: u32, col: u32 } = .{ .line = 0, .col = 0 },
    preview_content: ?[]const u8 = null,

    // UI state
    focused_pane: enum { editor, preview, file_browser } = .editor,
    status_message: ?[]const u8 = null,

    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        const terminal = try term.Terminal.init(allocator);

        self.* = .{
            .allocator = allocator,
            .terminal = terminal,
            .theme = Theme{},
            .terminal_size = .{ .width = 80, .height = 24 },
            .editor_content = std.ArrayList([]const u8).init(allocator),
        };

        // Add some sample content
        try self.editor_content.append(try allocator.dupe(u8, "# Welcome to Markdown Agent"));
        try self.editor_content.append(try allocator.dupe(u8, ""));
        try self.editor_content.append(try allocator.dupe(u8, "A modern, powerful markdown editor with AI assistance."));
        try self.editor_content.append(try allocator.dupe(u8, ""));
        try self.editor_content.append(try allocator.dupe(u8, "## Features"));
        try self.editor_content.append(try allocator.dupe(u8, ""));
        try self.editor_content.append(try allocator.dupe(u8, "- ✨ **Beautiful interface** - Modern, VS Code-inspired design"));
        try self.editor_content.append(try allocator.dupe(u8, "- 🚀 **Live preview** - See your markdown rendered in real-time"));
        try self.editor_content.append(try allocator.dupe(u8, "- 🤖 **AI assistance** - Get help with writing and editing"));
        try self.editor_content.append(try allocator.dupe(u8, "- ⚡ **Fast and responsive** - Built with Zig for performance"));

        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.editor_content.items) |line| {
            self.allocator.free(line);
        }
        self.editor_content.deinit();
        if (self.preview_content) |content| {
            self.allocator.free(content);
        }
        self.terminal.deinit();
        self.allocator.destroy(self);
    }

    pub fn run(self: *Self) !void {
        // Setup terminal
        try self.terminal.enterRawMode();
        defer self.terminal.exitRawMode() catch {};

        try self.terminal.enableMouse();
        defer self.terminal.disableMouse() catch {};

        // Get terminal size
        const size = try self.terminal.getSize();
        self.terminal_size = size;

        // Show welcome screen first
        try self.showWelcomeScreen();

        // Main application loop
        var running = true;
        var frame_count: u32 = 0;

        while (running and frame_count < 1200) { // 20 seconds at 60fps
            // Clear screen
            try self.terminal.clear();

            if (self.show_help) {
                try self.renderHelpOverlay();
            } else if (self.show_command_palette) {
                try self.renderCommandPalette();
            } else {
                try self.renderMainInterface();
            }

            try self.terminal.flush();

            // Handle input (simulated for now)
            if (frame_count == 180) { // After 3 seconds, show help
                self.show_help = true;
            } else if (frame_count == 540) { // After 9 seconds, hide help
                self.show_help = false;
            } else if (frame_count == 720) { // After 12 seconds, show command palette
                self.show_command_palette = true;
            } else if (frame_count == 900) { // After 15 seconds, hide command palette
                self.show_command_palette = false;
            }

            frame_count += 1;
            std.Thread.sleep(16_666_667); // 60 FPS
        }

        // Show goodbye message
        try self.showGoodbyeScreen();
    }

    fn showWelcomeScreen(self: *Self) !void {
        try self.terminal.clear();
        const theme = self.theme;

        // Center the welcome content
        const center_y = self.terminal_size.height / 2;
        const center_x = self.terminal_size.width / 2;

        // Draw logo/title
        try self.terminal.write(theme.bg_primary);
        try self.terminal.write(theme.text_accent);

        var y = center_y - 6;
        try self.moveCursor(center_x - 20, y);
        try self.terminal.write("╭─────────────────────────────────────────╮");
        y += 1;
        try self.moveCursor(center_x - 20, y);
        try self.terminal.write("│                                         │");
        y += 1;
        try self.moveCursor(center_x - 20, y);
        try self.terminal.write("│     🚀 Markdown Agent - Modern TUI     │");
        y += 1;
        try self.moveCursor(center_x - 20, y);
        try self.terminal.write("│                                         │");
        y += 1;
        try self.moveCursor(center_x - 20, y);
        try self.terminal.write("╰─────────────────────────────────────────╯");

        // Instructions
        y += 3;
        try self.terminal.write(theme.text_secondary);
        try self.moveCursor(center_x - 15, y);
        try self.terminal.write("Loading beautiful interface...");

        y += 2;
        try self.terminal.write(theme.text_muted);
        try self.moveCursor(center_x - 12, y);
        try self.terminal.write("Press Ctrl+C to exit anytime");

        try self.terminal.write(theme.reset);
        try self.terminal.flush();

        // Brief pause for welcome screen
        std.Thread.sleep(1_000_000_000); // 1 second
    }

    fn renderMainInterface(self: *Self) !void {
        const theme = self.theme;
        try self.terminal.write(theme.bg_primary);
        try self.terminal.write(theme.text_primary);

        // Calculate layout
        const editor_width = self.terminal_size.width / 2;
        const preview_width = self.terminal_size.width - editor_width;
        const content_height = self.terminal_size.height - 3; // Reserve space for status bar

        // Draw editor pane
        try self.renderEditorPane(0, 0, editor_width, content_height);

        // Draw preview pane
        try self.renderPreviewPane(editor_width, 0, preview_width, content_height);

        // Draw status bar
        try self.renderStatusBar(self.terminal_size.height - 2);

        try self.terminal.write(theme.reset);
    }

    fn renderEditorPane(self: *Self, x: u32, y: u32, width: u32, height: u32) !void {
        const theme = self.theme;

        // Draw pane border and title
        try self.terminal.write(theme.border_primary);
        try self.drawBox(x, y, width, height);

        // Pane title
        try self.terminal.write(theme.bg_secondary);
        try self.terminal.write(theme.text_primary);
        try self.moveCursor(x + 2, y);
        try self.terminal.write(" Editor ");

        // Focus indicator
        if (self.focused_pane == .editor) {
            try self.terminal.write(theme.text_accent);
            try self.terminal.write(" ●");
        }

        // Render editor content
        try self.terminal.write(theme.bg_primary);
        try self.terminal.write(theme.text_primary);

        var line_y = y + 2;
        for (self.editor_content.items, 0..) |line, i| {
            if (line_y >= y + height - 1) break;

            try self.moveCursor(x + 2, line_y);

            // Line number
            try self.terminal.write(theme.text_secondary);
            var buf: [8]u8 = undefined;
            const line_num = std.fmt.bufPrint(buf[0..], "{d:>3} ", .{i + 1}) catch "    ";
            try self.terminal.write(line_num);

            // Content with syntax highlighting
            try self.renderMarkdownLine(line, x + 6, line_y, width - 8);

            line_y += 1;
        }

        // Cursor
        if (self.focused_pane == .editor) {
            const cursor_y = y + 2 + self.editor_cursor.line;
            const cursor_x = x + 6 + self.editor_cursor.col;
            try self.moveCursor(cursor_x, cursor_y);
            try self.terminal.write(theme.text_accent);
            try self.terminal.write("│");
        }

        try self.terminal.write(theme.reset);
    }

    fn renderPreviewPane(self: *Self, x: u32, y: u32, width: u32, height: u32) !void {
        const theme = self.theme;

        // Draw pane border and title
        try self.terminal.write(theme.border_primary);
        try self.drawBox(x, y, width, height);

        // Pane title
        try self.terminal.write(theme.bg_secondary);
        try self.terminal.write(theme.text_primary);
        try self.moveCursor(x + 2, y);
        try self.terminal.write(" Preview ");

        // Focus indicator
        if (self.focused_pane == .preview) {
            try self.terminal.write(theme.text_accent);
            try self.terminal.write(" ●");
        }

        // Render preview content
        try self.terminal.write(theme.bg_primary);
        try self.terminal.write(theme.text_primary);

        var preview_y = y + 2;
        for (self.editor_content.items) |line| {
            if (preview_y >= y + height - 1) break;

            try self.moveCursor(x + 2, preview_y);
            try self.renderMarkdownPreview(line, x + 2, preview_y, width - 4);
            preview_y += 1;
        }

        try self.terminal.write(theme.reset);
    }

    fn renderStatusBar(self: *Self, y: u32) !void {
        const theme = self.theme;

        // Status bar background
        try self.terminal.write(theme.bg_accent);
        try self.terminal.write(theme.text_primary);

        try self.moveCursor(0, y);
        // Fill entire width
        var i: u32 = 0;
        while (i < self.terminal_size.width) : (i += 1) {
            try self.terminal.write(" ");
        }

        // Left side - file info
        try self.moveCursor(2, y);
        const filename = self.current_file orelse "Untitled";
        try self.terminal.write(filename);

        // Center - mode
        const mode_text = " EDIT ";
        const center_x = (self.terminal_size.width - mode_text.len) / 2;
        try self.moveCursor(center_x, y);
        try self.terminal.write(theme.bg_selection);
        try self.terminal.write(theme.text_primary);
        try self.terminal.write(mode_text);

        // Right side - cursor position
        try self.terminal.write(theme.bg_accent);
        var buf: [32]u8 = undefined;
        const pos_text = std.fmt.bufPrint(buf[0..], " Ln {d}, Col {d} ", .{ self.editor_cursor.line + 1, self.editor_cursor.col + 1 }) catch " Ln 1, Col 1 ";
        try self.moveCursor(self.terminal_size.width - pos_text.len, y);
        try self.terminal.write(pos_text);

        // Help hint
        try self.moveCursor(2, y + 1);
        try self.terminal.write(theme.text_muted);
        try self.terminal.write("Press F1 for help • Ctrl+P for commands • Ctrl+C to exit");

        try self.terminal.write(theme.reset);
    }

    fn renderHelpOverlay(self: *Self) !void {
        const theme = self.theme;

        // Semi-transparent background
        try self.terminal.write(theme.bg_primary);
        try self.terminal.write(theme.text_primary);

        // Center the help dialog
        const help_width: u32 = 60;
        const help_height: u32 = 20;
        const start_x = (self.terminal_size.width - help_width) / 2;
        const start_y = (self.terminal_size.height - help_height) / 2;

        // Draw help dialog
        try self.terminal.write(theme.bg_secondary);
        try self.drawBox(start_x, start_y, help_width, help_height);

        // Title
        try self.terminal.write(theme.text_accent);
        try self.moveCursor(start_x + 2, start_y);
        try self.terminal.write(" Markdown Agent - Help & Keyboard Shortcuts ");

        // Content
        try self.terminal.write(theme.text_primary);
        var y = start_y + 2;

        const help_sections = [_]struct { title: []const u8, items: []const []const u8 }{
            .{ .title = "Editor Shortcuts", .items = &[_][]const u8{
                "Ctrl+S          Save file",
                "Ctrl+O          Open file",
                "Ctrl+N          New file",
                "Ctrl+Z          Undo",
                "Ctrl+Y          Redo",
            } },
            .{ .title = "Navigation", .items = &[_][]const u8{
                "Tab             Switch panes",
                "Ctrl+1          Focus editor",
                "Ctrl+2          Focus preview",
                "F1              Toggle help",
            } },
        };

        for (help_sections) |section| {
            try self.moveCursor(start_x + 4, y);
            try self.terminal.write(theme.text_accent);
            try self.terminal.write(section.title);
            y += 1;

            try self.terminal.write(theme.text_primary);
            for (section.items) |item| {
                try self.moveCursor(start_x + 6, y);
                try self.terminal.write(item);
                y += 1;
            }
            y += 1;
        }

        // Footer
        try self.moveCursor(start_x + 2, start_y + help_height - 2);
        try self.terminal.write(theme.text_muted);
        try self.terminal.write("Press Escape to close • Use ↑↓ or j/k to scroll");

        try self.terminal.write(theme.reset);
    }

    fn renderCommandPalette(self: *Self) !void {
        const theme = self.theme;

        // Command palette at top
        const palette_height: u32 = 8;
        const palette_width = self.terminal_size.width - 4;
        const start_x: u32 = 2;
        const start_y: u32 = 2;

        // Background for main interface (dimmed)
        try self.renderMainInterface();

        // Command palette overlay
        try self.terminal.write(theme.bg_secondary);
        try self.drawBox(start_x, start_y, palette_width, palette_height);

        // Title
        try self.terminal.write(theme.text_accent);
        try self.moveCursor(start_x + 2, start_y);
        try self.terminal.write(" Command Palette ");

        // Search input
        try self.terminal.write(theme.bg_accent);
        try self.moveCursor(start_x + 2, start_y + 2);
        var i: u32 = 0;
        while (i < palette_width - 4) : (i += 1) {
            try self.terminal.write(" ");
        }
        try self.moveCursor(start_x + 4, start_y + 2);
        try self.terminal.write(theme.text_primary);
        try self.terminal.write("Type to search commands...");

        // Command suggestions
        const commands = [_][]const u8{
            "📝 New File",
            "📂 Open File",
            "💾 Save File",
            "🔍 Find in File",
            "🎨 Change Theme",
        };

        try self.terminal.write(theme.bg_secondary);
        var cmd_y = start_y + 4;
        for (commands) |cmd| {
            try self.moveCursor(start_x + 4, cmd_y);
            try self.terminal.write(theme.text_primary);
            try self.terminal.write(cmd);
            cmd_y += 1;
        }

        try self.terminal.write(theme.reset);
    }

    fn showGoodbyeScreen(self: *Self) !void {
        try self.terminal.clear();
        const theme = self.theme;

        try self.terminal.write(theme.bg_primary);
        try self.terminal.write(theme.text_primary);

        const center_y = self.terminal_size.height / 2;
        const center_x = self.terminal_size.width / 2;

        try self.moveCursor(center_x - 15, center_y - 2);
        try self.terminal.write(theme.text_accent);
        try self.terminal.write("✨ Thanks for using Markdown Agent!");

        try self.moveCursor(center_x - 20, center_y);
        try self.terminal.write(theme.text_secondary);
        try self.terminal.write("The future of markdown editing is here.");

        try self.terminal.write(theme.reset);
        try self.terminal.flush();

        std.Thread.sleep(2_000_000_000); // 2 seconds
    }

    // Helper functions

    fn moveCursor(self: *Self, x: u32, y: u32) !void {
        var buf: [32]u8 = undefined;
        const escape = std.fmt.bufPrint(buf[0..], "\x1b[{d};{d}H", .{ y + 1, x + 1 }) catch return;
        try self.terminal.write(escape);
    }

    fn drawBox(self: *Self, x: u32, y: u32, width: u32, height: u32) !void {
        // Top border
        try self.moveCursor(x, y);
        try self.terminal.write("╭");
        var i: u32 = 1;
        while (i < width - 1) : (i += 1) {
            try self.terminal.write("─");
        }
        try self.terminal.write("╮");

        // Side borders
        var j: u32 = 1;
        while (j < height - 1) : (j += 1) {
            try self.moveCursor(x, y + j);
            try self.terminal.write("│");
            try self.moveCursor(x + width - 1, y + j);
            try self.terminal.write("│");
        }

        // Bottom border
        try self.moveCursor(x, y + height - 1);
        try self.terminal.write("╰");
        i = 1;
        while (i < width - 1) : (i += 1) {
            try self.terminal.write("─");
        }
        try self.terminal.write("╯");
    }

    fn renderMarkdownLine(self: *Self, line: []const u8, x: u32, y: u32, max_width: u32) !void {
        const theme = self.theme;
        _ = max_width;

        try self.moveCursor(x, y);

        if (std.mem.startsWith(u8, line, "# ")) {
            try self.terminal.write(theme.syntax_keyword);
            try self.terminal.write(line);
        } else if (std.mem.startsWith(u8, line, "## ")) {
            try self.terminal.write(theme.text_accent);
            try self.terminal.write(line);
        } else if (std.mem.startsWith(u8, line, "- ")) {
            try self.terminal.write(theme.text_primary);
            try self.terminal.write(line);
        } else {
            try self.terminal.write(theme.text_primary);
            try self.terminal.write(line);
        }
    }

    fn renderMarkdownPreview(self: *Self, line: []const u8, x: u32, y: u32, max_width: u32) !void {
        const theme = self.theme;
        _ = max_width;

        try self.moveCursor(x, y);

        if (std.mem.startsWith(u8, line, "# ")) {
            try self.terminal.write(theme.text_accent);
            try self.terminal.write("▎");
            try self.terminal.write(theme.text_primary);
            try self.terminal.write(line[2..]);
        } else if (std.mem.startsWith(u8, line, "## ")) {
            try self.terminal.write(theme.text_secondary);
            try self.terminal.write("  ▸ ");
            try self.terminal.write(theme.text_primary);
            try self.terminal.write(line[3..]);
        } else if (std.mem.startsWith(u8, line, "- ")) {
            try self.terminal.write(theme.text_muted);
            try self.terminal.write("    • ");
            try self.terminal.write(theme.text_primary);
            try self.terminal.write(line[2..]);
        } else {
            try self.terminal.write(theme.text_primary);
            try self.terminal.write(line);
        }
    }
};

// Public interface
pub fn runModernTui(allocator: Allocator, _: anytype, initial_file: ?[]const u8) !u8 {
    var app = try ModernMarkdownTUI.init(allocator);
    defer app.deinit();

    if (initial_file) |file| {
        app.current_file = file;
    }

    try app.run();
    return 0;
}

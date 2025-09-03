//! Simple working TUI for markdown agent
//! Focuses on getting input handling right

const std = @import("std");
const c = @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
});

const Allocator = std.mem.Allocator;

pub fn runSimpleTui(allocator: Allocator) !void {
    // Save original terminal settings
    var orig_termios: c.struct_termios = undefined;
    _ = c.tcgetattr(c.STDIN_FILENO, &orig_termios);

    // Set terminal to raw mode
    var raw_termios = orig_termios;
    raw_termios.c_lflag &= ~@as(c.tcflag_t, c.ECHO | c.ICANON | c.ISIG | c.IEXTEN);
    raw_termios.c_iflag &= ~@as(c.tcflag_t, c.IXON | c.ICRNL);
    raw_termios.c_cc[c.VMIN] = 1;
    raw_termios.c_cc[c.VTIME] = 0;
    _ = c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &raw_termios);

    // Restore terminal on exit
    defer _ = c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &orig_termios);

    // Enter alternate screen and hide cursor
    const stdout = std.fs.File.stdout();
    try stdout.writeAll("\x1b[?1049h"); // Enter alternate screen
    try stdout.writeAll("\x1b[?25l"); // Hide cursor
    defer {
        stdout.writeAll("\x1b[?25h") catch {}; // Show cursor
        stdout.writeAll("\x1b[?1049l") catch {}; // Exit alternate screen
    }

    var current_screen: enum { welcome, editor } = .welcome;
    var help_visible = false;
    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();

    // Initial render
    try renderScreen(current_screen, help_visible, content.items);

    // Main input loop
    var running = true;
    while (running) {
        // Read one byte from stdin
        var byte: u8 = undefined;
        const result = c.read(c.STDIN_FILENO, &byte, 1);
        if (result <= 0) break;

        // Process input
        switch (byte) {
            3 => { // Ctrl+C
                running = false;
                break;
            },
            27 => { // Escape
                if (current_screen == .editor and help_visible) {
                    help_visible = false;
                } else if (current_screen == .editor) {
                    current_screen = .welcome;
                }
            },
            13, 10 => { // Enter
                if (current_screen == .welcome) {
                    current_screen = .editor;
                    help_visible = false;
                } else if (current_screen == .editor and !help_visible) {
                    try content.append('\n');
                }
            },
            '/', '@' => {
                if (current_screen == .welcome) {
                    current_screen = .editor;
                    help_visible = false;
                    try content.append(byte);
                } else if (current_screen == .editor and !help_visible) {
                    try content.append(byte);
                }
            },
            'h', '?' => {
                if (current_screen == .welcome or current_screen == .editor) {
                    help_visible = !help_visible;
                }
            },
            'q' => {
                if (current_screen == .welcome) {
                    running = false;
                } else if (current_screen == .editor and !help_visible) {
                    try content.append('q');
                }
            },
            127, 8 => { // Backspace
                if (current_screen == .editor and !help_visible and content.items.len > 0) {
                    _ = content.pop();
                }
            },
            else => {
                // Regular printable characters
                if (current_screen == .editor and !help_visible and byte >= 32 and byte < 127) {
                    try content.append(byte);
                }
            },
        }

        // Re-render
        try renderScreen(current_screen, help_visible, content.items);
    }

    // Exit message
    try stdout.writeAll("\x1b[2J\x1b[H");
    try stdout.writeAll("\x1b[32m✓ Markdown Agent session completed\x1b[0m\n");
    try stdout.writeAll("Thank you for using Markdown Agent!\n");
}

fn renderScreen(screen_type: anytype, help_visible: bool, content: []const u8) !void {
    const stdout = std.fs.File.stdout();

    // Clear screen and move to top
    try stdout.writeAll("\x1b[2J\x1b[H");

    if (screen_type == .welcome) {
        try renderWelcomeScreen();
        if (help_visible) {
            try renderHelpOverlay();
        }
    } else {
        try renderEditorScreen(content);
        if (help_visible) {
            try renderHelpOverlay();
        }
    }
}

fn renderWelcomeScreen() !void {
    const stdout = std.fs.File.stdout();

    // Beautiful ASCII art title
    try stdout.writeAll("\x1b[36m\x1b[1m"); // Cyan + Bold
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

    try stdout.writeAll("\x1b[0m"); // Reset
    try stdout.writeAll("\x1b[94m                     Enterprise-grade markdown systems architect\n\n");

    try stdout.writeAll("\x1b[92m    Welcome to Markdown Agent\n\n");

    try stdout.writeAll("\x1b[33m");
    try stdout.writeAll("    Type / to use slash commands\n");
    try stdout.writeAll("    Type @ to mention files\n");
    try stdout.writeAll("    Press Enter to start editing\n");
    try stdout.writeAll("    Ctrl+C or q to exit\n\n");

    try stdout.writeAll("\x1b[36m    Press h or ? for help\n\n");

    try stdout.writeAll("\x1b[95m\x1b[3m");
    try stdout.writeAll("    \"Great software is written with clarity of purpose.\n");
    try stdout.writeAll("     Every line should tell a story.\" - Clean Code Philosophy\n");
    try stdout.writeAll("\x1b[0m");
}

fn renderEditorScreen(content: []const u8) !void {
    const stdout = std.fs.File.stdout();

    // Draw editor layout
    try stdout.writeAll("╭─ Markdown Editor ─────────────────────────────────╮╭─ Preview ─────────────────╮\n");
    try stdout.writeAll("│                                                   ││                           │\n");

    // Display content with proper wrapping
    var lines = std.mem.splitScalar(u8, content, '\n');
    var line_count: usize = 0;
    while (lines.next()) |line| {
        if (line_count >= 18) break; // Limit to available lines

        try stdout.writeAll("│ ");

        // Display line with truncation if too long
        if (line.len <= 48) {
            try stdout.writeAll(line);
            // Pad to full width
            var i: usize = line.len;
            while (i < 48) : (i += 1) {
                try stdout.writeAll(" ");
            }
        } else {
            try stdout.writeAll(line[0..48]);
        }

        try stdout.writeAll(" ││                           │\n");
        line_count += 1;
    }

    // Fill remaining lines
    while (line_count < 18) : (line_count += 1) {
        try stdout.writeAll("│                                                   ││                           │\n");
    }

    try stdout.writeAll("╰───────────────────────────────────────────────────╯╰───────────────────────────╯\n");

    // Status bar
    try stdout.writeAll("\x1b[44m\x1b[37m"); // Blue background, white text
    try stdout.writeAll(" Untitled.md                                                    EDIT              ");
    try stdout.writeAll("\x1b[0m\n");
}

fn renderHelpOverlay() !void {
    const stdout = std.fs.File.stdout();

    // Position help in center
    try stdout.writeAll("\x1b[3;10H"); // Row 3, Col 10

    try stdout.writeAll("\x1b[36m");
    try stdout.writeAll("╭─────────────────────────────────────────────────────────────────────────╮\n");
    try stdout.writeAll("\x1b[4;10H│                    Markdown Agent - Help & Keyboard Shortcuts           │\n");
    try stdout.writeAll("\x1b[5;10H├─────────────────────────────────────────────────────────────────────────┤\n");
    try stdout.writeAll("\x1b[6;10H│                                                                         │\n");
    try stdout.writeAll("\x1b[7;10H│  Navigation:                          Editing:                          │\n");
    try stdout.writeAll("\x1b[8;10H│    Enter      Switch to editor         Backspace     Delete char       │\n");
    try stdout.writeAll("\x1b[9;10H│    Escape     Back to welcome          Any key       Type character    │\n");
    try stdout.writeAll("\x1b[10;10H│   Ctrl+C      Quit                     Enter         New line          │\n");
    try stdout.writeAll("\x1b[11;10H│   h or ?      Toggle help              / or @        Start command     │\n");
    try stdout.writeAll("\x1b[12;10H│                                                                         │\n");
    try stdout.writeAll("\x1b[13;10H├─────────────────────────────────────────────────────────────────────────┤\n");
    try stdout.writeAll("\x1b[14;10H│               Press Escape to close • Press h or ? to toggle            │\n");
    try stdout.writeAll("\x1b[15;10H╰─────────────────────────────────────────────────────────────────────────╯\n");
    try stdout.writeAll("\x1b[0m");
}

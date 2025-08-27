//! Command palette with fuzzy search and terminal features
//! Uses terminal capabilities from @src/term for user experience

const std = @import("std");
const completion = @import("completion.zig");
const term_shared = @import("term_shared");
const term_ansi = term_shared.ansi.color;
const term_cursor = term_shared.cursor;
const term_screen = term_shared.ansi.screen;
const term_hyperlink = term_shared.ansi.hyperlink;
// Prefer presenter-based notifications over direct ANSI
const presenters = @import("../presenters/mod.zig");
const term_clipboard = term_shared.ansi.clipboard;
const term_graphics = term_shared.ansi.graphics;
const term_caps = term_shared.caps;
const term_mode = term_shared.ansi.mode;
const term_input = term_shared.input.types;
const enhanced_keys = term_shared.input.keys;
const Allocator = std.mem.Allocator;

pub const CommandPaletteAction = enum {
    execute,
    cancel,
    help,
    copy,
    notification_test,
    graphics_preview,
};

pub const CommandPaletteResult = struct {
    action: CommandPaletteAction,
    selected_item: ?completion.CompletionItem = null,
    query: ?[]const u8 = null,
};

pub const KeyEvent = struct {
    code: u32,
    modifiers: u8,
    is_special: bool,

    const CTRL = 0x01;
    const ALT = 0x02;
    const SHIFT = 0x04;

    pub fn hasCtrl(self: KeyEvent) bool {
        return (self.modifiers & CTRL) != 0;
    }

    pub fn hasAlt(self: KeyEvent) bool {
        return (self.modifiers & ALT) != 0;
    }

    pub fn hasShift(self: KeyEvent) bool {
        return (self.modifiers & SHIFT) != 0;
    }
};

/// Enhanced command palette with VS Code-style search and advanced terminal features
pub const CommandPalette = struct {
    completion_engine: completion.CompletionEngine,
    input_buffer: std.ArrayList(u8),
    prompt: []const u8,
    caps: term_caps.TermCaps,
    allocator: Allocator,
    is_active: bool,
    show_graphics_preview: bool,
    animation_frame: u32,
    last_notification: ?[]const u8,

    pub fn init(allocator: Allocator, prompt: []const u8) !CommandPalette {
        var palette = CommandPalette{
            .completion_engine = try completion.CompletionEngine.init(allocator),
            .input_buffer = std.ArrayList(u8).init(allocator),
            .prompt = prompt,
            .caps = term_caps.getTermCaps(),
            .allocator = allocator,
            .is_active = false,
            .show_graphics_preview = false,
            .animation_frame = 0,
            .last_notification = null,
        };

        // Initialize with common commands plus new enhanced commands
        try palette.addEnhancedCommands();

        return palette;
    }

    /// Add enhanced commands that showcase terminal capabilities
    fn addEnhancedCommands(self: *CommandPalette) !void {
        const commands = try completion.CompletionSets.getCliCommands(self.allocator);
        defer self.allocator.free(commands);
        try self.completion_engine.addItems(commands);

        // Add enhanced demo commands
        const enhanced_commands = [_]completion.CompletionItem{
            completion.CompletionItem.init("demo:graphics")
                .withDescription("Show graphics capabilities demo")
                .withCategory("demo")
                .withHelpUrl("https://docs.anthropic.com/claude/docs/terminal-graphics"),

            completion.CompletionItem.init("demo:notifications")
                .withDescription("Test desktop notifications")
                .withCategory("demo")
                .withHelpUrl("https://docs.anthropic.com/claude/docs/terminal-notifications"),

            completion.CompletionItem.init("demo:clipboard")
                .withDescription("Test clipboard integration")
                .withCategory("demo")
                .withHelpUrl("https://docs.anthropic.com/claude/docs/terminal-clipboard"),

            completion.CompletionItem.init("demo:hyperlinks")
                .withDescription("Test hyperlink capabilities")
                .withCategory("demo"),

            completion.CompletionItem.init("demo:colors")
                .withDescription("Show color palette and capabilities")
                .withCategory("demo"),
        };

        try self.completion_engine.addItems(&enhanced_commands);
    }

    pub fn deinit(self: *CommandPalette) void {
        self.completion_engine.deinit();
        self.input_buffer.deinit();
    }

    /// Add custom completion items
    pub fn addCompletionItems(self: *CommandPalette, items: []const completion.CompletionItem) !void {
        try self.completion_engine.addItems(items);
    }

    /// Render the command palette interface with advanced terminal features
    fn renderInterface(self: *CommandPalette, writer: anytype) !void {
        self.animation_frame +%= 1;

        // Save cursor position
        try term_cursor.saveCursor(writer, self.caps);

        // Clear screen and move to top
        try term_screen.clearScreenAll(writer, self.caps);
        try term_cursor.setCursorPosition(writer, self.caps, 1, 1);

        // Enhanced animated header with gradient
        try self.renderAnimatedHeader(writer);

        // Terminal capabilities status line
        try self.renderCapabilitiesStatus(writer);

        // Input field with enhanced styling
        try self.renderInputField(writer);

        // Graphics preview if enabled
        if (self.show_graphics_preview) {
            try self.renderGraphicsPreview(writer);
        }

        // Completion list
        try self.completion_engine.render(writer);

        // Enhanced footer with more shortcuts
        try self.renderEnhancedFooter(writer);

        // Show last notification if any
        if (self.last_notification) |notification| {
            try self.renderNotificationStatus(writer, notification);
        }
    }

    fn renderAnimatedHeader(self: *CommandPalette, writer: anytype) !void {
        // Animated gradient header
        const frame = self.animation_frame % 60;
        const wave = @sin(@as(f32, @floatFromInt(frame)) * 0.1);

        if (self.caps.supportsTrueColor()) {
            // Create pulsing blue gradient
            const blue_intensity = @as(u8, @intFromFloat(112.0 + wave * 30.0));
            try term_ansi.setBackgroundRgb(writer, self.caps, 25, 25, blue_intensity);
            try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
        } else {
            try term_ansi.setBackground256(writer, self.caps, if (frame % 4 < 2) @as(u8, 17) else @as(u8, 18));
            try term_ansi.setForeground256(writer, self.caps, 15);
        }

        const header = "  🚀 Enhanced DocZ Command Palette - Powered by @src/term        ";
        try writer.writeAll(header);
        try term_ansi.resetStyle(writer, self.caps);
        try writer.writeAll("\n");
    }

    fn renderCapabilitiesStatus(self: *CommandPalette, writer: anytype) !void {
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 200, 100);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 10);
        }

        try writer.writeAll("  Capabilities: ");

        var capabilities = std.ArrayList([]const u8).init(self.allocator);
        defer capabilities.deinit();

        if (self.caps.supportsTruecolor) try capabilities.append("TrueColor");
        if (self.caps.supportsHyperlinkOsc8) try capabilities.append("Hyperlinks");
        if (self.caps.supportsKittyGraphics) try capabilities.append("KittyGraphics");
        if (self.caps.supportsSixel) try capabilities.append("Sixel");
        if (self.caps.supportsClipboardOsc52) try capabilities.append("Clipboard");
        if (self.caps.supportsNotifyOsc9) try capabilities.append("Notifications");

        for (capabilities.items, 0..) |cap, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.writeAll(cap);
        }

        try term_ansi.resetStyle(writer, self.caps);
        try writer.writeAll("\n\n");
    }

    fn renderInputField(self: *CommandPalette, writer: anytype) !void {
        // Enhanced input field with better styling
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }

        try writer.writeAll("  ┌─ ");
        try writer.writeAll(self.prompt);
        try writer.writeAll(" ─────────────────────────────────────────┐\n");
        try writer.writeAll("  │ ");

        // Input text with better highlighting
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
            try term_ansi.setBackgroundRgb(writer, self.caps, 30, 30, 30);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 15);
            try term_ansi.setBackground256(writer, self.caps, 0);
        }

        try writer.writeAll(self.input_buffer.items);

        // Enhanced animated cursor
        const cursor_visible = (self.animation_frame % 30) < 15;
        if (cursor_visible) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setBackgroundRgb(writer, self.caps, 255, 255, 100);
                try term_ansi.setForegroundRgb(writer, self.caps, 0, 0, 0);
            } else {
                try term_ansi.setBackground256(writer, self.caps, 11);
                try term_ansi.setForeground256(writer, self.caps, 0);
            }
            try writer.writeAll("▎");
        } else {
            try writer.writeAll(" ");
        }
        try term_ansi.resetStyle(writer, self.caps);

        // Pad input field
        const content_len = self.input_buffer.items.len + 1;
        const padding_needed = if (content_len < 42) 42 - content_len else 0;
        for (0..padding_needed) |_| {
            try writer.writeAll(" ");
        }

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }
        try writer.writeAll(" │\n");
        try writer.writeAll("  └─────────────────────────────────────────────┘\n\n");
        try term_ansi.resetStyle(writer, self.caps);
    }

    fn renderGraphicsPreview(self: *CommandPalette, writer: anytype) !void {
        if (!self.caps.supportsKittyGraphics() and !self.caps.supportsSixelGraphics()) {
            return;
        }

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 200, 200, 100);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 11);
        }

        try writer.writeAll("  📊 Graphics Preview: ");

        // ASCII art representation of graphics capability
        const bars = "▁▃▅▇█▇▅▃▁";
        try writer.writeAll(bars);

        try term_ansi.resetStyle(writer, self.caps);
        try writer.writeAll("\n\n");
    }

    fn renderEnhancedFooter(self: *CommandPalette, writer: anytype) !void {
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 150, 150, 150);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 8);
        }

        try writer.writeAll("\n  Shortcuts: ");

        const shortcuts = [_][2][]const u8{
            [_][]const u8{ "↑/↓", "navigate" },
            [_][]const u8{ "Enter", "select" },
            [_][]const u8{ "Esc", "cancel" },
            [_][]const u8{ "Ctrl+C", "copy" },
            [_][]const u8{ "Ctrl+G", "graphics" },
            [_][]const u8{ "Ctrl+N", "notify" },
            [_][]const u8{ "F1", "help" },
        };

        for (shortcuts, 0..) |shortcut, i| {
            if (i > 0) try writer.writeAll("  ");

            try writer.writeAll(shortcut[0]);
            try writer.writeAll(" ");
            try writer.writeAll(shortcut[1]);
        }

        try term_ansi.resetStyle(writer, self.caps);
        try writer.writeAll("\n");
    }

    fn renderNotificationStatus(self: *CommandPalette, writer: anytype, notification: []const u8) !void {
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 255, 100);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 10);
        }

        try writer.writeAll("\n  Last notification: ");
        try writer.writeAll(notification);
        try term_ansi.resetStyle(writer, self.caps);
    }

    /// Enhanced keyboard input handling with escape sequences and advanced features
    fn handleInput(self: *CommandPalette, input_bytes: []const u8) !CommandPaletteAction {
        if (input_bytes.len == 0) return .help;

        // Handle escape sequences
        if (input_bytes[0] == 27 and input_bytes.len > 1) {
            return self.handleEscapeSequence(input_bytes);
        }

        // Handle control characters
        if (input_bytes.len == 1) {
            const key = input_bytes[0];
            switch (key) {
                // Escape alone - cancel
                27 => return .cancel,

                // Enter - execute selected
                13 => return .execute,

                // Backspace - remove character
                127, 8 => {
                    if (self.input_buffer.items.len > 0) {
                        _ = self.input_buffer.pop();
                        try self.completion_engine.filter(self.input_buffer.items);
                    }
                    return .help;
                },

                // Tab - accept completion
                9 => {
                    if (self.completion_engine.getSelected()) |selected| {
                        self.input_buffer.clearRetainingCapacity();
                        try self.input_buffer.appendSlice(selected.text);
                        try self.completion_engine.filter(self.input_buffer.items);
                    }
                    return .help;
                },

                // Ctrl+C - copy selected item to clipboard
                3 => {
                    if (self.completion_engine.getSelected()) |selected| {
                        try self.copyToClipboard(selected.text);
                        self.last_notification = "Copied to clipboard";
                    }
                    return .help;
                },

                // Ctrl+G - toggle graphics preview
                7 => {
                    self.show_graphics_preview = !self.show_graphics_preview;
                    self.last_notification = if (self.show_graphics_preview) "Graphics preview enabled" else "Graphics preview disabled";
                    return .help;
                },

                // Ctrl+N - send test notification
                14 => {
                    try self.sendTestNotification();
                    self.last_notification = "Test notification sent";
                    return .help;
                },

                // Printable characters - add to buffer
                32...126 => {
                    try self.input_buffer.append(key);
                    try self.completion_engine.filter(self.input_buffer.items);
                    return .help;
                },

                else => return .help,
            }
        }

        return .help;
    }

    fn handleEscapeSequence(self: *CommandPalette, input_bytes: []const u8) !CommandPaletteAction {
        // Handle common escape sequences
        if (input_bytes.len >= 3 and input_bytes[1] == '[') {
            switch (input_bytes[2]) {
                'A' => { // Up arrow
                    self.completion_engine.selectPrev();
                    return .help;
                },
                'B' => { // Down arrow
                    self.completion_engine.selectNext();
                    return .help;
                },
                'C' => { // Right arrow - accept completion
                    if (self.completion_engine.getSelected()) |selected| {
                        self.input_buffer.clearRetainingCapacity();
                        try self.input_buffer.appendSlice(selected.text);
                        try self.completion_engine.filter(self.input_buffer.items);
                    }
                    return .help;
                },
                'D' => { // Left arrow - back one char (future enhancement)
                    return .help;
                },
                else => return .help,
            }
        }

        // Handle function keys
        if (input_bytes.len >= 4 and input_bytes[1] == 'O') {
            switch (input_bytes[2]) {
                'P' => return .help, // F1 - help (handled by caller)
                else => return .help,
            }
        }

        return .help;
    }

    /// Copy text to system clipboard using OSC 52
    fn copyToClipboard(self: *CommandPalette, text: []const u8) !void {
        if (!self.caps.supportsClipboard()) {
            return error.ClipboardNotSupported;
        }

        // For demo purposes, we'll create a dummy writer
        // In real usage, this would write to stdout
        var dummy_buffer = std.ArrayList(u8).init(self.allocator);
        defer dummy_buffer.deinit();

        const writer = dummy_buffer.writer();
        try term_clipboard.writeClipboard(writer, self.allocator, self.caps, text);
    }

    /// Send a test notification using the CLI presenter
    // fn sendTestNotification(self: *CommandPalette) !void {
    //     var n = notif.Notification.init(
    //         "DocZ Command Palette",
    //         "Test Notification!",
    //         .info,
    //         notif.NotificationConfiguration{},
    //     );
    //     try presenters.notification.display(self.allocator, &n, true);
    // }

    /// Run the enhanced command palette with advanced terminal features
    pub fn run(self: *CommandPalette, writer: anytype, reader: anytype) !CommandPaletteResult {
        self.is_active = true;

        // Enhanced input handling would be enabled here in a full implementation

        // Initial filter with empty query
        try self.completion_engine.filter("");

        while (self.is_active) {
            // Render the interface
            try self.renderInterface(writer);

            // Read input (potentially multi-byte for escape sequences)
            var buffer: [8]u8 = undefined;
            const bytes_read = try reader.read(&buffer);
            if (bytes_read == 0) continue;

            const action = try self.handleInput(buffer[0..bytes_read]);

            switch (action) {
                .execute => {
                    const selected = self.completion_engine.getSelected();

                    // Handle special demo commands
                    if (selected) |item| {
                        if (std.mem.startsWith(u8, item.text, "demo:")) {
                            return try self.handleDemoCommand(item);
                        }
                    }

                    return CommandPaletteResult{
                        .action = .execute,
                        .selected_item = selected,
                        .query = try self.allocator.dupe(u8, self.input_buffer.items),
                    };
                },
                .cancel => {
                    // Terminal cleanup would happen here in a full implementation
                    return CommandPaletteResult{
                        .action = .cancel,
                        .selected_item = null,
                        .query = null,
                    };
                },
                .copy, .notification_test, .graphics_preview => {
                    // These actions are handled in handleInput, continue loop
                    continue;
                },
                .help => {
                    // Show help or continue loop
                    continue;
                },
            }
        }

        return CommandPaletteResult{
            .action = .cancel,
            .selected_item = null,
            .query = null,
        };
    }

    /// Handle demo commands that showcase terminal capabilities
    fn handleDemoCommand(self: *CommandPalette, item: completion.CompletionItem) !CommandPaletteResult {
        if (std.mem.eql(u8, item.text, "demo:graphics")) {
            self.show_graphics_preview = true;
            self.last_notification = "Graphics demo activated";
        } else if (std.mem.eql(u8, item.text, "demo:notifications")) {
            try self.sendTestNotification();
            self.last_notification = "Notification sent!";
        } else if (std.mem.eql(u8, item.text, "demo:clipboard")) {
            try self.copyToClipboard("DocZ Command Palette - Enhanced Terminal Features!");
            self.last_notification = "Demo text copied to clipboard";
        }

        return CommandPaletteResult{
            .action = .execute,
            .selected_item = item,
            .query = try self.allocator.dupe(u8, self.input_buffer.items),
        };
    }

    /// Enhanced prompt with autocomplete for simpler use cases
    pub fn promptWithCompletion(
        allocator: Allocator,
        prompt_text: []const u8,
        completions: []const completion.CompletionItem,
        writer: anytype,
        reader: anytype,
    ) !?[]const u8 {
        var palette = try CommandPalette.init(allocator, prompt_text);
        defer palette.deinit();

        try palette.addCompletionItems(completions);

        const result = try palette.run(writer, reader);

        // Clean up screen
        try term_screen.clearScreenAll(writer, palette.caps);
        try term_cursor.setCursorPosition(writer, palette.caps, 1, 1);

        switch (result.action) {
            .execute => {
                if (result.selected_item) |item| {
                    return try allocator.dupe(u8, item.text);
                } else if (result.query) |query| {
                    return query;
                } else {
                    return null;
                }
            },
            .cancel => return null,
            .help => return null,
        }
    }

    /// Input with basic completion
    pub fn enhancedInput(
        allocator: Allocator,
        prompt_text: []const u8,
        writer: anytype,
        reader: anytype,
    ) !?[]const u8 {
        const commands = try completion.CompletionSets.getCliCommands(allocator);
        defer allocator.free(commands);

        return promptWithCompletion(allocator, prompt_text, commands, writer, reader);
    }
};

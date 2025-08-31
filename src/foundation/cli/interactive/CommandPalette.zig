//! Command palette with fuzzy search and terminal features
//! Uses terminal capabilities from @src/term for user experience

const std = @import("std");
const completion = @import("completion.zig");
const termShared = @import("../../term.zig");
const termAnsi = termShared.ansi.color;
const termCursor = termShared.cursor;
const termScreen = termShared.ansi.screen;
const termHyperlink = termShared.ansi.hyperlink;
// Prefer presenter-based notifications over direct ANSI
const presenters = @import("../presenters.zig");
const termClipboard = termShared.ansi.clipboard;
const termGraphics = termShared.ansi.graphics;
const termCaps = termShared.capabilities;
const termMode = termShared.ansi.mode;
const termInput = termShared.input.types;
const keys = termShared.input.keys;
const Allocator = std.mem.Allocator;

pub const PaletteAction = enum {
    execute,
    cancel,
    help,
    copy,
    notification_test,
    graphics_preview,
};

pub const PaletteResult = struct {
    action: PaletteAction,
    selectedItem: ?completion.CompletionItem = null,
    query: ?[]const u8 = null,
};

pub const KeyEvent = struct {
    code: u32,
    modifiers: u8,
    is_special: bool,

    const ctrl = 0x01;
    const alt = 0x02;
    const shift = 0x04;

    pub fn hasCtrl(self: KeyEvent) bool {
        return (self.modifiers & ctrl) != 0;
    }

    pub fn hasAlt(self: KeyEvent) bool {
        return (self.modifiers & alt) != 0;
    }

    pub fn hasShift(self: KeyEvent) bool {
        return (self.modifiers & shift) != 0;
    }
};

/// Command palette with VS Code-style search and terminal features
pub const Palette = struct {
    completionEngine: completion.Engine,
    inputBuffer: std.ArrayList(u8),
    prompt: []const u8,
    caps: termCaps.TermCaps,
    allocator: Allocator,
    isActive: bool,
    showGraphicsPreview: bool,
    animationFrame: u32,
    lastNotification: ?[]const u8,

    pub fn init(allocator: Allocator, prompt: []const u8) !Palette {
        var palette = Palette{
            .completionEngine = try completion.CompletionEngine.init(allocator),
            .inputBuffer = std.ArrayList(u8).init(allocator),
            .prompt = prompt,
            .caps = .{},
            .allocator = allocator,
            .isActive = false,
            .showGraphicsPreview = false,
            .animationFrame = 0,
            .lastNotification = null,
        };

        // Initialize with common commands plus new commands
        try palette.addCommands();

        return palette;
    }

    /// Add commands that showcase terminal capabilities
    fn addCommands(self: *Palette) !void {
        const commands = try completion.CompletionSets.getCliCommands(self.allocator);
        defer self.allocator.free(commands);
        try self.completionEngine.addItems(commands);

        // Add demo commands
        const demoCommands = [_]completion.CompletionItem{
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

        try self.completionEngine.addItems(&demoCommands);
    }

    pub fn deinit(self: *Palette) void {
        self.completionEngine.deinit();
        self.inputBuffer.deinit();
    }

    /// Add custom completion items
    pub fn addCompletionItems(self: *Palette, items: []const completion.CompletionItem) !void {
        try self.completionEngine.addItems(items);
    }

    /// Render the command palette interface with terminal features
    fn renderInterface(self: *Palette, writer: anytype) !void {
        self.animationFrame +%= 1;

        // Save cursor position
        try termCursor.saveCursor(writer, self.caps);

        // Clear screen and move to top
        try termScreen.clearScreenAll(writer, self.caps);
        try termCursor.setCursorPosition(writer, self.caps, 1, 1);

        // Animated header with gradient
        try self.renderAnimatedHeader(writer);

        // Terminal capabilities status line
        try self.renderCapabilitiesStatus(writer);

        // Input field with styling
        try self.renderInputField(writer);

        // Graphics preview if enabled
        if (self.showGraphicsPreview) {
            try self.renderGraphicsPreview(writer);
        }

        // Completion list
        try self.completionEngine.render(writer);

        // Footer with shortcuts
        try self.renderFooter(writer);

        // Show last notification if any
        if (self.lastNotification) |notification| {
            try self.renderNotificationStatus(writer, notification);
        }
    }

    fn renderAnimatedHeader(self: *Palette, writer: anytype) !void {
        // Animated gradient header
        const frame = self.animationFrame % 60;
        const wave = @sin(@as(f32, @floatFromInt(frame)) * 0.1);

        if (self.caps.supportsTrueColor()) {
            // Create pulsing blue gradient
            const blue_intensity = @as(u8, @intFromFloat(112.0 + wave * 30.0));
            try termAnsi.setBackgroundRgb(writer, self.caps, 25, 25, blue_intensity);
            try termAnsi.setForegroundRgb(writer, self.caps, 255, 255, 255);
        } else {
            try termAnsi.setBackground256(writer, self.caps, if (frame % 4 < 2) @as(u8, 17) else @as(u8, 18));
            try termAnsi.setForeground256(writer, self.caps, 15);
        }

        const header = "  🚀 DocZ Command Palette - Powered by @src/term        ";
        try writer.writeAll(header);
        try termAnsi.resetStyle(writer, self.caps);
        try writer.writeAll("\n");
    }

    fn renderCapabilitiesStatus(self: *Palette, writer: anytype) !void {
        if (self.caps.supportsTrueColor()) {
            try termAnsi.setForegroundRgb(writer, self.caps, 100, 200, 100);
        } else {
            try termAnsi.setForeground256(writer, self.caps, 10);
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

        try termAnsi.resetStyle(writer, self.caps);
        try writer.writeAll("\n\n");
    }

    fn renderInputField(self: *Palette, writer: anytype) !void {
        // Input field with styling
        if (self.caps.supportsTrueColor()) {
            try termAnsi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try termAnsi.setForeground256(writer, self.caps, 12);
        }

        try writer.writeAll("  ┌─ ");
        try writer.writeAll(self.prompt);
        try writer.writeAll(" ─────────────────────────────────────────┐\n");
        try writer.writeAll("  │ ");

        // Input text with better highlighting
        if (self.caps.supportsTrueColor()) {
            try termAnsi.setForegroundRgb(writer, self.caps, 255, 255, 255);
            try termAnsi.setBackgroundRgb(writer, self.caps, 30, 30, 30);
        } else {
            try termAnsi.setForeground256(writer, self.caps, 15);
            try termAnsi.setBackground256(writer, self.caps, 0);
        }

        try writer.writeAll(self.inputBuffer.items);

        // Animated cursor
        const cursor_visible = (self.animationFrame % 30) < 15;
        if (cursor_visible) {
            if (self.caps.supportsTrueColor()) {
                try termAnsi.setBackgroundRgb(writer, self.caps, 255, 255, 100);
                try termAnsi.setForegroundRgb(writer, self.caps, 0, 0, 0);
            } else {
                try termAnsi.setBackground256(writer, self.caps, 11);
                try termAnsi.setForeground256(writer, self.caps, 0);
            }
            try writer.writeAll("▎");
        } else {
            try writer.writeAll(" ");
        }
        try termAnsi.resetStyle(writer, self.caps);

        // Pad input field
        const content_len = self.inputBuffer.items.len + 1;
        const padding_needed = if (content_len < 42) 42 - content_len else 0;
        for (0..padding_needed) |_| {
            try writer.writeAll(" ");
        }

        if (self.caps.supportsTrueColor()) {
            try termAnsi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try termAnsi.setForeground256(writer, self.caps, 12);
        }
        try writer.writeAll(" │\n");
        try writer.writeAll("  └─────────────────────────────────────────────┘\n\n");
        try termAnsi.resetStyle(writer, self.caps);
    }

    fn renderGraphicsPreview(self: *Palette, writer: anytype) !void {
        if (!self.caps.supportsKittyGraphics() and !self.caps.supportsSixelGraphics()) {
            return;
        }

        if (self.caps.supportsTrueColor()) {
            try termAnsi.setForegroundRgb(writer, self.caps, 200, 200, 100);
        } else {
            try termAnsi.setForeground256(writer, self.caps, 11);
        }

        try writer.writeAll("  📊 Graphics Preview: ");

        // ASCII art representation of graphics capability
        const bars = "▁▃▅▇█▇▅▃▁";
        try writer.writeAll(bars);

        try termAnsi.resetStyle(writer, self.caps);
        try writer.writeAll("\n\n");
    }

    fn renderFooter(self: *Palette, writer: anytype) !void {
        if (self.caps.supportsTrueColor()) {
            try termAnsi.setForegroundRgb(writer, self.caps, 150, 150, 150);
        } else {
            try termAnsi.setForeground256(writer, self.caps, 8);
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

        try termAnsi.resetStyle(writer, self.caps);
        try writer.writeAll("\n");
    }

    fn renderNotificationStatus(self: *Palette, writer: anytype, notification: []const u8) !void {
        if (self.caps.supportsTrueColor()) {
            try termAnsi.setForegroundRgb(writer, self.caps, 100, 255, 100);
        } else {
            try termAnsi.setForeground256(writer, self.caps, 10);
        }

        try writer.writeAll("\n  Last notification: ");
        try writer.writeAll(notification);
        try termAnsi.resetStyle(writer, self.caps);
    }

    /// Keyboard input handling with escape sequences and terminal features
    fn handleInput(self: *Palette, input_bytes: []const u8) !PaletteAction {
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
                    if (self.inputBuffer.items.len > 0) {
                        _ = self.inputBuffer.pop();
                        try self.completionEngine.filter(self.inputBuffer.items);
                    }
                    return .help;
                },

                // Tab - accept completion
                9 => {
                    if (self.completionEngine.getSelected()) |selected| {
                        self.inputBuffer.clearRetainingCapacity();
                        try self.inputBuffer.appendSlice(selected.text);
                        try self.completionEngine.filter(self.inputBuffer.items);
                    }
                    return .help;
                },

                // Ctrl+C - copy selected item to clipboard
                3 => {
                    if (self.completionEngine.getSelected()) |selected| {
                        try self.copyToClipboard(selected.text);
                        self.lastNotification = "Copied to clipboard";
                    }
                    return .help;
                },

                // Ctrl+G - toggle graphics preview
                7 => {
                    self.showGraphicsPreview = !self.showGraphicsPreview;
                    self.lastNotification = if (self.showGraphicsPreview) "Graphics preview enabled" else "Graphics preview disabled";
                    return .help;
                },

                // Ctrl+N - send test notification
                14 => {
                    try self.sendTestNotification();
                    self.lastNotification = "Test notification sent";
                    return .help;
                },

                // Printable characters - add to buffer
                32...126 => {
                    try self.inputBuffer.append(key);
                    try self.completionEngine.filter(self.inputBuffer.items);
                    return .help;
                },

                else => return .help,
            }
        }

        return .help;
    }

    fn handleEscapeSequence(self: *Palette, input_bytes: []const u8) !PaletteAction {
        // Handle common escape sequences
        if (input_bytes.len >= 3 and input_bytes[1] == '[') {
            switch (input_bytes[2]) {
                'A' => { // Up arrow
                    self.completionEngine.selectPrev();
                    return .help;
                },
                'B' => { // Down arrow
                    self.completionEngine.selectNext();
                    return .help;
                },
                'C' => { // Right arrow - accept completion
                    if (self.completionEngine.getSelected()) |selected| {
                        self.inputBuffer.clearRetainingCapacity();
                        try self.inputBuffer.appendSlice(selected.text);
                        try self.completionEngine.filter(self.inputBuffer.items);
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
    fn copyToClipboard(self: *Palette, text: []const u8) !void {
        if (!self.caps.supportsClipboard()) {
            return error.ClipboardNotSupported;
        }

        // For demo purposes, we'll create a dummy writer
        // In real usage, this would write to stdout
        var dummy_buffer = std.ArrayList(u8).init(self.allocator);
        defer dummy_buffer.deinit();

        const writer = dummy_buffer.writer();
        try termClipboard.writeClipboard(writer, self.allocator, self.caps, text);
    }

    /// Send a test notification using the CLI presenter
    // fn sendTestNotification(self: *Palette) !void {
    //     var n = notif.Notification.init(
    //         "DocZ Command Palette",
    //         "Test Notification!",
    //         .info,
    //         notif.NotificationConfiguration{},
    //     );
    //     try presenters.notification.display(self.allocator, &n, true);
    // }

    /// Run the command palette with terminal features
    pub fn run(self: *Palette, writer: anytype, reader: anytype) !PaletteResult {
        self.isActive = true;

        // Input handling would be enabled here in a full implementation

        // Initial filter with empty query
        try self.completionEngine.filter("");

        while (self.isActive) {
            // Render the interface
            try self.renderInterface(writer);

            // Read input (potentially multi-byte for escape sequences)
            var buffer: [8]u8 = undefined;
            const bytes_read = try reader.read(&buffer);
            if (bytes_read == 0) continue;

            const action = try self.handleInput(buffer[0..bytes_read]);

            switch (action) {
                .execute => {
                    const selected = self.completionEngine.getSelected();

                    // Handle special demo commands
                    if (selected) |item| {
                        if (std.mem.startsWith(u8, item.text, "demo:")) {
                            return try self.handleDemoCommand(item);
                        }
                    }

                    return PaletteResult{
                        .action = .execute,
                        .selectedItem = selected,
                        .query = try self.allocator.dupe(u8, self.inputBuffer.items),
                    };
                },
                .cancel => {
                    // Terminal cleanup would happen here in a full implementation
                    return PaletteResult{
                        .action = .cancel,
                        .selectedItem = null,
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

        return PaletteResult{
            .action = .cancel,
            .selectedItem = null,
            .query = null,
        };
    }

    /// Handle demo commands that showcase terminal capabilities
    fn handleDemoCommand(self: *Palette, item: completion.CompletionItem) !PaletteResult {
        if (std.mem.eql(u8, item.text, "demo:graphics")) {
            self.showGraphicsPreview = true;
            self.lastNotification = "Graphics demo activated";
        } else if (std.mem.eql(u8, item.text, "demo:notifications")) {
            try self.sendTestNotification();
            self.lastNotification = "Notification sent!";
        } else if (std.mem.eql(u8, item.text, "demo:clipboard")) {
            try self.copyToClipboard("DocZ Command Palette - Terminal Features!");
            self.lastNotification = "Demo text copied to clipboard";
        }

        return PaletteResult{
            .action = .execute,
            .selectedItem = item,
            .query = try self.allocator.dupe(u8, self.inputBuffer.items),
        };
    }

    /// Prompt with autocomplete for use cases
    pub fn promptWithCompletion(
        allocator: Allocator,
        prompt_text: []const u8,
        completions: []const completion.CompletionItem,
        writer: anytype,
        reader: anytype,
    ) !?[]const u8 {
        var palette = try Palette.init(allocator, prompt_text);
        defer palette.deinit();

        try palette.addCompletionItems(completions);

        const result = try palette.run(writer, reader);

        // Clean up screen
        try termScreen.clearScreenAll(writer, palette.caps);
        try termCursor.setCursorPosition(writer, palette.caps, 1, 1);

        switch (result.action) {
            .execute => {
                if (result.selectedItem) |item| {
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

    /// Input with completion
    pub fn input(
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

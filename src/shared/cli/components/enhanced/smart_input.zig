//! Smart CLI Input Component
//!
//! This component provides enhanced input capabilities including:
//! - Clipboard integration for paste operations
//! - Smart autocomplete suggestions
//! - Syntax highlighting for different input types
//! - History navigation
//! - Real-time validation with visual feedback

const std = @import("std");
const term_shared = @import("term_shared");
const unified = term_shared.unified;
const terminal_bridge = @import("../../core/terminal_bridge.zig");

/// Input types for specialized handling
pub const InputType = enum {
    text, // Plain text input
    email, // Email validation
    url, // URL validation
    number, // Numeric input only
    password, // Hidden input
    path, // File/directory path with completion
    command, // Command with completion

    pub fn getPrompt(self: InputType) []const u8 {
        return switch (self) {
            .text => "Enter text",
            .email => "Enter email address",
            .url => "Enter URL",
            .number => "Enter number",
            .password => "Enter password",
            .path => "Enter path",
            .command => "Enter command",
        };
    }
};

/// Validation result for user input
pub const ValidationResult = union(enum) {
    valid,
    invalid: []const u8, // Error message
    warning: []const u8, // Warning message
};

/// Configuration for smart input behavior
pub const SmartInputConfig = struct {
    input_type: InputType = .text,
    max_length: ?u32 = null,
    allow_empty: bool = true,
    show_validation: bool = true,
    enable_history: bool = true,
    enable_autocomplete: bool = true,
    enable_clipboard_paste: bool = true,
    placeholder: ?[]const u8 = null,

    // Visual configuration
    prompt_style: unified.Style = terminal_bridge.Styles.INFO,
    input_style: ?unified.Style = null,
    error_style: unified.Style = terminal_bridge.Styles.ERROR,
    success_style: unified.Style = terminal_bridge.Styles.SUCCESS,
    placeholder_style: unified.Style = terminal_bridge.Styles.MUTED,
};

/// Smart input component with enhanced features
pub const SmartInput = struct {
    const Self = @This();

    bridge: *terminal_bridge.TerminalBridge,
    config: SmartInputConfig,

    // Input state
    current_input: std.ArrayList(u8),
    cursor_position: u32 = 0,
    history: std.ArrayList([]const u8),
    history_position: ?u32 = null,

    // Validation state
    last_validation: ValidationResult = .valid,

    // Autocomplete state
    suggestions: std.ArrayList([]const u8),
    selected_suggestion: ?u32 = null,

    pub fn init(allocator: std.mem.Allocator, bridge: *terminal_bridge.TerminalBridge, config: SmartInputConfig) Self {
        return Self{
            .bridge = bridge,
            .config = config,
            .current_input = std.ArrayList(u8).init(allocator),
            .history = std.ArrayList([]const u8).init(allocator),
            .suggestions = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.current_input.deinit();

        // Free history items
        for (self.history.items) |item| {
            self.current_input.allocator.free(item);
        }
        self.history.deinit();

        // Free suggestions
        for (self.suggestions.items) |item| {
            self.current_input.allocator.free(item);
        }
        self.suggestions.deinit();
    }

    /// Prompt for input and return the result
    pub fn prompt(self: *Self, prompt_text: ?[]const u8) ![]const u8 {
        // Clear any previous state
        self.current_input.clearRetainingCapacity();
        self.cursor_position = 0;
        self.history_position = null;
        self.selected_suggestion = null;

        // Show prompt
        const actual_prompt = prompt_text orelse self.config.input_type.getPrompt();
        try self.renderPrompt(actual_prompt);

        // Main input loop
        while (true) {
            // Show current input state
            try self.renderCurrentInput();

            // Handle input (simplified - in real implementation would handle keyboard events)
            // For now, simulate getting user input
            const input_result = try self.simulateInput();

            switch (input_result) {
                .character => |ch| {
                    try self.insertCharacter(ch);
                },
                .enter => {
                    const validation = self.validateInput();
                    switch (validation) {
                        .valid => {
                            const result = try self.current_input.allocator.dupe(u8, self.current_input.items);
                            try self.addToHistory(result);
                            return result;
                        },
                        .invalid => |msg| {
                            try self.showValidationError(msg);
                            continue;
                        },
                        .warning => |msg| {
                            try self.showValidationWarning(msg);
                            // Allow continuing despite warning
                        },
                    }
                },
                .escape => {
                    return error.InputCancelled;
                },
                .backspace => {
                    try self.deleteCharacter();
                },
                .paste => |text| {
                    try self.insertText(text);
                },
                .history_up => {
                    try self.navigateHistory(.up);
                },
                .history_down => {
                    try self.navigateHistory(.down);
                },
            }

            // Update suggestions if autocomplete is enabled
            if (self.config.enable_autocomplete) {
                try self.updateSuggestions();
            }
        }
    }

    /// Render the input prompt
    fn renderPrompt(self: *Self, prompt_text: []const u8) !void {
        try self.bridge.print(prompt_text, self.config.prompt_style);
        try self.bridge.print(": ", null);

        // Show placeholder if input is empty
        if (self.current_input.items.len == 0 and self.config.placeholder != null) {
            try self.bridge.print(self.config.placeholder.?, self.config.placeholder_style);
        }
    }

    /// Render the current input with cursor
    fn renderCurrentInput(self: *Self) !void {
        // Clear line and reposition
        try self.bridge.clearLine();

        const strategy = self.bridge.getRenderStrategy();

        // Render input text with syntax highlighting if supported
        if (strategy.supportsColor()) {
            try self.renderWithSyntaxHighlighting();
        } else {
            try self.bridge.print(self.current_input.items, self.config.input_style);
        }

        // Show cursor position
        if (strategy.supportsColor()) {
            try self.renderCursor();
        }

        // Show validation status
        if (self.config.show_validation) {
            try self.renderValidationStatus();
        }

        // Show suggestions
        if (self.config.enable_autocomplete and self.suggestions.items.len > 0) {
            try self.renderSuggestions();
        }
    }

    /// Render input with syntax highlighting based on input type
    fn renderWithSyntaxHighlighting(self: *Self) !void {
        const input_text = self.current_input.items;

        switch (self.config.input_type) {
            .email => {
                // Highlight email parts differently
                if (std.mem.indexOf(u8, input_text, "@")) |at_pos| {
                    const username = input_text[0..at_pos];
                    const domain = input_text[at_pos..];

                    try self.bridge.print(username, unified.Style{ .fg_color = unified.Colors.CYAN });
                    try self.bridge.print(domain, unified.Style{ .fg_color = unified.Colors.GREEN });
                } else {
                    try self.bridge.print(input_text, unified.Style{ .fg_color = unified.Colors.YELLOW });
                }
            },
            .url => {
                // Highlight URL protocol
                if (std.mem.startsWith(u8, input_text, "https://")) {
                    try self.bridge.print("https://", unified.Style{ .fg_color = unified.Colors.GREEN });
                    try self.bridge.print(input_text[8..], unified.Style{ .fg_color = unified.Colors.CYAN });
                } else if (std.mem.startsWith(u8, input_text, "http://")) {
                    try self.bridge.print("http://", unified.Style{ .fg_color = unified.Colors.YELLOW });
                    try self.bridge.print(input_text[7..], unified.Style{ .fg_color = unified.Colors.CYAN });
                } else {
                    try self.bridge.print(input_text, unified.Style{ .fg_color = unified.Colors.RED });
                }
            },
            .number => {
                // Highlight valid/invalid numbers
                const is_valid_number = std.fmt.parseFloat(f64, input_text) catch null != null;
                const color = if (is_valid_number) unified.Colors.GREEN else unified.Colors.RED;
                try self.bridge.print(input_text, unified.Style{ .fg_color = color });
            },
            .password => {
                // Show asterisks for password
                for (0..input_text.len) |_| {
                    try self.bridge.print("*", unified.Style{ .fg_color = unified.Colors.MAGENTA });
                }
            },
            else => {
                try self.bridge.print(input_text, self.config.input_style);
            },
        }
    }

    /// Render cursor position indicator
    fn renderCursor(self: *Self) !void {
        // Simple cursor indication - could be enhanced with blinking
        try self.bridge.print(" ▏", unified.Style{ .fg_color = unified.Colors.WHITE });
    }

    /// Render validation status indicator
    fn renderValidationStatus(self: *Self) !void {
        switch (self.last_validation) {
            .valid => {
                if (self.current_input.items.len > 0) {
                    try self.bridge.print(" ✓", self.config.success_style);
                }
            },
            .invalid => |msg| {
                try self.bridge.print(" ✗", self.config.error_style);
                try self.bridge.printf(" {s}", .{msg}, self.config.error_style);
            },
            .warning => |msg| {
                try self.bridge.print(" ⚠", unified.Style{ .fg_color = unified.Colors.YELLOW });
                try self.bridge.printf(" {s}", .{msg}, unified.Style{ .fg_color = unified.Colors.YELLOW });
            },
        }
    }

    /// Render autocomplete suggestions
    fn renderSuggestions(self: *Self) !void {
        try self.bridge.print("\n", null);

        for (self.suggestions.items, 0..) |suggestion, i| {
            const is_selected = self.selected_suggestion == i;
            const style = if (is_selected)
                terminal_bridge.Styles.HIGHLIGHT
            else
                terminal_bridge.Styles.MUTED;

            try self.bridge.printf("  {s} {s}\n", .{ if (is_selected) ">" else " ", suggestion }, style);
        }
    }

    /// Insert a character at the current cursor position
    fn insertCharacter(self: *Self, ch: u8) !void {
        if (self.config.max_length) |max_len| {
            if (self.current_input.items.len >= max_len) return;
        }

        try self.current_input.insert(self.cursor_position, ch);
        self.cursor_position += 1;

        // Update validation
        self.last_validation = self.validateInput();
    }

    /// Insert text at the current cursor position
    fn insertText(self: *Self, text: []const u8) !void {
        for (text) |ch| {
            try self.insertCharacter(ch);
        }
    }

    /// Delete character before cursor
    fn deleteCharacter(self: *Self) !void {
        if (self.cursor_position > 0) {
            _ = self.current_input.orderedRemove(self.cursor_position - 1);
            self.cursor_position -= 1;

            // Update validation
            self.last_validation = self.validateInput();
        }
    }

    /// Add input to history
    fn addToHistory(self: *Self, input: []const u8) !void {
        if (!self.config.enable_history or input.len == 0) return;

        const history_item = try self.current_input.allocator.dupe(u8, input);
        try self.history.append(history_item);
    }

    /// Navigate through input history
    fn navigateHistory(self: *Self, direction: enum { up, down }) !void {
        if (!self.config.enable_history or self.history.items.len == 0) return;

        switch (direction) {
            .up => {
                if (self.history_position) |pos| {
                    if (pos > 0) {
                        self.history_position = pos - 1;
                    }
                } else {
                    self.history_position = self.history.items.len - 1;
                }
            },
            .down => {
                if (self.history_position) |pos| {
                    if (pos < self.history.items.len - 1) {
                        self.history_position = pos + 1;
                    } else {
                        self.history_position = null;
                        self.current_input.clearRetainingCapacity();
                        self.cursor_position = 0;
                        return;
                    }
                }
            },
        }

        if (self.history_position) |pos| {
            const history_item = self.history.items[pos];
            self.current_input.clearRetainingCapacity();
            try self.current_input.appendSlice(history_item);
            self.cursor_position = @as(u32, @intCast(history_item.len));
        }
    }

    /// Update autocomplete suggestions based on current input
    fn updateSuggestions(self: *Self) !void {
        // Clear previous suggestions
        for (self.suggestions.items) |item| {
            self.current_input.allocator.free(item);
        }
        self.suggestions.clearRetainingCapacity();

        // Generate suggestions based on input type
        switch (self.config.input_type) {
            .path => {
                try self.generatePathSuggestions();
            },
            .command => {
                try self.generateCommandSuggestions();
            },
            else => {
                // No suggestions for other types currently
            },
        }
    }

    /// Generate file/directory path suggestions
    fn generatePathSuggestions(self: *Self) !void {
        // Simplified path completion - would need more sophisticated logic
        const common_paths = [_][]const u8{
            "/home/",
            "/tmp/",
            "/usr/local/",
            "./",
            "../",
        };

        for (common_paths) |path| {
            const suggestion = try self.current_input.allocator.dupe(u8, path);
            try self.suggestions.append(suggestion);
        }
    }

    /// Generate command suggestions
    fn generateCommandSuggestions(self: *Self) !void {
        const common_commands = [_][]const u8{
            "ls",
            "cd",
            "mkdir",
            "rm",
            "cp",
            "mv",
            "grep",
            "find",
        };

        const input_text = self.current_input.items;

        for (common_commands) |command| {
            if (std.mem.startsWith(u8, command, input_text)) {
                const suggestion = try self.current_input.allocator.dupe(u8, command);
                try self.suggestions.append(suggestion);
            }
        }
    }

    /// Validate current input based on type
    fn validateInput(self: *Self) ValidationResult {
        const input_text = self.current_input.items;

        // Check if empty input is allowed
        if (input_text.len == 0) {
            return if (self.config.allow_empty) .valid else .{ .invalid = "Input cannot be empty" };
        }

        // Check maximum length
        if (self.config.max_length) |max_len| {
            if (input_text.len > max_len) {
                return .{ .invalid = "Input too long" };
            }
        }

        // Type-specific validation
        return switch (self.config.input_type) {
            .text => .valid,
            .email => self.validateEmail(input_text),
            .url => self.validateUrl(input_text),
            .number => self.validateNumber(input_text),
            .password => self.validatePassword(input_text),
            .path => self.validatePath(input_text),
            .command => .valid, // Commands are validated at runtime
        };
    }

    /// Validate email format
    fn validateEmail(self: *Self, email: []const u8) ValidationResult {
        _ = self;

        if (std.mem.indexOf(u8, email, "@") == null) {
            return .{ .invalid = "Email must contain @" };
        }

        if (std.mem.count(u8, email, "@") > 1) {
            return .{ .invalid = "Email can only contain one @" };
        }

        return .valid;
    }

    /// Validate URL format
    fn validateUrl(self: *Self, url: []const u8) ValidationResult {
        _ = self;

        if (!std.mem.startsWith(u8, url, "http://") and !std.mem.startsWith(u8, url, "https://")) {
            return .{ .warning = "URL should start with http:// or https://" };
        }

        return .valid;
    }

    /// Validate number format
    fn validateNumber(self: *Self, number_str: []const u8) ValidationResult {
        _ = self;

        _ = std.fmt.parseFloat(f64, number_str) catch {
            return .{ .invalid = "Not a valid number" };
        };

        return .valid;
    }

    /// Validate password strength
    fn validatePassword(self: *Self, password: []const u8) ValidationResult {
        _ = self;

        if (password.len < 8) {
            return .{ .warning = "Password should be at least 8 characters" };
        }

        return .valid;
    }

    /// Validate path format
    fn validatePath(self: *Self, path: []const u8) ValidationResult {
        _ = self;

        // Basic path validation
        if (std.mem.indexOf(u8, path, "..") != null) {
            return .{ .warning = "Path contains '..' - be careful" };
        }

        return .valid;
    }

    /// Show validation error message
    fn showValidationError(self: *Self, message: []const u8) !void {
        try self.bridge.printf("\n❌ {s}\n", .{message}, self.config.error_style);
    }

    /// Show validation warning message
    fn showValidationWarning(self: *Self, message: []const u8) !void {
        try self.bridge.printf("\n⚠️  {s}\n", .{message}, unified.Style{ .fg_color = unified.Colors.YELLOW });
    }

    /// Simulate input events (in real implementation this would handle actual keyboard input)
    fn simulateInput(self: *Self) !InputEvent {
        _ = self;

        // This is a placeholder - in a real implementation this would:
        // 1. Read keyboard events
        // 2. Handle special keys (arrows, ctrl+c, etc.)
        // 3. Handle clipboard paste events
        // 4. Return appropriate InputEvent

        // For demo purposes, return a sample character
        return InputEvent{ .character = 'a' };
    }
};

/// Input events that can be processed
const InputEvent = union(enum) {
    character: u8,
    enter,
    escape,
    backspace,
    paste: []const u8,
    history_up,
    history_down,
};

/// Preset configurations for common input types
pub const SmartInputPresets = struct {
    /// Basic text input
    pub fn text(bridge: *terminal_bridge.TerminalBridge) SmartInput {
        return SmartInput.init(bridge.allocator, bridge, SmartInputConfig{ .input_type = .text });
    }

    /// Email input with validation
    pub fn email(bridge: *terminal_bridge.TerminalBridge) SmartInput {
        return SmartInput.init(bridge.allocator, bridge, SmartInputConfig{
            .input_type = .email,
            .placeholder = "user@example.com",
        });
    }

    /// Password input with hidden characters
    pub fn password(bridge: *terminal_bridge.TerminalBridge) SmartInput {
        return SmartInput.init(bridge.allocator, bridge, SmartInputConfig{
            .input_type = .password,
            .enable_history = false, // Don't save passwords in history
        });
    }

    /// Path input with autocomplete
    pub fn path(bridge: *terminal_bridge.TerminalBridge) SmartInput {
        return SmartInput.init(bridge.allocator, bridge, SmartInputConfig{
            .input_type = .path,
            .enable_autocomplete = true,
        });
    }
};

test "smart input validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bridge_config = terminal_bridge.Config{};
    var bridge = try terminal_bridge.TerminalBridge.init(allocator, bridge_config);
    defer bridge.deinit();

    var input = SmartInput.init(allocator, &bridge, SmartInputConfig{ .input_type = .email });
    defer input.deinit();

    // Test email validation
    try input.current_input.appendSlice("test@example.com");
    const result = input.validateInput();
    try std.testing.expect(result == .valid);
}

//! Smart Input Component with Advanced Terminal Features
//!
//! Features:
//! - Mouse support for text selection and cursor positioning
//! - Real-time validation with visual feedback
//! - Auto-completion with fuzzy matching
//! - Syntax highlighting for different input types
//! - Clipboard integration (paste support)
//! - Focus events and bracketed paste
//! - History navigation with arrow keys
//! - Multi-line support with proper line wrapping

const std = @import("std");
const unified = @import("../../../src/shared/term/unified.zig");
const caps = @import("../../../src/shared/term/caps.zig");
const terminal_abstraction = @import("../../core/terminal_abstraction.zig");

// Advanced input handling
const input_events = @import("../../../src/shared/term/input/advanced_input_driver.zig");
const mouse_handler = @import("../../../src/shared/term/input/mouse.zig");
const focus_events = @import("../../../src/shared/term/input/focus.zig");
const paste_handler = @import("../../../src/shared/term/input/paste.zig");

const Allocator = std.mem.Allocator;
const TerminalAbstraction = terminal_abstraction.TerminalAbstraction;

/// Smart input validation result
pub const ValidationResult = union(enum) {
    valid: void,
    invalid: []const u8, // Error message
    warning: []const u8, // Warning message
    info: []const u8, // Info message
};

/// Smart input validator function type
pub const ValidatorFn = *const fn (input: []const u8, context: ?*anyopaque) ValidationResult;

/// Auto-completion suggestion
pub const Suggestion = struct {
    text: []const u8,
    description: ?[]const u8 = null,
    score: f32 = 1.0, // Relevance score (0.0 - 1.0)
};

/// Auto-completion provider function type
pub const CompletionProviderFn = *const fn (input: []const u8, cursor_pos: usize, context: ?*anyopaque, allocator: Allocator) anyerror![]Suggestion;

/// Input configuration
pub const InputConfig = struct {
    prompt: []const u8 = "> ",
    placeholder: ?[]const u8 = null,
    max_length: ?usize = null,
    multiline: bool = false,
    password: bool = false,
    enable_mouse: bool = true,
    enable_completion: bool = true,
    enable_validation: bool = true,
    enable_history: bool = true,
    enable_syntax_highlighting: bool = false,
    completion_provider: ?CompletionProviderFn = null,
    validator: ?ValidatorFn = null,
    validator_context: ?*anyopaque = null,
    history_file: ?[]const u8 = null,
    syntax_type: SyntaxType = .none,
};

/// Syntax highlighting types
pub const SyntaxType = enum {
    none,
    shell_command,
    file_path,
    url,
    email,
    json,
    regex,
};

/// Current input state
pub const InputState = struct {
    text: std.ArrayList(u8),
    cursor_position: usize,
    selection_start: ?usize,
    selection_end: ?usize,
    scroll_offset: usize,
    current_line: usize,
    validation_result: ?ValidationResult,
    suggestions: []Suggestion,
    selected_suggestion: ?usize,
    show_suggestions: bool,
};

/// Input Component with Advanced Features
pub const Input = struct {
    allocator: Allocator,
    config: InputConfig,
    terminal: TerminalAbstraction,
    features: terminal_abstraction.TerminalAbstraction.Features,

    // Input state
    state: InputState,
    history: std.ArrayList([]u8),
    history_index: ?usize,

    // Mouse and interaction state
    mouse_enabled: bool,
    focus_enabled: bool,
    paste_enabled: bool,
    last_mouse_x: u16,
    last_mouse_y: u16,

    // Display metrics
    prompt_width: usize,
    display_width: usize,
    display_height: usize,

    // Buffers for rendering
    render_buffer: std.ArrayList(u8),

    pub fn init(allocator: Allocator, terminal: TerminalAbstraction, config: InputConfig) !Input {
        const features = terminal.getFeatures();

        return Input{
            .allocator = allocator,
            .config = config,
            .terminal = terminal,
            .features = features,
            .state = InputState{
                .text = std.ArrayList(u8).init(allocator),
                .cursor_position = 0,
                .selection_start = null,
                .selection_end = null,
                .scroll_offset = 0,
                .current_line = 0,
                .validation_result = null,
                .suggestions = &.{},
                .selected_suggestion = null,
                .show_suggestions = false,
            },
            .history = std.ArrayList([]u8).init(allocator),
            .history_index = null,
            .mouse_enabled = config.enable_mouse and features.mouse_support,
            .focus_enabled = features.mouse_support, // Usually comes together
            .paste_enabled = features.clipboard,
            .last_mouse_x = 0,
            .last_mouse_y = 0,
            .prompt_width = config.prompt.len,
            .display_width = 80, // Will be updated with actual terminal width
            .display_height = 24, // Will be updated with actual terminal height
            .render_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Input) void {
        // Clean up history
        for (self.history.items) |item| {
            self.allocator.free(item);
        }
        self.history.deinit();

        // Clean up suggestions
        if (self.state.suggestions.len > 0) {
            for (self.state.suggestions) |suggestion| {
                self.allocator.free(suggestion.text);
                if (suggestion.description) |desc| {
                    self.allocator.free(desc);
                }
            }
            self.allocator.free(self.state.suggestions);
        }

        self.state.text.deinit();
        self.render_buffer.deinit();
    }

    /// Initialize terminal features for input
    pub fn setup(self: *Input) !void {
        const writer = self.render_buffer.writer();
        self.render_buffer.clearRetainingCapacity();

        // Enable mouse reporting if supported
        if (self.mouse_enabled) {
            try writer.writeAll("\x1b[?1000h\x1b[?1002h\x1b[?1015h\x1b[?1006h");
        }

        // Enable focus reporting if supported
        if (self.focus_enabled) {
            try writer.writeAll("\x1b[?1004h");
        }

        // Enable bracketed paste if supported
        if (self.paste_enabled) {
            try writer.writeAll("\x1b[?2004h");
        }

        // Send setup commands to terminal
        if (self.render_buffer.items.len > 0) {
            try self.terminal.print(self.render_buffer.items, null);
        }

        // Load history from file if configured
        if (self.config.history_file) |file_path| {
            self.loadHistory(file_path) catch |err| {
                // Non-critical error, just log and continue
                std.log.warn("Failed to load history from {s}: {}", .{ file_path, err });
            };
        }
    }

    /// Clean up terminal features after input
    pub fn cleanup(self: *Input) !void {
        const writer = self.render_buffer.writer();
        self.render_buffer.clearRetainingCapacity();

        // Disable mouse reporting
        if (self.mouse_enabled) {
            try writer.writeAll("\x1b[?1000l\x1b[?1002l\x1b[?1015l\x1b[?1006l");
        }

        // Disable focus reporting
        if (self.focus_enabled) {
            try writer.writeAll("\x1b[?1004l");
        }

        // Disable bracketed paste
        if (self.paste_enabled) {
            try writer.writeAll("\x1b[?2004l");
        }

        // Send cleanup commands to terminal
        if (self.render_buffer.items.len > 0) {
            try self.terminal.print(self.render_buffer.items, null);
        }

        // Save history to file if configured
        if (self.config.history_file) |file_path| {
            self.saveHistory(file_path) catch |err| {
                std.log.warn("Failed to save history to {s}: {}", .{ file_path, err });
            };
        }
    }

    /// Read input with all smart features enabled
    pub fn readInput(self: *Input) ![]const u8 {
        try self.setup();
        defer self.cleanup() catch {};

        // Show cursor and initial render
        try self.terminal.showCursor(true);
        try self.render();

        while (true) {
            // Read input event (this would be implemented with proper input handling)
            const event = try self.readInputEvent();

            const should_exit = try self.handleInputEvent(event);
            if (should_exit) {
                break;
            }

            // Re-render if needed
            try self.render();
        }

        // Add to history if not empty and not duplicate
        if (self.state.text.items.len > 0 and !self.isDuplicateHistory()) {
            const history_entry = try self.allocator.dupe(u8, self.state.text.items);
            try self.history.append(history_entry);
        }

        return try self.allocator.dupe(u8, self.state.text.items);
    }

    /// Handle a single input event
    fn handleInputEvent(self: *Input, event: InputEvent) !bool {
        switch (event) {
            .key => |key_event| return try self.handleKeyEvent(key_event),
            .mouse => |mouse_event| try self.handleMouseEvent(mouse_event),
            .paste => |paste_data| try self.handlePaste(paste_data),
            .focus => |focus_event| try self.handleFocus(focus_event),
            .resize => |size| try self.handleResize(size),
        }
        return false;
    }

    /// Handle keyboard input
    fn handleKeyEvent(self: *Input, key: KeyEvent) !bool {
        switch (key.key) {
            .char => |c| {
                if (key.modifiers.ctrl) {
                    return try self.handleControlKey(c);
                } else {
                    try self.insertChar(c);
                    try self.updateValidation();
                    try self.updateCompletion();
                }
            },
            .enter => return true, // Exit input loop
            .backspace => {
                try self.deleteChar();
                try self.updateValidation();
                try self.updateCompletion();
            },
            .delete => {
                try self.deleteCharForward();
                try self.updateValidation();
                try self.updateCompletion();
            },
            .arrow_left => try self.moveCursorLeft(),
            .arrow_right => try self.moveCursorRight(),
            .arrow_up => try self.navigateHistory(.up),
            .arrow_down => try self.navigateHistory(.down),
            .home => self.state.cursor_position = 0,
            .end => self.state.cursor_position = self.state.text.items.len,
            .tab => try self.handleTabCompletion(),
            .escape => try self.handleEscape(),
        }
        return false;
    }

    /// Handle control key combinations
    fn handleControlKey(self: *Input, c: u8) !bool {
        switch (c) {
            'c' => return true, // Ctrl+C - cancel
            'd' => return true, // Ctrl+D - EOF
            'u' => {
                // Ctrl+U - clear line
                self.state.text.clearRetainingCapacity();
                self.state.cursor_position = 0;
                try self.updateValidation();
            },
            'w' => {
                // Ctrl+W - delete word backward
                try self.deleteWordBackward();
                try self.updateValidation();
            },
            'k' => {
                // Ctrl+K - kill to end of line
                try self.deleteToEndOfLine();
                try self.updateValidation();
            },
            'a' => self.state.cursor_position = 0, // Ctrl+A - beginning of line
            'e' => self.state.cursor_position = self.state.text.items.len, // Ctrl+E - end of line
            'v' => {
                // Ctrl+V - paste from clipboard
                if (self.paste_enabled) {
                    // Request paste - this would trigger a paste event
                    try self.requestPaste();
                }
            },
            else => {},
        }
        return false;
    }

    /// Handle mouse events
    fn handleMouseEvent(self: *Input, mouse: MouseEvent) !void {
        if (!self.mouse_enabled) return;

        switch (mouse.action) {
            .click => {
                // Position cursor at click location
                const click_pos = self.screenPosToTextPos(mouse.x, mouse.y);
                self.state.cursor_position = click_pos;
            },
            .drag => {
                // Handle text selection
                if (self.state.selection_start == null) {
                    self.state.selection_start = self.state.cursor_position;
                }
                const drag_pos = self.screenPosToTextPos(mouse.x, mouse.y);
                self.state.selection_end = drag_pos;
                self.state.cursor_position = drag_pos;
            },
            .scroll_up => {
                if (self.state.show_suggestions) {
                    try self.scrollSuggestions(.up);
                } else {
                    try self.scrollInput(.up);
                }
            },
            .scroll_down => {
                if (self.state.show_suggestions) {
                    try self.scrollSuggestions(.down);
                } else {
                    try self.scrollInput(.down);
                }
            },
        }

        self.last_mouse_x = mouse.x;
        self.last_mouse_y = mouse.y;
    }

    /// Render the complete input interface
    fn render(self: *Input) !void {
        self.render_buffer.clearRetainingCapacity();
        const writer = self.render_buffer.writer();

        // Clear line and render prompt
        try writer.writeAll("\r\x1b[K");

        // Render prompt with styling
        try self.renderPrompt(writer);

        // Render input text with syntax highlighting if enabled
        try self.renderInputText(writer);

        // Render cursor
        try self.renderCursor(writer);

        // Render validation feedback
        if (self.config.enable_validation and self.state.validation_result != null) {
            try self.renderValidation(writer);
        }

        // Render suggestions if enabled and visible
        if (self.config.enable_completion and self.state.show_suggestions) {
            try self.renderSuggestions(writer);
        }

        // Send to terminal
        try self.terminal.print(self.render_buffer.items, null);
    }

    /// Render the input prompt
    fn renderPrompt(self: *Input, writer: anytype) !void {
        // Apply accent styling if terminal supports it
        if (self.features.truecolor) {
            // Would apply CliStyles.ACCENT here in full implementation
        }
        try writer.writeAll(self.config.prompt);
    }

    /// Render input text with optional syntax highlighting
    fn renderInputText(self: *Input, writer: anytype) !void {
        const text = self.state.text.items;

        if (self.config.enable_syntax_highlighting and self.features.truecolor) {
            try self.renderSyntaxHighlighted(writer, text);
        } else {
            // Render with selection highlighting if active
            if (self.state.selection_start != null and self.state.selection_end != null) {
                try self.renderWithSelection(writer, text);
            } else {
                try writer.writeAll(text);
            }
        }
    }

    /// Render text with syntax highlighting
    fn renderSyntaxHighlighted(self: *Input, writer: anytype, text: []const u8) !void {
        // Basic syntax highlighting based on type
        switch (self.config.syntax_type) {
            .none => try writer.writeAll(text),
            .shell_command => try self.renderShellSyntax(writer, text),
            .file_path => try self.renderPathSyntax(writer, text),
            .url => try self.renderURLSyntax(writer, text),
            .email => try self.renderEmailSyntax(writer, text),
            .json => try self.renderJsonSyntax(writer, text),
            .regex => try self.renderRegexSyntax(writer, text),
        }
    }

    /// Render validation feedback
    fn renderValidation(self: *Input, writer: anytype) !void {
        const validation = self.state.validation_result orelse return;

        try writer.writeAll("\n  ");

        switch (validation) {
            .valid => {
                if (self.features.truecolor) {
                    // Apply success color
                }
                try writer.writeAll("✓ Valid");
            },
            .invalid => |msg| {
                if (self.features.truecolor) {
                    // Apply error color
                }
                try writer.print("✗ {s}", .{msg});
            },
            .warning => |msg| {
                if (self.features.truecolor) {
                    // Apply warning color
                }
                try writer.print("⚠ {s}", .{msg});
            },
            .info => |msg| {
                if (self.features.truecolor) {
                    // Apply info color
                }
                try writer.print("ℹ {s}", .{msg});
            },
        }

        // Move cursor back to input position
        try writer.writeAll("\x1b[A\x1b[G"); // Up one line, beginning of line
        try writer.print("\x1b[{d}C", .{self.prompt_width + self.getDisplayCursorPos()});
    }

    /// Render auto-completion suggestions
    fn renderSuggestions(self: *Input, writer: anytype) !void {
        if (self.state.suggestions.len == 0) return;

        try writer.writeAll("\n");

        const max_suggestions = @min(5, self.state.suggestions.len);
        for (self.state.suggestions[0..max_suggestions], 0..) |suggestion, i| {
            const is_selected = self.state.selected_suggestion == i;

            if (is_selected and self.features.truecolor) {
                // Apply selection background
            }

            try writer.print("  {s}", .{suggestion.text});
            if (suggestion.description) |desc| {
                try writer.print(" - {s}", .{desc});
            }

            if (i < max_suggestions - 1) {
                try writer.writeAll("\n");
            }
        }

        // Move cursor back to input position
        const lines_to_move = max_suggestions;
        try writer.print("\x1b[{d}A\x1b[G", .{lines_to_move}); // Up N lines, beginning of line
        try writer.print("\x1b[{d}C", .{self.prompt_width + self.getDisplayCursorPos()});
    }

    /// Update validation status
    fn updateValidation(self: *Input) !void {
        if (!self.config.enable_validation or self.config.validator == null) return;

        const validator = self.config.validator.?;
        self.state.validation_result = validator(self.state.text.items, self.config.validator_context);
    }

    /// Update auto-completion suggestions
    fn updateCompletion(self: *Input) !void {
        if (!self.config.enable_completion or self.config.completion_provider == null) return;

        // Clear existing suggestions
        if (self.state.suggestions.len > 0) {
            for (self.state.suggestions) |suggestion| {
                self.allocator.free(suggestion.text);
                if (suggestion.description) |desc| {
                    self.allocator.free(desc);
                }
            }
            self.allocator.free(self.state.suggestions);
        }

        // Get new suggestions
        const provider = self.config.completion_provider.?;
        self.state.suggestions = try provider(self.state.text.items, self.state.cursor_position, self.config.validator_context, self.allocator);

        self.state.show_suggestions = self.state.suggestions.len > 0;
        self.state.selected_suggestion = if (self.state.suggestions.len > 0) 0 else null;
    }

    // ========== HELPER FUNCTIONS ==========

    fn insertChar(self: *Input, c: u8) !void {
        if (self.config.max_length != null and self.state.text.items.len >= self.config.max_length.?) {
            return;
        }

        try self.state.text.insert(self.state.cursor_position, c);
        self.state.cursor_position += 1;
    }

    fn deleteChar(self: *Input) !void {
        if (self.state.cursor_position > 0) {
            _ = self.state.text.orderedRemove(self.state.cursor_position - 1);
            self.state.cursor_position -= 1;
        }
    }

    fn deleteCharForward(self: *Input) !void {
        if (self.state.cursor_position < self.state.text.items.len) {
            _ = self.state.text.orderedRemove(self.state.cursor_position);
        }
    }

    fn moveCursorLeft(self: *Input) !void {
        if (self.state.cursor_position > 0) {
            self.state.cursor_position -= 1;
        }
    }

    fn moveCursorRight(self: *Input) !void {
        if (self.state.cursor_position < self.state.text.items.len) {
            self.state.cursor_position += 1;
        }
    }

    fn getDisplayCursorPos(self: Input) usize {
        return self.state.cursor_position - self.state.scroll_offset;
    }

    fn screenPosToTextPos(self: Input, screen_x: u16, screen_y: u16) usize {
        _ = screen_y;
        // Simple conversion - would be more complex for multi-line
        const relative_x = if (screen_x >= self.prompt_width) screen_x - self.prompt_width else 0;
        return @min(self.state.text.items.len, self.state.scroll_offset + relative_x);
    }

    fn isDuplicateHistory(self: Input) bool {
        if (self.history.items.len == 0) return false;
        return std.mem.eql(u8, self.history.items[self.history.items.len - 1], self.state.text.items);
    }

    // ========== PLACEHOLDER IMPLEMENTATIONS ==========
    // These would be fully implemented in a complete version

    fn readInputEvent(self: *Input) !InputEvent {
        _ = self;
        // This would integrate with the actual input system
        return InputEvent{ .key = KeyEvent{ .key = .enter, .modifiers = KeyModifiers{} } };
    }

    fn loadHistory(self: *Input, file_path: []const u8) !void {
        _ = self;
        _ = file_path;
        // Load history from file
    }

    fn saveHistory(self: *Input, file_path: []const u8) !void {
        _ = self;
        _ = file_path;
        // Save history to file
    }

    fn renderShellSyntax(self: *Input, writer: anytype, text: []const u8) !void {
        _ = self;
        try writer.writeAll(text);
    }

    fn renderPathSyntax(self: *Input, writer: anytype, text: []const u8) !void {
        _ = self;
        try writer.writeAll(text);
    }

    fn renderURLSyntax(self: *Input, writer: anytype, text: []const u8) !void {
        _ = self;
        try writer.writeAll(text);
    }

    fn renderEmailSyntax(self: *Input, writer: anytype, text: []const u8) !void {
        _ = self;
        try writer.writeAll(text);
    }

    fn renderJsonSyntax(self: *Input, writer: anytype, text: []const u8) !void {
        _ = self;
        try writer.writeAll(text);
    }

    fn renderRegexSyntax(self: *Input, writer: anytype, text: []const u8) !void {
        _ = self;
        try writer.writeAll(text);
    }

    fn renderWithSelection(self: *Input, writer: anytype, text: []const u8) !void {
        _ = self;
        try writer.writeAll(text);
    }

    fn renderCursor(self: *Input, writer: anytype) !void {
        _ = self;
        _ = writer;
        // Position and render cursor
    }

    fn handleTabCompletion(self: *Input) !void {
        if (self.state.selected_suggestion) |idx| {
            if (idx < self.state.suggestions.len) {
                const suggestion = self.state.suggestions[idx];
                // Replace current word with suggestion
                self.state.text.clearRetainingCapacity();
                try self.state.text.appendSlice(suggestion.text);
                self.state.cursor_position = suggestion.text.len;
                self.state.show_suggestions = false;
            }
        }
    }

    fn handleEscape(self: *Input) !void {
        self.state.show_suggestions = false;
        self.state.selected_suggestion = null;
    }

    fn navigateHistory(self: *Input, direction: enum { up, down }) !void {
        if (self.history.items.len == 0) return;

        switch (direction) {
            .up => {
                if (self.history_index == null) {
                    self.history_index = self.history.items.len - 1;
                } else if (self.history_index.? > 0) {
                    self.history_index = self.history_index.? - 1;
                }
            },
            .down => {
                if (self.history_index != null) {
                    if (self.history_index.? < self.history.items.len - 1) {
                        self.history_index = self.history_index.? + 1;
                    } else {
                        self.history_index = null;
                    }
                }
            },
        }

        // Update input text
        self.state.text.clearRetainingCapacity();
        if (self.history_index) |idx| {
            try self.state.text.appendSlice(self.history.items[idx]);
        }
        self.state.cursor_position = self.state.text.items.len;
    }

    fn deleteWordBackward(self: *Input) !void {
        while (self.state.cursor_position > 0 and self.state.text.items[self.state.cursor_position - 1] == ' ') {
            try self.deleteChar();
        }
        while (self.state.cursor_position > 0 and self.state.text.items[self.state.cursor_position - 1] != ' ') {
            try self.deleteChar();
        }
    }

    fn deleteToEndOfLine(self: *Input) !void {
        self.state.text.shrinkRetainingCapacity(self.state.cursor_position);
    }

    fn requestPaste(self: *Input) !void {
        _ = self;
        // This would request paste from clipboard
    }

    fn handlePaste(self: *Input, data: []const u8) !void {
        try self.state.text.insertSlice(self.state.cursor_position, data);
        self.state.cursor_position += data.len;
    }

    fn handleFocus(self: *Input, focus_event: FocusEvent) !void {
        _ = self;
        _ = focus_event;
        // Handle focus in/out events
    }

    fn handleResize(self: *Input, size: TerminalSize) !void {
        self.display_width = size.width;
        self.display_height = size.height;
    }

    fn scrollSuggestions(self: *Input, direction: enum { up, down }) !void {
        if (self.state.selected_suggestion == null) return;

        switch (direction) {
            .up => {
                if (self.state.selected_suggestion.? > 0) {
                    self.state.selected_suggestion = self.state.selected_suggestion.? - 1;
                }
            },
            .down => {
                if (self.state.selected_suggestion.? < self.state.suggestions.len - 1) {
                    self.state.selected_suggestion = self.state.selected_suggestion.? + 1;
                }
            },
        }
    }

    fn scrollInput(self: *Input, direction: enum { up, down }) !void {
        _ = self;
        _ = direction;
        // Handle input scrolling for long text
    }
};

// ========== INPUT EVENT TYPES ==========

pub const InputEvent = union(enum) {
    key: KeyEvent,
    mouse: MouseEvent,
    paste: []const u8,
    focus: FocusEvent,
    resize: TerminalSize,
};

pub const KeyEvent = struct {
    key: Key,
    modifiers: KeyModifiers,
};

pub const Key = union(enum) {
    char: u8,
    enter,
    backspace,
    delete,
    arrow_left,
    arrow_right,
    arrow_up,
    arrow_down,
    home,
    end,
    tab,
    escape,
};

pub const KeyModifiers = struct {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
};

pub const MouseEvent = struct {
    action: MouseAction,
    x: u16,
    y: u16,
    modifiers: KeyModifiers,
};

pub const MouseAction = enum {
    click,
    drag,
    scroll_up,
    scroll_down,
};

pub const FocusEvent = enum {
    focus_in,
    focus_out,
};

pub const TerminalSize = struct {
    width: usize,
    height: usize,
};

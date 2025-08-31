//! Input Component
//!
//! An adaptive text input component that provides progressive enhancement
//! based on terminal capabilities, including autocomplete, syntax highlighting,
//! and keyboard support.

const std = @import("std");
const Component = @import("../Component.zig");
const Layout = @import("../Layout.zig");
const Event = @import("../Event.zig");
const render_mod = @import("../../render.zig");
const term = @import("../../term.zig");

const ComponentError = Component.ComponentError;

// Type aliases for compatibility
const Point = Layout.Point;
const Rect = Layout.Rect;
const Render = render_mod.Render;
const Color = term.color.Color;
const Style = render_mod.Style;

/// Input features
pub const Feature = packed struct {
    autocomplete: bool = true,
    syntaxHighlighting: bool = true,
    multiLine: bool = false,
    passwordMode: bool = false,
    liveValidation: bool = true,
    placeholder: bool = true,
};

/// Autocomplete suggestion
pub const Suggestion = struct {
    text: []const u8,
    description: ?[]const u8 = null,
    icon: ?[]const u8 = null,
    priority: f32 = 1.0,
};

/// Input validation result
pub const Validation = union(enum) {
    valid,
    warning: []const u8,
    @"error": []const u8,
};

/// Callback type for suggestion providers
pub const SuggestionProvider = *const fn (input: []const u8, allocator: std.mem.Allocator) ComponentError![]Suggestion;

/// Callback type for validators
pub const Validator = *const fn (input: []const u8) Validation;

/// Input configuration
pub const Config = struct {
    placeholder: ?[]const u8 = null,
    features: Feature = .{},
    suggestionProvider: ?SuggestionProvider = null,
    validator: ?Validator = null,
    maxLength: ?u32 = null,
    minWidth: u32 = 20,
    maxWidth: ?u32 = null,
};

/// Component state tracking
pub const State = struct {
    dirty: bool = false,

    pub fn markDirty(self: *State) void {
        self.dirty = true;
    }

    pub fn clearDirty(self: *State) void {
        self.dirty = false;
    }
};

/// Input component
pub const Input = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    state: State,
    config: Config,

    // Input state
    buffer: std.ArrayList(u8),
    cursorPositionition: usize = 0,
    selectionStart: ?usize = null,
    selectionEnd: ?usize = null,
    scrollOffset: usize = 0,

    // Feature state
    suggestions: ?[]Suggestion = null,
    selectedSuggestion: usize = 0,
    showSuggestions: bool = false,
    validationResult: Validation = .valid,
    history: std.ArrayList([]const u8),
    historyIndex: ?usize = null,

    // Animation and interaction
    cursorBlinkTime: f32 = 0.0,
    focusedTime: f32 = 0.0,

    const vtable = Component.VTable{
        .init = init,
        .deinit = deinit,
        .getState = getState,
        .setState = setState,
        .render = render,
        .measure = measure,
        .handleEvent = handleEvent,
        .addChild = null,
        .removeChild = null,
        .getChildren = null,
        .update = update,
    };

    pub fn create(allocator: std.mem.Allocator, config: Config) ComponentError!*Component {
        const self = allocator.create(Self) catch return ComponentError.OutOfMemory;
        self.* = Self{
            .allocator = allocator,
            .state = State{},
            .config = config,
            .buffer = std.ArrayList(u8).init(allocator),
            .history = std.ArrayList([]const u8).init(allocator),
        };

        const component = allocator.create(Component) catch return ComponentError.OutOfMemory;
        component.* = Component{
            .vtable = &vtable,
            .impl = self,
            .id = 0,
        };

        return component;
    }

    /// Get current input text
    pub fn getText(self: *Self) []const u8 {
        return self.buffer.items;
    }

    /// Set input text
    pub fn setText(self: *Self, text: []const u8) !void {
        self.buffer.clearRetainingCapacity();
        try self.buffer.appendSlice(text);
        self.cursorPositionition = text.len;
        self.state.markDirty();
        try self.updateSuggestions();
    }

    /// Clear input
    pub fn clear(self: *Self) void {
        self.buffer.clearRetainingCapacity();
        self.cursorPositionition = 0;
        self.clearSuggestions();
        self.state.markDirty();
    }

    /// Add to history
    pub fn addToHistory(self: *Self, text: []const u8) !void {
        if (self.config.features.history and text.len > 0) {
            const owned_text = try self.allocator.dupe(u8, text);
            try self.history.append(owned_text);
        }
    }

    // Component implementation

    fn init(impl: *anyopaque, allocator: std.mem.Allocator) ComponentError!void {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(impl));
        self.state = State{};
    }

    fn deinit(impl: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.buffer.deinit();

        // Clean up history
        for (self.history.items) |item| {
            self.allocator.free(item);
        }
        self.history.deinit();

        // Clean up suggestions
        self.clearSuggestions();
    }

    fn getState(impl: *anyopaque) *State {
        const self: *Self = @ptrCast(@alignCast(impl));
        return &self.state;
    }

    fn setState(impl: *anyopaque, state: State) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.state = state;
    }

    fn render(impl: *anyopaque, ctx: Render) ComponentError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        ctx.terminal.moveTo(self.state.bounds.x, self.state.bounds.y) catch return ComponentError.RenderFailed;

        self.renderInputField(ctx) catch return ComponentError.RenderFailed;
        self.renderContent(ctx) catch return ComponentError.RenderFailed;

        if (self.state.focused) {
            self.renderCursor(ctx) catch return ComponentError.RenderFailed;
        }

        if (self.showSuggestions and self.suggestions != null) {
            self.renderSuggestions(ctx) catch return ComponentError.RenderFailed;
        }

        switch (self.validationResult) {
            .warning => |msg| self.renderValidation(ctx, msg, ctx.theme.colors.warning) catch return ComponentError.RenderFailed,
            .@"error" => |msg| self.renderValidation(ctx, msg, ctx.theme.colors.errorColor) catch return ComponentError.RenderFailed,
            .valid => {},
        }
    }

    fn measure(impl: *anyopaque, available: Rect) Rect {
        const self: *Self = @ptrCast(@alignCast(impl));

        var width = self.config.minWidth;

        // Adjust width based on content
        if (self.buffer.items.len > 0) {
            width = @max(width, @as(u32, @intCast(self.buffer.items.len)) + 4); // +4 for padding and borders
        }

        // Apply max width constraint
        if (self.config.maxWidth) |max_w| {
            width = @min(width, max_w);
        }

        // Fit within available space
        width = @min(width, available.width);

        // Calculate height based on features
        var height: u32 = 1; // Base input line
        if (self.config.features.multiLine) height += 2; // Extra lines for multiline
        if (self.showSuggestions) height += @min(5, if (self.suggestions) |s| @as(u32, @intCast(s.len)) else 0); // Suggestions

        return Rect{
            .x = available.x,
            .y = available.y,
            .width = width,
            .height = @min(height, available.height),
        };
    }

    fn handleEvent(impl: *anyopaque, event: Event) ComponentError!bool {
        const self: *Self = @ptrCast(@alignCast(impl));

        switch (event) {
            .key => |key_event| {
                return self.handleKeyEvent(key_event);
            },
            .mouse => |mouse_event| {
                return self.handleMouseEvent(mouse_event);
            },
            .focus => |focus_event| {
                if (focus_event.gained) {
                    self.focusedTime = 0.0;
                } else {
                    self.showSuggestions = false;
                    self.clearSuggestions();
                }
                return true;
            },
            else => return false,
        }
    }

    fn update(impl: *anyopaque, dt: f32) ComponentError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Update cursor blink animation
        self.cursorBlinkTime += dt;
        if (self.cursorBlinkTime >= 1.0) {
            self.cursorBlinkTime = 0.0;
            self.state.markDirty();
        }

        if (self.state.focused) {
            self.focusedTime += dt;
            if (self.focusedTime < 0.5) {
                self.state.markDirty();
            }
        }
    }

    // Rendering methods

    fn renderInputField(self: *Self, ctx: Render) !void {
        const border_style = if (self.state.focused)
            Style{ .fg_color = ctx.theme.colors.focus, .bold = true }
        else
            Style{ .fg_color = ctx.theme.colors.border };

        // Draw border
        const width = self.state.bounds.width;

        // Top border
        try ctx.terminal.print("┌", border_style);
        var i: u32 = 1;
        while (i < width - 1) : (i += 1) {
            try ctx.terminal.print("─", border_style);
        }
        try ctx.terminal.print("┐", border_style);

        // Content area (will be filled by renderContent)
        try ctx.terminal.moveTo(self.state.bounds.x, self.state.bounds.y + 1);
        try ctx.terminal.print("│", border_style);

        // Bottom border
        try ctx.terminal.moveTo(self.state.bounds.x, self.state.bounds.y + 2);
        try ctx.terminal.print("└", border_style);
        i = 1;
        while (i < width - 1) : (i += 1) {
            try ctx.terminal.print("─", border_style);
        }
        try ctx.terminal.print("┘", border_style);

        // Right border
        try ctx.terminal.moveTo(self.state.bounds.x + @as(i32, @intCast(width)) - 1, self.state.bounds.y + 1);
        try ctx.terminal.print("│", border_style);
    }

    fn renderContent(self: *Self, ctx: Render) !void {
        // Move to content area
        try ctx.terminal.moveTo(self.state.bounds.x + 1, self.state.bounds.y + 1);

        const content_width = @max(1, self.state.bounds.width -| 2); // Account for borders
        var display_text: []const u8 = undefined;

        if (self.buffer.items.len == 0 and self.config.placeholder != null) {
            // Show placeholder
            display_text = self.config.placeholder.?;
            const placeholder_style = Style{
                .fg_color = ctx.theme.colors.border,
                .italic = true,
            };

            const display_len = @min(display_text.len, content_width);
            try ctx.terminal.print(display_text[0..display_len], placeholder_style);

            // Fill remaining space
            var i: u32 = @as(u32, @intCast(display_len));
            while (i < content_width) : (i += 1) {
                try ctx.terminal.print(" ", null);
            }
        } else {
            // Show actual content
            display_text = self.buffer.items;

            // Calculate visible portion based on scroll and cursor
            const start_pos = self.scrollOffset;
            const end_pos = @min(display_text.len, start_pos + content_width);
            const visible_text = display_text[start_pos..end_pos];

            if (self.config.features.passwordMode) {
                // Render as password (asterisks)
                for (visible_text) |_| {
                    try ctx.terminal.print("*", Style{ .fg_color = ctx.theme.colors.foreground });
                }
            } else if (self.config.features.syntaxHighlighting and ctx.terminal.getCapabilities().supportsTruecolor) {
                try self.renderWithSyntaxHighlighting(ctx, visible_text);
            } else {
                // Plain text
                const text_style = Style{ .fg_color = ctx.theme.colors.foreground };
                try ctx.terminal.print(visible_text, text_style);
            }

            // Fill remaining space
            var i: usize = visible_text.len;
            while (i < content_width) : (i += 1) {
                try ctx.terminal.print(" ", null);
            }
        }
    }

    fn renderCursor(self: *Self, ctx: Render) !void {
        // Calculate cursor position on screen
        const content_start_x = self.state.bounds.x + 1;
        const visible_cursor_pos = if (self.cursorPositionition >= self.scrollOffset)
            self.cursorPositionition - self.scrollOffset
        else
            0;

        const cursor_x = content_start_x + @as(i32, @intCast(visible_cursor_pos));
        const cursor_y = self.state.bounds.y + 1;

        // Only render cursor if it's visible
        if (visible_cursor_pos < self.state.bounds.width - 2) {
            try ctx.terminal.moveTo(cursor_x, cursor_y);

            // Animate cursor blink
            const should_show = self.cursorBlinkTime < 0.5;
            if (should_show) {
                const cursor_style = Style{
                    .fg_color = ctx.theme.colors.foreground,
                    .bg_color = ctx.theme.colors.focus,
                };

                // Show character under cursor or space
                const cursor_char = if (self.cursorPosition < self.buffer.items.len)
                    self.buffer.items[self.cursorPosition .. self.cursorPosition + 1]
                else
                    " ";

                try ctx.terminal.print(cursor_char, cursor_style);
            }
        }
    }

    fn renderSuggestions(self: *Self, ctx: Render) !void {
        if (self.suggestions) |suggestions| {
            const suggestions_y = self.state.bounds.y + 3; // Below input field
            const max_suggestions = @min(suggestions.len, 5); // Show max 5 suggestions

            for (suggestions[0..max_suggestions], 0..) |suggestion, i| {
                try ctx.terminal.moveTo(self.state.bounds.x, suggestions_y + @as(i32, @intCast(i)));

                const is_selected = i == self.selectedSuggestion;
                const style = if (is_selected)
                    Style{
                        .fg_color = ctx.theme.colors.background,
                        .bg_color = ctx.theme.colors.primary,
                        .bold = true,
                    }
                else
                    Style{ .fg_color = ctx.theme.colors.foreground };

                const prefix = if (is_selected) "► " else "  ";
                const icon = if (suggestion.icon) |ic| ic else "";

                try ctx.terminal.printf("{s}{s}{s}", .{ prefix, icon, suggestion.text }, style);

                if (suggestion.description) |desc| {
                    const desc_style = Style{
                        .fg_color = ctx.theme.colors.border,
                        .italic = true,
                    };
                    try ctx.terminal.printf(" - {s}", .{desc}, desc_style);
                }
            }
        }
    }

    fn renderValidation(self: *Self, ctx: Render, message: []const u8, color: Color) !void {
        const validation_y = self.state.bounds.y + self.state.bounds.height;
        try ctx.terminal.moveTo(self.state.bounds.x, validation_y);

        const validation_style = Style{ .fg_color = color, .italic = true };
        try ctx.terminal.print(message, validation_style);
    }

    fn renderWithSyntaxHighlighting(self: *Self, ctx: Render, text: []const u8) !void {
        _ = self;
        // Syntax highlighting for demonstration
        // In a real implementation, this would use a proper tokenizer

        var i: usize = 0;
        while (i < text.len) {
            const char = text[i];
            var style = Style{ .fg_color = ctx.theme.colors.foreground };

            // Simple rules
            if (std.ascii.isDigit(char)) {
                style.fg_color = Color{ .rgb = .{ .r = 100, .g = 200, .b = 255 } }; // Blue for numbers
            } else if (char == '"' or char == '\'') {
                style.fg_color = Color{ .rgb = .{ .r = 100, .g = 255, .b = 100 } }; // Green for strings
            } else if (char == '(' or char == ')' or char == '{' or char == '}' or char == '[' or char == ']') {
                style.fg_color = Color{ .rgb = .{ .r = 255, .g = 200, .b = 100 } }; // Yellow for brackets
            }

            try ctx.terminal.print(text[i .. i + 1], style);
            i += 1;
        }
    }

    // Event handling methods

    fn handleKeyEvent(self: *Self, key_event: Event.Key) ComponentError!bool {
        switch (key_event.key) {
            .char => {
                // Insert character (this is simplified - real implementation would handle Unicode properly)
                return self.insertChar('a'); // Placeholder
            },
            .backspace => {
                if (self.cursorPosition > 0) {
                    _ = self.buffer.orderedRemove(self.cursorPosition - 1);
                    self.cursorPosition -= 1;
                    self.state.markDirty();
                    try self.updateSuggestions();
                }
                return true;
            },
            .delete => {
                if (self.cursorPosition < self.buffer.items.len) {
                    _ = self.buffer.orderedRemove(self.cursorPosition);
                    self.state.markDirty();
                    try self.updateSuggestions();
                }
                return true;
            },
            .left => {
                if (self.cursorPosition > 0) {
                    self.cursorPosition -= 1;
                    self.updateScrollOffset();
                    self.state.markDirty();
                }
                return true;
            },
            .right => {
                if (self.cursorPosition < self.buffer.items.len) {
                    self.cursorPosition += 1;
                    self.updateScrollOffset();
                    self.state.markDirty();
                }
                return true;
            },
            .up => {
                if (self.showSuggestions and self.suggestions != null) {
                    if (self.selectedSuggestion > 0) {
                        self.selectedSuggestion -= 1;
                        self.state.markDirty();
                    }
                } else if (self.config.features.history) {
                    try self.navigateHistory(-1);
                }
                return true;
            },
            .down => {
                if (self.showSuggestions and self.suggestions != null) {
                    if (self.selectedSuggestion < self.suggestions.?.len - 1) {
                        self.selectedSuggestion += 1;
                        self.state.markDirty();
                    }
                } else if (self.config.features.history) {
                    try self.navigateHistory(1);
                }
                return true;
            },
            .enter => {
                if (self.showSuggestions and self.suggestions != null) {
                    try self.applySuggestion(self.selectedSuggestion);
                }
                return true;
            },
            .escape => {
                self.showSuggestions = false;
                self.clearSuggestions();
                self.state.markDirty();
                return true;
            },
            .tab => {
                if (self.showSuggestions and self.suggestions != null and self.suggestions.?.len > 0) {
                    try self.applySuggestion(self.selectedSuggestion);
                } else if (self.config.features.autocomplete) {
                    try self.updateSuggestions();
                    self.showSuggestions = true;
                    self.state.markDirty();
                }
                return true;
            },
            else => return false,
        }
    }

    fn handleMouseEvent(self: *Self, mouse_event: Event.Mouse) ComponentError!bool {
        // Convert screen coordinates to component-relative coordinates
        const bounds = self.state.bounds;
        const relative_x = mouse_event.pos.x - bounds.x;
        const relative_y = mouse_event.pos.y - bounds.y;

        // Check if mouse is within component bounds
        if (relative_x < 0 or relative_y < 0 or
            relative_x >= bounds.width or relative_y >= bounds.height)
        {
            return false;
        }

        switch (mouse_event.action) {
            .press => {
                switch (mouse_event.button) {
                    .left => {
                        // Handle cursor positioning
                        const clicked_pos = self.screenToTextPosition(relative_x +| self.scrollOffset);

                        if (clicked_pos <= self.buffer.items.len) {
                            self.cursorPosition = clicked_pos;
                            self.selectionStart = clicked_pos;
                            self.selectionEnd = clicked_pos;
                            self.state.markDirty();
                            try self.updateSuggestions();
                            return true;
                        }
                    },
                    .right => {
                        // Could implement context menu or paste
                        return false;
                    },
                    else => return false,
                }
            },
            .move => {
                // Handle text selection with mouse drag
                if (self.selectionStart != null) {
                    const text_pos = self.screenToTextPosition(relative_x +| self.scrollOffset);
                    if (text_pos <= self.buffer.items.len) {
                        self.cursorPosition = text_pos;
                        self.selectionEnd = text_pos;
                        self.state.markDirty();
                        return true;
                    }
                }
            },
            .release => {
                // Selection is complete
                if (self.selectionStart != null and self.selectionEnd != null) {
                    // Ensure selection is properly ordered
                    if (self.selectionEnd.? < self.selectionStart.?) {
                        const temp = self.selectionStart.?;
                        self.selectionStart = self.selectionEnd.?;
                        self.selectionEnd = temp;
                    }
                    self.state.markDirty();
                    return true;
                }
            },
        }

        return false;
    }

    /// Convert screen position to text buffer position
    fn screenToTextPosition(self: *Self, screen_x: u32) usize {
        if (screen_x == 0) return 0;

        var pos: usize = 0;
        var screen_pos: u32 = 0;

        for (self.buffer.items, 0..) |char, i| {
            const char_width = if (char < 0x80) 1 else 2; // Simple UTF-8 width approximation
            if (screen_pos + char_width > screen_x) {
                return i;
            }
            screen_pos += char_width;
            pos = i + 1;
        }

        return pos;
    }

    // Helper methods

    fn insertChar(self: *Self, char: u8) ComponentError!bool {
        if (self.config.maxLength) |max_len| {
            if (self.buffer.items.len >= max_len) return true;
        }

        self.buffer.insert(self.cursorPosition, char) catch return ComponentError.OutOfMemory;
        self.cursorPosition += 1;
        self.updateScrollOffset();
        self.state.markDirty();
        try self.updateSuggestions();

        // Live validation
        if (self.config.features.liveValidation and self.config.validator != null) {
            self.validationResult = self.config.validator.?(self.buffer.items);
            self.state.markDirty();
        }

        return true;
    }

    fn updateScrollOffset(self: *Self) void {
        const content_width = @max(1, self.state.bounds.width -| 2);

        // Ensure cursor is visible
        if (self.cursorPosition < self.scrollOffset) {
            self.scrollOffset = self.cursorPosition;
        } else if (self.cursorPosition >= self.scrollOffset + content_width) {
            self.scrollOffset = self.cursorPosition - content_width + 1;
        }
    }

    fn updateSuggestions(self: *Self) ComponentError!void {
        if (self.config.features.autocomplete and self.config.suggestionProvider != null) {
            if (self.suggestions) |previous_suggestions| {
                self.allocator.free(previous_suggestions);
            }

            self.suggestions = try self.config.suggestionProvider.?(self.buffer.items, self.allocator);
            self.selectedSuggestion = 0;
            self.showSuggestions = self.suggestions != null and self.suggestions.?.len > 0;
        }
    }

    fn clearSuggestions(self: *Self) void {
        if (self.suggestions) |suggestions| {
            self.allocator.free(suggestions);
            self.suggestions = null;
        }
        self.showSuggestions = false;
    }

    fn navigateHistory(self: *Self, direction: i32) ComponentError!void {
        if (self.history.items.len == 0) return;

        if (self.historyIndex == null) {
            self.historyIndex = if (direction > 0) 0 else self.history.items.len - 1;
        } else {
            const current = self.historyIndex.?;
            if (direction > 0 and current < self.history.items.len - 1) {
                self.historyIndex = current + 1;
            } else if (direction < 0 and current > 0) {
                self.historyIndex = current - 1;
            }
        }

        if (self.historyIndex) |idx| {
            self.setText(self.history.items[idx]) catch return ComponentError.EventHandlingFailed;
        }
    }

    fn applySuggestion(self: *Self, index: usize) ComponentError!void {
        if (self.suggestions) |suggestions| {
            if (index < suggestions.len) {
                self.setText(suggestions[index].text) catch return ComponentError.EventHandlingFailed;
                self.showSuggestions = false;
                self.clearSuggestions();
            }
        }
    }
};

/// Example suggestion provider for demonstration
pub fn defaultSuggestionProvider(input: []const u8, allocator: std.mem.Allocator) ComponentError![]Suggestion {
    // Demonstration suggestions
    if (input.len == 0) return &[_]Suggestion{};

    var suggestions = std.ArrayList(Suggestion).init(allocator);

    // Add some common completions based on input
    if (std.mem.startsWith(u8, "hello", input)) {
        suggestions.append(Suggestion{
            .text = "hello world",
            .description = "Classic greeting",
            .icon = "👋",
        }) catch return ComponentError.OutOfMemory;
    }

    if (std.mem.startsWith(u8, "git", input)) {
        suggestions.append(Suggestion{ .text = "git status", .description = "Show repository status" }) catch return ComponentError.OutOfMemory;
        suggestions.append(Suggestion{ .text = "git commit", .description = "Create a commit" }) catch return ComponentError.OutOfMemory;
        suggestions.append(Suggestion{ .text = "git push", .description = "Push to remote" }) catch return ComponentError.OutOfMemory;
    }

    return suggestions.toOwnedSlice() catch return ComponentError.OutOfMemory;
}

/// Example validator for demonstration
pub fn defaultValidator(input: []const u8) Validation {
    if (input.len == 0) return .valid;

    // Validation rules
    if (input.len < 3) {
        return .{ .warning = "Input too short" };
    }

    if (std.mem.indexOf(u8, input, "bad") != null) {
        return .{ .@"error" = "Contains forbidden word" };
    }

    return .valid;
}

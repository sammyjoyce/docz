//! Smart Input Component
//!
//! An adaptive text input component that provides progressive enhancement
//! based on terminal capabilities, including autocomplete, syntax highlighting,
//! and advanced keyboard support.

const std = @import("std");
const component_mod = @import("../component.zig");
const unified = @import("../../term/unified.zig");

const Component = component_mod.Component;
const ComponentState = component_mod.ComponentState;
const RenderContext = component_mod.RenderContext;
const Event = component_mod.Event;
const Theme = component_mod.Theme;

const Terminal = unified.Terminal;
const Style = unified.Style;
const Color = unified.Color;
const Point = unified.Point;
const Rect = unified.Rect;

/// Input enhancement features
pub const InputFeatures = packed struct {
    autocomplete: bool = true,
    syntax_highlighting: bool = true,
    multi_line: bool = false,
    password_mode: bool = false,
    history: bool = true,
    live_validation: bool = true,
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
pub const ValidationResult = union(enum) {
    valid,
    warning: []const u8,
    validation_error: []const u8,
};

/// Callback type for suggestion providers
pub const SuggestionProvider = *const fn (input: []const u8, allocator: std.mem.Allocator) anyerror![]Suggestion;

/// Callback type for validators
pub const Validator = *const fn (input: []const u8) ValidationResult;

/// Smart input configuration
pub const SmartInputConfig = struct {
    placeholder: ?[]const u8 = null,
    features: InputFeatures = .{},
    suggestion_provider: ?SuggestionProvider = null,
    validator: ?Validator = null,
    max_length: ?u32 = null,
    min_width: u32 = 20,
    max_width: ?u32 = null,
};

/// Smart input component
pub const SmartInput = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    state: ComponentState,
    config: SmartInputConfig,
    
    // Input state
    buffer: std.ArrayList(u8),
    cursor_pos: usize = 0,
    selection_start: ?usize = null,
    selection_end: ?usize = null,
    scroll_offset: usize = 0,
    
    // Enhancement state
    suggestions: ?[]Suggestion = null,
    selected_suggestion: usize = 0,
    show_suggestions: bool = false,
    validation_result: ValidationResult = .valid,
    history: std.ArrayList([]const u8),
    history_index: ?usize = null,
    
    // Animation and interaction
    cursor_blink_time: f32 = 0.0,
    focused_time: f32 = 0.0,
    
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
    
    pub fn create(allocator: std.mem.Allocator, config: SmartInputConfig) !*Component {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .state = ComponentState{},
            .config = config,
            .buffer = std.ArrayList(u8).init(allocator),
            .history = std.ArrayList([]const u8).init(allocator),
        };
        
        const component = try allocator.create(Component);
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
        self.cursor_pos = text.len;
        self.state.markDirty();
        try self.updateSuggestions();
    }
    
    /// Clear input
    pub fn clear(self: *Self) void {
        self.buffer.clearRetainingCapacity();
        self.cursor_pos = 0;
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
    
    fn init(impl: *anyopaque, allocator: std.mem.Allocator) anyerror!void {
        _ = allocator;
        const self: *Self = @ptrCast(@alignCast(impl));
        self.state = ComponentState{};
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
    
    fn getState(impl: *anyopaque) *ComponentState {
        const self: *Self = @ptrCast(@alignCast(impl));
        return &self.state;
    }
    
    fn setState(impl: *anyopaque, state: ComponentState) void {
        const self: *Self = @ptrCast(@alignCast(impl));
        self.state = state;
    }
    
    fn render(impl: *anyopaque, ctx: RenderContext) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        
        // Move to component position
        try ctx.terminal.moveTo(self.state.bounds.x, self.state.bounds.y);
        
        // Render input field background and border
        try self.renderInputField(ctx);
        
        // Render content
        try self.renderContent(ctx);
        
        // Render cursor if focused
        if (self.state.focused) {
            try self.renderCursor(ctx);
        }
        
        // Render suggestions if available
        if (self.show_suggestions and self.suggestions != null) {
            try self.renderSuggestions(ctx);
        }
        
        // Render validation feedback
        switch (self.validation_result) {
            .warning => |msg| try self.renderValidation(ctx, msg, ctx.theme.colors.warning),
            .validation_error => |msg| try self.renderValidation(ctx, msg, ctx.theme.colors.error_color),
            .valid => {},
        }
    }
    
    fn measure(impl: *anyopaque, available: Rect) Rect {
        const self: *Self = @ptrCast(@alignCast(impl));
        
        var width = self.config.min_width;
        
        // Adjust width based on content
        if (self.buffer.items.len > 0) {
            width = @max(width, @as(u32, @intCast(self.buffer.items.len)) + 4); // +4 for padding and borders
        }
        
        // Apply max width constraint
        if (self.config.max_width) |max_w| {
            width = @min(width, max_w);
        }
        
        // Fit within available space
        width = @min(width, available.width);
        
        // Calculate height based on features
        var height: u32 = 1; // Base input line
        if (self.config.features.multi_line) height += 2; // Extra lines for multiline
        if (self.show_suggestions) height += @min(5, if (self.suggestions) |s| @as(u32, @intCast(s.len)) else 0); // Suggestions
        
        return Rect{
            .x = available.x,
            .y = available.y,
            .width = width,
            .height = @min(height, available.height),
        };
    }
    
    fn handleEvent(impl: *anyopaque, event: Event) anyerror!bool {
        const self: *Self = @ptrCast(@alignCast(impl));
        
        switch (event) {
            .key => |key_event| {
                return try self.handleKeyEvent(key_event);
            },
            .mouse => |mouse_event| {
                return try self.handleMouseEvent(mouse_event);
            },
            .focus => |focus_event| {
                if (focus_event.gained) {
                    self.focused_time = 0.0;
                } else {
                    self.show_suggestions = false;
                    self.clearSuggestions();
                }
                return true;
            },
            else => return false,
        }
    }
    
    fn update(impl: *anyopaque, dt: f32) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(impl));
        
        // Update cursor blink animation
        self.cursor_blink_time += dt;
        if (self.cursor_blink_time >= 1.0) {
            self.cursor_blink_time = 0.0;
            self.state.markDirty(); // Trigger redraw for cursor blink
        }
        
        // Update focused animation
        if (self.state.focused) {
            self.focused_time += dt;
            if (self.focused_time < 0.5) {
                self.state.markDirty(); // Animate focus transition
            }
        }
    }
    
    // Rendering methods
    
    fn renderInputField(self: *Self, ctx: RenderContext) !void {
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
    
    fn renderContent(self: *Self, ctx: RenderContext) !void {
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
            const start_pos = self.scroll_offset;
            const end_pos = @min(display_text.len, start_pos + content_width);
            const visible_text = display_text[start_pos..end_pos];
            
            if (self.config.features.password_mode) {
                // Render as password (asterisks)
                for (visible_text) |_| {
                    try ctx.terminal.print("*", Style{ .fg_color = ctx.theme.colors.foreground });
                }
            } else if (self.config.features.syntax_highlighting and ctx.terminal.getCapabilities().supportsTruecolor) {
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
    
    fn renderCursor(self: *Self, ctx: RenderContext) !void {
        // Calculate cursor position on screen
        const content_start_x = self.state.bounds.x + 1;
        const visible_cursor_pos = if (self.cursor_pos >= self.scroll_offset)
            self.cursor_pos - self.scroll_offset
        else
            0;
        
        const cursor_x = content_start_x + @as(i32, @intCast(visible_cursor_pos));
        const cursor_y = self.state.bounds.y + 1;
        
        // Only render cursor if it's visible
        if (visible_cursor_pos < self.state.bounds.width - 2) {
            try ctx.terminal.moveTo(cursor_x, cursor_y);
            
            // Animate cursor blink
            const should_show = self.cursor_blink_time < 0.5;
            if (should_show) {
                const cursor_style = Style{ 
                    .fg_color = ctx.theme.colors.foreground,
                    .bg_color = ctx.theme.colors.focus,
                };
                
                // Show character under cursor or space
                const cursor_char = if (self.cursor_pos < self.buffer.items.len)
                    self.buffer.items[self.cursor_pos..self.cursor_pos + 1]
                else
                    " ";
                
                try ctx.terminal.print(cursor_char, cursor_style);
            }
        }
    }
    
    fn renderSuggestions(self: *Self, ctx: RenderContext) !void {
        if (self.suggestions) |suggestions| {
            const suggestions_y = self.state.bounds.y + 3; // Below input field
            const max_suggestions = @min(suggestions.len, 5); // Show max 5 suggestions
            
            for (suggestions[0..max_suggestions], 0..) |suggestion, i| {
                try ctx.terminal.moveTo(self.state.bounds.x, suggestions_y + @as(i32, @intCast(i)));
                
                const is_selected = i == self.selected_suggestion;
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
    
    fn renderValidation(self: *Self, ctx: RenderContext, message: []const u8, color: Color) !void {
        const validation_y = self.state.bounds.y + self.state.bounds.height;
        try ctx.terminal.moveTo(self.state.bounds.x, validation_y);
        
        const validation_style = Style{ .fg_color = color, .italic = true };
        try ctx.terminal.print(message, validation_style);
    }
    
    fn renderWithSyntaxHighlighting(self: *Self, ctx: RenderContext, text: []const u8) !void {
        _ = self;
        // Simple syntax highlighting for demonstration
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
            
            try ctx.terminal.print(text[i..i+1], style);
            i += 1;
        }
    }
    
    // Event handling methods
    
    fn handleKeyEvent(self: *Self, key_event: Event.KeyEvent) !bool {
        switch (key_event.key) {
            .char => {
                // Insert character (this is simplified - real implementation would handle Unicode properly)
                return self.insertChar('a'); // Placeholder
            },
            .backspace => {
                if (self.cursor_pos > 0) {
                    _ = self.buffer.orderedRemove(self.cursor_pos - 1);
                    self.cursor_pos -= 1;
                    self.state.markDirty();
                    try self.updateSuggestions();
                }
                return true;
            },
            .delete => {
                if (self.cursor_pos < self.buffer.items.len) {
                    _ = self.buffer.orderedRemove(self.cursor_pos);
                    self.state.markDirty();
                    try self.updateSuggestions();
                }
                return true;
            },
            .left => {
                if (self.cursor_pos > 0) {
                    self.cursor_pos -= 1;
                    self.updateScrollOffset();
                    self.state.markDirty();
                }
                return true;
            },
            .right => {
                if (self.cursor_pos < self.buffer.items.len) {
                    self.cursor_pos += 1;
                    self.updateScrollOffset();
                    self.state.markDirty();
                }
                return true;
            },
            .up => {
                if (self.show_suggestions and self.suggestions != null) {
                    if (self.selected_suggestion > 0) {
                        self.selected_suggestion -= 1;
                        self.state.markDirty();
                    }
                } else if (self.config.features.history) {
                    try self.navigateHistory(-1);
                }
                return true;
            },
            .down => {
                if (self.show_suggestions and self.suggestions != null) {
                    if (self.selected_suggestion < self.suggestions.?.len - 1) {
                        self.selected_suggestion += 1;
                        self.state.markDirty();
                    }
                } else if (self.config.features.history) {
                    try self.navigateHistory(1);
                }
                return true;
            },
            .enter => {
                if (self.show_suggestions and self.suggestions != null) {
                    try self.applySuggestion(self.selected_suggestion);
                }
                return true;
            },
            .escape => {
                self.show_suggestions = false;
                self.clearSuggestions();
                self.state.markDirty();
                return true;
            },
            .tab => {
                if (self.show_suggestions and self.suggestions != null and self.suggestions.?.len > 0) {
                    try self.applySuggestion(self.selected_suggestion);
                } else if (self.config.features.autocomplete) {
                    try self.updateSuggestions();
                    self.show_suggestions = true;
                    self.state.markDirty();
                }
                return true;
            },
            else => return false,
        }
    }
    
    fn handleMouseEvent(self: *Self, mouse_event: Event.MouseEvent) !bool {
        _ = self;
        _ = mouse_event;
        // TODO: Implement mouse support (cursor positioning, selection)
        return false;
    }
    
    // Helper methods
    
    fn insertChar(self: *Self, char: u8) !bool {
        if (self.config.max_length) |max_len| {
            if (self.buffer.items.len >= max_len) return true;
        }
        
        try self.buffer.insert(self.cursor_pos, char);
        self.cursor_pos += 1;
        self.updateScrollOffset();
        self.state.markDirty();
        try self.updateSuggestions();
        
        // Live validation
        if (self.config.features.live_validation and self.config.validator != null) {
            self.validation_result = self.config.validator.?(self.buffer.items);
            self.state.markDirty();
        }
        
        return true;
    }
    
    fn updateScrollOffset(self: *Self) void {
        const content_width = @max(1, self.state.bounds.width -| 2);
        
        // Ensure cursor is visible
        if (self.cursor_pos < self.scroll_offset) {
            self.scroll_offset = self.cursor_pos;
        } else if (self.cursor_pos >= self.scroll_offset + content_width) {
            self.scroll_offset = self.cursor_pos - content_width + 1;
        }
    }
    
    fn updateSuggestions(self: *Self) !void {
        if (self.config.features.autocomplete and self.config.suggestion_provider != null) {
            if (self.suggestions) |old_suggestions| {
                self.allocator.free(old_suggestions);
            }
            
            self.suggestions = try self.config.suggestion_provider.?(self.buffer.items, self.allocator);
            self.selected_suggestion = 0;
            self.show_suggestions = self.suggestions != null and self.suggestions.?.len > 0;
        }
    }
    
    fn clearSuggestions(self: *Self) void {
        if (self.suggestions) |suggestions| {
            self.allocator.free(suggestions);
            self.suggestions = null;
        }
        self.show_suggestions = false;
    }
    
    fn navigateHistory(self: *Self, direction: i32) !void {
        if (self.history.items.len == 0) return;
        
        if (self.history_index == null) {
            self.history_index = if (direction > 0) 0 else self.history.items.len - 1;
        } else {
            const current = self.history_index.?;
            if (direction > 0 and current < self.history.items.len - 1) {
                self.history_index = current + 1;
            } else if (direction < 0 and current > 0) {
                self.history_index = current - 1;
            }
        }
        
        if (self.history_index) |idx| {
            try self.setText(self.history.items[idx]);
        }
    }
    
    fn applySuggestion(self: *Self, index: usize) !void {
        if (self.suggestions) |suggestions| {
            if (index < suggestions.len) {
                try self.setText(suggestions[index].text);
                self.show_suggestions = false;
                self.clearSuggestions();
            }
        }
    }
};

/// Example suggestion provider for demonstration
pub fn defaultSuggestionProvider(input: []const u8, allocator: std.mem.Allocator) ![]Suggestion {
    // Simple demonstration suggestions
    if (input.len == 0) return &[_]Suggestion{};
    
    var suggestions = std.ArrayList(Suggestion).init(allocator);
    
    // Add some common completions based on input
    if (std.mem.startsWith(u8, "hello", input)) {
        try suggestions.append(Suggestion{ 
            .text = "hello world",
            .description = "Classic greeting",
            .icon = "👋",
        });
    }
    
    if (std.mem.startsWith(u8, "git", input)) {
        try suggestions.append(Suggestion{ .text = "git status", .description = "Show repository status" });
        try suggestions.append(Suggestion{ .text = "git commit", .description = "Create a commit" });
        try suggestions.append(Suggestion{ .text = "git push", .description = "Push to remote" });
    }
    
    return suggestions.toOwnedSlice();
}

/// Example validator for demonstration  
pub fn defaultValidator(input: []const u8) ValidationResult {
    if (input.len == 0) return .valid;
    
    // Simple validation rules
    if (input.len < 3) {
        return .{ .warning = "Input too short" };
    }
    
    if (std.mem.indexOf(u8, input, "bad") != null) {
        return .{ .validation_error = "Contains forbidden word" };
    }
    
    return .valid;
}
//! Tag input/chips widget for TUI applications
//! Provides a tag input field with visual chips, autocomplete, and validation
const std = @import("std");
const print = std.debug.print;
const Bounds = @import("../../core/bounds.zig").Bounds;
const Color = @import("../../themes/default.zig").Color;
const Box = @import("../../themes/default.zig").Box;
const term = @import("../../../term.zig");
const TermCaps = term.capabilities.TermCaps;
const events = @import("../../core/events.zig");
const KeyEvent = events.KeyEvent;
const MouseEvent = events.MouseEvent;
const focus_mod = @import("../../core/input/focus.zig");
const Focus = focus_mod.Focus;

/// Tag categories for different visual styles
pub const TagCategory = enum {
    default,
    primary,
    secondary,
    success,
    warning,
    danger,
    info,

    pub fn getColor(self: TagCategory) []const u8 {
        return switch (self) {
            .default => Color.WHITE,
            .primary => Color.BRIGHT_BLUE,
            .secondary => Color.GRAY,
            .success => Color.GREEN,
            .warning => Color.YELLOW,
            .danger => Color.RED,
            .info => Color.CYAN,
        };
    }

    pub fn getBackgroundColor(self: TagCategory) []const u8 {
        return switch (self) {
            .default => Color.BG_GRAY,
            .primary => Color.BG_BLUE,
            .secondary => "",
            .success => Color.BG_GREEN,
            .warning => Color.BG_YELLOW,
            .danger => Color.BG_RED,
            .info => Color.BG_CYAN,
        };
    }
};

/// Individual tag representation
pub const Tag = struct {
    text: []const u8,
    category: TagCategory = .default,
    id: ?[]const u8 = null, // Optional unique identifier
    editable: bool = true,
    metadata: ?*anyopaque = null, // For custom data attachment

    pub fn dupe(self: Tag, allocator: std.mem.Allocator) !Tag {
        return Tag{
            .text = try allocator.dupe(u8, self.text),
            .category = self.category,
            .id = if (self.id) |id| try allocator.dupe(u8, id) else null,
            .editable = self.editable,
            .metadata = self.metadata,
        };
    }

    pub fn free(self: *Tag, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        if (self.id) |id| {
            allocator.free(id);
        }
    }
};

/// Tag validation options
pub const TagValidation = struct {
    max_length: usize = 50,
    min_length: usize = 1,
    allow_duplicates: bool = false,
    allowed_chars: ?[]const u8 = null,
    custom_validator: ?*const fn (text: []const u8) bool = null,
};

/// Configuration for tag input widget
pub const TagInputConfig = struct {
    max_tags: ?usize = null,
    placeholder: []const u8 = "Type and press Enter to add tag...",
    delimiter: []const u8 = ",", // For paste operations
    validation: TagValidation = .{},
    enable_autocomplete: bool = true,
    enable_drag_reorder: bool = true,
    show_count: bool = true,
    show_clear_all: bool = true,
};

/// Tag input widget with chip display
pub const TagInput = struct {
    // Core state
    tags: std.ArrayList(Tag),
    input_buffer: std.ArrayList(u8),
    suggestions: ?[]const []const u8, // Autocomplete suggestions
    filtered_suggestions: std.ArrayList([]const u8),

    // UI state
    bounds: Bounds,
    config: TagInputConfig,
    caps: TermCaps,
    allocator: std.mem.Allocator,

    // Interaction state
    cursorPos: usize,
    selected_tag_index: ?usize, // For keyboard navigation
    dragging_tag_index: ?usize, // For mouse drag reordering
    suggestion_index: ?usize, // Current autocomplete selection
    is_focused: bool,
    show_suggestions: bool,

    // Scroll state for many tags
    scrollOffset: usize,
    visible_tag_count: usize,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        bounds: Bounds,
        caps: TermCaps,
        config: TagInputConfig,
    ) !Self {
        return Self{
            .tags = std.ArrayList(Tag).init(allocator),
            .input_buffer = std.ArrayList(u8).init(allocator),
            .suggestions = null,
            .filtered_suggestions = std.ArrayList([]const u8).init(allocator),
            .bounds = bounds,
            .config = config,
            .caps = caps,
            .allocator = allocator,
            .cursorPos = 0,
            .selected_tag_index = null,
            .dragging_tag_index = null,
            .suggestion_index = null,
            .is_focused = false,
            .show_suggestions = false,
            .scrollOffset = 0,
            .visible_tag_count = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.tags.items) |*tag| {
            tag.free(self.allocator);
        }
        self.tags.deinit();
        self.input_buffer.deinit();
        self.filtered_suggestions.deinit();
    }

    /// Set autocomplete suggestions
    pub fn setSuggestions(self: *Self, suggestions: []const []const u8) void {
        self.suggestions = suggestions;
    }

    /// Add a new tag
    pub fn addTag(self: *Self, text: []const u8, category: TagCategory) !void {
        // Check max tags limit
        if (self.config.max_tags) |max| {
            if (self.tags.items.len >= max) return;
        }

        // Validate tag
        if (!self.validateTag(text)) return;

        // Check for duplicates
        if (!self.config.validation.allow_duplicates) {
            for (self.tags.items) |tag| {
                if (std.mem.eql(u8, tag.text, text)) return;
            }
        }

        const tag = Tag{
            .text = try self.allocator.dupe(u8, text),
            .category = category,
        };
        try self.tags.append(tag);
    }

    /// Add tag from current input buffer
    pub fn addTagFromInput(self: *Self) !void {
        if (self.input_buffer.items.len == 0) return;

        const text = try self.allocator.dupe(u8, self.input_buffer.items);
        defer self.allocator.free(text);

        try self.addTag(text, .default);
        self.input_buffer.clearRetainingCapacity();
        self.cursorPos = 0;
        self.show_suggestions = false;
        self.suggestion_index = null;
    }

    /// Remove tag at index
    pub fn removeTag(self: *Self, index: usize) void {
        if (index >= self.tags.items.len) return;

        var tag = self.tags.orderedRemove(index);
        tag.free(self.allocator);

        // Adjust selection if needed
        if (self.selected_tag_index) |selected| {
            if (selected == index) {
                self.selected_tag_index = null;
            } else if (selected > index) {
                self.selected_tag_index = selected - 1;
            }
        }
    }

    /// Remove last tag (for backspace behavior)
    pub fn removeLastTag(self: *Self) void {
        if (self.tags.items.len > 0) {
            self.removeTag(self.tags.items.len - 1);
        }
    }

    /// Clear all tags
    pub fn clearAll(self: *Self) void {
        for (self.tags.items) |*tag| {
            tag.free(self.allocator);
        }
        self.tags.clearRetainingCapacity();
        self.selected_tag_index = null;
    }

    /// Validate tag text
    fn validateTag(self: *Self, text: []const u8) bool {
        const validation = self.config.validation;

        // Length checks
        if (text.len < validation.min_length or text.len > validation.max_length) {
            return false;
        }

        // Character validation
        if (validation.allowed_chars) |allowed| {
            for (text) |char| {
                var found = false;
                for (allowed) |allowed_char| {
                    if (char == allowed_char) {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            }
        }

        // Custom validator
        if (validation.custom_validator) |validator| {
            if (!validator(text)) return false;
        }

        return true;
    }

    /// Update filtered suggestions based on current input
    fn updateFilteredSuggestions(self: *Self) !void {
        self.filtered_suggestions.clearRetainingCapacity();

        if (self.suggestions == null or self.input_buffer.items.len == 0) {
            self.show_suggestions = false;
            return;
        }

        const input_lower = try std.ascii.allocLowerString(self.allocator, self.input_buffer.items);
        defer self.allocator.free(input_lower);

        for (self.suggestions.?) |suggestion| {
            const suggestion_lower = try std.ascii.allocLowerString(self.allocator, suggestion);
            defer self.allocator.free(suggestion_lower);

            // Check if suggestion starts with input
            if (std.mem.startsWith(u8, suggestion_lower, input_lower)) {
                // Don't suggest existing tags
                var exists = false;
                for (self.tags.items) |tag| {
                    if (std.mem.eql(u8, tag.text, suggestion)) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) {
                    try self.filtered_suggestions.append(suggestion);
                }
            }
        }

        self.show_suggestions = self.filtered_suggestions.items.len > 0;
        if (self.show_suggestions and self.suggestion_index == null) {
            self.suggestion_index = 0;
        }
    }

    /// Handle keyboard input
    pub fn handleKeyEvent(self: *Self, event: KeyEvent) !bool {
        if (!self.is_focused) return false;

        switch (event.key) {
            .enter => {
                if (self.show_suggestions and self.suggestion_index != null) {
                    // Apply selected suggestion
                    const suggestion = self.filtered_suggestions.items[self.suggestion_index.?];
                    try self.addTag(suggestion, .default);
                    self.input_buffer.clearRetainingCapacity();
                    self.cursor_pos = 0;
                    self.show_suggestions = false;
                    self.suggestion_index = null;
                } else {
                    // Add tag from input
                    try self.addTagFromInput();
                }
                return true;
            },
            .backspace => {
                if (self.input_buffer.items.len > 0 and self.cursorPos > 0) {
                    _ = self.input_buffer.orderedRemove(self.cursorPos - 1);
                    self.cursorPos -= 1;
                    try self.updateFilteredSuggestions();
                } else if (self.input_buffer.items.len == 0) {
                    // Remove last tag if input is empty
                    self.removeLastTag();
                }
                return true;
            },
            .delete => {
                if (self.selected_tag_index) |index| {
                    self.removeTag(index);
                    self.selected_tag_index = null;
                } else if (self.cursorPos < self.input_buffer.items.len) {
                    _ = self.input_buffer.orderedRemove(self.cursorPos);
                    try self.updateFilteredSuggestions();
                }
                return true;
            },
            .arrow_left => {
                if (event.modifiers.ctrl) {
                    // Navigate to previous tag
                    if (self.selected_tag_index) |index| {
                        if (index > 0) {
                            self.selected_tag_index = index - 1;
                        }
                    } else if (self.tags.items.len > 0) {
                        self.selected_tag_index = self.tags.items.len - 1;
                    }
                } else if (self.cursorPos > 0) {
                    self.cursorPos -= 1;
                }
                return true;
            },
            .arrow_right => {
                if (event.modifiers.ctrl) {
                    // Navigate to next tag
                    if (self.selected_tag_index) |index| {
                        if (index < self.tags.items.len - 1) {
                            self.selected_tag_index = index + 1;
                        } else {
                            self.selected_tag_index = null; // Back to input
                        }
                    }
                } else if (self.cursorPos < self.input_buffer.items.len) {
                    self.cursorPos += 1;
                }
                return true;
            },
            .arrow_up => {
                if (self.show_suggestions and self.suggestion_index != null) {
                    if (self.suggestion_index.? > 0) {
                        self.suggestion_index = self.suggestion_index.? - 1;
                    }
                }
                return true;
            },
            .arrow_down => {
                if (self.show_suggestions and self.suggestion_index != null) {
                    if (self.suggestion_index.? < self.filtered_suggestions.items.len - 1) {
                        self.suggestion_index = self.suggestion_index.? + 1;
                    }
                }
                return true;
            },
            .escape => {
                if (self.show_suggestions) {
                    self.show_suggestions = false;
                    self.suggestion_index = null;
                } else if (self.selected_tag_index != null) {
                    self.selected_tag_index = null;
                }
                return true;
            },
            .character => {
                if (event.character) |ch| {
                    if (event.modifiers.ctrl) {
                        return try self.handleCtrlShortcut(ch);
                    } else {
                        // Regular character input
                        const char: u8 = @intCast(ch);
                        try self.input_buffer.insert(self.cursorPos, char);
                        self.cursorPos += 1;
                        try self.updateFilteredSuggestions();
                        return true;
                    }
                }
            },
            else => {},
        }

        return false;
    }

    /// Handle Ctrl+key shortcuts
    fn handleCtrlShortcut(self: *Self, key: u21) !bool {
        const char: u8 = @intCast(key);
        switch (char) {
            'v', 'V' => {
                // Paste from clipboard
                try self.pasteFromClipboard();
                return true;
            },
            'c', 'C' => {
                // Copy selected tags or all tags
                try self.copyToClipboard();
                return true;
            },
            'x', 'X' => {
                // Cut selected tags or all tags
                try self.copyToClipboard();
                if (self.selected_tag_index != null) {
                    self.removeTag(self.selected_tag_index.?);
                    self.selected_tag_index = null;
                } else {
                    self.clearAll();
                }
                return true;
            },
            'a', 'A' => {
                // Select all tags (visual indication only)
                if (self.tags.items.len > 0) {
                    self.selected_tag_index = 0; // Just select first as indicator
                }
                return true;
            },
            else => {},
        }
        return false;
    }

    /// Copy tags to clipboard
    fn copyToClipboard(self: *Self) !void {
        if (self.tags.items.len == 0) return;

        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        // Build comma-separated list
        for (self.tags.items, 0..) |tag, i| {
            if (i > 0) {
                try buffer.appendSlice(self.config.delimiter);
                try buffer.append(' ');
            }
            try buffer.appendSlice(tag.text);
        }

        try term.ansi.clipboard.setClipboard(buffer.items, self.caps);
    }

    /// Paste tags from clipboard
    fn pasteFromClipboard(self: *Self) !void {
        if (try term.ansi.clipboard.getClipboard(self.caps)) |text| {
            defer self.allocator.free(text);
            try self.pasteMultipleTags(text);
        }
    }

    /// Parse and add multiple tags from text
    pub fn pasteMultipleTags(self: *Self, text: []const u8) !void {
        var it = std.mem.tokenize(u8, text, self.config.delimiter);
        while (it.next()) |token| {
            // Trim whitespace
            const trimmed = std.mem.trim(u8, token, " \t\n\r");
            if (trimmed.len > 0) {
                try self.addTag(trimmed, .default);
            }
        }
    }

    /// Handle mouse events for tag interaction
    pub fn handleMouseEvent(self: *Self, event: MouseEvent) bool {
        if (!self.is_focused) return false;

        const relative_x = if (event.x >= self.bounds.x) event.x - self.bounds.x else return false;
        const relative_y = if (event.y >= self.bounds.y) event.y - self.bounds.y else return false;

        // Check if click is within bounds
        if (relative_x >= self.bounds.width or relative_y >= self.bounds.height) {
            return false;
        }

        switch (event.action) {
            .press => {
                if (event.button == .left) {
                    // Determine which tag was clicked
                    const tag_index = self.getTagAtPosition(relative_x, relative_y);
                    if (tag_index) |index| {
                        if (self.config.enable_drag_reorder) {
                            self.dragging_tag_index = index;
                        }
                        self.selected_tag_index = index;
                    } else {
                        self.selected_tag_index = null;
                        // Focus on input area
                    }
                    return true;
                }
            },
            .release => {
                if (self.dragging_tag_index != null) {
                    self.dragging_tag_index = null;
                    return true;
                }
            },
            .drag => {
                if (self.dragging_tag_index) |dragging| {
                    const target_index = self.getTagAtPosition(relative_x, relative_y);
                    if (target_index) |target| {
                        if (target != dragging) {
                            // Swap tags
                            self.swapTags(dragging, target);
                            self.dragging_tag_index = target;
                        }
                    }
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    /// Swap two tags positions
    fn swapTags(self: *Self, index1: usize, index2: usize) void {
        if (index1 >= self.tags.items.len or index2 >= self.tags.items.len) return;

        const temp = self.tags.items[index1];
        self.tags.items[index1] = self.tags.items[index2];
        self.tags.items[index2] = temp;
    }

    /// Get tag index at screen position
    fn getTagAtPosition(self: *Self, x: u32, y: u32) ?usize {
        _ = y; // Tags are typically on a single line

        var current_x: u32 = 1; // Start position after border
        for (self.tags.items, 0..) |tag, i| {
            const tag_width = @as(u32, @intCast(tag.text.len + 4)); // Include padding and borders
            if (x >= current_x and x < current_x + tag_width) {
                return i;
            }
            current_x += tag_width + 1; // Add spacing between tags
        }
        return null;
    }

    /// Focus the widget
    pub fn focus(self: *Self) void {
        self.is_focused = true;
    }

    /// Blur the widget
    pub fn blur(self: *Self) void {
        self.is_focused = false;
        self.selected_tag_index = null;
        self.show_suggestions = false;
        self.suggestion_index = null;
    }

    /// Get all tags
    pub fn getTags(self: *Self) []const Tag {
        return self.tags.items;
    }

    /// Get tags as text array
    pub fn getTagTexts(self: *Self, allocator: std.mem.Allocator) ![][]const u8 {
        var texts = try allocator.alloc([]const u8, self.tags.items.len);
        for (self.tags.items, 0..) |tag, i| {
            texts[i] = try allocator.dupe(u8, tag.text);
        }
        return texts;
    }

    /// Draw the tag input widget
    pub fn draw(self: *Self) void {
        // Clear the widget area
        self.clearArea();

        // Draw border
        self.drawBorder();

        // Draw tags
        self.drawTags();

        // Draw input field
        self.drawInputField();

        // Draw suggestions dropdown if active
        if (self.show_suggestions) {
            self.drawSuggestions();
        }

        // Draw tag count if enabled
        if (self.config.show_count) {
            self.drawTagCount();
        }
    }

    fn clearArea(self: *Self) void {
        for (0..self.bounds.height) |row| {
            moveCursor(self.bounds.y + @as(u32, @intCast(row)), self.bounds.x);
            for (0..self.bounds.width) |_| {
                print(" ", .{});
            }
        }
    }

    fn drawBorder(self: *Self) void {
        const style = if (self.is_focused) Color.BRIGHT_CYAN else Color.WHITE;

        // Top border with rounded corners
        moveCursor(self.bounds.y, self.bounds.x);
        print("{s}{s}", .{ style, Box.ROUNDED_TOP_LEFT });
        for (0..self.bounds.width - 2) |_| {
            print("{s}", .{Box.HORIZONTAL});
        }
        print("{s}{s}", .{ Box.ROUNDED_TOP_RIGHT, Color.RESET });

        // Bottom border
        moveCursor(self.bounds.y + self.bounds.height - 1, self.bounds.x);
        print("{s}{s}", .{ style, Box.ROUNDED_BOTTOM_LEFT });
        for (0..self.bounds.width - 2) |_| {
            print("{s}", .{Box.HORIZONTAL});
        }
        print("{s}{s}", .{ Box.ROUNDED_BOTTOM_RIGHT, Color.RESET });

        // Side borders
        for (1..self.bounds.height - 1) |row| {
            moveCursor(self.bounds.y + @as(u32, @intCast(row)), self.bounds.x);
            print("{s}{s}", .{ style, Box.VERTICAL });
            moveCursor(self.bounds.y + @as(u32, @intCast(row)), self.bounds.x + self.bounds.width - 1);
            print("{s}{s}", .{ Box.VERTICAL, Color.RESET });
        }
    }

    fn drawTags(self: *Self) void {
        var x_offset: u32 = 2; // Start after border
        const y_pos = self.bounds.y + 1;

        // Calculate available width for tags
        const available_width = if (self.bounds.width > 4) self.bounds.width - 4 else 0;

        for (self.tags.items, 0..) |tag, i| {
            const tag_width = @as(u32, @intCast(tag.text.len + 4)); // Include decorations

            // Check if tag fits on current line
            if (x_offset + tag_width > available_width) {
                break; // Would need multi-line support
            }

            moveCursor(y_pos, self.bounds.x + x_offset);

            // Draw tag chip with rounded appearance
            const is_selected = self.selected_tag_index != null and self.selected_tag_index.? == i;
            const is_dragging = self.dragging_tag_index != null and self.dragging_tag_index.? == i;

            const color = tag.category.getColor();
            const bg_color = tag.category.getBackgroundColor();
            const highlight = if (is_selected) Color.BOLD else "";
            const drag_effect = if (is_dragging) Color.DIM else "";

            // Tag chip: ( tag-text × )
            print("{s}{s}{s}{s}( {s} × ){s}", .{
                highlight,
                drag_effect,
                color,
                bg_color,
                tag.text,
                Color.RESET,
            });

            x_offset += tag_width + 1; // Add spacing
        }
    }

    fn drawInputField(self: *Self) void {
        // Calculate position after tags
        var x_offset: u32 = 2;
        for (self.tags.items) |tag| {
            x_offset += @as(u32, @intCast(tag.text.len + 5)); // Tag width + spacing
        }

        const y_pos = self.bounds.y + 1;
        const available_width = if (self.bounds.width > x_offset + 2)
            self.bounds.width - x_offset - 2
        else
            0;

        if (available_width == 0) return; // No space for input

        moveCursor(y_pos, self.bounds.x + x_offset);

        if (self.input_buffer.items.len == 0 and !self.is_focused) {
            // Show placeholder
            print("{s}{s}{s}", .{
                Color.DIM,
                self.config.placeholder[0..@min(self.config.placeholder.len, available_width)],
                Color.RESET,
            });
        } else {
            // Show input text
            const visible_text = if (self.input_buffer.items.len > available_width)
                self.input_buffer.items[self.input_buffer.items.len - available_width ..]
            else
                self.input_buffer.items;

            print("{s}", .{visible_text});

            // Show cursor if focused
            if (self.is_focused) {
                const cursor_offset = @min(self.cursorPos, available_width - 1);
                moveCursor(y_pos, self.bounds.x + x_offset + @as(u32, @intCast(cursor_offset)));
                print("{s}│{s}", .{ Color.BRIGHT_CYAN, Color.RESET });
            }
        }
    }

    fn drawSuggestions(self: *Self) void {
        if (self.filtered_suggestions.items.len == 0) return;

        const max_suggestions: u32 = 5;
        const dropdown_y = self.bounds.y + 2;
        const dropdown_x = self.bounds.x + 2;
        const dropdown_width = @min(self.bounds.width - 4, 40);

        // Draw suggestion dropdown
        for (self.filtered_suggestions.items[0..@min(self.filtered_suggestions.items.len, max_suggestions)], 0..) |suggestion, i| {
            moveCursor(dropdown_y + @as(u32, @intCast(i)), dropdown_x);

            const is_selected = self.suggestion_index != null and self.suggestion_index.? == i;
            const highlight = if (is_selected) Color.BG_BLUE else "";

            // Clear line and draw suggestion
            for (0..dropdown_width) |_| print(" ", .{});
            moveCursor(dropdown_y + @as(u32, @intCast(i)), dropdown_x);

            const display_text = if (suggestion.len > dropdown_width - 2)
                suggestion[0 .. dropdown_width - 2]
            else
                suggestion;

            print("{s}{s}{s}", .{ highlight, display_text, Color.RESET });
        }
    }

    fn drawTagCount(self: *Self) void {
        const count_text = std.fmt.allocPrint(self.allocator, "{d} tag{s}", .{
            self.tags.items.len,
            if (self.tags.items.len == 1) "" else "s",
        }) catch return;
        defer self.allocator.free(count_text);

        const x_pos = self.bounds.x + self.bounds.width - @as(u32, @intCast(count_text.len)) - 2;
        moveCursor(self.bounds.y + self.bounds.height - 1, x_pos);
        print("{s}{s}{s}", .{ Color.DIM, count_text, Color.RESET });
    }
};

/// Move cursor to specific position (1-based coordinates)
fn moveCursor(row: u32, col: u32) void {
    print("\x1b[{d};{d}H", .{ row + 1, col + 1 });
}

// Tests
test "tag input initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const bounds = Bounds{ .x = 0, .y = 0, .width = 80, .height = 3 };
    const caps = TermCaps{};

    var tag_input = try TagInput.init(allocator, bounds, caps, .{});
    defer tag_input.deinit();

    try testing.expect(tag_input.tags.items.len == 0);
    try testing.expect(tag_input.input_buffer.items.len == 0);
}

test "adding and removing tags" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const bounds = Bounds{ .x = 0, .y = 0, .width = 80, .height = 3 };
    const caps = TermCaps{};

    var tag_input = try TagInput.init(allocator, bounds, caps, .{});
    defer tag_input.deinit();

    // Add tags
    try tag_input.addTag("tag1", .default);
    try tag_input.addTag("tag2", .primary);
    try tag_input.addTag("tag3", .success);

    try testing.expectEqual(@as(usize, 3), tag_input.tags.items.len);
    try testing.expectEqualStrings("tag1", tag_input.tags.items[0].text);
    try testing.expectEqual(TagCategory.primary, tag_input.tags.items[1].category);

    // Remove tag
    tag_input.removeTag(1);
    try testing.expectEqual(@as(usize, 2), tag_input.tags.items.len);
    try testing.expectEqualStrings("tag3", tag_input.tags.items[1].text);
}

test "tag validation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const bounds = Bounds{ .x = 0, .y = 0, .width = 80, .height = 3 };
    const caps = TermCaps{};

    var tag_input = try TagInput.init(allocator, bounds, caps, .{
        .validation = .{
            .max_length = 10,
            .min_length = 2,
            .allow_duplicates = false,
        },
    });
    defer tag_input.deinit();

    // Valid tag
    try tag_input.addTag("valid", .default);
    try testing.expectEqual(@as(usize, 1), tag_input.tags.items.len);

    // Too short
    try tag_input.addTag("a", .default);
    try testing.expectEqual(@as(usize, 1), tag_input.tags.items.len);

    // Too long
    try tag_input.addTag("verylongtagnamethatexceedslimit", .default);
    try testing.expectEqual(@as(usize, 1), tag_input.tags.items.len);

    // Duplicate (not allowed)
    try tag_input.addTag("valid", .default);
    try testing.expectEqual(@as(usize, 1), tag_input.tags.items.len);
}

test "paste multiple tags" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const bounds = Bounds{ .x = 0, .y = 0, .width = 80, .height = 3 };
    const caps = TermCaps{};

    var tag_input = try TagInput.init(allocator, bounds, caps, .{});
    defer tag_input.deinit();

    const paste_text = "apple, banana, cherry, date";
    try tag_input.pasteMultipleTags(paste_text);

    try testing.expectEqual(@as(usize, 4), tag_input.tags.items.len);
    try testing.expectEqualStrings("apple", tag_input.tags.items[0].text);
    try testing.expectEqualStrings("banana", tag_input.tags.items[1].text);
    try testing.expectEqualStrings("cherry", tag_input.tags.items[2].text);
    try testing.expectEqualStrings("date", tag_input.tags.items[3].text);
}

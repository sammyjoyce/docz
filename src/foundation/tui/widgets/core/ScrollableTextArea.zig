//! ScrollableTextArea - High-performance text viewing and editing widget
//!
//! This widget provides comprehensive text display and editing capabilities with:
//! - Multi-line text display with vertical and horizontal scrolling
//! - Line numbering support (optional)
//! - Word wrapping modes (none, word, character)
//! - Search functionality with highlight
//! - Syntax highlighting support (optional, via callback)
//! - Smooth scrolling with keyboard and mouse
//! - Selection support for copying text
//! - Read-only and editable modes
//! - Viewport management for efficient rendering
//! - Scrollbar indicators (vertical and horizontal)
//! - Keyboard navigation (arrows, page up/down, home/end)
//! - Mouse wheel scrolling and click positioning
//! - Find/search with next/previous navigation
//! - Line and column position tracking
//! - Configurable tab width
//! - Theme integration

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;

const term = @import("../../../term.zig");
const Style = @import("../../core/style.zig").Style;
const Bounds = @import("../../core/bounds.zig").Bounds;
const Widget = @import("../../core/widget_interface.zig").Widget;
const Event = @import("../../core/events.zig").Event;
const Renderer = @import("../../core/renderer.zig").Renderer;
const InputEvent = @import("../../core/renderer.zig").InputEvent;

/// Word wrapping modes
pub const WordWrapMode = enum {
    /// No word wrapping - lines extend beyond viewport
    none,
    /// Wrap at word boundaries
    word,
    /// Wrap at character boundaries
    character,
};

/// Text selection range
pub const Selection = struct {
    start_line: usize,
    start_col: usize,
    end_line: usize,
    end_col: usize,

    pub fn isEmpty(self: Selection) bool {
        return self.start_line == self.end_line and self.start_col == self.end_col;
    }

    pub fn normalize(self: Selection) Selection {
        if (self.start_line < self.end_line or
            (self.start_line == self.end_line and self.start_col <= self.end_col))
        {
            return self;
        }
        return .{
            .start_line = self.end_line,
            .start_col = self.end_col,
            .end_line = self.start_line,
            .end_col = self.start_col,
        };
    }
};

/// Search match with styling
pub const SearchMatch = struct {
    line: usize,
    start_col: usize,
    end_col: usize,
    style: Style = .{ .bg = .{ .ansi256 = 11 } }, // Yellow background
};

/// Syntax highlighting token
pub const SyntaxToken = struct {
    start_pos: usize,
    end_pos: usize,
    style: Style,
};

/// Syntax highlighting callback function type
pub const SyntaxHighlightFn = *const fn (
    line: []const u8,
    line_index: usize,
    user_data: ?*anyopaque,
) []const SyntaxToken;

/// Configuration for ScrollableTextArea
pub const Config = struct {
    /// Enable line numbers
    show_line_numbers: bool = true,
    /// Word wrapping mode
    word_wrap: WordWrapMode = .none,
    /// Tab width in spaces
    tab_width: u8 = 4,
    /// Enable smooth scrolling
    smooth_scrolling: bool = true,
    /// Scroll speed multiplier
    scroll_speed: f32 = 1.0,
    /// Enable syntax highlighting
    syntax_highlight: bool = false,
    /// Syntax highlighting callback
    syntax_highlight_fn: ?SyntaxHighlightFn = null,
    /// User data for syntax highlighting callback
    syntax_highlight_user_data: ?*anyopaque = null,
    /// Read-only mode
    read_only: bool = false,
    /// Show scrollbars
    show_scrollbars: bool = true,
    /// Highlight current line
    highlight_current_line: bool = false,
    /// Current line highlight style
    current_line_style: Style = .{ .bg = .{ .ansi256 = 236 } }, // Light gray
    /// Selection style
    selection_style: Style = .{ .bg = .{ .ansi256 = 4 } }, // Blue background
    /// Search match style
    search_match_style: Style = .{ .bg = .{ .ansi = 11 } }, // Yellow background
    /// Line number style
    line_number_style: Style = .{ .fg = .{ .ansi = 8 } }, // Gray
    /// Enable mouse support
    mouse_support: bool = true,
    /// Enable keyboard navigation
    keyboard_navigation: bool = true,
};

/// ScrollableTextArea widget state
pub const ScrollableTextArea = struct {
    /// Configuration
    config: Config,
    /// Text content (owned)
    content: ArrayList(u8),
    /// Lines cache for efficient rendering
    lines: ArrayList([]const u8),
    /// Current scroll position (line and column)
    scroll_line: usize = 0,
    scroll_col: usize = 0,
    /// Cursor position (line and column)
    cursor_line: usize = 0,
    cursor_col: usize = 0,
    /// Text selection
    selection: ?Selection = null,
    /// Viewport bounds
    viewport: Bounds = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    /// Search query
    search_query: ArrayList(u8),
    /// Search matches
    search_matches: ArrayList(SearchMatch),
    /// Current search match index
    current_search_match: ?usize = null,
    /// Scroll velocity for smooth scrolling
    scroll_velocity: f32 = 0,
    /// Last update timestamp
    last_update: i64 = 0,
    /// Focus state
    focused: bool = false,
    /// Modified state
    modified: bool = false,
    /// Line number width (calculated)
    line_number_width: usize = 0,

    allocator: Allocator,

    const Self = @This();

    /// Initialize ScrollableTextArea
    pub fn init(allocator: Allocator, config: Config) !Self {
        return Self{
            .config = config,
            .content = ArrayList(u8){},
            .lines = ArrayList([]const u8){},
            .search_query = ArrayList(u8){},
            .search_matches = ArrayList(SearchMatch){},
            .allocator = allocator,
            .last_update = std.time.milliTimestamp(),
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.content.deinit(self.allocator);
        self.lines.deinit(self.allocator);
        self.search_query.deinit(self.allocator);
        self.search_matches.deinit(self.allocator);
    }

    /// Set text content
    pub fn setText(self: *Self, text: []const u8) !void {
        self.content.clearRetainingCapacity();
        try self.content.appendSlice(self.allocator, text);
        try self.updateLines();
        self.modified = false;
        self.cursor_line = 0;
        self.cursor_col = 0;
        self.selection = null;
        self.scroll_line = 0;
        self.scroll_col = 0;
    }

    /// Get text content
    pub fn getText(self: Self) []const u8 {
        return self.content.items;
    }

    /// Insert text at cursor position
    pub fn insertText(self: *Self, text: []const u8) !void {
        if (self.config.read_only) return;

        // Delete selection first if it exists
        if (self.selection) |_| {
            try self.deleteSelection();
        }

        const cursor_pos = try self.getCursorBytePosition();
        try self.content.insertSlice(cursor_pos, text);
        try self.updateLines();

        // Update cursor position
        const new_cursor_pos = cursor_pos + text.len;
        const new_cursor_coords = try self.bytePositionToLineCol(new_cursor_pos);
        self.cursor_line = new_cursor_coords.line;
        self.cursor_col = new_cursor_coords.col;

        self.modified = true;
        self.ensureCursorVisible();
    }

    /// Delete character at cursor or selection
    pub fn delete(self: *Self) !void {
        if (self.config.read_only) return;

        if (self.selection) |_| {
            try self.deleteSelection();
        } else {
            const cursor_pos = try self.getCursorBytePosition();
            if (cursor_pos < self.content.items.len) {
                _ = self.content.orderedRemove(cursor_pos);
                try self.updateLines();
                self.modified = true;
            }
        }
    }

    /// Delete character before cursor
    pub fn backspace(self: *Self) !void {
        if (self.config.read_only) return;

        if (self.selection) |_| {
            try self.deleteSelection();
        } else if (self.cursor_col > 0 or self.cursor_line > 0) {
            // Move cursor back one position
            if (self.cursor_col > 0) {
                self.cursor_col -= 1;
            } else {
                self.cursor_line -= 1;
                self.cursor_col = self.getLineLength(self.cursor_line);
            }

            const cursor_pos = try self.getCursorBytePosition();
            _ = self.content.orderedRemove(cursor_pos);
            try self.updateLines();
            self.modified = true;
        }
    }

    /// Set cursor position
    pub fn setCursor(self: *Self, line: usize, col: usize) void {
        self.cursor_line = @min(line, self.lines.items.len -| 1);
        self.cursor_col = @min(col, self.getLineLength(self.cursor_line));
        self.ensureCursorVisible();
    }

    /// Set selection
    pub fn setSelection(self: *Self, selection: ?Selection) void {
        self.selection = if (selection) |sel| sel.normalize() else null;
    }

    /// Get current selection
    pub fn getSelection(self: Self) ?Selection {
        return self.selection;
    }

    /// Select all text
    pub fn selectAll(self: *Self) void {
        if (self.lines.items.len == 0) return;

        self.selection = .{
            .start_line = 0,
            .start_col = 0,
            .end_line = self.lines.items.len - 1,
            .end_col = self.getLineLength(self.lines.items.len - 1),
        };
    }

    /// Clear selection
    pub fn clearSelection(self: *Self) void {
        self.selection = null;
    }

    /// Copy selected text to clipboard
    pub fn copySelection(self: *Self) !?[]const u8 {
        if (self.selection) |sel| {
            const text = try self.getSelectedText(sel);
            // TODO: Implement clipboard integration
            return text;
        }
        return null;
    }

    /// Search for text
    pub fn search(self: *Self, query: []const u8) !void {
        self.search_query.clearRetainingCapacity();
        try self.search_query.appendSlice(query);
        self.search_matches.clearRetainingCapacity();
        self.current_search_match = null;

        if (query.len == 0) return;

        for (self.lines.items, 0..) |line, line_idx| {
            var col: usize = 0;
            while (col < line.len) {
                if (std.mem.indexOf(u8, line[col..], query)) |match_start| {
                    const match = SearchMatch{
                        .line = line_idx,
                        .start_col = col + match_start,
                        .end_col = col + match_start + query.len,
                    };
                    try self.search_matches.append(match);
                    col = match.end_col;
                } else {
                    break;
                }
            }
        }

        if (self.search_matches.items.len > 0) {
            self.current_search_match = 0;
            self.gotoSearchMatch(0);
        }
    }

    /// Go to next search match
    pub fn nextSearchMatch(self: *Self) void {
        if (self.search_matches.items.len == 0) return;

        const current = self.current_search_match orelse 0;
        const next = (current + 1) % self.search_matches.items.len;
        self.current_search_match = next;
        self.gotoSearchMatch(next);
    }

    /// Go to previous search match
    pub fn prevSearchMatch(self: *Self) void {
        if (self.search_matches.items.len == 0) return;

        const current = self.current_search_match orelse 0;
        const prev = if (current == 0) self.search_matches.items.len - 1 else current - 1;
        self.current_search_match = prev;
        self.gotoSearchMatch(prev);
    }

    /// Scroll to make cursor visible
    pub fn ensureCursorVisible(self: *Self) void {
        // Vertical scrolling
        if (self.cursor_line < self.scroll_line) {
            self.scroll_line = self.cursor_line;
        } else if (self.cursor_line >= self.scroll_line + self.viewport.height) {
            self.scroll_line = self.cursor_line - self.viewport.height + 1;
        }

        // Horizontal scrolling
        if (self.cursor_col < self.scroll_col) {
            self.scroll_col = self.cursor_col;
        } else {
            const visible_width = self.viewport.width -| self.line_number_width;
            if (self.cursor_col >= self.scroll_col + visible_width) {
                self.scroll_col = self.cursor_col - visible_width + 1;
            }
        }
    }

    /// Handle keyboard input
    pub fn handleKeyboard(self: *Self, key: term.Key) !void {
        if (!self.config.keyboard_navigation) return;

        switch (key) {
            .arrow_up => {
                if (self.cursor_line > 0) {
                    self.cursor_line -= 1;
                    self.cursor_col = @min(self.cursor_col, self.getLineLength(self.cursor_line));
                    self.ensureCursorVisible();
                }
            },
            .arrow_down => {
                if (self.cursor_line < self.lines.items.len - 1) {
                    self.cursor_line += 1;
                    self.cursor_col = @min(self.cursor_col, self.getLineLength(self.cursor_line));
                    self.ensureCursorVisible();
                }
            },
            .arrow_left => {
                if (self.cursor_col > 0) {
                    self.cursor_col -= 1;
                } else if (self.cursor_line > 0) {
                    self.cursor_line -= 1;
                    self.cursor_col = self.getLineLength(self.cursor_line);
                }
                self.ensureCursorVisible();
            },
            .arrow_right => {
                const line_len = self.getLineLength(self.cursor_line);
                if (self.cursor_col < line_len) {
                    self.cursor_col += 1;
                } else if (self.cursor_line < self.lines.items.len - 1) {
                    self.cursor_line += 1;
                    self.cursor_col = 0;
                }
                self.ensureCursorVisible();
            },
            .page_up => {
                const page_size = self.viewport.height;
                self.scroll_velocity = 0;
                if (self.scroll_line > page_size) {
                    self.scroll_line -= page_size;
                    self.cursor_line = @max(0, self.cursor_line -| page_size);
                } else {
                    self.scroll_line = 0;
                    self.cursor_line = 0;
                }
                self.cursor_col = @min(self.cursor_col, self.getLineLength(self.cursor_line));
            },
            .page_down => {
                const page_size = self.viewport.height;
                const max_scroll = self.lines.items.len -| self.viewport.height;
                self.scroll_velocity = 0;
                self.scroll_line = @min(max_scroll, self.scroll_line + page_size);
                self.cursor_line = @min(self.lines.items.len - 1, self.cursor_line + page_size);
                self.cursor_col = @min(self.cursor_col, self.getLineLength(self.cursor_line));
            },
            .home => {
                self.cursor_col = 0;
                self.ensureCursorVisible();
            },
            .end => {
                self.cursor_col = self.getLineLength(self.cursor_line);
                self.ensureCursorVisible();
            },
            else => {},
        }
    }

    /// Handle mouse input
    pub fn handleMouse(self: *Self, event: term.MouseEvent) !void {
        if (!self.config.mouse_support) return;

        switch (event.type) {
            .scroll_up => {
                self.scroll_velocity = -300 * self.config.scroll_speed;
            },
            .scroll_down => {
                self.scroll_velocity = 300 * self.config.scroll_speed;
            },
            .press => {
                // Calculate line and column from mouse position
                const mouse_line = self.scroll_line + (event.y - self.viewport.y);
                const mouse_col = self.scroll_col + (event.x - self.viewport.x - @as(i32, @intCast(self.line_number_width)));

                if (mouse_line < self.lines.items.len and mouse_col >= 0) {
                    self.cursor_line = mouse_line;
                    self.cursor_col = @max(0, @min(@as(usize, @intCast(mouse_col)), self.getLineLength(mouse_line)));
                    self.ensureCursorVisible();
                }
            },
            else => {},
        }
    }

    /// Update scroll physics
    fn updateScrollPhysics(self: *Self) void {
        if (!self.config.smooth_scrolling) return;

        const now = std.time.milliTimestamp();
        const delta_time = @as(f32, @floatFromInt(now - self.last_update)) / 1000.0;
        self.last_update = now;

        if (@abs(self.scroll_velocity) > 0.01) {
            self.scroll_line = @as(usize, @intFromFloat(@max(0, @as(f32, @floatFromInt(self.scroll_line)) + self.scroll_velocity * delta_time)));
            const max_scroll = self.lines.items.len -| self.viewport.height;
            self.scroll_line = @min(self.scroll_line, max_scroll);

            // Apply friction
            const friction = 0.95;
            self.scroll_velocity *= std.math.pow(f32, friction, delta_time);

            if (@abs(self.scroll_velocity) < 0.01) {
                self.scroll_velocity = 0;
            }
        }
    }

    /// Update line cache
    fn updateLines(self: *Self) !void {
        self.lines.clearRetainingCapacity();

        var line_start: usize = 0;
        var i: usize = 0;
        while (i < self.content.items.len) {
            if (self.content.items[i] == '\n') {
                try self.lines.append(self.allocator, self.content.items[line_start..i]);
                line_start = i + 1;
            }
            i += 1;
        }

        // Add final line if content doesn't end with newline
        if (line_start < self.content.items.len) {
            try self.lines.append(self.allocator, self.content.items[line_start..]);
        } else if (self.content.items.len == 0) {
            try self.lines.append(self.allocator, "");
        }

        // Update line number width
        if (self.config.show_line_numbers) {
            const max_line = self.lines.items.len;
            self.line_number_width = if (max_line == 0) 1 else std.math.log10(@as(f64, @floatFromInt(max_line))) + 2;
        } else {
            self.line_number_width = 0;
        }
    }

    /// Get line length
    fn getLineLength(self: Self, line_idx: usize) usize {
        if (line_idx >= self.lines.items.len) return 0;
        return self.lines.items[line_idx].len;
    }

    /// Get cursor byte position
    fn getCursorBytePosition(self: Self) !usize {
        if (self.cursor_line >= self.lines.items.len) return 0;

        var pos: usize = 0;
        for (0..self.cursor_line) |i| {
            pos += self.lines.items[i].len + 1; // +1 for newline
        }
        pos += self.cursor_col;
        return pos;
    }

    /// Convert byte position to line/column
    fn bytePositionToLineCol(self: Self, byte_pos: usize) !struct { line: usize, col: usize } {
        var pos: usize = 0;
        var line: usize = 0;

        while (line < self.lines.items.len) {
            const line_len = self.lines.items[line].len;
            if (pos + line_len >= byte_pos) {
                return .{ .line = line, .col = byte_pos - pos };
            }
            pos += line_len + 1; // +1 for newline
            line += 1;
        }

        return .{ .line = self.lines.items.len - 1, .col = self.lines.items[self.lines.items.len - 1].len };
    }

    /// Delete selected text
    fn deleteSelection(self: *Self) !void {
        if (self.selection) |sel| {
            const start_pos = try self.lineColToBytePosition(sel.start_line, sel.start_col);
            const end_pos = try self.lineColToBytePosition(sel.end_line, sel.end_col);

            // Remove the selected text
            const new_len = self.content.items.len - (end_pos - start_pos);
            std.mem.copyForwards(u8, self.content.items[start_pos..new_len], self.content.items[end_pos..]);
            self.content.shrinkRetainingCapacity(new_len);

            try self.updateLines();

            // Move cursor to start of selection
            self.cursor_line = sel.start_line;
            self.cursor_col = sel.start_col;
            self.selection = null;
            self.modified = true;
        }
    }

    /// Convert line/column to byte position
    fn lineColToBytePosition(self: Self, line: usize, col: usize) !usize {
        if (line >= self.lines.items.len) return self.content.items.len;

        var pos: usize = 0;
        for (0..line) |i| {
            pos += self.lines.items[i].len + 1;
        }
        pos += @min(col, self.lines.items[line].len);
        return pos;
    }

    /// Get selected text
    fn getSelectedText(self: Self, selection: Selection) ![]const u8 {
        const start_pos = try self.lineColToBytePosition(selection.start_line, selection.start_col);
        const end_pos = try self.lineColToBytePosition(selection.end_line, selection.end_col);
        return self.content.items[start_pos..end_pos];
    }

    /// Go to search match
    fn gotoSearchMatch(self: *Self, match_idx: usize) void {
        if (match_idx >= self.search_matches.items.len) return;

        const match = self.search_matches.items[match_idx];
        self.cursor_line = match.line;
        self.cursor_col = match.start_col;
        self.ensureCursorVisible();
    }

    /// Render the text area
    pub fn render(self: *Self, renderer: *Renderer, bounds: Bounds) !void {
        self.viewport = bounds;

        // Update scroll physics
        self.updateScrollPhysics();

        const visible_width = bounds.width -| self.line_number_width;
        const visible_height = bounds.height;

        // Render background
        try renderer.fillRect(bounds, .{ .indexed = 0 }); // Black background

        var y: usize = 0;
        const end_line = @min(self.lines.items.len, self.scroll_line + visible_height);

        for (self.scroll_line..end_line) |line_idx| {
            if (y >= visible_height) break;

            const line = self.lines.items[line_idx];
            const display_line = line_idx + 1; // 1-based for display

            // Render line number
            if (self.config.show_line_numbers) {
                const line_num_str = try std.fmt.allocPrint(self.allocator, "{d: >{d}} ", .{ display_line, self.line_number_width - 1 });
                defer self.allocator.free(line_num_str);

                try renderer.drawText(bounds.x, bounds.y + @as(i32, @intCast(y)), line_num_str, self.config.line_number_style);
            }

            // Render line content
            const line_x = bounds.x + @as(i32, @intCast(self.line_number_width));
            const line_start_col = self.scroll_col;
            const line_end_col = @min(line.len, line_start_col + visible_width);

            if (line_start_col < line.len) {
                const visible_text = line[line_start_col..line_end_col];

                // Apply syntax highlighting if enabled
                if (self.config.syntax_highlight and self.config.syntax_highlight_fn != null) {
                    try self.renderSyntaxHighlightedLine(renderer, line_x, bounds.y + @as(i32, @intCast(y)), line, line_idx, line_start_col);
                } else {
                    try renderer.drawText(line_x, bounds.y + @as(i32, @intCast(y)), visible_text, .{});
                }

                // Highlight search matches
                try self.renderSearchHighlights(renderer, line_x, bounds.y + @as(i32, @intCast(y)), line_idx, line_start_col, visible_text);

                // Highlight selection
                try self.renderSelection(renderer, line_x, bounds.y + @as(i32, @intCast(y)), line_idx, line_start_col, visible_text);

                // Highlight current line
                if (self.config.highlight_current_line and line_idx == self.cursor_line) {
                    const line_bounds = Bounds{
                        .x = line_x,
                        .y = bounds.y + @as(i32, @intCast(y)),
                        .width = visible_width,
                        .height = 1,
                    };
                    try renderer.fillRect(line_bounds, self.config.current_line_style.bg.?);
                }
            }

            y += 1;
        }

        // Render scrollbars
        if (self.config.show_scrollbars) {
            try self.renderScrollbars(renderer, bounds);
        }

        // Render cursor
        if (self.focused and !self.config.read_only) {
            const cursor_x = bounds.x + @as(i32, @intCast(self.line_number_width + self.cursor_col - self.scroll_col));
            const cursor_y = bounds.y + @as(i32, @intCast(self.cursor_line - self.scroll_line));
            if (cursor_x >= bounds.x and cursor_x < bounds.x + @as(i32, @intCast(bounds.width)) and
                cursor_y >= bounds.y and cursor_y < bounds.y + @as(i32, @intCast(bounds.height)))
            {
                try renderer.showCursor(true);
                try renderer.setCursorPosition(.{ .x = cursor_x, .y = cursor_y });
            }
        }
    }

    /// Render syntax highlighted line
    fn renderSyntaxHighlightedLine(self: *Self, renderer: *Renderer, x: i32, y: i32, line: []const u8, line_idx: usize, start_col: usize) !void {
        if (self.config.syntax_highlight_fn) |highlight_fn| {
            const tokens = highlight_fn(line, line_idx, self.config.syntax_highlight_user_data);

            var current_col: usize = 0;
            for (tokens) |token| {
                if (token.end_pos <= start_col) continue;
                if (token.start_pos >= start_col + (self.viewport.width - self.line_number_width)) break;

                const token_start = @max(token.start_pos, start_col);
                const token_end = @min(token.end_pos, start_col + (self.viewport.width - self.line_number_width));

                if (token_start < token_end) {
                    const token_text = line[token_start..token_end];
                    const token_x = x + @as(i32, @intCast(token_start - start_col));
                    try renderer.drawText(token_x, y, token_text, token.style);
                    current_col = token_end;
                }
            }

            // Render remaining text without highlighting
            if (current_col < line.len) {
                const remaining_start = @max(current_col, start_col);
                const remaining_end = @min(line.len, start_col + (self.viewport.width - self.line_number_width));
                if (remaining_start < remaining_end) {
                    const remaining_text = line[remaining_start..remaining_end];
                    const remaining_x = x + @as(i32, @intCast(remaining_start - start_col));
                    try renderer.drawText(remaining_x, y, remaining_text, .{});
                }
            }
        }
    }

    /// Render search highlights
    fn renderSearchHighlights(self: *Self, renderer: *Renderer, x: i32, y: i32, line_idx: usize, start_col: usize, visible_text: []const u8) !void {
        for (self.search_matches.items) |match| {
            if (match.line != line_idx) continue;

            const match_start = @max(match.start_col, start_col);
            const match_end = @min(match.end_col, start_col + visible_text.len);

            if (match_start < match_end) {
                const highlight_x = x + @as(i32, @intCast(match_start - start_col));
                const highlight_width = match_end - match_start;

                const highlight_bounds = Bounds{
                    .x = highlight_x,
                    .y = y,
                    .width = @intCast(highlight_width),
                    .height = 1,
                };
                try renderer.fillRect(highlight_bounds, self.config.search_match_style.bg.?);
            }
        }
    }

    /// Render selection
    fn renderSelection(self: *Self, renderer: *Renderer, x: i32, y: i32, line_idx: usize, start_col: usize, visible_text: []const u8) !void {
        if (self.selection) |sel| {
            var selection_start: usize = 0;
            var selection_end: usize = 0;

            if (line_idx == sel.start_line and line_idx == sel.end_line) {
                // Selection within single line
                selection_start = @max(sel.start_col, start_col);
                selection_end = @min(sel.end_col, start_col + visible_text.len);
            } else if (line_idx == sel.start_line) {
                // Selection starts on this line
                selection_start = @max(sel.start_col, start_col);
                selection_end = start_col + visible_text.len;
            } else if (line_idx == sel.end_line) {
                // Selection ends on this line
                selection_start = start_col;
                selection_end = @min(sel.end_col, start_col + visible_text.len);
            } else if (line_idx > sel.start_line and line_idx < sel.end_line) {
                // Selection spans entire line
                selection_start = start_col;
                selection_end = start_col + visible_text.len;
            }

            if (selection_start < selection_end) {
                const selection_x = x + @as(i32, @intCast(selection_start - start_col));
                const selection_width = selection_end - selection_start;

                const selection_bounds = Bounds{
                    .x = selection_x,
                    .y = y,
                    .width = @intCast(selection_width),
                    .height = 1,
                };
                try renderer.fillRect(selection_bounds, self.config.selection_style.bg.?);
            }
        }
    }

    /// Render scrollbars
    fn renderScrollbars(self: *Self, renderer: *Renderer, bounds: Bounds) !void {
        const content_height = self.lines.items.len;
        const content_width = self.getMaxLineLength();

        // Vertical scrollbar
        if (content_height > bounds.height) {
            const scrollbar_x = bounds.x + bounds.width - 1;
            const scrollbar_height = @max(1, (bounds.height * bounds.height) / content_height);
            const scrollbar_pos = (self.scroll_line * bounds.height) / content_height;

            // Track
            for (0..bounds.height) |i| {
                try renderer.drawText(scrollbar_x, bounds.y + @as(i32, @intCast(i)), "│", .{ .fg = .{ .indexed = 8 } });
            }

            // Thumb
            for (0..scrollbar_height) |i| {
                const y = bounds.y + @as(i32, @intCast(scrollbar_pos + i));
                if (y < bounds.y + @as(i32, @intCast(bounds.height))) {
                    try renderer.drawText(scrollbar_x, y, "█", .{ .fg = .{ .indexed = 7 } });
                }
            }
        }

        // Horizontal scrollbar
        if (content_width > (bounds.width - self.line_number_width)) {
            const scrollbar_y = bounds.y + bounds.height - 1;
            const visible_width = bounds.width - self.line_number_width;
            const scrollbar_width = @max(1, (visible_width * visible_width) / content_width);
            const scrollbar_pos = (self.scroll_col * visible_width) / content_width;

            // Track
            for (0..visible_width) |i| {
                try renderer.drawText(bounds.x + @as(i32, @intCast(self.line_number_width + i)), scrollbar_y, "─", .{ .fg = .{ .indexed = 8 } });
            }

            // Thumb
            for (0..scrollbar_width) |i| {
                const x = bounds.x + @as(i32, @intCast(self.line_number_width + scrollbar_pos + i));
                if (x < bounds.x + @as(i32, @intCast(bounds.width))) {
                    try renderer.drawText(x, scrollbar_y, "█", .{ .fg = .{ .indexed = 7 } });
                }
            }
        }
    }

    /// Get maximum line length
    fn getMaxLineLength(self: Self) usize {
        var max_len: usize = 0;
        for (self.lines.items) |line| {
            max_len = @max(max_len, line.len);
        }
        return max_len;
    }
};

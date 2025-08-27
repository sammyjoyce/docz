//! Enhanced select menu component with keyboard navigation and search
//! Supports multiple selection modes and rich item display

const std = @import("std");
const term_ansi = @import("term_shared").ansi.color;
const term_cursor = @import("term_shared").ansi.cursor;
const term_screen = @import("term_shared").ansi.screen;
const term_caps = @import("term_shared").caps;
const completion = @import("../../interactive/completion.zig");
const Allocator = std.mem.Allocator;

pub const SelectionMode = enum {
    single,
    multiple,
    radio, // Only one can be selected, but shows all options
};

pub const MenuAction = enum {
    select,
    cancel,
    search,
};

pub const SelectMenuItem = struct {
    id: []const u8,
    display_text: []const u8,
    description: ?[]const u8 = null,
    icon: ?[]const u8 = null,
    disabled: bool = false,
    selected: bool = false,
    value: ?[]const u8 = null, // Optional associated value

    pub fn init(id: []const u8, display_text: []const u8) SelectMenuItem {
        return .{
            .id = id,
            .display_text = display_text,
        };
    }

    pub fn withDescription(self: SelectMenuItem, desc: []const u8) SelectMenuItem {
        return .{
            .id = self.id,
            .display_text = self.display_text,
            .description = desc,
            .icon = self.icon,
            .disabled = self.disabled,
            .selected = self.selected,
            .value = self.value,
        };
    }

    pub fn withIcon(self: SelectMenuItem, icon_char: []const u8) SelectMenuItem {
        return .{
            .id = self.id,
            .display_text = self.display_text,
            .description = self.description,
            .icon = icon_char,
            .disabled = self.disabled,
            .selected = self.selected,
            .value = self.value,
        };
    }

    pub fn asDisabled(self: SelectMenuItem) SelectMenuItem {
        return .{
            .id = self.id,
            .display_text = self.display_text,
            .description = self.description,
            .icon = self.icon,
            .disabled = true,
            .selected = self.selected,
            .value = self.value,
        };
    }

    pub fn withValue(self: SelectMenuItem, val: []const u8) SelectMenuItem {
        return .{
            .id = self.id,
            .display_text = self.display_text,
            .description = self.description,
            .icon = self.icon,
            .disabled = self.disabled,
            .selected = self.selected,
            .value = val,
        };
    }
};

pub const SelectMenu = struct {
    allocator: Allocator,
    caps: term_caps.TermCaps,
    items: std.ArrayList(SelectMenuItem),
    filtered_items: std.ArrayList(usize), // Indices into items array
    title: []const u8,
    selection_mode: SelectionMode,
    currentIndex: usize,
    searchQuery: std.ArrayList(u8),
    showSearch: bool,
    showDescriptions: bool,
    showIcons: bool,
    maxVisibleItems: usize,
    scroll_offset: usize,

    pub fn init(
        allocator: Allocator,
        title: []const u8,
        selection_mode: SelectionMode,
    ) !SelectMenu {
        return .{
            .allocator = allocator,
            .caps = term_caps.getTermCaps(),
            .items = std.ArrayList(SelectMenuItem).init(allocator),
            .filtered_items = std.ArrayList(usize).init(allocator),
            .title = title,
            .selection_mode = selection_mode,
            .currentIndex = 0,
            .searchQuery = std.ArrayList(u8).init(allocator),
            .showSearch = false,
            .showDescriptions = true,
            .showIcons = true,
            .maxVisibleItems = 10,
            .scroll_offset = 0,
        };
    }

    pub fn deinit(self: *SelectMenu) void {
        self.items.deinit();
        self.filtered_items.deinit();
        self.searchQuery.deinit();
    }

    pub fn addItem(self: *SelectMenu, item: SelectMenuItem) !void {
        try self.items.append(item);
        try self.updateFilter();
    }

    pub fn addItems(self: *SelectMenu, items: []const SelectMenuItem) !void {
        for (items) |item| {
            try self.addItem(item);
        }
    }

    pub fn configure(
        self: *SelectMenu,
        options: struct {
            show_search: bool = false,
            show_descriptions: bool = true,
            show_icons: bool = true,
            max_visible_items: usize = 10,
        },
    ) void {
        self.showSearch = options.show_search;
        self.showDescriptions = options.show_descriptions;
        self.showIcons = options.show_icons;
        self.maxVisibleItems = options.max_visible_items;
    }

    /// Update the filtered items based on search query
    fn updateFilter(self: *SelectMenu) !void {
        self.filtered_items.clearRetainingCapacity();

        for (self.items.items, 0..) |item, i| {
            if (self.searchQuery.items.len == 0) {
                try self.filtered_items.append(i);
            } else {
                // Simple case-insensitive search
                const query_lower = try std.ascii.allocLowerString(self.allocator, self.searchQuery.items);
                defer self.allocator.free(query_lower);

                const text_lower = try std.ascii.allocLowerString(self.allocator, item.display_text);
                defer self.allocator.free(text_lower);

                if (std.mem.indexOf(u8, text_lower, query_lower) != null) {
                    try self.filtered_items.append(i);
                }
            }
        }

        // Reset selection if current index is out of bounds
        if (self.currentIndex >= self.filtered_items.items.len) {
            self.currentIndex = 0;
        }
    }

    /// Render the select menu
    pub fn render(self: *SelectMenu, writer: anytype) !void {
        // Clear screen area
        try term_cursor.saveCursor(writer, self.caps);

        // Title
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }

        try writer.print("┌─ {s} ", .{self.title});

        // Selection mode indicator
        const mode_text = switch (self.selection_mode) {
            .single => "(Single)",
            .multiple => "(Multiple)",
            .radio => "(Radio)",
        };
        try writer.writeAll(mode_text);

        // Fill rest of header
        const header_len = self.title.len + mode_text.len + 4;
        const total_width = 60;
        const padding = if (total_width > header_len) total_width - header_len else 0;
        for (0..padding) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┐\n");

        // Search bar if enabled
        if (self.showSearch) {
            try self.renderSearchBar(writer);
        }

        // Menu items
        const visible_start = self.scroll_offset;
        const visible_end = @min(visible_start + self.maxVisibleItems, self.filtered_items.items.len);

        for (self.filtered_items.items[visible_start..visible_end], 0..) |item_index, visible_idx| {
            const actual_index = visible_start + visible_idx;
            const is_current = actual_index == self.currentIndex;
            try self.renderMenuItem(writer, self.items.items[item_index], is_current);
        }

        // Scrolling indicators
        if (self.filtered_items.items.len > self.maxVisibleItems) {
            try self.renderScrollIndicators(writer);
        }

        // Footer
        try self.renderFooter(writer);

        try term_ansi.resetStyle(writer, self.caps);
        try term_cursor.restoreCursor(writer, self.caps);
    }

    fn renderSearchBar(self: *SelectMenu, writer: anytype) !void {
        try writer.writeAll("│ ");

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 200, 200, 200);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 7);
        }

        try writer.writeAll("Search: ");

        // Search input
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setBackgroundRgb(writer, self.caps, 30, 30, 30);
            try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
        } else {
            try term_ansi.setBackground256(writer, self.caps, 0);
            try term_ansi.setForeground256(writer, self.caps, 15);
        }

        try writer.writeAll(self.searchQuery.items);

        // Cursor
        try writer.writeAll("│");

        // Pad to width
        const used_width = 10 + self.searchQuery.items.len;
        const padding = if (58 > used_width) 58 - used_width else 0;
        for (0..padding) |_| {
            try writer.writeAll(" ");
        }

        try term_ansi.resetStyle(writer, self.caps);
        try writer.writeAll(" │\n");

        // Separator
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }
        try writer.writeAll("├");
        for (0..58) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┤\n");
    }

    fn renderMenuItem(self: *SelectMenu, writer: anytype, item: SelectMenuItem, is_current: bool) !void {
        try writer.writeAll("│");

        // Selection indicator background
        if (is_current) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setBackgroundRgb(writer, self.caps, 30, 30, 80);
                try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
            } else {
                try term_ansi.setBackground256(writer, self.caps, 18);
                try term_ansi.setForeground256(writer, self.caps, 15);
            }
        }

        // Selection state indicator
        const selection_indicator = switch (self.selection_mode) {
            .single => if (is_current) "► " else "  ",
            .multiple => if (item.selected) "☑ " else "☐ ",
            .radio => if (item.selected) "● " else "○ ",
        };
        try writer.writeAll(selection_indicator);

        // Icon
        if (self.showIcons and item.icon != null) {
            try writer.print("{s} ", .{item.icon.?});
        } else {
            try writer.writeAll("  ");
        }

        // Main text
        if (item.disabled) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 100, 100, 100);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 8);
            }
        }

        try writer.writeAll(item.display_text);

        // Description
        if (self.showDescriptions and item.description != null) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 150, 150, 150);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 8);
            }
            try writer.print(" - {s}", .{item.description.?});
        }

        try term_ansi.resetStyle(writer, self.caps);

        // Pad to edge
        try writer.writeAll("                     │\n");
    }

    fn renderScrollIndicators(self: *SelectMenu, writer: anytype) !void {
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }

        try writer.writeAll("│ ");

        if (self.scroll_offset > 0) {
            try writer.writeAll("↑ More items above");
        } else {
            try writer.writeAll("                  ");
        }

        try writer.writeAll("                                      │\n");

        if (self.scroll_offset + self.max_visible_items < self.filtered_items.items.len) {
            try writer.writeAll("│ ↓ More items below                                    │\n");
        }
    }

    fn renderFooter(self: *SelectMenu, writer: anytype) !void {
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }

        try writer.writeAll("└");
        for (0..58) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┘\n");

        // Instructions
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 150, 150, 150);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 8);
        }

        const instructions = switch (self.selection_mode) {
            .single => "↑/↓ navigate, Enter select, Esc cancel",
            .multiple => "↑/↓ navigate, Space toggle, Enter confirm, Esc cancel",
            .radio => "↑/↓ navigate, Space select, Enter confirm, Esc cancel",
        };

        if (self.showSearch) {
            try writer.print("{s}, / search\n", .{instructions});
        } else {
            try writer.print("{s}\n", .{instructions});
        }
    }

    /// Handle keyboard input
    pub fn handleInput(self: *SelectMenu, key: u8) !MenuAction {
        switch (key) {
            // Up arrow (simplified - in real implementation would handle escape sequences)
            // Using Ctrl+P for now
            16 => {
                if (self.currentIndex > 0) {
                    self.currentIndex -= 1;
                    self.updateScrollPosition();
                }
                return .search; // Continue
            },

            // Down arrow - Ctrl+N for now
            14 => {
                if (self.currentIndex + 1 < self.filtered_items.items.len) {
                    self.currentIndex += 1;
                    self.updateScrollPosition();
                }
                return .search; // Continue
            },

            // Space - toggle selection (for multiple/radio mode)
            32 => {
                if (self.filtered_items.items.len > 0) {
                    const item_index = self.filtered_items.items[self.currentIndex];
                    const item = &self.items.items[item_index];

                    if (!item.disabled) {
                        switch (self.selection_mode) {
                            .multiple => {
                                item.selected = !item.selected;
                            },
                            .radio => {
                                // Clear all selections first
                                for (self.items.items) |*it| {
                                    it.selected = false;
                                }
                                item.selected = true;
                            },
                            .single => {
                                return .select;
                            },
                        }
                    }
                }
                return .search; // Continue
            },

            // Enter - confirm selection
            13 => {
                return .select;
            },

            // Escape - cancel
            27 => {
                return .cancel;
            },

            // Search mode - '/'
            47 => {
                if (self.showSearch) {
                    // Enter search mode (would need more complex state management)
                }
                return .search; // Continue
            },

            // Backspace in search
            127, 8 => {
                if (self.showSearch and self.searchQuery.items.len > 0) {
                    _ = self.searchQuery.pop();
                    try self.updateFilter();
                }
                return .search; // Continue
            },

            // Printable characters for search
            33...126 => {
                if (self.showSearch) {
                    try self.searchQuery.append(key);
                    try self.updateFilter();
                }
                return .search; // Continue
            },

            else => return .search, // Continue for unhandled keys
        }
    }

    fn updateScrollPosition(self: *SelectMenu) void {
        if (self.currentIndex < self.scroll_offset) {
            self.scroll_offset = self.currentIndex;
        } else if (self.currentIndex >= self.scroll_offset + self.maxVisibleItems) {
            self.scroll_offset = self.currentIndex - self.maxVisibleItems + 1;
        }
    }

    /// Get selected items (for multiple selection mode)
    pub fn getSelectedItems(self: SelectMenu, allocator: Allocator) ![]SelectMenuItem {
        var selected = std.ArrayList(SelectMenuItem).init(allocator);
        errdefer selected.deinit();

        for (self.items.items) |item| {
            if (item.selected) {
                try selected.append(item);
            }
        }

        return try selected.toOwnedSlice();
    }

    /// Get currently highlighted item
    pub fn getCurrentItem(self: SelectMenu) ?SelectMenuItem {
        if (self.currentIndex < self.filtered_items.items.len) {
            const item_index = self.filtered_items.items[self.currentIndex];
            return self.items.items[item_index];
        }
        return null;
    }
};

//! Enhanced Select Menu with Advanced Terminal Capabilities
//! Supports mouse interaction, rich graphics, hyperlinks, and modern terminal features
//! while maintaining backward compatibility with basic terminals.

const std = @import("std");
const input_manager = @import("input_manager.zig");
const term_shared = @import("term_shared");
const term_ansi = term_shared.ansi.color;
const term_cursor = term_shared.ansi.cursor;
const term_screen = term_shared.ansi.screen;
const term_caps = term_shared.caps;
const graphics_manager = term_shared.graphics_manager;
const hyperlinks = @import("../../utils/hyperlinks.zig");

const Input = input_manager.Input;
const InputEvent = input_manager.InputEvent;
const Key = input_manager.Key;
const MouseEvent = input_manager.MouseEvent;
const GraphicsManager = graphics_manager.GraphicsManager;
const Allocator = std.mem.Allocator;

pub const SelectionMode = enum {
    single, // Single selection (traditional)
    multiple, // Multiple checkboxes
    radio, // Radio buttons (single selection)
};

pub const MenuAction = enum {
    select, // User confirmed selection
    cancel, // User cancelled
    keep_running, // Continue processing input
};

pub const SelectMenuItem = struct {
    id: []const u8,
    display_text: []const u8,
    description: ?[]const u8 = null,
    icon: ?[]const u8 = null,
    disabled: bool = false,
    selected: bool = false,
    value: ?[]const u8 = null,
    hyperlink: ?[]const u8 = null, // URL for OSC 8 hyperlinks

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
            .hyperlink = self.hyperlink,
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
            .hyperlink = self.hyperlink,
        };
    }

    pub fn withHyperlink(self: SelectMenuItem, url: []const u8) SelectMenuItem {
        return .{
            .id = self.id,
            .display_text = self.display_text,
            .description = self.description,
            .icon = self.icon,
            .disabled = self.disabled,
            .selected = self.selected,
            .value = self.value,
            .hyperlink = url,
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
            .hyperlink = self.hyperlink,
        };
    }
};

/// Enhanced Select Menu with mouse support and rich terminal features
pub const EnhancedSelectMenu = struct {
    allocator: Allocator,
    inputManager: *Input,
    caps: term_caps.TermCaps,
    graphics: ?*GraphicsManager,

    // Menu data
    items: std.array_list.Managed(SelectMenuItem),
    filtered_items: std.array_list.Managed(usize), // Indices into items array
    title: []const u8,
    selection_mode: SelectionMode,
    current_index: usize,
    search_query: std.array_list.Managed(u8),

    // Display configuration
    show_search: bool,
    show_descriptions: bool,
    show_icons: bool,
    show_mouse_hints: bool,
    max_visible_items: usize,
    scroll_offset: usize,

    // Mouse interaction
    menu_start_row: u32,
    menu_start_col: u32,
    mouse_enabled: bool,

    // Rich features
    use_graphics: bool,
    use_hyperlinks: bool,

    pub fn init(
        allocator: Allocator,
        input_mgr: *Input,
        title: []const u8,
        selection_mode: SelectionMode,
    ) !EnhancedSelectMenu {
        const caps = term_caps.getTermCaps();

        return EnhancedSelectMenu{
            .allocator = allocator,
            .input_manager = input_mgr,
            .caps = caps,
            .graphics = null,
            .items = std.array_list.Managed(SelectMenuItem).init(allocator),
            .filtered_items = std.array_list.Managed(usize).init(allocator),
            .title = title,
            .selection_mode = selection_mode,
            .current_index = 0,
            .search_query = std.array_list.Managed(u8).init(allocator),
            .show_search = false,
            .show_descriptions = true,
            .show_icons = true,
            .show_mouse_hints = caps.supportsEnhancedMouse,
            .max_visible_items = 10,
            .scroll_offset = 0,
            .menu_start_row = 0,
            .menu_start_col = 0,
            .mouse_enabled = caps.supportsEnhancedMouse,
            .use_graphics = caps.supportsKittyGraphics or caps.supportsSixel,
            .use_hyperlinks = caps.supportsHyperlinks,
        };
    }

    pub fn deinit(self: *EnhancedSelectMenu) void {
        self.items.deinit();
        self.filtered_items.deinit();
        self.search_query.deinit();
    }

    pub fn setGraphicsManager(self: *EnhancedSelectMenu, gm: *GraphicsManager) void {
        self.graphics = gm;
    }

    pub fn addItem(self: *EnhancedSelectMenu, item: SelectMenuItem) !void {
        try self.items.append(item);
        try self.updateFilter();
    }

    pub fn addItems(self: *EnhancedSelectMenu, items: []const SelectMenuItem) !void {
        for (items) |item| {
            try self.addItem(item);
        }
    }

    pub fn configure(
        self: *EnhancedSelectMenu,
        options: struct {
            show_search: bool = false,
            show_descriptions: bool = true,
            show_icons: bool = true,
            show_mouse_hints: ?bool = null,
            max_visible_items: usize = 10,
        },
    ) void {
        self.show_search = options.show_search;
        self.show_descriptions = options.show_descriptions;
        self.show_icons = options.show_icons;
        self.show_mouse_hints = options.show_mouse_hints orelse self.caps.supportsEnhancedMouse;
        self.max_visible_items = options.max_visible_items;
    }

    /// Run the interactive menu and return the user's selection
    pub fn run(self: *EnhancedSelectMenu) !MenuAction {
        // Enable terminal features
        try self.input_manager.enableFeatures(.{
            .raw_mode = true,
            .mouse_events = self.mouse_enabled,
            .bracketed_paste = true,
            .focus_events = false,
        });

        // Main input loop
        while (true) {
            // Render the menu
            try self.render();

            // Wait for input
            const event = try self.input_manager.nextEvent();
            const action = try self.handleInput(event);

            switch (action) {
                .select => return .select,
                .cancel => return .cancel,
                .keep_running => {}, // Keep processing
            }
        }
    }

    /// Update the filtered items based on search query
    fn updateFilter(self: *EnhancedSelectMenu) !void {
        self.filtered_items.clearRetainingCapacity();

        for (self.items.items, 0..) |item, i| {
            if (self.search_query.items.len == 0) {
                try self.filtered_items.append(i);
            } else {
                // Simple case-insensitive search
                const query_lower = try std.ascii.allocLowerString(self.allocator, self.search_query.items);
                defer self.allocator.free(query_lower);

                const text_lower = try std.ascii.allocLowerString(self.allocator, item.display_text);
                defer self.allocator.free(text_lower);

                if (std.mem.indexOf(u8, text_lower, query_lower) != null) {
                    try self.filtered_items.append(i);
                }
            }
        }

        // Reset selection if current index is out of bounds
        if (self.current_index >= self.filtered_items.items.len) {
            self.current_index = if (self.filtered_items.items.len > 0) 0 else 0;
        }
    }

    /// Render the enhanced select menu
    fn render(self: *EnhancedSelectMenu) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        // Clear screen and get cursor position
        try term_screen.clearScreen(stdout, self.caps);
        try term_cursor.moveTo(stdout, self.caps, 1, 1);

        // Store menu position for mouse calculations
        self.menu_start_row = 1;
        self.menu_start_col = 1;

        // Title with enhanced styling
        try self.renderTitle(stdout);

        // Search bar if enabled
        if (self.show_search) {
            try self.renderSearchBar(stdout);
        }

        // Menu items with mouse support
        try self.renderMenuItems(stdout);

        // Scrolling indicators
        if (self.filtered_items.items.len > self.max_visible_items) {
            try self.renderScrollIndicators(stdout);
        }

        // Enhanced footer with instructions
        try self.renderEnhancedFooter(stdout);

        // Flush output
        try stdout.context.flush();
    }

    fn renderTitle(self: *EnhancedSelectMenu, writer: anytype) !void {
        // Enhanced title with graphics support
        if (self.use_graphics and self.graphics != null) {
            // Could add a small icon or visual element here
        }

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

        // Mouse hint in title
        if (self.show_mouse_hints and self.mouse_enabled) {
            try writer.writeAll(" 🖱️");
        }

        // Fill rest of header
        const header_len = self.title.len + mode_text.len + (if (self.show_mouse_hints and self.mouse_enabled) 6 else 0) + 4;
        const total_width = 70;
        const padding = if (total_width > header_len) total_width - header_len else 0;
        for (0..padding) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┐\n");
    }

    fn renderSearchBar(self: *EnhancedSelectMenu, writer: anytype) !void {
        try writer.writeAll("│ ");

        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 200, 200, 200);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 7);
        }

        try writer.writeAll("🔍 Search: ");

        // Enhanced search input with background
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setBackgroundRgb(writer, self.caps, 30, 30, 30);
            try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
        } else {
            try term_ansi.setBackground256(writer, self.caps, 0);
            try term_ansi.setForeground256(writer, self.caps, 15);
        }

        try writer.writeAll(self.search_query.items);

        // Cursor with better visibility
        try writer.writeAll("▎");

        // Pad to width
        const used_width = 13 + self.search_query.items.len;
        const padding = if (68 > used_width) 68 - used_width else 0;
        for (0..padding) |_| {
            try writer.writeAll(" ");
        }

        try term_ansi.resetStyle(writer, self.caps);
        try writer.writeAll(" │\n");

        // Separator
        try self.renderSeparator(writer);
    }

    fn renderMenuItems(self: *EnhancedSelectMenu, writer: anytype) !void {
        const visible_start = self.scroll_offset;
        const visible_end = @min(visible_start + self.max_visible_items, self.filtered_items.items.len);

        for (self.filtered_items.items[visible_start..visible_end], 0..) |item_index, visible_idx| {
            const actual_index = visible_start + visible_idx;
            const is_current = actual_index == self.current_index;
            const row = self.menu_start_row + (if (self.show_search) 3 else 1) + @as(u32, @intCast(visible_idx));

            try self.renderMenuItem(writer, self.items.items[item_index], is_current, row);
        }
    }

    fn renderMenuItem(self: *EnhancedSelectMenu, writer: anytype, item: SelectMenuItem, is_current: bool, row: u32) !void {
        _ = row; // For future mouse coordinate calculations

        try writer.writeAll("│");

        // Enhanced selection indicator background
        if (is_current) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setBackgroundRgb(writer, self.caps, 30, 30, 80);
                try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
            } else {
                try term_ansi.setBackground256(writer, self.caps, 18);
                try term_ansi.setForeground256(writer, self.caps, 15);
            }
        }

        // Enhanced selection state indicator
        const selection_indicator = switch (self.selection_mode) {
            .single => if (is_current) "🢒 " else "  ",
            .multiple => if (item.selected) "☑ " else "☐ ",
            .radio => if (item.selected) "◉ " else "○ ",
        };
        try writer.writeAll(selection_indicator);

        // Enhanced icon support
        if (self.show_icons and item.icon != null) {
            try writer.print("{s} ", .{item.icon.?});
        } else {
            try writer.writeAll("  ");
        }

        // Main text with hyperlink support
        if (item.disabled) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 100, 100, 100);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 8);
            }
        }

        if (self.use_hyperlinks and item.hyperlink != null) {
            try hyperlinks.writeHyperlink(writer, self.caps, item.hyperlink.?, item.display_text);
        } else {
            try writer.writeAll(item.display_text);
        }

        // Enhanced description
        if (self.show_descriptions and item.description != null) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setForegroundRgb(writer, self.caps, 150, 150, 150);
            } else {
                try term_ansi.setForeground256(writer, self.caps, 8);
            }
            try writer.print(" - {s}", .{item.description.?});
        }

        try term_ansi.resetStyle(writer, self.caps);

        // Pad to edge with better calculation
        try writer.writeAll("                           │\n");
    }

    fn renderScrollIndicators(self: *EnhancedSelectMenu, writer: anytype) !void {
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }

        try writer.writeAll("│ ");

        if (self.scroll_offset > 0) {
            try writer.writeAll("⬆ More items above");
        } else {
            try writer.writeAll("                  ");
        }

        try writer.writeAll("                                        │\n");

        if (self.scroll_offset + self.max_visible_items < self.filtered_items.items.len) {
            try writer.writeAll("│ ⬇ More items below                                        │\n");
        }
    }

    fn renderEnhancedFooter(self: *EnhancedSelectMenu) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try self.renderSeparator(stdout);

        // Enhanced instructions
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(stdout, self.caps, 150, 150, 150);
        } else {
            try term_ansi.setForeground256(stdout, self.caps, 8);
        }

        const keyboard_instructions = switch (self.selection_mode) {
            .single => "↑/↓ navigate, Enter select, Esc cancel",
            .multiple => "↑/↓ navigate, Space toggle, Enter confirm, Esc cancel",
            .radio => "↑/↓ navigate, Space select, Enter confirm, Esc cancel",
        };

        try stdout.writeAll(keyboard_instructions);

        if (self.show_search) {
            try stdout.writeAll(", / search");
        }

        if (self.show_mouse_hints and self.mouse_enabled) {
            try stdout.writeAll("\n🖱️  Click to select, Scroll to navigate");
        }

        try stdout.writeAll("\n");
        try term_ansi.resetStyle(stdout, self.caps);
    }

    fn renderSeparator(self: *EnhancedSelectMenu, writer: anytype) !void {
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }
        try writer.writeAll("├");
        for (0..68) |_| {
            try writer.writeAll("─");
        }
        try writer.writeAll("┤\n");
    }

    /// Handle input events with enhanced keyboard and mouse support
    fn handleInput(self: *EnhancedSelectMenu, event: InputEvent) !MenuAction {
        switch (event) {
            .key => |key_event| {
                return self.handleKeyInput(key_event);
            },
            .mouse => |mouse_event| {
                return self.handleMouseInput(mouse_event);
            },
            .paste => |paste_event| {
                return self.handlePasteInput(paste_event);
            },
            .focus => |_| {
                // Refresh display on focus change
                return .keep_running;
            },
        }
    }

    fn handleKeyInput(self: *EnhancedSelectMenu, key_event: InputEvent.KeyEvent) !MenuAction {
        switch (key_event.key) {
            .up => {
                if (self.current_index > 0) {
                    self.current_index -= 1;
                    self.updateScrollPosition();
                }
                return .keep_running;
            },

            .down => {
                if (self.current_index + 1 < self.filtered_items.items.len) {
                    self.current_index += 1;
                    self.updateScrollPosition();
                }
                return .keep_running;
            },

            .page_up => {
                const jump = @min(self.max_visible_items, self.current_index);
                self.current_index -= jump;
                self.updateScrollPosition();
                return .keep_running;
            },

            .page_down => {
                const jump = @min(self.max_visible_items, self.filtered_items.items.len - self.current_index - 1);
                self.current_index += jump;
                self.updateScrollPosition();
                return .keep_running;
            },

            .home => {
                self.current_index = 0;
                self.updateScrollPosition();
                return .keep_running;
            },

            .end => {
                if (self.filtered_items.items.len > 0) {
                    self.current_index = self.filtered_items.items.len - 1;
                    self.updateScrollPosition();
                }
                return .keep_running;
            },

            .space => {
                return self.toggleCurrentItem();
            },

            .enter => {
                return .select;
            },

            .escape => {
                return .cancel;
            },

            // Search functionality
            .ctrl_f => {
                if (self.show_search) {
                    // Enter search mode (simplified)
                }
                return .keep_running;
            },

            .backspace => {
                if (self.show_search and self.search_query.items.len > 0) {
                    _ = self.search_query.pop();
                    try self.updateFilter();
                }
                return .keep_running;
            },

            else => {
                // Handle printable characters for search
                if (self.show_search and key_event.text != null) {
                    try self.search_query.appendSlice(key_event.text.?);
                    try self.updateFilter();
                }
                return .keep_running;
            },
        }
    }

    fn handleMouseInput(self: *EnhancedSelectMenu, mouse_event: MouseEvent) !MenuAction {
        switch (mouse_event.event_type) {
            .press => {
                if (mouse_event.button == .left) {
                    // Calculate which menu item was clicked
                    if (self.getItemFromMousePos(mouse_event.row, mouse_event.col)) |item_idx| {
                        self.current_index = item_idx;
                        return self.toggleCurrentItem();
                    }
                }
                return .keep_running;
            },

            .scroll_up => {
                if (self.current_index > 0) {
                    self.current_index -= 1;
                    self.updateScrollPosition();
                }
                return .keep_running;
            },

            .scroll_down => {
                if (self.current_index + 1 < self.filtered_items.items.len) {
                    self.current_index += 1;
                    self.updateScrollPosition();
                }
                return .keep_running;
            },

            else => return .keep_running,
        }
    }

    fn handlePasteInput(self: *EnhancedSelectMenu, paste_event: InputEvent.PasteEvent) !MenuAction {
        // Handle pasted search text
        if (self.show_search) {
            try self.search_query.appendSlice(paste_event.text);
            try self.updateFilter();
        }
        return .keep_running;
    }

    fn getItemFromMousePos(self: *EnhancedSelectMenu, row: u16, col: u16) ?usize {
        _ = col; // Column checking could be added for more precise hit detection

        // Calculate menu area
        const menu_start_row = self.menu_start_row + (if (self.show_search) 3 else 1);

        if (row < menu_start_row) return null;

        const clicked_item = row - menu_start_row;
        const visible_start = self.scroll_offset;
        const clicked_index = visible_start + clicked_item;

        if (clicked_index < self.filtered_items.items.len) {
            return clicked_index;
        }

        return null;
    }

    fn toggleCurrentItem(self: *EnhancedSelectMenu) !MenuAction {
        if (self.filtered_items.items.len == 0) return .keep_running;

        const item_index = self.filtered_items.items[self.current_index];
        const item = &self.items.items[item_index];

        if (item.disabled) return .keep_running;

        switch (self.selection_mode) {
            .single => return .select,
            .multiple => {
                item.selected = !item.selected;
                return .keep_running;
            },
            .radio => {
                // Clear all selections first
                for (self.items.items) |*it| {
                    it.selected = false;
                }
                item.selected = true;
                return .keep_running;
            },
        }
    }

    fn updateScrollPosition(self: *EnhancedSelectMenu) void {
        if (self.current_index < self.scroll_offset) {
            self.scroll_offset = self.current_index;
        } else if (self.current_index >= self.scroll_offset + self.max_visible_items) {
            self.scroll_offset = self.current_index - self.max_visible_items + 1;
        }
    }

    /// Get selected items (for multiple selection mode)
    pub fn getSelectedItems(self: EnhancedSelectMenu, allocator: Allocator) ![]SelectMenuItem {
        var selected = std.array_list.Managed(SelectMenuItem).init(allocator);
        errdefer selected.deinit();

        for (self.items.items) |item| {
            if (item.selected) {
                try selected.append(item);
            }
        }

        return try selected.toOwnedSlice();
    }

    /// Get currently highlighted item
    pub fn getCurrentItem(self: EnhancedSelectMenu) ?SelectMenuItem {
        if (self.current_index < self.filtered_items.items.len) {
            const item_index = self.filtered_items.items[self.current_index];
            return self.items.items[item_index];
        }
        return null;
    }
};

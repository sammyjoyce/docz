//! Select Menu with Terminal Capabilities
//! Supports mouse interaction, rich graphics, hyperlinks, and modern terminal features
//! while maintaining backward compatibility with basic terminals.

const std = @import("std");
const input = term_shared.input;
const term_shared = @import("term_shared");
const term_ansi = term_shared.ansi.color;
const term_cursor = term_shared.cursor;
const term_screen = term_shared.ansi.screen;
const term_caps = term_shared.caps;
const graphics_manager = term_shared.graphics_manager;

const Input = input.Input;
const InputEvent = input.InputEvent;
const Key = input.Key;
const MouseEvent = input.MouseEvent;
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

/// Select Menu with mouse support and rich terminal features
pub const SelectMenu = struct {
    allocator: Allocator,
    inputManager: *Input,
    caps: term_caps.TermCaps,
    graphics: ?*GraphicsManager,

    // Menu data
    items: std.array_list.Managed(SelectMenuItem),
    filteredItems: std.array_list.Managed(usize), // Indices into items array
    title: []const u8,
    selectionMode: SelectionMode,
    currentIndex: usize,
    searchQuery: std.array_list.Managed(u8),

    // Display configuration
    showSearch: bool,
    showDescriptions: bool,
    showIcons: bool,
    showMouseHints: bool,
    maxVisibleItems: usize,
    scrollOffset: usize,

    // Mouse interaction
    menuStartRow: u32,
    menuStartCol: u32,
    mouseEnabled: bool,

    // Rich features
    useGraphics: bool,
    useHyperlinks: bool,

    pub fn init(
        allocator: Allocator,
        inputMgr: *Input,
        title: []const u8,
        selectionMode: SelectionMode,
    ) !SelectMenu {
        const caps = term_caps.getTermCaps();

        return SelectMenu{
            .allocator = allocator,
            .inputManager = inputMgr,
            .caps = caps,
            .graphics = null,
            .items = std.array_list.Managed(SelectMenuItem).init(allocator),
            .filteredItems = std.array_list.Managed(usize).init(allocator),
            .title = title,
            .selectionMode = selectionMode,
            .currentIndex = 0,
            .searchQuery = std.array_list.Managed(u8).init(allocator),
            .showSearch = false,
            .showDescriptions = true,
            .showIcons = true,
            .showMouseHints = caps.supportsEnhancedMouse,
            .maxVisibleItems = 10,
            .scrollOffset = 0,
            .menuStartRow = 0,
            .menuStartCol = 0,
            .mouseEnabled = caps.supportsEnhancedMouse,
            .useGraphics = caps.supportsKittyGraphics or caps.supportsSixel,
            .useHyperlinks = caps.supportsHyperlinkOsc8,
        };
    }

    pub fn deinit(self: *SelectMenu) void {
        self.items.deinit();
        self.filteredItems.deinit();
        self.searchQuery.deinit();
    }

    pub fn setGraphicsManager(self: *SelectMenu, gm: *GraphicsManager) void {
        self.graphics = gm;
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
            showSearch: bool = false,
            showDescriptions: bool = true,
            showIcons: bool = true,
            showMouseHints: ?bool = null,
            maxVisibleItems: usize = 10,
        },
    ) void {
        self.showSearch = options.showSearch;
        self.showDescriptions = options.showDescriptions;
        self.showIcons = options.showIcons;
        self.showMouseHints = options.showMouseHints orelse self.caps.supportsEnhancedMouse;
        self.maxVisibleItems = options.maxVisibleItems;
    }

    /// Run the interactive menu and return the user's selection
    pub fn run(self: *SelectMenu) !MenuAction {
        // Enable terminal features
        try self.inputManager.enableFeatures(.{
            .raw_mode = true,
            .mouse_events = self.mouseEnabled,
            .bracketed_paste = true,
            .focus_events = false,
        });

        // Main input loop
        while (true) {
            // Render the menu
            try self.render();

            // Wait for input
            const event = try self.inputManager.nextEvent();
            const action = try self.handleInput(event);

            switch (action) {
                .select => return .select,
                .cancel => return .cancel,
                .keep_running => {}, // Keep processing
            }
        }
    }

    /// Update the filtered items based on search query
    fn updateFilter(self: *SelectMenu) !void {
        self.filteredItems.clearRetainingCapacity();

        for (self.items.items, 0..) |item, i| {
            if (self.searchQuery.items.len == 0) {
                try self.filteredItems.append(i);
            } else {
                // Simple case-insensitive search
                const query_lower = try std.ascii.allocLowerString(self.allocator, self.searchQuery.items);
                defer self.allocator.free(query_lower);

                const text_lower = try std.ascii.allocLowerString(self.allocator, item.display_text);
                defer self.allocator.free(text_lower);

                if (std.mem.indexOf(u8, text_lower, query_lower) != null) {
                    try self.filteredItems.append(i);
                }
            }
        }

        // Reset selection if current index is out of bounds
        if (self.currentIndex >= self.filteredItems.items.len) {
            self.currentIndex = if (self.filteredItems.items.len > 0) 0 else 0;
        }
    }

    /// Render the select menu
    fn render(self: *SelectMenu) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        // Clear screen and get cursor position
        try term_screen.clearScreen(stdout, self.caps);
        try term_cursor.moveTo(stdout, self.caps, 1, 1);

        // Store menu position for mouse calculations
        self.menuStartRow = 1;
        self.menuStartCol = 1;

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

        // Footer with instructions
        try self.renderFooter(stdout);

        // Flush output
        try stdout.context.flush();
    }

    fn renderTitle(self: *SelectMenu, writer: anytype) !void {
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

    fn renderSearchBar(self: *SelectMenu, writer: anytype) !void {
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

    fn renderMenuItems(self: *SelectMenu, writer: anytype) !void {
        const visibleStart = self.scrollOffset;
        const visibleEnd = @min(visibleStart + self.maxVisibleItems, self.filteredItems.items.len);

        for (self.filteredItems.items[visibleStart..visibleEnd], 0..) |itemIndex, visibleIdx| {
            const actualIndex = visibleStart + visibleIdx;
            const isCurrent = actualIndex == self.currentIndex;
            const row = self.menuStartRow + (if (self.showSearch) 3 else 1) + @as(u32, @intCast(visibleIdx));

            try self.renderMenuItem(writer, self.items.items[itemIndex], isCurrent, row);
        }
    }

    fn renderMenuItem(self: *SelectMenu, writer: anytype, item: SelectMenuItem, isCurrent: bool, row: u32) !void {
        _ = row; // For future mouse coordinate calculations

        try writer.writeAll("│");

        // Enhanced selection indicator background
        if (isCurrent) {
            if (self.caps.supportsTrueColor()) {
                try term_ansi.setBackgroundRgb(writer, self.caps, 30, 30, 80);
                try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
            } else {
                try term_ansi.setBackground256(writer, self.caps, 18);
                try term_ansi.setForeground256(writer, self.caps, 15);
            }
        }

        // Enhanced selection state indicator
        const selectionIndicator = switch (self.selectionMode) {
            .single => if (isCurrent) "🢒 " else "  ",
            .multiple => if (item.selected) "☑ " else "☐ ",
            .radio => if (item.selected) "◉ " else "○ ",
        };
        try writer.writeAll(selectionIndicator);

        // Enhanced icon support
        if (self.showIcons and item.icon != null) {
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

        if (self.useHyperlinks and item.hyperlink != null) {
            try term_shared.ansi.hyperlink.writeHyperlink(writer, self.allocator, self.caps, item.hyperlink.?, item.display_text);
        } else {
            try writer.writeAll(item.display_text);
        }

        // Enhanced description
        if (self.showDescriptions and item.description != null) {
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

    fn renderScrollIndicators(self: *SelectMenu, writer: anytype) !void {
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 100, 149, 237);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 12);
        }

        try writer.writeAll("│ ");

        if (self.scrollOffset > 0) {
            try writer.writeAll("⬆ More items above");
        } else {
            try writer.writeAll("                  ");
        }

        try writer.writeAll("                                        │\n");

        if (self.scrollOffset + self.maxVisibleItems < self.filteredItems.items.len) {
            try writer.writeAll("│ ⬇ More items below                                        │\n");
        }
    }

    fn renderFooter(self: *SelectMenu) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try self.renderSeparator(stdout);

        // Instructions
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(stdout, self.caps, 150, 150, 150);
        } else {
            try term_ansi.setForeground256(stdout, self.caps, 8);
        }

        const keyboardInstructions = switch (self.selectionMode) {
            .single => "↑/↓ navigate, Enter select, Esc cancel",
            .multiple => "↑/↓ navigate, Space toggle, Enter confirm, Esc cancel",
            .radio => "↑/↓ navigate, Space select, Enter confirm, Esc cancel",
        };

        try stdout.writeAll(keyboardInstructions);

        if (self.showSearch) {
            try stdout.writeAll(", / search");
        }

        if (self.showMouseHints and self.mouseEnabled) {
            try stdout.writeAll("\n🖱️  Click to select, Scroll to navigate");
        }

        try stdout.writeAll("\n");
        try term_ansi.resetStyle(stdout, self.caps);
    }

    fn renderSeparator(self: *SelectMenu, writer: anytype) !void {
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

    /// Handle input events with keyboard and mouse support
    fn handleInput(self: *SelectMenu, event: InputEvent) !MenuAction {
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

    fn handleKeyInput(self: *SelectMenu, key_event: InputEvent.KeyEvent) !MenuAction {
        switch (key_event.key) {
            .up => {
                if (self.currentIndex > 0) {
                    self.currentIndex -= 1;
                    self.updateScrollPosition();
                }
                return .keep_running;
            },

            .down => {
                if (self.currentIndex + 1 < self.filteredItems.items.len) {
                    self.currentIndex += 1;
                    self.updateScrollPosition();
                }
                return .keep_running;
            },

            .page_up => {
                const jump = @min(self.maxVisibleItems, self.currentIndex);
                self.currentIndex -= jump;
                self.updateScrollPosition();
                return .keep_running;
            },

            .page_down => {
                const jump = @min(self.maxVisibleItems, self.filteredItems.items.len - self.currentIndex - 1);
                self.currentIndex += jump;
                self.updateScrollPosition();
                return .keep_running;
            },

            .home => {
                self.currentIndex = 0;
                self.updateScrollPosition();
                return .keep_running;
            },

            .end => {
                if (self.filteredItems.items.len > 0) {
                    self.currentIndex = self.filteredItems.items.len - 1;
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
                if (self.showSearch) {
                    // Enter search mode (simplified)
                }
                return .keep_running;
            },

            .backspace => {
                if (self.showSearch and self.searchQuery.items.len > 0) {
                    _ = self.searchQuery.pop();
                    try self.updateFilter();
                }
                return .keep_running;
            },

            else => {
                // Handle printable characters for search
                if (self.showSearch and key_event.text != null) {
                    try self.searchQuery.appendSlice(key_event.text.?);
                    try self.updateFilter();
                }
                return .keep_running;
            },
        }
    }

    fn handleMouseInput(self: *SelectMenu, mouse_event: MouseEvent) !MenuAction {
        switch (mouse_event.event_type) {
            .press => {
                if (mouse_event.button == .left) {
                    // Calculate which menu item was clicked
                    if (self.getItemFromMousePos(mouse_event.row, mouse_event.col)) |itemIdx| {
                        self.currentIndex = itemIdx;
                        return self.toggleCurrentItem();
                    }
                }
                return .keep_running;
            },

            .scroll_up => {
                if (self.currentIndex > 0) {
                    self.currentIndex -= 1;
                    self.updateScrollPosition();
                }
                return .keep_running;
            },

            .scroll_down => {
                if (self.currentIndex + 1 < self.filteredItems.items.len) {
                    self.currentIndex += 1;
                    self.updateScrollPosition();
                }
                return .keep_running;
            },

            else => return .keep_running,
        }
    }

    fn handlePasteInput(self: *SelectMenu, paste_event: InputEvent.PasteEvent) !MenuAction {
        // Handle pasted search text
        if (self.showSearch) {
            try self.searchQuery.appendSlice(paste_event.text);
            try self.updateFilter();
        }
        return .keep_running;
    }

    fn getItemFromMousePos(self: *SelectMenu, row: u16, col: u16) ?usize {
        _ = col; // Column checking could be added for more precise hit detection

        // Calculate menu area
        const menuStartRow = self.menuStartRow + (if (self.showSearch) 3 else 1);

        if (row < menuStartRow) return null;

        const clickedItem = row - menuStartRow;
        const visibleStart = self.scrollOffset;
        const clickedIndex = visibleStart + clickedItem;

        if (clickedIndex < self.filteredItems.items.len) {
            return clickedIndex;
        }

        return null;
    }

    fn toggleCurrentItem(self: *SelectMenu) !MenuAction {
        if (self.filteredItems.items.len == 0) return .keep_running;

        const itemIndex = self.filteredItems.items[self.currentIndex];
        const item = &self.items.items[itemIndex];

        if (item.disabled) return .keep_running;

        switch (self.selectionMode) {
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

    fn updateScrollPosition(self: *SelectMenu) void {
        if (self.currentIndex < self.scrollOffset) {
            self.scrollOffset = self.currentIndex;
        } else if (self.currentIndex >= self.scrollOffset + self.maxVisibleItems) {
            self.scrollOffset = self.currentIndex - self.maxVisibleItems + 1;
        }
    }

    /// Get selected items (for multiple selection mode)
    pub fn getSelectedItems(self: SelectMenu, allocator: Allocator) ![]SelectMenuItem {
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
    pub fn getCurrentItem(self: SelectMenu) ?SelectMenuItem {
        if (self.currentIndex < self.filteredItems.items.len) {
            const itemIndex = self.filteredItems.items[self.currentIndex];
            return self.items.items[itemIndex];
        }
        return null;
    }
};

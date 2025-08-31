//! Menu widget for interactive navigation
//! Extracted from monolithic tui.zig with terminal capability support

const std = @import("std");
const term_shared = @import("term_shared");
const term_ansi = term_shared.ansi.color;
const term_hyperlink = term_shared.ansi.hyperlink;
const term_caps = term_shared.caps;
const print = std.debug.print;

/// Menu item with enhanced properties
pub const MenuItem = struct {
    key: []const u8,
    label: []const u8,
    description: ?[]const u8,
    shortcut: ?[]const u8,
    action: ?[]const u8,
    icon: ?[]const u8,
    help_url: ?[]const u8,
    enabled: bool,
    visible: bool,
    submenu: ?*Menu,

    pub fn init(key: []const u8, label: []const u8) MenuItem {
        return MenuItem{
            .key = key,
            .label = label,
            .description = null,
            .shortcut = null,
            .action = null,
            .icon = null,
            .help_url = null,
            .enabled = true,
            .visible = true,
            .submenu = null,
        };
    }

    // Convenient builder pattern methods
    pub fn withDescription(self: MenuItem, desc: []const u8) MenuItem {
        return MenuItem{
            .key = self.key,
            .label = self.label,
            .description = desc,
            .shortcut = self.shortcut,
            .action = self.action,
            .icon = self.icon,
            .help_url = self.help_url,
            .enabled = self.enabled,
            .visible = self.visible,
            .submenu = self.submenu,
        };
    }

    pub fn withShortcut(self: MenuItem, shortcut: []const u8) MenuItem {
        return MenuItem{
            .key = self.key,
            .label = self.label,
            .description = self.description,
            .shortcut = shortcut,
            .action = self.action,
            .icon = self.icon,
            .help_url = self.help_url,
            .enabled = self.enabled,
            .visible = self.visible,
            .submenu = self.submenu,
        };
    }

    pub fn withAction(self: MenuItem, action: []const u8) MenuItem {
        return MenuItem{
            .key = self.key,
            .label = self.label,
            .description = self.description,
            .shortcut = self.shortcut,
            .action = action,
            .icon = self.icon,
            .help_url = self.help_url,
            .enabled = self.enabled,
            .visible = self.visible,
            .submenu = self.submenu,
        };
    }

    pub fn withIcon(self: MenuItem, icon: []const u8) MenuItem {
        return MenuItem{
            .key = self.key,
            .label = self.label,
            .description = self.description,
            .shortcut = self.shortcut,
            .action = self.action,
            .icon = icon,
            .help_url = self.help_url,
            .enabled = self.enabled,
            .visible = self.visible,
            .submenu = self.submenu,
        };
    }

    pub fn withHelpUrl(self: MenuItem, url: []const u8) MenuItem {
        return MenuItem{
            .key = self.key,
            .label = self.label,
            .description = self.description,
            .shortcut = self.shortcut,
            .action = self.action,
            .icon = self.icon,
            .help_url = url,
            .enabled = self.enabled,
            .visible = self.visible,
            .submenu = self.submenu,
        };
    }

    pub fn disabled(self: MenuItem) MenuItem {
        return MenuItem{
            .key = self.key,
            .label = self.label,
            .description = self.description,
            .shortcut = self.shortcut,
            .action = self.action,
            .icon = self.icon,
            .help_url = self.help_url,
            .enabled = false,
            .visible = self.visible,
            .submenu = self.submenu,
        };
    }

    pub fn hidden(self: MenuItem) MenuItem {
        return MenuItem{
            .key = self.key,
            .label = self.label,
            .description = self.description,
            .shortcut = self.shortcut,
            .action = self.action,
            .icon = self.icon,
            .help_url = self.help_url,
            .enabled = self.enabled,
            .visible = false,
            .submenu = self.submenu,
        };
    }
};

/// Enhanced menu with terminal capabilities and navigation
pub const Menu = struct {
    items: std.ArrayList(MenuItem),
    selectedIndex: usize,
    title: []const u8,
    show_shortcuts: bool,
    show_descriptions: bool,
    max_visible_items: usize,
    scrollOffset: usize,
    caps: term_caps.TermCaps,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, title: []const u8) Menu {
        return Menu{
            .items = std.ArrayList(MenuItem).init(allocator),
            .selectedIndex = 0,
            .title = title,
            .show_shortcuts = true,
            .show_descriptions = true,
            .max_visible_items = 10,
            .scrollOffset = 0,
            .caps = term_caps.getTermCaps(),
            .allocator = allocator,
        };
    }

    /// Initialize from array of MenuItems (convenient constructor)
    pub fn initFromItems(allocator: std.mem.Allocator, title: []const u8, items: []const MenuItem) !Menu {
        var menu = Menu.init(allocator, title);
        for (items) |item| {
            try menu.addItem(item);
        }
        return menu;
    }

    pub fn deinit(self: *Menu) void {
        self.items.deinit();
    }

    pub fn addItem(self: *Menu, item: MenuItem) !void {
        try self.items.append(item);
    }

    pub fn removeItem(self: *Menu, index: usize) void {
        if (index < self.items.items.len) {
            _ = self.items.orderedRemove(index);
            if (self.selectedIndex >= self.items.items.len and self.items.items.len > 0) {
                self.selectedIndex = self.items.items.len - 1;
            }
        }
    }

    pub fn selectNext(self: *Menu) void {
        if (self.items.items.len == 0) return;

        var next = (self.selectedIndex + 1) % self.items.items.len;
        // Skip disabled/hidden items
        var attempts: usize = 0;
        while ((!self.items.items[next].enabled or !self.items.items[next].visible) and attempts < self.items.items.len) {
            next = (next + 1) % self.items.items.len;
            attempts += 1;
        }
        if (attempts < self.items.items.len) {
            self.selectedIndex = next;
            self.adjustScrollOffset();
        }
    }

    pub fn selectPrev(self: *Menu) void {
        if (self.items.items.len == 0) return;

        var prev = if (self.selectedIndex == 0) self.items.items.len - 1 else self.selectedIndex - 1;
        // Skip disabled/hidden items
        var attempts: usize = 0;
        while ((!self.items.items[prev].enabled or !self.items.items[prev].visible) and attempts < self.items.items.len) {
            prev = if (prev == 0) self.items.items.len - 1 else prev - 1;
            attempts += 1;
        }
        if (attempts < self.items.items.len) {
            self.selectedIndex = prev;
            self.adjustScrollOffset();
        }
    }

    pub fn selectByKey(self: *Menu, key: []const u8) bool {
        for (self.items.items, 0..) |item, i| {
            if (std.mem.eql(u8, item.key, key) and item.enabled and item.visible) {
                self.selectedIndex = i;
                self.adjustScrollOffset();
                return true;
            }
        }
        return false;
    }

    pub fn getSelectedItem(self: Menu) ?MenuItem {
        if (self.selectedIndex < self.items.items.len) {
            return self.items.items[self.selectedIndex];
        }
        return null;
    }

    pub fn getSelectedKey(self: Menu) ?[]const u8 {
        if (self.getSelectedItem()) |item| {
            return item.key;
        }
        return null;
    }

    fn adjustScrollOffset(self: *Menu) void {
        if (self.selectedIndex < self.scrollOffset) {
            self.scrollOffset = self.selectedIndex;
        } else if (self.selectedIndex >= self.scrollOffset + self.max_visible_items) {
            self.scrollOffset = self.selectedIndex - self.max_visible_items + 1;
        }
    }

    /// Enhanced drawing with terminal capabilities
    pub fn draw(self: Menu) void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const writer = &stdout_writer.interface;
        self.drawWithWriter(writer);
    }

    pub fn drawWithWriter(self: Menu, writer: anytype) void {
        self.drawImpl(writer) catch |err| {
            std.log.err("Failed to draw menu: {}", .{err});
        };
    }

    /// Simple convenience init (backward compatibility)
    pub fn initSimple(items: []const MenuItem) Menu {
        // This is a simplified version for backward compatibility
        // In practice, you'd want to use the full init method
        const dummy_allocator = std.heap.page_allocator;
        var menu = Menu.init(dummy_allocator, "Select command:");

        // Note: This is not ideal as it may fail, but maintains compatibility
        for (items) |item| {
            menu.addItem(item) catch break;
        }

        return menu;
    }

    fn drawImpl(self: Menu, writer: anytype) !void {
        // Title with colors
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
            try term_ansi.bold(writer, self.caps);
        } else if (self.caps.supports256Color()) {
            try term_ansi.setForeground256(writer, self.caps, 15);
            try term_ansi.bold(writer, self.caps);
        }

        try writer.writeAll(self.title);
        try term_ansi.resetStyle(writer, self.caps);
        try writer.writeAll("\n\n");

        const end_index = @min(self.scrollOffset + self.max_visible_items, self.items.items.len);

        for (self.items.items[self.scrollOffset..end_index], 0..) |item, i| {
            if (!item.visible) continue;

            const actual_index = self.scrollOffset + i;
            const is_selected = actual_index == self.selectedIndex;

            // Selection marker and colors
            if (is_selected) {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setBackgroundRgb(writer, self.caps, 30, 30, 80);
                    try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
                } else {
                    try term_ansi.setBackground256(writer, self.caps, 18);
                    try term_ansi.setForeground256(writer, self.caps, 15);
                }
                try writer.writeAll("  ► ");
            } else {
                try writer.writeAll("    ");

                if (item.enabled) {
                    if (self.caps.supportsTrueColor()) {
                        try term_ansi.setForegroundRgb(writer, self.caps, 255, 255, 255);
                    } else {
                        try term_ansi.setForeground256(writer, self.caps, 15);
                    }
                } else {
                    if (self.caps.supportsTrueColor()) {
                        try term_ansi.setForegroundRgb(writer, self.caps, 128, 128, 128);
                    } else {
                        try term_ansi.setForeground256(writer, self.caps, 8);
                    }
                }
            }

            // Icon
            if (item.icon) |icon| {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 255, 215, 0); // Gold
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 11);
                }
                try writer.print("{s} ", .{icon});
            }

            // Label (with hyperlink if help URL is available)
            if (item.help_url) |url| {
                try term_hyperlink.writeHyperlink(writer, self.allocator, self.caps, url, item.label);
            } else {
                try writer.writeAll(item.label);
            }

            // Shortcut
            if (self.show_shortcuts and item.shortcut != null) {
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 169, 169, 169); // Dark gray
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 8);
                }
                try writer.print(" ({s})", .{item.shortcut.?});
            }

            try term_ansi.resetStyle(writer, self.caps);

            // Description on next line if enabled
            if (self.show_descriptions and item.description != null) {
                try writer.writeAll("\n");
                if (self.caps.supportsTrueColor()) {
                    try term_ansi.setForegroundRgb(writer, self.caps, 169, 169, 169);
                } else {
                    try term_ansi.setForeground256(writer, self.caps, 8);
                }
                try writer.print("      {s}", .{item.description.?});
                try term_ansi.resetStyle(writer, self.caps);
            }

            try writer.writeAll("\n");
        }

        // Scroll indicators
        if (self.caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, self.caps, 169, 169, 169);
        } else {
            try term_ansi.setForeground256(writer, self.caps, 8);
        }

        if (self.scrollOffset > 0) {
            try writer.writeAll("    ↑ More items above\n");
        }
        if (end_index < self.items.items.len) {
            try writer.writeAll("    ↓ More items below\n");
        }

        try term_ansi.resetStyle(writer, self.caps);
    }

    /// Draw with ID for screen management (compatibility with TUI system)
    pub fn drawWithId(self: Menu, title: []const u8, id: []const u8) void {
        _ = title;
        _ = id;
        self.draw();
    }

    /// Handle mouse interaction
    pub fn handleClick(self: *Menu, x: u32, y: u32) bool {
        _ = x; // For now, assume any x coordinate is valid

        // Calculate which item was clicked
        if (y < 2) return false; // Skip title and spacing

        const clicked_index = self.scrollOffset + (y - 2);
        if (clicked_index < self.items.items.len) {
            const item = self.items.items[clicked_index];
            if (item.enabled and item.visible) {
                self.selectedIndex = clicked_index;
                return true;
            }
        }

        return false;
    }
};

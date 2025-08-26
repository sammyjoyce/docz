//! Tab container widget with keyboard navigation
const std = @import("std");
const print = std.debug.print;
const Bounds = @import("../core/bounds.zig").Bounds;
const Color = @import("../themes/default.zig").Color;
const Box = @import("../themes/default.zig").Box;
const KeyEvent = @import("../core/events.zig").KeyEvent;

/// Tab container widget for organizing multiple views
pub const TabContainer = struct {
    pub const Tab = struct {
        title: []const u8,
        icon: ?[]const u8,
        content: ?*anyopaque, // Generic widget pointer
        closeable: bool,
        dirty: bool, // Indicates content needs update

        pub fn init(title: []const u8) Tab {
            return Tab{
                .title = title,
                .icon = null,
                .content = null,
                .closeable = true,
                .dirty = false,
            };
        }

        pub fn withIcon(self: Tab, icon: []const u8) Tab {
            return Tab{
                .title = self.title,
                .icon = icon,
                .content = self.content,
                .closeable = self.closeable,
                .dirty = self.dirty,
            };
        }

        pub fn withContent(self: Tab, content: *anyopaque) Tab {
            return Tab{
                .title = self.title,
                .icon = self.icon,
                .content = content,
                .closeable = self.closeable,
                .dirty = self.dirty,
            };
        }

        pub fn notCloseable(self: Tab) Tab {
            return Tab{
                .title = self.title,
                .icon = self.icon,
                .content = self.content,
                .closeable = false,
                .dirty = self.dirty,
            };
        }
    };

    tabs: std.ArrayList(Tab),
    active_index: usize,
    bounds: Bounds,
    tab_height: u32,
    show_close_buttons: bool,
    show_icons: bool,
    max_tab_width: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, bounds: Bounds) TabContainer {
        return TabContainer{
            .tabs = std.ArrayList(Tab).init(allocator),
            .active_index = 0,
            .bounds = bounds,
            .tab_height = 1,
            .show_close_buttons = true,
            .show_icons = true,
            .max_tab_width = 20,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TabContainer) void {
        // Free tab titles if they were allocated
        for (self.tabs.items) |tab| {
            // Note: In a real implementation, we'd track which strings were allocated
            _ = tab;
        }
        self.tabs.deinit();
    }

    pub fn addTab(self: *TabContainer, tab: Tab) !usize {
        try self.tabs.append(tab);
        const index = self.tabs.items.len - 1;

        // If this is the first tab, make it active
        if (self.tabs.items.len == 1) {
            self.active_index = 0;
        }

        return index;
    }

    pub fn removeTab(self: *TabContainer, index: usize) void {
        if (index >= self.tabs.items.len) return;

        const tab = self.tabs.items[index];
        if (!tab.closeable) return; // Cannot close non-closeable tabs

        _ = self.tabs.orderedRemove(index);

        // Adjust active index if necessary
        if (self.tabs.items.len == 0) {
            self.active_index = 0;
        } else if (self.active_index >= self.tabs.items.len) {
            self.active_index = self.tabs.items.len - 1;
        } else if (index < self.active_index) {
            self.active_index -= 1;
        }
    }

    pub fn setActiveTab(self: *TabContainer, index: usize) void {
        if (index < self.tabs.items.len) {
            self.active_index = index;
        }
    }

    pub fn getActiveTab(self: *TabContainer) ?*Tab {
        if (self.active_index < self.tabs.items.len) {
            return &self.tabs.items[self.active_index];
        }
        return null;
    }

    pub fn nextTab(self: *TabContainer) void {
        if (self.tabs.items.len <= 1) return;
        self.active_index = (self.active_index + 1) % self.tabs.items.len;
    }

    pub fn prevTab(self: *TabContainer) void {
        if (self.tabs.items.len <= 1) return;
        if (self.active_index == 0) {
            self.active_index = self.tabs.items.len - 1;
        } else {
            self.active_index -= 1;
        }
    }

    pub fn closeTab(self: *TabContainer) void {
        if (self.active_index < self.tabs.items.len) {
            self.removeTab(self.active_index);
        }
    }

    pub fn closeAllTabs(self: *TabContainer) void {
        // Close tabs from end to avoid index issues
        var i: usize = self.tabs.items.len;
        while (i > 0) {
            i -= 1;
            if (self.tabs.items[i].closeable) {
                self.removeTab(i);
            }
        }
    }

    /// Handle keyboard shortcuts for tab navigation
    pub fn handleKeyboard(self: *TabContainer, event: KeyEvent) bool {
        // Handle common tab shortcuts
        if (event.modifiers.ctrl) {
            switch (event.key) {
                .tab => {
                    if (event.modifiers.shift) {
                        self.prevTab();
                    } else {
                        self.nextTab();
                    }
                    return true;
                },
                .character => {
                    if (event.character) |char| {
                        switch (char) {
                            'w', 'W' => {
                                self.closeTab();
                                return true;
                            },
                            't', 'T' => {
                                // Signal that a new tab should be created
                                // This would be handled by the parent application
                                return true;
                            },
                            '1'...'9' => {
                                const tab_num = char - '0';
                                if (tab_num <= self.tabs.items.len) {
                                    self.setActiveTab(tab_num - 1);
                                    return true;
                                }
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            }
        }

        return false;
    }

    pub fn draw(self: *TabContainer) void {
        self.drawTabBar();
        self.drawContent();
    }

    fn drawTabBar(self: *TabContainer) void {
        // Move to tab bar position
        moveCursor(self.bounds.y, self.bounds.x);

        var current_x: u32 = self.bounds.x;

        for (self.tabs.items, 0..) |tab, i| {
            if (current_x >= self.bounds.x + self.bounds.width) break; // No more room

            const is_active = (i == self.active_index);
            const tab_width = self.calculateTabWidth(tab);

            // Draw tab
            self.drawTab(tab, current_x, is_active, tab_width);
            current_x += tab_width;
        }

        // Fill remaining space with horizontal line
        while (current_x < self.bounds.x + self.bounds.width) {
            print("{s}", .{Box.HORIZONTAL});
            current_x += 1;
        }
    }

    fn drawTab(self: *TabContainer, tab: Tab, x: u32, is_active: bool, width: u32) void {
        moveCursor(self.bounds.y, x);

        const style = if (is_active) Color.BRIGHT_CYAN else Color.WHITE;
        const bg = if (is_active) "" else Color.DIM;

        // Left border
        print("{s}{s}{s}", .{ style, bg, if (is_active) "┌" else "─" });

        // Tab content
        var content_width = width - 2; // Account for borders
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();

        // Add icon if present and enabled
        if (self.show_icons and tab.icon != null) {
            content.appendSlice(tab.icon.?) catch {};
            content.append(' ') catch {};
            if (content_width > 2) content_width -= 2;
        }

        // Add title (truncated if necessary)
        const title = tab.title;
        var close_button_width: u32 = 0;
        if (self.show_close_buttons and tab.closeable) {
            close_button_width = 2; // " ×"
        }

        const title_width = if (content_width > close_button_width)
            @min(title.len, content_width - close_button_width)
        else
            0;

        content.appendSlice(title[0..title_width]) catch {};

        // Add close button if enabled and closeable
        if (self.show_close_buttons and tab.closeable and content_width >= close_button_width) {
            content.appendSlice(" ×") catch {};
        }

        // Pad to width
        while (content.items.len < content_width) {
            content.append(' ') catch break;
        }

        print("{s}", .{content.items});

        // Right border
        print("{s}", .{if (is_active) "┐" else "─"});
        print("{s}", .{Color.RESET});
    }

    fn drawContent(self: *TabContainer) void {
        // Draw content area border
        const content_y = self.bounds.y + self.tab_height + 1;
        const content_height = if (self.bounds.height > self.tab_height + 1)
            self.bounds.height - self.tab_height - 1
        else
            0;

        if (content_height == 0) return;

        // Top border of content area
        moveCursor(content_y - 1, self.bounds.x);
        print("{s}", .{Color.WHITE});
        for (0..self.bounds.width) |i| {
            // Connect with active tab
            if (self.active_index < self.tabs.items.len) {
                const tab_start = self.getTabStartPosition(self.active_index);
                const tab_width = self.calculateTabWidth(self.tabs.items[self.active_index]);
                if (i >= tab_start and i < tab_start + tab_width) {
                    print(" ");
                } else {
                    print("{s}", .{Box.HORIZONTAL});
                }
            } else {
                print("{s}", .{Box.HORIZONTAL});
            }
        }
        print("{s}", .{Color.RESET});

        // Side borders for content area
        for (0..content_height) |row| {
            moveCursor(content_y + @as(u32, @intCast(row)), self.bounds.x);
            print("{s}{s}", .{ Color.WHITE, Box.VERTICAL });
            moveCursor(content_y + @as(u32, @intCast(row)), self.bounds.x + self.bounds.width - 1);
            print("{s}{s}", .{ Box.VERTICAL, Color.RESET });
        }

        // Bottom border
        moveCursor(content_y + content_height, self.bounds.x);
        print("{s}{s}", .{ Color.WHITE, Box.BOTTOM_LEFT });
        for (1..self.bounds.width - 1) |_| {
            print("{s}", .{Box.HORIZONTAL});
        }
        print("{s}{s}", .{ Box.BOTTOM_RIGHT, Color.RESET });

        // TODO: Draw actual tab content here
        // For now, just show active tab info
        if (self.getActiveTab()) |active_tab| {
            moveCursor(content_y + 1, self.bounds.x + 2);
            print("Content for: {s}", .{active_tab.title});
        }
    }

    fn calculateTabWidth(self: *TabContainer, tab: Tab) u32 {
        var width: u32 = 2; // Borders

        if (self.show_icons and tab.icon != null) {
            width += 2; // Icon + space
        }

        width += @as(u32, @intCast(tab.title.len));

        if (self.show_close_buttons and tab.closeable) {
            width += 2; // Close button
        }

        return @min(width, self.max_tab_width);
    }

    fn getTabStartPosition(self: *TabContainer, index: usize) u32 {
        var x: u32 = 0;
        for (self.tabs.items[0..index]) |tab| {
            x += self.calculateTabWidth(tab);
        }
        return x;
    }
};

/// Move cursor to specific position
fn moveCursor(row: u32, col: u32) void {
    print("\x1b[{d};{d}H", .{ row + 1, col + 1 });
}

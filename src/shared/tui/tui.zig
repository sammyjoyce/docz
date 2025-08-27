//! Terminal User Interface framework for DocZ - Modular version
//!
//! This is the main TUI module that re-exports all components from the modular structure.
//! The actual implementations are now organized in tui/core/, tui/widgets/, and tui/themes/.

// Re-export the modular TUI framework
const tui_mod = @import("tui/mod.zig");
const core = @import("tui/core/mod.zig");

// Re-export commonly used types
pub const MouseEvent = tui_mod.MouseEvent;
pub const MouseHandler = tui_mod.MouseHandler;
pub const KeyEvent = tui_mod.KeyEvent;
pub const KeyboardHandler = tui_mod.KeyboardHandler;
pub const ShortcutRegistry = tui_mod.ShortcutRegistry;

pub const Bounds = tui_mod.Bounds;
pub const Point = tui_mod.Point;
pub const TerminalSize = tui_mod.TerminalSize;

pub const Layout = tui_mod.Layout;
pub const Direction = tui_mod.Direction;
pub const Alignment = tui_mod.Alignment;
pub const Size = tui_mod.Size;

pub const Screen = tui_mod.Screen;

// Re-export easing functions for animations
pub const Easing = core.Easing;

pub const ProgressBar = tui_mod.ProgressBar;
pub const TextInput = tui_mod.TextInput;
pub const TabContainer = tui_mod.TabContainer;

pub const Color = tui_mod.Color;
pub const Box = tui_mod.Box;
pub const Status = tui_mod.Status;
pub const Progress = tui_mod.Progress;
pub const Theme = tui_mod.Theme;

pub const TermCaps = tui_mod.TermCaps;

// Import the legacy components that weren't yet extracted
const std = @import("std");
const print = std.debug.print;

// Import terminal capabilities
const caps_mod = @import("term/capabilities.zig");
const mode = @import("term/ansi/mode.zig");

// Legacy components that are still in this file (to be extracted later)
// These maintain backward compatibility while we transition to the modular structure

/// Section component for organized display
pub const Section = struct {
    title: []const u8,
    content: std.ArrayList([]const u8),
    isExpanded: bool,
    has_border: bool,
    indent_level: u32,
    icon: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, title: []const u8) Section {
        return Section{
            .title = title,
            .content = std.ArrayList([]const u8).init(allocator),
            .isExpanded = true,
            .has_border = true,
            .indent_level = 0,
            .icon = null,
        };
    }

    pub fn deinit(self: *Section) void {
        self.content.deinit();
    }

    pub fn setIcon(self: *Section, icon: []const u8) void {
        self.icon = icon;
    }

    pub fn setBorder(self: *Section, has_border: bool) void {
        self.has_border = has_border;
    }

    pub fn setIndent(self: *Section, level: u32) void {
        self.indent_level = level;
    }

    pub fn addLine(self: *Section, line: []const u8) !void {
        try self.content.append(line);
    }

    pub fn toggle(self: *Section) void {
        self.isExpanded = !self.isExpanded;
    }

    pub fn expand(self: *Section) void {
        self.isExpanded = true;
    }

    pub fn collapse(self: *Section) void {
        self.isExpanded = false;
    }

    pub fn draw(self: Section) void {
        const indent = "  " ** self.indent_level;
        const expand_icon = if (self.isExpanded) "▼" else "▶";
        const section_icon = self.icon orelse "";

        print("{s}{s}{s} {s}{s}{s}\n", .{ Color.BRIGHT_BLUE, expand_icon, section_icon, self.title, Color.RESET, indent });

        if (self.isExpanded) {
            for (self.content.items) |line| {
                print("{s}  {s}\n", .{ indent, line });
            }
            if (self.content.items.len > 0) {
                print("\n");
            }
        }
    }
};

/// Menu component for interactive navigation
pub const Menu = struct {
    pub const MenuItem = struct {
        label: []const u8,
        description: ?[]const u8,
        shortcut: ?[]const u8,
        action: ?[]const u8,
        icon: ?[]const u8,
        enabled: bool,
        visible: bool,
        submenu: ?*Menu,

        pub fn init(label: []const u8) MenuItem {
            return MenuItem{
                .label = label,
                .description = null,
                .shortcut = null,
                .action = null,
                .icon = null,
                .enabled = true,
                .visible = true,
                .submenu = null,
            };
        }

        pub fn withDescription(self: MenuItem, desc: []const u8) MenuItem {
            return MenuItem{
                .label = self.label,
                .description = desc,
                .shortcut = self.shortcut,
                .action = self.action,
                .icon = self.icon,
                .enabled = self.enabled,
                .visible = self.visible,
                .submenu = self.submenu,
            };
        }

        pub fn withShortcut(self: MenuItem, shortcut: []const u8) MenuItem {
            return MenuItem{
                .label = self.label,
                .description = self.description,
                .shortcut = shortcut,
                .action = self.action,
                .icon = self.icon,
                .enabled = self.enabled,
                .visible = self.visible,
                .submenu = self.submenu,
            };
        }

        pub fn withAction(self: MenuItem, action: []const u8) MenuItem {
            return MenuItem{
                .label = self.label,
                .description = self.description,
                .shortcut = self.shortcut,
                .action = action,
                .icon = self.icon,
                .enabled = self.enabled,
                .visible = self.visible,
                .submenu = self.submenu,
            };
        }

        pub fn withIcon(self: MenuItem, icon: []const u8) MenuItem {
            return MenuItem{
                .label = self.label,
                .description = self.description,
                .shortcut = self.shortcut,
                .action = self.action,
                .icon = icon,
                .enabled = self.enabled,
                .visible = self.visible,
                .submenu = self.submenu,
            };
        }

        pub fn disabled(self: MenuItem) MenuItem {
            return MenuItem{
                .label = self.label,
                .description = self.description,
                .shortcut = self.shortcut,
                .action = self.action,
                .icon = self.icon,
                .enabled = false,
                .visible = self.visible,
                .submenu = self.submenu,
            };
        }

        pub fn hidden(self: MenuItem) MenuItem {
            return MenuItem{
                .label = self.label,
                .description = self.description,
                .shortcut = self.shortcut,
                .action = self.action,
                .icon = self.icon,
                .enabled = self.enabled,
                .visible = false,
                .submenu = self.submenu,
            };
        }
    };

    items: std.ArrayList(MenuItem),
    selectedIndex: usize,
    title: []const u8,
    show_shortcuts: bool,
    show_descriptions: bool,
    max_visible_items: usize,
    scrollOffset: usize,

    pub fn init(allocator: std.mem.Allocator, title: []const u8) Menu {
        return Menu{
            .items = std.ArrayList(MenuItem).init(allocator),
            .selectedIndex = 0,
            .title = title,
            .show_shortcuts = true,
            .show_descriptions = true,
            .max_visible_items = 10,
            .scrollOffset = 0,
        };
    }

    pub fn deinit(self: *Menu) void {
        self.items.deinit();
    }

    pub fn addItem(self: *Menu, item: MenuItem) !void {
        try self.items.append(item);
    }

    pub fn selectNext(self: *Menu) void {
        if (self.items.items.len == 0) return;

        var next = (self.selectedIndex + 1) % self.items.items.len;
        // Skip disabled/hidden items
        while (!self.items.items[next].enabled or !self.items.items[next].visible) {
            next = (next + 1) % self.items.items.len;
            if (next == self.selectedIndex) break; // Prevent infinite loop
        }
        self.selectedIndex = next;
        self.adjustScrollOffset();
    }

    pub fn selectPrev(self: *Menu) void {
        if (self.items.items.len == 0) return;

        var prev = if (self.selectedIndex == 0) self.items.items.len - 1 else self.selectedIndex - 1;
        // Skip disabled/hidden items
        while (!self.items.items[prev].enabled or !self.items.items[prev].visible) {
            prev = if (prev == 0) self.items.items.len - 1 else prev - 1;
            if (prev == self.selectedIndex) break; // Prevent infinite loop
        }
        self.selectedIndex = prev;
        self.adjustScrollOffset();
    }

    pub fn getSelectedItem(self: Menu) ?MenuItem {
        if (self.selectedIndex < self.items.items.len) {
            return self.items.items[self.selectedIndex];
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

    pub fn draw(self: Menu) void {
        print("{s}{s}{s}\n", .{ Color.BOLD, self.title, Color.RESET });

        const end_index = @min(self.scrollOffset + self.max_visible_items, self.items.items.len);

        for (self.items.items[self.scrollOffset..end_index], 0..) |item, i| {
            if (!item.visible) continue;

            const actual_index = self.scrollOffset + i;
            const is_selected = actual_index == self.selectedIndex;
            const color = if (is_selected) Color.BRIGHT_CYAN else if (item.enabled) Color.WHITE else Color.DIM;
            const marker = if (is_selected) ">" else " ";

            print(" {s}{s}", .{ marker, color });

            if (item.icon) |icon| {
                print("{s} ", .{icon});
            }

            print("{s}", .{item.label});

            if (self.show_shortcuts and item.shortcut != null) {
                print(" {s}({s}){s}", .{ Color.DIM, item.shortcut.?, color });
            }

            print("{s}", .{Color.RESET});

            if (self.show_descriptions and item.description != null) {
                print("\n   {s}{s}{s}", .{ Color.DIM, item.description.?, Color.RESET });
            }

            print("\n");
        }

        // Show scroll indicators
        if (self.scrollOffset > 0) {
            print("{s}  ↑ More items above{s}\n", .{ Color.DIM, Color.RESET });
        }
        if (end_index < self.items.items.len) {
            print("{s}  ↓ More items below{s}\n", .{ Color.DIM, Color.RESET });
        }
    }
};

/// Status bar component
pub const StatusBar = struct {
    left_text: []const u8,
    center_text: []const u8,
    right_text: []const u8,
    width: u32,
    style: []const u8,

    pub fn init(width: u32) StatusBar {
        return StatusBar{
            .left_text = "",
            .center_text = "",
            .right_text = "",
            .width = width,
            .style = Color.BG_BLUE,
        };
    }

    pub fn setLeft(self: *StatusBar, text: []const u8) void {
        self.left_text = text;
    }

    pub fn setCenter(self: *StatusBar, text: []const u8) void {
        self.center_text = text;
    }

    pub fn setRight(self: *StatusBar, text: []const u8) void {
        self.right_text = text;
    }

    pub fn setStyle(self: *StatusBar, style: []const u8) void {
        self.style = style;
    }

    pub fn draw(self: StatusBar) void {
        print("{s}", .{self.style});

        // Calculate spacing
        const total_text_len = self.left_text.len + self.center_text.len + self.right_text.len;
        if (total_text_len >= self.width) {
            // Not enough space, just show left text
            print("{s}", .{self.left_text[0..@min(self.left_text.len, self.width)]});
        } else {
            print("{s}", .{self.left_text});

            const remaining = self.width - total_text_len;
            const left_padding = remaining / 2;
            const right_padding = remaining - left_padding;

            // Print left padding
            var i: u32 = 0;
            while (i < left_padding) : (i += 1) {
                print(" ");
            }

            print("{s}", .{self.center_text});

            // Print right padding
            i = 0;
            while (i < right_padding) : (i += 1) {
                print(" ");
            }

            print("{s}", .{self.right_text});
        }

        print("{s}", .{Color.RESET});
    }
};

/// Command history for tracking user input
pub const CommandHistory = struct {
    commands: std.ArrayList([]const u8),
    current_index: ?usize,
    max_history: usize,

    pub fn init(allocator: std.mem.Allocator, max_history: usize) CommandHistory {
        return CommandHistory{
            .commands = std.ArrayList([]const u8).init(allocator),
            .current_index = null,
            .max_history = max_history,
        };
    }

    pub fn deinit(self: *CommandHistory) void {
        for (self.commands.items) |cmd| {
            self.commands.allocator.free(cmd);
        }
        self.commands.deinit();
    }

    pub fn add(self: *CommandHistory, command: []const u8) !void {
        // Don't add empty commands or duplicates
        if (command.len == 0) return;
        if (self.commands.items.len > 0) {
            if (std.mem.eql(u8, self.commands.items[self.commands.items.len - 1], command)) {
                return;
            }
        }

        // Add the command
        const owned_command = try self.commands.allocator.dupe(u8, command);
        try self.commands.append(owned_command);

        // Remove oldest command if we exceed max history
        if (self.commands.items.len > self.max_history) {
            const oldest = self.commands.orderedRemove(0);
            self.commands.allocator.free(oldest);
        }

        self.current_index = null;
    }

    pub fn getPrevious(self: *CommandHistory) ?[]const u8 {
        if (self.commands.items.len == 0) return null;

        if (self.current_index) |index| {
            if (index > 0) {
                self.current_index = index - 1;
            }
        } else {
            self.current_index = self.commands.items.len - 1;
        }

        return self.commands.items[self.current_index.?];
    }

    pub fn getNext(self: *CommandHistory) ?[]const u8 {
        if (self.current_index) |index| {
            if (index < self.commands.items.len - 1) {
                self.current_index = index + 1;
                return self.commands.items[self.current_index.?];
            } else {
                self.current_index = null;
                return "";
            }
        }
        return null;
    }

    pub fn reset(self: *CommandHistory) void {
        self.current_index = null;
    }
};

// Utility functions

/// Draw a horizontal border with custom characters
pub fn drawHorizontalBorder(width: u32, left_char: []const u8, middle_char: []const u8, right_char: []const u8) void {
    print("{s}", .{left_char});
    var i: u32 = 1;
    while (i < width - 1) : (i += 1) {
        print("{s}", .{middle_char});
    }
    if (width > 1) {
        print("{s}", .{right_char});
    }
    print("\n");
}

// For backward compatibility, continue to export legacy functions
// These will delegate to the new modular components

/// Clear entire screen (legacy function)
pub fn clearScreen() void {
    tui_mod.clearScreen();
}

/// Move cursor (legacy function)
pub fn moveCursor(row: u32, col: u32) void {
    tui_mod.moveCursor(row, col);
}

/// Clear lines (legacy function)
pub fn clearLines(count: u32) void {
    tui_mod.clearLines(count);
}

/// Parse SGR mouse event (legacy function)
pub fn parseSgrMouseEvent(sequence: []const u8) ?MouseEvent {
    return tui_mod.parseSgrMouseEvent(sequence);
}

/// Get terminal size (legacy function)
pub fn getTerminalSize() TerminalSize {
    return tui_mod.getTerminalSize();
}

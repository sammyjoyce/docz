//! Comprehensive Tabs Widget Demo
//! Shows all features of the tabs widget with rich content in each tab

const std = @import("std");
const tui_widgets = @import("../src/shared/tui/widgets/mod.zig");
const TabContainer = tui_widgets.core.TabContainer;
const Menu = tui_widgets.core.Menu;
const MenuItem = tui_widgets.core.MenuItem;
const TextInput = tui_widgets.core.TextInput;
const Section = tui_widgets.core.Section;
const Calendar = tui_widgets.core.Calendar;
const Date = tui_widgets.core.Date;
const term_ansi = @import("../src/shared/term/ansi/color.zig");
const term_caps = @import("../src/shared/term/capabilities.zig");
const KeyEvent = @import("../src/shared/tui/core/events.zig").KeyEvent;
const Bounds = @import("../src/shared/tui/core/bounds.zig").Bounds;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal capabilities
    var caps = try term_caps.TerminalCapabilities.init(allocator);
    defer caps.deinit();

    // Clear screen and setup
    const stdout_writer = std.io.getStdOut().writer();
    try stdout_writer.print("\x1b[2J\x1b[H", .{});

    // Create tabs container
    const screen_bounds = Bounds.init(0, 0, 80, 24);
    var tabs = TabContainer.init(allocator, screen_bounds);
    defer tabs.deinit();

    // Configure tabs appearance
    tabs.show_close_buttons = true;
    tabs.show_icons = true;
    tabs.max_tab_width = 15;

    // Create demo data structures
    var demo_data = DemoData.init(allocator);
    defer demo_data.deinit();

    // Add tabs with different content types
    _ = try tabs.addTab(TabContainer.Tab.init("Overview")
        .notCloseable());

    _ = try tabs.addTab(TabContainer.Tab.init("Editor")
        .withIcon("📝"));

    _ = try tabs.addTab(TabContainer.Tab.init("Data")
        .withIcon("📊"));

    _ = try tabs.addTab(TabContainer.Tab.init("Calendar")
        .withIcon("📅"));

    _ = try tabs.addTab(TabContainer.Tab.init("Settings")
        .withIcon("⚙️")
        .notCloseable());

    _ = try tabs.addTab(TabContainer.Tab.init("Logs")
        .withIcon("📋"));

    _ = try tabs.addTab(TabContainer.Tab.init("Help")
        .withIcon("❓")
        .notCloseable());

    // Initialize content for each tab
    try initializeTabContent(&demo_data, allocator, caps);

    // Print header
    try stdout_writer.print("Tabs Widget Comprehensive Demo\n", .{});
    try stdout_writer.print("================================\n\n", .{});
    try stdout_writer.print("This demo showcases all features of the tabs widget:\n", .{});
    try stdout_writer.print("• Multiple tabs with different content types\n", .{});
    try stdout_writer.print("• Tabs with icons and close buttons\n", .{});
    try stdout_writer.print("• Non-closeable system tabs\n", .{});
    try stdout_writer.print("• Keyboard navigation (Ctrl+Tab, Ctrl+Shift+Tab, Ctrl+W, Ctrl+1-9)\n", .{});
    try stdout_writer.print("• Dynamic tab creation and removal\n", .{});
    try stdout_writer.print("• Rich content in each tab\n\n", .{});

    try stdout_writer.print("Press 'q' to quit, 'n' for new tab, 'd' to delete current tab\n\n", .{});

    // Interactive demo loop
    var running = true;
    var tab_counter: u32 = 1;

    while (running) {
        // Clear content area and redraw
        try stdout_writer.print("\x1b[5;1H\x1b[J", .{}); // Clear from line 5 down

        // Draw tabs
        tabs.draw();

        // Draw content for active tab
        try drawActiveTabContent(&demo_data, tabs.getActiveTab().?, allocator, caps);

        // Draw status bar
        try drawStatusBar(&demo_data, tabs, allocator);

        // Handle input
        const input = try readKey();
        switch (input) {
            'q', 'Q' => running = false,
            'n', 'N' => {
                // Create new tab
                const tab_name = try std.fmt.allocPrint(allocator, "Tab {d}", .{tab_counter});
                defer allocator.free(tab_name);
                tab_counter += 1;

                const new_tab = TabContainer.Tab.init(tab_name)
                    .withIcon("🆕");
                _ = try tabs.addTab(new_tab);
            },
            'd', 'D' => {
                // Delete current tab (if closeable)
                if (tabs.getActiveTab()) |active_tab| {
                    if (active_tab.closeable) {
                        tabs.closeTab();
                    }
                }
            },
            'c', 'C' => {
                // Close all closeable tabs
                tabs.closeAllTabs();
            },
            '1'...'9' => {
                // Jump to tab by number
                const tab_num = input - '0';
                if (tab_num <= tabs.tabs.items.len) {
                    tabs.setActiveTab(tab_num - 1);
                }
            },
            '\t' => {
                // Handle Ctrl+Tab for navigation
                const key_event = KeyEvent{
                    .key = .tab,
                    .modifiers = .{ .ctrl = true },
                };
                _ = tabs.handleKeyboard(key_event);
            },
            else => {
                // Handle other keyboard shortcuts
                const key_event = KeyEvent{
                    .key = .character,
                    .character = input,
                    .modifiers = .{ .ctrl = false },
                };
                _ = tabs.handleKeyboard(key_event);
            },
        }
    }

    // Clear screen on exit
    try stdout_writer.print("\x1b[2J\x1b[H", .{});
    try stdout_writer.print("Tabs demo completed!\n", .{});
}

const DemoData = struct {
    allocator: std.mem.Allocator,
    editor_content: std.ArrayList(u8),
    log_entries: std.ArrayList([]const u8),
    settings: std.StringHashMap([]const u8),
    calendar: Calendar,

    pub fn init(allocator: std.mem.Allocator) DemoData {
        return DemoData{
            .allocator = allocator,
            .editor_content = std.ArrayList(u8).init(allocator),
            .log_entries = std.ArrayList([]const u8).init(allocator),
            .settings = std.StringHashMap([]const u8).init(allocator),
            .calendar = undefined, // Will be initialized later
        };
    }

    pub fn deinit(self: *DemoData) void {
        self.editor_content.deinit();
        for (self.log_entries.items) |entry| {
            self.allocator.free(entry);
        }
        self.log_entries.deinit();

        var settings_iter = self.settings.iterator();
        while (settings_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.settings.deinit();
    }
};

fn initializeTabContent(demo_data: *DemoData, allocator: std.mem.Allocator, caps: term_caps.TerminalCapabilities) !void {
    _ = caps; // Currently unused, but kept for future enhancement
    // Initialize editor content
    try demo_data.editor_content.appendSlice(
        \\# Welcome to the Tabs Demo Editor
        \\
        \\This is a mock text editor showing syntax highlighting capabilities.
        \\
        \\## Features Demonstrated:
        \\- Multi-line text editing
        \\- Syntax highlighting simulation
        \\- Cursor positioning
        \\- Text selection (simulated)
        \\
        \\## Code Example:
        \\```zig
        \\pub fn main() !void {
        \\    std.debug.print("Hello, World!\\n", .{});
        \\}
        \\```
        \\
        \\Try typing to see the editor in action!
    );

    // Initialize log entries
    const log_messages = [_][]const u8{
        "[INFO] Tabs demo started",
        "[INFO] Loading tab content...",
        "[DEBUG] Initializing editor tab",
        "[DEBUG] Setting up data table",
        "[INFO] Calendar widget ready",
        "[DEBUG] Loading settings",
        "[INFO] Log viewer initialized",
        "[INFO] Help system ready",
        "[INFO] All tabs loaded successfully",
        "[DEBUG] Starting interactive mode",
    };

    for (log_messages) |msg| {
        const entry = try allocator.dupe(u8, msg);
        try demo_data.log_entries.append(entry);
    }

    // Initialize settings
    const settings_data = [_]struct{ key: []const u8, value: []const u8 }{
        .{ .key = "theme", .value = "dark" },
        .{ .key = "font_size", .value = "12" },
        .{ .key = "show_icons", .value = "true" },
        .{ .key = "auto_save", .value = "enabled" },
        .{ .key = "max_tabs", .value = "10" },
        .{ .key = "animations", .value = "enabled" },
    };

    for (settings_data) |setting| {
        const key = try allocator.dupe(u8, setting.key);
        const value = try allocator.dupe(u8, setting.value);
        try demo_data.settings.put(key, value);
    }

    // Initialize calendar
    demo_data.calendar = try Calendar.init(allocator);
    demo_data.calendar.x = 2;
    demo_data.calendar.y = 8;
    demo_data.calendar.width = 35;
    demo_data.calendar.height = 12;
    demo_data.calendar.focused = true;
    demo_data.calendar.visible = true;
    demo_data.calendar.setCurrentView(2024, 8);

    // Add some demo events
    try demo_data.calendar.markDate(Date.init(2024, 8, 15));
    try demo_data.calendar.markDate(Date.init(2024, 8, 20));
    try demo_data.calendar.addEventMarker(
        try demo_data.calendar.createEventMarker(Date.init(2024, 8, 10), "!", term_ansi.Color.Red),
    );
}

fn drawActiveTabContent(demo_data: *DemoData, active_tab: *TabContainer.Tab, allocator: std.mem.Allocator, caps: term_caps.TerminalCapabilities) !void {
    _ = caps; // Currently unused, but kept for future enhancement
    const stdout_writer = std.io.getStdOut().writer();

    // Position cursor in content area (below tab bar)
    try stdout_writer.print("\x1b[6;2H", .{});

    if (std.mem.eql(u8, active_tab.title, "Overview")) {
        try drawOverviewTab(allocator);
    } else if (std.mem.eql(u8, active_tab.title, "Editor")) {
        try drawEditorTab(demo_data, allocator);
    } else if (std.mem.eql(u8, active_tab.title, "Data")) {
        try drawDataTab(allocator);
    } else if (std.mem.eql(u8, active_tab.title, "Calendar")) {
        try drawCalendarTab(&demo_data.calendar, allocator);
    } else if (std.mem.eql(u8, active_tab.title, "Settings")) {
        try drawSettingsTab(demo_data, allocator);
    } else if (std.mem.eql(u8, active_tab.title, "Logs")) {
        try drawLogsTab(demo_data, allocator);
    } else if (std.mem.eql(u8, active_tab.title, "Help")) {
        try drawHelpTab(allocator);
    } else {
        // Dynamic tab content
        try stdout_writer.print("Content for: {s}\n\n", .{active_tab.title});
        try stdout_writer.print("This is a dynamically created tab.\n", .{});
        try stdout_writer.print("You can add custom content here.\n\n", .{});
        try stdout_writer.print("Features:\n", .{});
        try stdout_writer.print("• Customizable title and icon\n", .{});
        try stdout_writer.print("• Closeable by default\n", .{});
        try stdout_writer.print("• Supports all tab widget features\n", .{});
    }
}

fn drawOverviewTab(allocator: std.mem.Allocator) !void {
    // allocator is used in section.content.append calls
    const stdout_writer = std.io.getStdOut().writer();

    var section = Section.init(allocator, "Tabs Widget Overview");
    defer section.deinit();

    try section.content.append(allocator, "");
    try section.content.append(allocator, "The tabs widget provides a comprehensive tabbed interface");
    try section.content.append(allocator, "with the following features:");
    try section.content.append(allocator, "");
    try section.content.append(allocator, "✓ Multiple tabs with different content types");
    try section.content.append(allocator, "✓ Icons and close buttons support");
    try section.content.append(allocator, "✓ Non-closeable system tabs");
    try section.content.append(allocator, "✓ Keyboard navigation (Ctrl+Tab, Ctrl+W, etc.)");
    try section.content.append(allocator, "✓ Dynamic tab creation and removal");
    try section.content.append(allocator, "✓ Rich content integration");
    try section.content.append(allocator, "✓ Customizable appearance");
    try section.content.append(allocator, "");

    try section.render(stdout_writer);
}

fn drawEditorTab(demo_data: *DemoData, allocator: std.mem.Allocator) !void {
    _ = allocator; // Currently unused, but kept for future enhancement
    const stdout_writer = std.io.getStdOut().writer();

    try stdout_writer.print("Mock Text Editor\n", .{});
    try stdout_writer.print("================\n\n", .{});

    // Show editor content with line numbers
    var lines = std.mem.split(u8, demo_data.editor_content.items, "\n");
    var line_num: u32 = 1;

    while (lines.next()) |line| {
        if (line_num < 10) {
            try stdout_writer.print(" {d} | {s}\n", .{ line_num, line });
        } else {
            try stdout_writer.print("{d} | {s}\n", .{ line_num, line });
        }
        line_num += 1;
        if (line_num > 15) break; // Limit display
    }

    try stdout_writer.print("\n[Editor Status: {d} lines, {d} characters]\n", .{
        line_num - 1,
        demo_data.editor_content.items.len,
    });
}

fn drawDataTab(allocator: std.mem.Allocator) !void {
    _ = allocator; // Currently unused, but kept for future enhancement
    const stdout_writer = std.io.getStdOut().writer();

    try stdout_writer.print("Sample Data Table\n", .{});
    try stdout_writer.print("=================\n\n", .{});

    // Draw a table
    const headers = [_][]const u8{ "ID", "Name", "Status", "Value" };
    const data = [_][4][]const u8{
        .{ "001", "Alice Johnson", "Active", "$1,250.00" },
        .{ "002", "Bob Smith", "Inactive", "$890.50" },
        .{ "003", "Carol Williams", "Active", "$2,100.75" },
        .{ "004", "David Brown", "Pending", "$450.25" },
        .{ "005", "Eva Davis", "Active", "$3,200.00" },
    };

    // Draw headers
    try stdout_writer.print("+-----+---------------+----------+----------+\n", .{});
    try stdout_writer.print("| {s:<3} | {s:<13} | {s:<8} | {s:<8} |\n", .{
        headers[0], headers[1], headers[2], headers[3],
    });
    try stdout_writer.print("+-----+---------------+----------+----------+\n", .{});

    // Draw data rows
    for (data) |row| {
        try stdout_writer.print("| {s:<3} | {s:<13} | {s:<8} | {s:<8} |\n", .{
            row[0], row[1], row[2], row[3],
        });
    }
    try stdout_writer.print("+-----+---------------+----------+----------+\n", .{});

    try stdout_writer.print("\n[Table: 5 rows × 4 columns]\n", .{});
}

fn drawCalendarTab(calendar: *Calendar, allocator: std.mem.Allocator) !void {
    _ = allocator; // Currently unused, but kept for future enhancement
    const stdout_writer = std.io.getStdOut().writer();

    try stdout_writer.print("Calendar Widget Integration\n", .{});
    try stdout_writer.print("===========================\n\n", .{});

    try calendar.render(stdout_writer);

    try stdout_writer.print("\nNavigation: ←→↑↓ arrows, PgUp/PgDn for months\n", .{});
    try stdout_writer.print("Space: Select date, T: Today, ESC: Clear selection\n", .{});
}

fn drawSettingsTab(demo_data: *DemoData, allocator: std.mem.Allocator) !void {
    _ = allocator; // Currently unused, but kept for future enhancement
    const stdout_writer = std.io.getStdOut().writer();

    try stdout_writer.print("Settings Panel\n", .{});
    try stdout_writer.print("==============\n\n", .{});

    var settings_iter = demo_data.settings.iterator();
    while (settings_iter.next()) |entry| {
        try stdout_writer.print("{s:<15} : {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    try stdout_writer.print("\n[Settings: {d} configured]\n", .{ demo_data.settings.count() });
    try stdout_writer.print("\nUse ↑↓ arrows to navigate, Enter to edit\n", .{});
}

fn drawLogsTab(demo_data: *DemoData, allocator: std.mem.Allocator) !void {
    _ = allocator; // Currently unused, but kept for future enhancement
    const stdout_writer = std.io.getStdOut().writer();

    try stdout_writer.print("System Logs\n", .{});
    try stdout_writer.print("===========\n\n", .{});

    // Show last 10 log entries
    const start_idx = if (demo_data.log_entries.items.len > 10)
        demo_data.log_entries.items.len - 10
    else
        0;

    for (demo_data.log_entries.items[start_idx..]) |entry| {
        try stdout_writer.print("{s}\n", .{entry});
    }

    try stdout_writer.print("\n[Logs: {d} entries total]\n", .{ demo_data.log_entries.items.len });
    try stdout_writer.print("\nUse ↑↓ to scroll, Ctrl+C to copy selected\n", .{});
}

fn drawHelpTab(allocator: std.mem.Allocator) !void {
    _ = allocator; // Currently unused, but kept for future enhancement
    const stdout_writer = std.io.getStdOut().writer();

    try stdout_writer.print("Keyboard Shortcuts & Help\n", .{});
    try stdout_writer.print("=========================\n\n", .{});

    const shortcuts = [_]struct{ keys: []const u8, description: []const u8 }{
        .{ .keys = "Ctrl+Tab", .description = "Next tab" },
        .{ .keys = "Ctrl+Shift+Tab", .description = "Previous tab" },
        .{ .keys = "Ctrl+W", .description = "Close current tab" },
        .{ .keys = "Ctrl+1-9", .description = "Jump to tab by number" },
        .{ .keys = "n", .description = "Create new tab" },
        .{ .keys = "d", .description = "Delete current tab" },
        .{ .keys = "c", .description = "Close all closeable tabs" },
        .{ .keys = "q", .description = "Quit demo" },
        .{ .keys = "Tab", .description = "Navigate between controls" },
        .{ .keys = "Enter", .description = "Activate selected item" },
        .{ .keys = "ESC", .description = "Cancel/Deselect" },
    };

    for (shortcuts) |shortcut| {
        try stdout_writer.print("{s:<15} - {s}\n", .{ shortcut.keys, shortcut.description });
    }

    try stdout_writer.print("\nTab-specific shortcuts:\n", .{});
    try stdout_writer.print("Editor tab     - Type to edit text\n", .{});
    try stdout_writer.print("Data tab       - ↑↓ to navigate rows\n", .{});
    try stdout_writer.print("Calendar tab   - Arrow keys to navigate dates\n", .{});
    try stdout_writer.print("Settings tab   - ↑↓ to navigate, Enter to edit\n", .{});
    try stdout_writer.print("Logs tab       - ↑↓ to scroll through entries\n", .{});
}

fn drawStatusBar(demo_data: *DemoData, tabs: TabContainer, allocator: std.mem.Allocator) !void {
    _ = demo_data; // Currently unused, but kept for future enhancement
    const stdout_writer = std.io.getStdOut().writer();

    // Position at bottom of screen
    try stdout_writer.print("\x1b[24;1H", .{});
    try stdout_writer.print("\x1b[47;30m", .{}); // White background, black text

    const active_tab = tabs.getActiveTab() orelse return;
    const tab_info = try std.fmt.allocPrint(allocator, "Tab: {s} ({d}/{d})", .{
        active_tab.title,
        tabs.active_index + 1,
        tabs.tabs.items.len,
    });
    defer allocator.free(tab_info);

    try stdout_writer.print("{s:<40}", .{tab_info});

    const status = if (active_tab.closeable)
        "Closeable | Ctrl+W to close"
    else
        "System Tab | Protected";

    try stdout_writer.print("{s:>39}", .{status});
    try stdout_writer.print("\x1b[0m", .{}); // Reset colors
}

fn readKey() !u8 {
    const stdin = std.io.getStdIn();
    var buffer: [1]u8 = undefined;

    // Set terminal to raw mode for single character input
    const stdout_writer_local = std.io.getStdOut().writer();
    try stdout_writer_local.print("\x1b[?25l", .{}); // Hide cursor
    defer stdout_writer_local.print("\x1b[?25h", .{}) catch {}; // Show cursor on exit

    const bytes_read = try stdin.read(&buffer);
    if (bytes_read == 1) {
        return buffer[0];
    }

    return 0;
}


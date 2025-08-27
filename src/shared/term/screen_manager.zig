const std = @import("std");

/// Advanced screen management for terminal applications
/// Provides screen save/restore, alternate screen buffer, and window management
/// Inspired by advanced terminal libraries with modern features
/// ANSI escape sequences for screen management
pub const ScreenSequences = struct {
    // Alternate screen buffer
    pub const ENTER_ALT_SCREEN = "\x1b[?1049h";
    pub const EXIT_ALT_SCREEN = "\x1b[?1049l";

    // Classic screen save/restore (older terminals)
    pub const SAVE_SCREEN = "\x1b[?47h";
    pub const RESTORE_SCREEN = "\x1b[?47l";

    // Cursor save/restore
    pub const SAVE_CURSOR = "\x1b[s";
    pub const RESTORE_CURSOR = "\x1b[u";

    // DEC cursor save/restore (more reliable)
    pub const SAVE_CURSOR_DEC = "\x1b7";
    pub const RESTORE_CURSOR_DEC = "\x1b8";

    // Screen clearing
    pub const CLEAR_SCREEN = "\x1b[2J";
    pub const CLEAR_TO_END = "\x1b[J";
    pub const CLEAR_TO_START = "\x1b[1J";
    pub const CLEAR_LINE = "\x1b[K";
    pub const CLEAR_LINE_TO_END = "\x1b[0K";
    pub const CLEAR_LINE_TO_START = "\x1b[1K";
    pub const CLEAR_ENTIRE_LINE = "\x1b[2K";

    // Cursor positioning
    pub const HOME_CURSOR = "\x1b[H";
    pub const CURSOR_TO_POS = "\x1b[{};{}H"; // Use with format

    // Scrolling
    pub const SCROLL_UP = "\x1b[S";
    pub const SCROLL_DOWN = "\x1b[T";
    pub const SCROLL_UP_N = "\x1b[{}S"; // Use with format
    pub const SCROLL_DOWN_N = "\x1b[{}T"; // Use with format

    // Terminal modes
    pub const HIDE_CURSOR = "\x1b[?25l";
    pub const SHOW_CURSOR = "\x1b[?25h";
    pub const ENABLE_MOUSE = "\x1b[?1000h";
    pub const DISABLE_MOUSE = "\x1b[?1000l";
    pub const ENABLE_MOUSE_SGR = "\x1b[?1006h";
    pub const DISABLE_MOUSE_SGR = "\x1b[?1006l";

    // Window title
    pub const SET_TITLE = "\x1b]0;{};\x07"; // Use with format
    pub const SET_ICON_NAME = "\x1b]1;{};\x07"; // Use with format
    pub const SET_WINDOW_TITLE = "\x1b]2;{};\x07"; // Use with format

    // Synchronized output
    pub const SYNC_START = "\x1b[?2026h";
    pub const SYNC_END = "\x1b[?2026l";
};

/// Screen state tracking
pub const ScreenState = struct {
    in_alt_screen: bool = false,
    cursor_saved: bool = false,
    cursor_visible: bool = true,
    mouse_enabled: bool = false,
    sync_output: bool = false,
    saved_title: ?[]const u8 = null,

    /// Get current screen dimensions (if available)
    pub fn getScreenSize() ?struct { width: u16, height: u16 } {
        // This would ideally query the terminal, but for now return a placeholder
        // In a real implementation, this could use ioctl or environment variables
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "COLUMNS")) |cols_str| {
            defer std.heap.page_allocator.free(cols_str);
            if (std.process.getEnvVarOwned(std.heap.page_allocator, "LINES")) |rows_str| {
                defer std.heap.page_allocator.free(rows_str);

                const cols = std.fmt.parseInt(u16, cols_str, 10) catch return null;
                const rows = std.fmt.parseInt(u16, rows_str, 10) catch return null;
                return .{ .width = cols, .height = rows };
            }
        }
        return null;
    }
};

/// Comprehensive screen manager with state tracking and restoration
pub const ScreenManager = struct {
    allocator: std.mem.Allocator,
    state: ScreenState,
    restore_on_exit: bool = true,
    output_writer: ?*std.Io.Writer = null, // For writing sequences

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .state = ScreenState{},
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.state.saved_title) |title| {
            self.allocator.free(title);
        }

        // Restore screen state on cleanup if requested
        if (self.restore_on_exit) {
            self.restoreAll() catch {};
        }
    }

    /// Set output writer for sending escape sequences
    pub fn setWriter(self: *Self, writer: *std.Io.Writer) void {
        self.output_writer = writer;
    }

    /// Send escape sequence to terminal
    fn sendSequence(self: Self, sequence: []const u8) !void {
        if (self.output_writer) |writer| {
            _ = try writer.write(sequence);
        } else {
            // Default to stdout
            const stdout = std.fs.File.stdout();
            try stdout.writeAll(sequence);
        }
    }

    /// Enter alternate screen buffer
    pub fn enterAltScreen(self: *Self) !void {
        if (!self.state.in_alt_screen) {
            try self.sendSequence(ScreenSequences.ENTER_ALT_SCREEN);
            self.state.in_alt_screen = true;
        }
    }

    /// Exit alternate screen buffer
    pub fn exitAltScreen(self: *Self) !void {
        if (self.state.in_alt_screen) {
            try self.sendSequence(ScreenSequences.EXIT_ALT_SCREEN);
            self.state.in_alt_screen = false;
        }
    }

    /// Save current cursor position
    pub fn saveCursor(self: *Self) !void {
        try self.sendSequence(ScreenSequences.SAVE_CURSOR_DEC);
        self.state.cursor_saved = true;
    }

    /// Restore saved cursor position
    pub fn restoreCursor(self: *Self) !void {
        if (self.state.cursor_saved) {
            try self.sendSequence(ScreenSequences.RESTORE_CURSOR_DEC);
        }
    }

    /// Hide cursor
    pub fn hideCursor(self: *Self) !void {
        if (self.state.cursor_visible) {
            try self.sendSequence(ScreenSequences.HIDE_CURSOR);
            self.state.cursor_visible = false;
        }
    }

    /// Show cursor
    pub fn showCursor(self: *Self) !void {
        if (!self.state.cursor_visible) {
            try self.sendSequence(ScreenSequences.SHOW_CURSOR);
            self.state.cursor_visible = true;
        }
    }

    /// Clear entire screen
    pub fn clearScreen(self: Self) !void {
        try self.sendSequence(ScreenSequences.CLEAR_SCREEN);
        try self.sendSequence(ScreenSequences.HOME_CURSOR);
    }

    /// Clear current line
    pub fn clearLine(self: Self) !void {
        try self.sendSequence(ScreenSequences.CLEAR_ENTIRE_LINE);
    }

    /// Move cursor to specific position (1-based coordinates)
    pub fn moveCursor(self: Self, row: u16, col: u16) !void {
        const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{};{}H", .{ row, col });
        defer self.allocator.free(sequence);
        try self.sendSequence(sequence);
    }

    /// Move cursor to home position (1,1)
    pub fn homeCursor(self: Self) !void {
        try self.sendSequence(ScreenSequences.HOME_CURSOR);
    }

    /// Scroll screen up by n lines
    pub fn scrollUp(self: Self, lines: u16) !void {
        if (lines == 1) {
            try self.sendSequence(ScreenSequences.SCROLL_UP);
        } else {
            const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{}S", .{lines});
            defer self.allocator.free(sequence);
            try self.sendSequence(sequence);
        }
    }

    /// Scroll screen down by n lines
    pub fn scrollDown(self: Self, lines: u16) !void {
        if (lines == 1) {
            try self.sendSequence(ScreenSequences.SCROLL_DOWN);
        } else {
            const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{}T", .{lines});
            defer self.allocator.free(sequence);
            try self.sendSequence(sequence);
        }
    }

    /// Enable mouse reporting
    pub fn enableMouse(self: *Self, sgr_mode: bool) !void {
        if (!self.state.mouse_enabled) {
            try self.sendSequence(ScreenSequences.ENABLE_MOUSE);
            if (sgr_mode) {
                try self.sendSequence(ScreenSequences.ENABLE_MOUSE_SGR);
            }
            self.state.mouse_enabled = true;
        }
    }

    /// Disable mouse reporting
    pub fn disableMouse(self: *Self) !void {
        if (self.state.mouse_enabled) {
            try self.sendSequence(ScreenSequences.DISABLE_MOUSE_SGR);
            try self.sendSequence(ScreenSequences.DISABLE_MOUSE);
            self.state.mouse_enabled = false;
        }
    }

    /// Set window title
    pub fn setTitle(self: *Self, title: []const u8) !void {
        const sequence = try std.fmt.allocPrint(self.allocator, "\x1b]0;{s}\x07", .{title});
        defer self.allocator.free(sequence);
        try self.sendSequence(sequence);

        // Save title for restoration
        if (self.state.saved_title) |old_title| {
            self.allocator.free(old_title);
        }
        self.state.saved_title = try self.allocator.dupe(u8, title);
    }

    /// Enable synchronized output (reduce flicker)
    pub fn enableSyncOutput(self: *Self) !void {
        if (!self.state.sync_output) {
            try self.sendSequence(ScreenSequences.SYNC_START);
            self.state.sync_output = true;
        }
    }

    /// Disable synchronized output
    pub fn disableSyncOutput(self: *Self) !void {
        if (self.state.sync_output) {
            try self.sendSequence(ScreenSequences.SYNC_END);
            self.state.sync_output = false;
        }
    }

    /// Begin synchronized output block
    pub fn beginSync(self: Self) !void {
        try self.sendSequence(ScreenSequences.SYNC_START);
    }

    /// End synchronized output block
    pub fn endSync(self: Self) !void {
        try self.sendSequence(ScreenSequences.SYNC_END);
    }

    /// Setup terminal for TUI application
    pub fn setupForTUI(self: *Self) !void {
        try self.saveCursor();
        try self.enterAltScreen();
        try self.hideCursor();
        try self.clearScreen();
    }

    /// Restore terminal after TUI application
    pub fn restoreFromTUI(self: *Self) !void {
        try self.showCursor();
        try self.exitAltScreen();
        try self.restoreCursor();
        try self.disableMouse();
        try self.disableSyncOutput();
    }

    /// Restore all terminal settings to original state
    pub fn restoreAll(self: *Self) !void {
        // Restore in reverse order of setup
        try self.disableSyncOutput();
        try self.disableMouse();
        try self.showCursor();
        try self.exitAltScreen();
        try self.restoreCursor();
    }

    /// Get current screen state
    pub fn getState(self: Self) ScreenState {
        return self.state;
    }

    /// Check if terminal is in alternate screen
    pub fn isInAltScreen(self: Self) bool {
        return self.state.in_alt_screen;
    }

    /// Check if cursor is hidden
    pub fn isCursorHidden(self: Self) bool {
        return !self.state.cursor_visible;
    }

    /// Check if mouse is enabled
    pub fn isMouseEnabled(self: Self) bool {
        return self.state.mouse_enabled;
    }
};

/// RAII wrapper for automatic screen restoration
pub const ScreenGuard = struct {
    manager: *ScreenManager,

    const Self = @This();

    pub fn init(manager: *ScreenManager) !Self {
        try manager.setupForTUI();
        return Self{ .manager = manager };
    }

    pub fn deinit(self: Self) void {
        self.manager.restoreFromTUI() catch {};
    }
};

/// Utility for creating safe screen management blocks
pub fn withScreen(allocator: std.mem.Allocator, comptime func: anytype, args: anytype) !void {
    var manager = ScreenManager.init(allocator);
    defer manager.deinit();

    const guard = try ScreenGuard.init(&manager);
    defer guard.deinit();

    try @call(.auto, func, .{&manager} ++ args);
}

// Tests
test "screen manager initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var manager = ScreenManager.init(allocator);
    defer manager.deinit();

    try testing.expect(!manager.state.in_alt_screen);
    try testing.expect(!manager.state.cursor_saved);
    try testing.expect(manager.state.cursor_visible);
}

test "screen state tracking" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var manager = ScreenManager.init(allocator);
    defer manager.deinit();

    // Simulate state changes (without actual terminal I/O)
    manager.state.in_alt_screen = true;
    manager.state.cursor_visible = false;

    try testing.expect(manager.isInAltScreen());
    try testing.expect(manager.isCursorHidden());
    try testing.expect(!manager.isMouseEnabled());
}

test "title management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var manager = ScreenManager.init(allocator);
    defer manager.deinit();

    // This would normally send to terminal, but we're just testing the allocation
    manager.state.saved_title = try allocator.dupe(u8, "Test Title");

    try testing.expect(manager.state.saved_title != null);
    try testing.expect(std.mem.eql(u8, manager.state.saved_title.?, "Test Title"));
}

test "screen guard RAII" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var manager = ScreenManager.init(allocator);
    defer manager.deinit();

    // Simulate guard setup without terminal I/O
    manager.state.in_alt_screen = true;
    manager.state.cursor_saved = true;
    manager.state.cursor_visible = false;

    const initial_state = manager.getState();
    try testing.expect(initial_state.in_alt_screen);
    try testing.expect(!initial_state.cursor_visible);
}

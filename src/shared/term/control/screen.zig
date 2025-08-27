const std = @import("std");
const caps_mod = @import("../capabilities.zig");
const passthrough = @import("../ansi/passthrough.zig");
const tab_processor = @import("../tab_processor.zig");
const error_mod = @import("../core/error.zig");

pub const TermCaps = caps_mod.TermCaps;
pub const TermError = error_mod.TermError;
pub const TabConfig = tab_processor.TabConfig;

/// Unified screen control module combining high-level state management
/// with low-level ANSI escape sequence operations
pub const ScreenControl = struct {
    allocator: std.mem.Allocator,
    state: ScreenState,
    restore_on_exit: bool = true,
    output_writer: ?*std.Io.Writer = null,
    caps: TermCaps,

    const Self = @This();

    /// Screen state tracking for high-level operations
    pub const ScreenState = struct {
        in_alt_screen: bool = false,
        cursor_saved: bool = false,
        cursor_visible: bool = true,
        mouse_enabled: bool = false,
        sync_output: bool = false,
        saved_title: ?[]const u8 = null,
        scroll_region_set: bool = false,
        tab_stops_modified: bool = false,

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
        pub const CLEAR_ENTIRE_LINE = "\x1b[2K";
        pub const CLEAR_LINE = "\x1b[K";
        pub const CLEAR_LINE_TO_END = "\x1b[0K";
        pub const CLEAR_LINE_TO_START = "\x1b[1K";

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

        // Scroll region
        pub const SET_SCROLL_REGION = "\x1b[{};{}r"; // Use with format
        pub const RESET_SCROLL_REGION = "\x1b[r";

        // Tab control
        pub const TAB_FORWARD = "\t";
        pub const SET_TAB_STOP = "\x1bH";
        pub const CLEAR_TAB_STOP = "\x1b[g";
        pub const CLEAR_ALL_TAB_STOPS = "\x1b[3g";
        pub const SET_TAB_EVERY_8 = "\x1b[?5W";
    };

    pub fn init(allocator: std.mem.Allocator, caps: TermCaps) Self {
        return Self{
            .allocator = allocator,
            .state = ScreenState{},
            .caps = caps,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.state.saved_title) |title| {
            self.allocator.free(title);
        }

        // Restore screen state on cleanup if requested
        if (self.restore_on_exit) {
            self.restoreAll() catch |err| {
                std.log.warn("Failed to restore screen state on cleanup: {any}", .{err});
            };
        }
    }

    /// Set output writer for sending escape sequences
    pub fn setWriter(self: *Self, writer: *std.Io.Writer) void {
        self.output_writer = writer;
    }

    /// Send escape sequence to terminal
    fn sendSequence(self: Self, sequence: []const u8) !void {
        if (self.output_writer) |writer| {
            try passthrough.writeWithPassthrough(writer.*, self.caps, sequence);
        } else {
            // Default to stdout
            const stdout = std.fs.File.stdout();
            try passthrough.writeWithPassthrough(stdout.writer(), self.caps, sequence);
        }
    }

    // ===== HIGH-LEVEL STATEFUL OPERATIONS =====

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
        const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d};{d}H", .{ row, col });
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
            const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d}S", .{lines});
            defer self.allocator.free(sequence);
            try self.sendSequence(sequence);
        }
    }

    /// Scroll screen down by n lines
    pub fn scrollDown(self: Self, lines: u16) !void {
        if (lines == 1) {
            try self.sendSequence(ScreenSequences.SCROLL_DOWN);
        } else {
            const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d}T", .{lines});
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

    // ===== LOW-LEVEL STATELESS OPERATIONS =====

    /// Clear part/all of the screen (ED)
    pub fn clearScreenToEnd(self: Self) !void {
        try self.sendSequence("\x1b[0J");
    }

    pub fn clearScreenToStart(self: Self) !void {
        try self.sendSequence("\x1b[1J");
    }

    pub fn clearScreenAll(self: Self) !void {
        try self.sendSequence("\x1b[2J");
    }

    /// Clear part/all of the line (EL)
    pub fn clearLineToEnd(self: Self) !void {
        try self.sendSequence("\x1b[0K");
    }

    pub fn clearLineToStart(self: Self) !void {
        try self.sendSequence("\x1b[1K");
    }

    pub fn clearLineAll(self: Self) !void {
        try self.sendSequence("\x1b[2K");
    }

    /// Set scroll region (DECSTBM): CSI top ; bottom r
    pub fn setScrollRegion(self: Self, top: u32, bottom: u32) !void {
        const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d};{d}r", .{ top, bottom });
        defer self.allocator.free(sequence);
        try self.sendSequence(sequence);
        self.state.scroll_region_set = true;
    }

    /// Reset scroll region to full screen: CSI r
    pub fn resetScrollRegion(self: *Self) !void {
        try self.sendSequence("\x1b[r");
        self.state.scroll_region_set = false;
    }

    /// Insert/Delete lines and characters
    pub fn insertLine(self: Self, n: u32) !void {
        const count = if (n == 0) 1 else n;
        const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d}L", .{count});
        defer self.allocator.free(sequence);
        try self.sendSequence(sequence);
    }

    pub fn deleteLine(self: Self, n: u32) !void {
        const count = if (n == 0) 1 else n;
        const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d}M", .{count});
        defer self.allocator.free(sequence);
        try self.sendSequence(sequence);
    }

    pub fn insertCharacter(self: Self, n: u32) !void {
        const count = if (n == 0) 1 else n;
        const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d}@", .{count});
        defer self.allocator.free(sequence);
        try self.sendSequence(sequence);
    }

    pub fn deleteCharacter(self: Self, n: u32) !void {
        const count = if (n == 0) 1 else n;
        const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d}P", .{count});
        defer self.allocator.free(sequence);
        try self.sendSequence(sequence);
    }

    /// Repeat previous character (REP): CSI n b
    pub fn repeatPreviousCharacter(self: Self, n: u32) !void {
        const count = if (n == 0) 1 else n;
        const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d}b", .{count});
        defer self.allocator.free(sequence);
        try self.sendSequence(sequence);
    }

    // ===== TAB CONTROL FUNCTIONS =====

    /// Move cursor to next tab stop (HT): TAB character
    pub fn horizontalTab(self: Self) !void {
        try self.sendSequence("\t");
    }

    /// Move cursor back to previous tab stop (CBT): CSI n Z
    pub fn cursorBackTab(self: Self, n: u32) !void {
        const count = if (n == 0) 1 else n;
        const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d}Z", .{count});
        defer self.allocator.free(sequence);
        try self.sendSequence(sequence);
    }

    /// Move cursor to next horizontal tab stop (CHT): CSI n I
    pub fn cursorHorizontalTab(self: Self, n: u32) !void {
        const count = if (n == 0) 1 else n;
        const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d}I", .{count});
        defer self.allocator.free(sequence);
        try self.sendSequence(sequence);
    }

    /// Move cursor to next vertical tab stop (CVT): CSI n Y
    pub fn cursorVerticalTab(self: Self, n: u32) !void {
        const count = if (n == 0) 1 else n;
        const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d}Y", .{count});
        defer self.allocator.free(sequence);
        try self.sendSequence(sequence);
    }

    /// Set a horizontal tab stop (HTS): ESC H
    pub fn setHorizontalTabStop(self: *Self) !void {
        try self.sendSequence("\x1bH");
        self.state.tab_stops_modified = true;
    }

    /// Tab Clear (TBC): CSI n g, where n=0 clears at current column, n=3 clears all
    pub fn tabClear(self: *Self, n: u32) !void {
        if (n == 0) {
            try self.sendSequence("\x1b[g");
        } else {
            const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d}g", .{n});
            defer self.allocator.free(sequence);
            try self.sendSequence(sequence);
        }
        self.state.tab_stops_modified = true;
    }

    /// Set tab stops every 8 columns (DECST8C): CSI ? 5 W
    pub fn setTabEvery8Columns(self: *Self) !void {
        try self.sendSequence("\x1b[?5W");
        self.state.tab_stops_modified = true;
    }

    /// Write text with tab expansion using ANSI tab control
    pub fn writeTextWithTabControl(self: Self, text: []const u8, tab_config: TabConfig) !void {
        if (tab_config.expand_tabs) {
            // Expand tabs to spaces for consistent rendering
            const expanded = try tab_processor.expandTabs(self.allocator, text, tab_config);
            defer self.allocator.free(expanded);
            try self.sendSequence(expanded);
        } else {
            // Use raw tab characters - terminal will handle tab stops
            try self.sendSequence(text);
        }
    }

    /// Request presentation state report (DECRQPSR): CSI Ps $ w
    pub fn requestPresentationStateReport(self: Self, ps: u32) !void {
        const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d}$w", .{ps});
        defer self.allocator.free(sequence);
        try self.sendSequence(sequence);
    }

    /// Set Top/Bottom Margins (DECSTBM): CSI top ; bot r (alias of setScrollRegion)
    pub fn setTopBottomMargins(self: Self, top: u32, bottom: u32) !void {
        try self.setScrollRegion(top, bottom);
    }

    /// Set Left/Right Margins (DECSLRM): CSI left ; right s
    pub fn setLeftRightMargins(self: Self, left: u32, right: u32) !void {
        const sequence = try std.fmt.allocPrint(self.allocator, "\x1b[{d};{d}s", .{ left, right });
        defer self.allocator.free(sequence);
        try self.sendSequence(sequence);
    }
};

/// RAII wrapper for automatic screen restoration
pub const ScreenGuard = struct {
    manager: *ScreenControl,

    const Self = @This();

    pub fn init(manager: *ScreenControl) !Self {
        try manager.setupForTUI();
        return Self{ .manager = manager };
    }

    pub fn deinit(self: Self) void {
        self.manager.restoreFromTUI() catch |err| {
            std.log.warn("Failed to restore screen from TUI mode: {any}", .{err});
        };
    }
};

/// Utility for creating safe screen management blocks
pub fn withScreenControl(allocator: std.mem.Allocator, caps: TermCaps, comptime func: anytype, args: anytype) !void {
    var manager = ScreenControl.init(allocator, caps);
    defer manager.deinit();

    const guard = try ScreenGuard.init(&manager);
    defer guard.deinit();

    try @call(.auto, func, .{&manager} ++ args);
}

// ===== STATELESS UTILITY FUNCTIONS =====

/// Stateless screen control functions that work with any writer
pub const Stateless = struct {
    /// Clear entire screen and home cursor
    pub fn clearScreen(writer: anytype, caps: TermCaps) !void {
        try passthrough.writeWithPassthrough(writer, caps, ScreenControl.ScreenSequences.CLEAR_SCREEN);
        try passthrough.writeWithPassthrough(writer, caps, ScreenControl.ScreenSequences.HOME_CURSOR);
    }

    /// Move cursor to position
    pub fn moveCursor(writer: anytype, caps: TermCaps, row: u16, col: u16) !void {
        var buf: [32]u8 = undefined;
        const sequence = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ row, col });
        try passthrough.writeWithPassthrough(writer, caps, sequence);
    }

    /// Hide/show cursor
    pub fn hideCursor(writer: anytype, caps: TermCaps) !void {
        try passthrough.writeWithPassthrough(writer, caps, ScreenControl.ScreenSequences.HIDE_CURSOR);
    }

    pub fn showCursor(writer: anytype, caps: TermCaps) !void {
        try passthrough.writeWithPassthrough(writer, caps, ScreenControl.ScreenSequences.SHOW_CURSOR);
    }

    /// Enter/exit alternate screen
    pub fn enterAltScreen(writer: anytype, caps: TermCaps) !void {
        try passthrough.writeWithPassthrough(writer, caps, ScreenControl.ScreenSequences.ENTER_ALT_SCREEN);
    }

    pub fn exitAltScreen(writer: anytype, caps: TermCaps) !void {
        try passthrough.writeWithPassthrough(writer, caps, ScreenControl.ScreenSequences.EXIT_ALT_SCREEN);
    }

    /// Clear operations
    pub fn clearScreenToEnd(writer: anytype, caps: TermCaps) !void {
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[0J");
    }

    pub fn clearLine(writer: anytype, caps: TermCaps) !void {
        try passthrough.writeWithPassthrough(writer, caps, "\x1b[2K");
    }

    /// Scroll operations
    pub fn scrollUp(writer: anytype, caps: TermCaps, lines: u16) !void {
        if (lines == 1) {
            try passthrough.writeWithPassthrough(writer, caps, "\x1b[S");
        } else {
            var buf: [32]u8 = undefined;
            const sequence = try std.fmt.bufPrint(&buf, "\x1b[{d}S", .{lines});
            try passthrough.writeWithPassthrough(writer, caps, sequence);
        }
    }

    pub fn scrollDown(writer: anytype, caps: TermCaps, lines: u16) !void {
        if (lines == 1) {
            try passthrough.writeWithPassthrough(writer, caps, "\x1b[T");
        } else {
            var buf: [32]u8 = undefined;
            const sequence = try std.fmt.bufPrint(&buf, "\x1b[{d}T", .{lines});
            try passthrough.writeWithPassthrough(writer, caps, sequence);
        }
    }

    /// Tab operations
    pub fn horizontalTab(writer: anytype, caps: TermCaps) !void {
        try passthrough.writeWithPassthrough(writer, caps, "\t");
    }

    pub fn setHorizontalTabStop(writer: anytype, caps: TermCaps) !void {
        try passthrough.writeWithPassthrough(writer, caps, "\x1bH");
    }

    pub fn tabClear(writer: anytype, caps: TermCaps, n: u32) !void {
        if (n == 0) {
            try passthrough.writeWithPassthrough(writer, caps, "\x1b[g");
        } else {
            var buf: [32]u8 = undefined;
            const sequence = try std.fmt.bufPrint(&buf, "\x1b[{d}g", .{n});
            try passthrough.writeWithPassthrough(writer, caps, sequence);
        }
    }
};

// Tests
test "screen control initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const caps = caps_mod.getTermCaps();

    var manager = ScreenControl.init(allocator, caps);
    defer manager.deinit();

    try testing.expect(!manager.state.in_alt_screen);
    try testing.expect(!manager.state.cursor_saved);
    try testing.expect(manager.state.cursor_visible);
}

test "screen state tracking" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const caps = caps_mod.getTermCaps();

    var manager = ScreenControl.init(allocator, caps);
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
    const caps = caps_mod.getTermCaps();

    var manager = ScreenControl.init(allocator, caps);
    defer manager.deinit();

    // This would normally send to terminal, but we're just testing the allocation
    manager.state.saved_title = try allocator.dupe(u8, "Test Title");

    try testing.expect(manager.state.saved_title != null);
    try testing.expect(std.mem.eql(u8, manager.state.saved_title.?, "Test Title"));
}

test "screen guard RAII" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const caps = caps_mod.getTermCaps();

    var manager = ScreenControl.init(allocator, caps);
    defer manager.deinit();

    // Simulate guard setup without terminal I/O
    manager.state.in_alt_screen = true;
    manager.state.cursor_saved = true;
    manager.state.cursor_visible = false;

    const initial_state = manager.getState();
    try testing.expect(initial_state.in_alt_screen);
    try testing.expect(!initial_state.cursor_visible);
}

test "tab config spaces to next tab stop" {
    const config = TabConfig{ .tab_width = 8 };

    try std.testing.expectEqual(@as(u8, 8), config.spacesToNextTabStop(0));
    try std.testing.expectEqual(@as(u8, 7), config.spacesToNextTabStop(1));
    try std.testing.expectEqual(@as(u8, 1), config.spacesToNextTabStop(7));
    try std.testing.expectEqual(@as(u8, 8), config.spacesToNextTabStop(8));
    try std.testing.expectEqual(@as(u8, 4), config.spacesToNextTabStop(12));
}

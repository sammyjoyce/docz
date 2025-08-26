const std = @import("std");

/// CursorStyle represents different cursor appearance styles.
pub const CursorStyle = enum(u8) {
    /// Blinking block cursor (default)
    blinking_block = 0,
    /// Blinking block cursor (same as default)  
    blinking_block_default = 1,
    /// Steady (non-blinking) block cursor
    steady_block = 2,
    /// Blinking underline cursor
    blinking_underline = 3,
    /// Steady (non-blinking) underline cursor
    steady_underline = 4,
    /// Blinking bar cursor (vertical line)
    blinking_bar = 5,
    /// Steady (non-blinking) bar cursor (vertical line)
    steady_bar = 6,
};

/// Enhanced cursor control functions based on charmbracelet/x implementation.
pub const CursorControl = struct {

    // Static buffers to avoid allocations for common cases
    threadlocal var up_buf: [16]u8 = undefined;
    threadlocal var down_buf: [16]u8 = undefined;
    threadlocal var forward_buf: [16]u8 = undefined;
    threadlocal var backward_buf: [16]u8 = undefined;
    threadlocal var position_buf: [32]u8 = undefined;
    threadlocal var style_buf: [16]u8 = undefined;

    // ===== CURSOR POSITIONING =====

    /// Move cursor up by n rows.
    pub fn cursorUp(n: u32) []const u8 {
        if (n <= 1) return "\x1b[A";
        return std.fmt.bufPrint(&up_buf, "\x1b[{}A", .{n}) catch "\x1b[A";
    }

    /// Move cursor down by n rows.
    pub fn cursorDown(n: u32) []const u8 {
        if (n <= 1) return "\x1b[B";
        return std.fmt.bufPrint(&down_buf, "\x1b[{}B", .{n}) catch "\x1b[B";
    }

    /// Move cursor right by n columns.
    pub fn cursorForward(n: u32) []const u8 {
        if (n <= 1) return "\x1b[C";
        return std.fmt.bufPrint(&forward_buf, "\x1b[{}C", .{n}) catch "\x1b[C";
    }

    /// Move cursor left by n columns.
    pub fn cursorBackward(n: u32) []const u8 {
        if (n <= 1) return "\x1b[D";
        return std.fmt.bufPrint(&backward_buf, "\x1b[{}D", .{n}) catch "\x1b[D";
    }

    /// Move cursor to the beginning of the next line, n times.
    pub fn cursorNextLine(n: u32) []const u8 {
        if (n <= 1) return "\x1b[E";
        return std.fmt.bufPrint(&up_buf, "\x1b[{}E", .{n}) catch "\x1b[E";
    }

    /// Move cursor to the beginning of the previous line, n times.
    pub fn cursorPreviousLine(n: u32) []const u8 {
        if (n <= 1) return "\x1b[F";
        return std.fmt.bufPrint(&up_buf, "\x1b[{}F", .{n}) catch "\x1b[F";
    }

    /// Move cursor to absolute column position.
    pub fn cursorHorizontalAbsolute(col: u32) []const u8 {
        return std.fmt.bufPrint(&up_buf, "\x1b[{}G", .{if (col == 0) 1 else col}) catch "\x1b[G";
    }

    /// Set cursor position to specific row and column (1-based).
    pub fn cursorPosition(col: u32, row: u32) []const u8 {
        if (row == 0 and col == 0) return "\x1b[H";
        const r = if (row == 0) 1 else row;
        const c = if (col == 0) 1 else col;
        return std.fmt.bufPrint(&position_buf, "\x1b[{};{}H", .{ r, c }) catch "\x1b[H";
    }

    /// Move cursor to home position (1,1).
    pub const cursorHome = "\x1b[H";

    /// Move cursor forward by n tab stops.
    pub fn cursorHorizontalForwardTab(n: u32) []const u8 {
        if (n <= 1) return "\x1b[I";
        return std.fmt.bufPrint(&up_buf, "\x1b[{}I", .{n}) catch "\x1b[I";
    }

    /// Move cursor backward by n tab stops.
    pub fn cursorBackwardTab(n: u32) []const u8 {
        if (n <= 1) return "\x1b[Z";
        return std.fmt.bufPrint(&up_buf, "\x1b[{}Z", .{n}) catch "\x1b[Z";
    }

    /// Move cursor to absolute row position.
    pub fn verticalPositionAbsolute(row: u32) []const u8 {
        return std.fmt.bufPrint(&up_buf, "\x1b[{}d", .{if (row == 0) 1 else row}) catch "\x1b[d";
    }

    /// Move cursor down by n rows relative to current position.
    pub fn verticalPositionRelative(n: u32) []const u8 {
        if (n <= 1) return "\x1b[e";
        return std.fmt.bufPrint(&up_buf, "\x1b[{}e", .{n}) catch "\x1b[e";
    }

    /// Alternative cursor position setting (same as cursorPosition).
    pub fn horizontalVerticalPosition(col: u32, row: u32) []const u8 {
        const r = if (row == 0) 1 else row;
        const c = if (col == 0) 1 else col;
        return std.fmt.bufPrint(&position_buf, "\x1b[{};{}f", .{ r, c }) catch "\x1b[f";
    }

    /// Move cursor to absolute column position (alternative to cursorHorizontalAbsolute).
    pub fn horizontalPositionAbsolute(col: u32) []const u8 {
        return std.fmt.bufPrint(&up_buf, "\x1b[{}`", .{if (col == 0) 1 else col}) catch "\x1b[`";
    }

    /// Move cursor right by n columns relative to current position.
    pub fn horizontalPositionRelative(n: u32) []const u8 {
        if (n == 0) return "";
        return std.fmt.bufPrint(&up_buf, "\x1b[{}a", .{n}) catch "";
    }

    // ===== CURSOR SAVE/RESTORE =====

    /// Save cursor position (DEC style).
    pub const saveCursor = "\x1b7";

    /// Restore cursor position (DEC style).
    pub const restoreCursor = "\x1b8";

    /// Save current cursor position (SCO style).
    pub const saveCurrentCursorPosition = "\x1b[s";

    /// Restore current cursor position (SCO style).
    pub const restoreCurrentCursorPosition = "\x1b[u";

    // ===== CURSOR STYLE CONTROL =====

    /// Set cursor style/appearance.
    pub fn setCursorStyle(style: CursorStyle) []const u8 {
        return std.fmt.bufPrint(&style_buf, "\x1b[{} q", .{@intFromEnum(style)}) catch "\x1b[0 q";
    }

    /// Set pointer/mouse cursor shape.
    pub fn setPointerShape(allocator: std.mem.Allocator, shape: []const u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "\x1b]22;{s}\x07", .{shape});
    }

    // Common pointer shapes
    pub const PointerShapes = struct {
        pub const default = "default";
        pub const copy = "copy";
        pub const crosshair = "crosshair";
        pub const text = "text";
        pub const wait = "wait";
        pub const ew_resize = "ew-resize";
        pub const n_resize = "n-resize";
        pub const pointer = "pointer";
        pub const help = "help";
        pub const not_allowed = "not-allowed";
        pub const progress = "progress";
        pub const move = "move";
    };

    // ===== CURSOR QUERIES =====

    /// Request cursor position report.
    pub const requestCursorPositionReport = "\x1b[6n";

    /// Request extended cursor position report (includes page number).
    pub const requestExtendedCursorPositionReport = "\x1b[?6n";

    // ===== EDITING OPERATIONS =====

    /// Erase n characters from cursor position.
    pub fn eraseCharacter(n: u32) []const u8 {
        if (n <= 1) return "\x1b[X";
        var buf: [16]u8 = undefined;
        return std.fmt.bufPrint(&buf, "\x1b[{}X", .{n}) catch "\x1b[X";
    }

    // ===== SCROLLING OPERATIONS =====

    /// Reverse index (move cursor up, scroll down if at top).
    pub const reverseIndex = "\x1bM";

    /// Index (move cursor down, scroll up if at bottom).
    pub const index = "\x1bD";

    // ===== UTILITY FUNCTIONS =====

    /// Create a cursor control sequence builder for complex operations.
    pub const Builder = struct {
        buffer: std.ArrayListUnmanaged(u8),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Builder {
            return Builder{
                .buffer = std.ArrayListUnmanaged(u8){},
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Builder) void {
            self.buffer.deinit(self.allocator);
        }

        pub fn clear(self: *Builder) void {
            self.buffer.clearRetainingCapacity();
        }

        pub fn toOwnedSlice(self: *Builder) ![]u8 {
            return self.buffer.toOwnedSlice(self.allocator);
        }

        /// Add cursor movement sequence.
        pub fn moveTo(self: *Builder, col: u32, row: u32) !*Builder {
            try self.buffer.appendSlice(self.allocator, cursorPosition(col, row));
            return self;
        }

        /// Add cursor style change.
        pub fn setStyle(self: *Builder, style: CursorStyle) !*Builder {
            try self.buffer.appendSlice(self.allocator, setCursorStyle(style));
            return self;
        }

        /// Add save cursor operation.
        pub fn save(self: *Builder) !*Builder {
            try self.buffer.appendSlice(self.allocator, saveCursor);
            return self;
        }

        /// Add restore cursor operation.
        pub fn restore(self: *Builder) !*Builder {
            try self.buffer.appendSlice(self.allocator, restoreCursor);
            return self;
        }

        /// Add relative cursor movement.
        pub fn moveBy(self: *Builder, dx: i32, dy: i32) !*Builder {
            if (dy > 0) {
                try self.buffer.appendSlice(self.allocator, cursorDown(@intCast(dy)));
            } else if (dy < 0) {
                try self.buffer.appendSlice(self.allocator, cursorUp(@intCast(-dy)));
            }

            if (dx > 0) {
                try self.buffer.appendSlice(self.allocator, cursorForward(@intCast(dx)));
            } else if (dx < 0) {
                try self.buffer.appendSlice(self.allocator, cursorBackward(@intCast(-dx)));
            }

            return self;
        }
    };
};

// Test the cursor control functionality
test "cursor control sequences" {
    // Test basic movement
    try std.testing.expectEqualStrings("\x1b[5A", CursorControl.cursorUp(5));
    try std.testing.expectEqualStrings("\x1b[A", CursorControl.cursorUp(1));
    try std.testing.expectEqualStrings("\x1b[A", CursorControl.cursorUp(0));

    // Test position setting
    try std.testing.expectEqualStrings("\x1b[10;20H", CursorControl.cursorPosition(20, 10));
    try std.testing.expectEqualStrings("\x1b[H", CursorControl.cursorPosition(0, 0));

    // Test cursor style
    try std.testing.expectEqualStrings("\x1b[2 q", CursorControl.setCursorStyle(.steady_block));
    try std.testing.expectEqualStrings("\x1b[5 q", CursorControl.setCursorStyle(.blinking_bar));

    // Test builder pattern
    var builder = CursorControl.Builder.init(std.testing.allocator);
    defer builder.deinit();

    const b1 = try builder.save();
    const b2 = try b1.moveTo(10, 5);
    const b3 = try b2.setStyle(.steady_underline);
    _ = try b3.restore();

    const result = try builder.toOwnedSlice();
    defer std.testing.allocator.free(result);

    // Should contain save, move, style, and restore sequences
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b7") != null); // save
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[5;10H") != null); // move
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[4 q") != null); // style
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b8") != null); // restore
}

test "cursor style enumeration" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(CursorStyle.blinking_block));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(CursorStyle.steady_block));
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(CursorStyle.steady_bar));
}
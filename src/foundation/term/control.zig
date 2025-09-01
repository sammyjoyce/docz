// Control sequences namespace

const std = @import("std");

/// ANSI escape sequences
pub const ansi = struct {
    // Cursor movement
    pub const cursor_up = "\x1b[A";
    pub const cursor_down = "\x1b[B";
    pub const cursor_forward = "\x1b[C";
    pub const cursor_back = "\x1b[D";
    pub const cursor_next_line = "\x1b[E";
    pub const cursor_prev_line = "\x1b[F";
    pub const cursor_save = "\x1b[s";
    pub const cursor_restore = "\x1b[u";
    pub const cursor_hide = "\x1b[?25l";
    pub const cursor_show = "\x1b[?25h";

    // Screen control
    pub const clear_screen = "\x1b[2J";
    pub const clear_line = "\x1b[2K";
    pub const clear_to_eol = "\x1b[K";
    pub const clear_to_bol = "\x1b[1K";
    pub const scroll_up = "\x1b[S";
    pub const scroll_down = "\x1b[T";

    // Alternate screen
    pub const alt_screen_enable = "\x1b[?1049h";
    pub const alt_screen_disable = "\x1b[?1049l";

    // Styles
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const italic = "\x1b[3m";
    pub const underline = "\x1b[4m";
    pub const blink = "\x1b[5m";
    pub const reverse = "\x1b[7m";
    pub const strikethrough = "\x1b[9m";
};

/// Build cursor movement sequence
pub fn cursorUp(writer: anytype, n: u16) !void {
    if (n == 0) return;
    if (n == 1) {
        try writer.writeAll(ansi.cursor_up);
    } else {
        try writer.print("\x1b[{}A", .{n});
    }
}

pub fn cursorDown(writer: anytype, n: u16) !void {
    if (n == 0) return;
    if (n == 1) {
        try writer.writeAll(ansi.cursor_down);
    } else {
        try writer.print("\x1b[{}B", .{n});
    }
}

pub fn cursorForward(writer: anytype, n: u16) !void {
    if (n == 0) return;
    if (n == 1) {
        try writer.writeAll(ansi.cursor_forward);
    } else {
        try writer.print("\x1b[{}C", .{n});
    }
}

pub fn cursorBack(writer: anytype, n: u16) !void {
    if (n == 0) return;
    if (n == 1) {
        try writer.writeAll(ansi.cursor_back);
    } else {
        try writer.print("\x1b[{}D", .{n});
    }
}

/// Set cursor position (1-indexed)
pub fn setCursorPosition(writer: anytype, row: u16, col: u16) !void {
    try writer.print("\x1b[{};{}H", .{ row, col });
}

/// Set foreground color (8-bit)
pub fn setForeground256(writer: anytype, color: u8) !void {
    try writer.print("\x1b[38;5;{}m", .{color});
}

/// Set background color (8-bit)
pub fn setBackground256(writer: anytype, color: u8) !void {
    try writer.print("\x1b[48;5;{}m", .{color});
}

/// Set foreground color (RGB)
pub fn setForegroundRGB(writer: anytype, r: u8, g: u8, b: u8) !void {
    try writer.print("\x1b[38;2;{};{};{}m", .{ r, g, b });
}

/// Set background color (RGB)
pub fn setBackgroundRGB(writer: anytype, r: u8, g: u8, b: u8) !void {
    try writer.print("\x1b[48;2;{};{};{}m", .{ r, g, b });
}

/// Hyperlink support (OSC 8)
pub fn hyperlink(writer: anytype, url: []const u8, text: []const u8) !void {
    try writer.print("\x1b]8;;{s}\x07{s}\x1b]8;;\x07", .{ url, text });
}

/// Set window title
pub fn setTitle(writer: anytype, title: []const u8) !void {
    try writer.print("\x1b]0;{s}\x07", .{title});
}

/// Ring bell
pub fn bell(writer: anytype) !void {
    try writer.writeAll("\x07");
}

/// Control sequence builder for complex sequences
pub const SequenceBuilder = struct {
    const Self = @This();

    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    pub fn csi(self: *Self) !*Self {
        try self.buffer.appendSlice("\x1b[");
        return self;
    }

    pub fn osc(self: *Self) !*Self {
        try self.buffer.appendSlice("\x1b]");
        return self;
    }

    pub fn param(self: *Self, value: anytype) !*Self {
        try std.fmt.format(self.buffer.writer(), "{}", .{value});
        return self;
    }

    pub fn separator(self: *Self) !*Self {
        try self.buffer.append(';');
        return self;
    }

    pub fn finish(self: *Self, code: u8) ![]const u8 {
        try self.buffer.append(code);
        return self.buffer.items;
    }

    pub fn finishST(self: *Self) ![]const u8 {
        try self.buffer.appendSlice("\x07");
        return self.buffer.items;
    }
};

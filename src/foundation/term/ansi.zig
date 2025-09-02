// ANSI escape codes namespace

const std = @import("std");

// ANSI Color codes
pub const AnsiColor = enum(u8) {
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,
    bright_black = 90,
    bright_red = 91,
    bright_green = 92,
    bright_yellow = 93,
    bright_blue = 94,
    bright_magenta = 95,
    bright_cyan = 96,
    bright_white = 97,
};

// ANSI escape sequences
pub fn reset(writer: anytype) !void {
    try writer.writeAll("\x1b[0m");
}

pub fn setForeground(writer: anytype, color: AnsiColor) !void {
    var buf: [16]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "\x1b[{d}m", .{@intFromEnum(color)});
    _ = try writer.write(s);
}

pub fn setBackground(writer: anytype, color: AnsiColor) !void {
    const bg_code = @intFromEnum(color) + 10; // Background colors are +10 from foreground
    var buf: [16]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "\x1b[{d}m", .{bg_code});
    _ = try writer.write(s);
}

pub fn setBold(writer: anytype, enabled: bool) !void {
    if (enabled) {
        try writer.writeAll("\x1b[1m");
    } else {
        try writer.writeAll("\x1b[22m");
    }
}

pub fn setItalic(writer: anytype, enabled: bool) !void {
    if (enabled) {
        try writer.writeAll("\x1b[3m");
    } else {
        try writer.writeAll("\x1b[23m");
    }
}

pub fn setUnderline(writer: anytype, enabled: bool) !void {
    if (enabled) {
        try writer.writeAll("\x1b[4m");
    } else {
        try writer.writeAll("\x1b[24m");
    }
}

pub fn clearScreen(writer: anytype) !void {
    try writer.writeAll("\x1b[2J");
}

pub fn moveCursor(writer: anytype, row: u32, col: u32) !void {
    var buf: [24]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ row + 1, col + 1 });
    _ = try writer.write(s);
}

pub fn hideCursor(writer: anytype) !void {
    try writer.writeAll("\x1b[?25l");
}

pub fn showCursor(writer: anytype) !void {
    try writer.writeAll("\x1b[?25h");
}

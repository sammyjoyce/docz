//! Color handling for terminal output
//! Provides color representation for different terminal capabilities

const std = @import("std");

/// Color representation supporting various terminal capabilities
pub const Color = union(enum) {
    /// Default terminal color
    default,
    /// 16-color ANSI palette (0-15)
    ansi: u8,
    /// 256-color palette
    ansi256: u8,
    /// 24-bit RGB color
    rgb: struct { r: u8, g: u8, b: u8 },

    pub fn format(
        self: Color,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .default => try writer.writeAll("default"),
            .ansi => |idx| try writer.print("ansi({})", .{idx}),
            .ansi256 => |idx| try writer.print("ansi256({})", .{idx}),
            .rgb => |c| try writer.print("rgb({},{},{})", .{ c.r, c.g, c.b }),
        }
    }

    /// Convert to ANSI escape sequence for foreground color
    pub fn toAnsiFg(self: Color, writer: anytype) !void {
        switch (self) {
            .default => try writer.writeAll("\x1b[39m"),
            .ansi => |idx| {
                if (idx < 8) {
                    try writer.print("\x1b[{}m", .{30 + idx});
                } else if (idx < 16) {
                    try writer.print("\x1b[{}m", .{90 + (idx - 8)});
                }
            },
            .ansi256 => |idx| try writer.print("\x1b[38;5;{}m", .{idx}),
            .rgb => |c| try writer.print("\x1b[38;2;{};{};{}m", .{ c.r, c.g, c.b }),
        }
    }

    /// Convert to ANSI escape sequence for background color
    pub fn toAnsiBg(self: Color, writer: anytype) !void {
        switch (self) {
            .default => try writer.writeAll("\x1b[49m"),
            .ansi => |idx| {
                if (idx < 8) {
                    try writer.print("\x1b[{}m", .{40 + idx});
                } else if (idx < 16) {
                    try writer.print("\x1b[{}m", .{100 + (idx - 8)});
                }
            },
            .ansi256 => |idx| try writer.print("\x1b[48;5;{}m", .{idx}),
            .rgb => |c| try writer.print("\x1b[48;2;{};{};{}m", .{ c.r, c.g, c.b }),
        }
    }
};

/// Common color constants
pub const colors = struct {
    pub const black = Color{ .ansi = 0 };
    pub const red = Color{ .ansi = 1 };
    pub const green = Color{ .ansi = 2 };
    pub const yellow = Color{ .ansi = 3 };
    pub const blue = Color{ .ansi = 4 };
    pub const magenta = Color{ .ansi = 5 };
    pub const cyan = Color{ .ansi = 6 };
    pub const white = Color{ .ansi = 7 };

    pub const bright_black = Color{ .ansi = 8 };
    pub const bright_red = Color{ .ansi = 9 };
    pub const bright_green = Color{ .ansi = 10 };
    pub const bright_yellow = Color{ .ansi = 11 };
    pub const bright_blue = Color{ .ansi = 12 };
    pub const bright_magenta = Color{ .ansi = 13 };
    pub const bright_cyan = Color{ .ansi = 14 };
    pub const bright_white = Color{ .ansi = 15 };
};

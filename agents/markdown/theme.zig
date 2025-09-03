const std = @import("std");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn toAnsi(self: Color, buf: []u8, bg: bool) ![]const u8 {
        const prefix = if (bg) "\x1b[48;2;" else "\x1b[38;2;";
        return std.fmt.bufPrint(buf, "{s}{d};{d};{d}m", .{ prefix, self.r, self.g, self.b });
    }

    pub const RESET = "\x1b[0m";
};

pub const Theme = struct {
    bg_primary: Color,
    bg_secondary: Color,
    fg_primary: Color,
    fg_secondary: Color,
    border: Color,
    border_focused: Color,
};

pub const DARK_THEME = Theme{
    .bg_primary = Color{ .r = 30, .g = 30, .b = 30 },
    .bg_secondary = Color{ .r = 37, .g = 37, .b = 37 },
    .fg_primary = Color{ .r = 212, .g = 212, .b = 212 },
    .fg_secondary = Color{ .r = 180, .g = 180, .b = 180 },
    .border = Color{ .r = 68, .g = 68, .b = 68 },
    .border_focused = Color{ .r = 0, .g = 120, .b = 215 },
};

pub const Style = struct {
    theme: *const Theme,

    pub fn init(theme: *const Theme) Style {
        return Style{ .theme = theme };
    }

    pub fn colorFg(_: Style, writer: anytype, color: Color) !void {
        var buf: [32]u8 = undefined;
        const ansi = try color.toAnsi(&buf, false);
        try writer.print("{s}", .{ansi});
    }

    pub fn reset(writer: anytype) !void {
        try writer.print("{s}", .{Color.RESET});
    }

    pub fn primary(self: Style, writer: anytype, text: []const u8) !void {
        try self.colorFg(writer, self.theme.fg_primary);
        try writer.print("{s}", .{text});
        try self.reset(writer);
    }
};

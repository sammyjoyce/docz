//! Shared UI components that work across CLI and TUI contexts

const std = @import("std");

// Re-export common UI components
pub const components = @import("../components/mod.zig");
pub const themes = @import("../cli/themes/mod.zig");

// Common UI interfaces
pub const Component = struct {
    /// Render the component to a text buffer
    render: *const fn (self: *anyopaque, allocator: std.mem.Allocator) anyerror![]const u8,

    /// Update component state
    update: ?*const fn (self: *anyopaque, event: Event) anyerror!void = null,

    /// Get component dimensions
    getDimensions: ?*const fn (self: *anyopaque) Dimensions = null,
};

pub const Event = union(enum) {
    key: struct { code: u8, modifiers: u8 },
    mouse: struct { x: u16, y: u16, button: u8 },
    resize: struct { width: u16, height: u16 },
    custom: std.json.Value,
};

pub const Dimensions = struct {
    width: u16,
    height: u16,
    minWidth: u16 = 0,
    minHeight: u16 = 0,
    maxWidth: u16 = std.math.maxInt(u16),
    maxHeight: u16 = std.math.maxInt(u16),
};

// Layout managers
pub const Layout = enum {
    vertical,
    horizontal,
    grid,
    absolute,
};

pub const LayoutConfig = struct {
    layoutType: Layout,
    spacing: u8 = 0,
    padding: u8 = 0,

    pub fn arrange(self: LayoutConfig, comps: []Component, area: Dimensions) ![]Dimensions {
        // Implementation would calculate positions for each component
        _ = self;
        _ = comps;
        _ = area;
        return error.NotImplemented;
    }
};

// Common UI utilities
pub const Utils = struct {
    /// Wrap text to fit within a given width
    pub fn wrapText(allocator: std.mem.Allocator, text: []const u8, width: usize) ![][]const u8 {
        var lines = std.ArrayList([]const u8).init(allocator);
        defer lines.deinit();

        var current_line = std.ArrayList(u8).init(allocator);
        defer current_line.deinit();

        var words = std.mem.tokenize(u8, text, " ");
        while (words.next()) |word| {
            if (current_line.items.len + word.len + 1 > width) {
                try lines.append(try allocator.dupe(u8, current_line.items));
                current_line.clearRetainingCapacity();
            }

            if (current_line.items.len > 0) {
                try current_line.append(' ');
            }
            try current_line.appendSlice(word);
        }

        if (current_line.items.len > 0) {
            try lines.append(try allocator.dupe(u8, current_line.items));
        }

        return try lines.toOwnedSlice();
    }

    /// Truncate text with ellipsis if it exceeds max length
    pub fn truncateText(allocator: std.mem.Allocator, text: []const u8, maxLen: usize) ![]const u8 {
        if (text.len <= maxLen) {
            return try allocator.dupe(u8, text);
        }

        const ellipsis = "...";
        if (maxLen <= ellipsis.len) {
            return try allocator.dupe(u8, ellipsis[0..maxLen]);
        }

        var result = try allocator.alloc(u8, maxLen);
        @memcpy(result[0 .. maxLen - ellipsis.len], text[0 .. maxLen - ellipsis.len]);
        @memcpy(result[maxLen - ellipsis.len ..], ellipsis);
        return result;
    }

    /// Center text within a given width
    pub fn centerText(allocator: std.mem.Allocator, text: []const u8, width: usize) ![]const u8 {
        if (text.len >= width) {
            return try allocator.dupe(u8, text);
        }

        const padding = (width - text.len) / 2;
        var result = try allocator.alloc(u8, width);
        @memset(result, ' ');
        @memcpy(result[padding .. padding + text.len], text);
        return result;
    }
};

// Style system that works across contexts
pub const Style = struct {
    foreground: ?Color = null,
    background: ?Color = null,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    dim: bool = false,
    blink: bool = false,
    reverse: bool = false,
    strike: bool = false,
};

pub const Color = union(enum) {
    named: NamedColor,
    indexed: u8,
    rgb: struct { r: u8, g: u8, b: u8 },
};

pub const NamedColor = enum {
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    brightBlack,
    BRIGHT_RED,
    BRIGHT_GREEN,
    bright_yellow,
    BRIGHT_BLUE,
    BRIGHT_MAGENTA,
    BRIGHT_CYAN,
    BRIGHT_WHITE,
};

/// Apply style to text (returns ANSI-styled text)
pub fn applyStyle(allocator: std.mem.Allocator, text: []const u8, style: Style) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    // Add ANSI escape codes based on style
    if (style.bold) try result.appendSlice("\x1b[1m");
    if (style.italic) try result.appendSlice("\x1b[3m");
    if (style.underline) try result.appendSlice("\x1b[4m");
    if (style.dim) try result.appendSlice("\x1b[2m");
    if (style.blink) try result.appendSlice("\x1b[5m");
    if (style.reverse) try result.appendSlice("\x1b[7m");
    if (style.strike) try result.appendSlice("\x1b[9m");

    // Add color codes
    if (style.foreground) |fg| {
        switch (fg) {
            .named => |color| {
                const code = @intFromEnum(color);
                if (code < 8) {
                    try result.writer().print("\x1b[{}m", .{30 + code});
                } else {
                    try result.writer().print("\x1b[{}m", .{82 + code});
                }
            },
            .indexed => |idx| try result.writer().print("\x1b[38;5;{}m", .{idx}),
            .rgb => |rgb| try result.writer().print("\x1b[38;2;{};{};{}m", .{ rgb.r, rgb.g, rgb.b }),
        }
    }

    if (style.background) |bg| {
        switch (bg) {
            .named => |color| {
                const code = @intFromEnum(color);
                if (code < 8) {
                    try result.writer().print("\x1b[{}m", .{40 + code});
                } else {
                    try result.writer().print("\x1b[{}m", .{92 + code});
                }
            },
            .indexed => |idx| try result.writer().print("\x1b[48;5;{}m", .{idx}),
            .rgb => |rgb| try result.writer().print("\x1b[48;2;{};{};{}m", .{ rgb.r, rgb.g, rgb.b }),
        }
    }

    try result.appendSlice(text);

    // Reset at the end
    try result.appendSlice("\x1b[0m");

    return try result.toOwnedSlice();
}

//! TUI Style definitions for widgets and rendering

const std = @import("std");
const term = @import("../../term.zig");

/// Style configuration for text rendering
pub const Style = struct {
    /// Foreground color
    fg: ?term.color.Color = null,
    /// Background color
    bg: ?term.color.Color = null,
    /// Text attributes
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    dim: bool = false,
    blink: bool = false,
    reverse: bool = false,
    hidden: bool = false,
    strikethrough: bool = false,

    /// Create a default style
    pub fn default() Style {
        return .{};
    }

    /// Create a style with foreground color
    pub fn withFg(color: term.color.Color) Style {
        return .{ .fg = color };
    }

    /// Create a style with background color
    pub fn withBg(color: term.color.Color) Style {
        return .{ .bg = color };
    }

    /// Create a bold style
    pub fn withBold() Style {
        return .{ .bold = true };
    }

    /// Merge two styles, with other taking precedence
    pub fn merge(self: Style, other: Style) Style {
        return .{
            .fg = other.fg orelse self.fg,
            .bg = other.bg orelse self.bg,
            .bold = other.bold or self.bold,
            .italic = other.italic or self.italic,
            .underline = other.underline or self.underline,
            .dim = other.dim or self.dim,
            .blink = other.blink or self.blink,
            .reverse = other.reverse or self.reverse,
            .hidden = other.hidden or self.hidden,
            .strikethrough = other.strikethrough or self.strikethrough,
        };
    }

    /// Apply style to a writer
    pub fn apply(self: Style, writer: anytype) !void {
        if (self.fg) |color| {
            try color.toAnsiFg(writer);
        }
        if (self.bg) |color| {
            try color.toAnsiBg(writer);
        }
        if (self.bold) {
            try writer.writeAll("\x1b[1m");
        }
        if (self.italic) {
            try writer.writeAll("\x1b[3m");
        }
        if (self.underline) {
            try writer.writeAll("\x1b[4m");
        }
        if (self.dim) {
            try writer.writeAll("\x1b[2m");
        }
        if (self.blink) {
            try writer.writeAll("\x1b[5m");
        }
        if (self.reverse) {
            try writer.writeAll("\x1b[7m");
        }
        if (self.hidden) {
            try writer.writeAll("\x1b[8m");
        }
        if (self.strikethrough) {
            try writer.writeAll("\x1b[9m");
        }
    }

    /// Reset style
    pub fn reset(writer: anytype) !void {
        try writer.writeAll("\x1b[0m");
    }
};

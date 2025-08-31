//! Stylize trait pattern for fluent, chainable styling APIs
//! Inspired by Ratatui's approach but adapted for Zig's type system
//!
//! This module provides ergonomic styling interfaces that enable:
//! - Method chaining for style composition
//! - Type-safe style builders
//! - Style merging and patching utilities
//! - Integration with existing Style structures

const std = @import("std");
const renderer = @import("renderer.zig");
const term = @import("../../term.zig");
const cell_buffer = term.cellbuf;

/// Core Style type that unifies different style representations
pub const Style = struct {
    fg_color: ?Color = null,
    bg_color: ?Color = null,
    bold: bool = false,
    faint: bool = false,
    italic: bool = false,
    underline: bool = false,
    strikethrough: bool = false,
    blink: bool = false,
    reverse: bool = false,
    conceal: bool = false,
    underline_style: UnderlineStyle = .none,
    underline_color: ?Color = null,

    pub const Color = union(enum) {
        default,
        ansi: u8, // 0-15 ANSI colors
        palette: u8, // 0-255 palette colors
        rgb: RGB, // RGB truecolor

        pub const RGB = struct {
            r: u8,
            g: u8,
            b: u8,
        };

        /// Create color from hex string
        pub fn fromHex(hex: []const u8) !Color {
            if (hex.len < 6) return error.InvalidHexColor;
            const start = if (hex[0] == '#') 1 else 0;
            const r = try std.fmt.parseInt(u8, hex[start .. start + 2], 16);
            const g = try std.fmt.parseInt(u8, hex[start + 2 .. start + 4], 16);
            const b = try std.fmt.parseInt(u8, hex[start + 4 .. start + 6], 16);
            return Color{ .rgb = .{ .r = r, .g = g, .b = b } };
        }
    };

    pub const UnderlineStyle = enum(u8) {
        none = 0,
        single = 1,
        double = 2,
        curly = 3,
        dotted = 4,
        dashed = 5,
    };

    /// Merge two styles, with `other` taking precedence
    pub fn merge(self: Style, other: Style) Style {
        return Style{
            .fg_color = other.fg_color orelse self.fg_color,
            .bg_color = other.bg_color orelse self.bg_color,
            .bold = other.bold or self.bold,
            .faint = other.faint or self.faint,
            .italic = other.italic or self.italic,
            .underline = other.underline or self.underline,
            .strikethrough = other.strikethrough or self.strikethrough,
            .blink = other.blink or self.blink,
            .reverse = other.reverse or self.reverse,
            .conceal = other.conceal or self.conceal,
            .underline_style = if (other.underline_style != .none) other.underline_style else self.underline_style,
            .underline_color = other.underline_color orelse self.underline_color,
        };
    }

    /// Patch style with specific attributes
    pub fn patch(self: Style, attrs: StylePatch) Style {
        var result = self;
        if (attrs.fg_color) |color| result.fg_color = color;
        if (attrs.bg_color) |color| result.bg_color = color;
        if (attrs.bold) |v| result.bold = v;
        if (attrs.faint) |v| result.faint = v;
        if (attrs.italic) |v| result.italic = v;
        if (attrs.underline) |v| result.underline = v;
        if (attrs.strikethrough) |v| result.strikethrough = v;
        if (attrs.blink) |v| result.blink = v;
        if (attrs.reverse) |v| result.reverse = v;
        if (attrs.conceal) |v| result.conceal = v;
        if (attrs.underline_style) |v| result.underline_style = v;
        if (attrs.underline_color) |v| result.underline_color = v;
        return result;
    }

    /// Convert to renderer.Style for TUI rendering
    pub fn toRendererStyle(self: Style) renderer.Style {
        return renderer.Style{
            .fg_color = if (self.fg_color) |c| switch (c) {
                .default => null,
                .ansi => |v| renderer.Style.Color{ .ansi = v },
                .palette => |v| renderer.Style.Color{ .palette = v },
                .rgb => |rgb| renderer.Style.Color{ .rgb = .{ .r = rgb.r, .g = rgb.g, .b = rgb.b } },
            } else null,
            .bg_color = if (self.bg_color) |c| switch (c) {
                .default => null,
                .ansi => |v| renderer.Style.Color{ .ansi = v },
                .palette => |v| renderer.Style.Color{ .palette = v },
                .rgb => |rgb| renderer.Style.Color{ .rgb = .{ .r = rgb.r, .g = rgb.g, .b = rgb.b } },
            } else null,
            .bold = self.bold,
            .italic = self.italic,
            .underline = self.underline,
            .strikethrough = self.strikethrough,
        };
    }

    /// Convert to cell_buffer.Style for cell-based rendering
    pub fn toCellStyle(self: Style) cell_buffer.Style {
        return cell_buffer.Style{
            .fg = if (self.fg_color) |c| switch (c) {
                .default => cell_buffer.Color.default,
                .ansi => |v| cell_buffer.Color{ .ansi = v },
                .palette => |v| cell_buffer.Color{ .ansi256 = v },
                .rgb => |rgb| cell_buffer.Color{ .rgb = .{ .r = rgb.r, .g = rgb.g, .b = rgb.b } },
            } else cell_buffer.Color.default,
            .bg = if (self.bg_color) |c| switch (c) {
                .default => cell_buffer.Color.default,
                .ansi => |v| cell_buffer.Color{ .ansi = v },
                .palette => |v| cell_buffer.Color{ .ansi256 = v },
                .rgb => |rgb| cell_buffer.Color{ .rgb = .{ .r = rgb.r, .g = rgb.g, .b = rgb.b } },
            } else cell_buffer.Color.default,
            .ulColor = if (self.underline_color) |c| switch (c) {
                .default => cell_buffer.Color.default,
                .ansi => |v| cell_buffer.Color{ .ansi = v },
                .palette => |v| cell_buffer.Color{ .ansi256 = v },
                .rgb => |rgb| cell_buffer.Color{ .rgb = .{ .r = rgb.r, .g = rgb.g, .b = rgb.b } },
            } else cell_buffer.Color.default,
            .attrs = .{
                .bold = self.bold,
                .faint = self.faint,
                .italic = self.italic,
                .slowBlink = self.blink,
                .rapidBlink = false,
                .reverse = self.reverse,
                .conceal = self.conceal,
                .strikethrough = self.strikethrough,
            },
            .ulStyle = @as(cell_buffer.UnderlineStyle, @enumFromInt(@intFromEnum(self.underline_style))),
        };
    }
};

/// Patch structure for partial style updates
pub const StylePatch = struct {
    fg_color: ?Style.Color = null,
    bg_color: ?Style.Color = null,
    bold: ?bool = null,
    faint: ?bool = null,
    italic: ?bool = null,
    underline: ?bool = null,
    strikethrough: ?bool = null,
    blink: ?bool = null,
    reverse: ?bool = null,
    conceal: ?bool = null,
    underline_style: ?Style.UnderlineStyle = null,
    underline_color: ?Style.Color = null,
};

/// Stylize trait for fluent styling APIs
pub fn Stylize(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Get the current style of the object
        pub fn getStyle(self: *const T) Style {
            if (@hasDecl(T, "style")) {
                if (@TypeOf(T.style) == Style) {
                    return self.style;
                } else if (@hasDecl(@TypeOf(T.style), "toStyle")) {
                    return self.style.toStyle();
                }
            }
            return Style{};
        }

        /// Set the style of the object
        pub fn setStyle(self: *T, style: Style) *T {
            if (@hasDecl(T, "style")) {
                if (@TypeOf(T.style) == Style) {
                    self.style = style;
                } else if (@hasDecl(@TypeOf(T.style), "fromStyle")) {
                    self.style = @TypeOf(T.style).fromStyle(style);
                }
            }
            return self;
        }

        /// Merge a style with the current style
        pub fn styled(self: *T, style: Style) *T {
            const current = self.getStyle();
            return self.setStyle(current.merge(style));
        }

        /// Set foreground color
        pub fn fg(self: *T, color: Style.Color) *T {
            var current = self.getStyle();
            current.fg_color = color;
            return self.setStyle(current);
        }

        /// Set background color
        pub fn bg(self: *T, color: Style.Color) *T {
            var current = self.getStyle();
            current.bg_color = color;
            return self.setStyle(current);
        }

        /// Set bold
        pub fn bold(self: *T) *T {
            var current = self.getStyle();
            current.bold = true;
            return self.setStyle(current);
        }

        /// Set faint/dim
        pub fn faint(self: *T) *T {
            var current = self.getStyle();
            current.faint = true;
            return self.setStyle(current);
        }

        /// Set italic
        pub fn italic(self: *T) *T {
            var current = self.getStyle();
            current.italic = true;
            return self.setStyle(current);
        }

        /// Set underline
        pub fn underline(self: *T) *T {
            var current = self.getStyle();
            current.underline = true;
            return self.setStyle(current);
        }

        /// Set strikethrough
        pub fn strikethrough(self: *T) *T {
            var current = self.getStyle();
            current.strikethrough = true;
            return self.setStyle(current);
        }

        /// Set blink
        pub fn blink(self: *T) *T {
            var current = self.getStyle();
            current.blink = true;
            return self.setStyle(current);
        }

        /// Set reverse/inverse video
        pub fn reverse(self: *T) *T {
            var current = self.getStyle();
            current.reverse = true;
            return self.setStyle(current);
        }

        /// Set concealed/hidden
        pub fn conceal(self: *T) *T {
            var current = self.getStyle();
            current.conceal = true;
            return self.setStyle(current);
        }

        // Color helper methods
        pub fn black(self: *T) *T {
            return self.fg(Style.Color{ .ansi = 0 });
        }
        pub fn red(self: *T) *T {
            return self.fg(Style.Color{ .ansi = 1 });
        }
        pub fn green(self: *T) *T {
            return self.fg(Style.Color{ .ansi = 2 });
        }
        pub fn yellow(self: *T) *T {
            return self.fg(Style.Color{ .ansi = 3 });
        }
        pub fn blue(self: *T) *T {
            return self.fg(Style.Color{ .ansi = 4 });
        }
        pub fn magenta(self: *T) *T {
            return self.fg(Style.Color{ .ansi = 5 });
        }
        pub fn cyan(self: *T) *T {
            return self.fg(Style.Color{ .ansi = 6 });
        }
        pub fn white(self: *T) *T {
            return self.fg(Style.Color{ .ansi = 7 });
        }
        pub fn gray(self: *T) *T {
            return self.fg(Style.Color{ .ansi = 8 });
        }

        pub fn onBlack(self: *T) *T {
            return self.bg(Style.Color{ .ansi = 0 });
        }
        pub fn onRed(self: *T) *T {
            return self.bg(Style.Color{ .ansi = 1 });
        }
        pub fn onGreen(self: *T) *T {
            return self.bg(Style.Color{ .ansi = 2 });
        }
        pub fn onYellow(self: *T) *T {
            return self.bg(Style.Color{ .ansi = 3 });
        }
        pub fn onBlue(self: *T) *T {
            return self.bg(Style.Color{ .ansi = 4 });
        }
        pub fn onMagenta(self: *T) *T {
            return self.bg(Style.Color{ .ansi = 5 });
        }
        pub fn onCyan(self: *T) *T {
            return self.bg(Style.Color{ .ansi = 6 });
        }
        pub fn onWhite(self: *T) *T {
            return self.bg(Style.Color{ .ansi = 7 });
        }

        /// Set RGB foreground color
        pub fn rgb(self: *T, r: u8, g: u8, b: u8) *T {
            return self.fg(Style.Color{ .rgb = .{ .r = r, .g = g, .b = b } });
        }

        /// Set RGB background color
        pub fn on_rgb(self: *T, r: u8, g: u8, b: u8) *T {
            return self.bg(Style.Color{ .rgb = .{ .r = r, .g = g, .b = b } });
        }

        /// Set hex foreground color
        pub fn hex(self: *T, hex_str: []const u8) *T {
            const color = Style.Color.fromHex(hex_str) catch return self;
            return self.fg(color);
        }

        /// Set hex background color
        pub fn on_hex(self: *T, hex_str: []const u8) *T {
            const color = Style.Color.fromHex(hex_str) catch return self;
            return self.bg(color);
        }

        /// Reset all styles
        pub fn reset(self: *T) *T {
            return self.setStyle(Style{});
        }

        /// Apply a style patch
        pub fn patch(self: *T, style_patch: StylePatch) *T {
            const current = self.getStyle();
            return self.setStyle(current.patch(style_patch));
        }
    };
}

/// StyleBuilder for creating complex styles step by step
pub const StyleBuilder = struct {
    style: Style = Style{},

    pub fn init() StyleBuilder {
        return StyleBuilder{};
    }

    pub fn fg(self: *StyleBuilder, color: Style.Color) *StyleBuilder {
        self.style.fg_color = color;
        return self;
    }

    pub fn bg(self: *StyleBuilder, color: Style.Color) *StyleBuilder {
        self.style.bg_color = color;
        return self;
    }

    pub fn bold(self: *StyleBuilder) *StyleBuilder {
        self.style.bold = true;
        return self;
    }

    pub fn italic(self: *StyleBuilder) *StyleBuilder {
        self.style.italic = true;
        return self;
    }

    pub fn underline(self: *StyleBuilder) *StyleBuilder {
        self.style.underline = true;
        return self;
    }

    pub fn build(self: StyleBuilder) Style {
        return self.style;
    }

    // Include all the color helpers from Stylize
    pub fn black(self: *StyleBuilder) *StyleBuilder {
        return self.fg(Style.Color{ .ansi = 0 });
    }
    pub fn red(self: *StyleBuilder) *StyleBuilder {
        return self.fg(Style.Color{ .ansi = 1 });
    }
    pub fn green(self: *StyleBuilder) *StyleBuilder {
        return self.fg(Style.Color{ .ansi = 2 });
    }
    pub fn yellow(self: *StyleBuilder) *StyleBuilder {
        return self.fg(Style.Color{ .ansi = 3 });
    }
    pub fn blue(self: *StyleBuilder) *StyleBuilder {
        return self.fg(Style.Color{ .ansi = 4 });
    }
    pub fn magenta(self: *StyleBuilder) *StyleBuilder {
        return self.fg(Style.Color{ .ansi = 5 });
    }
    pub fn cyan(self: *StyleBuilder) *StyleBuilder {
        return self.fg(Style.Color{ .ansi = 6 });
    }
    pub fn white(self: *StyleBuilder) *StyleBuilder {
        return self.fg(Style.Color{ .ansi = 7 });
    }

    pub fn onBlack(self: *StyleBuilder) *StyleBuilder {
        return self.bg(Style.Color{ .ansi = 0 });
    }
    pub fn onRed(self: *StyleBuilder) *StyleBuilder {
        return self.bg(Style.Color{ .ansi = 1 });
    }
    pub fn onGreen(self: *StyleBuilder) *StyleBuilder {
        return self.bg(Style.Color{ .ansi = 2 });
    }
    pub fn onYellow(self: *StyleBuilder) *StyleBuilder {
        return self.bg(Style.Color{ .ansi = 3 });
    }
    pub fn onBlue(self: *StyleBuilder) *StyleBuilder {
        return self.bg(Style.Color{ .ansi = 4 });
    }
    pub fn onMagenta(self: *StyleBuilder) *StyleBuilder {
        return self.bg(Style.Color{ .ansi = 5 });
    }
    pub fn onCyan(self: *StyleBuilder) *StyleBuilder {
        return self.bg(Style.Color{ .ansi = 6 });
    }
    pub fn onWhite(self: *StyleBuilder) *StyleBuilder {
        return self.bg(Style.Color{ .ansi = 7 });
    }
};

/// Example widget that implements Stylize
pub const StyledText = struct {
    content: []const u8,
    style: Style = Style{},

    // Include Stylize methods manually
    pub fn getStyle(self: *const StyledText) Style {
        return self.style;
    }

    pub fn setStyle(self: *StyledText, style: Style) *StyledText {
        self.style = style;
        return self;
    }

    pub fn styled(self: *StyledText, style: Style) *StyledText {
        const current = self.getStyle();
        return self.setStyle(current.merge(style));
    }

    pub fn fg(self: *StyledText, color: Style.Color) *StyledText {
        var current = self.getStyle();
        current.fg_color = color;
        return self.setStyle(current);
    }

    pub fn bg(self: *StyledText, color: Style.Color) *StyledText {
        var current = self.getStyle();
        current.bg_color = color;
        return self.setStyle(current);
    }

    pub fn bold(self: *StyledText) *StyledText {
        var current = self.getStyle();
        current.bold = true;
        return self.setStyle(current);
    }

    pub fn faint(self: *StyledText) *StyledText {
        var current = self.getStyle();
        current.faint = true;
        return self.setStyle(current);
    }

    pub fn italic(self: *StyledText) *StyledText {
        var current = self.getStyle();
        current.italic = true;
        return self.setStyle(current);
    }

    pub fn underline(self: *StyledText) *StyledText {
        var current = self.getStyle();
        current.underline = true;
        return self.setStyle(current);
    }

    pub fn strikethrough(self: *StyledText) *StyledText {
        var current = self.getStyle();
        current.strikethrough = true;
        return self.setStyle(current);
    }

    pub fn blink(self: *StyledText) *StyledText {
        var current = self.getStyle();
        current.blink = true;
        return self.setStyle(current);
    }

    pub fn reverse(self: *StyledText) *StyledText {
        var current = self.getStyle();
        current.reverse = true;
        return self.setStyle(current);
    }

    pub fn conceal(self: *StyledText) *StyledText {
        var current = self.getStyle();
        current.conceal = true;
        return self.setStyle(current);
    }

    pub fn black(self: *StyledText) *StyledText {
        return self.fg(Style.Color{ .ansi = 0 });
    }
    pub fn red(self: *StyledText) *StyledText {
        return self.fg(Style.Color{ .ansi = 1 });
    }
    pub fn green(self: *StyledText) *StyledText {
        return self.fg(Style.Color{ .ansi = 2 });
    }
    pub fn yellow(self: *StyledText) *StyledText {
        return self.fg(Style.Color{ .ansi = 3 });
    }
    pub fn blue(self: *StyledText) *StyledText {
        return self.fg(Style.Color{ .ansi = 4 });
    }
    pub fn magenta(self: *StyledText) *StyledText {
        return self.fg(Style.Color{ .ansi = 5 });
    }
    pub fn cyan(self: *StyledText) *StyledText {
        return self.fg(Style.Color{ .ansi = 6 });
    }
    pub fn white(self: *StyledText) *StyledText {
        return self.fg(Style.Color{ .ansi = 7 });
    }
    pub fn gray(self: *StyledText) *StyledText {
        return self.fg(Style.Color{ .ansi = 8 });
    }

    pub fn onBlack(self: *StyledText) *StyledText {
        return self.bg(Style.Color{ .ansi = 0 });
    }
    pub fn onRed(self: *StyledText) *StyledText {
        return self.bg(Style.Color{ .ansi = 1 });
    }
    pub fn onGreen(self: *StyledText) *StyledText {
        return self.bg(Style.Color{ .ansi = 2 });
    }
    pub fn onYellow(self: *StyledText) *StyledText {
        return self.bg(Style.Color{ .ansi = 3 });
    }
    pub fn onBlue(self: *StyledText) *StyledText {
        return self.bg(Style.Color{ .ansi = 4 });
    }
    pub fn onMagenta(self: *StyledText) *StyledText {
        return self.bg(Style.Color{ .ansi = 5 });
    }
    pub fn onCyan(self: *StyledText) *StyledText {
        return self.bg(Style.Color{ .ansi = 6 });
    }
    pub fn onWhite(self: *StyledText) *StyledText {
        return self.bg(Style.Color{ .ansi = 7 });
    }

    pub fn rgb(self: *StyledText, r: u8, g: u8, b: u8) *StyledText {
        return self.fg(Style.Color{ .rgb = .{ .r = r, .g = g, .b = b } });
    }

    pub fn on_rgb(self: *StyledText, r: u8, g: u8, b: u8) *StyledText {
        return self.bg(Style.Color{ .rgb = .{ .r = r, .g = g, .b = b } });
    }

    pub fn hex(self: *StyledText, hex_str: []const u8) *StyledText {
        const color = Style.Color.fromHex(hex_str) catch return self;
        return self.fg(color);
    }

    pub fn on_hex(self: *StyledText, hex_str: []const u8) *StyledText {
        const color = Style.Color.fromHex(hex_str) catch return self;
        return self.bg(color);
    }

    pub fn reset(self: *StyledText) *StyledText {
        return self.setStyle(Style{});
    }

    pub fn patch(self: *StyledText, style_patch: StylePatch) *StyledText {
        const current = self.getStyle();
        return self.setStyle(current.patch(style_patch));
    }

    pub fn init(text: []const u8) StyledText {
        return StyledText{ .content = text };
    }
};

// Tests
test "style merging" {
    const style1 = Style{ .fg_color = Style.Color{ .ansi = 1 }, .bold = true };
    const style2 = Style{ .bg_color = Style.Color{ .ansi = 2 }, .italic = true };
    const merged = style1.merge(style2);

    try std.testing.expect(merged.fg_color.?.ansi == 1);
    try std.testing.expect(merged.bg_color.?.ansi == 2);
    try std.testing.expect(merged.bold == true);
    try std.testing.expect(merged.italic == true);
}

test "style builder" {
    const style = StyleBuilder.init()
        .red()
        .on_blue()
        .bold()
        .italic()
        .build();

    try std.testing.expect(style.fg_color.?.ansi == 1);
    try std.testing.expect(style.bg_color.?.ansi == 4);
    try std.testing.expect(style.bold == true);
    try std.testing.expect(style.italic == true);
}

test "stylize trait" {
    var text = StyledText.init("Hello");
    _ = text.red().bold().italic();

    try std.testing.expect(text.style.fg_color.?.ansi == 1);
    try std.testing.expect(text.style.bold == true);
    try std.testing.expect(text.style.italic == true);
}

test "hex color parsing" {
    const color1 = try Style.Color.fromHex("#FF5733");
    try std.testing.expect(color1.rgb.r == 255);
    try std.testing.expect(color1.rgb.g == 87);
    try std.testing.expect(color1.rgb.b == 51);

    const color2 = try Style.Color.fromHex("00FF00");
    try std.testing.expect(color2.rgb.r == 0);
    try std.testing.expect(color2.rgb.g == 255);
    try std.testing.expect(color2.rgb.b == 0);
}

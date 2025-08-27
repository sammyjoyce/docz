//! Block widget - A container that can wrap content with borders, titles, and padding
//! Provides consistent framing for other widgets and content areas

const std = @import("std");
const Bounds = @import("../../core/bounds.zig").Bounds;
const Color = @import("../../themes/default.zig").Color;

/// Border style for the block
pub const BorderStyle = enum {
    none, // No border
    single, // Single line border ─│┌┐└┘
    double, // Double line border ═║╔╗╚╝
    rounded, // Rounded corners ─│╭╮╰╯
    thick, // Thick line border ━┃┏┓┗┛
    dashed, // Dashed line border ╌╎
    dotted, // Dotted line border ⋯⋮
    ascii, // ASCII border -|+++
};

/// Title alignment within the border
pub const TitleAlignment = enum {
    left,
    center,
    right,
};

/// Title position on the border
pub const TitlePosition = enum { top, bottom, inside };

/// Padding configuration
pub const Padding = struct {
    top: u8 = 0,
    right: u8 = 0,
    bottom: u8 = 0,
    left: u8 = 0,

    /// Create uniform padding
    pub fn uniform(value: u8) Padding {
        return .{
            .top = value,
            .right = value,
            .bottom = value,
            .left = value,
        };
    }

    /// Create symmetric padding (vertical, horizontal)
    pub fn symmetric(vertical: u8, horizontal: u8) Padding {
        return .{
            .top = vertical,
            .bottom = vertical,
            .left = horizontal,
            .right = horizontal,
        };
    }
};

/// Block widget for wrapping content with borders and titles
pub const Block = struct {
    // Configuration
    bounds: Bounds,
    border_style: BorderStyle,
    border_color: Color,
    background_color: ?Color,
    padding: Padding,

    // Title configuration
    title: ?[]const u8,
    title_alignment: TitleAlignment,
    title_position: TitlePosition,
    title_color: Color,

    // Subtitle configuration
    subtitle: ?[]const u8,
    subtitle_alignment: TitleAlignment,
    subtitle_color: Color,

    // Render callback for content
    render_content: ?*const fn (inner_bounds: Bounds) void,

    /// Initialize a new Block with default settings
    pub fn init(bounds: Bounds) Block {
        return .{
            .bounds = bounds,
            .border_style = .single,
            .border_color = Color.WHITE,
            .background_color = null,
            .padding = Padding{},
            .title = null,
            .title_alignment = .center,
            .title_position = .top,
            .title_color = Color.BRIGHT_WHITE,
            .subtitle = null,
            .subtitle_alignment = .center,
            .subtitle_color = Color.GRAY,
            .render_content = null,
        };
    }

    /// Set the border style
    pub fn withBorderStyle(self: Block, style: BorderStyle) Block {
        var new_block = self;
        new_block.border_style = style;
        return new_block;
    }

    /// Set the border color
    pub fn withBorderColor(self: Block, color: Color) Block {
        var new_block = self;
        new_block.border_color = color;
        return new_block;
    }

    /// Set the background color
    pub fn withBackground(self: Block, color: Color) Block {
        var new_block = self;
        new_block.background_color = color;
        return new_block;
    }

    /// Set the padding
    pub fn withPadding(self: Block, padding: Padding) Block {
        var new_block = self;
        new_block.padding = padding;
        return new_block;
    }

    /// Set the title
    pub fn withTitle(self: Block, title: []const u8, alignment: TitleAlignment, position: TitlePosition) Block {
        var new_block = self;
        new_block.title = title;
        new_block.title_alignment = alignment;
        new_block.title_position = position;
        return new_block;
    }

    /// Set the title color
    pub fn withTitleColor(self: Block, color: Color) Block {
        var new_block = self;
        new_block.title_color = color;
        return new_block;
    }

    /// Set the subtitle (always appears at bottom)
    pub fn withSubtitle(self: Block, subtitle: []const u8, alignment: TitleAlignment) Block {
        var new_block = self;
        new_block.subtitle = subtitle;
        new_block.subtitle_alignment = alignment;
        return new_block;
    }

    /// Set the content render function
    pub fn withContent(self: Block, render_fn: *const fn (Bounds) void) Block {
        var new_block = self;
        new_block.render_content = render_fn;
        return new_block;
    }

    /// Get the inner bounds (accounting for border and padding)
    pub fn getInnerBounds(self: *const Block) Bounds {
        var inner = self.bounds;

        // Account for border
        if (self.border_style != .none) {
            inner.x += 1;
            inner.y += 1;
            inner.width = inner.width.saturatingSub(2);
            inner.height = inner.height.saturatingSub(2);
        }

        // Account for padding
        inner.x += self.padding.left;
        inner.y += self.padding.top;
        inner.width = inner.width.saturatingSub(self.padding.left + self.padding.right);
        inner.height = inner.height.saturatingSub(self.padding.top + self.padding.bottom);

        // Account for inline title
        if (self.title_position == .inside and self.title != null) {
            inner.y += 1;
            inner.height = inner.height.saturatingSub(1);
        }

        return inner;
    }

    /// Draw the block
    pub fn draw(self: *const Block) void {
        // Fill background if specified
        if (self.background_color) |bg| {
            self.fillBackground(bg);
        }

        // Draw border
        if (self.border_style != .none) {
            self.drawBorder();
        }

        // Draw inline title if specified
        if (self.title_position == .inside and self.title != null) {
            self.drawInlineTitle();
        }

        // Render content if provided
        if (self.render_content) |render_fn| {
            const inner = self.getInnerBounds();
            render_fn(inner);
        }

        // Reset colors
        std.debug.print("\x1b[0m", .{});
    }

    fn fillBackground(self: *const Block, color: Color) void {
        // Use the ANSI sequence directly since Color contains them as constants
        std.debug.print("{s}", .{color});

        const start_y = if (self.border_style != .none) self.bounds.y + 1 else self.bounds.y;
        const end_y = if (self.border_style != .none) self.bounds.y + self.bounds.height - 1 else self.bounds.y + self.bounds.height;
        const start_x = if (self.border_style != .none) self.bounds.x + 1 else self.bounds.x;
        const end_x = if (self.border_style != .none) self.bounds.x + self.bounds.width - 1 else self.bounds.x + self.bounds.width;

        for (start_y..end_y) |y| {
            moveCursor(@intCast(y), @intCast(start_x));
            for (start_x..end_x) |_| {
                std.debug.print(" ", .{});
            }
        }
    }

    fn drawBorder(self: *const Block) void {
        const chars = getBorderChars(self.border_style);

        // Set border color
        std.debug.print("\x1b[{d}m", .{@intFromEnum(self.border_color)});

        // Top border with title
        moveCursor(self.bounds.y, self.bounds.x);
        std.debug.print("{s}", .{chars.top_left});

        if (self.title_position == .top and self.title) |title| {
            self.drawTitleOnBorder(title, self.title_alignment, self.title_color, chars.horizontal);
        } else {
            for (1..self.bounds.width - 1) |_| {
                std.debug.print("{s}", .{chars.horizontal});
            }
        }
        std.debug.print("{s}", .{chars.top_right});

        // Side borders
        for (1..self.bounds.height - 1) |i| {
            // Left border
            moveCursor(self.bounds.y + i, self.bounds.x);
            std.debug.print("{s}", .{chars.vertical});

            // Right border
            moveCursor(self.bounds.y + i, self.bounds.x + self.bounds.width - 1);
            std.debug.print("{s}", .{chars.vertical});
        }

        // Bottom border with subtitle
        moveCursor(self.bounds.y + self.bounds.height - 1, self.bounds.x);
        std.debug.print("{s}", .{chars.bottom_left});

        if (self.subtitle) |subtitle| {
            self.drawTitleOnBorder(subtitle, self.subtitle_alignment, self.subtitle_color, chars.horizontal);
        } else if (self.title_position == .bottom and self.title) |title| {
            self.drawTitleOnBorder(title, self.title_alignment, self.title_color, chars.horizontal);
        } else {
            for (1..self.bounds.width - 1) |_| {
                std.debug.print("{s}", .{chars.horizontal});
            }
        }
        std.debug.print("{s}", .{chars.bottom_right});
    }

    fn drawTitleOnBorder(self: *const Block, title: []const u8, alignment: TitleAlignment, color: Color, border_char: []const u8) void {
        const max_title_width = self.bounds.width -| 4; // Leave space for corners and padding
        const display_title = if (title.len > max_title_width)
            title[0..max_title_width]
        else
            title;

        const padding = (self.bounds.width -| 2 -| display_title.len) / 2;
        const left_padding = switch (alignment) {
            .left => 1,
            .center => padding,
            .right => self.bounds.width -| display_title.len -| 3,
        };

        // Draw border before title
        for (0..left_padding) |_| {
            std.debug.print("{s}", .{border_char});
        }

        // Draw title with color
        std.debug.print(" \x1b[{d}m{s}\x1b[{d}m ", .{
            @intFromEnum(color),
            display_title,
            @intFromEnum(self.border_color),
        });

        // Draw border after title
        const remaining = self.bounds.width -| left_padding -| display_title.len -| 4;
        for (0..remaining) |_| {
            std.debug.print("{s}", .{border_char});
        }
    }

    fn drawInlineTitle(self: *const Block) void {
        if (self.title) |title| {
            const inner = self.getInnerBounds();
            moveCursor(inner.y - 1, inner.x);

            // Draw title with alignment
            const padding = switch (self.title_alignment) {
                .left => 0,
                .center => (inner.width -| title.len) / 2,
                .right => inner.width -| title.len,
            };

            for (0..padding) |_| {
                std.debug.print(" ", .{});
            }
            std.debug.print("{s}{s}", .{ self.title_color, title });
            std.debug.print("\x1b[0m", .{});
        }
    }

    fn moveCursor(row: u32, col: u32) void {
        std.debug.print("\x1b[{d};{d}H", .{ row + 1, col + 1 });
    }
};

/// Border character sets for different styles
const BorderChars = struct {
    horizontal: []const u8,
    vertical: []const u8,
    top_left: []const u8,
    top_right: []const u8,
    bottom_left: []const u8,
    bottom_right: []const u8,
};

fn getBorderChars(style: BorderStyle) BorderChars {
    return switch (style) {
        .none => BorderChars{
            .horizontal = " ",
            .vertical = " ",
            .top_left = " ",
            .top_right = " ",
            .bottom_left = " ",
            .bottom_right = " ",
        },
        .single => BorderChars{
            .horizontal = "─",
            .vertical = "│",
            .top_left = "┌",
            .top_right = "┐",
            .bottom_left = "└",
            .bottom_right = "┘",
        },
        .double => BorderChars{
            .horizontal = "═",
            .vertical = "║",
            .top_left = "╔",
            .top_right = "╗",
            .bottom_left = "╚",
            .bottom_right = "╝",
        },
        .rounded => BorderChars{
            .horizontal = "─",
            .vertical = "│",
            .top_left = "╭",
            .top_right = "╮",
            .bottom_left = "╰",
            .bottom_right = "╯",
        },
        .thick => BorderChars{
            .horizontal = "━",
            .vertical = "┃",
            .top_left = "┏",
            .top_right = "┓",
            .bottom_left = "┗",
            .bottom_right = "┛",
        },
        .dashed => BorderChars{
            .horizontal = "╌",
            .vertical = "╎",
            .top_left = "┌",
            .top_right = "┐",
            .bottom_left = "└",
            .bottom_right = "┘",
        },
        .dotted => BorderChars{
            .horizontal = "⋯",
            .vertical = "⋮",
            .top_left = "·",
            .top_right = "·",
            .bottom_left = "·",
            .bottom_right = "·",
        },
        .ascii => BorderChars{
            .horizontal = "-",
            .vertical = "|",
            .top_left = "+",
            .top_right = "+",
            .bottom_left = "+",
            .bottom_right = "+",
        },
    };
}

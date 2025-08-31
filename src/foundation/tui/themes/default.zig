//! Default Theme Colors and Styles
//!
//! Provides color schemes and box drawing styles for TUI widgets.
//! This is a bridge to the main theme system.

const theme = @import("../../theme.zig");

// Re-export color types from the main theme system
pub const Color = theme.Color;
pub const Colors = theme.Colors;
pub const ColorEnum = Color;

// Box drawing characters and styles
pub const Box = struct {
    pub const single = BoxStyle{
        .top_left = "┌",
        .top_right = "┐",
        .bottom_left = "└",
        .bottom_right = "┘",
        .horizontal = "─",
        .vertical = "│",
        .cross = "┼",
        .vertical_right = "├",
        .vertical_left = "┤",
        .horizontal_down = "┬",
        .horizontal_up = "┴",
    };

    pub const double = BoxStyle{
        .top_left = "╔",
        .top_right = "╗",
        .bottom_left = "╚",
        .bottom_right = "╝",
        .horizontal = "═",
        .vertical = "║",
        .cross = "╬",
        .vertical_right = "╠",
        .vertical_left = "╣",
        .horizontal_down = "╦",
        .horizontal_up = "╩",
    };

    pub const rounded = BoxStyle{
        .top_left = "╭",
        .top_right = "╮",
        .bottom_left = "╰",
        .bottom_right = "╯",
        .horizontal = "─",
        .vertical = "│",
        .cross = "┼",
        .vertical_right = "├",
        .vertical_left = "┤",
        .horizontal_down = "┬",
        .horizontal_up = "┴",
    };

    pub const thick = BoxStyle{
        .top_left = "┏",
        .top_right = "┓",
        .bottom_left = "┗",
        .bottom_right = "┛",
        .horizontal = "━",
        .vertical = "┃",
        .cross = "╋",
        .vertical_right = "┣",
        .vertical_left = "┫",
        .horizontal_down = "┳",
        .horizontal_up = "┻",
    };
};

pub const BoxStyle = struct {
    top_left: []const u8,
    top_right: []const u8,
    bottom_left: []const u8,
    bottom_right: []const u8,
    horizontal: []const u8,
    vertical: []const u8,
    cross: []const u8,
    vertical_right: []const u8,
    vertical_left: []const u8,
    horizontal_down: []const u8,
    horizontal_up: []const u8,
};

//! Default theme definitions for TUI components
const std = @import("std");

/// ANSI color codes for styling
pub const Color = struct {
    pub const RESET = "\x1b[0m";
    pub const BOLD = "\x1b[1m";
    pub const DIM = "\x1b[2m";
    pub const BRIGHT_BLUE = "\x1b[94m";
    pub const BRIGHT_RED = "\x1b[91m";
    pub const BRIGHT_YELLOW = "\x1b[93m";
    pub const BRIGHT_CYAN = "\x1b[96m";
    pub const WHITE = "\x1b[37m";
    pub const BG_BLUE = "\x1b[44m";

    // Extended color palette
    pub const BLACK = "\x1b[30m";
    pub const RED = "\x1b[31m";
    pub const GREEN = "\x1b[32m";
    pub const YELLOW = "\x1b[33m";
    pub const BLUE = "\x1b[34m";
    pub const MAGENTA = "\x1b[35m";
    pub const CYAN = "\x1b[36m";
    pub const GRAY = "\x1b[90m";

    // Background colors
    pub const BG_BLACK = "\x1b[40m";
    pub const BG_RED = "\x1b[41m";
    pub const BG_GREEN = "\x1b[42m";
    pub const BG_YELLOW = "\x1b[43m";
    pub const BG_MAGENTA = "\x1b[45m";
    pub const BG_CYAN = "\x1b[46m";
    pub const BG_WHITE = "\x1b[47m";
    pub const BG_GRAY = "\x1b[100m";
};

/// ANSI color enum for widgets that need enum-based colors
pub const ColorEnum = enum(u8) {
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,
    gray = 90,
    bright_red = 91,
    bright_green = 92,
    bright_yellow = 93,
    bright_blue = 94,
    bright_magenta = 95,
    bright_cyan = 96,
    bright_white = 97,
    dark_gray = 100,
};

/// Box drawing characters for borders
pub const Box = struct {
    pub const HORIZONTAL = "─";
    pub const VERTICAL = "│";
    pub const TOP_LEFT = "┌";
    pub const TOP_RIGHT = "┐";
    pub const BOTTOM_LEFT = "└";
    pub const BOTTOM_RIGHT = "┘";
    pub const CROSS = "┼";
    pub const T_TOP = "┬";
    pub const T_BOTTOM = "┴";
    pub const T_LEFT = "├";
    pub const T_RIGHT = "┤";

    // Double line variants
    pub const DOUBLE_HORIZONTAL = "═";
    pub const DOUBLE_VERTICAL = "║";
    pub const DOUBLE_TOP_LEFT = "╔";
    pub const DOUBLE_TOP_RIGHT = "╗";
    pub const DOUBLE_BOTTOM_LEFT = "╚";
    pub const DOUBLE_BOTTOM_RIGHT = "╝";

    // Rounded variants
    pub const ROUNDED_TOP_LEFT = "╭";
    pub const ROUNDED_TOP_RIGHT = "╮";
    pub const ROUNDED_BOTTOM_LEFT = "╰";
    pub const ROUNDED_BOTTOM_RIGHT = "╯";
};

/// Status icons for various UI states
pub const Status = struct {
    pub const LOADING = "⏳";
    pub const GEAR = "⚙️";
    pub const LINK = "🔗";
    pub const BROWSER = "🌐";
    pub const WAITING = "⏱️";
    pub const INFO = "ℹ️";
    pub const SHIELD = "🛡️";
    pub const SUCCESS = "✅";
    pub const ERROR = "❌";
    pub const WARNING = "⚠️";
    pub const QUESTION = "❓";
    pub const STAR = "⭐";
    pub const HEART = "❤️";
    pub const FOLDER = "📁";
    pub const FILE = "📄";
    pub const ARROW_RIGHT = "➤";
    pub const ARROW_LEFT = "◀";
    pub const ARROW_UP = "▲";
    pub const ARROW_DOWN = "▼";
};

/// Progress bar characters
pub const Progress = struct {
    // Block characters
    pub const FULL_BLOCK = "█";
    pub const LIGHT_SHADE = "░";
    pub const MEDIUM_SHADE = "▒";
    pub const DARK_SHADE = "▓";

    // Partial blocks for smooth progress
    pub const LEFT_EIGHTH = "▏";
    pub const LEFT_QUARTER = "▎";
    pub const LEFT_THREE_EIGHTHS = "▍";
    pub const LEFT_HALF = "▌";
    pub const LEFT_FIVE_EIGHTHS = "▋";
    pub const LEFT_THREE_QUARTERS = "▊";
    pub const LEFT_SEVEN_EIGHTHS = "▉";
};

/// Theme configuration structure
pub const Theme = struct {
    pub const ColorScheme = struct {
        primary: []const u8,
        secondary: []const u8,
        background: []const u8,
        surface: []const u8,
        @"error": []const u8,
        warning: []const u8,
        success: []const u8,
        text: []const u8,
        text_secondary: []const u8,
        border: []const u8,
        accent: []const u8,
    };

    pub const Typography = struct {
        bold: []const u8,
        italic: []const u8,
        underline: []const u8,
        strikethrough: []const u8,
        reset: []const u8,
    };

    pub const BorderStyle = struct {
        top_left: []const u8,
        top_right: []const u8,
        bottom_left: []const u8,
        bottom_right: []const u8,
        horizontal: []const u8,
        vertical: []const u8,
        style: enum { single, double, rounded },
    };

    colors: ColorScheme,
    typography: Typography,
    border: BorderStyle,
    name: []const u8,

    pub fn default() Theme {
        return Theme{
            .name = "Default",
            .colors = ColorScheme{
                .primary = Color.BRIGHT_BLUE,
                .secondary = Color.BRIGHT_CYAN,
                .background = Color.RESET,
                .surface = Color.BG_GRAY,
                .@"error" = Color.BRIGHT_RED,
                .warning = Color.BRIGHT_YELLOW,
                .success = Color.GREEN,
                .text = Color.WHITE,
                .text_secondary = Color.GRAY,
                .border = Color.WHITE,
                .accent = Color.BRIGHT_YELLOW,
            },
            .typography = Typography{
                .bold = Color.BOLD,
                .italic = "\x1b[3m", // Italic
                .underline = "\x1b[4m", // Underline
                .strikethrough = "\x1b[9m", // Strikethrough
                .reset = Color.RESET,
            },
            .border = BorderStyle{
                .top_left = Box.TOP_LEFT,
                .top_right = Box.TOP_RIGHT,
                .bottom_left = Box.BOTTOM_LEFT,
                .bottom_right = Box.BOTTOM_RIGHT,
                .horizontal = Box.HORIZONTAL,
                .vertical = Box.VERTICAL,
                .style = .single,
            },
        };
    }

    pub fn dark() Theme {
        return Theme{
            .name = "Dark",
            .colors = ColorScheme{
                .primary = Color.BRIGHT_BLUE,
                .secondary = Color.BRIGHT_CYAN,
                .background = Color.BG_BLACK,
                .surface = Color.BG_GRAY,
                .@"error" = Color.BRIGHT_RED,
                .warning = Color.BRIGHT_YELLOW,
                .success = Color.GREEN,
                .text = Color.WHITE,
                .text_secondary = Color.GRAY,
                .border = Color.GRAY,
                .accent = Color.BRIGHT_CYAN,
            },
            .typography = Typography{
                .bold = Color.BOLD,
                .italic = "\x1b[3m",
                .underline = "\x1b[4m",
                .strikethrough = "\x1b[9m",
                .reset = Color.RESET,
            },
            .border = BorderStyle{
                .top_left = Box.ROUNDED_TOP_LEFT,
                .top_right = Box.ROUNDED_TOP_RIGHT,
                .bottom_left = Box.ROUNDED_BOTTOM_LEFT,
                .bottom_right = Box.ROUNDED_BOTTOM_RIGHT,
                .horizontal = Box.HORIZONTAL,
                .vertical = Box.VERTICAL,
                .style = .rounded,
            },
        };
    }

    pub fn light() Theme {
        return Theme{
            .name = "Light",
            .colors = ColorScheme{
                .primary = Color.BLUE,
                .secondary = Color.CYAN,
                .background = Color.BG_WHITE,
                .surface = Color.WHITE,
                .@"error" = Color.RED,
                .warning = Color.YELLOW,
                .success = Color.GREEN,
                .text = Color.BLACK,
                .text_secondary = Color.GRAY,
                .border = Color.BLACK,
                .accent = Color.BLUE,
            },
            .typography = Typography{
                .bold = Color.BOLD,
                .italic = "\x1b[3m",
                .underline = "\x1b[4m",
                .strikethrough = "\x1b[9m",
                .reset = Color.RESET,
            },
            .border = BorderStyle{
                .top_left = Box.TOP_LEFT,
                .top_right = Box.TOP_RIGHT,
                .bottom_left = Box.BOTTOM_LEFT,
                .bottom_right = Box.BOTTOM_RIGHT,
                .horizontal = Box.HORIZONTAL,
                .vertical = Box.VERTICAL,
                .style = .single,
            },
        };
    }
};

/// Available themes
pub const themes = [_]Theme{
    Theme.default(),
    Theme.dark(),
    Theme.light(),
};

/// Get theme by name
pub fn getTheme(name: []const u8) ?Theme {
    for (themes) |theme| {
        if (std.mem.eql(u8, theme.name, name)) {
            return theme;
        }
    }
    return null;
}

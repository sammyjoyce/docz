//! Centralized color definitions for CLI themes
//! Provides semantic color names and terminal capability adaptation

const std = @import("std");
const term_shared = @import("../../term/mod.zig");
const term_ansi = term_shared.ansi.color;
const term_caps = term_shared.caps;

/// RGB color values for true color terminals
pub const RgbColor = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RgbColor {
        return .{ .r = r, .g = g, .b = b };
    }
};

/// Color palette supporting multiple terminal types
pub const Color = struct {
    rgb: RgbColor, // True color (24-bit)
    ansi256: u8, // 256-color fallback
    ansi16: u8, // 16-color fallback
    name: []const u8, // Semantic name

    pub fn init(name: []const u8, rgb: RgbColor, ansi256: u8, ansi16: u8) Color {
        return .{
            .rgb = rgb,
            .ansi256 = ansi256,
            .ansi16 = ansi16,
            .name = name,
        };
    }

    /// Apply this color as foreground based on terminal capabilities
    pub fn setForeground(self: Color, writer: anytype, caps: term_caps.TermCaps) !void {
        if (caps.supportsTrueColor()) {
            try term_ansi.setForegroundRgb(writer, caps, self.rgb.r, self.rgb.g, self.rgb.b);
        } else if (caps.supports256Color()) {
            try term_ansi.setForeground256(writer, caps, self.ansi256);
        } else {
            try term_ansi.setForeground16(writer, caps, self.ansi16);
        }
    }

    /// Apply this color as background based on terminal capabilities
    pub fn setBackground(self: Color, writer: anytype, caps: term_caps.TermCaps) !void {
        if (caps.supportsTrueColor()) {
            try term_ansi.setBackgroundRgb(writer, caps, self.rgb.r, self.rgb.g, self.rgb.b);
        } else if (caps.supports256Color()) {
            try term_ansi.setBackground256(writer, caps, self.ansi256);
        } else {
            try term_ansi.setBackground16(writer, caps, self.ansi16);
        }
    }
};

/// Semantic color definitions
pub const SemanticColors = struct {
    // Text colors
    primary: Color,
    secondary: Color,
    muted: Color,
    inverse: Color,

    // Status colors
    success: Color,
    warning: Color,
    err: Color,
    info: Color,

    // UI colors
    border: Color,
    background: Color,
    selection: Color,
    highlight: Color,

    // Interactive colors
    link: Color,
    button: Color,
    input: Color,
    placeholder: Color,
};

/// Default semantic color palette
pub const default_colors = SemanticColors{
    // Text colors
    .primary = Color.init("primary", RgbColor.init(255, 255, 255), 15, 15), // White
    .secondary = Color.init("secondary", RgbColor.init(200, 200, 200), 7, 7), // Light gray
    .muted = Color.init("muted", RgbColor.init(120, 120, 120), 8, 8), // Dark gray
    .inverse = Color.init("inverse", RgbColor.init(0, 0, 0), 0, 0), // Black

    // Status colors
    .success = Color.init("success", RgbColor.init(50, 205, 50), 10, 10), // Lime green
    .warning = Color.init("warning", RgbColor.init(255, 165, 0), 11, 11), // Orange
    .err = Color.init("error", RgbColor.init(255, 69, 0), 9, 9), // Red orange
    .info = Color.init("info", RgbColor.init(100, 149, 237), 12, 12), // Cornflower blue

    // UI colors
    .border = Color.init("border", RgbColor.init(100, 149, 237), 12, 12), // Cornflower blue
    .background = Color.init("background", RgbColor.init(25, 25, 25), 0, 0), // Dark background
    .selection = Color.init("selection", RgbColor.init(30, 30, 80), 18, 4), // Dark blue
    .highlight = Color.init("highlight", RgbColor.init(255, 255, 100), 11, 11), // Bright yellow

    // Interactive colors
    .link = Color.init("link", RgbColor.init(100, 149, 237), 12, 12), // Cornflower blue
    .button = Color.init("button", RgbColor.init(147, 112, 219), 5, 5), // Medium purple
    .input = Color.init("input", RgbColor.init(255, 255, 255), 15, 15), // White
    .placeholder = Color.init("placeholder", RgbColor.init(120, 120, 120), 8, 8), // Gray
};

/// Dark theme colors
pub const dark_colors = SemanticColors{
    // Text colors
    .primary = Color.init("primary", RgbColor.init(230, 230, 230), 15, 15),
    .secondary = Color.init("secondary", RgbColor.init(180, 180, 180), 7, 7),
    .muted = Color.init("muted", RgbColor.init(100, 100, 100), 8, 8),
    .inverse = Color.init("inverse", RgbColor.init(20, 20, 20), 0, 0),

    // Status colors
    .success = Color.init("success", RgbColor.init(40, 180, 40), 10, 10),
    .warning = Color.init("warning", RgbColor.init(220, 140, 0), 11, 11),
    .err = Color.init("error", RgbColor.init(220, 50, 50), 9, 9),
    .info = Color.init("info", RgbColor.init(80, 120, 200), 12, 12),

    // UI colors
    .border = Color.init("border", RgbColor.init(70, 70, 70), 8, 8),
    .background = Color.init("background", RgbColor.init(20, 20, 20), 0, 0),
    .selection = Color.init("selection", RgbColor.init(40, 40, 70), 18, 4),
    .highlight = Color.init("highlight", RgbColor.init(200, 200, 80), 11, 11),

    // Interactive colors
    .link = Color.init("link", RgbColor.init(100, 150, 255), 12, 12),
    .button = Color.init("button", RgbColor.init(130, 90, 200), 5, 5),
    .input = Color.init("input", RgbColor.init(220, 220, 220), 15, 15),
    .placeholder = Color.init("placeholder", RgbColor.init(90, 90, 90), 8, 8),
};

/// Light theme colors
pub const light_colors = SemanticColors{
    // Text colors
    .primary = Color.init("primary", RgbColor.init(40, 40, 40), 0, 0),
    .secondary = Color.init("secondary", RgbColor.init(80, 80, 80), 8, 8),
    .muted = Color.init("muted", RgbColor.init(120, 120, 120), 8, 8),
    .inverse = Color.init("inverse", RgbColor.init(255, 255, 255), 15, 15),

    // Status colors
    .success = Color.init("success", RgbColor.init(0, 150, 0), 2, 2),
    .warning = Color.init("warning", RgbColor.init(200, 100, 0), 3, 3),
    .err = Color.init("error", RgbColor.init(200, 0, 0), 1, 1),
    .info = Color.init("info", RgbColor.init(0, 100, 200), 4, 4),

    // UI colors
    .border = Color.init("border", RgbColor.init(150, 150, 150), 8, 8),
    .background = Color.init("background", RgbColor.init(250, 250, 250), 15, 15),
    .selection = Color.init("selection", RgbColor.init(200, 220, 255), 7, 7),
    .highlight = Color.init("highlight", RgbColor.init(255, 255, 0), 11, 11),

    // Interactive colors
    .link = Color.init("link", RgbColor.init(0, 100, 200), 4, 4),
    .button = Color.init("button", RgbColor.init(100, 50, 150), 5, 5),
    .input = Color.init("input", RgbColor.init(40, 40, 40), 0, 0),
    .placeholder = Color.init("placeholder", RgbColor.init(150, 150, 150), 8, 8),
};

/// High contrast theme colors
pub const high_contrast_colors = SemanticColors{
    // Text colors
    .primary = Color.init("primary", RgbColor.init(255, 255, 255), 15, 15),
    .secondary = Color.init("secondary", RgbColor.init(255, 255, 255), 15, 15),
    .muted = Color.init("muted", RgbColor.init(200, 200, 200), 7, 7),
    .inverse = Color.init("inverse", RgbColor.init(0, 0, 0), 0, 0),

    // Status colors
    .success = Color.init("success", RgbColor.init(0, 255, 0), 10, 10),
    .warning = Color.init("warning", RgbColor.init(255, 255, 0), 11, 11),
    .err = Color.init("error", RgbColor.init(255, 0, 0), 9, 9),
    .info = Color.init("info", RgbColor.init(0, 255, 255), 14, 14),

    // UI colors
    .border = Color.init("border", RgbColor.init(255, 255, 255), 15, 15),
    .background = Color.init("background", RgbColor.init(0, 0, 0), 0, 0),
    .selection = Color.init("selection", RgbColor.init(255, 255, 255), 15, 15),
    .highlight = Color.init("highlight", RgbColor.init(255, 255, 0), 11, 11),

    // Interactive colors
    .link = Color.init("link", RgbColor.init(0, 255, 255), 14, 14),
    .button = Color.init("button", RgbColor.init(255, 0, 255), 13, 13),
    .input = Color.init("input", RgbColor.init(255, 255, 255), 15, 15),
    .placeholder = Color.init("placeholder", RgbColor.init(128, 128, 128), 8, 8),
};

/// Common color combinations for specific UI patterns
pub const ColorCombinations = struct {
    /// Colors for progress bars
    pub const progress_bar = struct {
        pub const filled = Color.init("progress_filled", RgbColor.init(50, 205, 50), 10, 10);
        pub const empty = Color.init("progress_empty", RgbColor.init(60, 60, 60), 8, 8);
        pub const text = Color.init("progress_text", RgbColor.init(255, 255, 255), 15, 15);
    };

    /// Colors for input fields
    pub const input_field = struct {
        pub const border_focused = Color.init("input_border_focused", RgbColor.init(100, 149, 237), 12, 12);
        pub const border_normal = Color.init("input_border_normal", RgbColor.init(100, 100, 100), 8, 8);
        pub const text = Color.init("input_text", RgbColor.init(255, 255, 255), 15, 15);
        pub const background = Color.init("input_background", RgbColor.init(25, 25, 25), 0, 0);
        pub const cursor = Color.init("input_cursor", RgbColor.init(255, 255, 255), 15, 15);
    };

    /// Colors for menus
    pub const menu = struct {
        pub const selected_bg = Color.init("menu_selected_bg", RgbColor.init(30, 30, 80), 18, 4);
        pub const selected_fg = Color.init("menu_selected_fg", RgbColor.init(255, 255, 255), 15, 15);
        pub const normal_fg = Color.init("menu_normal_fg", RgbColor.init(200, 200, 200), 7, 7);
        pub const disabled_fg = Color.init("menu_disabled_fg", RgbColor.init(100, 100, 100), 8, 8);
        pub const border = Color.init("menu_border", RgbColor.init(100, 149, 237), 12, 12);
    };

    /// Colors for notifications
    pub const notification = struct {
        pub const info_bg = Color.init("notif_info_bg", RgbColor.init(0, 50, 100), 18, 4);
        pub const success_bg = Color.init("notif_success_bg", RgbColor.init(0, 80, 0), 22, 2);
        pub const warning_bg = Color.init("notif_warning_bg", RgbColor.init(100, 60, 0), 94, 3);
        pub const err_bg = Color.init("notif_error_bg", RgbColor.init(100, 20, 20), 88, 1);
        pub const text = Color.init("notif_text", RgbColor.init(255, 255, 255), 15, 15);
    };
};

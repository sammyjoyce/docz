//! Enhanced theme system with dynamic color adaptation
//! Uses advanced terminal capabilities for rich color support

const std = @import("std");
const term_ansi = @import("../../../term/ansi/color.zig");
const term_caps = @import("../../../term/caps.zig");
const Allocator = std.mem.Allocator;

/// Color definitions with fallbacks for different terminal capabilities
pub const Color = struct {
    truecolor: ?TrueColor,
    color256: ?u8,
    ansi: u8,

    pub const TrueColor = struct {
        r: u8,
        g: u8,
        b: u8,
    };

    pub fn init(ansi_code: u8) Color {
        return Color{
            .truecolor = null,
            .color256 = null,
            .ansi = ansi_code,
        };
    }

    pub fn initTrueColor(r: u8, g: u8, b: u8, color256_fallback: u8, ansi_fallback: u8) Color {
        return Color{
            .truecolor = TrueColor{ .r = r, .g = g, .b = b },
            .color256 = color256_fallback,
            .ansi = ansi_fallback,
        };
    }

    /// Write the appropriate color escape sequence based on terminal capabilities
    pub fn write(self: Color, writer: anytype, caps: term_caps.TermCaps, fg: bool) !void {
        if (self.truecolor != null and caps.supportsTrueColor()) {
            const tc = self.truecolor.?;
            if (fg) {
                try term_ansi.setForegroundRgb(writer, caps, tc.r, tc.g, tc.b);
            } else {
                try term_ansi.setBackgroundRgb(writer, caps, tc.r, tc.g, tc.b);
            }
        } else if (self.color256 != null and caps.supports256Color()) {
            if (fg) {
                try term_ansi.setForeground256(writer, caps, self.color256.?);
            } else {
                try term_ansi.setBackground256(writer, caps, self.color256.?);
            }
        } else {
            // Fallback to basic ANSI
            const code = if (fg) self.ansi else self.ansi + 10; // Background = foreground + 10
            var buf: [16]u8 = undefined;
            const seq = try std.fmt.bufPrint(&buf, "\x1b[{}m", .{code});
            try writer.writeAll(seq);
        }
    }

    pub fn writeFg(self: Color, writer: anytype, caps: term_caps.TermCaps) !void {
        try self.write(writer, caps, true);
    }

    pub fn writeBg(self: Color, writer: anytype, caps: term_caps.TermCaps) !void {
        try self.write(writer, caps, false);
    }
};

/// Enhanced theme with rich color palette
pub const EnhancedTheme = struct {
    // UI Colors
    primary: Color,
    secondary: Color,
    accent: Color,
    background: Color,
    surface: Color,

    // Text Colors
    text_primary: Color,
    text_secondary: Color,
    text_muted: Color,
    text_link: Color,

    // Status Colors
    success: Color,
    warning: Color,
    err: Color,
    info: Color,

    // Syntax highlighting (for code blocks)
    syntax_keyword: Color,
    syntax_string: Color,
    syntax_comment: Color,
    syntax_function: Color,

    caps: term_caps.TermCaps,

    /// Modern dark theme with blue accents
    pub fn modernDark() EnhancedTheme {
        const caps = term_caps.getTermCaps();

        return EnhancedTheme{
            .primary = Color.initTrueColor(100, 149, 237, 12, 34), // Cornflower blue
            .secondary = Color.initTrueColor(75, 0, 130, 5, 35), // Indigo
            .accent = Color.initTrueColor(255, 215, 0, 11, 33), // Gold
            .background = Color.initTrueColor(18, 18, 18, 0, 40), // Very dark gray
            .surface = Color.initTrueColor(35, 35, 35, 8, 40), // Dark gray

            .text_primary = Color.initTrueColor(255, 255, 255, 15, 37), // White
            .text_secondary = Color.initTrueColor(200, 200, 200, 7, 37), // Light gray
            .text_muted = Color.initTrueColor(128, 128, 128, 8, 30), // Medium gray
            .text_link = Color.initTrueColor(135, 206, 250, 14, 36), // Light sky blue

            .success = Color.initTrueColor(144, 238, 144, 10, 32), // Light green
            .warning = Color.initTrueColor(255, 165, 0, 11, 33), // Orange
            .err = Color.initTrueColor(255, 99, 71, 9, 31), // Tomato
            .info = Color.initTrueColor(173, 216, 230, 14, 36), // Light blue

            .syntax_keyword = Color.initTrueColor(199, 146, 234, 13, 35), // Medium orchid
            .syntax_string = Color.initTrueColor(152, 251, 152, 10, 32), // Pale green
            .syntax_comment = Color.initTrueColor(105, 105, 105, 8, 30), // Dim gray
            .syntax_function = Color.initTrueColor(255, 228, 181, 11, 33), // Moccasin

            .caps = caps,
        };
    }

    /// Clean light theme with subtle colors
    pub fn cleanLight() EnhancedTheme {
        const caps = term_caps.getTermCaps();

        return EnhancedTheme{
            .primary = Color.initTrueColor(70, 130, 180, 4, 34), // Steel blue
            .secondary = Color.initTrueColor(106, 90, 205, 5, 35), // Slate blue
            .accent = Color.initTrueColor(255, 140, 0, 3, 33), // Dark orange
            .background = Color.initTrueColor(248, 248, 255, 15, 47), // Ghost white
            .surface = Color.initTrueColor(245, 245, 245, 7, 47), // White smoke

            .text_primary = Color.initTrueColor(25, 25, 25, 0, 30), // Very dark gray
            .text_secondary = Color.initTrueColor(64, 64, 64, 8, 30), // Dark gray
            .text_muted = Color.initTrueColor(128, 128, 128, 8, 37), // Gray
            .text_link = Color.initTrueColor(0, 0, 238, 4, 34), // Blue

            .success = Color.initTrueColor(0, 128, 0, 2, 32), // Green
            .warning = Color.initTrueColor(255, 140, 0, 3, 33), // Dark orange
            .err = Color.initTrueColor(220, 20, 60, 1, 31), // Crimson
            .info = Color.initTrueColor(30, 144, 255, 4, 34), // Dodger blue

            .syntax_keyword = Color.initTrueColor(128, 0, 128, 5, 35), // Purple
            .syntax_string = Color.initTrueColor(0, 128, 0, 2, 32), // Green
            .syntax_comment = Color.initTrueColor(128, 128, 128, 8, 30), // Gray
            .syntax_function = Color.initTrueColor(255, 140, 0, 3, 33), // Dark orange

            .caps = caps,
        };
    }

    /// High contrast theme for accessibility
    pub fn highContrast() EnhancedTheme {
        const caps = term_caps.getTermCaps();

        return EnhancedTheme{
            .primary = Color.initTrueColor(255, 255, 0, 11, 33), // Yellow
            .secondary = Color.initTrueColor(0, 255, 255, 14, 36), // Cyan
            .accent = Color.initTrueColor(255, 0, 255, 13, 35), // Magenta
            .background = Color.initTrueColor(0, 0, 0, 0, 40), // Black
            .surface = Color.initTrueColor(64, 64, 64, 8, 40), // Dark gray

            .text_primary = Color.initTrueColor(255, 255, 255, 15, 37), // White
            .text_secondary = Color.initTrueColor(255, 255, 255, 15, 37), // White
            .text_muted = Color.initTrueColor(192, 192, 192, 7, 37), // Silver
            .text_link = Color.initTrueColor(255, 255, 0, 11, 33), // Yellow

            .success = Color.initTrueColor(0, 255, 0, 10, 32), // Lime
            .warning = Color.initTrueColor(255, 255, 0, 11, 33), // Yellow
            .err = Color.initTrueColor(255, 0, 0, 9, 31), // Red
            .info = Color.initTrueColor(0, 255, 255, 14, 36), // Cyan

            .syntax_keyword = Color.initTrueColor(255, 255, 0, 11, 33), // Yellow
            .syntax_string = Color.initTrueColor(0, 255, 0, 10, 32), // Lime
            .syntax_comment = Color.initTrueColor(128, 128, 128, 8, 30), // Gray
            .syntax_function = Color.initTrueColor(0, 255, 255, 14, 36), // Cyan

            .caps = caps,
        };
    }

    /// Apply theme colors to terminal
    pub fn apply(self: EnhancedTheme, writer: anytype) !void {
        // Set terminal default colors if supported
        if (self.caps.supportsColorOsc10_12) {
            // Set default foreground
            try term_ansi.setForegroundColor(writer, std.heap.page_allocator, self.caps, "#FFFFFF");
            // Set default background
            try term_ansi.setBackgroundColor(writer, std.heap.page_allocator, self.caps, "#121212");
        }
    }

    /// Reset terminal colors to defaults
    pub fn reset(self: EnhancedTheme, writer: anytype) !void {
        if (self.caps.supportsColorOsc10_12) {
            try term_ansi.resetForegroundColor(writer, std.heap.page_allocator, self.caps);
            try term_ansi.resetBackgroundColor(writer, std.heap.page_allocator, self.caps);
        }
        try term_ansi.resetStyle(writer, self.caps);
    }
};

/// Theme manager for switching between themes and adapting to terminal capabilities
pub const Theme = struct {
    current_theme: EnhancedTheme,
    caps: term_caps.TermCaps,
    allocator: Allocator,

    pub fn init(allocator: Allocator) Theme {
        const caps = term_caps.getTermCaps();

        // Choose default theme based on terminal capabilities and environment
        const theme = if (isLightMode())
            EnhancedTheme.cleanLight()
        else
            EnhancedTheme.modernDark();

        return Theme{
            .current_theme = theme,
            .caps = caps,
            .allocator = allocator,
        };
    }

    pub fn setTheme(self: *Theme, theme: EnhancedTheme) void {
        self.current_theme = theme;
    }

    pub fn getTheme(self: Theme) EnhancedTheme {
        return self.current_theme;
    }

    /// Auto-detect if we're in light mode (e.g., from environment variables)
    fn isLightMode() bool {
        // Check various environment hints
        if (std.process.hasEnvVar(std.heap.page_allocator, "DOCZ_THEME")) |_| {
            const theme = std.process.getEnvVarOwned(std.heap.page_allocator, "DOCZ_THEME") catch return false;
            defer std.heap.page_allocator.free(theme);
            return std.mem.eql(u8, theme, "light");
        } else |_| {}

        // Check macOS system appearance
        if (std.process.hasEnvVar(std.heap.page_allocator, "TERM_PROGRAM")) |_| {
            const term_program = std.process.getEnvVarOwned(std.heap.page_allocator, "TERM_PROGRAM") catch return false;
            defer std.heap.page_allocator.free(term_program);

            if (std.mem.eql(u8, term_program, "Apple_Terminal") or std.mem.eql(u8, term_program, "iTerm.app")) {
                // On macOS, default to dark theme for now
                // In a full implementation, we could query the system appearance
                return false;
            }
        } else |_| {}

        // Default to dark theme
        return false;
    }

    /// Print available colors for debugging/demo purposes
    pub fn printColorDemo(self: Theme, writer: anytype) !void {
        const theme = self.current_theme;

        try writer.writeAll("🎨 Color Theme Demo:\n\n");

        // Primary colors
        try theme.primary.writeFg(writer, theme.caps);
        try writer.writeAll("■ Primary ");
        try theme.secondary.writeFg(writer, theme.caps);
        try writer.writeAll("■ Secondary ");
        try theme.accent.writeFg(writer, theme.caps);
        try writer.writeAll("■ Accent");
        try term_ansi.resetStyle(writer, theme.caps);
        try writer.writeAll("\n\n");

        // Text colors
        try theme.text_primary.writeFg(writer, theme.caps);
        try writer.writeAll("Primary text ");
        try theme.text_secondary.writeFg(writer, theme.caps);
        try writer.writeAll("Secondary text ");
        try theme.text_muted.writeFg(writer, theme.caps);
        try writer.writeAll("Muted text ");
        try theme.text_link.writeFg(writer, theme.caps);
        try writer.writeAll("Link text");
        try term_ansi.resetStyle(writer, theme.caps);
        try writer.writeAll("\n\n");

        // Status colors
        try theme.success.writeFg(writer, theme.caps);
        try writer.writeAll("✓ Success ");
        try theme.warning.writeFg(writer, theme.caps);
        try writer.writeAll("⚠ Warning ");
        try theme.err.writeFg(writer, theme.caps);
        try writer.writeAll("✗ Error ");
        try theme.info.writeFg(writer, theme.caps);
        try writer.writeAll("ℹ Info");
        try term_ansi.resetStyle(writer, theme.caps);
        try writer.writeAll("\n\n");

        // Syntax highlighting preview
        try writer.writeAll("Code syntax preview:\n");
        try theme.syntax_keyword.writeFg(writer, theme.caps);
        try writer.writeAll("const ");
        try theme.text_primary.writeFg(writer, theme.caps);
        try writer.writeAll("greeting ");
        try theme.text_secondary.writeFg(writer, theme.caps);
        try writer.writeAll("= ");
        try theme.syntax_string.writeFg(writer, theme.caps);
        try writer.writeAll("\"Hello, World!\"");
        try theme.text_secondary.writeFg(writer, theme.caps);
        try writer.writeAll("; ");
        try theme.syntax_comment.writeFg(writer, theme.caps);
        try writer.writeAll("// A greeting");
        try term_ansi.resetStyle(writer, theme.caps);
        try writer.writeAll("\n\n");

        // Terminal capabilities info
        try theme.text_muted.writeFg(writer, theme.caps);
        try writer.print("Terminal capabilities: TrueColor={} 256Color={} OSC={}\n", .{ theme.caps.supportsTrueColor(), theme.caps.supports256Color(), theme.caps.supportsColorOsc10_12 });
        try term_ansi.resetStyle(writer, theme.caps);
    }
};

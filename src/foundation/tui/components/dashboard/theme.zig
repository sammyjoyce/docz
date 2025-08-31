//! Dashboard Theme Integration
//! Provides theme support for the adaptive dashboard using the centralized theme system

const std = @import("std");
const theme = @import("../../../theme/mod.zig");
const term_caps = @import("../../../term/mod.zig");

/// Dashboard-specific theme colors and styles
pub const DashboardTheme = struct {
    allocator: std.mem.Allocator,

    // Background colors
    background: theme.ColorScheme.Color,
    surface: theme.ColorScheme.Color,

    // Text colors
    title_style: TextStyle,
    stats_style: TextStyle,
    footer_style: TextStyle,

    // Border and UI elements
    border_style: BorderStyle,

    // Terminal capabilities
    caps: term_caps.TermCaps,

    const Self = @This();

    /// Text style combining color and attributes
    pub const TextStyle = struct {
        color: theme.ColorScheme.Color,
        bold: bool = false,
        italic: bool = false,
        underline: bool = false,
    };

    /// Border style definition
    pub const BorderStyle = struct {
        color: theme.ColorScheme.Color,
        style: []const u8 = "─│┌┐└┘├┤┬┴┼",
    };

    /// Load theme by name with render level adaptation
    pub fn load(allocator: std.mem.Allocator, theme_name: []const u8, render_level: anytype) !DashboardTheme {
        // Get the centralized theme manager
        const manager = try theme.init(allocator);
        defer manager.deinit();

        // Switch to the requested theme
        try manager.switchTheme(theme_name);
        const color_scheme = manager.getCurrentTheme();

        // Get terminal capabilities
        const caps = term_caps.getTermCaps();

        // Create dashboard-specific theme from color scheme
        return Self{
            .allocator = allocator,
            .background = color_scheme.background,
            .surface = color_scheme.subtle,
            .title_style = .{
                .color = color_scheme.focus,
                .bold = true,
            },
            .stats_style = .{
                .color = color_scheme.tertiary,
                .bold = false,
            },
            .footer_style = .{
                .color = color_scheme.dimmed,
                .bold = false,
            },
            .border_style = .{
                .color = color_scheme.border,
            },
            .caps = caps,
        };
    }

    /// Deinitialize the theme
    pub fn deinit(self: *Self) void {
        // No dynamic allocation in this theme, so nothing to free
        _ = self;
    }

    /// Get theme description
    pub fn getDescription(self: Self) []const u8 {
        _ = self;
        return "Dashboard theme using centralized color scheme";
    }

    /// Check if theme is compatible with terminal capabilities
    pub fn isCompatible(self: Self, caps: term_caps.TermCaps) bool {
        _ = self;
        // Dashboard theme is compatible with basic color support
        return caps.supportsColor();
    }

    /// Apply theme settings to terminal
    pub fn applySettings(self: Self, writer: anytype, caps: term_caps.TermCaps) !void {
        _ = caps;
        // Apply background color if supported
        if (self.caps.supportsTrueColor()) {
            try writer.writeAll("\x1b[48;2;");
            try writer.print("{};{};{}m", .{
                self.background.rgb.r,
                self.background.rgb.g,
                self.background.rgb.b,
            });
        }
    }
};

//! Default CLI Theme
//! Balanced colors suitable for most terminal environments

const std = @import("std");
const colors = @import("colors.zig");

pub const Theme = struct {
    name: []const u8 = "default",
    colors: colors.SemanticColors = colors.default_colors,

    /// Initialize the default theme
    pub fn init() Theme {
        return .{};
    }

    /// Apply theme-specific terminal settings
    pub fn applySettings(self: Theme, writer: anytype, caps: anytype) !void {
        _ = self;
        _ = writer;
        _ = caps;
        // Default theme doesn't require special terminal configuration
    }

    /// Get theme description
    pub fn getDescription(self: Theme) []const u8 {
        _ = self;
        return "Balanced default theme suitable for most terminals";
    }

    /// Check if theme is suitable for current terminal capabilities
    pub fn isCompatible(self: Theme, caps: anytype) bool {
        _ = self;
        _ = caps;
        return true; // Default theme works with any terminal
    }
};

pub const default_theme = Theme.init();

//! Terminal Abstraction Layer
//!
//! This provides a unified interface to all terminal capabilities, standardizing
//! how CLI components interact with terminal features while providing progressive
//! enhancement based on detected capabilities.

const std = @import("std");
const unified = @import("../../src/shared/term/unified.zig");
const caps = @import("../../src/shared/term/caps.zig");

/// Unified terminal abstraction that all CLI components should use
pub const TerminalAbstraction = struct {
    terminal: *unified.Terminal,
    capabilities: caps.TermCaps,

    /// Feature flags for quick capability checking
    pub const Features = struct {
        truecolor: bool,
        graphics: bool, // Kitty or Sixel
        hyperlinks: bool,
        clipboard: bool,
        notifications: bool,
        mouse_support: bool,
        synchronized_output: bool,
        shell_integration: bool,
    };

    pub fn init(terminal: *unified.Terminal) TerminalAbstraction {
        const terminal_caps = terminal.getCapabilities();

        return TerminalAbstraction{
            .terminal = terminal,
            .capabilities = terminal_caps,
        };
    }

    /// Get feature flags for quick capability checking
    pub fn getFeatures(self: TerminalAbstraction) Features {
        return Features{
            .truecolor = self.capabilities.supportsTruecolor,
            .graphics = self.capabilities.supportsKittyGraphics or self.capabilities.supportsSixel,
            .hyperlinks = self.capabilities.supportsHyperlinkOsc8,
            .clipboard = self.capabilities.supportsClipboardOsc52,
            .notifications = self.capabilities.supportsNotifyOsc9,
            .mouse_support = self.capabilities.supportsSgrMouse or self.capabilities.supportsSgrPixelMouse,
            .synchronized_output = self.capabilities.supportsSynchronizedOutput,
            .shell_integration = self.capabilities.supportsFinalTermOsc133 or self.capabilities.supportsITerm2Osc1337,
        };
    }

    /// Standardized text output with optional styling
    pub fn print(self: TerminalAbstraction, text: []const u8, style: ?unified.Style) !void {
        try self.terminal.print(text, style);
    }

    /// Standardized formatted output
    pub fn printf(self: TerminalAbstraction, comptime fmt: []const u8, args: anytype, style: ?unified.Style) !void {
        try self.terminal.printf(fmt, args, style);
    }

    /// Clear screen with capability detection
    pub fn clear(self: TerminalAbstraction) !void {
        try self.terminal.clear();
    }

    /// Create hyperlink with fallback
    pub fn hyperlink(self: TerminalAbstraction, url: []const u8, text: []const u8, style: ?unified.Style) !void {
        try self.terminal.hyperlink(url, text, style);
    }

    /// Copy to clipboard with capability detection
    pub fn copyToClipboard(self: TerminalAbstraction, text: []const u8) !void {
        try self.terminal.copyToClipboard(text);
    }

    /// Send notification with fallback
    pub fn notify(self: TerminalAbstraction, level: unified.NotificationLevel, title: []const u8, message: []const u8) !void {
        try self.terminal.notification(level, title, message);
    }

    /// Move cursor to position
    pub fn moveTo(self: TerminalAbstraction, x: i32, y: i32) !void {
        try self.terminal.moveTo(x, y);
    }

    /// Show/hide cursor
    pub fn showCursor(self: TerminalAbstraction, visible: bool) !void {
        try self.terminal.showCursor(visible);
    }

    /// Create scoped context for automatic state restoration
    pub fn scopedContext(self: TerminalAbstraction) !unified.ScopedContext {
        return try self.terminal.scopedContext();
    }

    /// Access to underlying terminal for advanced operations
    pub fn getTerminal(self: TerminalAbstraction) *unified.Terminal {
        return self.terminal;
    }
};

/// Common color palette for consistent CLI styling
pub const CliColors = struct {
    pub const PRIMARY = unified.Color{ .rgb = .{ .r = 100, .g = 149, .b = 237 } }; // Cornflower blue
    pub const SUCCESS = unified.Color{ .rgb = .{ .r = 50, .g = 205, .b = 50 } }; // Lime green
    pub const WARNING = unified.Color{ .rgb = .{ .r = 255, .g = 215, .b = 0 } }; // Gold
    pub const ERROR = unified.Color{ .rgb = .{ .r = 220, .g = 20, .b = 60 } }; // Crimson
    pub const INFO = unified.Color{ .rgb = .{ .r = 135, .g = 206, .b = 235 } }; // Sky blue
    pub const MUTED = unified.Color{ .rgb = .{ .r = 128, .g = 128, .b = 128 } }; // Gray
    pub const ACCENT = unified.Color{ .rgb = .{ .r = 255, .g = 127, .b = 14 } }; // Orange
};

/// Common styles for CLI components
pub const CliStyles = struct {
    pub const HEADER = unified.Style{ .fg_color = CliColors.PRIMARY, .bold = true };
    pub const SUCCESS = unified.Style{ .fg_color = CliColors.SUCCESS, .bold = true };
    pub const WARNING = unified.Style{ .fg_color = CliColors.WARNING, .bold = true };
    pub const ERROR = unified.Style{ .fg_color = CliColors.ERROR, .bold = true };
    pub const INFO = unified.Style{ .fg_color = CliColors.INFO };
    pub const MUTED = unified.Style{ .fg_color = CliColors.MUTED };
    pub const ACCENT = unified.Style{ .fg_color = CliColors.ACCENT };
    pub const BOLD = unified.Style{ .bold = true };
    pub const ITALIC = unified.Style{ .italic = true };
    pub const UNDERLINE = unified.Style{ .underline = true };
};

/// Progress bar types that adapt to terminal capabilities
pub const ProgressType = enum {
    simple,
    unicode,
    gradient,
    animated,
    advanced, // Uses the new advanced progress component
};

/// Input field types with progressive enhancement
pub const InputType = enum {
    text,
    password,
    multiline,
    smart, // Smart input with validation and suggestions
    mouse_enabled, // Input with mouse support
};

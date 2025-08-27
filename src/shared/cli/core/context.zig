//! CLI Context
//! Central context that provides access to all terminal capabilities and shared state
//! This replaces the fragmented initialization patterns from multiple CLI entry points

const std = @import("std");
const term = @import("term_shared");
const ansi_clipboard = term.ansi.clipboard;
const ansi_notification = term.ansi.notification;
const ansi_graphics = term.ansi.graphics;
const ansi_hyperlink = term.ansi.hyperlink;
const types = @import("types.zig");

pub const ContextError = error{
    InitializationFailed,
    TerminalDetectionFailed,
    CapabilityQueryFailed,
    OutOfMemory,
};

/// Capability set representing what the current terminal can do
pub const Capability = struct {
    hyperlinks: bool = false,
    clipboard: bool = false,
    notifications: bool = false,
    graphics: bool = false,
    truecolor: bool = false,
    mouse: bool = false,

    pub fn detect(allocator: std.mem.Allocator) Capability {
        // For now, return basic capabilities since term.detectCapabilities doesn't exist yet
        // This would integrate with the actual terminal detection system
        _ = allocator;

        // Basic capability detection - this would be enhanced with real detection
        return Capability{
            .hyperlinks = true, // Most modern terminals support this
            .clipboard = true, // OSC 52 is widely supported
            .notifications = true, // OSC 9 is common
            .graphics = false, // Conservative default
            .truecolor = true, // Very common now
            .mouse = true, // Standard terminal feature
        };
    }
};

/// Notification manager for CLI operations
pub const Notification = struct {
    allocator: std.mem.Allocator,
    capabilities: Capability,
    termCaps: term.caps.TermCaps,
    terminal: *term.unified.Terminal,
    enabled: bool = true,

    pub const NotificationLevel = enum {
        info,
        success,
        warning,
        err, // error is reserved keyword
    };

    pub const NotificationData = struct {
        title: []const u8,
        body: ?[]const u8 = null,
        level: NotificationLevel = .info,
        sound: bool = false,
        duration: ?u32 = null, // seconds
    };

    pub fn init(allocator: std.mem.Allocator, capabilities: Capability, termCaps: term.caps.TermCaps, terminal: *term.unified.Terminal) Notification {
        return Notification{
            .allocator = allocator,
            .capabilities = capabilities,
            .termCaps = termCaps,
            .terminal = terminal,
        };
    }

    pub fn send(self: *Notification, notification: NotificationData) !void {
        if (!self.enabled) return;

        if (self.capabilities.notifications) {
            // Use system notifications via OSC sequences
            try ansi_notification.writeNotification(self.terminal.writer, self.allocator, self.termCaps, notification.body orelse notification.title);
        } else {
            // Fallback to formatted terminal output
            const level_prefix = switch (notification.level) {
                .info => "ℹ",
                .success => "✓",
                .warning => "⚠",
                .err => "✗",
            };

            if (notification.body) |body| {
                try self.terminal.printf("{s} {s}: {s}\n", .{ level_prefix, notification.title, body }, null);
            } else {
                try self.terminal.printf("{s} {s}\n", .{ level_prefix, notification.title }, null);
            }
        }
    }
};

/// Graphics manager for enhanced visual elements
pub const Graphics = struct {
    allocator: std.mem.Allocator,
    capabilities: Capability,
    terminal: *term.unified.Terminal,

    pub fn init(allocator: std.mem.Allocator, capabilities: Capability, terminal: *term.unified.Terminal) Graphics {
        return Graphics{
            .allocator = allocator,
            .capabilities = capabilities,
            .terminal = terminal,
        };
    }

    pub fn isAvailable(self: *Graphics) bool {
        return self.capabilities.graphics;
    }

    pub fn showProgress(self: *Graphics, progress: f32) !void {
        if (self.capabilities.graphics) {
            // Use advanced graphics for progress (charts, graphics)
            // For now, fall back to ASCII since renderProgressBar doesn't exist
            // TODO: Implement proper graphics progress bar
        }

        // ASCII progress bar
        const width = 40;
        const filled = @as(usize, @intFromFloat(progress * @as(f32, @floatFromInt(width))));

        try self.terminal.printf("[", .{}, null);
        for (0..width) |i| {
            if (i < filled) {
                try self.terminal.printf("█", .{}, null);
            } else {
                try self.terminal.printf("░", .{}, null);
            }
        }
        try self.terminal.printf("] {d:.1}%\r", .{progress * 100}, null);
    }
};

/// Clipboard manager for copy/paste operations
pub const Clipboard = struct {
    allocator: std.mem.Allocator,
    capabilities: Capability,
    termCaps: term.caps.TermCaps,
    terminal: *term.unified.Terminal,

    pub fn init(allocator: std.mem.Allocator, capabilities: Capability, termCaps: term.caps.TermCaps, terminal: *term.unified.Terminal) Clipboard {
        return Clipboard{
            .allocator = allocator,
            .capabilities = capabilities,
            .termCaps = termCaps,
            .terminal = terminal,
        };
    }

    pub fn copy(self: *Clipboard, data: []const u8) !void {
        if (self.capabilities.clipboard) {
            try ansi_clipboard.writeClipboardDefault(self.terminal.writer, self.allocator, self.termCaps, data);
        } else {
            // Fallback: display data and suggest manual copy
            try self.terminal.printf("Copy the following to clipboard:\n{s}\n", .{data}, null);
        }
    }

    pub fn isAvailable(self: *Clipboard) bool {
        return self.capabilities.clipboard;
    }
};

/// Hyperlink manager for clickable links
pub const Hyperlink = struct {
    allocator: std.mem.Allocator,
    capabilities: Capability,
    termCaps: term.caps.TermCaps,
    terminal: *term.unified.Terminal,

    pub fn init(allocator: std.mem.Allocator, capabilities: Capability, termCaps: term.caps.TermCaps, terminal: *term.unified.Terminal) Hyperlink {
        return Hyperlink{
            .allocator = allocator,
            .capabilities = capabilities,
            .termCaps = termCaps,
            .terminal = terminal,
        };
    }

    pub fn writeLink(self: *Hyperlink, url: []const u8, text: []const u8) !void {
        if (self.capabilities.hyperlinks) {
            try ansi_hyperlink.writeHyperlink(self.terminal.writer, self.allocator, self.termCaps, url, text);
        } else {
            try self.terminal.printf("{s} ({s})", .{ text, url }, null);
        }
    }

    pub fn isAvailable(self: *Hyperlink) bool {
        return self.capabilities.hyperlinks;
    }
};

/// Main CLI context that ties everything together
pub const Cli = struct {
    allocator: std.mem.Allocator,
    capabilities: Capability,
    termCaps: term.caps.TermCaps,
    terminal: term.unified.Terminal,
    notification: Notification,
    graphics: Graphics,
    clipboard: Clipboard,
    hyperlink: Hyperlink,
    config: types.Config,
    verbose: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Cli {
        // Detect terminal capabilities
        const capabilities = Capability.detect(allocator);
        const termCaps = try term.caps.detectCaps(allocator);

        // Initialize unified terminal
        var terminal = try term.unified.Terminal.init(allocator);

        // Load configuration
        const config = types.Config.loadDefault(allocator);

        return Cli{
            .allocator = allocator,
            .capabilities = capabilities,
            .termCaps = termCaps,
            .terminal = terminal,
            .notification = Notification.init(allocator, capabilities, termCaps, &terminal),
            .graphics = Graphics.init(allocator, capabilities, &terminal),
            .clipboard = Clipboard.init(allocator, capabilities, termCaps, &terminal),
            .hyperlink = Hyperlink.init(allocator, capabilities, termCaps, &terminal),
            .config = config,
        };
    }

    pub fn deinit(self: *Cli) void {
        self.terminal.deinit();
        self.config.deinit(self.allocator);
    }

    /// Get a summary of available capabilities for debugging
    pub fn capabilitySummary(self: *Cli) []const u8 {
        // This could be enhanced to provide detailed capability info
        if (self.capabilities.hyperlinks and self.capabilities.clipboard and self.capabilities.graphics) {
            return "Full Enhanced Terminal";
        } else if (self.capabilities.hyperlinks or self.capabilities.clipboard) {
            return "Enhanced Terminal";
        } else {
            return "Basic Terminal";
        }
    }

    /// Enable verbose mode for detailed output
    pub fn enableVerbose(self: *Cli) void {
        self.verbose = true;
    }

    /// Check if a specific feature is available
    pub fn hasFeature(self: *Cli, feature: enum { hyperlinks, clipboard, notifications, graphics, truecolor, mouse }) bool {
        return switch (feature) {
            .hyperlinks => self.capabilities.hyperlinks,
            .clipboard => self.capabilities.clipboard,
            .notifications => self.capabilities.notifications,
            .graphics => self.capabilities.graphics,
            .truecolor => self.capabilities.truecolor,
            .mouse => self.capabilities.mouse,
        };
    }

    /// Log a message if verbose mode is enabled
    pub fn verboseLog(self: *Cli, comptime fmt: []const u8, args: anytype) void {
        if (self.verbose) {
            self.terminal.printf("[VERBOSE] " ++ fmt ++ "\n", args, null) catch {};
        }
    }
};

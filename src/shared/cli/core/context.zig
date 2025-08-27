//! Unified CLI Context
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
pub const CapabilitySet = struct {
    hyperlinks: bool = false,
    clipboard: bool = false,
    notifications: bool = false,
    graphics: bool = false,
    truecolor: bool = false,
    mouse: bool = false,

    pub fn detect(allocator: std.mem.Allocator) CapabilitySet {
        // For now, return basic capabilities since term.detectCapabilities doesn't exist yet
        // This would integrate with the actual terminal detection system
        _ = allocator;

        // Basic capability detection - this would be enhanced with real detection
        return CapabilitySet{
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
pub const NotificationHandler = struct {
    allocator: std.mem.Allocator,
    capabilities: CapabilitySet,
    termCaps: term.caps.TermCaps,
    enabled: bool = true,

    pub const NotificationLevel = enum {
        info,
        success,
        warning,
        err, // error is reserved keyword
    };

    pub const Notification = struct {
        title: []const u8,
        body: ?[]const u8 = null,
        level: NotificationLevel = .info,
        sound: bool = false,
        duration: ?u32 = null, // seconds
    };

    pub fn init(allocator: std.mem.Allocator, capabilities: CapabilitySet, termCaps: term.caps.TermCaps) NotificationHandler {
        return NotificationHandler{
            .allocator = allocator,
            .capabilities = capabilities,
            .termCaps = termCaps,
        };
    }

    pub fn send(self: *NotificationHandler, notification: Notification) !void {
        if (!self.enabled) return;

        if (self.capabilities.notifications) {
            // Use system notifications via OSC sequences
            var stdoutBuffer: [4096]u8 = undefined;
            var stdoutWriter = std.fs.File.stdout().writer(&stdoutBuffer);
            try ansi_notification.writeNotification(&stdoutWriter.interface, self.allocator, self.termCaps, notification.body orelse notification.title);
        } else {
            // Fallback to formatted terminal output
            const level_prefix = switch (notification.level) {
                .info => "ℹ",
                .success => "✓",
                .warning => "⚠",
                .err => "✗",
            };

            if (notification.body) |body| {
                std.debug.print("{s} {s}: {s}\n", .{ level_prefix, notification.title, body });
            } else {
                std.debug.print("{s} {s}\n", .{ level_prefix, notification.title });
            }
        }
    }
};

/// Graphics manager for enhanced visual elements
pub const Graphics = struct {
    allocator: std.mem.Allocator,
    capabilities: CapabilitySet,

    pub fn init(allocator: std.mem.Allocator, capabilities: CapabilitySet) Graphics {
        return Graphics{
            .allocator = allocator,
            .capabilities = capabilities,
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

        std.debug.print("[");
        for (0..width) |i| {
            if (i < filled) {
                std.debug.print("█");
            } else {
                std.debug.print("░");
            }
        }
        std.debug.print("] {d:.1}%\r", .{progress * 100});
    }
};

/// Clipboard manager for copy/paste operations
pub const Clipboard = struct {
    allocator: std.mem.Allocator,
    capabilities: CapabilitySet,
    termCaps: term.caps.TermCaps,

    pub fn init(allocator: std.mem.Allocator, capabilities: CapabilitySet, termCaps: term.caps.TermCaps) Clipboard {
        return Clipboard{
            .allocator = allocator,
            .capabilities = capabilities,
            .termCaps = termCaps,
        };
    }

    pub fn copy(self: *Clipboard, data: []const u8) !void {
        if (self.capabilities.clipboard) {
            var stdoutBuffer: [4096]u8 = undefined;
            var stdoutWriter = std.fs.File.stdout().writer(&stdoutBuffer);
            try ansi_clipboard.writeClipboardDefault(&stdoutWriter.interface, self.allocator, self.termCaps, data);
        } else {
            // Fallback: display data and suggest manual copy
            std.debug.print("Copy the following to clipboard:\n{s}\n", .{data});
        }
    }

    pub fn isAvailable(self: *Clipboard) bool {
        return self.capabilities.clipboard;
    }
};

/// Hyperlink manager for clickable links
pub const Hyperlink = struct {
    allocator: std.mem.Allocator,
    capabilities: CapabilitySet,
    termCaps: term.caps.TermCaps,

    pub fn init(allocator: std.mem.Allocator, capabilities: CapabilitySet, termCaps: term.caps.TermCaps) Hyperlink {
        return Hyperlink{
            .allocator = allocator,
            .capabilities = capabilities,
            .termCaps = termCaps,
        };
    }

    pub fn writeLink(self: *Hyperlink, writer: anytype, url: []const u8, text: []const u8) !void {
        if (self.capabilities.hyperlinks) {
            try ansi_hyperlink.writeHyperlink(writer, self.allocator, self.termCaps, url, text);
        } else {
            try writer.print("{s} ({s})", .{ text, url });
        }
    }

    pub fn isAvailable(self: *Hyperlink) bool {
        return self.capabilities.hyperlinks;
    }
};

/// Main CLI context that ties everything together
pub const Cli = struct {
    allocator: std.mem.Allocator,
    capabilities: CapabilitySet,
    termCaps: term.caps.TermCaps,
    notification: NotificationHandler,
    graphics: Graphics,
    clipboard: Clipboard,
    hyperlink: Hyperlink,
    config: types.Config,
    verbose: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Cli {
        // Detect terminal capabilities
        const capabilities = CapabilitySet.detect(allocator);
        const termCaps = try term.caps.detectCaps(allocator);

        // Load configuration
        const config = types.Config.loadDefault(allocator);

        return Cli{
            .allocator = allocator,
            .capabilities = capabilities,
            .termCaps = termCaps,
            .notification = NotificationHandler.init(allocator, capabilities, termCaps),
            .graphics = Graphics.init(allocator, capabilities),
            .clipboard = Clipboard.init(allocator, capabilities, termCaps),
            .hyperlink = Hyperlink.init(allocator, capabilities, termCaps),
            .config = config,
        };
    }

    pub fn deinit(self: *Cli) void {
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
            std.debug.print("[VERBOSE] " ++ fmt ++ "\n", args);
        }
    }
};

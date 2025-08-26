//! Unified CLI Context
//! Central context that provides access to all terminal capabilities and shared state
//! This replaces the fragmented initialization patterns from multiple CLI entry points

const std = @import("std");
const term = @import("term_shared");
const ansi_clipboard = term.ansi.clipboard;
const ansi_notifications = term.ansi.notifications;
const ansi_graphics = term.ansi.graphics;
const ansi_hyperlinks = term.ansi.hyperlinks;
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
            .hyperlinks = true,  // Most modern terminals support this
            .clipboard = true,   // OSC 52 is widely supported
            .notifications = true, // OSC 9 is common
            .graphics = false,   // Conservative default
            .truecolor = true,   // Very common now
            .mouse = true,       // Standard terminal feature
        };
    }
};

/// Notification manager for CLI operations
pub const NotificationManager = struct {
    allocator: std.mem.Allocator,
    capabilities: CapabilitySet,
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
    
    pub fn init(allocator: std.mem.Allocator, capabilities: CapabilitySet) NotificationManager {
        return NotificationManager{
            .allocator = allocator,
            .capabilities = capabilities,
        };
    }
    
    pub fn send(self: *NotificationManager, notification: Notification) !void {
        if (!self.enabled) return;
        
        if (self.capabilities.notifications) {
            // Use system notifications via OSC sequences
            try ansi_notifications.sendNotification(.{
                .title = notification.title,
                .body = notification.body orelse "",
                .sound = notification.sound,
            });
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
pub const GraphicsManager = struct {
    allocator: std.mem.Allocator,
    capabilities: CapabilitySet,
    
    pub fn init(allocator: std.mem.Allocator, capabilities: CapabilitySet) GraphicsManager {
        return GraphicsManager{
            .allocator = allocator,
            .capabilities = capabilities,
        };
    }
    
    pub fn isAvailable(self: *GraphicsManager) bool {
        return self.capabilities.graphics;
    }
    
    pub fn showProgress(self: *GraphicsManager, progress: f32) !void {
        if (self.capabilities.graphics) {
            // Use advanced graphics for progress (charts, graphics)
            try ansi_graphics.renderProgressBar(progress);
        } else {
            // Fallback to ASCII progress bar
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
    }
};

/// Clipboard manager for copy/paste operations
pub const ClipboardManager = struct {
    allocator: std.mem.Allocator,
    capabilities: CapabilitySet,
    
    pub fn init(allocator: std.mem.Allocator, capabilities: CapabilitySet) ClipboardManager {
        return ClipboardManager{
            .allocator = allocator,
            .capabilities = capabilities,
        };
    }
    
    pub fn copy(self: *ClipboardManager, data: []const u8) !void {
        if (self.capabilities.clipboard) {
            try ansi_clipboard.copy(data);
        } else {
            // Fallback: display data and suggest manual copy
            std.debug.print("Copy the following to clipboard:\n{s}\n", .{data});
        }
    }
    
    pub fn isAvailable(self: *ClipboardManager) bool {
        return self.capabilities.clipboard;
    }
};

/// Hyperlink manager for clickable links
pub const HyperlinkManager = struct {
    allocator: std.mem.Allocator,
    capabilities: CapabilitySet,
    
    pub fn init(allocator: std.mem.Allocator, capabilities: CapabilitySet) HyperlinkManager {
        return HyperlinkManager{
            .allocator = allocator,
            .capabilities = capabilities,
        };
    }
    
    pub fn writeLink(self: *HyperlinkManager, writer: anytype, url: []const u8, text: []const u8) !void {
        if (self.capabilities.hyperlinks) {
            try ansi_hyperlinks.writeHyperlink(writer, url, text);
        } else {
            try writer.print("{s} ({s})", .{ text, url });
        }
    }
    
    pub fn isAvailable(self: *HyperlinkManager) bool {
        return self.capabilities.hyperlinks;
    }
};

/// Main CLI context that ties everything together
pub const CliContext = struct {
    allocator: std.mem.Allocator,
    capabilities: CapabilitySet,
    notification: NotificationManager,
    graphics: GraphicsManager,
    clipboard: ClipboardManager,
    hyperlink: HyperlinkManager,
    config: types.Config,
    verbose: bool = false,
    
    pub fn init(allocator: std.mem.Allocator) !CliContext {
        // Detect terminal capabilities
        const capabilities = CapabilitySet.detect(allocator);
        
        // Load configuration
        const config = types.Config.loadDefault(allocator);
        
        return CliContext{
            .allocator = allocator,
            .capabilities = capabilities,
            .notification = NotificationManager.init(allocator, capabilities),
            .graphics = GraphicsManager.init(allocator, capabilities),
            .clipboard = ClipboardManager.init(allocator, capabilities),
            .hyperlink = HyperlinkManager.init(allocator, capabilities),
            .config = config,
        };
    }
    
    pub fn deinit(self: *CliContext) void {
        self.config.deinit(self.allocator);
    }
    
    /// Get a summary of available capabilities for debugging
    pub fn capabilitySummary(self: *CliContext) []const u8 {
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
    pub fn enableVerbose(self: *CliContext) void {
        self.verbose = true;
    }
    
    /// Check if a specific feature is available
    pub fn hasFeature(self: *CliContext, feature: enum { hyperlinks, clipboard, notifications, graphics, truecolor, mouse }) bool {
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
    pub fn verbose_log(self: *CliContext, comptime fmt: []const u8, args: anytype) void {
        if (self.verbose) {
            std.debug.print("[VERBOSE] " ++ fmt ++ "\n", args);
        }
    }
};

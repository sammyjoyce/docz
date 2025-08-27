//! Comprehensive UX Framework for Terminal AI Agents
//! Provides reusable patterns and components that elevate the user experience
//! across all agents to a professional level.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import shared infrastructure
const cli = @import("../shared/cli/mod.zig");
const tui = @import("../shared/tui/mod.zig");
const render = @import("../shared/render/mod.zig");
const components = @import("../shared/components/mod.zig");
const term = @import("../shared/term/mod.zig");
const auth = @import("../shared/auth/core/mod.zig");

// Import core modules
const base_agent = @import("agent_base.zig");
const config = @import("config.zig");
const session = @import("session.zig");

/// Standard Agent Interface - Comprehensive base interface that agents can inherit
/// Provides dashboard layout, session management, command palette, notifications, and help system
pub const StandardAgentInterface = struct {
    allocator: Allocator,
    base_agent: *base_agent.BaseAgent,
    command_palette: ?*cli.interactive.CommandPalette = null,
    notification_system: ?*tui.components.notification_system.NotificationSystem = null,
    help_system: ?*HelpSystem = null,
    theme_manager: ?*cli.themes.ThemeManager = null,

    const Self = @This();

    /// Initialize the standard agent interface
    pub fn init(allocator: Allocator, base_agent_ptr: *base_agent.BaseAgent) !StandardAgentInterface {
        return Self{
            .allocator = allocator,
            .base_agent = base_agent_ptr,
        };
    }

    /// Enable CLI mode with essential components
    pub fn enableCLIMode(self: *StandardAgentInterface) !void {
        // Initialize command palette for CLI
        self.command_palette = try cli.interactive.CommandPalette.init(self.allocator);

        // Initialize notification system
        self.notification_system = try tui.components.notification_system.NotificationSystem.init(self.allocator, true);

        // Initialize help system
        self.help_system = try HelpSystem.init(self.allocator);
    }

    /// Start the main interaction loop
    pub fn startMainLoop(self: *StandardAgentInterface) !void {
        try self.startCLILoop();
    }

    /// Start CLI interaction loop
    fn startCLILoop(self: *StandardAgentInterface) !void {
        const stdout = std.io.getStdOut().writer();
        const stdin = std.io.getStdIn().reader();

        try stdout.print("🤖 Agent ready. Type 'help' for commands or 'quit' to exit.\n", .{});

        var buffer: [1024]u8 = undefined;
        while (true) {
            try stdout.print("\n> ", .{});
            const line = try stdin.readUntilDelimiterOrEof(&buffer, '\n') orelse break;
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

            if (std.mem.eql(u8, trimmed, "quit") or std.mem.eql(u8, trimmed, "exit")) {
                break;
            } else if (std.mem.eql(u8, trimmed, "help")) {
                try self.showHelp();
            } else if (std.mem.eql(u8, trimmed, "status")) {
                try self.showStatus();
            } else if (std.mem.startsWith(u8, trimmed, "theme")) {
                try self.handleThemeCommand(trimmed);
            } else {
                // Process as agent command
                try self.processCommand(trimmed);
            }
        }
    }

    /// Show help information
    fn showHelp(self: *StandardAgentInterface) !void {
        if (self.help_system) |help| {
            try help.displayHelp(std.io.getStdOut().writer());
        } else {
            const stdout = std.io.getStdOut().writer();
            try stdout.print(
                \\Available commands:
                \\  help     - Show this help
                \\  status   - Show agent status
                \\  quit     - Exit the agent
                \\
            , .{});
        }
    }

    /// Show agent status
    fn showStatus(self: *StandardAgentInterface) !void {
        const stdout = std.io.getStdOut().writer();
        const stats = self.base_agent.getSessionStats();
        const auth_status = try self.base_agent.getAuthStatusText();
        defer self.allocator.free(auth_status);

        try stdout.print(
            \\Agent Status:
            \\  Sessions: {d}
            \\  Messages: {d}
            \\  Auth: {s}
            \\  Theme: {s}
            \\
        , .{
            stats.total_sessions,
            stats.total_messages,
            auth_status,
            if (self.base_agent.isDarkTheme()) "dark" else "light",
        });
    }

    /// Handle theme commands
    fn handleThemeCommand(self: *StandardAgentInterface, command: []const u8) !void {
        const stdout = std.io.getStdOut().writer();
        if (std.mem.eql(u8, command, "theme")) {
            try stdout.print("Available themes: dark, light, high-contrast\n", .{});
            try stdout.print("Current: {s}\n", .{if (self.base_agent.isDarkTheme()) "dark" else "light"});
        } else if (std.mem.startsWith(u8, command, "theme ")) {
            const theme_name = command[6..];
            if (std.mem.eql(u8, theme_name, "dark")) {
                // Switch to dark theme
                try stdout.print("Switched to dark theme\n", .{});
            } else if (std.mem.eql(u8, theme_name, "light")) {
                // Switch to light theme
                try stdout.print("Switched to light theme\n", .{});
            } else {
                try stdout.print("Unknown theme: {s}\n", .{theme_name});
            }
        }
    }

    /// Process agent-specific commands
    fn processCommand(_: *StandardAgentInterface, command: []const u8) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Processing: {s}\n", .{command});
        // This would be overridden by specific agents
    }

    /// Display notification
    pub fn showNotification(self: *StandardAgentInterface, title: []const u8, message: []const u8, notification_type: tui.components.notification_system.NotificationType) !void {
        if (self.notification_system) |notif_system| {
            try notif_system.show(.{
                .title = title,
                .message = message,
                .type = notification_type,
                .timestamp = std.time.milliTimestamp(),
                .duration_ms = 3000, // 3 seconds
            });
        } else {
            const stdout = std.io.getStdOut().writer();
            const icon = switch (notification_type) {
                .info => "ℹ️",
                .success => "✅",
                .warning => "⚠️",
                .err => "❌",
            };
            try stdout.print("{s} {s}: {s}\n", .{ icon, title, message });
        }
    }

    /// Cleanup resources
    pub fn deinit(self: *StandardAgentInterface) void {
        if (self.command_palette) |palette| {
            palette.deinit();
        }
        if (self.notification_system) |notif_system| {
            notif_system.deinit();
        }
        if (self.help_system) |help| {
            help.deinit();
        }
        if (self.theme_manager) |theme_mgr| {
            theme_mgr.deinit();
        }
    }
};

/// Help System - Comprehensive help with keyboard shortcuts and documentation
pub const HelpSystem = struct {
    allocator: Allocator,
    topics: std.StringHashMap(HelpTopic),
    shortcuts: std.ArrayList(KeyboardShortcut),
    current_topic: ?[]const u8 = null,

    pub const HelpTopic = struct {
        id: []const u8,
        title: []const u8,
        content: []const u8,
        category: []const u8,
        related_topics: std.ArrayList([]const u8),
        last_updated: i64 = 0,
    };

    pub const KeyboardShortcut = struct {
        keys: []const u8,
        description: []const u8,
        category: []const u8,
        context: []const u8 = "global",
    };

    /// Initialize help system
    pub fn init(allocator: Allocator) !HelpSystem {
        var help = HelpSystem{
            .allocator = allocator,
            .topics = std.StringHashMap(HelpTopic).init(allocator),
            .shortcuts = std.ArrayList(KeyboardShortcut).init(allocator),
        };

        try help.initDefaultContent();
        return help;
    }

    /// Initialize default help content
    fn initDefaultContent(self: *HelpSystem) !void {
        // Basic commands topic
        var basic_related = std.ArrayList([]const u8).init(self.allocator);
        try basic_related.append("getting_started");
        try basic_related.append("advanced_commands");

        try self.addTopic(HelpTopic{
            .id = "basic_commands",
            .title = "Basic Commands",
            .content =
            \\🤖 Basic Commands
            \\
            \\• help - Show this help system
            \\• status - Display agent status and metrics
            \\• quit/exit - Exit the agent
            \\• clear - Clear the screen
            \\• history - Show command history
            \\
            \\For more detailed help, try: help <topic>
            ,
            .category = "commands",
            .related_topics = basic_related,
            .last_updated = std.time.timestamp(),
        });

        // Getting started topic
        var getting_started_related = std.ArrayList([]const u8).init(self.allocator);
        try getting_started_related.append("basic_commands");
        try getting_started_related.append("tools");

        try self.addTopic(HelpTopic{
            .id = "getting_started",
            .title = "Getting Started",
            .content =
            \\🚀 Getting Started
            \\
            \\Welcome to your AI Agent! Here's how to get started:
            \\
            \\1. Type any question or request in natural language
            \\2. Use 'help' to see available commands
            \\3. Try 'status' to see agent information
            \\4. Use 'tools' to see available tools
            \\
            \\The agent will respond conversationally and can use
            \\specialized tools to help with specific tasks.
            ,
            .category = "tutorial",
            .related_topics = getting_started_related,
            .last_updated = std.time.timestamp(),
        });

        // Tools topic
        var tools_related = std.ArrayList([]const u8).init(self.allocator);
        try tools_related.append("basic_commands");
        try tools_related.append("advanced_usage");

        try self.addTopic(HelpTopic{
            .id = "tools",
            .title = "Available Tools",
            .content =
            \\🔧 Available Tools
            \\
            \\Your agent comes with various tools to help with tasks:
            \\
            \\• File operations - Read, write, and manage files
            \\• Network requests - Make HTTP requests and APIs
            \\• System commands - Execute system operations
            \\• Data processing - Parse and manipulate data
            \\• Search and analysis - Find and analyze information
            \\
            \\Use 'tools' command to see all available tools.
            ,
            .category = "tools",
            .related_topics = tools_related,
            .last_updated = std.time.timestamp(),
        });

        // Keyboard shortcuts
        const shortcuts = [_]KeyboardShortcut{
            .{ .keys = "Ctrl+C", .description = "Interrupt current operation", .category = "global" },
            .{ .keys = "Ctrl+D", .description = "Exit agent", .category = "global" },
            .{ .keys = "↑/↓", .description = "Navigate command history", .category = "input" },
            .{ .keys = "Tab", .description = "Auto-complete commands and paths", .category = "input" },
            .{ .keys = "Ctrl+R", .description = "Search command history", .category = "input" },
            .{ .keys = "F1", .description = "Show help", .category = "global" },
            .{ .keys = "F2", .description = "Show tools palette", .category = "global" },
        };

        for (shortcuts) |shortcut| {
            try self.shortcuts.append(shortcut);
        }
    }

    /// Add a help topic
    pub fn addTopic(self: *HelpSystem, topic: HelpTopic) !void {
        try self.topics.put(try self.allocator.dupe(u8, topic.id), topic);
    }

    /// Display help information
    pub fn displayHelp(self: *HelpSystem, writer: anytype) !void {
        if (self.current_topic) |topic_id| {
            try self.displayTopic(topic_id, writer);
        } else {
            try self.displayHelpIndex(writer);
        }
    }

    /// Display help index
    fn displayHelpIndex(self: *HelpSystem, writer: anytype) !void {
        try writer.print("📚 Help System\n", .{});
        try writer.print("=============\n\n", .{});

        try writer.print("📖 Available Topics:\n", .{});
        var topic_iter = self.topics.iterator();
        while (topic_iter.next()) |entry| {
            const topic = entry.value_ptr.*;
            try writer.print("   • {s} - {s}\n", .{ topic.title, topic.content[0..@min(50, topic.content.len)] });
            if (topic.content.len > 50) {
                try writer.print("...\n", .{});
            }
        }

        try writer.print("\n⌨️  Keyboard Shortcuts:\n", .{});
        for (self.shortcuts.items) |shortcut| {
            try writer.print("   • {s:<10} - {s}\n", .{ shortcut.keys, shortcut.description });
        }

        try writer.print("\n💡 Type 'help <topic>' for detailed information\n", .{});
        try writer.print("   Type 'shortcuts' to see all keyboard shortcuts\n", .{});
    }

    /// Display specific topic
    fn displayTopic(self: *HelpSystem, topic_id: []const u8, writer: anytype) !void {
        const topic = self.topics.get(topic_id) orelse {
            try writer.print("❌ Topic '{s}' not found.\n", .{topic_id});
            try writer.print("   Type 'help' to see available topics.\n", .{});
            return;
        };

        try writer.print("📖 {s}\n", .{topic.title});
        try writer.print("{s}\n", .{topic.content});

        if (topic.related_topics.items.len > 0) {
            try writer.print("\n📚 Related Topics:\n", .{});
            for (topic.related_topics.items) |related| {
                if (self.topics.get(related)) |related_topic| {
                    try writer.print("   • {s}\n", .{related_topic.title});
                }
            }
        }
    }

    /// Set current topic
    pub fn setCurrentTopic(self: *HelpSystem, topic_id: ?[]const u8) void {
        if (topic_id) |id| {
            if (self.topics.get(id)) |_| {
                self.current_topic = id;
            }
        } else {
            self.current_topic = null;
        }
    }

    /// Search help content
    pub fn search(self: *HelpSystem, query: []const u8) ![]HelpTopic {
        var results = std.ArrayList(HelpTopic).init(self.allocator);
        errdefer results.deinit();

        var topic_iter = self.topics.iterator();
        while (topic_iter.next()) |entry| {
            const topic = entry.value_ptr.*;
            if (std.mem.indexOf(u8, topic.title, query) != null or
                std.mem.indexOf(u8, topic.content, query) != null or
                std.mem.indexOf(u8, topic.category, query) != null)
            {
                try results.append(topic);
            }
        }

        return results.toOwnedSlice();
    }

    /// Display keyboard shortcuts
    pub fn displayShortcuts(self: *HelpSystem, writer: anytype) !void {
        try writer.print("⌨️  Keyboard Shortcuts\n", .{});
        try writer.print("===================\n\n", .{});

        // Group by category
        var categories = std.StringHashMap(std.ArrayList(KeyboardShortcut)).init(self.allocator);
        defer {
            var cat_iter = categories.iterator();
            while (cat_iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            categories.deinit();
        }

        for (self.shortcuts.items) |shortcut| {
            const category_list = categories.getOrPut(shortcut.category) catch continue;
            if (category_list.found_existing) {
                try category_list.value_ptr.append(shortcut);
            } else {
                var list = std.ArrayList(KeyboardShortcut).init(self.allocator);
                try list.append(shortcut);
                category_list.value_ptr.* = list;
            }
        }

        var cat_iter = categories.iterator();
        while (cat_iter.next()) |entry| {
            try writer.print("📁 {s}:\n", .{entry.key_ptr.*});
            for (entry.value_ptr.items) |shortcut| {
                try writer.print("   • {s:<12} - {s}", .{ shortcut.keys, shortcut.description });
                if (shortcut.context.len > 0 and !std.mem.eql(u8, shortcut.context, "global")) {
                    try writer.print(" ({s})", .{shortcut.context});
                }
                try writer.print("\n", .{});
            }
            try writer.print("\n", .{});
        }
    }

    /// Add keyboard shortcut
    pub fn addShortcut(self: *HelpSystem, shortcut: KeyboardShortcut) !void {
        try self.shortcuts.append(shortcut);
    }

    /// Get shortcut by keys
    pub fn getShortcut(self: *HelpSystem, keys: []const u8) ?KeyboardShortcut {
        for (self.shortcuts.items) |shortcut| {
            if (std.mem.eql(u8, shortcut.keys, keys)) {
                return shortcut;
            }
        }
        return null;
    }

    /// Cleanup resources
    pub fn deinit(self: *HelpSystem) void {
        var topic_iter = self.topics.iterator();
        while (topic_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var related_iter = entry.value_ptr.related_topics.iterator();
            while (related_iter.next()) |related| {
                self.allocator.free(related.*);
            }
            entry.value_ptr.related_topics.deinit();
        }
        self.topics.deinit();
        self.shortcuts.deinit();
    }
};

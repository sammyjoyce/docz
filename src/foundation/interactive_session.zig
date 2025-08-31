//! Rich TUI interface for session management and visualization.
//! Provides comprehensive session browsing, monitoring, playback, and analytics.

const std = @import("std");
const Allocator = std.mem.Allocator;
const session = @import("session.zig");
const term = @import("term.zig");

// Re-export session types for use by other modules
pub const Sessions = session.Sessions;
pub const SessionStats = session.SessionStats;
pub const SessionHelpers = session.SessionHelpers;
pub const SessionConfig = session.SessionConfig;
pub const generateSessionId = session.generateSessionId;

/// Configuration for interactive sessions
pub const InteractiveConfig = struct {
    /// Enable interactive mode
    interactive: bool = true,
    /// Enable TUI interface
    enableTui: bool = false,
    /// Enable dashboard display
    enableDashboard: bool = false,
    /// Enable authentication
    enableAuth: bool = true,
    /// Session title
    title: []const u8 = "AI Agent Interactive Session",
    /// Maximum input length
    inputLengthMax: usize = 4096,
    /// Enable multi-line input
    multiLine: bool = true,
    /// Show session statistics
    showStats: bool = true,
};

/// Main session browser interface with rich TUI features
pub const Browser = struct {
    allocator: Allocator,
    sessionManager: *session.Sessions,
    terminal: term.TerminalInterface,
    currentView: ViewType = .list,
    selectedSession: ?[]const u8 = null,

    /// Available view types for the session browser
    pub const ViewType = enum {
        list, // Session list with thumbnails/cards
        timeline, // Timeline view of session history
        details, // Detailed session information
        playback, // Conversation playback with controls
        analytics, // Usage analytics and cost tracking
        monitor, // Live session monitoring
    };

    /// Initialize the session browser
    pub fn init(allocator: Allocator, sessionManager: *session.Sessions) !Browser {
        return Browser{
            .allocator = allocator,
            .sessionManager = sessionManager,
            .terminal = try term.Terminal.init(allocator),
        };
    }

    /// Deinitialize the session browser
    pub fn deinit(self: *Browser) void {
        if (self.selectedSession) |sessionId| {
            self.allocator.free(sessionId);
        }
        self.terminal.deinit();
    }

    /// Run the interactive session browser
    pub fn run(self: *Browser) !void {
        try self.terminal.clear();

        // Display the main interface
        try self.displayMainInterface();

        // In a full implementation, this would handle user input in a loop
        // For now, we just display the interface once
    }

    /// Display the main session browser interface
    pub fn displayMainInterface(self: *Browser) !void {
        // Header
        try self.displayHeader();

        // Navigation tabs
        try self.displayNavigationTabs();

        // Main content area
        switch (self.currentView) {
            .list => try self.displaySessionList(),
            .timeline => try self.displayTimelineView(),
            .details => try self.displaySessionDetails(),
            .playback => try self.displayPlaybackView(),
            .analytics => try self.displayAnalyticsDashboard(),
            .monitor => try self.displayLiveMonitor(),
        }

        // Footer with controls
        try self.displayFooter();
    }

    /// Display header with title and search
    pub fn displayHeader(self: *Browser) !void {
        try self.terminal.moveTo(0, 0);
        try self.terminal.print("╔═══════════════════════════════════════════════════════════════════════════════╗", .{ .fg_color = .{ .ansi = 6 }, .bold = true });
        try self.terminal.moveTo(1, 0);
        try self.terminal.print("║", .{ .fg_color = .{ .ansi = 6 }, .bold = true });
        try self.terminal.print("                          Session Browser - Rich TUI                           ", .{ .fg_color = .{ .ansi = 7 }, .bold = true, .bg_color = .{ .ansi = 6 } });
        try self.terminal.print("║", .{ .fg_color = .{ .ansi = 6 }, .bold = true });
        try self.terminal.moveTo(2, 0);
        try self.terminal.print("╚═══════════════════════════════════════════════════════════════════════════════╝", .{ .fg_color = .{ .ansi = 6 }, .bold = true });
    }

    /// Display navigation tabs
    pub fn displayNavigationTabs(self: *Browser) !void {
        const tabs = [_][]const u8{ "List", "Timeline", "Details", "Playback", "Analytics", "Monitor" };
        var x: i32 = 2;

        try self.terminal.moveTo(3, 0);
        for (tabs, 0..) |tab, i| {
            const isSelected = @intFromEnum(self.currentView) == i;
            const style = if (isSelected)
                term.Style{ .fg_color = .{ .ansi = 0 }, .bg_color = .{ .ansi = 7 }, .bold = true }
            else
                term.Style{ .fg_color = .{ .ansi = 7 } };

            try self.terminal.moveTo(3, x);
            try self.terminal.printf("[{s}]", .{tab}, style);
            x += @as(i32, @intCast(tab.len)) + 3;
        }
    }

    /// Display session list view
    pub fn displaySessionList(self: *Browser) !void {
        try self.terminal.moveTo(5, 0);
        try self.terminal.print("Active Sessions:", .{ .fg_color = .{ .ansi = 6 }, .bold = true });

        var y: i32 = 7;
        var it = self.sessionManager.activeSessions.iterator();
        var sessionCount: usize = 0;

        while (it.next()) |entry| {
            if (sessionCount >= 10) break; // Limit display for now

            const sessionData = entry.value_ptr.*;
            try self.terminal.moveTo(y, 2);

            // Session ID
            try self.terminal.printf("📋 {s}", .{sessionData.sessionId}, .{ .fg_color = .{ .ansi = 7 }, .bold = true });

            // Status indicator
            try self.terminal.moveTo(y, 45);
            const status = if (sessionData.isActive) "🟢 Active" else "🔴 Ended";
            const statusColor = if (sessionData.isActive) term.Color{ .ansi = 2 } else term.Color{ .ansi = 1 };
            try self.terminal.printf("{s}", .{status}, .{ .fg_color = statusColor });

            // Message count
            try self.terminal.moveTo(y, 60);
            try self.terminal.printf("💬 {} messages", .{sessionData.messagesProcessed}, .{ .fg_color = .{ .ansi = 4 } });

            // Duration
            try self.terminal.moveTo(y, 80);
            const duration = sessionData.getDuration();
            const durationStr = try self.formatDuration(duration);
            defer self.allocator.free(durationStr);
            try self.terminal.printf("⏱️ {s}", .{durationStr}, .{ .fg_color = .{ .ansi = 5 } });

            y += 2;
            sessionCount += 1;
        }

        if (sessionCount == 0) {
            try self.terminal.moveTo(7, 2);
            try self.terminal.print("No active sessions found.", .{ .fg_color = .{ .ansi = 3 } });
        }
    }

    /// Display timeline view
    pub fn displayTimelineView(self: *Browser) !void {
        try self.terminal.moveTo(5, 0);
        try self.terminal.print("Session Timeline:", .{ .fg_color = .{ .ansi = 6 }, .bold = true });

        try self.terminal.moveTo(7, 2);
        try self.terminal.print("Timeline visualization would show session history over time", .{ .fg_color = .{ .ansi = 7 } });
        try self.terminal.moveTo(8, 2);
        try self.terminal.print("• Each session represented as a point on the timeline", .{ .fg_color = .{ .ansi = 7 } });
        try self.terminal.moveTo(9, 2);
        try self.terminal.print("• Color-coded by status (active/ended)", .{ .fg_color = .{ .ansi = 7 } });
        try self.terminal.moveTo(10, 2);
        try self.terminal.print("• Clickable for session details", .{ .fg_color = .{ .ansi = 7 } });
    }

    /// Display session details view
    pub fn displaySessionDetails(self: *Browser) !void {
        try self.terminal.moveTo(5, 0);
        try self.terminal.print("Session Details:", .{ .fg_color = .{ .ansi = 6 }, .bold = true });

        if (self.selectedSession) |sessionId| {
            try self.terminal.moveTo(7, 2);
            try self.terminal.printf("Selected Session: {s}", .{sessionId}, .{ .fg_color = .{ .ansi = 7 }, .bold = true });

            if (self.sessionManager.getSession(sessionId)) |sessionData| {
                try self.terminal.moveTo(9, 2);
                try self.terminal.printf("Status: {s}", .{if (sessionData.isActive) "Active" else "Ended"}, .{ .fg_color = .{ .ansi = if (sessionData.isActive) 2 else 1 } });
                try self.terminal.moveTo(10, 2);
                try self.terminal.printf("Messages: {}", .{sessionData.messagesProcessed}, .{ .fg_color = .{ .ansi = 4 } });
                try self.terminal.moveTo(11, 2);
                try self.terminal.printf("Tools Used: {}", .{sessionData.toolsExecuted}, .{ .fg_color = .{ .ansi = 5 } });
            }
        } else {
            try self.terminal.moveTo(7, 2);
            try self.terminal.print("No session selected. Use arrow keys to select from the list.", .{ .fg_color = .{ .ansi = 3 } });
        }
    }

    /// Display playback view
    pub fn displayPlaybackView(self: *Browser) !void {
        try self.terminal.moveTo(5, 0);
        try self.terminal.print("Conversation Playback:", .{ .fg_color = .{ .ansi = 6 }, .bold = true });

        try self.terminal.moveTo(7, 2);
        try self.terminal.print("🎬 Playback Controls:", .{ .fg_color = .{ .ansi = 7 }, .bold = true });
        try self.terminal.moveTo(8, 4);
        try self.terminal.print("⏮️ Previous  ⏸️ Pause  ▶️ Play  ⏭️ Next  🔄 Speed", .{ .fg_color = .{ .ansi = 7 } });

        try self.terminal.moveTo(10, 2);
        try self.terminal.print("📜 Conversation History:", .{ .fg_color = .{ .ansi = 7 }, .bold = true });
        try self.terminal.moveTo(11, 4);
        try self.terminal.print("Step through messages with timeline controls", .{ .fg_color = .{ .ansi = 7 } });
        try self.terminal.moveTo(12, 4);
        try self.terminal.print("View tool calls and responses", .{ .fg_color = .{ .ansi = 7 } });
        try self.terminal.moveTo(13, 4);
        try self.terminal.print("Bookmark important messages", .{ .fg_color = .{ .ansi = 7 } });
    }

    /// Display analytics dashboard
    pub fn displayAnalyticsDashboard(self: *Browser) !void {
        const stats = self.sessionManager.getStats();

        try self.terminal.moveTo(5, 0);
        try self.terminal.print("📊 Analytics Dashboard:", .{ .fg_color = .{ .ansi = 6 }, .bold = true });

        try self.terminal.moveTo(7, 2);
        try self.terminal.printf("Total Sessions: {}", .{stats.total_sessions}, .{ .fg_color = .{ .ansi = 2 }, .bold = true });
        try self.terminal.moveTo(8, 2);
        try self.terminal.printf("Total Messages: {}", .{stats.total_messages}, .{ .fg_color = .{ .ansi = 4 }, .bold = true });
        try self.terminal.moveTo(9, 2);
        try self.terminal.printf("Total Tokens: {}", .{stats.total_tokens}, .{ .fg_color = .{ .ansi = 5 }, .bold = true });
        try self.terminal.moveTo(10, 2);
        try self.terminal.printf("Auth Success Rate: {d:.1}%", .{stats.getAuthSuccessRate()}, .{ .fg_color = .{ .ansi = 3 }, .bold = true });

        try self.terminal.moveTo(12, 2);
        try self.terminal.print("📈 Usage Patterns:", .{ .fg_color = .{ .ansi = 7 }, .bold = true });
        try self.terminal.moveTo(13, 4);
        try self.terminal.print("• Cost breakdown by agent/session", .{ .fg_color = .{ .ansi = 7 } });
        try self.terminal.moveTo(14, 4);
        try self.terminal.print("• Performance trends over time", .{ .fg_color = .{ .ansi = 7 } });
        try self.terminal.moveTo(15, 4);
        try self.terminal.print("• Most used tools and features", .{ .fg_color = .{ .ansi = 7 } });
    }

    /// Display live monitor view
    pub fn displayLiveMonitor(self: *Browser) !void {
        try self.terminal.moveTo(5, 0);
        try self.terminal.print("🔴 Live Session Monitor:", .{ .fg_color = .{ .ansi = 6 }, .bold = true });

        try self.terminal.moveTo(7, 2);
        try self.terminal.print("📊 Real-time Metrics:", .{ .fg_color = .{ .ansi = 7 }, .bold = true });
        try self.terminal.moveTo(8, 4);
        try self.terminal.print("• Token counter (updates live)", .{ .fg_color = .{ .ansi = 7 } });
        try self.terminal.moveTo(9, 4);
        try self.terminal.print("• Cost accumulator", .{ .fg_color = .{ .ansi = 7 } });
        try self.terminal.moveTo(10, 4);
        try self.terminal.print("• Response time tracking", .{ .fg_color = .{ .ansi = 7 } });
        try self.terminal.moveTo(11, 4);
        try self.terminal.print("• Error rate monitoring", .{ .fg_color = .{ .ansi = 7 } });

        try self.terminal.moveTo(13, 2);
        try self.terminal.print("🎯 Active Sessions:", .{ .fg_color = .{ .ansi = 7 }, .bold = true });
        try self.terminal.moveTo(14, 4);
        try self.terminal.print("Monitor all active sessions in real-time", .{ .fg_color = .{ .ansi = 7 } });
    }

    /// Display footer with controls
    pub fn displayFooter(self: *Browser) !void {
        const footer_y = 20; // Approximate footer position
        try self.terminal.moveTo(footer_y, 0);
        try self.terminal.print("═".repeat(80), .{ .fg_color = .{ .ansi = 6 } });

        try self.terminal.moveTo(footer_y + 1, 2);
        try self.terminal.print("↑/↓ Navigate • Enter Select • Tab Switch View • r Resume • d Delete • e Export • q Quit", .{ .fg_color = .{ .ansi = 7 } });
    }

    /// Format duration in seconds to human-readable string
    pub fn formatDuration(self: *Browser, duration_seconds: i64) ![]const u8 {
        const hours = @divFloor(duration_seconds, 3600);
        const minutes = @divFloor(@mod(duration_seconds, 3600), 60);
        const seconds = @mod(duration_seconds, 60);

        if (hours > 0) {
            return try std.fmt.allocPrint(self.allocator, "{}h {}m {}s", .{ hours, minutes, seconds });
        } else if (minutes > 0) {
            return try std.fmt.allocPrint(self.allocator, "{}m {}s", .{ minutes, seconds });
        } else {
            return try std.fmt.allocPrint(self.allocator, "{}s", .{seconds});
        }
    }
};

/// Helper function to create and run session browser
pub fn runBrowser(allocator: Allocator, session_manager: *session.Sessions) !void {
    var browser = try Browser.init(allocator, session_manager);
    defer browser.deinit();
    try browser.run();
}

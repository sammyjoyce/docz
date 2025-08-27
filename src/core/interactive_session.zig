//! Interactive session for terminal AI agents.
//!
//! Provides a simple interactive session with basic TUI support,
//! message display, and session management.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Re-export commonly used types
pub const Message = @import("../shared/network/anthropic.zig").Message;

/// Session configuration
pub const SessionConfig = struct {
    /// Enable interactive mode
    interactive: bool = true,
    /// Enable TUI interface
    enable_tui: bool = false,
    /// Enable dashboard
    enable_dashboard: bool = false,
    /// Enable authentication
    enable_auth: bool = true,
    /// Session title
    title: []const u8 = "AI Agent Session",
    /// Maximum input length
    max_input_length: usize = 4096,
    /// Support multi-line input
    multi_line: bool = false,
    /// Show session statistics
    show_stats: bool = false,
};

/// Session statistics
pub const SessionStats = struct {
    /// Total sessions started
    total_sessions: usize = 0,
    /// Total messages processed
    total_messages: usize = 0,
    /// Total tokens used
    total_tokens: usize = 0,
    /// Input tokens
    input_tokens: usize = 0,
    /// Output tokens
    output_tokens: usize = 0,
    /// Authentication attempts
    auth_attempts: usize = 0,
    /// Authentication failures
    auth_failures: usize = 0,
    /// Last session start time
    last_session_start: i64 = 0,
    /// Last session end time
    last_session_end: i64 = 0,
    /// Average response time in nanoseconds
    average_response_time: i64 = 0,
    /// Last response time
    last_response_time: i64 = 0,
    /// Error count
    error_count: usize = 0,
};

/// Interactive session
pub const InteractiveSession = struct {
    allocator: Allocator,
    config: SessionConfig,
    stats: SessionStats,
    messages: std.ArrayList(Message),
    start_time: i64,

    /// Initialize interactive session
    pub fn init(allocator: Allocator, config: SessionConfig) !*InteractiveSession {
        const session = try allocator.create(InteractiveSession);
        const now = std.time.timestamp();

        session.* = .{
            .allocator = allocator,
            .config = config,
            .stats = .{},
            .messages = std.ArrayList(Message).init(allocator),
            .start_time = now,
        };

        session.stats.last_session_start = now;
        session.stats.total_sessions += 1;

        return session;
    }

    /// Deinitialize the session
    pub fn deinit(self: *InteractiveSession) void {
        // Clean up messages
        for (self.messages.items) |*msg| {
            msg.deinit(self.allocator);
        }
        self.messages.deinit();

        self.allocator.destroy(self);
    }

    /// Start the interactive session
    pub fn start(self: *InteractiveSession) !void {
        if (self.config.interactive) {
            std.log.info("🤖 Starting interactive session: {s}", .{self.config.title});

            if (self.config.enable_tui) {
                std.log.info("🎨 TUI mode enabled", .{});
            } else {
                std.log.info("📝 CLI mode enabled", .{});
            }

            // In a real implementation, this would start the interactive loop
            // For now, just mark as started
            self.stats.last_session_start = std.time.timestamp();
        }
    }

    /// Check if TUI is available
    pub fn hasTUI(self: *InteractiveSession) bool {
        return self.config.enable_tui;
    }

    /// Get session statistics
    pub fn getStats(self: *InteractiveSession) SessionStats {
        return self.stats;
    }

    /// Add a message to the session
    pub fn addMessage(self: *InteractiveSession, message: Message) !void {
        try self.messages.append(message);
        self.stats.total_messages += 1;
    }
};

/// Create a basic interactive session
pub fn createBasicSession(allocator: Allocator, title: []const u8) !*InteractiveSession {
    const config = SessionConfig{
        .interactive = true,
        .enable_tui = false,
        .enable_dashboard = false,
        .enable_auth = true,
        .title = title,
        .max_input_length = 4096,
        .multi_line = false,
        .show_stats = false,
    };

    return try InteractiveSession.init(allocator, config);
}

/// Create a rich interactive session with TUI support
pub fn createRichSession(allocator: Allocator, title: []const u8) !*InteractiveSession {
    const config = SessionConfig{
        .interactive = true,
        .enable_tui = true,
        .enable_dashboard = true,
        .enable_auth = true,
        .title = title,
        .max_input_length = 4096,
        .multi_line = true,
        .show_stats = true,
    };

    return try InteractiveSession.init(allocator, config);
}

/// Create a CLI-only session
pub fn createCLISession(allocator: Allocator, title: []const u8) !*InteractiveSession {
    const config = SessionConfig{
        .interactive = true,
        .enable_tui = false,
        .enable_dashboard = false,
        .enable_auth = false,
        .title = title,
        .max_input_length = 4096,
        .multi_line = false,
        .show_stats = false,
    };

    return try InteractiveSession.init(allocator, config);
}</content>
</xai:function_call name="write">
<parameter name="filePath">src/core/agent_main.zig
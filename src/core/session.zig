//! Unified session management for all agent types.
//! Provides session data, statistics, performance metrics, and persistence.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Session data structure for tracking agent sessions
pub const SessionData = struct {
    session_id: []const u8 = "",
    start_time: i64 = 0,
    messages_processed: u64 = 0,
    tools_executed: u64 = 0,
    conversation_history: std.ArrayList(ConversationEntry) = undefined,
    metadata: std.StringHashMap([]const u8) = undefined,
    last_activity: i64 = 0,
    is_active: bool = false,

    /// Initialize session data
    pub fn init(allocator: Allocator, session_id: []const u8) !SessionData {
        const now = std.time.timestamp();
        return SessionData{
            .session_id = try allocator.dupe(u8, session_id),
            .start_time = now,
            .last_activity = now,
            .conversation_history = std.ArrayList(ConversationEntry).init(allocator),
            .metadata = std.StringHashMap([]const u8).init(allocator),
            .is_active = true,
        };
    }

    /// Deinitialize session data
    pub fn deinit(self: *SessionData) void {
        self.allocator.free(self.session_id);
        for (self.conversation_history.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.conversation_history.deinit();

        var it = self.metadata.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.metadata.deinit();
    }

    /// Add a conversation entry
    pub fn addConversationEntry(self: *SessionData, allocator: Allocator, role: anytype, content: []const u8) !void {
        const entry = ConversationEntry{
            .timestamp = std.time.timestamp(),
            .role = role,
            .content = try allocator.dupe(u8, content),
        };
        try self.conversation_history.append(entry);
        self.messages_processed += 1;
        self.last_activity = std.time.timestamp();
    }

    /// Update session metadata
    pub fn setMetadata(self: *SessionData, allocator: Allocator, key: []const u8, value: []const u8) !void {
        const key_copy = try allocator.dupe(u8, key);
        const value_copy = try allocator.dupe(u8, value);

        if (self.metadata.get(key_copy)) |old_value| {
            allocator.free(old_value);
        }
        try self.metadata.put(key_copy, value_copy);
    }

    /// Get session duration in seconds
    pub fn getDuration(self: *SessionData) i64 {
        return std.time.timestamp() - self.start_time;
    }

    /// Mark session as inactive
    pub fn endSession(self: *SessionData) void {
        self.is_active = false;
        self.last_activity = std.time.timestamp();
    }
};

/// Conversation entry for session history
pub const ConversationEntry = struct {
    timestamp: i64,
    role: enum { user, assistant, system, tool },
    content: []const u8,
    metadata: ?std.json.Value = null,

    /// Deinitialize conversation entry
    pub fn deinit(self: *ConversationEntry, allocator: Allocator) void {
        allocator.free(self.content);
        if (self.metadata) |meta| {
            meta.deinit();
        }
    }
};

/// Session statistics for tracking usage patterns
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
    /// Average session duration
    average_session_duration: f64 = 0,

    /// Update statistics with new session data
    pub fn updateWithSession(self: *SessionStats, session: *SessionData) void {
        self.total_sessions += 1;
        self.total_messages += session.messages_processed;
        self.last_session_start = session.start_time;
        self.last_session_end = std.time.timestamp();

        // Update average session duration
        const session_duration = @as(f64, @floatFromInt(self.last_session_end - session.start_time));
        const total_sessions = @as(f64, @floatFromInt(self.total_sessions));
        self.average_session_duration =
            (self.average_session_duration * (total_sessions - 1) + session_duration) / total_sessions;
    }

    /// Record response time
    pub fn recordResponseTime(self: *SessionStats, response_time_ns: i64) void {
        self.last_response_time = response_time_ns;
        // Update rolling average
        if (self.average_response_time == 0) {
            self.average_response_time = response_time_ns;
        } else {
            self.average_response_time = (self.average_response_time + response_time_ns) / 2;
        }
    }

    /// Record authentication attempt
    pub fn recordAuthAttempt(self: *SessionStats, success: bool) void {
        self.auth_attempts += 1;
        if (!success) {
            self.auth_failures += 1;
        }
    }

    /// Record token usage
    pub fn recordTokenUsage(self: *SessionStats, input_tokens: usize, output_tokens: usize) void {
        self.input_tokens += input_tokens;
        self.output_tokens += output_tokens;
        self.total_tokens += input_tokens + output_tokens;
    }

    /// Record error
    pub fn recordError(self: *SessionStats) void {
        self.error_count += 1;
    }

    /// Get success rate as percentage
    pub fn getAuthSuccessRate(self: *SessionStats) f64 {
        if (self.auth_attempts == 0) return 100.0;
        const success_count = self.auth_attempts - self.auth_failures;
        return @as(f64, @floatFromInt(success_count)) / @as(f64, @floatFromInt(self.auth_attempts)) * 100.0;
    }
};

/// Performance metrics for monitoring agent performance
pub const PerformanceMetrics = struct {
    render_time_ms: f64 = 0,
    response_time_ms: f64 = 0,
    memory_usage_mb: f64 = 0,
    cpu_usage_percent: f64 = 0,
    cache_hit_rate: f64 = 0,
    last_updated: i64 = 0,

    /// Update metrics with current values
    pub fn update(self: *PerformanceMetrics) void {
        self.last_updated = std.time.timestamp();
        // In a real implementation, these would be measured from system
        // For now, we'll set some placeholder values
        self.memory_usage_mb = 50.0; // Placeholder
        self.cpu_usage_percent = 15.0; // Placeholder
        self.cache_hit_rate = 85.0; // Placeholder
    }

    /// Record render time
    pub fn recordRenderTime(self: *PerformanceMetrics, render_time_ms: f64) void {
        self.render_time_ms = render_time_ms;
        self.update();
    }

    /// Record response time
    pub fn recordResponseTime(self: *PerformanceMetrics, response_time_ms: f64) void {
        self.response_time_ms = response_time_ms;
        self.update();
    }

    /// Get formatted metrics summary
    pub fn getSummary(self: *PerformanceMetrics, allocator: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator,
            \\Performance Metrics:
            \\  Render Time: {d:.2}ms
            \\  Response Time: {d:.2}ms
            \\  Memory Usage: {d:.1}MB
            \\  CPU Usage: {d:.1}%
            \\  Cache Hit Rate: {d:.1}%
        , .{
            self.render_time_ms,
            self.response_time_ms,
            self.memory_usage_mb,
            self.cpu_usage_percent,
            self.cache_hit_rate,
        });
    }
};

/// Session manager for persistence and lifecycle management
pub const SessionManager = struct {
    allocator: Allocator,
    sessions_dir: []const u8,
    active_sessions: std.StringHashMap(*SessionData),
    stats: SessionStats,

    /// Initialize session manager
    pub fn init(allocator: Allocator, sessions_dir: []const u8) !*SessionManager {
        const manager = try allocator.create(SessionManager);
        manager.* = SessionManager{
            .allocator = allocator,
            .sessions_dir = try allocator.dupe(u8, sessions_dir),
            .active_sessions = std.StringHashMap(*SessionData).init(allocator),
            .stats = SessionStats{},
        };

        // Create sessions directory if it doesn't exist
        std.fs.cwd().makePath(sessions_dir) catch {};

        return manager;
    }

    /// Deinitialize session manager
    pub fn deinit(self: *SessionManager) void {
        self.allocator.free(self.sessions_dir);

        var it = self.active_sessions.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.active_sessions.deinit();
    }

    /// Create a new session
    pub fn createSession(self: *SessionManager, session_id: []const u8) !*SessionData {
        const session = try self.allocator.create(SessionData);
        session.* = try SessionData.init(self.allocator, session_id);

        const key = try self.allocator.dupe(u8, session_id);
        try self.active_sessions.put(key, session);

        self.stats.updateWithSession(session);

        return session;
    }

    /// Get existing session
    pub fn getSession(self: *SessionManager, session_id: []const u8) ?*SessionData {
        return self.active_sessions.get(session_id);
    }

    /// End a session
    pub fn endSession(self: *SessionManager, session_id: []const u8) !void {
        if (self.active_sessions.getEntry(session_id)) |entry| {
            entry.value_ptr.*.endSession();
            try self.saveSession(entry.value_ptr.*);
        }
    }

    /// Save session to disk
    pub fn saveSession(self: *SessionManager, session: *SessionData) !void {
        const filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.sessions_dir, session.session_id });
        defer self.allocator.free(filename);

        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        // Convert session data to JSON
        const session_json = .{
            .session_id = session.session_id,
            .start_time = session.start_time,
            .messages_processed = session.messages_processed,
            .tools_executed = session.tools_executed,
            .last_activity = session.last_activity,
            .is_active = session.is_active,
            .conversation_history = session.conversation_history.items,
            .metadata = session.metadata,
        };

        try std.json.stringify(session_json, .{ .whitespace = true }, file.writer());
    }

    /// Load session from disk
    pub fn loadSession(self: *SessionManager, session_id: []const u8) !?*SessionData {
        const filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.sessions_dir, session_id });
        defer self.allocator.free(filename);

        const file = std.fs.cwd().openFile(filename, .{}) catch return null;
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(content);

        // Parse JSON and reconstruct session
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{});
        defer parsed.deinit();

        const session = try self.allocator.create(SessionData);
        // Implementation would reconstruct SessionData from JSON
        // For now, return null to indicate not implemented
        self.allocator.destroy(session);
        return null;
    }

    /// Get session statistics
    pub fn getStats(self: *SessionManager) SessionStats {
        return self.stats;
    }

    /// Clean up old sessions
    pub fn cleanupOldSessions(self: *SessionManager, max_age_days: u32) !void {
        const cutoff_time = std.time.timestamp() - (@as(i64, max_age_days) * 24 * 60 * 60);

        var dir = try std.fs.cwd().openDir(self.sessions_dir, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) {
                const filepath = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.sessions_dir, entry.name });
                defer self.allocator.free(filepath);

                const stat = try std.fs.cwd().statFile(filepath);
                if (stat.mtime < cutoff_time) {
                    try std.fs.cwd().deleteFile(filepath);
                }
            }
        }
    }
};

/// Generate a unique session ID
pub fn generateSessionId(allocator: Allocator) ![]const u8 {
    const timestamp = std.time.timestamp();
    const random = std.crypto.random.int(u32);
    return try std.fmt.allocPrint(allocator, "session_{x}_{x}", .{ timestamp, random });
}

/// Helper functions for session management
pub const SessionHelpers = struct {
    /// Create a basic session configuration
    pub fn createBasicConfig(title: []const u8) SessionConfig {
        return SessionConfig{
            .title = title,
            .interactive = true,
            .enable_tui = false,
            .enable_dashboard = false,
            .enable_auth = true,
        };
    }

    /// Create a rich session configuration with TUI support
    pub fn createRichConfig(title: []const u8) SessionConfig {
        return SessionConfig{
            .title = title,
            .interactive = true,
            .enable_tui = true,
            .enable_dashboard = true,
            .enable_auth = true,
            .show_stats = true,
        };
    }

    /// Create a CLI-only session configuration
    pub fn createCliConfig(title: []const u8) SessionConfig {
        return SessionConfig{
            .title = title,
            .interactive = true,
            .enable_tui = false,
            .enable_dashboard = false,
            .enable_auth = false,
            .multi_line = false,
        };
    }
};

/// Session configuration (moved from interactive_session.zig)
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

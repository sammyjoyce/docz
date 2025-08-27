//! Status Panel Renderer
//!
//! Renders agent status information including health, authentication,
//! session details, and connection status with visual indicators.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import dependencies
const state = @import("../state.zig");
const layout = @import("../layout.zig");
const theme = @import("../../../../theme/mod.zig");
const term_mod = @import("../../../../term/mod.zig");
const render_mod = @import("../../../../render/mod.zig");

// Import specific term modules for drawing functions
const cursor = term_mod.term.control.cursor.CursorController;
const sgr = term_mod.term.ansi.sgr;

// Type aliases
const DashboardStore = state.DashboardStore;
const Rect = layout.Rect;

/// Agent health status
pub const HealthStatus = enum {
    healthy,
    degraded,
    warning,
    critical,
    @"error",
    unknown,

    pub fn getIcon(self: HealthStatus) []const u8 {
        return switch (self) {
            .healthy => "✓",
            .degraded => "◐",
            .warning => "⚠",
            .critical => "⚠",
            .@"error" => "✗",
            .unknown => "?",
        };
    }

    pub fn getLabel(self: HealthStatus) []const u8 {
        return switch (self) {
            .healthy => "Healthy",
            .degraded => "Degraded",
            .warning => "Warning",
            .critical => "Critical",
            .@"error" => "Error",
            .unknown => "Unknown",
        };
    }
};

/// Authentication status
pub const AuthStatus = enum {
    authenticated,
    authenticating,
    unauthenticated,
    expired,
    @"error",

    pub fn getIcon(self: AuthStatus) []const u8 {
        return switch (self) {
            .authenticated => "🔐",
            .authenticating => "🔄",
            .unauthenticated => "🔓",
            .expired => "⏰",
            .@"error" => "❌",
        };
    }

    pub fn getLabel(self: AuthStatus) []const u8 {
        return switch (self) {
            .authenticated => "Authenticated",
            .authenticating => "Authenticating...",
            .unauthenticated => "Not Authenticated",
            .expired => "Token Expired",
            .@"error" => "Auth Error",
        };
    }
};

/// Connection status
pub const ConnectionStatus = enum {
    connected,
    connecting,
    disconnected,
    reconnecting,
    @"error",

    pub fn getIcon(self: ConnectionStatus) []const u8 {
        return switch (self) {
            .connected => "🟢",
            .connecting => "🟡",
            .disconnected => "🔴",
            .reconnecting => "🟠",
            .@"error" => "❌",
        };
    }

    pub fn getLabel(self: ConnectionStatus) []const u8 {
        return switch (self) {
            .connected => "Connected",
            .connecting => "Connecting...",
            .disconnected => "Disconnected",
            .reconnecting => "Reconnecting...",
            .@"error" => "Connection Error",
        };
    }
};

/// Session information
pub const Session = struct {
    id: []const u8 = "none",
    start_time: i64 = 0,
    duration_seconds: u64 = 0,
    request_count: u64 = 0,
    error_count: u64 = 0,
    token_usage: u64 = 0,
    rate_limit_remaining: u64 = 0,
    rate_limit_reset: i64 = 0,
};

/// Agent status data
pub const AgentStatus = struct {
    health: HealthStatus = .unknown,
    auth: AuthStatus = .unauthenticated,
    connection: ConnectionStatus = .disconnected,
    session: Session = .{},
    agent_name: []const u8 = "Unknown Agent",
    agent_version: []const u8 = "0.0.0",
    last_activity: i64 = 0,
    uptime_seconds: u64 = 0,
    api_endpoint: []const u8 = "",
    model: []const u8 = "",
};

/// Configuration for status rendering
pub const StatusConfig = struct {
    /// Show health status
    show_health: bool = true,

    /// Show authentication status
    show_auth: bool = true,

    /// Show connection status
    show_connection: bool = true,

    /// Show session details
    show_session: bool = true,

    /// Show agent info
    show_agent_info: bool = true,

    /// Show API details
    show_api_details: bool = false,

    /// Show uptime
    show_uptime: bool = true,

    /// Compact mode (single line per status)
    compact_mode: bool = false,

    /// Use icons for status
    use_icons: bool = true,

    /// Blink critical statuses
    blink_critical: bool = false,
};

/// Status panel renderer
pub const StatusRenderer = struct {
    allocator: Allocator,
    config: StatusConfig,
    status: AgentStatus,
    blink_state: bool = false,
    last_blink: i64 = 0,

    const Self = @This();

    pub fn init(allocator: Allocator, config: StatusConfig) !Self {
        return .{
            .allocator = allocator,
            .config = config,
            .status = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Update status data
    pub fn updateStatus(self: *Self, status: AgentStatus) void {
        self.status = status;
    }

    /// Render the status panel
    pub fn render(
        self: *Self,
        writer: anytype,
        bounds: Rect,
        data_store: *const DashboardStore,
        theme: *const theme.ColorScheme,
    ) !void {
        _ = data_store; // Status is typically updated separately

        // Update blink state for critical statuses
        if (self.config.blink_critical) {
            const now = std.time.timestamp();
            if (now - self.last_blink > 500) { // 500ms blink interval
                self.blink_state = !self.blink_state;
                self.last_blink = now;
            }
        }

        // Draw panel border
        try self.renderBorder(writer, bounds, theme);

        // Draw title bar
        try self.renderTitleBar(writer, bounds, theme);

        // Calculate content area
        const content_bounds = Rect{
            .x = bounds.x + 1,
            .y = bounds.y + 2,
            .width = bounds.width - 2,
            .height = bounds.height - 3,
        };

        // Render status items based on configuration
        if (self.config.compact_mode) {
            try self.renderCompact(writer, content_bounds, theme);
        } else {
            try self.renderDetailed(writer, content_bounds, theme);
        }
    }

    /// Render panel border
    fn renderBorder(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        theme: *const theme.ColorScheme,
    ) !void {
        _ = self;

        const box_chars = if (theme.use_unicode)
            term_mod.BoxDrawing.rounded
        else
            term_mod.BoxDrawing.ascii;

        try term_mod.drawBox(writer, bounds, box_chars, theme.border);
    }

    /// Render title bar
    fn renderTitleBar(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        theme: *const theme.ColorScheme,
    ) !void {
        try term_mod.moveTo(writer, bounds.x + 2, bounds.y);
        try term_mod.setStyle(writer, .{ .bold = true, .foreground = theme.title });
        try writer.writeAll(" Status ");

        // Show overall status indicator
        const overall_color = self.getOverallStatusColor(theme);
        try term_mod.setStyle(writer, .{ .foreground = overall_color });

        if (self.status.health == .healthy and
            self.status.auth == .authenticated and
            self.status.connection == .connected)
        {
            try writer.writeAll(" ● ");
        } else if (self.status.health == .@"error" or
            self.status.auth == .@"error" or
            self.status.connection == .@"error")
        {
            try writer.writeAll(" ▲ ");
        } else {
            try writer.writeAll(" ◆ ");
        }

        try term_mod.resetStyle(writer);
    }

    /// Render compact status view
    fn renderCompact(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        theme: *const theme.ColorScheme,
    ) !void {
        const y_offset: u16 = 0;

        // All statuses on one line
        if (y_offset < bounds.height) {
            const y = bounds.y + @as(i32, @intCast(y_offset));
            try term_mod.moveTo(writer, bounds.x, y);

            // Health
            if (self.config.show_health) {
                try self.renderStatusItem(
                    writer,
                    self.status.health.getIcon(),
                    self.status.health.getLabel(),
                    self.getHealthColor(self.status.health, theme),
                    true,
                );
                try writer.writeAll(" ");
            }

            // Auth
            if (self.config.show_auth) {
                try self.renderStatusItem(
                    writer,
                    self.status.auth.getIcon(),
                    self.status.auth.getLabel(),
                    self.getAuthColor(self.status.auth, theme),
                    true,
                );
                try writer.writeAll(" ");
            }

            // Connection
            if (self.config.show_connection) {
                try self.renderStatusItem(
                    writer,
                    self.status.connection.getIcon(),
                    self.status.connection.getLabel(),
                    self.getConnectionColor(self.status.connection, theme),
                    true,
                );
            }
        }
    }

    /// Render detailed status view
    fn renderDetailed(
        self: *Self,
        writer: anytype,
        bounds: Rect,
        theme: *const theme.ColorScheme,
    ) !void {
        var y_offset: u16 = 0;

        // Agent info
        if (self.config.show_agent_info and y_offset < bounds.height) {
            try self.renderAgentInfo(writer, bounds, y_offset, theme);
            y_offset += 2;
        }

        // Health status
        if (self.config.show_health and y_offset < bounds.height) {
            try self.renderHealthStatus(writer, bounds, y_offset, theme);
            y_offset += 1;
        }

        // Auth status
        if (self.config.show_auth and y_offset < bounds.height) {
            try self.renderAuthStatus(writer, bounds, y_offset, theme);
            y_offset += 1;
        }

        // Connection status
        if (self.config.show_connection and y_offset < bounds.height) {
            try self.renderConnectionStatus(writer, bounds, y_offset, theme);
            y_offset += 1;
        }

        // Session info
        if (self.config.show_session and y_offset + 1 < bounds.height) {
            y_offset += 1; // Add spacing
            try self.renderSession(writer, bounds, y_offset, theme);
            y_offset += 2;
        }

        // Uptime
        if (self.config.show_uptime and y_offset < bounds.height) {
            try self.renderUptime(writer, bounds, y_offset, theme);
            y_offset += 1;
        }

        // API details
        if (self.config.show_api_details and y_offset + 1 < bounds.height) {
            y_offset += 1; // Add spacing
            try self.renderAPIDetails(writer, bounds, y_offset, theme);
        }
    }

    /// Render agent information
    fn renderAgentInfo(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));

        try term_mod.moveTo(writer, bounds.x, y);
        try term_mod.setStyle(writer, .{ .foreground = theme.accent, .bold = true });
        try writer.print("{s}", .{self.status.agent_name});

        try term_mod.setStyle(writer, .{ .foreground = theme.dim });
        try writer.print(" v{s}", .{self.status.agent_version});

        try term_mod.resetStyle(writer);
    }

    /// Render health status
    fn renderHealthStatus(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));
        try term_mod.moveTo(writer, bounds.x, y);

        try term_mod.setStyle(writer, .{ .foreground = theme.foreground });
        try writer.writeAll(" Health: ");

        const color = self.getHealthColor(self.status.health, theme);
        const should_blink = self.config.blink_critical and
            (self.status.health == .critical or self.status.health == .@"error");

        if (!should_blink or self.blink_state) {
            try self.renderStatusItem(
                writer,
                self.status.health.getIcon(),
                self.status.health.getLabel(),
                color,
                false,
            );
        }

        try term_mod.resetStyle(writer);
    }

    /// Render authentication status
    fn renderAuthStatus(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));
        try term_mod.moveTo(writer, bounds.x, y);

        try term_mod.setStyle(writer, .{ .foreground = theme.foreground });
        try writer.writeAll("   Auth: ");

        const color = self.getAuthColor(self.status.auth, theme);
        try self.renderStatusItem(
            writer,
            self.status.auth.getIcon(),
            self.status.auth.getLabel(),
            color,
            false,
        );

        try term_mod.resetStyle(writer);
    }

    /// Render connection status
    fn renderConnectionStatus(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));
        try term_mod.moveTo(writer, bounds.x, y);

        try term_mod.setStyle(writer, .{ .foreground = theme.foreground });
        try writer.writeAll("   Conn: ");

        const color = self.getConnectionColor(self.status.connection, theme);
        try self.renderStatusItem(
            writer,
            self.status.connection.getIcon(),
            self.status.connection.getLabel(),
            color,
            false,
        );

        try term_mod.resetStyle(writer);
    }

    /// Render session information
    fn renderSession(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));

        // Session header
        try term_mod.moveTo(writer, bounds.x, y);
        try term_mod.setStyle(writer, .{ .foreground = theme.foreground, .underline = true });
        try writer.writeAll("Session");
        try term_mod.resetStyle(writer);

        // Session details
        if (self.status.session.id.len > 0 and !std.mem.eql(u8, self.status.session.id, "none")) {
            try term_mod.moveTo(writer, bounds.x, y + 1);
            try term_mod.setStyle(writer, .{ .foreground = theme.dim });

            // Format session ID (show first 8 chars)
            const id_display = if (self.status.session.id.len > 8)
                self.status.session.id[0..8]
            else
                self.status.session.id;

            try writer.print(" ID: {s}...", .{id_display});

            // Show request count and errors
            if (bounds.width > 30) {
                try term_mod.moveTo(writer, bounds.x + 20, y + 1);
                try writer.print("Reqs: {d}", .{self.status.session.request_count});

                if (self.status.session.error_count > 0) {
                    try term_mod.setStyle(writer, .{ .foreground = theme.warning });
                    try writer.print(" Errs: {d}", .{self.status.session.error_count});
                }
            }
        } else {
            try term_mod.moveTo(writer, bounds.x, y + 1);
            try term_mod.setStyle(writer, .{ .foreground = theme.dim });
            try writer.writeAll(" No active session");
        }

        try term_mod.resetStyle(writer);
    }

    /// Render uptime information
    fn renderUptime(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));
        try term_mod.moveTo(writer, bounds.x, y);

        try term_mod.setStyle(writer, .{ .foreground = theme.dim });
        try writer.writeAll(" Uptime: ");

        const uptime_str = try self.formatDuration(self.status.uptime_seconds);
        defer self.allocator.free(uptime_str);

        try writer.writeAll(uptime_str);
        try term_mod.resetStyle(writer);
    }

    /// Render API details
    fn renderAPIDetails(
        self: *const Self,
        writer: anytype,
        bounds: Rect,
        y_offset: u16,
        theme: *const theme.ColorScheme,
    ) !void {
        const y = bounds.y + @as(i32, @intCast(y_offset));

        // API endpoint
        if (self.status.api_endpoint.len > 0) {
            try term_mod.moveTo(writer, bounds.x, y);
            try term_mod.setStyle(writer, .{ .foreground = theme.dim });

            const max_len = @min(bounds.width - 10, self.status.api_endpoint.len);
            try writer.print("API: {s}", .{self.status.api_endpoint[0..max_len]});

            if (self.status.api_endpoint.len > max_len) {
                try writer.writeAll("...");
            }
        }

        // Model
        if (self.status.model.len > 0 and y + 1 < bounds.y + bounds.height) {
            try term_mod.moveTo(writer, bounds.x, y + 1);
            try term_mod.setStyle(writer, .{ .foreground = theme.dim });
            try writer.print("Model: {s}", .{self.status.model});
        }

        try term_mod.resetStyle(writer);
    }

    /// Render a single status item
    fn renderStatusItem(
        self: *const Self,
        writer: anytype,
        icon: []const u8,
        label: []const u8,
        color: theme.Color,
        compact: bool,
    ) !void {
        try term_mod.setStyle(writer, .{ .foreground = color });

        if (self.config.use_icons) {
            try writer.writeAll(icon);
            if (!compact) {
                try writer.writeAll(" ");
            }
        }

        if (!compact or !self.config.use_icons) {
            try writer.writeAll(label);
        }
    }

    /// Get color for health status
    fn getHealthColor(
        self: *const Self,
        health: HealthStatus,
        theme: *const theme.ColorScheme,
    ) theme.Color {
        _ = self;

        return switch (health) {
            .healthy => theme.success,
            .degraded => theme.warning,
            .warning => theme.warning,
            .critical => theme.@"error",
            .@"error" => theme.@"error",
            .unknown => theme.dim,
        };
    }

    /// Get color for auth status
    fn getAuthColor(
        self: *const Self,
        auth: AuthStatus,
        theme: *const theme.ColorScheme,
    ) theme.Color {
        _ = self;

        return switch (auth) {
            .authenticated => theme.success,
            .authenticating => theme.info,
            .unauthenticated => theme.warning,
            .expired => theme.warning,
            .@"error" => theme.@"error",
        };
    }

    /// Get color for connection status
    fn getConnectionColor(
        self: *const Self,
        conn: ConnectionStatus,
        theme: *const theme.ColorScheme,
    ) theme.Color {
        _ = self;

        return switch (conn) {
            .connected => theme.success,
            .connecting => theme.info,
            .disconnected => theme.warning,
            .reconnecting => theme.info,
            .@"error" => theme.@"error",
        };
    }

    /// Get overall status color
    fn getOverallStatusColor(
        self: *const Self,
        theme: *const theme.ColorScheme,
    ) theme.Color {
        if (self.status.health == .@"error" or
            self.status.auth == .@"error" or
            self.status.connection == .@"error")
        {
            return theme.@"error";
        }

        if (self.status.health == .warning or
            self.status.health == .critical or
            self.status.auth == .expired or
            self.status.connection == .disconnected)
        {
            return theme.warning;
        }

        if (self.status.health == .healthy and
            self.status.auth == .authenticated and
            self.status.connection == .connected)
        {
            return theme.success;
        }

        return theme.info;
    }

    /// Format duration in human-readable form
    fn formatDuration(self: *const Self, seconds: u64) ![]u8 {
        if (seconds < 60) {
            return try std.fmt.allocPrint(self.allocator, "{d}s", .{seconds});
        } else if (seconds < 3600) {
            const minutes = seconds / 60;
            const secs = seconds % 60;
            return try std.fmt.allocPrint(self.allocator, "{d}m {d}s", .{ minutes, secs });
        } else if (seconds < 86400) {
            const hours = seconds / 3600;
            const minutes = (seconds % 3600) / 60;
            return try std.fmt.allocPrint(self.allocator, "{d}h {d}m", .{ hours, minutes });
        } else {
            const days = seconds / 86400;
            const hours = (seconds % 86400) / 3600;
            return try std.fmt.allocPrint(self.allocator, "{d}d {d}h", .{ days, hours });
        }
    }

    /// Handle input events
    pub fn handleInput(self: *Self, event: term_mod.Event) bool {
        _ = event;
        _ = self;
        return false;
    }

    /// Set agent status
    pub fn setStatus(self: *Self, status: AgentStatus) void {
        self.status = status;
    }
};

/// Create a default status renderer
pub fn createDefault(allocator: Allocator) !*StatusRenderer {
    const renderer = try allocator.create(StatusRenderer);
    renderer.* = try StatusRenderer.init(allocator, .{});
    return renderer;
}

/// Create example status for testing
pub fn createExampleStatus() AgentStatus {
    return .{
        .health = .healthy,
        .auth = .authenticated,
        .connection = .connected,
        .session = .{
            .id = "abc123def456",
            .start_time = std.time.timestamp() - 3600,
            .duration_seconds = 3600,
            .request_count = 42,
            .error_count = 2,
            .token_usage = 15000,
            .rate_limit_remaining = 985,
            .rate_limit_reset = std.time.timestamp() + 300,
        },
        .agent_name = "Dashboard Agent",
        .agent_version = "1.0.0",
        .last_activity = std.time.timestamp() - 30,
        .uptime_seconds = 3600,
        .api_endpoint = "https://api.anthropic.com/v1",
        .model = "claude-3-sonnet-20240229",
    };
}

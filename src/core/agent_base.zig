//! Base agent functionality that all agents can inherit from.
//! Provides common lifecycle methods, template variable processing,
//! standardized configuration patterns, OAuth authentication support,
//! and interactive session management.

const std = @import("std");
const Allocator = std.mem.Allocator;

// These are wired by build.zig via named imports
const interactive_session = @import("interactive_session_shared");
const auth = @import("auth_shared");
const anthropic = @import("anthropic_shared");

/// Base agent structure with common functionality.
/// Agents can embed this struct or use composition to inherit base functionality.
pub const BaseAgent = struct {
    allocator: Allocator,
    interactive_session: ?*interactive_session.InteractiveSession = null,
    auth_client: ?auth.AuthClient = null,
    session_stats: SessionStats = .{},

    const Self = @This();

    /// Session statistics for tracking agent usage
    pub const SessionStats = struct {
        total_sessions: usize = 0,
        total_messages: usize = 0,
        total_tokens: usize = 0,
        auth_attempts: usize = 0,
        auth_failures: usize = 0,
        last_session_start: i64 = 0,
        last_session_end: i64 = 0,
        average_session_duration: f64 = 0,
    };

    /// Initialize base agent with allocator
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Clean up base agent resources
    pub fn deinit(self: *Self) void {
        // Clean up interactive session
        if (self.interactive_session) |session| {
            session.deinit();
        }

        // Clean up auth client
        if (self.auth_client) |*client| {
            client.deinit();
        }

        // Agents should override this if they have additional cleanup
    }

    /// Get current date in YYYY-MM-DD format
    pub fn getCurrentDate(self: *Self) ![]const u8 {
        const now = std.time.timestamp();
        const EPOCH_SECONDS = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
        const EPOCH_DAY = EPOCH_SECONDS.getEpochDay();
        const YEAR_DAY = EPOCH_DAY.calculateYearDay();
        const MONTH_DAY = YEAR_DAY.calculateMonthDay();

        return try std.fmt.allocPrint(self.allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
            YEAR_DAY.year,
            @intFromEnum(MONTH_DAY.month),
            MONTH_DAY.day_index + 1,
        });
    }

    /// Load system prompt from file with template variable processing
    /// Agents should override this to provide their specific prompt path
    pub fn loadSystemPrompt(self: *Self, prompt_path: []const u8) ![]const u8 {
        const file = std.fs.cwd().openFile(prompt_path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    // Return a default prompt if file doesn't exist
                    return try self.allocator.dupe(u8, "You are a helpful AI assistant.");
                },
                else => return err,
            }
        };
        defer file.close();

        const template = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(template);

        // Process template variables
        return self.processTemplateVariables(template);
    }

    /// Process template variables in system prompt
    /// Variables are in the format {variable_name}
    pub fn processTemplateVariables(self: *Self, template: []const u8) ![]const u8 {
        var result = std.ArrayList(u8).initCapacity(self.allocator, template.len) catch return error.OutOfMemory;
        defer result.deinit();

        var i: usize = 0;
        while (i < template.len) {
            if (std.mem.indexOf(u8, template[i..], "{")) |start| {
                // Copy everything before the {
                try result.appendSlice(template[i .. i + start]);
                i += start;

                if (std.mem.indexOf(u8, template[i..], "}")) |end| {
                    const varName = template[i + 1 .. i + end];
                    const replacement = try self.getTemplateVariableValue(varName);
                    defer self.allocator.free(replacement);
                    try result.appendSlice(replacement);
                    i += end + 1;
                } else {
                    // No closing }, copy the { as-is
                    try result.append(template[i]);
                    i += 1;
                }
            } else {
                // No more variables, copy the rest
                try result.appendSlice(template[i..]);
                break;
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Get value for template variable
    /// Agents should override this to provide agent-specific variables
    /// This base implementation provides common variables that work with AgentConfig
    pub fn getTemplateVariableValue(self: *Self, varName: []const u8) ![]const u8 {
        // This is a base implementation that doesn't have access to config
        // Agents should override this method to provide their specific config values

        if (std.mem.eql(u8, varName, "current_date")) {
            return self.getCurrentDate();
        } else if (std.mem.eql(u8, varName, "auth_status")) {
            return self.getAuthStatusText();
        } else if (std.mem.eql(u8, varName, "session_count")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{self.session_stats.total_sessions});
        } else if (std.mem.eql(u8, varName, "total_messages")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{self.session_stats.total_messages});
        } else {
            // Unknown variable, return as-is with braces
            return try std.fmt.allocPrint(self.allocator, "{{{s}}}", .{varName});
        }
    }

    // ===== INTERACTIVE SESSION METHODS =====

    /// Enable interactive mode for this agent
    /// This creates an interactive session that agents can use for rich terminal experiences
    pub fn enableInteractiveMode(self: *Self, config: interactive_session.SessionConfig) !void {
        if (self.interactive_session != null) {
            return error.AlreadyEnabled;
        }

        self.interactive_session = try interactive_session.InteractiveSession.init(self.allocator, config);
        self.session_stats.last_session_start = std.time.timestamp();
        self.session_stats.total_sessions += 1;

        std.log.info("🤖 Interactive mode enabled for agent", .{});
    }

    /// Start the interactive session
    /// This begins the main interaction loop with the user
    pub fn startInteractiveSession(self: *Self) !void {
        if (self.interactive_session) |session| {
            try session.start();
            self.session_stats.last_session_end = std.time.timestamp();

            // Update average session duration
            const session_duration = self.session_stats.last_session_end - self.session_stats.last_session_start;
            const total_sessions = @as(f64, @floatFromInt(self.session_stats.total_sessions));
            self.session_stats.average_session_duration =
                (self.session_stats.average_session_duration * (total_sessions - 1) + @as(f64, @floatFromInt(session_duration))) / total_sessions;
        } else {
            return error.InteractiveModeNotEnabled;
        }
    }

    /// Check if interactive mode is available
    pub fn hasInteractiveMode(self: *Self) bool {
        return self.interactive_session != null and self.interactive_session.?.hasTUI();
    }

    /// Get current session statistics
    pub fn getSessionStats(self: *Self) SessionStats {
        // Update with current session stats if interactive session is active
        if (self.interactive_session) |session| {
            const session_stats = session.getStats();
            self.session_stats.total_messages = session_stats.total_messages;
            self.session_stats.total_tokens = session_stats.total_tokens;
        }
        return self.session_stats;
    }

    // ===== AUTHENTICATION METHODS =====

    /// Initialize authentication for this agent
    /// This sets up OAuth or API key authentication as available
    pub fn initAuthentication(self: *Self) !void {
        if (self.auth_client != null) {
            return error.AlreadyInitialized;
        }

        self.auth_client = try auth.createClient(self.allocator);
        self.session_stats.auth_attempts += 1;

        std.log.info("🔐 Authentication initialized", .{});
    }

    /// Check authentication status
    pub fn checkAuthStatus(self: *Self) !auth.AuthMethod {
        if (self.auth_client) |client| {
            if (client.credentials.isValid()) {
                return client.credentials.getMethod();
            } else {
                // Try to refresh OAuth tokens
                if (client.credentials.getMethod() == .oauth) {
                    client.refresh() catch {
                        return .none;
                    };
                    if (client.credentials.isValid()) {
                        return .oauth;
                    }
                }
                return .none;
            }
        } else {
            // Try to initialize authentication
            self.initAuthentication() catch {
                return .none;
            };
            return self.checkAuthStatus();
        }
    }

    /// Get authentication status as text for templates
    pub fn getAuthStatusText(self: *Self) ![]const u8 {
        const status = try self.checkAuthStatus();
        return switch (status) {
            .oauth => try self.allocator.dupe(u8, "OAuth (Claude Pro/Max)"),
            .api_key => try self.allocator.dupe(u8, "API Key"),
            .none => try self.allocator.dupe(u8, "Not authenticated"),
        };
    }

    /// Setup OAuth authentication interactively
    /// This launches the OAuth wizard for first-time setup
    pub fn setupOAuth(self: *Self) !void {
        self.session_stats.auth_attempts += 1;

        const credentials = try auth.oauth.setupOAuth(self.allocator);

        // Create new auth client with the credentials
        if (self.auth_client) |*client| {
            client.deinit();
        }

        self.auth_client = auth.AuthClient.init(self.allocator, auth.AuthCredentials{ .oauth = credentials });

        std.log.info("✅ OAuth setup completed successfully!", .{});
    }

    /// Refresh authentication tokens
    pub fn refreshAuth(self: *Self) !void {
        if (self.auth_client) |*client| {
            try client.refresh();
            std.log.info("🔄 Authentication tokens refreshed", .{});
        } else {
            return error.AuthNotInitialized;
        }
    }

    /// Get the current authentication client
    /// Returns null if authentication is not initialized
    pub fn getAuthClient(self: *Self) ?*auth.AuthClient {
        return if (self.auth_client) |*client| client else null;
    }

    /// Create an Anthropic client using current authentication
    /// This is a convenience method for agents that need to make API calls
    pub fn createAnthropicClient(self: *Self) !*anthropic.AnthropicClient {
        const client = self.getAuthClient() orelse return error.AuthNotInitialized;

        const api_key = switch (client.credentials) {
            .api_key => |key| key,
            .oauth => |oauth_creds| oauth_creds.access_token,
            .none => return error.NoCredentials,
        };

        return try anthropic.AnthropicClient.init(self.allocator, api_key);
    }

    // ===== CONVENIENCE METHODS =====

    /// Create a basic interactive session configuration
    pub fn createBasicSessionConfig(title: []const u8) interactive_session.SessionConfig {
        return .{
            .title = title,
            .interactive = true,
            .enable_tui = false,
            .enable_dashboard = false,
            .enable_auth = true,
        };
    }

    /// Create a rich interactive session configuration with TUI support
    pub fn createRichSessionConfig(title: []const u8) interactive_session.SessionConfig {
        return .{
            .title = title,
            .interactive = true,
            .enable_tui = true,
            .enable_dashboard = true,
            .enable_auth = true,
            .show_stats = true,
        };
    }

    /// Create a CLI-only session configuration
    pub fn createCLISessionConfig(title: []const u8) interactive_session.SessionConfig {
        return .{
            .title = title,
            .interactive = true,
            .enable_tui = false,
            .enable_dashboard = false,
            .enable_auth = false,
            .multi_line = false,
        };
    }
};

/// Error types for base agent operations
pub const AgentError = error{
    InteractiveModeNotEnabled,
    AlreadyEnabled,
    AuthNotInitialized,
    NoCredentials,
    AlreadyInitialized,
    InvalidConfiguration,
    SessionCreationFailed,
    AuthenticationFailed,
};

/// Interactive session helpers for easy integration
pub const InteractiveHelpers = struct {
    /// Create and start a basic interactive session
    pub fn startBasicSession(allocator: Allocator, title: []const u8) !*interactive_session.InteractiveSession {
        const session = try interactive_session.createBasicSession(allocator, title);
        try session.start();
        return session;
    }

    /// Create and start a rich interactive session with TUI
    pub fn startRichSession(allocator: Allocator, title: []const u8) !*interactive_session.InteractiveSession {
        const session = try interactive_session.createRichSession(allocator, title);
        try session.start();
        return session;
    }

    /// Create and start a CLI-only session
    pub fn startCLISession(allocator: Allocator, title: []const u8) !*interactive_session.InteractiveSession {
        const session = try interactive_session.createCLISession(allocator, title);
        try session.start();
        return session;
    }
};

/// Authentication helpers for common auth operations
pub const AuthHelpers = struct {
    /// Check if OAuth is available and valid
    pub fn hasValidOAuth(allocator: Allocator) bool {
        const client = auth.createClient(allocator) catch return false;
        defer client.deinit();
        return client.isOAuth() and client.credentials.isValid();
    }

    /// Check if API key authentication is available
    pub fn hasValidAPIKey(allocator: Allocator) bool {
        const client = auth.createClient(allocator) catch return false;
        defer client.deinit();
        return client.credentials.getMethod() == .api_key and client.credentials.isValid();
    }

    /// Get current authentication status as a formatted string
    pub fn getStatusText(allocator: Allocator) ![]const u8 {
        const client = try auth.createClient(allocator);
        defer client.deinit();

        return switch (client.credentials) {
            .oauth => |creds| {
                if (creds.isExpired()) {
                    try allocator.dupe(u8, "OAuth (expired)");
                } else {
                    try allocator.dupe(u8, "OAuth (Claude Pro/Max)");
                }
            },
            .api_key => try allocator.dupe(u8, "API Key"),
            .none => try allocator.dupe(u8, "Not authenticated"),
        };
    }

    /// Attempt to setup OAuth if not already configured
    pub fn ensureOAuthSetup(allocator: Allocator) !bool {
        if (hasValidOAuth(allocator)) {
            return true; // Already set up
        }

        std.log.info("🔐 OAuth not configured. Starting setup...", .{});
        try auth.oauth.setupOAuth(allocator);
        return hasValidOAuth(allocator);
    }
};

/// Helper functions for agent configuration management
pub const ConfigHelpers = struct {
    /// Load agent configuration from file with defaults
    /// This is a convenience wrapper around the config utilities
    pub fn loadConfig(
        comptime ConfigType: type,
        allocator: Allocator,
        agent_name: []const u8,
        defaults: ConfigType,
    ) ConfigType {
        const configUtils = @import("config.zig");
        const configPath = configUtils.getAgentConfigPath(allocator, agent_name) catch {
            std.log.info("Using default configuration for agent: {s}", .{agent_name});
            return defaults;
        };
        defer allocator.free(configPath);

        return configUtils.loadWithDefaults(ConfigType, allocator, configPath, defaults);
    }

    /// Get standard agent config path
    pub fn getConfigPath(allocator: Allocator, agent_name: []const u8) ![]const u8 {
        const configUtils = @import("config.zig");
        return configUtils.getAgentConfigPath(allocator, agent_name);
    }

    /// Create validated agent config with standard defaults
    pub fn createAgentConfig(name: []const u8, description: []const u8, author: []const u8) @import("config.zig").AgentConfig {
        const configUtils = @import("config.zig");
        return configUtils.createValidatedAgentConfig(name, description, author);
    }

    /// Create agent config with interactive features enabled
    pub fn createInteractiveAgentConfig(name: []const u8, description: []const u8, author: []const u8) @import("config.zig").AgentConfig {
        var config = createAgentConfig(name, description, author);
        // Enable features commonly used with interactive agents
        config.features.enable_network_access = true;
        config.features.enable_custom_tools = true;
        config.defaults.enable_verbose_output = true;
        return config;
    }

    /// Save agent configuration to file
    pub fn saveConfig(
        comptime ConfigType: type,
        allocator: Allocator,
        agent_name: []const u8,
        config: ConfigType,
    ) !void {
        const configUtils = @import("config.zig");
        const configPath = try configUtils.getAgentConfigPath(allocator, agent_name);
        defer allocator.free(configPath);

        // Convert config to JSON for saving
        const json_content = try std.json.stringifyAlloc(allocator, config, .{});
        defer allocator.free(json_content);

        const file = try std.fs.cwd().createFile(configPath, .{ .mode = 0o600 });
        defer file.close();

        try file.writeAll(json_content);
    }
};

/// Template variable processing for agents with AgentConfig
/// This provides the standard template variables that work with the AgentConfig structure
pub const TemplateProcessor = struct {
    /// Process template variables using an AgentConfig
    pub fn getTemplateVariableValue(
        allocator: Allocator,
        varName: []const u8,
        config: @import("config.zig").AgentConfig,
    ) ![]const u8 {
        const cfg = &config;

        if (std.mem.eql(u8, varName, "agent_name")) {
            return try allocator.dupe(u8, cfg.agent_info.name);
        } else if (std.mem.eql(u8, varName, "agent_version")) {
            return try allocator.dupe(u8, cfg.agent_info.version);
        } else if (std.mem.eql(u8, varName, "agent_description")) {
            return try allocator.dupe(u8, cfg.agent_info.description);
        } else if (std.mem.eql(u8, varName, "agent_author")) {
            return try allocator.dupe(u8, cfg.agent_info.author);
        } else if (std.mem.eql(u8, varName, "debug_enabled")) {
            return try allocator.dupe(u8, if (cfg.defaults.enable_debug_logging) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "verbose_enabled")) {
            return try allocator.dupe(u8, if (cfg.defaults.enable_verbose_output) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "custom_tools_enabled")) {
            return try allocator.dupe(u8, if (cfg.features.enable_custom_tools) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "file_operations_enabled")) {
            return try allocator.dupe(u8, if (cfg.features.enable_file_operations) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "network_access_enabled")) {
            return try allocator.dupe(u8, if (cfg.features.enable_network_access) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "system_commands_enabled")) {
            return try allocator.dupe(u8, if (cfg.features.enable_system_commands) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "max_input_size")) {
            return try std.fmt.allocPrint(allocator, "{d}", .{cfg.limits.max_input_size});
        } else if (std.mem.eql(u8, varName, "max_output_size")) {
            return try std.fmt.allocPrint(allocator, "{d}", .{cfg.limits.max_output_size});
        } else if (std.mem.eql(u8, varName, "max_processing_time")) {
            return try std.fmt.allocPrint(allocator, "{d}", .{cfg.limits.max_processing_time_ms});
        } else if (std.mem.eql(u8, varName, "current_date")) {
            const now = std.time.timestamp();
            const epochSeconds = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
            const epochDay = epochSeconds.getEpochDay();
            const yearDay = epochDay.calculateYearDay();
            const monthDay = yearDay.calculateMonthDay();

            return try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
                yearDay.year,
                @intFromEnum(monthDay.month),
                monthDay.day_index + 1,
            });
        } else if (std.mem.eql(u8, varName, "auth_status")) {
            return AuthHelpers.getStatusText(allocator);
        } else if (std.mem.eql(u8, varName, "has_oauth")) {
            return try allocator.dupe(u8, if (AuthHelpers.hasValidOAuth(allocator)) "yes" else "no");
        } else if (std.mem.eql(u8, varName, "has_api_key")) {
            return try allocator.dupe(u8, if (AuthHelpers.hasValidAPIKey(allocator)) "yes" else "no");
        } else {
            // Unknown variable, return as-is with braces
            return try std.fmt.allocPrint(allocator, "{{{s}}}", .{varName});
        }
    }
};

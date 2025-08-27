//! Base agent functionality that all agents can inherit from.
//! Provides common lifecycle methods, template variable processing,
//! standardized configuration patterns, OAuth authentication support,
//! and interactive session management.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Use unified session and auth modules
const session = @import("interactive_session");
const auth = @import("auth_shared");
const anthropic = @import("anthropic_shared");
const agent_main = @import("agent_main");

/// Base agent structure with common functionality.
/// Agents can embed this struct or use composition to inherit base functionality.
pub const BaseAgent = struct {
    allocator: Allocator,
    session_manager: ?*session.Session = null,
    auth_client: ?*auth.AuthClient = null,
    session_stats: session.SessionStats = .{},

    const Self = @This();

    // SessionStats is now imported from session.zig

    /// Initialize base agent with allocator
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Clean up base agent resources
    pub fn deinit(self: *Self) void {
        // Clean up session manager
        if (self.sessionManager) |sess_mgr| {
            sess_mgr.deinit();
        }

        // Clean up auth client
        if (self.authClient) |*client| {
            client.deinit();
        }

        // Agents should override this if they have additional cleanup
    }

    /// Get current date in YYYY-MM-DD format
    pub fn get_current_date(self: *Self) ![]const u8 {
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
    pub fn load_system_prompt(self: *Self, prompt_path: []const u8) ![]const u8 {
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
        return self.process_template_variables(template);
    }

    /// Process template variables in system prompt
    /// Variables are in the format {variable_name}
    pub fn process_template_variables(self: *Self, template: []const u8) ![]const u8 {
        var result = std.ArrayListUnmanaged(u8){};
        try result.ensureTotalCapacity(self.allocator, template.len);
        defer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < template.len) {
            if (std.mem.indexOf(u8, template[i..], "{")) |start| {
                // Copy everything before the {
                try result.appendSlice(self.allocator, template[i .. i + start]);
                i += start;

                if (std.mem.indexOf(u8, template[i..], "}")) |end| {
                    const varName = template[i + 1 .. i + end];
                    const replacement = try self.getTemplateVariableValue(varName);
                    defer self.allocator.free(replacement);
                    try result.appendSlice(self.allocator, replacement);
                    i += end + 1;
                } else {
                    // No closing }, copy the { as-is
                    try result.append(self.allocator, template[i]);
                    i += 1;
                }
            } else {
                // No more variables, copy the rest
                try result.appendSlice(self.allocator, template[i..]);
                break;
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Get value for template variable
    /// Agents should override this to provide agent-specific variables
    /// This base implementation provides common variables that work with AgentConfig
    pub fn get_template_variable_value(self: *Self, var_name: []const u8) ![]const u8 {
        // This is a base implementation that doesn't have access to config
        // Agents should override this method to provide their specific config values

        if (std.mem.eql(u8, var_name, "current_date")) {
            return self.get_current_date();
        } else if (std.mem.eql(u8, var_name, "auth_status")) {
            return self.get_auth_status_text();
        } else if (std.mem.eql(u8, var_name, "session_count")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{self.session_stats.total_sessions});
        } else if (std.mem.eql(u8, var_name, "total_messages")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{self.session_stats.total_messages});
        } else {
            // Unknown variable, return as-is with braces
            return try std.fmt.allocPrint(self.allocator, "{{{s}}}", .{var_name});
        }
    }

    // ===== INTERACTIVE SESSION METHODS =====

    /// Enable interactive mode for this agent
    /// This creates a session manager that agents can use for rich terminal experiences
    pub fn enable_interactive_mode(self: *Self, config: session.SessionConfig) !void {
        _ = config; // Configuration stored but not currently used in session manager
        if (self.sessionManager != null) {
            return error.AlreadyEnabled;
        }

        // Create session manager with default directory
        const sessionsDir = try std.fmt.allocPrint(self.allocator, "{s}/.docz/sessions", .{std.fs.selfExePathAlloc(self.allocator)});
        defer self.allocator.free(sessionsDir);

        self.sessionManager = try session.Session.init(self.allocator, sessionsDir);
        self.sessionStats.last_session_start = std.time.timestamp();
        self.sessionStats.total_sessions += 1;

        std.log.info("🤖 Interactive mode enabled for agent", .{});
    }

    /// Start the interactive session
    /// This begins the main interaction loop with the user
    pub fn start_interactive_session(self: *Self) !void {
        if (self.sessionManager) |sess_mgr| {
            // Create a new session
            const sessionId = try session.generateSessionId(self.allocator);
            _ = try sess_mgr.createSession(sessionId);

            self.sessionStats.last_session_end = std.time.timestamp();

            // Update average session duration
            const sessionDuration = self.sessionStats.last_session_end - self.sessionStats.last_session_start;
            const totalSessions = @as(f64, @floatFromInt(self.sessionStats.total_sessions));
            self.sessionStats.average_session_duration =
                (self.sessionStats.average_session_duration * (totalSessions - 1) + @as(f64, @floatFromInt(sessionDuration))) / totalSessions;
        } else {
            return error.InteractiveModeNotEnabled;
        }
    }

    /// Check if interactive mode is available
    pub fn has_interactive_mode(self: *Self) bool {
        return self.sessionManager != null;
    }

    /// Get current session statistics
    pub fn get_session_stats(self: *Self) session.SessionStats {
        // Update with current session manager stats
        if (self.sessionManager) |sess_mgr| {
            self.sessionStats = sess_mgr.getStats();
        }
        return self.sessionStats;
    }

    // ===== AUTHENTICATION METHODS =====

    /// Initialize authentication for this agent
    /// This sets up OAuth or API key authentication as available
    pub fn init_authentication(self: *Self) !void {
        if (self.authClient != null) {
            return error.AlreadyInitialized;
        }

        self.authClient = try auth.createClient(self.allocator);
        self.sessionStats.auth_attempts += 1;

        std.log.info("🔐 Authentication initialized", .{});
    }

    /// Check authentication status
    pub fn check_auth_status(self: *Self) !auth.AuthMethod {
        if (self.authClient) |client| {
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
    pub fn get_auth_status_text(self: *Self) ![]const u8 {
        const status = try self.checkAuthStatus();
        return switch (status) {
            .oauth => try self.allocator.dupe(u8, "OAuth (Claude Pro/Max)"),
            .api_key => try self.allocator.dupe(u8, "API Key"),
            .none => try self.allocator.dupe(u8, "Not authenticated"),
        };
    }

    /// Setup OAuth authentication interactively
    /// This launches the OAuth wizard for first-time setup
    pub fn setup_oauth(self: *Self) !void {
        self.sessionStats.auth_attempts += 1;

        const credentials = try auth.oauth.setupOAuth(self.allocator);

        // Create new auth client with the credentials
        if (self.authClient) |*client| {
            client.deinit();
        }

        self.authClient = auth.AuthClient.init(self.allocator, auth.AuthCredentials{ .oauth = credentials });

        std.log.info("✅ OAuth setup completed successfully!", .{});
    }

    /// Refresh authentication tokens
    pub fn refresh_auth(self: *Self) !void {
        if (self.authClient) |*client| {
            try client.refresh();
            std.log.info("🔄 Authentication tokens refreshed", .{});
        } else {
            return error.AuthNotInitialized;
        }
    }

    /// Get the current authentication client
    /// Returns null if authentication is not initialized
    pub fn get_auth_client(self: *Self) ?*auth.AuthClient {
        return if (self.authClient) |*client| client else null;
    }

    /// Create an Anthropic client using current authentication
    /// This is a convenience method for agents that need to make API calls
    pub fn create_anthropic_client(self: *Self) !*anthropic.AnthropicClient {
        const client = self.getAuthClient() orelse return error.AuthNotInitialized;

        const apiKey = switch (client.credentials) {
            .api_key => |key| key,
            .oauth => |oauth_creds| oauth_creds.access_token,
            .none => return error.NoCredentials,
        };

        return try anthropic.AnthropicClient.init(self.allocator, apiKey);
    }

    // ===== CONVENIENCE METHODS =====

    /// Create a basic session configuration
    pub fn create_basic_session_config(title: []const u8) session.SessionConfig {
        return session.SessionHelpers.createBasicConfig(title);
    }

    /// Create a rich session configuration with TUI support
    pub fn create_rich_session_config(title: []const u8) session.SessionConfig {
        return session.SessionHelpers.createRichConfig(title);
    }

    /// Create a CLI-only session configuration
    pub fn create_cli_session_config(title: []const u8) session.SessionConfig {
        return session.SessionHelpers.createCliConfig(title);
    }

    // ===== THEME SUPPORT METHODS =====

    /// Get the current active theme
    /// This provides easy access to theme colors for agents
    pub fn get_current_theme(self: *Self) ?*agent_main.theme_manager.ColorScheme {
        _ = self; // Not currently used but available for future per-agent theme customization
        return agent_main.getCurrentTheme();
    }

    /// Get theme-aware color for UI elements
    /// Convenience method that wraps agent_main.getThemeColor
    pub fn get_theme_color(self: *Self, color_type: anytype) []const u8 {
        _ = self; // Not currently used but available for future per-agent customization
        _ = color_type; // TODO: Implement proper color type enum
        return agent_main.getThemeColor(.primary);
    }

    /// Get accessibility information about the current theme
    /// Useful for agents that need to adapt their UI based on accessibility settings
    pub fn get_theme_accessibility_info(self: *Self) @TypeOf(agent_main.getThemeAccessibilityInfo()) {
        _ = self; // Not currently used but available for future per-agent customization
        return agent_main.getThemeAccessibilityInfo();
    }

    /// Check if the current theme is dark mode
    /// Useful for agents that need to adapt content based on theme brightness
    pub fn is_dark_theme(self: *Self) bool {
        const theme = self.getCurrentTheme() orelse return false;
        return theme.isDark;
    }

    /// Get theme-aware progress indicator
    /// Convenience method for consistent progress display across agents
    pub fn get_progress_indicator(self: *Self, completed: bool) []const u8 {
        _ = self; // Not currently used but available for future per-agent customization
        return agent_main.styleProgressIndicator(completed);
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

/// Session helpers for easy integration
pub const SessionHelpers = struct {
    /// Create and start a basic session
    pub fn start_basic_session(allocator: Allocator, title: []const u8) !*session.Session {
        _ = title; // Not used in current implementation
        const sessionsDir = try std.fmt.allocPrint(allocator, "{s}/.docz/sessions", .{std.fs.selfExePathAlloc(allocator)});
        defer allocator.free(sessionsDir);

        const sess_mgr = try session.Session.init(allocator, sessionsDir);
        _ = try sess_mgr.createSession(try session.generateSessionId(allocator));
        return sess_mgr;
    }

    /// Create and start a rich session with TUI
    pub fn start_rich_session(allocator: Allocator, title: []const u8) !*session.Session {
        _ = title; // Not used in current implementation
        const sessionsDir = try std.fmt.allocPrint(allocator, "{s}/.docz/sessions", .{std.fs.selfExePathAlloc(allocator)});
        defer allocator.free(sessionsDir);

        const sess_mgr = try session.Session.init(allocator, sessionsDir);
        _ = try sess_mgr.createSession(try session.generateSessionId(allocator));
        return sess_mgr;
    }

    /// Create and start a CLI-only session
    pub fn start_cli_session(allocator: Allocator, title: []const u8) !*session.Session {
        _ = title; // Not used in current implementation
        const sessionsDir = try std.fmt.allocPrint(allocator, "{s}/.docz/sessions", .{std.fs.selfExePathAlloc(allocator)});
        defer allocator.free(sessionsDir);

        const sess_mgr = try session.Session.init(allocator, sessionsDir);
        _ = try sess_mgr.createSession(try session.generateSessionId(allocator));
        return sess_mgr;
    }
};

/// Authentication helpers for common auth operations
pub const AuthHelpers = struct {
    /// Check if OAuth is available and valid
    pub fn has_valid_oauth(allocator: Allocator) bool {
        const client = auth.createClient(allocator) catch return false;
        defer client.deinit();
        return client.isOAuth() and client.credentials.isValid();
    }

    /// Check if API key authentication is available
    pub fn has_valid_api_key(allocator: Allocator) bool {
        const client = auth.createClient(allocator) catch return false;
        defer client.deinit();
        return client.credentials.getMethod() == .api_key and client.credentials.isValid();
    }

    /// Get current authentication status as a formatted string
    pub fn get_status_text(allocator: Allocator) ![]const u8 {
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
    pub fn ensure_oauth_setup(allocator: Allocator) !bool {
        if (has_valid_oauth(allocator)) {
            return true; // Already set up
        }

        std.log.info("🔐 OAuth not configured. Starting setup...", .{});
        try auth.oauth.setupOAuth(allocator);
        return has_valid_oauth(allocator);
    }
};

/// Helper functions for agent configuration management
pub const ConfigHelpers = struct {
    /// Load agent configuration from file with defaults
    /// This is a convenience wrapper around the config utilities
    pub fn load_config(
        comptime ConfigType: type,
        allocator: Allocator,
        agent_name: []const u8,
        defaults: ConfigType,
    ) ConfigType {
        const configUtils = @import("config.zig");
        const config_path = configUtils.get_agent_config_path(allocator, agent_name) catch {
            std.log.info("Using default configuration for agent: {s}", .{agent_name});
            return defaults;
        };
        defer allocator.free(config_path);

        return configUtils.loadWithDefaults(ConfigType, allocator, config_path, defaults);
    }

    /// Get standard agent config path
    pub fn get_config_path(allocator: Allocator, agent_name: []const u8) ![]const u8 {
        const configUtils = @import("config.zig");
        return configUtils.get_agent_config_path(allocator, agent_name);
    }

    /// Create validated agent config with standard defaults
    pub fn create_agent_config(name: []const u8, description: []const u8, author: []const u8) @import("config.zig").AgentConfig {
        const configUtils = @import("config.zig");
        return configUtils.create_validated_agent_config(name, description, author);
    }

    /// Create agent config with interactive features enabled
    pub fn create_interactive_agent_config(name: []const u8, description: []const u8, author: []const u8) @import("config.zig").AgentConfig {
        var config = create_agent_config(name, description, author);
        // Enable features commonly used with interactive agents
        config.features.enable_network_access = true;
        config.features.enable_custom_tools = true;
        config.defaults.enable_verbose_output = true;
        return config;
    }

    /// Save agent configuration to file
    pub fn save_config(
        comptime ConfigType: type,
        allocator: Allocator,
        agent_name: []const u8,
        config: ConfigType,
    ) !void {
        const configUtils = @import("config.zig");
        const configPath = try configUtils.getAgentConfigPath(allocator, agent_name);
        defer allocator.free(configPath);

        // Convert config to JSON for saving
        const jsonContent = try std.json.stringifyAlloc(allocator, config, .{});
        defer allocator.free(jsonContent);

        const file = try std.fs.cwd().createFile(configPath, .{ .mode = 0o600 });
        defer file.close();

        try file.writeAll(jsonContent);
    }
};

/// Template variable processing for agents with AgentConfig
/// This provides the standard template variables that work with the AgentConfig structure
pub const TemplateProcessor = struct {
    /// Process template variables using an AgentConfig
    pub fn get_template_variable_value(
        allocator: Allocator,
        var_name: []const u8,
        config: @import("config.zig").AgentConfig,
    ) ![]const u8 {
        const cfg = &config;

        if (std.mem.eql(u8, var_name, "agent_name")) {
            return try allocator.dupe(u8, cfg.agent_info.name);
        } else if (std.mem.eql(u8, var_name, "agent_version")) {
            return try allocator.dupe(u8, cfg.agent_info.version);
        } else if (std.mem.eql(u8, var_name, "agent_description")) {
            return try allocator.dupe(u8, cfg.agent_info.description);
        } else if (std.mem.eql(u8, var_name, "agent_author")) {
            return try allocator.dupe(u8, cfg.agent_info.author);
        } else if (std.mem.eql(u8, var_name, "debug_enabled")) {
            return try allocator.dupe(u8, if (cfg.defaults.enable_debug_logging) "enabled" else "disabled");
        } else if (std.mem.eql(u8, var_name, "verbose_enabled")) {
            return try allocator.dupe(u8, if (cfg.defaults.enable_verbose_output) "enabled" else "disabled");
        } else if (std.mem.eql(u8, var_name, "custom_tools_enabled")) {
            return try allocator.dupe(u8, if (cfg.features.enable_custom_tools) "enabled" else "disabled");
        } else if (std.mem.eql(u8, var_name, "file_operations_enabled")) {
            return try allocator.dupe(u8, if (cfg.features.enable_file_operations) "enabled" else "disabled");
        } else if (std.mem.eql(u8, var_name, "network_access_enabled")) {
            return try allocator.dupe(u8, if (cfg.features.enable_network_access) "enabled" else "disabled");
        } else if (std.mem.eql(u8, var_name, "system_commands_enabled")) {
            return try allocator.dupe(u8, if (cfg.features.enable_system_commands) "enabled" else "disabled");
        } else if (std.mem.eql(u8, var_name, "max_input_size")) {
            return try std.fmt.allocPrint(allocator, "{d}", .{cfg.limits.max_input_size});
        } else if (std.mem.eql(u8, var_name, "max_output_size")) {
            return try std.fmt.allocPrint(allocator, "{d}", .{cfg.limits.max_output_size});
        } else if (std.mem.eql(u8, var_name, "max_processing_time")) {
            return try std.fmt.allocPrint(allocator, "{d}", .{cfg.limits.max_processing_time_ms});
        } else if (std.mem.eql(u8, var_name, "current_date")) {
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
        } else if (std.mem.eql(u8, var_name, "auth_status")) {
            return AuthHelpers.get_status_text(allocator);
        } else if (std.mem.eql(u8, var_name, "has_oauth")) {
            return try allocator.dupe(u8, if (AuthHelpers.has_valid_oauth(allocator)) "yes" else "no");
        } else if (std.mem.eql(u8, var_name, "has_api_key")) {
            return try allocator.dupe(u8, if (AuthHelpers.has_valid_api_key(allocator)) "yes" else "no");
        } else {
            // Unknown variable, return as-is with braces
            return try std.fmt.allocPrint(allocator, "{{{s}}}", .{var_name});
        }
    }
};

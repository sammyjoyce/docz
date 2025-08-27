//! Base agent functionality that all agents can inherit from.
//! Provides common lifecycle methods, template variable processing,
//! standardized configuration patterns, OAuth authentication support,
//! and interactive session management.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Use session and auth modules
const session = @import("interactive_session");
const auth = @import("auth_shared");
const anthropic = @import("anthropic_shared");
const agent_main = @import("agent_main");

/// Base agent structure with common functionality.
/// Agents can embed this struct or use composition to inherit base functionality.
pub const Agent = struct {
    allocator: Allocator,
    sessionManager: ?*session.Sessions = null,
    authClient: ?*auth.AuthClient = null,
    sessionStats: session.SessionStats = .{},

    const Self = @This();

    // SessionStats is now imported from session_core.zig

    /// Initialize base agent with allocator
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Clean up base agent resources
    pub fn deinit(self: *Self) void {
        // Clean up session manager
        if (self.sessionManager) |sessMgr| {
            sessMgr.deinit();
        }

        // Clean up auth client
        if (self.authClient) |clientPtr| {
            clientPtr.deinit();
            self.allocator.destroy(clientPtr);
        }

        // Agents should override this if they have additional cleanup
    }

    /// Get current date in YYYY-MM-DD format
    pub fn getCurrentDate(self: *Self) ![]const u8 {
        const now = std.time.timestamp();
        const epochSeconds = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
        const epochDay = epochSeconds.getEpochDay();
        const yearDay = epochDay.calculateYearDay();
        const monthDay = yearDay.calculateMonthDay();

        return try std.fmt.allocPrint(self.allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
            yearDay.year,
            @intFromEnum(monthDay.month),
            monthDay.day_index + 1,
        });
    }

    /// Load system prompt from file with template variable processing
    /// Agents should override this to provide their specific prompt path
    pub fn loadSystemPrompt(self: *Self, promptPath: []const u8) ![]const u8 {
        const file = std.fs.cwd().openFile(promptPath, .{}) catch |err| {
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
    pub fn getTemplateVariableValue(self: *Self, varName: []const u8) ![]const u8 {
        // This is a base implementation that doesn't have access to config
        // Agents should override this method to provide their specific config values

        if (std.mem.eql(u8, varName, "current_date")) {
            return self.getCurrentDate();
        } else if (std.mem.eql(u8, varName, "auth_status")) {
            return self.getAuthStatusText();
        } else if (std.mem.eql(u8, varName, "session_count")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{self.sessionStats.messagesProcessed});
        } else if (std.mem.eql(u8, varName, "total_messages")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{self.sessionStats.messagesProcessed});
        } else {
            // Unknown variable, return as-is with braces
            return try std.fmt.allocPrint(self.allocator, "{{{s}}}", .{varName});
        }
    }

    // ===== INTERACTIVE SESSION METHODS =====

    /// Enable interactive mode for this agent
    /// This creates a session manager that agents can use for rich terminal experiences
    pub fn enableInteractiveMode(self: *Self, config: anytype) !void {
        _ = config; // Configuration stored but not currently used in session manager
        if (self.sessionManager != null) {
            return error.AlreadyEnabled;
        }

        // Create session manager with default directory
        var exePathBuf: [4096]u8 = undefined;
        const exePath = try std.fs.selfExePath(exePathBuf[0..]);
        const sessionsDir = try std.fmt.allocPrint(self.allocator, "{s}/.docz/sessions", .{exePath});
        defer self.allocator.free(sessionsDir);

        self.sessionManager = try session.Sessions.init(self.allocator, sessionsDir, false);
        self.sessionStats.lastSessionStart = std.time.timestamp();
        self.sessionStats.totalSessions += 1;

        std.log.info("🤖 Interactive mode enabled for agent", .{});
    }

    /// Start the interactive session
    /// This begins the main interaction loop with the user
    pub fn startInteractiveSession(self: *Self) !void {
        if (self.sessionManager) |sessMgr| {
            // Create a new session
            const sessionId = try session.generateSessionId(self.allocator);
            const config = try self.createSessionConfig("Interactive Session");
            _ = try sessMgr.createSession(sessionId, config);

            self.sessionStats.lastSessionEnd = std.time.timestamp();

            // Update average session duration
            const sessionDuration = self.sessionStats.lastSessionEnd - self.sessionStats.lastSessionStart;
            const totalSessions = @as(f64, @floatFromInt(self.sessionStats.totalSessions));
            self.sessionStats.averageSessionDuration =
                (self.sessionStats.averageSessionDuration * (totalSessions - 1) + @as(f64, @floatFromInt(sessionDuration))) / totalSessions;
        } else {
            return error.InteractiveModeNotEnabled;
        }
    }

    /// Check if interactive mode is available
    pub fn hasInteractiveMode(self: *Self) bool {
        return self.sessionManager != null;
    }

    /// Get current session statistics
    pub fn getSessionStats(self: *Self) session.SessionStats {
        // Update with current session manager stats
        if (self.sessionManager) |sessMgr| {
            self.sessionStats = sessMgr.getStats();
        }
        return self.sessionStats;
    }

    // ===== AUTHENTICATION METHODS =====

    /// Initialize authentication for this agent
    /// This sets up OAuth or API key authentication as available
    pub fn initAuthentication(self: *Self) !void {
        if (self.authClient != null) {
            return error.AlreadyInitialized;
        }

        const clientPtr = try self.allocator.create(auth.AuthClient);
        clientPtr.* = try auth.createClient(self.allocator);
        self.authClient = clientPtr;
        self.sessionStats.authAttempts += 1;

        std.log.info("🔐 Authentication initialized", .{});
    }

    /// Check authentication status
    pub fn checkAuthStatus(self: *Self) !auth.AuthMethod {
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
    pub fn setupOauth(self: *Self) !void {
        self.sessionStats.authAttempts += 1;

        const credentials = try auth.oauth.setupOAuth(self.allocator);

        // Create new auth client with the credentials
        if (self.authClient) |clientPtr| {
            clientPtr.deinit();
        }

        const clientPtr = try self.allocator.create(auth.AuthClient);
        clientPtr.* = auth.AuthClient.init(self.allocator, auth.AuthCredentials{ .oauth = credentials });
        self.authClient = clientPtr;

        std.log.info("✅ OAuth setup completed successfully!", .{});
    }

    /// Refresh authentication tokens
    pub fn refreshAuth(self: *Self) !void {
        if (self.authClient) |*client| {
            try client.refresh();
            std.log.info("🔄 Authentication tokens refreshed", .{});
        } else {
            return error.AuthNotInitialized;
        }
    }

    /// Get the current authentication client
    /// Returns null if authentication is not initialized
    pub fn getAuthClient(self: *Self) ?*auth.AuthClient {
        return if (self.authClient) |*client| client else null;
    }

    /// Create an Anthropic client using current authentication
    /// This is a convenience method for agents that need to make API calls
    pub fn createAnthropicClient(self: *Self) !*anthropic.AnthropicClient {
        const client = self.getAuthClient() orelse return error.AuthNotInitialized;
        // Initialize the proper network client based on auth method
        switch (client.credentials) {
            .api_key => |key| {
                return try anthropic.AnthropicClient.init(self.allocator, key);
            },
            .oauth => |oauthCreds| {
                // Map auth.oauth.Credentials to anthropic.Credentials and use OAuth-aware init
                const creds = anthropic.Credentials{
                    .type = oauthCreds.type,
                    .accessToken = oauthCreds.accessToken,
                    .refreshToken = oauthCreds.refreshToken,
                    .expiresAt = oauthCreds.expiresAt,
                };
                // Persist path used by auth core for refreshed tokens
                const path: []const u8 = "claude_oauth_creds.json";
                return try anthropic.AnthropicClient.initWithOAuth(self.allocator, creds, path);
            },
            .none => return error.NoCredentials,
        }
    }

    // ===== CONVENIENCE METHODS =====

    /// Create a session configuration
    pub fn createSessionConfig(self: *Self, title: []const u8) anyerror!session.SessionConfig {
        return try session.SessionHelpers.createConfig(self.allocator, title, "agent");
    }

    /// Create a rich session configuration with TUI support
    pub fn createRichSessionConfig(self: *Self, title: []const u8) session.SessionConfig {
        return session.SessionHelpers.createRichConfig(self.allocator, title, "agent");
    }

    /// Create a CLI-only session configuration
    pub fn createCliSessionConfig(self: *Self, title: []const u8) session.SessionConfig {
        return session.SessionHelpers.createCliConfig(self.allocator, title, "agent");
    }

    // ===== THEME SUPPORT METHODS =====

    /// Get the current active theme
    /// This provides easy access to theme colors for agents
    pub fn getCurrentTheme(self: *Self) ?*agent_main.theme.ColorScheme {
        _ = self; // Not currently used but available for future per-agent theme customization
        return agent_main.getCurrentTheme();
    }

    /// Get theme-aware color for UI elements
    /// Convenience method that wraps agent_main.getThemeColor
    pub fn getThemeColor(self: *Self, colorType: anytype) []const u8 {
        _ = self; // Not currently used but available for future per-agent customization
        _ = colorType; // TODO: Implement proper color type enum
        return agent_main.getThemeColor(.primary);
    }

    /// Get accessibility information about the current theme
    /// Useful for agents that need to adapt their UI based on accessibility settings
    pub fn getThemeAccessibilityInfo(self: *Self) @TypeOf(agent_main.getThemeAccessibilityInfo()) {
        _ = self; // Not currently used but available for future per-agent customization
        return agent_main.getThemeAccessibilityInfo();
    }

    /// Check if the current theme is dark mode
    /// Useful for agents that need to adapt content based on theme brightness
    pub fn isDarkTheme(self: *Self) bool {
        const theme = self.getCurrentTheme() orelse return false;
        return theme.isDark;
    }

    /// Get theme-aware progress indicator
    /// Convenience method for consistent progress display across agents
    pub fn getProgressIndicator(self: *Self, completed: bool) []const u8 {
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
    /// Create and start a session
    pub fn startSession(allocator: Allocator, title: []const u8) !*session.Sessions {
        _ = title; // Not used in current implementation
        const sessionsDir = try std.fmt.allocPrint(allocator, "{s}/.docz/sessions", .{std.fs.selfExePathAlloc(allocator)});
        defer allocator.free(sessionsDir);

        const sessMgr = try session.Sessions.init(allocator, sessionsDir);
        _ = try sessMgr.createSession(try session.generateSessionId(allocator));
        return sessMgr;
    }

    /// Create and start a rich session with TUI
    pub fn startRichSession(allocator: Allocator, title: []const u8) !*session.Sessions {
        _ = title; // Not used in current implementation
        const sessionsDir = try std.fmt.allocPrint(allocator, "{s}/.docz/sessions", .{std.fs.selfExePathAlloc(allocator)});
        defer allocator.free(sessionsDir);

        const sessMgr = try session.Sessions.init(allocator, sessionsDir);
        _ = try sessMgr.createSession(try session.generateSessionId(allocator));
        return sessMgr;
    }

    /// Create and start a CLI-only session
    pub fn startCliSession(allocator: Allocator, title: []const u8) !*session.Sessions {
        _ = title; // Not used in current implementation
        const sessionsDir = try std.fmt.allocPrint(allocator, "{s}/.docz/sessions", .{std.fs.selfExePathAlloc(allocator)});
        defer allocator.free(sessionsDir);

        const sessMgr = try session.Sessions.init(allocator, sessionsDir);
        _ = try sessMgr.createSession(try session.generateSessionId(allocator));
        return sessMgr;
    }
};

/// Authentication helpers for common auth operations
pub const AuthHelpers = struct {
    /// Check if OAuth is available and valid
    pub fn hasValidOauth(allocator: Allocator) bool {
        var client = auth.createClient(allocator) catch return false;
        defer client.deinit();
        return client.isOAuth() and client.credentials.isValid();
    }

    /// Check if API key authentication is available
    pub fn hasValidApiKey(allocator: Allocator) bool {
        var client = auth.createClient(allocator) catch return false;
        defer client.deinit();
        return client.credentials.getMethod() == .api_key and client.credentials.isValid();
    }

    /// Get current authentication status as a formatted string
    pub fn getStatusText(allocator: Allocator) ![]const u8 {
        var client = try auth.createClient(allocator);
        defer client.deinit();

        return switch (client.credentials) {
            .oauth => |creds| {
                if (creds.isExpired()) {
                    return try allocator.dupe(u8, "OAuth (expired)");
                } else {
                    return try allocator.dupe(u8, "OAuth (Claude Pro/Max)");
                }
            },
            .api_key => try allocator.dupe(u8, "API Key"),
            .none => try allocator.dupe(u8, "Not authenticated"),
        };
    }

    /// Attempt to setup OAuth if not already configured
    pub fn ensureOauthSetup(allocator: Allocator) !bool {
        if (hasValidOauth(allocator)) {
            return true; // Already set up
        }

        std.log.info("🔐 OAuth not configured. Starting setup...", .{});
        try auth.oauth.setupOAuth(allocator);
        return hasValidOauth(allocator);
    }
};

/// Helper functions for agent configuration management
pub const ConfigHelpers = struct {
    /// Load agent configuration from file with defaults
    /// This is a convenience wrapper around the config utilities
    pub fn loadConfig(
        comptime ConfigType: type,
        allocator: Allocator,
        agentName: []const u8,
        defaults: ConfigType,
    ) ConfigType {
        const configUtils = @import("config_shared");
        const configPath = configUtils.getAgentConfigPath(allocator, agentName) catch {
            std.log.info("Using default configuration for agent: {s}", .{agentName});
            return defaults;
        };
        defer allocator.free(configPath);

        return configUtils.loadWithDefaults(ConfigType, allocator, configPath, defaults);
    }

    /// Get standard agent config path
    pub fn getConfigPath(allocator: Allocator, agentName: []const u8) ![]const u8 {
        const configUtils = @import("config_shared");
        return configUtils.getAgentConfigPath(allocator, agentName);
    }

    /// Create validated agent config with standard defaults
    pub fn createAgentConfig(name: []const u8, description: []const u8, author: []const u8) @import("config_shared").AgentConfig {
        const configUtils = @import("config_shared");
        return configUtils.createValidatedAgentConfig(name, description, author);
    }

    /// Create agent config with interactive features enabled
    pub fn createInteractiveAgentConfig(name: []const u8, description: []const u8, author: []const u8) @import("config_shared").AgentConfig {
        var config = createAgentConfig(name, description, author);
        // Enable features commonly used with interactive agents
        config.features.enableNetworkAccess = true;
        config.features.enableCustomTools = true;
        config.defaults.enableVerboseOutput = true;
        return config;
    }

    /// Save agent configuration to file
    pub fn saveConfig(
        comptime ConfigType: type,
        allocator: Allocator,
        agentName: []const u8,
        config: ConfigType,
    ) !void {
        const configUtils = @import("config_shared");
        const configPath = try configUtils.getAgentConfigPath(allocator, agentName);
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
    pub fn getTemplateVariableValue(
        allocator: Allocator,
        varName: []const u8,
        config: @import("config_shared").AgentConfig,
    ) ![]const u8 {
        const cfg = &config;

        if (std.mem.eql(u8, varName, "agent_name")) {
            return try allocator.dupe(u8, cfg.agentInfo.name);
        } else if (std.mem.eql(u8, varName, "agent_version")) {
            return try allocator.dupe(u8, cfg.agentInfo.version);
        } else if (std.mem.eql(u8, varName, "agent_description")) {
            return try allocator.dupe(u8, cfg.agentInfo.description);
        } else if (std.mem.eql(u8, varName, "agent_author")) {
            return try allocator.dupe(u8, cfg.agentInfo.author);
        } else if (std.mem.eql(u8, varName, "debug_enabled")) {
            return try allocator.dupe(u8, if (cfg.defaults.enableDebugLogging) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "verbose_enabled")) {
            return try allocator.dupe(u8, if (cfg.defaults.enableVerboseOutput) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "custom_tools_enabled")) {
            return try allocator.dupe(u8, if (cfg.features.enableCustomTools) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "file_operations_enabled")) {
            return try allocator.dupe(u8, if (cfg.features.enableFileOperations) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "network_access_enabled")) {
            return try allocator.dupe(u8, if (cfg.features.enableNetworkAccess) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "system_commands_enabled")) {
            return try allocator.dupe(u8, if (cfg.features.enableSystemCommands) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "max_input_size")) {
            return try std.fmt.allocPrint(allocator, "{d}", .{cfg.limits.inputSizeMax});
        } else if (std.mem.eql(u8, varName, "max_output_size")) {
            return try std.fmt.allocPrint(allocator, "{d}", .{cfg.limits.outputSizeMax});
        } else if (std.mem.eql(u8, varName, "max_processing_time")) {
            return try std.fmt.allocPrint(allocator, "{d}", .{cfg.limits.processingTimeMsMax});
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
            return try allocator.dupe(u8, if (AuthHelpers.hasValidOauth(allocator)) "yes" else "no");
        } else if (std.mem.eql(u8, varName, "has_api_key")) {
            return try allocator.dupe(u8, if (AuthHelpers.hasValidApiKey(allocator)) "yes" else "no");
        } else {
            // Unknown variable, return as-is with braces
            return try std.fmt.allocPrint(allocator, "{{{s}}}", .{varName});
        }
    }
};

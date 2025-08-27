//! Template agent implementation demonstrating best practices for agent development.
//!
//! This file shows how to:
//! - Extend the standard AgentConfig with agent-specific settings
//! - Use ConfigHelpers for standardized configuration management
//! - Implement clean agent lifecycle methods (init, deinit, etc.)
//! - Process template variables in system prompts
//! - Follow Zig 0.15.1+ best practices with proper error handling
//! - Document code thoroughly for maintainability

const std = @import("std");
const Allocator = std.mem.Allocator;
const ConfigHelpers = @import("core_config_helpers");

/// ============================================================================
/// CONFIGURATION STRUCTURE
/// ============================================================================
/// Agent-specific configuration extending the standard AgentConfig.
/// This demonstrates how to add custom settings while maintaining compatibility
/// with the shared configuration system.
pub const Config = struct {
    // ============================================================================
    // STANDARD AGENT CONFIGURATION
    // ============================================================================
    // Always include the standard AgentConfig as the first field
    // This ensures compatibility with shared configuration utilities
    agent_config: @import("core_config").AgentConfig,

    // ============================================================================
    // AGENT-SPECIFIC CONFIGURATION FIELDS
    // ============================================================================
    // Add your custom configuration fields here
    // These will be loaded from config.zon and have defaults

    /// Whether to enable the custom demonstration feature
    customFeatureEnabled: bool = false,

    /// Maximum number of custom operations to perform
    maxCustomOperations: u32 = 50,

    /// Custom processing timeout in seconds
    customTimeoutSeconds: u32 = 30,

    /// Example of a string configuration with default
    customMessage: []const u8 = "Hello from template agent!",

    /// ============================================================================
    /// CONFIGURATION LOADING METHODS
    /// ============================================================================
    /// Load configuration from file with fallback to defaults.
    /// This method demonstrates the recommended pattern for configuration loading.
    ///
    /// Parameters:
    ///   allocator: Memory allocator for string duplication
    ///   path: Path to the configuration file (usually config.zon)
    ///
    /// Returns: Loaded configuration with defaults applied for missing fields
    pub fn loadFromFile(allocator: Allocator, path: []const u8) !Config {
        // Define default configuration values
        const defaults = Config{
            .agent_config = ConfigHelpers.createAgentConfig("_template", // agent_id
                "Template Agent", // display name
                "A template for creating new agents", // description
                "Developer" // author
            ),
            .customFeatureEnabled = false,
            .maxCustomOperations = 50,
            .customTimeoutSeconds = 30,
            .customMessage = "Hello from template agent!",
        };

        // Use ConfigHelpers to load with validation and defaults
        return ConfigHelpers.loadWithDefaults(Config, allocator, path, defaults);
    }

    /// Get the standard agent configuration file path.
    /// This follows the convention of storing config files alongside the agent.
    ///
    /// Parameters:
    ///   allocator: Memory allocator for path construction
    ///
    /// Returns: Allocated path string that caller must free
    pub fn getConfigPath(allocator: Allocator) ![]const u8 {
        return ConfigHelpers.getAgentConfigPath(allocator, "_template");
    }

    /// Validate configuration values and set derived fields.
    /// Call this after loading configuration to ensure consistency.
    ///
    /// Returns: Error if configuration is invalid
    pub fn validate(self: *Config) !void {
        // Validate standard agent config
        try ConfigHelpers.validateAgentConfig(&self.agent_config);

        // Validate agent-specific fields
        if (self.maxCustomOperations == 0) {
            return error.InvalidConfiguration;
        }
        if (self.customTimeoutSeconds == 0) {
            return error.InvalidConfiguration;
        }
        if (self.customMessage.len == 0) {
            return error.InvalidConfiguration;
        }

        // Set derived configuration values if needed
        // For example, you might set model parameters based on other config
        if (self.config.customFeatureEnabled) {
            // Adjust limits when custom feature is enabled
            self.agent_config.limits.max_processing_time_ms =
                @max(self.agent_config.limits.max_processing_time_ms, 60000);
        }
    }
};

/// ============================================================================
/// MAIN AGENT STRUCTURE
/// ============================================================================
/// Main agent implementation demonstrating clean lifecycle management.
/// This shows the recommended pattern for agent initialization and cleanup.
pub const Template = struct {
    // ============================================================================
    // AGENT STATE
    // ============================================================================

    /// Memory allocator used by this agent
    allocator: Allocator,

    /// Agent configuration loaded from config.zon
    config: Config,

    /// Example of agent-specific state that persists across operations
    operationCount: u32 = 0,

    /// Example of managed resources (would be freed in deinit)
    customBuffer: ?[]u8 = null,

    // ============================================================================
    // INITIALIZATION METHODS
    // ============================================================================

    /// Initialize agent with provided configuration.
    /// This is the most basic initialization method.
    ///
    /// Parameters:
    ///   allocator: Memory allocator for agent operations
    ///   config: Pre-loaded and validated configuration
    ///
    /// Returns: Initialized agent instance
    pub fn init(allocator: Allocator, config: Config) Template {
        return Template{
            .allocator = allocator,
            .config = config,
            .operationCount = 0,
            .customBuffer = null,
        };
    }

    /// Initialize agent by loading configuration from the standard path.
    /// This is the recommended initialization method for most use cases.
    ///
    /// Parameters:
    ///   allocator: Memory allocator for agent operations
    ///
    /// Returns: Initialized agent instance with loaded configuration
    /// Errors: Configuration loading or validation errors
    pub fn initFromConfig(allocator: Allocator) !Template {
        // Get the standard configuration path
        const configPath = try Config.getConfigPath(allocator);
        defer allocator.free(configPath);

        // Load configuration with defaults
        var config = try Config.loadFromFile(allocator, configPath);

        // Validate configuration
        try config.validate();

        // Initialize agent with loaded config
        return Template.init(allocator, config);
    }

    /// Initialize agent with custom configuration path.
    /// Useful for testing or when you need to load from a specific location.
    ///
    /// Parameters:
    ///   allocator: Memory allocator for agent operations
    ///   configPath: Custom path to configuration file
    ///
    /// Returns: Initialized agent instance with loaded configuration
    /// Errors: File access or configuration errors
    pub fn initFromConfigPath(allocator: Allocator, configPath: []const u8) !Template {
        var config = try Config.loadFromFile(allocator, configPath);
        try config.validate();
        return Template.init(allocator, config);
    }

    // ============================================================================
    // LIFECYCLE MANAGEMENT
    // ============================================================================

    /// Clean up agent resources.
    /// This method is called when the agent is no longer needed.
    /// Always call this to prevent resource leaks.
    pub fn deinit(self: *Template) void {
        // Clean up managed resources
        if (self.customBuffer) |buffer| {
            self.allocator.free(buffer);
            self.customBuffer = null;
        }

        // Reset state
        self.operationCount = 0;

        // Note: We don't free the config here as it may be owned by the caller
        // The config contains allocated strings that should be freed by the caller
    }

    // ============================================================================
    // SYSTEM PROMPT PROCESSING
    // ============================================================================

    /// Load and process the system prompt template.
    /// This demonstrates template variable substitution using configuration values.
    ///
    /// Returns: Processed system prompt with variables replaced
    /// Errors: File access errors or template processing errors
    pub fn loadSystemPrompt(self: *Template) ![]const u8 {
        // Path to the system prompt template file
        const prompt_path = "agents/_template/system_prompt.txt";

        // Attempt to open the system prompt file
        const file = std.fs.cwd().openFile(prompt_path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    // Return a default prompt if the template file doesn't exist
                    // This ensures the agent can still function even without the file
                    return try self.allocator.dupe(u8,
                        \\You are a helpful AI assistant.
                        \\Customize this prompt in your system_prompt.txt file.
                    );
                },
                else => {
                    // Re-return other file access errors
                    return err;
                },
            }
        };
        defer file.close();

        // Read the entire template file
        const template = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(template);

        // Process template variables and return the result
        return try self.processTemplateVariables(template);
    }

    /// Process template variables in the system prompt.
    /// This method replaces {variable_name} placeholders with actual values.
    ///
    /// Parameters:
    ///   template: Raw template string with {variable} placeholders
    ///
    /// Returns: Processed string with variables replaced
    /// Errors: Memory allocation errors or unknown variable names
    fn processTemplateVariables(self: *Template, template: []const u8) ![]const u8 {
        // Allocate result buffer with some extra capacity for replacements
        var result = try std.ArrayList(u8).initCapacity(self.allocator, template.len + 1024);
        defer result.deinit();

        var i: usize = 0;
        while (i < template.len) {
            // Look for the next variable placeholder
            if (std.mem.indexOf(u8, template[i..], "{")) |start| {
                // Copy everything before the variable
                try result.appendSlice(template[i .. i + start]);
                i += start;

                // Find the closing brace
                if (std.mem.indexOf(u8, template[i..], "}")) |end| {
                    // Extract variable name
                    const var_name = template[i + 1 .. i + end];

                    // Get the replacement value
                    const replacement = try self.getTemplateVariableValue(var_name);
                    defer self.allocator.free(replacement);

                    // Append the replacement
                    try result.appendSlice(replacement);
                    i += end + 1;
                } else {
                    // No closing brace found, copy the { as-is
                    try result.append(template[i]);
                    i += 1;
                }
            } else {
                // No more variables, copy the rest
                try result.appendSlice(template[i..]);
                break;
            }
        }

        // Return the processed template as an owned string
        return try result.toOwnedSlice();
    }

    /// Get the value for a template variable.
    /// This method maps variable names to their string representations.
    /// Add your custom variables here when extending the template.
    ///
    /// Parameters:
    ///   varName: Name of the variable (without braces)
    ///
    /// Returns: String value for the variable
    /// Errors: Memory allocation errors
    fn getTemplateVariableValue(self: *Template, varName: []const u8) ![]const u8 {
        const cfg = &self.config.agent_config;

        // ============================================================================
        // STANDARD AGENT CONFIGURATION VARIABLES
        // ============================================================================
        // These variables are available for all agents using the standard config

        if (std.mem.eql(u8, varName, "agent_name")) {
            return try self.allocator.dupe(u8, cfg.agent_info.name);
        } else if (std.mem.eql(u8, varName, "agent_version")) {
            return try self.allocator.dupe(u8, cfg.agent_info.version);
        } else if (std.mem.eql(u8, varName, "agent_description")) {
            return try self.allocator.dupe(u8, cfg.agent_info.description);
        } else if (std.mem.eql(u8, varName, "agent_author")) {
            return try self.allocator.dupe(u8, cfg.agent_info.author);
        } else if (std.mem.eql(u8, varName, "debug_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.defaults.enable_debug_logging) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "verbose_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.defaults.enable_verbose_output) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "custom_tools_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.features.enable_custom_tools) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "file_operations_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.features.enable_file_operations) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "network_access_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.features.enable_network_access) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "system_commands_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.features.enable_system_commands) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "max_input_size")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{cfg.limits.max_input_size});
        } else if (std.mem.eql(u8, varName, "max_output_size")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{cfg.limits.max_output_size});
        } else if (std.mem.eql(u8, varName, "max_processing_time")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{cfg.limits.max_processing_time_ms});
        } else if (std.mem.eql(u8, varName, "current_date")) {
            // Get current date in YYYY-MM-DD format
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

        // ============================================================================
        // AGENT-SPECIFIC TEMPLATE VARIABLES
        // ============================================================================
        // Add your custom template variables here

        else if (std.mem.eql(u8, varName, "custom_feature_enabled")) {
            return try self.allocator.dupe(u8, if (self.config.customFeatureEnabled) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "max_custom_operations")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{self.config.maxCustomOperations});
        } else if (std.mem.eql(u8, varName, "custom_timeout_seconds")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{self.config.customTimeoutSeconds});
        } else if (std.mem.eql(u8, varName, "custom_message")) {
            return try self.allocator.dupe(u8, self.config.customMessage);
        } else if (std.mem.eql(u8, varName, "operation_count")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{self.operationCount});
        }

        // ============================================================================
        // UNKNOWN VARIABLE HANDLING
        // ============================================================================
        // For unknown variables, return them as-is with braces to preserve formatting
        else {
            return try std.fmt.allocPrint(self.allocator, "{{{s}}}", .{varName});
        }
    }

    // ============================================================================
    // AGENT-SPECIFIC METHODS
    // ============================================================================

    /// Example method demonstrating agent-specific functionality.
    /// This shows how to implement custom agent behavior.
    ///
    /// Parameters:
    ///   input: Input string to process
    ///
    /// Returns: Processed result
    /// Errors: Processing errors
    pub fn processCustomOperation(self: *Template, input: []const u8) ![]const u8 {
        // Check if custom feature is enabled
        if (!self.config.customFeatureEnabled) {
            return try self.allocator.dupe(u8, "Custom feature is disabled in configuration");
        }

        // Check operation limits
        if (self.operationCount >= self.config.maxCustomOperations) {
            return try self.allocator.dupe(u8, "Maximum custom operations reached");
        }

        // Increment operation count
        self.operationCount += 1;

        // Perform custom processing
        const result = try std.fmt.allocPrint(self.allocator, "Processed '{s}' using custom feature (operation #{d})", .{ input, self.operationCount });

        return result;
    }

    /// Get agent status information.
    /// This demonstrates how to provide runtime status information.
    ///
    /// Returns: Status information as a formatted string
    pub fn getStatus(self: *Template) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator,
            \\Agent Status:
            \\  Name: {s}
            \\  Version: {s}
            \\  Custom Feature: {s}
            \\  Operations Performed: {d}/{d}
            \\  Custom Timeout: {d}s
            \\  Memory Buffer: {s}
            \\
            \\Configuration:
            \\  Debug Logging: {s}
            \\  Verbose Output: {s}
            \\  File Operations: {s}
            \\  Network Access: {s}
            \\  System Commands: {s}
        , .{
            self.config.agent_config.agent_info.name,
            self.config.agent_config.agent_info.version,
            if (self.config.customFeatureEnabled) "enabled" else "disabled",
            self.operationCount,
            self.config.maxCustomOperations,
            self.config.customTimeoutSeconds,
            if (self.customBuffer != null) "allocated" else "none",
            if (self.config.agent_config.defaults.enable_debug_logging) "enabled" else "disabled",
            if (self.config.agent_config.defaults.enable_verbose_output) "enabled" else "disabled",
            if (self.config.agent_config.features.enable_file_operations) "enabled" else "disabled",
            if (self.config.agent_config.features.enable_network_access) "enabled" else "disabled",
            if (self.config.agent_config.features.enable_system_commands) "enabled" else "disabled",
        });
    }
};

//! Shared configuration utilities for all agents.
//! Provides standardized configuration loading with defaults fallback.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Load configuration from ZON file with defaults fallback.
/// If the file doesn't exist or fails to parse, returns the provided defaults.
pub fn loadWithDefaults(
    comptime T: type,
    allocator: Allocator,
    path: []const u8,
    defaults: T,
) !T {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.log.info("Config file not found: {s}, using defaults", .{path});
                return defaults;
            },
            else => {
                std.log.warn("Failed to open config file {s}: {any}, using defaults", .{ path, err });
                return defaults;
            },
        }
    };
    defer file.close();

    // Read file content with null terminator
    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        std.log.warn("Failed to read config file {s}: {any}, using defaults", .{ path, err });
        return defaults;
    };
    defer allocator.free(content);

    // Add null terminator for ZON parsing
    const contentNull = try allocator.allocSentinel(u8, content.len, 0);
    defer allocator.free(contentNull);
    @memcpy(contentNull[0..content.len], content);

    // Parse ZON content
    var diagnostics = std.zon.parse.Diagnostics{};
    const parsed = std.zon.parse.fromSlice(T, allocator, contentNull, &diagnostics, .{}) catch |err| {
        std.log.warn("Failed to parse config file {s}: {any}, using defaults", .{ path, err });
        return defaults;
    };

    std.log.info("Loaded configuration from: {s}", .{path});
    return parsed;
}

/// Validate that a configuration file exists and is readable
pub fn validateConfigFile(path: []const u8) !void {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => return error.ConfigFileNotFound,
            error.PermissionDenied => return error.ConfigFilePermissionDenied,
            else => return err,
        }
    };
    defer file.close();
}

/// Validate agent configuration and provide helpful error messages
pub fn validate_agent_config(config: AgentConfig) !void {
    // Validate agent info
    if (config.agent_info.name.len == 0) {
        return error.InvalidConfigFormat;
    }
    if (config.agent_info.version.len == 0) {
        return error.InvalidConfigFormat;
    }

    // Validate model configuration
    if (config.model.default_model.len == 0) {
        return error.InvalidConfigFormat;
    }
    if (config.model.max_tokens == 0) {
        return error.InvalidConfigFormat;
    }
    if (config.model.temperature < 0.0 or config.model.temperature > 2.0) {
        return error.InvalidConfigFormat;
    }

    // Validate resource limits
    if (config.limits.max_input_size == 0) {
        return error.InvalidConfigFormat;
    }
    if (config.limits.max_output_size == 0) {
        return error.InvalidConfigFormat;
    }
    if (config.limits.max_processing_time_ms == 0) {
        return error.InvalidConfigFormat;
    }

    // Validate defaults
    if (config.defaults.max_concurrent_operations == 0) {
        return error.InvalidConfigFormat;
    }
    if (config.defaults.default_timeout_ms == 0) {
        return error.InvalidConfigFormat;
    }
}

/// Create a default agent configuration with validation
pub fn create_validated_agent_config(name: []const u8, description: []const u8, author: []const u8) AgentConfig {
    const config = AgentConfig{
        .agent_info = .{
            .name = name,
            .description = description,
            .author = author,
        },
    };

    // Validate the created config
    validate_agent_config(config) catch |err| {
        std.log.err("Invalid default configuration: {any}", .{err});
        std.log.err("Default configuration validation failed", .{});
    };

    return config;
}

/// Configuration error types
pub const ConfigError = error{
    ConfigFileNotFound,
    ConfigFilePermissionDenied,
    ConfigParsingFailed,
    InvalidConfigFormat,
    InvalidAgentName,
    InvalidModelConfig,
    InvalidResourceLimits,
    InvalidDefaults,
};

/// Get the standard config path for an agent
pub fn get_agent_config_path(allocator: Allocator, agent_name: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "agents/{s}/config.zon", .{agent_name});
}

/// Standard agent configuration structure that all agents should implement
/// Agents can extend this with their own specific configuration fields
pub const AgentConfig = struct {
    /// Basic agent information
    agent_info: struct {
        name: []const u8,
        version: []const u8 = "1.0.0",
        description: []const u8 = "",
        author: []const u8 = "",
    } = .{
        .name = "Unknown Agent",
    },

    /// Default settings that apply to most agents
    defaults: struct {
        max_concurrent_operations: u32 = 10,
        default_timeout_ms: u32 = 30000,
        enable_debug_logging: bool = false,
        enable_verbose_output: bool = false,
    } = .{},

    /// Feature flags for enabling/disabling agent capabilities
    features: struct {
        enable_custom_tools: bool = true,
        enable_file_operations: bool = true,
        enable_network_access: bool = false,
        enable_system_commands: bool = false,
    } = .{},

    /// Resource limits
    limits: struct {
        max_input_size: u64 = 1048576, // 1MB
        max_output_size: u64 = 1048576, // 1MB
        max_processing_time_ms: u32 = 60000, // 1 minute
    } = .{},

    /// Model configuration
    model: struct {
        default_model: []const u8 = "claude-3-sonnet-20240229",
        max_tokens: u32 = 4096,
        temperature: f32 = 0.7,
        stream_responses: bool = true,
    } = .{},
};

/// Load agent configuration with standardized defaults
pub fn load_agent_config(allocator: Allocator, agent_name: []const u8, comptime ExtendedConfig: type) ExtendedConfig {
    const config_path = get_agent_config_path(allocator, agent_name) catch {
        std.log.info("Using default configuration for agent: {s}", .{agent_name});
        // Create a default instance using reflection
        return std.mem.zeroes(ExtendedConfig);
    };
    defer allocator.free(config_path);

    // Create default config based on the extended type
    const defaults = if (@hasDecl(ExtendedConfig, "default")) ExtendedConfig.default() else std.mem.zeroes(ExtendedConfig);

    return loadWithDefaults(ExtendedConfig, allocator, config_path, defaults);
}

/// Generate a standardized configuration file template for a new agent
pub fn generate_config_template(allocator: Allocator, agent_name: []const u8, description: []const u8, author: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator,
        \\.{{
        \\    .agent_config = .{{
        \\        .agent_info = .{{
        \\            .name = "{s}",
        \\            .version = "1.0.0",
        \\            .description = "{s}",
        \\            .author = "{s}",
        \\        }},
        \\
        \\        .defaults = .{{
        \\            .max_concurrent_operations = 10,
        \\            .default_timeout_ms = 30000,
        \\            .enable_debug_logging = false,
        \\            .enable_verbose_output = false,
        \\        }},
        \\
        \\        .features = .{{
        \\            .enable_custom_tools = true,
        \\            .enable_file_operations = true,
        \\            .enable_network_access = false,
        \\            .enable_system_commands = false,
        \\        }},
        \\
        \\        .limits = .{{
        \\            .max_input_size = 1048576, // 1MB
        \\            .max_output_size = 1048576, // 1MB
        \\            .max_processing_time_ms = 60000,
        \\        }},
        \\
        \\        .model = .{{
        \\            .default_model = "claude-3-sonnet-20240229",
        \\            .max_tokens = 4096,
        \\            .temperature = 0.7,
        \\            .stream_responses = true,
        \\        }},
        \\    }},
        \\
        \\    // Agent-specific configuration fields go here
        \\    // Add your custom configuration options below this line
        \\}}
    , .{ agent_name, description, author });
}

/// Validate and save agent configuration
pub fn save_agent_config(allocator: Allocator, agent_name: []const u8, config: anytype) !void {
    const config_path = try get_agent_config_path(allocator, agent_name);
    defer allocator.free(config_path);

    // Validate configuration before saving
    if (@hasDecl(@TypeOf(config), "agent_config")) {
        try validate_agent_config(config.agent_config);
    }

    // Create directory if it doesn't exist
    const config_dir = std.fs.path.dirname(config_path) orelse "";
    try std.fs.cwd().makePath(config_dir);

    // Write configuration to file
    const file = try std.fs.cwd().createFile(config_path, .{});
    defer file.close();

    const writer = file.writer();
    // Use std.zon.stringify to generate proper ZON format
    try std.zon.stringify.serialize(config, .{ .whitespace = true }, writer);
}

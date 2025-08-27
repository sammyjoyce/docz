//! Base agent functionality that all agents can inherit from.
//! Provides common lifecycle methods, template variable processing,
//! and standardized configuration patterns.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Base agent structure with common functionality.
/// Agents can embed this struct or use composition to inherit base functionality.
pub const BaseAgent = struct {
    allocator: Allocator,

    const Self = @This();

    /// Initialize base agent with allocator
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Clean up base agent resources
    pub fn deinit(self: *Self) void {
        _ = self;
        // Base agent has no resources to clean up
        // Agents should override this if they have additional cleanup
    }

    /// Get current date in YYYY-MM-DD format
    pub fn getCurrentDate(self: *Self) ![]const u8 {
        const now = std.time.timestamp();
        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
        const epoch_day = epoch_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return try std.fmt.allocPrint(self.allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
            year_day.year,
            @intFromEnum(month_day.month),
            month_day.day_index + 1,
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
                    const var_name = template[i + 1 .. i + end];
                    const replacement = try self.getTemplateVariableValue(var_name);
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
    pub fn getTemplateVariableValue(self: *Self, var_name: []const u8) ![]const u8 {
        // This is a base implementation that doesn't have access to config
        // Agents should override this method to provide their specific config values

        if (std.mem.eql(u8, var_name, "current_date")) {
            return self.getCurrentDate();
        } else {
            // Unknown variable, return as-is with braces
            return try std.fmt.allocPrint(self.allocator, "{{{s}}}", .{var_name});
        }
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
        const config_utils = @import("config.zig");
        const config_path = config_utils.getAgentConfigPath(allocator, agent_name) catch {
            std.log.info("Using default configuration for agent: {s}", .{agent_name});
            return defaults;
        };
        defer allocator.free(config_path);

        return config_utils.loadWithDefaults(ConfigType, allocator, config_path, defaults);
    }

    /// Get standard agent config path
    pub fn getConfigPath(allocator: Allocator, agent_name: []const u8) ![]const u8 {
        const config_utils = @import("config.zig");
        return config_utils.getAgentConfigPath(allocator, agent_name);
    }

    /// Create validated agent config with standard defaults
    pub fn createAgentConfig(name: []const u8, description: []const u8, author: []const u8) @import("config.zig").AgentConfig {
        const config_utils = @import("config.zig");
        return config_utils.createValidatedAgentConfig(name, description, author);
    }
};

/// Template variable processing for agents with AgentConfig
/// This provides the standard template variables that work with the AgentConfig structure
pub const TemplateProcessor = struct {
    /// Process template variables using an AgentConfig
    pub fn getTemplateVariableValue(
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
            const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
            const epoch_day = epoch_seconds.getEpochDay();
            const year_day = epoch_day.calculateYearDay();
            const month_day = year_day.calculateMonthDay();

            return try std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
                year_day.year,
                @intFromEnum(month_day.month),
                month_day.day_index + 1,
            });
        } else {
            // Unknown variable, return as-is with braces
            return try std.fmt.allocPrint(allocator, "{{{s}}}", .{var_name});
        }
    }
};

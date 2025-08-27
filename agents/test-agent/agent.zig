const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

// Test Agent Module
// Provides a simple example agent demonstrating standardized agent patterns

pub const TestAgent = struct {
    allocator: Allocator,
    config: Config,

    const Self = @This();

    /// Agent configuration structure - extends the standard AgentConfig
    pub const Config = struct {
        // Include standard agent configuration
        agent_config: @import("config_shared").AgentConfig,

        // Add agent-specific configuration fields here
        max_operations: u32 = 100,
        enable_feature: bool = true,

        /// Load configuration from file with defaults fallback
        pub fn loadFromFile(allocator: Allocator, path: []const u8) !Config {
            const config_utils = @import("config_shared");
            const defaults = Config{
                .agent_config = config_utils.createValidatedAgentConfig("test-agent", "Example agent demonstrating best practices", "Developer"),
                .max_operations = 100,
                .enable_feature = true,
            };
            return config_utils.loadWithDefaults(Config, allocator, path, defaults);
        }

        /// Get the standard agent config path for this agent
        pub fn getConfigPath(allocator: Allocator) ![]const u8 {
            const config_utils = @import("config_shared");
            return config_utils.getAgentConfigPath(allocator, "test-agent");
        }
    };

    /// Error set for test agent operations
    pub const AgentError = error{
        InvalidInput,
        MissingParameter,
        OutOfMemory,
        FileNotFound,
        PermissionDenied,
        ProcessingFailed,
        UnexpectedError,
    };

    pub fn init(allocator: Allocator, config: Config) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Initialize agent with configuration loaded from file
    pub fn initFromConfig(allocator: Allocator) !Self {
        const config_path = try Config.getConfigPath(allocator);
        defer allocator.free(config_path);

        const config = try Config.loadFromFile(allocator, config_path);
        return Self.init(allocator, config);
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // Cleanup resources if needed
    }

    /// Load system prompt from file or generate dynamically
    pub fn loadSystemPrompt(self: *Self) ![]const u8 {
        const prompt_path = "agents/test-agent/system_prompt.txt";
        const file = std.fs.cwd().openFile(prompt_path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    // Return a default prompt if file doesn't exist
                    return try self.allocator.dupe(u8, "You are a helpful AI assistant with access to example tools.");
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
    fn processTemplateVariables(self: *Self, template: []const u8) ![]const u8 {
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

    /// Override base agent method to provide config-aware template variable processing
    pub fn getTemplateVariableValue(self: *Self, var_name: []const u8) ![]const u8 {
        const cfg = &self.config.agent_config;

        if (std.mem.eql(u8, var_name, "agent_name")) {
            return try self.allocator.dupe(u8, cfg.agent_info.name);
        } else if (std.mem.eql(u8, var_name, "agent_version")) {
            return try self.allocator.dupe(u8, cfg.agent_info.version);
        } else if (std.mem.eql(u8, var_name, "agent_description")) {
            return try self.allocator.dupe(u8, cfg.agent_info.description);
        } else if (std.mem.eql(u8, var_name, "agent_author")) {
            return try self.allocator.dupe(u8, cfg.agent_info.author);
        } else if (std.mem.eql(u8, var_name, "debug_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.defaults.enable_debug_logging) "enabled" else "disabled");
        } else if (std.mem.eql(u8, var_name, "verbose_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.defaults.enable_verbose_output) "enabled" else "disabled");
        } else if (std.mem.eql(u8, var_name, "custom_tools_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.features.enable_custom_tools) "enabled" else "disabled");
        } else if (std.mem.eql(u8, var_name, "file_operations_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.features.enable_file_operations) "enabled" else "disabled");
        } else if (std.mem.eql(u8, var_name, "network_access_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.features.enable_network_access) "enabled" else "disabled");
        } else if (std.mem.eql(u8, var_name, "system_commands_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.features.enable_system_commands) "enabled" else "disabled");
        } else if (std.mem.eql(u8, var_name, "max_input_size")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{cfg.limits.max_input_size});
        } else if (std.mem.eql(u8, var_name, "max_output_size")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{cfg.limits.max_output_size});
        } else if (std.mem.eql(u8, var_name, "max_processing_time")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{cfg.limits.max_processing_time_ms});
        } else if (std.mem.eql(u8, var_name, "current_date")) {
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
        } else if (std.mem.eql(u8, var_name, "max_operations")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{self.config.max_operations});
        } else if (std.mem.eql(u8, var_name, "feature_enabled")) {
            return try self.allocator.dupe(u8, if (self.config.enable_feature) "enabled" else "disabled");
        } else {
            // Unknown variable, return as-is with braces
            return try std.fmt.allocPrint(self.allocator, "{{{s}}}", .{var_name});
        }
    }

    /// Get the list of available tools for this agent
    /// Note: Tools are now registered through the spec.zig file using the shared registry
    pub fn getAvailableTools(self: *Self) ![]const []const u8 {
        _ = self;
        // Tool names are now registered in spec.zig
        return &.{
            "example_tool",
        };
    }
};

// Note: Tool execution functions are now handled through the shared tools registry
// and registered in spec.zig. The actual implementations remain in the tools/ directory
// but are called through the standardized interface.

// Export the public interface
pub const test_agent = TestAgent;

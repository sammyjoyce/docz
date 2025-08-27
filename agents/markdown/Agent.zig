const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

// Markdown Agent Module
// Provides specialized functionality for markdown document creation and editing

pub const Markdown = struct {
    allocator: Allocator,
    config: Config,

    const Self = @This();

    /// Agent configuration structure - extends the standard AgentConfig
    pub const Config = struct {
        // Include standard agent configuration
        agentConfig: @import("config_shared").AgentConfig,

        // Add agent-specific configuration fields here
        textWrapWidth: u32 = 80,
        headingStyle: []const u8 = "atx",
        listStyle: []const u8 = "dash",
        codeFenceStyle: []const u8 = "backtick",
        tableAlignment: []const u8 = "auto",
        frontMatterFormat: []const u8 = "yaml",
        tocStyle: []const u8 = "github",
        linkStyle: []const u8 = "reference",

        /// Load configuration from file with defaults fallback
        pub fn loadFromFile(allocator: Allocator, path: []const u8) !Config {
            const config_utils = @import("config_shared");
            const defaults = Config{
                .agentConfig = config_utils.createValidatedAgentConfig("markdown", "Markdown document processing agent", "Developer"),
                .textWrapWidth = 80,
                .headingStyle = "atx",
                .listStyle = "dash",
                .codeFenceStyle = "backtick",
                .tableAlignment = "auto",
                .frontMatterFormat = "yaml",
                .tocStyle = "github",
                .linkStyle = "reference",
            };
            return config_utils.loadWithDefaults(Config, allocator, path, defaults);
        }

        /// Get the standard agent config path for this agent
        pub fn getConfigPath(allocator: Allocator) ![]const u8 {
            const config_utils = @import("config_shared");
            return config_utils.getAgentConfigPath(allocator, "markdown");
        }
    };

    pub const Document = struct {
        name: []const u8,
        frontMatter: json.Value,
        sections: [][]const u8,
    };

    /// Error set for markdown agent operations
    pub const Error = error{
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
        const configPath = try Config.getConfigPath(allocator);
        defer allocator.free(configPath);

        const config = try Config.loadFromFile(allocator, configPath);
        return Self.init(allocator, config);
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // Cleanup resources if needed
    }

    /// Load system prompt from file or generate dynamically
    pub fn loadSystemPrompt(self: *Self) ![]const u8 {
        const promptPath = "agents/markdown/system_prompt.txt";
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
    fn processTemplateVariables(self: *Self, template: []const u8) ![]const u8 {
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

    /// Override base agent method to provide config-aware template variable processing
    pub fn getTemplateVariableValue(self: *Self, varName: []const u8) ![]const u8 {
        const cfg = &self.config.agentConfig;

        if (std.mem.eql(u8, varName, "agent_name")) {
            return try self.allocator.dupe(u8, cfg.agentInfo.name);
        } else if (std.mem.eql(u8, varName, "agent_version")) {
            return try self.allocator.dupe(u8, cfg.agentInfo.version);
        } else if (std.mem.eql(u8, varName, "agent_description")) {
            return try self.allocator.dupe(u8, cfg.agentInfo.description);
        } else if (std.mem.eql(u8, varName, "agent_author")) {
            return try self.allocator.dupe(u8, cfg.agentInfo.author);
        } else if (std.mem.eql(u8, varName, "debug_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.defaults.enableDebugLogging) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "verbose_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.defaults.enableVerboseOutput) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "custom_tools_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.features.enableCustomTools) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "file_operations_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.features.enableFileOperations) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "network_access_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.features.enableNetworkAccess) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "system_commands_enabled")) {
            return try self.allocator.dupe(u8, if (cfg.features.enableSystemCommands) "enabled" else "disabled");
        } else if (std.mem.eql(u8, varName, "max_input_size")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{cfg.limits.maxInputSize});
        } else if (std.mem.eql(u8, varName, "max_output_size")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{cfg.limits.maxOutputSize});
        } else if (std.mem.eql(u8, varName, "max_processing_time")) {
            return try std.fmt.allocPrint(self.allocator, "{d}", .{cfg.limits.maxProcessingTimeMs});
        } else if (std.mem.eql(u8, varName, "current_date")) {
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
        } else {
            // Unknown variable, return as-is with braces
            return try std.fmt.allocPrint(self.allocator, "{{{s}}}", .{varName});
        }
    }

    /// Get the list of available tools for this agent
    /// Note: Tools are now registered through the spec.zig file using the shared registry
    pub fn getAvailableTools(self: *Self) ![]const []const u8 {
        _ = self;
        // Tool names are now registered in spec.zig
        return &.{
            "io",
            "content_editor",
            "validate",
            "document",
            "workflow",
            "file",
        };
    }
};

// Note: Tool execution functions are now handled through the shared tools registry
// and registered in spec.zig. The actual implementations remain in the tools/ directory
// but are called through the standardized interface.

// Markdown is already exported as pub const above

//! Markdown agent implementation: config + system prompt loading.
//! Single-entry struct; no loop/CLI logic here.

const std = @import("std");
const foundation = @import("foundation");
const Allocator = std.mem.Allocator;

pub const Error = foundation.config.ConfigError || error{
    OutOfMemory,
    FileNotFound,
    Unexpected,
};

// Agent-specific configuration extending foundation.config.AgentConfig
pub const Config = struct {
    agentConfig: foundation.config.AgentConfig,

    // Markdown-specific settings (match keys in config.zon)
    textWrapWidth: u32 = 80,
    headingStyle: []const u8 = "atx",
    listStyle: []const u8 = "dash",
    codeFenceStyle: []const u8 = "backtick",
    tableAlignment: []const u8 = "auto",
    frontMatterFormat: []const u8 = "yaml",
    tocStyle: []const u8 = "github",
    linkStyle: []const u8 = "reference",

    pub fn getConfigPath(allocator: Allocator) Error![]const u8 {
        return foundation.config.getAgentConfigPath(allocator, "markdown");
    }

    pub fn loadFromFile(allocator: Allocator, path: []const u8) Error!Config {
        const defaults = Config{
            .agentConfig = foundation.config.createValidatedAgentConfig(
                "markdown",
                "Enterprise-grade markdown systems architect & quality guardian",
                "AI Assistant",
            ),
        };
        return foundation.config.loadWithDefaults(Config, allocator, path, defaults);
    }

    pub fn validate(self: *Config) Error!void {
        try foundation.config.validateAgentConfig(self.agentConfig);
        if (self.textWrapWidth == 0) return error.InvalidConfigFormat;
    }
};

// Main agent type (single-entry struct)
pub const Markdown = struct {
    const Self = @This();

    allocator: Allocator,
    config: Config,

    pub fn init(allocator: Allocator, config: Config) Self {
        return .{ .allocator = allocator, .config = config };
    }

    pub fn initFromConfig(allocator: Allocator) Error!Self {
        const path = try Config.getConfigPath(allocator);
        defer allocator.free(path);
        var cfg = try Config.loadFromFile(allocator, path);
        try cfg.validate();
        return Self.init(allocator, cfg);
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn loadSystemPrompt(self: *Self) Error![]const u8 {
        const prompt_path = "agents/markdown/system_prompt.txt";
        const file = std.fs.cwd().openFile(prompt_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return self.allocator.dupe(u8, "You are the Markdown agent. Maintain high quality."),
            else => return error.Unexpected,
        };
        defer file.close();

        const raw = file.readToEndAlloc(self.allocator, std.math.maxInt(usize)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.Unexpected,
        };
        defer self.allocator.free(raw);
        return self.processTemplateVariables(raw);
    }

    fn processTemplateVariables(self: *Self, template: []const u8) ![]const u8 {
        var out = try std.ArrayList(u8).initCapacity(self.allocator, template.len + 256);
        defer out.deinit(self.allocator);
        var i: usize = 0;
        while (i < template.len) {
            if (std.mem.indexOf(u8, template[i..], "{")) |start| {
                try out.appendSlice(self.allocator, template[i .. i + start]);
                i += start;
                if (std.mem.indexOf(u8, template[i..], "}")) |end| {
                    const name = template[i + 1 .. i + end];
                    const value = try self.templateVar(name);
                    defer self.allocator.free(value);
                    try out.appendSlice(self.allocator, value);
                    i += end + 1;
                } else {
                    try out.append(self.allocator, template[i]);
                    i += 1;
                }
            } else {
                try out.appendSlice(self.allocator, template[i..]);
                break;
            }
        }
        return out.toOwnedSlice(self.allocator);
    }

    fn templateVar(self: *Self, name: []const u8) ![]const u8 {
        const cfg = &self.config.agentConfig;
        if (std.mem.eql(u8, name, "agent_name")) return self.allocator.dupe(u8, cfg.agentInfo.name);
        if (std.mem.eql(u8, name, "agent_version")) return self.allocator.dupe(u8, cfg.agentInfo.version);
        if (std.mem.eql(u8, name, "agent_description")) return self.allocator.dupe(u8, cfg.agentInfo.description);
        if (std.mem.eql(u8, name, "debug_enabled")) return self.allocator.dupe(u8, if (cfg.defaults.enableDebugLogging) "enabled" else "disabled");
        if (std.mem.eql(u8, name, "file_ops")) return self.allocator.dupe(u8, if (cfg.features.enableFileOperations) "enabled" else "disabled");
        if (std.mem.eql(u8, name, "wrap_width")) return std.fmt.allocPrint(self.allocator, "{d}", .{self.config.textWrapWidth});
        return std.fmt.allocPrint(self.allocator, "{{{s}}}", .{name});
    }
};

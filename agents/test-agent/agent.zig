//! Template agent implementation. Customize for your specific agent needs.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Agent configuration structure - customize as needed
pub const Config = struct {
    // Example configuration options
    max_operations: u32 = 100,
    enable_feature: bool = true,

    /// Load configuration from file with defaults fallback
    pub fn loadFromFile(allocator: Allocator, path: []const u8) Config {
        const config_utils = @import("config_shared");
        return config_utils.loadWithDefaults(Config, allocator, path, Config{});
    }
};

/// Main agent structure
pub const Agent = struct {
    allocator: Allocator,
    config: Config,

    const Self = @This();

    pub fn init(allocator: Allocator, config: Config) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // Cleanup resources if needed
    }

    /// Load system prompt from file or generate dynamically
    pub fn loadSystemPrompt(self: *Self) ![]const u8 {
        const prompt_path = "agents/_template/system_prompt.txt";
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

        const content = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));

        // Process template variables if needed
        return content;
    }
};

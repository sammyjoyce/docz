//! Template agent implementation. 
//! Copy this to agents/<name>/agent.zig and customize for your agent.

const std = @import("std");

/// Agent configuration structure.
/// Define your agent's configuration schema here.
pub const Config = struct {
    // Example configuration options
    max_concurrent_operations: u32 = 10,
    default_timeout_ms: u32 = 30000,
    enable_debug_logging: bool = false,

    /// Load configuration from a .zon file
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Config {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.info("Config file not found: {s}, using defaults", .{path});
                return Config{};
            },
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(content);

        // TODO: Implement .zon parsing when available
        // For now, return defaults
        return Config{};
    }
};

/// Main agent structure
pub const Agent = struct {
    allocator: std.mem.Allocator,
    config: Config,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: Config) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        // Cleanup any resources your agent allocates
        _ = self;
    }

    /// Load the system prompt for this agent.
    /// This is called by the engine if no explicit system prompt is provided.
    pub fn loadSystemPrompt(self: *Self) ![]const u8 {
        const prompt_path = "agents/_template/system_prompt.txt";
        const file = std.fs.cwd().openFile(prompt_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                // Return a default prompt if no file exists
                return try self.allocator.dupe(u8, 
                    \\You are a helpful AI assistant.
                    \\Respond to the user's requests clearly and accurately.
                );
            },
            else => return err,
        };
        defer file.close();

        const base_prompt = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(base_prompt);

        // Process template variables if needed
        const current_date = try getCurrentDate(self.allocator);
        defer self.allocator.free(current_date);

        const processed_prompt = try std.mem.replaceOwned(u8, self.allocator, base_prompt, "{current_date}", current_date);
        defer self.allocator.free(processed_prompt);

        // Read and prepend spoof content if it exists
        const spoof_content = blk: {
            const spoof_file = std.fs.cwd().openFile("prompt/anthropic_spoof.txt", .{}) catch {
                break :blk "";
            };
            defer spoof_file.close();
            break :blk spoof_file.readToEndAlloc(self.allocator, 1024) catch "";
        };
        defer if (spoof_content.len > 0) self.allocator.free(spoof_content);

        return if (spoof_content.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}\n\n{s}", .{ spoof_content, processed_prompt })
        else
            try self.allocator.dupe(u8, processed_prompt);
    }

    /// Get the current date in YYYY-MM-DD format
    fn getCurrentDate(allocator: std.mem.Allocator) ![]const u8 {
        const timestamp = std.time.timestamp();
        const epoch_seconds: i64 = @intCast(timestamp);
        const days_since_epoch: u47 = @intCast(@divFloor(epoch_seconds, std.time.s_per_day));
        const epoch_day = std.time.epoch.EpochDay{ .day = days_since_epoch };
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return try std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2}", .{
            year_day.year, @intFromEnum(month_day.month), month_day.day_index
        });
    }
};
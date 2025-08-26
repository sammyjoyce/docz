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
) T {
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

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        std.log.warn("Failed to read config file {s}: {any}, using defaults", .{ path, err });
        return defaults;
    };
    defer allocator.free(content);

    // Parse ZON content
    const parsed = std.zig.parseFromSlice(T, allocator, content, .{}) catch |err| {
        std.log.warn("Failed to parse config file {s}: {any}, using defaults", .{ path, err });
        return defaults;
    };
    defer parsed.deinit();

    std.log.info("Loaded configuration from: {s}", .{path});
    return parsed.value;
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

/// Configuration error types
pub const ConfigError = error{
    ConfigFileNotFound,
    ConfigFilePermissionDenied,
    ConfigParsingFailed,
    InvalidConfigFormat,
};

/// Get the standard config path for an agent
pub fn getAgentConfigPath(allocator: Allocator, agent_name: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "agents/{s}/config.zon", .{agent_name});
}

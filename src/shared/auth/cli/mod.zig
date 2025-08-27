//! CLI commands for authentication
//!
//! This module provides command-line interface handlers for authentication commands
//! that integrate with the CLI framework.

const std = @import("std");
const core = @import("../core/mod.zig");
const oauth = @import("../oauth/mod.zig");

/// Authentication command types
pub const AuthCommand = enum {
    login,
    status,
    refresh,

    pub fn fromString(str: []const u8) ?AuthCommand {
        if (std.mem.eql(u8, str, "login")) return .login;
        if (std.mem.eql(u8, str, "status")) return .status;
        if (std.mem.eql(u8, str, "refresh")) return .refresh;
        return null;
    }
};

/// Run authentication command
pub fn runAuthCommand(allocator: std.mem.Allocator, command: AuthCommand) !void {
    switch (command) {
        .login => try handleLoginCommand(allocator),
        .status => try handleStatusCommand(allocator),
        .refresh => try handleRefreshCommand(allocator),
    }
}

/// Handle login command (OAuth setup)
pub fn handleLoginCommand(allocator: std.mem.Allocator) !void {
    std.log.info("Starting OAuth authentication setup...", .{});
    _ = try oauth.setupOAuth(allocator);
}

/// Handle status command
pub fn handleStatusCommand(allocator: std.mem.Allocator) !void {
    std.log.info("Checking authentication status...", .{});
    try displayStatusCLI(allocator);
}

/// Handle refresh command
pub fn handleRefreshCommand(allocator: std.mem.Allocator) !void {
    std.log.info("Refreshing authentication tokens...", .{});

    var client = core.createClient(allocator) catch |err| {
        std.log.err("Failed to load authentication: {}", .{err});
        std.log.info("Run 'docz auth login' to setup authentication", .{});
        return;
    };
    defer client.deinit();

    client.refresh() catch |err| {
        std.log.err("Failed to refresh tokens: {}", .{err});
        std.log.info("Try running 'docz auth login' to re-authenticate", .{});
        return;
    };

    std.log.info("✅ Tokens refreshed successfully!", .{});
}

/// Simple CLI status display (without TUI)
pub fn displayStatusCLI(allocator: std.mem.Allocator) !void {
    var client = core.createClient(allocator) catch |err| {
        std.debug.print("❌ No authentication configured: {}\n", .{err});
        std.debug.print("Run 'docz auth login' to setup OAuth authentication\n");
        return;
    };
    defer client.deinit();

    switch (client.credentials) {
        .oauth => |creds| {
            if (creds.isExpired()) {
                std.debug.print("⚠️  OAuth credentials expired\n");
                std.debug.print("Run 'docz auth refresh' to renew tokens\n");
            } else {
                std.debug.print("✅ OAuth authentication active (Claude Pro/Max)\n");
                const time_to_expire = creds.expires_at - std.time.timestamp();
                std.debug.print("Expires in: {} seconds\n", .{time_to_expire});
            }
        },
        .api_key => {
            std.debug.print("✅ API key authentication active\n");
        },
        .none => {
            std.debug.print("❌ No authentication configured\n");
        },
    }
}

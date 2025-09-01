//! CLI commands for authentication
//!
//! This module provides command-line interface handlers for authentication commands
//! that integrate with the CLI framework.

const std = @import("std");
const core = @import("../../network/auth/Core.zig");
const oauth = @import("../../network/auth/OAuth.zig");

/// Authentication command types
pub const AuthCommand = enum {
    login,
    status,
    refresh,
    logout,
    whoami,
    test_call,

    pub fn fromString(str: []const u8) ?AuthCommand {
        if (std.mem.eql(u8, str, "login")) return .login;
        if (std.mem.eql(u8, str, "status")) return .status;
        if (std.mem.eql(u8, str, "refresh")) return .refresh;
        if (std.mem.eql(u8, str, "logout")) return .logout;
        if (std.mem.eql(u8, str, "whoami")) return .whoami;
        if (std.mem.eql(u8, str, "test-call") or std.mem.eql(u8, str, "test_call")) return .test_call;
        return null;
    }
};

/// Run authentication command
pub fn runAuthCommand(allocator: std.mem.Allocator, command: AuthCommand) !void {
    switch (command) {
        .login => try handleLoginCommand(allocator),
        .status => try handleStatusCommand(allocator),
        .refresh => try handleRefreshCommand(allocator),
        .logout => try handleLogoutCommand(allocator),
        .whoami => try handleWhoamiCommand(allocator),
        .test_call => try handleTestCallCommand(allocator),
    }
}

/// Handle login command (OAuth setup)
pub fn handleLoginCommand(allocator: std.mem.Allocator) !void {
    std.log.info("Starting OAuth authentication setup...", .{});
    // Prefer callback server flow for a code-less experience.
    oauth.completeOAuthFlow(allocator) catch |err| {
        std.log.warn("Callback flow failed ({any}); falling back to manual code entry.", .{err});
        // setupOAuth returns credentials; assign to '_' to acknowledge the value
        _ = try oauth.setupOAuth(allocator);
    };
}

/// Handle status command
pub fn handleStatusCommand(allocator: std.mem.Allocator) !void {
    std.log.info("Checking authentication status...", .{});
    try displayStatus(allocator);
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

/// Status display (without TUI)
pub fn displayStatus(allocator: std.mem.Allocator) !void {
    var client = core.createClient(allocator) catch |err| {
        std.debug.print("❌ No authentication configured: {}\n", .{err});
        std.debug.print("Run 'docz auth login' to setup OAuth authentication\n", .{});
        return;
    };
    defer client.deinit();

    switch (client.credentials) {
        .oauth => |creds| {
            if (creds.isExpired()) {
                std.debug.print("⚠️  OAuth credentials expired\n", .{});
                std.debug.print("Run 'docz auth refresh' to renew tokens\n", .{});
            } else {
                std.debug.print("✅ OAuth authentication active (Claude Pro/Max)\n", .{});
                const timeToExpire = creds.expiresAt - std.time.timestamp();
                std.debug.print("Expires in: {} seconds\n", .{timeToExpire});
            }
        },
        .api_key => {
            std.debug.print("✅ API key authentication active\n", .{});
        },
        .none => {
            std.debug.print("❌ No authentication configured\n", .{});
        },
    }
}

/// Remove stored OAuth credentials
pub fn handleLogoutCommand(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.fs.cwd().deleteFile("claude_oauth_creds.json") catch |err| switch (err) {
        error.FileNotFound => std.log.info("No credentials file found", .{}),
        else => return err,
    };
    std.log.info("✅ Logged out (credentials removed)", .{});
}

/// Print basic identity info
pub fn handleWhoamiCommand(allocator: std.mem.Allocator) !void {
    var client = core.createClient(allocator) catch |err| {
        std.debug.print("❌ No authentication configured: {}\n", .{err});
        return;
    };
    defer client.deinit();
    switch (client.credentials) {
        .api_key => std.debug.print("Using API key authentication\n", .{}),
        .oauth => |c| {
            const now: i64 = std.time.timestamp();
            const secs = c.expiresAt - now;
            std.debug.print("Using OAuth (expires in {d}s)\n", .{secs});
        },
        .none => std.debug.print("Unauthenticated\n", .{}),
    }
}

/// Make a small Messages API request to verify headers/auth
pub fn handleTestCallCommand(allocator: std.mem.Allocator) !void {
    const net = @import("../../network.zig");
    const anthropic = net.Anthropic;

    var ac = core.createClient(allocator) catch |err| {
        std.debug.print("❌ No authentication configured: {}\n", .{err});
        return;
    };
    defer ac.deinit();

    var client: anthropic.Client.Client = switch (ac.credentials) {
        .api_key => |k| try anthropic.Client.Client.init(allocator, k),
        .oauth => |c| blk: {
            const creds = anthropic.Models.Credentials{
                .type = c.type,
                .accessToken = c.accessToken,
                .refreshToken = c.refreshToken,
                .expiresAt = c.expiresAt,
            };
            break :blk try anthropic.Client.Client.initWithOAuth(allocator, creds, "claude_oauth_creds.json");
        },
        .none => return,
    };
    defer client.deinit();

    var ctx = anthropic.Client.SharedContext.init(allocator);
    defer ctx.deinit();

    const msg = [_]anthropic.Message{.{ .role = .user, .content = "ping" }};
    const res = try client.complete(&ctx, .{ .model = "claude-3-5-sonnet-20241022", .messages = &msg, .maxTokens = 16 });
    defer {
        var m = res;
        m.deinit();
    }
    std.debug.print("✅ Test call succeeded\n", .{});
}

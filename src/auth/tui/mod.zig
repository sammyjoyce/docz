//! TUI components for authentication
//!
//! This module provides terminal user interface components for OAuth setup,
//! authentication status display, and credential management.

const std = @import("std");
const tui = @import("../../tui/mod.zig");
const oauth = @import("../oauth/mod.zig");
const core = @import("../core/mod.zig");

// Re-export individual TUI components
pub const oauth_wizard = @import("oauth_wizard.zig");
pub const auth_status = @import("auth_status.zig");
pub const code_input = @import("code_input.zig");

// Re-export main functions
pub const runAuthTUI = runTUI;
pub const setupOAuthWithTUI = oauth_wizard.setupOAuth;
pub const showAuthStatus = auth_status.display;
pub const inputAuthCode = code_input.input;

/// Main authentication TUI entry point
pub fn runTUI(allocator: std.mem.Allocator, auth_type: AuthTUIType) !void {
    switch (auth_type) {
        .oauth_setup => try oauth_wizard.run(allocator),
        .status => try auth_status.run(allocator),
        .refresh => try refreshTUI(allocator),
    }
}

/// Types of authentication TUI interfaces
pub const AuthTUIType = enum {
    oauth_setup,
    status,
    refresh,
};

/// Refresh tokens with TUI feedback
fn refreshTUI(allocator: std.mem.Allocator) !void {
    tui.clearScreen();

    // Display header

    // Show status while refreshing
    print("{s}🔄 Refreshing Authentication Tokens{s}\n\n", .{ tui.Color.BRIGHT_CYAN, tui.Color.RESET });

    // Try to refresh
    var client = core.createClient(allocator) catch |err| {
        print("{s}❌ Failed to initialize auth client: {}{s}\n", .{ tui.Color.BRIGHT_RED, err, tui.Color.RESET });
        return;
    };
    defer client.deinit();

    client.refresh() catch |err| {
        print("{s}❌ Failed to refresh tokens: {}{s}\n", .{ tui.Color.BRIGHT_RED, err, tui.Color.RESET });
        print("\nTry running: docz auth login\n");
        return;
    };

    print("{s}✅ Tokens refreshed successfully!{s}\n", .{ tui.Color.BRIGHT_GREEN, tui.Color.RESET });
}

// Helper to get terminal size safely
const print = std.debug.print;

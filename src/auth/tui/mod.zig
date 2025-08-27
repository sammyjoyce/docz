//! TUI components for authentication
//!
//! This module provides terminal user interface components for OAuth setup,
//! authentication status display, and credential management.

const std = @import("std");
const oauth = @import("../oauth/mod.zig");
const core = @import("../core/mod.zig");

// Minimal TUI interface with basic ANSI escape codes
const tui = struct {
    fn getTerminalSize() struct { width: u16, height: u16 } {
        // Use a reasonable default since we don't have access to full TUI
        return .{ .width = 80, .height = 24 };
    }

    fn clearScreen() void {
        print("\x1b[2J\x1b[H", .{});
    }

    const Color = struct {
        pub const BRIGHT_BLUE = "\x1b[94m";
        pub const BRIGHT_GREEN = "\x1b[92m";
        pub const BRIGHT_RED = "\x1b[91m";
        pub const BRIGHT_CYAN = "\x1b[96m";
        pub const DIM = "\x1b[2m";
        pub const BOLD = "\x1b[1m";
        pub const RESET = "\x1b[0m";
    };

    const TerminalSize = struct {
        width: u16,
        height: u16,
    };
};

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

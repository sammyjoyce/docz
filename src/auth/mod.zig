//! Authentication module for DocZ
//!
//! This module provides a unified interface for authentication functionality,
//! including OAuth, API key authentication, TUI components, and CLI commands.

const std = @import("std");

// Core authentication types and logic
pub const core = @import("core/mod.zig");

// OAuth-specific implementations
pub const oauth = @import("oauth/mod.zig");

// TUI components for authentication
pub const tui = @import("tui/mod.zig");

// CLI commands for authentication
pub const cli = @import("cli/mod.zig");

// Re-export commonly used types for convenience
pub const AuthMethod = core.AuthMethod;
pub const AuthCredentials = core.AuthCredentials;
pub const OAuthCredentials = oauth.OAuthCredentials;
pub const AuthClient = core.AuthClient;
pub const AuthError = core.AuthError;

// Re-export main authentication functions
pub const createClient = core.createClient;
pub const loadCredentials = core.loadCredentials;
pub const saveCredentials = core.saveCredentials;

// Re-export OAuth functions
pub const setupOAuth = oauth.setupOAuth;
pub const refreshTokens = oauth.refreshTokens;

// Re-export TUI functions
pub const runAuthTUI = tui.runAuthTUI;
pub const setupOAuthWithTUI = tui.setupOAuthWithTUI;

// Re-export CLI functions
pub const runAuthCommand = cli.runAuthCommand;
pub const handleLoginCommand = cli.handleLoginCommand;
pub const handleStatusCommand = cli.handleStatusCommand;
pub const handleRefreshCommand = cli.handleRefreshCommand;

/// Initialize the authentication module
pub fn init() void {
    std.log.debug("Authentication module initialized", .{});
}

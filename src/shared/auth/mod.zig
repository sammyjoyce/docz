//! Authentication module for DocZ
//!
//! This module provides a unified interface for authentication functionality,
//! including OAuth, API key authentication, TUI components, and CLI commands.

const std = @import("std");

// Core authentication types and logic
pub const core = @import("core/mod.zig");

// OAuth-specific implementations
pub const oauth = @import("oauth/mod.zig");

// CLI commands for authentication
pub const cli = @import("cli/mod.zig");

// Re-export commonly used types for convenience
pub const AuthMethod = core.AuthMethod;
pub const AuthCredentials = core.AuthCredentials;
pub const Credentials = oauth.Credentials;
pub const AuthClient = core.AuthClient;
pub const AuthError = core.AuthError;

// Re-export main authentication functions
pub const createClient = core.createClient;
pub const loadCredentials = core.loadCredentials;
pub const saveCredentials = core.saveCredentials;

// Re-export OAuth functions
pub const setupOAuth = oauth.setupOAuth;
pub const refreshTokens = oauth.refreshTokens;

// Re-export curl for OAuth module usage
pub const curl = @import("anthropic_shared").curl;

// Re-export callback server types and functions
pub const Server = oauth.Server;
pub const Config = oauth.Config;
pub const Result = oauth.Result;
pub const runCallbackServer = oauth.runCallbackServer;
pub const integrateWithWizard = oauth.integrateWithWizard;
pub const completeOAuthFlow = oauth.completeOAuthFlow;

// TUI functions are available via the TUI module when building interactive flows.

// Re-export CLI functions
pub const runAuthCommand = cli.runAuthCommand;
pub const handleLoginCommand = cli.handleLoginCommand;
pub const handleStatusCommand = cli.handleStatusCommand;
pub const handleRefreshCommand = cli.handleRefreshCommand;

/// Initialize the authentication module
pub fn init() void {
    std.log.debug("Authentication module initialized", .{});
}

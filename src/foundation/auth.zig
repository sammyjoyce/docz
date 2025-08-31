//! Authentication module for DocZ
//!
//! Barrel for auth core + OAuth + CLI glue.
//! - Import via this barrel; avoid deep-importing subfiles.
//! - Feature-gate in consumers via `@import("../shared/mod.zig").options.feature_tui` if tying to TUI.
//! - Override behavior using root `shared_options` to toggle auth-related features in builds.

const std = @import("std");

// Core authentication types and logic
pub const core = @import("auth/core.zig");

// OAuth-specific implementations
pub const oauth = @import("auth/oauth.zig");

// CLI commands for authentication
pub const cli = @import("auth/cli.zig");

// Re-export commonly used types for convenience
pub const AuthMethod = core.AuthMethod;
pub const AuthCredentials = core.AuthCredentials;
pub const Credentials = oauth.Credentials;
pub const AuthClient = core.AuthClient;
pub const AuthError = core.AuthError;
pub const Service = core.Service;

// Re-export main authentication functions
pub const createClient = core.createClient;
pub const loadCredentials = core.loadCredentials;
pub const saveCredentials = core.saveCredentials;

// Re-export OAuth functions
pub const setupOAuth = oauth.setupOAuth;
pub const refreshTokens = oauth.refreshTokens;

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

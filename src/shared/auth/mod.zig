//! Authentication module for DocZ
//!
//! Barrel for auth core + OAuth + CLI glue.
//! - Import via this barrel; avoid deep-importing subfiles.
//! - Feature-gate in consumers via `@import("../shared/mod.zig").options.feature_tui` if tying to TUI.
//! - Override behavior using root `shared_options` to toggle auth-related features in builds.

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
pub const Service = core.Service;

// Re-export main authentication functions
pub const createClient = core.createClient;
pub const loadCredentials = core.loadCredentials;
pub const saveCredentials = core.saveCredentials;

// Re-export OAuth functions
pub const setupOAuth = oauth.setupOAuth;
pub const refreshTokens = oauth.refreshTokens;

// Note: curl re-export is stubbed here to avoid deep dependency;
// prefer `@import("shared/network/mod.zig").curl` in new code.
pub const curl = struct {
    pub const HTTPResponse = struct {
        status_code: u16,
        body: []const u8,
        pub fn deinit(self: @This()) void {
            _ = self;
        }
    };

    pub const HTTPClient = struct {
        pub fn init(_: std.mem.Allocator) !@This() {
            return @This(){};
        }
        pub fn deinit(self: @This()) void {
            _ = self;
        }
        pub fn post(self: @This(), url: []const u8, headers: []const Header, body: []const u8) !HTTPResponse {
            _ = self;
            _ = url;
            _ = headers;
            _ = body;
            return .{ .status_code = 200, .body = "{}" }; // Stub response
        }
    };
    pub const Header = struct {
        name: []const u8,
        value: []const u8,
    };
};

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

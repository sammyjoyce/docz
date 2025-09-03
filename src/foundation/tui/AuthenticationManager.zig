//! Authentication Manager for TUI Agent Interface
//!
//! This module provides authentication management for the TUI agent interface,
//! integrating with the network authentication services.

const std = @import("std");
const auth_port = @import("../ports/auth.zig");
const tui = @import("../tui.zig");

const Allocator = std.mem.Allocator;
const AuthPort = auth_port.AuthPort;
const Credentials = auth_port.Credentials;
const AuthError = auth_port.Error;

/// Authentication state
pub const AuthState = enum {
    unauthenticated,
    authenticating,
    authenticated,
    refreshing,
    auth_error,
};

/// Authentication events for callbacks
pub const AuthEvent = union(enum) {
    state_changed: AuthState,
    credentials_loaded: Credentials,
    credentials_expired: void,
    auth_failed: AuthError,
    auth_success: void,
};

/// Callback function type for authentication events
pub const AuthCallback = *const fn (event: AuthEvent, ctx: *anyopaque) void;

/// Authentication method summary for UI logic
pub const AuthMethod = enum { api_key, oauth, none };

const CallbackEntry = struct { callback: AuthCallback, ctx: *anyopaque };
const CallbackList = std.ArrayListUnmanaged(CallbackEntry);

/// Authentication Manager
pub const AuthenticationManager = struct {
    allocator: Allocator,
    port: AuthPort,
    state: AuthState,
    current_credentials: ?Credentials,
    callbacks: CallbackList,
    mutex: std.Thread.Mutex,
    refresh_task: ?std.Thread = null,

    const Self = @This();

    /// Initialize the authentication manager
    pub fn init(allocator: Allocator, maybe_port: ?AuthPort) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = Self{
            .allocator = allocator,
            .port = if (maybe_port) |p| p else auth_port.nullAuthPort(),
            .state = .unauthenticated,
            .current_credentials = null,
            .callbacks = .{},
            .mutex = std.Thread.Mutex{},
            .refresh_task = null,
        };

        return self;
    }

    /// Deinitialize the authentication manager
    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.refresh_task) |task| {
            task.join();
            self.refresh_task = null;
        }

        if (self.current_credentials) |creds| {
            creds.deinit(self.allocator);
            self.current_credentials = null;
        }

        self.callbacks.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Register a callback for authentication events
    pub fn registerCallback(self: *Self, callback: AuthCallback, ctx: *anyopaque) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.callbacks.append(self.allocator, .{ .callback = callback, .ctx = ctx });
    }

    /// Notify all registered callbacks of an event
    fn notifyCallbacks(self: *Self, event: AuthEvent) void {
        for (self.callbacks.items) |cb| {
            cb.callback(event, cb.ctx);
        }
    }

    /// Update authentication state
    fn setState(self: *Self, new_state: AuthState) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.state != new_state) {
            self.state = new_state;
            self.notifyCallbacks(.{ .state_changed = new_state });
        }
    }

    /// Get current authentication state
    pub fn getState(self: *Self) AuthState {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.state;
    }

    /// Check if authenticated
    pub fn isAuthenticated(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.state == .authenticated and
            self.current_credentials != null and
            self.current_credentials.?.isValid();
    }

    /// Get current authentication method
    pub fn getAuthMethod(self: *Self) AuthMethod {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.current_credentials) |creds| {
            return switch (creds) {
                .api_key => .api_key,
                .oauth => .oauth,
                .none => .none,
            };
        }
        return .none;
    }

    /// Load credentials from file or environment
    pub fn loadCredentials(self: *Self) !void {
        self.setState(.authenticating);

        _ = self.port.load(self.allocator) catch |err| {
            self.setState(.auth_error);
            self.notifyCallbacks(.{ .auth_failed = err });
            return err;
        };
        const creds = try self.port.load(self.allocator);

        self.mutex.lock();
        if (self.current_credentials) |old_creds| {
            old_creds.deinit(self.allocator);
        }
        self.current_credentials = creds;
        self.mutex.unlock();

        self.setState(.authenticated);
        self.notifyCallbacks(.{ .credentials_loaded = creds });
        self.notifyCallbacks(.{ .auth_success = {} });

        // Start refresh task for OAuth credentials
        if (creds == .oauth) {
            try self.startRefreshTask();
        }
    }

    /// Save credentials to file
    pub fn saveCredentials(self: *Self, credentials: Credentials) !void {
        const path = switch (credentials) {
            .oauth => "claude_oauth_creds.json",
            .api_key => "claude_api_key.txt",
            .none => return AuthError.InvalidCredentials,
        };

        // Delegate to port; a default adapter may persist based on type
        _ = path;
        try self.port.save(self.allocator, credentials);

        self.mutex.lock();
        if (self.current_credentials) |old_creds| {
            old_creds.deinit(self.allocator);
        }
        self.current_credentials = credentials;
        self.mutex.unlock();

        self.setState(.authenticated);
        self.notifyCallbacks(.{ .credentials_loaded = credentials });
    }

    /// Authenticate with API key
    pub fn authenticateWithApiKey(self: *Self, api_key: []const u8) !void {
        self.setState(.authenticating);

        const key_copy = try self.allocator.dupe(u8, api_key);
        errdefer self.allocator.free(key_copy);

        const creds = Credentials{ .api_key = key_copy };

        if (!creds.isValid()) {
            self.setState(.auth_error);
            self.notifyCallbacks(.{ .auth_failed = AuthError.InvalidAPIKey });
            return AuthError.InvalidAPIKey;
        }

        try self.saveCredentials(creds);
        self.notifyCallbacks(.{ .auth_success = {} });
    }

    /// Start OAuth flow (returns authorization URL)
    pub fn startOAuthFlow(self: *Self) ![]const u8 {
        self.setState(.authenticating);

        const session = try self.port.startOAuth(self.allocator);
        // The caller (wizard) is responsible for capturing/storing pkce_verifier
        const url = try self.allocator.dupe(u8, session.url);
        session.deinit(self.allocator);
        return url;
    }

    /// Complete OAuth flow with authorization code
    pub fn completeOAuthFlow(self: *Self, auth_code: []const u8, pkce_verifier: []const u8) !void {
        const creds = try self.port.completeOAuth(self.allocator, auth_code, pkce_verifier);

        try self.saveCredentials(.{ .oauth = creds });
        self.notifyCallbacks(.{ .auth_success = {} });

        try self.startRefreshTask();
    }

    /// Refresh OAuth tokens if needed
    pub fn refreshTokensIfNeeded(self: *Self) !void {
        self.mutex.lock();
        const creds = self.current_credentials;
        self.mutex.unlock();

        if (creds == null) return;

        switch (creds.?) {
            .oauth => |oauth_creds| {
                if (oauth_creds.willExpireSoon(300)) { // 5 minutes leeway
                    self.setState(.refreshing);

                    const updated = try self.port.refreshIfNeeded(self.allocator, .{ .oauth = oauth_creds });
                    try self.saveCredentials(updated);
                }
            },
            else => {},
        }
    }

    /// Start background refresh task for OAuth tokens
    fn startRefreshTask(self: *Self) !void {
        if (self.refresh_task != null) return;

        const RefreshContext = struct {
            manager: *AuthenticationManager,

            fn refreshLoop(ctx: *@This()) void {
                while (ctx.manager.getState() == .authenticated) {
                    ctx.manager.refreshTokensIfNeeded() catch |err| {
                        std.log.err("Token refresh failed: {}", .{err});
                        ctx.manager.setState(.auth_error);
                        ctx.manager.notifyCallbacks(.{ .auth_failed = AuthError.TokenExpired });
                        break;
                    };

                    // Check every minute (if sleep available)
                    sleepNs(60 * std.time.ns_per_s);
                }
            }
        };

        const ctx = try self.allocator.create(RefreshContext);
        ctx.* = .{ .manager = self };

        self.refresh_task = try std.Thread.spawn(.{}, RefreshContext.refreshLoop, .{ctx});
    }

    fn sleepNs(ns: u64) void {
        if (comptime @hasDecl(std.time, "sleep")) {
            std.time.sleep(ns);
        } else {
            // no-op if unavailable
            {}
        }
    }

    /// Clear current credentials and logout
    pub fn logout(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.refresh_task) |task| {
            task.join();
            self.refresh_task = null;
        }

        if (self.current_credentials) |creds| {
            creds.deinit(self.allocator);
            self.current_credentials = null;
        }

        self.state = .unauthenticated;
        self.notifyCallbacks(.{ .state_changed = .unauthenticated });
    }

    /// Get authorization header value for HTTP requests
    pub fn getAuthorizationHeader(self: *Self) !?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.current_credentials) |creds| {
            return try self.port.authHeader(self.allocator, creds);
        }
        return null;
    }
};

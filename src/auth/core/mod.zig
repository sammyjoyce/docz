//! Core authentication types and functions

const std = @import("std");
const oauth = @import("../oauth/mod.zig");

/// Authentication error types
pub const AuthError = error{
    MissingAPIKey,
    InvalidCredentials,
    TokenExpired,
    AuthenticationFailed,
    NetworkError,
    FileNotFound,
    InvalidFormat,
    OutOfMemory,
};

/// Authentication methods supported by the system
pub const AuthMethod = enum {
    api_key,
    oauth,
    none,
};

/// Generic authentication credentials
pub const AuthCredentials = union(AuthMethod) {
    api_key: []const u8,
    oauth: oauth.OAuthCredentials,
    none: void,

    /// Check if credentials are valid/not expired
    pub fn isValid(self: AuthCredentials) bool {
        return switch (self) {
            .api_key => |key| key.len > 0,
            .oauth => |creds| !creds.isExpired(),
            .none => false,
        };
    }

    /// Get the authentication method type
    pub fn getMethod(self: AuthCredentials) AuthMethod {
        return switch (self) {
            .api_key => .api_key,
            .oauth => .oauth,
            .none => .none,
        };
    }

    /// Free any allocated memory in credentials
    pub fn deinit(self: AuthCredentials, allocator: std.mem.Allocator) void {
        switch (self) {
            .api_key => |key| allocator.free(key),
            .oauth => |creds| creds.deinit(allocator),
            .none => {},
        }
    }
};

/// Authentication client wrapper
pub const AuthClient = struct {
    allocator: std.mem.Allocator,
    credentials: AuthCredentials,
    credentials_path: ?[]const u8,

    /// Initialize an authentication client with given credentials
    pub fn init(allocator: std.mem.Allocator, credentials: AuthCredentials) AuthClient {
        return AuthClient{
            .allocator = allocator,
            .credentials = credentials,
            .credentials_path = null,
        };
    }

    /// Initialize with credentials path for persistence
    pub fn initWithPath(
        allocator: std.mem.Allocator,
        credentials: AuthCredentials,
        credentials_path: []const u8,
    ) !AuthClient {
        return AuthClient{
            .allocator = allocator,
            .credentials = credentials,
            .credentials_path = try allocator.dupe(u8, credentials_path),
        };
    }

    /// Clean up the auth client
    pub fn deinit(self: *AuthClient) void {
        self.credentials.deinit(self.allocator);
        if (self.credentials_path) |path| {
            self.allocator.free(path);
        }
    }

    /// Check if the client is using OAuth authentication
    pub fn isOAuth(self: AuthClient) bool {
        return self.credentials.getMethod() == .oauth;
    }

    /// Refresh authentication if needed (OAuth only)
    pub fn refresh(self: *AuthClient) AuthError!void {
        switch (self.credentials) {
            .oauth => |creds| {
                if (creds.willExpireSoon(300)) { // 5 minute buffer
                    const new_creds = oauth.refreshTokens(self.allocator, creds.refresh_token) catch |err| {
                        std.log.err("Failed to refresh OAuth tokens: {}", .{err});
                        return AuthError.AuthenticationFailed;
                    };

                    // Free old credentials
                    creds.deinit(self.allocator);

                    // Update with new credentials
                    self.credentials = AuthCredentials{ .oauth = new_creds };

                    // Save updated credentials if path is available
                    if (self.credentials_path) |path| {
                        saveCredentials(self.allocator, path, self.credentials) catch |err| {
                            std.log.warn("Failed to save refreshed credentials: {}", .{err});
                        };
                    }
                }
            },
            .api_key, .none => {}, // No refresh needed
        }
    }
};

/// Create an authentication client from available sources
pub fn createClient(allocator: std.mem.Allocator) AuthError!AuthClient {
    // Try OAuth first
    const oauth_path = "claude_oauth_creds.json";
    if (loadCredentials(allocator, oauth_path)) |credentials| {
        if (credentials.isValid()) {
            std.log.info("Using OAuth authentication", .{});
            return AuthClient.initWithPath(allocator, credentials, oauth_path) catch |err| {
                credentials.deinit(allocator);
                return err;
            };
        }
        credentials.deinit(allocator);
    } else |_| {}

    // Try API key from environment
    if (std.process.getEnvVarOwned(allocator, "ANTHROPIC_API_KEY")) |api_key| {
        if (api_key.len > 0) {
            std.log.info("Using API key authentication", .{});
            const credentials = AuthCredentials{ .api_key = api_key };
            return AuthClient.init(allocator, credentials);
        }
        allocator.free(api_key);
    } else |_| {}

    std.log.err("No authentication method available", .{});
    return AuthError.MissingAPIKey;
}

/// Load authentication credentials from file
pub fn loadCredentials(allocator: std.mem.Allocator, file_path: []const u8) AuthError!AuthCredentials {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return AuthError.FileNotFound,
        else => return AuthError.FileNotFound,
    };
    defer file.close();

    const contents = file.readToEndAlloc(allocator, 16 * 1024) catch {
        return AuthError.InvalidFormat;
    };
    defer allocator.free(contents);

    // Try to parse as OAuth credentials
    if (oauth.parseCredentials(allocator, contents)) |oauth_creds| {
        return AuthCredentials{ .oauth = oauth_creds };
    } else |_| {}

    // Could add other credential types here (API key files, etc.)

    return AuthError.InvalidFormat;
}

/// Save authentication credentials to file
pub fn saveCredentials(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    credentials: AuthCredentials,
) AuthError!void {
    switch (credentials) {
        .oauth => |creds| {
            oauth.saveCredentials(allocator, file_path, creds) catch {
                return AuthError.InvalidFormat;
            };
        },
        .api_key => {
            // Could save API key to file if needed
            return AuthError.InvalidFormat;
        },
        .none => return AuthError.InvalidCredentials,
    }
}

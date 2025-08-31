//! UI-free Authentication Service
//!
//! This module provides a clean, UI-free interface for authentication operations,
//! wrapping the existing OAuth and credential management logic.

const std = @import("std");
const oauth = @import("../oauth.zig");
const core_auth = @import("../core.zig");
const curl = @import("../../network/curl.zig");

/// Authentication service errors
pub const AuthError = error{
    MissingAPIKey,
    InvalidAPIKey,
    InvalidCredentials,
    TokenExpired,
    AuthenticationFailed,
    NetworkError,
    FileNotFound,
    InvalidFormat,
    OutOfMemory,
    InvalidGrant,
    RefreshInProgress,
};

/// Generic authentication credentials for the service
pub const Credentials = union(core_auth.AuthMethod) {
    api_key: []const u8,
    oauth: oauth.Credentials,
    none: void,

    /// Check if credentials are valid/not expired
    pub fn isValid(self: Credentials) bool {
        return switch (self) {
            .api_key => |key| key.len > 0,
            .oauth => |creds| !creds.isExpired(),
            .none => false,
        };
    }

    /// Get the authentication method type
    pub fn getMethod(self: Credentials) core_auth.AuthMethod {
        return switch (self) {
            .api_key => .api_key,
            .oauth => .oauth,
            .none => .none,
        };
    }

    /// Free any allocated memory in credentials
    pub fn deinit(self: Credentials, allocator: std.mem.Allocator) void {
        switch (self) {
            .api_key => |key| allocator.free(key),
            .oauth => |creds| creds.deinit(allocator),
            .none => {},
        }
    }
};

/// Authentication service providing UI-free operations
pub const Service = struct {
    allocator: std.mem.Allocator,

    /// Initialize the authentication service
    pub fn init(allocator: std.mem.Allocator) Service {
        return Service{
            .allocator = allocator,
        };
    }

    /// Load credentials from file or environment
    /// First tries OAuth credentials from file, then API key from environment
    pub fn loadCredentials(self: Service) AuthError!Credentials {
        // Try OAuth first
        const oauthPath = "claude_oauth_creds.json";
        if (self.loadCredentialsFromFile(oauthPath)) |credentials| {
            if (credentials.isValid()) {
                return credentials;
            }
            credentials.deinit(self.allocator);
        } else |_| {}

        // Try API key from environment
        if (std.process.getEnvVarOwned(self.allocator, "ANTHROPIC_API_KEY")) |apiKey| {
            defer self.allocator.free(apiKey);
            if (apiKey.len > 0) {
                if (std.unicode.utf8ValidateSlice(apiKey)) {
                    // Sanitize the API key
                    const sanitizedKey = try self.allocator.alloc(u8, apiKey.len);
                    var validLen: usize = 0;
                    for (apiKey) |c| {
                        if (c >= 32 and c != 127) {
                            sanitizedKey[validLen] = c;
                            validLen += 1;
                        }
                    }

                    if (validLen == 0) {
                        self.allocator.free(sanitizedKey);
                        return AuthError.InvalidAPIKey;
                    }

                    const finalKey = if (validLen < apiKey.len) try self.allocator.realloc(sanitizedKey, validLen) else sanitizedKey;
                    return Credentials{ .api_key = finalKey };
                } else {
                    return AuthError.InvalidAPIKey;
                }
            }
        } else |_| {}

        return AuthError.MissingAPIKey;
    }

    /// Save credentials to file
    pub fn saveCredentials(self: Service, creds: Credentials) AuthError!void {
        switch (creds) {
            .oauth => |oauthCreds| {
                try oauth.saveCredentials(self.allocator, "claude_oauth_creds.json", oauthCreds);
            },
            .api_key => {
                // API keys are typically stored in environment, not file
                return AuthError.InvalidFormat;
            },
            .none => return AuthError.InvalidCredentials,
        }
    }

    /// Generate OAuth login URL with PKCE
    pub fn loginUrl(self: Service, state: []const u8) AuthError![]u8 {
        var pkceParams = try oauth.generatePkceParams(self.allocator);
        defer pkceParams.deinit(self.allocator);

        // Override the generated state with the provided state
        self.allocator.free(pkceParams.state);
        pkceParams.state = try self.allocator.dupe(u8, state);

        const scopes = [_][]const u8{ "org:create_api_key", "user:profile", "user:inference" };
        const provider = oauth.Provider{
            .clientId = oauth.OAUTH_CLIENT_ID,
            .authorizationUrl = oauth.OAUTH_AUTHORIZATION_URL,
            .tokenUrl = oauth.OAUTH_TOKEN_ENDPOINT,
            .redirectUri = oauth.OAUTH_REDIRECT_URI,
            .scopes = &scopes,
        };

        return try provider.buildAuthorizationUrl(self.allocator, pkceParams);
    }

    /// Exchange authorization code for tokens
    pub fn exchangeCode(self: Service, code: []const u8, pkceVerifier: []const u8) AuthError!Credentials {
        const pkceParams = oauth.Pkce{
            .codeVerifier = try self.allocator.dupe(u8, pkceVerifier),
            .codeChallenge = try self.allocator.dupe(u8, ""), // Not needed for exchange
            .state = try self.allocator.dupe(u8, ""), // Not needed for exchange
        };
        defer pkceParams.deinit(self.allocator);

        const oauthCreds = try oauth.exchangeCodeForTokens(self.allocator, code, pkceParams);
        return Credentials{ .oauth = oauthCreds };
    }

    /// Refresh OAuth tokens
    pub fn refresh(self: Service, creds: Credentials) AuthError!Credentials {
        switch (creds) {
            .oauth => |oauthCreds| {
                if (oauthCreds.willExpireSoon(300)) {
                    const newCreds = oauth.refreshTokens(self.allocator, oauthCreds.refreshToken) catch |err| {
                        std.log.err("Failed to refresh OAuth tokens: {}", .{err});
                        return AuthError.AuthenticationFailed;
                    };
                    return Credentials{ .oauth = newCreds };
                }
                // Return copy if not expired
                return Credentials{
                    .oauth = oauth.Credentials{
                        .type = try self.allocator.dupe(u8, oauthCreds.type),
                        .accessToken = try self.allocator.dupe(u8, oauthCreds.accessToken),
                        .refreshToken = try self.allocator.dupe(u8, oauthCreds.refreshToken),
                        .expiresAt = oauthCreds.expiresAt,
                    },
                };
            },
            else => return AuthError.InvalidCredentials,
        }
    }

    /// Check authentication status
    pub fn status(self: Service, creds: Credentials) AuthError!bool {
        // Suppress unused parameter warning
        _ = &self;
        return creds.isValid();
    }

    /// Load credentials from file (internal helper)
    fn loadCredentialsFromFile(self: Service, filePath: []const u8) AuthError!Credentials {
        const file = std.fs.cwd().openFile(filePath, .{}) catch |err| switch (err) {
            error.FileNotFound => return AuthError.FileNotFound,
            else => return AuthError.FileNotFound,
        };
        defer file.close();

        const contents = file.readToEndAlloc(self.allocator, 16 * 1024) catch {
            return AuthError.InvalidFormat;
        };
        defer self.allocator.free(contents);

        // Try to parse as OAuth credentials
        if (oauth.parseCredentials(self.allocator, contents)) |oauthCreds| {
            return Credentials{ .oauth = oauthCreds };
        } else |_| {}

        return AuthError.InvalidFormat;
    }
};

//! Core authentication types and functions

const std = @import("std");
const oauth = @import("OAuth.zig");

// Re-export the UI-free service
pub const Service = @import("Service.zig").Service;

/// Authentication error types
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
    oauth: oauth.Credentials,
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
    credentialsPath: ?[]const u8,

    /// Initialize an authentication client with given credentials
    pub fn init(allocator: std.mem.Allocator, credentials: AuthCredentials) AuthClient {
        return AuthClient{
            .allocator = allocator,
            .credentials = credentials,
            .credentialsPath = null,
        };
    }

    /// Initialize with credentials path for persistence
    pub fn initWithPath(
        allocator: std.mem.Allocator,
        credentials: AuthCredentials,
        credentialsPath: []const u8,
    ) !AuthClient {
        return AuthClient{
            .allocator = allocator,
            .credentials = credentials,
            .credentialsPath = try allocator.dupe(u8, credentialsPath),
        };
    }

    /// Clean up the auth client
    pub fn deinit(self: *AuthClient) void {
        self.credentials.deinit(self.allocator);
        if (self.credentialsPath) |path| {
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
                    const newCreds = oauth.refreshTokens(self.allocator, creds.refreshToken) catch |err| {
                        std.log.err("Failed to refresh OAuth tokens: {}", .{err});
                        return AuthError.AuthenticationFailed;
                    };

                    // Free old credentials
                    creds.deinit(self.allocator);

                    // Update with new credentials
                    self.credentials = AuthCredentials{ .oauth = newCreds };

                    // Save updated credentials if path is available
                    if (self.credentialsPath) |path| {
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
    // Prefer API key from environment (works for API usage)
    if (std.process.getEnvVarOwned(allocator, "ANTHROPIC_API_KEY")) |apiKey| {
        if (apiKey.len > 0) {
            // Validate and sanitize the API key
            if (std.unicode.utf8ValidateSlice(apiKey)) {
                // Sanitize the API key by replacing any control characters
                const sanitizedKey = try allocator.alloc(u8, apiKey.len);
                var validLen: usize = 0;
                for (apiKey) |c| {
                    if (c >= 32 and c != 127) { // Printable ASCII range (excluding DEL)
                        sanitizedKey[validLen] = c;
                        validLen += 1;
                    }
                }

                if (validLen == 0) {
                    std.log.err("ANTHROPIC_API_KEY contains only invalid characters", .{});
                    allocator.free(apiKey);
                    allocator.free(sanitizedKey);
                    return AuthError.InvalidAPIKey;
                }

                // Use the sanitized key
                const finalKey = if (validLen < apiKey.len) try allocator.realloc(sanitizedKey, validLen) else sanitizedKey;
                allocator.free(apiKey);

                std.log.info("Using API key authentication", .{});
                const credentials = AuthCredentials{ .api_key = finalKey };
                return AuthClient.init(allocator, credentials);
            } else {
                std.log.err("ANTHROPIC_API_KEY contains invalid UTF-8 characters", .{});
                allocator.free(apiKey);
                return AuthError.InvalidAPIKey;
            }
        } else {
            allocator.free(apiKey);
        }
    } else |_| {}

    // Then try OAuth credentials on disk (for future consumer flows)
    const oauthPath = "claude_oauth_creds.json";
    if (loadCredentials(allocator, oauthPath)) |credentials| {
        if (credentials.isValid()) {
            std.log.info("Using OAuth authentication", .{});
            // Sanitize tokens (strip whitespace/newlines) before storing
            const sanitized = sanitizeCredentials(allocator, credentials) catch |e| {
                credentials.deinit(allocator);
                return e;
            };
            credentials.deinit(allocator);
            return AuthClient.initWithPath(allocator, sanitized, oauthPath) catch |err| {
                sanitized.deinit(allocator);
                return err;
            };
        }
        credentials.deinit(allocator);
    } else |_| {}

    std.log.err("No authentication method available", .{});
    return AuthError.MissingAPIKey;
}

/// Remove whitespace/newlines from OAuth tokens to avoid malformed Authorization headers
fn stripWhitespace(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, input.len);
    var n: usize = 0;
    for (input) |c| {
        if (c == '\n' or c == '\r' or c == ' ' or c == '\t') continue;
        out[n] = c;
        n += 1;
    }
    return if (n == input.len) out else try allocator.realloc(out, n);
}

fn sanitizeCredentials(allocator: std.mem.Allocator, creds: AuthCredentials) !AuthCredentials {
    return switch (creds) {
        .oauth => |c| blk: {
            const at = try stripWhitespace(allocator, c.accessToken);
            const rt = try stripWhitespace(allocator, c.refreshToken);
            break :blk AuthCredentials{ .oauth = .{
                .type = try allocator.dupe(u8, c.type),
                .accessToken = at,
                .refreshToken = rt,
                .expiresAt = c.expiresAt,
            } };
        },
        .api_key => creds,
        .none => creds,
    };
}

/// Load authentication credentials from file
pub fn loadCredentials(allocator: std.mem.Allocator, filePath: []const u8) AuthError!AuthCredentials {
    const file = std.fs.cwd().openFile(filePath, .{}) catch |err| switch (err) {
        error.FileNotFound => return AuthError.FileNotFound,
        else => return AuthError.FileNotFound,
    };
    defer file.close();

    const contents = file.readToEndAlloc(allocator, 16 * 1024) catch {
        return AuthError.InvalidFormat;
    };
    defer allocator.free(contents);

    // Try to parse as OAuth credentials
    if (oauth.parseCredentials(allocator, contents)) |oauthCreds| {
        return AuthCredentials{ .oauth = oauthCreds };
    } else |_| {}

    // Could add other credential types here (API key files, etc.)

    return AuthError.InvalidFormat;
}

/// Save authentication credentials to file
pub fn saveCredentials(
    allocator: std.mem.Allocator,
    filePath: []const u8,
    credentials: AuthCredentials,
) AuthError!void {
    switch (credentials) {
        .oauth => |creds| {
            oauth.saveCredentials(allocator, filePath, creds) catch {
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

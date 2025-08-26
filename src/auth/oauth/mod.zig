//! OAuth authentication implementation for DocZ
//!
//! This module provides a clean interface to OAuth functionality while delegating
//! to the anthropic module for actual OAuth operations to avoid module conflicts.

const std = @import("std");

// Re-export OAuth constants and types from anthropic
pub const OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
pub const OAUTH_AUTHORIZATION_URL = "https://claude.ai/oauth/authorize";
pub const OAUTH_TOKEN_ENDPOINT = "https://console.anthropic.com/v1/oauth/token";
pub const OAUTH_REDIRECT_URI = "https://console.anthropic.com/oauth/code/callback";
pub const OAUTH_SCOPES = "org:create_api_key user:profile user:inference";

/// OAuth error types
pub const OAuthError = error{
    NetworkError,
    AuthError,
    TokenExpired,
    InvalidGrant,
    InvalidFormat,
    OutOfMemory,
    InvalidPort,
    RefreshInProgress,
};

/// OAuth credentials - compatible with anthropic module
pub const OAuthCredentials = struct {
    type: []const u8, // Always "oauth"
    access_token: []const u8,
    refresh_token: []const u8,
    expires_at: i64, // Unix timestamp

    /// Check if the token is expired
    pub fn isExpired(self: OAuthCredentials) bool {
        const now = std.time.timestamp();
        return now >= self.expires_at;
    }

    /// Check if the token will expire within the specified leeway (in seconds)
    pub fn willExpireSoon(self: OAuthCredentials, leeway: i64) bool {
        const now = std.time.timestamp();
        return now + leeway >= self.expires_at;
    }

    /// Clean up allocated memory
    pub fn deinit(self: OAuthCredentials, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        allocator.free(self.access_token);
        allocator.free(self.refresh_token);
    }
};

/// PKCE parameters - compatible with anthropic module
pub const PkceParams = struct {
    code_verifier: []const u8,
    code_challenge: []const u8,
    state: []const u8,

    /// Clean up allocated memory
    pub fn deinit(self: PkceParams, allocator: std.mem.Allocator) void {
        allocator.free(self.code_verifier);
        allocator.free(self.code_challenge);
        allocator.free(self.state);
    }
};

/// OAuth provider configuration
pub const OAuthProvider = struct {
    client_id: []const u8,
    authorization_url: []const u8,
    token_url: []const u8,
    redirect_uri: []const u8,
    scopes: []const []const u8,

    /// Build authorization URL with PKCE parameters
    pub fn buildAuthUrl(self: OAuthProvider, allocator: std.mem.Allocator, pkce_params: PkceParams) ![]u8 {
        const scopes_joined = try std.mem.join(allocator, " ", self.scopes);
        defer allocator.free(scopes_joined);

        return try std.fmt.allocPrint(allocator, "{s}?client_id={s}&response_type=code&redirect_uri={s}&scope={s}&code_challenge={s}&code_challenge_method=S256&state={s}", .{
            self.authorization_url,
            self.client_id,
            self.redirect_uri,
            scopes_joined,
            pkce_params.code_challenge,
            pkce_params.state,
        });
    }
};

// Delegate to anthropic module functions to avoid duplication and module conflicts
// Note: These functions will be implemented as pass-through to the anthropic module

/// Generate PKCE parameters - delegates to anthropic module
pub fn generatePkceParams(allocator: std.mem.Allocator) !PkceParams {
    const anthropic = @import("anthropic_shared");

    const anthropic_pkce = try anthropic.generatePkceParams(allocator);

    // Convert to our format (structures should be compatible)
    return PkceParams{
        .code_verifier = anthropic_pkce.code_verifier,
        .code_challenge = anthropic_pkce.code_challenge,
        .state = anthropic_pkce.state,
    };
}

/// Build OAuth authorization URL
pub fn buildAuthorizationUrl(allocator: std.mem.Allocator, pkce_params: PkceParams) ![]u8 {
    const scopes = [_][]const u8{ "org:create_api_key", "user:profile", "user:inference" };
    const provider = OAuthProvider{
        .client_id = OAUTH_CLIENT_ID,
        .authorization_url = OAUTH_AUTHORIZATION_URL,
        .token_url = OAUTH_TOKEN_ENDPOINT,
        .redirect_uri = OAUTH_REDIRECT_URI,
        .scopes = &scopes,
    };

    return try provider.buildAuthUrl(allocator, pkce_params);
}

/// Exchange authorization code for tokens - delegates to anthropic module
pub fn exchangeCodeForTokens(allocator: std.mem.Allocator, authorization_code: []const u8, pkce_params: PkceParams) !OAuthCredentials {
    const anthropic = @import("anthropic_shared");

    // Convert our PKCE params to anthropic format
    const anthropic_pkce = anthropic.PkceParams{
        .code_verifier = pkce_params.code_verifier,
        .code_challenge = pkce_params.code_challenge,
        .state = pkce_params.state,
    };

    const anthropic_creds = try anthropic.exchangeCodeForTokens(allocator, authorization_code, anthropic_pkce);

    // Convert anthropic credentials to our format (should be compatible)
    return OAuthCredentials{
        .type = anthropic_creds.type,
        .access_token = anthropic_creds.access_token,
        .refresh_token = anthropic_creds.refresh_token,
        .expires_at = anthropic_creds.expires_at,
    };
}

pub fn refreshTokens(allocator: std.mem.Allocator, refresh_token: []const u8) !OAuthCredentials {
    const anthropic = @import("anthropic_shared");

    const anthropic_creds = try anthropic.refreshTokens(allocator, refresh_token);

    // Convert anthropic credentials to our format (should be compatible)
    return OAuthCredentials{
        .type = anthropic_creds.type,
        .access_token = anthropic_creds.access_token,
        .refresh_token = anthropic_creds.refresh_token,
        .expires_at = anthropic_creds.expires_at,
    };
}

pub fn parseCredentials(allocator: std.mem.Allocator, json_content: []const u8) !OAuthCredentials {
    const parsed = try std.json.parseFromSlice(OAuthCredentials, allocator, json_content, .{});
    defer parsed.deinit();

    return OAuthCredentials{
        .type = try allocator.dupe(u8, parsed.value.type),
        .access_token = try allocator.dupe(u8, parsed.value.access_token),
        .refresh_token = try allocator.dupe(u8, parsed.value.refresh_token),
        .expires_at = parsed.value.expires_at,
    };
}

pub fn saveCredentials(allocator: std.mem.Allocator, file_path: []const u8, creds: OAuthCredentials) !void {
    const json_content = try std.fmt.allocPrint(allocator, "{{\"type\":\"{s}\",\"access_token\":\"{s}\",\"refresh_token\":\"{s}\",\"expires_at\":{}}}", .{ creds.type, creds.access_token, creds.refresh_token, creds.expires_at });
    defer allocator.free(json_content);

    const file = try std.fs.cwd().createFile(file_path, .{ .mode = 0o600 });
    defer file.close();

    try file.writeAll(json_content);
}

pub fn launchBrowser(url: []const u8) !void {
    const allocator = std.heap.page_allocator;

    switch (@import("builtin").os.tag) {
        .macos => {
            const argv = [_][]const u8{ "open", url };
            _ = try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &argv,
            });
        },
        .linux => {
            const argv = [_][]const u8{ "xdg-open", url };
            _ = try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &argv,
            });
        },
        .windows => {
            const argv = [_][]const u8{ "cmd", "/c", "start", url };
            _ = try std.process.Child.run(.{
                .allocator = allocator,
                .argv = &argv,
            });
        },
        else => {
            std.log.warn("Unsupported platform for browser launching. Please manually open: {s}", .{url});
        },
    }
}

/// High-level OAuth setup function - simplified implementation without TUI
pub fn setupOAuth(allocator: std.mem.Allocator) !OAuthCredentials {
    std.log.info("🔐 Starting OAuth setup...", .{});
    
    // Generate PKCE parameters
    const pkce_params = try generatePkceParams(allocator);
    defer pkce_params.deinit(allocator);
    
    // Build authorization URL
    const auth_url = try buildAuthorizationUrl(allocator, pkce_params);
    defer allocator.free(auth_url);
    
    std.log.info("Please visit this URL to authorize the application:", .{});
    std.log.info("{s}", .{auth_url});
    
    // Try to launch browser
    launchBrowser(auth_url) catch {
        std.log.warn("Could not launch browser automatically. Please copy and paste the URL above.", .{});
    };
    
    std.log.info("After authorization, you'll be redirected to a URL containing the authorization code.", .{});
    std.log.info("Enter the authorization code from the redirect URL:");
    
    // Read authorization code from stdin
    const stdin = std.fs.File.stdin();
    var buffer: [1024]u8 = undefined;
    const bytes_read = try stdin.readAll(buffer[0..]);
    if (bytes_read == 0) {
        return OAuthError.AuthError;
    }
    
    const auth_code = std.mem.trim(u8, buffer[0..bytes_read], " \t\r\n");
    
    // Exchange code for tokens
    const credentials = try exchangeCodeForTokens(allocator, auth_code, pkce_params);
    
    // Save credentials
    try saveCredentials(allocator, "claude_oauth_creds.json", credentials);
    
    std.log.info("✅ OAuth setup completed successfully!", .{});
    
    return credentials;
}

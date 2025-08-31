//! Stub network module for minimal builds without network support.
//! Provides empty types and no-op functions to satisfy compile-time dependencies.

const std = @import("std");

/// Stub auth types
pub const AuthMethod = enum { none };
pub const Credentials = struct {};
pub const AuthError = error{NotSupported};

/// Stub OAuth types
pub const OAuth = struct {
    pub fn setupOAuth(allocator: std.mem.Allocator) AuthError!void {
        _ = allocator;
        return AuthError.NotSupported;
    }

    pub fn refreshTokens(allocator: std.mem.Allocator) AuthError!void {
        _ = allocator;
        return AuthError.NotSupported;
    }
};

/// Stub HTTP types
pub const Http = struct {
    pub const Error = error{NotSupported};
    pub const Method = enum { GET };
    pub const Response = struct {
        status: u16 = 501,
        body: []const u8 = "Network support not compiled in",
    };
};

/// Stub SSE types
pub const SSE = struct {
    pub const Event = struct {
        data: []const u8 = "",
    };
};

/// Stub provider access
pub const Anthropic = struct {};

/// Stub auth namespace
pub const Auth = struct {
    pub const Core = struct {
        pub const AuthMethod = AuthMethod;
        pub const Credentials = Credentials;
        pub const AuthError = AuthError;
    };
    pub const OAuth = OAuth;
    pub const setupOAuth = OAuth.setupOAuth;
    pub const refreshTokens = OAuth.refreshTokens;
};

/// Check if network is available
pub fn isAvailable() bool {
    return false;
}

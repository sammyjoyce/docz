//! Unified authentication error handling
//! Layer: network (standalone)

const std = @import("std");
const Http = @import("../Http.zig");

pub const AuthError = error{
    InvalidCredentials,
    TokenExpired,
    RefreshFailed,
    NetworkError,
    ServerError,
    RateLimited,
    InvalidScope,
    InvalidGrant,
    InvalidClient,
    InvalidRequest,
    UnauthorizedClient,
    UnsupportedResponseType,
    AccessDenied,
    ServerBusy,
    TemporarilyUnavailable,
    OutOfMemory,
    ConfigurationError,
    CallbackServerError,
    BrowserOpenFailed,
    UserCanceled,
};

/// Convert HTTP errors to auth errors
pub fn fromNetwork(err: Http.Error) AuthError {
    return switch (err) {
        Http.Error.Transport, Http.Error.Timeout => AuthError.NetworkError,
        Http.Error.Status => AuthError.ServerError,
        Http.Error.OutOfMemory => AuthError.OutOfMemory,
        Http.Error.Canceled => AuthError.UserCanceled,
        else => AuthError.NetworkError,
    };
}

/// Convert auth errors to HTTP errors
pub fn asNetwork(err: AuthError) Http.Error {
    return switch (err) {
        AuthError.NetworkError => Http.Error.Transport,
        AuthError.ServerError, AuthError.ServerBusy => Http.Error.Status,
        AuthError.OutOfMemory => Http.Error.OutOfMemory,
        AuthError.UserCanceled => Http.Error.Canceled,
        else => Http.Error.Status,
    };
}

/// Parse OAuth error response
pub fn parseOAuthError(json_str: []const u8) ?AuthError {
    const parsed = std.json.parseFromSlice(
        struct {
            @"error": []const u8,
            error_description: ?[]const u8 = null,
        },
        std.heap.page_allocator,
        json_str,
        .{ .ignore_unknown_fields = true },
    ) catch return null;
    defer parsed.deinit();

    const err_code = parsed.value.@"error";

    if (std.mem.eql(u8, err_code, "invalid_request")) return AuthError.InvalidRequest;
    if (std.mem.eql(u8, err_code, "invalid_client")) return AuthError.InvalidClient;
    if (std.mem.eql(u8, err_code, "invalid_grant")) return AuthError.InvalidGrant;
    if (std.mem.eql(u8, err_code, "unauthorized_client")) return AuthError.UnauthorizedClient;
    if (std.mem.eql(u8, err_code, "unsupported_response_type")) return AuthError.UnsupportedResponseType;
    if (std.mem.eql(u8, err_code, "invalid_scope")) return AuthError.InvalidScope;
    if (std.mem.eql(u8, err_code, "access_denied")) return AuthError.AccessDenied;
    if (std.mem.eql(u8, err_code, "temporarily_unavailable")) return AuthError.TemporarilyUnavailable;
    if (std.mem.eql(u8, err_code, "server_error")) return AuthError.ServerError;

    return AuthError.ServerError;
}

test "error conversions" {
    const testing = std.testing;

    // Test network to auth conversion
    try testing.expectEqual(AuthError.NetworkError, fromNetwork(Http.Error.Transport));
    try testing.expectEqual(AuthError.ServerError, fromNetwork(Http.Error.Status));

    // Test auth to network conversion
    try testing.expectEqual(Http.Error.Transport, asNetwork(AuthError.NetworkError));
    try testing.expectEqual(Http.Error.Status, asNetwork(AuthError.ServerError));
}

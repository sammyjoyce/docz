//! AuthPort: UI-neutral authentication interface (no network imports)
//!
//! TUI/UI consume this port; engine/services provide an implementation.

const std = @import("std");

pub const Allocator = std.mem.Allocator;

pub const Error = error{
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

pub const OauthTokens = struct {
    access_token: []const u8,
    refresh_token: []const u8,
    expires_at: i64,

    pub fn isExpired(self: OauthTokens) bool {
        return std.time.timestamp() >= self.expires_at;
    }
    pub fn willExpireSoon(self: OauthTokens, leeway_secs: i64) bool {
        return std.time.timestamp() >= self.expires_at - leeway_secs;
    }
};

pub const Credentials = union(enum) {
    api_key: []const u8,
    oauth: OauthTokens,
    none: void,

    pub fn isValid(self: Credentials) bool {
        return switch (self) {
            .api_key => |k| k.len > 0,
            .oauth => |t| !t.isExpired(),
            .none => false,
        };
    }
    pub fn deinit(self: Credentials, allocator: Allocator) void {
        switch (self) {
            .api_key => |k| allocator.free(k),
            .oauth => |t| {
                allocator.free(t.access_token);
                allocator.free(t.refresh_token);
            },
            .none => {},
        }
    }
};

pub const OAuthSession = struct {
    url: []u8,
    pkce_verifier: []u8,
    pub fn deinit(self: OAuthSession, allocator: Allocator) void {
        allocator.free(self.url);
        allocator.free(self.pkce_verifier);
    }
};

pub const AuthPort = struct {
    const Self = @This();
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        load: *const fn (ctx: *anyopaque, allocator: Allocator) Error!Credentials,
        save: *const fn (ctx: *anyopaque, allocator: Allocator, creds: Credentials) Error!void,
        start_oauth: *const fn (ctx: *anyopaque, allocator: Allocator) Error!OAuthSession,
        complete_oauth: *const fn (ctx: *anyopaque, allocator: Allocator, code: []const u8, pkce_verifier: []const u8) Error!Credentials,
        refresh_if_needed: *const fn (ctx: *anyopaque, allocator: Allocator, creds: Credentials) Error!Credentials,
        auth_header: *const fn (ctx: *anyopaque, allocator: Allocator, creds: Credentials) Error!?[]u8,
    };

    pub fn load(self: Self, allocator: Allocator) Error!Credentials {
        return self.vtable.load(self.ctx, allocator);
    }
    pub fn save(self: Self, allocator: Allocator, creds: Credentials) Error!void {
        return self.vtable.save(self.ctx, allocator, creds);
    }
    pub fn startOAuth(self: Self, allocator: Allocator) Error!OAuthSession {
        return self.vtable.start_oauth(self.ctx, allocator);
    }
    pub fn completeOAuth(self: Self, allocator: Allocator, code: []const u8, pkce_verifier: []const u8) Error!Credentials {
        return self.vtable.complete_oauth(self.ctx, allocator, code, pkce_verifier);
    }
    pub fn refreshIfNeeded(self: Self, allocator: Allocator, creds: Credentials) Error!Credentials {
        return self.vtable.refresh_if_needed(self.ctx, allocator, creds);
    }
    pub fn authHeader(self: Self, allocator: Allocator, creds: Credentials) Error!?[]u8 {
        return self.vtable.auth_header(self.ctx, allocator, creds);
    }
};

// Null / no-op implementation (for tests or headless UIs)
pub const NullAuth = struct {
    fn load(_: *anyopaque, _: Allocator) Error!Credentials {
        return Error.MissingAPIKey;
    }
    fn save(_: *anyopaque, _: Allocator, _: Credentials) Error!void {
        return Error.InvalidFormat;
    }
    fn start(_: *anyopaque, _: Allocator) Error!OAuthSession {
        return Error.InvalidGrant;
    }
    fn complete(_: *anyopaque, _: Allocator, _: []const u8, _: []const u8) Error!Credentials {
        return Error.InvalidGrant;
    }
    fn refresh(_: *anyopaque, _: Allocator, creds: Credentials) Error!Credentials {
        return creds;
    }
    fn header(_: *anyopaque, _: Allocator, _: Credentials) Error!?[]u8 {
        return null;
    }
};

const NULL_VTABLE = AuthPort.VTable{
    .load = NullAuth.load,
    .save = NullAuth.save,
    .start_oauth = NullAuth.start,
    .complete_oauth = NullAuth.complete,
    .refresh_if_needed = NullAuth.refresh,
    .auth_header = NullAuth.header,
};

pub fn nullAuthPort() AuthPort {
    return .{ .ctx = undefined, .vtable = &NULL_VTABLE };
}

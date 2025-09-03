//! Mock AuthPort adapter for headless tests

const std = @import("std");
const ports = @import("../ports/auth.zig");

const Allocator = std.mem.Allocator;

pub const Config = struct {
    mode: enum { api_key, oauth } = .oauth,
    api_key: []const u8 = "test_api_key_123",
    access_token: []const u8 = "mock_access",
    refresh_token: []const u8 = "mock_refresh",
    ttl_secs: i64 = 3600,
};

const Ctx = struct { cfg: Config };

fn load(ctx: *anyopaque, allocator: Allocator) ports.Error!ports.Credentials {
    const c: *const Ctx = @ptrCast(@alignCast(ctx));
    return switch (c.cfg.mode) {
        .api_key => ports.Credentials{ .api_key = try allocator.dupe(u8, c.cfg.api_key) },
        .oauth => ports.Credentials{ .oauth = .{
            .access_token = try allocator.dupe(u8, c.cfg.access_token),
            .refresh_token = try allocator.dupe(u8, c.cfg.refresh_token),
            .expires_at = std.time.timestamp() + c.cfg.ttl_secs,
        } },
    };
}

fn save(_: *anyopaque, _: Allocator, _: ports.Credentials) ports.Error!void {
    return; // no-op
}

fn start_oauth(ctx: *anyopaque, allocator: Allocator) ports.Error!ports.OAuthSession {
    const c: *const Ctx = @ptrCast(@alignCast(ctx));
    _ = c;
    return ports.OAuthSession{
        .url = try allocator.dupe(u8, "http://localhost/mock_oauth"),
        .pkce_verifier = try allocator.dupe(u8, "mock_pkce"),
    };
}

fn complete_oauth(ctx: *anyopaque, allocator: Allocator, _: []const u8, _: []const u8) ports.Error!ports.Credentials {
    const c: *const Ctx = @ptrCast(@alignCast(ctx));
    return ports.Credentials{ .oauth = .{
        .access_token = try allocator.dupe(u8, c.cfg.access_token),
        .refresh_token = try allocator.dupe(u8, c.cfg.refresh_token),
        .expires_at = std.time.timestamp() + c.cfg.ttl_secs,
    } };
}

fn refresh_if_needed(ctx: *anyopaque, allocator: Allocator, creds: ports.Credentials) ports.Error!ports.Credentials {
    const c: *const Ctx = @ptrCast(@alignCast(ctx));
    return switch (creds) {
        .oauth => |t| if (t.willExpireSoon(60)) ports.Credentials{ .oauth = .{
            .access_token = try allocator.dupe(u8, c.cfg.access_token),
            .refresh_token = try allocator.dupe(u8, c.cfg.refresh_token),
            .expires_at = std.time.timestamp() + c.cfg.ttl_secs,
        } } else creds,
        else => creds,
    };
}

fn auth_header(_: *anyopaque, allocator: Allocator, creds: ports.Credentials) ports.Error!?[]u8 {
    return switch (creds) {
        .api_key => |k| try std.fmt.allocPrint(allocator, "x-api-key: {s}", .{k}),
        .oauth => |t| if (!t.isExpired()) try std.fmt.allocPrint(allocator, "Bearer {s}", .{t.access_token}) else null,
        .none => null,
    };
}

const VTABLE = ports.AuthPort.VTable{
    .load = load,
    .save = save,
    .start_oauth = start_oauth,
    .complete_oauth = complete_oauth,
    .refresh_if_needed = refresh_if_needed,
    .auth_header = auth_header,
};

pub fn make(cfg: Config) ports.AuthPort {
    // Static context to simplify lifetimes in tests
    const ctx: *const Ctx = &_CTX;
    _CTX = .{ .cfg = cfg };
    return .{ .ctx = @ptrCast(@constCast(ctx)), .vtable = &VTABLE };
}

var _CTX: Ctx = .{ .cfg = .{} };


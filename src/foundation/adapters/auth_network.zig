//! Default adapter: implements ports.auth.AuthPort using foundation.network

const std = @import("std");
const Allocator = std.mem.Allocator;

const ports = @import("../ports/auth.zig");
const network = @import("../network.zig");

const Service = network.Auth.Service;
const OAuth = network.Auth.OAuth;
const pkce = network.Auth.pkce;

const Self = struct {
    // placeholder for future state
};

fn load(ctx: *anyopaque, allocator: Allocator) ports.Error!ports.Credentials {
    _ = ctx;
    const svc = Service.init(allocator);
    const creds = try svc.loadCredentials();
    return convertToPort(allocator, creds);
}

fn save(ctx: *anyopaque, allocator: Allocator, creds: ports.Credentials) ports.Error!void {
    _ = ctx;
    switch (creds) {
        .oauth => {
            // Persist OAuth credentials using network layer
            const converted = try convertFromPort(allocator, creds);
            defer converted.deinit(allocator);
            try Service.init(allocator).saveCredentials(converted);
        },
        .api_key => |k| {
            // Write API key to default path for compatibility
            var file = try std.fs.cwd().createFile("claude_api_key.txt", .{ .truncate = true });
            defer file.close();
            try file.writeAll(k);
        },
        .none => return ports.Error.InvalidCredentials,
    }
}

fn start_oauth(ctx: *anyopaque, allocator: Allocator) ports.Error!ports.OAuthSession {
    _ = ctx;
    var params = try pkce.generatePkceParams(allocator);
    errdefer params.deinit(allocator);

    const provider = OAuth.Provider{
        .clientId = OAuth.OAUTH_CLIENT_ID,
        .authorizationUrl = OAuth.OAUTH_AUTHORIZATION_URL,
        .tokenUrl = OAuth.OAUTH_TOKEN_ENDPOINT,
        .redirectUri = OAuth.OAUTH_REDIRECT_URI,
        .scopes = &[_][]const u8{OAuth.OAUTH_SCOPES},
    };

    const url = try provider.buildAuthorizationUrl(allocator, params);
    const verifier = try allocator.dupe(u8, params.verifier);
    return ports.OAuthSession{ .url = url, .pkce_verifier = verifier };
}

fn complete_oauth(ctx: *anyopaque, allocator: Allocator, code: []const u8, pkce_verifier: []const u8) ports.Error!ports.Credentials {
    _ = ctx;
    const creds = try OAuth.exchangeCodeForTokens(allocator, code, pkce_verifier);
    return convertToPort(allocator, .{ .oauth = creds });
}

fn refresh_if_needed(ctx: *anyopaque, allocator: Allocator, creds: ports.Credentials) ports.Error!ports.Credentials {
    _ = ctx;
    switch (creds) {
        .oauth => |t| {
            if (t.willExpireSoon(300)) {
                const new_creds = try OAuth.refreshTokens(allocator, t.refresh_token);
                return convertToPort(allocator, .{ .oauth = new_creds });
            }
            return creds;
        },
        else => return creds,
    }
}

fn auth_header(ctx: *anyopaque, allocator: Allocator, creds: ports.Credentials) ports.Error!?[]u8 {
    _ = ctx;
    return switch (creds) {
        .api_key => |k| try std.fmt.allocPrint(allocator, "x-api-key: {s}", .{k}),
        .oauth => |t| if (!t.isExpired()) try std.fmt.allocPrint(allocator, "Bearer {s}", .{t.access_token}) else null,
        .none => null,
    };
}

fn convertToPort(allocator: Allocator, c: Service.Credentials) !ports.Credentials {
    return switch (c) {
        .api_key => |k| ports.Credentials{ .api_key = try allocator.dupe(u8, k) },
        .oauth => |o| ports.Credentials{ .oauth = .{
            .access_token = try allocator.dupe(u8, o.accessToken),
            .refresh_token = try allocator.dupe(u8, o.refreshToken),
            .expires_at = o.expiresAt,
        } },
        .none => .{ .none = {} },
    };
}

fn convertFromPort(allocator: Allocator, c: ports.Credentials) !Service.Credentials {
    return switch (c) {
        .api_key => |k| Service.Credentials{ .api_key = try allocator.dupe(u8, k) },
        .oauth => |o| Service.Credentials{ .oauth = .{
            .type = try allocator.dupe(u8, "oauth"),
            .accessToken = try allocator.dupe(u8, o.access_token),
            .refreshToken = try allocator.dupe(u8, o.refresh_token),
            .expiresAt = o.expires_at,
        } },
        .none => .{ .none = {} },
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

pub fn make() ports.AuthPort {
    return .{ .ctx = @ptrCast(@constCast(&Self{})), .vtable = &VTABLE };
}

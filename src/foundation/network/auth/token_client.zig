//! OAuth token exchange and refresh client

const std = @import("std");
const http = std.http;
const json = std.json;
const Uri = std.Uri;

const log = std.log.scoped(.oauth_token);

/// Token endpoint response
pub const TokenResponse = struct {
    access_token: []const u8,
    refresh_token: []const u8,
    expires_in: i64,
    token_type: []const u8,

    pub fn deinit(self: TokenResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.access_token);
        allocator.free(self.refresh_token);
        allocator.free(self.token_type);
    }
};

/// Token client configuration
pub const TokenClientConfig = struct {
    client_id: []const u8,
    token_endpoint: []const u8 = "https://console.anthropic.com/v1/oauth/token",
    timeout_ms: u32 = 30000,
};

/// OAuth token client for exchange and refresh
pub const TokenClient = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: TokenClientConfig,
    client: http.Client,

    pub fn init(allocator: std.mem.Allocator, config: TokenClientConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .client = http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
    }

    /// Exchange authorization code for tokens
    pub fn exchangeCode(
        self: *Self,
        code: []const u8,
        code_verifier: []const u8,
        redirect_uri: []const u8,
    ) !TokenResponse {
        const body = try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "grant_type": "authorization_code",
            \\  "code": "{s}",
            \\  "code_verifier": "{s}",
            \\  "client_id": "{s}",
            \\  "redirect_uri": "{s}"
            \\}}
        , .{ code, code_verifier, self.config.client_id, redirect_uri });
        defer self.allocator.free(body);

        log.info("Exchanging authorization code for tokens", .{});
        return self.makeTokenRequest(body);
    }

    /// Refresh access token using refresh token
    pub fn refreshToken(self: *Self, refresh_token: []const u8) !TokenResponse {
        const body = try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "grant_type": "refresh_token",
            \\  "refresh_token": "{s}",
            \\  "client_id": "{s}"
            \\}}
        , .{ refresh_token, self.config.client_id });
        defer self.allocator.free(body);

        log.info("Refreshing access token", .{});
        return self.makeTokenRequest(body);
    }

    fn makeTokenRequest(self: *Self, body: []const u8) !TokenResponse {
        const uri = try Uri.parse(self.config.token_endpoint);

        var req = try self.client.open(.POST, uri, .{
            .server_header_buffer = &[_]u8{},
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/json" },
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "User-Agent", .value = "docz/1.0" },
            },
        });
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = body.len };
        log.debug("Content-Type: application/json", .{});
        log.debug("Request body: {s}", .{body});
        try req.send();
        try req.writeAll(body);
        try req.finish();

        try req.wait();

        if (req.response.status != .ok) {
            const error_body = try req.reader().readAllAlloc(self.allocator, 1024 * 1024);
            defer self.allocator.free(error_body);

            log.err("Token request failed with status {}: {s}", .{ req.response.status, error_body });

            // Parse error response for specific error codes
            if (std.mem.indexOf(u8, error_body, "invalid_grant") != null) {
                return error.InvalidGrant;
            }
            return error.TokenRequestFailed;
        }

        const response_body = try req.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(response_body);

        const parsed = try json.parseFromSlice(TokenResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        // Duplicate strings for caller ownership
        return TokenResponse{
            .access_token = try self.allocator.dupe(u8, parsed.value.access_token),
            .refresh_token = try self.allocator.dupe(u8, parsed.value.refresh_token),
            .expires_in = parsed.value.expires_in,
            .token_type = try self.allocator.dupe(u8, parsed.value.token_type),
        };
    }
};

/// Build authorization URL with PKCE parameters
pub fn buildAuthorizationUrl(
    allocator: std.mem.Allocator,
    auth_endpoint: []const u8,
    client_id: []const u8,
    redirect_uri: []const u8,
    scopes: []const u8,
    code_challenge: []const u8,
    state: []const u8,
) ![]u8 {
    // URL encode parameters
    const client_id_enc = try urlEncode(allocator, client_id);
    defer allocator.free(client_id_enc);

    const redirect_enc = try urlEncode(allocator, redirect_uri);
    defer allocator.free(redirect_enc);

    const scopes_enc = try urlEncode(allocator, scopes);
    defer allocator.free(scopes_enc);

    const challenge_enc = try urlEncode(allocator, code_challenge);
    defer allocator.free(challenge_enc);

    const state_enc = try urlEncode(allocator, state);
    defer allocator.free(state_enc);

    return std.fmt.allocPrint(allocator, "{s}?client_id={s}&response_type=code&redirect_uri={s}&scope={s}&code_challenge={s}&code_challenge_method=S256&state={s}", .{ auth_endpoint, client_id_enc, redirect_enc, scopes_enc, challenge_enc, state_enc });
}

/// URL encode a string per RFC 3986
fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (input) |c| {
        if ((c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '_' or c == '.' or c == '~')
        {
            try result.append(c);
        } else {
            try result.writer().print("%{X:0>2}", .{c});
        }
    }

    return result.toOwnedSlice();
}

test "url encoding" {
    const allocator = std.testing.allocator;

    const input = "hello world!@#";
    const encoded = try urlEncode(allocator, input);
    defer allocator.free(encoded);

    try std.testing.expectEqualStrings("hello%20world%21%40%23", encoded);
}

test "build authorization url" {
    const allocator = std.testing.allocator;

    const url = try buildAuthorizationUrl(
        allocator,
        "https://example.com/authorize",
        "client123",
        "http://localhost:8080/callback",
        "read write",
        "challenge123",
        "state456",
    );
    defer allocator.free(url);

    try std.testing.expect(std.mem.indexOf(u8, url, "client_id=client123") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "response_type=code") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge=challenge123") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge_method=S256") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "state=state456") != null);
}

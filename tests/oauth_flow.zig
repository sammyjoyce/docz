const std = @import("std");
const foundation = @import("foundation");

test "pkce generator: lengths, url-safety, and distinct state" {
    const a = std.testing.allocator;
    const oauth = foundation.network.Auth.OAuth;
    const pk = try oauth.generatePkceParams(a);
    defer pk.deinit(a);

    try std.testing.expect(pk.codeVerifier.len >= 43 and pk.codeVerifier.len <= 128);
    // URL-safe base64 (no '=')
    for (pk.codeChallenge) |c| {
        const ok = (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-' or c == '_';
        try std.testing.expect(ok);
    }
    // Ensure state is independent from verifier
    try std.testing.expect(!std.mem.eql(u8, pk.state, pk.codeVerifier));
}

test "authorization URL encodes redirect_uri and includes PKCE params" {
    const a = std.testing.allocator;
    const oauth = foundation.network.Auth.OAuth;

    const pk = try oauth.generatePkceParams(a);
    defer pk.deinit(a);

    const scopes = [_][]const u8{ "org:create_api_key", "user:profile", "user:inference" };
    const provider = oauth.Provider{
        .clientId = oauth.OAUTH_CLIENT_ID,
        .authorizationUrl = oauth.OAUTH_AUTHORIZATION_URL,
        .tokenUrl = oauth.OAUTH_TOKEN_ENDPOINT,
        .redirectUri = "http://localhost:8080/callback",
        .scopes = &scopes,
    };
    const url = try provider.buildAuthorizationUrl(a, pk);
    defer a.free(url);

    try std.testing.expect(std.mem.indexOf(u8, url, "response_type=code") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "client_id=") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "redirect_uri=http%3A%2F%2Flocalhost%3A8080%2Fcallback") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge=") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge_method=S256") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "state=") != null);
}

test "callback parser enforces /callback and returns code+state" {
    const a = std.testing.allocator;
    const cb = foundation.network.Auth.Callback;
    var server = try cb.Server.init(a, .{});
    defer server.deinit();

    const req = "GET /callback?code=abc123&state=xyz HTTP/1.1\r\nHost: localhost\r\n\r\n";
    const res = try server.parseCallbackRequest(req);
    defer res.deinit(a);
    try std.testing.expectEqualStrings("abc123", res.code);
    try std.testing.expectEqualStrings("xyz", res.state);
}

test "OAuth headers are Bearer (no x-api-key) and beta is present" {
    const a = std.testing.allocator;
    const anth = foundation.network.Anthropic;

    const creds = anth.Models.Credentials{ .type = "oauth", .accessToken = "tkn", .refreshToken = "rfr", .expiresAt = 9999999999 };
    var client = try anth.Client.Client.initWithOAuth(a, creds, null);
    defer client.deinit();
    // Check single auth header utility
    const h = try client.getAuthHeader(a);
    defer a.free(h.value);
    try std.testing.expectEqualStrings("Authorization", h.name);
    try std.testing.expectEqualStrings("Bearer tkn", h.value);

    // Check full header composition (non-streaming)
    const headers = try client.buildHeadersForTest(a, false);
    defer {
        var i: usize = 0;
        while (i < headers.len) : (i += 1) {
            // Only values are heap allocated in helper
            a.free(headers[i].value);
        }
        a.free(headers);
    }
    var saw_auth = false;
    var saw_version = false;
    var saw_beta = false;
    var saw_x_api = false;
    for (headers) |hdr| {
        if (std.ascii.eqlIgnoreCase(hdr.name, "authorization")) {
            saw_auth = true;
            try std.testing.expectEqualStrings("Bearer tkn", hdr.value);
        }
        if (std.ascii.eqlIgnoreCase(hdr.name, "anthropic-version")) {
            saw_version = true;
            try std.testing.expectEqualStrings("2023-06-01", hdr.value);
        }
        if (std.ascii.eqlIgnoreCase(hdr.name, "anthropic-beta")) {
            saw_beta = true;
            try std.testing.expectEqualStrings("oauth-2025-04-20", hdr.value);
        }
        if (std.ascii.eqlIgnoreCase(hdr.name, "x-api-key")) saw_x_api = true;
    }
    try std.testing.expect(saw_auth);
    try std.testing.expect(saw_version);
    try std.testing.expect(saw_beta);
    try std.testing.expect(!saw_x_api);
}

test "Streaming headers set accept to text/event-stream" {
    const a = std.testing.allocator;
    const anth = foundation.network.Anthropic;
    const creds = anth.Models.Credentials{ .type = "oauth", .accessToken = "tok", .refreshToken = "ref", .expiresAt = 0 };
    var c = try anth.Client.Client.initWithOAuth(a, creds, null);
    defer c.deinit();
    const hdrs = try c.buildHeadersForTest(a, true);
    defer {
        for (hdrs) |h| a.free(h.value);
        a.free(hdrs);
    }
    var saw_accept = false;
    var accept_ok = false;
    for (hdrs) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "accept")) {
            saw_accept = true;
            accept_ok = std.ascii.eqlIgnoreCase(h.value, "text/event-stream");
        }
    }
    try std.testing.expect(saw_accept);
    try std.testing.expect(accept_ok);
}

//! OAuth helpers for Anthropic client

const std = @import("std");
const curl = @import("curl_shared");
const models = @import("models.zig");

pub const oauthClientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
pub const oauthAuthorizationUrl = "https://claude.ai/oauth/authorize";
pub const oauthTokenEndpoint = "https://console.anthropic.com/v1/oauth/token";
pub const oauthRedirectUri = "https://console.anthropic.com/oauth/code/callback";
pub const oauthScopes = "org:create_api_key user:profile user:inference";

const Credentials = models.Credentials;
const Pkce = models.Pkce;
const Error = models.Error;

pub fn exchangeCodeForTokens(allocator: std.mem.Allocator, authorizationCode: []const u8, pkceParams: Pkce) !Credentials {
    std.log.info("🔄 Exchanging authorization code for OAuth tokens...", .{});

    var client = curl.HTTPClient.init(allocator) catch |err| {
        std.log.err("Failed to initialize HTTP client: {}", .{err});
        return Error.NetworkError;
    };
    defer client.deinit();

    var codeParts = std.mem.splitSequence(u8, authorizationCode, "#");
    const code = codeParts.next() orelse authorizationCode;
    const state = codeParts.next() orelse "";

    const body = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "code": "{s}",
        \\  "state": "{s}",
        \\  "grant_type": "authorization_code",
        \\  "client_id": "{s}",
        \\  "redirect_uri": "{s}",
        \\  "code_verifier": "{s}"
        \\}}
    , .{ code, state, oauthClientId, oauthRedirectUri, pkceParams.codeVerifier });
    defer allocator.free(body);

    std.log.debug("Sending OAuth token request with JSON body: {s}", .{body});

    const headers = [_]curl.Header{
        .{ .name = "content-type", .value = "application/json" },
        .{ .name = "accept", .value = "application/json" },
        .{ .name = "user-agent", .value = "docz/1.0 (libcurl)" },
    };

    const req = curl.HTTPRequest{
        .method = .POST,
        .url = oauthTokenEndpoint,
        .headers = &headers,
        .body = body,
        .timeout_ms = 30000,
        .verify_ssl = true,
        .follow_redirects = false,
        .verbose = false,
    };

    var resp = client.request(req) catch |err| {
        std.log.err("❌ Token exchange request failed: {}", .{err});
        switch (err) {
            curl.HTTPError.NetworkError => {
                std.log.err("   Network connection failed", .{});
                std.log.err("   • Check your internet connection", .{});
                std.log.err("   • Check if corporate firewall blocks HTTPS", .{});
            },
            curl.HTTPError.TlsError => {
                std.log.err("   TLS/SSL connection failed", .{});
                std.log.err("   • Certificate validation or security settings issue", .{});
            },
            curl.HTTPError.Timeout => {
                std.log.err("   Request timed out", .{});
                std.log.err("   🔄 Try again - this is often temporary", .{});
            },
            else => {
                std.log.err("   Unexpected error: {}", .{err});
                std.log.err("   🔄 Please try again", .{});
            },
        }
        return Error.NetworkError;
    };
    defer resp.deinit();

    if (resp.status_code != 200) {
        std.log.err("OAuth token exchange failed with status: {}", .{resp.status_code});
        if (resp.status_code >= 400 and resp.status_code < 500) {
            std.log.err("Client error - check OAuth configuration", .{});
        } else if (resp.status_code >= 500) {
            std.log.err("Server error - Anthropic's OAuth service may be unavailable", .{});
        }
        return Error.AuthError;
    }

    const parsed = std.json.parseFromSlice(struct {
        access_token: []const u8,
        refresh_token: []const u8,
        expires_in: i64,
    }, allocator, resp.body, .{}) catch |err| {
        std.log.err("Failed to parse OAuth token response: {}", .{err});
        std.log.debug("Response body: {s}", .{resp.body});
        return Error.AuthError;
    };
    defer parsed.deinit();

    const now = std.time.timestamp();
    const expiresAt = now + parsed.value.expires_in;

    std.log.info("✅ OAuth tokens received successfully!", .{});

    return Credentials{
        .type = try allocator.dupe(u8, "oauth"),
        .accessToken = try allocator.dupe(u8, parsed.value.access_token),
        .refreshToken = try allocator.dupe(u8, parsed.value.refresh_token),
        .expiresAt = expiresAt,
    };
}

pub fn refreshTokens(allocator: std.mem.Allocator, refreshToken: []const u8) !Credentials {
    std.log.info("🔄 Refreshing OAuth tokens...", .{});

    var client = curl.HTTPClient.init(allocator) catch |err| {
        std.log.err("Failed to initialize HTTP client: {}", .{err});
        return Error.NetworkError;
    };
    defer client.deinit();

    const body = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "grant_type": "refresh_token",
        \\  "refresh_token": "{s}",
        \\  "client_id": "{s}"
        \\}}
    , .{ refreshToken, oauthClientId });
    defer allocator.free(body);

    const headers = [_]curl.Header{
        .{ .name = "content-type", .value = "application/json" },
        .{ .name = "accept", .value = "application/json" },
        .{ .name = "user-agent", .value = "docz/1.0 (libcurl)" },
    };

    const req = curl.HTTPRequest{
        .method = .POST,
        .url = oauthTokenEndpoint,
        .headers = &headers,
        .body = body,
        .timeout_ms = 30000,
        .verify_ssl = true,
        .follow_redirects = false,
        .verbose = false,
    };

    var resp = client.request(req) catch |err| {
        std.log.err("❌ Token refresh request failed: {}", .{err});
        switch (err) {
            curl.HTTPError.NetworkError => {
                std.log.err("Connection was reset by Anthropic's OAuth server during token refresh. This can happen due to network issues or server load.", .{});
                std.log.err("Please try again in a few moments.", .{});
            },
            curl.HTTPError.TlsError => {
                std.log.err("TLS connection failed during token refresh.", .{});
                std.log.err("Please check your network settings.", .{});
            },
            curl.HTTPError.Timeout => {
                std.log.err("Token refresh request timed out.", .{});
                std.log.err("🔄 Try again - this is often temporary", .{});
            },
            else => {
                std.log.err("Failed to refresh OAuth tokens: {}", .{err});
            },
        }
        return Error.NetworkError;
    };
    defer resp.deinit();

    if (resp.status_code != 200) {
        std.log.err("OAuth token refresh failed with status: {}", .{resp.status_code});
        return Error.AuthError;
    }

    const parsed = std.json.parseFromSlice(struct {
        access_token: []const u8,
        refresh_token: []const u8,
        expires_in: i64,
    }, allocator, resp.body, .{}) catch |err| {
        std.log.err("Failed to parse OAuth token refresh response: {}", .{err});
        return Error.AuthError;
    };
    defer parsed.deinit();

    const now = std.time.timestamp();
    const expiresAt = now + parsed.value.expires_in;

    std.log.info("✅ OAuth tokens refreshed successfully!", .{});

    return Credentials{
        .type = try allocator.dupe(u8, "oauth"),
        .accessToken = try allocator.dupe(u8, parsed.value.access_token),
        .refreshToken = try allocator.dupe(u8, parsed.value.refresh_token),
        .expiresAt = expiresAt,
    };
}

pub fn loadOAuthCredentials(allocator: std.mem.Allocator, filePath: []const u8) !?Credentials {
    const file = std.fs.cwd().openFile(filePath, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 16 * 1024);
    defer allocator.free(contents);

    const parsed = try std.json.parseFromSlice(struct {
        type: []const u8,
        access_token: []const u8,
        refresh_token: []const u8,
        expires_at: i64,
    }, allocator, contents, .{});
    defer parsed.deinit();

    return Credentials{
        .type = try allocator.dupe(u8, parsed.value.type),
        .accessToken = try allocator.dupe(u8, parsed.value.access_token),
        .refreshToken = try allocator.dupe(u8, parsed.value.refresh_token),
        .expiresAt = parsed.value.expires_at,
    };
}

pub fn saveOAuthCredentials(allocator: std.mem.Allocator, filePath: []const u8, creds: Credentials) !void {
    const jsonContent = try std.fmt.allocPrint(allocator, "{{\"type\":\"{s}\",\"access_token\":\"{s}\",\"refresh_token\":\"{s}\",\"expires_at\":{}}}", .{ creds.type, creds.accessToken, creds.refreshToken, creds.expiresAt });
    defer allocator.free(jsonContent);

    const file = try std.fs.cwd().createFile(filePath, .{ .mode = 0o600 });
    defer file.close();

    try file.writeAll(jsonContent);
}

pub fn extractCodeFromCallbackUrl(allocator: std.mem.Allocator, callbackUrl: []const u8) ![]u8 {
    const url = try std.URI.parse(callbackUrl);

    if (url.query) |queryComponent| {
        const queryStr = switch (queryComponent) {
            .percent_encoded => |str| str,
            .raw => |str| str,
        };
        if (std.mem.indexOf(u8, queryStr, "code=")) |start| {
            const codeStart = start + 5;
            const codeEnd = std.mem.indexOf(u8, queryStr[codeStart..], "&") orelse queryStr.len - codeStart;
            return try allocator.dupe(u8, queryStr[codeStart .. codeStart + codeEnd]);
        }
    }

    if (url.fragment) |fragmentComponent| {
        const fragmentStr = switch (fragmentComponent) {
            .percent_encoded => |str| str,
            .raw => |str| str,
        };
        if (std.mem.indexOf(u8, fragmentStr, "code=")) |start| {
            const codeStart = start + 5;
            const codeEnd = std.mem.indexOf(u8, fragmentStr[codeStart..], "&") orelse fragmentStr.len - codeStart;
            return try allocator.dupe(u8, fragmentStr[codeStart .. codeStart + codeEnd]);
        }
    }

    return Error.AuthError;
}

pub fn launchBrowser(url: []const u8) !void {
    const allocator = std.heap.page_allocator;
    switch (@import("builtin").os.tag) {
        .macos => {
            const argv = [_][]const u8{ "open", url };
            _ = try std.process.Child.run(.{ .allocator = allocator, .argv = &argv });
        },
        .linux => {
            const argv = [_][]const u8{ "xdg-open", url };
            _ = try std.process.Child.run(.{ .allocator = allocator, .argv = &argv });
        },
        .windows => {
            const argv = [_][]const u8{ "cmd", "/c", "start", url };
            _ = try std.process.Child.run(.{ .allocator = allocator, .argv = &argv });
        },
        else => {
            std.log.warn("Unsupported platform for browser launching. Please manually open: {s}", .{url});
        },
    }
}

pub fn waitForOAuthCallback(allocator: std.mem.Allocator, port: u16) ![]const u8 {
    std.log.info("Starting OAuth callback server on port {}...", .{port});

    const address = std.net.Address.parseIp4("127.0.0.1", port) catch |err| {
        std.log.err("Failed to parse callback server address: {}", .{err});
        return Error.InvalidPort;
    };

    var server = address.listen(.{}) catch |err| {
        std.log.err("Failed to start callback server on port {}: {}", .{ port, err });
        return Error.NetworkError;
    };
    defer server.deinit();

    std.log.info("✅ Callback server ready at http://127.0.0.1:{}", .{port});
    std.log.info("🔗 Complete the authorization in your browser...", .{});

    while (true) {
        var connection = server.accept() catch |err| {
            std.log.err("Failed to accept connection: {}", .{err});
            continue;
        };
        defer connection.stream.close();

        var readerBuffer: [8192]u8 = undefined;
        var reader = connection.stream.reader(&readerBuffer);

        const requestLine = reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => {
                std.log.warn("Unexpected end of stream while reading request line", .{});
                continue;
            },
            error.StreamTooLong => {
                std.log.warn("Request line too long", .{});
                continue;
            },
            else => {
                std.log.warn("Error reading request line: {}", .{err});
                continue;
            },
        };

        const requestLineTrimmed = std.mem.trim(u8, requestLine, " \t\r\n");
        var requestParts = std.mem.splitSequence(u8, requestLineTrimmed, " ");
        const method = requestParts.next() orelse {
            sendHTTPError(&connection.stream, 400, "Invalid request format") catch {};
            continue;
        };
        const pathAndQuery = requestParts.next() orelse {
            sendHTTPError(&connection.stream, 400, "Invalid request format") catch {};
            continue;
        };

        if (!std.mem.eql(u8, method, "GET")) {
            sendHTTPError(&connection.stream, 405, "Method not allowed") catch {};
            continue;
        }

        std.log.debug("Received OAuth callback request: GET {s}", .{pathAndQuery});
        const queryStart = std.mem.indexOf(u8, pathAndQuery, "?");
        if (queryStart == null) {
            sendHTTPError(&connection.stream, 400, "No query parameters in OAuth callback") catch {};
            continue;
        }

        const queryString = pathAndQuery[queryStart.? + 1 ..];

        if (std.mem.indexOf(u8, queryString, "error=")) |_| {
            const errorCode = extractQueryParam(queryString, "error") orelse "unknown_error";
            const errorDesc = extractQueryParam(queryString, "error_description");
            sendOAuthErrorResponse(&connection.stream, errorCode, errorDesc) catch {};
            return handleOAuthError(allocator, errorCode, errorDesc);
        }

        if (extractQueryParam(queryString, "code")) |authCode| {
            sendOAuthSuccessResponse(&connection.stream) catch |err| {
                std.log.warn("Failed to send success response to browser: {}", .{err});
            };
            std.log.info("✅ Authorization code received successfully!", .{});
            return allocator.dupe(u8, authCode);
        } else {
            sendHTTPError(&connection.stream, 400, "Authorization code not found in OAuth callback") catch {};
            continue;
        }
    }
}

fn sendHTTPError(stream: *std.net.Stream, statusCode: u16, message: []const u8) !void {
    const statusText = switch (statusCode) {
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        500 => "Internal Server Error",
        else => "Error",
    };
    var responseBuffer: [1024]u8 = undefined;
    var writerBuffer: [1024]u8 = undefined;
    const response = try std.fmt.bufPrint(&responseBuffer, "HTTP/1.1 {} {s}\r\n" ++
        "Content-Type: text/plain\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "{s}\r\n", .{ statusCode, statusText, message });
    var streamWriter = stream.writer(&writerBuffer);
    const writerInterface = &streamWriter.interface;
    try writerInterface.writeAll(response);
}

fn sendOAuthSuccessResponse(stream: *std.net.Stream) !void {
    const htmlContent = "<!DOCTYPE html>\n" ++
        "<html><head><title>Authorization Successful</title>" ++
        "<style>body{font-family:Arial,sans-serif;max-width:600px;margin:50px auto;text-align:center;background:#f5f5f5;padding:20px}" ++
        ".success{color:#28a745;font-size:24px;margin:20px 0}" ++
        ".message{color:#333;font-size:16px;margin:10px 0}</style></head>" ++
        "<body><div class='success'>✅ Authorization Successful!</div>" ++
        "<div class='message'>You can now close this browser tab and return to your terminal.</div>" ++
        "<div class='message'>The OAuth setup will continue automatically.</div></body></html>";

    var responseBuffer: [2048]u8 = undefined;
    var writerBuffer: [2048]u8 = undefined;
    const response = try std.fmt.bufPrint(&responseBuffer, "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/html\r\n" ++
        "Content-Length: {}\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "{s}", .{ htmlContent.len, htmlContent });
    var streamWriter = stream.writer(&writerBuffer);
    const writerInterface = &streamWriter.interface;
    try writerInterface.writeAll(response);
}

fn sendOAuthErrorResponse(stream: *std.net.Stream, errorCode: []const u8, errorDescription: ?[]const u8) !void {
    var htmlBuffer: [2048]u8 = undefined;
    const description = errorDescription orelse "No additional details provided.";
    const htmlContent = try std.fmt.bufPrint(&htmlBuffer, "<!DOCTYPE html>\n" ++
        "<html><head><title>Authorization Error</title>" ++
        "<style>body{{font-family:Arial,sans-serif;max-width:600Dpx;margin:50px auto;text-align:center;background:#f5f5f5;padding:20px}}" ++
        ".error{{color:#dc3545;font-size:24px;margin:20px 0}}" ++
        ".message{{color:#333;font-size:16px;margin:10px 0}}" ++
        ".code{{background:#e9ecef;padding:10px;border-radius:5px;font-family:monospace}}</style></head>" ++
        "<body><div class='error'>❌ Authorization Failed</div>" ++
        "<div class='message'><strong>Error:</strong> {s}</div>" ++
        "<div class='message'>{s}</div>" ++
        "<div class='message'>Please close this tab and try the authorization again.</div></body></html>", .{ errorCode, description });

    var responseBuffer: [3072]u8 = undefined;
    var writerBuffer: [3072]u8 = undefined;
    const response = try std.fmt.bufPrint(&responseBuffer, "HTTP/1.1 400 Bad Request\r\n" ++
        "Content-Type: text/html\r\n" ++
        "Content-Length: {}\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "{s}", .{ htmlContent.len, htmlContent });
    var streamWriter = stream.writer(&writerBuffer);
    const writerInterface = &streamWriter.interface;
    try writerInterface.writeAll(response);
}

fn extractQueryParam(queryString: []const u8, paramName: []const u8) ?[]const u8 {
    const searchKey = std.fmt.allocPrint(std.heap.page_allocator, "{s}=", .{paramName}) catch return null;
    defer std.heap.page_allocator.free(searchKey);
    const paramStart = std.mem.indexOf(u8, queryString, searchKey) orelse return null;
    const valueStart = paramStart + searchKey.len;
    const valueEnd = std.mem.indexOfScalarPos(u8, queryString, valueStart, '&') orelse queryString.len;
    if (valueEnd <= valueStart) return null;
    return queryString[valueStart..valueEnd];
}

pub fn validateState(receivedState: []const u8, expectedState: []const u8) bool {
    return std.mem.eql(u8, receivedState, expectedState);
}

pub fn handleOAuthError(allocator: std.mem.Allocator, errorCode: []const u8, errorDescription: ?[]const u8) Error {
    std.log.err("OAuth error: {s}", .{errorCode});
    if (errorDescription) |desc| {
        std.log.err("Description: {s}", .{desc});
    }
    if (std.mem.eql(u8, errorCode, "invalid_grant")) {
        std.log.err("🔄 Your authorization has expired or been revoked.", .{});
        std.log.err("   Please run OAuth setup again: --oauth", .{});
        return Error.InvalidGrant;
    } else if (std.mem.eql(u8, errorCode, "invalid_request")) {
        std.log.err("⚠️  Invalid OAuth request. This may be a client issue.", .{});
        std.log.err("   Try running OAuth setup again: --oauth", .{});
        return Error.AuthError;
    } else if (std.mem.eql(u8, errorCode, "access_denied")) {
        std.log.err("🚫 Authorization was denied.", .{});
        std.log.err("   Please authorize the application to continue.", .{});
        return Error.AuthError;
    } else if (std.mem.eql(u8, errorCode, "server_error")) {
        std.log.err("🔧 Server error occurred. Please try again later.", .{});
        return Error.NetworkError;
    }
    _ = allocator;
    return Error.AuthError;
}

pub fn validateCredentialsFile(filePath: []const u8) bool {
    const file = std.fs.cwd().openFile(filePath, .{}) catch return false;
    defer file.close();
    const stat = file.stat() catch return false;
    return stat.size > 0;
}

pub fn cleanupCredentials(allocator: std.mem.Allocator, filePath: []const u8) !void {
    if (validateCredentialsFile(filePath)) {
        std.log.info("Removing invalid OAuth credentials file: {s}", .{filePath});
        std.fs.cwd().deleteFile(filePath) catch |err| {
            std.log.warn("Failed to cleanup credentials file: {}", .{err});
        };
    }
    _ = allocator;
}

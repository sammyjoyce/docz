//! OAuth helpers for Anthropic client

const std = @import("std");
const curl = @import("../curl.zig");
const models = @import("models.zig");

pub const OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
pub const OAUTH_AUTHORIZATION_URL = "https://claude.ai/oauth/authorize";
pub const OAUTH_TOKEN_ENDPOINT = "https://console.anthropic.com/v1/oauth/token";
pub const OAUTH_REDIRECT_URI = "https://console.anthropic.com/oauth/code/callback";
pub const OAUTH_SCOPES = "org:create_api_key user:profile user:inference";

const OAuthCredentials = models.OAuthCredentials;
const Pkce = models.Pkce;
const Error = models.Error;

pub fn exchangeCodeForTokens(allocator: std.mem.Allocator, authorization_code: []const u8, pkce_params: Pkce) !OAuthCredentials {
    std.log.info("🔄 Exchanging authorization code for OAuth tokens...", .{});

    var client = curl.HTTPClient.init(allocator) catch |err| {
        std.log.err("Failed to initialize HTTP client: {}", .{err});
        return Error.NetworkError;
    };
    defer client.deinit();

    var code_parts = std.mem.splitSequence(u8, authorization_code, "#");
    const code = code_parts.next() orelse authorization_code;
    const state = code_parts.next() orelse "";

    const body = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "code": "{s}",
        \\  "state": "{s}",
        \\  "grant_type": "authorization_code",
        \\  "client_id": "{s}",
        \\  "redirect_uri": "{s}",
        \\  "code_verifier": "{s}"
        \\}}
    , .{ code, state, OAUTH_CLIENT_ID, OAUTH_REDIRECT_URI, pkce_params.code_verifier });
    defer allocator.free(body);

    std.log.debug("Sending OAuth token request with JSON body: {s}", .{body});

    const headers = [_]curl.Header{
        .{ .name = "content-type", .value = "application/json" },
        .{ .name = "accept", .value = "application/json" },
        .{ .name = "user-agent", .value = "docz/1.0 (libcurl)" },
    };

    const req = curl.HTTPRequest{
        .method = .POST,
        .url = OAUTH_TOKEN_ENDPOINT,
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
    const expires_at = now + parsed.value.expires_in;

    std.log.info("✅ OAuth tokens received successfully!", .{});

    return OAuthCredentials{
        .type = try allocator.dupe(u8, "oauth"),
        .access_token = try allocator.dupe(u8, parsed.value.access_token),
        .refresh_token = try allocator.dupe(u8, parsed.value.refresh_token),
        .expires_at = expires_at,
    };
}

pub fn refreshTokens(allocator: std.mem.Allocator, refresh_token: []const u8) !OAuthCredentials {
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
    , .{ refresh_token, OAUTH_CLIENT_ID });
    defer allocator.free(body);

    const headers = [_]curl.Header{
        .{ .name = "content-type", .value = "application/json" },
        .{ .name = "accept", .value = "application/json" },
        .{ .name = "user-agent", .value = "docz/1.0 (libcurl)" },
    };

    const req = curl.HTTPRequest{
        .method = .POST,
        .url = OAUTH_TOKEN_ENDPOINT,
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
    const expires_at = now + parsed.value.expires_in;

    std.log.info("✅ OAuth tokens refreshed successfully!", .{});

    return OAuthCredentials{
        .type = try allocator.dupe(u8, "oauth"),
        .access_token = try allocator.dupe(u8, parsed.value.access_token),
        .refresh_token = try allocator.dupe(u8, parsed.value.refresh_token),
        .expires_at = expires_at,
    };
}

pub fn loadOAuthCredentials(allocator: std.mem.Allocator, file_path: []const u8) !?OAuthCredentials {
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 16 * 1024);
    defer allocator.free(contents);

    const parsed = try std.json.parseFromSlice(OAuthCredentials, allocator, contents, .{});
    defer parsed.deinit();

    return OAuthCredentials{
        .type = try allocator.dupe(u8, parsed.value.type),
        .access_token = try allocator.dupe(u8, parsed.value.access_token),
        .refresh_token = try allocator.dupe(u8, parsed.value.refresh_token),
        .expires_at = parsed.value.expires_at,
    };
}

pub fn saveOAuthCredentials(allocator: std.mem.Allocator, file_path: []const u8, creds: OAuthCredentials) !void {
    const json_content = try std.fmt.allocPrint(allocator, "{\"type\":\"{s}\",\"access_token\":\"{s}\",\"refresh_token\":\"{s}\",\"expires_at\":{}}", .{ creds.type, creds.access_token, creds.refresh_token, creds.expires_at });
    defer allocator.free(json_content);

    const file = try std.fs.cwd().createFile(file_path, .{ .mode = 0o600 });
    defer file.close();

    try file.writeAll(json_content);
}

pub fn extractCodeFromCallbackUrl(allocator: std.mem.Allocator, callback_url: []const u8) ![]u8 {
    const url = try std.URI.parse(callback_url);

    if (url.query) |query_component| {
        const query_str = switch (query_component) {
            .percent_encoded => |str| str,
            .raw => |str| str,
        };
        if (std.mem.indexOf(u8, query_str, "code=")) |start| {
            const code_start = start + 5;
            const code_end = std.mem.indexOf(u8, query_str[code_start..], "&") orelse query_str.len - code_start;
            return try allocator.dupe(u8, query_str[code_start .. code_start + code_end]);
        }
    }

    if (url.fragment) |fragment_component| {
        const fragment_str = switch (fragment_component) {
            .percent_encoded => |str| str,
            .raw => |str| str,
        };
        if (std.mem.indexOf(u8, fragment_str, "code=")) |start| {
            const code_start = start + 5;
            const code_end = std.mem.indexOf(u8, fragment_str[code_start..], "&") orelse fragment_str.len - code_start;
            return try allocator.dupe(u8, fragment_str[code_start .. code_start + code_end]);
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

        var reader_buffer: [8192]u8 = undefined;
        var reader = connection.stream.reader(&reader_buffer);

        const request_line = reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
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

        const request_line_trimmed = std.mem.trim(u8, request_line, " \t\r\n");
        var request_parts = std.mem.splitSequence(u8, request_line_trimmed, " ");
        const method = request_parts.next() orelse {
            sendHTTPError(&connection.stream, 400, "Invalid request format") catch {};
            continue;
        };
        const path_and_query = request_parts.next() orelse {
            sendHTTPError(&connection.stream, 400, "Invalid request format") catch {};
            continue;
        };

        if (!std.mem.eql(u8, method, "GET")) {
            sendHTTPError(&connection.stream, 405, "Method not allowed") catch {};
            continue;
        }

        std.log.debug("Received OAuth callback request: GET {s}", .{path_and_query});
        const query_start = std.mem.indexOf(u8, path_and_query, "?");
        if (query_start == null) {
            sendHTTPError(&connection.stream, 400, "No query parameters in OAuth callback") catch {};
            continue;
        }

        const query_string = path_and_query[query_start.? + 1 ..];

        if (std.mem.indexOf(u8, query_string, "error=")) |_| {
            const error_code = extractQueryParam(query_string, "error") orelse "unknown_error";
            const error_desc = extractQueryParam(query_string, "error_description");
            sendOAuthErrorResponse(&connection.stream, error_code, error_desc) catch {};
            return handleOAuthError(allocator, error_code, error_desc);
        }

        if (extractQueryParam(query_string, "code")) |auth_code| {
            sendOAuthSuccessResponse(&connection.stream) catch |err| {
                std.log.warn("Failed to send success response to browser: {}", .{err});
            };
            std.log.info("✅ Authorization code received successfully!", .{});
            return allocator.dupe(u8, auth_code);
        } else {
            sendHTTPError(&connection.stream, 400, "Authorization code not found in OAuth callback") catch {};
            continue;
        }
    }
}

fn sendHTTPError(stream: *std.net.Stream, status_code: u16, message: []const u8) !void {
    const status_text = switch (status_code) {
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        500 => "Internal Server Error",
        else => "Error",
    };
    var response_buffer: [1024]u8 = undefined;
    var writer_buffer: [1024]u8 = undefined;
    const response = try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 {} {s}\r\n" ++
        "Content-Type: text/plain\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "{s}\r\n", .{ status_code, status_text, message });
    var stream_writer = stream.writer(&writer_buffer);
    const writer_interface = &stream_writer.interface;
    try writer_interface.writeAll(response);
}

fn sendOAuthSuccessResponse(stream: *std.net.Stream) !void {
    const html_content = "<!DOCTYPE html>\n" ++
        "<html><head><title>Authorization Successful</title>" ++
        "<style>body{font-family:Arial,sans-serif;max-width:600px;margin:50px auto;text-align:center;background:#f5f5f5;padding:20px}" ++
        ".success{color:#28a745;font-size:24px;margin:20px 0}" ++
        ".message{color:#333;font-size:16px;margin:10px 0}</style></head>" ++
        "<body><div class='success'>✅ Authorization Successful!</div>" ++
        "<div class='message'>You can now close this browser tab and return to your terminal.</div>" ++
        "<div class='message'>The OAuth setup will continue automatically.</div></body></html>";

    var response_buffer: [2048]u8 = undefined;
    var writer_buffer: [2048]u8 = undefined;
    const response = try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/html\r\n" ++
        "Content-Length: {}\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "{s}", .{ html_content.len, html_content });
    var stream_writer = stream.writer(&writer_buffer);
    const writer_interface = &stream_writer.interface;
    try writer_interface.writeAll(response);
}

fn sendOAuthErrorResponse(stream: *std.net.Stream, error_code: []const u8, error_description: ?[]const u8) !void {
    var html_buffer: [2048]u8 = undefined;
    const description = error_description orelse "No additional details provided.";
    const html_content = try std.fmt.bufPrint(&html_buffer, "<!DOCTYPE html>\n" ++
        "<html><head><title>Authorization Error</title>" ++
        "<style>body{{font-family:Arial,sans-serif;max-width:600Dpx;margin:50px auto;text-align:center;background:#f5f5f5;padding:20px}}" ++
        ".error{{color:#dc3545;font-size:24px;margin:20px 0}}" ++
        ".message{{color:#333;font-size:16px;margin:10px 0}}" ++
        ".code{{background:#e9ecef;padding:10px;border-radius:5px;font-family:monospace}}</style></head>" ++
        "<body><div class='error'>❌ Authorization Failed</div>" ++
        "<div class='message'><strong>Error:</strong> {s}</div>" ++
        "<div class='message'>{s}</div>" ++
        "<div class='message'>Please close this tab and try the authorization again.</div></body></html>", .{ error_code, description });

    var response_buffer: [3072]u8 = undefined;
    var writer_buffer: [3072]u8 = undefined;
    const response = try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 400 Bad Request\r\n" ++
        "Content-Type: text/html\r\n" ++
        "Content-Length: {}\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "{s}", .{ html_content.len, html_content });
    var stream_writer = stream.writer(&writer_buffer);
    const writer_interface = &stream_writer.interface;
    try writer_interface.writeAll(response);
}

fn extractQueryParam(query_string: []const u8, param_name: []const u8) ?[]const u8 {
    const search_key = std.fmt.allocPrint(std.heap.page_allocator, "{s}=", .{param_name}) catch return null;
    defer std.heap.page_allocator.free(search_key);
    const param_start = std.mem.indexOf(u8, query_string, search_key) orelse return null;
    const value_start = param_start + search_key.len;
    const value_end = std.mem.indexOfScalarPos(u8, query_string, value_start, '&') orelse query_string.len;
    if (value_end <= value_start) return null;
    return query_string[value_start..value_end];
}

pub fn validateState(received_state: []const u8, expected_state: []const u8) bool {
    return std.mem.eql(u8, received_state, expected_state);
}

pub fn handleOAuthError(allocator: std.mem.Allocator, error_code: []const u8, error_description: ?[]const u8) Error {
    std.log.err("OAuth error: {s}", .{error_code});
    if (error_description) |desc| {
        std.log.err("Description: {s}", .{desc});
    }
    if (std.mem.eql(u8, error_code, "invalid_grant")) {
        std.log.err("🔄 Your authorization has expired or been revoked.", .{});
        std.log.err("   Please run OAuth setup again: --oauth", .{});
        return Error.InvalidGrant;
    } else if (std.mem.eql(u8, error_code, "invalid_request")) {
        std.log.err("⚠️  Invalid OAuth request. This may be a client issue.", .{});
        std.log.err("   Try running OAuth setup again: --oauth", .{});
        return Error.AuthError;
    } else if (std.mem.eql(u8, error_code, "access_denied")) {
        std.log.err("🚫 Authorization was denied.", .{});
        std.log.err("   Please authorize the application to continue.", .{});
        return Error.AuthError;
    } else if (std.mem.eql(u8, error_code, "server_error")) {
        std.log.err("🔧 Server error occurred. Please try again later.", .{});
        return Error.NetworkError;
    }
    _ = allocator;
    return Error.AuthError;
}

pub fn validateCredentialsFile(file_path: []const u8) bool {
    const file = std.fs.cwd().openFile(file_path, .{}) catch return false;
    defer file.close();
    const stat = file.stat() catch return false;
    return stat.size > 0;
}

pub fn cleanupCredentials(allocator: std.mem.Allocator, file_path: []const u8) !void {
    if (validateCredentialsFile(file_path)) {
        std.log.info("Removing invalid OAuth credentials file: {s}", .{file_path});
        std.fs.cwd().deleteFile(file_path) catch |err| {
            std.log.warn("Failed to cleanup credentials file: {}", .{err});
        };
    }
    _ = allocator;
}

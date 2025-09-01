//! Loopback HTTP server for OAuth callback handling
//! Binds to localhost only for security per RFC 8252

const std = @import("std");
const net = std.net;
const http = std.http;

const log = std.log.scoped(.oauth_callback);

/// OAuth callback result
pub const CallbackResult = struct {
    code: []const u8,
    state: []const u8,
    error_msg: ?[]const u8 = null,

    pub fn deinit(self: CallbackResult, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        allocator.free(self.state);
        if (self.error_msg) |msg| {
            allocator.free(msg);
        }
    }
};

/// Loopback server configuration
pub const ServerConfig = struct {
    host: []const u8 = "localhost",
    port: u16 = 8080,
    path: []const u8 = "/callback",
    timeout_ms: u32 = 300000, // 5 minutes
};

/// Loopback OAuth callback server
pub const LoopbackServer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: ServerConfig,
    server: ?net.Server,
    address: net.Address,

    pub fn init(allocator: std.mem.Allocator, config: ServerConfig) !Self {
        // Bind to loopback interface only - use 127.0.0.1 for RFC 8252 compliance
        const address = try net.Address.parseIp("127.0.0.1", config.port);

        var server = try address.listen(.{
            .reuse_address = true,
            .kernel_backlog = 1,
        });

        const actual_address = try server.getLocalAddress();
        log.info("OAuth callback server listening on http://{}:{}/callback", .{ config.host, actual_address.getPort() });

        return Self{
            .allocator = allocator,
            .config = config,
            .server = server,
            .address = actual_address,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.server) |*server| {
            server.deinit();
            self.server = null;
        }
    }

    /// Get the redirect URI for OAuth flow
    pub fn getRedirectUri(self: Self, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "http://{s}:{d}{s}", .{
            self.config.host,
            self.address.getPort(),
            self.config.path,
        });
    }

    /// Wait for OAuth callback and extract code and state
    /// Validates the callback path matches the expected path
    pub fn waitForCallback(self: *Self, expected_state: ?[]const u8) !CallbackResult {
        const server = self.server orelse return error.ServerNotInitialized;

        // Accept connection with timeout
        const connection = try server.accept();
        defer connection.stream.close();

        var buf: [8192]u8 = undefined;
        const bytes_read = try connection.stream.read(&buf);

        if (bytes_read == 0) {
            return error.EmptyRequest;
        }

        const request_line = std.mem.sliceTo(buf[0..bytes_read], '\r') orelse
            return error.InvalidRequest;

        // Parse GET request
        var parts = std.mem.tokenize(u8, request_line, " ");
        const method = parts.next() orelse return error.InvalidRequest;
        const full_path = parts.next() orelse return error.InvalidRequest;

        if (!std.mem.eql(u8, method, "GET")) {
            try self.sendErrorResponse(connection.stream, "Invalid method");
            return error.InvalidMethod;
        }

        // Verify path matches expected callback path
        const query_start = std.mem.indexOf(u8, full_path, "?");
        const path = if (query_start) |qs| full_path[0..qs] else full_path;

        if (!std.mem.eql(u8, path, self.config.path)) {
            log.warn("Unexpected callback path: {s}, expected: {s}", .{ path, self.config.path });
            try self.sendErrorResponse(connection.stream, "Invalid callback path");
            return error.InvalidCallbackPath;
        }

        // Extract query parameters
        if (query_start == null) {
            // Check if this is an error callback
            if (std.mem.indexOf(u8, full_path, "error=") != null) {
                var error_desc: ?[]const u8 = null;
                const query = full_path[query_start.? + 1 ..];
                var params = std.mem.tokenize(u8, query, "&");
                while (params.next()) |param| {
                    const eq_pos = std.mem.indexOf(u8, param, "=") orelse continue;
                    const key = param[0..eq_pos];
                    const value = param[eq_pos + 1 ..];
                    if (std.mem.eql(u8, key, "error_description")) {
                        error_desc = try urlDecode(self.allocator, value);
                    }
                }
                try self.sendErrorResponse(connection.stream, error_desc orelse "Authorization denied");
                return CallbackResult{
                    .code = try self.allocator.dupe(u8, ""),
                    .state = try self.allocator.dupe(u8, ""),
                    .error_msg = error_desc,
                };
            }
            try self.sendErrorResponse(connection.stream, "Missing parameters");
            return error.NoQueryParameters;
        }

        const query = full_path[query_start.? + 1 ..];

        // Parse code and state (and potential error)
        var code: ?[]const u8 = null;
        var state: ?[]const u8 = null;
        var error_param: ?[]const u8 = null;

        var params = std.mem.tokenize(u8, query, "&");
        while (params.next()) |param| {
            const eq_pos = std.mem.indexOf(u8, param, "=") orelse continue;
            const key = param[0..eq_pos];
            const value = param[eq_pos + 1 ..];

            if (std.mem.eql(u8, key, "code")) {
                code = try urlDecode(self.allocator, value);
            } else if (std.mem.eql(u8, key, "state")) {
                state = try urlDecode(self.allocator, value);
            } else if (std.mem.eql(u8, key, "error")) {
                error_param = try urlDecode(self.allocator, value);
            }
        }

        // Handle OAuth error response
        if (error_param) |err| {
            log.err("OAuth error: {s}", .{err});
            try self.sendErrorResponse(connection.stream, err);
            self.allocator.free(err);
            return error.OAuthError;
        }

        if (code == null or state == null) {
            try self.sendErrorResponse(connection.stream, "Missing code or state");
            return error.MissingParameters;
        }

        // Verify state matches if expected
        if (expected_state) |exp_state| {
            if (!std.mem.eql(u8, state.?, exp_state)) {
                log.err("State mismatch: expected={s}, received={s}", .{ exp_state, state.? });
                try self.sendErrorResponse(connection.stream, "State mismatch");
                self.allocator.free(code.?);
                self.allocator.free(state.?);
                return error.StateMismatch;
            }
        }

        // Send success response with auto-close HTML
        try self.sendSuccessResponse(connection.stream);

        // Close server after first valid callback
        self.deinit();

        return CallbackResult{
            .code = code.?,
            .state = state.?,
        };
    }

    fn sendSuccessResponse(self: *const Self, stream: net.Stream) !void {
        _ = self;
        const html =
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\    <title>Authentication Successful</title>
            \\    <style>
            \\        body { font-family: system-ui; padding: 40px; text-align: center; }
            \\        h1 { color: #22c55e; }
            \\        p { color: #666; margin: 20px 0; }
            \\    </style>
            \\    <script>
            \\        setTimeout(() => window.close(), 3000);
            \\    </script>
            \\</head>
            \\<body>
            \\    <h1>✓ Authentication Successful</h1>
            \\    <p>You can now close this window and return to the terminal.</p>
            \\    <p style="font-size: 0.9em; color: #999;">This window will close automatically in 3 seconds...</p>
            \\</body>
            \\</html>
        ;

        const response = std.fmt.comptimePrint("HTTP/1.1 200 OK\r\n" ++
            "Content-Type: text/html\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "\r\n" ++
            "{s}", .{ html.len, html });

        _ = try stream.write(response);
    }

    fn sendErrorResponse(self: *const Self, stream: net.Stream, error_msg: []const u8) !void {
        const html = try std.fmt.allocPrint(self.allocator,
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\    <title>Authentication Failed</title>
            \\    <style>
            \\        body {{ font-family: system-ui; padding: 40px; text-align: center; }}
            \\        h1 {{ color: #ef4444; }}
            \\        p {{ color: #666; margin: 20px 0; }}
            \\        .error {{ color: #ef4444; font-weight: bold; }}
            \\    </style>
            \\</head>
            \\<body>
            \\    <h1>✗ Authentication Failed</h1>
            \\    <p class="error">{s}</p>
            \\    <p>Please try logging in again.</p>
            \\</body>
            \\</html>
        , .{error_msg});
        defer self.allocator.free(html);

        const response = try std.fmt.allocPrint(self.allocator, "HTTP/1.1 400 Bad Request\r\n" ++
            "Content-Type: text/html\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "\r\n" ++
            "{s}", .{ html.len, html });
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }
};

/// URL decode a string (reverse of percent encoding)
fn urlDecode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%' and i + 2 < input.len) {
            const hex = input[i + 1 .. i + 3];
            const byte = std.fmt.parseInt(u8, hex, 16) catch {
                // Invalid hex, just append the %
                try result.append(input[i]);
                i += 1;
                continue;
            };
            try result.append(byte);
            i += 3;
        } else if (input[i] == '+') {
            // + is space in URL encoding
            try result.append(' ');
            i += 1;
        } else {
            try result.append(input[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

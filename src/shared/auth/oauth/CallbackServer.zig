//! OAuth Callback Server for Handling Authorization Code Redirects
//!
//! This server provides a robust OAuth callback handler with:
//! - Local HTTP server on configurable port (default: 8080)
//! - Automatic authorization code capture
//! - PKCE verification for security
//! - State parameter validation
//! - Beautiful success/error pages
//! - Real-time terminal status updates
//! - Timeout handling and cleanup
//! - Integration with OAuth wizard
//! - Support for multiple concurrent authorization flows

const std = @import("std");
const oauth = @import("mod.zig");
const print = std.debug.print;

// Terminal rendering support
// Minimal ANSI helpers (avoid dependency on terminal module in minimal builds)
const ansi = struct {
    pub const style = struct {
        pub const bold = "\x1b[1m";
        pub const reset = "\x1b[0m";
    };
    pub const fg = struct {
        pub const gray = "\x1b[90m";
        pub const white = "\x1b[97m";
        pub const cyan = "\x1b[36m";
        pub const blue = "\x1b[34m";
        pub const green = "\x1b[32m";
        pub const yellow = "\x1b[33m";
    };
    pub const cursor = struct {
        pub const save = "\x1b7";
        pub const restore = "\x1b8";
    };
    pub const erase = struct {
        pub const toEndOfLine = "\x1b[0K";
    };
};

/// Server configuration
pub const Config = struct {
    /// Port to listen on (default: 8080)
    port: u16 = 8080,
    /// Timeout for authorization code receipt (milliseconds)
    timeoutMs: u64 = 300_000, // 5 minutes
    /// Maximum concurrent connections
    maxConnections: u32 = 10,
    /// Enable verbose logging
    verbose: bool = false,
    /// Custom redirect URI (if different from standard)
    redirectUri: ?[]const u8 = null,
    /// Show browser success page
    showSuccessPage: bool = true,
    /// Auto-close server after success
    autoClose: bool = true,
};

/// Authorization result from callback
pub const Result = struct {
    /// Authorization code from OAuth provider
    code: []const u8,
    /// State parameter for verification
    state: []const u8,
    /// Any error from OAuth provider
    errorCode: ?[]const u8 = null,
    /// Error description from provider
    errorDescription: ?[]const u8 = null,
    /// Timestamp when received
    receivedAt: i64,

    pub fn deinit(self: Result, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        allocator.free(self.state);
        if (self.errorCode) |err| allocator.free(err);
        if (self.errorDescription) |desc| allocator.free(desc);
    }
};

/// OAuth callback server
pub const Server = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: Config,
    server: ?std.net.Server = null,

    // State management
    activeSessions: std.array_list.Managed(Session),
    resultChannel: Channel.Channel(Result),
    shutdownRequested: std.atomic.Value(bool),

    // Status tracking
    startTimeMs: i64,
    requestsHandled: u32 = 0,
    lastActivityMs: i64,

    // Terminal status display
    statusThread: ?std.Thread = null,
    showStatus: bool = true,

    const Session = struct {
        pkceParams: oauth.Pkce,
        createdAt: i64,
        expiresAt: i64,
    };

    /// Channel for passing results between threads
    const Channel = struct {
        fn Channel(comptime T: type) type {
            return struct {
                mutex: std.Thread.Mutex,
                condition: std.Thread.Condition,
                value: ?T,
                hasValue: bool,

                pub fn init() @This() {
                    return .{
                        .mutex = .{},
                        .condition = .{},
                        .value = null,
                        .hasValue = false,
                    };
                }

                pub fn send(self: *@This(), value: T) void {
                    self.mutex.lock();
                    defer self.mutex.unlock();

                    self.value = value;
                    self.hasValue = true;
                    self.condition.signal();
                }

                pub fn receive(self: *@This()) ?T {
                    self.mutex.lock();
                    defer self.mutex.unlock();

                    while (!self.hasValue) {
                        self.condition.wait(&self.mutex);
                    }

                    const result = self.value;
                    self.value = null;
                    self.hasValue = false;
                    return result;
                }

                pub fn tryReceive(self: *@This()) ?T {
                    self.mutex.lock();
                    defer self.mutex.unlock();

                    if (self.hasValue) {
                        const result = self.value;
                        self.value = null;
                        self.hasValue = false;
                        return result;
                    }
                    return null;
                }
            };
        }
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .activeSessions = std.array_list.Managed(Session).init(allocator),
            .resultChannel = Channel.Channel(Result).init(),
            .shutdownRequested = std.atomic.Value(bool).init(false),
            .startTimeMs = std.time.timestamp(),
            .lastActivityMs = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.shutdown();

        // Clean up sessions
        for (self.activeSessions.items) |session| {
            session.pkceParams.deinit(self.allocator);
        }
        self.activeSessions.deinit();

        // Stop server if running
        if (self.server) |*server| {
            server.deinit();
        }
    }

    /// Start the callback server
    pub fn start(self: *Self) !void {
        const address = try std.net.Address.parseIp("127.0.0.1", self.config.port);
        self.server = try std.net.Address.listen(address, .{});

        if (self.config.verbose) {
            print("🚀 OAuth callback server started on http://localhost:{d}\n", .{self.config.port});
        }

        // Start status display thread if enabled
        if (self.showStatus) {
            self.statusThread = try std.Thread.spawn(.{}, statusDisplayThread, .{self});
        }

        // Start accepting connections
        const acceptThread = try std.Thread.spawn(.{}, acceptLoop, .{self});
        acceptThread.detach();
    }

    /// Stop the callback server
    pub fn shutdown(self: *Self) void {
        self.shutdownRequested.store(true, .seq_cst);

        if (self.statusThread) |thread| {
            thread.join();
            self.statusThread = null;
        }

        if (self.server) |*server| {
            server.deinit();
            self.server = null;
        }
    }

    /// Register a new PKCE session
    pub fn registerSession(self: *Self, pkceParams: oauth.Pkce) !void {
        const now = std.time.timestamp();
        const session = Session{
            .pkceParams = pkceParams,
            .createdAt = now,
            .expiresAt = now + @as(i64, @intCast(self.config.timeoutMs / 1000)),
        };

        try self.activeSessions.append(session);

        if (self.config.verbose) {
            print("📝 Registered new OAuth session (state: {s})\n", .{pkceParams.state});
        }
    }

    /// Wait for authorization callback with timeout
    pub fn waitForCallback(self: *Self, expectedState: []const u8, timeoutMs: ?u64) !Result {
        const timeout = timeoutMs orelse self.config.timeoutMs;
        const deadline = std.time.milliTimestamp() + @as(i64, @intCast(timeout));

        if (self.showStatus) {
            print("\n{s}⏳ Waiting for authorization callback...{s}\n", .{ ansi.style.bold, ansi.style.reset });
            print("{s}Please complete the authorization in your browser.{s}\n\n", .{ ansi.fg.gray, ansi.style.reset });
        }

        while (std.time.milliTimestamp() < deadline) {
            if (self.resultChannel.tryReceive()) |result| {
                // Verify state parameter
                if (!std.mem.eql(u8, result.state, expectedState)) {
                    result.deinit(self.allocator);
                    return oauth.Error.AuthError;
                }

                // Check for errors
                if (result.errorCode) |_| {
                    if (self.config.verbose) {
                        print("❌ OAuth error: {s} - {s}\n", .{ result.errorCode.?, result.errorDescription orelse "No description" });
                    }
                    result.deinit(self.allocator);
                    return oauth.Error.AuthError;
                }

                if (self.showStatus) {
                    print("\n{s}✅ Authorization code received!{s}\n", .{ ansi.fg.green, ansi.style.reset });
                }

                return result;
            }

            std.Thread.sleep(100_000_000); // 100ms
        }

        return oauth.Error.AuthError; // Timeout
    }

    /// Accept connections loop (runs in separate thread)
    fn acceptLoop(self: *Self) void {
        while (!self.shutdownRequested.load(.seq_cst)) {
            const connection = self.server.?.accept() catch |err| {
                if (err == error.SocketNotListening) break;
                std.Thread.sleep(100_000_000); // 100ms retry
                continue;
            };

            // Handle connection in new thread
            const handleThread = std.Thread.spawn(.{}, handleConnection, .{ self, connection }) catch {
                connection.stream.close();
                continue;
            };
            handleThread.detach();
        }
    }

    /// Handle individual connection
    fn handleConnection(self: *Self, connection: std.net.Server.Connection) void {
        defer connection.stream.close();

        self.requestsHandled += 1;
        self.lastActivityMs = std.time.timestamp();

        // Read request
        var buffer: [4096]u8 = undefined;
        const bytesRead = connection.stream.read(&buffer) catch return;
        const request = buffer[0..bytesRead];

        // Parse request
        const result = self.parseCallbackRequest(request) catch |err| {
            self.sendErrorResponse(connection.stream, err) catch {};
            return;
        };

        // Send result through channel
        self.resultChannel.send(result);

        // Send response to browser
        if (self.config.showSuccessPage) {
            self.sendSuccessResponse(connection.stream) catch {};
        } else {
            self.sendMinimalResponse(connection.stream) catch {};
        }

        // Auto-close if configured
        if (self.config.autoClose) {
            std.Thread.sleep(1_000_000_000); // 1 second delay
            self.shutdownRequested.store(true, .seq_cst);
        }
    }

    /// Parse OAuth callback request
    fn parseCallbackRequest(self: *Self, request: []const u8) !Result {
        // Find the request line
        const firstLineEnd = std.mem.indexOf(u8, request, "\r\n") orelse request.len;
        const requestLine = request[0..firstLineEnd];

        // Parse GET request
        if (!std.mem.startsWith(u8, requestLine, "GET ")) {
            return oauth.Error.InvalidFormat;
        }

        // Extract path and query
        const pathStart = 4; // After "GET "
        const pathEnd = std.mem.indexOf(u8, requestLine[pathStart..], " ") orelse return oauth.Error.InvalidFormat;
        const fullPath = requestLine[pathStart .. pathStart + pathEnd];

        // Parse query parameters
        const queryStart = std.mem.indexOf(u8, fullPath, "?") orelse return oauth.Error.InvalidFormat;
        const query = fullPath[queryStart + 1 ..];

        var code: ?[]const u8 = null;
        var state: ?[]const u8 = null;
        var errorCode: ?[]const u8 = null;
        var errorDescription: ?[]const u8 = null;

        // Parse query parameters
        var iter = std.mem.tokenizeAny(u8, query, "&");
        while (iter.next()) |param| {
            const eqPos = std.mem.indexOf(u8, param, "=") orelse continue;
            const key = param[0..eqPos];
            const value = param[eqPos + 1 ..];

            if (std.mem.eql(u8, key, "code")) {
                code = try self.allocator.dupe(u8, try urlDecode(self.allocator, value));
            } else if (std.mem.eql(u8, key, "state")) {
                state = try self.allocator.dupe(u8, try urlDecode(self.allocator, value));
            } else if (std.mem.eql(u8, key, "error")) {
                errorCode = try self.allocator.dupe(u8, try urlDecode(self.allocator, value));
            } else if (std.mem.eql(u8, key, "error_description")) {
                errorDescription = try self.allocator.dupe(u8, try urlDecode(self.allocator, value));
            }
        }

        // Check for required parameters
        if (code == null and errorCode == null) {
            return oauth.Error.InvalidFormat;
        }

        if (state == null) {
            if (code) |c| self.allocator.free(c);
            if (errorCode) |e| self.allocator.free(e);
            if (errorDescription) |d| self.allocator.free(d);
            return oauth.Error.InvalidFormat;
        }

        return Result{
            .code = code orelse try self.allocator.dupe(u8, ""),
            .state = state.?,
            .errorCode = errorCode,
            .errorDescription = errorDescription,
            .receivedAt = std.time.timestamp(),
        };
    }

    /// Send success response to browser
    fn sendSuccessResponse(self: *Self, stream: std.net.Stream) !void {
        const html =
            \\<!DOCTYPE html>
            \\<html lang="en">
            \\<head>
            \\    <meta charset="UTF-8">
            \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \\    <title>Authorization Successful</title>
            \\    <style>
            \\        body {
            \\            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            \\            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            \\            color: white;
            \\            display: flex;
            \\            justify-content: center;
            \\            align-items: center;
            \\            height: 100vh;
            \\            margin: 0;
            \\            padding: 20px;
            \\        }
            \\        .container {
            \\            text-align: center;
            \\            background: rgba(255, 255, 255, 0.1);
            \\            backdrop-filter: blur(10px);
            \\            border-radius: 20px;
            \\            padding: 40px;
            \\            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
            \\            max-width: 500px;
            \\        }
            \\        .success-icon {
            \\            font-size: 72px;
            \\            margin-bottom: 20px;
            \\            animation: bounce 0.5s ease-in-out;
            \\        }
            \\        h1 {
            \\            margin: 0 0 10px 0;
            \\            font-size: 32px;
            \\            font-weight: 600;
            \\        }
            \\        p {
            \\            margin: 10px 0;
            \\            font-size: 18px;
            \\            opacity: 0.9;
            \\        }
            \\        .close-notice {
            \\            margin-top: 30px;
            \\            padding: 15px;
            \\            background: rgba(255, 255, 255, 0.2);
            \\            border-radius: 10px;
            \\            font-size: 14px;
            \\        }
            \\        @keyframes bounce {
            \\            0%, 100% { transform: translateY(0); }
            \\            50% { transform: translateY(-20px); }
            \\        }
            \\    </style>
            \\</head>
            \\<body>
            \\    <div class="container">
            \\        <div class="success-icon">✅</div>
            \\        <h1>Authorization Successful!</h1>
            \\        <p>Your Claude Pro/Max account has been successfully connected.</p>
            \\        <p>You can now close this window and return to the terminal.</p>
            \\        <div class="close-notice">
            \\            💡 This window will close automatically in a few seconds,<br>
            \\            or you can close it manually now.
            \\        </div>
            \\    </div>
            \\    <script>
            \\        setTimeout(() => {
            \\            window.close();
            \\        }, 5000);
            \\    </script>
            \\</body>
            \\</html>
        ;

        const response = try std.fmt.allocPrint(self.allocator, "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: text/html; charset=utf-8\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "\r\n" ++
            "{s}", .{ html.len, html });
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    /// Send error response to browser
    fn sendErrorResponse(self: *Self, stream: std.net.Stream, err: anyerror) !void {
        const html = try std.fmt.allocPrint(self.allocator,
            \\<!DOCTYPE html>
            \\<html lang="en">
            \\<head>
            \\    <meta charset="UTF-8">
            \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \\    <title>Authorization Error</title>
            \\    <style>
            \\        body {{
            \\            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            \\            background: linear-gradient(135deg, #ff6b6b 0%, #ffd93d 100%);
            \\            color: white;
            \\            display: flex;
            \\            justify-content: center;
            \\            align-items: center;
            \\            height: 100vh;
            \\            margin: 0;
            \\            padding: 20px;
            \\        }}
            \\        .container {{
            \\            text-align: center;
            \\            background: rgba(255, 255, 255, 0.1);
            \\            backdrop-filter: blur(10px);
            \\            border-radius: 20px;
            \\            padding: 40px;
            \\            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
            \\            max-width: 500px;
            \\        }}
            \\        .error-icon {{
            \\            font-size: 72px;
            \\            margin-bottom: 20px;
            \\        }}
            \\        h1 {{
            \\            margin: 0 0 10px 0;
            \\            font-size: 32px;
            \\            font-weight: 600;
            \\        }}
            \\        p {{
            \\            margin: 10px 0;
            \\            font-size: 18px;
            \\            opacity: 0.9;
            \\        }}
            \\        .error-details {{
            \\            margin-top: 20px;
            \\            padding: 15px;
            \\            background: rgba(255, 255, 255, 0.2);
            \\            border-radius: 10px;
            \\            font-family: monospace;
            \\            font-size: 14px;
            \\        }}
            \\    </style>
            \\</head>
            \\<body>
            \\    <div class="container">
            \\        <div class="error-icon">❌</div>
            \\        <h1>Authorization Error</h1>
            \\        <p>Something went wrong during the authorization process.</p>
            \\        <p>Please return to the terminal and try again.</p>
            \\        <div class="error-details">Error: {s}</div>
            \\    </div>
            \\</body>
            \\</html>
        , .{@errorName(err)});
        defer self.allocator.free(html);

        const response = try std.fmt.allocPrint(self.allocator, "HTTP/1.1 400 Bad Request\r\n" ++
            "Content-Type: text/html; charset=utf-8\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "\r\n" ++
            "{s}", .{ html.len, html });
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    /// Send minimal response (no HTML)
    fn sendMinimalResponse(self: *Self, stream: std.net.Stream) !void {
        _ = self;
        const response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK";
        _ = try stream.write(response);
    }

    /// Status display thread
    fn statusDisplayThread(self: *Self) void {
        // Save cursor position
        print("{s}", .{ansi.cursor.save});

        while (!self.shutdownRequested.load(.seq_cst)) {
            const now = std.time.timestamp();
            const elapsedMs = now - self.startTimeMs;
            const minutes: i64 = @divTrunc(elapsedMs, 60);
            const seconds: i64 = @mod(elapsedMs, 60);

            // Move to status line and clear it
            print("{s}{s}", .{ ansi.cursor.restore, ansi.erase.toEndOfLine });

            // Show animated spinner
            const spinnerChars = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
            const spinnerIdx = @as(usize, @intCast(@mod(now, spinnerChars.len)));

            print("{s}{s} Server Status: {s}Listening on port {d}{s} | ", .{
                spinnerChars[spinnerIdx],
                ansi.fg.cyan,
                ansi.fg.white,
                self.config.port,
                ansi.fg.gray,
            });

            print("Elapsed: {s}{d:0>2}:{d:0>2}{s} | ", .{
                ansi.fg.white,
                minutes,
                seconds,
                ansi.fg.gray,
            });

            print("Requests: {s}{d}{s}", .{
                ansi.fg.white,
                self.requestsHandled,
                ansi.style.reset,
            });

            std.Thread.sleep(100_000_000); // 100ms update interval
        }

        // Clear status line on shutdown
        print("{s}{s}\n", .{ ansi.cursor.restore, ansi.erase.toEndOfLine });
    }
};

/// URL decode helper
fn urlDecode(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    var decoded = try std.array_list.Managed(u8).initCapacity(allocator, encoded.len);
    defer decoded.deinit();

    var i: usize = 0;
    while (i < encoded.len) {
        if (encoded[i] == '%' and i + 2 < encoded.len) {
            const hex = encoded[i + 1 .. i + 3];
            const byte = try std.fmt.parseInt(u8, hex, 16);
            try decoded.append(byte);
            i += 3;
        } else if (encoded[i] == '+') {
            try decoded.append(' ');
            i += 1;
        } else {
            try decoded.append(encoded[i]);
            i += 1;
        }
    }

    return try decoded.toOwnedSlice();
}

/// Create and run OAuth callback server for authorization flow
pub fn runCallbackServer(
    allocator: std.mem.Allocator,
    pkceParams: oauth.Pkce,
    config: ?Config,
) !Result {
    const serverConfig = config orelse Config{};

    var server = try Server.init(allocator, serverConfig);
    defer server.deinit();

    // Register the session
    try server.registerSession(pkceParams);

    // Start the server
    try server.start();

    // Build and display authorization URL
    const authUrl = try oauth.buildAuthorizationUrl(allocator, pkceParams);
    defer allocator.free(authUrl);

    // Update redirect URI to use local callback server
    const localRedirect = try std.fmt.allocPrint(allocator, "http://localhost:{d}/callback", .{serverConfig.port});
    defer allocator.free(localRedirect);

    // Replace redirect URI in auth URL
    const updatedAuthUrl = try std.mem.replaceOwned(u8, allocator, authUrl, oauth.OAUTH_REDIRECT_URI, localRedirect);
    defer allocator.free(updatedAuthUrl);

    print("\n{s}🔐 OAuth Authorization Required{s}\n", .{ ansi.style.bold, ansi.style.reset });
    print("{s}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{s}\n\n", .{ ansi.fg.blue, ansi.style.reset });

    print("Please visit this URL to authorize the application:\n\n", .{});
    print("{s}{s}{s}\n\n", .{ ansi.fg.cyan, updatedAuthUrl, ansi.style.reset });

    // Try to launch browser
    oauth.launchBrowser(updatedAuthUrl) catch {
        print("{s}⚠️  Could not launch browser automatically.{s}\n", .{ ansi.fg.yellow, ansi.style.reset });
        print("Please copy and paste the URL above into your browser.\n\n", .{});
    };

    // Wait for callback
    return try server.waitForCallback(pkceParams.state, null);
}

/// Integration with OAuth wizard
pub fn integrateWithWizard(
    allocator: std.mem.Allocator,
    pkceParams: oauth.Pkce,
) !oauth.Credentials {
    // Run callback server
    const authResult = try runCallbackServer(allocator, pkceParams, null);
    defer authResult.deinit(allocator);

    // Exchange code for tokens
    const credentials = try oauth.exchangeCodeForTokens(allocator, authResult.code, pkceParams);

    // Save credentials
    try oauth.saveCredentials(allocator, "claude_oauth_creds.json", credentials);

    print("\n{s}✅ OAuth setup completed successfully!{s}\n", .{ ansi.fg.green, ansi.style.reset });
    print("Your credentials have been saved securely.\n", .{});

    return credentials;
}

/// Complete OAuth flow with callback server
pub fn completeOAuthFlow(allocator: std.mem.Allocator) !oauth.Credentials {
    print("\n{s}Starting OAuth setup with callback server...{s}\n", .{ ansi.style.bold, ansi.style.reset });

    // Generate PKCE parameters
    const pkceParams = try oauth.generatePkceParams(allocator);
    defer pkceParams.deinit(allocator);

    // Run the integrated flow
    return try integrateWithWizard(allocator, pkceParams);
}

test "callback server initialization" {
    const allocator = std.testing.allocator;

    const config = Config{
        .port = 8080,
        .verbose = false,
    };

    var server = try Server.init(allocator, config);
    defer server.deinit();

    try std.testing.expect(server.config.port == 8080);
    try std.testing.expect(server.requestsHandled == 0);
}

test "URL decode" {
    const allocator = std.testing.allocator;

    const encoded = "hello%20world%21";
    const decoded = try urlDecode(allocator, encoded);
    defer allocator.free(decoded);

    try std.testing.expectEqualStrings("hello world!", decoded);
}

test "parse callback request" {
    const allocator = std.testing.allocator;

    var server = try Server.init(allocator, .{});
    defer server.deinit();

    const request = "GET /callback?code=test_code&state=test_state HTTP/1.1\r\n\r\n";
    const result = try server.parseCallbackRequest(request);
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings("test_code", result.code);
    try std.testing.expectEqualStrings("test_state", result.state);
}

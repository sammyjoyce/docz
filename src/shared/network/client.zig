//! UI-free Network Service interface

const std = @import("std");
const curl = @import("curl.zig");
const sse = @import("sse.zig");

pub const Error = error{
    Timeout,
    Connection,
    BadStatus,
    Decode,
    Canceled,
};

pub const NetworkRequest = struct {
    method: []const u8 = "GET",
    url: []const u8,
    headers: []const []const u8 = &.{},
    body: ?[]const u8 = null,
    timeout_ms: u32 = 30000,
};

pub const NetworkResponse = struct {
    status: u16,
    body: []const u8,
};

pub const NetworkEvent = struct {
    event: []const u8 = "message",
    data: []const u8,
};

pub const Service = struct {
    pub fn request(alloc: std.mem.Allocator, req: NetworkRequest) Error!NetworkResponse {
        var client = try curl.HTTPClient.init(alloc);
        defer client.deinit();

        // Convert headers of form "Name: Value" to curl.Header
        var headersList = std.ArrayListUnmanaged(curl.Header){};
        defer headersList.deinit(alloc);
        for (req.headers) |h| {
            if (std.mem.indexOfScalar(u8, h, ':')) |pos| {
                const name = std.mem.trim(u8, h[0..pos], " \t");
                const value = std.mem.trim(u8, h[pos + 1 ..], " \t");
                try headersList.append(alloc, .{ .name = name, .value = value });
            } else {
                // Skip malformed header entries
                std.log.warn("Skipping malformed header (missing colon): '{s}'", .{h});
            }
        }

        const method: curl.HTTPMethod = blk: {
            if (std.mem.eql(u8, req.method, "GET")) break :blk .GET;
            if (std.mem.eql(u8, req.method, "POST")) break :blk .POST;
            if (std.mem.eql(u8, req.method, "PUT")) break :blk .PUT;
            if (std.mem.eql(u8, req.method, "DELETE")) break :blk .DELETE;
            if (std.mem.eql(u8, req.method, "PATCH")) break :blk .PATCH;
            break :blk .GET;
        };

        const http_req = curl.HTTPRequest{
            .method = method,
            .url = req.url,
            .headers = headersList.items,
            .body = req.body,
            .timeout_ms = req.timeout_ms,
            .follow_redirects = true,
        };

        const http_resp = client.request(http_req) catch |err| switch (err) {
            curl.HTTPError.Timeout => return Error.Timeout,
            curl.HTTPError.Error => return Error.Connection,
            curl.HTTPError.TlsError => return Error.Connection,
            curl.HTTPError.InvalidURL => return Error.BadStatus,
            curl.HTTPError.OutOfMemory => return Error.Decode,
            else => return Error.Connection,
        };
        defer http_resp.deinit();

        const body = try alloc.dupe(u8, http_resp.body);
        return NetworkResponse{ .status = http_resp.status_code, .body = body };
    }

    pub fn stream(alloc: std.mem.Allocator, req: NetworkRequest, on_chunk: *const fn ([]const u8) void) Error!void {
        var client = try curl.HTTPClient.init(alloc);
        defer client.deinit();

        // Convert headers
        var headersList = std.ArrayListUnmanaged(curl.Header){};
        defer headersList.deinit(alloc);
        for (req.headers) |h| {
            if (std.mem.indexOfScalar(u8, h, ':')) |pos| {
                const name = std.mem.trim(u8, h[0..pos], " \t");
                const value = std.mem.trim(u8, h[pos + 1 ..], " \t");
                try headersList.append(alloc, .{ .name = name, .value = value });
            }
        }

        const method: curl.HTTPMethod = if (std.mem.eql(u8, req.method, "POST")) .POST else .GET;
        const http_req = curl.HTTPRequest{
            .method = method,
            .url = req.url,
            .headers = headersList.items,
            .body = req.body,
            .timeout_ms = req.timeout_ms,
            .follow_redirects = true,
        };

        _ = client.streamRequest(http_req, streamChunkThunk, @ptrFromInt(@intFromPtr(on_chunk))) catch |err| switch (err) {
            curl.HTTPError.Timeout => return Error.Timeout,
            curl.HTTPError.Error => return Error.Connection,
            else => return Error.Connection,
        };
    }

    pub fn sse(alloc: std.mem.Allocator, req: NetworkRequest, on_event: *const fn (NetworkEvent) void) Error!void {
        // Basic SSE adapter using streaming; parse lines and dispatch minimal events
        var buffer = std.ArrayListUnmanaged(u8){};
        defer buffer.deinit(alloc);

        const Self = struct {
            on_event: *const fn (NetworkEvent) void,
            alloc: std.mem.Allocator,
            buf: *std.ArrayListUnmanaged(u8),
        };
        var ctx = Self{ .on_event = on_event, .alloc = alloc, .buf = &buffer };

        // Wire our local callback by calling the HTTP client directly:
        var client = try curl.HTTPClient.init(alloc);
        defer client.deinit();

        var headersList = std.ArrayListUnmanaged(curl.Header){};
        defer headersList.deinit(alloc);
        for (req.headers) |h| {
            if (std.mem.indexOfScalar(u8, h, ':')) |pos| {
                const name = std.mem.trim(u8, h[0..pos], " \t");
                const value = std.mem.trim(u8, h[pos + 1 ..], " \t");
                try headersList.append(alloc, .{ .name = name, .value = value });
            }
        }
        const http_req = curl.HTTPRequest{
            .method = .GET,
            .url = req.url,
            .headers = headersList.items,
            .body = req.body,
            .timeout_ms = req.timeout_ms,
            .follow_redirects = true,
        };
        _ = client.streamRequest(http_req, streamChunkThunkWithCtx, @ptrCast(&ctx)) catch |err| switch (err) {
            curl.HTTPError.Timeout => return Error.Timeout,
            curl.HTTPError.Error => return Error.Connection,
            else => return Error.Connection,
        };
    }

    pub fn download(alloc: std.mem.Allocator, req: NetworkRequest, path: []const u8) Error!void {
        const resp = try Service.request(alloc, req);
        defer alloc.free(resp.body);
        var file = std.fs.cwd().createFile(path, .{ .truncate = true }) catch return Error.Connection;
        defer file.close();
        try file.writeAll(resp.body);
    }
};

/// Duck-typed client adapter
///
/// Exposes a uniform API over any backend type `T` that provides the
/// following declarations (no formal interface needed):
///   - `request(alloc: std.mem.Allocator, req: NetworkRequest) Error!NetworkResponse`
///   - `stream(alloc: std.mem.Allocator, req: NetworkRequest, on_chunk: *const fn([]const u8) void) Error!void`
///   - `sse(alloc: std.mem.Allocator, req: NetworkRequest, on_event: *const fn(NetworkEvent) void) Error!void`
///
/// Usage:
///   const net = @import("../network/mod.zig");
///   const Client = net.client.use(MyBackend);
///   const resp = try Client.request(alloc, .{ .url = "https://example.com" });
pub fn use(comptime T: type) type {
    comptime {
        if (!@hasDecl(T, "request")) @compileError("backend is missing required decl 'request'");
        if (!@hasDecl(T, "stream")) @compileError("backend is missing required decl 'stream'");
        if (!@hasDecl(T, "sse")) @compileError("backend is missing required decl 'sse'");
    }

    return struct {
        /// Re-export types for convenience
        pub const Error = @This().ErrorAlias;
        pub const NetworkRequest = @This().RequestAlias;
        pub const NetworkResponse = @This().ResponseAlias;
        pub const NetworkEvent = @This().EventAlias;

        const ErrorAlias = Error; // from outer file
        const RequestAlias = NetworkRequest;
        const ResponseAlias = NetworkResponse;
        const EventAlias = NetworkEvent;

        /// Forward directly to backend declarations. We intentionally do not
        /// constrain signatures beyond name presence to keep it duck-typed.
        pub const request = T.request;
        pub const stream = T.stream;
        pub const sse = T.sse;

        /// Portable helper implemented here to avoid duplication.
        pub fn download(alloc: std.mem.Allocator, req: NetworkRequest, path: []const u8) Error!void {
            const resp = try T.request(alloc, req);
            defer alloc.free(resp.body);
            var file = std.fs.cwd().createFile(path, .{ .truncate = true }) catch return Error.Connection;
            defer file.close();
            try file.writeAll(resp.body);
        }
    };
}

// Thin wrappers to bridge function pointer types for curl streaming
fn streamChunkThunk(chunk: []const u8, context: *anyopaque) void {
    // Context carries a pointer-encoded function pointer to on_chunk
    const fp_int: usize = @intFromPtr(context);
    const cb: *const fn ([]const u8) void = @ptrFromInt(fp_int);
    cb(chunk);
}

fn streamChunkThunkWithCtx(chunk: []const u8, context: *anyopaque) void {
    const Self = struct {
        on_event: *const fn (NetworkEvent) void,
        alloc: std.mem.Allocator,
        buf: *std.ArrayList(u8),
    };
    const self: *Self = @ptrCast(@alignCast(context));
    // Reuse SSE parser for robustness if needed later; for now, dispatch minimal events in sse()
    self.buf.appendSlice(self.alloc, chunk) catch return;
    var it = std.mem.splitScalar(u8, self.buf.items, '\n');
    var consumed: usize = 0;
    while (it.next()) |line| {
        consumed += line.len + 1;
        if (line.len == 0) continue;
        self.on_event(NetworkEvent{ .data = line });
    }
    if (consumed > 0 and consumed <= self.buf.items.len) {
        const remaining = self.buf.items[consumed..];
        _ = self.buf.replaceRange(self.alloc, 0, self.buf.items.len, &[_]u8{}) catch return;
        _ = self.buf.appendSlice(self.alloc, remaining) catch return;
    }
}

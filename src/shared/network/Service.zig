//! UI-free Network Service interface

const std = @import("std");
const curl = @import("curl.zig");
const sse = @import("sse.zig");

pub const NetworkError = error{
    Timeout,
    Connection,
    BadStatus,
    Decode,
    Canceled,
};

pub const Request = struct {
    method: []const u8 = "GET",
    url: []const u8,
    headers: []const []const u8 = &.{},
    body: ?[]const u8 = null,
    timeout_ms: u32 = 30000,
};

pub const Response = struct {
    status: u16,
    body: []const u8,
};

pub const Event = struct {
    event: []const u8 = "message",
    data: []const u8,
};

pub const Service = struct {
    pub fn request(alloc: std.mem.Allocator, req: Request) NetworkError!Response {
        var client = try curl.HTTPClient.init(alloc);
        defer client.deinit();

        // Convert headers of form "Name: Value" to curl.Header
        var headers_list = std.ArrayListUnmanaged(curl.Header){};
        defer headers_list.deinit(alloc);
        for (req.headers) |h| {
            if (std.mem.indexOfScalar(u8, h, ':')) |pos| {
                const name = std.mem.trim(u8, h[0..pos], " \t");
                const value = std.mem.trim(u8, h[pos + 1 ..], " \t");
                try headers_list.append(alloc, .{ .name = name, .value = value });
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
            .headers = headers_list.items,
            .body = req.body,
            .timeout_ms = req.timeout_ms,
            .follow_redirects = true,
        };

        const http_resp = client.request(http_req) catch |err| switch (err) {
            curl.HTTPError.Timeout => return NetworkError.Timeout,
            curl.HTTPError.NetworkError => return NetworkError.Connection,
            curl.HTTPError.TlsError => return NetworkError.Connection,
            curl.HTTPError.InvalidURL => return NetworkError.BadStatus,
            curl.HTTPError.OutOfMemory => return NetworkError.Decode,
            else => return NetworkError.Connection,
        };
        defer http_resp.deinit();

        const body = try alloc.dupe(u8, http_resp.body);
        return Response{ .status = http_resp.status_code, .body = body };
    }

    pub fn stream(alloc: std.mem.Allocator, req: Request, on_chunk: *const fn ([]const u8) void) NetworkError!void {
        var client = try curl.HTTPClient.init(alloc);
        defer client.deinit();

        // Convert headers
        var headers_list = std.ArrayListUnmanaged(curl.Header){};
        defer headers_list.deinit(alloc);
        for (req.headers) |h| {
            if (std.mem.indexOfScalar(u8, h, ':')) |pos| {
                const name = std.mem.trim(u8, h[0..pos], " \t");
                const value = std.mem.trim(u8, h[pos + 1 ..], " \t");
                try headers_list.append(alloc, .{ .name = name, .value = value });
            }
        }

        const method: curl.HTTPMethod = if (std.mem.eql(u8, req.method, "POST")) .POST else .GET;
        const http_req = curl.HTTPRequest{
            .method = method,
            .url = req.url,
            .headers = headers_list.items,
            .body = req.body,
            .timeout_ms = req.timeout_ms,
            .follow_redirects = true,
        };

        _ = client.streamRequest(http_req, streamChunkThunk, @ptrFromInt(@intFromPtr(on_chunk))) catch |err| switch (err) {
            curl.HTTPError.Timeout => return NetworkError.Timeout,
            curl.HTTPError.NetworkError => return NetworkError.Connection,
            else => return NetworkError.Connection,
        };
    }

    pub fn sse(alloc: std.mem.Allocator, req: Request, on_event: *const fn (Event) void) NetworkError!void {
        // Basic SSE adapter using streaming; parse lines and dispatch minimal events
        var buffer = std.ArrayListUnmanaged(u8){};
        defer buffer.deinit(alloc);

        const Self = struct {
            on_event: *const fn (Event) void,
            alloc: std.mem.Allocator,
            buf: *std.ArrayListUnmanaged(u8),
        };
        var ctx = Self{ .on_event = on_event, .alloc = alloc, .buf = &buffer };

        // Wire our local callback by calling the HTTP client directly:
        var client = try curl.HTTPClient.init(alloc);
        defer client.deinit();

        var headers_list = std.ArrayListUnmanaged(curl.Header){};
        defer headers_list.deinit(alloc);
        for (req.headers) |h| {
            if (std.mem.indexOfScalar(u8, h, ':')) |pos| {
                const name = std.mem.trim(u8, h[0..pos], " \t");
                const value = std.mem.trim(u8, h[pos + 1 ..], " \t");
                try headers_list.append(alloc, .{ .name = name, .value = value });
            }
        }
        const http_req = curl.HTTPRequest{
            .method = .GET,
            .url = req.url,
            .headers = headers_list.items,
            .body = req.body,
            .timeout_ms = req.timeout_ms,
            .follow_redirects = true,
        };
        _ = client.streamRequest(http_req, streamChunkThunkWithCtx, @ptrCast(&ctx)) catch |err| switch (err) {
            curl.HTTPError.Timeout => return NetworkError.Timeout,
            curl.HTTPError.NetworkError => return NetworkError.Connection,
            else => return NetworkError.Connection,
        };
    }

    pub fn download(alloc: std.mem.Allocator, req: Request, path: []const u8) NetworkError!void {
        const resp = try Service.request(alloc, req);
        defer alloc.free(resp.body);
        var file = std.fs.cwd().createFile(path, .{ .truncate = true }) catch return NetworkError.Connection;
        defer file.close();
        try file.writeAll(resp.body);
    }
};

// Thin wrappers to bridge function pointer types for curl streaming
fn streamChunkThunk(chunk: []const u8, context: *anyopaque) void {
    // Context carries a pointer-encoded function pointer to on_chunk
    const fp_int: usize = @intFromPtr(context);
    const cb: *const fn ([]const u8) void = @ptrFromInt(fp_int);
    cb(chunk);
}

fn streamChunkThunkWithCtx(chunk: []const u8, context: *anyopaque) void {
    const Self = struct {
        on_event: *const fn (Event) void,
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
        self.on_event(Event{ .data = line });
    }
    if (consumed > 0 and consumed <= self.buf.items.len) {
        const remaining = self.buf.items[consumed..];
        _ = self.buf.replaceRange(self.alloc, 0, self.buf.items.len, &[_]u8{}) catch return;
        _ = self.buf.appendSlice(self.alloc, remaining) catch return;
    }
}

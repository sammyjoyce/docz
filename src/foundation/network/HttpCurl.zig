//! cURL-based implementation of the Http interface
//! Layer: network (standalone)

const std = @import("std");
const Http = @import("Http.zig");
const curl = @import("curl.zig");

const Self = @This();

allocator: std.mem.Allocator,
curl_client: curl.HTTPClient,

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .curl_client = try curl.HTTPClient.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.curl_client.deinit();
}

/// Get the Http.Client interface for this implementation
pub fn client(self: *Self) Http.Client {
    return .{
        .ptr = self,
        .vtable = &vtable,
    };
}

const vtable = Http.Client.VTable{
    .request = request,
    .deinit = deinitVTable,
};

fn request(ptr: *anyopaque, req: Http.Request) Http.Error!Http.Response {
    const self: *Self = @ptrCast(@alignCast(ptr));

    // Convert Http.Request to curl.HTTPRequest
    const curl_headers = try self.allocator.alloc(curl.Header, req.headers.len);
    defer self.allocator.free(curl_headers);

    for (req.headers, 0..) |header, i| {
        curl_headers[i] = .{
            .name = header.name,
            .value = header.value,
        };
    }

    const curl_req = curl.HTTPRequest{
        .method = switch (req.method) {
            .GET => .GET,
            .POST => .POST,
            .PUT => .PUT,
            .DELETE => .DELETE,
            .PATCH => .PATCH,
            .HEAD, .OPTIONS => .GET, // Map unsupported methods to GET
        },
        .url = req.url,
        .headers = curl_headers,
        .body = req.body,
        .timeout_ms = req.timeout_ms,
        .follow_redirects = req.follow_redirects,
        .max_redirects = req.max_redirects,
        .verify_ssl = req.verify_ssl,
        .verbose = req.verbose,
    };

    // Perform request and convert response
    const curl_resp = self.curl_client.request(curl_req) catch |err| {
        return Http.asHttpError(err);
    };

    // Move ownership to Http.Response
    return .{
        .status_code = curl_resp.status_code,
        .headers = curl_resp.headers,
        .body = curl_resp.body,
        .allocator = curl_resp.allocator,
    };
}

fn deinitVTable(ptr: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.deinit();
}

test "HttpCurl adapter" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var http_curl = try init(allocator);
    defer http_curl.deinit();

    const http_client = http_curl.client();
    _ = http_client;

    // Would need actual network to test further
}

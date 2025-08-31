//! Provider-agnostic HTTP client interface
//! Layer: network (standalone)

const std = @import("std");

pub const Error = error{
    Transport,
    Timeout,
    Status,
    Protocol,
    InvalidURL,
    OutOfMemory,
    Canceled,
    TlsError,
};

pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Request = struct {
    method: Method = .GET,
    url: []const u8,
    headers: []const Header = &[_]Header{},
    body: ?[]const u8 = null,
    timeout_ms: u32 = 30000,
    follow_redirects: bool = false,
    max_redirects: u32 = 5,
    verify_ssl: bool = true,
    verbose: bool = false,
};

pub const Response = struct {
    status_code: u16,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Response) void {
        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
        self.allocator.free(self.body);
    }

    pub fn getHeader(self: *const Response, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }
};

/// HTTP client interface - implementations should provide this API
pub const Client = struct {
    const Self = @This();

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        request: *const fn (ptr: *anyopaque, req: Request) Error!Response,
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub fn request(self: Self, req: Request) Error!Response {
        return self.vtable.request(self.ptr, req);
    }

    pub fn deinit(self: Self) void {
        self.vtable.deinit(self.ptr);
    }
};

/// Convert implementation-specific errors to generic HTTP errors
pub fn asHttpError(err: anytype) Error {
    const T = @TypeOf(err);
    if (T == Error) return err;

    // Map common error types
    return switch (err) {
        error.OutOfMemory => Error.OutOfMemory,
        error.Timeout => Error.Timeout,
        error.InvalidURL => Error.InvalidURL,
        error.NetworkError => Error.Transport,
        error.TlsError => Error.TlsError,
        error.HTTPError => Error.Status,
        error.CurlInit, error.CurlPerform => Error.Transport,
        error.InvalidResponse => Error.Protocol,
        error.Aborted, error.Canceled => Error.Canceled,
        else => Error.Transport,
    };
}

test "Http interface basics" {
    const testing = std.testing;

    const req = Request{
        .method = .GET,
        .url = "https://example.com",
    };

    try testing.expectEqual(req.method, .GET);
    try testing.expectEqualStrings(req.url, "https://example.com");
    try testing.expectEqual(req.timeout_ms, 30000);
}

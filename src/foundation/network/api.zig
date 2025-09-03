//! Network port: small runtime interface for UI/TUI consumers
//!
//! Goal: decouple presentation from concrete HTTP/auth backends. UIs depend
//! only on this thin interface. Engines or services provide implementations.

const std = @import("std");

pub const Allocator = std.mem.Allocator;

pub const Error = error{
    Connection,
    Timeout,
    HttpStatus,
    Decode,
    Unexpected,
};

pub const Response = struct {
    status: u16,
    body: []u8, // owned by caller allocator
    headers: []const Header = &.{},

    pub fn deinit(self: *Response, allocator: Allocator) void {
        allocator.free(self.body);
    }
};

pub const Header = struct { name: []const u8, value: []const u8 };

pub const Request = struct {
    method: []const u8 = "GET",
    url: []const u8,
    headers: []const Header = &.{},
    body: ?[]const u8 = null,
};

pub const NetworkClient = struct {
    const Self = @This();
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        request: *const fn (ctx: *anyopaque, allocator: Allocator, req: Request) Error!Response,
        // Optional future extensions (SSE, websockets) can be added here.
    };

    pub fn request(self: Self, allocator: Allocator, req: Request) Error!Response {
        return self.vtable.request(self.ctx, allocator, req);
    }
};


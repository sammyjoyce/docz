//! UI-free Network Service interface

const std = @import("std");

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
        _ = alloc;
        _ = req;
        return NetworkError.Canceled; // placeholder
    }
    pub fn stream(alloc: std.mem.Allocator, req: Request, on_chunk: *const fn ([]const u8) void) NetworkError!void {
        _ = alloc;
        _ = req;
        _ = on_chunk;
        return NetworkError.Canceled; // placeholder
    }
    pub fn sse(alloc: std.mem.Allocator, req: Request, on_event: *const fn (Event) void) NetworkError!void {
        _ = alloc;
        _ = req;
        _ = on_event;
        return NetworkError.Canceled; // placeholder
    }
    pub fn download(alloc: std.mem.Allocator, req: Request, path: []const u8) NetworkError!void {
        _ = alloc;
        _ = req;
        _ = path;
        return NetworkError.Canceled; // placeholder
    }
};

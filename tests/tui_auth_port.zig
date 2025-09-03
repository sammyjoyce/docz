//! Tests for TUI AuthenticationManager via AuthPort using mock adapter

const std = @import("std");
const testing = std.testing;

const foundation = @import("foundation");
const tui = foundation.tui;

test "auth manager with mock oauth credentials authenticates and returns header" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Mock port with oauth mode, short TTL
    const port = foundation.adapters.auth_mock.make(.{
        .mode = .oauth,
        .access_token = "token_abc",
        .refresh_token = "refresh_xyz",
        .ttl_secs = 300,
    });

    var mgr = try tui.AuthenticationManager.init(alloc, port);
    defer mgr.deinit();

    try mgr.loadCredentials();
    try testing.expect(mgr.isAuthenticated());

    const hdr = try mgr.getAuthorizationHeader();
    try testing.expect(hdr != null);
    const s = hdr.?;
    defer alloc.free(s);
    try testing.expect(std.mem.startsWith(u8, s, "Bearer "));
}

test "auth manager refreshes soon-to-expire oauth credentials" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // TTL already expired; refreshIfNeeded should replace immediately
    const port = foundation.adapters.auth_mock.make(.{
        .mode = .oauth,
        .access_token = "token_old",
        .refresh_token = "refresh_old",
        .ttl_secs = 0,
    });

    var mgr = try tui.AuthenticationManager.init(alloc, port);
    defer mgr.deinit();
    try mgr.loadCredentials();

    try mgr.refreshTokensIfNeeded();

    const hdr = try mgr.getAuthorizationHeader();
    try testing.expect(hdr != null);
    const s = hdr.?;
    defer alloc.free(s);
    try testing.expect(std.mem.startsWith(u8, s, "Bearer "));
}

test "auth manager supports api key mode" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const port = foundation.adapters.auth_mock.make(.{
        .mode = .api_key,
        .api_key = "k123",
    });

    var mgr = try tui.AuthenticationManager.init(alloc, port);
    defer mgr.deinit();
    try mgr.loadCredentials();

    const hdr = try mgr.getAuthorizationHeader();
    try testing.expect(hdr != null);
    const s = hdr.?;
    defer alloc.free(s);
    try testing.expect(std.mem.startsWith(u8, s, "x-api-key: "));
}

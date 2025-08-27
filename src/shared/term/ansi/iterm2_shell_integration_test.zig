const std = @import("std");
const iterm2_si = @import("iterm2_shell_integration.zig");

test "basic functionality" {
    const allocator = std.testing.allocator;

    // Test remote host identification
    const remote = try iterm2_si.markRemoteHost(allocator, .{
        .hostname = "example.com",
    });
    defer allocator.free(remote);
    try std.testing.expect(std.mem.eql(u8, remote, "RemoteHost=example.com"));

    // Test shell integration mode
    const enable = try iterm2_si.enableShellIntegration(allocator);
    defer allocator.free(enable);
    try std.testing.expect(std.mem.eql(u8, enable, "ShellIntegration=2"));

    // Test badge support
    const badge = try iterm2_si.setBadge(allocator, "Hello");
    defer allocator.free(badge);
    try std.testing.expect(std.mem.eql(u8, badge, "SetBadge=Hello"));

    // Test attention requests
    const attention = try iterm2_si.requestAttention(allocator, null);
    defer allocator.free(attention);
    try std.testing.expect(std.mem.eql(u8, attention, "RequestAttention"));

    // Test command status
    const cmd_start = try iterm2_si.markCommandStart(allocator, .{
        .command = "test",
    });
    defer allocator.free(cmd_start);
    try std.testing.expect(std.mem.eql(u8, cmd_start, "CommandStart=test"));

    // Test marks
    const mark = try iterm2_si.setMark(allocator, .command, "test");
    defer allocator.free(mark);
    try std.testing.expect(std.mem.eql(u8, mark, "SetMark=command;test"));

    // Test download
    const download = try iterm2_si.triggerDownload(allocator, .{
        .url = "http://example.com",
    });
    defer allocator.free(download);
    try std.testing.expect(std.mem.eql(u8, download, "Download=http://example.com"));
}

test "convenience functions" {
    const allocator = std.testing.allocator;

    // Test command execution convenience
    const exec = try iterm2_si.Convenience.executeCommand(allocator, "ls", "/tmp");
    defer allocator.free(exec);
    try std.testing.expect(std.mem.eql(u8, exec, "CommandStart=ls;cwd=/tmp"));

    // Test command completion convenience
    const complete = try iterm2_si.Convenience.completeCommand(allocator, "ls", 0, 100);
    defer allocator.free(complete);
    try std.testing.expect(std.mem.eql(u8, complete, "CommandEnd=ls;exit=0;duration=100"));
}

test "error handling" {
    const allocator = std.testing.allocator;

    // Test that functions handle empty inputs gracefully
    const empty_badge = try iterm2_si.setBadge(allocator, "");
    defer allocator.free(empty_badge);
    try std.testing.expect(std.mem.eql(u8, empty_badge, "SetBadge="));

    // Test clear functions
    const clear_remote = try iterm2_si.clearRemoteHost(allocator);
    defer allocator.free(clear_remote);
    try std.testing.expect(std.mem.eql(u8, clear_remote, "RemoteHost="));

    const clear_badge = try iterm2_si.clearBadge(allocator);
    defer allocator.free(clear_badge);
    try std.testing.expect(std.mem.eql(u8, clear_badge, "SetBadge="));
}

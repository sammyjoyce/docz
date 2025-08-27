const std = @import("std");
const caps_mod = @import("../caps.zig");
const passthrough = @import("passthrough.zig");
const seqcfg = @import("ansi.zon");

pub const TermCaps = caps_mod.TermCaps;

/// iTerm2 Shell Integration Module
/// Implements iTerm2-specific shell integration features based on Charmbracelet's approach
/// Provides advanced terminal integration capabilities beyond standard FinalTerm markers
///
/// Reference: https://iterm2.com/documentation-shell-integration.html
fn oscTerminator() []const u8 {
    return if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel"))
        seqcfg.osc.bel
    else
        seqcfg.osc.st;
}

fn sanitize(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    // Filter control chars that could break OSC framing
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(alloc);

    try out.ensureTotalCapacity(alloc, s.len);
    for (s) |ch| {
        if (ch == 0x1b or ch == 0x07) continue; // ESC, BEL
        out.appendAssumeCapacity(ch);
    }
    return try out.toOwnedSlice(alloc);
}

fn buildIterm2Sequence(alloc: std.mem.Allocator, payload: []const u8) ![]u8 {
    const st = oscTerminator();
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    try buf.appendSlice(alloc, "\x1b]");
    // OSC 1337 ; payload
    var tmp: [16]u8 = undefined;
    const code = try std.fmt.bufPrint(&tmp, "{d}", .{seqcfg.osc.ops.iterm2});
    try buf.appendSlice(alloc, code);
    try buf.append(alloc, ';');
    try buf.appendSlice(alloc, payload);
    try buf.appendSlice(alloc, st);
    return try buf.toOwnedSlice(alloc);
}

/// Write a raw iTerm2 OSC 1337 sequence with the provided data payload.
pub fn writeITerm2Sequence(writer: anytype, alloc: std.mem.Allocator, caps: TermCaps, payload: []const u8) !void {
    if (!caps.supportsITerm2Osc1337) return error.Unsupported;
    const clean = try sanitize(alloc, payload);
    defer alloc.free(clean);
    const seq = try buildIterm2Sequence(alloc, clean);
    defer alloc.free(seq);
    try passthrough.writeWithPassthrough(writer, caps, seq);
}

// ============================================================================
// 1. REMOTE HOST IDENTIFICATION
// ============================================================================

/// Remote host configuration for SSH sessions
pub const RemoteHostConfig = struct {
    hostname: []const u8,
    username: ?[]const u8 = null,
    port: ?u16 = null,
};

/// Mark the start of an SSH connection to a remote host
/// This helps iTerm2 track when you're on a remote system
pub fn markRemoteHost(alloc: std.mem.Allocator, config: RemoteHostConfig) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    try buf.appendSlice(alloc, "RemoteHost=");
    try buf.appendSlice(alloc, config.hostname);

    if (config.username) |user| {
        try buf.append(alloc, '@');
        try buf.appendSlice(alloc, user);
    }

    if (config.port) |port| {
        var port_str: [8]u8 = undefined;
        const port_slice = try std.fmt.bufPrint(&port_str, ":{d}", .{port});
        try buf.appendSlice(alloc, port_slice);
    }

    return try buf.toOwnedSlice(alloc);
}

/// Clear remote host marking (back to local)
pub fn clearRemoteHost(alloc: std.mem.Allocator) ![]u8 {
    return try alloc.dupe(u8, "RemoteHost=");
}

// ============================================================================
// 2. CURRENT USER TRACKING
// ============================================================================

/// Set the current user for shell integration
/// This helps iTerm2 display the correct user in various UI elements
pub fn setCurrentUser(alloc: std.mem.Allocator, username: []const u8) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    try buf.appendSlice(alloc, "SetUser=");
    try buf.appendSlice(alloc, username);

    return try buf.toOwnedSlice(alloc);
}

/// Get current user from environment (helper function)
pub fn getCurrentUser(alloc: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(alloc, "USER")) |user| {
        return user;
    } else |_| {
        // Fallback to whoami command or default
        return try alloc.dupe(u8, "unknown");
    }
}

// ============================================================================
// 3. SHELL INTEGRATION MODE
// ============================================================================

/// Shell integration mode configuration
pub const ShellIntegrationMode = enum {
    off,
    basic,
    full,
};

/// Activate iTerm2 shell integration mode
/// This enables various shell integration features
pub fn setShellIntegrationMode(alloc: std.mem.Allocator, mode: ShellIntegrationMode) ![]u8 {
    const mode_str = switch (mode) {
        .off => "ShellIntegration=0",
        .basic => "ShellIntegration=1",
        .full => "ShellIntegration=2",
    };
    return try alloc.dupe(u8, mode_str);
}

/// Enable full shell integration (convenience function)
pub fn enableShellIntegration(alloc: std.mem.Allocator) ![]u8 {
    return try setShellIntegrationMode(alloc, .full);
}

/// Disable shell integration (convenience function)
pub fn disableShellIntegration(alloc: std.mem.Allocator) ![]u8 {
    return try setShellIntegrationMode(alloc, .off);
}

// ============================================================================
// 4. COMMAND STATUS INDICATORS
// ============================================================================

/// Command status information
pub const CommandStatus = struct {
    command: []const u8,
    exit_code: ?i32 = null,
    duration_ms: ?u64 = null,
    working_directory: ?[]const u8 = null,
};

/// Mark the start of command execution with enhanced status
pub fn markCommandStart(alloc: std.mem.Allocator, status: CommandStatus) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    try buf.appendSlice(alloc, "CommandStart=");
    try buf.appendSlice(alloc, status.command);

    if (status.working_directory) |cwd| {
        try buf.append(alloc, ';');
        try buf.appendSlice(alloc, "cwd=");
        try buf.appendSlice(alloc, cwd);
    }

    return try buf.toOwnedSlice(alloc);
}

/// Mark command completion with detailed status
pub fn markCommandEnd(alloc: std.mem.Allocator, status: CommandStatus) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    try buf.appendSlice(alloc, "CommandEnd=");
    try buf.appendSlice(alloc, status.command);

    if (status.exit_code) |code| {
        var code_str: [16]u8 = undefined;
        const code_slice = try std.fmt.bufPrint(&code_str, ";exit={d}", .{code});
        try buf.appendSlice(alloc, code_slice);
    }

    if (status.duration_ms) |duration| {
        var duration_str: [32]u8 = undefined;
        const duration_slice = try std.fmt.bufPrint(&duration_str, ";duration={d}", .{duration});
        try buf.appendSlice(alloc, duration_slice);
    }

    return try buf.toOwnedSlice(alloc);
}

// ============================================================================
// 5. ATTENTION REQUESTS
// ============================================================================

/// Request terminal attention/notification
pub fn requestAttention(alloc: std.mem.Allocator, message: ?[]const u8) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    try buf.appendSlice(alloc, "RequestAttention");

    if (message) |msg| {
        try buf.append(alloc, '=');
        try buf.appendSlice(alloc, msg);
    }

    return try buf.toOwnedSlice(alloc);
}

/// Request attention with a specific message
pub fn notify(alloc: std.mem.Allocator, message: []const u8) ![]u8 {
    return try requestAttention(alloc, message);
}

// ============================================================================
// 6. BADGE SUPPORT
// ============================================================================

/// Set the iTerm2 badge text
/// The badge appears in the terminal window's title bar or tab
pub fn setBadge(alloc: std.mem.Allocator, text: []const u8) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    try buf.appendSlice(alloc, "SetBadge=");
    try buf.appendSlice(alloc, text);

    return try buf.toOwnedSlice(alloc);
}

/// Clear the badge
pub fn clearBadge(alloc: std.mem.Allocator) ![]u8 {
    return try alloc.dupe(u8, "SetBadge=");
}

/// Set badge with format string (convenience function)
pub fn setBadgeFormat(alloc: std.mem.Allocator, comptime format: []const u8, args: anytype) ![]u8 {
    const text = try std.fmt.allocPrint(alloc, format, args);
    defer alloc.free(text);
    return try setBadge(alloc, text);
}

// ============================================================================
// 7. ANNOTATIONS
// ============================================================================

/// Annotation configuration
pub const AnnotationConfig = struct {
    text: []const u8,
    x: ?i32 = null, // X coordinate (pixels from left)
    y: ?i32 = null, // Y coordinate (pixels from top)
    length: ?u32 = null, // Length of annotated text
    url: ?[]const u8 = null, // Optional URL to open
};

/// Add an annotation to terminal output
/// Annotations can be clicked and may contain links
pub fn addAnnotation(alloc: std.mem.Allocator, config: AnnotationConfig) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    try buf.appendSlice(alloc, "AddAnnotation=");

    // Base64 encode the text for safety
    const text_b64 = try base64EncodeAlloc(alloc, config.text);
    defer alloc.free(text_b64);
    try buf.appendSlice(alloc, text_b64);

    if (config.x) |x| {
        var x_str: [16]u8 = undefined;
        const x_slice = try std.fmt.bufPrint(&x_str, ";x={d}", .{x});
        try buf.appendSlice(alloc, x_slice);
    }

    if (config.y) |y| {
        var y_str: [16]u8 = undefined;
        const y_slice = try std.fmt.bufPrint(&y_str, ";y={d}", .{y});
        try buf.appendSlice(alloc, y_slice);
    }

    if (config.length) |len| {
        var len_str: [16]u8 = undefined;
        const len_slice = try std.fmt.bufPrint(&len_str, ";length={d}", .{len});
        try buf.appendSlice(alloc, len_slice);
    }

    if (config.url) |url| {
        try buf.appendSlice(alloc, ";url=");
        try buf.appendSlice(alloc, url);
    }

    return try buf.toOwnedSlice(alloc);
}

/// Clear all annotations
pub fn clearAnnotations(alloc: std.mem.Allocator) ![]u8 {
    return try alloc.dupe(u8, "ClearAnnotations");
}

// ============================================================================
// 8. MARK SUPPORT
// ============================================================================

/// Mark types for navigation
pub const MarkType = enum {
    command,
    error_mark,
    warning,
    info,
    custom,
};

/// Set a mark that can be navigated to
pub fn setMark(alloc: std.mem.Allocator, mark_type: MarkType, name: ?[]const u8) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    const type_str = switch (mark_type) {
        .command => "SetMark=command",
        .error_mark => "SetMark=error",
        .warning => "SetMark=warning",
        .info => "SetMark=info",
        .custom => "SetMark=custom",
    };

    try buf.appendSlice(alloc, type_str);

    if (name) |n| {
        try buf.append(alloc, ';');
        try buf.appendSlice(alloc, n);
    }

    return try buf.toOwnedSlice(alloc);
}

/// Set a command mark (convenience function)
pub fn markCommand(alloc: std.mem.Allocator, command_name: ?[]const u8) ![]u8 {
    return try setMark(alloc, .command, command_name);
}

/// Set an error mark
pub fn markError(alloc: std.mem.Allocator, message: ?[]const u8) ![]u8 {
    return try setMark(alloc, .error_mark, message);
}

// ============================================================================
// 9. ALERT ON COMPLETION
// ============================================================================

/// Alert configuration for command completion
pub const AlertConfig = struct {
    message: []const u8,
    sound: bool = true,
    only_on_failure: bool = false,
};

/// Configure alert on command completion
pub fn setAlertOnCompletion(alloc: std.mem.Allocator, config: AlertConfig) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    try buf.appendSlice(alloc, "AlertOnCompletion=");
    try buf.appendSlice(alloc, config.message);

    if (!config.sound) {
        try buf.appendSlice(alloc, ";nosound");
    }

    if (config.only_on_failure) {
        try buf.appendSlice(alloc, ";onfailure");
    }

    return try buf.toOwnedSlice(alloc);
}

/// Enable alert for long-running commands
pub fn alertOnLongCommand(alloc: std.mem.Allocator, threshold_seconds: u32) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    var threshold_str: [16]u8 = undefined;
    const threshold_slice = try std.fmt.bufPrint(&threshold_str, "AlertOnLongCommand={d}", .{threshold_seconds});
    try buf.appendSlice(alloc, threshold_slice);

    return try buf.toOwnedSlice(alloc);
}

// ============================================================================
// 10. DOWNLOAD SUPPORT
// ============================================================================

/// Download configuration
pub const DownloadConfig = struct {
    url: []const u8,
    filename: ?[]const u8 = null,
    open_after_download: bool = false,
};

/// Trigger a file download from the terminal
pub fn triggerDownload(alloc: std.mem.Allocator, config: DownloadConfig) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);

    try buf.appendSlice(alloc, "Download=");
    try buf.appendSlice(alloc, config.url);

    if (config.filename) |fname| {
        try buf.append(alloc, ';');
        try buf.appendSlice(alloc, fname);
    }

    if (config.open_after_download) {
        try buf.appendSlice(alloc, ";open");
    }

    return try buf.toOwnedSlice(alloc);
}

/// Download and open a file
pub fn downloadAndOpen(alloc: std.mem.Allocator, url: []const u8, filename: ?[]const u8) ![]u8 {
    return try triggerDownload(alloc, .{
        .url = url,
        .filename = filename,
        .open_after_download = true,
    });
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

fn base64EncodeAlloc(alloc: std.mem.Allocator, data: []const u8) ![]u8 {
    const out_len = ((data.len + 2) / 3) * 4;
    var out = try alloc.alloc(u8, out_len);
    const n = std.base64.standard.Encoder.encode(out, data);
    return out[0..n];
}

/// High-level convenience functions for common use cases
pub const Convenience = struct {
    /// Initialize full iTerm2 shell integration
    pub fn initFullIntegration(alloc: std.mem.Allocator) ![][]u8 {
        var sequences = std.ArrayListUnmanaged([]u8){};
        defer sequences.deinit(alloc);

        // Enable shell integration
        try sequences.append(alloc, try enableShellIntegration(alloc));

        // Set current user
        const user = try getCurrentUser(alloc);
        defer alloc.free(user);
        try sequences.append(alloc, try setCurrentUser(alloc, user));

        // Set initial badge
        try sequences.append(alloc, try setBadge(alloc, "Shell Ready"));

        return try sequences.toOwnedSlice(alloc);
    }

    /// Mark SSH session start
    pub fn startSshSession(alloc: std.mem.Allocator, hostname: []const u8, username: ?[]const u8) ![][]u8 {
        var sequences = std.ArrayListUnmanaged([]u8){};
        defer sequences.deinit(alloc);

        // Mark remote host
        try sequences.append(alloc, try markRemoteHost(alloc, .{
            .hostname = hostname,
            .username = username,
        }));

        // Update badge
        const badge_text = try std.fmt.allocPrint(alloc, "SSH: {s}", .{hostname});
        defer alloc.free(badge_text);
        try sequences.append(alloc, try setBadge(alloc, badge_text));

        return try sequences.toOwnedSlice(alloc);
    }

    /// Mark SSH session end
    pub fn endSshSession(alloc: std.mem.Allocator) ![][]u8 {
        var sequences = std.ArrayListUnmanaged([]u8){};
        defer sequences.deinit(alloc);

        // Clear remote host
        try sequences.append(alloc, try clearRemoteHost(alloc));

        // Reset badge
        try sequences.append(alloc, try setBadge(alloc, "Local Shell"));

        return try sequences.toOwnedSlice(alloc);
    }

    /// Mark command execution with timing
    pub fn executeCommand(alloc: std.mem.Allocator, command: []const u8, cwd: ?[]const u8) ![]u8 {
        return try markCommandStart(alloc, .{
            .command = command,
            .working_directory = cwd,
        });
    }

    /// Mark command completion with status
    pub fn completeCommand(alloc: std.mem.Allocator, command: []const u8, exit_code: i32, duration_ms: u64) ![]u8 {
        return try markCommandEnd(alloc, .{
            .command = command,
            .exit_code = exit_code,
            .duration_ms = duration_ms,
        });
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "remote host identification" {
    const allocator = std.testing.allocator;

    // Test basic remote host
    const remote = try markRemoteHost(allocator, .{
        .hostname = "example.com",
    });
    defer allocator.free(remote);
    try std.testing.expect(std.mem.eql(u8, remote, "RemoteHost=example.com"));

    // Test remote host with user
    const remote_user = try markRemoteHost(allocator, .{
        .hostname = "example.com",
        .username = "user",
    });
    defer allocator.free(remote_user);
    try std.testing.expect(std.mem.eql(u8, remote_user, "RemoteHost=user@example.com"));

    // Test clear remote host
    const clear = try clearRemoteHost(allocator);
    defer allocator.free(clear);
    try std.testing.expect(std.mem.eql(u8, clear, "RemoteHost="));
}

test "shell integration mode" {
    const allocator = std.testing.allocator;

    // Test enable full integration
    const full = try enableShellIntegration(allocator);
    defer allocator.free(full);
    try std.testing.expect(std.mem.eql(u8, full, "ShellIntegration=2"));

    // Test disable integration
    const off = try disableShellIntegration(allocator);
    defer allocator.free(off);
    try std.testing.expect(std.mem.eql(u8, off, "ShellIntegration=0"));
}

test "badge support" {
    const allocator = std.testing.allocator;

    // Test set badge
    const badge = try setBadge(allocator, "Hello World");
    defer allocator.free(badge);
    try std.testing.expect(std.mem.eql(u8, badge, "SetBadge=Hello World"));

    // Test clear badge
    const clear = try clearBadge(allocator);
    defer allocator.free(clear);
    try std.testing.expect(std.mem.eql(u8, clear, "SetBadge="));
}

test "command status indicators" {
    const allocator = std.testing.allocator;

    // Test command start
    const start = try markCommandStart(allocator, .{
        .command = "ls -la",
        .working_directory = "/home/user",
    });
    defer allocator.free(start);
    try std.testing.expect(std.mem.eql(u8, start, "CommandStart=ls -la;cwd=/home/user"));

    // Test command end with exit code
    const end = try markCommandEnd(allocator, .{
        .command = "ls -la",
        .exit_code = 0,
        .duration_ms = 150,
    });
    defer allocator.free(end);
    try std.testing.expect(std.mem.eql(u8, end, "CommandEnd=ls -la;exit=0;duration=150"));
}

test "attention requests" {
    const allocator = std.testing.allocator;

    // Test simple attention
    const attention = try requestAttention(allocator, null);
    defer allocator.free(attention);
    try std.testing.expect(std.mem.eql(u8, attention, "RequestAttention"));

    // Test attention with message
    const attention_msg = try requestAttention(allocator, "Command completed!");
    defer allocator.free(attention_msg);
    try std.testing.expect(std.mem.eql(u8, attention_msg, "RequestAttention=Command completed!"));
}

test "mark support" {
    const allocator = std.testing.allocator;

    // Test command mark
    const cmd_mark = try markCommand(allocator, "build");
    defer allocator.free(cmd_mark);
    try std.testing.expect(std.mem.eql(u8, cmd_mark, "SetMark=command;build"));

    // Test error mark
    const err_mark = try markError(allocator, "Compilation failed");
    defer allocator.free(err_mark);
    try std.testing.expect(std.mem.eql(u8, err_mark, "SetMark=error;Compilation failed"));
}

test "download support" {
    const allocator = std.testing.allocator;

    // Test download
    const download = try triggerDownload(allocator, .{
        .url = "https://example.com/file.txt",
        .filename = "downloaded.txt",
        .open_after_download = true,
    });
    defer allocator.free(download);
    try std.testing.expect(std.mem.eql(u8, download, "Download=https://example.com/file.txt;downloaded.txt;open"));
}

test "convenience functions" {
    const allocator = std.testing.allocator;

    // Test command execution
    const exec = try Convenience.executeCommand(allocator, "make", "/src/project");
    defer allocator.free(exec);
    try std.testing.expect(std.mem.eql(u8, exec, "CommandStart=make;cwd=/src/project"));

    // Test command completion
    const complete = try Convenience.completeCommand(allocator, "make", 0, 5000);
    defer allocator.free(complete);
    try std.testing.expect(std.mem.eql(u8, complete, "CommandEnd=make;exit=0;duration=5000"));
}

const std = @import("std");
const seqcfg = @import("ansi.zon");

/// FinalTerm shell integration markers for improved shell UX
/// Originally designed by FinalTerm, now widely supported by iTerm2, etc.
/// See: https://iterm2.com/documentation-shell-integration.html
fn oscTerminator() []const u8 {
    return if (std.mem.eql(u8, seqcfg.osc.default_terminator, "bel"))
        seqcfg.osc.bel
    else
        seqcfg.osc.st;
}

/// Build FinalTerm OSC 133 sequence with parameters
pub fn buildFinalTermSequence(allocator: std.mem.Allocator, params: []const []const u8) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "\x1b]133;");

    for (params, 0..) |param, i| {
        if (i > 0) try buf.append(allocator, ';');
        try buf.appendSlice(allocator, param);
    }

    try buf.appendSlice(allocator, oscTerminator());
    return try buf.toOwnedSlice(allocator);
}

/// Prompt marker - sent before shell prompt
pub fn promptMarker(allocator: std.mem.Allocator, extra_params: ?[]const []const u8) ![]u8 {
    var params = std.ArrayListUnmanaged([]const u8){};
    defer params.deinit(allocator);

    try params.append(allocator, "A");
    if (extra_params) |extra| {
        try params.appendSlice(allocator, extra);
    }

    return buildFinalTermSequence(allocator, params.items);
}

/// Command start marker - sent after prompt, before user input
pub fn commandStartMarker(allocator: std.mem.Allocator, extra_params: ?[]const []const u8) ![]u8 {
    var params = std.ArrayListUnmanaged([]const u8){};
    defer params.deinit(allocator);

    try params.append(allocator, "B");
    if (extra_params) |extra| {
        try params.appendSlice(allocator, extra);
    }

    return buildFinalTermSequence(allocator, params.items);
}

/// Command executed marker - sent before command output
pub fn commandExecutedMarker(allocator: std.mem.Allocator, extra_params: ?[]const []const u8) ![]u8 {
    var params = std.ArrayListUnmanaged([]const u8){};
    defer params.deinit(allocator);

    try params.append(allocator, "C");
    if (extra_params) |extra| {
        try params.appendSlice(allocator, extra);
    }

    return buildFinalTermSequence(allocator, params.items);
}

/// Command finished marker - sent after command completes
pub fn commandFinishedMarker(allocator: std.mem.Allocator, exit_code: ?i32, extra_params: ?[]const []const u8) ![]u8 {
    var params = std.ArrayListUnmanaged([]const u8){};
    defer params.deinit(allocator);

    try params.append(allocator, "D");

    // Add exit code if provided - need to keep the string alive until we're done
    var code_str: ?[]u8 = null;
    defer if (code_str) |str| allocator.free(str);

    if (exit_code) |code| {
        code_str = try std.fmt.allocPrint(allocator, "{d}", .{code});
        try params.append(allocator, code_str.?);
    }

    if (extra_params) |extra| {
        try params.appendSlice(allocator, extra);
    }

    return buildFinalTermSequence(allocator, params.items);
}

/// Generic FinalTerm sequence builder
pub fn finalTerm(allocator: std.mem.Allocator, params: []const []const u8) ![]u8 {
    return buildFinalTermSequence(allocator, params);
}

/// Common shell integration constants (no allocation needed)
pub const PROMPT_MARKER = "\x1b]133;A\x07";
pub const COMMAND_START_MARKER = "\x1b]133;B\x07";
pub const COMMAND_EXECUTED_MARKER = "\x1b]133;C\x07";
pub const COMMAND_FINISHED_MARKER = "\x1b]133;D\x07";

/// Extended shell integration with working directory
pub fn commandWithCwd(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    const params = [_][]const u8{ "C", cwd };
    return buildFinalTermSequence(allocator, &params);
}

/// Convenient aliases for shell integration
pub const FinalTerm = struct {
    /// Generic FinalTerm sequence builder with variadic parameters
    pub fn finalTerm(allocator: std.mem.Allocator, params: []const []const u8) ![]u8 {
        return buildFinalTermSequence(allocator, params);
    }

    /// Prompt start marker - alias for promptMarker
    pub fn prompt(allocator: std.mem.Allocator, extra_params: ?[]const []const u8) ![]u8 {
        return promptMarker(allocator, extra_params);
    }

    /// Command start marker - alias for commandStartMarker
    pub fn cmdStart(allocator: std.mem.Allocator, extra_params: ?[]const []const u8) ![]u8 {
        return commandStartMarker(allocator, extra_params);
    }

    /// Command executed marker - alias for commandExecutedMarker
    pub fn cmdExecuted(allocator: std.mem.Allocator, extra_params: ?[]const []const u8) ![]u8 {
        return commandExecutedMarker(allocator, extra_params);
    }

    /// Command finished marker - alias for commandFinishedMarker
    pub fn cmdFinished(allocator: std.mem.Allocator, exit_code: ?i32, extra_params: ?[]const []const u8) ![]u8 {
        return commandFinishedMarker(allocator, exit_code, extra_params);
    }
};

/// Current working directory notification
pub fn currentWorkingDirectory(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "\x1b]7;file://");

    // Add hostname if available
    if (std.process.getEnvVarOwned(allocator, "HOSTNAME")) |hostname| {
        defer allocator.free(hostname);
        try buf.appendSlice(allocator, hostname);
    } else |_| {
        try buf.appendSlice(allocator, "localhost");
    }

    try buf.appendSlice(allocator, cwd);
    try buf.appendSlice(allocator, oscTerminator());
    return try buf.toOwnedSlice(allocator);
}

test "build basic FinalTerm sequences" {
    const allocator = std.testing.allocator;

    // Test prompt marker (using ST terminator as per config)
    const prompt = try promptMarker(allocator, null);
    defer allocator.free(prompt);
    try std.testing.expectEqualStrings("\x1b]133;A\x1b\\", prompt);

    // Test command start
    const cmd_start = try commandStartMarker(allocator, null);
    defer allocator.free(cmd_start);
    try std.testing.expectEqualStrings("\x1b]133;B\x1b\\", cmd_start);

    // Test command executed
    const cmd_exec = try commandExecutedMarker(allocator, null);
    defer allocator.free(cmd_exec);
    try std.testing.expectEqualStrings("\x1b]133;C\x1b\\", cmd_exec);

    // Test command finished with exit code
    const cmd_finished = try commandFinishedMarker(allocator, 1, null);
    defer allocator.free(cmd_finished);
    // Note: exit code will be in a separate allocation, so the exact string will vary
    try std.testing.expect(std.mem.startsWith(u8, cmd_finished, "\x1b]133;D;"));
    try std.testing.expect(std.mem.endsWith(u8, cmd_finished, "\x1b\\"));
}

test "build FinalTerm sequence with extra params" {
    const allocator = std.testing.allocator;

    const extra_params = [_][]const u8{ "param1", "param2" };
    const sequence = try promptMarker(allocator, &extra_params);
    defer allocator.free(sequence);

    try std.testing.expectEqualStrings("\x1b]133;A;param1;param2\x1b\\", sequence);
}

test "current working directory notification" {
    const allocator = std.testing.allocator;

    const cwd_seq = try currentWorkingDirectory(allocator, "/home/user/project");
    defer allocator.free(cwd_seq);

    try std.testing.expect(std.mem.startsWith(u8, cwd_seq, "\x1b]7;file://"));
    try std.testing.expect(std.mem.endsWith(u8, cwd_seq, "/home/user/project\x1b\\"));
}

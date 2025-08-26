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
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    
    try buf.appendSlice("\x1b]133;");
    
    for (params, 0..) |param, i| {
        if (i > 0) try buf.append(';');
        try buf.appendSlice(param);
    }
    
    try buf.appendSlice(oscTerminator());
    return try buf.toOwnedSlice();
}

/// Prompt marker - sent before shell prompt
pub fn promptMarker(allocator: std.mem.Allocator, extra_params: ?[]const []const u8) ![]u8 {
    var params = std.ArrayList([]const u8).init(allocator);
    defer params.deinit();
    
    try params.append("A");
    if (extra_params) |extra| {
        try params.appendSlice(extra);
    }
    
    return buildFinalTermSequence(allocator, params.items);
}

/// Command start marker - sent after prompt, before user input
pub fn commandStartMarker(allocator: std.mem.Allocator, extra_params: ?[]const []const u8) ![]u8 {
    var params = std.ArrayList([]const u8).init(allocator);
    defer params.deinit();
    
    try params.append("B");
    if (extra_params) |extra| {
        try params.appendSlice(extra);
    }
    
    return buildFinalTermSequence(allocator, params.items);
}

/// Command executed marker - sent before command output
pub fn commandExecutedMarker(allocator: std.mem.Allocator, extra_params: ?[]const []const u8) ![]u8 {
    var params = std.ArrayList([]const u8).init(allocator);
    defer params.deinit();
    
    try params.append("C");
    if (extra_params) |extra| {
        try params.appendSlice(extra);
    }
    
    return buildFinalTermSequence(allocator, params.items);
}

/// Command finished marker - sent after command completes
pub fn commandFinishedMarker(allocator: std.mem.Allocator, exit_code: ?i32, extra_params: ?[]const []const u8) ![]u8 {
    var params = std.ArrayList([]const u8).init(allocator);
    defer params.deinit();
    
    try params.append("D");
    
    // Add exit code if provided
    if (exit_code) |code| {
        const code_str = try std.fmt.allocPrint(allocator, "{d}", .{code});
        defer allocator.free(code_str);
        try params.append(code_str);
    }
    
    if (extra_params) |extra| {
        try params.appendSlice(extra);
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

/// Current working directory notification
pub fn currentWorkingDirectory(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    
    try buf.appendSlice("\x1b]7;file://");
    
    // Add hostname if available
    if (std.os.getenv("HOSTNAME")) |hostname| {
        try buf.appendSlice(hostname);
    } else {
        try buf.appendSlice("localhost");
    }
    
    try buf.appendSlice(cwd);
    try buf.appendSlice(oscTerminator());
    return try buf.toOwnedSlice();
}

test "build basic FinalTerm sequences" {
    const allocator = std.testing.allocator;
    
    // Test prompt marker
    const prompt = try promptMarker(allocator, null);
    defer allocator.free(prompt);
    try std.testing.expectEqualStrings("\x1b]133;A\x07", prompt);
    
    // Test command start  
    const cmd_start = try commandStartMarker(allocator, null);
    defer allocator.free(cmd_start);
    try std.testing.expectEqualStrings("\x1b]133;B\x07", cmd_start);
    
    // Test command executed
    const cmd_exec = try commandExecutedMarker(allocator, null);
    defer allocator.free(cmd_exec);
    try std.testing.expectEqualStrings("\x1b]133;C\x07", cmd_exec);
    
    // Test command finished with exit code
    const cmd_finished = try commandFinishedMarker(allocator, 1, null);
    defer allocator.free(cmd_finished);
    try std.testing.expectEqualStrings("\x1b]133;D;1\x07", cmd_finished);
}

test "build FinalTerm sequence with extra params" {
    const allocator = std.testing.allocator;
    
    const extra_params = [_][]const u8{ "param1", "param2" };
    const sequence = try promptMarker(allocator, &extra_params);
    defer allocator.free(sequence);
    
    try std.testing.expectEqualStrings("\x1b]133;A;param1;param2\x07", sequence);
}

test "current working directory notification" {
    const allocator = std.testing.allocator;
    
    const cwd_seq = try currentWorkingDirectory(allocator, "/home/user/project");
    defer allocator.free(cwd_seq);
    
    try std.testing.expect(std.mem.startsWith(u8, cwd_seq, "\x1b]7;file://"));
    try std.testing.expect(std.mem.endsWith(u8, cwd_seq, "/home/user/project\x07"));
}
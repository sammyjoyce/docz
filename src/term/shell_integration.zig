const std = @import("std");

/// FinalTerm/iTerm2 shell integration protocol support
/// Originally designed by FinalTerm, widely adopted by modern terminals
/// 
/// This module provides escape sequences for shell integration that enable
/// advanced terminal features like command history, working directory tracking,
/// and semantic understanding of shell output.
///
/// See: https://iterm2.com/documentation-shell-integration.html
/// See: https://wezfurlong.org/wezterm/shell-integration.html

/// Base function for creating FinalTerm escape sequences
/// OSC 133 ; Ps ; Pm ST/BEL
fn finalTermSequence(alloc: std.mem.Allocator, params: []const []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();
    
    try result.appendSlice("\x1b]133;");
    
    for (params, 0..) |param, i| {
        if (i > 0) try result.append(';');
        try result.appendSlice(param);
    }
    
    try result.appendSlice("\x07"); // BEL terminator
    
    return try result.toOwnedSlice();
}

/// Mark the start of a shell prompt
/// OSC 133 ; A ST/BEL
///
/// This should be sent just before the shell prompt is displayed.
/// Enables terminals to identify where prompts begin for navigation and selection.
pub fn promptStart(alloc: std.mem.Allocator) ![]u8 {
    return finalTermSequence(alloc, &[_][]const u8{"A"});
}

/// Mark the start of a shell prompt with additional parameters
/// OSC 133 ; A ; params... ST/BEL
pub fn promptStartWithParams(alloc: std.mem.Allocator, params: []const []const u8) ![]u8 {
    var all_params = std.ArrayList([]const u8).init(alloc);
    defer all_params.deinit();
    
    try all_params.append("A");
    try all_params.appendSlice(params);
    
    return finalTermSequence(alloc, all_params.items);
}

/// Mark the end of the shell prompt and start of user command input
/// OSC 133 ; B ST/BEL
///
/// This should be sent just after the shell prompt, before user input begins.
/// Allows terminals to distinguish between prompt and user input.
pub fn commandStart(alloc: std.mem.Allocator) ![]u8 {
    return finalTermSequence(alloc, &[_][]const u8{"B"});
}

/// Mark the end of command input and start of command execution
/// OSC 133 ; C ST/BEL
/// 
/// This should be sent when the user presses Enter and command execution begins.
/// Enables terminals to track command execution timing and separate input from output.
pub fn commandExecuted(alloc: std.mem.Allocator) ![]u8 {
    return finalTermSequence(alloc, &[_][]const u8{"C"});
}

/// Mark the end of command execution and output
/// OSC 133 ; D ; exit_code ST/BEL
///
/// This should be sent when a command finishes executing.
/// The exit_code parameter is optional but recommended for better integration.
pub fn commandFinished(alloc: std.mem.Allocator, exit_code: ?i32) ![]u8 {
    var params = std.ArrayList([]const u8).init(alloc);
    defer params.deinit();
    
    try params.append("D");
    
    if (exit_code) |code| {
        const code_str = try std.fmt.allocPrint(alloc, "{d}", .{code});
        defer alloc.free(code_str);
        
        // Create a copy that we own
        const owned_code = try alloc.dupe(u8, code_str);
        try params.append(owned_code);
        
        const result = try finalTermSequence(alloc, params.items);
        alloc.free(owned_code);
        return result;
    }
    
    return finalTermSequence(alloc, params.items);
}

/// Set the current working directory
/// OSC 7 ; file://hostname/path BEL
///
/// This notifies the terminal of the current working directory, enabling
/// features like opening new tabs in the same directory.
pub fn setWorkingDirectory(alloc: std.mem.Allocator, hostname: []const u8, path: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();
    
    try result.appendSlice("\x1b]7;file://");
    try result.appendSlice(hostname);
    try result.appendSlice(path);
    try result.appendSlice("\x07");
    
    return try result.toOwnedSlice();
}

/// Set the current working directory for localhost
/// Convenience function for local paths
pub fn setLocalWorkingDirectory(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    return setWorkingDirectory(alloc, "localhost", path);
}

/// Report the current user name
/// OSC 1337 ; RemoteHost=user@hostname BEL
///
/// This is iTerm2 specific but supported by other terminals.
/// Helps with session management and remote connection tracking.
pub fn setRemoteHost(alloc: std.mem.Allocator, user: []const u8, hostname: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();
    
    try result.appendSlice("\x1b]1337;RemoteHost=");
    try result.appendSlice(user);
    try result.append('@');
    try result.appendSlice(hostname);
    try result.appendSlice("\x07");
    
    return try result.toOwnedSlice();
}

/// Set the current directory (iTerm2 specific)
/// OSC 1337 ; CurrentDir=path BEL
pub fn setCurrentDirectory(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();
    
    try result.appendSlice("\x1b]1337;CurrentDir=");
    try result.appendSlice(path);
    try result.appendSlice("\x07");
    
    return try result.toOwnedSlice();
}

/// High-level shell integration helper
/// This struct helps manage the shell integration lifecycle
pub const ShellIntegration = struct {
    alloc: std.mem.Allocator,
    
    pub fn init(alloc: std.mem.Allocator) ShellIntegration {
        return ShellIntegration{ .alloc = alloc };
    }
    
    /// Begin a new command cycle
    pub fn beginPrompt(self: *ShellIntegration) ![]u8 {
        return promptStart(self.alloc);
    }
    
    /// Mark the transition from prompt to user input
    pub fn beginInput(self: *ShellIntegration) ![]u8 {
        return commandStart(self.alloc);
    }
    
    /// Mark the start of command execution
    pub fn beginExecution(self: *ShellIntegration) ![]u8 {
        return commandExecuted(self.alloc);
    }
    
    /// Mark the end of command execution
    pub fn endExecution(self: *ShellIntegration, exit_code: ?i32) ![]u8 {
        return commandFinished(self.alloc, exit_code);
    }
    
    /// Update working directory
    pub fn updateWorkingDirectory(self: *ShellIntegration, path: []const u8) ![]u8 {
        return setLocalWorkingDirectory(self.alloc, path);
    }
    
    /// Set remote connection info
    pub fn setConnection(self: *ShellIntegration, user: []const u8, host: []const u8) ![]u8 {
        return setRemoteHost(self.alloc, user, host);
    }
};

/// Convenience constants for common sequences
pub const PROMPT_START = "\x1b]133;A\x07";
pub const COMMAND_START = "\x1b]133;B\x07";
pub const COMMAND_EXECUTED = "\x1b]133;C\x07";
pub const COMMAND_FINISHED = "\x1b]133;D\x07";

test "shell integration sequences" {
    const testing = std.testing;
    const alloc = testing.allocator;
    
    // Test basic sequences
    const prompt = try promptStart(alloc);
    defer alloc.free(prompt);
    try testing.expectEqualStrings(PROMPT_START, prompt);
    
    const cmd_start = try commandStart(alloc);
    defer alloc.free(cmd_start);
    try testing.expectEqualStrings(COMMAND_START, cmd_start);
    
    const cmd_executed = try commandExecuted(alloc);
    defer alloc.free(cmd_executed);
    try testing.expectEqualStrings(COMMAND_EXECUTED, cmd_executed);
    
    // Test command finished with exit code
    const cmd_finished = try commandFinished(alloc, 0);
    defer alloc.free(cmd_finished);
    try testing.expectEqualStrings("\x1b]133;D;0\x07", cmd_finished);
    
    // Test working directory
    const cwd = try setLocalWorkingDirectory(alloc, "/home/user");
    defer alloc.free(cwd);
    try testing.expectEqualStrings("\x1b]7;file://localhost/home/user\x07", cwd);
    
    // Test remote host
    const remote = try setRemoteHost(alloc, "user", "example.com");
    defer alloc.free(remote);
    try testing.expectEqualStrings("\x1b]1337;RemoteHost=user@example.com\x07", remote);
}

test "shell integration helper" {
    const testing = std.testing;
    const alloc = testing.allocator;
    
    var shell = ShellIntegration.init(alloc);
    
    const prompt = try shell.beginPrompt();
    defer alloc.free(prompt);
    try testing.expectEqualStrings(PROMPT_START, prompt);
    
    const input = try shell.beginInput();
    defer alloc.free(input);
    try testing.expectEqualStrings(COMMAND_START, input);
    
    const exec = try shell.beginExecution();
    defer alloc.free(exec);
    try testing.expectEqualStrings(COMMAND_EXECUTED, exec);
    
    const end = try shell.endExecution(42);
    defer alloc.free(end);
    try testing.expectEqualStrings("\x1b]133;D;42\x07", end);
    
    const wd = try shell.updateWorkingDirectory("/tmp");
    defer alloc.free(wd);
    try testing.expectEqualStrings("\x1b]7;file://localhost/tmp\x07", wd);
}
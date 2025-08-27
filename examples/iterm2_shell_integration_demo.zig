const std = @import("std");
const ansi = @import("../src/shared/term/ansi/mod.zig");
const iterm2_si = ansi.iterm2_shell_integration;

/// Comprehensive demo of iTerm2 shell integration features
/// This example shows how to use all the shell integration capabilities
pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var stdout_buffer: [4096]u8 = undefined;
    const stdout_file = std.fs.File.stdout();
    var stdout = stdout_file.writer(&stdout_buffer);

    // Initialize full shell integration
    std.debug.print("Initializing iTerm2 shell integration...\n", .{});
    const init_sequences = try iterm2_si.Convenience.initFullIntegration(allocator);
    defer {
        for (init_sequences) |seq| {
            allocator.free(seq);
        }
        allocator.free(init_sequences);
    }

    for (init_sequences) |seq| {
        try stdout.writeAll(seq);
    }

    // Demo remote host identification
    std.debug.print("Marking SSH session to remote host...\n", .{});
    const ssh_sequences = try iterm2_si.Convenience.startSshSession(allocator, "example.com", "user");
    defer {
        for (ssh_sequences) |seq| {
            allocator.free(seq);
        }
        allocator.free(ssh_sequences);
    }

    for (ssh_sequences) |seq| {
        try stdout.writeAll(seq);
    }

    // Simulate command execution
    std.debug.print("Simulating command execution...\n", .{});

    // Mark command start
    const cmd_start = try iterm2_si.Convenience.executeCommand(allocator, "git status", "/home/user/project");
    defer allocator.free(cmd_start);
    try stdout.writeAll(cmd_start);

    // Simulate some output
    try stdout.writeAll("On branch main\nYour branch is up to date with 'origin/main'.\n\n");

    // Mark command completion
    const cmd_complete = try iterm2_si.Convenience.completeCommand(allocator, "git status", 0, 250);
    defer allocator.free(cmd_complete);
    try stdout.writeAll(cmd_complete);

    // Demo badge updates
    std.debug.print("Updating badge...\n", .{});
    const badge = try iterm2_si.setBadgeFormat(allocator, "Working on: {s}", .{"project-x"});
    defer allocator.free(badge);
    try stdout.writeAll(badge);

    // Demo annotations
    std.debug.print("Adding annotation...\n", .{});
    const annotation = try iterm2_si.addAnnotation(allocator, .{
        .text = "This is an important note!",
        .url = "https://example.com/help",
    });
    defer allocator.free(annotation);
    try stdout.writeAll(annotation);

    // Demo marks
    std.debug.print("Setting navigation marks...\n", .{});
    const error_mark = try iterm2_si.markError(allocator, "Potential issue here");
    defer allocator.free(error_mark);
    try stdout.writeAll(error_mark);

    // Demo attention request
    std.debug.print("Requesting attention...\n", .{});
    const attention = try iterm2_si.notify(allocator, "Task completed successfully!");
    defer allocator.free(attention);
    try stdout.writeAll(attention);

    // Demo download trigger
    std.debug.print("Triggering file download...\n", .{});
    const download = try iterm2_si.downloadAndOpen(allocator, "https://example.com/report.pdf", "monthly-report.pdf");
    defer allocator.free(download);
    try stdout.writeAll(download);

    // Demo alert on completion
    std.debug.print("Setting up completion alert...\n", .{});
    const alert = try iterm2_si.setAlertOnCompletion(allocator, .{
        .message = "Build process finished",
        .only_on_failure = true,
    });
    defer allocator.free(alert);
    try stdout.writeAll(alert);

    // End SSH session
    std.debug.print("Ending SSH session...\n", .{});
    const end_ssh_sequences = try iterm2_si.Convenience.endSshSession(allocator);
    defer {
        for (end_ssh_sequences) |seq| {
            allocator.free(seq);
        }
        allocator.free(end_ssh_sequences);
    }

    for (end_ssh_sequences) |seq| {
        try stdout.writeAll(seq);
    }

    std.debug.print("iTerm2 shell integration demo completed!\n", .{});
}

/// Example of how to integrate with a shell or command runner
pub const ShellIntegrationExample = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ShellIntegrationExample {
        return .{ .allocator = allocator };
    }

    /// Wrap a command execution with full iTerm2 integration
    pub fn executeCommandWithIntegration(
        self: *ShellIntegrationExample,
        writer: anytype,
        command: []const u8,
        cwd: ?[]const u8,
    ) !i32 {
        const start_time = std.time.milliTimestamp();

        // Mark command start
        const start_seq = try iterm2_si.Convenience.executeCommand(self.allocator, command, cwd);
        defer self.allocator.free(start_seq);
        try writer.writeAll(start_seq);

        // Execute the actual command (simulated here)
        const exit_code = try simulateCommandExecution(writer, command);

        const end_time = std.time.milliTimestamp();
        const duration = @as(u64, @intCast(end_time - start_time));

        // Mark command completion
        const end_seq = try iterm2_si.Convenience.completeCommand(self.allocator, command, exit_code, duration);
        defer self.allocator.free(end_seq);
        try writer.writeAll(end_seq);

        // Set mark based on result
        if (exit_code != 0) {
            const error_seq = try iterm2_si.markError(self.allocator, command);
            defer self.allocator.free(error_seq);
            try writer.writeAll(error_seq);
        } else {
            const success_seq = try iterm2_si.markCommand(self.allocator, command);
            defer self.allocator.free(success_seq);
            try writer.writeAll(success_seq);
        }

        return exit_code;
    }

    fn simulateCommandExecution(writer: anytype, command: []const u8) !i32 {
        // Simulate command output
        try writer.print("Executing: {s}\n", .{command});

        // Simulate some processing time
        std.time.sleep(100 * std.time.ns_per_ms);

        // Simulate output
        if (std.mem.eql(u8, command, "ls")) {
            try writer.writeAll("file1.txt\nfile2.txt\ndirectory/\n");
            return 0;
        } else if (std.mem.eql(u8, command, "failing-command")) {
            try writer.writeAll("Error: Something went wrong!\n");
            return 1;
        } else {
            try writer.print("Command '{s}' completed successfully\n", .{command});
            return 0;
        }
    }
};

/// Example shell profile configuration
pub const ShellProfile = struct {
    /// Generate shell integration setup commands for .bashrc or .zshrc
    pub fn generateShellIntegrationSetup(allocator: std.mem.Allocator, shell: enum { bash, zsh, fish }) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(allocator);

        const comment = switch (shell) {
            .bash => "# iTerm2 Shell Integration Setup\n",
            .zsh => "# iTerm2 Shell Integration Setup\n",
            .fish => "# iTerm2 Shell Integration Setup\n",
        };

        try buf.appendSlice(allocator, comment);

        // Enable shell integration
        const enable_seq = try iterm2_si.enableShellIntegration(allocator);
        defer allocator.free(enable_seq);
        try buf.appendSlice(allocator, "printf '");
        try buf.appendSlice(allocator, enable_seq);
        try buf.appendSlice(allocator, "'\n");

        // Set current user
        const user_seq = try iterm2_si.setCurrentUser(allocator, "$USER");
        defer allocator.free(user_seq);
        try buf.appendSlice(allocator, "printf '");
        try buf.appendSlice(allocator, user_seq);
        try buf.appendSlice(allocator, "'\n");

        // Set initial badge
        const badge_seq = try iterm2_si.setBadge(allocator, "Shell Ready");
        defer allocator.free(badge_seq);
        try buf.appendSlice(allocator, "printf '");
        try buf.appendSlice(allocator, badge_seq);
        try buf.appendSlice(allocator, "'\n");

        // Add prompt markers
        const prompt_start = try ansi.shell_integration.promptMarker(allocator, null);
        defer allocator.free(prompt_start);
        const prompt_end = try ansi.shell_integration.commandFinishedMarker(allocator, null, null);
        defer allocator.free(prompt_end);

        switch (shell) {
            .bash => {
                try buf.appendSlice(allocator, "PS1='");
                try buf.appendSlice(allocator, prompt_start);
                try buf.appendSlice(allocator, "\\h:\\W \\u\\$ ");
                try buf.appendSlice(allocator, prompt_end);
                try buf.appendSlice(allocator, "'\n");
            },
            .zsh => {
                try buf.appendSlice(allocator, "PROMPT='");
                try buf.appendSlice(allocator, prompt_start);
                try buf.appendSlice(allocator, "%m:%~ %n%# ");
                try buf.appendSlice(allocator, prompt_end);
                try buf.appendSlice(allocator, "'\n");
            },
            .fish => {
                try buf.appendSlice(allocator, "function fish_prompt\n");
                try buf.appendSlice(allocator, "    printf '");
                try buf.appendSlice(allocator, prompt_start);
                try buf.appendSlice(allocator, "'\n");
                try buf.appendSlice(allocator, "    echo (prompt_hostname):(prompt_pwd) (whoami)$ \n");
                try buf.appendSlice(allocator, "    printf '");
                try buf.appendSlice(allocator, prompt_end);
                try buf.appendSlice(allocator, "'\n");
                try buf.appendSlice(allocator, "end\n");
            },
        }

        return try buf.toOwnedSlice(allocator);
    }
};

test "shell integration demo" {
    const allocator = std.testing.allocator;

    // Test shell integration example
    var shell_integration = ShellIntegrationExample.init(allocator);

    var output_buf = std.ArrayListUnmanaged(u8){};
    defer output_buf.deinit(allocator);

    const exit_code = try shell_integration.executeCommandWithIntegration(
        output_buf.writer(allocator),
        "ls",
        "/home/user",
    );

    try std.testing.expectEqual(@as(i32, 0), exit_code);
    try std.testing.expect(output_buf.items.len > 0);
}

test "shell profile generation" {
    const allocator = std.testing.allocator;

    // Test bash profile generation
    const bash_profile = try ShellProfile.generateShellIntegrationSetup(allocator, .bash);
    defer allocator.free(bash_profile);

    try std.testing.expect(std.mem.indexOf(u8, bash_profile, "ShellIntegration=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, bash_profile, "PS1=") != null);

    // Test zsh profile generation
    const zsh_profile = try ShellProfile.generateShellIntegrationSetup(allocator, .zsh);
    defer allocator.free(zsh_profile);

    try std.testing.expect(std.mem.indexOf(u8, zsh_profile, "ShellIntegration=2") != null);
    try std.testing.expect(std.mem.indexOf(u8, zsh_profile, "PROMPT=") != null);
}
# iTerm2 Shell Integration Module

This module provides comprehensive iTerm2-specific shell integration features based on Charmbracelet's approach. It extends beyond standard FinalTerm markers to provide advanced terminal integration capabilities.

## Features

### 1. Remote Host Identification
Mark when SSH'ing to remote hosts to help iTerm2 track sessions:

```zig
const iterm2_si = @import("iterm2_shell_integration");

// Mark SSH connection to remote host
const remote_seq = try iterm2_si.markRemoteHost(allocator, .{
    .hostname = "example.com",
    .username = "user",
    .port = 22,
});
defer allocator.free(remote_seq);
try writer.writeAll(remote_seq);

// Clear remote host marking (back to local)
const clear_seq = try iterm2_si.clearRemoteHost(allocator);
defer allocator.free(clear_seq);
try writer.writeAll(clear_seq);
```

### 2. Current User Tracking
Track the current user for shell prompts and UI elements:

```zig
// Set current user
const user_seq = try iterm2_si.setCurrentUser(allocator, "username");
defer allocator.free(user_seq);
try writer.writeAll(user_seq);

// Get current user from environment
const current_user = try iterm2_si.getCurrentUser(allocator);
defer allocator.free(current_user);
```

### 3. Shell Integration Mode
Activate iTerm2's shell integration features:

```zig
// Enable full shell integration
const enable_seq = try iterm2_si.enableShellIntegration(allocator);
defer allocator.free(enable_seq);
try writer.writeAll(enable_seq);

// Disable shell integration
const disable_seq = try iterm2_si.disableShellIntegration(allocator);
defer allocator.free(disable_seq);
try writer.writeAll(disable_seq);
```

### 4. Command Status Indicators
More detailed command status than FinalTerm:

```zig
// Mark command start with working directory
const start_seq = try iterm2_si.markCommandStart(allocator, .{
    .command = "git status",
    .working_directory = "/home/user/project",
});
defer allocator.free(start_seq);
try writer.writeAll(start_seq);

// Mark command completion with exit code and duration
const end_seq = try iterm2_si.markCommandEnd(allocator, .{
    .command = "git status",
    .exit_code = 0,
    .duration_ms = 250,
});
defer allocator.free(end_seq);
try writer.writeAll(end_seq);
```

### 5. Attention Requests
Request terminal attention/notification:

```zig
// Simple attention request
const attention_seq = try iterm2_si.requestAttention(allocator, null);
defer allocator.free(attention_seq);
try writer.writeAll(attention_seq);

// Attention with custom message
const notify_seq = try iterm2_si.notify(allocator, "Build completed!");
defer allocator.free(notify_seq);
try writer.writeAll(notify_seq);
```

### 6. Badge Support
Set badge text in iTerm2 window/tab:

```zig
// Set simple badge
const badge_seq = try iterm2_si.setBadge(allocator, "Working...");
defer allocator.free(badge_seq);
try writer.writeAll(badge_seq);

// Set badge with formatting
const badge_fmt_seq = try iterm2_si.setBadgeFormat(allocator, "Branch: {s}", .{"main"});
defer allocator.free(badge_fmt_seq);
try writer.writeAll(badge_fmt_seq);

// Clear badge
const clear_badge_seq = try iterm2_si.clearBadge(allocator);
defer allocator.free(clear_badge_seq);
try writer.writeAll(clear_badge_seq);
```

### 7. Annotations
Add inline annotations to terminal output:

```zig
// Add annotation with URL
const annotation_seq = try iterm2_si.addAnnotation(allocator, .{
    .text = "Click here for help",
    .x = 10,
    .y = 5,
    .url = "https://example.com/help",
});
defer allocator.free(annotation_seq);
try writer.writeAll(annotation_seq);

// Clear all annotations
const clear_annotations_seq = try iterm2_si.clearAnnotations(allocator);
defer allocator.free(clear_annotations_seq);
try writer.writeAll(clear_annotations_seq);
```

### 8. Mark Support
Set marks that can be navigated to:

```zig
// Set command mark
const cmd_mark_seq = try iterm2_si.markCommand(allocator, "build");
defer allocator.free(cmd_mark_seq);
try writer.writeAll(cmd_mark_seq);

// Set error mark
const error_mark_seq = try iterm2_si.markError(allocator, "Compilation failed");
defer allocator.free(error_mark_seq);
try writer.writeAll(error_mark_seq);
```

### 9. Alert on Completion
Trigger alerts when commands complete:

```zig
// Alert on command completion
const alert_seq = try iterm2_si.setAlertOnCompletion(allocator, .{
    .message = "Task finished",
    .only_on_failure = false,
});
defer allocator.free(alert_seq);
try writer.writeAll(alert_seq);

// Alert on long-running commands
const long_cmd_alert_seq = try iterm2_si.alertOnLongCommand(allocator, 300); // 5 minutes
defer allocator.free(long_cmd_alert_seq);
try writer.writeAll(long_cmd_alert_seq);
```

### 10. Download Support
Trigger file downloads from terminal:

```zig
// Trigger file download
const download_seq = try iterm2_si.triggerDownload(allocator, .{
    .url = "https://example.com/file.pdf",
    .filename = "report.pdf",
    .open_after_download = true,
});
defer allocator.free(download_seq);
try writer.writeAll(download_seq);

// Download and open convenience function
const download_open_seq = try iterm2_si.downloadAndOpen(allocator, "https://example.com/image.png", "diagram.png");
defer allocator.free(download_open_seq);
try writer.writeAll(download_open_seq);
```

## Convenience Functions

The module provides high-level convenience functions for common use cases:

```zig
// Initialize full shell integration
const init_sequences = try iterm2_si.Convenience.initFullIntegration(allocator);
defer {
    for (init_sequences) |seq| allocator.free(seq);
    allocator.free(init_sequences);
}
for (init_sequences) |seq| try writer.writeAll(seq);

// Start SSH session with automatic badge and host marking
const ssh_sequences = try iterm2_si.Convenience.startSshSession(allocator, "server.com", "user");
defer {
    for (ssh_sequences) |seq| allocator.free(seq);
    allocator.free(ssh_sequences);
}
for (ssh_sequences) |seq| try writer.writeAll(seq);

// End SSH session
const end_ssh_sequences = try iterm2_si.Convenience.endSshSession(allocator);
defer {
    for (end_ssh_sequences) |seq| allocator.free(seq);
    allocator.free(end_ssh_sequences);
}
for (end_ssh_sequences) |seq| try writer.writeAll(seq);
```

## Shell Integration Setup

### Bash (.bashrc)
```bash
# iTerm2 Shell Integration Setup
printf '\x1b]1337;ShellIntegration=2\x1b\\'
printf '\x1b]1337;SetUser=$USER\x1b\\'
printf '\x1b]1337;SetBadge=Shell Ready\x1b\\'

# Enhanced prompt with shell integration markers
PS1='\x1b]133;A\x1b\\\h:\W \u\$ \x1b]133;D\x1b\\'
```

### Zsh (.zshrc)
```zsh
# iTerm2 Shell Integration Setup
printf '\x1b]1337;ShellIntegration=2\x1b\\'
printf '\x1b]1337;SetUser=$USER\x1b\\'
printf '\x1b]1337;SetBadge=Shell Ready\x1b\\'

# Enhanced prompt with shell integration markers
PROMPT='%{\x1b]133;A\x1b\\%}%m:%~ %n%# %{\x1b]133;D\x1b\\%}'
```

### Fish (config.fish)
```fish
# iTerm2 Shell Integration Setup
printf '\x1b]1337;ShellIntegration=2\x1b\\'
printf '\x1b]1337;SetUser=(whoami)\x1b\\'
printf '\x1b]1337;SetBadge=Shell Ready\x1b\\'

function fish_prompt
    printf '\x1b]133;A\x1b\\'
    echo (prompt_hostname):(prompt_pwd) (whoami)$
    printf '\x1b]133;D\x1b\\'
end
```

## Integration with Existing Code

The module is designed to be compatible with the existing `iterm2.zig` module for image display. You can use both modules together:

```zig
const ansi = @import("shared/term/ansi/mod.zig");

// Use shell integration features
const badge_seq = try ansi.iterm2_shell_integration.setBadge(allocator, "Processing...");
defer allocator.free(badge_seq);
try writer.writeAll(badge_seq);

// Use image display features
const image_seq = try ansi.iterm2.writeITerm2Image(writer, allocator, caps, opts, image_data);
```

## Error Handling

All functions return errors that should be handled appropriately:

```zig
const seq = iterm2_si.setBadge(allocator, "Status") catch |err| {
    // Handle error - perhaps terminal doesn't support iTerm2 features
    std.debug.print("Failed to set badge: {}\n", .{err});
    return err;
};
defer allocator.free(seq);
try writer.writeAll(seq);
```

## Testing

The module includes comprehensive tests that can be run with:

```bash
zig test src/shared/term/ansi/iterm2_shell_integration.zig
```

## Reference

- [iTerm2 Documentation - Shell Integration](https://iterm2.com/documentation-shell-integration.html)
- [Charmbracelet - iTerm2 Integration](https://github.com/charmbracelet)
- [FinalTerm Shell Integration](https://iterm2.com/documentation-shell-integration.html)
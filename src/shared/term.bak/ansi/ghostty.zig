const std = @import("std");

/// Ghostty terminal emulator support module
/// Provides functions for Ghostty-specific features and capabilities
pub const Ghostty = struct {
    /// Shell integration features that Ghostty supports
    pub const ShellIntegrationFeature = enum {
        prompt_marking, // Prompt marking for navigation
        command_marking, // Command output marking
        cwd_reporting, // Current working directory reporting
        exit_code_reporting, // Exit code reporting
        title_setting, // Dynamic title setting
        clipboard_access, // Clipboard integration
        notification_support, // System notifications

        pub fn toString(feature: ShellIntegrationFeature) []const u8 {
            return switch (feature) {
                .prompt_marking => "Prompt Marking",
                .command_marking => "Command Output Marking",
                .cwd_reporting => "Current Working Directory Reporting",
                .exit_code_reporting => "Exit Code Reporting",
                .title_setting => "Dynamic Title Setting",
                .clipboard_access => "Clipboard Integration",
                .notification_support => "System Notifications",
            };
        }
    };

    /// Supported graphics protocols in Ghostty
    pub const GraphicsProtocol = enum {
        kitty, // Kitty Graphics Protocol (preferred)
        sixel, // Sixel graphics
        iterm2, // iTerm2 inline images

        pub fn isSupported(_: GraphicsProtocol) bool {
            // All protocols are supported in Ghostty
            return true;
        }
    };

    /// Check if running in Ghostty terminal
    pub fn isGhostty() bool {
        // Check for GHOSTTY_RESOURCES_DIR (most reliable)
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "GHOSTTY_RESOURCES_DIR")) |_| {
            return true;
        } else |_| {}

        // Check TERM variable
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "TERM")) |term_val| {
            defer std.heap.page_allocator.free(term_val);
            if (std.mem.startsWith(u8, term_val, "xterm-ghostty")) {
                return true;
            }
        } else |_| {}

        return false;
    }

    /// Get the Ghostty resources directory path
    pub fn getResourcesDir(allocator: std.mem.Allocator) !?[]u8 {
        return std.process.getEnvVarOwned(allocator, "GHOSTTY_RESOURCES_DIR") catch |err| {
            if (err == error.EnvironmentVariableNotFound) {
                return null;
            }
            return err;
        };
    }

    /// Get the configured shell integration features
    pub fn getShellIntegrationFeatures(allocator: std.mem.Allocator) ![]ShellIntegrationFeature {
        const features_str = std.process.getEnvVarOwned(allocator, "GHOSTTY_SHELL_INTEGRATION_FEATURES") catch |err| {
            if (err == error.EnvironmentVariableNotFound) {
                // Default features if not specified
                var default_features = try allocator.alloc(ShellIntegrationFeature, 5);
                default_features[0] = .prompt_marking;
                default_features[1] = .command_marking;
                default_features[2] = .cwd_reporting;
                default_features[3] = .title_setting;
                default_features[4] = .clipboard_access;
                return default_features;
            }
            return err;
        };
        defer allocator.free(features_str);

        // Parse comma-separated features
        var features = std.ArrayList(ShellIntegrationFeature).init(allocator);
        var it = std.mem.tokenize(u8, features_str, ",");
        while (it.next()) |feature| {
            const trimmed = std.mem.trim(u8, feature, " ");
            if (std.mem.eql(u8, trimmed, "prompt-marking") or std.mem.eql(u8, trimmed, "prompt_marking")) {
                try features.append(.prompt_marking);
            } else if (std.mem.eql(u8, trimmed, "command-marking") or std.mem.eql(u8, trimmed, "command_marking")) {
                try features.append(.command_marking);
            } else if (std.mem.eql(u8, trimmed, "cwd-reporting") or std.mem.eql(u8, trimmed, "cwd_reporting")) {
                try features.append(.cwd_reporting);
            } else if (std.mem.eql(u8, trimmed, "exit-code-reporting") or std.mem.eql(u8, trimmed, "exit_code_reporting")) {
                try features.append(.exit_code_reporting);
            } else if (std.mem.eql(u8, trimmed, "title-setting") or std.mem.eql(u8, trimmed, "title_setting")) {
                try features.append(.title_setting);
            } else if (std.mem.eql(u8, trimmed, "clipboard-access") or std.mem.eql(u8, trimmed, "clipboard_access")) {
                try features.append(.clipboard_access);
            } else if (std.mem.eql(u8, trimmed, "notification-support") or std.mem.eql(u8, trimmed, "notification_support")) {
                try features.append(.notification_support);
            }
        }

        return features.toOwnedSlice();
    }

    /// Select the best graphics protocol for Ghostty
    /// Prefers Kitty Graphics Protocol as it's the most feature-rich
    pub fn selectBestGraphicsProtocol() GraphicsProtocol {
        // Ghostty supports all three protocols, but Kitty graphics is preferred
        // for its features and efficiency
        return .kitty;
    }

    /// Check if Ghostty is in Quick Terminal mode (macOS)
    pub fn isQuickTerminal() bool {
        // Quick Terminal can be detected through window properties
        // This would require platform-specific code for full detection
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "GHOSTTY_QUICK_TERMINAL")) |val| {
            defer std.heap.page_allocator.free(val);
            return std.mem.eql(u8, val, "1") or std.mem.eql(u8, val, "true");
        } else |_| {}
        return false;
    }

    /// Format text for shell integration prompt marking
    pub fn formatPromptMark(allocator: std.mem.Allocator, prompt: []const u8) ![]u8 {
        // Uses OSC 133 for prompt marking (FinalTerm protocol)
        return std.fmt.allocPrint(allocator, "\x1b]133;A\x07{s}\x1b]133;B\x07", .{prompt});
    }

    /// Format command output region markers
    pub fn formatCommandOutput(allocator: std.mem.Allocator, command: []const u8) ![]u8 {
        // Mark command execution start and end
        return std.fmt.allocPrint(allocator, "\x1b]133;C\x07{s}\x1b]133;D\x07", .{command});
    }

    /// Enable synchronized output for atomic screen updates
    pub fn enableSynchronizedOutput(writer: anytype) !void {
        // Begin synchronized update
        try writer.writeAll("\x1b[?2026h");
    }

    /// Disable synchronized output
    pub fn disableSynchronizedOutput(writer: anytype) !void {
        // End synchronized update
        try writer.writeAll("\x1b[?2026l");
    }

    /// Set clipboard content using OSC 52
    pub fn setClipboard(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
        const base64_encoder = std.base64.standard.Encoder;
        const encoded_len = base64_encoder.calcSize(content.len);
        const encoded = try allocator.alloc(u8, encoded_len);
        _ = base64_encoder.encode(encoded, content);

        return std.fmt.allocPrint(allocator, "\x1b]52;c;{s}\x07", .{encoded});
    }

    /// Query terminal for theme (light/dark mode)
    pub fn queryTheme(writer: anytype) !void {
        // Uses OSC 11 to query background color
        try writer.writeAll("\x1b]11;?\x07");
    }

    /// Enable focus event reporting
    pub fn enableFocusReporting(writer: anytype) !void {
        try writer.writeAll("\x1b[?1004h");
    }

    /// Disable focus event reporting
    pub fn disableFocusReporting(writer: anytype) !void {
        try writer.writeAll("\x1b[?1004l");
    }

    /// Jump to previous prompt (requires shell integration)
    pub fn jumpToPreviousPrompt(writer: anytype) !void {
        // This would typically be bound to a key in Ghostty config
        // Sending the escape sequence for prompt navigation
        try writer.writeAll("\x1b[1;2A"); // Shift+Up by default
    }

    /// Jump to next prompt (requires shell integration)
    pub fn jumpToNextPrompt(writer: anytype) !void {
        try writer.writeAll("\x1b[1;2B"); // Shift+Down by default
    }

    /// Create a notification using OSC 9
    pub fn sendNotification(allocator: std.mem.Allocator, message: []const u8) ![]u8 {
        return std.fmt.allocPrint(allocator, "\x1b]9;{s}\x07", .{message});
    }

    /// Get Ghostty version if available
    pub fn getVersion(allocator: std.mem.Allocator) !?[]u8 {
        return std.process.getEnvVarOwned(allocator, "GHOSTTY_VERSION") catch |err| {
            if (err == error.EnvironmentVariableNotFound) {
                return null;
            }
            return err;
        };
    }

    /// Check if running over SSH (Ghostty may have reduced capabilities)
    pub fn isSSHSession() bool {
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "SSH_CONNECTION")) |_| {
            return true;
        } else |_| {}

        if (std.process.getEnvVarOwned(std.heap.page_allocator, "SSH_CLIENT")) |_| {
            return true;
        } else |_| {}

        return false;
    }

    /// Get optimal configuration based on Ghostty capabilities
    pub const Config = struct {
        use_kitty_graphics: bool = true,
        use_synchronized_output: bool = true,
        use_focus_events: bool = true,
        use_bracketed_paste: bool = true,
        use_shell_integration: bool = true,
        max_image_size: usize = 335544320, // 320MB default

        pub fn getOptimal() Config {
            var config = Config{};

            // Reduce features over SSH
            if (isSSHSession()) {
                config.use_kitty_graphics = false; // Use sixel over SSH
                config.max_image_size = 10485760; // Limit to 10MB over SSH
            }

            return config;
        }
    };
};

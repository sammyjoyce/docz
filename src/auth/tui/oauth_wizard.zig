//! OAuth Setup Wizard TUI Component
//!
//! Provides an elegant interactive experience for OAuth setup using the modular TUI framework

const std = @import("std");
const print = std.debug.print;
const tui = @import("tui_shared");
const oauth = @import("../oauth/mod.zig");

/// OAuth setup states for progress tracking
const OAuthState = enum {
    initializing,
    generating_pkce,
    building_auth_url,
    waiting_for_browser,
    waiting_for_callback,
    manual_fallback,
    exchanging_tokens,
    saving_credentials,
    completed,
    error_state,
};

/// OAuth progress tracker
const OAuthProgress = struct {
    state: OAuthState,
    step: u32,
    total_steps: u32,
    current_message: []const u8,
    error_message: ?[]const u8,
    is_first_display: bool,
    progress_lines_count: u32,

    fn init() OAuthProgress {
        return OAuthProgress{
            .state = .initializing,
            .step = 1,
            .total_steps = 7,
            .current_message = "Initializing OAuth setup...",
            .error_message = null,
            .is_first_display = true,
            .progress_lines_count = 0,
        };
    }

    fn update(self: *OAuthProgress, state: OAuthState, message: []const u8) void {
        self.state = state;
        self.current_message = message;
        self.step = switch (state) {
            .initializing => 1,
            .generating_pkce => 2,
            .building_auth_url => 3,
            .waiting_for_browser => 4,
            .waiting_for_callback => 5,
            .exchanging_tokens => 5,
            .saving_credentials => 6,
            .completed => 7,
            .manual_fallback => 4,
            .error_state => self.step,
        };
    }

    fn setError(self: *OAuthProgress, error_msg: []const u8) void {
        self.state = .error_state;
        self.error_message = error_msg;
    }

    fn markDisplayed(self: *OAuthProgress, lines_count: u32) void {
        self.is_first_display = false;
        self.progress_lines_count = lines_count;
    }
};

/// Run the OAuth setup wizard - simplified version without TUI
pub fn run(allocator: std.mem.Allocator) !void {
    const oauth_mod = @import("../oauth/mod.zig");
    _ = try oauth_mod.setupOAuth(allocator);
}

/// Enhanced OAuth setup with polished TUI
pub fn setupOAuth(allocator: std.mem.Allocator) !void {
    var progress = OAuthProgress.init();

    // Display header
    displayOAuthHeader();

    // Step 1: Initialize
    progress.update(.initializing, "Initializing OAuth setup...");
    displayProgress(&progress);
    std.Thread.sleep(500_000_000); // 0.5 second delay for effect

    // Step 2: Generate PKCE parameters
    progress.update(.generating_pkce, "Generating PKCE parameters...");
    displayProgress(&progress);

    const pkce_params = oauth.generatePkceParams(allocator) catch |err| {
        progress.setError("Failed to generate PKCE parameters");
        displayProgress(&progress);
        displayGenericError("PKCE parameter generation failed", &[_][]const u8{
            "• This is likely a system-level crypto issue",
            "• Try running the command again",
            "• Check system entropy sources",
        });
        return err;
    };
    defer pkce_params.deinit(allocator);

    // Step 3: Build authorization URL
    progress.update(.building_auth_url, "Building authorization URL...");
    displayProgress(&progress);

    const auth_url = oauth.buildAuthorizationUrl(allocator, pkce_params) catch |err| {
        progress.setError("Failed to build authorization URL");
        displayProgress(&progress);
        displayGenericError("URL construction failed", &[_][]const u8{
            "• This may be a memory allocation issue",
            "• Try restarting the terminal",
            "• Contact support if the problem persists",
        });
        return err;
    };
    defer allocator.free(auth_url);

    // Step 4: Launch browser
    progress.update(.waiting_for_browser, "Opening browser...");
    displayProgress(&progress);
    displayBrowserInstructions(auth_url);

    oauth.launchBrowser(auth_url) catch {
        // Browser launch failed, but continue - user can copy URL manually
    };

    std.Thread.sleep(2_000_000_000); // 2 second delay

    // Step 5: Manual code entry (local callback doesn't work with Anthropic's OAuth setup)
    progress.update(.manual_fallback, "Ready for manual code entry...");
    displayProgress(&progress);
    std.Thread.sleep(1_000_000_000); // 1 second delay

    displayManualCodeEntry();
    const auth_code = readAuthorizationCode(allocator) catch |err| {
        displayGenericError("Failed to read authorization code", &[_][]const u8{
            "• Make sure you entered the complete authorization code",
            "• Check that you copied it correctly from the browser",
            "• Try the OAuth setup process again",
        });
        return err;
    };
    defer allocator.free(auth_code);

    // After manual code entry, we need to re-display the header since the screen was cleared
    displayOAuthHeader();
    progress.is_first_display = true; // Reset progress display state

    // Step 5: Exchange tokens
    progress.update(.exchanging_tokens, "Exchanging authorization code for tokens...");
    displayProgress(&progress);

    const credentials = oauth.exchangeCodeForTokens(allocator, auth_code, pkce_params) catch |err| {
        displayGenericError("Token exchange failed", &[_][]const u8{
            "• Authorization code may have expired",
            "• Try the OAuth setup process again",
            "• Check your network connection",
        });
        return err;
    };

    // Step 6: Save credentials
    progress.update(.saving_credentials, "Saving OAuth credentials securely...");
    displayProgress(&progress);

    const creds_path = "claude_oauth_creds.json";
    oauth.saveCredentials(allocator, creds_path, credentials) catch |err| {
        displayGenericError("Failed to save credentials", &[_][]const u8{
            "• Check write permissions in current directory",
            "• Ensure disk space is available",
            "• Try running with elevated permissions if needed",
        });
        return err;
    };

    // Set secure file permissions
    if (std.fs.cwd().openFile(creds_path, .{})) |file| {
        defer file.close();
        file.chmod(0o600) catch {};
    } else |_| {}

    // Step 7: Completion
    progress.update(.completed, "OAuth setup completed successfully!");
    displayProgress(&progress);
    std.Thread.sleep(1_000_000_000); // 1 second delay

    // Clean up credentials memory
    credentials.deinit(allocator);

    // Show success screen
    displaySuccess();
}

/// Display the OAuth setup header using TUI framework
fn displayOAuthHeader() void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    tui.clearScreen();

    // Main title section with consistent formatting
    print("{s}╔{s}╗{s}\n", .{ tui.Color.BRIGHT_BLUE, "═" ** (width - 4), tui.Color.RESET });
    print("{s}║{s} 🔐 Claude Pro/Max OAuth Setup {s}║{s}\n", .{ tui.Color.BRIGHT_BLUE, " " ** ((width - 34) / 2), " " ** ((width - 34) / 2), tui.Color.RESET });
    print("{s}╚{s}╝{s}\n\n", .{ tui.Color.BRIGHT_BLUE, "═" ** (width - 4), tui.Color.RESET });

    print("Connect your Claude Pro or Claude Max subscription for unlimited usage\n");
    print("This setup only needs to be done once per machine\n\n");
}

/// Display progress information using TUI components
fn displayProgress(progress: *OAuthProgress) void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    // If this is an update, move cursor back to overwrite previous progress
    if (!progress.is_first_display) {
        // Move cursor up to overwrite previous progress
        print("\x1b[{}A", .{progress.progress_lines_count});
    }

    var lines_used: u32 = 0;

    // Progress bar using TUI framework
    var progress_bar = tui.ProgressBar.init(width - 20, progress.total_steps);
    progress_bar.update(@floatFromInt(progress.step));

    print("{s}Progress: {s}", .{ tui.Color.BRIGHT_BLUE, tui.Color.RESET });
    progress_bar.draw();
    print("\n\n");
    lines_used += 2;

    // Current status with appropriate icon
    const status_icon = switch (progress.state) {
        .initializing => "⚡",
        .generating_pkce => "🔧",
        .building_auth_url => "🔗",
        .waiting_for_browser => "🌐",
        .waiting_for_callback => "⏳",
        .manual_fallback => "💡",
        .exchanging_tokens => "⚡",
        .saving_credentials => "🛡️",
        .completed => "✅",
        .error_state => "❌",
    };

    const status_color = switch (progress.state) {
        .completed => tui.Color.BRIGHT_GREEN,
        .error_state => tui.Color.BRIGHT_RED,
        else => tui.Color.BRIGHT_CYAN,
    };

    print("{s}{s} {s}{s}{s}\n\n", .{ status_color, status_icon, tui.Color.BOLD, progress.current_message, tui.Color.RESET });
    lines_used += 2;

    // Error message if present
    if (progress.error_message) |error_msg| {
        print("{s}❌ Error Details{s}\n", .{ tui.Color.BRIGHT_RED, tui.Color.RESET });
        print("{s}\n", .{error_msg});
        print("Please check the message above and try again\n\n");
        lines_used += 4;
    }

    // Clear any remaining lines from previous display
    if (!progress.is_first_display and lines_used < progress.progress_lines_count) {
        const clear_lines = progress.progress_lines_count - lines_used;
        var i: u32 = 0;
        while (i < clear_lines) : (i += 1) {
            print("\x1b[K\n"); // Clear line and move down
        }
        // Move cursor back up
        print("\x1b[{}A", .{clear_lines});
    }

    // Mark this display as completed and record line count
    progress.markDisplayed(lines_used);
}

/// Display browser launch instructions
fn displayBrowserInstructions(auth_url: []const u8) void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    print("\n{s}Browser Authorization{s}\n", .{ tui.Color.BRIGHT_BLUE, tui.Color.RESET });
    print("{s}\n", .{"─" ** @min(width, 50)});

    print("🌐 Your browser should open automatically\n");
    print("📋 If it doesn't, copy and paste this URL:\n\n");
    print("{s}{s}{s}\n\n", .{ tui.Color.DIM, auth_url, tui.Color.RESET });
    print("✅ Complete the authorization in your browser\n");
    print("🔄 You'll be redirected to a callback page with the authorization code\n");
    print("💡 Copy the code from the callback page and return here\n\n");
}

/// Display manual code entry screen
fn displayManualCodeEntry() void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    tui.clearScreen();

    print("{s}╔{s}╗{s}\n", .{ tui.Color.BRIGHT_CYAN, "═" ** (width - 4), tui.Color.RESET });
    print("{s}║{s} 📋 Manual Code Entry {s}║{s}\n", .{ tui.Color.BRIGHT_CYAN, " " ** ((width - 24) / 2), " " ** ((width - 24) / 2), tui.Color.RESET });
    print("{s}╚{s}╝{s}\n\n", .{ tui.Color.BRIGHT_CYAN, "═" ** (width - 4), tui.Color.RESET });

    print("1. Complete the authorization in your browser\n");
    print("2. You'll be redirected to a URL that starts with:\n");
    print("   {s}https://console.anthropic.com/oauth/code/callback?code=...{s}\n", .{ tui.Color.DIM, tui.Color.RESET });
    print("3. Copy the authorization code from that URL\n\n");
    print("💡 TIP: The code appears after 'code=' and before '&state='\n");
    print("       Example: ...?code=AUTH_CODE_HERE&state=...\n\n");
    print("⌨️  INPUT FEATURES:\n");
    print("   • Paste support: Ctrl+V or right-click paste\n");
    print("   • Ctrl+U: Clear entire input line\n");
    print("   • Ctrl+C: Cancel and exit setup\n\n");
}

/// Enhanced authorization code input
fn readAuthorizationCode(allocator: std.mem.Allocator) ![]u8 {
    print("Please enter the authorization code: ");

    const stdin = std.fs.File.stdin();
    var buffer: [1024]u8 = undefined;

    if (try stdin.readAll(buffer[0..])) |bytes_read| {
        if (bytes_read == 0) {
            return error.NoInput;
        }

        const input = std.mem.trim(u8, buffer[0..bytes_read], " \t\r\n");

        // Basic validation
        if (input.len < 10) {
            print("{s}❌ Authorization code seems too short (got {} chars). Please verify and try again.{s}\n", .{ tui.Color.BRIGHT_RED, input.len, tui.Color.RESET });
            return error.InvalidAuthCode;
        }

        print("\n{s}✅ Authorization code received ({} characters){s}\n", .{ tui.Color.BRIGHT_GREEN, input.len, tui.Color.RESET });

        return allocator.dupe(u8, input);
    }

    return error.NoInput;
}

/// Display success screen
fn displaySuccess() void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    tui.clearScreen();

    print("{s}╔{s}╗{s}\n", .{ tui.Color.BRIGHT_GREEN, "═" ** (width - 4), tui.Color.RESET });
    print("{s}║{s} 🚀 Setup Complete! {s}║{s}\n", .{ tui.Color.BRIGHT_GREEN, " " ** ((width - 21) / 2), " " ** ((width - 21) / 2), tui.Color.RESET });
    print("{s}╚{s}╝{s}\n\n", .{ tui.Color.BRIGHT_GREEN, "═" ** (width - 4), tui.Color.RESET });

    print("🎉 OAuth setup completed successfully!\n\n");
    print("✅ Your Claude Pro/Max authentication is now configured\n");
    print("🔒 Credentials saved securely to claude_oauth_creds.json\n");
    print("💰 Usage costs are covered by your subscription\n");
    print("🔄 Tokens will be automatically refreshed as needed\n\n");
    print("Next steps:\n");
    print("• Run regular CLI commands to test the setup\n");
    print("• Your authentication will work seamlessly\n");
    print("• No need to set ANTHROPIC_API_KEY anymore\n\n");

    print("Press any key to continue...");
    const stdin = std.fs.File.stdin();
    var buffer: [1]u8 = undefined;
    _ = stdin.read(buffer[0..]) catch {};
}

/// Display generic error with suggestions
fn displayGenericError(error_msg: []const u8, suggestions: []const []const u8) void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    tui.clearScreen();

    print("{s}╔{s}╗{s}\n", .{ tui.Color.BRIGHT_RED, "═" ** (width - 4), tui.Color.RESET });
    print("{s}║{s} 🚨 Setup Error {s}║{s}\n", .{ tui.Color.BRIGHT_RED, " " ** ((width - 16) / 2), " " ** ((width - 16) / 2), tui.Color.RESET });
    print("{s}╚{s}╝{s}\n\n", .{ tui.Color.BRIGHT_RED, "═" ** (width - 4), tui.Color.RESET });

    print("{s}\n\n", .{error_msg});
    print("🔧 Troubleshooting suggestions:\n");

    for (suggestions) |suggestion| {
        print("{s}\n", .{suggestion});
    }

    print("\n🔄 Try running: docz auth login\n\n");

    print("Press any key to continue...");
    const stdin = std.fs.File.stdin();
    var buffer: [1]u8 = undefined;
    _ = stdin.read(buffer[0..]) catch {};
}

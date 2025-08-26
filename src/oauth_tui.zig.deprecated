//! Polished OAuth Terminal User Interface for DocZ
//! Provides an elegant interactive experience for OAuth setup

const std = @import("std");
const tui = @import("tui.zig");
const anthropic = @import("anthropic_shared");
const print = std.debug.print;

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
pub const OAuthProgress = struct {
    state: OAuthState,
    step: u32,
    total_steps: u32,
    current_message: []const u8,
    error_message: ?[]const u8,
    is_first_display: bool,
    progress_lines_count: u32, // Track how many lines the progress section takes

    pub fn init() OAuthProgress {
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

    pub fn update(self: *OAuthProgress, state: OAuthState, message: []const u8) void {
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

    pub fn setError(self: *OAuthProgress, error_msg: []const u8) void {
        self.state = .error_state;
        self.error_message = error_msg;
    }

    pub fn markDisplayed(self: *OAuthProgress, lines_count: u32) void {
        self.is_first_display = false;
        self.progress_lines_count = lines_count;
    }
};

/// Display the OAuth setup header
fn displayOAuthHeader() void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    tui.clearScreen();

    // Main title section
    const title_section = tui.Section.init("🔐 Claude Pro/Max OAuth Setup", &[_][]const u8{
        "",
        "Connect your Claude Pro or Claude Max subscription for unlimited usage",
        "This setup only needs to be done once per machine",
        "",
    }, width);
    title_section.draw();

    print("\n", .{});
}

/// Display progress information
fn displayProgress(progress: *OAuthProgress) void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    // If this is an update, move cursor back to overwrite previous progress
    if (!progress.is_first_display) {
        tui.Control.moveUp(progress.progress_lines_count);
    }

    var lines_used: u32 = 0;

    // Progress bar
    var progress_bar = tui.ProgressBar.init(width - 20, progress.total_steps);
    progress_bar.update(progress.step);

    print("{s}Progress: {s}", .{ tui.Color.BRIGHT_BLUE, tui.Color.RESET });
    progress_bar.draw();
    print("\n\n", .{});
    lines_used += 2;

    // Current status
    const status_icon = switch (progress.state) {
        .initializing => tui.Status.LOADING,
        .generating_pkce => tui.Status.GEAR,
        .building_auth_url => tui.Status.LINK,
        .waiting_for_browser => tui.Status.BROWSER,
        .waiting_for_callback => tui.Status.WAITING,
        .manual_fallback => tui.Status.INFO,
        .exchanging_tokens => tui.Status.LOADING,
        .saving_credentials => tui.Status.SHIELD,
        .completed => tui.Status.SUCCESS,
        .error_state => tui.Status.ERROR,
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
        const error_section = tui.Section.init("❌ Error Details", &[_][]const u8{
            error_msg,
            "",
            "Please check the message above and try again",
        }, width);
        error_section.draw();
        print("\n", .{});
        lines_used += 6; // Section typically uses about 6 lines
    }

    // Clear any remaining lines from previous display (if this update uses fewer lines)
    if (!progress.is_first_display and lines_used < progress.progress_lines_count) {
        tui.Control.clearLinesDown(progress.progress_lines_count - lines_used);
    }

    // Mark this display as completed and record line count
    progress.markDisplayed(lines_used);
}

/// Display browser launch instructions
fn displayBrowserInstructions(auth_url: []const u8) void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    const instructions = [_][]const u8{
        "",
        "🌐 Your browser should open automatically",
        "📋 If it doesn't, copy and paste this URL:",
        "",
        auth_url,
        "",
        "✅ Complete the authorization in your browser",
        "🔄 You'll be redirected to a callback page with the authorization code",
        "",
        "💡 Copy the code from the callback page and return here",
        "",
    };

    const browser_section = tui.Section.init("Browser Authorization", &instructions, width);
    browser_section.draw();
    print("\n", .{});
}

/// Display callback waiting screen with animation
fn displayCallbackWaiting(spinner: *tui.Spinner) void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    print("\r{s}", .{tui.Control.CLEAR_LINE});

    const waiting_text = [1][]const u8{
        "Waiting for authorization callback... (Press Ctrl+C for manual entry)",
    };

    const callback_section = tui.Section.init("Callback Status", &waiting_text, width);
    callback_section.draw();

    // Animated spinner
    print("\n", .{});
    spinner.draw("Listening for callback");

    // Status bar
    const status_bar = tui.StatusBar.init("🔗 Waiting for browser callback", "Esc to cancel  Ctrl+C for manual  1 file changed");
    status_bar.draw();
}

/// Enhanced authorization code input using the TUI TextInput widget
fn readAuthorizationCode(allocator: std.mem.Allocator) ![]u8 {
    print("\n", .{});

    const auth_code = tui.TextInput.readOAuthCode(allocator) catch |err| {
        switch (err) {
            error.InputCancelled => {
                print("{s}OAuth setup cancelled by user{s}\n", .{ tui.Color.BRIGHT_YELLOW, tui.Color.RESET });
                return err;
            },
            error.NoInput => {
                print("{s}❌ No authorization code provided{s}\n", .{ tui.Color.BRIGHT_RED, tui.Color.RESET });
                return err;
            },
            else => {
                print("{s}❌ Error reading authorization code: {}{s}\n", .{ tui.Color.BRIGHT_RED, err, tui.Color.RESET });
                return err;
            },
        }
    };

    // Additional validation for OAuth codes
    if (auth_code.len < 10) {
        print("{s}❌ Authorization code seems too short (got {} chars). Please verify and try again.{s}\n", .{ tui.Color.BRIGHT_RED, auth_code.len, tui.Color.RESET });
        allocator.free(auth_code);
        return error.InvalidAuthCode;
    }

    // Check for common OAuth code patterns
    const looks_like_oauth_code = blk: {
        // OAuth codes typically contain alphanumeric characters and some symbols
        for (auth_code) |char| {
            if (!std.ascii.isAlphanumeric(char) and
                char != '-' and char != '_' and char != '.' and
                char != '~' and char != '+' and char != '=')
            {
                break :blk false;
            }
        }
        break :blk true;
    };

    if (!looks_like_oauth_code) {
        print("{s}⚠️  Warning: This doesn't look like a typical OAuth authorization code.{s}\n", .{ tui.Color.BRIGHT_YELLOW, tui.Color.RESET });
        print("{s}Expected: alphanumeric characters with dashes, underscores, etc.{s}\n", .{ tui.Color.DIM, tui.Color.RESET });
        print("{s}Continuing anyway...{s}\n", .{ tui.Color.DIM, tui.Color.RESET });
    }

    print("\n{s}✅ Authorization code received ({} characters){s}\n", .{ tui.Color.BRIGHT_GREEN, auth_code.len, tui.Color.RESET });

    return auth_code;
}

/// Display manual code entry screen
fn displayManualCodeEntry() void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    tui.clearScreen();

    const instructions = [_][]const u8{
        "",
        "📋 MANUAL CODE ENTRY",
        "",
        "1. Complete the authorization in your browser",
        "2. You'll be redirected to a URL that starts with:",
        "   https://console.anthropic.com/oauth/code/callback?code=...",
        "3. Copy the authorization code from that URL",
        "",
        "💡 TIP: The code appears after 'code=' and before '&state='",
        "       Example: ...?code=AUTH_CODE_HERE&state=...",
        "",
        "⌨️  ENHANCED INPUT FEATURES:",
        "   • Paste support: Ctrl+V or right-click paste",
        "   • Backspace: Delete characters one by one",
        "   • Ctrl+U: Clear entire input line",
        "   • Ctrl+C: Cancel and exit setup",
        "   • Automatic validation of code format",
        "",
    };

    const manual_section = tui.Section.init("🔐 Enhanced Manual OAuth Setup", &instructions, width);
    manual_section.draw();
    print("\n", .{});
}

/// Display success screen
fn displaySuccess() void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    tui.clearScreen();

    const success_content = [_][]const u8{
        "",
        "🎉 OAuth setup completed successfully!",
        "",
        "✅ Your Claude Pro/Max authentication is now configured",
        "🔒 Credentials saved securely to claude_oauth_creds.json",
        "💰 Usage costs are covered by your subscription",
        "🔄 Tokens will be automatically refreshed as needed",
        "",
        "Next steps:",
        "• Run regular CLI commands to test the setup",
        "• Your authentication will work seamlessly",
        "• No need to set ANTHROPIC_API_KEY anymore",
        "",
    };

    const success_section = tui.Section.init("🚀 Setup Complete!", &success_content, width);
    success_section.draw();
    print("\n", .{});

    // Status bar
    const status_bar = tui.StatusBar.init("✅ OAuth setup completed successfully", "Press any key to continue");
    status_bar.draw();

    // Wait for keypress
    const stdin = std.fs.File.stdin();
    var buffer: [1]u8 = undefined;
    _ = stdin.read(buffer[0..]) catch {};
}

/// Enhanced error display with detailed, context-specific messages
fn displayError(error_type: anthropic.Error) void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    tui.clearScreen();

    // Build detailed error content based on error type
    var error_content = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
    defer error_content.deinit();

    const main_title = switch (error_type) {
        anthropic.Error.AuthError => "🚫 Authentication Error",
        anthropic.Error.NetworkError => "🌐 Network Error",
        else => "🔧 OAuth Setup Error",
    };

    const error_description = switch (error_type) {
        anthropic.Error.AuthError => "Authentication failed during the OAuth token exchange",
        anthropic.Error.NetworkError => "Network error occurred during OAuth token exchange",
        else => "An unexpected error occurred during the OAuth setup",
    };

    // Add main error info
    error_content.append("") catch return;
    error_content.append(error_description) catch return;
    error_content.append("") catch return;

    // Add detailed troubleshooting based on error type
    const troubleshooting_header = "💡 Detailed troubleshooting and solutions:";
    error_content.append(troubleshooting_header) catch return;
    error_content.append("") catch return;

    switch (error_type) {
        anthropic.Error.AuthError => {
            error_content.append("• Authorization code expired (codes expire after 10 minutes)") catch return;
            error_content.append("  → Re-run the OAuth setup: docz --oauth") catch return;
            error_content.append("") catch return;
            error_content.append("• Invalid or incomplete callback URL") catch return;
            error_content.append("  → Make sure you copied the complete authorization code") catch return;
            error_content.append("  → Check that the code starts and ends correctly") catch return;
            error_content.append("") catch return;
            error_content.append("• Using the wrong Claude account") catch return;
            error_content.append("  → Ensure you're logged into the correct Claude account") catch return;
            error_content.append("  → Check that your account has Pro or Max subscription") catch return;
            error_content.append("") catch return;
            error_content.append("• Code already used or corrupted") catch return;
            error_content.append("  → Authorization codes can only be used once") catch return;
            error_content.append("  → Start fresh with: docz --oauth") catch return;
        },
        anthropic.Error.NetworkError => {
            error_content.append("• Check your internet connection") catch return;
            error_content.append("  → Ensure you have stable connectivity") catch return;
            error_content.append("  → Try accessing other websites to verify connection") catch return;
            error_content.append("") catch return;
            error_content.append("• Anthropic servers may be temporarily unavailable") catch return;
            error_content.append("  → Try again in a few moments (server may be busy)") catch return;
            error_content.append("  → Check Anthropic's status page for service updates") catch return;
            error_content.append("") catch return;
            error_content.append("• Firewall or proxy blocking connection") catch return;
            error_content.append("  → Check corporate firewall settings") catch return;
            error_content.append("  → Try from a different network if possible") catch return;
            error_content.append("") catch return;
            error_content.append("• DNS resolution issues") catch return;
            error_content.append("  → Try flushing DNS cache") catch return;
            error_content.append("  → Use alternative DNS servers (8.8.8.8, 1.1.1.1)") catch return;
        },
        else => {
            error_content.append("• Unexpected error occurred during OAuth setup") catch return;
            error_content.append("  → This may be a system-level issue") catch return;
            error_content.append("  → Try restarting the terminal/application") catch return;
            error_content.append("") catch return;
            error_content.append("• Memory or resource constraints") catch return;
            error_content.append("  → Close other applications to free resources") catch return;
            error_content.append("  → Try running the command again") catch return;
        },
    }

    error_content.append("") catch return;
    error_content.append("🔄 Next steps:") catch return;
    error_content.append("  • Try running the OAuth setup again: docz --oauth") catch return;
    error_content.append("  • If problems persist, try the classic setup: docz -O") catch return;
    error_content.append("  • Check that you have Claude Pro or Max subscription") catch return;
    error_content.append("") catch return;

    const error_section = tui.Section.init(main_title, error_content.items, width);
    error_section.draw();
    print("\n", .{});

    // Status bar with additional context
    const status_text = switch (error_type) {
        anthropic.Error.AuthError => "❌ Authentication failed - Check authorization code",
        anthropic.Error.NetworkError => "❌ Network error - Check connection and try again",
        else => "❌ OAuth setup failed - Try again or use fallback",
    };

    const status_bar = tui.StatusBar.init(status_text, "Press any key to continue");
    status_bar.draw();

    // Wait for keypress
    const stdin = std.fs.File.stdin();
    var buffer: [1]u8 = undefined;
    _ = stdin.read(buffer[0..]) catch {};
}

/// Compatibility wrapper for generic error messages (fallback)
fn displayGenericError(error_msg: []const u8, suggestions: []const []const u8) void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    tui.clearScreen();

    // Build error content
    var error_content = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
    defer error_content.deinit();

    error_content.append("") catch return;
    error_content.append(error_msg) catch return;
    error_content.append("") catch return;
    error_content.append("🔧 Troubleshooting suggestions:") catch return;

    for (suggestions) |suggestion| {
        error_content.append(suggestion) catch return;
    }

    error_content.append("") catch return;
    error_content.append("🔄 Try running: docz --oauth") catch return;
    error_content.append("") catch return;

    const error_section = tui.Section.init("🚨 Setup Error", error_content.items, width);
    error_section.draw();
    print("\n", .{});

    // Status bar
    const status_bar = tui.StatusBar.init("❌ OAuth setup failed", "Press any key to continue");
    status_bar.draw();

    // Wait for keypress
    const stdin = std.fs.File.stdin();
    var buffer: [1]u8 = undefined;
    _ = stdin.read(buffer[0..]) catch {};
}

/// Enhanced OAuth setup with polished TUI
pub fn setupOAuthWithTUI(allocator: std.mem.Allocator) !void {
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

    const pkce_params = anthropic.generatePkceParams(allocator) catch |err| {
        progress.setError("Failed to generate PKCE parameters");
        displayProgress(&progress);
        displayGenericError("PKCE parameter generation failed", &[_][]const u8{
            "• This is likely a system-level crypto issue",
            "• Try running the command again",
            "• Check system entropy sources",
        });
        return err;
    };
    defer {
        allocator.free(pkce_params.code_verifier);
        allocator.free(pkce_params.code_challenge);
        allocator.free(pkce_params.state);
    }

    // Step 3: Build authorization URL
    progress.update(.building_auth_url, "Building authorization URL...");
    displayProgress(&progress);

    const auth_url = anthropic.buildAuthorizationUrl(allocator, pkce_params) catch |err| {
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

    anthropic.launchBrowser(auth_url) catch {
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

    const credentials = anthropic.exchangeCodeForTokens(allocator, auth_code, pkce_params) catch |err| {
        // Use enhanced error display for known error types
        switch (err) {
            anthropic.Error.AuthError, anthropic.Error.NetworkError => {
                displayError(err);
            },
            else => {
                displayGenericError("Token exchange failed", &[_][]const u8{
                    "• Unknown error occurred during token exchange",
                    "• Try the OAuth setup process again",
                    "• Contact support if the problem persists",
                });
            },
        }
        return err;
    };

    // Step 6: Save credentials
    progress.update(.saving_credentials, "Saving OAuth credentials securely...");
    displayProgress(&progress);

    const creds_path = "claude_oauth_creds.json";
    anthropic.saveOAuthCredentials(allocator, creds_path, credentials) catch |err| {
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
    allocator.free(credentials.type);
    allocator.free(credentials.access_token);
    allocator.free(credentials.refresh_token);

    // Show success screen
    displaySuccess();
}

//! Interactive CLI interface for DocZ
//! Provides command palette and enhanced user experience

const std = @import("std");
const tui = @import("tui/mod.zig");
const engine = @import("core_engine");
const selected_spec = @import("agent_spec");
const anthropic = @import("anthropic_shared");
const auth = @import("../auth/mod.zig");

const print = std.debug.print;

/// Available commands in the interactive interface
const Command = enum {
    chat,
    oauth_setup,
    help,
    status,
    refresh,
    quit,

    pub fn fromString(str: []const u8) ?Command {
        if (std.mem.eql(u8, str, "chat")) return .chat;
        if (std.mem.eql(u8, str, "oauth")) return .oauth_setup;
        if (std.mem.eql(u8, str, "help")) return .help;
        if (std.mem.eql(u8, str, "status")) return .status;
        if (std.mem.eql(u8, str, "refresh")) return .refresh;

        if (std.mem.eql(u8, str, "quit") or std.mem.eql(u8, str, "exit")) return .quit;
        return null;
    }
};

/// Available command names for tab completion
const COMMAND_NAMES = [_][]const u8{
    "chat",
    "oauth",
    "help",
    "status",
    "refresh",
    "quit",
};

/// Cached authentication status to avoid repeated file I/O operations
const AuthStatusCache = struct {
    auth_status: []const u8,
    auth_detail: []const u8,
    last_updated: i64,

    const CACHE_DURATION_MS = 30000; // 30 seconds

    fn init() AuthStatusCache {
        return .{
            .auth_status = "",
            .auth_detail = "",
            .last_updated = 0,
        };
    }

    fn needsRefresh(self: *const AuthStatusCache) bool {
        const now = std.time.milliTimestamp();
        return (now - self.last_updated) > CACHE_DURATION_MS;
    }

    fn update(self: *AuthStatusCache, allocator: std.mem.Allocator) void {
        // Check authentication status using the new auth system
        var auth_status: []const u8 = "❌ No Auth";
        var auth_detail: []const u8 = "No authentication configured - setup required";

        if (auth.createClient(allocator)) |client| {
            defer client.deinit();

            switch (client.credentials) {
                .oauth => |creds| {
                    if (creds.isExpired()) {
                        auth_status = "⚠️  OAuth (Expired)";
                        auth_detail = "OAuth credentials found but expired - refresh needed";
                    } else {
                        auth_status = "🔐 OAuth (Active)";
                        auth_detail = "Using Claude Pro/Max OAuth authentication";
                    }
                },
                .api_key => {
                    auth_status = "🔑 API Key";
                    auth_detail = "Using ANTHROPIC_API_KEY environment variable";
                },
                .none => {
                    auth_status = "❌ No Auth";
                    auth_detail = "No authentication configured - setup required";
                },
            }
        } else |_| {
            // Keep default values set above
        }

        self.auth_status = auth_status;
        self.auth_detail = auth_detail;
        self.last_updated = std.time.milliTimestamp();
    }
};

/// Command menu items for the interactive interface
const COMMANDS = [_]tui.Menu.MenuItem{
    .{ .key = "chat", .description = "Start a chat conversation with Claude", .action = "Launch interactive chat mode" },
    .{ .key = "oauth", .description = "Setup Claude Pro/Max OAuth authentication", .action = "Configure OAuth credentials" },
    .{ .key = "status", .description = "Show authentication and system status", .action = "Display current status" },
    .{ .key = "refresh", .description = "Refresh authentication status cache", .action = "Update cached auth status" },
    .{ .key = "help", .description = "Show detailed help information", .action = "Display help documentation" },
    .{ .key = "quit", .description = "Exit the interactive interface", .action = "Terminate the program" },
};

/// Display the main header with optional partial update
fn displayHeader(force_redraw: bool) void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    if (force_redraw) {
        tui.clearScreen();
        if (tui.getScreen()) |screen| {
            screen.reset();
        }
    }

    // Main header
    const header_content = [_][]const u8{
        "",
        "🚀 DocZ - Interactive Zig CLI for Claude",
        "Markdown-focused AI assistant with elegant terminal interface",
        "",
    };

    const header_section = tui.Section.init("Welcome to DocZ", &header_content, width);
    header_section.drawWithId("header");
    print("\n", .{});
}

/// Display current authentication status using cached data
fn displayAuthStatus(auth_cache: *const AuthStatusCache) void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    const status_content = [_][]const u8{
        "",
        auth_cache.auth_status,
        auth_cache.auth_detail,
        "",
        "💡 Run 'oauth' command to setup Claude Pro/Max authentication",
        "   Run 'refresh' to update authentication status",
        "",
    };

    const status_section = tui.Section.init("Authentication Status", &status_content, width);
    status_section.drawWithId("auth_status");
    print("\n", .{});
}

/// Display command palette with optional partial update
fn displayCommandPalette() void {
    const menu = tui.Menu.init(&COMMANDS);
    menu.drawWithId("Select command:", "command_palette");
    print("\n", .{});
}

/// Display help information
fn displayHelp() void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    const help_content = [_][]const u8{
        "",
        "📖 USAGE GUIDE:",
        "",
        "• Type a command name and press Enter",
        "• Use Tab for command auto-completion (e.g., 'oau' + Tab → 'oauth')",
        "• Use ↑/↓ arrow keys to navigate command history",
        "• Use 'chat' to start an interactive conversation",
        "• Use 'oauth' to setup Claude Pro/Max authentication",
        "• Use 'status' to check your current authentication",
        "• Use 'refresh' to update authentication status cache",

        "• Use 'quit' or 'exit' to leave the interface",
        "",
        "⚡ QUICK START:",
        "1. Run 'oauth' to setup authentication (recommended)",
        "2. Run 'chat' to start conversing with Claude",
        "3. Type your questions and get instant responses",
        "",
        "🔧 CLI OPTIONS:",
        "• docz \"your prompt\" - Direct prompt mode",
        "• docz --input file.txt - Process file input",
        "• docz --oauth - Setup OAuth authentication",
        "• docz --help - Show detailed help",
        "",
    };

    const help_section = tui.Section.init("📚 Help & Documentation", &help_content, width);
    help_section.draw();
    print("\n", .{});
}

/// Run the interactive CLI interface
pub fn runInteractiveMode(allocator: std.mem.Allocator) !void {
    // Initialize screen state management
    tui.initScreen(allocator);
    defer tui.deinitScreen();

    // Initialize command history (max 100 commands)
    var command_history = tui.CommandHistory.init(allocator, 100);
    defer command_history.deinit();

    // Initialize authentication status cache
    var auth_cache = AuthStatusCache.init();
    auth_cache.update(allocator); // Load initial status

    var is_first_draw = true;

    while (true) {
        // Check if auth cache needs refresh (auto-refresh after timeout)
        if (auth_cache.needsRefresh()) {
            auth_cache.update(allocator);
        }

        // Only force full redraw on first iteration
        displayHeader(is_first_draw);
        displayAuthStatus(&auth_cache);
        displayCommandPalette();

        // Status bar
        const status_bar = tui.StatusBar.init("🔗 Interactive Mode - DocZ CLI", "↑/↓ History  Tab Completion  Ctrl+C to exit");
        status_bar.drawWithId("status_bar");

        // Mark screen as having completed initial draw
        if (is_first_draw) {
            is_first_draw = false;
            if (tui.getScreen()) |screen| {
                screen.finishRedraw();
            }
        }

        print("\n", .{});

        // Get user command with history and tab completion
        const command_input = tui.promptInputEnhanced("docz>", allocator, &command_history, &COMMAND_NAMES) catch |err| switch (err) {
            error.Interrupted => {
                print("Interrupted by user\n");
                continue;
            },
            else => {
                print("Error reading input: {}\n", .{err});
                continue;
            },
        };
        defer allocator.free(command_input);

        if (command_input.len == 0) {
            continue;
        }

        const command = Command.fromString(command_input) orelse {
            print("\n{s}Unknown command: '{s}'{s}\n", .{ tui.Color.BRIGHT_RED, command_input, tui.Color.RESET });
            print("Type 'help' to see available commands.\n\n", .{});
            print("Press Enter to continue...", .{});
            var buffer: [1]u8 = undefined;
            _ = std.fs.File.stdin().read(&buffer) catch {};
            continue;
        };

        print("\n", .{});

        switch (command) {
            .chat => {
                print("🚀 Starting interactive chat mode...\n", .{});
                print("(This would launch the chat interface)\n", .{});
                print("\nPress Enter to continue...", .{});
                var buffer: [1]u8 = undefined;
                _ = std.fs.File.stdin().read(&buffer) catch {};
            },
            .oauth_setup => {
                print("🔐 Starting OAuth setup...\n\n", .{});
                auth.setupOAuth(allocator) catch |err| {
                    print("OAuth setup failed: {}\n", .{err});
                };
                // Refresh auth cache after OAuth setup
                auth_cache.update(allocator);
                print("\nPress Enter to continue...", .{});
                var buffer: [1]u8 = undefined;
                _ = std.fs.File.stdin().read(&buffer) catch {};
            },
            .help => {
                displayHelp();
                print("Press Enter to continue...", .{});
                var buffer: [1]u8 = undefined;
                _ = std.fs.File.stdin().read(&buffer) catch {};
            },
            .status => {
                // For status command, force a refresh and full redraw
                auth_cache.update(allocator);
                displayHeader(true);
                displayAuthStatus(&auth_cache);

                // Additional system info
                const terminal_size = tui.getTerminalSize();
                const width = @min(terminal_size.width, 80);

                // Calculate cache age for display
                const cache_age = (std.time.milliTimestamp() - auth_cache.last_updated) / 1000;
                const cache_info = std.fmt.allocPrint(allocator, "   Auth cache: Updated {d} seconds ago", .{cache_age}) catch "   Auth cache: Unknown";

                const system_content = [_][]const u8{
                    "",
                    "🖥️  Terminal Information:",
                    "",
                    std.fmt.allocPrint(allocator, "   Size: {}x{} characters", .{ terminal_size.width, terminal_size.height }) catch "   Size: Unknown",
                    std.fmt.allocPrint(allocator, "   Platform: {s}", .{@tagName(@import("builtin").os.tag)}) catch "   Platform: Unknown",
                    "",
                    "⚡ Performance:",
                    "   • TUI framework: Active",
                    "   • OAuth integration: Available",
                    "   • Streaming API: Enabled",
                    cache_info,
                    "",
                };

                const system_section = tui.Section.init("System Status", &system_content, width);
                system_section.drawWithId("system_status");

                print("\nPress Enter to continue...", .{});
                var buffer: [1]u8 = undefined;
                _ = std.fs.File.stdin().read(&buffer) catch {};
            },
            .refresh => {
                print("🔄 Refreshing authentication...\n", .{});
                auth.refreshTokens(allocator) catch |err| {
                    print("Refresh failed: {}\n", .{err});
                    print("Updating authentication status cache...\n", .{});
                };
                // Always update the cache after attempting refresh
                auth_cache.update(allocator);
                print("✅ Authentication refresh completed!\n", .{});
                print("\nPress Enter to continue...", .{});
                var buffer: [1]u8 = undefined;
                _ = std.fs.File.stdin().read(&buffer) catch {};
            },

            .quit => {
                print("👋 Thank you for using DocZ!\n", .{});
                return;
            },
        }
    }
}

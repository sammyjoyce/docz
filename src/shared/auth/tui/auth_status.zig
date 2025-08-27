//! Authentication Status Display TUI Component

const std = @import("std");
const print = std.debug.print;
const core = @import("../core/mod.zig");

// Minimal TUI interface with basic ANSI escape codes
const tui = struct {
    fn getTerminalSize() struct { width: u16, height: u16 } {
        // Use a reasonable default since we don't have access to full TUI
        return .{ .width = 80, .height = 24 };
    }

    fn clearScreen() void {
        print("\x1b[2J\x1b[H", .{});
    }

    const Color = struct {
        pub const BRIGHT_BLUE = "\x1b[94m";
        pub const BRIGHT_GREEN = "\x1b[92m";
        pub const BRIGHT_RED = "\x1b[91m";
        pub const BRIGHT_YELLOW = "\x1b[93m";
        pub const BRIGHT_CYAN = "\x1b[96m";
        pub const DIM = "\x1b[2m";
        pub const BOLD = "\x1b[1m";
        pub const RESET = "\x1b[0m";
    };

    const TerminalSize = struct {
        width: u16,
        height: u16,
    };
};

/// Run the authentication status display
pub fn run(allocator: std.mem.Allocator) !void {
    try display(allocator);
}

/// Display current authentication status with TUI formatting
pub fn display(allocator: std.mem.Allocator) !void {
    const terminal_size = tui.getTerminalSize();
    const width = @min(terminal_size.width, 80);

    tui.clearScreen();

    // Header
    print("{s}╔", .{tui.Color.BRIGHT_BLUE});
    var i: u16 = 0;
    while (i < width - 4) : (i += 1) {
        print("═", .{});
    }
    print("╗{s}\n", .{tui.Color.RESET});

    print("{s}║", .{tui.Color.BRIGHT_BLUE});
    const spaces = (width - 26) / 2;
    var j: u16 = 0;
    while (j < spaces) : (j += 1) {
        print(" ", .{});
    }
    print(" 🔐 Authentication Status ", .{});
    j = 0;
    while (j < spaces) : (j += 1) {
        print(" ", .{});
    }
    print("║{s}\n", .{tui.Color.RESET});

    print("{s}╚", .{tui.Color.BRIGHT_BLUE});
    i = 0;
    while (i < width - 4) : (i += 1) {
        print("═", .{});
    }
    print("╝{s}\n\n", .{tui.Color.RESET});

    // Use anthropic module directly for now to get a working implementation
    const anthropic = @import("anthropic_shared");

    // Check OAuth credentials first
    const oauth_path = "claude_oauth_creds.json";
    if (anthropic.loadOAuthCredentials(allocator, oauth_path)) |maybe_creds| {
        if (maybe_creds) |creds| {
            defer {
                allocator.free(creds.type);
                allocator.free(creds.access_token);
                allocator.free(creds.refresh_token);
            }

            const now = std.time.timestamp();
            const time_to_expire = creds.expires_at - now;

            if (creds.isExpired()) {
                print("{s}Status: OAuth Credentials EXPIRED{s}\n", .{ tui.Color.BRIGHT_RED, tui.Color.RESET });
                print("   Expired: {} seconds ago\n", .{-time_to_expire});
                print("   Action: Run 'docz auth refresh' to renew tokens\n", .{});
            } else if (creds.willExpireSoon(3600)) { // 1 hour warning
                print("{s}Status: OAuth Credentials EXPIRING SOON{s}\n", .{ tui.Color.BRIGHT_YELLOW, tui.Color.RESET });
                print("   Expires in: {} seconds\n", .{time_to_expire});
                print("   Action: Run 'docz auth refresh' to renew tokens\n", .{});
            } else {
                print("{s}Status: Using Claude Pro/Max OAuth authentication{s}\n", .{ tui.Color.BRIGHT_GREEN, tui.Color.RESET });
                print("   Expires in: {} seconds\n", .{time_to_expire});
            }

            print("   Type: Claude Pro/Max Subscription\n", .{});
            print("   Cost: Free (covered by subscription)\n", .{});
            print("   Credentials: claude_oauth_creds.json\n", .{});

            if (!creds.isExpired()) {
                print("\n{s}✅ Your authentication is working properly{s}\n", .{ tui.Color.BRIGHT_GREEN, tui.Color.RESET });
            } else {
                print("\n{s}⚠️ Your tokens need to be refreshed{s}\n", .{ tui.Color.BRIGHT_YELLOW, tui.Color.RESET });
            }
            return;
        }
    } else |_| {}

    // Check API key
    const api_key = std.posix.getenv("ANTHROPIC_API_KEY") orelse "";
    if (api_key.len > 0) {
        displayAPIKeyStatus();
    } else {
        print("{s}Status: No authentication configured{s}\n", .{ tui.Color.BRIGHT_RED, tui.Color.RESET });
        print("   Error: No authentication method available\n", .{});
        print("\n{s}Available options:{s}\n", .{ tui.Color.BRIGHT_CYAN, tui.Color.RESET });
        print("   1. Run 'docz auth login' to setup OAuth authentication\n", .{});
        print("   2. Set ANTHROPIC_API_KEY environment variable\n", .{});
        print("\n{s}❌ Authentication required to use DocZ{s}\n", .{ tui.Color.BRIGHT_RED, tui.Color.RESET });
    }

    print("\nPress any key to continue...", .{});
    const stdin = std.fs.File.stdin();
    var buffer: [1]u8 = undefined;
    _ = stdin.read(buffer[0..]) catch {};
}

/// Display OAuth authentication status
fn displayOAuthStatus(creds: anytype) void {
    const now = std.time.timestamp();
    const time_to_expire = creds.expires_at - now;

    if (creds.isExpired()) {
        print("{s}Status: OAuth Credentials EXPIRED{s}\n", .{ tui.Color.BRIGHT_RED, tui.Color.RESET });
        print("   Expired: {} seconds ago\n", .{-time_to_expire});
        print("   Action: Run 'docz auth refresh' to renew tokens\n");
    } else if (creds.willExpireSoon(3600)) { // 1 hour warning
        print("{s}Status: OAuth Credentials EXPIRING SOON{s}\n", .{ tui.Color.BRIGHT_YELLOW, tui.Color.RESET });
        print("   Expires in: {} seconds\n", .{time_to_expire});
        print("   Action: Run 'docz auth refresh' to renew tokens\n");
    } else {
        print("{s}Status: Using Claude Pro/Max OAuth authentication{s}\n", .{ tui.Color.BRIGHT_GREEN, tui.Color.RESET });
        print("   Expires in: {} seconds\n", .{time_to_expire});
    }

    print("   Type: Claude Pro/Max Subscription\n");
    print("   Cost: Free (covered by subscription)\n");
    print("   Credentials: claude_oauth_creds.json\n");

    if (!creds.isExpired()) {
        print("\n{s}✅ Your authentication is working properly{s}\n", .{ tui.Color.BRIGHT_GREEN, tui.Color.RESET });
    } else {
        print("\n{s}⚠️ Your tokens need to be refreshed{s}\n", .{ tui.Color.BRIGHT_YELLOW, tui.Color.RESET });
    }
}

/// Display API key authentication status
fn displayAPIKeyStatus() void {
    print("{s}Status: Using API key authentication{s}\n", .{ tui.Color.BRIGHT_GREEN, tui.Color.RESET });
    print("   Type: Personal API Key\n", .{});
    print("   Cost: Pay-per-use\n", .{});
    print("   Source: ANTHROPIC_API_KEY environment variable\n", .{});
    print("\n{s}✅ Your authentication is working properly{s}\n", .{ tui.Color.BRIGHT_GREEN, tui.Color.RESET });
}

/// Display no authentication available
fn displayNoAuth(err: core.AuthError) void {
    print("{s}Status: No authentication configured{s}\n", .{ tui.Color.BRIGHT_RED, tui.Color.RESET });
    print("   Error: {}\n", .{err});
    print("\n{s}Available options:{s}\n", .{ tui.Color.BRIGHT_CYAN, tui.Color.RESET });
    print("   1. Run 'docz auth login' to setup OAuth authentication\n");
    print("   2. Set ANTHROPIC_API_KEY environment variable\n");
    print("\n{s}❌ Authentication required to use DocZ{s}\n", .{ tui.Color.BRIGHT_RED, tui.Color.RESET });
}

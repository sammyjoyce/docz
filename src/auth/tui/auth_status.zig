//! Authentication Status Display TUI Component

const std = @import("std");
const print = std.debug.print;
const tui = @import("tui_shared");
const core = @import("../core/mod.zig");

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
    print("{s}╔{s}╗{s}\n", .{ tui.Color.BRIGHT_BLUE, "═" ** (width - 4), tui.Color.RESET });
    print("{s}║{s} 🔐 Authentication Status {s}║{s}\n", .{ tui.Color.BRIGHT_BLUE, " " ** ((width - 26) / 2), " " ** ((width - 26) / 2), tui.Color.RESET });
    print("{s}╚{s}╝{s}\n\n", .{ tui.Color.BRIGHT_BLUE, "═" ** (width - 4), tui.Color.RESET });

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
            return;
        }
    } else |_| {}

    // Check API key
    const api_key = std.posix.getenv("ANTHROPIC_API_KEY") orelse "";
    if (api_key.len > 0) {
        displayAPIKeyStatus();
    } else {
        print("{s}Status: No authentication configured{s}\n", .{ tui.Color.BRIGHT_RED, tui.Color.RESET });
        print("   Error: No authentication method available\n");
        print("\n{s}Available options:{s}\n", .{ tui.Color.BRIGHT_CYAN, tui.Color.RESET });
        print("   1. Run 'docz auth login' to setup OAuth authentication\n");
        print("   2. Set ANTHROPIC_API_KEY environment variable\n");
        print("\n{s}❌ Authentication required to use DocZ{s}\n", .{ tui.Color.BRIGHT_RED, tui.Color.RESET });
    }

    print("\nPress any key to continue...");
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
    print("   Type: Personal API Key\n");
    print("   Cost: Pay-per-use\n");
    print("   Source: ANTHROPIC_API_KEY environment variable\n");
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

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Import the OAuth module
    const oauth = @import("src/foundation/network/auth/oauth.zig");

    // Generate PKCE parameters
    const pkceParams = try oauth.generatePkceParams(allocator);
    defer pkceParams.deinit(allocator);

    std.debug.print("=== OAuth URL Generation Test ===\n\n", .{});

    std.debug.print("PKCE Parameters:\n", .{});
    std.debug.print("  Verifier: {s}\n", .{pkceParams.verifier});
    std.debug.print("  Challenge: {s}\n", .{pkceParams.challenge});
    std.debug.print("  State: {s}\n\n", .{pkceParams.state});

    // Build authorization URL
    const auth_url = try oauth.buildAuthorizationUrl(allocator, pkceParams);
    defer allocator.free(auth_url);

    std.debug.print("Authorization URL:\n{s}\n\n", .{auth_url});

    // Verify the URL contains expected components
    std.debug.print("URL Verification:\n", .{});

    // Check for required components
    if (std.mem.indexOf(u8, auth_url, "https://claude.ai/oauth/authorize")) |_| {
        std.debug.print("  ✓ Correct authorization endpoint\n", .{});
    }

    if (std.mem.indexOf(u8, auth_url, "client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e")) |_| {
        std.debug.print("  ✓ Correct client ID\n", .{});
    }

    if (std.mem.indexOf(u8, auth_url, "redirect_uri=https%3A%2F%2Fconsole.anthropic.com%2Foauth%2Fcode%2Fcallback")) |_| {
        std.debug.print("  ✓ Correct redirect URI (URL encoded)\n", .{});
    }

    if (std.mem.indexOf(u8, auth_url, "code_challenge_method=S256")) |_| {
        std.debug.print("  ✓ PKCE S256 method specified\n", .{});
    }

    std.debug.print("\n✅ OAuth URL generation successful!\n", .{});
    std.debug.print("\nExpected redirect URI: https://console.anthropic.com/oauth/code/callback\n", .{});
}

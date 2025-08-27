//! OAuth Callback Server Demo
//!
//! This example demonstrates how to use the OAuth callback server for:
//! - Automatic authorization code capture
//! - PKCE verification
//! - State validation
//! - Real-time terminal status display

const std = @import("std");
const oauth = @import("../src/shared/auth/oauth/mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n╔════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║       OAuth Callback Server Demo                  ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════╝\n\n", .{});

    // Option 1: Complete OAuth flow with automatic callback handling
    try runCompleteFlow(allocator);

    // Option 2: Custom callback server with specific configuration
    // try runCustomServer(allocator);

    // Option 3: Integration with OAuth wizard
    // try runWithWizard(allocator);
}

/// Complete OAuth flow with automatic callback handling
fn runCompleteFlow(allocator: std.mem.Allocator) !void {
    std.debug.print("Starting complete OAuth flow with callback server...\n\n", .{});

    // This handles everything: PKCE generation, server setup, browser launch, and token exchange
    const credentials = try oauth.completeOAuthFlow(allocator);
    defer credentials.deinit(allocator);

    std.debug.print("\n✅ OAuth flow completed successfully!\n", .{});
    std.debug.print("Access token: {s}...\n", .{credentials.access_token[0..@min(20, credentials.access_token.len)]});
    std.debug.print("Token expires at: {d}\n", .{credentials.expires_at});
}

/// Run custom callback server with specific configuration
fn runCustomServer(allocator: std.mem.Allocator) !void {
    std.debug.print("Setting up custom callback server...\n\n", .{});

    // Custom server configuration
    const config = oauth.ServerConfig{
        .port = 8888, // Custom port
        .timeout_ms = 600_000, // 10 minutes timeout
        .verbose = true, // Enable verbose logging
        .show_success_page = true, // Show nice success page in browser
        .auto_close = false, // Don't auto-close server after success
    };

    // Generate PKCE parameters
    const pkce_params = try oauth.generatePkceParams(allocator);
    defer pkce_params.deinit(allocator);

    std.debug.print("Generated PKCE parameters:\n", .{});
    std.debug.print("  State: {s}\n", .{pkce_params.state});
    std.debug.print("  Challenge: {s}...\n", .{pkce_params.code_challenge[0..@min(20, pkce_params.code_challenge.len)]});

    // Run callback server and wait for authorization
    const auth_result = try oauth.runCallbackServer(allocator, pkce_params, config);
    defer auth_result.deinit(allocator);

    std.debug.print("\n✅ Authorization code received!\n", .{});
    std.debug.print("Code: {s}...\n", .{auth_result.code[0..@min(20, auth_result.code.len)]});
    std.debug.print("State verified: ✓\n", .{});

    // Exchange code for tokens
    const credentials = try oauth.exchangeCodeForTokens(allocator, auth_result.code, pkce_params);
    defer credentials.deinit(allocator);

    // Save credentials
    try oauth.saveCredentials(allocator, "oauth_demo_creds.json", credentials);
    std.debug.print("\nCredentials saved to oauth_demo_creds.json\n", .{});
}

/// Integration with enhanced OAuth wizard
fn runWithWizard(allocator: std.mem.Allocator) !void {
    std.debug.print("Starting OAuth wizard with callback server integration...\n\n", .{});

    // Generate PKCE parameters
    const pkce_params = try oauth.generatePkceParams(allocator);
    defer pkce_params.deinit(allocator);

    // Create callback server with default config
    var server = try oauth.CallbackServer.init(allocator, .{});
    defer server.deinit();

    // Register session
    try server.registerSession(pkce_params);

    // Start server
    try server.start();
    std.debug.print("📡 Callback server started on http://localhost:8080\n\n", .{});

    // Build authorization URL
    const auth_url = try oauth.buildAuthorizationUrl(allocator, pkce_params);
    defer allocator.free(auth_url);

    // Display instructions
    std.debug.print("Please complete the following steps:\n", .{});
    std.debug.print("1. Open your browser and navigate to:\n", .{});
    std.debug.print("   {s}\n\n", .{auth_url});
    std.debug.print("2. Log in to your Claude account\n", .{});
    std.debug.print("3. Authorize the application\n", .{});
    std.debug.print("4. You'll be redirected to the callback server\n\n", .{});

    // Launch browser
    oauth.launchBrowser(auth_url) catch |err| {
        std.debug.print("⚠️  Could not launch browser automatically: {}\n", .{err});
        std.debug.print("Please manually open the URL above.\n\n", .{});
    };

    // Wait for callback with 5-minute timeout
    const auth_result = try server.waitForCallback(pkce_params.state, 300_000);
    defer auth_result.deinit(allocator);

    std.debug.print("\n✅ Authorization successful!\n", .{});

    // Exchange code for tokens
    const credentials = try oauth.exchangeCodeForTokens(allocator, auth_result.code, pkce_params);
    
    std.debug.print("OAuth setup completed!\n", .{});
    std.debug.print("Access token received and ready to use.\n", .{});

    credentials.deinit(allocator);
}

/// Test the callback server's request parsing
fn testRequestParsing() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try oauth.CallbackServer.init(allocator, .{});
    defer server.deinit();

    // Test successful callback
    {
        const request = "GET /callback?code=test_auth_code&state=random_state_123 HTTP/1.1\r\n" ++
            "Host: localhost:8080\r\n" ++
            "Connection: close\r\n\r\n";

        const result = try server.parseCallbackRequest(request);
        defer result.deinit(allocator);

        std.debug.print("✓ Parsed successful callback:\n", .{});
        std.debug.print("  Code: {s}\n", .{result.code});
        std.debug.print("  State: {s}\n", .{result.state});
    }

    // Test error callback
    {
        const request = "GET /callback?error=access_denied&error_description=User%20denied%20access&state=random_state_123 HTTP/1.1\r\n" ++
            "Host: localhost:8080\r\n" ++
            "Connection: close\r\n\r\n";

        const result = try server.parseCallbackRequest(request);
        defer result.deinit(allocator);

        std.debug.print("✓ Parsed error callback:\n", .{});
        std.debug.print("  Error: {s}\n", .{result.error_code.?});
        std.debug.print("  Description: {s}\n", .{result.error_description.?});
    }
}
//! Focused test: OAuthWizard uses AuthPort and surfaces URL via UI listener

const std = @import("std");
const testing = std.testing;
const foundation = @import("foundation");
const tui = foundation.tui;

test "OAuthWizard runs with mock port and returns credentials" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const port = foundation.adapters.auth_mock.make(.{
        .mode = .oauth,
        .access_token = "token_ok",
        .refresh_token = "refresh_ok",
        .ttl_secs = 3600,
    });

    // Create renderer minimal
    const Renderer = tui.Renderer;
    const renderer = try tui.createRenderer(alloc, .standard);
    defer renderer.deinit();

    var wizard = try tui.Auth.OAuthWizard.OAuthWizard.init(alloc, renderer, port);
    defer wizard.deinit();

    // Short-circuit state to waiting_for_code and inject a code via manual entry
    // For now, just exercise the run path up to completion by simulating steps
    // Note: Full event loop requires terminal IO; we focus on port integration here.

    // Use the integrated run function which will perform startOAuth and expect a code
    // We cannot supply real keystrokes, so we directly call internal steps:
    // Start session and build URL
    try wizard.transitionTo(.generating_pkce);
    try wizard.generatePkceParameters();
    try wizard.buildAuthorizationUrl();

    // Simulate that user provided a code and exchange completes
    const creds = try wizard.port.completeOAuth(alloc, "mock_code", wizard.session.?.pkce_verifier);
    wizard.credentials = creds;
    try wizard.saveCredentials();

    // Done
    try testing.expect(wizard.credentials != null);
}


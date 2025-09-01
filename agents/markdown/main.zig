const std = @import("std");
const engine = @import("core_engine");
const spec = @import("spec.zig");
const foundation = @import("foundation");

// Minimal CLI → engine adapter for the markdown agent.
// Keeps foundation decoupled from the engine while ensuring the agent runs.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Collect argv (skip program name)
    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);
    const args = if (argv.len > 1) argv[1..] else argv[0..0];

    // Minimal auth subcommands passthrough: `docz auth <sub>`
    if (args.len >= 1 and std.mem.eql(u8, args[0], "auth")) {
        const Auth = foundation.cli.Auth;
        const sub = if (args.len >= 2) args[1] else "status";

        if (std.mem.eql(u8, sub, "login")) {
            try Auth.login(allocator, .{});
        } else if (std.mem.eql(u8, sub, "status")) {
            try Auth.status(allocator);
        } else if (std.mem.eql(u8, sub, "whoami")) {
            try Auth.whoami(allocator);
        } else if (std.mem.eql(u8, sub, "logout")) {
            try Auth.logout(allocator);
        } else if (std.mem.eql(u8, sub, "test-call")) {
            try Auth.testCall(allocator, .{});
        } else {
            std.debug.print("Unknown auth subcommand: {s}\n", .{sub});
        }
        return;
    }

    // Special flag to trigger OAuth login for minimal agent
    if (args.len == 1 and (std.mem.eql(u8, args[0], "--oauth") or std.mem.eql(u8, args[0], "login"))) {
        try foundation.cli.Auth.login(allocator, .{});
        return;
    }
    if (args.len == 1 and (std.mem.eql(u8, args[0], "--oauth-paste") or std.mem.eql(u8, args[0], "--paste-oauth"))) {
        try foundation.cli.Auth.login(allocator, .{ .manual = true });
        return;
    }
    // Support for Anthropic-specific OAuth if needed
    if (args.len == 1 and std.mem.eql(u8, args[0], "--anthropic-oauth")) {
        const anthropic_auth = foundation.network.AnthropicAuth;
        std.log.info("Using Anthropic OAuth: client_id = {s}", .{anthropic_auth.oauthClientId});
        return;
    }

    // Build minimal engine options with sensible defaults.
    const default_model = "claude-3-5-sonnet-20241022";
    var options = engine.CliOptions{
        .model = default_model,
        .max_tokens = 4096,
        .temperature = 0.7,
        .stream = true,
        .verbose = false,
        .history = null,
        .input = null,
        .output = null,
    };

    // If user passed a prompt, join remaining args into one positional string.
    if (args.len > 0) {
        const joined = try std.mem.join(allocator, " ", args);
        defer allocator.free(joined);
        // Use input field for prompt
        options.input = try allocator.dupe(u8, joined);
    }

    // Ensure any owned option strings are released
    defer if (options.input) |p| allocator.free(p);

    // Run the engine. It will read stdin if no positional prompt is provided.
    const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);
    try engine.runWithOptions(allocator, options, spec.SPEC, cwd_path);
}

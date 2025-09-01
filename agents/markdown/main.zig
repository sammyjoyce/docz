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
        const Commands = foundation.cli.Auth.Commands;
        const sub = if (args.len >= 2) args[1] else "status";
        if (Commands.AuthCommand.fromString(sub)) |cmd| {
            try Commands.runAuthCommand(allocator, cmd);
            return;
        } else {
            std.debug.print("Unknown auth subcommand: {s}\n", .{sub});
            return;
        }
    }

    // Special flag to trigger OAuth login for minimal agent
    if (args.len == 1 and (std.mem.eql(u8, args[0], "--oauth") or std.mem.eql(u8, args[0], "auth") or std.mem.eql(u8, args[0], "login"))) {
        try foundation.cli.Auth.handleLoginCommand(allocator);
        return;
    }
    if (args.len == 1 and (std.mem.eql(u8, args[0], "--oauth-paste") or std.mem.eql(u8, args[0], "--paste-oauth"))) {
        const oauth = foundation.network.Auth.OAuth;
        const creds = try oauth.setupOAuth(allocator);
        creds.deinit(allocator);
        return;
    }
    // Support for Anthropic-specific OAuth if needed
    if (args.len == 1 and std.mem.eql(u8, args[0], "--anthropic-oauth")) {
        const anthropic_auth = foundation.network.AnthropicAuth;
        std.log.info("Using Anthropic OAuth: client_id = {s}", .{anthropic_auth.oauthClientId});
        return;
    }

    // Build minimal engine options with sensible defaults.
    // Use a model from the Anthropic Models list
    const default_model = "claude-sonnet-4-0"; // From foundation.network.AnthropicAuth model pricing table
    var options = engine.CliOptions{
        .options = .{
            .model = default_model,
            .output = null,
            .input = null,
            .system = null,
            .config = null,
            .tokensMax = 1024,
            .temperature = 0.7,
        },
        .flags = .{
            .verbose = false,
            .help = false,
            .version = false,
            .stream = true,
            .pretty = false,
            .debug = false,
            .interactive = false,
        },
        .positionals = null,
    };

    // If user passed a prompt, join remaining args into one positional string.
    if (args.len > 0) {
        const joined = try std.mem.join(allocator, " ", args);
        defer allocator.free(joined);
        // Duplicate to give ownership to engine
        options.positionals = try allocator.dupe(u8, joined);
    }

    // Ensure any owned option strings are released
    defer if (options.positionals) |p| allocator.free(p);

    // Run the engine. It will read stdin if no positional prompt is provided.
    try engine.runWithOptions(allocator, options, spec.SPEC, std.fs.cwd());
}

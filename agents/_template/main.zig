//! Example agent entry point. Copy to agents/<name>/main.zig and adjust.
const std = @import("std");
const engine = @import("core_engine");
const cli = @import("cli_shared");
const spec = @import("spec.zig");

const CliOptions = engine.CliOptions;

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    const gpa = gpa_state.allocator();
    defer _ = gpa_state.deinit();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);
    const cli_args = if (args.len > 1) args[1..] else args[0..0];

    var parsed = cli.parseArgs(gpa, cli_args) catch |err| {
        cli.printError(gpa, err, null) catch {};
        std.process.exit(1);
    };
    defer parsed.deinit();

    if (cli.shouldShowHelp(&parsed)) return cli.printHelp(gpa) catch {};
    if (cli.shouldShowVersion(&parsed)) return cli.printVersion(gpa) catch {};

    switch (parsed.positionals.command) {
        .auth => |auth_cmd| switch (auth_cmd) {
            .login => return engine.setupOAuth(gpa),
            .status => return engine.showAuthStatus(gpa),
            .refresh => return engine.refreshAuth(gpa),
        },
        .chat => {},
    }

    const options = CliOptions{
        .options = .{
            .model = parsed.options.model orelse "claude-3-sonnet-20240229",
            .output = parsed.options.output,
            .input = parsed.options.input,
            .system = parsed.options.system,
            .config = parsed.options.config,
            .max_tokens = parsed.options.max_tokens orelse 4096,
            .temperature = parsed.options.temperature orelse 0.7,
        },
        .flags = .{
            .verbose = parsed.flags.verbose,
            .help = parsed.flags.help,
            .version = parsed.flags.version,
            .stream = parsed.flags.stream,
            .pretty = parsed.flags.pretty,
            .debug = parsed.flags.debug,
            .interactive = parsed.flags.interactive,
        },
        .positionals = parsed.positionals.prompt,
    };

    try engine.runWithOptions(gpa, options, spec.SPEC);
}


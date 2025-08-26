//! Markdown agent entry point. Parses CLI and delegates to core engine with the Markdown spec.

const std = @import("std");
const engine = @import("core_engine");
const cli = @import("cli_shared");
const spec = @import("spec.zig");

const CliOptions = engine.CliOptions;

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    const gpa = gpa_state.allocator();
    defer if (gpa_state.deinit() == .leak) {
        @panic("Memory leak detected");
    };

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const cli_args = if (args.len > 1) args[1..] else args[0..0];

    var parsed_args = cli.parseArgs(gpa, cli_args) catch |err| {
        cli.printError(gpa, err, null) catch {};
        std.process.exit(1);
    };
    defer parsed_args.deinit();

    if (cli.shouldShowHelp(&parsed_args)) {
        cli.printHelp(gpa) catch {};
        return;
    }

    if (cli.shouldShowVersion(&parsed_args)) {
        cli.printVersion(gpa) catch {};
        return;
    }

    switch (parsed_args.positionals.command) {
        .auth => |auth_cmd| {
            switch (auth_cmd) {
                .login => {
                    try engine.setupOAuth(gpa);
                    return;
                },
                .status => {
                    try engine.showAuthStatus(gpa);
                    return;
                },
                .refresh => {
                    try engine.refreshAuth(gpa);
                    return;
                },
            }
        },
        .chat => {},
    }

    const options = CliOptions{
        .options = .{
            .model = parsed_args.options.model orelse "claude-3-sonnet-20240229",
            .output = parsed_args.options.output,
            .input = parsed_args.options.input,
            .system = parsed_args.options.system,
            .config = parsed_args.options.config,
            .max_tokens = parsed_args.options.max_tokens orelse 4096,
            .temperature = parsed_args.options.temperature orelse 0.7,
        },
        .flags = .{
            .verbose = parsed_args.flags.verbose,
            .help = parsed_args.flags.help,
            .version = parsed_args.flags.version,
            .stream = parsed_args.flags.stream,
            .pretty = parsed_args.flags.pretty,
            .debug = parsed_args.flags.debug,
            .interactive = parsed_args.flags.interactive,
        },
        .positionals = parsed_args.positionals.prompt,
    };

    try engine.runWithOptions(gpa, options, spec.SPEC);
}

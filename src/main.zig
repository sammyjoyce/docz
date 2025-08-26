//! Root entry that initialises allocator then launches agent loop.
const std = @import("std");
const cli = @import("cli.zig");
const agent = @import("agent.zig");

const CliOptions = agent.CliOptions;

pub fn main() !void {
    // Debug allocator to catch leaks in dev builds
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    const gpa = gpa_state.allocator();
    defer if (gpa_state.deinit() == .leak) {
        @panic("Memory leak detected");
    };

    // Parse command line arguments
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    // Skip program name for parsing
    const cli_args = if (args.len > 1) args[1..] else args[0..0];

    var parsed_args = cli.parseArgs(gpa, cli_args) catch |err| {
        cli.printError(err);
        std.process.exit(1);
    };
    defer parsed_args.deinit();

    // Handle help flag
    if (cli.shouldShowHelp(&parsed_args)) {
        cli.printHelp();
        return;
    }

    // Handle version flag
    if (cli.shouldShowVersion(&parsed_args)) {
        cli.printVersion();
        return;
    }

    // Handle OAuth setup command
    if (parsed_args.flags.oauth) {
        try agent.setupOAuth(gpa);
        return;
    }

    // Convert parsed CLI arguments to agent CliOptions
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
            .oauth = parsed_args.flags.oauth,
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

    // Run agent loop (blocking) with parsed options
    try agent.runWithOptions(gpa, options);
}

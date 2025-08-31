const std = @import("std");
const engine = @import("core_engine");
const spec = @import("spec.zig");

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

    // Build minimal engine options with sensible defaults.
    var options = engine.CliOptions{
        .options = .{
            .model = "claude-3-haiku-20240307",
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

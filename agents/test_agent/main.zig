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

    const commandLineArgs = if (args.len > 1) args[1..] else args[0..0];

    // Convert [][:0]u8 to [][]const u8
    const cliArgsConst = try gpa.alloc([]const u8, commandLineArgs.len);
    defer gpa.free(cliArgsConst);
    for (commandLineArgs, 0..) |arg, i| {
        cliArgsConst[i] = std.mem.sliceTo(arg, 0);
    }

    // Use the new CLI API that handles built-in commands internally
    const parsedArgs = try cli.parseAndHandle(gpa, cliArgsConst);

    // If parseAndHandle returns null, a built-in command was handled
    if (parsedArgs == null) {
        return;
    }

    // Otherwise we have parsed args to process
    var argsToProcess = parsedArgs.?;
    defer argsToProcess.deinit();

    // Handle auth commands (these are handled by parseAndHandle, but we keep this for completeness)
    if (argsToProcess.command) |command| {
        switch (command) {
            .auth => {
                if (argsToProcess.auth_subcommand) |subcommand| {
                    switch (subcommand) {
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
                }
            },
            else => {},
        }
    }

    const options = CliOptions{
        .options = .{
            .model = argsToProcess.model,
            .output = null, // Not supported in new parser
            .input = null, // Not supported in new parser
            .system = null, // Not supported in new parser
            .config = null, // Not supported in new parser
            .maxTokens = argsToProcess.max_tokens orelse 4096,
            .temperature = argsToProcess.temperature orelse 0.7,
        },
        .flags = .{
            .verbose = argsToProcess.verbose,
            .help = argsToProcess.help,
            .version = argsToProcess.version,
            .stream = argsToProcess.stream,
            .pretty = false, // Not supported in new parser
            .debug = false, // Not supported in new parser
            .interactive = false, // Not supported in new parser
        },
        .positionals = argsToProcess.prompt,
    };

    try engine.runWithOptions(gpa, options, spec.SPEC);
}

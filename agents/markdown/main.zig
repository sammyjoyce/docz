const std = @import("std");
const foundation = @import("foundation");
const engine = @import("core_engine");
const spec = @import("spec.zig");
const tui_app = @import("tui.zig");
const cli_app = @import("cli.zig");

/// Markdown agent entrypoint - PRODUCTION-READY implementation.
/// DEFAULT BEHAVIOR: Launch the full TUI when no arguments are provided.
/// CLI COMMANDS: Available when specific commands are provided (edit/preview/...).
/// FOUNDATION INTEGRATION: Uses shared agent runner for auth/chat and OAuth flows.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var argv = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, argv);
    const args = if (argv.len > 1) argv[1..] else argv[0..0];

    // DEFAULT: no args -> launch the Markdown TUI
    if (args.len == 0) {
        const rc = try tui_app.runTui(alloc, .{}, null);
        if (rc != 0) std.process.exit(@intCast(rc));
        return;
    }

    // Global help/version flags for the markdown CLI
    if (std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h")) {
        var app = try cli_app.MarkdownCLI.init(alloc);
        defer app.deinit();
        const code = try app.run(&[_][]const u8{"help"});
        if (code != 0) std.process.exit(@intCast(code));
        return;
    }
    if (std.mem.eql(u8, args[0], "--version") or std.mem.eql(u8, args[0], "-V")) {
        var out = std.fs.File.stdout().deprecatedWriter();
        try out.writeAll("markdown 2.0.0\n");
        return;
    }

    // Fast-path: allow explicit --tui anywhere to launch the TUI immediately
    for (args) |a| {
        if (std.mem.eql(u8, a, "--tui") or std.mem.eql(u8, a, "-t")) {
            // If in edit subcommand, pass file if provided
            var initial: ?[]const u8 = null;
            if (args.len >= 2 and std.mem.eql(u8, args[0], "edit")) {
                // Find first non-flag positional after "edit"
                var j: usize = 1;
                while (j < args.len) : (j += 1) {
                    if (args[j].len > 0 and args[j][0] != '-') {
                        initial = args[j];
                        break;
                    }
                }
            }
            const rc = try tui_app.runTui(alloc, .{}, initial);
            if (rc != 0) std.process.exit(@intCast(rc));
            return;
        }
    }
    const markdown_commands = [_][]const u8{
        "edit",   "preview", "validate", "convert", "serve", "stats",
        "format", "toc",     "link",     "help",    "chat",
    };

    // Check if it's a markdown command
    inline for (markdown_commands) |cmd| {
        if (std.mem.eql(u8, args[0], cmd)) {
            var app = try cli_app.MarkdownCLI.init(alloc);
            defer app.deinit();
            const code = try app.run(args);
            if (code != 0) std.process.exit(@intCast(code));
            return;
        }
    }

    // Foundation commands (auth, run, etc.) - delegate to agent_main
    try foundation.agent_main.runAgent(alloc, spec.SPEC);
}

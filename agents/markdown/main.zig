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

    // Check for --tui flag first (before other argument processing)
    const force_tui = for (args) |arg| {
        if (std.mem.eql(u8, arg, "--tui") or std.mem.eql(u8, arg, "-t")) break true;
    } else false;

    // DEFAULT: no args OR --tui flag -> check if stdin has data
    if (args.len == 0 or force_tui) {
        // Check if stdin is being piped to us
        const stdin = std.fs.File.stdin();
        const stat = stdin.stat() catch {
            // Can't stat stdin, assume interactive - launch TUI
            const rc = try tui_app.runTui(alloc, .{}, null);
            if (rc != 0) std.process.exit(@intCast(rc));
            return;
        };

        // If stdin is a pipe/file, read from it and process with CLI
        if (stat.kind != .character_device) {
            // Read all stdin content
            const content = stdin.readToEndAlloc(alloc, 1024 * 1024) catch {
                // Handle read errors by launching TUI instead
                const rc = try tui_app.runTui(alloc, .{}, null);
                if (rc != 0) std.process.exit(@intCast(rc));
                return;
            };
            defer alloc.free(content);

            if (content.len > 0) {
                if (force_tui) {
                    // --tui flag with piped content: launch TUI with the content pre-loaded
                    const rc = try tui_app.runTuiWithContent(alloc, .{}, content);
                    if (rc != 0) std.process.exit(@intCast(rc));
                    return;
                }
            }
        }

        // No piped content - launch TUI
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

    // Skip --tui handling here since we handle it at the top
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
    try foundation.agent_main.runAgent(engine, alloc, spec.SPEC);
}

const std = @import("std");
const engine = @import("core_engine");
const cli = @import("cli_shared");
const spec = @import("spec.zig");
const interactive_markdown = @import("interactive_markdown.zig");

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

    // Convert [][:0]u8 to [][]const u8
    const cli_args_const = try gpa.alloc([]const u8, cli_args.len);
    defer gpa.free(cli_args_const);
    for (cli_args, 0..) |arg, i| {
        cli_args_const[i] = std.mem.sliceTo(arg, 0);
    }

    // Use the new CLI API that handles built-in commands internally
    const parsed_args = try cli.parseAndHandle(gpa, cli_args_const);

    // If parseAndHandle returns null, a built-in command was handled
    if (parsed_args == null) {
        return;
    }

    // Otherwise we have parsed args to process
    var args_to_process = parsed_args.?;
    defer args_to_process.deinit();

    // Handle preview mode
    if (args_to_process.preview) {
        const config = interactive_markdown.EditorConfig{
            .split_position = 0.5,
            .show_line_numbers = true,
            .syntax_highlight = true,
            .auto_save_interval = 30,
            .word_wrap = true,
            .max_preview_width = 80,
            .enable_mouse = true,
            .enable_hyperlinks = true,
            .theme = "default",
        };

        // Get file path from positional arguments if provided
        const file_path = if (args_to_process.prompt) |prompt| blk: {
            // If prompt looks like a file path, use it
            if (!std.mem.containsAtLeast(u8, prompt, 1, " ") and
                (std.mem.endsWith(u8, prompt, ".md") or std.mem.endsWith(u8, prompt, ".markdown")))
            {
                break :blk prompt;
            }
            break :blk null;
        } else null;

        try interactive_markdown.launchInteractiveEditor(gpa, file_path, config);
        return;
    }

    // Handle auth commands (these are handled by parseAndHandle, but we keep this for completeness)
    if (args_to_process.command) |cmd| {
        switch (cmd) {
            .auth => {
                if (args_to_process.auth_subcommand) |sub| {
                    switch (sub) {
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
            .model = args_to_process.model,
            .output = null, // Not supported in new parser
            .input = null, // Not supported in new parser
            .system = null, // Not supported in new parser
            .config = null, // Not supported in new parser
            .maxTokens = args_to_process.max_tokens orelse 4096,
            .temperature = args_to_process.temperature orelse 0.7,
        },
        .flags = .{
            .verbose = args_to_process.verbose,
            .help = args_to_process.help,
            .version = args_to_process.version,
            .stream = args_to_process.stream,
            .pretty = false, // Not supported in new parser
            .debug = false, // Not supported in new parser
            .interactive = false, // Not supported in new parser
        },
        .positionals = args_to_process.prompt,
    };

    try engine.runWithOptions(gpa, options, spec.SPEC);
}

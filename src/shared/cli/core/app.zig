//! CLI Application
//! Main application that coordinates all CLI functionality

const std = @import("std");
const state = @import("state.zig");
const types = @import("types.zig");
const router = @import("Router.zig");

pub const CliApp = struct {
    allocator: std.mem.Allocator,
    state: state.Cli,
    router: router.CommandRouter,

    pub fn init(allocator: std.mem.Allocator) !CliApp {
        // Initialize context with terminal capabilities
        var ctx = try state.Cli.init(allocator);

        // Initialize command router
        const commandRouter = try router.CommandRouter.init(allocator, &ctx);

        return CliApp{
            .allocator = allocator,
            .state = ctx,
            .router = commandRouter,
        };
    }

    pub fn deinit(self: *CliApp) void {
        self.router.deinit();
        self.state.deinit();
    }

    /// Main entry point for CLI execution
    pub fn run(self: *CliApp, args: []const []const u8) !u8 {
        // Parse arguments via parser
        const parsedArgs = try self.parseArguments(args);

        // Handle built-in commands
        if (parsedArgs.help) {
            try self.showHelp();
            return 0;
        }

        if (parsedArgs.version) {
            try self.showVersion();
            return 0;
        }

        if (parsedArgs.verbose) {
            self.state.enableVerbose();
        }

        // Show capability info in verbose mode
        if (self.state.verbose) {
            self.state.verboseLog("Terminal capabilities: {s}", .{self.state.capabilitySummary()});
        }

        // Execute command through router
        const result = try self.router.execute(parsedArgs);

        // Handle result
        if (result.success) {
            if (result.output) |output| {
                try self.state.terminal.printf("{s}", .{output}, null);
            }
            return result.exit_code;
        } else {
            if (result.errorMessage) |msg| {
                try self.state.terminal.printf("{s}\n", .{msg}, .{ .fg_color = .{ .rgb = .{ .r = 220, .g = 20, .b = 60 } } });
            }
            return result.exit_code;
        }
    }

    fn parseArguments(self: *CliApp, args: []const []const u8) !types.Args {
        const legacy_parser = @import("legacy_parser.zig");
        // The parser expects argv-style input including program name at index 0.
        var argv = try self.allocator.alloc([]const u8, args.len + 1);
        defer self.allocator.free(argv);
        argv[0] = "docz"; // synthetic argv[0]
        for (args, 0..) |a, i| argv[i + 1] = a;

        var parser = legacy_parser.Parser.init(self.allocator);
        var parsed = try parser.parse(argv);
        defer parsed.deinit();

        var cliArgs = types.Args.fromConfig(self.state.config, self.allocator);

        // Map parsed -> cliArgs
        cliArgs.stream = parsed.stream;
        cliArgs.verbose = parsed.verbose;
        cliArgs.help = parsed.help;
        cliArgs.version = parsed.version;
        cliArgs.color = !parsed.no_color;

        // Command mapping
        if (parsed.command) |cmd| {
            cliArgs.command = cmd; // matches types.Command
        } else {
            cliArgs.command = .chat;
        }
        cliArgs.authSubcommand = parsed.authSubcommand;

        // Positional prompt as raw message (dupe for lifetime)
        if (parsed.prompt) |p| {
            cliArgs.rawMessage = try self.allocator.dupe(u8, p);
        }

        return cliArgs;
    }

    fn showHelp(self: *CliApp) !void {
        var stdoutBuffer: [4096]u8 = undefined;
        var stdoutWriter = std.fs.File.stdout().writer(&stdoutBuffer);
        const writer = &stdoutWriter.interface;

        const helpText =
            \\docz - AI-powered document assistant
            \\
            \\Usage: docz [COMMAND] [OPTIONS] [MESSAGE]
            \\
            \\Commands:
            \\  chat           Start a chat session (default)
            \\  auth           Authentication management
            \\  interactive    Interactive mode with features
            \\  help           Show this help message
            \\  version        Show version information
            \\
            \\Options:
            \\  -h, --help        Show help
            \\  -v, --version     Show version
            \\  --verbose         Enable verbose output
            \\  -i, --interactive Enable interactive mode
            \\  --stream          Stream responses
            \\  --no-hyperlinks   Disable hyperlinks
            \\  --no-clipboard    Disable clipboard integration
            \\  --format FORMAT   Output format (minimal|rich|json|markdown)
            \\
            \\Terminal Features:
        ;

        try writer.writeAll(helpText);

        // Show available terminal features
        if (self.state.hasFeature(.hyperlinks)) {
            try writer.writeAll("  ✓ Hyperlinks supported\n");
        }
        if (self.state.hasFeature(.clipboard)) {
            try writer.writeAll("  ✓ Clipboard integration\n");
        }
        if (self.state.hasFeature(.notifications)) {
            try writer.writeAll("  ✓ System notifications\n");
        }
        if (self.state.hasFeature(.graphics)) {
            try writer.writeAll("  ✓ Graphics\n");
        }

        try writer.writeAll("\n");
        try writer.flush();
    }

    fn showVersion(self: *CliApp) !void {
        _ = self;
        var stdoutBuffer: [4096]u8 = undefined;
        var stdoutWriter = std.fs.File.stdout().writer(&stdoutBuffer);
        const writer = &stdoutWriter.interface;
        const versionText = "docz 1.0.0\n";
        try writer.writeAll(versionText);
        try writer.flush();
    }
};

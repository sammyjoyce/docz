//! CLI Application
//! Main application that coordinates all CLI functionality

const std = @import("std");
const state = @import("state.zig");
const types = @import("types.zig");
const router = @import("router.zig");

pub const CliError = error{
    ParseFailed,
    InvalidCommand,
    Io,
    Rendering,
    Unknown,
};

pub const CliApp = struct {
    allocator: std.mem.Allocator,
    state: state.Cli,
    router: router.CommandRouter,

    pub fn init(allocator: std.mem.Allocator) CliError!CliApp {
        // Initialize context with terminal capabilities
        var ctx = state.Cli.init(allocator) catch |err| switch (err) {
            else => return CliError.Io,
        };

        // Initialize command router
        const commandRouter = router.CommandRouter.init(allocator, &ctx) catch |err| switch (err) {
            else => return CliError.Unknown,
        };

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
    pub fn run(self: *CliApp, args: []const []const u8) CliError!u8 {
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
        const result = self.router.execute(parsedArgs) catch |err| switch (err) {
            types.CliError.UnknownCommand, types.CliError.UnknownSubcommand => return CliError.InvalidCommand,
            else => return CliError.Unknown,
        };

        // Handle result
        if (result.success) {
            if (result.output) |output| {
                self.state.terminal.printf("{s}", .{output}, null) catch |err| switch (err) {
                    else => return CliError.Rendering,
                };
            }
            return result.exit_code;
        } else {
            if (result.errorMessage) |msg| {
                self.state.terminal.printf("{s}\n", .{msg}, .{ .fg_color = .{ .rgb = .{ .r = 220, .g = 20, .b = 60 } } }) catch |err| switch (err) {
                    else => return CliError.Rendering,
                };
            }
            return result.exit_code;
        }
    }

    fn parseArguments(self: *CliApp, args: []const []const u8) CliError!types.Args {
        const build_options = @import("build_options");
        const ParserMod = comptime if (build_options.include_legacy)
            @import("../legacy/Parser.zig")
        else
            @import("parser.zig");
        const ParserError = ParserMod.CliError;

        // The parser expects argv-style input including program name at index 0.
        var argv = self.allocator.alloc([]const u8, args.len + 1) catch |err| switch (err) {
            else => return CliError.Unknown,
        };
        defer self.allocator.free(argv);
        argv[0] = "docz"; // synthetic argv[0]
        for (args, 0..) |a, i| argv[i + 1] = a;

        var parser = ParserMod.Parser.init(self.allocator);
        var parsed = parser.parse(argv) catch |err| switch (err) {
            ParserError.UnknownCommand, ParserError.UnknownSubcommand => return CliError.InvalidCommand,
            else => return CliError.ParseFailed,
        };
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
            cliArgs.rawMessage = self.allocator.dupe(u8, p) catch |err| switch (err) {
                else => return CliError.Unknown,
            };
        }

        return cliArgs;
    }

    fn showHelp(self: *CliApp) CliError!void {
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

        writer.writeAll(helpText) catch |err| switch (err) {
            else => return CliError.Io,
        };

        // Show available terminal features
        if (self.state.hasFeature(.hyperlinks)) {
            writer.writeAll("  ✓ Hyperlinks supported\n") catch |err| switch (err) {
                else => return CliError.Io,
            };
        }
        if (self.state.hasFeature(.clipboard)) {
            writer.writeAll("  ✓ Clipboard integration\n") catch |err| switch (err) {
                else => return CliError.Io,
            };
        }
        if (self.state.hasFeature(.notifications)) {
            writer.writeAll("  ✓ System notifications\n") catch |err| switch (err) {
                else => return CliError.Io,
            };
        }
        if (self.state.hasFeature(.graphics)) {
            writer.writeAll("  ✓ Graphics\n") catch |err| switch (err) {
                else => return CliError.Io,
            };
        }

        writer.writeAll("\n") catch |err| switch (err) {
            else => return CliError.Io,
        };
        writer.flush() catch |err| switch (err) {
            else => return CliError.Io,
        };
    }

    fn showVersion(self: *CliApp) CliError!void {
        _ = self;
        var stdoutBuffer: [4096]u8 = undefined;
        var stdoutWriter = std.fs.File.stdout().writer(&stdoutBuffer);
        const writer = &stdoutWriter.interface;
        const versionText = "docz 1.0.0\n";
        writer.writeAll(versionText) catch |err| switch (err) {
            else => return CliError.Io,
        };
        writer.flush() catch |err| switch (err) {
            else => return CliError.Io,
        };
    }
};

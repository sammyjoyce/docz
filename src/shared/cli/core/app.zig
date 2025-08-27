//! Unified CLI Application
//! Main application that coordinates all CLI functionality

const std = @import("std");
const context = @import("context.zig");
const types = @import("types.zig");
const router = @import("router.zig");

pub const CliApp = struct {
    allocator: std.mem.Allocator,
    context: context.Cli,

    pub fn init(allocator: std.mem.Allocator) !CliApp {
        // Initialize context with terminal capabilities
        var ctx = try context.Cli.init(allocator);

        // Initialize command router
        const commandRouter = try router.CommandRouter.init(allocator, &ctx);

        return CliApp{
            .allocator = allocator,
            .context = ctx,
            .router = commandRouter,
        };
    }

    pub fn deinit(self: *CliApp) void {
        self.router.deinit();
        self.context.deinit();
    }

    /// Main entry point for CLI execution
    pub fn run(self: *CliApp, args: []const []const u8) !u8 {
        // Parse arguments (unified via enhanced parser)
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
            self.context.enableVerbose();
        }

        // Show capability info in verbose mode
        if (self.context.verbose) {
            self.context.verboseLog("Terminal capabilities: {s}", .{self.context.capabilitySummary()});
        }

        // Execute command through router
        const result = try self.router.execute(parsedArgs);

        // Handle result
        if (result.success) {
            if (result.output) |output| {
                var stdoutBuffer: [4096]u8 = undefined;
                var stdoutWriter = std.fs.File.stdout().writer(&stdoutBuffer);
                const writer = &stdoutWriter.interface;
                try writer.writeAll(output);
                try writer.flush();
            }
            return result.exit_code;
        } else {
            if (result.errorMessage) |msg| {
                var stderrBuffer: [4096]u8 = undefined;
                var stderrWriter = std.fs.File.stderr().writer(&stderrBuffer);
                const writer = &stderrWriter.interface;
                try writer.writeAll(msg);
                try writer.writeAll("\n");
                try writer.flush();
            }
            return result.exit_code;
        }
    }

    fn parseArguments(self: *CliApp, args: []const []const u8) !types.ParsedArgsUnified {
        const legacy_parser = @import("legacy_parser.zig");
        // The enhanced parser expects argv-style input including program name at index 0.
        var argv = try self.allocator.alloc([]const u8, args.len + 1);
        defer self.allocator.free(argv);
        argv[0] = "docz"; // synthetic argv[0]
        for (args, 0..) |a, i| argv[i + 1] = a;

        var parser = legacy_parser.EnhancedParser.init(self.allocator);
        var parsed = try parser.parse(argv);
        defer parsed.deinit();

        var unified = types.ParsedArgsUnified.fromConfig(self.context.config, self.allocator);

        // Map enhanced -> unified
        unified.stream = parsed.stream;
        unified.verbose = parsed.verbose;
        unified.help = parsed.help;
        unified.version = parsed.version;
        unified.color = !parsed.no_color;

        // Command mapping
        if (parsed.command) |cmd| {
            unified.command = cmd; // matches types.UnifiedCommand
        } else {
            unified.command = .chat;
        }
        unified.authSubcommand = parsed.authSubcommand;

        // Positional prompt as raw message (dupe for lifetime)
        if (parsed.prompt) |p| {
            unified.rawMessage = try self.allocator.dupe(u8, p);
        }

        return unified;
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
            \\  interactive    Interactive mode with enhanced features
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
            \\  --format FORMAT   Output format (simple|enhanced|json|markdown)
            \\
            \\Terminal Features:
        ;

        try writer.writeAll(helpText);

        // Show available terminal features
        if (self.context.hasFeature(.hyperlinks)) {
            try writer.writeAll("  ✓ Hyperlinks supported\n");
        }
        if (self.context.hasFeature(.clipboard)) {
            try writer.writeAll("  ✓ Clipboard integration\n");
        }
        if (self.context.hasFeature(.notifications)) {
            try writer.writeAll("  ✓ System notifications\n");
        }
        if (self.context.hasFeature(.graphics)) {
            try writer.writeAll("  ✓ Enhanced graphics\n");
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

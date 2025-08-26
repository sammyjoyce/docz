//! Pure Zig CLI parser using comptime reflection from cli.zon configuration

const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const cli_config = @import("cli.zon");

pub const CliError = error{
    UnknownOption,
    MissingValue,
    InvalidValue,
    MutuallyExclusiveOptions,
    OutOfMemory,
    InvalidArgument,
};

// Manually define the parsed structures based on cli.zon
pub const ParsedOptions = struct {
    model: ?[]const u8 = null,
    output: ?[]const u8 = null,
    input: ?[]const u8 = null,
    system: ?[]const u8 = null,
    config: ?[]const u8 = null,
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
};

pub const ParsedFlags = struct {
    oauth: bool = false,
    verbose: bool = false,
    help_me: bool = false,
    version: bool = false,
    stream: bool = false,
    disable_stream: bool = false,
    pretty: bool = false,
    debug: bool = false,
    interactive: bool = false,
};

pub const ParsedPositionals = struct {
    prompt: ?[]const u8 = null,
};

pub const ParsedArgs = struct {
    options: ParsedOptions,
    flags: ParsedFlags,
    positionals: ParsedPositionals,
    allocator: Allocator,

    pub fn deinit(self: *ParsedArgs) void {
        // Clean up allocated strings
        if (self.options.model) |str| self.allocator.free(str);
        if (self.options.output) |str| self.allocator.free(str);
        if (self.options.input) |str| self.allocator.free(str);
        if (self.options.system) |str| self.allocator.free(str);
        if (self.options.config) |str| self.allocator.free(str);
        if (self.positionals.prompt) |prompt| self.allocator.free(prompt);
    }
};

pub fn parseArgs(allocator: Allocator, args: []const []const u8) !ParsedArgs {
    var result = ParsedArgs{
        .options = ParsedOptions{},
        .flags = ParsedFlags{},
        .positionals = ParsedPositionals{},
        .allocator = allocator,
    };

    // Set default values from cli.zon
    result.options.model = try allocator.dupe(u8, "claude-3-sonnet-20240229");
    result.options.max_tokens = 4096;
    result.options.temperature = 0.7;
    result.flags.stream = true;

    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "--")) {
            const name = arg[2..];

            if (std.mem.eql(u8, name, "model")) {
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                if (result.options.model) |old| allocator.free(old);
                result.options.model = try allocator.dupe(u8, args[i]);
            } else if (std.mem.eql(u8, name, "output")) {
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                result.options.output = try allocator.dupe(u8, args[i]);
            } else if (std.mem.eql(u8, name, "input")) {
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                result.options.input = try allocator.dupe(u8, args[i]);
            } else if (std.mem.eql(u8, name, "system")) {
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                result.options.system = try allocator.dupe(u8, args[i]);
            } else if (std.mem.eql(u8, name, "config")) {
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                result.options.config = try allocator.dupe(u8, args[i]);
            } else if (std.mem.eql(u8, name, "max-tokens")) {
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                result.options.max_tokens = std.fmt.parseInt(u32, args[i], 10) catch {
                    return CliError.InvalidValue;
                };
            } else if (std.mem.eql(u8, name, "temperature")) {
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                result.options.temperature = std.fmt.parseFloat(f32, args[i]) catch {
                    return CliError.InvalidValue;
                };
            } else if (std.mem.eql(u8, name, "oauth")) {
                result.flags.oauth = true;
            } else if (std.mem.eql(u8, name, "verbose")) {
                result.flags.verbose = true;
            } else if (std.mem.eql(u8, name, "help-me")) {
                result.flags.help_me = true;
            } else if (std.mem.eql(u8, name, "version")) {
                result.flags.version = true;
            } else if (std.mem.eql(u8, name, "stream")) {
                result.flags.stream = true;
            } else if (std.mem.eql(u8, name, "disable-stream")) {
                result.flags.disable_stream = true;
                result.flags.stream = false;
            } else if (std.mem.eql(u8, name, "pretty")) {
                result.flags.pretty = true;
            } else if (std.mem.eql(u8, name, "debug")) {
                result.flags.debug = true;
            } else if (std.mem.eql(u8, name, "interactive")) {
                result.flags.interactive = true;
            } else {
                return CliError.UnknownOption;
            }
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len == 2) {
            const short_char = arg[1];

            if (short_char == 'm') {
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                if (result.options.model) |old| allocator.free(old);
                result.options.model = try allocator.dupe(u8, args[i]);
            } else if (short_char == 'o') {
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                result.options.output = try allocator.dupe(u8, args[i]);
            } else if (short_char == 'i') {
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                result.options.input = try allocator.dupe(u8, args[i]);
            } else if (short_char == 's') {
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                result.options.system = try allocator.dupe(u8, args[i]);
            } else if (short_char == 'c') {
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                result.options.config = try allocator.dupe(u8, args[i]);
            } else if (short_char == 'v') {
                result.flags.verbose = true;
            } else {
                return CliError.UnknownOption;
            }
        } else {
            // Positional argument
            if (result.positionals.prompt == null) {
                result.positionals.prompt = try allocator.dupe(u8, arg);
            }
        }

        i += 1;
    }

    // Check for mutually exclusive options
    if (result.flags.stream and result.flags.disable_stream) {
        return CliError.MutuallyExclusiveOptions;
    }

    return result;
}

pub fn printHelp() void {
    print("{s} - {s}\n\n", .{ cli_config.name, cli_config.description });

    print("USAGE:\n", .{});
    print("    {s} [OPTIONS] [FLAGS] [PROMPT]\n\n", .{cli_config.name});

    print("OPTIONS:\n", .{});
    print("    -m, --model <string>        Anthropic model to use [default: claude-3-sonnet-20240229]\n", .{});
    print("    -o, --output <string>       Output file path (defaults to stdout)\n", .{});
    print("    -i, --input <string>        Input file path (defaults to stdin)\n", .{});
    print("    -s, --system <string>       Custom system prompt override\n", .{});
    print("    -c, --config <string>       Path to configuration file\n", .{});
    print("        --max-tokens <u32>      Maximum tokens for response [default: 4096]\n", .{});
    print("        --temperature <f32>     Temperature setting (0.0-1.0) [default: 0.7]\n\n", .{});

    print("FLAGS:\n", .{});
    print("        --oauth                 Setup OAuth authentication flow\n", .{});
    print("    -v, --verbose              Enable verbose logging output\n", .{});
    print("        --help-me              Show help message and usage information\n", .{});
    print("        --version              Show version information\n", .{});
    print("        --stream               Enable streaming output (default)\n", .{});
    print("        --disable-stream       Disable streaming, wait for complete response\n", .{});
    print("        --pretty               Pretty print JSON responses\n", .{});
    print("        --debug                Enable debug mode with detailed logging\n", .{});
    print("        --interactive          Run in interactive mode\n\n", .{});

    print("POSITIONAL ARGUMENTS:\n", .{});
    print("    PROMPT                     The prompt text to send (optional)\n", .{});
}

pub fn printVersion() void {
    print("{s} version 0.1.0\n", .{cli_config.name});
}

pub fn shouldShowHelp(parsed: *const ParsedArgs) bool {
    return parsed.flags.help_me;
}

pub fn shouldShowVersion(parsed: *const ParsedArgs) bool {
    return parsed.flags.version;
}

pub fn printError(err: CliError) void {
    switch (err) {
        CliError.InvalidArgument => print("Error: Invalid argument provided\n", .{}),
        CliError.MissingValue => print("Error: Missing value for option\n", .{}),
        CliError.UnknownOption => print("Error: Unknown option\n", .{}),
        CliError.InvalidValue => print("Error: Invalid value for option\n", .{}),
        CliError.MutuallyExclusiveOptions => print("Error: Mutually exclusive options provided\n", .{}),
        CliError.OutOfMemory => print("Error: Out of memory\n", .{}),
    }
    print("Use --help-me for usage information\n", .{});
}

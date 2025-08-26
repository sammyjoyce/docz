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
    help: bool = false,
    version: bool = false,
    stream: bool = false,
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
            } else if (std.mem.eql(u8, name, "help")) {
                result.flags.help = true;
            } else if (std.mem.eql(u8, name, "version")) {
                result.flags.version = true;
            } else if (std.mem.eql(u8, name, "stream")) {
                result.flags.stream = true;
            } else if (std.mem.eql(u8, name, "no-stream")) {
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
            } else if (short_char == 'T') {
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                result.options.max_tokens = std.fmt.parseInt(u32, args[i], 10) catch {
                    return CliError.InvalidValue;
                };
            } else if (short_char == 't') {
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                result.options.temperature = std.fmt.parseFloat(f32, args[i]) catch {
                    return CliError.InvalidValue;
                };
            } else if (short_char == 'v') {
                result.flags.verbose = true;
            } else if (short_char == 'h') {
                result.flags.help = true;
            } else if (short_char == 'O') {
                result.flags.oauth = true;
            } else if (short_char == 'V') {
                result.flags.version = true;
            } else if (short_char == 'S') {
                result.flags.stream = true;
            } else if (short_char == 'D') {
                // deprecated: '-D' (disable-stream) removed; treat as unknown
                return CliError.UnknownOption;
            } else if (short_char == 'p') {
                result.flags.pretty = true;
            } else if (short_char == 'd') {
                result.flags.debug = true;
            } else if (short_char == 'I') {
                result.flags.interactive = true;
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

    return result;
}

fn hasShort(comptime T: type) bool {
    return @hasField(T, "short");
}

fn hasDefault(comptime T: type) bool {
    return @hasField(T, "default");
}

fn hasDeprecated(comptime T: type) bool {
    return @hasField(T, "deprecated");
}

fn labelLenOption(comptime T: type, opt: T) usize {
    var len: usize = 0;
    // short part or spaces
    len += 4; // "-x, " or four spaces
    // long part
    len += 2 + opt.long.len; // "--" + name
    // type suffix
    len += 3 + opt.type.len; // " <" + type + ">"
    return len;
}

fn labelLenFlag(comptime T: type, flag: T) usize {
    var len: usize = 0;
    len += 4; // short or spaces
    len += 2 + flag.long.len; // --name
    return len;
}

fn printSpaces(n: usize) void {
    var i: usize = 0;
    while (i < n) : (i += 1) print(" ", .{});
}

pub fn printHelp() void {
    const cfg = cli_config;
    print("{s} - {s}\n\n", .{ cfg.name, cfg.description });

    // Usage line derived from positionals
    const PosT = @TypeOf(cfg.positionals);
    const PosInfo = @typeInfo(PosT).@"struct";
    const have_positionals = PosInfo.fields.len > 0;
    print("USAGE:\n", .{});
    if (have_positionals) {
        // Use first positional meta tag in usage
        const pos0 = @field(cfg.positionals, PosInfo.fields[0].name);
        const meta_name = @tagName(pos0.meta);
        print("    {s} [OPTIONS] [FLAGS] [{s}]\n\n", .{ cfg.name, meta_name });
    } else {
        print("    {s} [OPTIONS] [FLAGS]\n\n", .{cfg.name});
    }

    // Compute column widths for alignment
    var max_opt: usize = 0;
    const OptsT = @TypeOf(cfg.options);
    const OptsInfo = @typeInfo(OptsT).@"struct";
    inline for (OptsInfo.fields) |f| {
        const opt = @field(cfg.options, f.name);
        const l = labelLenOption(@TypeOf(opt), opt);
        if (l > max_opt) max_opt = l;
    }
    var max_flag: usize = 0;
    const FlagsT = @TypeOf(cfg.flags);
    const FlagsInfo = @typeInfo(FlagsT).@"struct";
    inline for (FlagsInfo.fields) |f2| {
        const flag = @field(cfg.flags, f2.name);
        const l = labelLenFlag(@TypeOf(flag), flag);
        if (l > max_flag) max_flag = l;
    }
    var max_pos: usize = 0;
    inline for (PosInfo.fields) |pf| {
        const pos = @field(cfg.positionals, pf.name);
        const l = @tagName(pos.meta).len;
        if (l > max_pos) max_pos = l;
    }

    if (OptsInfo.fields.len > 0) {
        print("OPTIONS:\n", .{});
        inline for (OptsInfo.fields) |f3| {
            const opt = @field(cfg.options, f3.name);
            // Indent
            print("    ", .{});
            // short or spaces
            if (@hasField(@TypeOf(opt), "short")) {
                const sc: u8 = @intCast(opt.short);
                print("-{c}, ", .{sc});
            } else {
                print("    ", .{});
            }
            // long + type
            print("--{s} <{s}>", .{ opt.long, opt.type });

            const label_len = labelLenOption(@TypeOf(opt), opt);
            const pad = if (max_opt > label_len) (max_opt - label_len + 2) else 2;
            printSpaces(pad);

            // description
            print("{s}", .{opt.description});
            if (@hasField(@TypeOf(opt), "default")) {
                if (comptime std.mem.eql(u8, opt.long, "model")) {
                    print(" [default: {s}]", .{opt.default});
                } else {
                    print(" [default: {}]", .{opt.default});
                }
            }
            if (@hasField(@TypeOf(opt), "deprecated")) {
                if (opt.deprecated) print(" (deprecated)", .{});
            }
            print("\n", .{});
        }
        print("\n", .{});
    }

    if (FlagsInfo.fields.len > 0) {
        print("FLAGS:\n", .{});
        inline for (FlagsInfo.fields) |f4| {
            const flag = @field(cfg.flags, f4.name);
            print("    ", .{});
            if (@hasField(@TypeOf(flag), "short")) {
                const sc2: u8 = @intCast(flag.short);
                print("-{c}, ", .{sc2});
            } else {
                print("    ", .{});
            }
            print("--{s}", .{flag.long});

            const label_len2 = labelLenFlag(@TypeOf(flag), flag);
            const pad2 = if (max_flag > label_len2) (max_flag - label_len2 + 2) else 2;
            printSpaces(pad2);

            print("{s}", .{flag.description});
            if (@hasField(@TypeOf(flag), "default")) {
                print(" [default: {}]", .{flag.default});
            }
            if (@hasField(@TypeOf(flag), "deprecated")) {
                if (flag.deprecated) print(" (deprecated)", .{});
            }
            print("\n", .{});
        }
        print("\n", .{});
    }

    if (PosInfo.fields.len > 0) {
        print("POSITIONAL ARGUMENTS:\n", .{});
        inline for (PosInfo.fields) |pf2| {
            const pos = @field(cfg.positionals, pf2.name);
            const meta_str = @tagName(pos.meta);
            print("    {s}", .{meta_str});
            const pad3 = if (max_pos > meta_str.len) (max_pos - meta_str.len + 2) else 2;
            printSpaces(pad3);
            print("{s}\n", .{pos.description});
        }
    }
}

pub fn printVersion() void {
    print("{s} version 0.1.0\n", .{cli_config.name});
}

pub fn shouldShowHelp(parsed: *const ParsedArgs) bool {
    return parsed.flags.help;
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
    print("Use --help for usage information\n", .{});
}

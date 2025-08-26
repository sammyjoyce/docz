//! Pure Zig CLI parser using comptime reflection from cli.zon configuration

const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const cli_config = @import("cli.zon");
const CliFormatter = @import("cli/formatters/simple.zig").CliFormatter;

pub const CliError = error{
    UnknownOption,
    MissingValue,
    InvalidValue,
    MutuallyExclusiveOptions,
    OutOfMemory,
    InvalidArgument,
    UnknownCommand,
    UnknownSubcommand,
};

// Subcommand definitions
pub const AuthSubcommand = enum {
    login,
    status,
    refresh,

    pub fn fromString(str: []const u8) ?AuthSubcommand {
        if (std.mem.eql(u8, str, "login")) return .login;
        if (std.mem.eql(u8, str, "status")) return .status;
        if (std.mem.eql(u8, str, "refresh")) return .refresh;
        return null;
    }
};

pub const Command = union(enum) {
    chat: void, // Default command for normal operation
    auth: AuthSubcommand,

    pub fn fromString(str: []const u8) ?Command {
        if (std.mem.eql(u8, str, "auth")) return Command{ .auth = undefined }; // Will be filled in later
        return null;
    }
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
    verbose: bool = false,
    help: bool = false,
    version: bool = false,
    stream: bool = false,
    pretty: bool = false,
    debug: bool = false,
    interactive: bool = false,
    oauth: bool = false,
};

pub const ParsedPositionals = struct {
    command: Command = Command.chat,
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

// Comptime reflection helpers for argument parsing
fn parseOptionValue(comptime T: type, str: []const u8) !T {
    return switch (T) {
        []const u8 => str,
        u32 => std.fmt.parseInt(u32, str, 10),
        f32 => std.fmt.parseFloat(f32, str),
        else => @compileError("Unsupported option type: " ++ @typeName(T)),
    };
}

fn getOptionType(comptime opt: anytype) type {
    const type_str = opt.type;
    return switch (comptime std.mem.eql(u8, type_str, "string")) {
        true => []const u8,
        false => switch (comptime std.mem.eql(u8, type_str, "u32")) {
            true => u32,
            false => switch (comptime std.mem.eql(u8, type_str, "f32")) {
                true => f32,
                false => @compileError("Unknown option type: " ++ type_str),
            },
        },
    };
}

fn matchesOption(comptime opt: anytype, arg: []const u8) bool {
    // Check long form
    if (std.mem.startsWith(u8, arg, "--")) {
        const name = arg[2..];
        if (std.mem.eql(u8, name, opt.long)) return true;
    }
    // Check short form
    if (@hasField(@TypeOf(opt), "short") and std.mem.startsWith(u8, arg, "-") and arg.len == 2) {
        const short_char = arg[1];
        if (short_char == @as(u8, @intCast(opt.short))) return true;
    }
    return false;
}

fn matchesFlag(comptime flag: anytype, arg: []const u8) bool {
    // Check long form
    if (std.mem.startsWith(u8, arg, "--")) {
        const name = arg[2..];
        if (std.mem.eql(u8, name, flag.long)) return true;
    }
    // Check short form
    if (@hasField(@TypeOf(flag), "short") and std.mem.startsWith(u8, arg, "-") and arg.len == 2) {
        const short_char = arg[1];
        if (short_char == @as(u8, @intCast(flag.short))) return true;
    }
    return false;
}

pub fn parseArgs(allocator: Allocator, args: []const []const u8) !ParsedArgs {
    var result = ParsedArgs{
        .options = ParsedOptions{},
        .flags = ParsedFlags{},
        .positionals = ParsedPositionals{},
        .allocator = allocator,
    };

    // Set default values from cli.zon using comptime reflection
    const cfg = cli_config;
    const OptsT = @TypeOf(cfg.options);
    const OptsInfo = @typeInfo(OptsT).@"struct";
    inline for (OptsInfo.fields) |opt_field| {
        const opt = @field(cfg.options, opt_field.name);
        if (@hasField(@TypeOf(opt), "default")) {
            const field_name = opt.long;

            // Use comptime string matching to set defaults
            if (comptime std.mem.eql(u8, field_name, "model")) {
                result.options.model = try allocator.dupe(u8, opt.default);
            } else if (comptime std.mem.eql(u8, field_name, "max-tokens")) {
                result.options.max_tokens = opt.default;
            } else if (comptime std.mem.eql(u8, field_name, "temperature")) {
                result.options.temperature = opt.default;
            }
        }
    }

    // Set flag defaults
    const FlagsT = @TypeOf(cfg.flags);
    const FlagsInfo = @typeInfo(FlagsT).@"struct";
    inline for (FlagsInfo.fields) |flag_field| {
        const flag = @field(cfg.flags, flag_field.name);
        if (@hasField(@TypeOf(flag), "default")) {
            const field_name = flag.long;
            if (comptime std.mem.eql(u8, field_name, "stream")) {
                result.flags.stream = flag.default;
            }
        }
    }

    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        // Try to match options using comptime reflection
        var option_matched = false;
        inline for (OptsInfo.fields) |opt_field| {
            const opt = @field(cfg.options, opt_field.name);
            if (!option_matched and matchesOption(opt, arg)) {
                option_matched = true;
                if (i + 1 >= args.len) return CliError.MissingValue;
                i += 1;
                const OptionType = getOptionType(opt);
                const parsed_value = parseOptionValue(OptionType, args[i]) catch {
                    return CliError.InvalidValue;
                };

                // Set the field value using comptime string matching
                const field_name = opt.long;
                if (comptime std.mem.eql(u8, field_name, "model")) {
                    if (result.options.model) |old| allocator.free(old);
                    result.options.model = try allocator.dupe(u8, parsed_value);
                } else if (comptime std.mem.eql(u8, field_name, "output")) {
                    result.options.output = try allocator.dupe(u8, parsed_value);
                } else if (comptime std.mem.eql(u8, field_name, "input")) {
                    result.options.input = try allocator.dupe(u8, parsed_value);
                } else if (comptime std.mem.eql(u8, field_name, "system")) {
                    result.options.system = try allocator.dupe(u8, parsed_value);
                } else if (comptime std.mem.eql(u8, field_name, "config")) {
                    result.options.config = try allocator.dupe(u8, parsed_value);
                } else if (comptime std.mem.eql(u8, field_name, "max-tokens")) {
                    result.options.max_tokens = parsed_value;
                } else if (comptime std.mem.eql(u8, field_name, "temperature")) {
                    result.options.temperature = parsed_value;
                }
            }
        }

        // Try to match flags using comptime reflection
        if (!option_matched) {
            var flag_matched = false;
            inline for (FlagsInfo.fields) |flag_field| {
                const flag = @field(cfg.flags, flag_field.name);
                if (!flag_matched and matchesFlag(flag, arg)) {
                    flag_matched = true;
                    const field_name = flag.long;

                    if (comptime std.mem.eql(u8, field_name, "verbose")) {
                        result.flags.verbose = true;
                    } else if (comptime std.mem.eql(u8, field_name, "help")) {
                        result.flags.help = true;
                    } else if (comptime std.mem.eql(u8, field_name, "version")) {
                        result.flags.version = true;
                    } else if (comptime std.mem.eql(u8, field_name, "stream")) {
                        result.flags.stream = true;
                    } else if (comptime std.mem.eql(u8, field_name, "no-stream")) {
                        result.flags.stream = false;
                    } else if (comptime std.mem.eql(u8, field_name, "pretty")) {
                        result.flags.pretty = true;
                    } else if (comptime std.mem.eql(u8, field_name, "debug")) {
                        result.flags.debug = true;
                    } else if (comptime std.mem.eql(u8, field_name, "interactive")) {
                        result.flags.interactive = true;
                    }
                }
            }

            if (!flag_matched and !option_matched) {
                if (std.mem.startsWith(u8, arg, "-")) {
                    return CliError.UnknownOption;
                } else {
                    // Positional argument - handle commands and subcommands
                    switch (result.positionals.command) {
                        .chat => {
                            // For chat command, check if this is actually a command
                            if (std.mem.eql(u8, arg, "auth")) {
                                if (i + 1 >= args.len) {
                                    return CliError.MissingValue; // auth subcommand is required
                                }
                                i += 1;
                                const subcommand_str = args[i];
                                if (AuthSubcommand.fromString(subcommand_str)) |sub| {
                                    result.positionals.command = Command{ .auth = sub };
                                } else {
                                    return CliError.UnknownSubcommand;
                                }
                            } else {
                                // Not a known command, treat as prompt for default chat command
                                if (result.positionals.prompt == null) {
                                    result.positionals.prompt = try allocator.dupe(u8, arg);
                                }
                            }
                        },
                        .auth => {
                            // Auth commands don't accept additional positional arguments
                            // Silently ignore additional arguments
                        },
                    }
                }
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

fn printOption(opt: anytype, max_width: usize) void {
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
    const pad = if (max_width > label_len) (max_width - label_len + 2) else 2;
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

fn printFlag(flag: anytype, max_width: usize) void {
    print("    ", .{});
    if (@hasField(@TypeOf(flag), "short")) {
        const sc: u8 = @intCast(flag.short);
        print("-{c}, ", .{sc});
    } else {
        print("    ", .{});
    }
    print("--{s}", .{flag.long});

    const label_len = labelLenFlag(@TypeOf(flag), flag);
    const pad = if (max_width > label_len) (max_width - label_len + 2) else 2;
    printSpaces(pad);

    print("{s}", .{flag.description});
    if (@hasField(@TypeOf(flag), "default")) {
        print(" [default: {}]", .{flag.default});
    }
    if (@hasField(@TypeOf(flag), "deprecated")) {
        if (flag.deprecated) print(" (deprecated)", .{});
    }
    print("\n", .{});
}

fn printSubcommands(subcommands: anytype) void {
    const SubcommandsT = @TypeOf(subcommands);
    const subcommands_info = @typeInfo(SubcommandsT).@"struct";

    inline for (subcommands_info.fields) |cmd_field| {
        const command = @field(subcommands, cmd_field.name);

        // Convert command name to uppercase for display
        var cmd_name_upper: [cmd_field.name.len]u8 = undefined;
        for (cmd_field.name, 0..) |c, i| {
            cmd_name_upper[i] = std.ascii.toUpper(c);
        }

        print("{s} COMMANDS:\n", .{cmd_name_upper});

        if (@hasField(@TypeOf(command), "subcommands")) {
            const SubT = @TypeOf(command.subcommands);
            const sub_info = @typeInfo(SubT).@"struct";

            // Calculate max width for alignment
            var max_subcmd_width: usize = 0;
            inline for (sub_info.fields) |sub_field| {
                if (sub_field.name.len > max_subcmd_width) {
                    max_subcmd_width = sub_field.name.len;
                }
            }

            inline for (sub_info.fields) |sub_field| {
                const subcmd_desc = @field(command.subcommands, sub_field.name);
                print("    {s}", .{sub_field.name});
                const pad = if (max_subcmd_width > sub_field.name.len)
                    (max_subcmd_width - sub_field.name.len + 4)
                else
                    4;
                printSpaces(pad);
                print("{s}\n", .{subcmd_desc});
            }
        }
        print("\n", .{});
    }
}

pub fn printHelp(allocator: Allocator) !void {
    // For now, use a simple approach
    var formatter = CliFormatter.init(allocator);
    try formatter.printEnhancedHelp(cli_config);
}

pub fn printVersion(allocator: Allocator) !void {
    var formatter = CliFormatter.init(allocator);
    try formatter.printEnhancedVersion(cli_config);
}

pub fn shouldShowHelp(parsed: *const ParsedArgs) bool {
    return parsed.flags.help;
}

pub fn shouldShowVersion(parsed: *const ParsedArgs) bool {
    return parsed.flags.version;
}

pub fn printError(allocator: Allocator, err: CliError, context: ?[]const u8) !void {
    var formatter = CliFormatter.init(allocator);
    try formatter.printEnhancedError(err, context);
}

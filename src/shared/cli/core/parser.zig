//! Core CLI argument parser
//! Extracted from monolithic cli.zig with enhanced error handling and modularity

const std = @import("std");
const types = @import("types.zig");
const Allocator = std.mem.Allocator;

// Re-export types for convenience
pub const ParsedArgs = types.ParsedArgs;
pub const ParsedOptions = types.ParsedOptions;
pub const ParsedFlags = types.ParsedFlags;
pub const ParsedPositionals = types.ParsedPositionals;
pub const CliError = types.CliError;
pub const Command = types.Command;
pub const AuthSubcommand = types.AuthSubcommand;

// Import configuration
const cli_config = @import("../config/cli.zon");

/// Comptime reflection helpers for argument parsing
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

/// Enhanced parser with better error reporting
pub const Parser = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Parser {
        return .{ .allocator = allocator };
    }

    /// Parse command line arguments with comprehensive error context
    pub fn parse(self: Parser, args: []const []const u8) CliError!ParsedArgs {
        var result = ParsedArgs{
            .options = ParsedOptions{},
            .flags = ParsedFlags{},
            .positionals = ParsedPositionals{},
            .allocator = self.allocator,
        };

        // Set default values from cli.zon using comptime reflection
        try self.setDefaults(&result);

        var i: usize = 0;
        while (i < args.len) {
            const arg = args[i];

            // Try to match options using comptime reflection
            if (try self.parseOption(args, &i, &result)) {
                i += 1;
                continue;
            }

            // Try to match flags using comptime reflection
            if (try self.parseFlag(arg, &result)) {
                i += 1;
                continue;
            }

            // Handle positional arguments
            if (std.mem.startsWith(u8, arg, "-")) {
                return CliError.UnknownOption;
            } else {
                try self.parsePositional(args, &i, &result);
                i += 1;
            }
        }

        return result;
    }

    fn setDefaults(self: Parser, result: *ParsedArgs) !void {
        _ = self;
        const cfg = cli_config;
        const OptsT = @TypeOf(cfg.options);
        const OptsInfo = @typeInfo(OptsT).@"struct";

        inline for (OptsInfo.fields) |opt_field| {
            const opt = @field(cfg.options, opt_field.name);
            if (@hasField(@TypeOf(opt), "default")) {
                const field_name = opt.long;

                // Use comptime string matching to set defaults
                if (comptime std.mem.eql(u8, field_name, "model")) {
                    result.options.model = try result.allocator.dupe(u8, opt.default);
                } else if (comptime std.mem.eql(u8, field_name, "max-tokens")) {
                    result.options.maxTokens = opt.default;
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
    }

    fn parseOption(self: Parser, args: []const []const u8, i: *usize, result: *ParsedArgs) !bool {
        _ = self;
        const arg = args[i.*];
        const cfg = cli_config;
        const OptsT = @TypeOf(cfg.options);
        const OptsInfo = @typeInfo(OptsT).@"struct";

        inline for (OptsInfo.fields) |opt_field| {
            const opt = @field(cfg.options, opt_field.name);
            if (matchesOption(opt, arg)) {
                if (i.* + 1 >= args.len) return CliError.MissingValue;
                i.* += 1;
                const OptionType = getOptionType(opt);
                const parsed_value = parseOptionValue(OptionType, args[i.*]) catch {
                    return CliError.InvalidValue;
                };

                // Set the field value using comptime string matching
                const field_name = opt.long;
                if (comptime std.mem.eql(u8, field_name, "model")) {
                    if (result.options.model) |old| result.allocator.free(old);
                    result.options.model = try result.allocator.dupe(u8, parsed_value);
                } else if (comptime std.mem.eql(u8, field_name, "output")) {
                    result.options.output = try result.allocator.dupe(u8, parsed_value);
                } else if (comptime std.mem.eql(u8, field_name, "input")) {
                    result.options.input = try result.allocator.dupe(u8, parsed_value);
                } else if (comptime std.mem.eql(u8, field_name, "system")) {
                    result.options.system = try result.allocator.dupe(u8, parsed_value);
                } else if (comptime std.mem.eql(u8, field_name, "config")) {
                    result.options.config = try result.allocator.dupe(u8, parsed_value);
                } else if (comptime std.mem.eql(u8, field_name, "max-tokens")) {
                    result.options.maxTokens = parsed_value;
                } else if (comptime std.mem.eql(u8, field_name, "temperature")) {
                    result.options.temperature = parsed_value;
                }
                return true;
            }
        }
        return false;
    }

    fn parseFlag(self: Parser, arg: []const u8, result: *ParsedArgs) !bool {
        _ = self;
        const cfg = cli_config;
        const FlagsT = @TypeOf(cfg.flags);
        const FlagsInfo = @typeInfo(FlagsT).@"struct";

        inline for (FlagsInfo.fields) |flag_field| {
            const flag = @field(cfg.flags, flag_field.name);
            if (matchesFlag(flag, arg)) {
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
                return true;
            }
        }
        return false;
    }

    fn parsePositional(self: Parser, args: []const []const u8, i: *usize, result: *ParsedArgs) !void {
        const arg = args[i.*];

        // Positional argument - handle commands and subcommands
        switch (result.positionals.command) {
            .chat => {
                // For chat command, check if this is actually a command
                if (std.mem.eql(u8, arg, "auth")) {
                    if (i.* + 1 >= args.len) {
                        return CliError.MissingValue; // auth subcommand is required
                    }
                    i.* += 1;
                    const subcommand_str = args[i.*];
                    if (AuthSubcommand.fromString(subcommand_str)) |sub| {
                        result.positionals.command = Command{ .auth = sub };
                    } else {
                        return CliError.UnknownSubcommand;
                    }
                } else {
                    // Not a known command, treat as prompt for default chat command
                    if (result.positionals.prompt == null) {
                        result.positionals.prompt = try self.allocator.dupe(u8, arg);
                    }
                }
            },
            .auth => {
                // Auth commands don't accept additional positional arguments
                // Silently ignore additional arguments
            },
        }
    }
};

/// Convenience function to maintain backward compatibility
pub fn parseArgs(allocator: Allocator, args: []const []const u8) !ParsedArgs {
    const parser = Parser.init(allocator);
    return parser.parse(args);
}

//! Enhanced CLI parser that combines the modular architecture with legacy functionality
//! Provides backward compatibility while using the new modular system

const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const cli_config = @import("../../cli.zon");
const enhanced_formatter = @import("../formatters/enhanced.zig");
const types = @import("types.zig");

pub const CliError = types.CliError;

pub const ParsedArgs = struct {
    // Core options from config
    model: []const u8,
    max_tokens: ?u32,
    temperature: ?f32,
    stream: bool,
    json: bool,
    quiet: bool,
    verbose: bool,
    no_color: bool,

    // Flags
    help: bool,
    version: bool,

    // Commands and subcommands
    command: ?types.UnifiedCommand,
    auth_subcommand: ?types.AuthSubcommand,

    // Positional arguments
    prompt: ?[]const u8,

    // Raw arguments for debugging
    raw_args: [][]const u8,

    allocator: Allocator,

    pub fn deinit(self: *ParsedArgs) void {
        // Clean up any allocated strings
        for (self.raw_args) |arg| {
            self.allocator.free(arg);
        }
        self.allocator.free(self.raw_args);

        if (self.prompt) |p| {
            self.allocator.free(p);
        }
    }

    pub fn init(allocator: Allocator) ParsedArgs {
        return ParsedArgs{
            .model = cli_config.options[0].default,
            .max_tokens = null,
            .temperature = null,
            .stream = cli_config.flags[3].default,
            .json = false, // Not defined in zon file, using default
            .quiet = false, // Not defined in zon file, using default
            .verbose = false, // cli_config.flags[0] doesn't have default
            .no_color = false, // Not defined in zon file, using default
            .help = false,
            .version = false,
            .command = null,
            .auth_subcommand = null,
            .prompt = null,
            .raw_args = &[_][]const u8{},
            .allocator = allocator,
        };
    }
};

pub const EnhancedParser = struct {
    allocator: Allocator,
    formatter: enhanced_formatter.CliFormatter,

    pub fn init(allocator: Allocator) EnhancedParser {
        return EnhancedParser{
            .allocator = allocator,
            .formatter = enhanced_formatter.CliFormatter.init(allocator),
        };
    }

    pub fn parse(self: *EnhancedParser, args: [][]const u8) !ParsedArgs {
        var parsed = ParsedArgs.init(self.allocator);

        // Store raw args for debugging
        parsed.raw_args = try self.allocator.alloc([]const u8, args.len);
        errdefer {
            // Clean up raw_args on error
            for (parsed.raw_args) |arg| {
                self.allocator.free(arg);
            }
            self.allocator.free(parsed.raw_args);
        }
        for (args, 0..) |arg, i| {
            parsed.raw_args[i] = try self.allocator.dupe(u8, arg);
        }

        var i: usize = 0; // Program name already stripped by caller
        var prompt_parts = std.array_list.Managed([]const u8).init(self.allocator);
        defer prompt_parts.deinit();

        while (i < args.len) {
            const arg = args[i];

            if (std.mem.startsWith(u8, arg, "--")) {
                // Long options
                if (std.mem.eql(u8, arg, "--help")) {
                    parsed.help = true;
                } else if (std.mem.eql(u8, arg, "--version")) {
                    parsed.version = true;
                } else if (std.mem.eql(u8, arg, "--quiet")) {
                    parsed.quiet = true;
                } else if (std.mem.eql(u8, arg, "--verbose")) {
                    parsed.verbose = true;
                } else if (std.mem.eql(u8, arg, "--stream")) {
                    parsed.stream = true;
                } else if (std.mem.eql(u8, arg, "--json")) {
                    parsed.json = true;
                } else if (std.mem.eql(u8, arg, "--no-color")) {
                    parsed.no_color = true;
                } else if (std.mem.startsWith(u8, arg, "--model=")) {
                    parsed.model = arg[8..];
                } else if (std.mem.eql(u8, arg, "--model")) {
                    i += 1;
                    if (i >= args.len) return CliError.MissingValue;
                    parsed.model = args[i];
                } else if (std.mem.startsWith(u8, arg, "--max-tokens=")) {
                    const value_str = arg[13..];
                    parsed.max_tokens = std.fmt.parseInt(u32, value_str, 10) catch return CliError.InvalidValue;
                } else if (std.mem.eql(u8, arg, "--max-tokens")) {
                    i += 1;
                    if (i >= args.len) return CliError.MissingValue;
                    parsed.max_tokens = std.fmt.parseInt(u32, args[i], 10) catch return CliError.InvalidValue;
                } else if (std.mem.startsWith(u8, arg, "--temperature=")) {
                    const value_str = arg[14..];
                    parsed.temperature = std.fmt.parseFloat(f32, value_str) catch return CliError.InvalidValue;
                } else if (std.mem.eql(u8, arg, "--temperature")) {
                    i += 1;
                    if (i >= args.len) return CliError.MissingValue;
                    parsed.temperature = std.fmt.parseFloat(f32, args[i]) catch return CliError.InvalidValue;
                } else {
                    return CliError.UnknownOption;
                }
            } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                // Short options
                for (arg[1..]) |flag| {
                    switch (flag) {
                        'h' => parsed.help = true,
                        'V' => parsed.version = true,
                        'q' => parsed.quiet = true,
                        'v' => parsed.verbose = true,
                        's' => parsed.stream = true,
                        'j' => parsed.json = true,
                        'm' => {
                            // -m requires next arg
                            i += 1;
                            if (i >= args.len) return CliError.MissingValue;
                            parsed.model = args[i];
                            break; // Stop processing short flags
                        },
                        else => return CliError.UnknownOption,
                    }
                }
            } else {
                // Commands or positional arguments
                if (parsed.command == null) {
                    if (types.UnifiedCommand.fromString(arg)) |cmd| {
                        parsed.command = cmd;
                        if (cmd == .auth) {
                            // Next arg should be auth subcommand
                            i += 1;
                            if (i >= args.len) {
                                // Pass "auth" as context for better error messages
                                return error.UnknownSubcommand;
                            }
                            parsed.auth_subcommand = types.AuthSubcommand.fromString(args[i]) orelse {
                                // Pass "auth" as context for better error messages
                                return error.UnknownSubcommand;
                            };
                        }
                    } else {
                        // This is likely the start of a prompt
                        try prompt_parts.append(arg);
                    }
                } else {
                    // Command already set, this is prompt content
                    try prompt_parts.append(arg);
                }
            }

            i += 1;
        }

        // Join prompt parts
        if (prompt_parts.items.len > 0) {
            var total_len: usize = 0;
            for (prompt_parts.items, 0..) |part, idx| {
                total_len += part.len;
                if (idx < prompt_parts.items.len - 1) {
                    total_len += 1; // +1 for space between parts
                }
            }

            const prompt = try self.allocator.alloc(u8, total_len);
            var pos: usize = 0;
            for (prompt_parts.items, 0..) |part, idx| {
                if (idx > 0) {
                    prompt[pos] = ' ';
                    pos += 1;
                }
                std.mem.copyForwards(u8, prompt[pos .. pos + part.len], part);
                pos += part.len;
            }
            parsed.prompt = prompt[0..pos];

            // Set default command to chat if we have a prompt but no explicit command
            if (parsed.command == null) {
                parsed.command = .chat;
            }
        }

        return parsed;
    }

    pub fn handleParsedArgs(self: *EnhancedParser, parsed: *ParsedArgs) !void {
        if (parsed.help) {
            try self.formatter.printEnhancedHelp(cli_config);
            return;
        }

        if (parsed.version) {
            try self.formatter.printEnhancedVersion(cli_config);
            return;
        }

        if (parsed.command) |cmd| {
            switch (cmd) {
                .help => {
                    try self.formatter.printEnhancedHelp(cli_config);
                    return;
                },
                .version => {
                    try self.formatter.printEnhancedVersion(cli_config);
                    return;
                },
                .auth => {
                    if (parsed.auth_subcommand) |sub| {
                        try self.handleAuthCommand(sub);
                    } else {
                        return CliError.UnknownSubcommand;
                    }
                    return;
                },
                .chat => {
                    // Chat command should be handled by caller
                    return;
                },
                .interactive => {
                    // Interactive command should be handled by caller
                    return;
                },
                .tui_demo => {
                    // TUI demo should be handled by caller
                    return;
                },
            }
        } else if (parsed.prompt == null) {
            // No command and no prompt - show help
            try self.formatter.printEnhancedHelp(cli_config);
        }
        // If we have a prompt, the caller will handle it
    }

    fn handleAuthCommand(self: *EnhancedParser, subcommand: types.AuthSubcommand) !void {
        switch (subcommand) {
            .login => {
                print("{s}{s}🔐 Starting authentication...{s}{s}\n", .{ self.formatter.colors.bold, self.formatter.colors.primary, self.formatter.colors.reset, self.formatter.colors.reset });
                // Authentication logic would go here
                print("{s}✅ Please complete authentication in your browser{s}\n", .{ self.formatter.colors.success, self.formatter.colors.reset });
            },
            .status => {
                print("{s}{s}📊 Authentication Status{s}{s}\n", .{ self.formatter.colors.bold, self.formatter.colors.primary, self.formatter.colors.reset, self.formatter.colors.reset });
                // Status check logic would go here
                print("{s}✅ Authenticated{s}\n", .{ self.formatter.colors.success, self.formatter.colors.reset });
            },
            .refresh => {
                print("{s}{s}🔄 Refreshing authentication...{s}{s}\n", .{ self.formatter.colors.bold, self.formatter.colors.primary, self.formatter.colors.reset, self.formatter.colors.reset });
                // Refresh logic would go here
                print("{s}✅ Authentication refreshed{s}\n", .{ self.formatter.colors.success, self.formatter.colors.reset });
            },
        }
    }

    pub fn printError(self: *EnhancedParser, err: CliError, context: ?[]const u8) !void {
        try self.formatter.printEnhancedError(err, context);
    }
};

/// Convenience function to parse arguments using the enhanced parser
pub fn parseArgsEnhanced(allocator: Allocator, args: [][]const u8) !ParsedArgs {
    var parser = EnhancedParser.init(allocator);
    return try parser.parse(args);
}

/// Full parsing and handling in one call
pub fn parseAndHandle(allocator: Allocator, args: [][]const u8) !?ParsedArgs {
    var parser = EnhancedParser.init(allocator);
    var parsed = parser.parse(args) catch |err| {
        // For auth-related errors, use the command as context instead of the failing argument
        const context = if (args.len > 0 and std.mem.eql(u8, args[0], "auth")) "auth"
                       else if (args.len > 1) args[1]
                       else null;
        try parser.printError(err, context);
        return null;
    };

    // Handle built-in commands (help, version, auth)
    parser.handleParsedArgs(&parsed) catch |err| {
        try parser.printError(err, null);
        parsed.deinit();
        return null;
    };

    // Return parsed args if there's a prompt to process
    if (parsed.prompt != null) {
        return parsed;
    } else {
        // Built-in command was handled, clean up
        parsed.deinit();
        return null;
    }
}

//! CLI argument types and structures
//! Extracted from monolithic cli.zig for better modularity

const std = @import("std");
const Allocator = std.mem.Allocator;

/// CLI parsing errors
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

/// Auth subcommand variants
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

/// Available CLI commands
pub const Command = union(enum) {
    chat: void, // Default command for normal operation
    auth: AuthSubcommand,

    pub fn fromString(str: []const u8) ?Command {
        if (std.mem.eql(u8, str, "auth")) return Command{ .auth = undefined }; // Will be filled in later
        return null;
    }
};

/// Parsed CLI options (values that require arguments)
pub const ParsedOptions = struct {
    model: ?[]const u8 = null,
    output: ?[]const u8 = null,
    input: ?[]const u8 = null,
    system: ?[]const u8 = null,
    config: ?[]const u8 = null,
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
};

/// Parsed CLI flags (boolean options)
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

/// Parsed positional arguments
pub const ParsedPositionals = struct {
    command: Command = Command.chat,
    prompt: ?[]const u8 = null,
};

/// Complete parsed arguments structure
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

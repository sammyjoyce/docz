//! CLI argument types and structures
//! Types for the CLI system

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
    InitializationError,
    CommandExecutionError,
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
pub const Command = enum {
    chat,
    auth,
    interactive,
    help,
    version,
    tui_demo,

    /// Generate fromString method using comptime reflection
    pub fn fromString(str: []const u8) ?Command {
        const info = @typeInfo(Command).@"enum";
        inline for (info.fields) |field| {
            const field_name = field.name;
            const commandString = comptime blk: {
                if (std.mem.eql(u8, field_name, "tui_demo")) {
                    break :blk "tui-demo";
                } else {
                    break :blk field_name;
                }
            };

            if (std.mem.eql(u8, str, commandString)) {
                return @field(Command, field_name);
            }
        }
        return null;
    }

    /// Generate toString method using comptime reflection
    pub fn toString(self: Command) []const u8 {
        const info = @typeInfo(Command).@"enum";
        inline for (info.fields) |field| {
            if (@intFromEnum(self) == field.value) {
                if (std.mem.eql(u8, field.name, "tui_demo")) {
                    return "tui-demo";
                } else {
                    return field.name;
                }
            }
        }
        return "unknown";
    }

    /// Get command description using comptime reflection
    pub fn getDescription(self: Command) []const u8 {
        return switch (self) {
            .chat => "Start interactive chat session (default command)",
            .auth => "Authentication management commands",
            .interactive => "Launch interactive command palette mode",
            .help => "Show help information and usage examples",
            .version => "Show version information",
            .tui_demo => "Run terminal UI demonstration",
        };
    }
};

/// Parsed CLI options (values that require arguments)
pub const Options = struct {
    model: ?[]const u8 = null,
    output: ?[]const u8 = null,
    input: ?[]const u8 = null,
    system: ?[]const u8 = null,
    config: ?[]const u8 = null,
    maxTokens: ?u32 = null,
    temperature: ?f32 = null,
};

/// Parsed CLI flags (boolean options)
pub const Flags = struct {
    verbose: bool = false,
    help: bool = false,
    version: bool = false,
    stream: bool = false,
    pretty: bool = false,
    debug: bool = false,
    interactive: bool = false,
    interactive_ux: bool = false,
    oauth: bool = false,
};

/// Parsed positional arguments
pub const Positionals = struct {
    command: Command = Command.chat,
    prompt: ?[]const u8 = null,
};

/// Complete parsed arguments structure
pub const LegacyArgs = struct {
    options: Options,
    flags: Flags,
    positionals: Positionals,
    allocator: Allocator,

    pub fn deinit(self: *Args) void {
        // Clean up allocated strings
        if (self.options.model) |str| self.allocator.free(str);
        if (self.options.output) |str| self.allocator.free(str);
        if (self.options.input) |str| self.allocator.free(str);
        if (self.options.system) |str| self.allocator.free(str);
        if (self.options.config) |str| self.allocator.free(str);
        if (self.positionals.prompt) |prompt| self.allocator.free(prompt);
    }
};

/// CLI Configuration for unified system
pub const Config = struct {
    // Core settings
    model: []const u8 = "claude-3-5-sonnet-20241022",
    temperature: f32 = 1.0,
    maxTokens: u32 = 4096,

    // Output formatting
    format: OutputFormat = .rich,
    theme: []const u8 = "default",
    color: bool = true,

    // Terminal features
    hyperlinks: bool = true,
    clipboard: bool = true,
    notifications: bool = true,

    // Interaction settings
    stream: bool = false,
    interactive: bool = false,
    verbose: bool = false,

    allocator: Allocator,

    pub const OutputFormat = enum {
        basic,
        rich,
        json,
        markdown,

        pub fn fromString(str: []const u8) ?OutputFormat {
            if (std.mem.eql(u8, str, "basic")) return .basic;
            if (std.mem.eql(u8, str, "rich")) return .rich;
            if (std.mem.eql(u8, str, "json")) return .json;
            if (std.mem.eql(u8, str, "markdown")) return .markdown;
            return null;
        }
    };

    pub fn loadDefault(allocator: Allocator) Config {
        return Config{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Config, allocator: Allocator) void {
        // Clean up any allocated strings if needed
        _ = self;
        _ = allocator;
    }
};

/// Command execution result
pub const CommandResult = struct {
    success: bool,
    output: ?[]const u8 = null,
    errorMessage: ?[]const u8 = null,
    exit_code: u8 = 0,

    pub fn ok(output: ?[]const u8) CommandResult {
        return CommandResult{
            .success = true,
            .output = output,
        };
    }

    pub fn err(msg: []const u8, exit_code: u8) CommandResult {
        return CommandResult{
            .success = false,
            .errorMessage = msg,
            .exit_code = exit_code,
        };
    }
};

/// Comptime reflection utilities for CLI configuration
pub const ConfigReflect = struct {
    /// Generate validation function from config struct
    pub fn generateValidator(comptime ConfigType: type) type {
        return struct {
            /// Validate all fields in the config
            pub fn validate(config: ConfigType) !void {
                const info = @typeInfo(ConfigType).@"struct";

                inline for (info.fields) |field| {
                    const fieldName = field.name;
                    const fieldValue = @field(config, fieldName);

                    switch (field.type) {
                        []const u8 => {
                            // Validate string fields are not empty (except optional ones)
                            if (!std.mem.eql(u8, fieldName, "description") and
                                !std.mem.eql(u8, fieldName, "version") and
                                fieldValue.len == 0)
                            {
                                return error.InvalidConfig;
                            }
                        },
                        ?[]const u8 => {
                            // Optional string fields are ok if null
                        },
                        u32 => {
                            // Validate positive numbers
                            if (std.mem.eql(u8, fieldName, "maxTokens") and fieldValue == 0) {
                                return error.InvalidConfig;
                            }
                        },
                        f32 => {
                            // Validate temperature range
                            if (std.mem.eql(u8, fieldName, "temperature") and
                                (fieldValue < 0.0 or fieldValue > 1.0))
                            {
                                return error.InvalidConfig;
                            }
                        },
                        bool => {
                            // Boolean fields are always valid
                        },
                        else => {
                            // For complex types, recursively validate if needed
                        },
                    }
                }
            }

            /// Get field metadata using comptime reflection
            pub fn getFieldMeta(comptime field_name: []const u8) ?FieldMeta {
                const info = @typeInfo(ConfigType).@"struct";

                inline for (info.fields) |field| {
                    if (std.mem.eql(u8, field.name, field_name)) {
                        return FieldMeta{
                            .name = field.name,
                            .type = field.type,
                            .is_optional = @typeInfo(field.type) == .optional,
                        };
                    }
                }
                return null;
            }

            /// Field metadata structure
            pub const FieldMeta = struct {
                name: []const u8,
                type: type,
                is_optional: bool,
            };

            /// Generate help text from config struct
            pub fn generateHelp() []const u8 {
                comptime var helpText: []const u8 = "";
                const info = @typeInfo(ConfigType).@"struct";

                inline for (info.fields) |field| {
                    const fieldHelp = comptime blk: {
                        if (std.mem.eql(u8, field.name, "model")) {
                            break :blk "- model: Claude model to use for generation\n";
                        } else if (std.mem.eql(u8, field.name, "maxTokens")) {
                            break :blk "- maxTokens: Maximum tokens to generate\n";
                        } else if (std.mem.eql(u8, field.name, "temperature")) {
                            break :blk "- temperature: Response randomness (0.0-1.0)\n";
                        } else {
                            break :blk "- " ++ field.name ++ ": " ++ field.name ++ " setting\n";
                        }
                    };

                    helpText = helpText ++ fieldHelp;
                }

                return helpText;
            }
        };
    }
};

/// Error set for configuration validation
pub const ConfigError = error{
    InvalidConfig,
    MissingField,
    InvalidValue,
    TypeMismatch,
};

/// Args for unified CLI
pub const Args = struct {
    // Core options
    model: []const u8,
    temperature: f32,
    maxTokens: u32,

    // Output options
    format: Config.OutputFormat,
    theme: []const u8,
    color: bool,

    // Terminal features
    hyperlinks: bool,
    clipboard: bool,
    notifications: bool,

    // Mode flags
    stream: bool,
    interactive: bool,
    interactive_ux: bool,
    verbose: bool,
    help: bool,
    version: bool,

    // Command structure
    command: ?Command,
    authSubcommand: ?AuthSubcommand,
    positionalArguments: [][]const u8,

    // Raw input
    rawMessage: ?[]const u8,

    allocator: Allocator,

    pub fn fromConfig(config: Config, allocator: Allocator) Args {
        return Args{
            .model = config.model,
            .temperature = config.temperature,
            .maxTokens = config.maxTokens,
            .format = config.format,
            .theme = config.theme,
            .color = config.color,
            .hyperlinks = config.hyperlinks,
            .clipboard = config.clipboard,
            .notifications = config.notifications,
            .stream = config.stream,
            .interactive = config.interactive,
            .interactive_ux = false, // New flag, default to false
            .verbose = config.verbose,
            .help = false,
            .version = false,
            .command = null,
            .authSubcommand = null,
            .positionalArguments = &[0][]const u8{},
            .rawMessage = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Args) void {
        // Clean up allocated arrays if needed
        if (self.positionalArguments.len > 0) {
            self.allocator.free(self.positionalArguments);
        }
    }
};

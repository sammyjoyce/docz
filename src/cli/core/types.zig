//! CLI argument types and structures
//! Unified types for the new CLI system

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
pub const UnifiedCommand = enum {
    chat,
    auth,
    interactive,
    help,
    version,
    tui_demo,

    pub fn fromString(str: []const u8) ?UnifiedCommand {
        if (std.mem.eql(u8, str, "chat")) return .chat;
        if (std.mem.eql(u8, str, "auth")) return .auth;
        if (std.mem.eql(u8, str, "interactive")) return .interactive;
        if (std.mem.eql(u8, str, "help")) return .help;
        if (std.mem.eql(u8, str, "version")) return .version;
        if (std.mem.eql(u8, str, "tui-demo")) return .tui_demo;
        return null;
    }

    pub fn toString(self: UnifiedCommand) []const u8 {
        return switch (self) {
            .chat => "chat",
            .auth => "auth",
            .interactive => "interactive",
            .help => "help",
            .version => "version",
            .tui_demo => "tui-demo",
        };
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
    command: UnifiedCommand = UnifiedCommand.chat,
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

/// CLI Configuration for unified system
pub const Config = struct {
    // Core settings
    model: []const u8 = "claude-3-5-sonnet-20241022",
    temperature: f32 = 1.0,
    max_tokens: u32 = 4096,

    // Output formatting
    format: OutputFormat = .enhanced,
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
        simple,
        enhanced,
        json,
        markdown,

        pub fn fromString(str: []const u8) ?OutputFormat {
            if (std.mem.eql(u8, str, "simple")) return .simple;
            if (std.mem.eql(u8, str, "enhanced")) return .enhanced;
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
    error_msg: ?[]const u8 = null,
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
            .error_msg = msg,
            .exit_code = exit_code,
        };
    }
};

/// Enhanced ParsedArgs for unified CLI
pub const ParsedArgsUnified = struct {
    // Core options
    model: []const u8,
    temperature: f32,
    max_tokens: u32,

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
    verbose: bool,
    help: bool,
    version: bool,

    // Command structure
    command: ?UnifiedCommand,
    auth_subcommand: ?AuthSubcommand,
    positional_args: [][]const u8,

    // Raw input
    raw_message: ?[]const u8,

    allocator: Allocator,

    pub fn fromConfig(config: Config, allocator: Allocator) ParsedArgsUnified {
        return ParsedArgsUnified{
            .model = config.model,
            .temperature = config.temperature,
            .max_tokens = config.max_tokens,
            .format = config.format,
            .theme = config.theme,
            .color = config.color,
            .hyperlinks = config.hyperlinks,
            .clipboard = config.clipboard,
            .notifications = config.notifications,
            .stream = config.stream,
            .interactive = config.interactive,
            .verbose = config.verbose,
            .help = false,
            .version = false,
            .command = null,
            .auth_subcommand = null,
            .positional_args = &[_][]const u8{},
            .raw_message = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ParsedArgsUnified) void {
        // Clean up allocated arrays if needed
        if (self.positional_args.len > 0) {
            self.allocator.free(self.positional_args);
        }
    }
};

const std = @import("std");

/// Common shell integration interface
/// Defines the standard operations that shell integration should support
pub const ShellIntegration = struct {
    /// Context for shell integration operations
    pub fn Context(comptime WriterType: type) type {
        return struct {
            allocator: std.mem.Allocator,
            writer: WriterType,
            caps: TermCaps,

            const Self = @This();

            pub fn init(writer: WriterType, allocator: std.mem.Allocator, caps: TermCaps) Self {
                return .{
                    .writer = writer,
                    .allocator = allocator,
                    .caps = caps,
                };
            }
        };
    }

    /// Terminal capabilities for shell integration
    pub const TermCaps = struct {
        supports_final_term: bool = false,
        supports_iterm2_osc1337: bool = false,
        supports_iterm2_images: bool = false,
        supports_kitty_graphics: bool = false,
        supports_sixel_graphics: bool = false,
        supports_notifications: bool = false,
        supports_badges: bool = false,
        supports_annotations: bool = false,
        supports_marks: bool = false,
        supports_downloads: bool = false,
        supports_alerts: bool = false,
    };

    /// Prompt marking operations
    pub const PromptOps = struct {
        /// Mark the start of a shell prompt
        markPromptStart: *const fn (ctx: Context) anyerror!void,

        /// Mark the end of a shell prompt (start of user input)
        markPromptEnd: *const fn (ctx: Context) anyerror!void,

        /// Mark prompt start with additional parameters
        markPromptStartWithParams: *const fn (ctx: Context, params: []const []const u8) anyerror!void,

        /// Mark prompt end with additional parameters
        markPromptEndWithParams: *const fn (ctx: Context, params: []const []const u8) anyerror!void,
    };

    /// Command tracking operations
    pub const CommandOps = struct {
        /// Mark the start of command execution
        markCommandStart: *const fn (ctx: Context, command: []const u8, cwd: ?[]const u8) anyerror!void,

        /// Mark the end of command execution
        markCommandEnd: *const fn (ctx: Context, command: []const u8, exit_code: i32, duration_ms: ?u64) anyerror!void,

        /// Mark command start with additional parameters
        markCommandStartWithParams: *const fn (ctx: Context, command: []const u8, cwd: ?[]const u8, params: []const []const u8) anyerror!void,

        /// Mark command end with additional parameters
        markCommandEndWithParams: *const fn (ctx: Context, command: []const u8, exit_code: i32, duration_ms: ?u64, params: []const []const u8) anyerror!void,
    };

    /// Current directory tracking operations
    pub const DirectoryOps = struct {
        /// Set the current working directory
        setWorkingDirectory: *const fn (ctx: Context, path: []const u8) anyerror!void,

        /// Set remote host information
        setRemoteHost: *const fn (ctx: Context, hostname: []const u8, username: ?[]const u8, port: ?u16) anyerror!void,

        /// Clear remote host information (back to local)
        clearRemoteHost: *const fn (ctx: Context) anyerror!void,
    };

    /// Semantic zone operations
    pub const SemanticOps = struct {
        /// Mark a semantic zone start
        markZoneStart: *const fn (ctx: Context, zone_type: []const u8, name: ?[]const u8) anyerror!void,

        /// Mark a semantic zone end
        markZoneEnd: *const fn (ctx: Context, zone_type: []const u8) anyerror!void,

        /// Add an annotation to terminal output
        addAnnotation: *const fn (ctx: Context, config: AnnotationConfig) anyerror!void,

        /// Clear all annotations
        clearAnnotations: *const fn (ctx: Context) anyerror!void,
    };

    /// Notification operations
    pub const NotificationOps = struct {
        /// Request terminal attention/notification
        requestAttention: *const fn (ctx: Context, message: ?[]const u8) anyerror!void,

        /// Set the terminal badge
        setBadge: *const fn (ctx: Context, text: []const u8) anyerror!void,

        /// Clear the terminal badge
        clearBadge: *const fn (ctx: Context) anyerror!void,

        /// Set alert on command completion
        setAlertOnCompletion: *const fn (ctx: Context, config: AlertConfig) anyerror!void,

        /// Trigger a file download
        triggerDownload: *const fn (ctx: Context, config: DownloadConfig) anyerror!void,
    };

    /// Configuration for annotations
    pub const AnnotationConfig = struct {
        text: []const u8,
        x: ?i32 = null,
        y: ?i32 = null,
        length: ?u32 = null,
        url: ?[]const u8 = null,
    };

    /// Configuration for alerts
    pub const AlertConfig = struct {
        message: []const u8,
        sound: bool = true,
        only_on_failure: bool = false,
    };

    /// Configuration for downloads
    pub const DownloadConfig = struct {
        url: []const u8,
        filename: ?[]const u8 = null,
        open_after_download: bool = false,
    };

    /// Complete shell integration interface
    pub const Interface = struct {
        prompt_ops: PromptOps,
        command_ops: CommandOps,
        directory_ops: DirectoryOps,
        semantic_ops: SemanticOps,
        notification_ops: NotificationOps,

        /// Get the name of this integration implementation
        name: []const u8,

        /// Get the capabilities supported by this implementation
        getCapabilities: *const fn () TermCaps,
    };

    /// Helper function to create a context
    pub fn createContext(comptime WriterType: type, writer: WriterType, allocator: std.mem.Allocator, caps: TermCaps) Context(WriterType) {
        return Context(WriterType).init(writer, allocator, caps);
    }
};

/// Convenience functions that work with any shell integration implementation
pub const Convenience = struct {
    /// Initialize full shell integration for a given implementation
    pub fn initFullIntegration(comptime WriterType: type, ctx: ShellIntegration.Context(WriterType), iface: ShellIntegration.Interface) !void {
        // Set current user if supported
        if (iface.notification_ops.setBadge != undefined) {
            try iface.notification_ops.setBadge(ctx, "Shell Ready");
        }

        // Mark initial prompt
        try iface.prompt_ops.markPromptStart(ctx);
    }

    /// Mark SSH session start
    pub fn startSshSession(
        comptime WriterType: type,
        ctx: ShellIntegration.Context(WriterType),
        iface: ShellIntegration.Interface,
        hostname: []const u8,
        username: ?[]const u8,
    ) !void {
        try iface.directory_ops.setRemoteHost(ctx, hostname, username, null);

        if (iface.notification_ops.setBadge != undefined) {
            const badge_text = try std.fmt.allocPrint(ctx.allocator, "SSH: {s}", .{hostname});
            defer ctx.allocator.free(badge_text);
            try iface.notification_ops.setBadge(ctx, badge_text);
        }
    }

    /// Mark SSH session end
    pub fn endSshSession(comptime WriterType: type, ctx: ShellIntegration.Context(WriterType), iface: ShellIntegration.Interface) !void {
        try iface.directory_ops.clearRemoteHost(ctx);

        if (iface.notification_ops.setBadge != undefined) {
            try iface.notification_ops.setBadge(ctx, "Local Shell");
        }
    }

    /// Execute a command with proper shell integration markers
    pub fn executeCommand(
        comptime WriterType: type,
        ctx: ShellIntegration.Context(WriterType),
        iface: ShellIntegration.Interface,
        command: []const u8,
        cwd: ?[]const u8,
    ) !void {
        try iface.command_ops.markCommandStart(ctx, command, cwd);
    }

    /// Complete a command with status
    pub fn completeCommand(
        comptime WriterType: type,
        ctx: ShellIntegration.Context(WriterType),
        iface: ShellIntegration.Interface,
        command: []const u8,
        exit_code: i32,
        duration_ms: u64,
    ) !void {
        try iface.command_ops.markCommandEnd(ctx, command, exit_code, duration_ms);
    }
};

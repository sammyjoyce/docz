const std = @import("std");
const integration = @import("integration.zig");

/// Prompt and command tracking functionality
/// Provides high-level utilities for managing shell integration lifecycle
pub fn PromptTracker(comptime WriterType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        context: ?ShellContext(WriterType) = null,

        pub fn ShellContext(comptime InnerWriterType: type) type {
            return struct {
                writer: InnerWriterType,
                allocator: std.mem.Allocator,
                caps: integration.ShellManager.TermCaps,
                iface: integration.ShellManager.Interface,

                const Self = @This();

                pub fn init(writer: InnerWriterType, allocator: std.mem.Allocator, caps: integration.ShellManager.TermCaps, iface: integration.ShellManager.Interface) Self {
                    return .{
                        .writer = writer,
                        .allocator = allocator,
                        .caps = caps,
                        .iface = iface,
                    };
                }

                /// Create a shell integration context
                pub fn createShellContext(self: Self) integration.ShellManager.Context(InnerWriterType) {
                    return integration.ShellManager.createContext(InnerWriterType, self.writer, self.allocator, self.caps);
                }
            };
        }

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        /// Set the shell integration context
        pub fn setContext(self: *Self, context: ShellContext(WriterType)) void {
            self.context = context;
        }

        /// Mark the start of a shell prompt
        pub fn markPromptStart(self: Self) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.prompt_ops.markPromptStart(shell_ctx);
            }
        }

        /// Mark the end of a shell prompt (start of user input)
        pub fn markPromptEnd(self: Self) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.prompt_ops.markPromptEnd(shell_ctx);
            }
        }

        /// Mark prompt start with additional parameters
        pub fn markPromptStartWithParams(self: Self, params: []const []const u8) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.prompt_ops.markPromptStartWithParams(shell_ctx, params);
            }
        }

        /// Mark prompt end with additional parameters
        pub fn markPromptEndWithParams(self: Self, params: []const []const u8) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.prompt_ops.markPromptEndWithParams(shell_ctx, params);
            }
        }
    };
}

/// Command execution tracker
pub fn CommandTracker(comptime WriterType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        context: ?PromptTracker(WriterType).ShellContext(WriterType) = null,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        /// Set the shell integration context
        pub fn setContext(self: *Self, context: PromptTracker(WriterType).ShellContext(WriterType)) void {
            self.context = context;
        }

        /// Mark the start of command execution
        pub fn markCommandStart(self: Self, command: []const u8, cwd: ?[]const u8) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.command_ops.markCommandStart(shell_ctx, command, cwd);
            }
        }

        /// Mark the end of command execution
        pub fn markCommandEnd(self: Self, command: []const u8, exit_code: i32, duration_ms: ?u64) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.command_ops.markCommandEnd(shell_ctx, command, exit_code, duration_ms);
            }
        }

        /// Mark command start with additional parameters
        pub fn markCommandStartWithParams(self: Self, command: []const u8, cwd: ?[]const u8, params: []const []const u8) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.command_ops.markCommandStartWithParams(shell_ctx, command, cwd, params);
            }
        }

        /// Mark command end with additional parameters
        pub fn markCommandEndWithParams(self: Self, command: []const u8, exit_code: i32, duration_ms: ?u64, params: []const []const u8) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.command_ops.markCommandEndWithParams(shell_ctx, command, exit_code, duration_ms, params);
            }
        }

        /// Execute a command with proper shell integration markers
        pub fn executeCommand(
            self: Self,
            command: []const u8,
            cwd: ?[]const u8,
            command_fn: anytype,
            args: anytype,
        ) !i32 {
            // Mark command start
            try self.markCommandStart(command, cwd);

            // Record start time
            const start_time = std.time.milliTimestamp();

            // Execute command
            const exit_code = @call(.auto, command_fn, args);

            // Calculate duration
            const end_time = std.time.milliTimestamp();
            const duration_ms = if (end_time > start_time) @as(u64, @intCast(end_time - start_time)) else null;

            // Mark command end
            try self.markCommandEnd(command, exit_code, duration_ms);

            return exit_code;
        }
    };
}

/// Directory tracker for working directory changes
pub fn DirectoryTracker(comptime WriterType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        context: ?PromptTracker(WriterType).ShellContext(WriterType) = null,
        current_dir: ?[]u8 = null,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.current_dir) |dir| {
                self.allocator.free(dir);
            }
        }

        /// Set the shell integration context
        pub fn setContext(self: *Self, context: PromptTracker(WriterType).ShellContext(WriterType)) void {
            self.context = context;
        }

        /// Set the current working directory
        pub fn setWorkingDirectory(self: *Self, path: []const u8) !void {
            // Free previous directory
            if (self.current_dir) |dir| {
                self.allocator.free(dir);
            }

            // Store new directory
            self.current_dir = try self.allocator.dupe(u8, path);

            // Notify terminal if context is available
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.directory_ops.setWorkingDirectory(shell_ctx, path);
            }
        }

        /// Set remote host information
        pub fn setRemoteHost(self: *Self, hostname: []const u8, username: ?[]const u8, port: ?u16) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.directory_ops.setRemoteHost(shell_ctx, hostname, username, port);
            }
        }

        /// Clear remote host information (back to local)
        pub fn clearRemoteHost(self: *Self) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.directory_ops.clearRemoteHost(shell_ctx);
            }
        }

        /// Get the current working directory
        pub fn getCurrentDirectory(self: Self) ?[]const u8 {
            return self.current_dir;
        }
    };
}

/// Notification manager for terminal notifications
pub fn Notification(comptime WriterType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        context: ?PromptTracker(WriterType).ShellContext(WriterType) = null,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        /// Set the shell integration context
        pub fn setContext(self: *Self, context: PromptTracker(WriterType).ShellContext(WriterType)) void {
            self.context = context;
        }

        /// Request terminal attention/notification
        pub fn requestAttention(self: Self, message: ?[]const u8) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.notification_ops.requestAttention(shell_ctx, message);
            }
        }

        /// Set the terminal badge
        pub fn setBadge(self: Self, text: []const u8) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.notification_ops.setBadge(shell_ctx, text);
            }
        }

        /// Clear the terminal badge
        pub fn clearBadge(self: Self) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.notification_ops.clearBadge(shell_ctx);
            }
        }

        /// Set alert on command completion
        pub fn setAlertOnCompletion(self: Self, config: integration.ShellIntegration.AlertConfig) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.notification_ops.setAlertOnCompletion(shell_ctx, config);
            }
        }

        /// Trigger a file download
        pub fn triggerDownload(self: Self, config: integration.ShellIntegration.DownloadConfig) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.notification_ops.triggerDownload(shell_ctx, config);
            }
        }
    };
}

/// Semantic zone manager for marking regions of output
pub fn SemanticZone(comptime WriterType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        context: ?PromptTracker(WriterType).ShellContext(WriterType) = null,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        /// Set the shell integration context
        pub fn setContext(self: *Self, context: PromptTracker(WriterType).ShellContext(WriterType)) void {
            self.context = context;
        }

        /// Mark a semantic zone start
        pub fn markZoneStart(self: Self, zone_type: []const u8, name: ?[]const u8) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.semantic_ops.markZoneStart(shell_ctx, zone_type, name);
            }
        }

        /// Mark a semantic zone end
        pub fn markZoneEnd(self: Self, zone_type: []const u8) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.semantic_ops.markZoneEnd(shell_ctx, zone_type);
            }
        }

        /// Add an annotation to terminal output
        pub fn addAnnotation(self: Self, config: integration.ShellIntegration.AnnotationConfig) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.semantic_ops.addAnnotation(shell_ctx, config);
            }
        }

        /// Clear all annotations
        pub fn clearAnnotations(self: Self) !void {
            if (self.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try ctx.iface.semantic_ops.clearAnnotations(shell_ctx);
            }
        }
    };
}

/// Complete shell integration manager
pub fn ShellManager(comptime WriterType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        prompt_tracker: PromptTracker(WriterType),
        command_tracker: CommandTracker(WriterType),
        directory_tracker: DirectoryTracker(WriterType),
        notification_manager: Notification(WriterType),
        semantic_manager: SemanticZone(WriterType),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .prompt_tracker = PromptTracker(WriterType).init(allocator),
                .command_tracker = CommandTracker(WriterType).init(allocator),
                .directory_tracker = DirectoryTracker(WriterType).init(allocator),
                .notification_manager = Notification(WriterType).init(allocator),
                .semantic_manager = SemanticZone(WriterType).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.directory_tracker.deinit();
        }

        /// Set the shell integration context for all trackers
        pub fn setContext(self: *Self, writer: WriterType, caps: integration.ShellIntegration.TermCaps, iface: integration.ShellIntegration.Interface) void {
            const context = PromptTracker(WriterType).ShellContext(WriterType).init(writer, self.allocator, caps, iface);
            self.prompt_tracker.setContext(context);
            self.command_tracker.setContext(context);
            self.directory_tracker.setContext(context);
            self.notification_manager.setContext(context);
            self.semantic_manager.setContext(context);
        }

        /// Convenience method to initialize full shell integration
        pub fn initFullIntegration(self: *Self, writer: WriterType, caps: integration.ShellIntegration.TermCaps, iface: integration.ShellIntegration.Interface) !void {
            self.setContext(writer, caps, iface);

            const context = PromptTracker(WriterType).ShellContext(WriterType).init(writer, self.allocator, caps, iface);
            const shell_ctx = context.createShellContext();
            try integration.ShellIntegration.Convenience.initFullIntegration(WriterType, shell_ctx, iface);
        }

        /// Convenience method to mark SSH session start
        pub fn startSshSession(self: *Self, hostname: []const u8, username: ?[]const u8) !void {
            if (self.prompt_tracker.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try integration.ShellIntegration.Convenience.startSshSession(WriterType, shell_ctx, ctx.iface, hostname, username);
            }
        }

        /// Convenience method to mark SSH session end
        pub fn endSshSession(self: *Self) !void {
            if (self.prompt_tracker.context) |ctx| {
                const shell_ctx = ctx.createShellContext();
                try integration.ShellIntegration.Convenience.endSshSession(WriterType, shell_ctx, ctx.iface);
            }
        }

        /// Convenience method to execute a command with full integration
        pub fn executeCommand(
            self: *Self,
            command: []const u8,
            cwd: ?[]const u8,
            command_fn: anytype,
            args: anytype,
        ) !i32 {
            return try self.command_tracker.executeCommand(command, cwd, command_fn, args);
        }
    };
}
